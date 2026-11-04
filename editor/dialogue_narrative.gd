@tool
extends ScrollContainer

## Vue narrative d'un dialogue : le déroulé lu comme un script (personnage,
## réplique), les embranchements en retrait sous l'option ou la condition
## qui y mène. Les répliques et options se modifient ici (même donnée que le
## graphe) ; chaque ligne a un accès direct au nœud dans le graphe.

const Tokens = preload("text_theme.gd")
const Widgets = preload("widgets.gd")
const DialogueData = preload("../core/dialogue_data.gd")

## La vue Dialogues (dialogue_view.gd).
var view: Control

var _column: VBoxContainer


func _ready() -> void:
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	var margin: MarginContainer = MarginContainer.new()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	_column = Widgets.vbox(6)
	_column.size_flags_horizontal = SIZE_EXPAND_FILL
	margin.add_child(_column)


func refresh() -> void:
	for child in _column.get_children():
		child.queue_free()
	var data: Dictionary = view.dialogue()
	if data.is_empty():
		return
	var items: Array = DialogueData.narrative(data)
	if items.is_empty():
		_column.add_child(Widgets.label(Widgets.t("narrative_no_start"), Tokens.DIM))
	for item in items:
		if not String(item["port_label"]).is_empty():
			_column.add_child(_indent(_branch_header(data, item), item["depth"] - 1))
		_column.add_child(_indent(_line(data, item), item["depth"]))


func _indent(control: Control, depth: int) -> Control:
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28 * maxi(depth, 0))
	margin.add_child(control)
	return margin


# Ce qui mène à cette branche : texte de l'option, condition, « sinon ».
func _branch_header(data: Dictionary, item: Dictionary) -> Control:
	var parent: Dictionary = data["nodes"].get(item["parent"], {})
	var port: int = int(item["port_label"])
	var text: String = ""
	match String(parent.get("type", "")):
		DialogueData.CHOICE:
			var option: Dictionary = parent["options"][port] if port < parent["options"].size() else {}
			var key: String = option.get("text_key", "")
			text = "▸ " + (view.db().text(key, view.db().source_language()) if not key.is_empty() else Widgets.t("option_empty"))
			if not String(option.get("condition", "")).is_empty():
				text += "   [%s]" % option["condition"]
		DialogueData.BRANCH:
			var conditions: Array = parent.get("conditions", [])
			text = Widgets.tf("narrative_if", [conditions[port]]) if port < conditions.size() else Widgets.t("else")
		DialogueData.CONDITION:
			text = Widgets.tf("narrative_if", [parent.get("expression", "")]) if port == 0 else Widgets.t("else")
		DialogueData.VARIABLE_CHECK:
			var test: String = "%s %s %s" % [parent.get("variable", ""), parent.get("operator", ""), parent.get("value", "")]
			text = Widgets.tf("narrative_if", [test]) if port == 0 else Widgets.t("else")
	var label: Label = Widgets.label(text, Tokens.KICKER)
	label.add_theme_color_override("font_color", Tokens.color("sand"))
	return label


func _line(data: Dictionary, item: Dictionary) -> Control:
	var id: String = item["id"]
	var node: Dictionary = data["nodes"][id]
	var row: HBoxContainer = Widgets.hbox(10)
	var locate: Button = Widgets.tool_button(&"GraphEdit", "locate_node_tip", func() -> void: view.select(view.current, id))
	if item["repeat"]:
		row.add_child(Widgets.label(Widgets.tf("narrative_back", [id, Widgets.t("node_" + node["type"])]), Tokens.DIM))
		row.add_child(locate)
		return row
	match String(node["type"]):
		DialogueData.START:
			row.add_child(Widgets.label(Widgets.t("node_start").to_upper(), Tokens.KICKER))
		DialogueData.END:
			row.add_child(Widgets.label(Widgets.t("node_end").to_upper(), Tokens.KICKER))
		DialogueData.LINE:
			var speaker: String = node.get("speaker", "")
			var character: Dictionary = view.db().project.get("characters", {}).get(speaker, {})
			var name_key: String = character.get("name_key", "")
			var name: Label = Widgets.label((view.db().text(name_key, view.db().source_language()) if not name_key.is_empty() else speaker).to_upper() + " :" if not speaker.is_empty() else "— :")
			name.custom_minimum_size.x = 130
			name.add_theme_font_override("font", Tokens.font(&"condensed"))
			if character.has("color") and Color.html_is_valid(String(character["color"])):
				name.add_theme_color_override("font_color", Color(String(character["color"])))
			row.add_child(name)
			row.add_child(_editable(node, "text_key", "dialogue"))
		DialogueData.CHOICE:
			row.add_child(Widgets.label(Widgets.tf("narrative_choice", [node.get("options", []).size()]), Tokens.DIM))
		DialogueData.EVENT:
			row.add_child(Widgets.label(Widgets.tf("narrative_event", [node.get("name", ""), node.get("args", "")]), Tokens.MONO))
		DialogueData.JUMP:
			row.add_child(Widgets.label(Widgets.tf("narrative_jump", [node.get("target", "?")]), Tokens.DIM))
		_:
			row.add_child(Widgets.label(Widgets.t("node_" + node["type"]), Tokens.DIM))
	row.add_child(locate)
	return row


# Réplique modifiable : même texte (clé de la base) que le graphe.
func _editable(holder: Dictionary, field: String, category: String) -> Control:
	var area: TextEdit = TextEdit.new()
	area.size_flags_horizontal = SIZE_EXPAND_FILL
	area.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	area.scroll_fit_content_height = true
	area.custom_minimum_size.y = 34
	area.placeholder_text = Widgets.t("line_placeholder")
	area.text = view.db().text(holder.get(field, ""), view.db().source_language())
	area.focus_exited.connect(func() -> void: view._commit_text(holder, field, category, area.text))
	return area
