@tool
extends RefCounted

## Base des textes d'un jeu : réglages du projet, entrées (une par clé) et
## dialogues. Données seules, sans interface : l'onglet « Texts » et les
## tests passent par ici.
##
## Fichiers (dans [member dir], par défaut res://game/ui/texts) :
##   project.json            langues, catégories, plateformes, tokens…
##   strings/<categorie>.json les entrées de cette catégorie, triées par clé
##   dialogues/<id>.json     un dialogue (nœuds et liens)
## Écriture déterministe (clés triées, tabulations) : un fichier n'est réécrit
## que si son contenu change, pour des diffs Git propres. Format : FORMAT.md.

const Migrations = preload("migrations.gd")

## Une ou plusieurs entrées ont changé (clés concernées ; vide = tout).
signal changed(keys: PackedStringArray)
## Un dialogue a changé (id ; vide = la liste).
signal dialogue_changed(id: String)
## Les réglages du projet ont changé.
signal project_changed

const MISSING: String = "missing"
const TO_TRANSLATE: String = "to_translate"
const TRANSLATED: String = "translated"
const NEEDS_REVIEW: String = "needs_review"
const APPROVED: String = "approved"
## Du pire au meilleur : le statut d'une entrée est le pire de ses langues.
const STATUSES: PackedStringArray = ["missing", "needs_review", "to_translate", "translated", "approved"]
## Anciennes versions gardées par langue (comparaison, retour arrière).
const HISTORY_SIZE: int = 10
const ENTRY_FIELDS: PackedStringArray = ["category", "context", "description", "tags", "max_length"]
const KEY_PATTERN: String = "^[A-Z][A-Z0-9_]*$"

const DEFAULT_CATEGORIES: PackedStringArray = ["ui", "menu", "dialogue", "choice", "item", "skill",
	"tutorial", "tooltip", "notification", "system", "title", "level", "reward", "quest", "credits", "error", "interaction"]
const DEFAULT_PLATFORMS: PackedStringArray = ["pc", "playstation", "xbox", "switch", "steam_deck"]

var dir: String = ""
var project: Dictionary = {}
## Clé -> entrée (voir _new_entry()).
var entries: Dictionary = {}
## Id -> dialogue (voir dialogue_data.gd).
var dialogues: Dictionary = {}
## Problèmes rencontrés au chargement : { "code", "args" }.
var load_errors: Array = []
## Date des modifications ; remplaçable (tests).
var clock: Callable = func() -> String: return Time.get_datetime_string_from_system(true)

var _dirty_categories: Dictionary = {}
var _dirty_dialogues: Dictionary = {}
var _removed_dialogues: Dictionary = {}
var _project_dirty: bool = false
var _key_regex: RegEx = RegEx.create_from_string(KEY_PATTERN)


# --- Projet ---

static func default_project() -> Dictionary:
	return {
		"schema": Migrations.SCHEMA,
		"source_language": "en",
		"languages": ["en", "fr"],
		"categories": Array(DEFAULT_CATEGORIES),
		"platforms": Array(DEFAULT_PLATFORMS),
		"tokens": {},
		"limits": {},
		"characters": {},
		"font": "",
		"export_dir": "export",
	}


func source_language() -> String:
	return String(project.get("source_language", "en"))


## Toutes les langues, la langue source d'abord.
func languages() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray([source_language()])
	for language in project.get("languages", []):
		if not result.has(String(language)):
			result.append(String(language))
	return result


func target_languages() -> PackedStringArray:
	var result: PackedStringArray = languages()
	result.remove_at(0)
	return result


func categories() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for category in project.get("categories", []):
		result.append(String(category))
	for key in entries:
		var category: String = entries[key]["category"]
		if not result.has(category):
			result.append(category)
	return result


func set_project_value(name: String, value: Variant) -> void:
	project[name] = value
	if name == "source_language" or name == "languages":
		project["languages"] = Array(languages())
	_project_dirty = true
	project_changed.emit()


func add_language(code: String) -> bool:
	code = code.strip_edges()
	if code.is_empty() or languages().has(code):
		return false
	var list: Array = project.get("languages", []).duplicate()
	list.append(code)
	set_project_value("languages", list)
	return true


