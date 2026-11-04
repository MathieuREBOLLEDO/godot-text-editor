extends TestCase

## Base de textes (core/text_db.gd) : entrées, statuts, traductions
## obsolètes, historique, filtres, lecture / écriture, migration.
## Fichiers dans user://test_runner/text_editor/ : rien du jeu n'est touché.

const Fixtures = preload("res://addons/text_editor/tests/fixtures.gd")
const TextDb = preload("res://addons/text_editor/core/text_db.gd")
const Migrations = preload("res://addons/text_editor/core/migrations.gd")


func test_add_entry_rules() -> void:
	var db: TextDb = Fixtures.empty_db(Fixtures.fresh_dir("rules"))
	assert_true(db.add_entry("MENU_PLAY", "UI", "Play"))
	assert_false(db.add_entry("MENU_PLAY", "ui"), "same key twice")
	assert_false(db.add_entry("menu play", "ui"), "invalid key")
	assert_eq(db.get_entry("MENU_PLAY")["category"], "ui", "category in lower case")
	assert_eq(db.text("MENU_PLAY", "en"), "Play")
	assert_eq(db.unique_key("MENU_PLAY"), "MENU_PLAY_2")
	assert_eq(db.unique_key("new text"), "NEW_TEXT")


func test_statuses_and_entry_status() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("statuses"))
	assert_eq(db.status("MENU_PLAY", "en"), TextDb.APPROVED, "source with text")
	assert_eq(db.status("MENU_PLAY", "fr"), TextDb.TRANSLATED)
	assert_eq(db.status("MENU_QUIT", "de"), TextDb.MISSING)
	assert_eq(db.entry_status("MENU_PLAY"), TextDb.TRANSLATED)
	assert_eq(db.entry_status("MENU_QUIT"), TextDb.MISSING, "worst language")
	db.set_status("MENU_QUIT", "de", TextDb.TO_TRANSLATE)
	assert_eq(db.status("MENU_QUIT", "de"), TextDb.TO_TRANSLATE, "empty but marked to translate")
	db.set_status("MENU_PLAY", "fr", TextDb.APPROVED)
	assert_eq(db.status("MENU_PLAY", "fr"), TextDb.APPROVED)


func test_source_change_marks_translations_for_review() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("review"))
	db.set_status("MENU_PLAY", "de", TextDb.APPROVED)
	assert_true(db.set_source("MENU_PLAY", "Start"))
	assert_eq(db.status("MENU_PLAY", "fr"), TextDb.NEEDS_REVIEW)
	assert_eq(db.status("MENU_PLAY", "de"), TextDb.NEEDS_REVIEW, "approved too")
	assert_eq(db.text("MENU_PLAY", "fr"), "Jouer", "translation kept")
	assert_eq(db.status("MENU_QUIT", "fr"), TextDb.TRANSLATED, "other entries untouched")
	db.set_status("MENU_PLAY", "fr", TextDb.TRANSLATED)
	assert_eq(db.status("MENU_PLAY", "fr"), TextDb.TRANSLATED, "reviewed")
	assert_false(db.set_source("MENU_PLAY", "Start"), "same text: no change")


func test_history_keeps_previous_versions() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("history"))
	db.set_translation("MENU_PLAY", "fr", "Lancer")
	db.set_translation("MENU_PLAY", "fr", "Démarrer")
	var list: Array = db.history("MENU_PLAY", "fr")
	assert_eq(list.size(), 2)
	assert_eq(list[0]["text"], "Lancer", "most recent first")
	assert_eq(list[1]["text"], "Jouer")
	for i in TextDb.HISTORY_SIZE + 5:
		db.set_translation("MENU_PLAY", "fr", "v%d" % i)
	assert_eq(db.history("MENU_PLAY", "fr").size(), TextDb.HISTORY_SIZE, "history is bounded")


func test_duplicate_rename_remove() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("copy"))
	assert_true(db.duplicate_entry("MENU_PLAY", "MENU_PLAY_COPY"))
	assert_eq(db.text("MENU_PLAY_COPY", "fr"), "Jouer")
	db.set_translation("MENU_PLAY_COPY", "fr", "Autre")
	assert_eq(db.text("MENU_PLAY", "fr"), "Jouer", "copy is independent")
	assert_true(db.rename_key("DLG_HELLO", "DLG_GREETING"))
	assert_false(db.has_key("DLG_HELLO"))
	var keys: PackedStringArray = PackedStringArray()
	for node in db.dialogues["village"]["nodes"].values():
		if node.has("text_key"):
			keys.append(node["text_key"])
	assert_has(keys, "DLG_GREETING", "dialogue follows the rename")
	assert_true(db.remove_entry("MENU_PLAY_COPY"))
	assert_false(db.has_key("MENU_PLAY_COPY"))


