@tool
extends ScrollContainer

## Import / Export : CSV pour les traducteurs (catégorie, langues, seulement
## ce qui reste à faire, séparateur), import d'un CSV revu en deux temps
## (aperçu des changements, conflits décochés, rien n'est écrit avant
## « Appliquer »), et fichiers du jeu (texts.csv de Godot, JSON par langue,
## dialogues), avec leur déclaration dans les traductions du projet.

const Tokens = preload("text_theme.gd")
const Widgets = preload("widgets.gd")
const TextDb = preload("../core/text_db.gd")
const CsvIo = preload("../core/csv_io.gd")
const Exporter = preload("../core/exporter.gd")

var main: Control

var _category: OptionButton
var _languages: HFlowContainer
var _only_missing: CheckBox
var _delimiter: OptionButton
var _fallback: CheckBox
var _export_dir: Label
var _export_result: Label
var _file_dialog: EditorFileDialog
var _dialog_purpose: String = ""
var _import_dialog: ConfirmationDialog
var _import_tree: Tree
var _import_warnings: Label
var _plan: Dictionary = {}


func _ready() -> void:
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var column: VBoxContainer = Widgets.vbox(16)
	margin.add_child(column)
	var row: HBoxContainer = Widgets.hbox(16)
	column.add_child(row)

	var translators: Array = Widgets.card("export_translators")
	translators[0].size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(translators[0])
	var body: VBoxContainer = translators[1]
	body.add_child(_help("export_translators_help"))
	_category = Widgets.option([])
	body.add_child(_labeled("column_category", _category))
	_languages = HFlowContainer.new()
	body.add_child(_labeled("export_languages", _languages))
	_only_missing = CheckBox.new()
	_only_missing.text = Widgets.t("only_missing")
	_only_missing.tooltip_text = Widgets.t("only_missing_tip")
	body.add_child(_only_missing)
	_delimiter = Widgets.option([[Widgets.t("delimiter_comma"), ","], [Widgets.t("delimiter_semicolon"), ";"]], "delimiter_tip")
	body.add_child(_labeled("delimiter", _delimiter))
	body.add_child(Widgets.button("export_csv", &"Save", "export_csv_tip", _open_dialog.bind("export")))

	var import_card: Array = Widgets.card("import_translations")
	import_card[0].size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(import_card[0])
	import_card[1].add_child(_help("import_help"))
	import_card[1].add_child(Widgets.button("import_csv", &"Load", "import_csv_tip", _open_dialog.bind("import")))

	var game: Array = Widgets.card("export_game")
	column.add_child(game[0])
	game[1].add_child(_help("export_game_help"))
	_export_dir = Widgets.label("", Tokens.MONO)
	game[1].add_child(_labeled("export_folder", _export_dir))
	_fallback = CheckBox.new()
	_fallback.text = Widgets.t("fallback_to_source")
	_fallback.tooltip_text = Widgets.t("fallback_to_source_tip")
	_fallback.button_pressed = true
	game[1].add_child(_fallback)
	var actions: HBoxContainer = Widgets.hbox(8)
	game[1].add_child(actions)
	actions.add_child(Widgets.button("export_game_files", &"", "export_game_files_tip", _export_game, true))
	actions.add_child(Widgets.button("register_translations", &"Translation", "register_translations_tip", _register))
	_export_result = Widgets.label("", Tokens.DIM)
	_export_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game[1].add_child(_export_result)

	_build_import_dialog()


func refresh() -> void:
	var db: TextDb = main.db
	var categories: Array = [[Widgets.t("all_categories"), ""]]
	for category in db.categories():
		categories.append([category, category])
	Widgets.set_options(_category, categories)
	var previous: Dictionary = {}
	for child in _languages.get_children():
		previous[child.get_meta("language")] = child.button_pressed
		child.queue_free()
	for language in db.target_languages():
		var check: CheckBox = CheckBox.new()
		check.text = Widgets.language_name(language)
		check.set_meta("language", language)
		check.button_pressed = previous.get(language, true)
		_languages.add_child(check)
	_export_dir.text = Exporter.export_dir(db)


