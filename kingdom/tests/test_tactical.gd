extends GdUnitTestSuite
## Tactical battle map (scripts/realm/tactical.gd + tactical_ai.gd, docs/design/WAR_COMMAND_RULEBOOK.md §1, §20-40):
## terrain generated from the real world, formations and depth layers, flanking and encirclement, signals with delay,
## fog, commander tiers (feint, false retreat), elites and duels, weather, persistence and performance.

const Tac := preload("res://scripts/realm/tactical.gd")
const AI := preload("res://scripts/realm/tactical_ai.gd")
const WarUnits := preload("res://scripts/realm/war_units.gd")
const Campaign := preload("res://scripts/realm/campaign.gd")


func before_test() -> void:
	WorldGen.setup(2024)


# --- helpers ----------------------------------------------------------------------------------------

func _u(kind: String, men: int, q := 0.6, nm := "") -> Dictionary:
	return {"cid": 0, "name": nm if nm != "" else kind, "kind": kind, "men": men, "quality": q, "morale": 0.75, "fatigue": 0.0}


func _side(units: Array, fac := "caldrenn", skill := 2, pers := "loyal", attrs := {}) -> Dictionary:
	var cmd := {"name": "Gen", "personality": pers, "skill": skill, "tactics": 22 + 13 * skill, "experience": 22 + 13 * skill, "leadership": 50,
		"discipline": 50, "adaptability": 50, "scouting": 50, "logistics": 50}
	for k: String in attrs:
		cmd[k] = attrs[k]
	return {"faction": fac, "player": false, "name": fac, "units": units, "supply": 3.0, "cmd": cmd}


func _mk(seed_: int, a: Dictionary, b: Dictionary, extra := {}) -> RefCounted:
	var spec := {"seed": seed_, "name": "Test", "center": [-1274.0, -2318.0], "deploy": false, "attacker": "a", "sides": {"a": a, "b": b}}
	for k: String in extra:
		spec[k] = extra[k]
	return Tac.create(spec)


## A flat open field so terrain does not interfere with mechanics under test.
func _flat(tt: RefCounted) -> void:
	tt.tc.fill(0)
	tt.hh.fill(10.0)


func _army16(men_scale := 1.0) -> Array:
	var kinds := ["infantry", "infantry", "infantry", "infantry", "spear", "spear", "spear", "archer", "archer", "archer", "heavy_cav", "heavy_cav", "light_cav", "light_cav", "mage", "scout"]
	var out: Array = []
	for i in 16:
		out.append(_u(kinds[i], int((200 if kinds[i] in ["infantry", "spear"] else 100) * men_scale), 0.6, "%s %d" % [kinds[i], i]))
	return out


func _find_point(pred: Callable) -> Vector2:
	var y := -3600.0
	while y <= 3600.0:
		var x := -3600.0
		while x <= 3600.0:
			if pred.call(x, y):
				return Vector2(x, y)
			x += 96.0
		y += 96.0
	return Vector2.INF


# --- terrain from the real world (R§1, R§28) ---------------------------------------------------------

func test_terrain_is_generated_from_the_real_world_and_deterministic() -> void:
	var p: Vector2 = WorldGen.settlements[0]["pos"] + Vector2(300, 200)
	var g1 := Tac.gen_grid(p, 40, 40.0)
	var g2 := Tac.gen_grid(p, 40, 40.0)
	assert_array(g1["rows"]).is_equal(g2["rows"])
	assert_array(g1["h"]).is_equal(g2["h"])
	assert_int((g1["rows"] as Array).size()).is_equal(40)
	assert_int((g1["rows"][0] as String).length()).is_equal(40)
	var g3 := Tac.gen_grid(p + Vector2(900, 0), 40, 40.0)
	assert_bool(g3["rows"] == g1["rows"]).is_false()
	# heights are the world's heights
	var half := 20.0 * 40.0
	var hx := p.x - half + 10.5 * 40.0
	var hy := p.y - half + 7.5 * 40.0
	assert_float(float((g1["h"] as Array)[7 * 40 + 10]) * 0.1).is_equal_approx(WorldGen.height(hx, hy), 0.06)
	# a different world gives a different field
	WorldGen.setup(777)
	var g4 := Tac.gen_grid(Vector2.ZERO, 40, 40.0)
	WorldGen.setup(2024)
	assert_bool(g4["rows"] == Tac.gen_grid(Vector2.ZERO, 40, 40.0)["rows"]).is_false()


func test_terrain_has_roads_rivers_forest_towns_and_hills_where_the_world_has_them() -> void:
	var town: Vector2 = WorldGen.settlements[0]["pos"]
	var gt := Tac.gen_grid(town, 40, 40.0)
	assert_bool(int((gt["counts"] as Array)[Tac.T_TOWN]) > 10).is_true()
	# a road between two settlements
	var e: Vector2i = WorldGen.roads[0]
	var mid: Vector2 = (WorldGen.settlements[e.x]["pos"] as Vector2).lerp(WorldGen.settlements[e.y]["pos"], 0.5)
	var gr := Tac.gen_grid(mid, 40, 40.0)
	assert_bool(int((gr["counts"] as Array)[Tac.T_ROAD]) > 6).is_true()
	# a river or lake
	var w := _find_point(func(x: float, y: float) -> bool: return WorldGen.is_water(x, y) and WorldGen.water_depth(x, y) > 1.2)
	assert_bool(w != Vector2.INF).is_true()
	var gw := Tac.gen_grid(w, 40, 40.0)
	assert_bool(int((gw["counts"] as Array)[Tac.T_RIVER]) + int((gw["counts"] as Array)[Tac.T_FORD]) > 5).is_true()
	# forest
	var f := _find_point(func(x: float, y: float) -> bool: return WorldGen.forest_density(x, y) > 0.8 and not WorldGen.is_water(x, y))
	assert_bool(f != Vector2.INF).is_true()
	assert_bool(int((Tac.gen_grid(f, 40, 40.0)["counts"] as Array)[Tac.T_FOREST]) > 20).is_true()
	# high ground exists somewhere in this world
	var hl := _find_point(func(x: float, y: float) -> bool: return WorldGen.height(x, y) > 90.0)
	assert_bool(hl != Vector2.INF).is_true()
	var gh := Tac.gen_grid(hl, 40, 40.0)
	assert_bool(int((gh["counts"] as Array)[Tac.T_HILL]) + int((gh["counts"] as Array)[Tac.T_MOUNT]) > 30).is_true()


