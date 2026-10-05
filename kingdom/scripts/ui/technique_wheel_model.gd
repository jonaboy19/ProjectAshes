extends RefCounted
## Pure logic of the radial technique wheel (scripts/ui/technique_wheel.gd): which learned techniques get a wedge,
## which wedge a pointer / stick direction is over, and the live numbers for the hub label. No nodes, so it is
## unit tested (tests/test_technique_wheel.gd).
##
## Sources, in priority order, max MAX_WEDGES:
##   1. the equipped loadout slots (skills.loadout),
##   2. every other learned ACTIVE technique of the legacy trees (skills.ranks),
##   3. techniques taught through power_paths (realm hub mod "power_paths" known_techniques), resolved by AbilityLib.
## Wedge 0 sits at 12 o'clock and the rest follow clockwise.

const AbilityLib := preload("res://scripts/abilities/ability_lib.gd")
const AbilityDef := preload("res://scripts/abilities/ability_def.gd")

const MAX_WEDGES := 8
const DEADZONE := 0.3            # of the ring's reach: inside the hub nothing is hovered
const DEFAULT_COLOR := Color("f5b841")
const RESOURCE_NAMES := {"stamina": "stamina", "qi": "qi", "magicules": "magicules", "bending": "focus", "beast": "instinct"}


## Angle (rad, 0 = up, clockwise) at the centre of wedge i of n.
static func wedge_angle(i: int, n: int) -> float:
	return TAU * float(i) / float(maxi(n, 1))


## Wedge under a pointer / stick vector (y down, like screen space). -1 inside the hub or with no wedges.
## `reach` is the vector length that counts as the full ring (so a stick passes 1.0).
static func wedge_at(v: Vector2, n: int, reach := 1.0) -> int:
	if n <= 0 or v.length() < DEADZONE * maxf(reach, 0.001):
		return -1
	var a := fposmod(atan2(v.x, -v.y), TAU)
	var step := TAU / float(n)
	return int(floor((a + step * 0.5) / step)) % n


## Next wedge after i in direction dir (+1 clockwise, -1 counter), wrapping; from "none" it starts at 0 / the last.
static func step_wedge(i: int, dir: int, n: int) -> int:
	if n <= 0:
		return -1
	if i < 0:
		return 0 if dir > 0 else n - 1
	return posmod(i + dir, n)


## Learned active techniques that deserve a wedge (ids, max MAX_WEDGES), loadout first.
static func gather_ids(skills: RefCounted, power_known: Array = []) -> Array[String]:
	var out: Array[String] = []
	if skills != null:
		for id: Variant in skills.loadout:
			var s := String(id)
			if s != "" and not out.has(s) and _active(s):
				out.append(s)
		var rest: Array = skills.ranks.keys()
		rest.sort()
		for id: Variant in rest:
			var s := String(id)
			if not out.has(s) and skills.is_learned(s) and _active(s):
				out.append(s)
	for id: Variant in power_known:
		var s := String(id)
		if not out.has(s) and _active(s):
			out.append(s)
	if out.size() > MAX_WEDGES:
		out.resize(MAX_WEDGES)
	return out


static func _active(id: String) -> bool:
	var d := AbilityLib.get_def(id)
	return not d.is_empty() and String(d.get("kind", "active")) != "passive"


## One wedge's display row, with live cooldown / affordability. `pools` as TechniqueCaster.pools().
## -> {id, name, color, resource, cost, cooldown, left, ready, reason, tier}
static func entry(id: String, skills: RefCounted, pools: Dictionary = {}, left_override := -1.0) -> Dictionary:
	var d := AbilityLib.get_def(id)
	var flat: Dictionary = AbilityDef.flat(d)
	var cost := AbilityDef.primary_cost(d)
	var res := String(cost.get("resource", ""))
	var amount := float(cost.get("amount", 0.0))
	var cd := float(d.get("cooldown", flat.get("cooldown", 0.0)))
	var left := left_override
	var legacy: bool = skills != null and skills.techniques.has(id)
	if legacy:
		res = String(skills.get_def(id).get("resource", res))
		amount = skills.cost_of(id)
		cd = skills.cooldown_of(id)
		if left < 0.0:
			left = skills.cooldown_left(id)
	left = maxf(left, 0.0)
	var color := DEFAULT_COLOR
	if legacy:
		color = skills.color_of(id)
	var have := INF
	if res == "qi" and skills != null:
		have = skills.qi
	elif pools.has(res):
		have = float(pools[res])
	var reason := ""
	if left > 0.0:
		reason = "%.1fs" % left if left < 10.0 else "%ds" % int(ceil(left))
	elif have + 0.001 < amount:
		reason = "Not enough %s" % String(RESOURCE_NAMES.get(res, res))
	return {"id": id, "name": String(d.get("name", id)), "color": color, "resource": res, "cost": amount,
		"cooldown": cd, "left": left, "ready": reason == "", "reason": reason, "tier": int(d.get("tier", 1))}


## Hub text for an entry: {name, cost, state}. `cost` is "14 magicules" / "Free"; `state` is "Ready", "2.3s" or why not.
static func hub_lines(e: Dictionary) -> Dictionary:
	if e.is_empty():
		return {"name": "Techniques", "cost": "", "state": "Choose one"}
	var amount := float(e.get("cost", 0.0))
	var res := String(RESOURCE_NAMES.get(String(e.get("resource", "")), String(e.get("resource", ""))))
	var cost := "Free" if amount <= 0.0 else "%d %s" % [int(round(amount)), res]
	var state := "Ready" if bool(e.get("ready", false)) else String(e.get("reason", ""))
	if bool(e.get("ready", false)) and float(e.get("cooldown", 0.0)) > 0.0:
		state = "Ready  ·  %.1fs recharge" % float(e["cooldown"])
	elif float(e.get("left", 0.0)) > 0.0:
		state = "Recharging  %s" % String(e.get("reason", ""))
	return {"name": String(e.get("name", "")), "cost": cost, "state": state}


## Slow-time rule shared by the wheel and its tests: the scale to hold while open (1.0 = no slow).
static func slow_scale(enabled: bool, blocked: bool) -> float:
	return 1.0 if (not enabled or blocked) else 0.2
