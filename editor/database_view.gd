@tool
extends VBoxContainer

## Base de textes : tableau paginé (une ligne par clé, une colonne par
## langue), recherche, filtres (catégorie, statut, langue, tag), tri par
## colonne, cellules modifiables, sélection multiple pour les modifications
## groupées, et à droite l'inspecteur de l'entrée choisie (clé, catégorie,
## contexte, description, tags, limite, texte de chaque langue).

const Tokens = preload("text_theme.gd")
const Widgets = preload("widgets.gd")
const TextDb = preload("../core/text_db.gd")

## Lignes par page (le Tree reste fluide avec des milliers d'entrées).
const PAGE_SIZE: int = 200
const FIXED_COLUMNS: int = 3

var main: Control

var _search: LineEdit
var _category: OptionButton
var _status: OptionButton
var _language: OptionButton
var _tag: OptionButton
var _bulk: MenuButton
var _tree: Tree
var _pager: Label
var _previous: Button
var _next: Button
var _inspector: VBoxContainer
var _inspector_scroll: ScrollContainer
var _empty: Control
var _table: Control
var _delete_dialog: ConfirmationDialog
var _tag_dialog: ConfirmationDialog
var _tag_edit: LineEdit

var _keys: PackedStringArray = PackedStringArray()
var _page: int = 0
var _sort: String = "key"
var _descending: bool = false
var _filling: bool = false
var _selected: String = ""


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	var bar: Array = Widgets.toolbar()
	add_child(bar[0])
	var actions: HBoxContainer = bar[1]
	# Filtres à gauche, qui passent à la ligne si l'onglet est étroit ;
	# actions à droite.
	var row: HFlowContainer = HFlowContainer.new()
	row.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 4)
	actions.add_child(row)
	_search = Widgets.line_edit("filter_texts")
	_search.custom_minimum_size.x = 170
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void: _apply_filter())
	row.add_child(_search)
	_category = Widgets.option([], "filter_category_tip")
	_category.item_selected.connect(func(_index: int) -> void: _apply_filter())
	row.add_child(_category)
	_status = Widgets.option([], "filter_status_tip")
	_status.item_selected.connect(func(_index: int) -> void: _apply_filter())
	row.add_child(_status)
	_language = Widgets.option([], "filter_language_tip")
	_language.item_selected.connect(func(_index: int) -> void: _apply_filter())
	row.add_child(_language)
	_tag = Widgets.option([], "filter_tag_tip")
	_tag.item_selected.connect(func(_index: int) -> void: _apply_filter())
	row.add_child(_tag)
	_bulk = MenuButton.new()
	_bulk.text = Widgets.t("bulk")
	_bulk.tooltip_text = Widgets.t("bulk_tip")
	_bulk.flat = false
	_bulk.size_flags_vertical = SIZE_SHRINK_CENTER
	_bulk.about_to_popup.connect(_fill_bulk_menu)
	_bulk.get_popup().id_pressed.connect(_on_bulk)
	actions.add_child(_bulk)
	actions.add_child(Widgets.tool_button(&"Duplicate", "duplicate_tip", _duplicate))
	actions.add_child(Widgets.tool_button(&"Remove", "delete_tip", _ask_delete))
	actions.add_child(Widgets.button("add_text", &"Add", "add_text_tip", add_entry, true))

	var body: HSplitContainer = HSplitContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(body)
	var left: Control = Control.new()
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(left)
	_table = Widgets.vbox(0)
	_table.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	left.add_child(_table)
	_tree = Tree.new()
	_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.column_titles_visible = true
	_tree.select_mode = Tree.SELECT_MULTI
	_tree.allow_reselect = true
	_tree.item_edited.connect(_on_item_edited)
	_tree.multi_selected.connect(func(_item: TreeItem, _column: int, _selected_now: bool) -> void: _on_selection())
	_tree.item_selected.connect(_on_selection)
	_tree.column_title_clicked.connect(_on_title_clicked)
	_table.add_child(_tree)
	var pager: PanelContainer = Tokens.band(Vector4(0, 1, 0, 0), Vector4(10, 4, 10, 4))
	_table.add_child(pager)
	var pager_row: HBoxContainer = Widgets.hbox(6)
	pager.add_child(pager_row)
	_pager = Widgets.label("", Tokens.MONO)
	_pager.size_flags_horizontal = SIZE_EXPAND_FILL
	pager_row.add_child(_pager)
	_previous = Widgets.tool_button(&"PagePrevious", "page_previous", func() -> void: _turn(-1))
	pager_row.add_child(_previous)
	_next = Widgets.tool_button(&"PageNext", "page_next", func() -> void: _turn(1))
	pager_row.add_child(_next)
	_empty = Widgets.empty_state("empty_db_title", "empty_db_text", "add_first_text", add_entry)
	left.add_child(_empty)

	var side: PanelContainer = Tokens.band(Vector4(1, 0, 0, 0), Vector4(12, 10, 12, 10))
	side.custom_minimum_size.x = 280
	body.add_child(side)
	_inspector_scroll = ScrollContainer.new()
	_inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(_inspector_scroll)
	_inspector = Widgets.vbox(6)
	_inspector.size_flags_horizontal = SIZE_EXPAND_FILL
	_inspector_scroll.add_child(_inspector)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.confirmed.connect(_delete_selected)
	add_child(_delete_dialog)
	_tag_dialog = ConfirmationDialog.new()
	_tag_dialog.title = Widgets.t("add_tag")
	_tag_edit = Widgets.line_edit("tag_placeholder")
	_tag_dialog.add_child(_tag_edit)
	_tag_dialog.register_text_enter(_tag_edit)
	_tag_dialog.confirmed.connect(func() -> void: _bulk_tag(_tag_edit.text))
	add_child(_tag_dialog)


