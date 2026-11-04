@tool
extends RefCounted

## CSV pour les traducteurs (Excel, Google Sheets, LibreOffice) : export
## filtré, puis import en deux temps : plan_import() liste les changements,
## rien n'est écrit avant apply_import() (choix de l'utilisateur).
##
## Colonnes : Key, Category, Context, Description, Tags, Max Length, une par
## langue (« English [en] ») et Revision. Revision est l'empreinte de la ligne
## à l'export : si la base a changé depuis, une cellule différente est un
## conflit (décoché par défaut) au lieu d'une simple mise à jour. Une cellule
## vide n'efface jamais un texte de la base.
## UTF-8 avec BOM (Excel), fins de ligne CRLF, guillemets doublés.

const TextDb = preload("text_db.gd")

const KEY: String = "Key"
const REVISION: String = "Revision"
const FIELDS: Dictionary = {"Category": "category", "Context": "context", "Description": "description",
	"Tags": "tags", "Max Length": "max_length"}
const BOM: String = "﻿"

const ADD: String = "add"
const UPDATE: String = "update"
const CONFLICT: String = "conflict"


# --- Format CSV ---

## Champ entre guillemets s'il contient le séparateur, un guillemet, un
## retour à la ligne ou une espace au bord.
static func quote(value: String, delimiter: String) -> String:
	if value.contains(delimiter) or value.contains("\"") or value.contains("\n") or value.contains("\r") \
			or value != value.strip_edges():
		return "\"%s\"" % value.replace("\"", "\"\"")
	return value


static func line(fields: PackedStringArray, delimiter: String) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for field in fields:
		parts.append(quote(field, delimiter))
	return delimiter.join(parts)


## Séparateur d'un CSV : celui qui revient le plus sur la 1re ligne hors
## guillemets (« , », « ; » ou tabulation).
static func detect_delimiter(text: String) -> String:
	var counts: Dictionary = {",": 0, ";": 0, "\t": 0}
	var quoted: bool = false
	for character in text:
		if character == "\"":
			quoted = not quoted
		elif not quoted and (character == "\n" or character == "\r"):
			break
		elif not quoted and counts.has(character):
			counts[character] += 1
	var best: String = ","
	for delimiter in [";", "\t"]:
		if counts[delimiter] > counts[best]:
			best = delimiter
	return best


## Lignes d'un CSV (guillemets, guillemets doublés, retours à la ligne dans
## un champ, BOM, CRLF). Les lignes entièrement vides sont sautées.
static func parse(text: String, delimiter: String = "") -> Array:
	if text.begins_with(BOM):
		text = text.substr(1)
	if delimiter.is_empty():
		delimiter = detect_delimiter(text)
	var rows: Array = []
	var row: PackedStringArray = PackedStringArray()
	var field: String = ""
	var quoted: bool = false
	var index: int = 0
	var length: int = text.length()
	while index < length:
		var character: String = text[index]
		if quoted:
			if character == "\"":
				if index + 1 < length and text[index + 1] == "\"":
					field += "\""
					index += 1
				else:
					quoted = false
			else:
				field += character
		elif character == "\"":
			quoted = true
		elif character == delimiter:
			row.append(field)
			field = ""
		elif character == "\n" or character == "\r":
			if character == "\r" and index + 1 < length and text[index + 1] == "\n":
				index += 1
			row.append(field)
			field = ""
			if not (row.size() == 1 and row[0].is_empty()):
				rows.append(row)
			row = PackedStringArray()
		else:
			field += character
		index += 1
	if not field.is_empty() or not row.is_empty():
		row.append(field)
		rows.append(row)
	return rows


# --- Export ---

static func language_header(code: String) -> String:
	var name: String = TranslationServer.get_language_name(code.get_slice("_", 0))
	return "%s [%s]" % [name if not name.is_empty() else code, code]


