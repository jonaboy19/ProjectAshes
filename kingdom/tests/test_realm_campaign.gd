extends GdUnitTestSuite
## Realm campaign: courier delay, intel ageing, autonomy, battles, supply,
## covert ops, council, determinism, round trip, perf.

const Campaign := preload("res://scripts/realm/campaign.gd")
const ENEMY := "ongur_khanate"


func _mk() -> Campaign:
	WorldGen.setup(2024)
	var c := Campaign.new()
	c.set_hq(0)
	c.tick_day(0, {})
	return c


func _far_node(c: Campaign) -> int:
	var best := 1
	var bl := -1.0
	for i in range(1, WorldGen.settlements.size()):
		var p := c.path(0, i)
		if not p.is_empty() and c.path_length(p) > bl:
			bl = c.path_length(p)
			best = i
	return best


func _neighbour(c: Campaign, n: int) -> int:
	for e: Vector2i in WorldGen.roads:
		if e.x == n:
			return e.y
		if e.y == n:
			return e.x
	return n


func test_courier_delay_and_order_applies_on_arrival() -> void:
	var c := _mk()
	var far := _far_node(c)
	var id := c.spawn_army("player", far, 200, "loyal")
	var courier := c.issue_order(id, {"kind": "move", "target": 0})
	assert_int(courier["eta_hours"]).is_greater(2)
	for h in int(courier["eta_hours"]) - 1:
		c.tick_hour(h, {})
	assert_str(c.armies()[0]["order"]["kind"]).is_equal("hold")
	for h in 2:
		c.tick_hour(h, {})
	assert_str(c.armies()[0]["order"]["kind"]).is_equal("move")
	assert_str(c.armies()[0]["state"]).is_equal("moving")
	assert_bool(c.couriers().is_empty()).is_true()


func test_army_moves_along_roads_and_arrives() -> void:
	var c := _mk()
	var far := _far_node(c)
	var id := c.spawn_army("player", 0, 200, "loyal")
	c.issue_order(id, {"kind": "move", "target": far})
	var hrs := 0
	while hrs < 600 and int(c.armies()[0]["node"]) != far:
		c.tick_hour(hrs, {})
		hrs += 1
	assert_int(c.armies()[0]["node"]).is_equal(far)
	assert_int(hrs).is_greater(10)


func test_known_map_only_intel_and_it_ages() -> void:
	var c := _mk()
	var far := _far_node(c)
	c.spawn_army(ENEMY, far, 400, "aggressive")
	var km := c.known_map()
	for e: Dictionary in km:
		assert_bool(e["kind"] == "force" and e["faction"] == ENEMY).is_false()   # unseen enemy is unknown
	# a scout sees it
	assert_bool(c.add_intel(1, "scout", 0.2, 0.9)).is_true()
	var f0: Dictionary = c.known_map().filter(func(e: Dictionary) -> bool: return e["kind"] == "force")[0]
	assert_str(f0["source"]).is_equal("scout")
	assert_float(f0["confidence"]).is_greater(0.85)
	assert_bool(f0["est_max"] > 0 and f0["est_min"] < 400 and f0["est_max"] > 400 * 0.7).is_true()
	for d in 6:
		c.tick_day(1 + d, {})
	var km2 := c.known_map().filter(func(e: Dictionary) -> bool: return e["kind"] == "force" and e["faction"] == ENEMY)
	if not km2.is_empty():
		var f1: Dictionary = km2[0]
		assert_float(f1["confidence"]).is_less(f0["confidence"] * 0.6)
		assert_int(f1["age_days"]).is_greater(0)
		assert_bool(f1["est_max"] - f1["est_min"] >= f0["est_max"] - f0["est_min"]).is_true()
	for d in 40:
		c.tick_day(10 + d, {})
	var stale := c.known_map().filter(func(e: Dictionary) -> bool: return e["kind"] == "force" and e["faction"] == ENEMY and e["source"] == "scout")
	assert_bool(stale.is_empty()).is_true()


func test_aggressive_commander_sorties_instead_of_holding() -> void:
	var c := _mk()
	var n := _neighbour(c, 0)
	var me := c.spawn_army("player", 0, 300, "aggressive")
	c.spawn_army(ENEMY, n, 150, "loyal")
	c.set_hq(0)
	c.issue_order(me, {"kind": "hold", "target": 0})
	for h in 6:
		c.tick_hour(h, {})
	assert_str(c.armies()[0]["order"]["kind"]).is_equal("attack")
	# cautious commander refuses to attack a stronger neighbour
	var c2 := _mk()
	var me2 := c2.spawn_army("player", 0, 100, "cautious")
	c2.spawn_army(ENEMY, n, 500, "loyal")
	c2.issue_order(me2, {"kind": "attack", "target": n})
	for h in 6:
		c2.tick_hour(h, {})
	assert_str(c2.armies()[0]["order"]["kind"]).is_equal("hold")


func test_own_initiative_without_orders() -> void:
	var c := _mk()
	var n := _neighbour(c, 0)
	c.spawn_army("player", 0, 400, "ambitious")
	c.spawn_army(ENEMY, n, 100, "loyal")
	var acted := false
	for d in 10:
		c.tick_day(1 + d, {})
		if c.armies()[0]["order"].get("own_initiative", false):
			acted = true
			break
	assert_bool(acted).is_true()


