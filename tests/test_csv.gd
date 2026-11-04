extends TestCase

## CSV des traducteurs (core/csv_io.gd) : format (guillemets, retours à la
## ligne, BOM, séparateurs), export filtré, import en deux temps (aperçu,
## conflits, cellules vides, nouvelles clés).

const Fixtures = preload("res://addons/text_editor/tests/fixtures.gd")
const TextDb = preload("res://addons/text_editor/core/text_db.gd")
const CsvIo = preload("res://addons/text_editor/core/csv_io.gd")


func test_csv_quote_and_parse_round_trip() -> void:
	var tricky: PackedStringArray = PackedStringArray(["plain", "with, comma", "with \"quotes\"", "two\nlines", " padded ", "", "é ü 日本"])
	for delimiter in [",", ";"]:
		var text: String = CsvIo.line(tricky, delimiter) + "\r\n" + CsvIo.line(PackedStringArray(["a", "b"]), delimiter)
		var rows: Array = CsvIo.parse(text, delimiter)
		assert_eq(rows.size(), 2, "two rows with " + delimiter)
		assert_eq(rows[0], tricky, "fields survive with " + delimiter)


func test_csv_parse_bom_crlf_and_blank_lines() -> void:
	var rows: Array = CsvIo.parse(CsvIo.BOM + "Key;en\r\n\r\nA;\"x;y\"\r\n")
	assert_eq(rows.size(), 2)
	assert_eq(rows[0][0], "Key", "BOM removed")
	assert_eq(rows[1][1], "x;y", "semicolon detected")


func test_csv_detect_delimiter() -> void:
	assert_eq(CsvIo.detect_delimiter("a,b,c\n1;2"), ",")
	assert_eq(CsvIo.detect_delimiter("a;b;\"c,d,e\"\n"), ";", "commas in quotes ignored")
	assert_eq(CsvIo.detect_delimiter("a\tb\tc"), "\t")


func test_csv_export_columns_and_filters() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("csv_export"))
	var text: String = CsvIo.export_csv(db)
	assert_true(text.begins_with(CsvIo.BOM), "BOM for Excel")
	var rows: Array = CsvIo.parse(text)
	assert_eq(rows[0][0], "Key")
	assert_eq(rows[0][6], "English [en]")
	assert_eq(rows[0][rows[0].size() - 1], "Revision")
	assert_eq(rows.size(), 9, "header + 8 entries")
	var ui: Array = CsvIo.parse(CsvIo.export_csv(db, {"category": "ui"}))
	assert_eq(ui.size(), 3)
	var french: Array = CsvIo.parse(CsvIo.export_csv(db, {"languages": PackedStringArray(["fr"])}))
	assert_eq(french[0].size(), 6 + 2 + 1, "fields, en, fr, revision")
	var missing: Array = CsvIo.parse(CsvIo.export_csv(db, {"languages": PackedStringArray(["fr"]), "only_missing": true}))
	assert_eq(missing.size(), 1 + 4, "only the 4 entries without French")


func test_csv_export_is_deterministic() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("csv_same"))
	assert_eq(CsvIo.export_csv(db), CsvIo.export_csv(db))


func test_csv_import_plans_without_writing() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("csv_plan"))
	var text: String = CsvIo.export_csv(db, {"delimiter": ";"})
	text = text.replace("Quitter", "Sortir")
	var plan: Dictionary = CsvIo.plan_import(db, text)
	assert_eq(plan["error"], "")
	assert_eq(plan["changes"].size(), 1)
	var change: Dictionary = plan["changes"][0]
	assert_eq([change["kind"], change["key"], change["language"], change["old"], change["new"], change["apply"]],
		[CsvIo.UPDATE, "MENU_QUIT", "fr", "Quitter", "Sortir", true])
	assert_eq(db.text("MENU_QUIT", "fr"), "Quitter", "nothing written before apply")
	assert_eq(CsvIo.apply_import(db, plan["changes"]), 1)
	assert_eq(db.text("MENU_QUIT", "fr"), "Sortir")


func test_csv_import_empty_cell_never_erases() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("csv_empty"))
	var text: String = CsvIo.export_csv(db).replace(",Jouer,", ",,")
	var plan: Dictionary = CsvIo.plan_import(db, text)
	assert_eq(plan["changes"].size(), 0)
	assert_eq(plan["warnings"][0]["code"], "empty_cells")


func test_csv_import_conflict_when_base_changed() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("csv_conflict"))
	var text: String = CsvIo.export_csv(db).replace("Quitter", "Sortir")
	db.set_translation("MENU_QUIT", "fr", "Fermer")
	var plan: Dictionary = CsvIo.plan_import(db, text)
	assert_eq(plan["changes"].size(), 1)
	assert_eq(plan["changes"][0]["kind"], CsvIo.CONFLICT)
	assert_false(plan["changes"][0]["apply"], "conflict unchecked by default")
	CsvIo.apply_import(db, plan["changes"])
	assert_eq(db.text("MENU_QUIT", "fr"), "Fermer", "unchecked conflict not applied")


func test_csv_import_new_keys_and_unknown_columns() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("csv_new"))
	var text: String = "Key,Category,English [en],French [fr],Notes\nITEM_SWORD,item,Sword,Épée,x\nbad key,ui,X,,\n"
	var plan: Dictionary = CsvIo.plan_import(db, text)
	assert_eq(plan["changes"].size(), 1)
	assert_eq(plan["changes"][0]["kind"], CsvIo.ADD)
	var codes: Array = []
	for warning in plan["warnings"]:
		codes.append(warning["code"])
	assert_has(codes, "unknown_column")
	assert_has(codes, "invalid_key")
	CsvIo.apply_import(db, plan["changes"])
	assert_eq(db.text("ITEM_SWORD", "fr"), "Épée")
	assert_eq(db.get_entry("ITEM_SWORD")["category"], "item")
	assert_eq(db.status("ITEM_SWORD", "fr"), TextDb.TRANSLATED, "imported with its source: up to date")


func test_csv_import_source_and_translation_same_row() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("csv_both"))
	var text: String = CsvIo.export_csv(db).replace(",Quit,", ",Exit,").replace("Quitter", "Sortir")
	var plan: Dictionary = CsvIo.plan_import(db, text)
	assert_eq(plan["changes"].size(), 2)
	CsvIo.apply_import(db, plan["changes"])
	assert_eq(db.text("MENU_QUIT", "en"), "Exit")
	assert_eq(db.status("MENU_QUIT", "fr"), TextDb.TRANSLATED, "translation imported with the new source")


func test_csv_import_errors() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("csv_errors"))
	assert_eq(CsvIo.plan_import(db, "")["error"], "empty")
	assert_eq(CsvIo.plan_import(db, "Name,en\nA,B\n")["error"], "no_key")
	var twice: Dictionary = CsvIo.plan_import(db, "Key,fr\nMENU_PLAY,A\nMENU_PLAY,B\n")
	assert_eq(twice["warnings"][0]["code"], "duplicate_row")


func test_csv_tokens_survive_round_trip() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("csv_tokens"))
	var plan: Dictionary = CsvIo.plan_import(db, CsvIo.export_csv(db, {"delimiter": ";"}))
	assert_eq(plan["changes"].size(), 0, "unchanged export imports nothing")
	assert_true(CsvIo.export_csv(db).contains("{INTERACT_BUTTON}"))