## Code d'une colonne de langue (« French [fr] » ou « fr ») ; "" sinon.
static func header_language(header: String, languages: PackedStringArray) -> String:
	header = header.strip_edges()
	if header.ends_with("]") and header.contains("["):
		var code: String = header.get_slice("[", header.get_slice_count("[") - 1).trim_suffix("]")
		return code if languages.has(code) else ""
	return header if languages.has(header) else ""


## Options : category (""=toutes), languages (cibles exportées, vide =
## toutes ; la source est toujours là), only_missing (lignes où une langue
## exportée est missing, to_translate ou needs_review), delimiter.
static func export_csv(db: TextDb, options: Dictionary = {}) -> String:
	var delimiter: String = options.get("delimiter", ",")
	var languages: PackedStringArray = _export_languages(db, options.get("languages", PackedStringArray()))
	var header: PackedStringArray = PackedStringArray([KEY])
	for title in FIELDS:
		header.append(title)
	for language in languages:
		header.append(language_header(language))
	header.append(REVISION)
	var lines: PackedStringArray = PackedStringArray([line(header, delimiter)])
	var filter: Dictionary = {"category": options.get("category", "")}
	for key in db.query(filter):
		if options.get("only_missing", false) and not _needs_work(db, key, languages):
			continue
		var entry: Dictionary = db.get_entry(key)
		var row: PackedStringArray = PackedStringArray([key])
		for title in FIELDS:
			row.append(_field_text(entry, FIELDS[title]))
		for language in languages:
			row.append(db.text(key, language))
		row.append(revision(db, key, languages))
		lines.append(line(row, delimiter))
	return BOM + "\r\n".join(lines) + "\r\n"


## Empreinte d'une ligne (champs et textes des langues données).
static func revision(db: TextDb, key: String, languages: PackedStringArray) -> String:
	var entry: Dictionary = db.get_entry(key)
	var parts: PackedStringArray = PackedStringArray()
	for title in FIELDS:
		parts.append(_field_text(entry, FIELDS[title]))
	for language in languages:
		parts.append(db.text(key, language))
	return "\u001f".join(parts).md5_text().substr(0, 8)


# --- Import ---

## Changements qu'apporterait un CSV, sans rien écrire :
## { "changes": [...], "warnings": [{ "code", "args" }], "error": "" }.
## Changement : { "kind": add|update|conflict, "key", "field" (champ ou
## « text »), "language", "old", "new", "apply" }. Un ajout porte aussi
## « row » (champs et textes de la nouvelle entrée).
static func plan_import(db: TextDb, text: String) -> Dictionary:
	var result: Dictionary = {"changes": [], "warnings": [], "error": ""}
	var rows: Array = parse(text)
	if rows.is_empty():
		result["error"] = "empty"
		return result
	var header: PackedStringArray = rows[0]
	var key_column: int = -1
	var revision_column: int = -1
	var field_columns: Dictionary = {}
	var language_columns: Dictionary = {}
	for column in header.size():
		var title: String = header[column].strip_edges()
		if title == KEY:
			key_column = column
		elif title == REVISION:
			revision_column = column
		elif FIELDS.has(title):
			field_columns[column] = FIELDS[title]
		elif not header_language(title, db.languages()).is_empty():
			language_columns[column] = header_language(title, db.languages())
		elif not title.is_empty():
			result["warnings"].append({"code": "unknown_column", "args": [title]})
	if key_column < 0:
		result["error"] = "no_key"
		return result
	var exported: PackedStringArray = PackedStringArray()
	for language in db.languages():
		if language_columns.values().has(language):
			exported.append(language)
	var seen: Dictionary = {}
	var empty_cells: int = 0
	for index in range(1, rows.size()):
		var row: PackedStringArray = rows[index]
		var key: String = _cell(row, key_column).strip_edges()
		if key.is_empty():
			continue
		if seen.has(key):
			result["warnings"].append({"code": "duplicate_row", "args": [key]})
			continue
		seen[key] = true
		if not db.has_key(key):
			_plan_add(db, key, row, field_columns, language_columns, result)
			continue
		var stale: bool = revision_column >= 0 and not _cell(row, revision_column).is_empty() \
				and _cell(row, revision_column) != revision(db, key, exported)
		var kind: String = CONFLICT if stale else UPDATE
		var entry: Dictionary = db.get_entry(key)
		for column in field_columns:
			var field: String = field_columns[column]
			var value: String = _cell(row, column)
			var old: String = _field_text(entry, field)
			if value.strip_edges() != old.strip_edges():
				if value.strip_edges().is_empty():
					empty_cells += 1
					continue
				result["changes"].append({"kind": kind, "key": key, "field": field, "language": "", "old": old, "new": value, "apply": kind == UPDATE})
		for column in language_columns:
			var language: String = language_columns[column]
			var value: String = _cell(row, column)
			var old: String = db.text(key, language)
			if value == old:
				continue
			if value.is_empty():
				empty_cells += 1
				continue
			result["changes"].append({"kind": kind, "key": key, "field": "text", "language": language, "old": old, "new": value, "apply": kind == UPDATE})
	if empty_cells > 0:
		result["warnings"].append({"code": "empty_cells", "args": [empty_cells]})
	return result


