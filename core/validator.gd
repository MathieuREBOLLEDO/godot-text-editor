@tool
extends RefCounted

## Validation de la base et des dialogues. Chaque problème :
## { "severity": error|warning|info, "code", "key", "language", "dialogue",
##   "node", "args": [] } ; le texte et l'explication viennent de texts.gd
## (issue_<code>, issue_<code>_help). Rien n'est modifié.
##
## Options de run() : project_text (texte de tous les fichiers du jeu, pour
## les textes inutilisés ; absent : pas de recherche), font (Font : caractères
## absents de la police).

const TextDb = preload("text_db.gd")
const DialogueData = preload("dialogue_data.gd")
const Tokens = preload("../runtime/text_tokens.gd")

const ERROR: String = "error"
const WARNING: String = "warning"
const INFO: String = "info"


static func run(db: TextDb, options: Dictionary = {}) -> Array:
	var issues: Array = []
	for error in db.load_errors:
		issues.append(_issue(ERROR if error["code"] != "duplicate_key" else WARNING, error["code"],
			error["args"][1] if error["code"] == "duplicate_key" else "", error["args"]))
	var used: Dictionary = {}
	for id in db.dialogues:
		for key in DialogueData.text_keys(db.dialogues[id]):
			used[key] = true
	for character in db.project.get("characters", {}).values():
		used[String(character.get("name_key", ""))] = true
	for key in db.query():
		check_entry(db, key, options, issues)
		if options.has("project_text") and not used.has(key) and not String(options["project_text"]).contains(key):
			issues.append(_issue(INFO, "unused", key))
	for id in db.dialogues.keys():
		check_dialogue(db, id, issues)
	return issues


static func check_entry(db: TextDb, key: String, options: Dictionary, issues: Array) -> void:
	if not db.is_valid_key(key):
		issues.append(_issue(WARNING, "invalid_key", key))
	var source: String = db.text(key, db.source_language())
	if source.strip_edges().is_empty():
		issues.append(_issue(ERROR, "empty_source", key))
		return
	var missing: PackedStringArray = PackedStringArray()
	var obsolete: PackedStringArray = PackedStringArray()
	var source_tokens: PackedStringArray = Tokens.find(source)
	var declared: Dictionary = db.project.get("tokens", {})
	var unknown: PackedStringArray = PackedStringArray()
	for token in source_tokens:
		if not declared.has(token):
			unknown.append(token)
	if not unknown.is_empty():
		issues.append(_issue(INFO, "unknown_token", key, [", ".join(unknown)]))
	var font: Font = options.get("font", null)
	for language in db.languages():
		var value: String = db.text(key, language)
		var current: String = db.status(key, language)
		if current == TextDb.MISSING or current == TextDb.TO_TRANSLATE:
			missing.append(language)
			continue
		if current == TextDb.NEEDS_REVIEW:
			obsolete.append(language)
		if language != db.source_language():
			var tokens: PackedStringArray = Tokens.find(value)
			var lost: PackedStringArray = PackedStringArray()
			var extra: PackedStringArray = PackedStringArray()
			for token in source_tokens:
				if not tokens.has(token):
					lost.append(token)
			for token in tokens:
				if not source_tokens.has(token):
					extra.append(token)
			if not lost.is_empty():
				issues.append(_issue(ERROR, "missing_token", key, ["{%s}" % "}, {".join(lost)], language))
			if not extra.is_empty():
				issues.append(_issue(ERROR, "extra_token", key, ["{%s}" % "}, {".join(extra)], language))
		_check_length(db, key, language, value, issues)
		if font != null:
			var absent: String = ""
			for character in value:
				if character.unicode_at(0) > 32 and not font.has_char(character.unicode_at(0)) and not absent.contains(character):
					absent += character
			if not absent.is_empty():
				issues.append(_issue(WARNING, "unsupported_chars", key, [absent], language))
	if not missing.is_empty():
		issues.append(_issue(WARNING, "missing_translation", key, [", ".join(missing)]))
	if not obsolete.is_empty():
		issues.append(_issue(WARNING, "obsolete", key, [", ".join(obsolete)]))


