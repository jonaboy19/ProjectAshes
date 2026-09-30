extends RefCounted
## Intelligent monster factions for realm/ecology.gd (CIV-C): one clan per goblin warren / orc village in
## data/world/first_region.json. They hunt their zone's prey, and every DECISION_DAYS they pick an intent
## (hold, trade, raid, negotiate, migrate, settle). The intent is HIDDEN from the player until learned
## (learn_intent); acting on it (a raid landing, traders at the market) reveals only the act itself.
## State is a plain Array of JSON-safe Dictionaries, owned here, serialised by the ecology module.

const D := preload("res://scripts/realm/ecology_data.gd")
const REGION := "res://data/world/first_region.json"

var eco: RefCounted = null
var list: Array = []


func seed_factions(owner: RefCounted) -> void:
	eco = owner
	list.clear()
	var places: Array = []
	if FileAccess.file_exists(REGION):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGION))
		if data is Dictionary:
			places = (data as Dictionary).get("places", [])
	for pl: Variant in places:
		if not pl is Dictionary:
			continue
		var kind := String(pl.get("kind", ""))
		if kind != "goblin_warren" and kind != "orc_village":
			continue
		var species := "goblin" if kind == "goblin_warren" else "orc"
		var arr: Array = pl["pos"]
		var id := list.size()
		var base: Dictionary = D.FACTION_SPECIES[species]
		var r := RandomNumberGenerator.new()
		r.seed = hash([_seed(), "faction", id])
		var tier := int(pl.get("danger_tier", 1))
		var f := {"id": id, "place": String(pl.get("id", "camp%d" % id)), "name": _clan_name(String(pl.get("name", "Clan")), species),
			"species": species, "home": [float(arr[0]), float(arr[1])], "pos": [float(arr[0]), float(arr[1])],
			"strength": float(base["strength"]) * (0.8 + 0.25 * tier) * r.randf_range(0.85, 1.15),
			"food": r.randf_range(0.45, 0.8), "temper": clampf(float(base["temper"]) + r.randf_range(-0.2, 0.2), 0.05, 0.95),
			"cunning": clampf(float(base["cunning"]) + r.randf_range(-0.2, 0.2), 0.05, 0.95),
			"rel": {}, "intent": "hold", "since": 0, "target": -1, "exec": -1, "known": 0, "known_day": -999,
			"status": "home", "dest": [float(arr[0]), float(arr[1])], "arrive": -1, "trade": {}, "hist": [],
			"offset": id % D.DECISION_DAYS, "cool": 0, "tfat": 0.0, "raids": 0, "trades": 0, "cap": float(base["strength"]) * (1.2 + 0.3 * tier)}
		list.append(f)
		_seed_relations(f, r)


func _seed() -> int:
	return int(eco.call("seed_value")) if eco != null and eco.has_method("seed_value") else 1066


func _clan_name(n: String, species: String) -> String:
	return "%s clan" % n.replace(" Warren", "").replace(" Hold", "") if species == "goblin" else "%s host" % n.replace(" Hold", "")


func _seed_relations(f: Dictionary, r: RandomNumberGenerator) -> void:
	var p := Vector2(f["pos"][0], f["pos"][1])
	for sid: int in _near_settlements(p, 3):
		(f["rel"] as Dictionary)[str(sid)] = snappedf(r.randf_range(-0.45, 0.25), 0.01)


func _near_settlements(p: Vector2, k: int) -> Array:
	var scored: Array = []
	for s: Dictionary in WorldGen.settlements:
		scored.append([p.distance_to(s["pos"]), int(s["id"])])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array = []
	for i in mini(k, scored.size()):
		out.append(int(scored[i][1]))
	return out


func fpos(f: Dictionary) -> Vector2:
	return Vector2(f["pos"][0], f["pos"][1])


func _rel(f: Dictionary, sid: int) -> float:
	return float((f["rel"] as Dictionary).get(str(sid), -0.1))


func _bump_rel(f: Dictionary, sid: int, d: float) -> void:
	var k := str(sid)
	(f["rel"] as Dictionary)[k] = clampf(float((f["rel"] as Dictionary).get(k, -0.1)) + d, -1.0, 1.0)