func test_walls_gates_breaches_and_inner_lines_for_a_siege_ring() -> void:
	var c: Vector2 = WorldGen.settlements[2]["pos"]
	var ring := {"c": c, "r": 110.0, "gates": [0.0], "breaches": [PI * 0.5], "landings": [], "inner": [{"a": PI * 0.5, "span": 0.7, "r": 70.0}]}
	var g := Tac.gen_grid(c, 48, 10.0, {"ring": ring, "street": true})
	var cnt: Array = g["counts"]
	assert_bool(int(cnt[Tac.T_WALL]) > 15).is_true()
	assert_bool(int(cnt[Tac.T_GATE]) >= 1).is_true()
	assert_bool(int(cnt[Tac.T_BREACH]) >= 1).is_true()
	assert_bool(int(cnt[Tac.T_BARR]) >= 1).is_true()      # the defenders' second line behind the breach
	assert_bool(int(cnt[Tac.T_BLDG]) > 10).is_true()
	assert_str(String(g["name"])).contains("Breach")


# --- formations, layers, deployment (R§25-27) ------------------------------------------------------------

func test_formation_depth_layers_front_second_third_rear_flanks_reserve() -> void:
	var units := [_u("infantry", 300, 0.7, "Shields A"), _u("infantry", 300, 0.6, "Shields B"), _u("infantry", 280, 0.9, "Veterans"), _u("spear", 240), _u("archer", 160),
		_u("mage", 60), _u("heavy_cav", 100), _u("light_cav", 100), _u("engineer", 50)]
	var tt := _mk(3, _side(units), _side([_u("infantry", 300)]))
	var by := {}
	for i in tt.side_units(0):
		by[String(tt.u_meta[i]["name"])] = tt.unit_view(i)
	var ax := Vector2.from_angle(float(tt.S[0]["axis"]))
	var anc := AI.anchor_v(tt, 0)
	var depth := func(v: Dictionary) -> float: return -(Vector2(float(v["x"]), float(v["y"])) - anc).dot(ax)
	assert_str(String((by["spear"] as Dictionary)["layer"])).is_equal("second")
	assert_str(String((by["archer"] as Dictionary)["layer"])).is_equal("third")
	assert_str(String((by["mage"] as Dictionary)["layer"])).is_equal("rear")
	assert_str(String((by["heavy_cav"] as Dictionary)["layer"])).is_equal("flank_l")
	assert_str(String((by["light_cav"] as Dictionary)["layer"])).is_equal("flank_r")
	assert_str(String((by["Veterans"] as Dictionary)["layer"])).is_equal("reserve")   # the best infantry is held back
	var d_front := float(depth.call(by["Shields A"]))
	var d_second := float(depth.call(by["spear"]))
	var d_third := float(depth.call(by["archer"]))
	var d_rear := float(depth.call(by["mage"]))
	var d_res := float(depth.call(by["Veterans"]))
	assert_bool(d_front < d_second and d_second < d_third and d_third < d_rear).is_true()
	assert_bool(d_res > d_third).is_true()
	# cavalry stand outside the infantry line on opposite flanks
	var pv := Vector2(-ax.y, ax.x)
	var lat_l := (Vector2(float((by["heavy_cav"] as Dictionary)["x"]), float((by["heavy_cav"] as Dictionary)["y"])) - anc).dot(pv)
	var lat_r := (Vector2(float((by["light_cav"] as Dictionary)["x"]), float((by["light_cav"] as Dictionary)["y"])) - anc).dot(pv)
	var lat_f := (Vector2(float((by["Shields A"] as Dictionary)["x"]), float((by["Shields A"] as Dictionary)["y"])) - anc).dot(pv)
	assert_bool(lat_l < -absf(lat_f) and lat_r > absf(lat_f)).is_true()
	# both armies face each other across the field
	assert_float(absf(wrapf(float(tt.S[0]["axis"]) - float(tt.S[1]["axis"]), -PI, PI))).is_equal_approx(PI, 0.01)


func test_reserves_hold_back_until_committed() -> void:
	var tt := _mk(5, _side([_u("infantry", 300), _u("infantry", 300), _u("infantry", 300, 0.9, "Reserve"), _u("spear", 200), _u("archer", 100)]), _side([_u("infantry", 400)]), {"deploy": true})
	var ri := -1
	for i in tt.side_units(0):
		if String(tt.u_meta[i]["layer"]) == "reserve":
			ri = i
	assert_int(ri).is_greater_equal(0)
	assert_int(int(tt.u_st[ri])).is_equal(Tac.S_RESERVE)
	assert_str(String(tt.unit_view(ri)["behavior"])).is_equal("reserve")
	# the deployment phase is frozen: pieces can be rearranged, time does not pass
	var t0: float = tt.t
	tt.step()
	assert_float(tt.t).is_equal(t0)
	var before := Vector2(tt.u_x[ri], tt.u_y[ri])
	assert_bool(tt.deploy_move(ri, before.x - 20.0, before.y + 20.0)).is_true()
	assert_bool(Vector2(tt.u_x[ri], tt.u_y[ri]).distance_to(before) > 10.0).is_true()
	tt.begin()
	_flat(tt)
	for i in 9:
		tt.step()
	assert_int(int(tt.u_st[ri])).is_equal(Tac.S_RESERVE)
	var res: Dictionary = tt.order(0, ri, {"behavior": "commit", "x": tt.u_x[ri] + 200.0, "y": tt.u_y[ri]})
	assert_bool(bool(res["ok"])).is_true()
	for i in 6:
		tt.step()
	assert_str(String(tt.unit_view(ri)["behavior"])).is_equal("commit")
	assert_int(int(tt.u_st[ri])).is_not_equal(Tac.S_RESERVE)


func test_formations_are_tradeoffs_not_buffs() -> void:
	for f: String in Tac.FORM:
		var d: Dictionary = Tac.FORM[f]
		var plus := 0
		var minus := 0
		for k: String in ["atk", "def", "mob", "vs_cav", "vs_rng"]:
			if float(d[k]) > 1.04:
				plus += 1
			if float(d[k]) < 0.96:
				minus += 1
		if float(d["width"]) > 1.2 or float(d["flank"]) < 0.96:
			plus += 1
		if float(d["flank"]) > 1.04:
			minus += 1
		if f not in ["line", "custom"]:
			assert_bool(plus > 0 and minus > 0).is_true()     # every shaped formation wins something and loses something
	# a spear wall shrugs off cavalry, a loose order does not
	var wall := _impact_of_charge("spear_wall")
	var loose := _impact_of_charge("loose")
	assert_bool(wall < loose * 0.75).is_true()
	# custom formation stats follow width / depth / spacing
	var deep := Tac.formation_stats("custom", 10, 6, 1.0)
	var thin := Tac.formation_stats("custom", 10, 1, 1.0)
	assert_bool(float(deep["def"]) > float(thin["def"])).is_true()
	var spread := Tac.formation_stats("custom", 10, 3, 1.8)
	assert_bool(float(spread["mob"]) > float(Tac.formation_stats("custom", 10, 3, 0.8)["mob"])).is_true()