func refresh() -> void:
	var db: TextDb = main.db
	var categories: Array = [[Widgets.t("all_categories"), ""]]
	for category in db.categories():
		categories.append([category, category])
	Widgets.set_options(_category, categories)
	var statuses: Array = [[Widgets.t("all_statuses"), ""]]
	for status in TextDb.STATUSES:
		statuses.append([Widgets.status_text(status), status])
	Widgets.set_options(_status, statuses)
	var languages: Array = [[Widgets.t("any_language"), ""]]
	for language in db.languages():
		languages.append([Widgets.language_name(language), language])
	Widgets.set_options(_language, languages)
	var tags: Array = [[Widgets.t("all_tags"), ""]]
	for tag in db.tags():
		tags.append([tag, tag])
	Widgets.set_options(_tag, tags)
	_apply_filter()


## Recherche venue de l'en-tête (Ctrl+F, Entrée).
func search(text: String) -> void:
	_search.text = text
	_apply_filter()


## Montre et choisit une entrée (filtres levés si elle n'y passe pas).
func select(key: String) -> void:
	if not main.db.has_key(key):
		return
	if not _keys.has(key):
		_search.text = ""
		for option_button in [_category, _status, _language, _tag]:
			option_button.select(0)
		_apply_filter()
	_page = _keys.find(key) / PAGE_SIZE
	_fill_tree()
	for item in _tree.get_root().get_children():
		if item.get_metadata(0) == key:
			_tree.deselect_all()
			item.select(0)
			_tree.scroll_to_item(item)
			break
	_selected = key
	_fill_inspector()


## Nouvelle entrée (catégorie du filtre), choisie, sa clé prête à renommer.
func add_entry() -> void:
	var db: TextDb = main.db
	var category: String = Widgets.selected_value(_category) if _category.item_count > 0 else ""
	if category.is_empty():
		category = "ui"
	var key: String = db.unique_key(category.to_upper() + "_NEW")
	main.edit(Widgets.t("action_add"), PackedStringArray([key]), func() -> void: db.add_entry(key, category))
	refresh()
	select(key)
	var key_edit: LineEdit = _inspector.find_child("KeyEdit", true, false)
	if key_edit != null:
		key_edit.grab_focus()
		key_edit.select_all()


func _filter() -> Dictionary:
	return {"search": _search.text, "category": Widgets.selected_value(_category), "status": Widgets.selected_value(_status),
		"language": Widgets.selected_value(_language), "tag": Widgets.selected_value(_tag), "sort": _sort, "descending": _descending}


