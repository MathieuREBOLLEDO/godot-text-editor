@tool
extends Control

## Onglet « Texts » : en-tête (titre de l'espace, recherche globale), rail
## des espaces à gauche (Dashboard, Database, Dialogues, Localization,
## Import / Export, QA, Settings), l'espace ouvert, pied (état, raccourcis).
## Porte la base (core/text_db.gd), l'enregistre peu après chaque changement
## (sauvegarde automatique) et l'annulation des entrées (Ctrl+Z de
## l'éditeur).

const TextDb = preload("../core/text_db.gd")
const Validator = preload("../core/validator.gd")
const Tokens = preload("text_theme.gd")
const Texts = preload("texts.gd")
const Widgets = preload("widgets.gd")

const SETTING_DATA_DIR: String = "text_editor/data_dir"
const DEFAULT_DATA_DIR: String = "res://game/ui/texts"
## Délai entre le dernier changement et l'écriture des fichiers.
const SAVE_DELAY: float = 0.6
## Lignes du fond (façon cahier) et marge.
const RULE_STEP: float = 26.0
const MARGIN_X: float = 64.0
const VIEWS: Array = [
	["dashboard", &"Grid", preload("dashboard_view.gd")],
	["database", &"ItemList", preload("database_view.gd")],
	["dialogues", &"GraphEdit", preload("dialogue_view.gd")],
	["localization", &"Translation", preload("localization_view.gd")],
	["import_export", &"Load", preload("import_export_view.gd")],
	["qa", &"StatusWarning", preload("qa_view.gd")],
	["settings", &"Tools", preload("settings_view.gd")],
]

var editor_interface: EditorInterface
var undo: EditorUndoRedoManager
var db: TextDb
## Derniers problèmes trouvés (validate()).
var issues: Array = []
var current: String = ""

var _views: Dictionary = {}
var _nav: Dictionary = {}
var _title: Label
var _search: LineEdit
var _status: Label
var _save_timer: Timer
var _pages: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	size_flags_vertical = SIZE_EXPAND_FILL
	# Les textes passent par texts.gd : l'éditeur ne doit pas les retraduire
	# avec sa propre langue (« Settings » devenait « Paramètres »).
	auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED
	theme = Tokens.build()
	if editor_interface != null:
		Widgets.base = editor_interface.get_base_control()
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = SAVE_DELAY
	_save_timer.timeout.connect(save_now)
	add_child(_save_timer)
	load_data()
	_build()
	show_view("dashboard")


func _exit_tree() -> void:
	if db != null and db.is_dirty():
		db.save()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Tokens.color("ink"))
	var rule: Color = Color(Tokens.color("ink_line"), 0.16)
	var y: float = RULE_STEP
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), rule)
		y += RULE_STEP
	draw_line(Vector2(MARGIN_X, 0), Vector2(MARGIN_X, size.y), Color(Tokens.color("ink_line"), 0.35))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


static func data_dir() -> String:
	return String(ProjectSettings.get_setting(SETTING_DATA_DIR, DEFAULT_DATA_DIR))


# --- Données ---

func load_data() -> void:
	if db != null and db.is_dirty():
		db.save()
	db = TextDb.new()
	db.load_dir(data_dir())
	db.changed.connect(func(_keys: PackedStringArray) -> void: schedule_save())
	db.dialogue_changed.connect(func(_id: String) -> void: schedule_save())
	db.project_changed.connect(schedule_save)
	issues = Validator.run(db)
	_report_load()


func _report_load() -> void:
	if db.has_blocking_errors():
		var error: Dictionary = db.load_errors[0]
		set_status(Texts.tf("load_" + String(error["code"]), error["args"]), "bad")
	elif not db.load_errors.is_empty():
		set_status(Texts.tf("load_duplicates", [db.load_errors.size()]), "bad")


func schedule_save() -> void:
	if _save_timer != null:
		_save_timer.start()


func save_now() -> void:
	if not db.is_dirty():
		return
	if db.save():
		set_status(Texts.tf("saved", [db.dir]), "")
	else:
		set_status(Texts.tf("error_save", [db.dir]), "bad")


## Modifie des entrées de façon annulable : [param change] est appelé, puis
## l'état avant / après de [param keys] part dans l'historique de l'éditeur.
func edit(label: String, keys: PackedStringArray, change: Callable) -> void:
	var before: Dictionary = {}
	for key in keys:
		before[key] = db.snapshot(key)
	change.call()
	var after: Dictionary = {}
	for key in keys:
		after[key] = db.snapshot(key)
	if undo != null and before != after:
		undo.create_action(label, UndoRedo.MERGE_DISABLE, self)
		undo.add_do_method(self, &"_restore", after)
		undo.add_undo_method(self, &"_restore", before)
		undo.commit_action(false)


func _restore(states: Dictionary) -> void:
	for key in states:
		db.restore(key, states[key])
	refresh_current()


## Valide tout ; [param scan] cherche aussi les textes inutilisés dans les
## fichiers du jeu (scripts, scènes, ressources).
func validate(scan: bool = false) -> Array:
	var options: Dictionary = {}
	if scan:
		options["project_text"] = _project_text("res://")
	var font_path: String = db.project.get("font", "")
	if not font_path.is_empty() and ResourceLoader.exists(font_path):
		options["font"] = load(font_path)
	issues = Validator.run(db, options)
	return issues


