extends GdUnitTestSuite
## Build kit (scripts/realm/build_kit.gd): catalogue, snapping, support and collapse, plans raised by construction crews,
## refunds, settlement cap, roads, the packed save and its size, and the placement check cost.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const BuildKit := preload("res://scripts/realm/build_kit.gd")
const RoadTool := preload("res://scripts/build/road_tool.gd")
const Mastery := preload("res://scripts/sim/mastery.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 0, "life": null}


func _rich() -> Dictionary:
	return {"log": 4000, "plank": 4000, "stone": 4000, "cut_stone": 4000, "clay": 2000, "thatch": 2000, "iron_ingot": 500, "tools": 200, "cloth": 200}


## A hub with construction + build kit sharing one bag, all know-how learned, flat ground.
func _kit(bag := {}) -> RefCounted:
	WorldGen.setup(2024)
	var hub: RefCounted = Hub.new()
	var c: RefCounted = hub.mod("construction")
	c.bag = bag
	c.gold_ref = {"gold": 5000}
	c.mastery_ref = Mastery.new()
	for f: String in ["build:carpentry", "build:masonry", "build:architecture"]:
		c.known[f] = true
	var k: RefCounted = hub.mod("build_kit")
	k.height_fn = func(_x: float, _z: float) -> float: return 0.0
	return k


func _put(k: RefCounted, gid: int, kind: String, x: float, z: float, rot := 0, lv := 0, plan := false) -> Dictionary:
	return k.place(gid, k.snap_local(gid, kind, Vector3(x, 0, z), rot, lv), plan)


func test_catalogue_is_complete() -> void:
	var cat: Dictionary = BuildKit.catalog()
	assert_int((cat["order"] as Array).size()).is_greater_equal(60)
	var cats: Array = cat["categories"]
	var ids := {}
	for id: String in cat["order"]:
		var d := BuildKit.def(id)
		assert_bool(ids.has(id)).is_false()
		ids[id] = true
		assert_bool(cats.has(String(d["cat"]))).is_true()
		assert_int(int(d["tier"])).is_between(0, 4)
		assert_bool(String(d["snap"]) in ["cell", "edge", "free"]).is_true()
		for item: String in d.get("cost", {}):
			assert_bool(item in ["log", "plank", "stone", "cut_stone", "clay", "thatch", "iron_ingot", "tools", "cloth"]).is_true()
	for c: String in cats:
		assert_array(BuildKit.kinds_in(c)).is_not_empty()
	# every blueprint row names a real piece
	for bp: String in cat["blueprints"]:
		for row: Array in cat["blueprints"][bp]["pieces"]:
			assert_bool(ids.has(String(row[0]))).is_true()


func test_snapping_cells_edges_storeys_and_props() -> void:
	var k := _kit(_rich())
	var gid := int(k.ensure_grid(Vector3(101, 0, 49))["gid"])
	assert_vector(k.to_world(gid, Vector3.ZERO)).is_equal(Vector3(102, 0, 50))
	var s: Dictionary = k.snap_local(gid, "foundation_stone", Vector3(2.7, 0, -1.2), 0, 0)
	assert_vector(s["p"]).is_equal(Vector3(2, 0, -2))
	var w: Dictionary = k.snap_local(gid, "wall_plaster", Vector3(0.4, 0, 0.8), 0, 0)
	assert_str(String(w["slot"])).is_equal("ex")
	assert_vector(w["p"]).is_equal(Vector3(0, 0.5, 1))
	var w2: Dictionary = k.snap_local(gid, "wall_plaster", Vector3(0.8, 0, 0.4), 1, 1)
	assert_str(String(w2["slot"])).is_equal("ez")
	assert_vector(w2["p"]).is_equal(Vector3(1, 3.5, 0))
	var st: Dictionary = k.snap_local(gid, "stairs_wood", Vector3(0, 0, 0.6), 0, 0)
	assert_vector(st["p"]).is_equal(Vector3(0, 0.5, 1))
	var pr: Dictionary = k.snap_local(gid, "anvil", Vector3(0.37, 0, 1.12), 3, 0)
	assert_vector(pr["p"]).is_equal(Vector3(0.5, 0, 1.0))
	assert_int(int(pr["rot"])).is_equal(45)
	var roof: Dictionary = k.snap_local(gid, "roof_slate", Vector3.ZERO, 0, 0)
	assert_int(int(roof["L"])).is_equal(1)          # roofs never sit on the ground


func test_support_rules_and_collapse_with_refunds() -> void:
	var bag := _rich()
	var k := _kit(bag)
	var gid := int(k.ensure_grid(Vector3.ZERO)["gid"])
	# a wall in mid-air has nothing to hold it
	var lone: Dictionary = k.check(gid, k.snap_local(gid, "wall_log", Vector3(0, 0, 1), 0, 0))
	assert_bool(bool(lone["ok"])).is_false()
	assert_str(String(lone["reason"])).contains("holds")
	assert_bool(bool(_put(k, gid, "foundation_timber", 0, 0)["ok"])).is_true()
	var wall: Dictionary = _put(k, gid, "wall_log", 0, 1)
	assert_bool(bool(wall["ok"])).is_true()
	# second storey: a wall on the wall, a floor carried by it, floors cantilever up to the wood span
	assert_bool(bool(_put(k, gid, "wall_log", 0, 1, 0, 1)["ok"])).is_true()
	var f1: Dictionary = _put(k, gid, "floor_plank", 0, 2, 0, 1)
	assert_bool(bool(f1["ok"])).is_true()
	var f2: Dictionary = _put(k, gid, "floor_plank", 0, 4, 0, 1)
	var f3: Dictionary = _put(k, gid, "floor_plank", 0, 6, 0, 1)
	assert_bool(bool(f2["ok"]) and bool(f3["ok"])).is_true()
	assert_float(float(k.integrity(gid, int(f3["id"])))).is_less(float(k.integrity(gid, int(f1["id"]))))
	var f4: Dictionary = k.check(gid, k.snap_local(gid, "floor_plank", Vector3(0, 0, 8), 0, 1))
	assert_bool(bool(f4["ok"])).is_false()          # past the 3-cell wood span
	# the same reach in stone carries further (5 cells)
	assert_float(float(BuildKit.LOSS_H["stone"])).is_less(float(BuildKit.LOSS_H["wood"]))
	# knock out the ground-floor wall: everything above falls, with a quarter refund each
	var before := int(bag["log"])
	var r: Dictionary = k.remove(gid, int(wall["id"]))
	assert_bool(bool(r["ok"])).is_true()
	assert_int((r["collapsed"] as Array).size()).is_equal(4)
	assert_int(int(bag["log"])).is_greater(before)
	assert_int(k.piece_count(gid)).is_equal(1)


func test_occupancy_doors_and_ground() -> void:
	var k := _kit(_rich())
	var gid := int(k.ensure_grid(Vector3.ZERO)["gid"])
	_put(k, gid, "foundation_stone", 0, 0)
	assert_bool(bool(_put(k, gid, "foundation_stone", 0.3, 0.2)["ok"])).is_false()
	_put(k, gid, "wall_stone", 0, 1)
	var door: Dictionary = k.check(gid, k.snap_local(gid, "door_wood", Vector3(0, 0, 1), 0, 0))
	assert_bool(bool(door["ok"])).is_false()        # not a doorway (and the slot is the same edge)
	assert_bool(bool(_put(k, gid, "wall_stone_door", 0, -1)["ok"])).is_true()
	assert_bool(bool(_put(k, gid, "door_wood", 0, -1)["ok"])).is_true()
	# steep ground refuses foundations
	k.height_fn = func(x: float, _z: float) -> float: return x * 0.9
	var steep: Dictionary = k.check(gid, k.snap_local(gid, "foundation_timber", Vector3(6, 0, 0), 0, 0))
	assert_str(String(steep["reason"])).contains("steep")


func test_materials_plans_and_crew_build_them() -> void:
	var bag := {"log": 3}
	var k := _kit(bag)
	var gid := int(k.ensure_grid(Vector3.ZERO)["gid"])
	var direct: Dictionary = _put(k, gid, "foundation_timber", 0, 0)
	assert_bool(bool(direct["ok"])).is_false()      # 4 logs needed
	var bp: Dictionary = k.place_blueprint(gid, "cottage", 0, 0, 0)
	assert_int(int(bp["failed"])).is_equal(0)
	assert_int(int(bp["placed"])).is_equal(23)
	var hand: Dictionary = k.hand_to_workers(gid)
	assert_bool(bool(hand["ok"])).is_true()
	var c: RefCounted = k.hub.mod("construction")
	var site: Dictionary = c.sites[int(hand["site"])]
	assert_str(String(site["kind"])).is_equal("kit_plan")
	assert_int(int(site["need"]["log"])).is_greater(40)
	assert_bool(k.plan_piece_built(gid, int(hand["site"]) * 0 + 1)).is_false()
	# the crew finishes: half way the lower pieces stand, at the end every plan is a real piece
	site["progress"] = float(site["total"]) * 0.5
	var standing := 0
	for pid: int in k.grids[gid]["pieces"]:
		if k.plan_piece_built(gid, pid):
			standing += 1
	assert_int(standing).is_between(9, 13)
	site["state"] = "done"
	k.tick_hour(8, CTX)
	for pid: int in k.grids[gid]["pieces"]:
		assert_str(String(k.grids[gid]["pieces"][pid]["state"])).is_equal("done")


func test_three_settlements_max_and_piece_cap() -> void:
	var k := _kit(_rich())
	for i in 3:
		assert_bool(bool(k.ensure_grid(Vector3(i * 500.0, 0, 0))["ok"])).is_true()
	var fourth: Dictionary = k.ensure_grid(Vector3(5000, 0, 0))
	assert_bool(bool(fourth["ok"])).is_false()
	assert_bool(bool(k.ensure_grid(Vector3(10, 0, 10))["ok"])).is_true()   # inside the first one
	k.cap = 2
	_put(k, 1, "foundation_timber", 0, 0)
	_put(k, 1, "foundation_timber", 2, 0)
	assert_str(String(_put(k, 1, "foundation_timber", 4, 0)["reason"])).contains("limit")


func test_roads_smooth_cost_and_ribbon() -> void:
	var stroke: Array = []
	for i in 60:
		stroke.append(Vector3(i * 1.0, 0, sin(i * 0.15) * 4.0 + randf() * 0.2))
	var t0 := Time.get_ticks_usec()
	var pts := RoadTool.process(stroke, [Vector3(-3, 0, 1)])
	var mesh := RoadTool.ribbon(pts, 4.0, func(_x: float, _z: float) -> float: return 0.0)
	assert_int(Time.get_ticks_usec() - t0).is_less(50000)
	assert_vector(pts[0]).is_equal(Vector3(-3, 0, 1))         # snapped to the existing road end
	assert_int(mesh.get_surface_count()).is_equal(1)
	var bag := {"stone": 100}
	var k := _kit(bag)
	var gid := int(k.ensure_grid(Vector3.ZERO)["gid"])
	var r: Dictionary = k.add_road(gid, "cobble", pts)
	assert_bool(bool(r["ok"])).is_true()
	assert_int(int(bag["stone"])).is_less(100)


func test_save_round_trip_and_size() -> void:
	var k := _kit(_rich())
	var gid := int(k.ensure_grid(Vector3(40, 0, 40))["gid"])
	k.place_blueprint(gid, "townhouse", 0, 0, 1)
	_put(k, gid, "anvil", 7.3, 2.2, 5)
	var before: Dictionary = k.grids[gid]["pieces"].duplicate(true)
	var data: Dictionary = k.serialize()
	var k2 := _kit(_rich())
	k2.deserialize(JSON.parse_string(JSON.stringify(data)))
	assert_int(k2.piece_count(gid)).is_equal(before.size())
	var kinds_a: Array = []
	var kinds_b: Array = []
	for pid: int in before:
		kinds_a.append("%s@%s,%s" % [before[pid]["kind"], before[pid]["slot"], before[pid]["L"]])
	for pid: int in k2.grids[gid]["pieces"]:
		var r: Dictionary = k2.grids[gid]["pieces"][pid]
		kinds_b.append("%s@%s,%s" % [r["kind"], r["slot"], r["L"]])
	kinds_a.sort()
	kinds_b.sort()
	assert_array(kinds_b).is_equal(kinds_a)
	# the slot index is rebuilt: the same cell is taken again after loading
	assert_bool(bool(k2.place(gid, k2.snap_local(gid, "foundation_stone", Vector3(0, 0, 0), 0, 0))["ok"])).is_false()
	# 2,200 pieces stay within the 60 KB settlement budget
	var big := _kit(_rich())
	var g2 := int(big.ensure_grid(Vector3.ZERO)["gid"])
	for i in 2200:
		var rec := {"id": i + 1, "kind": "anvil", "slot": "free", "i": 0, "k": 0, "L": 0, "rot": 30, "p": [float(i % 50), 0.0, float(i / 50)], "state": "done", "hp": 1.0, "site": 0}
		big.grids[g2]["pieces"][i + 1] = rec
	var size := JSON.stringify(big.serialize()).length()
	assert_int(size).is_less(60 * 1024)


func test_place_check_is_fast() -> void:
	var k := _kit(_rich())
	var gid := int(k.ensure_grid(Vector3.ZERO)["gid"])
	for i in 6:
		for j in 6:
			k.place_blueprint(gid, "cottage", i * 4, j * 4, 0)
	assert_int(k.piece_count(gid)).is_greater(700)
	var t0 := Time.get_ticks_usec()
	for n in 100:
		k.check(gid, k.snap_local(gid, "wall_plaster", Vector3(n * 0.3, 0, 7), 0, 1))
	var per := (Time.get_ticks_usec() - t0) / 100.0
	assert_float(per).is_less(1000.0 * 4.0)          # < 1 ms target; loose for slow CI runners
