extends GdUnitTestSuite
## War Map data layer (scripts/realm/campaign.gd "war field" + war_units.gd): formations, split/merge
## conservation, command authority, couriers with delay (old order persists), fog of war, deterministic
## engagements with bounded variance, terrain, persistence and perf.

const Campaign := preload("res://scripts/realm/campaign.gd")
const WarUnits := preload("res://scripts/realm/war_units.gd")
const ENEMY := "ongur_khanate"


func _mk() -> Campaign:
	WorldGen.setup(2024)
	var c := Campaign.new()
	c.set_hq(0)
	c.tick_day(0, {})
	return c


func _far_node(c: Campaign, from := 0) -> int:
	var best := 1
	var bl := -1.0
	for i in WorldGen.settlements.size():
		var p := c.path(from, i)
		if i != from and not p.is_empty() and c.path_length(p) > bl:
			bl = c.path_length(p)
			best = i
	return best


func _unit_named(c: Campaign, army: int, name: String) -> Dictionary:
	for u: Dictionary in c.army_units(army):
		if String(u["name"]) == name:
			return u
	return {}


func _men(c: Campaign, army: int) -> int:
	var s := 0
	for u: Dictionary in c.army_units(army):
		s += int(u["men"])
	return s


func _first(c: Campaign, army: int, kind: String) -> Dictionary:
	for u: Dictionary in c.army_units(army):
		if String(u["kind"]) == kind:
			return u
	return {}


# --- formations (R§3-4) ------------------------------------------------------------------

func test_army_has_internal_formations_and_sub_commanders() -> void:
	var c := _mk()
	var id := c.spawn_army("player", 0, 2040, "loyal")
	var units := c.army_units(id)
	assert_int(units.size()).is_equal(10)
	var kinds := {}
	var sum := 0
	for u: Dictionary in units:
		kinds[u["kind"]] = true
		sum += int(u["men"])
		assert_float(float(u["morale"])).is_between(0.0, 1.0)
		assert_bool(bool(u["detached"])).is_false()
	assert_int(sum).is_equal(2040)
	assert_int(kinds.size()).is_equal(9)   # two infantry battalions, every other kind once
	var cmd := c.army_command(id)
	assert_bool((cmd["subs"] as Array).size() >= 3).is_true()
	for k: String in ["tactics", "leadership", "discipline", "logistics", "scouting", "capacity", "personality"]:
		assert_bool((cmd["commander"] as Dictionary).has(k)).is_true()
	# a tiny company only gets the formations big enough to matter
	var small := c.spawn_army("player", 0, 40, "loyal")
	assert_int(_men(c, small)).is_equal(40)
	assert_int(c.army_units(small).size()).is_less(10)


func test_split_merge_conserve_men_and_respect_limits() -> void:
	var c := _mk()
	var id := c.spawn_army("player", 0, 2040, "loyal")
	var inf2 := _unit_named(c, id, "Second Infantry")
	var men0 := int(inf2["men"])
	var total0 := _men(c, id)
	var nid := c.split_unit(int(inf2["id"]), 150)
	assert_int(nid).is_greater(0)
	assert_int(_men(c, id)).is_equal(total0)
	assert_int(c.army_units(id).size()).is_equal(11)
	var a := c.unit(int(inf2["id"]))
	var b := c.unit(nid)
	assert_int(int(a["men"]) + int(b["men"])).is_equal(men0)
	assert_int(int(b["men"])).is_equal(150)
	assert_str(String(a["name"])).is_equal("Second Infantry A")
	assert_str(String(b["name"])).is_equal("Second Infantry B")
	assert_int(int((c.armies()[0] as Dictionary)["strength"])).is_equal(total0)
	# too small a piece, or emptying the parent, is refused
	assert_int(c.split_unit(nid, 2)).is_equal(0)
	assert_int(c.split_unit(nid, int(b["men"]))).is_equal(0)
	assert_int(_men(c, id)).is_equal(total0)
	# different kinds cannot merge
	var arch := _first(c, id, "archer")
	assert_bool(c.merge_units(nid, int(arch["id"]))).is_false()
	# merge back
	assert_bool(c.merge_units(int(inf2["id"]), nid)).is_true()
	assert_int(_men(c, id)).is_equal(total0)
	assert_int(c.army_units(id).size()).is_equal(10)
	assert_int(int(c.unit(int(inf2["id"]))["men"])).is_equal(men0)
	assert_bool(c.unit(nid).is_empty()).is_true()
	assert_str(String(c.unit(int(inf2["id"]))["name"])).is_equal("Second Infantry")


func test_detach_makes_a_piece_and_far_pieces_cannot_merge() -> void:
	var c := _mk()
	var id := c.spawn_army("player", 0, 1200, "loyal")
	c.set_army_owner(id, "personal")
	var cav := _first(c, id, "light_cav")
	var det := c.detach(int(cav["id"]), 20)
	assert_int(det).is_greater(0)
	var d := c.unit(det)
	assert_bool(bool(d["detached"])).is_true()
	assert_int(int(d["men"])).is_equal(20)
	assert_str(String(d["name"])).contains("Detachment")
	assert_int(_men(c, id)).is_equal(1200)
	# send it away, it cannot merge back until it returns
	far_order(c, det)
	assert_bool(c.merge_units(int(cav["id"]), det)).is_false()


