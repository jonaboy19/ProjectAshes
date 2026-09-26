extends Node
## Global game state: story flags, counters, the player's blessing, save/load
## and the input map (registered in code so it lives in version control).

signal flag_changed(flag: String, value: Variant)
signal toast_requested(text: String)

const SAVE_PATH := "user://save.json"

var flags: Dictionary = {}
## Empty string = unblessed. Sugo starts the story without a blessing.
var player_blessing: String = ""
var blessings: Dictionary = {}


func _ready() -> void:
	_setup_input()
	blessings = load_json("res://data/blessings.json")


func set_flag(flag: String, value: Variant = true) -> void:
	flags[flag] = value
	flag_changed.emit(flag, value)


func get_flag(flag: String, default: Variant = false) -> Variant:
	return flags.get(flag, default)


func add_to_counter(counter: String, amount: int = 1) -> int:
	var total: int = int(flags.get(counter, 0)) + amount
	set_flag(counter, total)
	return total


func toast(text: String) -> void:
	toast_requested.emit(text)


func save_game(extra: Dictionary = {}) -> void:
	var data := {"flags": flags, "blessing": player_blessing, "quests": Quests.serialize()}
	data.merge(extra, true)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))


func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	flags = parsed.get("flags", {})
	player_blessing = parsed.get("blessing", "")
	Quests.deserialize(parsed.get("quests", {}))
	return parsed


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing data file: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid JSON in %s" % path)
		return {}
	return parsed


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT],
		"dodge": [KEY_SPACE],
		"attack": [KEY_J],
		"blessing": [KEY_K],
		"interact": [KEY_E],
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: Key in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