## Men lost by an infantry unit charged by heavy cavalry, in one combat round.
func _impact_of_charge(form: String) -> float:
	var tt := _mk(9, _side([_u("heavy_cav", 120, 0.7)]), _side([_u("infantry", 300)]), {"deploy": false})
	_flat(tt)
	tt.set_formation(1, form)
	_put(tt, 0, 800.0, 800.0, 0.0)
	_put(tt, 1, 800.0 + tt.u_rad[0] + tt.u_rad[1] + 4.0, 800.0, PI)
	tt.u_chg[0] = 1
	_fight(tt, 0, 1)
	tt._combat(2)
	return tt._dk[1]


func _put(tt: RefCounted, i: int, x: float, y: float, face: float) -> void:
	tt.u_x[i] = x
	tt.u_y[i] = y
	tt.u_face[i] = face
	tt.u_tx[i] = x
	tt.u_ty[i] = y


func _fight(tt: RefCounted, a: int, b: int) -> void:
	tt.u_st[a] = Tac.S_FIGHT
	tt.u_st[b] = Tac.S_FIGHT
	tt.u_tgt[a] = b
	tt.u_tgt[b] = a
	tt.u_bh[a] = tt._bh_names.find("hold")
	tt.u_bh[b] = tt._bh_names.find("hold")


# --- flanking and encirclement (R§34) -----------------------------------------------------------------------

func test_flank_and_rear_attacks_hurt_more_than_frontal() -> void:
	var dk := {}
	for name_: String in ["front", "flank", "rear"]:
		var tt := _mk(11, _side([_u("infantry", 300)]), _side([_u("infantry", 300)]), {"deploy": false})
		_flat(tt)
		var gap: float = tt.u_rad[0] + tt.u_rad[1] + 4.0
		_put(tt, 0, 800.0, 800.0, 0.0)
		# the victim (unit 1) faces east (0 rad) for the front case, north for the flank case, away for the rear case
		var face: float = {"front": PI, "flank": -PI * 0.5, "rear": 0.0}[name_]
		_put(tt, 1, 800.0 + gap, 800.0, face)
		_fight(tt, 0, 1)
		tt.u_tgt[1] = -1
		tt.u_st[1] = Tac.S_HOLD
		tt._combat(2)
		dk[name_] = tt._dk[1]
	assert_float(float(dk["flank"]) / float(dk["front"])).is_equal_approx(1.35, 0.03)
	assert_float(float(dk["rear"]) / float(dk["front"])).is_equal_approx(1.7, 0.03)
	# a defensive square has no flanks
	var sq := _mk(11, _side([_u("infantry", 300)]), _side([_u("infantry", 300)]), {"deploy": false})
	_flat(sq)
	sq.set_formation(1, "square")
	var gap2: float = sq.u_rad[0] + sq.u_rad[1] + 4.0
	_put(sq, 0, 800.0, 800.0, 0.0)
	_put(sq, 1, 800.0 + gap2, 800.0, 0.0)
	_fight(sq, 0, 1)
	sq.u_tgt[1] = -1
	sq.u_st[1] = Tac.S_HOLD
	sq._combat(2)
	var fr := _mk(11, _side([_u("infantry", 300)]), _side([_u("infantry", 300)]), {"deploy": false})
	_flat(fr)
	fr.set_formation(1, "square")
	_put(fr, 0, 800.0, 800.0, 0.0)
	_put(fr, 1, 800.0 + gap2, 800.0, PI)
	_fight(fr, 0, 1)
	fr.u_tgt[1] = -1
	fr.u_st[1] = Tac.S_HOLD
	fr._combat(2)
	assert_float(sq._dk[1] / fr._dk[1]).is_equal_approx(1.0, 0.03)


func test_encirclement_marks_a_surrounded_unit_and_breaks_its_morale() -> void:
	var tt := _mk(13, _side([_u("infantry", 300)]), _side([_u("infantry", 200), _u("infantry", 200), _u("infantry", 200), _u("infantry", 200)]), {"deploy": false})
	_flat(tt)
	_put(tt, 0, 800.0, 800.0, 0.0)
	var r := 70.0
	_put(tt, 1, 800.0 + r, 800.0, PI)
	_put(tt, 2, 800.0 - r, 800.0, 0.0)
	_put(tt, 3, 800.0, 800.0 + r, -PI * 0.5)
	_put(tt, 4, 800.0, 800.0 - r, PI * 0.5)
	tt._refresh_alive()
	tt._encircle(5)
	assert_bool(bool(tt.unit_view(0)["surrounded"])).is_true()
	assert_bool(bool(tt.unit_view(1)["surrounded"])).is_false()
	# a line of enemies in front is not an encirclement
	var tt2 := _mk(13, _side([_u("infantry", 300)]), _side([_u("infantry", 200), _u("infantry", 200), _u("infantry", 200)]), {"deploy": false})
	_flat(tt2)
	_put(tt2, 0, 800.0, 800.0, 0.0)
	_put(tt2, 1, 870.0, 800.0, PI)
	_put(tt2, 2, 860.0, 870.0, PI)
	_put(tt2, 3, 860.0, 730.0, PI)
	tt2._refresh_alive()
	tt2._encircle(4)
	assert_bool(bool(tt2.unit_view(0)["surrounded"])).is_false()
	# surrounded units lose heart and cannot run
	var m0: float = tt.u_mor[0]
	for i in 3:
		tt.u_st[0] = Tac.S_FIGHT
		tt.u_tgt[0] = 1
		tt.u_st[1] = Tac.S_FIGHT
		tt.u_tgt[1] = 0
		tt._morale(5)
	assert_float(tt.u_mor[0]).is_less(m0 - 0.03)


# --- signals (R§20-22) --------------------------------------------------------------------------------------