## Longueur affichée : chaque token compte pour sa plus longue valeur.
static func display_length(db: TextDb, value: String) -> int:
	var length: int = value.length()
	var table: Dictionary = db.project.get("tokens", {})
	for token in Tokens.find(value):
		if table.has(token) and typeof(table[token]) == TYPE_DICTIONARY:
			var longest: int = 0
			for platform_value in table[token].values():
				longest = maxi(longest, str(platform_value).length())
			length += (longest - (token.length() + 2)) * value.count("{%s}" % token)
	return length


static func _check_length(db: TextDb, key: String, language: String, value: String, issues: Array) -> void:
	var length: int = display_length(db, value)
	var platforms: Array = [""] + Array(db.project.get("platforms", []))
	for platform in platforms:
		var limit: int = db.max_length(key, platform)
		if limit > 0 and length > limit and (platform == "" or limit != db.max_length(key, "")):
			var issue: Dictionary = _issue(WARNING, "too_long", key, [length, limit, platform if platform != "" else "-"], language)
			issues.append(issue)


static func check_dialogue(db: TextDb, id: String, issues: Array) -> void:
	var dialogue: Dictionary = db.dialogues[id]
	if typeof(dialogue.get("nodes", null)) != TYPE_DICTIONARY:
		issues.append(_dialogue_issue(ERROR, "unreadable_dialogue", id, ""))
		return
	var nodes: Dictionary = dialogue["nodes"]
	var starts: PackedStringArray = DialogueData.start_ids(dialogue)
	if starts.is_empty():
		issues.append(_dialogue_issue(ERROR, "no_start", id, ""))
	var reachable: Dictionary = _reachable(dialogue, starts)
	var characters: Dictionary = db.project.get("characters", {})
	for node_id in DialogueData.sorted_ids(dialogue):
		var node: Dictionary = nodes[node_id]
		var type: String = node.get("type", "")
		if not reachable.has(node_id) and type != DialogueData.START:
			issues.append(_dialogue_issue(WARNING, "orphan_node", id, node_id))
		for port in DialogueData.ports(node):
			if DialogueData.target(dialogue, node_id, port).is_empty():
				var code: String = "choice_without_target" if type == DialogueData.CHOICE else "no_exit"
				issues.append(_dialogue_issue(ERROR, code, id, node_id, [port + 1]))
		if type == DialogueData.JUMP and not nodes.has(node.get("target", "")):
			issues.append(_dialogue_issue(ERROR, "jump_target_missing", id, node_id))
		if type == DialogueData.LINE:
			_check_key(db, id, node_id, node.get("text_key", ""), issues)
			var speaker: String = node.get("speaker", "")
			if not speaker.is_empty() and not characters.has(speaker):
				issues.append(_dialogue_issue(WARNING, "unknown_speaker", id, node_id, [speaker]))
		for option in node.get("options", []):
			_check_key(db, id, node_id, option.get("text_key", ""), issues)
	# Branches qui n'atteignent aucune fin.
	var ends: Dictionary = _reaching_end(dialogue)
	for node_id in reachable:
		if not ends.has(node_id) and nodes[node_id]["type"] != DialogueData.END:
			issues.append(_dialogue_issue(ERROR, "no_end", id, node_id))
	for loop in infinite_loops(dialogue):
		issues.append(_dialogue_issue(ERROR, "infinite_loop", id, loop[0], [" → ".join(PackedStringArray(loop))]))


static func _check_key(db: TextDb, id: String, node_id: String, key: String, issues: Array) -> void:
	if key.is_empty():
		issues.append(_dialogue_issue(WARNING, "empty_text_key", id, node_id))
	elif not db.has_key(key):
		var issue: Dictionary = _dialogue_issue(ERROR, "unknown_key", id, node_id, [key])
		issue["key"] = key
		issues.append(issue)


