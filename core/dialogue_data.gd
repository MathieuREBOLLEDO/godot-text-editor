@tool
extends RefCounted

## Un dialogue : des nœuds et des liens, rangé à part de la base de textes
## (dialogues/<id>.json) ; ses textes sont des clés de la base.
##
## { "nodes": { id: nœud }, "links": [[de, sortie, vers], ...], "next_id": n }
## Nœud : { "type", "position": [x, y], ...champs du type } :
##   start           -                                1 sortie
##   line            speaker, text_key                1 sortie
##   choice          options: [{ text_key, condition }]  1 sortie par option
##   branch          conditions: [expression, ...]    1 par condition + « else »
##   condition       expression                       2 sorties (vrai, faux)
##   variable_check  variable, operator, value        2 sorties (vrai, faux)
##   event           name, args                       1 sortie
##   jump            target (id d'un nœud)            0
##   end             -                                0
## Une sortie mène à un seul nœud ; un nœud peut avoir plusieurs entrées.

const START: String = "start"
const LINE: String = "line"
const CHOICE: String = "choice"
const BRANCH: String = "branch"
const CONDITION: String = "condition"
const VARIABLE_CHECK: String = "variable_check"
const EVENT: String = "event"
const JUMP: String = "jump"
const END: String = "end"
const TYPES: PackedStringArray = ["start", "line", "choice", "branch", "condition", "variable_check", "event", "jump", "end"]
const OPERATORS: PackedStringArray = ["==", "!=", "<", "<=", ">", ">="]


static func create() -> Dictionary:
	var dialogue: Dictionary = {"nodes": {}, "links": [], "next_id": 1}
	var start: String = add_node(dialogue, START, Vector2(0, 0))
	var finish: String = add_node(dialogue, END, Vector2(360, 0))
	connect_nodes(dialogue, start, 0, finish)
	return dialogue


static func new_node(type: String) -> Dictionary:
	var node: Dictionary = {"type": type, "position": [0, 0]}
	match type:
		LINE:
			node["speaker"] = ""
			node["text_key"] = ""
		CHOICE:
			node["options"] = [{"text_key": "", "condition": ""}]
		BRANCH:
			node["conditions"] = [""]
		CONDITION:
			node["expression"] = ""
		VARIABLE_CHECK:
			node["variable"] = ""
			node["operator"] = "=="
			node["value"] = ""
		EVENT:
			node["name"] = ""
			node["args"] = ""
		JUMP:
			node["target"] = ""
	return node


static func add_node(dialogue: Dictionary, type: String, position: Vector2) -> String:
	var id: String = "n%d" % int(dialogue.get("next_id", 1))
	while dialogue["nodes"].has(id):
		dialogue["next_id"] = int(dialogue.get("next_id", 1)) + 1
		id = "n%d" % int(dialogue["next_id"])
	dialogue["next_id"] = int(dialogue.get("next_id", 1)) + 1
	var node: Dictionary = new_node(type)
	node["position"] = [roundi(position.x), roundi(position.y)]
	dialogue["nodes"][id] = node
	return id


static func remove_node(dialogue: Dictionary, id: String) -> void:
	dialogue["nodes"].erase(id)
	var kept: Array = []
	for link in dialogue["links"]:
		if link[0] != id and link[2] != id:
			kept.append(link)
	dialogue["links"] = kept
	for other in dialogue["nodes"]:
		if dialogue["nodes"][other].get("target", "") == id:
			dialogue["nodes"][other]["target"] = ""


## Relie une sortie à un nœud (remplace le lien de cette sortie).
static func connect_nodes(dialogue: Dictionary, from: String, port: int, to: String) -> bool:
	if not dialogue["nodes"].has(from) or not dialogue["nodes"].has(to) or port < 0 or port >= ports(dialogue["nodes"][from]):
		return false
	if dialogue["nodes"][to]["type"] == START:
		return false
	disconnect_port(dialogue, from, port)
	dialogue["links"].append([from, port, to])
	sort_links(dialogue)
	return true


static func disconnect_port(dialogue: Dictionary, from: String, port: int) -> void:
	var kept: Array = []
	for link in dialogue["links"]:
		if not (link[0] == from and int(link[1]) == port):
			kept.append(link)
	dialogue["links"] = kept