func _apply_filter() -> void:
	if _category.item_count == 0:
		return
	_keys = main.db.query(_filter())
	_page = clampi(_page, 0, maxi(0, (_keys.size() - 1) / PAGE_SIZE))
	_fill_tree()


func _turn(delta: int) -> void:
	_page = clampi(_page + delta, 0, maxi(0, (_keys.size() - 1) / PAGE_SIZE))
	_fill_tree()


func _fill_tree() -> void:
	var db: TextDb = main.db
	_empty.visible = db.entries.is_empty()
	_table.visible = not _empty.visible
	_filling = true
	_tree.clear()
	var languages: PackedStringArray = db.languages()
	_tree.columns = FIXED_COLUMNS + languages.size() + 1
	var titles: Array = [Widgets.t("column_key"), Widgets.t("column_category"), Widgets.t("column_context")]
	for language in languages:
		titles.append(language.to_upper())
	titles.append(Widgets.t("column_status"))
	for column in titles.size():
		var sort_name: String = _column_sort(column, languages)
		var arrow: String = (" ↓" if _descending else " ↑") if sort_name == _sort else ""
		_tree.set_column_title(column, titles[column] + arrow)
		_tree.set_column_title_alignment(column, HORIZONTAL_ALIGNMENT_LEFT)
		_tree.set_column_expand(column, column >= FIXED_COLUMNS and column < FIXED_COLUMNS + languages.size())
		_tree.set_column_clip_content(column, true)
	_tree.set_column_custom_minimum_width(0, 170)
	_tree.set_column_custom_minimum_width(1, 80)
	_tree.set_column_custom_minimum_width(2, 90)
	_tree.set_column_custom_minimum_width(titles.size() - 1, 104)
	for offset in languages.size():
		_tree.set_column_custom_minimum_width(FIXED_COLUMNS + offset, 80)
	var root: TreeItem = _tree.create_item()
	var first: int = _page * PAGE_SIZE
	var mono: Font = Tokens.font(&"mono")
	for index in range(first, mini(first + PAGE_SIZE, _keys.size())):
		var key: String = _keys[index]
		var entry: Dictionary = db.get_entry(key)
		var item: TreeItem = _tree.create_item(root)
		item.set_metadata(0, key)
		item.set_text(0, key)
		item.set_custom_font(0, mono)
		item.set_custom_font_size(0, Tokens.size("small"))
		item.set_text(1, entry["category"])
		item.set_text(2, entry["context"])
		item.set_editable(2, true)
		for offset in languages.size():
			var language: String = languages[offset]
			var value: String = db.text(key, language)
			var column: int = FIXED_COLUMNS + offset
			item.set_text(column, value.replace("\n", " ⏎ "))
			# Texte sur plusieurs lignes : il se modifie dans l'inspecteur.
			item.set_editable(column, not value.contains("\n"))
			item.set_tooltip_text(column, "%s · %s\n%s" % [language, Widgets.status_text(db.status(key, language)), value])
			var current: String = db.status(key, language)
			if current == TextDb.MISSING or current == TextDb.NEEDS_REVIEW:
				item.set_icon(column, Widgets.dot(Tokens.status_color(current), 8))
		var status: String = db.entry_status(key)
		item.set_text(titles.size() - 1, Widgets.status_text(status))
		item.set_icon(titles.size() - 1, Widgets.dot(Tokens.status_color(status)))
		item.set_custom_color(titles.size() - 1, Tokens.status_color(status))
		if key == _selected:
			item.select(0)
	_filling = false
	var last: int = mini(first + PAGE_SIZE, _keys.size())
	_pager.text = Widgets.tf("pager", [first + 1 if not _keys.is_empty() else 0, last, _keys.size(), db.entries.size()])
	_previous.disabled = _page == 0
	_next.disabled = last >= _keys.size()
	_fill_inspector()


func _column_sort(column: int, languages: PackedStringArray) -> String:
	if column == 0:
		return "key"
	if column == 1:
		return "category"
	if column >= FIXED_COLUMNS and column < FIXED_COLUMNS + languages.size():
		return languages[column - FIXED_COLUMNS]
	if column == FIXED_COLUMNS + languages.size():
		return "status"
	return ""


