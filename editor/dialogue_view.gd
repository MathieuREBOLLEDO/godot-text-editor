@tool
extends VBoxContainer

## Dialogues : liste à gauche, et pour le dialogue choisi trois vues
## synchronisées sur les mêmes données : Graph (nœuds reliés, type
## Blueprint), Narrative (le déroulé lisible, textes modifiables) et Preview
## (la conversation jouée comme en jeu). Les textes des nœuds sont des clés
## de la base : écrire une réplique crée sa clé, modifier le texte modifie
## l'entrée (donc ses traductions passent « à revoir »).

const Tokens = preload("text_theme.gd")
const Widgets = preload("widgets.gd")
const TextDb = preload("../core/text_db.gd")
const DialogueData = preload("../core/dialogue_data.gd")
const Validator = preload("../core/validator.gd")
const Narrative = preload("dialogue_narrative.gd")
const Preview = preload("dialogue_preview.gd")

const TAB_GRAPH: int = 0
const TAB_NARRATIVE: int = 1
const TAB_PREVIEW: int = 2

var main: Control
## Id du dialogue ouvert ("" : aucun).
var current: String = ""

var _list: ItemList
var _tabs: TabContainer
var _graph: GraphEdit
var _narrative: Narrative
var _preview: Preview
var _issues_label: Label
var _empty: Control
var _content: Control
var _add_menu: PopupMenu
var _add_position: Vector2 = Vector2.ZERO
var _pending_from: Array = []
var _name_dialog: ConfirmationDialog
var _name_edit: LineEdit
var _name_mode: String = ""
var _delete_dialog: ConfirmationDialog
var _building: bool = false
var _rebuild_pending: bool = false


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	var body: HSplitContainer = HSplitContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(body)
	var side: PanelContainer = Tokens.band(Vector4(0, 0, 1, 0), Vector4(10, 10, 10, 10))
	side.custom_minimum_size.x = 200
	body.add_child(side)
	var column: VBoxContainer = Widgets.vbox(8)
	side.add_child(column)
	column.add_child(Widgets.label(Widgets.t("dialogues_list"), Tokens.KICKER))
	_list = ItemList.new()
	_list.size_flags_vertical = SIZE_EXPAND_FILL
	_list.add_theme_font_override("font", Tokens.font(&"mono"))
	_list.add_theme_font_size_override("font_size", Tokens.size("small"))
	_list.item_selected.connect(func(index: int) -> void: open(_list.get_item_metadata(index)))
	column.add_child(_list)
	var buttons: HBoxContainer = Widgets.hbox(4)
	column.add_child(buttons)
	var add: Button = Widgets.button("new_dialogue", &"Add", "new_dialogue_tip", _ask_name.bind("new"), true)
	add.size_flags_horizontal = SIZE_EXPAND_FILL
	buttons.add_child(add)
	buttons.add_child(Widgets.tool_button(&"Rename", "rename_dialogue_tip", _ask_name.bind("rename")))
	buttons.add_child(Widgets.tool_button(&"Remove", "delete_dialogue_tip", func() -> void:
		if not current.is_empty():
			_delete_dialog.dialog_text = Widgets.tf("delete_dialogue_confirm", [current])
			_delete_dialog.popup_centered()))

	var right: Control = Control.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(right)
	_content = Widgets.vbox(0)
	_content.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	right.add_child(_content)
	var bar: Array = Widgets.toolbar()
	_content.add_child(bar[0])
	var row: HBoxContainer = bar[1]
	var add_node: MenuButton = MenuButton.new()
	add_node.text = Widgets.t("add_node")
	add_node.icon = Widgets.icon(&"Add")
	add_node.flat = false
	add_node.tooltip_text = Widgets.t("add_node_tip")
	_fill_type_menu(add_node.get_popup())
	add_node.get_popup().id_pressed.connect(func(id: int) -> void:
		_pending_from = []
		_add_position = (_graph.scroll_offset + _graph.size / 2.0) / _graph.zoom
		_add_node(DialogueData.TYPES[id]))
	row.add_child(add_node)
	row.add_child(Widgets.tool_button(&"CenterView", "frame_all_tip", _frame_all))
	row.add_child(Widgets.spacer())
	_issues_label = Widgets.label("", Tokens.DIM)
	_issues_label.mouse_filter = MOUSE_FILTER_STOP
	_issues_label.tooltip_text = Widgets.t("dialogue_issues_tip")
	_issues_label.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			main.show_view("qa")
			main.view("qa").filter_dialogue(current))
	row.add_child(_issues_label)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = SIZE_EXPAND_FILL
	_tabs.tab_changed.connect(func(_tab: int) -> void: _refresh_tab())
	_content.add_child(_tabs)
	_graph = GraphEdit.new()
	_graph.name = Widgets.t("tab_graph")
	_graph.right_disconnects = true
	_graph.minimap_enabled = true
	_graph.show_arrange_button = false
	_graph.connection_request.connect(_on_connection_request)
	_graph.disconnection_request.connect(_on_disconnection_request)
	_graph.delete_nodes_request.connect(_on_delete_request)
	_graph.duplicate_nodes_request.connect(_duplicate_selected)
	_graph.end_node_move.connect(_save_positions)
	_graph.popup_request.connect(func(at: Vector2) -> void:
		_pending_from = []
		_open_add_menu(at))
	_graph.connection_to_empty.connect(func(from: StringName, port: int, at: Vector2) -> void:
		_pending_from = [String(from), port]
		_open_add_menu(at))
	_tabs.add_child(_graph)
	_narrative = Narrative.new()
	_narrative.name = Widgets.t("tab_narrative")
	_narrative.view = self
	_tabs.add_child(_narrative)
	_preview = Preview.new()
	_preview.name = Widgets.t("tab_preview")
	_preview.view = self
	_tabs.add_child(_preview)
	_empty = Widgets.empty_state("empty_dialogues_title", "empty_dialogues_text", "new_dialogue", _ask_name.bind("new"))
	right.add_child(_empty)

	_add_menu = PopupMenu.new()
	_fill_type_menu(_add_menu)
	_add_menu.id_pressed.connect(func(id: int) -> void: _add_node(DialogueData.TYPES[id]))
	add_child(_add_menu)
	_name_dialog = ConfirmationDialog.new()
	_name_edit = Widgets.line_edit("dialogue_id_placeholder", true)
	_name_dialog.add_child(_name_edit)
	_name_dialog.register_text_enter(_name_edit)
	_name_dialog.confirmed.connect(_on_name_confirmed)
	add_child(_name_dialog)
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.confirmed.connect(func() -> void:
		main.db.remove_dialogue(current)
		current = ""
		refresh())
	add_child(_delete_dialog)


