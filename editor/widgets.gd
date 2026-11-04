@tool
extends RefCounted

## Petites briques d'interface communes aux vues de l'onglet Texts (boutons,
## listes déroulantes, cartes, états vides), toutes dans le thème de
## text_theme.gd. Les icônes sont celles de l'éditeur Godot.

const Tokens = preload("text_theme.gd")
const Texts = preload("texts.gd")

## Contrôle de l'éditeur qui porte ses icônes (posé par main_view.gd).
static var base: Control = null


static func t(key: String) -> String:
	return Texts.t(key)


static func tf(key: String, args: Array) -> String:
	return Texts.tf(key, args)


static func icon(name: StringName) -> Texture2D:
	if base == null or not base.has_theme_icon(name, &"EditorIcons"):
		return null
	return base.get_theme_icon(name, &"EditorIcons")


static func button(text_key: String, icon_name: StringName, tip_key: String, callback: Callable, primary: bool = false) -> Button:
	var result: Button = Button.new()
	result.text = t(text_key) if not text_key.is_empty() else ""
	result.icon = icon(icon_name) if icon_name != &"" else null
	result.tooltip_text = t(tip_key) if not tip_key.is_empty() else ""
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if primary:
		result.theme_type_variation = Tokens.PRIMARY
	result.pressed.connect(callback)
	return result


## Bouton icône sans cadre.
static func tool_button(icon_name: StringName, tip_key: String, callback: Callable) -> Button:
	var result: Button = Button.new()
	result.icon = icon(icon_name)
	result.tooltip_text = t(tip_key)
	result.theme_type_variation = Tokens.TOOL
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	result.pressed.connect(callback)
	return result


## Liste déroulante : [param items] = [[texte affiché, valeur], ...]. La
## valeur choisie se lit avec selected_value().
static func option(items: Array, tip_key: String = "") -> OptionButton:
	var result: OptionButton = OptionButton.new()
	result.tooltip_text = t(tip_key) if not tip_key.is_empty() else ""
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Largeur fixe, texte coupé : une barre d'outils tient dans l'onglet.
	result.fit_to_longest_item = false
	result.clip_text = true
	result.custom_minimum_size.x = 120
	set_options(result, items)
	return result


static func set_options(target: OptionButton, items: Array, keep: Variant = null) -> void:
	var previous: Variant = selected_value(target) if keep == null else keep
	target.clear()
	for item in items:
		target.add_item(String(item[0]))
		target.set_item_metadata(target.item_count - 1, item[1])
	select_value(target, previous)


static func selected_value(target: OptionButton) -> Variant:
	return target.get_item_metadata(target.selected) if target.selected >= 0 else null


static func select_value(target: OptionButton, value: Variant) -> void:
	for index in target.item_count:
		if target.get_item_metadata(index) == value:
			target.select(index)
			return
	if target.item_count > 0 and target.selected < 0:
		target.select(0)


static func line_edit(placeholder_key: String, mono: bool = false) -> LineEdit:
	var result: LineEdit = LineEdit.new()
	result.placeholder_text = t(placeholder_key) if not placeholder_key.is_empty() else ""
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if mono:
		result.theme_type_variation = Tokens.MONO_EDIT
	return result


static func label(text: String, variation: StringName = &"") -> Label:
	var result: Label = Label.new()
	result.text = text
	if variation != &"":
		result.theme_type_variation = variation
	return result


static func hbox(separation: int = 8) -> HBoxContainer:
	var result: HBoxContainer = HBoxContainer.new()
	result.add_theme_constant_override("separation", separation)
	return result


static func vbox(separation: int = 8) -> VBoxContainer:
	var result: VBoxContainer = VBoxContainer.new()
	result.add_theme_constant_override("separation", separation)
	return result


static func spacer() -> Control:
	var result: Control = Control.new()
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result


## Carte : cadre panneau, surtitre ; renvoie [carte, colonne de contenu].
static func card(title_key: String) -> Array:
	var panel: PanelContainer = PanelContainer.new()
	panel.theme_type_variation = Tokens.CARD
	var column: VBoxContainer = vbox(8)
	panel.add_child(column)
	if not title_key.is_empty():
		column.add_child(label(t(title_key), Tokens.KICKER))
	return [panel, column]


## Barre d'outils d'une vue : bandeau sous l'en-tête.
static func toolbar() -> Array:
	var band: PanelContainer = Tokens.band(Vector4(0, 0, 0, 1), Vector4(12, 6, 12, 6))
	var row: HBoxContainer = hbox(6)
	band.add_child(row)
	return [band, row]


## État vide qui guide : titre, explication, bouton d'action.
static func empty_state(title_key: String, text_key: String, button_key: String, callback: Callable) -> CenterContainer:
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column: VBoxContainer = vbox(10)
	column.custom_minimum_size.x = 420
	center.add_child(column)
	var title: Label = label(t(title_key), Tokens.TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var text: Label = label(t(text_key), Tokens.DIM)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(text)
	if not button_key.is_empty():
		var action: Button = button(button_key, &"Add", "", callback, true)
		action.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(action)
	return center


## Pastille de couleur (statut, gravité) pour une cellule de Tree.
static func dot(color: Color, side: int = 10) -> ImageTexture:
	var image: Image = Image.create(side, side, false, Image.FORMAT_RGBA8)
	var center: Vector2 = Vector2(side, side) / 2.0
	for x in side:
		for y in side:
			var distance: float = Vector2(x + 0.5, y + 0.5).distance_to(center)
			image.set_pixel(x, y, Color(color, clampf(side / 2.0 - distance, 0.0, 1.0)))
	return ImageTexture.create_from_image(image)


static func language_name(code: String) -> String:
	var name: String = TranslationServer.get_locale_name(code)
	return "%s (%s)" % [name, code] if not name.is_empty() else code


## Texte d'un statut (« Needs review »).
static func status_text(status: String) -> String:
	return t("status_" + status)
