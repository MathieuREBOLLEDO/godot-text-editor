@tool
extends EditorPlugin

## Onglet « Texts » de l'éditeur (à côté de 2D, 3D, Script) : tous les textes
## du jeu et leurs traductions (editor/main_view.gd).
## get_editor_interface() plutôt que le singleton EditorInterface (4.2+),
## comme les autres addons.
## Dans un jeu sans test runner (addons/test_runner), les tests de l'addon
## sont cachés à Godot (tests/.gdignore, ignoré par git) : sans lui, leur
## classe TestCase manque et l'éditeur affiche une erreur par fichier.

const MainView = preload("res://addons/text_editor/editor/main_view.gd")
const Texts = preload("res://addons/text_editor/editor/texts.gd")
const Tokens = preload("res://addons/text_editor/editor/text_theme.gd")
const TESTS_IGNORE: String = "res://addons/text_editor/tests/.gdignore"
const TEST_RUNNER: String = "res://addons/test_runner/test_case.gd"

var _view: MainView


func _enter_tree() -> void:
	Texts.register_setting(get_editor_interface().get_editor_settings())
	_register_data_dir()
	_create()
	get_editor_interface().get_editor_settings().settings_changed.connect(_on_settings_changed)
	_hide_tests()


func _exit_tree() -> void:
	get_editor_interface().get_editor_settings().settings_changed.disconnect(_on_settings_changed)
	if _view != null:
		_view.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _view != null:
		_view.visible = visible
		if visible:
			_view.refresh_current()


func _get_plugin_name() -> String:
	return "Texts"


func _get_plugin_icon() -> Texture2D:
	return get_editor_interface().get_base_control().get_theme_icon(&"Translation", &"EditorIcons")


## Les données sont enregistrées en quittant l'éditeur ou en changeant de scène.
func _save_external_data() -> void:
	if _view != null:
		_view.save_now()


func _create() -> void:
	_view = MainView.new()
	_view.editor_interface = get_editor_interface()
	_view.undo = get_undo_redo()
	_view.visible = false
	get_editor_interface().get_editor_main_screen().add_child(_view)


# Réglage du dossier des données, visible dans Paramètres du projet ; écrit
# dans project.godot seulement s'il change.
func _register_data_dir() -> void:
	var name: String = MainView.SETTING_DATA_DIR
	if not ProjectSettings.has_setting(name):
		ProjectSettings.set_setting(name, MainView.DEFAULT_DATA_DIR)
	ProjectSettings.set_initial_value(name, MainView.DEFAULT_DATA_DIR)
	ProjectSettings.add_property_info({"name": name, "type": TYPE_STRING, "hint": PROPERTY_HINT_DIR})


func _hide_tests() -> void:
	if FileAccess.file_exists(TEST_RUNNER) or FileAccess.file_exists(TESTS_IGNORE):
		return
	var file: FileAccess = FileAccess.open(TESTS_IGNORE, FileAccess.WRITE)
	if file != null:
		file.close()
		get_editor_interface().get_resource_filesystem().scan()


## Langue ou thème changés : l'onglet est reconstruit.
func _on_settings_changed() -> void:
	var settings: EditorSettings = get_editor_interface().get_editor_settings()
	if not settings.check_changed_settings_in_group(Texts.SETTING) and not settings.check_changed_settings_in_group("interface/theme"):
		return
	Tokens.reload()
	var was_visible: bool = _view.visible
	var current: String = _view.current
	_view.save_now()
	_view.queue_free()
	_create()
	_view.visible = was_visible
	if not current.is_empty():
		_view.show_view.call_deferred(current)