## Retire une langue de la liste ; ses traductions restent dans les fichiers
## (rien n'est effacé), elles réapparaissent si on la remet.
func remove_language(code: String) -> bool:
	if code == source_language() or not languages().has(code):
		return false
	var list: Array = project.get("languages", []).duplicate()
	list.erase(code)
	set_project_value("languages", list)
	return true


## Limite de caractères d'une entrée : la sienne, sinon celle de
## « categorie@plateforme », sinon celle de la catégorie ; 0 = aucune.
func max_length(key: String, platform: String = "") -> int:
	var entry: Dictionary = entries.get(key, {})
	if entry.is_empty():
		return 0
	if int(entry["max_length"]) > 0:
		return int(entry["max_length"])
	var limits: Dictionary = project.get("limits", {})
	if not platform.is_empty() and limits.has("%s@%s" % [entry["category"], platform]):
		return int(limits["%s@%s" % [entry["category"], platform]])
	return int(limits.get(entry["category"], 0))


# --- Entrées ---

func is_valid_key(key: String) -> bool:
	return _key_regex.search(key) != null


func has_key(key: String) -> bool:
	return entries.has(key)


## Clé libre : [param base], sinon base_2, base_3…
func unique_key(base: String) -> String:
	base = base.strip_edges().to_upper().replace(" ", "_")
	if base.is_empty():
		base = "TEXT"
	if not entries.has(base):
		return base
	var index: int = 2
	while entries.has("%s_%d" % [base, index]):
		index += 1
	return "%s_%d" % [base, index]


func add_entry(key: String, category: String = "ui", source: String = "") -> bool:
	if entries.has(key) or not is_valid_key(key):
		return false
	entries[key] = _new_entry(category)
	if not source.is_empty():
		entries[key]["texts"][source_language()]["text"] = source
	_touch(key)
	return true


func remove_entry(key: String) -> bool:
	if not entries.has(key):
		return false
	_dirty_categories[entries[key]["category"]] = true
	entries.erase(key)
	changed.emit(PackedStringArray([key]))
	return true


func duplicate_entry(key: String, new_key: String) -> bool:
	if not entries.has(key) or entries.has(new_key) or not is_valid_key(new_key):
		return false
	entries[new_key] = (entries[key] as Dictionary).duplicate(true)
	_touch(new_key)
	return true


## Change la clé et met à jour les dialogues qui l'utilisent.
func rename_key(old_key: String, new_key: String) -> bool:
	if not entries.has(old_key) or entries.has(new_key) or not is_valid_key(new_key):
		return false
	entries[new_key] = entries[old_key]
	entries.erase(old_key)
	for id in dialogues:
		if _replace_key_in(dialogues[id], old_key, new_key):
			mark_dialogue_dirty(id)
	_touch(new_key)
	changed.emit(PackedStringArray([old_key, new_key]))
	return true


func get_entry(key: String) -> Dictionary:
	return entries.get(key, {})


func set_field(key: String, field: String, value: Variant) -> bool:
	if not entries.has(key) or not ENTRY_FIELDS.has(field):
		return false
	var entry: Dictionary = entries[key]
	match field:
		"category":
			value = String(value).strip_edges().to_lower()
			if String(value).is_empty():
				return false
			_dirty_categories[entry["category"]] = true
		"tags":
			value = _clean_tags(value)
		"max_length":
			value = maxi(0, int(value))
		_:
			value = String(value)
	if entry[field] == value:
		return false
	entry[field] = value
	_touch(key)
	return true


func text(key: String, language: String) -> String:
	var entry: Dictionary = entries.get(key, {})
	if entry.is_empty() or not entry["texts"].has(language):
		return ""
	return entry["texts"][language]["text"]


## Texte source. S'il change, les traductions faites sur l'ancien passent en
## « needs_review » (elles ne sont jamais effacées).
func set_source(key: String, value: String) -> bool:
	if not entries.has(key):
		return false
	var slot: Dictionary = _slot(key, source_language())
	if slot["text"] == value:
		return false
	_push_history(slot)
	slot["text"] = value
	slot["modified"] = clock.call()
	var hash: String = source_hash(value)
	for language in target_languages():
		var target: Dictionary = _slot(key, language)
		if not String(target["text"]).is_empty() and target.get("source_hash", "") != hash:
			if target["status"] == TRANSLATED or target["status"] == APPROVED:
				target["status"] = NEEDS_REVIEW
	_touch(key)
	return true