func _help(key: String) -> Control:
	var bubble: PanelContainer = PanelContainer.new()
	bubble.theme_type_variation = Tokens.BUBBLE
	var text: Label = Widgets.label(Widgets.t(key), Tokens.DIM)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 260
	bubble.add_child(text)
	return bubble


func _labeled(key: String, control: Control) -> Control:
	var row: HBoxContainer = Widgets.hbox(8)
	var caption: Label = Widgets.label(Widgets.t(key), Tokens.DIM)
	caption.custom_minimum_size.x = 110
	row.add_child(caption)
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _open_dialog(purpose: String) -> void:
	# Créée au premier usage : EditorFileDialog n'existe que dans l'éditeur
	# (les tests construisent la vue hors éditeur).
	if _file_dialog == null:
		_file_dialog = EditorFileDialog.new()
		_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
		_file_dialog.add_filter("*.csv", "CSV")
		_file_dialog.file_selected.connect(_on_file_selected)
		add_child(_file_dialog)
	_dialog_purpose = purpose
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE if purpose == "export" else EditorFileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.title = Widgets.t("export_csv" if purpose == "export" else "import_csv")
	if purpose == "export":
		var category: String = Widgets.selected_value(_category)
		_file_dialog.current_file = "texts_%s.csv" % (category if not category.is_empty() else "all")
	_file_dialog.popup_file_dialog()


func _on_file_selected(path: String) -> void:
	if _dialog_purpose == "export":
		_export_csv(path)
	else:
		_preview_import(path)


func _export_csv(path: String) -> void:
	var languages: PackedStringArray = PackedStringArray()
	for child in _languages.get_children():
		if child.button_pressed:
			languages.append(child.get_meta("language"))
	var text: String = CsvIo.export_csv(main.db, {"category": Widgets.selected_value(_category), "languages": languages,
		"only_missing": _only_missing.button_pressed, "delimiter": Widgets.selected_value(_delimiter)})
	if not TextDb.write_text(path, text):
		main.set_status(Widgets.tf("error_save", [path]), "bad")
		return
	_keep_csv_out_of_import(path)
	main.set_status(Widgets.tf("exported", [path, CsvIo.parse(text).size() - 1]), "good")


## Un CSV rangé dans le projet serait importé par Godot comme traduction :
## « Keep File » (laissé tel quel).
func _keep_csv_out_of_import(path: String) -> void:
	var local: String = ProjectSettings.localize_path(path)
	if not local.begins_with("res://") or FileAccess.file_exists(local + ".import"):
		return
	TextDb.write_text(local + ".import", "[remap]\n\nimporter=\"keep\"\n")


# --- Import ---

func _build_import_dialog() -> void:
	_import_dialog = ConfirmationDialog.new()
	_import_dialog.title = Widgets.t("import_title")
	_import_dialog.min_size = Vector2i(860, 480)
	_import_dialog.confirmed.connect(_apply_import)
	var column: VBoxContainer = Widgets.vbox(8)
	_import_dialog.add_child(column)
	_import_warnings = Widgets.label("", Tokens.DIM)
	_import_warnings.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_import_warnings)
	_import_tree = Tree.new()
	_import_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_import_tree.columns = 5
	_import_tree.hide_root = true
	_import_tree.column_titles_visible = true
	for index in 5:
		_import_tree.set_column_title(index, Widgets.t(["import_apply_column", "import_kind", "column_key", "import_old", "import_new"][index]))
		_import_tree.set_column_expand(index, index >= 3)
	_import_tree.set_column_custom_minimum_width(0, 70)
	_import_tree.set_column_custom_minimum_width(1, 100)
	_import_tree.set_column_custom_minimum_width(2, 220)
	_import_tree.item_edited.connect(_on_import_toggled)
	column.add_child(_import_tree)
	add_child(_import_dialog)