func _hist(f: Dictionary, day: int, text: String) -> void:
	var h: Array = f["hist"]
	h.append([day, text])
	if h.size() > 12:
		h.pop_front()


# ----------------------------------------------------------------------------------------------- daily

## Food, strength and whatever the clan's current intent asks of this day. Returns nothing; news goes to eco.
func tick_day(day: int) -> void:
	for f: Dictionary in list:
		_upkeep(f, 1.0)
		if String(f["status"]) == "marching":
			if day >= int(f["arrive"]):
				_arrive(f, day)
			continue
		var exec := int(f["exec"])
		if exec >= 0 and day >= exec:
			_execute(f, day)
		elif String(f["intent"]) == "trade" and int(f["target"]) >= 0 and exec < 0:
			_trade_day(f, day)
		if (day + int(f["offset"])) % D.DECISION_DAYS == 0 and exec < 0:
			_decide(f, day)


func _upkeep(f: Dictionary, h: float) -> void:
	var z: int = eco.call("zone_of", fpos(f))
	var idx: float = eco.call("prey_index_z", z)
	var strength: float = f["strength"]
	var hunt := 0.05 * idx
	var eat := 0.02 + strength * 0.0004
	var food := clampf(float(f["food"]) + (hunt - eat) * h, 0.0, 1.0)
	f["food"] = food
	eco.call("take_prey", z, strength * 0.0003 * h)
	if food > 0.6:
		strength += 0.002 * strength * (1.0 - strength / float(f["cap"])) * h
	elif food < 0.15:
		strength -= 0.004 * strength * h
	f["strength"] = maxf(strength, 2.0)
	f["tfat"] = maxf(float(f["tfat"]) - 0.03 * h, 0.0)


## Decision scoring. Everything here reads the simulation, nothing is random except a little noise.
func _decide(f: Dictionary, day: int) -> void:
	var p := fpos(f)
	var r := RandomNumberGenerator.new()
	r.seed = hash([_seed(), "mfac", day, int(f["id"])])
	var hunger := 1.0 - float(f["food"])
	var temper: float = f["temper"]
	var cunning: float = f["cunning"]
	var strength: float = f["strength"]
	var z: int = eco.call("zone_of", p)
	var apexed: bool = eco.call("apex_count_z", z) > 0.4
	var best_sid := -1
	var best_rel := -2.0
	var weakest_sid := -1
	var weakest_def := INF
	for sid: int in _near_settlements(p, 3):
		var d := p.distance_to(WorldGen.settlements[sid]["pos"])
		if d > 2200.0:
			continue
		var rel := _rel(f, sid)
		if rel > best_rel:
			best_rel = rel
			best_sid = sid
		var df: float = eco.call("defense_of", sid)
		if df < weakest_def:
			weakest_def = df
			weakest_sid = sid
	var scores := {"hold": 0.45}
	if best_sid >= 0:
		scores["trade"] = 0.25 + 0.6 * best_rel + 0.5 * hunger * (1.0 - temper) + 0.15 * cunning - float(f["tfat"])
		scores["negotiate"] = 0.1 + 0.4 * cunning + 0.25 * hunger - 0.35 * absf(best_rel - 0.0) - (0.6 if best_rel > 0.35 else 0.0)
		if best_rel < 0.0 and cunning > 0.35:
			scores["negotiate"] = float(scores["negotiate"]) + 0.2
	if weakest_sid >= 0:
		var ratio := strength * (0.55 + 0.5 * temper) / maxf(weakest_def, 1.0)
		scores["raid"] = -0.15 + 0.5 * temper + 0.7 * hunger + 0.6 * (ratio - 0.8) - 0.5 * maxf(_rel(f, weakest_sid), 0.0) - (1.5 if day < int(f["cool"]) else 0.0)
	var prey: float = eco.call("prey_index_z", z)
	scores["migrate"] = -0.2 + (0.7 if apexed else 0.0) + 0.9 * maxf(0.35 - prey, 0.0) + (0.5 * maxf(hunger - 0.6, 0.0))
	if best_sid >= 0 and best_rel > 0.4 and temper < 0.6 and hunger > 0.3:
		scores["settle"] = 0.3 + 0.6 * best_rel + 0.4 * hunger
	var pick := "hold"
	var top := -INF
	for k: String in scores:
		var v: float = float(scores[k]) + r.randf_range(-0.12, 0.12)
		if v > top:
			top = v
			pick = k
	var sid := best_sid
	if pick == "raid":
		sid = weakest_sid
	if pick != String(f["intent"]) or sid != int(f["target"]):
		f["known"] = 0
	f["intent"] = pick
	f["since"] = day
	f["target"] = sid if pick in ["trade", "raid", "negotiate", "settle"] else -1
	f["exec"] = day + r.randi_range(2, 6) if pick in ["raid", "negotiate", "migrate", "settle"] else -1
	if pick == "trade":
		f["exec"] = -1
		f["trades"] = int(f["trades"]) + 1
		f["tfat"] = float(f["tfat"]) + 0.12
		_hist(f, day, "set out to trade with %s" % eco.call("sname", sid))
		eco.call("faction_news", f, "trade_start", sid, day)
	elif pick != "hold":
		_hist(f, day, "decided to %s%s" % [pick, (" at %s" % eco.call("sname", sid)) if sid >= 0 else ""])