func far_order(c: Campaign, uid: int) -> void:
	var far := _far_node(c)
	var res := c.order_unit(uid, {"behavior": "advance", "node": far})
	assert_bool(res["ok"]).is_true()
	for h in 40:
		c.tick_hour(h, {})


# --- command authority (R§12-15) ---------------------------------------------------------

func test_authority_denial_rank_personal_and_appointed() -> void:
	var c := _mk()
	var mine := c.spawn_army("player", 0, 2040, "loyal")
	var foe := c.spawn_army(ENEMY, 1, 300, "loyal")
	var inf := _first(c, mine, "infantry")
	# an ordinary soldier commands nothing
	c.set_player_rank("soldier")
	var res := c.order_unit(int(inf["id"]), {"behavior": "hold"})
	assert_bool(res["ok"]).is_false()
	assert_bool(res["denied"]).is_true()
	assert_str(String(res["reason"])).contains("do not belong to your command")
	assert_int((c.couriers() as Array).size()).is_equal(0)
	# enemy pieces are never yours
	assert_bool(c.can_command(int(_first(c, foe, "infantry")["id"]))["ok"]).is_false()
	# a captain gets a hundred men, no more
	c.grant_rank_command("captain")
	var scope := c.command_scope()
	assert_int(int(scope["capacity"])).is_greater_equal(100)
	assert_bool((scope["units"] as Array).size() > 0).is_true()
	assert_bool(int(scope["men"]) <= 300).is_true()
	var allowed := 0
	var denied := 0
	for u: Dictionary in c.army_units(mine):
		if bool(c.can_command(int(u["id"]))["ok"]):
			allowed += 1
		else:
			denied += 1
	assert_int(allowed).is_greater(0)
	assert_int(denied).is_greater(0)
	# personal troops answer to you regardless of rank
	c.set_player_rank("soldier")
	c.grant_rank_command("soldier")
	assert_bool(c.can_command(int(inf["id"]))["ok"]).is_false()
	c.set_army_owner(mine, "personal")
	assert_str(String(c.can_command(int(inf["id"]))["source"])).is_equal("personal")
	# an appointment expands authority temporarily and then lapses; the troops stay the kingdom's
	var c2 := _mk()
	var m2 := c2.spawn_army("player", 0, 900, "loyal")
	var u2 := _first(c2, m2, "spear")
	assert_bool(c2.can_command(int(u2["id"]))["ok"]).is_false()
	c2.appoint_command([m2], 3)
	assert_str(String(c2.can_command(int(u2["id"]))["source"])).is_equal("appointed")
	for d in 4:
		c2.tick_day(1 + d, {})
	assert_bool(c2.can_command(int(u2["id"]))["ok"]).is_false()


func test_request_assistance_superior_decides_deterministically() -> void:
	var results := {}
	for pers: String in ["loyal", "stubborn", "aggressive", "cautious"]:
		var c := _mk()
		var id := c.spawn_army("player", 0, 900, pers)
		var u := _first(c, id, "infantry")
		c.set_player_rank("captain")
		var far := _far_node(c)
		var r1 := c.request_assistance(int(u["id"]), {"behavior": "advance", "node": far})
		var r2 := c.request_assistance(int(u["id"]), {"behavior": "advance", "node": far})
		assert_str(String(r1["decision"])).is_not_empty()
		assert_str(String(r1["text"])).is_not_empty()
		results[pers] = bool(r1["ok"])
		if bool(r1["ok"]):
			assert_bool((r1["courier"] as Dictionary).is_empty()).is_false()
		assert_str(String(r1["by"])).is_not_empty()
		assert_bool(r2.has("decision")).is_true()
	assert_bool(results["loyal"]).is_true()
	assert_bool(results["stubborn"]).is_false()


func test_over_capacity_slows_orders() -> void:
	var c := _mk()
	var far := _far_node(c)
	var id := c.spawn_army("player", far, 3000, "loyal")
	c.set_army_owner(id, "personal")
	var u := _first(c, id, "infantry")
	c.set_player_rank("captain")
	var over := c.command_scope()
	assert_float(float(over["overload"])).is_greater(0.5)   # 3000 men, capacity of a lone officer
	var slow: Dictionary = {}
	for w: Dictionary in c.army_units(id):   # micromanaging every formation of a 3000-man army at once
		slow = c.order_unit(int(w["id"]), {"behavior": "advance", "node": 0})["courier"]
	var c2 := _mk()
	var id2 := c2.spawn_army("player", far, 150, "loyal")
	c2.set_army_owner(id2, "personal")
	c2.set_player_rank("captain")
	var u2 := _first(c2, id2, "infantry")
	var quick: Dictionary = c2.order_unit(int(u2["id"]), {"behavior": "advance", "node": 0})["courier"]
	assert_int(int(slow["eta_hours"])).is_greater(int(quick["eta_hours"]))
	assert_float(float(slow["mult"])).is_greater(1.2)