func _preview_import(path: String) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		main.set_status(Widgets.tf("import_unreadable", [path]), "bad")
		return
	_plan = CsvIo.plan_import(main.db, text)
	if not String(_plan["error"]).is_empty():
		main.set_status(Widgets.t("import_error_" + _plan["error"]), "bad")
		return
	if _plan["changes"].is_empty():
		main.set_status(Widgets.t("import_no_changes"), "")
		return
	_import_tree.clear()
	var root: TreeItem = _import_tree.create_item()
	var mono: Font = Tokens.font(&"mono")
	for index in _plan["changes"].size():
		var change: Dictionary = _plan["changes"][index]
		var item: TreeItem = _import_tree.create_item(root)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_editable(0, true)
		item.set_checked(0, change["apply"])
		item.set_metadata(0, index)
		item.set_text(1, Widgets.t("import_kind_" + change["kind"]))
		var kind_color: Color = Tokens.color("bad") if change["kind"] == CsvIo.CONFLICT else (Tokens.color("info") if change["kind"] == CsvIo.ADD else Tokens.color("sand"))
		item.set_custom_color(1, kind_color)
		var where: String = change["key"]
		if not String(change["language"]).is_empty():
			where += "  ·  " + change["language"]
		elif not String(change["field"]).is_empty():
			where += "  ·  " + Widgets.t("field_" + change["field"])
		item.set_text(2, where)
		item.set_custom_font(2, mono)
		item.set_text(3, String(change["old"]).replace("\n", " ⏎ "))
		item.set_custom_color(3, Tokens.color("sand_dim"))
		item.set_text(4, String(change["new"]).replace("\n", " ⏎ "))
		item.set_tooltip_text(4, change["new"])
		if change["kind"] == CsvIo.CONFLICT:
			item.set_tooltip_text(1, Widgets.t("import_conflict_tip"))
	var lines: PackedStringArray = PackedStringArray([Widgets.tf("import_summary", [_count(CsvIo.UPDATE), _count(CsvIo.ADD), _count(CsvIo.CONFLICT)])])
	for warning in _plan["warnings"]:
		lines.append("• " + Widgets.tf("import_warning_" + warning["code"], warning["args"]))
	_import_warnings.text = "\n".join(lines)
	_update_apply_button()
	_import_dialog.popup_centered()


func _count(kind: String) -> int:
	var total: int = 0
	for change in _plan["changes"]:
		if change["kind"] == kind:
			total += 1
	return total


func _on_import_toggled() -> void:
	var item: TreeItem = _import_tree.get_edited()
	_plan["changes"][item.get_metadata(0)]["apply"] = item.is_checked(0)
	_update_apply_button()


func _update_apply_button() -> void:
	var selected: int = 0
	for change in _plan["changes"]:
		if change["apply"]:
			selected += 1
	_import_dialog.get_ok_button().text = Widgets.tf("import_apply", [selected])
	_import_dialog.get_ok_button().disabled = selected == 0


func _apply_import() -> void:
	var db: TextDb = main.db
	var keys: PackedStringArray = PackedStringArray()
	for change in _plan["changes"]:
		if change["apply"] and not keys.has(change["key"]):
			keys.append(change["key"])
	var applied: Array = [0]
	main.edit(Widgets.t("action_import"), keys, func() -> void: applied[0] = CsvIo.apply_import(db, _plan["changes"]))
	main.set_status(Widgets.tf("import_applied", [applied[0]]), "good")


# --- Jeu ---

func _export_game() -> void:
	var db: TextDb = main.db
	main.save_now()
	var result: Dictionary = Exporter.export_all(db, "", {"fallback_to_source": _fallback.button_pressed})
	if main.editor_interface != null:
		main.editor_interface.get_resource_filesystem().scan()
	if result["ok"]:
		_export_result.text = Widgets.tf("export_game_done", [result["files"].size(), Exporter.export_dir(db)])
		main.set_status(Widgets.tf("export_game_done", [result["files"].size(), Exporter.export_dir(db)]), "good")
	else:
		main.set_status(Widgets.tf("error_save", [Exporter.export_dir(db)]), "bad")


func _register() -> void:
	if Exporter.register_translations(main.db):
		ProjectSettings.save()
		main.set_status(Widgets.t("registered"), "good")
	else:
		main.set_status(Widgets.t("already_registered"), "")
