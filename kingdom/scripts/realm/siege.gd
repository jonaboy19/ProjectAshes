extends RefCounted
## Sieges (docs/design/WAR_COMMAND_RULEBOOK.md §41-47): a siege is its own small strategic game played in days.
## One instance per besieged stronghold or town. Pure data, deterministic, JSON safe (state dictionary `s`).
## Walls, gates, towers, garrison, food, water, morale and civilians on one side; camp, engineers, engines and
## patience on the other. Breaches open new tactical points with inner defence lines behind them (R§45); the assault
## is fought on a real battlefield (tactical.gd, fed by assault_spec) or auto-resolved with the same code.

const WarUnits := preload("res://scripts/realm/war_units.gd")
const Tactical := preload("res://scripts/realm/tactical.gd")

const VERSION := 1
## Engines (R§44). days: build time with `eng` engineers on hand; wood: timber units; dmg: share of wall hp per day.
const ENGINES := {
	"ladders": {"name": "Scaling ladders", "days": 1.0, "wood": 4.0, "eng": 10, "dmg": 0.0, "vs": "escalade", "tech": 0},
	"ram": {"name": "Battering ram", "days": 3.0, "wood": 10.0, "eng": 20, "dmg": 0.22, "vs": "gate", "tech": 0},
	"tower": {"name": "Siege tower", "days": 6.0, "wood": 20.0, "eng": 40, "dmg": 0.0, "vs": "landing", "tech": 1},
	"catapult": {"name": "Catapult", "days": 5.0, "wood": 14.0, "eng": 30, "dmg": 0.09, "vs": "wall", "tech": 1},
	"ballista": {"name": "Ballista", "days": 3.0, "wood": 8.0, "eng": 15, "dmg": 0.0, "vs": "men", "tech": 0},
	"trebuchet": {"name": "Trebuchet", "days": 10.0, "wood": 28.0, "eng": 50, "dmg": 0.15, "vs": "wall", "tech": 2},
	"mage_artillery": {"name": "Mage artillery", "days": 4.0, "wood": 0.0, "eng": 10, "dmg": 0.12, "vs": "wall", "tech": 3},
}
const ENGINE_ORDER := ["ladders", "ram", "tower", "catapult", "ballista", "trebuchet", "mage_artillery"]
## Approaches (R§42).
const APPROACHES := ["starve", "bombard", "ladders", "undermine", "gate_assault", "infiltrate", "bribe", "cut_water", "poison", "negotiate"]
const APPROACH_NAMES := {"starve": "Surround and starve", "bombard": "Bombard the walls", "ladders": "Escalade with ladders", "undermine": "Undermine the wall",
	"gate_assault": "Assault the gate", "infiltrate": "Infiltrate agents", "bribe": "Bribe someone inside", "cut_water": "Cut the water", "poison": "Poison supplies", "negotiate": "Negotiate surrender"}
## Street-fighting layers (R§46) by stronghold kind.
const LAYERS := {
	"castle": ["Outer wall", "Courtyard", "Inner ward", "Keep"],
	"town": ["Town wall", "Streets", "Market square", "Inner wall"],
	"frontier_town": ["Palisade wall", "Streets", "Market square"],
	"fort": ["Wall", "Yard", "Keep"],
	"watchfort": ["Wall", "Keep"],
	"village": ["Palisade", "Lanes"],
	"default": ["Wall", "Streets", "Keep"],
}
const SURRENDER_BASE := 0.55
const PERS_STUBBORN := {"stubborn": 0.28, "loyal": 0.16, "aggressive": 0.2, "cautious": -0.1, "ambitious": 0.02, "inventive": 0.05, "independent": 0.0}

var s: Dictionary = {}