func _on_title_clicked(column: int, _mouse_button: int) -> void:
	var sort_name: String = _column_sort(column, main.db.languages())
	if sort_name.is_empty():
		return
	_descending = not _descending if sort_name == _sort else false
	_sort = sort_name
	_apply_filter()


func _on_item_edited() -> void:
	if _filling:
		return
	var item: TreeItem = _tree.get_edited()
	var column: int = _tree.get_edited_column()
	var key: String = item.get_metadata(0)
	var value: String = item.get_text(column)
	var db: TextDb = main.db
	var languages: PackedStringArray = db.languages()
	if column == 2:
		main.edit(Widgets.t("action_edit"), PackedStringArray([key]), func() -> void: db.set_field(key, "context", value))
	elif column >= FIXED_COLUMNS and column < FIXED_COLUMNS + languages.size():
		var language: String = languages[column - FIXED_COLUMNS]
		main.edit(Widgets.t("action_edit"), PackedStringArray([key]), func() -> void: db.set_translation(key, language, value))
	_fill_tree.call_deferred()


func _selected_keys() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var item: TreeItem = _tree.get_next_selected(null)
	while item != null:
		result.append(item.get_metadata(0))
		item = _tree.get_next_selected(item)
	return result


func _on_selection() -> void:
	if _filling:
		return
	var keys: PackedStringArray = _selected_keys()
	_selected = keys[0] if keys.size() == 1 else ""
	_fill_inspector.call_deferred()


# --- Inspecteur ---

func _fill_inspector() -> void:
	for child in _inspector.get_children():
		child.queue_free()
	var db: TextDb = main.db
	var keys: PackedStringArray = _selected_keys()
	if keys.size() > 1:
		_inspector.add_child(Widgets.label(Widgets.t("inspector"), Tokens.KICKER))
		var many: Label = Widgets.label(Widgets.tf("selected_many", [keys.size()]), Tokens.TITLE)
		_inspector.add_child(many)
		var tip: Label = Widgets.label(Widgets.t("selected_many_tip"), Tokens.DIM)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_inspector.add_child(tip)
		return
	if _selected.is_empty() or not db.has_key(_selected):
		var hint: Label = Widgets.label(Widgets.t("inspector_empty"), Tokens.DIM)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_inspector.add_child(hint)
		return
	var key: String = _selected
	var entry: Dictionary = db.get_entry(key)
	_inspector.add_child(Widgets.label(Widgets.t("inspector"), Tokens.KICKER))
	var key_edit: LineEdit = Widgets.line_edit("", true)
	key_edit.name = "KeyEdit"
	key_edit.text = key
	key_edit.tooltip_text = Widgets.t("key_tip")
	key_edit.text_submitted.connect(func(new_key: String) -> void: _rename(key, new_key))
	key_edit.focus_exited.connect(func() -> void: _rename(key, key_edit.text))
	_inspector.add_child(key_edit)

	_inspector.add_child(_caption("column_category"))
	var category: OptionButton = OptionButton.new()
	var items: Array = []
	for name in db.categories():
		items.append([name, name])
	Widgets.set_options(category, items, entry["category"])
	category.item_selected.connect(func(_index: int) -> void:
		_set_field(key, "category", Widgets.selected_value(category)))
	_inspector.add_child(category)
	_inspector.add_child(_caption("column_context"))
	_inspector.add_child(_field_edit(key, "context", entry["context"]))
	_inspector.add_child(_caption("description"))
	var description: TextEdit = _text_area(entry["description"], 56)
	description.placeholder_text = Widgets.t("description_placeholder")
	description.focus_exited.connect(func() -> void: _set_field(key, "description", description.text))
	_inspector.add_child(description)
	var line: HBoxContainer = Widgets.hbox(8)
	_inspector.add_child(line)
	var tags_column: VBoxContainer = Widgets.vbox(4)
	tags_column.size_flags_horizontal = SIZE_EXPAND_FILL
	line.add_child(tags_column)
	tags_column.add_child(_caption("tags"))
	tags_column.add_child(_field_edit(key, "tags", ", ".join(PackedStringArray(entry["tags"]))))
	var limit_column: VBoxContainer = Widgets.vbox(4)
	line.add_child(limit_column)
	limit_column.add_child(_caption("max_length"))
	var limit: SpinBox = SpinBox.new()
	limit.max_value = 9999
	limit.value = int(entry["max_length"])
	limit.tooltip_text = Widgets.t("max_length_tip")
	limit.value_changed.connect(func(value: float) -> void: _set_field(key, "max_length", int(value)))
	limit_column.add_child(limit)

	for language in db.languages():
		var header: HBoxContainer = Widgets.hbox(6)
		_inspector.add_child(header)
		var status: String = db.status(key, language)
		var title: Label = Widgets.label(Widgets.language_name(language), Tokens.KICKER)
		title.size_flags_horizontal = SIZE_EXPAND_FILL
		header.add_child(title)
		var badge: Label = Widgets.label(Widgets.status_text(status), Tokens.DIM)
		badge.add_theme_color_override("font_color", Tokens.status_color(status))
		header.add_child(badge)
		var area: TextEdit = _text_area(db.text(key, language), 48)
		area.focus_exited.connect(func() -> void:
			main.edit(Widgets.t("action_edit"), PackedStringArray([key]), func() -> void: db.set_translation(key, language, area.text))
			_fill_tree.call_deferred())
		_inspector.add_child(area)
		var limit_value: int = db.max_length(key)
		if limit_value > 0:
			var count: Label = Widgets.label(Widgets.tf("length", [db.text(key, language).length(), limit_value]), Tokens.MONO)
			if db.text(key, language).length() > limit_value:
				count.add_theme_color_override("font_color", Tokens.color("bad"))
			_inspector.add_child(count)
	var actions: HBoxContainer = Widgets.hbox(6)
	_inspector.add_child(actions)
	actions.add_child(Widgets.button("translate", &"Translation", "translate_tip", func() -> void:
		var target: String = db.target_languages()[0] if not db.target_languages().is_empty() else ""
		main.open_entry(key, target)))
	actions.add_child(Widgets.label(Widgets.tf("modified", [entry["modified"]]), Tokens.DIM))


