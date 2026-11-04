class_name DialogueRunner
extends RefCounted

## Lecteur de dialogues pour le jeu : avance dans un dialogue exporté par
## l'onglet « Texts » (export/dialogues/<id>.json) et renvoie à chaque pas ce
## qu'il faut afficher. L'affichage reste au jeu.
##
##   var runner := DialogueRunner.load_file("res://game/ui/texts/export/dialogues/village.json")
##   runner.variables["gold"] = 10
##   runner.event_handler = func(name: String, args: String) -> void: ...
##   var step := runner.start()
##   while step["type"] != "end":
##       if step["type"] == "line": show(step["speaker_name"], step["text"]); step = runner.next()
##       else: step = runner.choose(await pick(step["options"]))
##
## Pas : { "type": "line", "node", "speaker", "speaker_name", "color",
## "portrait", "text_key", "text" }, { "type": "choice", "node", "options":
## [{ "index", "text_key", "text" }] } ou { "type": "end", "node", "error" }.
## Les conditions (choice, branch, condition) passent par condition_handler,
## sinon par variables : « gold » est vrai si la variable l'est, « !gold »
## l'inverse. Les nœuds event appellent event_handler puis continuent.

const Tokens = preload("text_tokens.gd")
## Pas automatiques (conditions, événements, sauts) au plus entre deux
## affichages : au-delà, le dialogue boucle sans fin et s'arrête.
const MAX_AUTO_STEPS: int = 256

var dialogue: Dictionary = {}
var variables: Dictionary = {}
## func(expression: String) -> bool ; vide : variables.
var condition_handler: Callable
## func(name: String, args: String) -> void
var event_handler: Callable
## func(key: String) -> String ; vide : la traduction de Godot (tr).
var translate: Callable
## Valeurs des tokens {NOM} (TextTokens.for_platform()).
var tokens: Dictionary = {}
var current_id: String = ""
var step: Dictionary = {}


static func load_file(path: String) -> DialogueRunner:
	var runner: DialogueRunner = DialogueRunner.new()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) == TYPE_DICTIONARY:
		runner.dialogue = data
	return runner


func start(start_id: String = "") -> Dictionary:
	if start_id.is_empty():
		var ids: Array = dialogue.get("nodes", {}).keys()
		ids.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
		for id in ids:
			if dialogue["nodes"][id].get("type", "") == "start":
				start_id = id
				break
	return _run_from(start_id)


## Après une réplique : la suite.
func next() -> Dictionary:
	if step.get("type", "") != "line":
		return step
	return _run_from(_target(current_id, 0))


## Après un choix : [param index] est le champ « index » de l'option.
func choose(index: int) -> Dictionary:
	if step.get("type", "") != "choice":
		return step
	return _run_from(_target(current_id, index))


## Texte d'une clé dans la langue du jeu, tokens remplis.
func text(key: String) -> String:
	if key.is_empty():
		return ""
	var value: String = translate.call(key) if translate.is_valid() else TranslationServer.translate(key)
	return Tokens.fill(value, tokens)


func check(expression: String) -> bool:
	expression = expression.strip_edges()
	if expression.is_empty():
		return true
	if condition_handler.is_valid():
		return bool(condition_handler.call(expression))
	if expression.begins_with("!"):
		return not bool(variables.get(expression.substr(1).strip_edges(), false))
	return bool(variables.get(expression, false))


func _run_from(id: String) -> Dictionary:
	var nodes: Dictionary = dialogue.get("nodes", {})
	for _i in MAX_AUTO_STEPS:
		if id.is_empty() or not nodes.has(id):
			return _end(current_id, "" if id.is_empty() else "missing_node")
		current_id = id
		var node: Dictionary = nodes[id]
		match String(node.get("type", "")):
			"line":
				var speaker: String = node.get("speaker", "")
				var character: Dictionary = dialogue.get("characters", {}).get(speaker, {})
				step = {"type": "line", "node": id, "speaker": speaker,
					"speaker_name": text(character.get("name_key", "")) if character.has("name_key") else speaker,
					"color": character.get("color", ""), "portrait": character.get("portrait", ""),
					"text_key": node.get("text_key", ""), "text": text(node.get("text_key", ""))}
				return step
			"choice":
				var options: Array = []
				var list: Array = node.get("options", [])
				for index in list.size():
					if check(list[index].get("condition", "")):
						options.append({"index": index, "text_key": list[index].get("text_key", ""), "text": text(list[index].get("text_key", ""))})
				if options.is_empty():
					return _end(id, "no_option")
				step = {"type": "choice", "node": id, "options": options}
				return step
			"branch":
				var conditions: Array = node.get("conditions", [])
				var port: int = conditions.size()
				for index in conditions.size():
					if check(conditions[index]):
						port = index
						break
				id = _target(id, port)
			"condition":
				id = _target(id, 0 if check(node.get("expression", "")) else 1)
			"variable_check":
				id = _target(id, 0 if _compare(node) else 1)
			"event":
				if event_handler.is_valid():
					event_handler.call(String(node.get("name", "")), String(node.get("args", "")))
				id = _target(id, 0)
			"jump":
				id = node.get("target", "")
			"start":
				id = _target(id, 0)
			_:
				return _end(id, "")
	return _end(current_id, "loop")


func _end(id: String, error: String) -> Dictionary:
	step = {"type": "end", "node": id, "error": error}
	return step


func _target(from: String, port: int) -> String:
	for link in dialogue.get("links", []):
		if link[0] == from and int(link[1]) == port:
			return link[2]
	return ""


func _compare(node: Dictionary) -> bool:
	var current: Variant = variables.get(node.get("variable", ""), null)
	var raw: String = String(node.get("value", ""))
	var expected: Variant = raw
	if raw.is_valid_float():
		expected = raw.to_float()
	elif raw == "true" or raw == "false":
		expected = raw == "true"
	if typeof(current) in [TYPE_INT, TYPE_FLOAT] and typeof(expected) == TYPE_FLOAT:
		current = float(current)
	elif typeof(current) != typeof(expected):
		current = str(current) if current != null else ""
		expected = raw
	match String(node.get("operator", "==")):
		"==":
			return current == expected
		"!=":
			return current != expected
		"<":
			return current < expected
		"<=":
			return current <= expected
		">":
			return current > expected
		">=":
			return current >= expected
	return false