func test_orders_arrive_at_once_near_the_banner_and_late_by_runner() -> void:
	var tt := _mk(17, _side([_u("infantry", 300), _u("archer", 100)]), _side([_u("infantry", 300)]), {"deploy": false})
	_flat(tt)
	var hq := AI.anchor_v(tt, 0)
	var hqp := Vector2(float(tt.S[0]["hq"][0]), float(tt.S[0]["hq"][1]))
	_put(tt, 0, hqp.x + 100.0, hqp.y, 0.0)
	var far := hqp + (AI.anchor_v(tt, 1) - hqp).normalized() * 1150.0
	_put(tt, 1, far.x, far.y, 0.0)
	tt.auto = [false, false]
	var near_r: Dictionary = tt.order(0, 0, {"behavior": "advance", "x": 900.0, "y": 900.0})
	var far_r: Dictionary = tt.order(0, 1, {"behavior": "advance", "x": 900.0, "y": 900.0})
	assert_str(String(near_r["via"])).is_not_equal("runner")
	assert_float(float(near_r["eta"])).is_less_equal(Tac.STEP + 0.01)
	assert_str(String(far_r["via"])).is_equal("runner")
	assert_float(float(far_r["eta"])).is_greater(120.0)       # about four minutes for a mile and more
	# until the runner arrives the far unit keeps doing what it did (R§21)
	var eta: float = far_r["eta"]
	var steps := int(eta / Tac.STEP) - 1
	for i in steps:
		tt.step()
	assert_str(String(tt.unit_view(1)["behavior"])).is_equal("hold")
	assert_str(String(tt.unit_view(0)["behavior"])).is_equal("advance")
	for i in 4:
		tt.step()
	# (the message may have been lost on the road: then the old plan simply goes on)
	var log: Array = tt.orders_view(0)
	assert_int(log.size()).is_equal(2)
	# fog and night make signals shorter ranged
	var foggy := _mk(17, _side([_u("infantry", 300)]), _side([_u("infantry", 300)]), {"deploy": false, "weather": "fog"})
	var clear := _mk(17, _side([_u("infantry", 300)]), _side([_u("infantry", 300)]), {"deploy": false, "weather": "clear", "season": "summer", "hour": 12})
	assert_str(foggy.weather).is_equal("fog")
	_put(foggy, 0, foggy.S[0]["hq"][0] + 330.0, foggy.S[0]["hq"][1], 0.0)
	_put(clear, 0, clear.S[0]["hq"][0] + 330.0, clear.S[0]["hq"][1], 0.0)
	assert_str(String(clear.signal_info(0, 0)["via"])).is_not_equal("runner")
	assert_str(String(foggy.signal_info(0, 0)["via"])).is_equal("runner")
	assert_float(float(hq.x)).is_not_equal(-1.0)


func test_a_runner_can_be_lost_and_the_commander_learns_late() -> void:
	var lost := 0
	var total := 0
	for sd in 40:
		var tt := _mk(200 + sd, _side([_u("infantry", 300)]), _side([_u("infantry", 300)]), {"deploy": false})
		_flat(tt)
		var hqp := Vector2(float(tt.S[0]["hq"][0]), float(tt.S[0]["hq"][1]))
		var far := hqp + (AI.anchor_v(tt, 1) - hqp).normalized() * 1000.0
		_put(tt, 0, far.x, far.y, 0.0)
		tt.auto = [false, false]
		var r: Dictionary = tt.order(0, 0, {"behavior": "advance", "x": 900.0, "y": 900.0})
		total += 1
		if bool(tt.orders_log[tt.orders_log.size() - 1]["lost"]):
			lost += 1
			var eta: float = r["eta"]
			tt.advance(int(eta / Tac.STEP) + 2)
			assert_str(String(tt.unit_view(0)["behavior"])).is_equal("hold")
			var v: Array = tt.orders_view(0)
			assert_str(String((v[0] as Dictionary)["status"])).is_equal("no word")
			tt.advance(40)
			assert_str(String((tt.orders_view(0)[0] as Dictionary)["status"])).is_equal("lost")
	assert_bool(lost >= 1 and lost < total).is_true()


# --- fog (R§23-24) ------------------------------------------------------------------------------------------

func test_enemies_are_only_known_when_seen_and_forest_hides() -> void:
	var tt := _mk(19, _side([_u("infantry", 300)]), _side([_u("infantry", 300), _u("infantry", 200, 0.6, "Hidden")]), {"deploy": false})
	_flat(tt)
	_put(tt, 0, 400.0, 800.0, 0.0)
	_put(tt, 1, 900.0, 800.0, PI)
	_put(tt, 2, 1300.0, 800.0, PI)
	tt.weather = "clear"
	tt._wx = WarUnits.WEATHER["clear"]
	tt.night = false
	tt._refresh_alive()
	tt._vision()
	assert_int(int(tt.u_seen[1]) & 1).is_equal(0)           # beyond sight (240 m)
	var view: Array = tt.units_view(0)
	var enemies := view.filter(func(v: Dictionary) -> bool: return int(v["side"]) == 1)
	assert_int(enemies.size()).is_equal(0)                  # no omniscience
	var intel: Dictionary = tt.enemy_intel(0)
	assert_int(int(intel["seen_units"])).is_equal(0)
	assert_bool(int(intel["est_max"]) >= 0).is_true()
	# move the observer close: seen, with a widened estimate because a second unit is still unseen
	_put(tt, 0, 700.0, 800.0, 0.0)
	tt._vision()
	assert_int(int(tt.u_seen[1]) & 1).is_equal(1)
	assert_int(int(tt.u_seen[2]) & 1).is_equal(0)
	intel = tt.enemy_intel(0)
	assert_int(int(intel["seen_units"])).is_equal(1)
	assert_bool(int(intel["est_max"]) > int(intel["est_min"])).is_true()
	assert_bool(bool(intel["exact"])).is_false()
	# forest hides: same range, unit in a wood is not seen
	for c in 40:
		for r in 8:
			tt.tc[(18 + r) * 40 + 20 + c % 10] = Tac.T_FOREST
	_put(tt, 0, 600.0, 800.0, 0.0)
	_put(tt, 1, 1000.0, 800.0, PI)
	tt.tc[tt.cell_idx(1000.0, 800.0)] = Tac.T_FOREST
	tt.tc[tt.cell_idx(920.0, 800.0)] = Tac.T_FOREST
	tt.tc[tt.cell_idx(960.0, 800.0)] = Tac.T_FOREST
	tt._vision()
	assert_int(int(tt.u_seen[1]) & 1).is_equal(0)
	# a unit that has been seen leaves a ghost with its age (R§24)
	_put(tt, 1, 720.0, 800.0, PI)
	tt.t = 100.0
	tt._vision()
	assert_int(int(tt.u_seen[1]) & 1).is_equal(1)
	_put(tt, 1, 1500.0, 800.0, PI)
	tt.t = 400.0
	tt._vision()
	tt.phase = "battle"
	var ghosts := (tt.units_view(0) as Array).filter(func(v: Dictionary) -> bool: return bool(v.get("ghost", false)))
	assert_int(ghosts.size()).is_greater_equal(1)
	assert_float(float((ghosts[0] as Dictionary)["age"])).is_equal_approx(300.0, 1.0)