func _caption(key: String) -> Label:
	return Widgets.label(Widgets.t(key), Tokens.DIM)


func _field_edit(key: String, field: String, value: String) -> LineEdit:
	var edit: LineEdit = LineEdit.new()
	edit.text = value
	edit.text_submitted.connect(func(text: String) -> void: _set_field(key, field, text))
	edit.focus_exited.connect(func() -> void: _set_field(key, field, edit.text))
	return edit


func _text_area(value: String, height: int) -> TextEdit:
	var area: TextEdit = TextEdit.new()
	area.text = value
	area.custom_minimum_size.y = height
	area.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	area.scroll_fit_content_height = true
	return area


func _set_field(key: String, field: String, value: Variant) -> void:
	var db: TextDb = main.db
	if not db.has_key(key):
		return
	var before: Variant = db.get_entry(key).get(field)
	main.edit(Widgets.t("action_edit"), PackedStringArray([key]), func() -> void: db.set_field(key, field, value))
	if db.get_entry(key).get(field) != before:
		_apply_filter.call_deferred()


func _rename(key: String, new_key: String) -> void:
	new_key = new_key.strip_edges()
	var db: TextDb = main.db
	if new_key == key or not db.has_key(key):
		return
	if not db.is_valid_key(new_key) or db.has_key(new_key):
		main.set_status(Widgets.tf("invalid_key", [new_key]), "bad")
		return
	# Renommer touche aussi les dialogues : pas dans l'historique d'annulation.
	db.rename_key(key, new_key)
	_selected = new_key
	main.set_status(Widgets.tf("renamed", [key, new_key]), "good")
	_apply_filter.call_deferred()


# --- Actions ---

func _duplicate() -> void:
	var db: TextDb = main.db
	if _selected.is_empty():
		return
	var key: String = db.unique_key(_selected + "_COPY")
	var source: String = _selected
	main.edit(Widgets.t("action_duplicate"), PackedStringArray([key]), func() -> void: db.duplicate_entry(source, key))
	_apply_filter()
	select(key)


