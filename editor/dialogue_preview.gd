@tool
extends HSplitContainer

## Prévisualisation d'un dialogue comme en jeu : boîte de dialogue (portrait,
## nom en couleur du personnage, texte, choix cliquables), jouée par le même
## lecteur que le jeu (DialogueRunner). À gauche : langue, plateforme (valeur
## des tokens), conditions et variables à tester, taille de la boîte ; la
## mise en forme est rangée dans project.json (« preview »).

const Tokens = preload("text_theme.gd")
const Widgets = preload("widgets.gd")
const DialogueData = preload("../core/dialogue_data.gd")
const TextTokens = preload("../runtime/text_tokens.gd")
const Runner = preload("../runtime/dialogue_runner.gd")

const DEFAULT_STYLE: Dictionary = {"box_width": 640, "font_size": 18, "box_color": "#11151b", "text_color": "#f2f2f2"}

## La vue Dialogues (dialogue_view.gd).
var view: Control

var _language: OptionButton
var _platform: OptionButton
var _conditions: VBoxContainer
var _variables: TextEdit
var _width: SpinBox
var _font_size: SpinBox
var _screen: Control
var _box: PanelContainer
var _portrait: TextureRect
var _name: Label
var _text: RichTextLabel
var _choices: VBoxContainer
var _next: Button
var _warning: Label
var _log: Label
var _runner: Runner
var _checked: Dictionary = {}
var _layout: VBoxContainer


func _ready() -> void:
	var side: PanelContainer = Tokens.band(Vector4(0, 0, 1, 0), Vector4(12, 10, 12, 10))
	side.custom_minimum_size.x = 250
	add_child(side)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var column: VBoxContainer = Widgets.vbox(6)
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(column)
	column.add_child(Widgets.label(Widgets.t("preview_settings"), Tokens.KICKER))
	_language = Widgets.option([], "preview_language_tip")
	_language.item_selected.connect(func(_index: int) -> void: restart())
	column.add_child(_language)
	_platform = Widgets.option([], "preview_platform_tip")
	_platform.item_selected.connect(func(_index: int) -> void: restart())
	column.add_child(_platform)
	column.add_child(Widgets.label(Widgets.t("preview_conditions"), Tokens.KICKER))
	_conditions = Widgets.vbox(2)
	column.add_child(_conditions)
	column.add_child(Widgets.label(Widgets.t("preview_variables"), Tokens.KICKER))
	_variables = TextEdit.new()
	_variables.custom_minimum_size.y = 70
	_variables.placeholder_text = "gold = 10\nmet = true"
	_variables.add_theme_font_override("font", Tokens.font(&"mono"))
	_variables.tooltip_text = Widgets.t("preview_variables_tip")
	column.add_child(_variables)
	column.add_child(Widgets.label(Widgets.t("preview_box"), Tokens.KICKER))
	var sizes: HBoxContainer = Widgets.hbox(6)
	column.add_child(sizes)
	_width = SpinBox.new()
	_width.min_value = 240
	_width.max_value = 1920
	_width.step = 10
	_width.tooltip_text = Widgets.t("preview_width_tip")
	_width.value_changed.connect(func(value: float) -> void: _set_style("box_width", int(value)))
	sizes.add_child(_width)
	_font_size = SpinBox.new()
	_font_size.min_value = 8
	_font_size.max_value = 64
	_font_size.tooltip_text = Widgets.t("preview_font_tip")
	_font_size.value_changed.connect(func(value: float) -> void: _set_style("font_size", int(value)))
	sizes.add_child(_font_size)
	var restart_button: Button = Widgets.button("restart", &"Play", "restart_tip", restart, true)
	column.add_child(restart_button)

	_screen = Control.new()
	_screen.size_flags_horizontal = SIZE_EXPAND_FILL
	_screen.clip_contents = true
	_screen.draw.connect(_draw_screen)
	_screen.resized.connect(_fit_layout)
	add_child(_screen)
	var layout: VBoxContainer = Widgets.vbox(10)
	layout.alignment = BoxContainer.ALIGNMENT_END
	_layout = layout
	_screen.add_child(layout)
	_log = Widgets.label("", Tokens.MONO)
	_log.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log.size_flags_vertical = SIZE_EXPAND_FILL
	_log.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	layout.add_child(_log)
	_choices = Widgets.vbox(6)
	_choices.size_flags_horizontal = SIZE_SHRINK_CENTER
	layout.add_child(_choices)
	var center: CenterContainer = CenterContainer.new()
	layout.add_child(center)
	_box = PanelContainer.new()
	center.add_child(_box)
	var box_row: HBoxContainer = Widgets.hbox(14)
	_box.add_child(box_row)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(96, 96)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box_row.add_child(_portrait)
	var box_column: VBoxContainer = Widgets.vbox(6)
	box_column.size_flags_horizontal = SIZE_EXPAND_FILL
	box_row.add_child(box_column)
	_name = Widgets.label("")
	_name.add_theme_font_override("font", Tokens.font(&"condensed"))
	box_column.add_child(_name)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = false
	_text.fit_content = true
	_text.scroll_active = false
	box_column.add_child(_text)
	var foot: HBoxContainer = Widgets.hbox(8)
	box_column.add_child(foot)
	_warning = Widgets.label("", Tokens.DIM)
	_warning.add_theme_color_override("font_color", Tokens.color("bad"))
	_warning.size_flags_horizontal = SIZE_EXPAND_FILL
	foot.add_child(_warning)
	_next = Widgets.button("next_line", &"", "next_line_tip", func() -> void: _show(_runner.next()))
	foot.add_child(_next)