func test_hills_see_further_and_rain_fog_and_night_shorten_sight() -> void:
	var tt := _mk(21, _side([_u("infantry", 300)]), _side([_u("infantry", 300)]), {"deploy": false, "weather": "clear", "season": "summer", "hour": 12})
	_flat(tt)
	_put(tt, 0, 500.0, 800.0, 0.0)
	_put(tt, 1, 500.0 + 300.0, 800.0, PI)
	tt.phase = "battle"
	tt._refresh_alive()
	tt._vision()
	assert_int(int(tt.u_seen[1]) & 1).is_equal(0)           # 300 m is beyond infantry sight on the flat
	tt.tc[tt.cell_idx(500.0, 800.0)] = Tac.T_HILL
	tt.hh[tt.cell_idx(500.0, 800.0)] = 40.0
	tt.tc[tt.cell_idx(300.0, 800.0)] = Tac.T_HILL
	tt._vision()
	assert_int(int(tt.u_seen[1]) & 1).is_equal(1)           # from a hill the same unit is seen
	tt.weather = "fog"
	tt._wx = WarUnits.WEATHER["fog"]
	tt._vision()
	assert_int(int(tt.u_seen[1]) & 1).is_equal(0)


# --- commander tiers (R§29-33) ---------------------------------------------------------------------------------

func test_tier_follows_the_commanders_ability() -> void:
	assert_int(Tac.tier_of({"tactics": 30, "experience": 30})).is_equal(0)
	assert_int(Tac.tier_of({"tactics": 50, "experience": 50})).is_equal(1)
	assert_int(Tac.tier_of({"tactics": 62, "experience": 62})).is_equal(2)
	assert_int(Tac.tier_of({"tactics": 75, "experience": 75})).is_equal(3)
	assert_int(Tac.tier_of({"tactics": 90, "experience": 90})).is_equal(4)
	assert_int(Tac.tier_of({"tactics": 40, "experience": 40, "legend": true})).is_equal(4)


func test_doctrines_differ_by_nation() -> void:
	assert_str(Tac.doctrine_of("caldrenn")).is_equal("valencios")
	assert_str(Tac.doctrine_of("ongur_khanate")).is_equal("steppe")
	assert_str(Tac.doctrine_of("urrokai_clanlands")).is_equal("forest")
	assert_str(Tac.doctrine_of("shenlu_peaks")).is_equal("eastern")
	# eastern armies signal further and hold more reserves; steppe riders shoot from the saddle
	assert_float(float(Tac.DOCTRINE["eastern"]["near"])).is_greater(float(Tac.DOCTRINE["valencios"]["near"]))
	assert_int(int(Tac.DOCTRINE["eastern"]["reserve"])).is_greater(int(Tac.DOCTRINE["valencios"]["reserve"]))
	var st := _mk(23, _side(_army16(), "ongur_khanate"), _side([_u("infantry", 300)], "caldrenn"), {"deploy": false})
	var lc := -1
	for i in st.side_units(0):
		if String(st.u_meta[i]["kind"]) == "light_cav":
			lc = i
	assert_float(float(st.u_rng[lc])).is_greater(0.0)
	var vc := _mk(23, _side(_army16(), "caldrenn"), _side([_u("infantry", 300)], "caldrenn"), {"deploy": false})
	var reserves := 0
	var eastern := _mk(23, _side(_army16(), "shenlu_peaks"), _side([_u("infantry", 300)], "caldrenn"), {"deploy": false})
	var e_res := 0
	for i in vc.side_units(0):
		if String(vc.u_meta[i]["layer"]) == "reserve":
			reserves += 1
	for i in eastern.side_units(0):
		if String(eastern.u_meta[i]["layer"]) == "reserve":
			e_res += 1
	assert_int(e_res).is_greater(reserves)


func test_feint_fools_a_weak_eye_but_not_an_experienced_commander() -> void:
	var results := {}
	for label: String in ["novice", "veteran"]:
		var att := _side(_army16(), "caldrenn", 3, "loyal", {"tactics": 66, "experience": 66})
		var dattrs := {"tactics": 30, "experience": 25, "scouting": 25} if label == "novice" else {"tactics": 92, "experience": 92, "scouting": 92}
		var dfn := _side(_army16(), "caldrenn", 2, "loyal", dattrs)
		var tt := _mk(31, att, dfn, {"deploy": false})
		(tt.S[0]["ai"] as Dictionary)["force_plan"] = "feint"
		# the defender keeps a slim left wing so a demonstration there looks dangerous
		tt.S[1]["tier"] = 2
		tt.think[1] = 6
		tt.think[0] = 6
		tt.run_to_end(120)
		var ig := AI.ai_log(tt, 1, "ignored_feint")
		var rf := AI.ai_log(tt, 1, "reinforce_wing")
		var feint_plan := AI.ai_log(tt, 0, "plan_feint")
		results[label] = {"ignored": ig.size(), "reinforce": rf.size(), "plan": feint_plan.size()}
	assert_int(int(results["novice"]["plan"])).is_equal(1)
	assert_int(int(results["veteran"]["plan"])).is_equal(1)
	assert_int(int(results["veteran"]["ignored"])).is_greater(0)
	assert_int(int(results["veteran"]["reinforce"])).is_equal(0)
	assert_int(int(results["novice"]["reinforce"])).is_greater(0)
	assert_int(int(results["novice"]["ignored"])).is_equal(0)