func test_command_capacity_scales_with_ability() -> void:
	var poor := WarUnits.capacity({"leadership": 20, "tactics": 20, "discipline": 20, "experience": 20})
	var captain := WarUnits.capacity({"leadership": 40, "tactics": 40, "discipline": 40, "experience": 40})
	var general := WarUnits.capacity({"leadership": 62, "tactics": 62, "discipline": 62, "experience": 60})
	var great := WarUnits.capacity({"leadership": 85, "tactics": 85, "discipline": 85, "experience": 80})
	assert_bool(poor >= 50 and poor <= 200).is_true()
	assert_bool(captain >= 200 and captain <= 700).is_true()
	assert_bool(general >= 1000 and general <= 3000).is_true()
	assert_int(great).is_greater(4000)
	assert_float(WarUnits.overload(3000, 100)).is_greater(1.0)
	assert_float(WarUnits.overload(80, 100)).is_equal(0.0)


# --- couriers: delay, old order persists, loss (R§21-22) ---------------------------------

func test_unit_order_arrives_after_courier_delay_and_old_order_persists() -> void:
	var c := _mk()
	var far := _far_node(c)
	var id := c.spawn_army("player", far, 600, "loyal")
	c.set_army_owner(id, "personal")
	var u := _first(c, id, "infantry")
	var uid := int(u["id"])
	var start := c.unit_pos(uid)
	var res := c.order_unit(uid, {"behavior": "advance", "node": 0})
	assert_bool(res["ok"]).is_true()
	var courier: Dictionary = res["courier"]
	var eta := int(courier["eta_hours"])
	assert_int(eta).is_greater(2)
	for h in eta - 1:
		c.tick_hour(h, {})
		var cur := c.unit(uid)
		assert_str(String((cur["order"] as Dictionary)["behavior"])).is_equal("hold")
		assert_bool(bool(cur["detached"])).is_false()
		assert_float(c.unit_pos(uid).distance_to(start)).is_equal(0.0)
	var pending: Array = c.orders()
	assert_int(pending.size()).is_equal(1)
	assert_str(String(pending[0]["state"])).is_equal("riding")
	# the order lands (a courier can also be late) and the piece starts walking
	var guard := 0
	while (c.couriers() as Array).size() > 0 and guard < 30:
		c.tick_hour(guard, {})
		guard += 1
	var lost: bool = String((c.unit(uid)["order"] as Dictionary)["behavior"]) == "hold"
	if not lost:
		assert_str(String((c.unit(uid)["order"] as Dictionary)["behavior"])).is_equal("advance")
		assert_bool(bool(c.unit(uid)["detached"])).is_true()
		var p1 := c.unit_pos(uid)
		for h in 5:
			c.tick_hour(h, {})
		var p2 := c.unit_pos(uid)
		assert_float(p2.distance_to(start)).is_greater(p1.distance_to(start))   # it does not teleport
		assert_float(p2.distance_to(c.node_pos(0))).is_less(start.distance_to(c.node_pos(0)))
		assert_bool(c.unit(uid)["state"] in ["moving", "idle"]).is_true()


func test_some_couriers_are_lost_or_late_and_the_player_only_learns_by_silence() -> void:
	var c := _mk()
	var far := _far_node(c)
	var id := c.spawn_army("player", far, 700, "loyal")
	c.set_army_owner(id, "personal")
	c.spawn_army(ENEMY, far, 200, "loyal")   # enemy riders around the recipients
	var sent := 0
	for u: Dictionary in c.army_units(id):
		var r := c.order_unit(int(u["id"]), {"behavior": "hold"})
		if bool(r["ok"]):
			sent += 1
	assert_int(sent).is_equal(10)
	for h in 130:
		c.tick_hour(h, {})
	var delivered := 0
	var silent := 0
	for o: Dictionary in c.orders():
		if o["state"] == "acked":
			delivered += 1
		elif o["state"] == "silent":
			silent += 1
	assert_int(delivered + silent).is_equal(10)
	assert_int(delivered).is_greater(0)
	assert_int(silent).is_greater(0)   # some riders never came back


func test_order_needing_a_point_or_target_is_validated() -> void:
	var c := _mk()
	var id := c.spawn_army("player", 0, 500, "loyal")
	c.set_army_owner(id, "personal")
	var u := _first(c, id, "infantry")
	assert_bool(c.order_unit(int(u["id"]), {"behavior": "advance"})["ok"]).is_false()
	assert_bool(c.order_unit(int(u["id"]), {"behavior": "follow"})["ok"]).is_false()
	assert_bool(c.order_unit(int(u["id"]), {"behavior": "nonsense"})["ok"]).is_false()
	assert_bool(c.order_unit(int(u["id"]), {"behavior": "hold"})["ok"]).is_true()
	assert_bool(c.order_unit(int(u["id"]), {"behavior": "retreat"})["ok"]).is_true()   # goes home by itself
	var est := c.estimate_order(int(u["id"]), c.node_pos(1))
	assert_float(float(est["distance"])).is_greater(100.0)
	assert_float(float(est["hours"])).is_greater(0.5)
	assert_str(String(est["terrain"])).is_not_empty()


