@tool
extends ScrollContainer

## Réglages du projet de textes (project.json) : langue source et langues,
## catégories, plateformes, tokens (valeur par plateforme), limites de
## caractères (par catégorie et plateforme), personnages des dialogues
## (nom, couleur, portrait), dossiers, police vérifiée par la QA.

const Tokens = preload("text_theme.gd")
const Widgets = preload("widgets.gd")
const TextDb = preload("../core/text_db.gd")

var main: Control

var _column: VBoxContainer


func _ready() -> void:
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	_column = Widgets.vbox(14)
	_column.size_flags_horizontal = SIZE_EXPAND_FILL
	margin.add_child(_column)


func refresh() -> void:
	for child in _column.get_children():
		child.queue_free()
	var db: TextDb = main.db
	var top: HBoxContainer = Widgets.hbox(14)
	_column.add_child(top)
	top.add_child(_languages_card(db))
	top.add_child(_files_card(db))
	var lists: HBoxContainer = Widgets.hbox(14)
	_column.add_child(lists)
	lists.add_child(_chips_card("categories", db.categories(), func(value: String) -> void:
		var list: Array = db.project.get("categories", []).duplicate()
		list.append(value.to_lower())
		db.set_project_value("categories", list), func(value: String) -> void:
		var list: Array = db.project.get("categories", []).duplicate()
		list.erase(value)
		db.set_project_value("categories", list)))
	lists.add_child(_chips_card("platforms", PackedStringArray(db.project.get("platforms", [])), func(value: String) -> void:
		var list: Array = db.project.get("platforms", []).duplicate()
		list.append(value.to_snake_case())
		db.set_project_value("platforms", list), func(value: String) -> void:
		var list: Array = db.project.get("platforms", []).duplicate()
		list.erase(value)
		db.set_project_value("platforms", list)))
	_column.add_child(_tokens_card(db))
	_column.add_child(_limits_card(db))
	_column.add_child(_characters_card(db))


func _changed() -> void:
	refresh.call_deferred()