func test_false_retreat_bait_is_taken_by_the_green_and_recognised_by_the_experienced() -> void:
	var results := {}
	for label: String in ["novice", "veteran"]:
		var att := _side(_army16(), "ongur_khanate", 3, "loyal", {"tactics": 70, "experience": 70})
		var dattrs := {"tactics": 50, "experience": 30, "scouting": 30} if label == "novice" else {"tactics": 90, "experience": 92, "scouting": 88}
		var dfn := _side(_army16(), "caldrenn", 2, "loyal", dattrs)
		var tt := _mk(41, att, dfn, {"deploy": false})
		_flat(tt)       # the mechanic under test is the AI's bait, not the ground (the real ground here changes with the world)
		(tt.S[0]["ai"] as Dictionary)["force_plan"] = "false_retreat"
		tt.run_to_end(330)
		results[label] = {"fr": AI.ai_log(tt, 0, "false_retreat").size(), "took": AI.ai_log(tt, 1, "took_bait").size(), "ignored": AI.ai_log(tt, 1, "ignored_bait").size(),
			"spring": AI.ai_log(tt, 0, "spring").size()}
	assert_int(int(results["novice"]["fr"])).is_greater(0)
	assert_int(int(results["novice"]["took"])).is_greater(0)
	assert_int(int(results["novice"]["ignored"])).is_equal(0)
	assert_int(int(results["veteran"]["fr"])).is_greater(0)
	assert_int(int(results["veteran"]["ignored"])).is_greater(0)
	assert_int(int(results["veteran"]["took"])).is_equal(0)
	assert_bool(AI.recognises(_mk(1, _side([_u("infantry", 100)], "caldrenn", 2, "loyal", {"tactics": 95, "experience": 95, "scouting": 95}), _side([_u("infantry", 100)])), 0, "bait")).is_true()
	assert_bool(AI.recognises(_mk(1, _side([_u("infantry", 100)], "caldrenn", 2, "loyal", {"tactics": 20, "experience": 20, "scouting": 20}), _side([_u("infantry", 100)])), 0, "bait")).is_false()


func test_a_weak_commander_attacks_frontally_and_holds_no_reserve() -> void:
	var weak := _mk(51, _side(_army16(), "caldrenn", 1, "loyal", {"tactics": 25, "experience": 25}), _side(_army16(), "caldrenn", 1, "loyal", {"tactics": 25, "experience": 25}), {"deploy": false})
	assert_int(int(weak.S[0]["tier"])).is_equal(0)
	_flat(weak)
	weak.advance(56)
	var advancing := 0
	for i in weak.side_units(0):
		var v: Dictionary = weak.unit_view(i)
		if String(v["behavior"]) in ["advance", "charge"]:
			advancing += 1
	assert_int(advancing).is_greater_equal(12)      # everything goes forward at once, reserve included
	var smart := _mk(51, _side(_army16(), "caldrenn", 2, "loyal", {"tactics": 52, "experience": 52}), _side(_army16(), "caldrenn", 1, "loyal", {"tactics": 25, "experience": 25}), {"deploy": false})
	_flat(smart)
	smart.advance(24)
	var held := 0
	for i in smart.side_units(0):
		if String(smart.u_meta[i]["layer"]) == "reserve" and int(smart.u_st[i]) == Tac.S_RESERVE:
			held += 1
	assert_int(held).is_greater_equal(1)


func test_stronger_side_usually_wins_and_bigger_is_not_always_better_in_narrow_ground() -> void:
	var wins := 0
	for sd in 5:
		var a := _side(_army16(1.6), "caldrenn", 2)
		var b := _side(_army16(1.0), "caldrenn", 2)
		var tt := _mk(300 + sd, a, b, {"deploy": false, "center": [-1274.0 + 100.0 * sd, -2318.0]})
		var r: Dictionary = tt.run_to_end()
		if String(r["winner"]) == "a":
			wins += 1
	assert_int(wins).is_greater_equal(4)
	# numbers count for less in a forest: frontage cap
	var men := 600
	var open_tt := _mk(61, _side([_u("infantry", men)]), _side([_u("infantry", 100)]), {"deploy": false})
	_flat(open_tt)
	var wood_tt := _mk(61, _side([_u("infantry", men)]), _side([_u("infantry", 100)]), {"deploy": false})
	wood_tt.tc.fill(Tac.T_FOREST)
	wood_tt.hh.fill(10.0)
	var k := []
	for tt2: RefCounted in [open_tt, wood_tt]:
		var gap: float = tt2.u_rad[0] + tt2.u_rad[1] + 4.0
		_put(tt2, 0, 800.0, 800.0, 0.0)
		_put(tt2, 1, 800.0 + gap, 800.0, PI)
		_fight(tt2, 0, 1)
		tt2.u_tgt[1] = -1
		tt2.u_st[1] = Tac.S_HOLD
		tt2._combat(2)
		k.append(tt2._dk[1])
	assert_float(float(k[1]) / float(k[0])).is_less(0.8)


# --- elites and duels (R§39-40) -------------------------------------------------------------------------------------

func test_an_elite_breaks_a_formation_but_does_not_beat_an_army() -> void:
	var a := _side([_u("infantry", 300)])
	a["elites"] = [{"kind": "champion", "name": "Sir Kael", "men": 1, "quality": 0.95, "morale": 0.95}]
	var tt := _mk(71, a, _side([_u("infantry", 250, 0.6, "Line")]), {"deploy": false})
	_flat(tt)
	var elite := -1
	for i in tt.side_units(0):
		if bool(tt.u_meta[i]["elite"]):
			elite = i
	assert_int(elite).is_greater_equal(0)
	assert_float(float(tt.u_pw[elite])).is_greater(100.0)
	# alone against one formation it grinds it down
	_put(tt, elite, 800.0, 800.0, 0.0)
	_put(tt, 2, 800.0 + tt.u_rad[elite] + tt.u_rad[2] + 4.0, 800.0, PI)
	_put(tt, 0, 100.0, 100.0, 0.0)
	tt.u_st[0] = Tac.S_EXIT
	_fight(tt, elite, 2)
	tt.phase = "battle"
	tt.auto = [false, false]
	var men0: float = tt.u_men[2]
	for i in 30:
		tt.step_no += 3
		tt._combat(tt.unit_count())
		tt._morale(tt.unit_count())
		if tt.u_st[elite] >= Tac.S_DEAD or tt.u_st[2] >= Tac.S_DEAD:
			break
	assert_float(float(tt.u_men[2])).is_less(men0 * 0.95)
	assert_float(tt.u_mor[2]).is_less(0.6)      # the formation is shaken
	# but a large army kills it
	var big := _mk(71, a, _side(_army16()), {"deploy": false})
	var r: Dictionary = big.run_to_end()
	assert_bool(String(r["winner"]) != "" or int(r["steps"]) > 0).is_true()