static func _hash(a: int, b: int, c: int) -> float:
	var x: int = (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	x = (x ^ (x >> 13)) * 1274126177
	x = x ^ (x >> 16)
	return float(x & 0xFFFF) / 65536.0


## spec: {key, name, pos: [x, y], kind, defender, attacker, garrison, food_days, water_days, well, civilians, wall_age (0..1),
##   wall_radius, gates: [angles], commander: {name, personality}, camp: {engineers, guards, medical, mages, men}, tech (0..3),
##   timber (0..1), att_units: [unit specs], seed}
static func create(spec: Dictionary) -> RefCounted:
	var sg: RefCounted = load("res://scripts/realm/siege.gd").new()
	sg.call("_setup", spec)
	return sg


func _setup(spec: Dictionary) -> void:
	var kind := String(spec.get("kind", "town"))
	var seed_ := int(spec.get("seed", 1))
	var pos: Array = spec.get("pos", [0.0, 0.0])
	var garrison := int(spec.get("garrison", 200))
	var age := clampf(float(spec.get("wall_age", 0.3)), 0.0, 1.0)
	var dirs := [-PI * 0.5, 0.0, PI * 0.5, PI]
	var names := ["North wall", "East wall", "South wall", "West wall"]
	var gates_a: Array = spec.get("gates", [0.0, PI])
	var walls: Array = []
	for i in 4:
		var a2 := clampf(age + (_hash(seed_, i, 3) - 0.5) * 0.5, 0.0, 1.0)
		var mx := 100.0 * (1.25 if kind == "castle" else (1.0 if kind in ["town", "fort", "frontier_town"] else 0.6))
		walls.append({"name": names[i], "dir": dirs[i], "hp": mx, "max": mx, "age": a2, "breach": false, "tower": 1 + int(_hash(seed_, i, 9) * 2.0)})
	var gates: Array = []
	for g in gates_a.size():
		var gd := float(gates_a[g])
		gates.append({"name": "Gate %d" % (g + 1), "dir": gd, "hp": 80.0, "max": 80.0, "open": false, "wall": _wall_for(gd)})
	var cmd: Dictionary = (spec.get("commander", {}) as Dictionary).duplicate(true)
	var camp: Dictionary = spec.get("camp", {})
	var layers: Array = (LAYERS.get(kind, LAYERS["default"]) as Array).duplicate()
	s = {"v": VERSION, "key": String(spec.get("key", "s0")), "name": String(spec.get("name", "Stronghold")), "pos": [float(pos[0]), float(pos[1])], "kind": kind,
		"defender": String(spec.get("defender", "caldrenn")), "attacker": String(spec.get("attacker", "player")), "seed": seed_, "day": 0, "start_day": int(spec.get("day", 0)),
		"walls": walls, "gates": gates, "garrison": garrison, "garrison_max": int(spec.get("garrison_max", garrison)), "food_days": float(spec.get("food_days", 30.0)),
		"water_days": float(spec.get("water_days", 20.0)), "well": bool(spec.get("well", false)), "civilians": int(spec.get("civilians", garrison * 2)),
		"morale": clampf(float(spec.get("morale", 0.7)), 0.0, 1.0), "hope": float(spec.get("hope", 0.3)), "cmd": {"name": String(cmd.get("name", "The Castellan")),
		"personality": String(cmd.get("personality", "loyal"))}, "radius": float(spec.get("wall_radius", 110.0)),
		"camp": {"pos": spec.get("camp_pos", [float(pos[0]) - 190.0, float(pos[1]) + 140.0]), "men": int(camp.get("men", 800)), "engineers": int(camp.get("engineers", 40)),
			"guards": int(camp.get("guards", 120)), "medical": int(camp.get("medical", 20)), "mages": int(camp.get("mages", 0)), "food_days": float(camp.get("food_days", 14.0)),
			"morale": float(camp.get("morale", 0.7)), "disease": 0.0, "workshops": 1, "wood": 60.0 * float(spec.get("timber", 0.6))},
		"tech": int(spec.get("tech", 1)), "timber": clampf(float(spec.get("timber", 0.6)), 0.1, 1.0), "engines": [], "approaches": {}, "tunnel": {"wall": -1, "progress": 0.0, "found": false},
		"inner_lines": 0, "inner_men": 0, "layers": layers, "layer": 0, "status": "active", "log": [], "agents": 0, "gold_spent": 0, "gate_betrayed": false,
		"defence": {"gate": 0, "wall_w": 0, "wall_e": 0, "inner": 0, "reserve": 0}, "structures": {"oil": false, "stakes": true, "barricades": false, "archers": true},
		"att_units": (spec.get("att_units", []) as Array).duplicate(true), "sortie_due": false, "sorties": 0, "surrender": {}, "conduct": "", "plan": []}
	auto_assign()
	_rebuild_plan()


func _wall_for(dir: float) -> int:
	var best := 0
	var bd := 9.0
	for i in 4:
		var d := absf(wrapf(dir - [-PI * 0.5, 0.0, PI * 0.5, PI][i], -PI, PI))
		if d < bd:
			bd = d
			best = i
	return best


func _say(text: String) -> void:
	(s["log"] as Array).append({"day": int(s["day"]), "text": text})
	if (s["log"] as Array).size() > 60:
		(s["log"] as Array).pop_front()


# --- state views (R§41 inspection) --------------------------------------------------------------------------

func wall_fraction(i: int) -> float:
	var w: Dictionary = (s["walls"] as Array)[i]
	return clampf(float(w["hp"]) / float(w["max"]), 0.0, 1.0)


func wall_label() -> String:
	var t := 0.0
	for i in 4:
		t += wall_fraction(i)
	t /= 4.0
	return "High" if t > 0.75 else ("Medium" if t > 0.4 else ("Low" if t > 0.0 else "Breached"))


func morale_label() -> String:
	var m := float(s["morale"])
	return "High" if m > 0.7 else ("Normal" if m > 0.45 else ("Low" if m > 0.25 else "Breaking"))


func breaches() -> Array:
	var out: Array = []
	for i in 4:
		if bool(((s["walls"] as Array)[i] as Dictionary)["breach"]):
			out.append(i)
	for gt: Dictionary in s["gates"]:
		if float(gt["hp"]) <= 0.0 and not out.has(int(gt["wall"])):
			out.append(int(gt["wall"]))
	return out


func engine_count(kind: String, ready_only := true) -> int:
	var n := 0
	for e: Dictionary in s["engines"]:
		if String(e["kind"]) == kind and (not ready_only or String(e["state"]) == "ready"):
			n += 1
	return n


func supplies_days() -> float:
	return float(s["food_days"])


func view() -> Dictionary:
	var engs: Array = []
	for e: Dictionary in s["engines"]:
		engs.append({"kind": String(e["kind"]), "name": String((ENGINES[e["kind"]] as Dictionary)["name"]), "state": String(e["state"]), "days_left": int(ceil(float(e["left"]))), "hp": float(e["hp"]), "target": e["target"]})
	return {"name": s["name"], "kind": s["kind"], "day": int(s["day"]) - 0, "status": s["status"], "walls": wall_label(), "garrison": int(s["garrison"]), "food_days": float(s["food_days"]),
		"water_days": float(s["water_days"]), "morale": float(s["morale"]), "morale_label": morale_label(), "civilians": int(s["civilians"]), "inner_lines": int(s["inner_lines"]),
		"breaches": breaches(), "engines": engs, "camp": (s["camp"] as Dictionary).duplicate(true), "layer": String((s["layers"] as Array)[int(s["layer"])]), "layers": s["layers"],
		"approaches": (s["approaches"] as Dictionary).duplicate(true), "plan": plan(), "tunnel": (s["tunnel"] as Dictionary).duplicate(true), "defence": (s["defence"] as Dictionary).duplicate(true),
		"structures": (s["structures"] as Dictionary).duplicate(true), "commander": (s["cmd"] as Dictionary).duplicate(true), "attacker": s["attacker"], "defender": s["defender"]}


## The checklist on the siege screen: what the plan asks for and whether it is done.
func plan() -> Array:
	return (s["plan"] as Array).duplicate(true)


func _rebuild_plan() -> void:
	var items: Array = []
	items.append({"id": "build_ram", "label": "Build Battering Ram", "done": engine_count("ram") > 0})
	items.append({"id": "build_tower", "label": "Build Siege Tower", "done": engine_count("tower") > 0})
	items.append({"id": "deploy_trebuchets", "label": "Deploy Trebuchets", "done": engine_count("trebuchet") > 0 or engine_count("catapult") > 0})
	items.append({"id": "dig_tunnel", "label": "Dig Tunnel", "done": float((s["tunnel"] as Dictionary)["progress"]) >= 1.0})
	items.append({"id": "block_supplies", "label": "Block Supplies", "done": bool((s["approaches"] as Dictionary).get("starve", false))})
	items.append({"id": "assault_gate", "label": "Assault Gate", "done": float(((s["gates"] as Array)[0] as Dictionary)["hp"]) <= 0.0 if not (s["gates"] as Array).is_empty() else false})
	s["plan"] = items


# --- engineers and engines (R§43-44) ------------------------------------------------------------------------

func engineers() -> int:
	return int((s["camp"] as Dictionary)["engineers"])


## Days the engine would need now: more engineers shorten it, scarce timber and few workshops lengthen it.
func build_days(kind: String, concurrent := 1) -> float:
	var d: Dictionary = ENGINES[kind]
	var eng := maxf(1.0, float(engineers()) / float(maxi(concurrent, 1)))
	var f := clampf(float(d["eng"]) / eng, 0.4, 3.0)
	var tm := 0.6 + 0.4 * float(s["timber"]) / 0.6 if float(d["wood"]) > 0.0 else 1.0
	return maxf(1.0, round(float(d["days"]) * f / clampf(tm, 0.6, 1.4) / (1.0 + 0.25 * float((s["camp"] as Dictionary)["workshops"] - 1))))


func can_build(kind: String) -> Dictionary:
	if not ENGINES.has(kind):
		return {"ok": false, "reason": "Unknown engine."}
	var d: Dictionary = ENGINES[kind]
	if int(d["tech"]) > int(s["tech"]):
		return {"ok": false, "reason": "Your engineers do not know how to build a %s yet." % String(d["name"]).to_lower()}
	if engineers() < 5:
		return {"ok": false, "reason": "You have no engineers in the camp."}
	if kind == "mage_artillery" and int((s["camp"] as Dictionary)["mages"]) < 10:
		return {"ok": false, "reason": "Mage artillery needs a mage company."}
	if float((s["camp"] as Dictionary)["wood"]) < float(d["wood"]):
		return {"ok": false, "reason": "Not enough timber in the camp."}
	return {"ok": true, "reason": ""}


func build_engine(kind: String) -> Dictionary:
	var chk := can_build(kind)
	if not bool(chk["ok"]):
		return chk
	var building := 0
	for e: Dictionary in s["engines"]:
		if String(e["state"]) == "building":
			building += 1
	var days := build_days(kind, building + 1)
	(s["camp"] as Dictionary)["wood"] = float((s["camp"] as Dictionary)["wood"]) - float((ENGINES[kind] as Dictionary)["wood"])
	(s["engines"] as Array).append({"kind": kind, "state": "building", "left": days, "total": days, "hp": 1.0, "target": -1})
	_say("Engineers begin a %s (%d days)." % [String((ENGINES[kind] as Dictionary)["name"]).to_lower(), int(days)])
	_rebuild_plan()
	return {"ok": true, "reason": "", "days": days}


func set_target(engine_index: int, wall: int) -> void:
	var es: Array = s["engines"]
	if engine_index >= 0 and engine_index < es.size():
		(es[engine_index] as Dictionary)["target"] = wall


func start_tunnel(wall: int) -> Dictionary:
	if engineers() < 10:
		return {"ok": false, "reason": "Not enough engineers to dig."}
	s["tunnel"] = {"wall": wall, "progress": 0.0, "found": false}
	(s["approaches"] as Dictionary)["undermine"] = true
	_say("Sappers begin a tunnel under the %s." % String(((s["walls"] as Array)[wall] as Dictionary)["name"]).to_lower())
	_rebuild_plan()
	return {"ok": true, "reason": ""}


## Choose an approach (R§42). Several can run together. Returns {ok, reason}.
func approach(kind: String, on := true, params := {}) -> Dictionary:
	if not APPROACHES.has(kind):
		return {"ok": false, "reason": "Unknown approach."}
	var ap: Dictionary = s["approaches"]
	match kind:
		"undermine":
			if on:
				return start_tunnel(int(params.get("wall", 0)))
			ap.erase("undermine")
			s["tunnel"] = {"wall": -1, "progress": 0.0, "found": false}
		"bribe":
			return bribe(int(params.get("gold", 200)))
		"infiltrate":
			if on:
				s["agents"] = int(s["agents"]) + int(params.get("agents", 2))
			ap["infiltrate"] = on
		"negotiate":
			return {"ok": true, "reason": "", "eval": surrender_eval(params.get("rep", {}), params.get("terms", {}))}
		"cut_water":
			if on and bool(s["well"]):
				_say("The fortress has a deep well: cutting the stream will only slow it.")
			ap["cut_water"] = on
		_:
			ap[kind] = on
	if not on:
		ap.erase(kind)
	_rebuild_plan()
	return {"ok": true, "reason": ""}


func bribe(gold: int) -> Dictionary:
	s["agents"] = int(s["agents"]) + 1
	s["gold_spent"] = int(s["gold_spent"]) + gold
	var pers := String((s["cmd"] as Dictionary)["personality"])
	var p := clampf(float(gold) / maxf(1.0, float(s["garrison"]) * 4.0), 0.0, 0.7) * (1.0 - 0.6 * float(PERS_STUBBORN.get(pers, 0.1)) - 0.3 * float(s["morale"])) + 0.1 * (1.0 - float(s["morale"]))
	var ok := _hash(int(s["seed"]), int(s["day"]) * 7 + int(s["agents"]), 55) < p
	if ok:
		s["gate_betrayed"] = true
		s["morale"] = maxf(0.0, float(s["morale"]) - 0.08)
		_say("A guard captain takes the gold: a postern will be left open.")
	else:
		_say("The bribe was refused; the agent was driven off.")
	return {"ok": ok, "reason": "" if ok else "The offer was refused.", "chance": p}


# --- daily tick ---------------------------------------------------------------------------------------------

## One day of siege. Returns report lines. Sets sortie_due when the garrison decides to attack the camp.
func tick_day() -> Array:
	var out: Array = []
	if String(s["status"]) != "active":
		return out
	s["day"] = int(s["day"]) + 1
	var day := int(s["day"])
	var ap: Dictionary = s["approaches"]
	var camp: Dictionary = s["camp"]
	# supplies: the fortress eats, the camp eats and forages
	var eat := 1.0 + (0.6 if bool(ap.get("poison", false)) else 0.0) + (0.4 if bool(ap.get("starve", false)) else 0.0)
	s["food_days"] = maxf(0.0, float(s["food_days"]) - eat)
	var wdrain := 1.0 if (bool(ap.get("cut_water", false)) and not bool(s["well"])) else (0.15 if bool(ap.get("cut_water", false)) else 0.05)
	s["water_days"] = maxf(0.0, float(s["water_days"]) - wdrain)
	camp["food_days"] = maxf(0.0, float(camp["food_days"]) - 1.0 + 0.1 * float(s["timber"]))
	camp["wood"] = minf(120.0, float(camp["wood"]) + 6.0 * float(s["timber"]))
	camp["disease"] = clampf(float(camp["disease"]) + 0.01 - 0.0006 * float(camp["medical"]), 0.0, 0.5)
	var fell_out := int(round(float(camp["men"]) * float(camp["disease"]) * 0.01))
	camp["men"] = maxi(0, int(camp["men"]) - fell_out)
	# engines
	var mult_eng := 1.0
	for e: Dictionary in s["engines"]:
		if String(e["state"]) == "building":
			e["left"] = float(e["left"]) - 1.0
			if float(e["left"]) <= 0.0:
				e["state"] = "ready"
				e["left"] = 0.0
				out.append("The %s is ready." % String((ENGINES[e["kind"]] as Dictionary)["name"]).to_lower())
				_say(out[out.size() - 1])
		elif String(e["state"]) == "ready":
			var d: Dictionary = ENGINES[e["kind"]]
			if float(d["dmg"]) > 0.0 and bool(ap.get("bombard", false)) or (String(d["vs"]) == "gate" and bool(ap.get("gate_assault", false))):
				_fire(e, d, out)
			elif String(d["vs"]) == "men" and bool(ap.get("bombard", false)):
				var k := int(round(6.0 * float(e["hp"])))
				s["garrison"] = maxi(0, int(s["garrison"]) - k)
				s["morale"] = maxf(0.0, float(s["morale"]) - 0.004)
			# the defenders hit back at engines in range
			if _hash(int(s["seed"]), day, 11 + int(e["hp"] * 10.0)) < 0.12 and int(s["garrison"]) > 20 and bool(((s["structures"] as Dictionary))["archers"]):
				e["hp"] = float(e["hp"]) - 0.25
				if float(e["hp"]) <= 0.0:
					e["state"] = "destroyed"
					out.append("Defenders burn the %s." % String((ENGINES[e["kind"]] as Dictionary)["name"]).to_lower())
					_say(out[out.size() - 1])
	# tunnel
	var tn: Dictionary = s["tunnel"]
	if int(tn["wall"]) >= 0 and bool(ap.get("undermine", false)):
		tn["progress"] = float(tn["progress"]) + 0.08 * clampf(float(engineers()) / 30.0, 0.3, 2.5)
		if not bool(tn["found"]) and _hash(int(s["seed"]), day, 77) < 0.06 + 0.1 * float(int(s["garrison"]) > 100):
			tn["found"] = true
			out.append("The defenders hear digging and sink a counter-mine.")
			tn["progress"] = float(tn["progress"]) * 0.5
		if float(tn["progress"]) >= 1.0:
			var w: Dictionary = (s["walls"] as Array)[int(tn["wall"])]
			w["hp"] = 0.0
			w["breach"] = true
			out.append("The tunnel collapses: a breach opens in the %s." % String(w["name"]).to_lower())
			_say(out[out.size() - 1])
			s["tunnel"] = {"wall": -1, "progress": 0.0, "found": false}
			ap.erase("undermine")
	# agents and infiltration
	if bool(ap.get("infiltrate", false)) and int(s["agents"]) > 0 and _hash(int(s["seed"]), day, 88) < 0.1:
		s["morale"] = maxf(0.0, float(s["morale"]) - 0.03)
		s["garrison"] = maxi(0, int(s["garrison"]) - 3)
		out.append("Agents spread rumours and sabotage the stores.")
	# defenders repair what bombardment did not touch, raise inner lines behind breaches (R§45)
	for w2: Dictionary in s["walls"]:
		if not bool(w2["breach"]) and not bool(ap.get("bombard", false)) and float(w2["hp"]) < float(w2["max"]):
			w2["hp"] = minf(float(w2["max"]), float(w2["hp"]) + float(w2["max"]) * 0.02)
	var br := breaches()
	if not br.is_empty() and int(s["inner_lines"]) < mini(3, br.size() + 1) and int(s["garrison"]) > 30:
		s["inner_lines"] = int(s["inner_lines"]) + 1
		s["inner_men"] = int(s["inner_men"]) + int(float(s["garrison"]) * 0.25)
		out.append("The garrison builds an inner line behind the breach.")
		_say(out[out.size() - 1])
	# morale of the garrison
	var m := float(s["morale"])
	var dm := 0.0
	if float(s["food_days"]) < 10.0:
		dm -= 0.012 + (0.03 if float(s["food_days"]) < 3.0 else 0.0)
	if float(s["water_days"]) < 4.0:
		dm -= 0.04
	dm -= 0.006 * float(br.size())
	if bool(ap.get("bombard", false)):
		dm -= 0.004
	dm += 0.004 * float(s["hope"])
	if float(s["food_days"]) >= 10.0 and br.is_empty() and not bool(ap.get("bombard", false)):
		dm += 0.004
	s["morale"] = clampf(m + dm, 0.0, 1.0)
	s["hope"] = maxf(0.0, float(s["hope"]) - 0.006)
	camp["morale"] = clampf(float(camp["morale"]) - 0.004 - (0.03 if float(camp["food_days"]) < 2.0 else 0.0) + 0.002, 0.0, 1.0)
	# desertion from a starving garrison
	if float(s["food_days"]) <= 0.0:
		var lost := int(round(float(s["garrison"]) * 0.04))
		s["garrison"] = maxi(0, int(s["garrison"]) - lost)
	# sortie decision (R§43): the garrison attacks a weakly guarded camp
	s["sortie_due"] = false
	if int(s["garrison"]) > 60 and int(camp["guards"]) < int(float(s["garrison"]) * 0.6) and engines_building_or_ready() > 0 and _hash(int(s["seed"]), day, 99) < 0.3:
		s["sortie_due"] = true
		out.append("The garrison sallies out against the camp!")
		_say(out[out.size() - 1])
	_rebuild_plan()
	if int(s["garrison"]) <= 0:
		_fall("starved", out)
	return out


func engines_building_or_ready() -> int:
	var n := 0
	for e: Dictionary in s["engines"]:
		if String(e["state"]) != "destroyed":
			n += 1
	return n


func _fire(e: Dictionary, d: Dictionary, out: Array) -> void:
	var walls: Array = s["walls"]
	var t := int(e["target"])
	if t < 0 or t > 3:
		# default: hit the oldest wall still standing
		var bi := -1
		var ba := -1.0
		for i in 4:
			var w: Dictionary = walls[i]
			if not bool(w["breach"]) and float(w["age"]) > ba:
				ba = float(w["age"])
				bi = i
		t = bi
	if t < 0:
		return
	var w2: Dictionary = walls[t]
	var dmg := float(d["dmg"]) * float(w2["max"]) * (1.0 + 0.8 * float(w2["age"])) * float(e["hp"])
	if String(d["vs"]) == "gate":
		for gt: Dictionary in s["gates"]:
			if float(gt["hp"]) > 0.0 and (int(e["target"]) < 0 or int(gt["wall"]) == int(e["target"]) or true):
				gt["hp"] = maxf(0.0, float(gt["hp"]) - float(d["dmg"]) * float(gt["max"]) * 1.5 * float(e["hp"]))
				if float(gt["hp"]) <= 0.0:
					out.append("The %s is smashed open." % String(gt["name"]).to_lower())
					_say(out[out.size() - 1])
				break
		return
	w2["hp"] = maxf(0.0, float(w2["hp"]) - dmg)
	if float(w2["hp"]) <= 0.0 and not bool(w2["breach"]):
		w2["breach"] = true
		out.append("A breach opens in the %s." % String(w2["name"]).to_lower())
		_say(out[out.size() - 1])


# --- assault and sorties on the tactical map (R§45-46) ----------------------------------------------------

func _ring_opts() -> Dictionary:
	var breaches_a: Array = []
	for i: int in breaches():
		breaches_a.append(float(((s["walls"] as Array)[i] as Dictionary)["dir"]))
	var gates_a: Array = []
	for gt: Dictionary in s["gates"]:
		if float(gt["hp"]) > 0.0:
			gates_a.append(float(gt["dir"]))
		else:
			breaches_a.append(float(gt["dir"]))
	var landings: Array = []
	if engine_count("tower") > 0:
		landings.append(float(((s["walls"] as Array)[_weakest_wall()] as Dictionary)["dir"]) + 0.35)
	var inner: Array = []
	var r := float(s["radius"])
	for b in breaches_a:
		for l in int(s["inner_lines"]):
			inner.append({"a": float(b), "span": 0.75, "r": r * (0.72 - 0.22 * float(l))})
	var pos: Array = s["pos"]
	return {"ring": {"c": Vector2(float(pos[0]), float(pos[1])), "r": r, "gates": gates_a, "breaches": breaches_a, "landings": landings, "inner": inner}, "street": true}


func _weakest_wall() -> int:
	var bi := 0
	var bh := 1e9
	for i in 4:
		var w: Dictionary = (s["walls"] as Array)[i]
		var v := float(w["hp"]) * (1.0 - 0.4 * float(w["age"]))
		if v < bh:
			bh = v
			bi = i
	return bi


func _defender_units() -> Array:
	var g := int(s["garrison"])
	var df: Dictionary = s["defence"]
	var tot := 0
	for k: String in df:
		tot += int(df[k])
	var out: Array = []
	var parts := [["Wall Guard", "infantry", 0.36, 0.55], ["Archers", "archer", 0.22, 0.55], ["Spear Line", "spear", 0.2, 0.55], ["Militia", "infantry", 0.14, 0.4], ["Veteran Reserve", "infantry", 0.08, 0.8]]
	for p: Array in parts:
		var n := int(round(float(g) * float(p[2])))
		if n >= 5:
			out.append({"cid": 0, "name": String(p[0]), "kind": String(p[1]), "men": n, "quality": float(p[3]) + (0.05 if bool((s["structures"] as Dictionary)["stakes"]) else 0.0), "morale": clampf(0.35 + float(s["morale"]) * 0.6, 0.2, 0.95), "fatigue": 0.0})
	return out


func _attacker_units() -> Array:
	var units: Array = (s["att_units"] as Array).duplicate(true)
	if units.is_empty():
		var men := int((s["camp"] as Dictionary)["men"])
		for p: Array in [["Storm Infantry", "infantry", 0.4], ["Spearmen", "spear", 0.25], ["Archers", "archer", 0.2], ["Heavy Cavalry", "heavy_cav", 0.15]]:
			var n := int(round(float(men) * float(p[2])))
			if n >= 5:
				units.append({"cid": 0, "name": String(p[0]), "kind": String(p[1]), "men": n, "quality": 0.6, "morale": clampf(0.3 + float((s["camp"] as Dictionary)["morale"]) * 0.6, 0.2, 0.95), "fatigue": 0.0})
	return units


## A tactical-battle spec for storming the walls at the breach (or layer) the plan points to. Feed it to Tactical.create.
func assault_spec(attacker_cmd := {}, defender_cmd := {}) -> Dictionary:
	var pos: Array = s["pos"]
	var layer := int(s["layer"])
	var ring := not (layer > 0)
	var cmd_a := {"name": "Siege Commander", "personality": "aggressive", "skill": 2}
	for k: String in attacker_cmd:
		cmd_a[k] = attacker_cmd[k]
	var cmd_d := (s["cmd"] as Dictionary).duplicate()
	cmd_d["skill"] = 2
	for k2: String in defender_cmd:
		cmd_d[k2] = defender_cmd[k2]
	var half := 24.0 * 10.0
	var br := breaches()
	var bdir := float(((s["walls"] as Array)[br[0]] as Dictionary)["dir"]) if not br.is_empty() else float(((s["walls"] as Array)[_weakest_wall()] as Dictionary)["dir"])
	var dirv := Vector2.from_angle(bdir)
	var r := float(s["radius"])
	var opts: Dictionary
	var a_anchor: Array
	var d_anchor: Array
	var a_axis: float
	var d_axis: float
	if ring:
		opts = _ring_opts()
		var ac := Vector2(half, half) + dirv * (r + 72.0)
		var dc := Vector2(half, half) + dirv * (r * 0.42)
		a_anchor = [ac.x, ac.y]
		d_anchor = [dc.x, dc.y]
		a_axis = bdir + PI
		d_axis = bdir
	else:
		opts = {"street": true, "ring": {"c": Vector2(float(pos[0]), float(pos[1])), "r": 4000.0, "gates": [], "breaches": [], "landings": [], "inner": []}}
		opts.erase("ring")
		var ac2 := Vector2(half, half) + dirv * 110.0
		var dc2 := Vector2(half, half) - dirv * 40.0
		a_anchor = [ac2.x, ac2.y]
		d_anchor = [dc2.x, dc2.y]
		a_axis = bdir + PI
		d_axis = bdir
	var sides := {
		"a": {"faction": String(s["attacker"]), "player": String(s["attacker"]) == "player", "name": "Besiegers", "cmd": cmd_a, "units": _attacker_units(), "supply": 2.0, "anchor": a_anchor, "axis": a_axis, "zone_w": 70.0, "dscale": 0.4,
			"formation": "column"},
		"b": {"faction": String(s["defender"]), "player": String(s["defender"]) == "player", "name": "Garrison", "cmd": cmd_d, "units": _defender_units(), "supply": maxf(0.5, float(s["food_days"]) / 4.0), "anchor": d_anchor, "axis": d_axis, "zone_w": 70.0, "dscale": 0.4,
			"formation": "line"}}
	return {"seed": int(hash([int(s["seed"]), int(s["day"]), layer])) & 0x7fffffff, "name": "%s: %s" % [String(s["name"]), String((s["layers"] as Array)[layer])], "center": [float(pos[0]), float(pos[1])], "n": 48, "cell": 10.0,
		"weather": "clear", "season": "spring", "hour": 9 if not bool(s["gate_betrayed"]) else 3, "attacker": "a", "surprise": "a" if bool(s["gate_betrayed"]) else "", "deploy": true, "opts": opts, "sides": sides}


func sortie_spec() -> Dictionary:
	var camp: Dictionary = s["camp"]
	var cp: Array = camp["pos"]
	var guards := int(camp["guards"])
	var att: Array = [{"cid": 0, "name": "Camp Guards", "kind": "infantry", "men": maxi(guards, 10), "quality": 0.55, "morale": 0.6, "fatigue": 0.2}, {"cid": 0, "name": "Engineers", "kind": "engineer", "men": maxi(int(camp["engineers"]), 5), "quality": 0.4, "morale": 0.5, "fatigue": 0.0}]
	if int(camp["medical"]) >= 5:
		att.append({"cid": 0, "name": "Medical Tents", "kind": "medical", "men": int(camp["medical"]), "quality": 0.3, "morale": 0.5, "fatigue": 0.0})
	var g := int(float(s["garrison"]) * 0.45)
	var sor: Array = [{"cid": 0, "name": "Sortie Infantry", "kind": "infantry", "men": int(g * 0.6), "quality": 0.6, "morale": 0.8, "fatigue": 0.0}, {"cid": 0, "name": "Sortie Horse", "kind": "light_cav", "men": int(g * 0.15), "quality": 0.6, "morale": 0.8, "fatigue": 0.0},
		{"cid": 0, "name": "Sortie Archers", "kind": "archer", "men": int(g * 0.25), "quality": 0.55, "morale": 0.8, "fatigue": 0.0}]
	return {"seed": int(hash([int(s["seed"]), int(s["day"]), 991])) & 0x7fffffff, "name": "Sortie from %s" % String(s["name"]), "center": [float(cp[0]), float(cp[1])], "n": 40, "cell": 40.0, "weather": "clear", "season": "spring", "hour": 5,
		"attacker": "b", "surprise": "b", "deploy": String(s["attacker"]) == "player", "sides": {
			"a": {"faction": String(s["attacker"]), "player": String(s["attacker"]) == "player", "name": "The camp", "cmd": {"name": "Camp Marshal", "personality": "loyal", "skill": 2}, "units": att, "supply": 2.0},
			"b": {"faction": String(s["defender"]), "player": false, "name": "Sortie", "cmd": (s["cmd"] as Dictionary).duplicate(), "units": sor, "supply": 3.0}}}


## Applies a finished assault battle (Tactical.result): garrison and camp losses, layer progress, fall (R§45-46).
## Returns {won, fell, lines}.
func apply_assault(res: Dictionary) -> Dictionary:
	var lines: Array = []
	var lost_a := 0
	var lost_d := 0
	var left_d := 0
	for u: Dictionary in res.get("units", []):
		if int(u["side"]) == 0:
			lost_a += int(u["men0"]) - int(u["men"]) if String(u["state"]) != "left the field" else 0
		else:
			lost_d += int(u["men0"]) - int(u["men"])
			left_d += int(u["men"]) if String(u["state"]) not in ["left the field", "destroyed"] else 0
	var camp: Dictionary = s["camp"]
	camp["men"] = maxi(0, int(camp["men"]) - lost_a)
	var won := String(res.get("winner", "")) == "a"
	if won:
		s["garrison"] = maxi(0, int(round(float(s["garrison"]) * 0.45)) - 0)
		s["garrison"] = mini(int(s["garrison"]), maxi(0, left_d))
		s["morale"] = maxf(0.0, float(s["morale"]) - 0.25)
		if int(s["layer"]) >= (s["layers"] as Array).size() - 1 or int(s["garrison"]) <= 0:
			var out: Array = []
			_fall("stormed", out)
			lines.append_array(out)
		else:
			s["layer"] = int(s["layer"]) + 1
			s["inner_lines"] = maxi(0, int(s["inner_lines"]) - 1)
			lines.append("The %s is taken. The fighting moves to the %s." % [String((s["layers"] as Array)[int(s["layer"]) - 1]).to_lower(), String((s["layers"] as Array)[int(s["layer"])]).to_lower()])
	else:
		s["garrison"] = maxi(0, int(s["garrison"]) - lost_d)
		s["morale"] = clampf(float(s["morale"]) + 0.08, 0.0, 1.0)
		s["hope"] = minf(1.0, float(s["hope"]) + 0.1)
		(s["camp"] as Dictionary)["morale"] = maxf(0.0, float((s["camp"] as Dictionary)["morale"]) - 0.12)
		lines.append("The assault was thrown back with %d dead." % lost_a)
	s["garrison"] = maxi(0, int(s["garrison"]))
	_say(String(lines[0]) if not lines.is_empty() else "Assault over.")
	_rebuild_plan()
	return {"won": won, "fell": String(s["status"]) == "fallen", "lines": lines, "lost_attackers": lost_a, "lost_defenders": lost_d}


func apply_sortie(res: Dictionary) -> Dictionary:
	var won := String(res.get("winner", "")) == "b"      # the sortie side is b
	var camp: Dictionary = s["camp"]
	var lines: Array = []
	if won:
		camp["guards"] = int(int(camp["guards"]) * 0.5)
		camp["engineers"] = int(int(camp["engineers"]) * 0.75)
		for e: Dictionary in s["engines"]:
			if String(e["state"]) == "building" and _hash(int(s["seed"]), int(s["day"]), 4) < 0.6:
				e["state"] = "destroyed"
		(camp["morale"]) = maxf(0.0, float(camp["morale"]) - 0.15)
		lines.append("The sortie burned part of the siege works.")
	else:
		s["garrison"] = maxi(0, int(int(s["garrison"]) * 0.85))
		s["morale"] = maxf(0.0, float(s["morale"]) - 0.06)
		lines.append("The camp beat off the sortie.")
	s["sorties"] = int(s["sorties"]) + 1
	s["sortie_due"] = false
	_say(String(lines[0]))
	_rebuild_plan()
	return {"won": won, "lines": lines}


## Plays an assault or a sortie with both commanders' AI (no player at the table).
func auto_assault() -> Dictionary:
	var spec := assault_spec()
	spec["deploy"] = false
	var tt: RefCounted = Tactical.create(spec)
	var r: Dictionary = tt.call("run_to_end")
	return apply_assault(r)


func auto_sortie() -> Dictionary:
	var spec := sortie_spec()
	spec["deploy"] = false
	var tt: RefCounted = Tactical.create(spec)
	var r: Dictionary = tt.call("run_to_end")
	return apply_sortie(r)


# --- defence (R§41, panel "Fortress Defence") ----------------------------------------------------------------

func assign_defence(alloc: Dictionary) -> void:
	var df: Dictionary = s["defence"]
	for k: String in df:
		df[k] = int(alloc.get(k, df[k]))


func auto_assign() -> void:
	var g := int(s["garrison"])
	var df: Dictionary = s["defence"]
	df["gate"] = int(g * 0.22)
	df["wall_w"] = int(g * 0.26)
	df["wall_e"] = int(g * 0.22)
	df["inner"] = int(g * 0.15)
	df["reserve"] = g - int(df["gate"]) - int(df["wall_w"]) - int(df["wall_e"]) - int(df["inner"])


func set_structure(k: String, on: bool) -> void:
	(s["structures"] as Dictionary)[k] = on


# --- surrender (R§47) ---------------------------------------------------------------------------------------

## Would the garrison surrender on these terms? rep: the besieger's factions.war_rep(): {honour, ruthless, cowardly, label}.
## Reasons include food, morale, hope of relief, civilians, the commander's character and the besieger's reputation:
## a commander who believes you massacre prisoners refuses even when defeat is certain.
func surrender_eval(rep: Dictionary, terms := {}) -> Dictionary:
	var pers := String((s["cmd"] as Dictionary)["personality"])
	var reasons: Array = []
	var despair := 0.0
	var morale := float(s["morale"])
	despair += (1.0 - morale) * 0.42
	var food := clampf(1.0 - float(s["food_days"]) / 20.0, 0.0, 1.0)
	despair += food * 0.26
	if food > 0.5:
		reasons.append("the granaries are nearly empty")
	var water := clampf(1.0 - float(s["water_days"]) / 10.0, 0.0, 1.0)
	despair += water * 0.12
	if water > 0.5:
		reasons.append("the water is failing")
	var br := breaches()
	if not br.is_empty():
		despair += 0.12
		reasons.append("the walls are breached")
	if int(s["inner_lines"]) >= 2:
		despair -= 0.05
	despair -= 0.22 * float(s["hope"])
	var civ_suffer := clampf(float(s["civilians"]) / maxf(1.0, float(s["garrison"]) * 3.0), 0.0, 1.0) * food
	despair += 0.1 * civ_suffer
	if civ_suffer > 0.4:
		reasons.append("the townsfolk are starving")
	var ratio := float((s["camp"] as Dictionary)["men"]) / maxf(1.0, float(s["garrison"]))
	despair += clampf((ratio - 1.0) * 0.06, -0.08, 0.14)
	var thr := SURRENDER_BASE + float(PERS_STUBBORN.get(pers, 0.0))
	if String(s["defender"]) in ["independent", "bandits"]:
		thr -= 0.05
	var honour := float(rep.get("honour", 0.0))
	var ruthless := float(rep.get("ruthless", 0.0))
	var label := String(rep.get("label", "unknown"))
	if label == "honourable" or honour >= 12.0:
		thr -= 0.1
		reasons.append("%s is known to honour surrender" % "the besieger")
	if bool(terms.get("spare_civilians", false)):
		thr -= 0.06
	if bool(terms.get("free_passage", false)):
		thr -= 0.08
	var fear := ruthless - honour >= 15.0 or label == "ruthless" and ruthless >= 20.0
	var accept := despair >= thr and not fear
	var refusal := ""
	if fear and despair >= thr:
		refusal = "massacre"
		reasons.append("they believe you massacre prisoners: better to die fighting")
	elif not accept:
		refusal = "hope"
		if despair < thr:
			reasons.append("the garrison still believes it can hold")
	return {"accept": accept, "score": snappedf(despair, 0.001), "threshold": snappedf(thr, 0.001), "reasons": reasons, "refusal": refusal, "fear": fear}


## The garrison gives up on terms (or does not). Returns the eval plus {surrendered}.
func negotiate(rep: Dictionary, terms := {}) -> Dictionary:
	var ev := surrender_eval(rep, terms)
	ev["surrendered"] = false
	if bool(ev["accept"]):
		ev["surrendered"] = true
		var out: Array = []
		_fall("surrender", out)
		s["conduct"] = "honour_surrender"
		ev["lines"] = out
	else:
		_say("The %s refuses your terms." % String((s["cmd"] as Dictionary)["name"]))
	return ev


func _fall(how: String, out: Array) -> void:
	s["status"] = "fallen"
	s["conduct"] = "" if how != "surrender" else "honour_surrender"
	out.append("%s has %s." % [String(s["name"]), {"stormed": "been stormed", "surrender": "surrendered", "starved": "been starved into surrender"}.get(how, "fallen")])
	_say(String(out[out.size() - 1]))


## After the fall: how the victor treats the place (spare, plunder, massacre). Returns the factions.record_war_act name.
func conduct(kind: String) -> String:
	s["conduct"] = kind
	match kind:
		"spare":
			s["morale"] = 0.5
			return "spare_civilians"
		"massacre":
			s["civilians"] = int(int(s["civilians"]) * 0.4)
			return "massacre"
		"plunder":
			return "burn_villages"
	return ""


func lift() -> void:
	if String(s["status"]) == "active":
		s["status"] = "lifted"
		_say("The siege is lifted.")


func serialize() -> Dictionary:
	return s.duplicate(true)


static func restore(d: Dictionary) -> RefCounted:
	var sg: RefCounted = load("res://scripts/realm/siege.gd").new()
	sg.set("s", d.duplicate(true))
	sg.call("_fix")
	return sg


func _fix() -> void:
	for k: String in ["v", "day", "start_day", "garrison", "garrison_max", "civilians", "tech", "inner_lines", "inner_men", "layer", "agents", "gold_spent", "sorties", "seed"]:
		s[k] = int(s[k])
	for w: Dictionary in s["walls"]:
		w["tower"] = int(w["tower"])
	for g: Dictionary in s["gates"]:
		g["wall"] = int(g["wall"])
	for e: Dictionary in s["engines"]:
		e["target"] = int(e["target"])
	var tn: Dictionary = s["tunnel"]
	tn["wall"] = int(tn["wall"])
	var camp: Dictionary = s["camp"]
	for k2: String in ["men", "engineers", "guards", "medical", "mages", "workshops"]:
		camp[k2] = int(camp[k2])
	for k3: String in (s["defence"] as Dictionary):
		(s["defence"] as Dictionary)[k3] = int((s["defence"] as Dictionary)[k3])
	for l: Dictionary in s["log"]:
		l["day"] = int(l["day"])