func db() -> TextDb:
	return main.db


func dialogue() -> Dictionary:
	return main.db.dialogues.get(current, {})


func refresh() -> void:
	var ids: Array = main.db.dialogues.keys()
	ids.sort()
	_list.clear()
	for id in ids:
		var index: int = _list.add_item(id)
		_list.set_item_metadata(index, id)
		if id == current:
			_list.select(index)
	if not main.db.dialogues.has(current):
		current = ids[0] if not ids.is_empty() else ""
		if not current.is_empty():
			_list.select(0)
	_empty.visible = current.is_empty()
	_content.visible = not _empty.visible
	if not current.is_empty():
		_rebuild_graph()
		_refresh_tab()


func open(id: String) -> void:
	current = id
	_preview.reset()
	refresh()
	_frame_all.call_deferred()


## Ouvre un dialogue sur le graphe, nœud choisi et centré.
func select(id: String, node_id: String) -> void:
	open(id)
	_tabs.current_tab = TAB_GRAPH
	if node_id.is_empty():
		return
	var graph_node: GraphNode = _graph.get_node_or_null(NodePath(node_id))
	if graph_node == null:
		return
	for child in _graph.get_children():
		if child is GraphNode:
			child.selected = child == graph_node
	_center_on.call_deferred(graph_node)


## Le dialogue a changé (données) : enregistrer et rafraîchir les vues.
func changed(rebuild: bool = false) -> void:
	main.db.mark_dialogue_dirty(current)
	# Un champ qui perd le focus pendant la reconstruction du graphe : ses
	# données sont déjà écrites, pas de reconstruction imbriquée.
	if _building:
		return
	# Reconstruction différée : on est souvent dans le signal d'un contrôle
	# du graphe, qu'on ne retire pas pendant qu'il s'exécute.
	if rebuild and not _rebuild_pending:
		_rebuild_pending = true
		(func() -> void:
			_rebuild_pending = false
			_refresh_tab()).call_deferred()
	_update_issues()