## Traduction d'une langue ; [param status] vide : « translated » s'il y a un
## texte, « missing » sinon.
func set_translation(key: String, language: String, value: String, status: String = "") -> bool:
	if language == source_language():
		return set_source(key, value)
	if not entries.has(key) or not languages().has(language):
		return false
	var slot: Dictionary = _slot(key, language)
	if slot["text"] == value and (status.is_empty() or slot["status"] == status):
		return false
	if slot["text"] != value:
		_push_history(slot)
		slot["text"] = value
	slot["status"] = status if STATUSES.has(status) else (TRANSLATED if not value.is_empty() else MISSING)
	slot["source_hash"] = source_hash(text(key, source_language()))
	slot["modified"] = clock.call()
	_touch(key)
	return true


## Statut d'une langue. « translated » ou « approved » valident la traduction
## pour le texte source actuel.
func set_status(key: String, language: String, status: String) -> bool:
	if not entries.has(key) or not STATUSES.has(status) or language == source_language():
		return false
	var slot: Dictionary = _slot(key, language)
	if slot["status"] == status:
		return false
	slot["status"] = status
	if status == TRANSLATED or status == APPROVED:
		slot["source_hash"] = source_hash(text(key, source_language()))
	slot["modified"] = clock.call()
	_touch(key)
	return true


## Statut d'une langue ; la langue source est « approved » dès qu'elle a un
## texte. Une langue sans texte est toujours « missing ».
func status(key: String, language: String) -> String:
	var entry: Dictionary = entries.get(key, {})
	if entry.is_empty():
		return MISSING
	var slot: Dictionary = entry["texts"].get(language, {})
	if slot.is_empty() or String(slot["text"]).is_empty():
		return MISSING if language == source_language() or slot.get("status", "") != TO_TRANSLATE else TO_TRANSLATE
	if language == source_language():
		return APPROVED
	return String(slot.get("status", TRANSLATED))


## Le pire statut des langues cibles (voir STATUSES).
func entry_status(key: String) -> String:
	var worst: int = STATUSES.size() - 1
	if status(key, source_language()) == MISSING:
		return MISSING
	for language in target_languages():
		worst = mini(worst, STATUSES.find(status(key, language)))
	return STATUSES[worst]


func history(key: String, language: String) -> Array:
	var entry: Dictionary = entries.get(key, {})
	if entry.is_empty() or not entry["texts"].has(language):
		return []
	return entry["texts"][language].get("history", [])


static func source_hash(value: String) -> String:
	return value.md5_text().substr(0, 10)


## Copie d'une entrée (null si elle n'existe pas), pour annuler.
func snapshot(key: String) -> Variant:
	return (entries[key] as Dictionary).duplicate(true) if entries.has(key) else null


## Remet une entrée dans l'état d'un snapshot() (null : la retire).
func restore(key: String, state: Variant) -> void:
	if entries.has(key):
		_dirty_categories[entries[key]["category"]] = true
	if state == null:
		entries.erase(key)
	else:
		entries[key] = (state as Dictionary).duplicate(true)
		_dirty_categories[entries[key]["category"]] = true
	changed.emit(PackedStringArray([key]))