# --- fog of war (R§23-24) ----------------------------------------------------------------

func _scene_with_scout(c: Campaign, enemy_men: int) -> Dictionary:
	# player army at node 0, enemy at the nearest neighbour; the scout piece is placed next to the enemy
	var n := 1
	var bl := 1e18
	for i in range(1, WorldGen.settlements.size()):
		var p := c.path(0, i)
		if not p.is_empty() and c.path_length(p) < bl:
			bl = c.path_length(p)
			n = i
	var me := c.spawn_army("player", 0, 800, "loyal")
	c.set_army_owner(me, "personal")
	var foe := c.spawn_army(ENEMY, n, enemy_men, "loyal")
	return {"me": me, "foe": foe, "node": n}


func test_enemy_is_unknown_until_seen_then_estimated_and_confirmed_by_scouts() -> void:
	var c := _mk()
	var far := _far_node(c)
	var me := c.spawn_army("player", 0, 800, "loyal")
	c.set_army_owner(me, "personal")
	var foe := c.spawn_army(ENEMY, far, 500, "loyal")
	c.tick_hour(0, {})
	assert_int((c.enemy_pieces() as Array).size()).is_equal(0)   # nothing is magically known
	# a scout team rides up to the enemy
	var scouts := _first(c, me, "scout")
	var sid := int(scouts["id"])
	var enemy_pos := c.node_pos(far)
	c.order_unit(sid, {"behavior": "advance", "x": enemy_pos.x + 480.0, "y": enemy_pos.y})
	var seen := {}
	for h in 300:
		c.tick_hour(h, {})
		var ep: Array = c.enemy_pieces()
		if not ep.is_empty():
			seen = ep[0]
			break
	assert_bool(seen.is_empty()).is_false()
	var truth := 0
	for a: Dictionary in c.armies():
		if int(a["id"]) == foe:
			truth = int((a["strength"]))
	# estimates honestly bracket the truth unless a scout confirmed it
	assert_int(int(seen["est_min"])).is_less_equal(truth)
	assert_int(int(seen["est_max"])).is_greater_equal(truth)
	assert_str(String(seen["label"])).is_not_empty()
	# scouts close in: confirmed exactly, composition revealed (the player re-sends if a rider never came back)
	var exact := false
	for attempt in 4:
		c.order_unit(sid, {"behavior": "advance", "x": enemy_pos.x + 120.0, "y": enemy_pos.y})
		for h in 70:
			c.tick_hour(h, {})
			for e: Dictionary in c.enemy_pieces():
				if bool(e["exact"]) and int(e["age_hours"]) == 0:
					exact = true
					assert_int(int(e["est_min"])).is_equal(truth)
					assert_int(int(e["est_max"])).is_equal(truth)
					assert_bool((e["comp"] as Dictionary).size() > 0).is_true()
			if exact:
				break
		if exact:
			break
	assert_bool(exact).is_true()


func test_sighting_goes_stale_and_the_marker_says_when_it_was_last_confirmed() -> void:
	var c := _mk()
	var s := _scene_with_scout(c, 400)
	var foe_pos := c.node_pos(int(s["node"]))
	var scout := _first(c, int(s["me"]), "scout")
	c.order_unit(int(scout["id"]), {"behavior": "advance", "x": foe_pos.x + 100.0, "y": foe_pos.y})
	var sid := int(scout["id"])
	for h in 120:
		c.tick_hour(h, {})
		if not (c.enemy_pieces() as Array).is_empty() and bool((c.enemy_pieces()[0] as Dictionary)["exact"]):
			break
	var e0: Dictionary = c.enemy_pieces()[0]
	assert_bool(bool(e0["exact"])).is_true()
	# the scout rides home; the marker stays where the enemy was
	c.order_unit(sid, {"behavior": "retreat", "x": c.node_pos(0).x, "y": c.node_pos(0).y})
	for h in 30:
		c.tick_hour(h, {})
	var aged: Array = c.enemy_pieces().filter(func(p: Dictionary) -> bool: return int(p["age_hours"]) > 0)
	if not aged.is_empty():
		var e1: Dictionary = aged[0]
		assert_str(String(e1["label"])).contains("h ago")
		assert_float(float(e1["radius"])).is_greater(0.0)
		assert_float(float(e1["confidence"])).is_less(1.0)
		assert_bool(e1["pos"].distance_to(e0["pos"]) < 1.0).is_true()


# --- engagements (R§7-8) -----------------------------------------------------------------

