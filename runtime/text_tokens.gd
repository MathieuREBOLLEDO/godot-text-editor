extends RefCounted

## Variables dans les textes : « Press {INTERACT_BUTTON} to interact. ».
## Un token s'écrit en majuscules, chiffres et _ entre accolades ; il n'est
## pas traduit et doit se retrouver tel quel dans chaque traduction.
## Utilisé par l'éditeur (validation) et par le jeu (DialogueRunner).

const PATTERN: String = "\\{([A-Z][A-Z0-9_]*)\\}"

static var _regex: RegEx = null


## Noms des tokens d'un texte, triés, sans doublon.
static func find(text: String) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	for match_result in _get_regex().search_all(text):
		var name: String = match_result.get_string(1)
		if not names.has(name):
			names.append(name)
	names.sort()
	return names


## Remplace chaque {NOM} connu de [param values] par sa valeur ; les tokens
## inconnus restent écrits.
static func fill(text: String, values: Dictionary) -> String:
	if values.is_empty() or not text.contains("{"):
		return text
	var result: String = text
	for name in find(text):
		if values.has(name):
			result = result.replace("{%s}" % name, str(values[name]))
	return result


## Valeurs des tokens pour une plateforme : { "INTERACT_BUTTON": "E" }, à
## partir de la table du projet { NOM: { plateforme: valeur } }. Sans valeur
## pour cette plateforme, celle de « default » s'il y en a une.
static func for_platform(table: Dictionary, platform: String) -> Dictionary:
	var values: Dictionary = {}
	for name in table:
		var by_platform: Dictionary = table[name] if typeof(table[name]) == TYPE_DICTIONARY else {}
		if by_platform.has(platform):
			values[name] = by_platform[platform]
		elif by_platform.has("default"):
			values[name] = by_platform["default"]
	return values


static func _get_regex() -> RegEx:
	if _regex == null:
		_regex = RegEx.create_from_string(PATTERN)
	return _regex