## Clés qui passent le filtre, triées. Filtre (tout optionnel) :
## search (clé ou texte d'une langue, sans casse), category, tag,
## status (+ language : statut dans cette langue, sinon celui de l'entrée),
## sort ("key", "category", "modified", "status", ou un code de langue),
## descending.
func query(filter: Dictionary = {}) -> PackedStringArray:
	var search: String = String(filter.get("search", "")).strip_edges().to_lower()
	var category: String = filter.get("category", "")
	var tag: String = filter.get("tag", "")
	var wanted_status: String = filter.get("status", "")
	var language: String = filter.get("language", "")
	var keys: Array = []
	for key in entries:
		var entry: Dictionary = entries[key]
		if not category.is_empty() and entry["category"] != category:
			continue
		if not tag.is_empty() and not entry["tags"].has(tag):
			continue
		if not wanted_status.is_empty():
			var current: String = status(key, language) if not language.is_empty() else entry_status(key)
			if current != wanted_status:
				continue
		if not search.is_empty() and not _matches(key, entry, search):
			continue
		keys.append(key)
	var sort: String = filter.get("sort", "key")
	var sorter: Callable = func(a: String, b: String) -> bool: return a < b
	if sort == "modified" or sort == "category" or sort == "status" or languages().has(sort):
		var values: Dictionary = {}
		for key in keys:
			match sort:
				"modified":
					values[key] = entries[key]["modified"]
				"category":
					values[key] = entries[key]["category"]
				"status":
					values[key] = str(STATUSES.find(entry_status(key)))
				_:
					values[key] = text(key, sort).to_lower()
		sorter = func(a: String, b: String) -> bool:
			return a < b if values[a] == values[b] else values[a] < values[b]
	keys.sort_custom(sorter)
	if filter.get("descending", false):
		keys.reverse()
	return PackedStringArray(keys)


func tags() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for key in entries:
		for tag in entries[key]["tags"]:
			if not result.has(tag):
				result.append(tag)
	result.sort()
	return result


## Chiffres du tableau de bord : entries, dialogues, languages, et par langue
## (by_language[code]) le nombre d'entrées par statut et le pourcentage
## traduit (translated + approved).
func stats() -> Dictionary:
	var by_language: Dictionary = {}
	for language in languages():
		var counts: Dictionary = {}
		for status_name in STATUSES:
			counts[status_name] = 0
		for key in entries:
			counts[status(key, language)] += 1
		var done: int = counts[TRANSLATED] + counts[APPROVED]
		counts["percent"] = 100.0 * done / entries.size() if not entries.is_empty() else 100.0
		by_language[language] = counts
	return {"entries": entries.size(), "dialogues": dialogues.size(), "languages": languages().size(), "by_language": by_language}


# --- Dialogues ---

func add_dialogue(id: String, data: Dictionary) -> bool:
	if id.is_empty() or dialogues.has(id):
		return false
	dialogues[id] = data
	_removed_dialogues.erase(id)
	mark_dialogue_dirty(id)
	dialogue_changed.emit("")
	return true


func remove_dialogue(id: String) -> bool:
	if not dialogues.has(id):
		return false
	dialogues.erase(id)
	_dirty_dialogues.erase(id)
	_removed_dialogues[id] = true
	dialogue_changed.emit("")
	return true


func rename_dialogue(id: String, new_id: String) -> bool:
	if not dialogues.has(id) or dialogues.has(new_id) or new_id.is_empty():
		return false
	dialogues[new_id] = dialogues[id]
	remove_dialogue(id)
	mark_dialogue_dirty(new_id)
	return true


func mark_dialogue_dirty(id: String) -> void:
	_dirty_dialogues[id] = true
	dialogue_changed.emit(id)


func is_dirty() -> bool:
	return _project_dirty or not _dirty_categories.is_empty() or not _dirty_dialogues.is_empty() or not _removed_dialogues.is_empty()


# --- Lecture et écriture ---

## Nouveau projet vide (rien n'est écrit avant save()).
func create(path: String) -> void:
	dir = path
	project = default_project()
	entries = {}
	dialogues = {}
	load_errors = []
	_project_dirty = true


## Lit un dossier de données. Sans project.json, un projet neuf (rien n'est
## écrit). Faux si un fichier est illisible ou d'une version plus récente :
## dans ce cas save() refuse d'écrire, pour ne rien perdre.
func load_dir(path: String) -> bool:
	create(path)
	_project_dirty = false
	_dirty_categories = {}
	_dirty_dialogues = {}
	_removed_dialogues = {}
	var project_path: String = path.path_join("project.json")
	# Sans project.json : projet neuf, écrit au premier vrai changement
	# (ouvrir l'éditeur ne crée aucun fichier).
	if not FileAccess.file_exists(project_path):
		return true
	var read: Dictionary = _read_json(project_path)
	if read["ok"]:
		project = _normalize_project(read["data"])
	var files: PackedStringArray = _json_files(path.path_join("strings"))
	for file in files:
		var data: Dictionary = _read_json(path.path_join("strings").path_join(file))
		if data["ok"]:
			_load_strings(file.get_basename(), data["data"].get("entries", {}))
	for file in _json_files(path.path_join("dialogues")):
		var data: Dictionary = _read_json(path.path_join("dialogues").path_join(file))
		if data["ok"]:
			dialogues[file.get_basename()] = data["data"]
	_refresh_obsolete()
	return not has_blocking_errors()


