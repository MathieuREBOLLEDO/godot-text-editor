@tool
extends VBoxContainer

## Validation & QA : lance la validation globale (avec, au choix, la
## recherche des textes inutilisés dans les fichiers du jeu), liste les
## problèmes par gravité avec leur explication ; double-clic : ouvre l'entrée
## ou le nœud concerné.

const Tokens = preload("text_theme.gd")
const Widgets = preload("widgets.gd")
const Validator = preload("../core/validator.gd")

var main: Control

var _scan: CheckBox
var _severity: OptionButton
var _code: OptionButton
var _tree: Tree
var _help_title: Label
var _help_text: Label
var _counts: Label
var _dialogue_filter: String = ""
var _ran: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	var bar: Array = Widgets.toolbar()
	add_child(bar[0])
	var row: HBoxContainer = bar[1]
	_severity = Widgets.option([[Widgets.t("all_severities"), ""], [Widgets.t("severity_error"), Validator.ERROR],
		[Widgets.t("severity_warning"), Validator.WARNING], [Widgets.t("severity_info"), Validator.INFO]])
	_severity.item_selected.connect(func(_index: int) -> void: _fill())
	row.add_child(_severity)
	_code = Widgets.option([], "issue_type_tip")
	_code.item_selected.connect(func(_index: int) -> void: _fill())
	row.add_child(_code)
	row.add_child(Widgets.spacer())
	_counts = Widgets.label("", Tokens.MONO)
	row.add_child(_counts)
	_scan = CheckBox.new()
	_scan.text = Widgets.t("scan_unused")
	_scan.tooltip_text = Widgets.t("scan_unused_tip")
	row.add_child(_scan)
	row.add_child(Widgets.button("run_validation", &"", "run_validation_tip", run, true))

	var body: VSplitContainer = VSplitContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(body)
	_tree = Tree.new()
	_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_tree.columns = 3
	_tree.hide_root = true
	_tree.column_titles_visible = true
	_tree.set_column_title(0, Widgets.t("issue_column_problem"))
	_tree.set_column_title(1, Widgets.t("issue_column_where"))
	_tree.set_column_title(2, Widgets.t("issue_column_detail"))
	for column in 3:
		_tree.set_column_expand(column, column == 2)
		_tree.set_column_title_alignment(column, HORIZONTAL_ALIGNMENT_LEFT)
	_tree.set_column_custom_minimum_width(0, 240)
	_tree.set_column_custom_minimum_width(1, 260)
	_tree.item_selected.connect(_on_selected)
	_tree.item_activated.connect(_on_activated)
	body.add_child(_tree)
	var help: PanelContainer = Tokens.band(Vector4(0, 1, 0, 0), Vector4(14, 10, 14, 10))
	help.custom_minimum_size.y = 80
	body.add_child(help)
	var help_column: VBoxContainer = Widgets.vbox(4)
	help.add_child(help_column)
	_help_title = Widgets.label(Widgets.t("issue_help_empty"), Tokens.KICKER)
	help_column.add_child(_help_title)
	_help_text = Widgets.label("", Tokens.DIM)
	_help_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_column.add_child(_help_text)


func refresh() -> void:
	if not _ran:
		run()
	else:
		_fill()


func run() -> void:
	_ran = true
	main.validate(_scan.button_pressed)
	var codes: Array = [[Widgets.t("all_issue_types"), ""]]
	var seen: Dictionary = {}
	for issue in main.issues:
		if not seen.has(issue["code"]):
			seen[issue["code"]] = true
			codes.append([Widgets.t("issue_" + issue["code"] + "_title"), issue["code"]])
	Widgets.set_options(_code, codes)
	_fill()
	var counts: Dictionary = Validator.counts(main.issues)
	main.set_status(Widgets.tf("validation_done", [counts[Validator.ERROR], counts[Validator.WARNING], counts[Validator.INFO]]),
		"bad" if counts[Validator.ERROR] > 0 else "good")


## Montre seulement un type de problème (depuis le tableau de bord).
func filter_code(code: String) -> void:
	_dialogue_filter = ""
	if not _ran:
		run()
	Widgets.select_value(_code, code)
	_fill()


## Montre les problèmes d'un dialogue.
func filter_dialogue(id: String) -> void:
	run()
	_dialogue_filter = id
	_fill()


func _fill() -> void:
	_tree.clear()
	var root: TreeItem = _tree.create_item()
	var severity: String = Widgets.selected_value(_severity)
	var code: Variant = Widgets.selected_value(_code)
	var order: Array = [Validator.ERROR, Validator.WARNING, Validator.INFO]
	# Par gravité, dans l'ordre de la validation (tri stable).
	var list: Array = []
	for level in order:
		for issue in main.issues:
			if issue["severity"] == level:
				list.append(issue)
	var shown: int = 0
	var mono: Font = Tokens.font(&"mono")
	for index in list.size():
		var issue: Dictionary = list[index]
		if not severity.is_empty() and issue["severity"] != severity:
			continue
		if code != null and not String(code).is_empty() and issue["code"] != code:
			continue
		if not _dialogue_filter.is_empty() and issue["dialogue"] != _dialogue_filter:
			continue
		shown += 1
		var item: TreeItem = _tree.create_item(root)
		item.set_metadata(0, issue)
		item.set_icon(0, Widgets.dot(Tokens.severity_color(issue["severity"])))
		item.set_text(0, Widgets.t("issue_" + issue["code"] + "_title"))
		item.set_tooltip_text(0, Widgets.t("issue_" + issue["code"] + "_help"))
		item.set_text(1, _where(issue))
		item.set_custom_font(1, mono)
		item.set_text(2, Widgets.tf("issue_" + issue["code"], issue["args"]))
		if shown >= 2000:
			break
	var counts: Dictionary = Validator.counts(main.issues)
	_counts.text = Widgets.tf("issue_counts", [counts[Validator.ERROR], counts[Validator.WARNING], counts[Validator.INFO]])
	if shown == 0:
		var item: TreeItem = _tree.create_item(root)
		item.set_text(0, Widgets.t("no_issues"))
		item.set_custom_color(0, Tokens.color("good"))


func _where(issue: Dictionary) -> String:
	if not String(issue["dialogue"]).is_empty():
		return "%s · %s" % [issue["dialogue"], issue["node"]] if not String(issue["node"]).is_empty() else issue["dialogue"]
	if not String(issue["language"]).is_empty():
		return "%s · %s" % [issue["key"], issue["language"]]
	return issue["key"]


func _on_selected() -> void:
	var item: TreeItem = _tree.get_selected()
	var issue: Variant = item.get_metadata(0) if item != null else null
	if issue == null:
		return
	_help_title.text = Widgets.t("issue_" + issue["code"] + "_title")
	_help_text.text = Widgets.t("issue_" + issue["code"] + "_help") + "\n" + Widgets.t("issue_open_hint")


func _on_activated() -> void:
	var item: TreeItem = _tree.get_selected()
	var issue: Variant = item.get_metadata(0) if item != null else null
	if issue == null:
		return
	if not String(issue["dialogue"]).is_empty():
		main.open_node(issue["dialogue"], issue["node"])
	elif not String(issue["key"]).is_empty() and main.db.has_key(issue["key"]):
		main.open_entry(issue["key"], issue["language"])