func _clash(seed_hours: int, mine_q: float, mine_men: int, foe_men: int, foe_q := 0.3, kind := "infantry") -> Dictionary:
	var c := _mk()
	var me := c.spawn_army("player", 0, mine_men, "loyal")
	var foe := c.spawn_army(ENEMY, 1, foe_men, "loyal")
	c.advance_hours(seed_hours)
	var mu := c.army_units(me)
	var fu := c.army_units(foe)
	var mine: Array = []
	var theirs: Array = []
	for u: Dictionary in mu:
		if u["kind"] == kind:
			mine.append(int(u["id"]))
	for u: Dictionary in fu:
		if u["kind"] == kind:
			theirs.append(int(u["id"]))
	# rig quality
	for id in mine:
		c.tune_unit(id, {"quality": mine_q})
	for id in theirs:
		c.tune_unit(id, {"quality": foe_q})
	var pos := c.node_pos(0) + Vector2(300, 0)
	var e := c.open_engagement(mine, theirs, pos.x, pos.y)
	var guard := 0
	while String(c.engagement_view(int(e["id"]))["status"]) != "ended" and guard < 60:
		c.tick_hour(guard, {})
		guard += 1
	return {"c": c, "eng": c.engagement_view(int(e["id"])), "me": me, "foe": foe}


func test_engagement_is_deterministic_and_records_its_factors() -> void:
	var r1 := _clash(3, 0.8, 900, 700)
	var r2 := _clash(3, 0.8, 900, 700)
	var e1: Dictionary = r1["eng"]
	var e2: Dictionary = r2["eng"]
	assert_str(String(e1["status"])).is_equal("ended")
	assert_int(int(e1["rounds"])).is_equal(int(e2["rounds"]))
	assert_str(JSON.stringify(e1["cas"])).is_equal(JSON.stringify(e2["cas"]))
	assert_str(String(e1["outcome"])).is_equal(String(e2["outcome"]))
	assert_str(JSON.stringify(e1["factors"])).is_equal(JSON.stringify(e2["factors"]))
	assert_int(int(e1["rounds"])).is_greater(1)
	var f: Dictionary = (e1["factors"] as Dictionary)["a"]
	for k: String in ["quality", "morale", "fatigue", "terrain", "commander", "formation", "supply", "weather", "surprise", "numbers", "position"]:
		assert_bool(f.has(k)).is_true()
	assert_bool((e1["log"] as Array).size() >= 2).is_true()
	assert_str(String(e1["name"])).contains("Engagement")


func test_quality_and_numbers_decide_and_variance_stays_small() -> void:
	# veterans beat a rabble twice their size... no: 900 veterans beat 700 peasants every time
	var wins := 0
	var lost_ratios: Array = []
	for k in 12:
		var r := _clash(k * 2, 0.9, 900, 700, 0.25)
		var e: Dictionary = r["eng"]
		if String(e["outcome"]) == "a":
			wins += 1
		lost_ratios.append(float(e["casualties_player"]) / maxf(1.0, float(e["casualties_enemy"])))
	assert_int(wins).is_equal(12)
	var lo := 1e9
	var hi := 0.0
	for x: float in lost_ratios:
		lo = minf(lo, x)
		hi = maxf(hi, x)
	assert_float(hi / maxf(lo, 0.001)).is_less(1.6)   # small bounded variance in the exchange
	# and the reverse: the rabble does not win because the dice rolled 7
	var upsets := 0
	for k in 12:
		var r2 := _clash(k * 2, 0.25, 500, 800, 0.9)
		if String(r2["eng"]["outcome"]) == "a":
			upsets += 1
	assert_int(upsets).is_equal(0)


func test_terrain_narrows_big_armies_and_weakens_cavalry() -> void:
	var cav := [{"kind": "heavy_cav", "men": 300, "quality": 0.7, "morale": 0.8, "fatigue": 0.0, "order": {"behavior": "advance"}}]
	var plain := WarUnits.side_power(cav, {"terrain": WarUnits.TERRAIN["plain"], "role": "attack"})
	var forest := WarUnits.side_power(cav, {"terrain": WarUnits.TERRAIN["forest"], "role": "attack"})
	assert_float(float(forest["power"])).is_less(float(plain["power"]) * 0.8)
	var mass := [{"kind": "infantry", "men": 3000, "quality": 0.6, "morale": 0.8, "fatigue": 0.0, "order": {"behavior": "advance"}}]
	var wide := WarUnits.side_power(mass, {"terrain": WarUnits.TERRAIN["plain"], "role": "attack"})
	var narrow := WarUnits.side_power(mass, {"terrain": WarUnits.TERRAIN["mountain"], "role": "attack"})
	assert_float(float((narrow["factors"] as Dictionary)["numbers"])).is_less(0.5)
	assert_float(float(narrow["power"])).is_less(float(wide["power"]) * 0.5)
	var hard := [{"kind": "infantry", "men": 300, "quality": 0.6, "morale": 0.8, "fatigue": 0.0, "order": {"behavior": "hold"}}]
	var tired := [{"kind": "infantry", "men": 300, "quality": 0.6, "morale": 0.8, "fatigue": 0.9, "order": {"behavior": "hold"}}]
	assert_float(float(WarUnits.side_power(tired, {})["power"])).is_less(float(WarUnits.side_power(hard, {})["power"]))
	# spearmen counter cavalry
	var sp := [{"kind": "spear", "men": 300, "quality": 0.6, "morale": 0.8, "fatigue": 0.0, "order": {"behavior": "hold"}}]
	assert_float(float(WarUnits.side_power(sp, {"foe_mounted": 1.0})["power"])).is_greater(float(WarUnits.side_power(sp, {"foe_mounted": 0.0})["power"]) * 1.3)