func _trade_day(f: Dictionary, day: int) -> void:
	var sid := int(f["target"])
	var vol := minf(float(f["strength"]) * 0.05, 1.5)
	f["food"] = clampf(float(f["food"]) + 0.012, 0.0, 1.0)
	_bump_rel(f, sid, 0.006)
	var tr: Dictionary = f["trade"]
	tr[str(sid)] = float(tr.get(str(sid), 0.0)) + vol
	eco.call("trade_goods", sid, vol)


func _execute(f: Dictionary, day: int) -> void:
	var sid := int(f["target"])
	f["exec"] = -1
	match String(f["intent"]):
		"raid":
			_raid(f, sid, day)
		"negotiate":
			_negotiate(f, sid, day)
		"migrate":
			_begin_march(f, day)
		"settle":
			_settle_near(f, sid, day)
	f["intent"] = "hold"
	f["target"] = -1


func _raid(f: Dictionary, sid: int, day: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([_seed(), "raid", day, int(f["id"])])
	var attack := float(f["strength"]) * (0.55 + 0.5 * float(f["temper"])) * r.randf_range(0.8, 1.25)
	var defense: float = eco.call("defense_of", sid)
	f["raids"] = int(f["raids"]) + 1
	f["cool"] = day + 40
	f["known"] = 2
	f["known_day"] = day
	if attack > defense:
		f["strength"] = float(f["strength"]) * 0.88
		f["food"] = clampf(float(f["food"]) + 0.35, 0.0, 1.0)
		_bump_rel(f, sid, -0.5)
		var sev := clampf(attack / maxf(defense, 1.0) - 0.6, 0.2, 0.9)
		eco.call("raid_lands", sid, sev)
		_hist(f, day, "raided %s" % eco.call("sname", sid))
		eco.call("faction_news", f, "raid", sid, day)
	else:
		f["strength"] = float(f["strength"]) * 0.72
		_bump_rel(f, sid, -0.15)
		_hist(f, day, "was driven off from %s" % eco.call("sname", sid))
		eco.call("faction_news", f, "raid_repelled", sid, day)


func _negotiate(f: Dictionary, sid: int, day: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash([_seed(), "parley", day, int(f["id"])])
	var chance := 0.4 + float(f["cunning"]) * 0.4 + _rel(f, sid) * 0.3
	if r.randf() < chance:
		_bump_rel(f, sid, 0.3)
		f["food"] = clampf(float(f["food"]) + 0.08, 0.0, 1.0)
		_hist(f, day, "parleyed with %s" % eco.call("sname", sid))
		eco.call("faction_news", f, "parley", sid, day)
	else:
		_bump_rel(f, sid, -0.12)
		_hist(f, day, "broke off talks with %s" % eco.call("sname", sid))
		eco.call("faction_news", f, "parley_failed", sid, day)


func _begin_march(f: Dictionary, day: int) -> void:
	var dest: Vector2 = eco.call("best_refuge", fpos(f))
	f["dest"] = [dest.x, dest.y]
	f["status"] = "marching"
	f["arrive"] = day + maxi(2, int(fpos(f).distance_to(dest) / D.MARCH_M_PER_DAY))
	f["strength"] = float(f["strength"]) * 0.92
	_hist(f, day, "left their camp")
	eco.call("faction_news", f, "march", -1, day)


func _arrive(f: Dictionary, day: int) -> void:
	f["pos"] = (f["dest"] as Array).duplicate()
	f["status"] = "settled"
	f["food"] = clampf(float(f["food"]) + 0.1, 0.0, 1.0)
	for sid: int in _near_settlements(fpos(f), 3):
		if not (f["rel"] as Dictionary).has(str(sid)):
			(f["rel"] as Dictionary)[str(sid)] = -0.2
	_hist(f, day, "settled a new camp")
	eco.call("faction_news", f, "settled", -1, day)


func _settle_near(f: Dictionary, sid: int, day: int) -> void:
	if sid < 0:
		return
	var s: Vector2 = WorldGen.settlements[sid]["pos"]
	var r: float = WorldGen.settlements[sid]["radius"]
	var away := (fpos(f) - s).normalized()
	var spot := s + away * (r * 2.4 + 60.0)
	f["pos"] = [spot.x, spot.y]
	f["status"] = "settled"
	_bump_rel(f, sid, 0.2)
	_hist(f, day, "settled beside %s" % eco.call("sname", sid))
	eco.call("faction_news", f, "settle_near", sid, day)


# ----------------------------------------------------------------------------------------------- player-facing

## Level 1 reveals the kind of intent (hostile, peaceful, leaving); level 2 the exact intent and target.
func learn(fid: int, level: int, day: int) -> bool:
	if fid < 0 or fid >= list.size():
		return false
	var f: Dictionary = list[fid]
	f["known"] = maxi(int(f["known"]), clampi(level, 0, 2))
	f["known_day"] = day
	return true


func view(fid: int) -> Dictionary:
	if fid < 0 or fid >= list.size():
		return {}
	var f: Dictionary = list[fid]
	var known := int(f["known"])
	var s := float(f["strength"])
	var out := {"id": fid, "name": f["name"], "species": f["species"], "pos": fpos(f), "status": f["status"],
		"size": "a handful" if s < 8.0 else ("a warband" if s < 16.0 else "a large host"),
		"known": known, "intent": "unknown", "hint": _observed_hint(f), "target": -1}
	if known >= 1:
		out["intent"] = {"hold": "peaceful", "trade": "peaceful", "negotiate": "peaceful", "raid": "hostile", "migrate": "leaving", "settle": "peaceful"}.get(String(f["intent"]), "unknown")
	if known >= 2:
		out["intent"] = f["intent"]
		out["target"] = f["target"]
	out["history"] = (f["hist"] as Array).duplicate(true) if known >= 2 else []
	return out


func _observed_hint(f: Dictionary) -> String:
	if String(f["status"]) == "marching":
		return "a column is on the move"
	if float(f["food"]) < 0.2:
		return "gaunt and restless"
	if float(f["strength"]) > float(f["cap"]) * 0.85:
		return "drilling and well fed"
	return "watchful"


func band_threat(p: Vector2) -> Array:
	var lines: Array = []
	for f: Dictionary in list:
		var fp := fpos(f)
		var band := 130.0 + float(f["strength"]) * 6.0
		var d := p.distance_to(fp)
		if d < band:
			var bonus := 1.0
			if int(f["known"]) < 2 and String(f["intent"]) == "raid":
				bonus = 1.2
			lines.append(["%s" % f["name"], float(f["strength"]) * 1.1 * bonus * (1.0 - smoothstep(band * 0.4, band, d))])
	return lines
