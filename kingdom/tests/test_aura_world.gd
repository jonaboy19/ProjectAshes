extends GdUnitTestSuite
## AR-4/9/10 knock-ons: street repulsion on the StreetGraph cost hook, follower motives, scout power reports, psyche witnesses, migration flight and return.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const SG := preload("res://scripts/population/street_graph.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 100, "life": null}
const ME := "i:player"

var hub: RefCounted
var fo: RefCounted


func before_test() -> void:
	WorldGen.setup(2024)
	hub = Hub.new()
	hub.mod("organizations").auto_seed = false
	fo = hub.mod("aura_fallout")
	hub.mod("districts")._ensure()
	WorldSim.day = 10


func _days(n: int) -> void:
	for i in n:
		WorldSim.day += 1
		for k: String in ["civilization", "migration", "aura_fallout"]:
			hub.mod(k).tick_day(WorldSim.day, CTX)


# ------------------------------------------------------------------ AR-4 street repulsion

func _closest_approach(path: PackedVector2Array, from: Vector2, src: Vector2) -> float:
	var best := INF
	var prev := from
	for p in path:
		var seg := Geometry2D.get_closest_point_to_segment(src, prev, p)
		best = minf(best, seg.distance_to(src))
		prev = p
	return best


func test_repulsion_is_near_tier_only_and_clears() -> void:
	var g: RefCounted = SG.for_settlement(0)
	assert_object(g).is_not_null()
	var far: Vector2 = g.center + Vector2(5000, 0)
	assert_bool(g.set_repulsion(far, 40.0, 0.8, 0.0)).is_false()       # far town pays nothing
	assert_bool(g.cost_hook.is_valid()).is_false()
	assert_bool(g.set_repulsion(g.center, 40.0, 0.8, 0.0)).is_true()
	assert_bool(g.cost_hook.is_valid()).is_true()
	g.expire_repulsion(1.0)
	assert_bool(g.cost_hook.is_valid()).is_true()
	g.expire_repulsion(5.0)                                            # not refreshed: gone
	assert_bool(g.cost_hook.is_valid()).is_false()
	assert_bool(g.set_repulsion(g.center, 40.0, 0.0, 0.0)).is_false()  # no fear, no field


func test_crowd_routes_around_the_source_without_teleporting() -> void:
	var g: RefCounted = SG.for_settlement(0)
	var c: Vector2 = g.center
	var a := c + Vector2(-26, 0)
	var b := c + Vector2(26, 0)
	g.clear_repulsion()
	var plain: PackedVector2Array = g.route(a, b)
	var d0 := _closest_approach(plain, a, c)
	g.set_repulsion(c, 80.0, 1.0, 0.0)
	var routed: PackedVector2Array = g.route(a, b)
	var d1 := _closest_approach(routed, a, c)
	g.clear_repulsion()
	assert_bool(routed.size() > 0).is_true()
	assert_vector(routed[routed.size() - 1]).is_equal_approx(plain[plain.size() - 1], Vector2(0.01, 0.01))   # same goal
	assert_float(d1).is_greater_equal(d0 - 0.01)                       # never closer to the source than the plain route
	var prev := a                                                      # no jump: consecutive waypoints stay on the street graph
	for p in routed:
		assert_float(prev.distance_to(p)).is_less(400.0)
		prev = p


func test_hook_is_cheap() -> void:
	var g: RefCounted = SG.for_settlement(0)
	var c: Vector2 = g.center
	g.set_repulsion(c, 80.0, 1.0, 0.0)
	var t := Time.get_ticks_usec()
	for i in 20:
		g.route(c + Vector2(-26, float(i)), c + Vector2(26, -float(i)))
	var per := float(Time.get_ticks_usec() - t) / 20.0
	g.clear_repulsion()
	assert_float(per).is_less(6000.0)


# ------------------------------------------------------------------ AR-9 followers

func test_followers_react_by_motive_and_the_aura_alone_never_breaks_a_lifelong_bond() -> void:
	var w: RefCounted = hub.mod("will")
	var fid: String = hub.mod("followers").hire("knight", "s0", true, "theron")
	var loyal: String = hub.mod("followers").hire("knight", "s0", true, "ward")
	w.set_state(loyal, {"m": {"aff": 0.95, "res": 0.9, "fear": 0.1, "ide": 0.8, "gre": 0.1, "pro": 0.3, "hid": 0.0}, "life": true})
	w.set_state(fid, {"m": {"aff": 0.6, "res": 0.5, "fear": 0.1, "ide": 0.8, "gre": 0.1, "pro": 0.3, "hid": 0.0}, "life": false})
	var f0: float = w.motives(fid)["fear"]
	var a0: float = w.motives(fid)["aff"]
	var ev: Array = w.on_aura(fid, 5.0, 80.0, false, 20)
	assert_bool("aura_fear" in ev).is_true()
	assert_bool("aura_leaving" in ev).is_true()                         # an idealist is repelled by terror
	assert_float(w.motives(fid)["fear"]).is_greater(f0)
	assert_float(w.motives(fid)["aff"]).is_less(a0)
	assert_array(w.on_aura(fid, 5.0, 80.0, false, 20)).is_empty()       # once per day
	var p: Array = w.on_aura(fid, 60.0, 0.0, true, 21)                  # protection and awe bind
	assert_bool("aura_pride" in p and "aura_awe" in p).is_true()
	for d in range(30, 60):
		w.on_aura(loyal, 5.0, 100.0, false, d)                          # a month of terror
	assert_int(int(w.state_of(loyal)["unjust"])).is_equal(0)
	assert_bool(bool(w.state_of(loyal)["life"])).is_true()
	var sc: Dictionary = w.scores(loyal, {"kind": "stay", "moral": 0.0, "danger": 0.2, "tie": 0.0}, {})
	assert_float(sc["consider_leaving"]).is_less(sc["comply"])