func test_terrain_comes_from_the_world_and_is_cached() -> void:
	var c := _mk()
	var seen := {}
	for i in 400:
		var p := Vector2(-3800.0 + fmod(float(i) * 397.0, 7600.0), -3800.0 + fmod(float(i) * 811.0, 7600.0))
		seen[String(c.terrain_at(p)["id"])] = true
	assert_bool(seen.size() >= 3).is_true()
	var p0 := Vector2(120, 80)
	assert_str(String(c.terrain_at(p0)["id"])).is_equal(String(c.terrain_at(p0 + Vector2(3, 3))["id"]))


func test_contact_opens_an_engagement_the_commander_fights_until_it_breaks() -> void:
	var c := _mk()
	var s := _scene_with_scout(c, 250)
	var me := int(s["me"])
	var foe_node := int(s["node"])
	var target := c.node_pos(foe_node)
	var ids: Array = []
	for u: Dictionary in c.army_units(me):
		if u["kind"] in ["infantry", "spear", "heavy_cav"]:
			ids.append(int(u["id"]))
	for r: Dictionary in c.order_units(ids, {"behavior": "advance", "x": target.x, "y": target.y}):
		assert_bool(r["ok"]).is_true()
	var opened := false
	var guard := 0
	while guard < 200:
		c.tick_hour(guard, {})
		guard += 1
		if not (c.engagements() as Array).is_empty():
			opened = true
			break
	assert_bool(opened).is_true()
	var e: Dictionary = c.engagements()[0]
	assert_bool(bool(e["player_involved"])).is_true()
	assert_str(String(e["name"])).contains("Engagement")
	assert_int(int(e["your_men"])).is_greater(0)
	assert_str(String(e["commander"])).is_not_empty()
	# it goes on by itself, hour after hour, without any orders from the player
	var status_seen := {}
	guard = 0
	while guard < 80:
		c.tick_hour(guard, {})
		guard += 1
		var v: Dictionary = c.engagement_view(int(e["id"]))
		status_seen[v["status"]] = true
		if v["status"] == "ended":
			break
	assert_bool(status_seen.has("ended")).is_true()
	var done: Dictionary = c.engagement_view(int(e["id"]))
	assert_str(String(done["outcome"])).is_not_empty()
	assert_bool(int(done["casualties_enemy"]) > 0).is_true()
	assert_bool((c.battles() as Array).size() > 0).is_true()
	# the enemy estimate is a range or an exact figure the player's side has actually seen
	assert_int(int(done["enemy_max"])).is_greater_equal(int(done["enemy_min"]))


func test_player_can_intervene_and_withdraw_by_courier() -> void:
	var r := _clash(0, 0.5, 900, 900, 0.5)   # runs to the end; check a fresh one for intervention
	assert_str(String(r["eng"]["status"])).is_equal("ended")
	var c := _mk()
	var me := c.spawn_army("player", 0, 900, "loyal")
	c.set_army_owner(me, "personal")
	var foe := c.spawn_army(ENEMY, 1, 900, "loyal")
	var mine: Array = []
	var theirs: Array = []
	for u: Dictionary in c.army_units(me):
		if u["kind"] == "infantry":
			mine.append(int(u["id"]))
	for u: Dictionary in c.army_units(foe):
		if u["kind"] == "infantry":
			theirs.append(int(u["id"]))
	var e := c.open_engagement(mine, theirs, c.node_pos(0).x + 200.0, c.node_pos(0).y)
	c.tick_hour(0, {})
	assert_bool(c.intervene(int(e["id"]), "take_command")["ok"]).is_true()
	var w := c.intervene(int(e["id"]), "withdraw")
	assert_bool(w["ok"]).is_true()
	assert_int((c.couriers() as Array).size()).is_greater(0)
	# still fighting until the couriers arrive
	assert_str(String(c.engagement_view(int(e["id"]))["status"])).is_not_equal("ended")
	var ended := false
	for h in 40:
		c.tick_hour(h, {})
		if String(c.engagement_view(int(e["id"]))["status"]) == "ended":
			ended = true
			break
	assert_bool(ended).is_true()