## Applique les changements cochés (apply) ; renvoie leur nombre. Le texte
## source passe en premier : les traductions importées sur la même ligne
## sont alors à jour (pas « needs_review »).
static func apply_import(db: TextDb, changes: Array) -> int:
	var count: int = 0
	var ordered: Array = changes.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["language"] == db.source_language() and b["language"] != db.source_language())
	for change in ordered:
		if not change.get("apply", false):
			continue
		if change["kind"] == ADD:
			var row: Dictionary = change["row"]
			if not db.add_entry(change["key"], row.get("category", "ui")):
				continue
			for field in row:
				if field != "texts" and field != "category":
					db.set_field(change["key"], field, row[field])
			var texts: Dictionary = row.get("texts", {})
			if texts.has(db.source_language()):
				db.set_source(change["key"], texts[db.source_language()])
			for language in texts:
				if language != db.source_language():
					db.set_translation(change["key"], language, texts[language])
			count += 1
		elif change["field"] == "text":
			if db.set_translation(change["key"], change["language"], change["new"]):
				count += 1
		elif db.set_field(change["key"], change["field"], change["new"]):
			count += 1
	return count


static func _plan_add(db: TextDb, key: String, row: PackedStringArray, field_columns: Dictionary, language_columns: Dictionary, result: Dictionary) -> void:
	if not db.is_valid_key(key):
		result["warnings"].append({"code": "invalid_key", "args": [key]})
		return
	var data: Dictionary = {"category": "ui", "texts": {}}
	for column in field_columns:
		if not _cell(row, column).strip_edges().is_empty():
			data[field_columns[column]] = _cell(row, column)
	for column in language_columns:
		if not _cell(row, column).is_empty():
			data["texts"][language_columns[column]] = _cell(row, column)
	var source: String = data["texts"].get(db.source_language(), "")
	result["changes"].append({"kind": ADD, "key": key, "field": "", "language": "", "old": "", "new": source, "apply": true, "row": data})


static func _export_languages(db: TextDb, wanted: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray([db.source_language()])
	for language in db.target_languages():
		if wanted.is_empty() or wanted.has(language):
			result.append(language)
	return result


static func _needs_work(db: TextDb, key: String, languages: PackedStringArray) -> bool:
	for language in languages:
		var current: String = db.status(key, language)
		if current == TextDb.MISSING or current == TextDb.TO_TRANSLATE or current == TextDb.NEEDS_REVIEW:
			return true
	return false


static func _field_text(entry: Dictionary, field: String) -> String:
	match field:
		"tags":
			return ", ".join(PackedStringArray(entry.get("tags", [])))
		"max_length":
			return str(int(entry.get("max_length", 0))) if int(entry.get("max_length", 0)) > 0 else ""
	return String(entry.get(field, ""))


static func _cell(row: PackedStringArray, column: int) -> String:
	return row[column] if column < row.size() else ""