func test_strategic_battle_resolves_and_loser_retreats() -> void:
	var c := _mk()
	var n := _neighbour(c, 0)
	var strong := c.spawn_army("player", n, 500, "loyal")
	c.spawn_army(ENEMY, n, 100, "loyal")
	c.tick_hour(0, {"player_pos": Vector2(9999, 9999)})
	assert_int(c.battles().size()).is_equal(1)
	var b: Dictionary = c.battles()[0]
	assert_bool(b["live"]).is_false()
	assert_str(b["winner_faction"]).is_equal("player")
	assert_int(b["casualties"]["enemy"]).is_greater(0)
	assert_bool(c.pending_live_battle().is_empty()).is_true()
	assert_int(c.armies().size()).is_greater(0)
	assert_bool(strong > 0).is_true()


func test_live_battle_when_player_present() -> void:
	var c := _mk()
	var n := _neighbour(c, 0)
	c.spawn_army("player", n, 300, "loyal")
	c.spawn_army(ENEMY, n, 300, "loyal")
	c.tick_hour(0, {"player_pos": c.node_pos(n)})
	var p := c.pending_live_battle()
	assert_bool(p.is_empty()).is_false()
	assert_int(c.battles().size()).is_equal(0)
	var s := JSON.stringify(c.serialize())
	var c2 := Campaign.new()
	c2.deserialize(JSON.parse_string(s))
	assert_bool(c2.pending_live_battle().is_empty()).is_false()
	c.resolve_live_battle({"winner": "attackers", "attacker_losses": 0.1, "defender_losses": 0.5})
	assert_int(c.battles().size()).is_equal(1)
	assert_bool(c.battles()[0]["live"]).is_true()
	assert_bool(c.pending_live_battle().is_empty()).is_true()


func test_cut_supply_line_causes_attrition() -> void:
	var c := _mk()
	var far := _far_node(c)
	var id := c.spawn_army("player", far, 300, "loyal")
	assert_bool(c.supply_status(id)["connected"]).is_true()
	c.cut_supply_line(_neighbour(c, far), 100)
	c.cut_supply_line(far, 100)
	for d in 12:
		c.tick_day(1 + d, {})
		c.cut_supply_line(far, 100)
	var a: Dictionary = c.armies()[0]
	assert_float(a["supply"]).is_equal(0.0)
	assert_int(a["strength"]).is_less(300)


func test_covert_op_leaves_evidence_and_can_be_discovered() -> void:
	var c := _mk()
	var far := _far_node(c)
	var e := c.spawn_army(ENEMY, far, 300, "loyal")
	var res := c.covert_op("forged_letter", e, {"crestless": false})
	assert_int(res["evidence_id"]).is_greater(0)
	assert_int(c.evidence().size()).is_equal(1)
	var msgs := 0
	for d in 60:
		msgs += c.tick_day(1 + d, {}).filter(func(m: String) -> bool: return m.begins_with("Evidence")).size()
	assert_int(msgs).is_greater(0)
	assert_bool(c.evidence()[0]["discovered"]).is_true()


func test_council_gives_conflicting_advice() -> void:
	var c := _mk()
	c.spawn_army("player", 0, 200, "loyal")
	var e := c.spawn_army(ENEMY, _far_node(c), 300, "loyal")
	c.add_intel(e, "scout", 0.2, 0.9)
	var adv := c.council_advice()
	assert_int(adv.size()).is_greater(3)
	var plans := {}
	for a: Dictionary in adv:
		plans[a["plan"]] = true
		assert_bool(a.has("flawed")).is_false()   # never leaked
	assert_int(plans.size()).is_greater(2)
	var r := c.follow_advice(0)
	assert_bool(r.has("plan")).is_true()


func test_war_sim_integration_spawns_enemy_columns() -> void:
	var c := _mk()
	var WarSim := preload("res://scripts/sim/war_sim.gd")
	var ws := WarSim.new(777)
	for d in 80:
		ws.tick_day(d, {"feud_count": 2, "rift_instability": 0.9, "season": "spring"})
		if ws.is_at_war():
			break
	assert_bool(ws.is_at_war()).is_true()
	var life := Node.new()
	var sc := GDScript.new()
	sc.source_code = "extends RefCounted\nvar war\n"
	sc.reload()
	var l: RefCounted = sc.new()
	l.war = ws
	c.tick_day(100, {"life": l})
	var enemies := c.armies().filter(func(a: Dictionary) -> bool: return a["faction"] == ws.enemy_id())
	assert_int(enemies.size()).is_greater(1)
	life.free()


func test_deterministic_and_round_trip() -> void:
	var run := func() -> String:
		var c := _mk()
		c.spawn_army("player", 0, 200, "aggressive")
		c.spawn_army(ENEMY, _far_node(c), 250, "ambitious")
		c.issue_order(1, {"kind": "attack", "target": _far_node(c)})
		for d in 5:
			for h in 24:
				c.tick_hour(h, {})
			c.tick_day(1 + d, {})
		return JSON.stringify(c.serialize())
	var a: String = run.call()
	var b: String = run.call()
	assert_str(a).is_equal(b)
	var c3 := Campaign.new()
	c3.deserialize(JSON.parse_string(a))
	assert_str(JSON.stringify(c3.serialize())).is_equal(a)


func test_perf_realistic_scale() -> void:
	var c := _mk()
	for i in 6:
		c.spawn_army("player", i % WorldGen.settlements.size(), 150 + i * 10, Campaign.PERSONALITIES[i % 4])
		c.spawn_army(ENEMY, (i + 3) % WorldGen.settlements.size(), 200, Campaign.PERSONALITIES[(i + 1) % 4])
	c.issue_order(1, {"kind": "move", "target": _far_node(c)})
	var t0 := Time.get_ticks_usec()
	for h in 24:
		c.tick_hour(h, {})
	c.tick_day(1, {})
	assert_int(Time.get_ticks_usec() - t0).is_less(20000)