func test_snapshot_restore() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("snapshot"))
	var before: Variant = db.snapshot("MENU_PLAY")
	db.set_translation("MENU_PLAY", "fr", "Changé")
	db.restore("MENU_PLAY", before)
	assert_eq(db.text("MENU_PLAY", "fr"), "Jouer")
	db.restore("MENU_PLAY", null)
	assert_false(db.has_key("MENU_PLAY"), "null removes")
	assert_null(db.snapshot("NOPE"))


func test_query_filters_and_sort() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("query"))
	db.set_field("MENU_QUIT", "tags", "Main, menu ,main")
	assert_eq(db.get_entry("MENU_QUIT")["tags"], ["main", "menu"], "tags cleaned and sorted")
	assert_eq(db.query({"category": "ui"}), PackedStringArray(["MENU_PLAY", "MENU_QUIT"]))
	assert_eq(db.query({"search": "voyageur"}), PackedStringArray(["DLG_HELLO"]), "search in translations")
	assert_eq(db.query({"search": "menu_q"}), PackedStringArray(["MENU_QUIT"]), "search in keys")
	assert_eq(db.query({"tag": "main"}), PackedStringArray(["MENU_QUIT"]))
	assert_eq(db.query({"status": "missing", "language": "fr"}), PackedStringArray(["CHAR_MERCHANT", "DLG_ASK", "DLG_HERE", "DLG_LEAVE"]))
	var by_text: PackedStringArray = db.query({"category": "ui", "sort": "en", "descending": true})
	assert_eq(by_text, PackedStringArray(["MENU_QUIT", "MENU_PLAY"]))


func test_max_length_lookup() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("limits"))
	db.project["limits"] = {"ui": 12, "ui@switch": 8}
	assert_eq(db.max_length("MENU_PLAY"), 12)
	assert_eq(db.max_length("MENU_PLAY", "switch"), 8)
	db.set_field("MENU_PLAY", "max_length", 5)
	assert_eq(db.max_length("MENU_PLAY", "switch"), 5, "entry limit wins")
	assert_eq(db.max_length("DLG_HELLO"), 0)


func test_stats() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("stats"))
	var stats: Dictionary = db.stats()
	assert_eq(stats["entries"], 8)
	assert_eq(stats["dialogues"], 1)
	assert_eq(stats["languages"], 3)
	assert_almost(stats["by_language"]["fr"]["percent"], 50.0, 0.01, "4 of 8 in French")
	assert_eq(stats["by_language"]["de"]["missing"], 7)


func test_save_and_load_round_trip() -> void:
	var path: String = Fixtures.fresh_dir("round_trip")
	var db: TextDb = Fixtures.sample_db(path)
	assert_true(db.save())
	assert_true(FileAccess.file_exists(path + "/project.json"))
	assert_true(FileAccess.file_exists(path + "/strings/ui.json"))
	assert_true(FileAccess.file_exists(path + "/dialogues/village.json"))
	var loaded: TextDb = TextDb.new()
	assert_true(loaded.load_dir(path))
	assert_eq(loaded.query(), db.query())
	assert_eq(loaded.text("TUTORIAL_INTERACT", "fr"), "Appuie sur {INTERACT_BUTTON} pour interagir.")
	assert_eq(loaded.status("MENU_PLAY", "fr"), TextDb.TRANSLATED)
	assert_eq(loaded.languages(), PackedStringArray(["en", "fr", "de"]))
	assert_eq(loaded.dialogues["village"]["nodes"].size(), 5)
	assert_false(loaded.is_dirty(), "nothing to save after a load")


func test_save_writes_only_changed_files() -> void:
	var path: String = Fixtures.fresh_dir("dirty")
	var db: TextDb = Fixtures.sample_db(path)
	db.save()
	var before: String = Fixtures.read(path + "/strings/tutorial.json")
	Fixtures.write(path + "/strings/tutorial.json", before + " ")
	db.set_translation("MENU_PLAY", "fr", "Jouer !")
	db.save()
	assert_eq(Fixtures.read(path + "/strings/tutorial.json"), before + " ", "untouched category not rewritten")
	assert_true(Fixtures.read(path + "/strings/ui.json").contains("Jouer !"))


