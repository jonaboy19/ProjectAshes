extends GdUnitTestSuite
## Survival construction: tier gating, materials, skill -> speed, stalls, catch-up, placement, upgrades,
## paths, save round trip and perf (scripts/realm/construction.gd).

const Hub := preload("res://scripts/realm/realm_hub.gd")
const D := preload("res://scripts/realm/construction_data.gd")
const Nav := preload("res://scripts/realm/construction_nav.gd")
const Mastery := preload("res://scripts/sim/mastery.gd")
const StreetGraph := preload("res://scripts/population/street_graph.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 0, "life": null}

var _spot := Vector2.INF


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _rich() -> Dictionary:
	return {"log": 400, "plank": 400, "stone": 400, "cut_stone": 400, "clay": 200, "thatch": 200, "iron_ingot": 100, "tools": 50}


## A fresh module with a stocked bag, a mastery record and plenty of gold.
func _mod(bag := {}) -> RefCounted:
	WorldGen.setup(2024)
	var m: RefCounted = Hub.new().mod("construction")
	m.bag = bag
	m.gold_ref = {"gold": 1000}
	m.mastery_ref = Mastery.new()
	return m


## A flat, dry spot with room for a row of big buildings (found once per suite run).
func _flat() -> Vector2:
	if _spot != Vector2.INF:
		return _spot
	var m := _mod()
	for x in range(-900, 900, 60):
		for z in range(-900, 900, 60):
			var p := Vector2(x, z)
			var ok := true
			for i in 7:
				var q := p + Vector2(14.0 * i, 0.0)
				if m.can_place_here("keep", q, 0.0) != "":
					ok = false
					break
			if ok:
				_spot = p
				return p
	return Vector2.INF


## Like _flat(), but the open ground around it must also be walkable and out in the wild: the perf test routes ~140 m across it,
## and the first flat spot of a scan can sit under a cliff (new world sites change which spot that is), which made Nav.route
## return no way through. It must also lie beyond 3 settlement radii of any town (+ the 150 m the test spreads over), because a
## finished building within that range registers with the town's street graph (~10 ms each, not what this test measures).
func _flat_walkable() -> Vector2:
	var m := _mod()
	for x in range(-900, 900, 60):
		for z in range(-900, 900, 60):
			var p := Vector2(x, z)
			var ok := true
			for st: Dictionary in WorldGen.settlements:
				if (st["pos"] as Vector2).distance_to(p + Vector2(60, 60)) < float(st["radius"]) * 3.0 + 150.0:
					ok = false
					break
			for i in 7:
				if not ok:
					break
				if m.can_place_here("keep", p + Vector2(14.0 * i, 0.0), 0.0) != "":
					ok = false
			if ok and Nav.route(m, p + Vector2(-20, 20), p + Vector2(120, 100)).size() >= 2:
				return p
	return Vector2.INF


func _at(i: int) -> Vector2:
	return _flat() + Vector2(14.0 * i, 0.0)


## Lays a blueprint, stocks it, and finishes it instantly (skips the labour).
func _done(m: RefCounted, kind: String, i: int) -> int:
	var r: Dictionary = m.place(kind, _at(i), 0.0)
	assert_str(String(r["reason"])).is_equal("")
	var id := int(r["id"])
	var s: Dictionary = m.sites[id]
	for item: String in s["need"]:
		s["have"][item] = s["need"][item]
	m._complete(s)
	return id


func _work(m: RefCounted, site_id: int, hours := 400) -> void:
	m.assign_player(site_id)
	m.advance(hours, {})


func test_flat_spot_exists() -> void:
	assert_bool(_flat() != Vector2.INF).is_true()


func test_tier_gating_needs_lower_tiers_and_buildings() -> void:
	var m := _mod(_rich())
	assert_str(m.can_place("campfire", _at(0), 0.0)).is_equal("")
	var why: String = m.can_place("hut", _at(1), 0.0)
	assert_str(why).contains("survival")
	_done(m, "campfire", 0)
	why = m.can_place("hut", _at(1), 0.0)
	assert_str(why).contains("storage pile")
	_done(m, "storage_pile", 1)
	assert_str(m.can_place("hut", _at(2), 0.0)).is_equal("")
	# tier 2 needs know-how and tools, not just gold
	_done(m, "hut", 2)
	assert_str(m.can_place("timber_house", _at(3), 0.0)).is_not_empty()
	_done(m, "workbench", 3)
	assert_bool(m.knows("build:carpentry")).is_true()
	_done(m, "sawhorse", 4)
	assert_str(m.can_place("timber_house", _at(5), 0.0)).is_equal("")
	# tier 4 is far out of reach from here
	assert_array(m.missing_needs("keep")).is_not_empty()
	assert_str(m.can_place("keep", _at(5), 0.0)).is_not_empty()


func test_learning_from_a_master_unlocks_knowledge() -> void:
	var m := _mod(_rich())
	assert_bool(bool(m.learn_lesson("build:masonry")["ok"])).is_false()
	_done(m, "campfire", 0)
	_done(m, "storage_pile", 1)
	var id := int(m.place("fence", _at(2), 0.0)["id"])
	var w: Dictionary = m.assign_player(id)
	w["master"] = true   # stands in for a hired master builder on the crew
	var r: Dictionary = m.learn_lesson("build:masonry")
	assert_bool(bool(r["ok"])).is_true()
	assert_bool(m.knows("build:masonry")).is_true()
	assert_int(m.gold_available()).is_equal(1000 - int(D.LESSONS["build:masonry"]["gold"]))


func test_material_deduction_and_start_share() -> void:
	var m := _mod({"log": 1, "thatch": 0})
	# a lean-to needs 5 log + 4 thatch: one log is under the starting share
	assert_str(m.can_place("lean_to", _at(0), 0.0)).contains("Bring")
	m.bag = {"log": 12, "thatch": 4}
	var r: Dictionary = m.place("lean_to", _at(0), 0.0)
	assert_bool(bool(r["ok"])).is_true()
	assert_int(int(m.bag["log"])).is_equal(7)
	assert_int(int(m.bag["thatch"])).is_equal(0)
	var s: Dictionary = m.sites[int(r["id"])]
	assert_int(int(s["have"]["log"])).is_equal(5)
	assert_dict(m.missing_materials(s)).is_empty()
	# partial stock: the site only allows a matching share of the work
	var r2: Dictionary = m.place("tent", _at(1), 0.0)
	assert_bool(bool(r2["ok"])).is_false()   # no thatch left to start it


func test_skill_changes_speed() -> void:
	var novice: Dictionary = preload("res://scripts/realm/construction.gd").crew_labour([0.1, 0.1], false, 4)
	var expert: Dictionary = preload("res://scripts/realm/construction.gd").crew_labour([0.8, 0.1], false, 4)
	assert_float(float(expert["rate"])).is_greater(float(novice["rate"]) * 1.4)
	assert_int(int(expert["masters"])).is_equal(1)
	var tooled: Dictionary = preload("res://scripts/realm/construction.gd").crew_labour([0.1, 0.1], true, 4)
	assert_float(float(tooled["rate"])).is_equal_approx(float(novice["rate"]) * D.TOOL_BONUS, 0.001)
	# more hands: faster, with diminishing returns beyond the site's room
	var four: Dictionary = preload("res://scripts/realm/construction.gd").crew_labour([0.3, 0.3, 0.3, 0.3], false, 2)
	var two: Dictionary = preload("res://scripts/realm/construction.gd").crew_labour([0.3, 0.3], false, 2)
	assert_float(float(four["rate"])).is_greater(float(two["rate"]))
	assert_float(float(four["rate"])).is_less(float(two["rate"]) * 2.0)
	# in the simulation: a master and two hired hands finish a hut faster than you alone
	var a := _mod(_rich())
	_done(a, "campfire", 0)
	_done(a, "storage_pile", 1)
	var solo := int(a.place("hut", _at(2), 0.0)["id"])
	a.assign_player(solo)
	var b := _mod(_rich())
	_done(b, "campfire", 0)
	_done(b, "storage_pile", 1)
	var crew := int(b.place("hut", _at(2), 0.0)["id"])
	b.assign_player(crew)
	for i in 3:
		var w: Dictionary = b._new_worker("hired", "H%d" % i, 0.8 if i == 0 else 0.3, 4, "build")
		b._attach(w, crew)
	a.advance(3, {})
	b.advance(3, {})
	assert_float(float(b.sites[crew]["progress"])).is_greater(float(a.sites[solo]["progress"]) * 2.0)


func test_stall_on_missing_materials_and_resume() -> void:
	var m := _mod({"log": 10, "thatch": 4, "clay": 0})
	_done(m, "campfire", 0)
	_done(m, "storage_pile", 1)
	m.bag = {"log": 10, "thatch": 2, "clay": 1}   # a hut needs 10 log, 8 thatch, 4 clay: the start share is 3 log, 2 thatch, 1 clay
	var r: Dictionary = m.place("hut", _at(2), 0.0)
	assert_bool(bool(r["ok"])).is_true()
	var id := int(r["id"])
	m.assign_player(id)
	m.advance(200, {})
	var s: Dictionary = m.sites[id]
	assert_str(String(s["state"])).is_equal("site")
	var allowed: float = m.allowed_progress(s)
	assert_float(float(s["progress"])).is_equal_approx(allowed, 0.001)
	assert_float(float(s["progress"])).is_less(float(s["total"]))
	assert_str(m.stall_reason(s)).contains("Waiting for")
	# bring the rest and it finishes
	m.bag = _rich()
	m.deliver_all(id)
	m.advance(200, {})
	assert_str(String(m.sites[id]["state"])).is_equal("done")


func test_tall_buildings_need_a_skilled_builder() -> void:
	var m := _mod(_rich())
	for i in 4:
		_done(m, ["campfire", "storage_pile", "hut", "workbench"][i], i)
	_done(m, "sawhorse", 4)
	_done(m, "mason_bench", 5)
	_done(m, "timber_house", 6)
	var id := int(m.place("stone_house", _at(7), 0.0)["id"]) if m.can_place_here("stone_house", _at(7), 0.0) == "" else 0
	if id == 0:
		return
	m.assign_player(id)
	assert_str(m.stall_reason(m.sites[id])).contains("skilled builder")
	var w: Dictionary = m._new_worker("hired", "Master Hale", 0.8, 14, "build")
	m._attach(w, id)
	assert_str(m.stall_reason(m.sites[id])).is_equal("")
	assert_float(m.eta_hours(m.sites[id])).is_greater(0.0)


func test_catch_up_matches_hour_by_hour() -> void:
	var a := _mod(_rich())
	var b := _mod(_rich())
	var ids: Array[int] = []
	for m: RefCounted in [a, b]:
		_done(m, "campfire", 0)
		_done(m, "storage_pile", 1)
		var id := int(m.place("hut", _at(2), 0.0)["id"])
		m.assign_player(id)
		var w: Dictionary = m._new_worker("hired", "H", 0.35, 4, "build")
		m._attach(w, id)
		ids.append(id)
	for day in 2:
		for h in 24:
			a.tick_hour(h, CTX)
		a.tick_day(day + 2, CTX)
	b.catch_up(2, CTX)
	assert_float(float(a.sites[ids[0]]["progress"])).is_equal_approx(float(b.sites[ids[1]]["progress"]), 0.0001)
	assert_str(String(a.sites[ids[0]]["state"])).is_equal(String(b.sites[ids[1]]["state"]))
	assert_int(int(a.gold_available())).is_equal(int(b.gold_available()))


func test_catch_up_stalls_with_no_materials_and_ends_early() -> void:
	var m := _mod({"log": 5, "thatch": 4})
	var id := int(m.place("lean_to", _at(0), 0.0)["id"])
	m.sites[id]["have"] = {"log": 2, "thatch": 1}   # under-stocked
	m.assign_player(id)
	m.catch_up(30, CTX)
	var s: Dictionary = m.sites[id]
	assert_float(float(s["progress"])).is_less(float(s["total"]))
	assert_float(float(s["progress"])).is_equal_approx(m.allowed_progress(s), 0.001)


func test_placement_validation() -> void:
	var m := _mod(_rich())
	assert_str(m.can_place_here("campfire", WorldGen.lake_center, 0.0)).contains("wet")
	var st: Dictionary = WorldGen.settlements[0]
	assert_str(m.can_place_here("campfire", st["pos"], 0.0)).contains("Too close")
	_done(m, "campfire", 0)
	assert_str(m.can_place_here("campfire", _at(0) + Vector2(0.4, 0.2), 0.0)).contains("already stands")
	assert_str(m.can_place_here("campfire", _at(0) + Vector2(6.0, 0.0), 0.0)).is_equal("")
	# a steep cliff face
	var cliff := Vector2.INF
	for x in range(-1400, 1400, 37):
		for z in range(-1400, 1400, 37):
			var g: Dictionary = m.ground("keep", Vector2(x, z), 0.0)
			if not bool(g["ok"]) and String(g["reason"]) == "Too steep.":
				cliff = Vector2(x, z)
				break
		if cliff != Vector2.INF:
			break
	if cliff != Vector2.INF:
		assert_str(m.can_place_here("keep", cliff, 0.0)).is_equal("Too steep.")
	assert_vector(m.snap(Vector2(3.3, 4.9))).is_equal(Vector2(4, 4))


func test_upgrade_path_hut_to_timber_to_stone() -> void:
	var m := _mod(_rich())
	_done(m, "campfire", 0)
	_done(m, "storage_pile", 1)
	var hut := _done(m, "hut", 2)
	assert_str(m.can_place("timber_house", _at(2), 0.0, hut)).is_not_empty()   # needs a workbench and sawhorse first
	_done(m, "workbench", 3)
	_done(m, "sawhorse", 4)
	assert_array(m.upgrade_options(hut)).contains_exactly(["timber_house"])
	var r: Dictionary = m.upgrade(hut, "timber_house")
	assert_bool(bool(r["ok"])).is_true()
	var up: Dictionary = m.sites[int(r["id"])]
	assert_int(int(up["need"]["plank"])).is_equal(int(ceil(24 * D.UPGRADE_COST)))
	assert_float(float(up["total"])).is_equal_approx(60.0 * D.UPGRADE_HOURS, 0.001)
	assert_str(m.can_place("timber_house", _at(2), 0.0, hut)).contains("lready being upgraded")
	m.assign_player(int(r["id"]))
	m.advance(200, {})
	assert_str(String(up["state"])).is_equal("site")   # a novice cannot frame a timber house
	assert_str(m.stall_reason(up)).contains("skilled builder")
	m._attach(m._new_worker("hired", "Piers", 0.4, 4, "build"), int(r["id"]))
	m.advance(200, {})
	assert_str(String(up["state"])).is_equal("done")
	assert_bool(m.sites.has(hut)).is_false()
	assert_str(String(up["from_kind"])).is_equal("hut")
	assert_int(m.count_built("hut")).is_equal(0)
	assert_int(m.count_built("timber_house")).is_equal(1)
	# and on to stone once masonry stands
	_done(m, "mason_bench", 5)
	assert_array(m.upgrade_options(int(up["id"]))).contains_exactly(["stone_house"])


func test_obstacles_and_routes_go_around_new_buildings() -> void:
	var m := _mod(_rich())
	var wall_id := _done(m, "campfire", 0)
	# a long palisade across the way
	_done(m, "storage_pile", 1)
	var p := _flat()
	var a := p + Vector2(-6, -16)
	var b := p + Vector2(-6, 16)
	var before: PackedVector2Array = Nav.route(m, a, b)
	assert_int(before.size()).is_equal(2)
	var s := {"id": 99, "kind": "palisade", "pos": [p.x - 6.0, p.y], "yaw": PI * 0.5, "holding": 1, "state": "done", "progress": 1.0, "total": 1.0, "need": {}, "have": {}, "workers": []}
	m.sites[99] = s
	var blocker: Array = Nav.box_of(s)
	assert_bool(Nav.in_box(blocker, Vector2(p.x - 6.0, p.y))).is_true()
	var after: PackedVector2Array = Nav.route(m, a, b)
	assert_int(after.size()).is_greater(2)
	assert_float(Nav.length(after)).is_greater(Nav.length(before))
	for i in range(after.size() - 1):
		assert_bool(Nav.clear_line(Nav.boxes(m), after[i], after[i + 1])).is_true()
	assert_int(wall_id).is_greater(0)
	# water blocks completely: no path into the lake
	assert_bool(Nav.reachable(m, a, WorldGen.lake_center)).is_false()


func test_new_buildings_register_in_the_street_graph() -> void:
	WorldGen.setup(2024)
	var sg: RefCounted = StreetGraph.for_settlement(0)
	if sg == null:
		return
	var st: Dictionary = WorldGen.settlements[0]
	var n0: int = sg.node_count()
	var c: Vector2 = st["pos"] + Vector2(float(st["radius"]) * 1.05, 4.0)
	var door := c + Vector2(0, 3.0)
	sg.register_building(c, 0.0, Vector2(2.0, 2.0), door)
	assert_int(sg.node_count()).is_greater(n0)
	assert_bool(sg.inside(c)).is_true()


func test_catch_up_registers_many_buildings_near_a_town_cheaply() -> void:
	var m := _mod(_rich())
	m.bag = {}
	var best := 0
	for i in WorldGen.settlements.size():
		if float(WorldGen.settlements[i]["radius"]) > float(WorldGen.settlements[best]["radius"]):
			best = i
	var st: Dictionary = WorldGen.settlements[best]
	var sg: RefCounted = StreetGraph.for_settlement(best)
	if sg == null:
		return
	sg.node_count()   # the lazy one-off graph build is not what this measures
	var r := float(st["radius"])
	var ids: Array[int] = []
	for i in 60:
		var pos: Vector2 = st["pos"] + Vector2(r * 1.05 + float(i % 10) * 14.0, -r * 0.5 + float(i / 10) * 14.0)
		var id := _add_raw(m, "fence" if i % 2 == 0 else "hut", pos)
		ids.append(id)
		m._attach(m._new_worker("hired", "H", 0.3, 4, "build"), id)
	var e0: int = sg._edges.size()
	var boxes0: int = sg._box_c.size()
	var t0 := Time.get_ticks_usec()
	m.catch_up(30, CTX)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("catch_up near town, 60 buildings: %.1f ms" % ms)
	assert_float(ms).is_less(250.0)
	for id in ids:
		assert_str(String(m.sites[id]["state"])).is_equal("done")
	var done := 0
	var routed := 0
	for id in ids:
		if String(m.sites[id]["state"]) != "done":
			continue
		var pos: Vector2 = m.site_pos(m.sites[id])
		if int(WorldGen.nearest_settlement(pos)["id"]) != best:
			continue   # registered with a neighbouring town's graph
		done += 1
		assert_bool(sg.inside(pos)).is_true()
		# a route across the footprint's row never enters any footprint
		var a := pos + Vector2(-12, 0)
		var b := pos + Vector2(12, 0)
		if sg.inside(a) or sg.inside(b):
			continue
		routed += 1
		var route: PackedVector2Array = sg.route(a, b)
		var prev := a
		for p in route:
			assert_bool(sg.inside(p, 0.0)).is_false()
			for k in range(boxes0, sg._box_c.size()):
				assert_bool(sg._segment_hits_box(prev, p, k, 0.0)).is_false()
			prev = p
	assert_int(routed).is_greater(0)
	assert_int(done).is_greater(15)   # the rest of the 60 stand nearer another town
	assert_int(sg._edges.size()).is_greater(e0)
	assert_int(sg._indexed_edges).is_equal(sg._edges.size() / 2)


func test_batched_registration_matches_one_by_one() -> void:
	WorldGen.setup(2024)
	var st: Dictionary = WorldGen.settlements[0]
	var r := float(st["radius"])
	var batch: Array = []
	for i in 12:
		var c: Vector2 = st["pos"] + Vector2(r * 0.6 + float(i % 4) * 6.0, -r * 0.4 + float(i / 4) * 6.0)
		batch.append([c, 0.3 * i, Vector2(2.0, 2.0), c + Vector2(0, 3.3)])
	var a: RefCounted = StreetGraph.new()
	a._setup(st)
	for b: Array in batch:
		a.register_building(b[0], b[1], b[2], b[3])
	var c2: RefCounted = StreetGraph.new()
	c2._setup(st)
	c2.register_buildings(batch)
	assert_array(c2._nodes).is_equal(a._nodes)
	assert_array(c2._edges).is_equal(a._edges)
	assert_int(c2._edge_grid.size()).is_equal(a._edge_grid.size())
	# the incremental index equals a full re-index
	var grid_before: Dictionary = c2._edge_grid.duplicate(true)
	c2._edge_grid.clear()
	c2._indexed_edges = 0
	c2._index_edges()
	assert_bool(c2._edge_grid == grid_before).is_true()


func test_paths_wear_in_with_use_and_become_roads() -> void:
	var m := _mod(_rich())
	var a := _done(m, "storage_pile", 0)
	var b := _done(m, "campfire", 1)
	assert_str(m.trail_level(0.0)).is_equal("")
	m.note_trip(a, b, D.FOOTPATH_USES - 1.0)
	assert_array(m.trail_segments()).is_empty()
	m.note_trip(a, b, 1.0)
	assert_int(m.trail_segments().size()).is_equal(1)
	assert_float(m.path_speed(a, b)).is_equal(D.PATH_SPEED["footpath"])
	m.note_trip(a, b, D.ROAD_USES)
	assert_float(m.path_speed(a, b)).is_equal(D.PATH_SPEED["road"])
	assert_int(m.trail_list().size()).is_equal(1)


func test_haulers_carry_from_store_and_lay_trails() -> void:
	var m := _mod(_rich())
	_done(m, "campfire", 0)
	var pile := _done(m, "storage_pile", 1)
	var hid := int(m.sites[pile]["holding"])
	m.deposit(hid, "log", 50)
	m.deposit(hid, "thatch", 30)
	m.deposit(hid, "clay", 15)
	var hut := int(m.place("hut", _at(3), 0.0)["id"])
	m.sites[hut]["have"] = {}
	var hauler: Dictionary = m._new_worker("hired", "Carter", 0.3, 3, "haul")
	m._attach(hauler, hut)
	m.assign_player(hut)
	m.advance(100, {})
	assert_str(String(m.sites[hut]["state"])).is_equal("done")
	assert_float(float(m.trails[m._tkey(pile, hut)]["uses"])).is_greater(0.5)
	assert_int(m.store_count(hid, "log")).is_less(50)


func test_fewer_haulers_are_slower() -> void:
	var m := _mod(_rich())
	_done(m, "campfire", 0)
	var pile := _done(m, "storage_pile", 1)
	var hid := int(m.sites[pile]["holding"])
	m.deposit(hid, "log", 100)
	var id := int(m.place("fence", _at(3), 0.0)["id"])
	var site: Dictionary = m.sites[id]
	var w1: Dictionary = m._new_worker("hired", "A", 0.3, 3, "haul")
	m._attach(w1, id)
	var one: float = m.haul_rate(site, {})
	var w2: Dictionary = m._new_worker("hired", "B", 0.3, 3, "haul")
	m._attach(w2, id)
	assert_float(m.haul_rate(site, {})).is_greater(one * 1.6)


func test_settlement_levels_follow_buildings_and_population() -> void:
	var m := _mod(_rich())
	var kinds := ["campfire", "storage_pile", "lean_to", "tent", "hut", "hut", "hut"]
	var hid := 0
	for i in kinds.size():
		var id := _done(m, String(kinds[i]), i)
		hid = int(m.sites[id]["holding"])
	assert_str(String(m.holdings[hid]["level"])).is_equal("camp")   # buildings alone are not a hamlet: nobody lives there yet
	for day in 20:
		m.tick_day(day + 1, CTX)
	assert_int(int(m.holdings[hid]["pop"])).is_greater(5)
	assert_str(String(m.holdings[hid]["level"])).is_equal("hamlet")
	assert_array(m.next_level_needs(hid)).is_not_empty()
	var idn: Dictionary = m.holding_identity(hid)
	assert_str(String(idn["top"])).is_not_empty()
	assert_str(String(m.holding_info(hid)["level_name"])).is_equal("Hamlet")


func test_gathering_nodes_deplete_and_regrow() -> void:
	var m := _mod()
	var key := "3,4"
	var got := 0
	for i in 3:
		var r: Dictionary = m.strike_node(key, "tree", 10, true, 1, 0.9)
		got += int(r["n"])
		if i == 2:
			assert_bool(bool(r["felled"])).is_true()
	assert_int(got).is_equal(3 * 2 + 2)
	assert_bool(m.node_ready(key, "tree", 12)).is_false()
	assert_int(int(m.strike_node(key, "tree", 12, true, 1, 0.9)["n"])).is_equal(0)
	assert_bool(m.node_ready(key, "tree", 10 + int(D.NODES["tree"]["regrow"]))).is_true()
	# without a tool you get less
	assert_int(int(m.strike_node("9,9", "rock", 1, false, 1, 0.9)["n"])).is_equal(1)
	assert_int(int(m.strike_node("8,8", "rock", 1, true, 1, 0.9)["n"])).is_equal(2)


func test_world_has_gatherable_cells_of_each_kind() -> void:
	WorldGen.setup(2024)
	var m := _mod()
	var seen := {}
	for cx in range(-60, 60):
		for cz in range(-60, 60):
			var c: Dictionary = m.node_cell(Vector2i(cx, cz))
			if bool(c["ok"]):
				seen[String(c["kind"])] = int(seen.get(String(c["kind"]), 0)) + 1
	for k: String in D.NODES:
		assert_int(int(seen.get(k, 0))).is_greater(0)
	# deterministic
	assert_str(_norm(m.node_cell(Vector2i(7, 9)))).is_equal(_norm(m.node_cell(Vector2i(7, 9))))


func test_processing_needs_a_station_nearby() -> void:
	var m := _mod(_rich())
	_done(m, "campfire", 0)
	_done(m, "storage_pile", 1)
	_done(m, "hut", 2)
	_done(m, "workbench", 3)
	var horse := _done(m, "sawhorse", 4)
	m.bag["log"] = 10
	m.bag["plank"] = 0
	var far: Dictionary = m.process("sawhorse", 5, Vector2(99999, 99999))
	assert_bool(bool(far["ok"])).is_false()
	var r: Dictionary = m.process("sawhorse", 5, _at(4))
	assert_bool(bool(r["ok"])).is_true()
	assert_int(int(m.bag["plank"])).is_equal(5)
	assert_int(int(m.bag["log"])).is_equal(5)
	# a hired sawyer turns stored logs into planks while you are away
	var hid := int(m.sites[horse]["holding"])
	m.deposit(hid, "log", 30)
	var w: Dictionary = m._new_worker("hired", "Sawyer", 0.4, 3, "craft")
	m._attach(w, horse)
	m.sites[horse]["state"] = "done"
	m.advance(4, {})
	assert_int(m.store_count(hid, "plank")).is_greater(0)


func test_hiring_costs_wages_and_unpaid_workers_leave() -> void:
	var m := _mod(_rich())
	_done(m, "campfire", 0)
	_done(m, "storage_pile", 1)
	var id := int(m.place("hut", _at(2), 0.0)["id"])
	var r: Dictionary = m.hire_builder(id)
	if not bool(r["ok"]):
		assert_str(String(r["reason"])).is_not_empty()
		return
	assert_int(m.worker_count(id, "build")).is_equal(1)
	m.tick_day(5, CTX)
	assert_int(m.pending_gold).is_equal(-D.HIRE_WAGE)
	m.gold_ref = {"gold": 0}
	m.pending_gold = 0
	m.tick_day(6, CTX)
	assert_int(m.worker_count(id, "build")).is_equal(0)


func test_crew_output_is_the_shared_labour_model() -> void:
	var m := _mod()
	assert_float(m.crew_output(6)).is_equal_approx(6.0, 0.001)
	assert_float(m.crew_output(6, 0.8)).is_greater(6.5)
	assert_float(m.crew_output(6, 0.4, true)).is_greater(6.0 * 1.2)
	assert_float(m.crew_output(6, 0.4, false, 1)).is_greater(6.0)
	# fief projects count as buildings
	m.on_fief_complete(0, "market")
	assert_int(m.count_built("market")).is_equal(1)


func test_enterprise_projects_use_the_construction_crew_model() -> void:
	var hub: RefCounted = Hub.new()
	var e: RefCounted = hub.mod("enterprise")
	assert_bool(e.has_method("_construction")).is_true()
	assert_object(e.call("_construction")).is_same(hub.mod("construction"))


func test_json_round_trip() -> void:
	var m := _mod(_rich())
	_done(m, "campfire", 0)
	var pile := _done(m, "storage_pile", 1)
	var hut := int(m.place("hut", _at(2), 0.0)["id"])
	m.assign_player(hut)
	m.hire_builder(hut)
	m.deposit(int(m.sites[pile]["holding"]), "log", 7)
	m.note_trip(pile, hut, 9.0)
	m.strike_node("1,2", "tree", 3, true, 1, 0.5)
	m.known["build:masonry"] = true
	m.advance(5, {})
	var saved: Dictionary = JSON.parse_string(JSON.stringify(m.serialize()))
	var m2: RefCounted = Hub.new().mod("construction")
	m2.deserialize(saved)
	assert_str(_norm(m2.serialize())).is_equal(_norm(m.serialize()))
	assert_int(m2.sites.size()).is_equal(m.sites.size())
	assert_bool(m2.knows("build:masonry")).is_true()
	assert_float(float(m2.trails[m2._tkey(pile, hut)]["uses"])).is_equal(9.0)
	# the restored module keeps building
	m2.bag = _rich()
	m2.gold_ref = {"gold": 1000}
	m2.mastery_ref = Mastery.new()
	m2.advance(300, {})
	assert_str(String(m2.sites[hut]["state"])).is_equal("done")
	# the hub saves it with everything else
	var h := Hub.new()
	assert_bool((h.serialize() as Dictionary).has("construction")).is_true()


func test_realm_hub_registers_the_module() -> void:
	assert_bool(Hub.MODULES.has("construction")).is_true()
	assert_bool(Hub.ORDER.has("construction")).is_true()
	# Runs after the modules it reads (enterprise, work); later modules (towers) may follow it.
	assert_int(Hub.ORDER.find("construction")).is_greater(Hub.ORDER.find("enterprise"))


func test_catalogue_is_consistent() -> void:
	for k: String in D.KIND_ORDER:
		assert_bool(D.CATALOG.has(k)).is_true()
	assert_int(D.KIND_ORDER.size()).is_equal(D.CATALOG.size())
	for k: String in D.CATALOG:
		var d: Dictionary = D.CATALOG[k]
		assert_bool(int(d["tier"]) >= 0 and int(d["tier"]) <= 4).is_true()
		for n: String in d.get("needs", []):
			assert_bool(D.CATALOG.has(n)).is_true()
			assert_bool(int(D.CATALOG[n]["tier"]) <= int(d["tier"])).is_true()
		var from := String(d.get("upgrades_from", ""))
		if from != "":
			assert_bool(D.CATALOG.has(from)).is_true()
			assert_int(int(D.CATALOG[from]["tier"])).is_less(int(d["tier"]))
		for item: String in d["cost"]:
			assert_bool(D.MATERIALS.has(item)).is_true()
	# every tier has something to build, and higher tiers cost more labour
	for t in 5:
		assert_array(D.kinds_of_tier(t)).is_not_empty()
	assert_float(float(D.CATALOG["keep"]["hours"])).is_greater(float(D.CATALOG["hut"]["hours"]) * 10.0)
	# every material exists as an item
	var items: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	for item: String in D.MATERIALS:
		assert_bool(items.has(item)).is_true()


func test_stage_names_follow_progress() -> void:
	assert_str(D.stage_name(0.0)).is_equal("foundation")
	assert_str(D.stage_name(0.2)).is_equal("frame")
	assert_str(D.stage_name(0.5)).is_equal("walls")
	assert_str(D.stage_name(0.8)).is_equal("roof")
	assert_str(D.stage_name(1.0)).is_equal("complete")


func test_perf_many_sites_and_long_absence() -> void:
	var m := _mod(_rich())
	m.bag = {}
	var base := _flat_walkable()
	assert_bool(base != Vector2.INF).is_true()
	for i in 60:
		var pos := base + Vector2(float(i % 10) * 9.0, float(i / 10) * 9.0 + 40.0)
		var id := _add_raw(m, "fence" if i % 2 == 0 else "hut", pos)
		var w: Dictionary = m._new_worker("hired", "H", 0.3, 4, "build")
		m._attach(w, id)
	var t0 := Time.get_ticks_usec()
	m.catch_up(30, CTX)
	var catch_ms := (Time.get_ticks_usec() - t0) / 1000.0
	assert_float(catch_ms).is_less(250.0)
	t0 = Time.get_ticks_usec()
	for h in 24:
		m.tick_hour(h, CTX)
	var tick_ms := (Time.get_ticks_usec() - t0) / 1000.0
	assert_float(tick_ms).is_less(40.0)
	t0 = Time.get_ticks_usec()
	var route: PackedVector2Array = Nav.route(m, base + Vector2(-20, 20), base + Vector2(120, 100))
	assert_bool(route.size() >= 2).is_true()
	assert_float((Time.get_ticks_usec() - t0) / 1000.0).is_less(120.0)


func _add_raw(m: RefCounted, kind: String, pos: Vector2) -> int:
	var id: int = m._next_site
	m._next_site += 1
	var cost: Dictionary = m.costs_for(kind)
	m.sites[id] = {"id": id, "kind": kind, "pos": [pos.x, pos.y], "yaw": 0.0, "holding": 1, "state": "site", "progress": 0.0,
		"total": m.hours_for(kind), "need": cost, "have": cost.duplicate(), "workers": [], "upgrade_of": 0, "started_day": 0, "done_day": -1, "carry": 0.0}
	if m.holdings.is_empty():
		m.holdings[1] = {"id": 1, "name": "Camp 1", "pos": [pos.x, pos.y], "camp": -1, "pop": 0.0, "level": "camp", "store": {}, "founded_day": 0, "road_done": false}
	return id