func has_blocking_errors() -> bool:
	for error in load_errors:
		if error["code"] == "unreadable" or error["code"] == "newer":
			return true
	return false


## Écrit ce qui a changé. Faux en cas d'erreur (ou si le chargement a buté
## sur un fichier : rien n'est écrit).
func save() -> bool:
	if has_blocking_errors() or dir.is_empty():
		return false
	var ok: bool = true
	var has_content: bool = not _dirty_categories.is_empty() or not _dirty_dialogues.is_empty()
	if _project_dirty or (has_content and not FileAccess.file_exists(dir.path_join("project.json"))):
		ok = _write_json(dir.path_join("project.json"), project) and ok
	for category in _dirty_categories:
		ok = _save_category(category) and ok
	for id in _dirty_dialogues:
		if dialogues.has(id):
			var data: Dictionary = dialogues[id]
			data["schema"] = Migrations.SCHEMA
			ok = _write_json(dir.path_join("dialogues").path_join(id + ".json"), data) and ok
	for id in _removed_dialogues:
		var file: String = dir.path_join("dialogues").path_join(id + ".json")
		if FileAccess.file_exists(file):
			ok = DirAccess.remove_absolute(file) == OK and ok
	if ok:
		_project_dirty = false
		_dirty_categories = {}
		_dirty_dialogues = {}
		_removed_dialogues = {}
	return ok


## Texte JSON tel qu'écrit dans les fichiers (clés triées, tabulations).
static func to_json(data: Variant) -> String:
	return JSON.stringify(data, "\t", true) + "\n"


## Écrit [param content] si le fichier n'a pas déjà ce contenu.
static func write_text(path: String, content: String) -> bool:
	if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == content:
		return true
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.close()
	return true


func _save_category(category: String) -> bool:
	var path: String = dir.path_join("strings").path_join(category + ".json")
	var list: Dictionary = {}
	for key in entries:
		if entries[key]["category"] == category:
			list[key] = entries[key]
	if list.is_empty():
		return not FileAccess.file_exists(path) or DirAccess.remove_absolute(path) == OK
	return _write_json(path, {"schema": Migrations.SCHEMA, "category": category, "entries": list})


func _write_json(path: String, data: Dictionary) -> bool:
	return write_text(path, to_json(data))


func _read_json(path: String) -> Dictionary:
	var json: JSON = JSON.new()
	var parsed: Variant = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	var migrated: Dictionary = Migrations.migrate(parsed)
	if not migrated["ok"]:
		load_errors.append({"code": "newer" if migrated["error"] == "newer" else "unreadable", "args": [path]})
	return migrated


func _load_strings(category: String, list: Variant) -> void:
	if typeof(list) != TYPE_DICTIONARY:
		return
	var keys: Array = (list as Dictionary).keys()
	keys.sort()
	for key in keys:
		var entry: Dictionary = _normalize_entry(list[key], category)
		var final_key: String = key
		if entries.has(key):
			# Même clé dans deux fichiers : la seconde est renommée (et
			# signalée), pas perdue.
			final_key = unique_key(key + "_DUPLICATE")
			load_errors.append({"code": "duplicate_key", "args": [key, final_key]})
			_dirty_categories[entry["category"]] = true
		if entry["category"] != category:
			_dirty_categories[category] = true
			_dirty_categories[entry["category"]] = true
		entries[final_key] = entry


# Traductions faites sur un ancien texte source (modifié hors de l'outil,
# fusion Git…) : needs_review.
func _refresh_obsolete() -> void:
	for key in entries:
		var hash: String = source_hash(text(key, source_language()))
		for language in entries[key]["texts"]:
			if language == source_language():
				continue
			var slot: Dictionary = entries[key]["texts"][language]
			if String(slot["text"]).is_empty() or slot.get("source_hash", "") == hash:
				continue
			if slot["status"] == TRANSLATED or slot["status"] == APPROVED:
				slot["status"] = NEEDS_REVIEW
				_dirty_categories[entries[key]["category"]] = true