func test_personality_shapes_how_orders_are_carried_out() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 5
	var sit := {"foe_ratio": 0.8, "morale": 0.8}
	assert_str(String(WarUnits.personality_reaction("aggressive", "hold", sit, r)["behavior"])).is_equal("advance")
	assert_str(String(WarUnits.personality_reaction("loyal", "hold", sit, r)["behavior"])).is_equal("hold")
	assert_str(String(WarUnits.personality_reaction("stubborn", "retreat", sit, r)["behavior"])).is_equal("hold")
	assert_str(String(WarUnits.personality_reaction("independent", "advance", {"foe_ratio": 3.0, "morale": 0.7}, r)["behavior"])).is_equal("hold")
	assert_str(String(WarUnits.personality_reaction("cautious", "advance", {"foe_ratio": 2.0, "morale": 0.7}, r)["behavior"])).is_equal("hold")
	assert_str(String(WarUnits.personality_reaction("loyal", "advance", {"foe_ratio": 3.0, "morale": 0.7}, r)["behavior"])).is_equal("advance")


func test_behaviours_move_pieces_differently() -> void:
	var c := _mk()
	var far := _far_node(c)
	var id := c.spawn_army("player", 0, 1500, "loyal")
	c.set_army_owner(id, "personal")
	var inf := _first(c, id, "infantry")
	var lc := _first(c, id, "light_cav")
	var dest := c.node_pos(far)
	c.order_unit(int(inf["id"]), {"behavior": "advance", "x": dest.x, "y": dest.y})
	c.order_unit(int(lc["id"]), {"behavior": "advance", "x": dest.x, "y": dest.y})
	var hv := _first(c, id, "heavy_cav")
	c.order_unit(int(hv["id"]), {"behavior": "hold"})
	var sp := _first(c, id, "spear")
	c.order_unit(int(sp["id"]), {"behavior": "charge", "x": dest.x, "y": dest.y})
	for h in 30:
		c.tick_hour(h, {})
	var d_inf := c.unit_pos(int(inf["id"])).distance_to(c.node_pos(0))
	var d_lc := c.unit_pos(int(lc["id"])).distance_to(c.node_pos(0))
	var d_sp := c.unit_pos(int(sp["id"])).distance_to(c.node_pos(0))
	assert_float(d_lc).is_greater(d_inf)     # light cavalry outruns infantry
	assert_float(d_sp).is_greater(d_inf * 0.9)   # a charge is faster but tires
	assert_float(float(c.unit(int(sp["id"]))["fatigue"])).is_greater(float(c.unit(int(inf["id"]))["fatigue"]) * 0.9)
	assert_float(c.unit_pos(int(hv["id"])).distance_to(c.node_pos(0))).is_less(1.0)


# --- persistence and perf ----------------------------------------------------------------

func test_round_trip_keeps_units_orders_sightings_and_engagements() -> void:
	var c := _mk()
	var far := _far_node(c)
	var me := c.spawn_army("player", 0, 1000, "loyal")
	c.set_army_owner(me, "personal")
	c.spawn_army(ENEMY, far, 400, "aggressive")
	var inf := _first(c, me, "infantry")
	c.split_unit(int(inf["id"]), 60)
	c.order_unit(int(inf["id"]), {"behavior": "advance", "node": far})
	c.tick_hour(0, {})
	c.tick_hour(1, {})
	var mine: Array = []
	var theirs: Array = []
	for a: Dictionary in c.armies():
		for u: Dictionary in a["units"]:
			if u["kind"] == "spear":
				(mine if a["faction"] == "player" else theirs).append(int(u["id"]))
	c.open_engagement(mine, theirs, 100.0, 100.0)
	c.tick_hour(2, {})
	var data := JSON.stringify(c.serialize())
	var back: Variant = JSON.parse_string(data)
	var c2 := Campaign.new()
	c2.deserialize(back)
	assert_str(JSON.stringify(c2.serialize())).is_equal(data)
	assert_int((c2.army_units(me) as Array).size()).is_equal((c.army_units(me) as Array).size())
	assert_int((c2.orders() as Array).size()).is_equal((c.orders() as Array).size())
	assert_int((c2.engagements() as Array).size()).is_equal((c.engagements() as Array).size())
	# the restored simulation continues identically
	for h in 6:
		c.tick_hour(3 + h, {})
		c2.tick_hour(3 + h, {})
	assert_str(JSON.stringify(c2.own_pieces().map(func(p: Dictionary) -> Array: return [p["id"], p["men"], snappedf(p["pos"].x, 0.01)]))).is_equal(
		JSON.stringify(c.own_pieces().map(func(p: Dictionary) -> Array: return [p["id"], p["men"], snappedf(p["pos"].x, 0.01)])))


func _big_field(c: Campaign, detached_each: int) -> void:
	var nodes := WorldGen.settlements.size()
	for i in 20:
		var fac := "player" if i < 10 else ENEMY
		var id := c.spawn_army(fac, i % nodes, 400 + i * 20, "loyal")
		if fac == "player":
			c.set_army_owner(id, "personal")
	for a: Dictionary in c.armies():
		if a["faction"] != "player":
			continue
		var n := 0
		for u: Dictionary in a["units"]:
			if n >= detached_each:
				break
			var dest := c.node_pos((int(a["node"]) + 3 + n) % nodes)
			c.order_unit(int(u["id"]), {"behavior": "advance", "x": dest.x, "y": dest.y})
			n += 1


