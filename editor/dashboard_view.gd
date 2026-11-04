@tool
extends VBoxContainer

## Tableau de bord : chiffres de la base (textes, dialogues, langues,
## erreurs), avancement par langue, et ce qui demande de l'attention, avec un
## accès direct à l'espace concerné.

const Tokens = preload("text_theme.gd")
const Widgets = preload("widgets.gd")
const Validator = preload("../core/validator.gd")
const TextDb = preload("../core/text_db.gd")

var main: Control

var _tiles: HBoxContainer
var _languages: VBoxContainer
var _attention: VBoxContainer
var _empty: Control
var _content: Control


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	scroll.add_child(margin)
	var column: VBoxContainer = Widgets.vbox(16)
	margin.add_child(column)
	_content = column
	_tiles = Widgets.hbox(12)
	column.add_child(_tiles)
	var row: HBoxContainer = Widgets.hbox(16)
	column.add_child(row)
	var progress: Array = Widgets.card("languages_progress")
	progress[0].size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(progress[0])
	_languages = progress[1]
	var attention: Array = Widgets.card("attention")
	attention[0].size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(attention[0])
	_attention = attention[1]
	_empty = Widgets.empty_state("empty_db_title", "empty_db_text", "add_first_text", func() -> void:
		main.show_view("database")
		main.view("database").add_entry())
	add_child(_empty)


func refresh() -> void:
	var db: TextDb = main.db
	_empty.visible = db.entries.is_empty() and db.dialogues.is_empty()
	_content.get_parent().get_parent().visible = not _empty.visible
	if _empty.visible:
		return
	var issues: Array = main.validate()
	var counts: Dictionary = Validator.counts(issues)
	var stats: Dictionary = db.stats()
	for child in _tiles.get_children():
		child.queue_free()
	_tile("tile_texts", str(stats["entries"]), "", func() -> void: main.show_view("database"))
	_tile("tile_dialogues", str(stats["dialogues"]), "", func() -> void: main.show_view("dialogues"))
	_tile("tile_languages", str(stats["languages"]), "", func() -> void: main.show_view("settings"))
	_tile("tile_errors", str(counts[Validator.ERROR]), "bad" if counts[Validator.ERROR] > 0 else "good", func() -> void: main.show_view("qa"))
	_tile("tile_warnings", str(counts[Validator.WARNING]), "", func() -> void: main.show_view("qa"))

	for child in _languages.get_children():
		if not (child is Label) or child.theme_type_variation != Tokens.KICKER:
			child.queue_free()
	for language in db.languages():
		var data: Dictionary = stats["by_language"][language]
		var line: HBoxContainer = Widgets.hbox(10)
		_languages.add_child(line)
		var name: Label = Widgets.label(Widgets.language_name(language) + ("  · " + Widgets.t("source") if language == db.source_language() else ""))
		name.custom_minimum_size.x = 150
		name.clip_text = true
		line.add_child(name)
		var bar: ProgressBar = ProgressBar.new()
		bar.value = data["percent"]
		bar.custom_minimum_size = Vector2(160, 18)
		bar.size_flags_horizontal = SIZE_EXPAND_FILL
		bar.size_flags_vertical = SIZE_SHRINK_CENTER
		line.add_child(bar)
		var detail: Label = Widgets.label(Widgets.tf("language_detail", [data[TextDb.MISSING], data[TextDb.NEEDS_REVIEW]]), Tokens.MONO)
		line.add_child(detail)
		if language != db.source_language():
			line.add_child(Widgets.tool_button(&"Translation", "translate_tip", func() -> void:
				main.show_view("localization")
				main.view("localization").select("", language)))

	for child in _attention.get_children():
		if not (child is Label) or child.theme_type_variation != Tokens.KICKER:
			child.queue_free()
	var by_code: Dictionary = {}
	for issue in issues:
		by_code[issue["code"]] = by_code.get(issue["code"], 0) + 1
	var codes: Array = by_code.keys()
	codes.sort_custom(func(a: String, b: String) -> bool: return by_code[a] > by_code[b])
	if codes.is_empty():
		_attention.add_child(Widgets.label(Widgets.t("nothing_to_fix"), Tokens.DIM))
	for code in codes.slice(0, 8):
		var severity: String = Validator.INFO
		for issue in issues:
			if issue["code"] == code:
				severity = issue["severity"]
				break
		var item: Button = Button.new()
		item.text = "%d  ·  %s" % [by_code[code], Widgets.t("issue_" + code + "_title")]
		item.icon = Widgets.dot(Tokens.severity_color(severity))
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item.clip_text = true
		item.custom_minimum_size.x = 180
		item.theme_type_variation = Tokens.TOOL
		item.tooltip_text = Widgets.t("issue_" + code + "_help")
		item.pressed.connect(func() -> void:
			main.show_view("qa")
			main.view("qa").filter_code(code))
		_attention.add_child(item)


func _tile(title_key: String, value: String, kind: String, callback: Callable) -> void:
	var card: Array = Widgets.card(title_key)
	card[0].size_flags_horizontal = SIZE_EXPAND_FILL
	card[0].mouse_filter = MOUSE_FILTER_STOP
	card[0].mouse_default_cursor_shape = CURSOR_POINTING_HAND
	card[0].gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			callback.call())
	var number: Label = Widgets.label(value, Tokens.TITLE)
	number.add_theme_font_size_override("font_size", Tokens.size("title") * 2)
	number.add_theme_font_override("font", Tokens.font(&"mono"))
	if not kind.is_empty():
		number.add_theme_color_override("font_color", Tokens.color(kind))
	card[1].add_child(number)
	_tiles.add_child(card[0])
	# Apparition en cascade, discrète.
	card[0].modulate.a = 0.0
	var tween: Tween = card[0].create_tween()
	tween.tween_interval(0.04 * _tiles.get_child_count())
	tween.tween_property(card[0], "modulate:a", 1.0, 0.18)