func reset() -> void:
	_runner = null
	_checked = {}


func refresh() -> void:
	var db: Object = view.db()
	var languages: Array = []
	for language in db.languages():
		languages.append([Widgets.language_name(language), language])
	Widgets.set_options(_language, languages)
	var platforms: Array = []
	for platform in db.project.get("platforms", []):
		platforms.append([platform, platform])
	Widgets.set_options(_platform, platforms)
	var style: Dictionary = _style()
	_width.set_value_no_signal(style["box_width"])
	_font_size.set_value_no_signal(style["font_size"])
	_fill_conditions()
	if _runner == null:
		restart()
	else:
		_apply_style()


func restart() -> void:
	var db: Object = view.db()
	var data: Dictionary = view.dialogue()
	if data.is_empty():
		return
	_runner = Runner.new()
	_runner.dialogue = DialogueData.for_game(data, db.project.get("characters", {}))
	var language: String = String(Widgets.selected_value(_language)) if _language.item_count > 0 else db.source_language()
	_runner.translate = func(key: String) -> String:
		var value: String = db.text(key, language)
		return value if not value.is_empty() else db.text(key, db.source_language())
	var platform: Variant = Widgets.selected_value(_platform)
	_runner.tokens = TextTokens.for_platform(db.project.get("tokens", {}), String(platform) if platform != null else "")
	_runner.variables = _parse_variables()
	_runner.condition_handler = func(expression: String) -> bool:
		var negate: bool = expression.begins_with("!")
		var name: String = expression.trim_prefix("!").strip_edges()
		var value: bool = bool(_checked.get(name, _runner.variables.get(name, false)))
		return not value if negate else value
	# Array (référence) : la lambda garde la même liste d'un appel à l'autre.
	var events: Array = []
	_runner.event_handler = func(name: String, args: String) -> void:
		events.append("⚡ %s(%s)" % [name, args])
		_log.text = "\n".join(PackedStringArray(events))
	_log.text = ""
	_apply_style()
	_show(_runner.start())


func _show(step: Dictionary) -> void:
	for child in _choices.get_children():
		child.queue_free()
	_warning.text = ""
	match String(step.get("type", "")):
		"line":
			_name.text = String(step["speaker_name"])
			_name.visible = not _name.text.is_empty()
			var color: String = step.get("color", "")
			_name.add_theme_color_override("font_color", Color(color) if Color.html_is_valid(color) else Tokens.color("accent"))
			_portrait.texture = load(step["portrait"]) as Texture2D if not String(step["portrait"]).is_empty() and ResourceLoader.exists(step["portrait"]) else null
			_portrait.visible = _portrait.texture != null
			_text.text = step["text"]
			_next.visible = true
			_check_length(step["text_key"], step["text"])
		"choice":
			_next.visible = false
			for option in step["options"]:
				var choice: Button = Button.new()
				choice.text = option["text"]
				choice.custom_minimum_size.x = 320
				choice.pressed.connect(func() -> void: _show(_runner.choose(option["index"])))
				_choices.add_child(choice)
				_check_length(option["text_key"], option["text"])
		_:
			_name.visible = false
			_portrait.visible = false
			_next.visible = false
			var error: String = step.get("error", "")
			_text.text = Widgets.t("preview_end") if error.is_empty() else Widgets.tf("preview_end_error", [Widgets.t("runner_" + error)])


