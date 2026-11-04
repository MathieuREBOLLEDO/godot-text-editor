@tool
extends VBoxContainer

## Traduction : file des textes d'une langue (à faire, manquants, à revoir,
## tous), texte source à gauche, traduction à droite, contexte et
## description, longueur et tokens vérifiés à la frappe, statut, historique
## des versions avec comparaison mot à mot. Ctrl+Entrée enregistre et passe
## au suivant.

const Tokens = preload("text_theme.gd")
const Widgets = preload("widgets.gd")
const TextDb = preload("../core/text_db.gd")
const TextDiff = preload("../core/text_diff.gd")
const TextTokens = preload("../runtime/text_tokens.gd")
const Validator = preload("../core/validator.gd")

var main: Control

var _language: OptionButton
var _queue_filter: OptionButton
var _search: LineEdit
var _progress: Label
var _list: ItemList
var _work: VBoxContainer
var _empty: Control
var _key_label: Label
var _where: Label
var _description: PanelContainer
var _description_text: Label
var _source_title: Label
var _source: TextEdit
var _target_title: Label
var _target: TextEdit
var _checks: Label
var _status: OptionButton
var _source_change: PanelContainer
var _source_diff: RichTextLabel
var _history: ItemList
var _history_diff: RichTextLabel
var _restore: Button

var _keys: PackedStringArray = PackedStringArray()
var _key: String = ""


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	var bar: Array = Widgets.toolbar()
	add_child(bar[0])
	var row: HBoxContainer = bar[1]
	_language = Widgets.option([], "target_language_tip")
	_language.item_selected.connect(func(_index: int) -> void: _fill_queue())
	row.add_child(_language)
	_queue_filter = Widgets.option([[Widgets.t("queue_todo"), "todo"], [Widgets.t("status_missing"), TextDb.MISSING],
		[Widgets.t("status_needs_review"), TextDb.NEEDS_REVIEW], [Widgets.t("queue_all"), "all"]], "queue_tip")
	_queue_filter.item_selected.connect(func(_index: int) -> void: _fill_queue())
	row.add_child(_queue_filter)
	_search = Widgets.line_edit("filter_texts")
	_search.custom_minimum_size.x = 180
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void: _fill_queue())
	row.add_child(_search)
	row.add_child(Widgets.spacer())
	_progress = Widgets.label("", Tokens.MONO)
	row.add_child(_progress)

	var body: HSplitContainer = HSplitContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(body)
	var side: PanelContainer = Tokens.band(Vector4(0, 0, 1, 0), Vector4(8, 8, 8, 8))
	side.custom_minimum_size.x = 260
	body.add_child(side)
	_list = ItemList.new()
	_list.size_flags_vertical = SIZE_EXPAND_FILL
	_list.add_theme_font_override("font", Tokens.font(&"mono"))
	_list.add_theme_font_size_override("font_size", Tokens.size("small"))
	_list.item_selected.connect(func(index: int) -> void: _open(_list.get_item_metadata(index)))
	side.add_child(_list)

	var right: Control = Control.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(right)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	for side_name in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side_name, 16)
	scroll.add_child(margin)
	_work = Widgets.vbox(10)
	margin.add_child(_work)
	_build_work()
	_empty = Widgets.empty_state("queue_empty_title", "queue_empty_text", "", Callable())
	right.add_child(_empty)


