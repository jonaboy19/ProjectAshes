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


## Back to a fresh new game (Flow.reset_world_state via Life.reset).
func reset() -> void:
	gold = 40
	rank = 0
	renown = 0
	merit = 0
	stats_changed.emit()


func serialize() -> Dictionary:
	return {"gold": gold, "rank": rank, "renown": renown, "merit": merit}


func deserialize(d: Dictionary) -> void:
	gold = int(d.get("gold", gold))
	rank = int(d.get("rank", rank))
	renown = int(d.get("renown", renown))
	merit = int(d.get("merit", merit))
	stats_changed.emit()


## THE default input map (docs/controls.md). Every keyboard / mouse / gamepad default lives here so no
## two actions share a key and "Reset controls" (InputMap.load_from_project_settings + _setup_input)
## brings back every action, including those other scripts only add when missing. While a menu is
## open it owns the keyboard, so its page-local keys never compete with these.
const KEYS := {
	"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT], "attack": [KEY_J], "block": [KEY_L], "interact": [KEY_E],
	"view_cycle": [KEY_V], "zoom_in": [KEY_EQUAL], "zoom_out": [KEY_MINUS],
	"dodge": [KEY_SPACE], "eat": [KEY_F], "quick_save": [KEY_F5], "quick_load": [KEY_F9],
	"journal": [KEY_TAB], "menu_inventory": [KEY_I], "menu_skills": [KEY_K],
	"world_map": [KEY_M], "photo_mode": [KEY_P],
	"lock_on": [KEY_Q], "crouch": [KEY_C], "ability_dash": [KEY_R],
	"order_follow": [KEY_1], "order_hold": [KEY_2], "order_charge": [KEY_3],
	"order_retreat": [KEY_G], "order_formation": [KEY_B],
	"technique_1": [KEY_U], "technique_2": [KEY_Y], "technique_3": [KEY_O], "technique_4": [KEY_H],
	"seal_1": [KEY_4], "seal_2": [KEY_5], "seal_3": [KEY_6], "seal_4": [KEY_7], "seal_5": [KEY_8], "seal_6": [KEY_9],
}
## Mouse and gamepad defaults: action -> [[mouse buttons], [joypad buttons]].
const PADS := {
	"zoom_in": [[MOUSE_BUTTON_WHEEL_UP], []], "zoom_out": [[MOUSE_BUTTON_WHEEL_DOWN], []],
	"lock_on": [[MOUSE_BUTTON_MIDDLE], [JOY_BUTTON_RIGHT_STICK]],
	"crouch": [[], [JOY_BUTTON_LEFT_STICK]], "ability_dash": [[], [JOY_BUTTON_LEFT_SHOULDER]],
}


func _setup_input() -> void:
	for action: String in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		else:
			InputMap.action_erase_events(action)
		for key: Key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
		var extra: Array = PADS.get(action, [[], []])
		for b: int in extra[0]:
			var mb := InputEventMouseButton.new()
			mb.button_index = b
			InputMap.action_add_event(action, mb)
		for b: int in extra[1]:
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			InputMap.action_add_event(action, jb)
	# The legacy skills screen has no key of its own: K opens the Skills tab of the Pack menu.
	if not InputMap.has_action("skills_screen"):
		InputMap.add_action("skills_screen")
