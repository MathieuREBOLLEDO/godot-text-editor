extends TestCase

## Export pour le jeu (core/exporter.gd), comparaison de versions
## (core/text_diff.gd), et non-régression : l'export de la base d'exemple
## doit rester identique, octet pour octet, aux fichiers de référence de
## tests/expected/ (en .txt). Un changement voulu du format : relancer avec
## TEXT_EDITOR_UPDATE_EXPECTED=1 pour réécrire les références, puis relire
## leur diff avant de commiter.

const Fixtures = preload("res://addons/text_editor/tests/fixtures.gd")
const TextDb = preload("res://addons/text_editor/core/text_db.gd")
const Exporter = preload("res://addons/text_editor/core/exporter.gd")
const CsvIo = preload("res://addons/text_editor/core/csv_io.gd")
const TextDiff = preload("res://addons/text_editor/core/text_diff.gd")

const EXPECTED: String = "res://addons/text_editor/tests/expected/"
const COMPARED: PackedStringArray = ["texts.csv", "json/en.json", "json/fr.json", "dialogues/village.json", "tokens.json", "manifest.json"]


func test_export_files() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("export_files"))
	var out: String = Fixtures.fresh_dir("export_files_out")
	var result: Dictionary = Exporter.export_all(db, out)
	assert_true(result["ok"])
	var csv: String = Fixtures.read(out + "/texts.csv")
	assert_true(csv.begins_with("keys,en,fr,de\n"), "Godot translation header")
	assert_true(csv.contains("MENU_QUIT,Quit,Quitter,Quit\n"), "missing German falls back to English")
	var french: Dictionary = JSON.parse_string(Fixtures.read(out + "/json/fr.json"))
	assert_eq(french["MENU_PLAY"], "Jouer")
	var dialogue: Dictionary = JSON.parse_string(Fixtures.read(out + "/dialogues/village.json"))
	assert_false(dialogue["nodes"]["n1"].has("position"), "no editor positions in the game file")
	assert_true(dialogue["characters"].has("merchant"))


func test_export_without_fallback() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("export_raw"))
	var out: String = Fixtures.fresh_dir("export_raw_out")
	Exporter.export_all(db, out, {"fallback_to_source": false})
	var german: Dictionary = JSON.parse_string(Fixtures.read(out + "/json/de.json"))
	assert_eq(german["MENU_QUIT"], "")


func test_export_is_deterministic() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("export_twice"))
	var first: String = Fixtures.fresh_dir("export_a")
	var second: String = Fixtures.fresh_dir("export_b")
	Exporter.export_all(db, first)
	Exporter.export_all(db, second)
	for name in COMPARED:
		assert_eq(Fixtures.read(first.path_join(name)), Fixtures.read(second.path_join(name)), name)


func test_export_removes_stale_dialogues() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("export_stale"))
	var out: String = Fixtures.fresh_dir("export_stale_out")
	Exporter.export_all(db, out)
	db.remove_dialogue("village")
	Exporter.export_all(db, out)
	assert_false(FileAccess.file_exists(out + "/dialogues/village.json"))


func test_export_matches_expected_files() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("regression"))
	var out: String = Fixtures.fresh_dir("regression_out")
	Exporter.export_all(db, out)
	var update: bool = OS.get_environment("TEXT_EDITOR_UPDATE_EXPECTED") == "1"
	var files: Dictionary = {}
	for name in COMPARED:
		files[name] = Fixtures.read(out.path_join(name))
	files["translators.csv"] = CsvIo.export_csv(db, {"delimiter": ";"})
	db.save()
	for name in ["project.json", "strings/ui.json", "dialogues/village.json"]:
		files["data/" + name] = Fixtures.read(db.dir.path_join(name))
	for name in files:
		# En .txt : un .csv du projet serait importé par Godot comme traduction.
		var path: String = EXPECTED + name + ".txt"
		if update:
			Fixtures.write(ProjectSettings.globalize_path(path), files[name])
			continue
		if assert_true(FileAccess.file_exists(path), "reference exists: " + name):
			# La lecture de Godot retire le BOM (vérifié par test_csv).
			assert_eq(String(files[name]).trim_prefix(CsvIo.BOM), Fixtures.read(path), "same as tests/expected/" + name)


func test_translation_files_paths() -> void:
	var db: TextDb = Fixtures.sample_db("res://game/ui/texts")
	assert_eq(Exporter.translation_files(db)[1], "res://game/ui/texts/export/texts.fr.translation")


func test_text_diff() -> void:
	var parts: Array = TextDiff.diff("Press the red button", "Press the blue button now")
	var rebuilt_a: String = ""
	var rebuilt_b: String = ""
	for part in parts:
		if part[0] != TextDiff.ADDED:
			rebuilt_a += part[1]
		if part[0] != TextDiff.REMOVED:
			rebuilt_b += part[1]
	assert_eq(rebuilt_a, "Press the red button", "old text rebuilt")
	assert_eq(rebuilt_b, "Press the blue button now", "new text rebuilt")
	assert_eq(parts[0], [TextDiff.SAME, "Press the"])
	assert_true(TextDiff.to_bbcode(parts, Color.RED, Color.GREEN).contains("[s] red[/s]"))
	assert_eq(TextDiff.diff("same", "same"), [[TextDiff.SAME, "same"]])