func _build_work() -> void:
	var head: HBoxContainer = Widgets.hbox(10)
	_work.add_child(head)
	_key_label = Widgets.label("", Tokens.TITLE)
	_key_label.add_theme_font_override("font", Tokens.font(&"mono"))
	head.add_child(_key_label)
	_where = Widgets.label("", Tokens.DIM)
	_where.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(_where)
	head.add_child(Widgets.tool_button(&"ItemList", "open_in_database", func() -> void: main.open_entry(_key)))
	_description = PanelContainer.new()
	_description.theme_type_variation = Tokens.BUBBLE
	_description_text = Widgets.label("", Tokens.DIM)
	_description_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.add_child(_description_text)
	_work.add_child(_description)
	_source_change = PanelContainer.new()
	_source_change.theme_type_variation = Tokens.BUBBLE
	var change_column: VBoxContainer = Widgets.vbox(4)
	_source_change.add_child(change_column)
	change_column.add_child(Widgets.label(Widgets.t("source_changed"), Tokens.KICKER))
	_source_diff = _rich()
	change_column.add_child(_source_diff)
	_work.add_child(_source_change)

	var columns: HBoxContainer = Widgets.hbox(12)
	_work.add_child(columns)
	var left: VBoxContainer = Widgets.vbox(4)
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	columns.add_child(left)
	_source_title = Widgets.label("", Tokens.KICKER)
	left.add_child(_source_title)
	_source = _area()
	_source.editable = false
	left.add_child(_source)
	var right: VBoxContainer = Widgets.vbox(4)
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	columns.add_child(right)
	_target_title = Widgets.label("", Tokens.KICKER)
	right.add_child(_target_title)
	_target = _area()
	_target.placeholder_text = Widgets.t("translation_placeholder")
	_target.text_changed.connect(_update_checks)
	_target.gui_input.connect(_on_target_input)
	right.add_child(_target)

	var actions: HBoxContainer = Widgets.hbox(8)
	_work.add_child(actions)
	_checks = Widgets.label("", Tokens.MONO)
	_checks.size_flags_horizontal = SIZE_EXPAND_FILL
	actions.add_child(_checks)
	var statuses: Array = []
	for status in [TextDb.TO_TRANSLATE, TextDb.TRANSLATED, TextDb.NEEDS_REVIEW, TextDb.APPROVED]:
		statuses.append([Widgets.status_text(status), status])
	_status = Widgets.option(statuses, "status_tip")
	actions.add_child(_status)
	actions.add_child(Widgets.tool_button(&"MoveUp", "previous_text", func() -> void: _step(-1)))
	actions.add_child(Widgets.button("save_next", &"", "save_next_tip", func() -> void: _save_and_next(), true))

	var history: Array = Widgets.card("history")
	_work.add_child(history[0])
	var history_row: HBoxContainer = Widgets.hbox(10)
	history[1].add_child(history_row)
	_history = ItemList.new()
	_history.custom_minimum_size = Vector2(240, 110)
	_history.item_selected.connect(_on_history_selected)
	history_row.add_child(_history)
	var compare: VBoxContainer = Widgets.vbox(6)
	compare.size_flags_horizontal = SIZE_EXPAND_FILL
	history_row.add_child(compare)
	var compare_tip: Label = Widgets.label(Widgets.t("compare_tip"), Tokens.DIM)
	compare_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	compare.add_child(compare_tip)
	_history_diff = _rich()
	compare.add_child(_history_diff)
	_restore = Widgets.button("restore_version", &"Reload", "restore_version_tip", _restore_version)
	_restore.size_flags_horizontal = SIZE_SHRINK_BEGIN
	compare.add_child(_restore)


func refresh() -> void:
	var db: TextDb = main.db
	var items: Array = []
	for language in db.target_languages():
		items.append([Widgets.language_name(language), language])
	Widgets.set_options(_language, items)
	_fill_queue()


## Ouvre une langue (et une entrée si [param key] n'est pas vide).
func select(key: String, language: String) -> void:
	refresh()
	Widgets.select_value(_language, language)
	_fill_queue()
	if not key.is_empty() and not _keys.has(key):
		Widgets.select_value(_queue_filter, "all")
		_search.text = ""
		_fill_queue()
	if not key.is_empty():
		_open(key)


func _language_code() -> String:
	var value: Variant = Widgets.selected_value(_language)
	return String(value) if value != null else ""


func _fill_queue() -> void:
	var db: TextDb = main.db
	var language: String = _language_code()
	_list.clear()
	_keys = PackedStringArray()
	if language.is_empty():
		_show_work(false)
		return
	var mode: String = Widgets.selected_value(_queue_filter)
	for key in db.query({"search": _search.text}):
		var status: String = db.status(key, language)
		var keep: bool = mode == "all" or status == mode \
				or (mode == "todo" and (status == TextDb.MISSING or status == TextDb.TO_TRANSLATE or status == TextDb.NEEDS_REVIEW))
		if keep and not db.text(key, db.source_language()).is_empty():
			_keys.append(key)
			var index: int = _list.add_item(key, Widgets.dot(Tokens.status_color(status)))
			_list.set_item_metadata(index, key)
			_list.set_item_tooltip(index, "%s\n%s" % [Widgets.status_text(status), db.text(key, db.source_language())])
	var stats: Dictionary = db.stats()["by_language"].get(language, {})
	_progress.text = Widgets.tf("progress", [roundi(stats.get("percent", 0.0)), _keys.size()])
	if _keys.has(_key):
		_open(_key)
	elif not _keys.is_empty():
		_open(_keys[0])
	else:
		_key = ""
		_show_work(false)


func _show_work(visible_now: bool) -> void:
	_work.get_parent().get_parent().visible = visible_now
	_empty.visible = not visible_now


