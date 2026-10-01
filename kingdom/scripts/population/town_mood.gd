extends RefCounted
## What is going on in a settlement, as numbers every simulation level can read.
##
## Reads the realm (read only, null-guarded: every module may be absent in a test) and boils it down to a
## Schedule flag mask plus 0..1 intensities the near AI scores, the micro-event director weighs and the
## WorldSim rows use:
##   rest day / festival   WorldSim.day (every 7th day) and scripts/sim/seasons.gd festivals
##   war                   Life.war (at war: the whole realm is wary, the frontier more so) and hostile armies
##   monster               a raid marching on or striking the town (realm/strongholds.gd), raid aftermath,
##                         monster raid news, the frontier threat map at the gates
##   scarcity              realm/settlements.gd shortages (food counts most), famine
##   mourning              notables who died in the last days, plague, raid aftermath
##   curfew / crime heat   realm/governance.gd laws, realm/society.gd crimes of the last days
## Results are cached per settlement for one game hour or REFRESH_MS of real time, whichever is shorter,
## so a thousand callers cost one realm read each.

const Schedule := preload("res://scripts/population/schedule.gd")
const SeasonsScript := preload("res://scripts/sim/seasons.gd")

const REFRESH_MS := 4000
static var _cache := {}        # sid -> [stamp_ms, abs_hour, mood]
## Tests / tools: pretend facts instead of reading the realm (sid -> partial mood dict; -1 = every settlement).
static var override := {}


static func reset() -> void:
	_cache.clear()
	override = {}


static func clear_cache() -> void:
	_cache.clear()


## The mood of settlement `sid` now (a fresh dictionary is never allocated twice within the cache window).
static func mood_of(sid: int) -> Dictionary:
	var now := Time.get_ticks_msec()
	var abs_h := int(_clock_day() * 24 + _clock_hour())
	var c: Array = _cache.get(sid, [])
	if not c.is_empty() and now - int(c[0]) < REFRESH_MS and int(c[1]) == abs_h:
		return c[2]
	var m := read(sid)
	_cache[sid] = [now, abs_h, m]
	return m


## Fresh read of the realm (no cache).
static func read(sid: int) -> Dictionary:
	var day := _clock_day()
	var hour := _clock_hour()
	var m := {"sid": sid, "rest_day": day % 7 == 0, "festival": "", "festival_name": "", "war": 0.0, "monster": 0.0,
		"scarcity": 0.0, "mourning": 0.0, "curfew": false, "crime": 0.0, "fire": false, "plague": false, "flags": 0}
	var cal := day + _day_offset()
	var fest := SeasonsScript.festival_on(cal)
	if not fest.is_empty():
		m["festival"] = String(fest["id"])
		m["festival_name"] = String(fest["name"])
	var life := _life()
	var realm: RefCounted = life.get("realm") if life != null else null
	if life != null:
		var war: Variant = life.get("war")
		if war != null and war.has_method("is_at_war") and bool(war.call("is_at_war")):
			m["war"] = 0.55 + 0.45 * _front_closeness(war, sid)
	if realm != null and sid >= 0:
		_read_realm(realm, sid, day, hour, m)
	var ov: Dictionary = override.get(-1, {})
	m.merge(ov, true)
	m.merge(override.get(sid, {}), true)
	m["flags"] = flags_from(m)
	return m


## Schedule flag mask for a mood dictionary.
static func flags_from(m: Dictionary) -> int:
	var f := 0
	if bool(m.get("rest_day", false)):
		f |= Schedule.F_REST
	if String(m.get("festival", "")) != "":
		f |= Schedule.F_FESTIVAL
	if float(m.get("war", 0.0)) >= 0.5:
		f |= Schedule.F_WAR
	if float(m.get("monster", 0.0)) >= 0.5:
		f |= Schedule.F_MONSTER
	if float(m.get("scarcity", 0.0)) >= 0.4:
		f |= Schedule.F_SCARCE
	if float(m.get("mourning", 0.0)) >= 0.5:
		f |= Schedule.F_MOURN
	if bool(m.get("curfew", false)):
		f |= Schedule.F_CURFEW
	return f


static func flags_of(sid: int) -> int:
	return int(mood_of(sid)["flags"])


## Poorer meals under scarcity: food restored by one meal, 1.0 = a full table.
static func meal_quality(scarcity: float) -> float:
	return clampf(1.0 - 0.6 * scarcity, 0.3, 1.0)


## People queueing at the bread stall: 0 (none) .. 1 (a long line).
static func queue_level(scarcity: float, hour: float) -> float:
	var morning := 1.0 - smoothstep(0.0, 1.8, absf(hour - 7.5))
	var noon := 0.6 * (1.0 - smoothstep(0.0, 1.5, absf(hour - 12.0)))
	return clampf(scarcity * maxf(morning, noon) * 1.4, 0.0, 1.0)


## Bark category a villager grumbles with, or "" (nothing to complain about).
static func grumble_category(m: Dictionary) -> String:
	if float(m.get("monster", 0.0)) >= 0.5:
		return "monster_talk"
	if float(m.get("scarcity", 0.0)) >= 0.4:
		return "shortage"
	if float(m.get("war", 0.0)) >= 0.5:
		return "war_talk"
	if float(m.get("mourning", 0.0)) >= 0.5:
		return "mourning"
	if bool(m.get("curfew", false)) or float(m.get("crime", 0.0)) >= 0.5:
		return "curfew_talk"
	if String(m.get("festival", "")) != "":
		return "festival_talk"
	if bool(m.get("rest_day", false)):
		return "rest_talk"
	return ""


