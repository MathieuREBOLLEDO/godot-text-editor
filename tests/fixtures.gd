extends RefCounted

## Données d'exemple communes aux tests : une base anglais / français /
## allemand, deux catégories, un token, un dialogue avec choix. Date figée
## (clock) pour des fichiers identiques d'un lancement à l'autre.

const TextDb = preload("res://addons/text_editor/core/text_db.gd")
const DialogueData = preload("res://addons/text_editor/core/dialogue_data.gd")

const ROOT: String = "user://test_runner/text_editor/"
const DATE: String = "2026-01-01T00:00:00"


static func clean(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub in DirAccess.get_directories_at(path):
		clean(path.path_join(sub))
		DirAccess.remove_absolute(path.path_join(sub))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))


static func fresh_dir(name: String) -> String:
	var path: String = ROOT + name
	clean(path)
	DirAccess.make_dir_recursive_absolute(path)
	return path


static func empty_db(path: String) -> TextDb:
	var db: TextDb = TextDb.new()
	db.clock = func() -> String: return DATE
	db.create(path)
	db.set_project_value("languages", ["en", "fr", "de"])
	return db


static func sample_db(path: String) -> TextDb:
	var db: TextDb = empty_db(path)
	db.project["tokens"] = {"INTERACT_BUTTON": {"pc": "E", "playstation": "Cross", "xbox": "A"}}
	db.project["characters"] = {"merchant": {"name_key": "CHAR_MERCHANT", "color": "#e0a040", "portrait": ""}}
	db.add_entry("MENU_PLAY", "ui", "Play")
	db.set_field("MENU_PLAY", "context", "Main Menu")
	db.set_translation("MENU_PLAY", "fr", "Jouer")
	db.set_translation("MENU_PLAY", "de", "Spielen")
	db.add_entry("MENU_QUIT", "ui", "Quit")
	db.set_translation("MENU_QUIT", "fr", "Quitter")
	db.add_entry("TUTORIAL_INTERACT", "tutorial", "Press {INTERACT_BUTTON} to interact.")
	db.set_translation("TUTORIAL_INTERACT", "fr", "Appuie sur {INTERACT_BUTTON} pour interagir.")
	db.add_entry("CHAR_MERCHANT", "dialogue", "Merchant")
	db.add_entry("DLG_HELLO", "dialogue", "Hello, traveller.")
	db.set_translation("DLG_HELLO", "fr", "Bonjour, voyageur.")
	db.add_entry("DLG_ASK", "choice", "Tell me about the merchant.")
	db.add_entry("DLG_LEAVE", "choice", "Goodbye.")
	db.add_entry("DLG_HERE", "dialogue", "He is right here.")
	db.add_dialogue("village", village())
	return db


## START → « Hello » → choix (marchand → « He is here » → END ; partir → END).
static func village() -> Dictionary:
	var dialogue: Dictionary = {"nodes": {}, "links": [], "next_id": 1}
	var start: String = DialogueData.add_node(dialogue, DialogueData.START, Vector2.ZERO)
	var hello: String = DialogueData.add_node(dialogue, DialogueData.LINE, Vector2(300, 0))
	dialogue["nodes"][hello]["speaker"] = "merchant"
	dialogue["nodes"][hello]["text_key"] = "DLG_HELLO"
	var choice: String = DialogueData.add_node(dialogue, DialogueData.CHOICE, Vector2(600, 0))
	dialogue["nodes"][choice]["options"] = [{"text_key": "DLG_ASK", "condition": ""}, {"text_key": "DLG_LEAVE", "condition": ""}]
	var here: String = DialogueData.add_node(dialogue, DialogueData.LINE, Vector2(900, 0))
	dialogue["nodes"][here]["speaker"] = "merchant"
	dialogue["nodes"][here]["text_key"] = "DLG_HERE"
	var finish: String = DialogueData.add_node(dialogue, DialogueData.END, Vector2(1200, 0))
	DialogueData.connect_nodes(dialogue, start, 0, hello)
	DialogueData.connect_nodes(dialogue, hello, 0, choice)
	DialogueData.connect_nodes(dialogue, choice, 0, here)
	DialogueData.connect_nodes(dialogue, choice, 1, finish)
	DialogueData.connect_nodes(dialogue, here, 0, finish)
	return dialogue


static func read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


static func write(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