func _open(key: String) -> void:
	var db: TextDb = main.db
	var language: String = _language_code()
	if not db.has_key(key) or language.is_empty():
		return
	_key = key
	_show_work(true)
	var index: int = _keys.find(key)
	if index >= 0:
		_list.select(index)
		_list.ensure_current_is_visible()
	var entry: Dictionary = db.get_entry(key)
	_key_label.text = key
	_where.text = "%s · %s" % [entry["category"], entry["context"]] if not String(entry["context"]).is_empty() else entry["category"]
	_description.visible = not String(entry["description"]).is_empty()
	_description_text.text = entry["description"]
	_source_title.text = Widgets.language_name(db.source_language())
	_target_title.text = Widgets.language_name(language)
	_source.text = db.text(key, db.source_language())
	_target.text = db.text(key, language)
	var status: String = db.status(key, language)
	Widgets.select_value(_status, status if status != TextDb.MISSING else TextDb.TO_TRANSLATE)
	# Source changée depuis la traduction : ce qui a changé.
	var source_history: Array = db.history(key, db.source_language())
	_source_change.visible = status == TextDb.NEEDS_REVIEW and not source_history.is_empty()
	if _source_change.visible:
		_source_diff.text = TextDiff.to_bbcode(TextDiff.diff(source_history[0]["text"], _source.text), Tokens.color("bad"), Tokens.color("good"))
	_history.clear()
	for version in db.history(key, language):
		var item: int = _history.add_item(String(version["text"]).left(40))
		_history.set_item_metadata(item, version["text"])
		_history.set_item_tooltip(item, "%s\n%s" % [version.get("date", ""), version["text"]])
	_history_diff.text = Widgets.t("history_empty") if _history.item_count == 0 else ""
	_restore.disabled = true
	_update_checks()


func _update_checks() -> void:
	var db: TextDb = main.db
	if _key.is_empty():
		return
	var parts: PackedStringArray = PackedStringArray()
	var bad: bool = false
	var limit: int = db.max_length(_key)
	var length: int = Validator.display_length(db, _target.text)
	parts.append(Widgets.tf("length", [length, limit]) if limit > 0 else Widgets.tf("length_free", [length]))
	bad = limit > 0 and length > limit
	var wanted: PackedStringArray = TextTokens.find(_source.text)
	var found: PackedStringArray = TextTokens.find(_target.text)
	var lost: PackedStringArray = PackedStringArray()
	for token in wanted:
		if not found.has(token):
			lost.append("{%s}" % token)
	if not lost.is_empty() and not _target.text.is_empty():
		parts.append(Widgets.tf("tokens_missing", [", ".join(lost)]))
		bad = true
	elif not wanted.is_empty():
		parts.append(Widgets.t("tokens_ok"))
	_checks.text = "  ·  ".join(parts)
	_checks.add_theme_color_override("font_color", Tokens.color("bad") if bad else Tokens.color("sand_dim"))


func _on_target_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and event.ctrl_pressed:
		_save_and_next()
		_target.accept_event()


func _save_and_next() -> void:
	_save()
	_step(1)
	_target.grab_focus()


func _save() -> void:
	var db: TextDb = main.db
	var key: String = _key
	var language: String = _language_code()
	if key.is_empty():
		return
	var value: String = _target.text
	var status: String = Widgets.selected_value(_status)
	# Texte saisi alors que le statut dit « à traduire » : traduit.
	if status == TextDb.TO_TRANSLATE and not value.is_empty() and value != db.text(key, language):
		status = TextDb.TRANSLATED
	if status == TextDb.NEEDS_REVIEW and value != db.text(key, language):
		status = TextDb.TRANSLATED
	main.edit(Widgets.t("action_translate"), PackedStringArray([key]), func() -> void:
		db.set_translation(key, language, value, status if not value.is_empty() else ""))
	main.set_status(Widgets.tf("translation_saved", [key, language]), "good")


func _step(delta: int) -> void:
	var previous: String = _key
	var position: int = _keys.find(previous)
	_fill_queue()
	if _keys.is_empty():
		return
	# Le texte enregistré peut avoir quitté la file : on garde la place.
	var index: int = _keys.find(previous)
	if index < 0:
		index = clampi(position, 0, _keys.size() - 1)
	else:
		index = clampi(index + delta, 0, _keys.size() - 1)
	_open(_keys[index])


func _on_history_selected(index: int) -> void:
	var old: String = _history.get_item_metadata(index)
	_history_diff.text = TextDiff.to_bbcode(TextDiff.diff(old, _target.text), Tokens.color("bad"), Tokens.color("good"))
	_restore.disabled = false


func _restore_version() -> void:
	var selected: PackedInt32Array = _history.get_selected_items()
	if selected.is_empty():
		return
	_target.text = _history.get_item_metadata(selected[0])
	_update_checks()
	_save()
	_open(_key)


func _area() -> TextEdit:
	var area: TextEdit = TextEdit.new()
	area.custom_minimum_size.y = 120
	area.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	area.add_theme_font_size_override("font_size", Tokens.size("text") + 1)
	return area


func _rich() -> RichTextLabel:
	var rich: RichTextLabel = RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.selection_enabled = true
	return rich
