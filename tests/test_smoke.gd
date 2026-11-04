extends TestCase

## Fumée de Text Editor : chaque fichier de l'addon se charge, chaque texte
## anglais a sa traduction française (et rien de plus), les textes à trous
## gardent leurs trous, et chaque clé de texte écrite en clair dans le code
## de l'onglet existe en anglais.

const ADDON_DIR: String = "res://addons/text_editor"
const LOADED_EXTENSIONS: PackedStringArray = ["gd", "tscn", "tres"]
const SKIPPED_DIRS: PackedStringArray = ["tests"]
const Texts = preload("res://addons/text_editor/editor/texts.gd")
## Appels dont le 1er argument (ou le n-ième) est une clé de texte.
const KEY_CALLS: PackedStringArray = ["t(\"", "tf(\"", "button(\"", "line_edit(\"", "card(\"", "empty_state(\"",
	"_caption(\"", "_row(\"", "_labeled(\"", "_help(\"", "_hint(\"", "_chips_card(\"", "_tile(\"", "_add_row_line(\""]


func test_addon_files_load() -> void:
	var paths: PackedStringArray = []
	_collect(ADDON_DIR, paths)
	assert_gt(paths.size(), 15, "files found in %s" % ADDON_DIR)
	for path in paths:
		assert_not_null(load(path), path)


func test_every_text_is_translated() -> void:
	var english: Dictionary = Texts.TEXTS["en"]
	for language in Texts.LANGUAGES:
		var texts: Dictionary = Texts.TEXTS[language]
		for key in english:
			if assert_has(texts, key, "%s: %s" % [language, key]):
				assert_eq(texts[key].count("%"), english[key].count("%"), "%s: %s keeps its placeholders" % [language, key])
		for key in texts:
			assert_has(english, key, "%s: %s exists in English" % [language, key])


func test_text_keys_in_code_exist() -> void:
	var english: Dictionary = Texts.TEXTS["en"]
	var regex: RegEx = RegEx.create_from_string("\"([a-z][a-z0-9_]*)\"")
	for file in DirAccess.get_files_at(ADDON_DIR + "/editor"):
		if file.get_extension() != "gd" or file == "texts.gd" or file == "text_theme.gd":
			continue
		var source: String = FileAccess.get_file_as_string(ADDON_DIR + "/editor/" + file)
		for call in KEY_CALLS:
			var from: int = source.find(call)
			while from >= 0:
				var found: RegExMatch = regex.search(source, from + call.length() - 1)
				# "issue_" + code : un préfixe, pas une clé.
				var prefix: bool = found != null and source.substr(found.get_end(), 2) == " +"
				# get("type") finit aussi par t(" : le nom doit commencer là.
				var before: String = source[from - 1] if from > 0 else " "
				var inside_word: bool = before == "_" or (before.to_lower() != before.to_upper()) or before.is_valid_int()
				if found != null and not inside_word and found.get_start() == from + call.length() - 1 and not prefix:
					assert_true(english.has(found.get_string(1)), "%s: key %s exists in texts.gd" % [file, found.get_string(1)])
				from = source.find(call, from + 1)


func test_tf_ignores_extra_arguments() -> void:
	assert_eq(Texts.tf("issue_no_exit", [2, "village", "n4"]), "Exit 2")
	assert_eq(Texts.tf("overline", ["x"]), "TEXTS")


func _collect(dir: String, out: PackedStringArray) -> void:
	for sub in DirAccess.get_directories_at(dir):
		if dir == ADDON_DIR and sub in SKIPPED_DIRS:
			continue
		_collect(dir.path_join(sub), out)
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() in LOADED_EXTENSIONS:
			out.append(dir.path_join(file))
