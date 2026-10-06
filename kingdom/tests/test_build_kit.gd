extends GdUnitTestSuite
## Build kit (scripts/realm/build_kit.gd): catalogue, snapping, support and collapse, plans raised by construction crews,
## refunds, settlement cap, roads, the packed save and its size, and the placement check cost.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const BuildKit := preload("res://scripts/realm/build_kit.gd")
const RoadTool := preload("res://scripts/build/road_tool.gd")
const Mastery := preload("res://scripts/sim/mastery.gd")
const Crafting := preload("res://scripts/sim/crafting.gd")
const LandClaim := preload("res://scripts/realm/land_claim.gd")
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


# --- hooks for the rest of the game (HOOKS_FOR_CLOUD.md, "Build kit hooks") ------------------------------------------

func _valid_claims(n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var step := 450.0
	for ix in range(-8, 9):
		for iz in range(-8, 9):
			var p := Vector2(ix * step, iz * step)
			if LandClaim.block_reason(p) == "" and not WorldGen.is_water(p.x, p.y):
				out.append(Vector3(p.x, 0, p.y))
				if out.size() >= n:
					return out
	return out


func test_claim_flow_founds_through_ensure_grid_with_land_rules_and_the_cap() -> void:
	var k := _kit(_rich())
	assert_bool(k.claim_rules).is_true()
	# Ashford's own square is not claimable; the reason names the town and the gap.
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	var refused: Dictionary = k.claim(Vector3(home.x + 20.0, 0, home.y))
	assert_bool(bool(refused["ok"])).is_false()
	assert_str(String(refused["reason"])).contains("Too close")
	assert_int(k.grids.size()).is_equal(0)
	# Open country is: three settlements, recorded as squats, then the cap (OWNER_DECISIONS: at most 3).
	var spots := _valid_claims(4)
	assert_int(spots.size()).is_equal(4)
	for i in 3:
		var r: Dictionary = k.claim(spots[i])
		assert_bool(bool(r["ok"])).is_true()
		assert_bool(bool(r["founded"])).is_true()
		assert_str(String(k.grids[int(r["gid"])]["claim"])).is_equal("squat")
	var fourth: Dictionary = k.claim(spots[3])
	assert_bool(bool(fourth["ok"])).is_false()
	assert_str(String(fourth["reason"])).contains("at most 3")
	# Standing inside a claimed grid is always fine, even where the rules would now refuse a new claim.
	var again: Dictionary = k.claim(Vector3(spots[0].x + 10.0, 0, spots[0].z))
	assert_bool(bool(again["ok"])).is_true()
	assert_bool(bool(again["founded"])).is_false()
	assert_int(k.grids.size()).is_equal(3)
	# The claim kind survives the save.
	var k2 := _kit(_rich())
	k2.deserialize(JSON.parse_string(JSON.stringify(k.serialize())))
	assert_str(String(k2.grids[1]["claim"])).is_equal("squat")
	# Water and the road centreline are refused too.
	var wet := Vector2.INF
	for x in range(-3000, 3000, 25):
		if WorldGen.is_water(x, 100):
			wet = Vector2(x, 100)
			break
	if wet != Vector2.INF:
		assert_str(LandClaim.block_reason(wet)).is_not_empty()


func test_built_stations_become_crafting_benches_and_construction_stations() -> void:
	var crafting: RefCounted = Crafting.new()
	var k := _kit(_rich())
	k.crafting = crafting
	var gid := int(k.ensure_grid(Vector3(3000, 0, 3000))["gid"])
	var c: RefCounted = k.hub.mod("construction")
	var at := {"forge": 0.0, "anvil": 2.0, "workbench": 4.0, "sawhorse_bench": 6.0, "loom": 8.0, "oven": 10.0}
	var ids := {}
	for kind: String in at:
		var r: Dictionary = _put(k, gid, kind, float(at[kind]), 0.0)
		assert_bool(bool(r["ok"])).override_failure_message("%s: %s" % [kind, r["reason"]]).is_true()
		ids[kind] = int(r["id"])
	var here: Vector3 = k.to_world(gid, Vector3(2.0, 0, 0))
	# crafting benches: forge and anvil are "anvil", workbench and sawhorse are "workbench", plus loom and oven
	for pair in [["forge", "anvil"], ["anvil", "anvil"], ["workbench", "workbench"], ["sawhorse_bench", "workbench"], ["loom", "loom"], ["oven", "oven"]]:
		var w: Vector3 = k.to_world(gid, Vector3(float(at[pair[0]]), 0, 0))
		assert_array(crafting.kinds_near(w)).override_failure_message("no %s bench at the %s" % [pair[1], pair[0]]).contains([pair[1]])
	var forge_st: Array = crafting.stations_near(k.to_world(gid, Vector3(0, 0, 0)))
	assert_bool(forge_st.any(func(st: Dictionary) -> bool: return String(st["ref"]).begins_with("kit:%d:%d" % [gid, ids["forge"]]))).is_true()
	# construction: a kit sawhorse is a crew station, a kit workbench is a workbench (and teaches carpentry)
	var kinds_built := {}
	for sid: int in c.sites:
		var s: Dictionary = c.sites[sid]
		if s.has("kit_key"):
			kinds_built[String(s["kind"])] = sid
			assert_str(String(s["state"])).is_equal("done")
	assert_bool(kinds_built.has("sawhorse")).is_true()
	assert_bool(kinds_built.has("workbench")).is_true()
	assert_bool(kinds_built.has("anvil")).is_false()
	assert_bool(c.known.has("build:carpentry")).is_true()
	# idempotent: another sync neither duplicates benches nor sites
	var n_sites: int = c.sites.size()
	var n_benches: int = crafting.all_stations().size()
	k.sync_realm()
	assert_int(c.sites.size()).is_equal(n_sites)
	assert_int(crafting.all_stations().size()).is_equal(n_benches)
	# removing the pieces takes the benches and sites away again
	k.remove(gid, int(ids["sawhorse_bench"]))
	k.remove(gid, int(ids["forge"]))
	assert_bool(c.sites.values().any(func(s: Dictionary) -> bool: return String(s.get("kit_key", "")) == "%d:%d" % [gid, ids["sawhorse_bench"]])).is_false()
	assert_bool(crafting.all_stations().any(func(st: Dictionary) -> bool: return String(st["ref"]).begins_with("kit:%d:%d:" % [gid, ids["forge"]]))).is_false()
	assert_array(crafting.kinds_near(Vector3(here.x, here.y, here.z))).contains(["anvil"])      # the standalone anvil still stands
	# a plan is not a bench until the crew has built it
	var before: int = crafting.all_stations().size()
	_put(k, gid, "loom", 12.0, 2.0, 0, 0, true)
	assert_int(crafting.all_stations().size()).is_equal(before)


func test_built_stations_survive_a_save_without_doubling() -> void:
	var crafting: RefCounted = Crafting.new()
	var k := _kit(_rich())
	k.crafting = crafting
	var gid := int(k.ensure_grid(Vector3(3000, 0, 3000))["gid"])
	_put(k, gid, "workbench", 0.0, 0.0)
	_put(k, gid, "oven", 2.0, 0.0)
	var c: RefCounted = k.hub.mod("construction")
	var data: Dictionary = k.serialize()
	var cdata: Dictionary = c.serialize()
	var crafting2: RefCounted = Crafting.new()
	var k2 := _kit(_rich())
	k2.crafting = crafting2
	var c2: RefCounted = k2.hub.mod("construction")
	c2.deserialize(JSON.parse_string(JSON.stringify(cdata)))
	k2.deserialize(JSON.parse_string(JSON.stringify(data)))
	assert_int(c2.sites.size()).is_equal(c.sites.size())          # the workbench site came back once, not twice
	assert_int(crafting2.all_stations().size()).is_equal(crafting.all_stations().size())
	assert_array(crafting2.kinds_near(k2.to_world(gid, Vector3(1, 0, 0)))).contains(["workbench", "oven"])


func test_storage_and_beds_add_to_the_holding() -> void:
	var k := _kit(_rich())
	var gid := int(k.ensure_grid(Vector3(3000, 0, 3000))["gid"])
	var c: RefCounted = k.hub.mod("construction")
	var spot: Vector3 = k.to_world(gid, Vector3.ZERO)
	var hid: int = c.holding_at(Vector2(spot.x, spot.z))
	var cap0 := 40
	var beds0 := 0
	if hid > 0:
		cap0 = c.store_cap(hid)
		beds0 = c.beds_of(hid)
	_put(k, gid, "storage_crates", 0.0, 0.0)
	_put(k, gid, "meshy_chest_metal_wood", 2.0, 0.0)
	_put(k, gid, "bed_simple", 4.0, 0.0)
	_put(k, gid, "meshy_bed_canopy_red", 6.0, 0.0)
	hid = c.holding_at(Vector2(spot.x, spot.z))
	assert_int(hid).is_greater(0)
	assert_int(c.store_cap(hid)).is_equal(cap0 + 40 + 30)
	assert_int(c.beds_of(hid)).is_equal(beds0 + 1 + 2)
	assert_int(int(c.holding_info(hid)["beds"])).is_equal(beds0 + 3)
	# the pieces going away takes the capacity with them
	for pid: int in k.grids[gid]["pieces"].keys():
		if String(k.grids[gid]["pieces"][pid]["kind"]) == "storage_crates":
			k.remove(gid, pid)
	assert_int(c.store_cap(hid)).is_equal(cap0 + 30)


func test_kit_roads_feed_route_speed_and_cart_traffic() -> void:
	var bag := {"stone": 400, "log": 50}
	var k := _kit(bag)
	var gid := int(k.ensure_grid(Vector3(3000, 0, 3000))["gid"])
	var c: RefCounted = k.hub.mod("construction")
	assert_array(c.trail_segments()).is_empty()
	var origin: Vector3 = k.to_world(gid, Vector3.ZERO)
	var stroke: Array = []
	for i in 12:
		stroke.append(Vector3(origin.x + i * 5.0, 0, origin.z))
	assert_bool(bool(k.add_road(gid, "cobble", stroke)["ok"])).is_true()
	assert_bool(bool(k.add_road(gid, "dirt", stroke.map(func(p: Vector3) -> Vector3: return p + Vector3(0, 0, 8)))["ok"])).is_true()
	var segs: Array = c.trail_segments()
	assert_int(segs.size()).is_greater(4)
	var speeds := {}
	for sg: Array in segs:
		speeds[sg[2]] = true
	assert_bool(speeds.has(float(BuildKit.road_def("cobble")["speed"]))).is_true()
	assert_bool(speeds.has(float(BuildKit.road_def("dirt")["speed"]))).is_true()
	# the crews' route search prefers the road: a cell on the cobble is faster than open ground
	var Nav := preload("res://scripts/realm/construction_nav.gd")
	assert_float(Nav._trail_speed(segs, Vector2(origin.x + 20.0, origin.z))).is_equal(float(BuildKit.road_def("cobble")["speed"]))
	assert_float(Nav._trail_speed(segs, Vector2(origin.x + 20.0, origin.z + 30.0))).is_equal(1.0)
	# cart traffic: dirt and cobble yield chords near the player (footpaths none), at the road's speed
	var near := Vector2(origin.x + 25.0, origin.z)
	var carts: Array = k.traffic_segments(near, 130.0)
	assert_int(carts.size()).is_greater(0)
	for t: Dictionary in carts:
		assert_float(float(t["speed"])).is_greater_equal(float(BuildKit.road_def("dirt")["speed"]))
	assert_int((k.traffic_segments(Vector2(origin.x + 4000.0, origin.z), 130.0) as Array).size()).is_equal(0)
	assert_bool(bool(k.add_road(gid, "path", stroke.map(func(p: Vector3) -> Vector3: return p + Vector3(0, 0, 20)))["ok"])).is_true()
	assert_int((k.road_chords(24.0, ["path"]) as Array).size()).is_greater(0)
	for t: Dictionary in k.traffic_segments(Vector2(origin.x + 25.0, origin.z + 20.0), 5.0):
		assert_float(float(t["speed"])).is_greater(1.25)        # the footpath (speed 1.25) carries no carts
	# the route segments are capped
	assert_int((k.road_chords(BuildKit.ROUTE_STEP, [], Vector2.INF, INF, BuildKit.MAX_ROUTE_SEGMENTS) as Array).size()).is_less_equal(BuildKit.MAX_ROUTE_SEGMENTS)