func _languages_card(db: TextDb) -> Control:
	var card: Array = Widgets.card("languages")
	card[0].size_flags_horizontal = SIZE_EXPAND_FILL
	var body: VBoxContainer = card[1]
	var source_items: Array = []
	for language in db.languages():
		source_items.append([Widgets.language_name(language), language])
	var source: OptionButton = Widgets.option(source_items, "source_language_tip")
	Widgets.select_value(source, db.source_language())
	source.item_selected.connect(func(_index: int) -> void:
		db.set_project_value("source_language", Widgets.selected_value(source))
		main.set_status(Widgets.t("source_language_changed"), "")
		_changed())
	body.add_child(_row("source_language", source))
	var chips: HFlowContainer = HFlowContainer.new()
	for language in db.target_languages():
		chips.add_child(_chip(Widgets.language_name(language), func() -> void:
			db.remove_language(language)
			_changed()))
	body.add_child(chips)
	var add_row: HBoxContainer = Widgets.hbox(6)
	var code: LineEdit = Widgets.line_edit("language_code_placeholder", true)
	code.tooltip_text = Widgets.t("language_code_tip")
	code.size_flags_horizontal = SIZE_EXPAND_FILL
	var add: Callable = func() -> void:
		if not TranslationServer.get_all_languages().has(code.text.get_slice("_", 0)):
			main.set_status(Widgets.tf("unknown_language", [code.text]), "bad")
			return
		if db.add_language(code.text):
			_changed()
	code.text_submitted.connect(func(_text: String) -> void: add.call())
	add_row.add_child(code)
	add_row.add_child(Widgets.button("add", &"Add", "", add))
	body.add_child(add_row)
	var help: Label = Widgets.label(Widgets.t("languages_help"), Tokens.DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(help)
	return card[0]


func _files_card(db: TextDb) -> Control:
	var card: Array = Widgets.card("files")
	card[0].size_flags_horizontal = SIZE_EXPAND_FILL
	var body: VBoxContainer = card[1]
	var data_dir: LineEdit = Widgets.line_edit("", true)
	data_dir.text = main.data_dir()
	data_dir.tooltip_text = Widgets.t("data_dir_tip")
	data_dir.text_submitted.connect(func(text: String) -> void:
		ProjectSettings.set_setting(main.SETTING_DATA_DIR, text.strip_edges())
		ProjectSettings.set_initial_value(main.SETTING_DATA_DIR, main.DEFAULT_DATA_DIR)
		ProjectSettings.save()
		main.load_data()
		main.set_status(Widgets.tf("data_dir_changed", [text]), "good")
		_changed())
	body.add_child(_row("data_dir", data_dir))
	body.add_child(_row("export_dir", _project_field(db, "export_dir", "export_dir_tip")))
	body.add_child(_row("qa_font", _project_field(db, "font", "qa_font_tip")))
	var help: Label = Widgets.label(Widgets.t("files_help"), Tokens.DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(help)
	return card[0]


func _project_field(db: TextDb, name: String, tip: String) -> LineEdit:
	var edit: LineEdit = Widgets.line_edit("", true)
	edit.text = String(db.project.get(name, ""))
	edit.tooltip_text = Widgets.t(tip)
	edit.text_submitted.connect(func(text: String) -> void: db.set_project_value(name, text.strip_edges()))
	edit.focus_exited.connect(func() -> void:
		if edit.text.strip_edges() != String(db.project.get(name, "")):
			db.set_project_value(name, edit.text.strip_edges()))
	return edit


func _chips_card(title: String, values: PackedStringArray, add: Callable, remove: Callable) -> Control:
	var card: Array = Widgets.card(title)
	card[0].size_flags_horizontal = SIZE_EXPAND_FILL
	var chips: HFlowContainer = HFlowContainer.new()
	for value in values:
		chips.add_child(_chip(value, func() -> void:
			remove.call(value)
			_changed()))
	card[1].add_child(chips)
	var row: HBoxContainer = Widgets.hbox(6)
	var edit: LineEdit = Widgets.line_edit("new_value_placeholder", true)
	edit.size_flags_horizontal = SIZE_EXPAND_FILL
	var submit: Callable = func() -> void:
		var value: String = edit.text.strip_edges()
		if not value.is_empty() and not values.has(value):
			add.call(value)
			_changed()
	edit.text_submitted.connect(func(_text: String) -> void: submit.call())
	row.add_child(edit)
	row.add_child(Widgets.button("add", &"Add", "", submit))
	card[1].add_child(row)
	return card[0]


func _chip(text: String, remove: Callable) -> Button:
	var chip: Button = Button.new()
	chip.text = text
	chip.icon = Widgets.icon(&"Close")
	chip.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	chip.tooltip_text = Widgets.t("remove_tip")
	chip.pressed.connect(remove)
	return chip


func _row(key: String, control: Control) -> Control:
	var row: HBoxContainer = Widgets.hbox(8)
	var caption: Label = Widgets.label(Widgets.t(key), Tokens.DIM)
	caption.custom_minimum_size.x = 130
	row.add_child(caption)
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(control)
	return row


# --- Tableaux (tokens, limites, personnages) ---

## Tableau modifiable : [param columns] titres, [param rows] [[id, valeurs…]],
## [param on_edit](id, colonne, texte). La 1re colonne (id) n'est pas
## modifiable.
func _table(columns: Array, rows: Array, on_edit: Callable) -> Tree:
	var tree: Tree = Tree.new()
	tree.columns = columns.size()
	tree.hide_root = true
	tree.column_titles_visible = true
	tree.custom_minimum_size.y = clampi(34 + rows.size() * 28, 90, 320)
	for index in columns.size():
		tree.set_column_title(index, columns[index])
		tree.set_column_title_alignment(index, HORIZONTAL_ALIGNMENT_LEFT)
	var root: TreeItem = tree.create_item()
	var mono: Font = Tokens.font(&"mono")
	for row in rows:
		var item: TreeItem = tree.create_item(root)
		item.set_metadata(0, row[0])
		for index in row.size():
			item.set_text(index, str(row[index]))
			item.set_editable(index, index > 0)
		item.set_custom_font(0, mono)
	tree.item_edited.connect(func() -> void:
		var item: TreeItem = tree.get_edited()
		var column: int = tree.get_edited_column()
		on_edit.call(item.get_metadata(0), column, item.get_text(column).strip_edges()))
	return tree


func _add_row_line(placeholder: String, add: Callable) -> HBoxContainer:
	var row: HBoxContainer = Widgets.hbox(6)
	var edit: LineEdit = Widgets.line_edit(placeholder, true)
	edit.size_flags_horizontal = SIZE_EXPAND_FILL
	var submit: Callable = func() -> void:
		var value: String = edit.text.strip_edges()
		if not value.is_empty():
			add.call(value)
			_changed()
	edit.text_submitted.connect(func(_text: String) -> void: submit.call())
	row.add_child(edit)
	row.add_child(Widgets.button("add", &"Add", "", submit))
	return row


func _tokens_card(db: TextDb) -> Control:
	var card: Array = Widgets.card("tokens")
	card[1].add_child(_hint("tokens_help"))
	var platforms: Array = ["default"] + Array(db.project.get("platforms", []))
	var table: Dictionary = db.project.get("tokens", {})
	var rows: Array = []
	var names: Array = table.keys()
	names.sort()
	for name in names:
		var row: Array = ["{%s}" % name]
		for platform in platforms:
			row.append(str(table[name].get(platform, "")))
		rows.append(row)
	var tree: Tree = _table([Widgets.t("token")] + platforms, rows, func(id: String, column: int, text: String) -> void:
		var tokens: Dictionary = db.project.get("tokens", {}).duplicate(true)
		var name: String = id.trim_prefix("{").trim_suffix("}")
		if text.is_empty():
			tokens[name].erase(platforms[column - 1])
		else:
			tokens[name][platforms[column - 1]] = text
		db.set_project_value("tokens", tokens))
	card[1].add_child(tree)
	var actions: HBoxContainer = Widgets.hbox(6)
	actions.add_child(_add_row_line("token_placeholder", func(value: String) -> void:
		var name: String = value.trim_prefix("{").trim_suffix("}").to_upper().replace(" ", "_")
		var tokens: Dictionary = db.project.get("tokens", {}).duplicate(true)
		if not tokens.has(name):
			tokens[name] = {}
			db.set_project_value("tokens", tokens)))
	actions.get_child(0).size_flags_horizontal = SIZE_EXPAND_FILL
	actions.add_child(Widgets.button("remove_selected", &"Remove", "", func() -> void:
		var item: TreeItem = tree.get_selected()
		if item == null:
			return
		var tokens: Dictionary = db.project.get("tokens", {}).duplicate(true)
		tokens.erase(String(item.get_metadata(0)).trim_prefix("{").trim_suffix("}"))
		db.set_project_value("tokens", tokens)
		_changed()))
	card[1].add_child(actions)
	return card[0]


func _limits_card(db: TextDb) -> Control:
	var card: Array = Widgets.card("limits")
	card[1].add_child(_hint("limits_help"))
	var platforms: Array = Array(db.project.get("platforms", []))
	var limits: Dictionary = db.project.get("limits", {})
	var rows: Array = []
	for category in db.categories():
		var row: Array = [category, str(limits.get(category, "")) if int(limits.get(category, 0)) > 0 else ""]
		for platform in platforms:
			var name: String = "%s@%s" % [category, platform]
			row.append(str(limits[name]) if limits.has(name) and int(limits[name]) > 0 else "")
		rows.append(row)
	card[1].add_child(_table([Widgets.t("column_category"), Widgets.t("all_platforms")] + platforms, rows, func(id: String, column: int, text: String) -> void:
		var values: Dictionary = db.project.get("limits", {}).duplicate()
		var name: String = id if column == 1 else "%s@%s" % [id, platforms[column - 2]]
		if text.is_valid_int() and text.to_int() > 0:
			values[name] = text.to_int()
		else:
			values.erase(name)
		db.set_project_value("limits", values)))
	return card[0]


func _characters_card(db: TextDb) -> Control:
	var card: Array = Widgets.card("characters")
	card[1].add_child(_hint("characters_help"))
	var characters: Dictionary = db.project.get("characters", {})
	var rows: Array = []
	var ids: Array = characters.keys()
	ids.sort()
	for id in ids:
		rows.append([id, characters[id].get("name_key", ""), characters[id].get("color", ""), characters[id].get("portrait", "")])
	var fields: Array = ["", "name_key", "color", "portrait"]
	var tree: Tree = _table([Widgets.t("character_id"), Widgets.t("character_name_key"), Widgets.t("character_color"), Widgets.t("character_portrait")], rows,
		func(id: String, column: int, text: String) -> void:
			var list: Dictionary = db.project.get("characters", {}).duplicate(true)
			list[id][fields[column]] = text
			db.set_project_value("characters", list))
	for item in tree.get_root().get_children():
		var color: String = item.get_text(2)
		if Color.html_is_valid(color):
			item.set_icon(2, Widgets.dot(Color(color), 12))
	card[1].add_child(tree)
	var actions: HBoxContainer = Widgets.hbox(6)
	actions.add_child(_add_row_line("character_placeholder", func(value: String) -> void:
		var id: String = value.to_snake_case()
		var list: Dictionary = db.project.get("characters", {}).duplicate(true)
		if list.has(id):
			return
		var name_key: String = db.unique_key("CHAR_" + id.to_upper())
		main.edit(Widgets.t("action_add"), PackedStringArray([name_key]), func() -> void: db.add_entry(name_key, "dialogue", value))
		list[id] = {"name_key": name_key, "color": "#e0e0e0", "portrait": ""}
		db.set_project_value("characters", list)))
	actions.get_child(0).size_flags_horizontal = SIZE_EXPAND_FILL
	actions.add_child(Widgets.button("remove_selected", &"Remove", "", func() -> void:
		var item: TreeItem = tree.get_selected()
		if item == null:
			return
		var list: Dictionary = db.project.get("characters", {}).duplicate(true)
		list.erase(item.get_metadata(0))
		db.set_project_value("characters", list)
		_changed()))
	card[1].add_child(actions)
	return card[0]


func _hint(key: String) -> Control:
	var bubble: PanelContainer = PanelContainer.new()
	bubble.theme_type_variation = Tokens.BUBBLE
	var text: Label = Widgets.label(Widgets.t(key), Tokens.DIM)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.add_child(text)
	return bubble