func test_category_change_moves_entry_between_files() -> void:
	var path: String = Fixtures.fresh_dir("move")
	var db: TextDb = Fixtures.sample_db(path)
	db.save()
	db.set_field("TUTORIAL_INTERACT", "category", "ui")
	db.save()
	assert_false(FileAccess.file_exists(path + "/strings/tutorial.json"), "empty category file removed")
	assert_true(Fixtures.read(path + "/strings/ui.json").contains("TUTORIAL_INTERACT"))


func test_external_source_edit_marks_review_on_load() -> void:
	var path: String = Fixtures.fresh_dir("external")
	Fixtures.sample_db(path).save()
	var file: String = path + "/strings/ui.json"
	Fixtures.write(file, Fixtures.read(file).replace("\"Play\"", "\"Start\""))
	var db: TextDb = TextDb.new()
	db.load_dir(path)
	assert_eq(db.status("MENU_PLAY", "fr"), TextDb.NEEDS_REVIEW, "source changed outside the tool (Git merge)")


func test_duplicate_key_across_files_is_kept() -> void:
	var path: String = Fixtures.fresh_dir("duplicates")
	Fixtures.sample_db(path).save()
	Fixtures.write(path + "/strings/zz.json", TextDb.to_json({"schema": 1, "entries": {"MENU_PLAY": {"category": "zz", "texts": {"en": {"text": "Other"}}}}}))
	var db: TextDb = TextDb.new()
	assert_true(db.load_dir(path))
	assert_eq(db.text("MENU_PLAY", "en"), "Play", "first file wins")
	assert_eq(db.text("MENU_PLAY_DUPLICATE", "en"), "Other", "second renamed, not lost")
	assert_eq(db.load_errors[0]["code"], "duplicate_key")


func test_newer_schema_is_not_overwritten() -> void:
	var path: String = Fixtures.fresh_dir("newer")
	Fixtures.sample_db(path).save()
	var file: String = path + "/strings/ui.json"
	Fixtures.write(file, Fixtures.read(file).replace("\"schema\": 1", "\"schema\": 99"))
	var content: String = Fixtures.read(file)
	var db: TextDb = TextDb.new()
	assert_false(db.load_dir(path))
	db.set_project_value("font", "x")
	assert_false(db.save(), "save refused")
	assert_eq(Fixtures.read(file), content)


func test_unreadable_file_blocks_save() -> void:
	var path: String = Fixtures.fresh_dir("unreadable")
	Fixtures.sample_db(path).save()
	Fixtures.write(path + "/strings/ui.json", "{ not json")
	var db: TextDb = TextDb.new()
	assert_false(db.load_dir(path))
	assert_eq(db.load_errors[0]["code"], "unreadable")
	assert_false(db.save())


func test_opening_empty_folder_writes_nothing() -> void:
	var path: String = Fixtures.fresh_dir("untouched")
	var db: TextDb = TextDb.new()
	assert_true(db.load_dir(path))
	assert_false(db.is_dirty(), "nothing to save")
	db.save()
	assert_false(FileAccess.file_exists(path + "/project.json"), "opening the editor creates no file")
	db.add_entry("MENU_OK", "ui", "OK")
	db.save()
	assert_true(FileAccess.file_exists(path + "/project.json"), "written with the first text")


func test_migrations() -> void:
	assert_eq(Migrations.migrate({"a": 1})["data"]["schema"], Migrations.SCHEMA, "no schema: version 1")
	assert_eq(Migrations.migrate({"schema": Migrations.SCHEMA + 1})["error"], "newer")
	assert_eq(Migrations.migrate([1, 2])["error"], "invalid")


func test_old_plain_text_entries_are_normalized() -> void:
	var path: String = Fixtures.fresh_dir("plain")
	Fixtures.write(path + "/project.json", TextDb.to_json({"source_language": "en", "languages": ["en", "fr"]}))
	Fixtures.write(path + "/strings/ui.json", TextDb.to_json({"entries": {"MENU_OK": {"texts": {"en": "OK", "fr": "D'accord"}}}}))
	var db: TextDb = TextDb.new()
	assert_true(db.load_dir(path))
	assert_eq(db.text("MENU_OK", "fr"), "D'accord")
	assert_eq(db.get_entry("MENU_OK")["category"], "ui", "category from the file name")
	assert_eq(db.project["categories"], Array(TextDb.DEFAULT_CATEGORIES), "missing settings get defaults")


func test_languages() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("languages"))
	assert_true(db.add_language("ja"))
	assert_false(db.add_language("fr"))
	assert_true(db.remove_language("de"))
	assert_false(db.remove_language("en"), "source stays")
	assert_eq(db.languages(), PackedStringArray(["en", "fr", "ja"]))
	assert_eq(db.text("MENU_PLAY", "de"), "Spielen", "texts of a removed language are kept")