func _refresh_tab() -> void:
	_update_issues()
	match _tabs.current_tab:
		TAB_NARRATIVE:
			_narrative.refresh()
		TAB_PREVIEW:
			_preview.refresh()
		TAB_GRAPH:
			_refresh_graph_texts()


func _update_issues() -> void:
	if current.is_empty():
		return
	var issues: Array = []
	Validator.check_dialogue(main.db, current, issues)
	var counts: Dictionary = Validator.counts(issues)
	if issues.is_empty():
		_issues_label.text = Widgets.t("dialogue_ok")
		_issues_label.add_theme_color_override("font_color", Tokens.color("good"))
	else:
		_issues_label.text = Widgets.tf("dialogue_issues", [counts[Validator.ERROR], counts[Validator.WARNING]])
		_issues_label.add_theme_color_override("font_color", Tokens.color("bad") if counts[Validator.ERROR] > 0 else Tokens.color("sand_dim"))


# --- Graphe ---

func _fill_type_menu(menu: PopupMenu) -> void:
	menu.clear()
	for index in DialogueData.TYPES.size():
		menu.add_item(Widgets.t("node_" + DialogueData.TYPES[index]), index)
		menu.set_item_tooltip(index, Widgets.t("node_" + DialogueData.TYPES[index] + "_tip"))


func _open_add_menu(at: Vector2) -> void:
	_add_position = (_graph.scroll_offset + at) / _graph.zoom
	_add_menu.position = Vector2i(_graph.get_screen_position() + at)
	_add_menu.reset_size()
	_add_menu.popup()


func _add_node(type: String) -> void:
	var data: Dictionary = dialogue()
	if data.is_empty():
		return
	var id: String = DialogueData.add_node(data, type, _add_position)
	if not _pending_from.is_empty():
		DialogueData.connect_nodes(data, _pending_from[0], _pending_from[1], id)
		_pending_from = []
	changed(true)


func _rebuild_graph() -> void:
	_building = true
	_graph.clear_connections()
	for child in _graph.get_children():
		if child is GraphNode:
			_graph.remove_child(child)
			child.queue_free()
	var data: Dictionary = dialogue()
	if data.is_empty():
		_building = false
		return
	for id in DialogueData.sorted_ids(data):
		_graph.add_child(_make_graph_node(id, data["nodes"][id]))
	for link in data["links"]:
		if _graph.has_node(NodePath(link[0])) and _graph.has_node(NodePath(link[2])):
			_graph.connect_node(StringName(link[0]), int(link[1]), StringName(link[2]), 0)
	_building = false


func _refresh_graph_texts() -> void:
	# Textes modifiés ailleurs (narratif, base) : le plus simple est de
	# reconstruire, le graphe garde son zoom et son défilement.
	_rebuild_graph()


func _frame_all() -> void:
	var nodes: Array = []
	for child in _graph.get_children():
		if child is GraphNode:
			nodes.append(child)
	if nodes.is_empty():
		return
	var area: Rect2 = Rect2(nodes[0].position_offset, nodes[0].size)
	for graph_node in nodes:
		area = area.merge(Rect2(graph_node.position_offset, graph_node.size))
	var fit: float = minf(_graph.size.x / maxf(area.size.x + 80.0, 1.0), _graph.size.y / maxf(area.size.y + 80.0, 1.0))
	# Pas en dessous de 0.7 : les champs des nœuds restent lisibles (le reste
	# se parcourt en faisant glisser).
	_graph.zoom = clampf(fit, 0.7, 1.0)
	_graph.scroll_offset = area.get_center() * _graph.zoom - _graph.size / 2.0


func _center_on(graph_node: GraphNode) -> void:
	_graph.scroll_offset = (graph_node.position_offset + graph_node.size / 2.0) * _graph.zoom - _graph.size / 2.0


func _on_connection_request(from: StringName, from_port: int, to: StringName, _to_port: int) -> void:
	if DialogueData.connect_nodes(dialogue(), String(from), from_port, String(to)):
		changed(true)


func _on_disconnection_request(from: StringName, from_port: int, _to: StringName, _to_port: int) -> void:
	DialogueData.disconnect_port(dialogue(), String(from), from_port)
	changed(true)


func _on_delete_request(names: Array) -> void:
	for node_name in names:
		DialogueData.remove_node(dialogue(), String(node_name))
	changed(true)


