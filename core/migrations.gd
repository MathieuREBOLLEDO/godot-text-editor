@tool
extends RefCounted

## Version du format des fichiers (project.json, strings/*.json,
## dialogues/*.json). Un fichier sans « schema » est en version 1. Pour faire
## évoluer le format : monter SCHEMA et ajouter une étape dans _step(), qui
## passe un fichier de la version v à v + 1. Un fichier plus récent que
## l'addon n'est pas chargé (il serait réécrit en perdant ce que l'addon ne
## connaît pas).

const SCHEMA: int = 1


## { "ok": bool, "data": Dictionary, "error": String }. error vaut
## « newer » (fichier d'une version plus récente de l'addon) ou « invalid ».
static func migrate(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "data": {}, "error": "invalid"}
	var result: Dictionary = (data as Dictionary).duplicate(true)
	var version: int = int(result.get("schema", 1))
	if version > SCHEMA:
		return {"ok": false, "data": result, "error": "newer"}
	while version < SCHEMA:
		result = _step(version, result)
		version += 1
	result["schema"] = SCHEMA
	return {"ok": true, "data": result, "error": ""}


# Passage de la version [param from] à from + 1. Aucune pour l'instant.
static func _step(from: int, data: Dictionary) -> Dictionary:
	match from:
		_:
			return data
