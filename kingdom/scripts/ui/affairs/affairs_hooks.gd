extends Node
## The Affairs hooks the HUD owns: ONE 2-second timer (never per frame) that
##   * tells the war-intel digest who is reading (once, and when the role changes),
##   * keeps `unread` (letters) and `envoys` (waiting at the door) for badges,
##   * says a single toast when a letter or envoy arrives (at most one per in-game day),
##   * opens the officer parley dialog when the aura ladder reaches an officer who has arrived (step 2 or more, once per step).
## Gates have no timer: the world calls hud.show_gate_prompt(party, town, extra) when the player reaches one.

const Base := preload("res://scripts/ui/affairs/affairs_base.gd")
const Letters := preload("res://scripts/ui/affairs/letters_panel.gd")
const Parley := preload("res://scripts/ui/affairs/aura_parley_dialog.gd")
const PARLEY_STEP := 2
const INTERVAL := 2.0

static var unread := 0
static var envoys := 0

var hud: CanvasLayer
var realm_override: RefCounted = null
var _timer: Timer
var _role := ""
var _viewer_sid := -1
var _toast_day := -999
var _last_unread := 0
var _last_envoys := 0
var _parley_step := -1
var _parley: Control = null
var _letters: Control = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_letters = Letters.new()
	_letters.set("realm_override", realm_override)
	_timer = Timer.new()
	_timer.wait_time = INTERVAL
	_timer.one_shot = false
	_timer.autostart = true
	_timer.timeout.connect(poll)
	add_child(_timer)


func _hub() -> Variant:
	if realm_override != null:
		return realm_override
	return Life.get("realm") if Life != null else null


func poll() -> void:
	var h: Variant = _hub()
	if h == null:
		return
	var wi: Variant = h.call("mod", "war_intel")
	if wi != null:
		_viewer(h, wi)
		_letters.set("realm_override", realm_override)
		unread = int(_letters.call("unread_count"))
		envoys = (wi.call("envoys", "waiting") as Array).size()
		var day := int(WorldSim.day)
		if (unread > _last_unread or envoys > _last_envoys) and day != _toast_day:
			_toast_day = day
			Game.say("An envoy waits to see you." if envoys > _last_envoys else "A letter has come for you. (%s)" % _key_label("menu_letters"))
		_last_unread = unread
		_last_envoys = envoys
	_check_parley(h)


func _viewer(h: Variant, wi: Variant) -> void:
	var lg: Variant = h.call("mod", "ledger")
	var role := "ruler" if lg != null and String(lg.call("steward_of", "player")) != "" else "adventurer"
	var sid := Base.player_sid()
	if role != _role or sid != _viewer_sid:
		_role = role
		_viewer_sid = sid
		wi.call("set_viewer", "player", sid, role, "player", [sid] if role == "ruler" else [])


func _check_parley(h: Variant) -> void:
	if hud == null or (_parley != null and is_instance_valid(_parley)):
		return
	var af: Variant = h.call("mod", "aura_fallout")
	if af == null:
		return
	var sid := Base.player_sid()
	var lad: Dictionary = af.call("ladder", "player", sid)
	var step := int(lad["step"])
	if step < PARLEY_STEP:
		_parley_step = -1
		return
	if bool(lad["arrived"]) and step != _parley_step:
		_parley_step = step
		_parley = Parley.open(hud, "player", sid, realm_override)


static func _key_label(action: String) -> String:
	if InputMap.has_action(action):
		for ev: InputEvent in InputMap.action_get_events(action):
			if ev is InputEventKey:
				return OS.get_keycode_string((ev as InputEventKey).get_physical_keycode_with_modifiers())
	return "Affairs"
