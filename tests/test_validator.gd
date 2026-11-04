extends TestCase

## Validation (core/validator.gd) : chaque contrôle sur un cas qui le
## déclenche, et la base d'exemple propre sur les contrôles bloquants.

const Fixtures = preload("res://addons/text_editor/tests/fixtures.gd")
const TextDb = preload("res://addons/text_editor/core/text_db.gd")
const DialogueData = preload("res://addons/text_editor/core/dialogue_data.gd")
const Validator = preload("res://addons/text_editor/core/validator.gd")


func _codes(issues: Array) -> Array:
	var result: Array = []
	for issue in issues:
		result.append(issue["code"])
	return result


func _find(issues: Array, code: String) -> Dictionary:
	for issue in issues:
		if issue["code"] == code:
			return issue
	return {}


func test_sample_has_no_errors() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("valid"))
	var issues: Array = Validator.run(db)
	assert_eq(Validator.counts(issues)[Validator.ERROR], 0, str(_codes(issues)))
	assert_has(_codes(issues), "missing_translation", "German is missing")


func test_entry_checks() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("entry_checks"))
	db.add_entry("EMPTY_ONE", "ui", "")
	db.set_translation("TUTORIAL_INTERACT", "de", "Drücke {INTERACT} zum {X}.")
	db.set_source("MENU_QUIT", "Quit game")
	db.project["limits"] = {"ui": 6}
	db.add_entry("PLAYER_HELLO", "ui", "Hi {PLAYER_NAME}")
	var issues: Array = Validator.run(db)
	var codes: Array = _codes(issues)
	assert_has(codes, "empty_source")
	assert_has(codes, "missing_token")
	assert_has(codes, "extra_token")
	assert_has(codes, "obsolete")
	assert_has(codes, "too_long")
	assert_has(codes, "unknown_token")
	assert_eq(_find(issues, "missing_token")["language"], "de")
	assert_eq(_find(issues, "missing_token")["args"], ["{INTERACT_BUTTON}"])
	assert_eq(_find(issues, "too_long")["key"], "MENU_PLAY", "Spielen > 6")


func test_token_length_uses_longest_value() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("token_length"))
	assert_eq(Validator.display_length(db, "Press {INTERACT_BUTTON}"), "Press Cross".length())


func test_platform_limit() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("platform_limit"))
	db.project["limits"] = {"ui": 20, "ui@switch": 5}
	var issues: Array = Validator.run(db)
	var issue: Dictionary = _find(issues, "too_long")
	assert_eq(issue.get("key", ""), "MENU_PLAY", "Spielen > 5 on Switch")
	assert_eq(issue["args"][2], "switch")


func test_unused_texts() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("unused"))
	var issues: Array = Validator.run(db, {"project_text": "tr(\"MENU_PLAY\")\ntr(\"TUTORIAL_INTERACT\")"})
	var unused: Array = []
	for issue in issues:
		if issue["code"] == "unused":
			unused.append(issue["key"])
	assert_eq(unused, ["MENU_QUIT"], "used in code, in a dialogue or as a character name")


func test_unsupported_characters() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("font"))
	db.set_translation("MENU_QUIT", "de", "終了")
	var font: FontFile = FontFile.new()
	var issues: Array = Validator.run(db, {"font": font})
	assert_has(_codes(issues), "unsupported_chars")


func test_dialogue_checks() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("dialogue_checks"))
	var dialogue: Dictionary = db.dialogues["village"]
	DialogueData.disconnect_port(dialogue, "n3", 1)
	var orphan: String = DialogueData.add_node(dialogue, DialogueData.LINE, Vector2.ZERO)
	dialogue["nodes"][orphan]["text_key"] = "NOPE_KEY"
	dialogue["nodes"][orphan]["speaker"] = "ghost"
	var jump: String = DialogueData.add_node(dialogue, DialogueData.JUMP, Vector2.ZERO)
	DialogueData.connect_nodes(dialogue, "n4", 0, jump)
	var issues: Array = Validator.run(db)
	var codes: Array = _codes(issues)
	assert_has(codes, "choice_without_target")
	assert_has(codes, "orphan_node")
	assert_has(codes, "unknown_key")
	assert_has(codes, "unknown_speaker")
	assert_has(codes, "jump_target_missing")
	assert_has(codes, "no_end")
	var orphans: Array = []
	for issue in issues:
		if issue["code"] == "orphan_node":
			orphans.append(issue["node"])
	assert_has(orphans, orphan)
	assert_has(orphans, "n5", "END no longer reached")
	assert_eq(_find(issues, "unknown_key")["key"], "NOPE_KEY", "points to the key")


func test_dialogue_without_start() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("no_start"))
	db.add_dialogue("empty", {"nodes": {}, "links": [], "next_id": 1})
	assert_has(_codes(Validator.run(db)), "no_start")


func test_infinite_loop_detection() -> void:
	var dialogue: Dictionary = Fixtures.village()
	# Boucle avec un choix qui en sort : voulue, pas signalée.
	DialogueData.connect_nodes(dialogue, "n4", 0, "n3")
	assert_eq(Validator.infinite_loops(dialogue).size(), 0, "loop back to a choice with an exit")
	# Deux répliques qui se renvoient l'une à l'autre : sans fin.
	DialogueData.connect_nodes(dialogue, "n4", 0, "n2")
	DialogueData.connect_nodes(dialogue, "n2", 0, "n4")
	var loops: Array = Validator.infinite_loops(dialogue)
	assert_eq(loops.size(), 1)
	assert_eq(loops[0], ["n2", "n4"])


func test_load_errors_are_reported() -> void:
	var db: TextDb = Fixtures.sample_db(Fixtures.fresh_dir("load_issues"))
	db.load_errors.append({"code": "duplicate_key", "args": ["A", "A_DUPLICATE"]})
	var issue: Dictionary = _find(Validator.run(db), "duplicate_key")
	assert_eq(issue["key"], "A_DUPLICATE")
	assert_eq(issue["severity"], Validator.WARNING)