func _duplicate_selected() -> void:
	var data: Dictionary = dialogue()
	for child in _graph.get_children():
		if child is GraphNode and child.selected:
			var source: Dictionary = data["nodes"][String(child.name)]
			var id: String = DialogueData.add_node(data, source["type"], child.position_offset + Vector2(40, 40))
			var copy: Dictionary = source.duplicate(true)
			copy["position"] = data["nodes"][id]["position"]
			data["nodes"][id] = copy
	changed(true)


func _save_positions() -> void:
	var data: Dictionary = dialogue()
	for child in _graph.get_children():
		if child is GraphNode and data["nodes"].has(String(child.name)):
			data["nodes"][String(child.name)]["position"] = [roundi(child.position_offset.x), roundi(child.position_offset.y)]
	changed()


## Nœud du graphe : une ligne par contrôle ; l'entrée sur la 1re ligne, une
## sortie par port sur la ligne de son option / condition.
func _make_graph_node(id: String, node: Dictionary) -> GraphNode:
	var graph_node: GraphNode = GraphNode.new()
	graph_node.name = id
	var type: String = node.get("type", "")
	graph_node.title = "%s  ·  %s" % [Widgets.t("node_" + type), id]
	graph_node.tooltip_text = Widgets.t("node_" + type + "_tip")
	var position: Array = node.get("position", [0, 0])
	graph_node.position_offset = Vector2(float(position[0]), float(position[1]))
	graph_node.custom_minimum_size.x = 240 if type in [DialogueData.START, DialogueData.END, DialogueData.JUMP] else 320
	var rows: Array = []
	var outputs: Array = []
	match type:
		DialogueData.START:
			rows.append(Widgets.label(Widgets.t("node_start_text"), Tokens.DIM))
			outputs = [0]
		DialogueData.END:
			rows.append(Widgets.label(Widgets.t("node_end_text"), Tokens.DIM))
		DialogueData.LINE:
			rows.append(_speaker_option(node))
			rows.append(_text_editor(node, "text_key", "dialogue", true))
			outputs = [0]
		DialogueData.CHOICE:
			rows.append(_row_with_add(Widgets.t("options"), func() -> void:
				node["options"].append({"text_key": "", "condition": ""})
				changed(true)))
			for index in node.get("options", []).size():
				rows.append(_option_row(node, index))
				outputs.append(rows.size() - 1)
		DialogueData.BRANCH:
			rows.append(_row_with_add(Widgets.t("conditions"), func() -> void:
				node["conditions"].append("")
				changed(true)))
			for index in node.get("conditions", []).size():
				rows.append(_condition_row(node, index))
				outputs.append(rows.size() - 1)
			rows.append(_port_label(Widgets.t("else")))
			outputs.append(rows.size() - 1)
		DialogueData.CONDITION:
			rows.append(_field(node, "expression", "expression_placeholder"))
			rows.append(_port_label(Widgets.t("if_true")))
			rows.append(_port_label(Widgets.t("if_false")))
			outputs = [1, 2]
		DialogueData.VARIABLE_CHECK:
			var line: HBoxContainer = Widgets.hbox(4)
			var variable: LineEdit = _field(node, "variable", "variable_placeholder")
			variable.size_flags_horizontal = SIZE_EXPAND_FILL
			line.add_child(variable)
			var operators: Array = []
			for operator in DialogueData.OPERATORS:
				operators.append([operator, operator])
			var operator_option: OptionButton = Widgets.option(operators)
			Widgets.select_value(operator_option, node.get("operator", "=="))
			operator_option.item_selected.connect(func(_index: int) -> void:
				node["operator"] = Widgets.selected_value(operator_option)
				changed())
			line.add_child(operator_option)
			var value: LineEdit = _field(node, "value", "value_placeholder")
			value.custom_minimum_size.x = 70
			line.add_child(value)
			rows.append(line)
			rows.append(_port_label(Widgets.t("if_true")))
			rows.append(_port_label(Widgets.t("if_false")))
			outputs = [1, 2]
		DialogueData.EVENT:
			rows.append(_field(node, "name", "event_placeholder"))
			rows.append(_field(node, "args", "args_placeholder"))
			outputs = [0]
		DialogueData.JUMP:
			var targets: Array = [[Widgets.t("jump_none"), ""]]
			for other in DialogueData.sorted_ids(dialogue()):
				if other != id:
					targets.append(["%s · %s" % [other, Widgets.t("node_" + dialogue()["nodes"][other]["type"])], other])
			var target: OptionButton = Widgets.option(targets, "jump_tip")
			Widgets.select_value(target, node.get("target", ""))
			target.item_selected.connect(func(_index: int) -> void:
				node["target"] = Widgets.selected_value(target)
				changed())
			rows.append(target)
	for row in rows:
		graph_node.add_child(row)
	var accent: Color = Tokens.color("accent")
	var dim: Color = Tokens.color("sand_dim")
	for index in rows.size():
		var has_input: bool = index == 0 and DialogueData.has_input(node)
		graph_node.set_slot(index, has_input, 0, dim, outputs.has(index), 0, accent)
	return graph_node


