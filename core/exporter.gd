@tool
extends RefCounted

## Fichiers pour le jeu (dossier export/ des données, voir FORMAT.md) :
##   texts.csv              format de traduction de Godot (keys,en,fr…) :
##                          Godot l'importe en texts.<langue>.translation,
##                          tr("MENU_PLAY") marche une fois ces fichiers
##                          déclarés (register_translations()).
##   json/<langue>.json     { clé: texte } par langue (Unity, Unreal, autre)
##   dialogues/<id>.json    dialogues pour DialogueRunner (sans positions)
##   tokens.json            { NOM: { plateforme: valeur } }
##   manifest.json          langues, dialogues, nombre d'entrées
## Déterministe : mêmes données, mêmes octets (pas de date). Les .json en
## trop dans json/ et dialogues/ (dialogue supprimé…) sont retirés.
## Traduction vide : le texte source (option fallback_to_source, vrai par
## défaut), pour qu'un texte manquant ne s'affiche pas vide en jeu.

const TextDb = preload("text_db.gd")
const DialogueData = preload("dialogue_data.gd")
const CsvIo = preload("csv_io.gd")

const TRANSLATIONS_SETTING: String = "internationalization/locale/translations"


static func export_dir(db: TextDb) -> String:
	var path: String = String(db.project.get("export_dir", "export"))
	return path if path.begins_with("res://") or path.is_absolute_path() else db.dir.path_join(path)


## Écrit tout ; { "ok": bool, "files": PackedStringArray }.
static func export_all(db: TextDb, out_dir: String = "", options: Dictionary = {}) -> Dictionary:
	if out_dir.is_empty():
		out_dir = export_dir(db)
	var fallback: bool = options.get("fallback_to_source", true)
	var files: PackedStringArray = PackedStringArray()
	var contents: Dictionary = {}
	var keys: PackedStringArray = db.query()
	contents["texts.csv"] = godot_csv(db, keys, fallback)
	for language in db.languages():
		var table: Dictionary = {}
		for key in keys:
			table[key] = _text(db, key, language, fallback)
		contents["json/%s.json" % language] = TextDb.to_json(table)
	var ids: Array = db.dialogues.keys()
	ids.sort()
	for id in ids:
		contents["dialogues/%s.json" % id] = TextDb.to_json(DialogueData.for_game(db.dialogues[id], db.project.get("characters", {})))
	contents["tokens.json"] = TextDb.to_json(db.project.get("tokens", {}))
	contents["manifest.json"] = TextDb.to_json({"schema": db.project.get("schema", 1), "source_language": db.source_language(),
		"languages": Array(db.languages()), "dialogues": ids, "entries": keys.size(),
		"platforms": db.project.get("platforms", [])})
	var ok: bool = true
	for name in contents:
		ok = TextDb.write_text(out_dir.path_join(name), contents[name]) and ok
		files.append(out_dir.path_join(name))
	for sub in ["json", "dialogues"]:
		var folder: String = out_dir.path_join(sub)
		if not DirAccess.dir_exists_absolute(folder):
			continue
		for file in DirAccess.get_files_at(folder):
			if file.get_extension() == "json" and not contents.has("%s/%s" % [sub, file]):
				DirAccess.remove_absolute(folder.path_join(file))
	return {"ok": ok, "files": files}


## CSV de traduction de Godot (séparateur « , », pas de BOM).
static func godot_csv(db: TextDb, keys: PackedStringArray, fallback: bool) -> String:
	var header: PackedStringArray = PackedStringArray(["keys"])
	header.append_array(db.languages())
	var lines: PackedStringArray = PackedStringArray([CsvIo.line(header, ",")])
	for key in keys:
		var row: PackedStringArray = PackedStringArray([key])
		for language in db.languages():
			row.append(_text(db, key, language, fallback))
		lines.append(CsvIo.line(row, ","))
	return "\n".join(lines) + "\n"


## Fichiers .translation que Godot tire de texts.csv.
static func translation_files(db: TextDb, out_dir: String = "") -> PackedStringArray:
	if out_dir.is_empty():
		out_dir = export_dir(db)
	var result: PackedStringArray = PackedStringArray()
	for language in db.languages():
		result.append(out_dir.path_join("texts.%s.translation" % language))
	return result


## Ajoute les .translation de l'export aux traductions du projet (Paramètres
## du projet > Localisation) ; vrai si la liste a changé. Modifie
## project.godot : à enregistrer par l'appelant (ProjectSettings.save()).
static func register_translations(db: TextDb, out_dir: String = "") -> bool:
	var current: PackedStringArray = ProjectSettings.get_setting(TRANSLATIONS_SETTING, PackedStringArray())
	var changed: bool = false
	for path in translation_files(db, out_dir):
		if not current.has(path):
			current.append(path)
			changed = true
	if changed:
		ProjectSettings.set_setting(TRANSLATIONS_SETTING, current)
	return changed


static func _text(db: TextDb, key: String, language: String, fallback: bool) -> String:
	var value: String = db.text(key, language)
	if value.is_empty() and fallback:
		value = db.text(key, db.source_language())
	return value