func _ask_delete() -> void:
	var keys: PackedStringArray = _selected_keys()
	if keys.is_empty():
		return
	_delete_dialog.dialog_text = Widgets.tf("delete_confirm", [keys.size(), ", ".join(keys.slice(0, 5)) + ("…" if keys.size() > 5 else "")])
	_delete_dialog.popup_centered()


func _delete_selected() -> void:
	var db: TextDb = main.db
	var keys: PackedStringArray = _selected_keys()
	main.edit(Widgets.t("action_delete"), keys, func() -> void:
		for key in keys:
			db.remove_entry(key))
	_selected = ""
	main.set_status(Widgets.tf("deleted", [keys.size()]), "")
	_apply_filter()


const BULK_CATEGORY: int = 1000
const BULK_STATUS: int = 2000
const BULK_TAG: int = 3000
const BULK_DELETE: int = 3001


func _fill_bulk_menu() -> void:
	var popup: PopupMenu = _bulk.get_popup()
	popup.clear(true)
	var count: int = _selected_keys().size()
	popup.add_separator(Widgets.tf("selected_many", [count]))
	var categories: PopupMenu = PopupMenu.new()
	categories.name = "Categories"
	var names: PackedStringArray = main.db.categories()
	for index in names.size():
		categories.add_item(names[index], BULK_CATEGORY + index)
	categories.id_pressed.connect(_on_bulk)
	popup.add_child(categories)
	popup.add_submenu_node_item(Widgets.t("bulk_category"), categories)
	var statuses: PopupMenu = PopupMenu.new()
	statuses.name = "Statuses"
	for index in TextDb.STATUSES.size():
		statuses.add_item(Widgets.status_text(TextDb.STATUSES[index]), BULK_STATUS + index)
	statuses.id_pressed.connect(_on_bulk)
	popup.add_child(statuses)
	var language: String = Widgets.selected_value(_language)
	popup.add_submenu_node_item(Widgets.tf("bulk_status", [language if not language.is_empty() else Widgets.t("all_targets")]), statuses)
	popup.add_item(Widgets.t("add_tag"), BULK_TAG)
	popup.add_separator()
	popup.add_item(Widgets.t("delete_selected"), BULK_DELETE)
	for index in popup.item_count:
		popup.set_item_disabled(index, count == 0 and not popup.is_item_separator(index))


func _on_bulk(id: int) -> void:
	var db: TextDb = main.db
	var keys: PackedStringArray = _selected_keys()
	if keys.is_empty():
		return
	if id >= BULK_STATUS and id < BULK_STATUS + TextDb.STATUSES.size():
		var status: String = TextDb.STATUSES[id - BULK_STATUS]
		var language: String = Widgets.selected_value(_language)
		var languages: PackedStringArray = PackedStringArray([language]) if not language.is_empty() else db.target_languages()
		main.edit(Widgets.t("action_bulk"), keys, func() -> void:
			for key in keys:
				for code in languages:
					db.set_status(key, code, status))
	elif id >= BULK_CATEGORY and id < BULK_STATUS:
		var category: String = db.categories()[id - BULK_CATEGORY]
		main.edit(Widgets.t("action_bulk"), keys, func() -> void:
			for key in keys:
				db.set_field(key, "category", category))
	elif id == BULK_TAG:
		_tag_edit.text = ""
		_tag_dialog.popup_centered(Vector2i(320, 80))
		_tag_edit.grab_focus()
		return
	elif id == BULK_DELETE:
		_ask_delete()
		return
	main.set_status(Widgets.tf("bulk_done", [keys.size()]), "good")
	_apply_filter()


func _bulk_tag(tag: String) -> void:
	var db: TextDb = main.db
	var keys: PackedStringArray = _selected_keys()
	if tag.strip_edges().is_empty():
		return
	main.edit(Widgets.t("action_bulk"), keys, func() -> void:
		for key in keys:
			db.set_field(key, "tags", db.get_entry(key)["tags"] + [tag]))
	refresh()
