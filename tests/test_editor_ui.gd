extends TestCase

## Intégration de l'onglet Texts : la vue entière construite sur une base
## d'exemple (user://), chaque espace ouvert, quelques actions faites comme à
## la souris (ajout, traduction, nœud de dialogue, aperçu joué, export,
## validation), sans erreur moteur ; aucun texte d'interface ne reste une clé
## brute (texte manquant dans texts.gd). Le rendu se vérifie à l'œil (capture).

const Fixtures = preload("res://addons/text_editor/tests/fixtures.gd")
const MainView = preload("res://addons/text_editor/editor/main_view.gd")
const TextDb = preload("res://addons/text_editor/core/text_db.gd")
const DialogueData = preload("res://addons/text_editor/core/dialogue_data.gd")

var _previous_dir: Variant = null
var _view: MainView
var _dir: String = ""


func before_each() -> void:
	_dir = Fixtures.fresh_dir("ui")
	var db: TextDb = Fixtures.sample_db(_dir)
	db.project["export_dir"] = Fixtures.fresh_dir("ui_export")
	db.save()
	_previous_dir = ProjectSettings.get_setting(MainView.SETTING_DATA_DIR) if ProjectSettings.has_setting(MainView.SETTING_DATA_DIR) else null
	ProjectSettings.set_setting(MainView.SETTING_DATA_DIR, _dir)
	_view = MainView.new()
	_view.size = Vector2(1400, 860)
	add_test_node(_view)
	await frames(2)


func after_each() -> void:
	ProjectSettings.set_setting(MainView.SETTING_DATA_DIR, _previous_dir)


func test_every_view_opens_without_raw_keys() -> void:
	for entry in MainView.VIEWS:
		_view.show_view(entry[0])
		await frames(2)
		var raw: PackedStringArray = _raw_keys(_view)
		assert_eq(raw, PackedStringArray(), "%s shows text keys instead of texts" % entry[0])


func test_database_add_and_edit() -> void:
	_view.show_view("database")
	var database: Control = _view.view("database")
	database.add_entry()
	await frames(1)
	assert_true(_view.db.has_key("UI_NEW"), "new text created in the filtered category")
	database.search("Jouer")
	await frames(1)
	assert_eq(database._keys, PackedStringArray(["MENU_PLAY"]))
	database.select("MENU_QUIT")
	await frames(2)
	assert_eq(database._selected, "MENU_QUIT")


func test_localization_save_and_next() -> void:
	_view.open_entry("CHAR_MERCHANT", "fr")
	await frames(2)
	var localization: Control = _view.view("localization")
	assert_eq(localization._key, "CHAR_MERCHANT")
	localization._target.text = "Marchand"
	localization._save_and_next()
	await frames(1)
	assert_eq(_view.db.text("CHAR_MERCHANT", "fr"), "Marchand")
	assert_eq(_view.db.status("CHAR_MERCHANT", "fr"), TextDb.TRANSLATED)
	assert_ne(localization._key, "CHAR_MERCHANT", "next text opened")


func test_dialogue_graph_and_preview() -> void:
	_view.open_node("village", "n3")
	await frames(3)
	var dialogues: Control = _view.view("dialogues")
	var graph: GraphEdit = dialogues._graph
	var count: int = 0
	for child in graph.get_children():
		if child is GraphNode:
			count += 1
	assert_eq(count, 5, "one graph node per dialogue node")
	assert_eq(graph.get_connection_list().size(), 5, "one connection per link")
	assert_true((graph.get_node("n3") as GraphNode).selected, "target node selected")
	dialogues._add_position = Vector2(100, 300)
	dialogues._add_node(DialogueData.EVENT)
	await frames(2)
	assert_eq(_view.db.dialogues["village"]["nodes"].size(), 6)
	dialogues._tabs.current_tab = dialogues.TAB_NARRATIVE
	await frames(2)
	dialogues._tabs.current_tab = dialogues.TAB_PREVIEW
	await frames(2)
	var preview: Control = dialogues._preview
	assert_eq(preview._text.text, "Hello, traveller.")
	preview._show(preview._runner.next())
	await frames(1)
	assert_eq(preview._choices.get_child_count(), 2, "two choices shown")
	assert_eq(_raw_keys(_view), PackedStringArray())


func test_export_and_validation() -> void:
	_view.show_view("import_export")
	await frames(1)
	_view.view("import_export")._export_game()
	assert_true(FileAccess.file_exists(_view.db.project["export_dir"].path_join("texts.csv")))
	_view.show_view("qa")
	await frames(1)
	var qa: Control = _view.view("qa")
	assert_gt(qa._tree.get_root().get_child_count(), 0, "issues listed (German is missing)")


func test_autosave_writes_files() -> void:
	_view.db.set_translation("MENU_QUIT", "de", "Beenden")
	_view.save_now()
	assert_true(Fixtures.read(_dir + "/strings/ui.json").contains("Beenden"))


# Textes affichés qui ressemblent à une clé de texts.gd (snake_case).
func _raw_keys(root: Node) -> PackedStringArray:
	var regex: RegEx = RegEx.create_from_string("^[a-z]+(_[a-z0-9]+)+$")
	# Les données du projet (plateforme steam_deck…) ne sont pas des clés.
	var data: String = TextDb.to_json(_view.db.project) + TextDb.to_json(_view.db.dialogues)
	var found: PackedStringArray = PackedStringArray()
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var values: Array = []
		if node is Label or node is Button or node is LineEdit:
			values.append(node.get("text"))
		if node is LineEdit:
			values.append(node.placeholder_text)
		if node is Control:
			values.append(node.tooltip_text)
		for value in values:
			if regex.search(String(value)) != null and not found.has(value) and not data.contains("\"%s\"" % value):
				found.append(value)
	return found
