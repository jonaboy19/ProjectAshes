extends RefCounted
## Battlefield assistants (docs/design/WAR_COMMAND_RULEBOOK.md §18-19): strategist, logistics officer, scout master and
## siege engineer give situational advice. They can be wrong: an advisor may misread the situation, be inexperienced,
## follow outdated doctrine, panic, lie, or have political motives. High intelligence is not the same as being right:
## knowledge and experience decide. Every line carries `correct` (for tests and debugging; the UI never shows it).

const ROLES := ["strategist", "logistics", "scout_master", "siege_engineer"]
const TITLES := {"strategist": "Chief Strategist", "logistics": "Logistics Officer", "scout_master": "Scout Master", "siege_engineer": "Siege Engineer"}
const FLAWS := ["misread", "outdated", "panic", "lie", "political"]
const NAMES := ["Arlen Voss", "Mei Tanaka", "Joro Hale", "Kessa Dorn", "Marek Ilse", "Sela Bryn", "Oswin Dunmark", "Ilse Coldwater"]
const DIRS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]


static func _hash(a: int, b: int, c: int) -> float:
	var x: int = (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	x = (x ^ (x >> 13)) * 1274126177
	x = x ^ (x >> 16)
	return float(x & 0xFFFF) / 65536.0


## A deterministic staff of four. skill / experience 0..1, flaw: how this one goes wrong.
static func roster(seed_: int) -> Array:
	var out: Array = []
	for i in ROLES.size():
		var r := ROLES[i] as String
		out.append({"role": r, "title": String(TITLES[r]), "name": String(NAMES[int(_hash(seed_, i, 1) * float(NAMES.size())) % NAMES.size()]), "skill": snappedf(0.3 + 0.65 * _hash(seed_, i, 2), 0.01),
			"experience": snappedf(0.2 + 0.75 * _hash(seed_, i, 3), 0.01), "flaw": String(FLAWS[int(_hash(seed_, i, 4) * 5.0) % 5]), "bias": ["cautious", "aggressive", "none"][int(_hash(seed_, i, 5) * 3.0) % 3]})
	return out


## Chance that this advisor's line is wrong now.
static func error_chance(adv: Dictionary) -> float:
	return clampf(0.5 * (1.0 - float(adv["skill"])) + 0.3 * (1.0 - float(adv["experience"])) + (0.08 if String(adv["bias"]) != "none" else 0.0), 0.03, 0.75)


static func _wrong(adv: Dictionary, seed_: int, tick: int) -> bool:
	return _hash(seed_, int(ROLES.find(String(adv["role"]))) + 10, tick) < error_chance(adv)


static func _dir_name(a: float) -> String:
	var i := int(round(wrapf(a, 0.0, TAU) / (TAU / 8.0))) % 8
	# tactical y is down: angle 0 east, PI/2 south; DIRS runs clockwise from north
	var compass := (i + 2) % 8
	return String(DIRS[compass])


static func _confidence(adv: Dictionary) -> String:
	var c := float(adv["skill"]) * 0.6 + float(adv["experience"]) * 0.4
	return "sure" if c > 0.7 else ("fairly sure" if c > 0.45 else "unsure")


## Lines for a tactical battle as seen by `side` (0/1). tt: the Tactical battle. tick: changes every few minutes so advice varies.
static func battle_advice(tt: RefCounted, side: int, staff: Array, tick: int) -> Array:
	var out: Array = []
	for adv: Dictionary in staff:
		var role := String(adv["role"])
		if role == "siege_engineer":
			continue
		var wrong := _wrong(adv, int(tt.seed), tick)
		var line := {}
		match role:
			"strategist":
				line = _strategist(tt, side, adv, wrong)
			"logistics":
				line = _logistics_battle(tt, side, adv, wrong)
			"scout_master":
				line = _scout(tt, side, adv, wrong)
		if not line.is_empty():
			line["role"] = role
			line["title"] = String(adv["title"])
			line["name"] = String(adv["name"])
			line["confidence"] = _confidence(adv)
			line["correct"] = not wrong
			out.append(line)
	return out


static func _strategist(tt: RefCounted, side: int, adv: Dictionary, wrong: bool) -> Dictionary:
	var flaw := String(adv["flaw"])
	# 1. enemy cavalry that has gone out of sight: a flank is coming
	var hidden := -1
	for i in tt.u_side.size():
		if tt.u_side[i] != side and tt.u_st[i] < tt.S_DEAD and int(tt.u_cls[i]) == 3 and ((tt.u_seen[i] >> side) & 1) == 0 and tt.u_lst[i] >= 0.0:
			hidden = i
			break
	var f: Dictionary = tt.forces(side)
	if hidden >= 0:
		var mid: float = tt.size_m() * 0.5
		var ang := atan2(float(tt.u_lsy[hidden]) - mid, float(tt.u_lsx[hidden]) - mid)
		var d := _dir_name(ang if not (wrong and flaw == "misread") else ang + PI)
		return {"kind": "flank", "text": "Enemy cavalry has disappeared behind the %s ridge. They may be preparing to flank us." % d}
	if float(f["morale"]) < 0.45 and int(f["units"]) > 1:
		if wrong and flaw == "panic":
			return {"kind": "retreat", "text": "We cannot hold. Order the retreat now!"}
		return {"kind": "reserve", "text": "The line is wavering. Commit the reserve before it breaks."}
	if wrong and flaw == "panic":
		return {"kind": "retreat", "text": "They are too many. We should fall back while we still can."}
	if wrong and flaw == "outdated":
		return {"kind": "charge", "text": "Send the cavalry straight at their centre. That is how it is done."}
	if wrong and flaw in ["lie", "political"]:
		return {"kind": "wing", "text": "Move everything to the far wing; the centre can look after itself."}
	var e: Dictionary = tt.enemy_intel(side)
	if int(e["seen_units"]) == 0:
		return {"kind": "scout", "text": "We have not seen them yet. Keep the line closed and wait for the scouts."}
	if float(f["men"]) > float(e["est_max"]) * 1.2:
		return {"kind": "press", "text": "We outnumber what we can see. Press while their formations are still forming."}
	return {"kind": "hold", "text": "Hold good ground and make them come to us."}


static func _logistics_battle(tt: RefCounted, side: int, adv: Dictionary, wrong: bool) -> Dictionary:
	var days := float((tt.S[side] as Dictionary)["supply"])
	var shown := days
	if wrong:
		shown = days * (1.7 if String(adv["flaw"]) in ["lie", "political"] else 0.5)
	var ammo := 0.0
	var n := 0
	for i in tt.u_side.size():
		if tt.u_side[i] == side and tt.u_st[i] < tt.S_DEAD and tt.u_rng[i] > 0.0:
			ammo += tt.u_ammo[i]
			n += 1
	var low_ammo := n > 0 and ammo / float(n) < 0.35
	if low_ammo and not wrong:
		return {"kind": "ammo", "text": "Our archers are running low on arrows. Pull them back or get them covered."}
	return {"kind": "supply", "text": "We can hold this position for roughly %d more days before grain becomes critical." % maxi(0, int(round(shown)))}


static func _scout(tt: RefCounted, side: int, adv: Dictionary, wrong: bool) -> Dictionary:
	var e: Dictionary = tt.enemy_intel(side)
	var lo := int(e["est_min"])
	var hi := int(e["est_max"])
	if wrong:
		lo = int(lo * 0.5)
		hi = int(hi * 0.55)
	if int(e["seen_units"]) == 0:
		# forest that could hide a column
		var share: Dictionary = tt.terrain_share()
		var wood := float(share.get("Forest", 0.0))
		if wood > 0.1:
			return {"kind": "cover", "text": "The woods could hide two or three formations. Send scouts before we move."}
		return {"kind": "scout", "text": "Nothing in sight. Send riders forward before the line advances."}
	return {"kind": "estimate", "text": "Enemy force estimated %d to %d men, %d formations confirmed." % [lo, hi, int(e["seen_units"])]}


## Advice for a siege (siege.view()): the engineer reads the walls, the logistics officer the granaries.
static func siege_advice(sv: Dictionary, staff: Array, seed_: int, tick: int, walls: Array = []) -> Array:
	var out: Array = []
	for adv: Dictionary in staff:
		var role := String(adv["role"])
		if role not in ["siege_engineer", "logistics", "strategist"]:
			continue
		var wrong := _wrong(adv, seed_, tick)
		var line := {}
		match role:
			"siege_engineer":
				if not walls.is_empty():
					# the truly weakest wall is the oldest / most damaged; a bad engineer points at the strongest
					var pick := 0
					var bs := 1e9
					for i in walls.size():
						var w: Dictionary = walls[i]
						var v := float(w["hp"]) * (1.0 - 0.5 * float(w["age"]))
						v = -v if wrong else v
						if v < bs:
							bs = v
							pick = i
					var name_ := String((walls[pick] as Dictionary)["name"]).to_lower()
					line = {"kind": "wall", "wall": pick, "text": "Their %s is older. Concentrated bombardment there should create a breach faster." % name_ if not wrong else "The %s looks weakest to me. Put everything against it." % name_}
			"logistics":
				var days := float(sv.get("food_days", 10.0))
				var camp_days := float((sv.get("camp", {}) as Dictionary).get("food_days", 10.0))
				var shown := camp_days * (0.45 if wrong else 1.0)
				line = {"kind": "supply", "text": "The camp has food for %d more days; they have about %d. Sieges consume enormous resources." % [int(round(shown)), int(round(days * (1.5 if wrong and String(adv["flaw"]) == "lie" else 1.0)))]}
			"strategist":
				if int(sv.get("inner_lines", 0)) > 0 and not wrong:
					line = {"kind": "inner", "text": "They are raising a second line behind the breach. Breaking the wall will not be enough."}
				elif wrong and String(adv["flaw"]) == "panic":
					line = {"kind": "retreat", "text": "The garrison is fresh. Lift the siege before winter."}
				else:
					line = {"kind": "starve", "text": "Their morale is %s. Time may do more than steel." % String(sv.get("morale_label", "Normal")).to_lower()}
		if not line.is_empty():
			line["role"] = role
			line["title"] = String(adv["title"])
			line["name"] = String(adv["name"])
			line["confidence"] = _confidence(adv)
			line["correct"] = not wrong
			out.append(line)
	return out
