extends TestCase

## Dialogues (core/dialogue_data.gd) et lecteur du jeu
## (runtime/dialogue_runner.gd, DialogueRunner) : nœuds, liens, déroulé
## narratif, conditions, variables, événements, sauts, boucle sans fin.

const Fixtures = preload("res://addons/text_editor/tests/fixtures.gd")
const DialogueData = preload("res://addons/text_editor/core/dialogue_data.gd")
const Tokens = preload("res://addons/text_editor/runtime/text_tokens.gd")

const TEXTS: Dictionary = {"DLG_HELLO": "Hello, traveller.", "DLG_ASK": "Tell me about the merchant.",
	"DLG_LEAVE": "Goodbye.", "DLG_HERE": "He is right here.", "CHAR_MERCHANT": "Merchant", "DLG_PRESS": "Press {INTERACT_BUTTON}."}


func _runner(dialogue: Dictionary) -> DialogueRunner:
	var runner: DialogueRunner = DialogueRunner.new()
	runner.dialogue = DialogueData.for_game(dialogue, {"merchant": {"name_key": "CHAR_MERCHANT", "color": "#e0a040"}})
	runner.translate = func(key: String) -> String: return TEXTS.get(key, key)
	return runner


func test_create_has_start_and_end() -> void:
	var dialogue: Dictionary = DialogueData.create()
	assert_eq(dialogue["nodes"].size(), 2)
	assert_eq(DialogueData.start_ids(dialogue), PackedStringArray(["n1"]))
	assert_eq(DialogueData.target(dialogue, "n1", 0), "n2")


func test_ports_per_type() -> void:
	assert_eq(DialogueData.ports(DialogueData.new_node(DialogueData.LINE)), 1)
	assert_eq(DialogueData.ports(DialogueData.new_node(DialogueData.CONDITION)), 2)
	assert_eq(DialogueData.ports(DialogueData.new_node(DialogueData.END)), 0)
	assert_eq(DialogueData.ports(DialogueData.new_node(DialogueData.JUMP)), 0)
	var branch: Dictionary = DialogueData.new_node(DialogueData.BRANCH)
	branch["conditions"] = ["a", "b"]
	assert_eq(DialogueData.ports(branch), 3, "one per condition + else")


func test_connect_rules() -> void:
	var dialogue: Dictionary = Fixtures.village()
	assert_false(DialogueData.connect_nodes(dialogue, "n2", 0, "n1"), "nothing goes into START")
	assert_false(DialogueData.connect_nodes(dialogue, "n2", 3, "n5"), "no such port")
	assert_true(DialogueData.connect_nodes(dialogue, "n2", 0, "n5"))
	assert_eq(DialogueData.target(dialogue, "n2", 0), "n5", "one link per port: replaced")
	DialogueData.remove_node(dialogue, "n5")
	for link in dialogue["links"]:
		assert_ne(link[2], "n5", "links to a removed node are removed")


func test_node_ids_stay_stable() -> void:
	var dialogue: Dictionary = Fixtures.village()
	DialogueData.remove_node(dialogue, "n5")
	var id: String = DialogueData.add_node(dialogue, DialogueData.END, Vector2.ZERO)
	assert_eq(id, "n6", "a removed id is not reused")


func test_narrative_walk() -> void:
	var items: Array = DialogueData.narrative(Fixtures.village())
	var ids: Array = []
	for item in items:
		ids.append(item["id"])
	assert_eq(ids, ["n1", "n2", "n3", "n4", "n5", "n5"])
	assert_true(items[5]["repeat"], "END reached twice: second is a reference")
	assert_eq(items[3]["port_label"], "0")
	assert_eq(items[3]["depth"], 1)


func test_runner_plays_choices() -> void:
	var runner: DialogueRunner = _runner(Fixtures.village())
	var step: Dictionary = runner.start()
	assert_eq(step["type"], "line")
	assert_eq(step["text"], "Hello, traveller.")
	assert_eq(step["speaker_name"], "Merchant")
	assert_eq(step["color"], "#e0a040")
	step = runner.next()
	assert_eq(step["type"], "choice")
	assert_eq(step["options"].size(), 2)
	step = runner.choose(0)
	assert_eq(step["text_key"], "DLG_HERE")
	assert_eq(runner.next()["type"], "end")
	runner.start()
	runner.next()
	assert_eq(runner.choose(1)["type"], "end", "leave")