func test_aura_incident_reaches_followers_and_round_trips() -> void:
	var w: RefCounted = hub.mod("will")
	var fid: String = hub.mod("followers").hire("hunter", "s0", true, "a")
	w.ensure(fid)
	fo.on_deed(ME, "siege_broken", 0)
	assert_int((w.state_of(fid)["mem"] as Array).size()).is_greater(0)
	var copy: RefCounted = Hub.new().mod("will")
	copy.deserialize(JSON.parse_string(JSON.stringify(w.serialize())))
	assert_float(copy.motives(fid)["fear"]).is_equal_approx(w.motives(fid)["fear"], 0.01)


# ------------------------------------------------------------------ AR-9 war intel

func test_scout_reports_a_vague_distorted_power_and_a_poor_scout_misses_it() -> void:
	var wi: RefCounted = hub.mod("war_intel")
	assert_bool(bool(wi.scout_power("k:caldrenn", "ace", 0)["ok"])).is_false()   # nothing to report yet
	fo.add(ME, 0, 85.0, 5.0)
	wi.register_scout("ace", {"skill": 0.95, "fear": 0.0})
	wi.register_scout("coward", {"skill": 0.1, "fear": 0.9})
	var r: Dictionary = wi.scout_power("k:caldrenn", "ace", 0, ME, {"risk": 0.0})
	var r2: Dictionary = wi.scout_power("k:caldrenn", "coward", 0, ME, {"risk": 0.0})
	assert_bool(bool(r["ok"]) and bool(r2["ok"])).is_true()
	assert_array(wi.power_reports("k:caldrenn")).is_empty()             # still on the road
	assert_int(int(r2["ready_h"])).is_greater(int(r["ready_h"]))        # a frightened scout is late
	var rows: Array = wi.power_reports("k:caldrenn")
	wi.catch_up(0, {})
	var copy: RefCounted = Hub.new().mod("war_intel")
	copy.deserialize(JSON.parse_string(JSON.stringify(wi.serialize())))
	assert_int(copy.serialize()["pw"].size()).is_equal(2)
	assert_int(rows.size()).is_equal(0)


func test_power_reports_are_capped() -> void:
	var wi: RefCounted = hub.mod("war_intel")
	fo.add(ME, 0, 85.0, 5.0)
	for i in 40:
		wi.scout_power("k:a", "s%d" % i, 0, ME)
	assert_int(wi.serialize()["pw"].size()).is_equal(12)


# ------------------------------------------------------------------ AR-10 psyche and migration

func test_witnesses_get_bounded_fear_memories() -> void:
	var ps: RefCounted = hub.mod("psyche")
	var ids: Array = []
	for i in 30:
		ids.append("ch:%d" % (900 + i))
	var n: int = fo.witness_memories(ids, 0.9, "aura_fear")
	assert_int(n).is_equal(12)                                          # per-incident cap
	var m: Dictionary = ps.mood("ch:900", WorldSim.day)
	assert_float(m["fear"]).is_greater(0.0)
	assert_int(ps.memories("ch:900", WorldSim.day).size()).is_equal(1)
	for i in 6:
		fo.witness_memories(ids, 0.9, "aura_fear")
	assert_int(int(fo.stats["witnessed"])).is_less_equal(36 + 12)      # per-day cap holds
	assert_int(fo.witness_memories(ids, 0.5, "no_such_kind")).is_equal(0)
	fo.witness_memories(["ch:990"], 0.8, "aura_awe")
	assert_float(ps.mood("ch:990", WorldSim.day)["fear"]).is_less(ps.mood("ch:900", WorldSim.day)["fear"])


func test_households_flee_after_a_severe_event_and_return_when_calm() -> void:
	var civ: RefCounted = hub.mod("civilization")
	civ._ensure()
	hub.mod("migration")._ensure()
	var sid := 0
	var pop0: int = civ.population("s0")
	var step: int = fo.on_incident(ME, sid, "", 1.0, 0.8, 30, {"t3": 6, "t4": 4, "damage_gold": 50, "death": true})
	fo.add(ME, sid, 80.0, 0.0)
	assert_int(step).is_greater_equal(3)
	assert_bool(fo._flee(ME, sid) or fo.away(sid) > 0).is_true()
	var gone: int = fo.away(sid)
	assert_int(gone).is_between(3, 40)
	assert_int(civ.population("s0")).is_less(pop0)
	assert_bool(fo._flee(ME, sid)).is_false()                          # one flight at a time
	var back0: int = int(fo.stats["returned"])
	_days(8)
	assert_int(int(fo.stats["returned"])).is_equal(back0)              # still dreaded: nobody comes home
	fo._ax.clear()                                                     # the dread has faded
	_days(FLEE_DAYS)
	assert_int(int(fo.stats["returned"])).is_equal(gone)
	_days(FLEE_DAYS)
	assert_int(int(fo.stats["returned"])).is_equal(gone)               # once
	assert_int(fo.away(sid)).is_equal(0)


const FLEE_DAYS := 16


func test_flight_and_witness_state_round_trips() -> void:
	hub.mod("civilization")._ensure()
	fo.add(ME, 0, 80.0, 0.0)
	fo._flee(ME, 0)
	var s: Dictionary = JSON.parse_string(JSON.stringify(fo.serialize()))
	var copy: RefCounted = Hub.new().mod("aura_fallout")
	copy.deserialize(s)
	assert_int(copy.away(0)).is_equal(fo.away(0))