# ------------------------------------------------------------------ realm reads
static func _read_realm(realm: RefCounted, sid: int, day: int, hour: float, m: Dictionary) -> void:
	var st: Variant = realm.call("mod", "settlements")
	if st != null:
		var sh: Dictionary = st.call("shortages", sid)
		var food := float(sh.get("food", 0))
		var scarce := maxf(food / 3.0, maxf(float(sh.get("bread", 0)) / 5.0, float(sh.get("tools", 0)) / 9.0))
		m["scarcity"] = clampf(scarce, 0.0, 1.0)
		for e: Dictionary in st.call("emergencies", sid):
			match String(e.get("kind", "")):
				"fire":
					m["fire"] = true
				"famine":
					m["scarcity"] = 1.0
				"plague":
					m["plague"] = true
					m["mourning"] = maxf(float(m["mourning"]), 0.55)
				"raid_aftermath":
					m["monster"] = maxf(float(m["monster"]), 0.55)
					m["mourning"] = maxf(float(m["mourning"]), 0.5)
	var sg: Variant = realm.call("mod", "strongholds")
	if sg != null:
		for rd: Dictionary in sg.call("raids"):
			var t: Dictionary = rd.get("target", {})
			if String(t.get("type", "")) == "settlement" and int(t.get("id", -1)) == sid and String(rd.get("phase", "")) != "done":
				m["monster"] = maxf(float(m["monster"]), 1.0 if String(rd.get("phase", "")) == "strike" else 0.6)
	var nt: Variant = realm.call("mod", "notables")
	if nt != null and nt.has_method("news_events"):
		var newest := int(nt.get("_seq")) if nt.get("_seq") != null else 0
		for e: Dictionary in nt.call("news_events", maxi(newest - 80, 1)):
			if int(e.get("sid", -1)) == sid and String(e.get("kind", "")) == "notable_gone":
				var age := day - int(e.get("day", day))
				if age >= 0 and age <= 3:
					m["mourning"] = maxf(float(m["mourning"]), 1.0 - 0.3 * float(age))
	var ec: Variant = realm.call("mod", "ecology")
	if ec != null and ec.has_method("news_events"):
		var ec_newest := int(ec.get("_seq")) if ec.get("_seq") != null else 0
		for e: Dictionary in ec.call("news_events", maxi(ec_newest - 80, 1)):
			if int(e.get("sid", -1)) == sid and String(e.get("kind", "")) == "monster_raid" and day - int(e.get("day", day)) <= 1:
				m["monster"] = maxf(float(m["monster"]), 0.8)
	# Armies on the march near the town (realm/campaign.gd): a hostile one is a siege in the making.
	var cp: Variant = realm.call("mod", "campaign")
	if cp != null and sid < WorldGen.settlements.size():
		var sp: Vector2 = WorldGen.settlements[sid]["pos"]
		for a: Dictionary in cp.call("armies"):
			if (a["pos"] as Vector2).distance_to(sp) < 450.0:
				m["war"] = maxf(float(m["war"]), 0.6 if String(a["faction"]) == String(cp.get("PLAYER")) else 0.95)
	var gov: Variant = realm.call("mod", "governance")
	if gov != null:
		m["curfew"] = bool(gov.call("curfew_active", sid, int(hour)))
	var soc: Variant = realm.call("mod", "society")
	if soc != null:
		var n := 0
		for c: Dictionary in soc.get("crimes"):
			if int(c.get("sid", -1)) == sid and day - int(c.get("day", day)) <= 2:
				n += 1
		m["crime"] = clampf(float(n) / 3.0, 0.0, 1.0)


## 0..1: how near the war is to this settlement (the closest front region within a few km counts fully).
static func _front_closeness(war: Variant, sid: int) -> float:
	if sid < 0 or sid >= WorldGen.settlements.size():
		return 0.0
	var p: Vector2 = WorldGen.settlements[sid]["pos"]
	var best := INF
	for f: Dictionary in war.call("front"):
		best = minf(best, p.distance_to(f["pos"]))
	if best == INF:
		return 0.0
	return 1.0 - smoothstep(600.0, 3200.0, best)


static func _life() -> Node:
	var loop := Engine.get_main_loop()
	return (loop as SceneTree).root.get_node_or_null("Life") if loop is SceneTree else null


static func _world_sim() -> Node:
	var loop := Engine.get_main_loop()
	return (loop as SceneTree).root.get_node_or_null("WorldSim") if loop is SceneTree else null


static func _clock_day() -> int:
	var w := _world_sim()
	return int(w.get("day")) if w != null else 1


static func _clock_hour() -> float:
	var w := _world_sim()
	return float(w.get("time_of_day")) if w != null else 8.0


static func _day_offset() -> int:
	var w := _world_sim()
	if w != null and w.get("seasons") != null:
		return int((w.get("seasons") as Node).get("day_offset"))
	return 0