## Boucles involontaires : un groupe de nœuds qui se rejoignent en cycle sans
## qu'aucun n'offre de sortie hors du groupe (le joueur ne peut plus en
## sortir). Chaque boucle : ses ids triés.
static func infinite_loops(dialogue: Dictionary) -> Array:
	var result: Array = []
	for group in _cycles(dialogue):
		var leaves: bool = false
		for node_id in group:
			for next in DialogueData.successors(dialogue, node_id):
				if not group.has(next):
					leaves = true
			if dialogue["nodes"][node_id]["type"] == DialogueData.END:
				leaves = true
		if not leaves:
			result.append(group)
	return result


# Groupes fortement connexes qui forment un cycle (Kosaraju).
static func _cycles(dialogue: Dictionary) -> Array:
	var ids: Array = DialogueData.sorted_ids(dialogue)
	var order: Array = []
	var seen: Dictionary = {}
	for node_id in ids:
		_post_order(dialogue, node_id, seen, order)
	var reverse: Dictionary = {}
	for node_id in ids:
		reverse[node_id] = []
	for node_id in ids:
		for next in DialogueData.successors(dialogue, node_id):
			reverse[next].append(node_id)
	var assigned: Dictionary = {}
	var groups: Array = []
	order.reverse()
	for node_id in order:
		if assigned.has(node_id):
			continue
		var group: Array = []
		var stack: Array = [node_id]
		assigned[node_id] = true
		while not stack.is_empty():
			var current: String = stack.pop_back()
			group.append(current)
			for previous in reverse[current]:
				if not assigned.has(previous):
					assigned[previous] = true
					stack.append(previous)
		var cyclic: bool = group.size() > 1 or DialogueData.successors(dialogue, group[0]).has(group[0])
		if cyclic:
			group.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
			groups.append(group)
	return groups


static func _post_order(dialogue: Dictionary, root: String, seen: Dictionary, order: Array) -> void:
	if seen.has(root):
		return
	# Parcours itératif (pas de récursion profonde sur un grand graphe).
	var stack: Array = [[root, 0]]
	seen[root] = true
	while not stack.is_empty():
		var top: Array = stack.back()
		var nexts: PackedStringArray = DialogueData.successors(dialogue, top[0])
		if top[1] < nexts.size():
			var next: String = nexts[top[1]]
			top[1] += 1
			if not seen.has(next):
				seen[next] = true
				stack.append([next, 0])
		else:
			order.append(top[0])
			stack.pop_back()


static func _reachable(dialogue: Dictionary, starts: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	var stack: Array = Array(starts)
	while not stack.is_empty():
		var current: String = stack.pop_back()
		if result.has(current) or not dialogue["nodes"].has(current):
			continue
		result[current] = true
		for next in DialogueData.successors(dialogue, current):
			stack.append(next)
	return result


# Nœuds depuis lesquels une fin est atteignable.
static func _reaching_end(dialogue: Dictionary) -> Dictionary:
	var reverse: Dictionary = {}
	var stack: Array = []
	for node_id in dialogue["nodes"]:
		reverse[node_id] = []
		if dialogue["nodes"][node_id]["type"] == DialogueData.END:
			stack.append(node_id)
	for node_id in dialogue["nodes"]:
		for next in DialogueData.successors(dialogue, node_id):
			reverse[next].append(node_id)
	var result: Dictionary = {}
	while not stack.is_empty():
		var current: String = stack.pop_back()
		if result.has(current):
			continue
		result[current] = true
		for previous in reverse[current]:
			stack.append(previous)
	return result


static func _issue(severity: String, code: String, key: String, args: Array = [], language: String = "") -> Dictionary:
	return {"severity": severity, "code": code, "key": key, "language": language, "dialogue": "", "node": "", "args": args}


static func _dialogue_issue(severity: String, code: String, dialogue: String, node: String, args: Array = []) -> Dictionary:
	# Les arguments propres au problème d'abord (le texte n'en utilise
	# souvent qu'un), puis le dialogue et le nœud.
	return {"severity": severity, "code": code, "key": "", "language": "", "dialogue": dialogue, "node": node, "args": args + [dialogue, node]}


## Nombre de problèmes par gravité.
static func counts(issues: Array) -> Dictionary:
	var result: Dictionary = {ERROR: 0, WARNING: 0, INFO: 0}
	for issue in issues:
		result[issue["severity"]] += 1
	return result