func _normalize_project(data: Dictionary) -> Dictionary:
	var result: Dictionary = default_project()
	for name in data:
		result[name] = data[name]
	result["schema"] = Migrations.SCHEMA
	return result


func _new_entry(category: String) -> Dictionary:
	var entry: Dictionary = {"category": category.strip_edges().to_lower(), "context": "", "description": "",
		"tags": [], "max_length": 0, "modified": "", "texts": {}}
	entry["texts"][source_language()] = {"text": "", "modified": "", "history": []}
	return entry


func _normalize_entry(data: Variant, category: String) -> Dictionary:
	var entry: Dictionary = _new_entry(category)
	if typeof(data) != TYPE_DICTIONARY:
		return entry
	for field in data:
		entry[field] = data[field]
	entry["category"] = String(entry["category"]).to_lower() if not String(entry["category"]).is_empty() else category
	entry["tags"] = _clean_tags(entry["tags"])
	entry["max_length"] = int(entry["max_length"])
	if typeof(entry["texts"]) != TYPE_DICTIONARY:
		entry["texts"] = {}
	for language in entry["texts"]:
		var slot: Variant = entry["texts"][language]
		if typeof(slot) == TYPE_STRING:
			slot = {"text": slot}
		var clean: Dictionary = {"text": String(slot.get("text", "")), "modified": String(slot.get("modified", "")),
			"history": slot.get("history", []) if typeof(slot.get("history", [])) == TYPE_ARRAY else []}
		if language != source_language():
			clean["status"] = String(slot.get("status", TRANSLATED if not clean["text"].is_empty() else MISSING))
			clean["source_hash"] = String(slot.get("source_hash", ""))
		entry["texts"][language] = clean
	if not entry["texts"].has(source_language()):
		entry["texts"][source_language()] = {"text": "", "modified": "", "history": []}
	return entry


func _slot(key: String, language: String) -> Dictionary:
	var texts: Dictionary = entries[key]["texts"]
	if not texts.has(language):
		texts[language] = {"text": "", "modified": "", "history": []}
		if language != source_language():
			texts[language]["status"] = MISSING
			texts[language]["source_hash"] = ""
	return texts[language]


func _push_history(slot: Dictionary) -> void:
	if String(slot["text"]).is_empty():
		return
	var list: Array = slot.get("history", [])
	list.push_front({"text": slot["text"], "date": slot.get("modified", "")})
	while list.size() > HISTORY_SIZE:
		list.pop_back()
	slot["history"] = list


func _touch(key: String) -> void:
	entries[key]["modified"] = clock.call()
	_dirty_categories[entries[key]["category"]] = true
	changed.emit(PackedStringArray([key]))


func _matches(key: String, entry: Dictionary, search: String) -> bool:
	if key.to_lower().contains(search) or String(entry["context"]).to_lower().contains(search):
		return true
	for language in entry["texts"]:
		if String(entry["texts"][language]["text"]).to_lower().contains(search):
			return true
	return false


static func _clean_tags(value: Variant) -> Array:
	var raw: Array = []
	if typeof(value) == TYPE_STRING:
		raw = Array((value as String).split(",", false))
	elif typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_PACKED_STRING_ARRAY:
		raw = Array(value)
	var result: Array = []
	for tag in raw:
		var clean: String = String(tag).strip_edges().to_lower()
		if not clean.is_empty() and not result.has(clean):
			result.append(clean)
	result.sort()
	return result


static func _json_files(path: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if not DirAccess.dir_exists_absolute(path):
		return result
	for file in DirAccess.get_files_at(path):
		if file.get_extension() == "json":
			result.append(file)
	result.sort()
	return result


# Remplace une clé de texte dans les nœuds d'un dialogue ; vrai si trouvée.
static func _replace_key_in(dialogue: Dictionary, old_key: String, new_key: String) -> bool:
	var found: bool = false
	for id in dialogue.get("nodes", {}):
		var node: Dictionary = dialogue["nodes"][id]
		if node.get("text_key", "") == old_key:
			node["text_key"] = new_key
			found = true
		for option in node.get("options", []):
			if option.get("text_key", "") == old_key:
				option["text_key"] = new_key
				found = true
	return found