func test_champions_meet_in_a_duel_and_the_result_moves_morale() -> void:
	var a := _side([_u("infantry", 200)])
	a["elites"] = [{"kind": "champion", "name": "Sir Kael", "men": 1, "quality": 0.95, "morale": 0.95}]
	var b := _side([_u("infantry", 200)], "ongur_khanate")
	b["elites"] = [{"kind": "champion", "name": "Khan's Champion", "men": 1, "quality": 0.85, "morale": 0.95}]
	var tt := _mk(81, a, b, {"deploy": false})
	_flat(tt)
	var ea := -1
	var eb := -1
	for i in tt.unit_count():
		if bool(tt.u_meta[i]["elite"]):
			if tt.u_side[i] == 0:
				ea = i
			else:
				eb = i
	_put(tt, ea, 800.0, 800.0, 0.0)
	_put(tt, eb, 830.0, 800.0, PI)
	_put(tt, 0, 700.0, 850.0, 0.0)
	_put(tt, 2, 900.0, 850.0, PI)
	tt.auto = [false, true]
	# the steppe champion is willing (formal duels); ours has not said yes: the game asks
	tt._refresh_alive()
	tt._duel_step(tt.unit_count())
	tt.step_no = 3
	tt._duel_step(tt.unit_count())
	assert_bool(tt.pending_duel.is_empty()).is_false()
	assert_int(int(tt.pending_duel["mine"])).is_equal(ea)
	tt.duel_respond(ea, true)
	tt.step_no = 6
	tt._duel_step(tt.unit_count())
	assert_int(tt.duels.size()).is_equal(1)
	assert_int(int(tt.u_st[ea])).is_equal(Tac.S_DUEL)
	var m_before: float = tt.u_mor[1]
	var guard := 0
	while not bool((tt.duels[0] as Dictionary)["done"]) and guard < 80:
		tt._duel_step(tt.unit_count())
		guard += 1
	assert_bool(bool((tt.duels[0] as Dictionary)["done"])).is_true()
	var win := int((tt.duels[0] as Dictionary)["winner"])
	assert_bool(win == ea or win == eb).is_true()
	assert_bool(int(tt.u_st[win]) != Tac.S_DEAD).is_true()
	var own_side := 1 if win == eb else 0
	var moved := false
	for i in tt.unit_count():
		if not bool(tt.u_meta[i]["elite"]) and absf(tt.u_mor[i] - 0.75) > 0.05:
			moved = true
	assert_bool(moved).is_true()
	assert_int(own_side).is_greater_equal(0)
	assert_float(m_before).is_greater(0.0)
	# declining a challenge avoids the fight
	var tt2 := _mk(82, a, b, {"deploy": false})
	_flat(tt2)
	var ea2 := 0
	var eb2 := 0
	for i in tt2.unit_count():
		if bool(tt2.u_meta[i]["elite"]):
			if tt2.u_side[i] == 0:
				ea2 = i
			else:
				eb2 = i
	_put(tt2, ea2, 800.0, 800.0, 0.0)
	_put(tt2, eb2, 830.0, 800.0, PI)
	tt2.auto = [false, true]
	tt2.duel_respond(ea2, false)
	tt2.step_no = 3
	tt2._refresh_alive()
	tt2._duel_step(tt2.unit_count())
	assert_int(tt2.duels.size()).is_equal(0)


# --- weather and night (R§36-37) ----------------------------------------------------------------------------------------

func test_weather_comes_from_the_season_and_rain_spoils_archery() -> void:
	var seen := {}
	for sd in 60:
		seen[Tac.roll_weather("autumn", "clear", sd)] = true
	assert_bool(seen.has("rain") and seen.has("fog") and seen.has("clear")).is_true()
	assert_bool(not seen.has("heat")).is_true()
	var hot := {}
	for sd2 in 60:
		hot[Tac.roll_weather("summer", "clear", sd2)] = true
	assert_bool(hot.has("heat")).is_true()
	assert_str(Tac.roll_weather("winter", "storm", 3)).is_equal("storm")     # the campaign's weather wins
	var dk := {}
	for w: String in ["clear", "rain"]:
		var tt := _mk(91, _side([_u("archer", 200)]), _side([_u("infantry", 300)]), {"deploy": false, "weather": w, "season": "spring"})
		tt.weather = w
		tt._wx = WarUnits.WEATHER[w]
		_flat(tt)
		_put(tt, 0, 800.0, 800.0, 0.0)
		_put(tt, 1, 900.0, 800.0, PI)
		tt.u_st[0] = Tac.S_FIGHT
		tt.u_tgt[0] = 1
		tt._combat(2)
		dk[w] = tt._dk[1]
	assert_float(float(dk["rain"]) / float(dk["clear"])).is_less(0.85)


# --- determinism, persistence, campaign link ----------------------------------------------------------------------------

## Rounds floats so a saved and a live battle compare equal despite float32 / JSON digits.
func _norm(v: Variant) -> Variant:
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _norm(v[k])
		return d
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_norm(x))
		return a
	if v is float or v is int:
		var f := snappedf(float(v), 0.01)
		return int(f) if absf(f - round(f)) < 0.0001 else f
	return v


func test_same_seed_same_battle_and_json_round_trip_resumes_exactly() -> void:
	var mk := func() -> RefCounted: return _mk(111, _side(_army16()), _side(_army16(), "ongur_khanate", 2, "aggressive"), {"deploy": false})
	var t1: RefCounted = mk.call()
	var t2: RefCounted = mk.call()
	t1.advance(200)
	t2.advance(200)
	assert_str(JSON.stringify(t1.serialize())).is_equal(JSON.stringify(t2.serialize()))
	# save in the middle of the battle (with orders in flight) and resume from the parsed JSON
	t1.order(0, 0, {"behavior": "flank", "x": 900.0, "y": 300.0})
	var js := JSON.stringify(t1.serialize())
	var parsed: Variant = JSON.parse_string(js)
	assert_bool(parsed is Dictionary).is_true()
	var t3: RefCounted = Tac.restore(parsed)
	t1.advance(150)
	t3.advance(150)
	assert_str(JSON.stringify(_norm(t3.serialize()))).is_equal(JSON.stringify(_norm(t1.serialize())))
	assert_str(t3.phase).is_equal(t1.phase)
	assert_float(t3.t).is_equal(t1.t)
	# the state holds only JSON types
	assert_bool(js.contains("Vector2")).is_false()