func _row_with_add(text: String, callback: Callable) -> HBoxContainer:
	var row: HBoxContainer = Widgets.hbox(4)
	var label: Label = Widgets.label(text, Tokens.DIM)
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(Widgets.tool_button(&"Add", "add_port_tip", callback))
	return row


func _port_label(text: String) -> Label:
	var label: Label = Widgets.label(text, Tokens.DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


func _field(node: Dictionary, field: String, placeholder: String) -> LineEdit:
	var edit: LineEdit = Widgets.line_edit(placeholder, true)
	edit.text = String(node.get(field, ""))
	edit.text_changed.connect(func(text: String) -> void:
		node[field] = text
		changed())
	return edit


func _speaker_option(node: Dictionary) -> OptionButton:
	var items: Array = [[Widgets.t("no_speaker"), ""]]
	var characters: Dictionary = main.db.project.get("characters", {})
	var names: Array = characters.keys()
	names.sort()
	for name in names:
		items.append([name, name])
	var speaker: String = node.get("speaker", "")
	if not speaker.is_empty() and not characters.has(speaker):
		items.append([speaker + " ?", speaker])
	var option_button: OptionButton = Widgets.option(items, "speaker_tip")
	Widgets.select_value(option_button, speaker)
	option_button.item_selected.connect(func(_index: int) -> void:
		node["speaker"] = Widgets.selected_value(option_button)
		changed())
	return option_button


## Clé (petite, à chasse fixe) et texte source d'une réplique ou d'une
## option ; écrire un texte sans clé crée l'entrée.
func _text_editor(holder: Dictionary, field: String, category: String, multiline: bool) -> Control:
	var column: VBoxContainer = Widgets.vbox(2)
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	var key_edit: LineEdit = Widgets.line_edit("key_placeholder", true)
	key_edit.text = holder.get(field, "")
	key_edit.tooltip_text = Widgets.t("node_key_tip")
	column.add_child(key_edit)
	var text_control: Control
	if multiline:
		var area: TextEdit = TextEdit.new()
		area.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		area.scroll_fit_content_height = true
		area.custom_minimum_size.y = 34
		area.placeholder_text = Widgets.t("line_placeholder")
		area.text = main.db.text(holder.get(field, ""), main.db.source_language())
		area.focus_exited.connect(func() -> void: _commit_text(holder, field, category, area.text))
		text_control = area
	else:
		var edit: LineEdit = LineEdit.new()
		edit.placeholder_text = Widgets.t("option_placeholder")
		edit.text = main.db.text(holder.get(field, ""), main.db.source_language())
		edit.text_submitted.connect(func(text: String) -> void: _commit_text(holder, field, category, text))
		edit.focus_exited.connect(func() -> void: _commit_text(holder, field, category, edit.text))
		text_control = edit
	if not main.db.has_key(holder.get(field, "")) and not String(holder.get(field, "")).is_empty():
		key_edit.add_theme_color_override("font_color", Tokens.color("bad"))
		key_edit.tooltip_text = Widgets.t("unknown_key_tip")
	key_edit.text_submitted.connect(func(new_key: String) -> void: _set_key(holder, field, category, new_key, text_control))
	key_edit.focus_exited.connect(func() -> void: _set_key(holder, field, category, key_edit.text, text_control))
	column.add_child(text_control)
	return column


func _commit_text(holder: Dictionary, field: String, category: String, text: String) -> void:
	var db_ref: TextDb = main.db
	var key: String = holder.get(field, "")
	if key.is_empty():
		if text.strip_edges().is_empty():
			return
		key = db_ref.unique_key("%s_%s" % [current.to_upper(), category.to_upper()])
		holder[field] = key
		main.edit(Widgets.t("action_add"), PackedStringArray([key]), func() -> void:
			db_ref.add_entry(key, category, text))
		changed(true)
		return
	if not db_ref.has_key(key):
		main.edit(Widgets.t("action_add"), PackedStringArray([key]), func() -> void:
			db_ref.add_entry(key, category, text))
		changed(true)
		return
	if db_ref.text(key, db_ref.source_language()) != text:
		main.edit(Widgets.t("action_edit"), PackedStringArray([key]), func() -> void:
			db_ref.set_source(key, text))
		changed()


func _set_key(holder: Dictionary, field: String, _category: String, new_key: String, text_control: Control) -> void:
	new_key = new_key.strip_edges()
	if new_key == holder.get(field, ""):
		return
	if not new_key.is_empty() and not main.db.is_valid_key(new_key):
		main.set_status(Widgets.tf("invalid_key", [new_key]), "bad")
		return
	holder[field] = new_key
	# Clé existante : son texte s'affiche ; sinon le texte en cours la crée.
	if main.db.has_key(new_key):
		text_control.set("text", main.db.text(new_key, main.db.source_language()))
	changed(true)


func _option_row(node: Dictionary, index: int) -> HBoxContainer:
	var option: Dictionary = node["options"][index]
	var row: HBoxContainer = Widgets.hbox(4)
	var texts: Control = _text_editor(option, "text_key", "choice", false)
	row.add_child(texts)
	var side: VBoxContainer = Widgets.vbox(2)
	row.add_child(side)
	var condition: LineEdit = Widgets.line_edit("condition_placeholder", true)
	condition.custom_minimum_size.x = 90
	condition.text = option.get("condition", "")
	condition.tooltip_text = Widgets.t("option_condition_tip")
	condition.text_changed.connect(func(text: String) -> void:
		option["condition"] = text
		changed())
	side.add_child(condition)
	side.add_child(Widgets.tool_button(&"Remove", "remove_port_tip", func() -> void:
		_remove_port(node, "options", index)))
	return row


func _condition_row(node: Dictionary, index: int) -> HBoxContainer:
	var row: HBoxContainer = Widgets.hbox(4)
	var edit: LineEdit = Widgets.line_edit("expression_placeholder", true)
	edit.size_flags_horizontal = SIZE_EXPAND_FILL
	edit.text = node["conditions"][index]
	edit.text_changed.connect(func(text: String) -> void:
		node["conditions"][index] = text
		changed())
	row.add_child(edit)
	row.add_child(Widgets.tool_button(&"Remove", "remove_port_tip", func() -> void:
		_remove_port(node, "conditions", index)))
	return row


## Retire une option ou une condition ; les liens des sorties suivantes
## remontent d'un cran pour rester sur leur option.
func _remove_port(node: Dictionary, list_name: String, index: int) -> void:
	var data: Dictionary = dialogue()
	var id: String = ""
	for other in data["nodes"]:
		if data["nodes"][other] == node:
			id = other
	node[list_name].remove_at(index)
	var kept: Array = []
	for link in data["links"]:
		if link[0] == id and int(link[1]) == index:
			continue
		if link[0] == id and int(link[1]) > index:
			kept.append([link[0], int(link[1]) - 1, link[2]])
		else:
			kept.append(link)
	data["links"] = kept
	DialogueData.sort_links(data)
	changed(true)


# --- Nom d'un dialogue ---

func _ask_name(mode: String) -> void:
	if mode == "rename" and current.is_empty():
		return
	_name_mode = mode
	_name_dialog.title = Widgets.t("new_dialogue" if mode == "new" else "rename_dialogue")
	_name_edit.text = "" if mode == "new" else current
	_name_dialog.popup_centered(Vector2i(360, 90))
	_name_edit.grab_focus()
	_name_edit.select_all()


func _on_name_confirmed() -> void:
	var id: String = _name_edit.text.strip_edges().to_snake_case().validate_filename()
	if id.is_empty() or main.db.dialogues.has(id):
		main.set_status(Widgets.tf("invalid_dialogue_id", [_name_edit.text]), "bad")
		return
	if _name_mode == "new":
		main.db.add_dialogue(id, DialogueData.create())
	else:
		main.db.rename_dialogue(current, id)
	open(id)