func _project_text(dir: String) -> String:
	var text: String = ""
	if dir.begins_with(db.dir) or dir == "res://addons" or dir.get_file().begins_with("."):
		return ""
	for sub in DirAccess.get_directories_at(dir):
		text += _project_text(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() in ["gd", "tscn", "tres", "cfg", "json", "cs"]:
			text += FileAccess.get_file_as_string(dir.path_join(file)) + "\n"
	return text


# --- Navigation ---

func show_view(name: String) -> void:
	current = name
	for view_name in _views:
		_views[view_name].visible = view_name == name
		_nav[view_name].set_pressed_no_signal(view_name == name)
	_title.text = Texts.t("view_" + name)
	_views[name].refresh()


func refresh_current() -> void:
	if _views.has(current):
		_views[current].refresh()


func view(name: String) -> Control:
	return _views.get(name, null)


## Ouvre une entrée dans la base (et sa langue dans Localization si donnée).
func open_entry(key: String, language: String = "") -> void:
	if not language.is_empty() and language != db.source_language():
		show_view("localization")
		_views["localization"].select(key, language)
	else:
		show_view("database")
		_views["database"].select(key)


func open_node(dialogue: String, node: String) -> void:
	show_view("dialogues")
	_views["dialogues"].select(dialogue, node)


## Message du pied ; [param kind] : "" (neutre), "good", "bad".
func set_status(text: String, kind: String = "") -> void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override("font_color", Tokens.color(kind) if not kind.is_empty() else Tokens.color("sand_dim"))


func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null and not is_ancestor_of(focus):
		return
	var key: InputEventKey = event
	if key.alt_pressed and key.keycode >= KEY_1 and key.keycode < KEY_1 + VIEWS.size():
		show_view(VIEWS[key.keycode - KEY_1][0])
		accept_event()
	elif key.ctrl_pressed and key.keycode == KEY_F:
		_search.grab_focus()
		_search.select_all()
		accept_event()


# --- Construction ---

func _build() -> void:
	var page: VBoxContainer = Widgets.vbox(0)
	page.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(page)
	page.add_child(_build_header())
	var body: HBoxContainer = Widgets.hbox(0)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	page.add_child(body)
	body.add_child(_build_rail())
	_pages = Control.new()
	_pages.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(_pages)
	for index in VIEWS.size():
		var view_node: Control = VIEWS[index][2].new()
		view_node.set("main", self)
		view_node.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		view_node.visible = false
		_pages.add_child(view_node)
		_views[VIEWS[index][0]] = view_node
	var footer: PanelContainer = Tokens.band(Vector4(0, 1, 0, 0), Vector4(12, 5, 12, 5))
	page.add_child(footer)
	var row: HBoxContainer = Widgets.hbox()
	footer.add_child(row)
	_status = Widgets.label("", Tokens.DIM)
	_status.size_flags_horizontal = SIZE_EXPAND_FILL
	_status.clip_text = true
	row.add_child(_status)
	row.add_child(Widgets.label(Texts.t("hint"), Tokens.DIM))
	_report_load()


func _build_header() -> Control:
	var header: PanelContainer = Tokens.band(Vector4(0, 0, 0, 1), Vector4(14, 8, 12, 8))
	var row: HBoxContainer = Widgets.hbox()
	header.add_child(row)
	var titles: VBoxContainer = Widgets.vbox(0)
	titles.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(titles)
	titles.add_child(Widgets.label(Texts.t("overline"), Tokens.KICKER))
	_title = Widgets.label("", Tokens.TITLE)
	titles.add_child(_title)
	_search = Widgets.line_edit("search_all")
	_search.custom_minimum_size.x = 260
	_search.clear_button_enabled = true
	_search.right_icon = Widgets.icon(&"Search")
	_search.tooltip_text = Texts.t("search_all_tip")
	_search.text_submitted.connect(func(text: String) -> void:
		show_view("database")
		_views["database"].search(text))
	row.add_child(_search)
	row.add_child(Widgets.tool_button(&"Reload", "reload_tip", func() -> void:
		load_data()
		refresh_current()))
	return header


func _build_rail() -> Control:
	var rail: PanelContainer = Tokens.band(Vector4(0, 0, 1, 0), Vector4(6, 10, 6, 10))
	rail.custom_minimum_size.x = 150
	var column: VBoxContainer = Widgets.vbox(2)
	rail.add_child(column)
	for index in VIEWS.size():
		var name: String = VIEWS[index][0]
		var nav: Button = Button.new()
		nav.text = Texts.t("view_" + name)
		nav.icon = Widgets.icon(VIEWS[index][1])
		nav.toggle_mode = true
		nav.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nav.theme_type_variation = Tokens.NAV
		nav.tooltip_text = Texts.tf("view_tip", [Texts.t("view_" + name + "_tip"), index + 1])
		nav.pressed.connect(show_view.bind(name))
		column.add_child(nav)
		_nav[name] = nav
		if name == "import_export":
			column.add_child(HSeparator.new())
	return rail