func test_runner_conditions_variables_events_jumps() -> void:
	var dialogue: Dictionary = {"nodes": {}, "links": [], "next_id": 1}
	var start: String = DialogueData.add_node(dialogue, DialogueData.START, Vector2.ZERO)
	var check: String = DialogueData.add_node(dialogue, DialogueData.VARIABLE_CHECK, Vector2.ZERO)
	dialogue["nodes"][check].merge({"variable": "gold", "operator": ">=", "value": "10"}, true)
	var event: String = DialogueData.add_node(dialogue, DialogueData.EVENT, Vector2.ZERO)
	dialogue["nodes"][event].merge({"name": "give_item", "args": "sword"}, true)
	var rich: String = DialogueData.add_node(dialogue, DialogueData.LINE, Vector2.ZERO)
	dialogue["nodes"][rich]["text_key"] = "DLG_HERE"
	var condition: String = DialogueData.add_node(dialogue, DialogueData.CONDITION, Vector2.ZERO)
	dialogue["nodes"][condition]["expression"] = "!met"
	var jump: String = DialogueData.add_node(dialogue, DialogueData.JUMP, Vector2.ZERO)
	dialogue["nodes"][jump]["target"] = rich
	var poor: String = DialogueData.add_node(dialogue, DialogueData.LINE, Vector2.ZERO)
	dialogue["nodes"][poor]["text_key"] = "DLG_LEAVE"
	var finish: String = DialogueData.add_node(dialogue, DialogueData.END, Vector2.ZERO)
	DialogueData.connect_nodes(dialogue, start, 0, check)
	DialogueData.connect_nodes(dialogue, check, 0, event)
	DialogueData.connect_nodes(dialogue, check, 1, condition)
	DialogueData.connect_nodes(dialogue, event, 0, rich)
	DialogueData.connect_nodes(dialogue, condition, 0, jump)
	DialogueData.connect_nodes(dialogue, condition, 1, poor)
	DialogueData.connect_nodes(dialogue, rich, 0, finish)
	DialogueData.connect_nodes(dialogue, poor, 0, finish)
	var runner: DialogueRunner = _runner(dialogue)
	var events: Array = []
	runner.event_handler = func(name: String, args: String) -> void: events.append([name, args])
	runner.variables = {"gold": 12}
	assert_eq(runner.start()["text_key"], "DLG_HERE", "rich path")
	assert_eq(events, [["give_item", "sword"]])
	runner.variables = {"gold": 3, "met": false}
	assert_eq(runner.start()["text_key"], "DLG_HERE", "poor, not met: jump")
	runner.variables = {"gold": 3, "met": true}
	assert_eq(runner.start()["text_key"], "DLG_LEAVE")
	runner.condition_handler = func(_expression: String) -> bool: return false
	assert_eq(runner.start()["text_key"], "DLG_LEAVE", "handler decides")


func test_runner_choice_conditions() -> void:
	var dialogue: Dictionary = Fixtures.village()
	dialogue["nodes"]["n3"]["options"][0]["condition"] = "knows_merchant"
	var runner: DialogueRunner = _runner(dialogue)
	runner.start()
	var step: Dictionary = runner.next()
	assert_eq(step["options"].size(), 1, "hidden option")
	assert_eq(step["options"][0]["index"], 1, "index of the original option")
	assert_eq(runner.choose(1)["type"], "end")


func test_runner_stops_infinite_loop() -> void:
	var dialogue: Dictionary = {"nodes": {}, "links": [], "next_id": 1}
	var start: String = DialogueData.add_node(dialogue, DialogueData.START, Vector2.ZERO)
	var a: String = DialogueData.add_node(dialogue, DialogueData.EVENT, Vector2.ZERO)
	var b: String = DialogueData.add_node(dialogue, DialogueData.EVENT, Vector2.ZERO)
	DialogueData.connect_nodes(dialogue, start, 0, a)
	DialogueData.connect_nodes(dialogue, a, 0, b)
	DialogueData.connect_nodes(dialogue, b, 0, a)
	var step: Dictionary = _runner(dialogue).start()
	assert_eq(step["type"], "end")
	assert_eq(step["error"], "loop")


func test_runner_tokens_and_load_file() -> void:
	var dialogue: Dictionary = {"nodes": {}, "links": [], "next_id": 1}
	var start: String = DialogueData.add_node(dialogue, DialogueData.START, Vector2.ZERO)
	var line: String = DialogueData.add_node(dialogue, DialogueData.LINE, Vector2.ZERO)
	dialogue["nodes"][line]["text_key"] = "DLG_PRESS"
	DialogueData.connect_nodes(dialogue, start, 0, line)
	var path: String = Fixtures.fresh_dir("runner") + "/d.json"
	Fixtures.write(path, JSON.stringify(DialogueData.for_game(dialogue, {})))
	var runner: DialogueRunner = DialogueRunner.load_file(path)
	runner.translate = func(key: String) -> String: return TEXTS.get(key, key)
	runner.tokens = Tokens.for_platform({"INTERACT_BUTTON": {"pc": "E", "xbox": "A"}}, "xbox")
	assert_eq(runner.start()["text"], "Press A.")
	assert_eq(runner.next()["type"], "end", "unlinked exit ends the dialogue")


func test_tokens() -> void:
	assert_eq(Tokens.find("{B} and {A} and {B}, {lower}"), PackedStringArray(["A", "B"]))
	assert_eq(Tokens.fill("Press {X} or {Y}", {"X": "E"}), "Press E or {Y}", "unknown token kept")
	var values: Dictionary = Tokens.for_platform({"X": {"pc": "E", "default": "?"}}, "switch")
	assert_eq(values["X"], "?", "default value")
