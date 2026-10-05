extends RefCounted
## The player's knockdown as a pure state machine (no scene access): FALL -> DOWN -> GETUP -> NONE, with brief
## i-frames on get-up, a dodge-roll get-up from the down state, and a cooldown so a pack cannot chain-floor the
## player. Durations and thresholds: data/combat/player_weapons.json "knockdown" (via weapon_rules.gd).
## player_arms.gd drives it and plays the clips; the ragdoll path is only used when the data enables it.

const WeaponRules := preload("res://scripts/combat/weapon_rules.gd")

enum S { NONE, FALL, DOWN, GETUP }
const NAMES := ["none", "fall", "down", "getup"]

var state := S.NONE
var t := 0.0                  ## seconds spent in the current state
var kind := ""                ## "fall" or "ragdoll"
var iframes := 0.0            ## seconds of invulnerability left (get-up or roll)
var cooldown := 0.0           ## no new knockdown until this runs out
var roll_queued := false      ## dodge pressed while still falling: roll the moment the body is down


func is_active() -> bool:
	return state != S.NONE


func is_down() -> bool:
	return state == S.FALL or state == S.DOWN


func invulnerable() -> bool:
	return iframes > 0.0


## Starts a knockdown when the blow clears the thresholds and none is running. Returns the kind or "".
func try_begin(poise_damage: float, knockback: float) -> String:
	if state != S.NONE or cooldown > 0.0:
		return ""
	var k := WeaponRules.knockdown_kind(poise_damage, knockback)
	if k == "":
		return ""
	state = S.FALL
	t = 0.0
	kind = k
	roll_queued = false
	return k


## Seconds the whole fall + down + get-up takes (the player's stun budget).
static func total_time() -> float:
	var k := WeaponRules.cfg("knockdown")
	return float(k["fall_time"]) + float(k["down_time"]) + float(k["getup_time"])


## Advances the machine. Returns "" or the event that just happened: "down", "getup", "done".
func tick(delta: float) -> String:
	iframes = maxf(iframes - delta, 0.0)
	cooldown = maxf(cooldown - delta, 0.0)
	if state == S.NONE:
		return ""
	var k := WeaponRules.cfg("knockdown")
	t += delta
	match state:
		S.FALL:
			if t >= float(k["fall_time"]):
				state = S.DOWN
				t = 0.0
				return "down"
		S.DOWN:
			if t >= float(k["down_time"]):
				state = S.GETUP
				t = 0.0
				iframes = float(k["getup_iframes"])
				return "getup"
		S.GETUP:
			if t >= float(k["getup_time"]):
				state = S.NONE
				t = 0.0
				cooldown = float(k["cooldown"])
				return "done"
	return ""


## Dodge pressed while floored. "roll" = get up through a roll now (the caller plays the roll, spends stamina);
## "queued" = still falling, the roll fires when the body is down; "" = nothing to do.
func dodge_pressed() -> String:
	if state == S.FALL:
		roll_queued = true
		return "queued"
	if state != S.DOWN:
		return ""
	if t < float(WeaponRules.cfg("knockdown")["roll_min_down"]):
		return ""
	return _roll()


## True once the queued roll may fire (the fall finished).
func take_queued_roll() -> bool:
	if roll_queued and state == S.DOWN:
		roll_queued = false
		return not _roll().is_empty()
	return false


func _roll() -> String:
	state = S.NONE
	t = 0.0
	iframes = float(WeaponRules.cfg("knockdown")["roll_iframes"])
	cooldown = float(WeaponRules.cfg("knockdown")["cooldown"])
	return "roll"


func reset() -> void:
	state = S.NONE
	t = 0.0
	iframes = 0.0
	roll_queued = false
