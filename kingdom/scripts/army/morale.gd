extends RefCounted
## Unit morale, 0..100. One per squad, updated on the squad's slow tick.
##
## Morale drifts toward a target built from the situation: the unit's base
## steadiness minus losses (total and recent), being flanked or taken in the
## rear (weighted by how exposed the formation's sides are), being outnumbered,
## and horse bearing down on a formation that can't stop it; plus officers in
## earshot and the cohesion of a tight formation. It falls fast and recovers
## slowly.
##
##   STEADY    fights normally
##   WAVERING  below WAVER_AT: still fights, the banner greys
##   ROUTED    at BREAK_AT or below: the men throw off the formation and run.
##             Once no enemy is within SAFE_DISTANCE they recover and, back at
##             RALLY_AT, rally and re-form. Each rally leaves them jumpier.
##   SHATTERED lost SHATTER_LOSSES of their strength: runs and only rallies to
##             an officer standing among them.

enum State { STEADY, WAVERING, ROUTED, SHATTERED }

const STATE_NAMES := ["Steady", "Wavering", "Routed", "Shattered"]

const WAVER_AT := 35.0
const BREAK_AT := 15.0
const RALLY_AT := 40.0
const SHATTER_LOSSES := 0.8
## Per unit of loss ratio (0..1): half the men dead costs 50 points.
const CASUALTY_WEIGHT := 100.0
## Per unit of recent-loss ratio: men falling fast shock more than slow attrition.
const SHOCK_WEIGHT := 45.0
## Per share of nearby enemies on a flank / in the rear, times exposure.
const FLANK_WEIGHT := 22.0
const REAR_WEIGHT := 32.0
## Per extra enemy per man (2:1 costs 12), capped.
const OUTNUMBER_WEIGHT := 12.0
const OUTNUMBER_CAP := 30.0
## Enemy horse against a formation with no anti-cavalry answer.
const CAVALRY_WEIGHT := 15.0
const OFFICER_CAP := 25.0
const CHARGE_BONUS := 5.0
## Each rally lowers the unit's base by this much.
const RALLY_PENALTY := 10.0
const FALL_RATE := 14.0      # points per second
const RISE_RATE := 3.0
const ROUT_RECOVER := 4.0
const MIN_ROUT_TIME := 8.0
const SAFE_DISTANCE := 22.0

var value := 70.0
var state := State.STEADY
var rallies := 0
var rout_time := 0.0
## Losses when the unit last rallied: a shattered unit that rallied to an
## officer only shatters again if it keeps losing men.
var rally_losses := 0.0


func _init(start := 70.0) -> void:
	value = start


## The morale a situation pulls toward. Keys (all optional):
##   base        unit steadiness (70)
##   casualties  share of peak strength lost, 0..1
##   shock       share lost in the last few seconds, 0..1
##   flank, rear share of nearby enemies on the flanks / behind, 0..1
##   exposure_flank, exposure_rear   formation exposure (1 = line)
##   outnumber   enemies near / own men
##   cavalry     share of nearby enemies that are horse, 0..1
##   anti_cav    how well formation and troop type stop horse, 0..1+
##   officer     steadying from officers present (points)
##   cohesion    formation morale bonus (points)
##   charging    true while charging
##   rallies     times already rallied
static func target(inp: Dictionary) -> float:
	var t := float(inp.get("base", 70.0))
	t -= float(inp.get("casualties", 0.0)) * CASUALTY_WEIGHT
	t -= float(inp.get("shock", 0.0)) * SHOCK_WEIGHT
	t -= float(inp.get("flank", 0.0)) * FLANK_WEIGHT * float(inp.get("exposure_flank", 1.0))
	t -= float(inp.get("rear", 0.0)) * REAR_WEIGHT * float(inp.get("exposure_rear", 1.3))
	t -= clampf((float(inp.get("outnumber", 1.0)) - 1.0) * OUTNUMBER_WEIGHT, 0.0, OUTNUMBER_CAP)
	t -= float(inp.get("cavalry", 0.0)) * CAVALRY_WEIGHT * maxf(0.0, 1.0 - float(inp.get("anti_cav", 0.0)))
	t += minf(float(inp.get("officer", 0.0)), OFFICER_CAP)
	t += float(inp.get("cohesion", 0.0))
	if inp.get("charging", false):
		t += CHARGE_BONUS
	t -= int(inp.get("rallies", 0)) * RALLY_PENALTY
	return clampf(t, 0.0, 100.0)


## Whether this situation, held long enough, breaks the unit.
static func breaks(inp: Dictionary) -> bool:
	return float(inp.get("casualties", 0.0)) >= SHATTER_LOSSES or target(inp) <= BREAK_AT


static func state_for(v: float) -> int:
	if v <= BREAK_AT:
		return State.ROUTED
	if v < WAVER_AT:
		return State.WAVERING
	return State.STEADY


func is_broken() -> bool:
	return state == State.ROUTED or state == State.SHATTERED


func state_name() -> String:
	return STATE_NAMES[state]


## Advance by dt seconds. pursued: an enemy is within SAFE_DISTANCE.
## officer_among: an officer is standing with the routers (lets even a
## shattered unit rally). Returns true when the state changed.
func update(dt: float, inp: Dictionary, pursued: bool, officer_among := false) -> bool:
	var before := state
	var inp2 := inp.duplicate()
	inp2["rallies"] = rallies
	var goal := target(inp2)
	var losses := float(inp.get("casualties", 0.0))
	if is_broken():
		rout_time += dt
		if _shattering(losses):
			state = State.SHATTERED
		if pursued:
			value = move_toward(value, minf(value, BREAK_AT), FALL_RATE * dt)
		else:
			# Out of reach the flanking and numbers no longer bite, and the
			# survivors regroup around those still standing: losses count half.
			var calm := inp2.duplicate()
			for k in ["flank", "rear", "outnumber", "cavalry", "shock", "charging"]:
				calm.erase(k)
			calm["casualties"] = losses * 0.5
			value = move_toward(value, target(calm), ROUT_RECOVER * dt)
		var may_rally := state == State.ROUTED or officer_among
		if may_rally and not pursued and rout_time >= MIN_ROUT_TIME and value >= RALLY_AT:
			state = State.STEADY
			rallies += 1
			rally_losses = losses
			value = RALLY_AT + 5.0
	else:
		value = move_toward(value, goal, (FALL_RATE if goal < value else RISE_RATE) * dt)
		if _shattering(losses):
			state = State.SHATTERED
		else:
			state = state_for(value)
		if is_broken():
			rout_time = 0.0
	return state != before


func _shattering(losses: float) -> bool:
	return losses >= SHATTER_LOSSES and losses > rally_losses + 0.05


func serialize() -> Dictionary:
	return {"value": value, "state": state, "rallies": rallies, "rally_losses": rally_losses}


func deserialize(d: Dictionary) -> void:
	value = float(d.get("value", value))
	state = int(d.get("state", state))
	rallies = int(d.get("rallies", rallies))
	rally_losses = float(d.get("rally_losses", rally_losses))
