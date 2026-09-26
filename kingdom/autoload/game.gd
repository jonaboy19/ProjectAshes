extends Node
## Player-facing state: gold, rank progression, messages and the input map.

signal toast(text: String)
signal stats_changed

const RANKS := [
	{"name": "Peasant",   "max_soldiers": 0},
	{"name": "Militia",   "max_soldiers": 12},
	{"name": "Sergeant",  "max_soldiers": 24},
	{"name": "Captain",   "max_soldiers": 48},
	{"name": "Commander", "max_soldiers": 96},
	{"name": "Lord",      "max_soldiers": 200},
	{"name": "King",      "max_soldiers": 1000},
]
const RECRUIT_COST := 20

var gold := 40
var rank := 0
var renown := 0
## War Merit: earned by deeds (monsters slain, raids broken). Opens senior seats.
var merit := 0


func _ready() -> void:
	_setup_input()


func rank_name() -> String:
	return RANKS[rank]["name"]


func max_soldiers() -> int:
	return RANKS[rank]["max_soldiers"]


func add_gold(amount: int) -> void:
	gold += amount
	stats_changed.emit()


func promote() -> void:
	if rank < RANKS.size() - 1:
		rank += 1
		toast.emit("Promoted to %s. You may lead %d soldiers." % [rank_name(), max_soldiers()])
		stats_changed.emit()


func say(text: String) -> void:
	toast.emit(text)


func serialize() -> Dictionary:
	return {"gold": gold, "rank": rank, "renown": renown, "merit": merit}


func deserialize(d: Dictionary) -> void:
	gold = int(d.get("gold", gold))
	rank = int(d.get("rank", rank))
	renown = int(d.get("renown", renown))
	merit = int(d.get("merit", merit))
	stats_changed.emit()


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT], "attack": [KEY_J], "block": [KEY_L], "interact": [KEY_E],
		"view_cycle": [KEY_V], "zoom_in": [KEY_EQUAL], "zoom_out": [KEY_MINUS],
		"dodge": [KEY_SPACE], "eat": [KEY_F], "quick_save": [KEY_F5], "quick_load": [KEY_F9], "journal": [KEY_TAB], "order_follow": [KEY_1], "order_hold": [KEY_2], "order_charge": [KEY_3],
	}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: Key in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	for pair in [["zoom_in", MOUSE_BUTTON_WHEEL_UP], ["zoom_out", MOUSE_BUTTON_WHEEL_DOWN]]:
		var mb := InputEventMouseButton.new()
		mb.button_index = pair[1]
		InputMap.action_add_event(pair[0], mb)