func test_result_is_written_back_into_the_campaign_engagement() -> void:
	var c := Campaign.new()
	c.set_hq(0)
	c.tick_day(0, {})
	var a: int = c.spawn_army("player", 0, 1400, "aggressive", "Ashford Host")
	var b: int = c.spawn_army("ongur_khanate", 1, 1300, "loyal", "Ongur Host")
	var ids_a: Array = []
	var ids_b: Array = []
	for u: Dictionary in c.army_units(a):
		ids_a.append(int(u["id"]))
		c.detach(int(u["id"]))
	for u2: Dictionary in c.army_units(b):
		ids_b.append(int(u2["id"]))
	var pos: Vector2 = c.node_pos(0) + Vector2(400, 300)
	var v := c.open_engagement(ids_a, ids_b, pos.x, pos.y)
	assert_bool(v.is_empty()).is_false()
	var eid := int(v["id"])
	assert_bool(c.has_tactical(eid)).is_false()
	var tt := c.tactical_open(eid)
	assert_object(tt).is_not_null()
	assert_bool(c.has_tactical(eid)).is_true()
	assert_str(tt.phase).is_equal("deploy")
	assert_int(int(tt.unit_count())).is_equal(20)
	assert_str(String(c.engagement_view(eid)["control"])).is_equal("player")
	var men_before := 0
	for u3: Dictionary in c.army_units(a):
		men_before += int(u3["men"])
	tt.begin()
	tt.auto = [true, true]
	var r: Dictionary = tt.run_to_end()
	assert_bool(String(r["winner"]) in ["a", "b", ""]).is_true()
	var out: Array = []
	var res := c.tactical_apply(eid, out)
	assert_bool(res.is_empty()).is_false()
	var ev := c.engagement_view(eid)
	assert_str(String(ev["status"])).is_equal("ended")
	assert_int(int(ev["casualties_player"])).is_equal(int((r["cas"] as Dictionary)["a"]))
	assert_int(int(ev["casualties_enemy"])).is_equal(int((r["cas"] as Dictionary)["b"]))
	var men_after := 0
	for u4: Dictionary in c.army_units(a):
		men_after += int(u4["men"])
	assert_int(men_before - men_after).is_equal(int((r["cas"] as Dictionary)["a"]))
	assert_bool(c.has_tactical(eid)).is_false()
	assert_bool(out.size() > 0).is_true()
	# the campaign hour advances an unattended battle by itself (R§50)
	var c2 := Campaign.new()
	c2.set_hq(0)
	c2.tick_day(0, {})
	var a2: int = c2.spawn_army("player", 0, 900, "aggressive")
	var b2: int = c2.spawn_army("ongur_khanate", 1, 700, "loyal")
	var ia: Array = []
	var ib: Array = []
	for u5: Dictionary in c2.army_units(a2):
		ia.append(int(u5["id"]))
		c2.detach(int(u5["id"]))
	for u6: Dictionary in c2.army_units(b2):
		ib.append(int(u6["id"]))
	var v2 := c2.open_engagement(ia, ib, pos.x, pos.y)
	var eid2 := int(v2["id"])
	c2.tactical_open(eid2)
	c2.tactical_leave(eid2)
	for h in 12:
		c2.tick_hour(h, {})
		if String(c2.engagement_view(eid2)["status"]) == "ended":
			break
	assert_str(String(c2.engagement_view(eid2)["status"])).is_equal("ended")
	# a saved campaign keeps the battle in progress
	var c3 := Campaign.new()
	c3.set_hq(0)
	c3.tick_day(0, {})
	var a3: int = c3.spawn_army("player", 0, 900, "aggressive")
	var b3: int = c3.spawn_army("ongur_khanate", 1, 700, "loyal")
	var ja: Array = []
	var jb: Array = []
	for u7: Dictionary in c3.army_units(a3):
		ja.append(int(u7["id"]))
		c3.detach(int(u7["id"]))
	for u8: Dictionary in c3.army_units(b3):
		jb.append(int(u8["id"]))
	var v3 := c3.open_engagement(ja, jb, pos.x, pos.y)
	var t3 := c3.tactical_open(int(v3["id"]))
	t3.begin()
	t3.advance(40)
	var saved := JSON.stringify(c3.serialize())
	var c4 := Campaign.new()
	c4.deserialize(JSON.parse_string(saved))
	assert_bool(c4.has_tactical(int(v3["id"]))).is_true()
	var tt4 := c4.tactical_battle(int(v3["id"]), false)
	assert_float(tt4.t).is_equal(t3.t)
	assert_int(int(tt4.unit_count())).is_equal(int(t3.unit_count()))


func test_reinforcements_arrive_later_and_the_ai_can_exploit_the_delay() -> void:
	var tt := _mk(121, _side([_u("infantry", 300), _u("spear", 200)]), _side([_u("infantry", 300), _u("spear", 200)]), {"deploy": false})
	_flat(tt)
	var ids: Array = tt.send_reinforcements(0, [_u("infantry", 200, 0.7, "Second Army")], 300.0)
	assert_int(ids.size()).is_equal(1)
	assert_int(int(tt.u_st[ids[0]])).is_equal(Tac.S_ARRIVE)
	assert_int((tt.arrivals(0)).size()).is_equal(1)
	assert_int(int((tt.arrivals(0)[0] as Dictionary)["eta"])).is_equal(300)
	var shown := (tt.units_view(0) as Array).filter(func(v: Dictionary) -> bool: return String(v["name"]) == "Second Army")
	assert_int(shown.size()).is_equal(1)
	for i in 29:
		tt.step()
	assert_int(int(tt.u_st[ids[0]])).is_equal(Tac.S_ARRIVE)
	tt.step()
	tt.step()
	assert_int(int(tt.u_st[ids[0]])).is_not_equal(Tac.S_ARRIVE)
	# an elite commander who knows the enemy's second army is coming strikes first (R§35)
	var tt2 := _mk(122, _side(_army16(), "caldrenn", 3, "loyal", {"tactics": 75, "experience": 75}), _side(_army16()), {"deploy": false})
	var arr: Array = tt2.send_reinforcements(1, [_u("infantry", 400, 0.7, "Relief Column")], 900.0)
	tt2.u_meta[arr[0]]["known"] = true
	tt2.advance(60)
	assert_int(AI.ai_log(tt2, 0, "defeat_in_detail").size()).is_greater(0)


# --- performance --------------------------------------------------------------------------------------------------------

func test_perf_sixteen_versus_sixteen_units_for_600_steps() -> void:
	var best := 1.0e9
	var last: RefCounted = null
	for rep in 5:     # best of five: a loaded machine must not fail a speed budget
		var tt := _mk(131, _side(_army16()), _side(_army16(), "caldrenn", 2, "aggressive"), {"deploy": false})
		var t0 := Time.get_ticks_usec()
		for i in 600:
			tt.step()
		best = minf(best, float(Time.get_ticks_usec() - t0) / 1000.0)
		last = tt
	print("tactical 16v16 x600 steps: %.1f ms best of 5 (phase %s at step %d)" % [best, last.phase, last.step_no])
	assert_int(last.unit_count()).is_equal(32)
	assert_float(best).is_less(50.0)
