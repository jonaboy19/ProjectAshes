extends Node
## TalkSession: the world-side of one in-world conversation (docs/design/FOUNDATION_PLAN.md F4).
## Opening the bottom-sheet dialogue starts a session; it
##   - pauses the villager (talk_begin: stops, turns, looks at the player; its schedule is kept) and eases the
##     player's camera to the over-the-shoulder framing (player.set_talk_framing),
##   - ends the talk gracefully when the player walks away (> END_DISTANCE m) or moves the stick / keys,
##   - and resumes the villager and the camera when it ends for any reason (including the menu closing).
## Pure of UI: it takes plain callables, so tests drive it with stubs. VillageServices owns one.
##
## While a full-screen menu (shop, trade) has replaced the sheet the world checks are suspended (`sheet_open`
## false) so stick noise never closes a shop; the villager stays paused until the whole menu closes.

signal ended(reason: String)

const END_DISTANCE := 4.0
const STICK_DEADZONE := 0.3
## A fresh session ignores "menu closed" until the menu has been seen open once (the menu source is asked
## for its first page before the HUD shows it) or this long has passed.
const OPEN_GRACE := 1.0

var player: Node3D
var npc: Node3D
var active := false
var npc_id := ""
## () -> bool, whether any menu is open / whether the conversation sheet itself is the open menu.
var menu_open := Callable()
var sheet_open := Callable()

var _armed := false       # the stick has been neutral since the session began
var _seen_open := false
var _age := 0.0


func begin(p_player: Node3D, p_npc: Node3D, p_menu_open := Callable(), p_sheet_open := Callable(), p_id := "") -> void:
	if active:
		end("restarted")
	player = p_player
	npc = p_npc
	npc_id = p_id
	menu_open = p_menu_open
	sheet_open = p_sheet_open
	active = true
	_armed = false
	_seen_open = false
	_age = 0.0
	if npc != null and is_instance_valid(npc) and npc.has_method("talk_begin"):
		npc.call("talk_begin", player)
	if player != null and is_instance_valid(player) and player.has_method("set_talk_framing"):
		player.call("set_talk_framing", true, npc)


func end(reason := "closed") -> void:
	if not active:
		return
	active = false
	if npc != null and is_instance_valid(npc) and npc.has_method("talk_end"):
		npc.call("talk_end")
	if player != null and is_instance_valid(player) and player.has_method("set_talk_framing"):
		player.call("set_talk_framing", false)
	ended.emit(reason)


## Planar player <-> NPC distance in metres.
func distance() -> float:
	if player == null or npc == null or not is_instance_valid(player) or not is_instance_valid(npc):
		return INF
	var d := npc.global_position - player.global_position
	d.y = 0.0
	return d.length()


## One step. `stick` is the movement input (touch stick + keys). Returns the end reason, or "" while it goes on.
func tick(delta: float, stick: Vector2) -> String:
	if not active:
		return ""
	_age += delta
	var open := not menu_open.is_valid() or bool(menu_open.call())
	if open:
		_seen_open = true
	if not open and (_seen_open or _age > OPEN_GRACE):
		end("closed")
		return "closed"
	if not open:
		return ""
	if npc == null or not is_instance_valid(npc) or player == null or not is_instance_valid(player):
		end("gone")
		return "gone"
	if sheet_open.is_valid() and not bool(sheet_open.call()):
		return ""            # a full-screen menu is up: only its own close ends the talk
	if stick.length() < STICK_DEADZONE:
		_armed = true        # a stick still held from walking up never ends the talk by itself
	elif _armed:
		end("moved")
		return "moved"
	if distance() > END_DISTANCE:
		end("distance")
		return "distance"
	return ""


## The player's movement input: the HUD touch stick plus the move keys / gamepad axes.
static func stick_of(p: Node) -> Vector2:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var t: Variant = p.get("touch_move") if p != null else null
	if t is Vector2:
		v += t
	return v.limit_length(1.0)


func _physics_process(delta: float) -> void:
	if active:
		tick(delta, stick_of(player))