func _check_length(key: String, text: String) -> void:
	var db: Object = view.db()
	var limit: int = db.max_length(key)
	if limit > 0 and text.length() > limit:
		_warning.text = Widgets.tf("preview_too_long", [key, text.length(), limit])


func _fill_conditions() -> void:
	for child in _conditions.get_children():
		child.queue_free()
	var names: PackedStringArray = PackedStringArray()
	var data: Dictionary = view.dialogue()
	for node in data.get("nodes", {}).values():
		var expressions: Array = []
		expressions.append(node.get("expression", ""))
		expressions.append_array(node.get("conditions", []))
		for option in node.get("options", []):
			expressions.append(option.get("condition", ""))
		for expression in expressions:
			var name: String = String(expression).trim_prefix("!").strip_edges()
			if not name.is_empty() and not names.has(name):
				names.append(name)
	names.sort()
	if names.is_empty():
		_conditions.add_child(Widgets.label(Widgets.t("preview_no_conditions"), Tokens.DIM))
	for name in names:
		var check: CheckBox = CheckBox.new()
		check.text = name
		check.add_theme_font_override("font", Tokens.font(&"mono"))
		check.button_pressed = bool(_checked.get(name, false))
		check.toggled.connect(func(on: bool) -> void:
			_checked[name] = on
			restart())
		_conditions.add_child(check)


func _parse_variables() -> Dictionary:
	var result: Dictionary = {}
	for line in _variables.text.split("\n", false):
		if not line.contains("="):
			continue
		var name: String = line.get_slice("=", 0).strip_edges()
		var raw: String = line.substr(line.find("=") + 1).strip_edges()
		var value: Variant = raw
		if raw.is_valid_int():
			value = raw.to_int()
		elif raw.is_valid_float():
			value = raw.to_float()
		elif raw == "true" or raw == "false":
			value = raw == "true"
		result[name] = value
	return result


func _style() -> Dictionary:
	var style: Dictionary = DEFAULT_STYLE.duplicate()
	var saved: Variant = view.db().project.get("preview", {})
	if typeof(saved) == TYPE_DICTIONARY:
		style.merge(saved, true)
	return style


func _set_style(name: String, value: Variant) -> void:
	var style: Dictionary = _style()
	style[name] = value
	view.db().set_project_value("preview", style)
	_apply_style()


func _apply_style() -> void:
	var style: Dictionary = _style()
	var box_color: Color = Color(String(style["box_color"])) if Color.html_is_valid(String(style["box_color"])) else Color("#11151b")
	var text_color: Color = Color(String(style["text_color"])) if Color.html_is_valid(String(style["text_color"])) else Color.WHITE
	var panel: StyleBoxFlat = Tokens.framed(Color(box_color, 0.94), Tokens.color("ink_line"), 6, 18, 14)
	_box.add_theme_stylebox_override("panel", panel)
	_box.custom_minimum_size.x = int(style["box_width"])
	_text.add_theme_color_override("default_color", text_color)
	_text.add_theme_font_size_override("normal_font_size", int(style["font_size"]))
	_name.add_theme_font_size_override("font_size", int(style["font_size"]))
	_fit_layout()
	_screen.queue_redraw()


# La « scène de jeu » est réduite si la boîte (largeur du jeu) ne tient pas :
# on voit le rendu entier, à l'échelle.
func _fit_layout() -> void:
	if _layout == null or _screen.size.x <= 0.0:
		return
	var needed: float = float(_style()["box_width"]) + 48.0
	var ratio: float = minf(1.0, _screen.size.x / needed)
	_layout.scale = Vector2(ratio, ratio)
	_layout.position = Vector2.ZERO
	_layout.size = Vector2(_screen.size.x / ratio, _screen.size.y / ratio - 24.0)


# Fond de la « scène de jeu » : dégradé sombre et vignette, discrets.
func _draw_screen() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, _screen.size)
	_screen.draw_rect(rect, Tokens.color("ink").darkened(0.35))
	var steps: int = 12
	for index in steps:
		var inset: float = index * minf(rect.size.x, rect.size.y) / (steps * 4.0)
		_screen.draw_rect(rect.grow(-inset), Color(Tokens.color("ink_panel"), 0.05), false, 2.0)
	_screen.draw_line(Vector2(0, rect.size.y * 0.62), Vector2(rect.size.x, rect.size.y * 0.62), Color(Tokens.color("ink_line"), 0.25))