func test_perf_20_armies_of_10_units_over_a_day() -> void:
	var c := _mk()
	_big_field(c, 0)
	assert_int((c.armies() as Array).size()).is_equal(20)
	var t0 := Time.get_ticks_usec()
	for h in 24:
		c.tick_hour(h, {})
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("[perf] war 20x10 attached, 24h: %.2f ms" % ms)
	assert_float(ms).is_less(20.0)


func test_perf_with_moving_pieces_and_fog() -> void:
	var c := _mk()
	_big_field(c, 3)
	for h in 3:   # deliver the orders and warm the terrain cache
		c.tick_hour(h, {})
	var t0 := Time.get_ticks_usec()
	for h in 24:
		c.tick_hour(h, {})
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("[perf] war 20x10, 30 detached pieces moving, 24h: %.2f ms  phases(us) %s" % [ms, c.perf_stats()])
	assert_float(ms).is_less(90.0)   # includes sampling the terrain under every piece for the first time
	var t1 := Time.get_ticks_usec()
	var pieces: Array = c.own_pieces()
	var enemies: Array = c.enemy_pieces()
	var ms2 := float(Time.get_ticks_usec() - t1) / 1000.0
	assert_int(pieces.size()).is_greater(90)
	assert_float(ms2).is_less(20.0)
	assert_int(enemies.size()).is_greater_equal(0)


func test_all_sixteen_behaviours_run_without_teleporting() -> void:
	var ids: Array = WarUnits.MENU_PRIMARY + WarUnits.MENU_MORE
	assert_int(ids.size()).is_equal(16)
	var c := _mk()
	var far := _far_node(c)
	var id := c.spawn_army("player", 0, 1600, "loyal")
	c.set_army_owner(id, "personal")
	c.spawn_army(ENEMY, far, 300, "loyal")
	var units := c.army_units(id)
	var dest := c.node_pos(1)
	var prev: Dictionary = {}
	for i in ids.size():
		var uid := int(units[i % units.size()]["id"])
		var other := int(units[(i + 1) % units.size()]["id"])
		var order := {"behavior": ids[i], "x": dest.x, "y": dest.y, "target_unit": other}
		var r := c.order_unit(uid, order)
		assert_bool(r["ok"]).is_true()
		prev[uid] = c.unit_pos(uid)
	for h in 12:
		c.tick_hour(h, {})
		for uid: int in prev:
			var p := c.unit_pos(uid)
			# nothing jumps further than a fast rider can go in an hour
			assert_float(p.distance_to(prev[uid])).is_less(1200.0)
			prev[uid] = p
	for u: Dictionary in c.army_units(id):
		assert_bool(u["state"] in ["idle", "moving", "retreating", "engaged", "capturing"]).is_true()
	assert_int(_men(c, id)).is_greater(1000)


func test_overloaded_player_sends_muddled_orders() -> void:
	var c := _mk()
	var far := _far_node(c)
	var id := c.spawn_army("player", far, 3000, "loyal")
	c.set_army_owner(id, "personal")
	var dest := c.node_pos(0)
	for u: Dictionary in c.army_units(id):
		c.order_unit(int(u["id"]), {"behavior": "advance", "x": dest.x, "y": dest.y})
	for h in 90:
		c.tick_hour(h, {})
	var garbled := 0
	for u: Dictionary in c.army_units(id):
		if (u["order"] as Dictionary).get("garbled", false):
			garbled += 1
	assert_int(garbled).is_greater(0)
	# a modest command is not muddled
	var c2 := _mk()
	var id2 := c2.spawn_army("player", far, 300, "loyal")
	c2.set_army_owner(id2, "personal")
	c2.order_unit(int(_first(c2, id2, "infantry")["id"]), {"behavior": "advance", "x": dest.x, "y": dest.y})
	for h in 60:
		c2.tick_hour(h, {})
	for u: Dictionary in c2.army_units(id2):
		assert_bool((u["order"] as Dictionary).get("garbled", false)).is_false()


func test_legacy_army_orders_and_strategic_battles_still_drive_attached_units() -> void:
	var c := _mk()
	var n := 1
	var strong := c.spawn_army("player", n, 500, "loyal")
	var weak := c.spawn_army(ENEMY, n, 100, "loyal")
	var det := c.detach(int(_first(c, strong, "light_cav")["id"]), 20)
	assert_int(det).is_greater(0)
	var det_men := int(c.unit(det)["men"])
	for h in 3:
		c.tick_hour(h, {})
	# the army-level battle cost the units with the army, not the detached piece
	assert_bool(c.battles().size() > 0).is_true()
	assert_int(int(c.unit(det)["men"])).is_equal(det_men)
	var total := 0
	for a: Dictionary in c.armies():
		if a["faction"] == "player":
			total = int(a["strength"])
			var sum := 0
			for u: Dictionary in a["units"]:
				sum += int(u["men"])
			assert_int(sum).is_equal(total)
	assert_int(weak).is_greater(0)
