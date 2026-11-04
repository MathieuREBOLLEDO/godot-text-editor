@tool
extends RefCounted

## Différence mot à mot entre deux versions d'un texte (comparaison de
## traductions). Résultat : [[op, morceau], ...] avec op = 0 (commun),
## -1 (retiré de a), 1 (ajouté dans b). Les espaces restent collées au mot
## qui les suit, pour pouvoir recoller le texte.

const SAME: int = 0
const REMOVED: int = -1
const ADDED: int = 1


static func words(text: String) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var current: String = ""
	for character in text:
		if (character == " " or character == "\n" or character == "\t") and not current.strip_edges().is_empty():
			result.append(current)
			current = ""
		current += character
	if not current.is_empty():
		result.append(current)
	return result


static func diff(a: String, b: String) -> Array:
	var left: PackedStringArray = words(a)
	var right: PackedStringArray = words(b)
	# Plus longue sous-suite commune (textes courts : table complète).
	var rows: int = left.size() + 1
	var columns: int = right.size() + 1
	var table: PackedInt32Array = PackedInt32Array()
	table.resize(rows * columns)
	for i in range(left.size() - 1, -1, -1):
		for j in range(right.size() - 1, -1, -1):
			if left[i] == right[j]:
				table[i * columns + j] = table[(i + 1) * columns + j + 1] + 1
			else:
				table[i * columns + j] = maxi(table[(i + 1) * columns + j], table[i * columns + j + 1])
	var result: Array = []
	var i: int = 0
	var j: int = 0
	while i < left.size() and j < right.size():
		if left[i] == right[j]:
			_push(result, SAME, left[i])
			i += 1
			j += 1
		elif table[(i + 1) * columns + j] >= table[i * columns + j + 1]:
			_push(result, REMOVED, left[i])
			i += 1
		else:
			_push(result, ADDED, right[j])
			j += 1
	while i < left.size():
		_push(result, REMOVED, left[i])
		i += 1
	while j < right.size():
		_push(result, ADDED, right[j])
		j += 1
	return result


## BBCode pour un RichTextLabel : retiré barré dans [param removed], ajouté
## souligné dans [param added].
static func to_bbcode(parts: Array, removed: Color, added: Color) -> String:
	var text: String = ""
	for part in parts:
		var escaped: String = String(part[1]).replace("[", "[lb]")
		match int(part[0]):
			REMOVED:
				text += "[color=#%s][s]%s[/s][/color]" % [removed.to_html(false), escaped]
			ADDED:
				text += "[color=#%s][u]%s[/u][/color]" % [added.to_html(false), escaped]
			_:
				text += escaped
	return text


static func _push(result: Array, op: int, word: String) -> void:
	if not result.is_empty() and result.back()[0] == op:
		result.back()[1] += word
	else:
		result.append([op, word])