static func sort_links(dialogue: Dictionary) -> void:
	var links: Array = []
	for link in dialogue["links"]:
		links.append([String(link[0]), int(link[1]), String(link[2])])
	links.sort_custom(func(a: Array, b: Array) -> bool:
		return str(a) < str(b))
	dialogue["links"] = links


## Nombre de sorties d'un nœud.
static func ports(node: Dictionary) -> int:
	match String(node.get("type", "")):
		START, LINE, EVENT:
			return 1
		CHOICE:
			return node.get("options", []).size()
		BRANCH:
			return node.get("conditions", []).size() + 1
		CONDITION, VARIABLE_CHECK:
			return 2
	return 0


static func has_input(node: Dictionary) -> bool:
	return node.get("type", "") != START


## Nœud au bout de la sortie [param port] ("" si rien).
static func target(dialogue: Dictionary, from: String, port: int) -> String:
	for link in dialogue["links"]:
		if link[0] == from and int(link[1]) == port:
			return link[2]
	return ""


## Nœuds suivants (sorties reliées, et cible d'un saut).
static func successors(dialogue: Dictionary, id: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var node: Dictionary = dialogue["nodes"].get(id, {})
	for port in ports(node):
		var next: String = target(dialogue, id, port)
		if not next.is_empty() and dialogue["nodes"].has(next) and not result.has(next):
			result.append(next)
	if node.get("type", "") == JUMP and dialogue["nodes"].has(node.get("target", "")):
		result.append(node["target"])
	return result


static func start_ids(dialogue: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for id in sorted_ids(dialogue):
		if dialogue["nodes"][id]["type"] == START:
			result.append(id)
	return result


## Ids triés dans l'ordre de création (n1, n2, … n10).
static func sorted_ids(dialogue: Dictionary) -> Array:
	var ids: Array = dialogue["nodes"].keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return a.naturalnocasecmp_to(b) < 0)
	return ids


## Clés de texte utilisées (répliques, options, nom des personnages exclu).
static func text_keys(dialogue: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for id in sorted_ids(dialogue):
		var node: Dictionary = dialogue["nodes"][id]
		if not String(node.get("text_key", "")).is_empty() and not result.has(node["text_key"]):
			result.append(node["text_key"])
		for option in node.get("options", []):
			if not String(option.get("text_key", "")).is_empty() and not result.has(option["text_key"]):
				result.append(option["text_key"])
	return result


## Déroulé lisible du dialogue pour la vue narrative : depuis le départ, on
## suit chaque sortie en profondeur ; un nœud déjà montré n'est pas répété
## (« revient à … »). Éléments : { "id", "depth", "port_label", "repeat",
## "parent" } ; port_label est le numéro de la sortie du parent quand il en a
## plusieurs (choix, condition…).
static func narrative(dialogue: Dictionary) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for start in start_ids(dialogue):
		_walk(dialogue, start, 0, "", "", seen, result)
	return result


static func _walk(dialogue: Dictionary, id: String, depth: int, port_label: String, parent: String, seen: Dictionary, out: Array) -> void:
	if seen.has(id):
		out.append({"id": id, "depth": depth, "port_label": port_label, "repeat": true, "parent": parent})
		return
	seen[id] = true
	out.append({"id": id, "depth": depth, "port_label": port_label, "repeat": false, "parent": parent})
	var node: Dictionary = dialogue["nodes"][id]
	var count: int = ports(node)
	if node["type"] == JUMP and dialogue["nodes"].has(node.get("target", "")):
		_walk(dialogue, node["target"], depth, "", id, seen, out)
		return
	for port in count:
		var next: String = target(dialogue, id, port)
		if next.is_empty():
			continue
		var label: String = str(port) if count > 1 else ""
		_walk(dialogue, next, depth + (1 if count > 1 else 0), label, id, seen, out)


## Copie pour le jeu : sans positions, avec les personnages utilisés.
static func for_game(dialogue: Dictionary, characters: Dictionary) -> Dictionary:
	var nodes: Dictionary = {}
	var used: Dictionary = {}
	for id in dialogue["nodes"]:
		var node: Dictionary = (dialogue["nodes"][id] as Dictionary).duplicate(true)
		node.erase("position")
		nodes[id] = node
		var speaker: String = node.get("speaker", "")
		if not speaker.is_empty() and characters.has(speaker):
			used[speaker] = characters[speaker]
	var copy: Dictionary = {"nodes": nodes, "links": dialogue["links"].duplicate(true), "characters": used}
	sort_links(copy)
	return copy
