extends GdUnitTestSuite
## READY_V1 C2, one settlement model: a build-kit claim starts exactly one founding record and one civilization row, all three share
## ids (RealmHub.player_settlements / settlement_of_grid), abandoning clears all three, the cap of 3 holds and the ids survive a save.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const BuildKit := preload("res://scripts/realm/build_kit.gd")
const LandClaim := preload("res://scripts/realm/land_claim.gd")


func _mk() -> RefCounted:
	WorldGen.setup(WorldSim.SEED)
	var hub: RefCounted = Hub.new()
	var rs := RARunestoneNetwork.new()
	rs.seed_road_stones()
	hub.mod("civilization").runestones = rs
	for m: String in ["civilization", "migration", "land"]:
		hub.mod(m)._ensure()
	hub.mod("build_kit").height_fn = func(x: float, z: float) -> float: return WorldGen.height(x, z)
	return hub


## Open ground that LandClaim allows and that the founding module accepts, at least 500 m apart.
func _spots(hub: RefCounted, n: int) -> Array:
	var fd: RefCounted = hub.mod("founding")
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for _i in 6000:
		if out.size() >= n:
			break
		var p := Vector2(rng.randf_range(-3000.0, 3000.0), rng.randf_range(-3000.0, 3000.0))
		if LandClaim.block_reason(p) != "":
			continue
		var ev: Dictionary = fd.evaluate_site(p)
		if String(ev["blocked"]) != "" or float(ev["overall"]) < 0.3 or float(ev["camp"]) < float(hub.mod("camps").MIN_CAMP_SCORE):
			continue
		var far := true
		for q: Vector2 in out:
			far = far and q.distance_to(p) > 500.0
		if far:
			out.append(p)
	return out


func _w(p: Vector2) -> Vector3:
	return Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


func test_claim_makes_one_founding_and_one_row_linked_by_ids() -> void:
	var hub := _mk()
	var spots := _spots(hub, 4)
	assert_int(spots.size()).is_equal(4)
	var bk: RefCounted = hub.mod("build_kit")
	var fd: RefCounted = hub.mod("founding")
	var civ: RefCounted = hub.mod("civilization")
	var dyn0: int = civ.dynamic_count()
	var r: Dictionary = bk.claim(_w(spots[0]), "squat", "Newhold")
	assert_bool(bool(r["ok"])).override_failure_message(String(r["reason"])).is_true()
	var gid := int(r["gid"])
	assert_int(fd.active_count("player")).is_equal(1)
	assert_int(civ.dynamic_count()).is_equal(dyn0 + 1)
	var rows: Array = hub.player_settlements()
	assert_int(rows.size()).is_equal(1)
	var row: Dictionary = hub.settlement_of_grid(gid)
	assert_int(int(row["gid"])).is_equal(gid)
	assert_str(String(row["name"])).is_equal("Newhold")
	var f: Dictionary = fd.get_founding(int(row["fid"]))
	assert_int(int(f["gid"])).is_equal(gid)
	assert_str(String(f["node"])).is_equal(String(row["node"]))
	assert_bool(civ.has_place(String(row["node"]))).is_true()
	assert_str(String(civ.place(String(row["node"]))["name"])).is_equal("Newhold")
	# claiming again inside the grid changes nothing
	var again: Dictionary = bk.claim(_w(spots[0]) + Vector3(8, 0, 0))
	assert_bool(bool(again["founded"])).is_false()
	assert_int(fd.active_count("player")).is_equal(1)
	assert_int(civ.dynamic_count()).is_equal(dyn0 + 1)
	assert_dict(hub.settlement_of_grid(999)).is_empty()


func test_abandon_clears_grid_founding_and_row() -> void:
	var hub := _mk()
	var spots := _spots(hub, 4)
	var bk: RefCounted = hub.mod("build_kit")
	var fd: RefCounted = hub.mod("founding")
	var civ: RefCounted = hub.mod("civilization")
	var dyn0: int = civ.dynamic_count()
	var gid := int(bk.claim(_w(spots[0]))["gid"])
	var node := String(hub.settlement_of_grid(gid)["node"])
	assert_bool(bool(bk.abandon(gid)["ok"])).is_true()
	assert_int(bk.grids.size()).is_equal(0)
	assert_int(fd.active_count("player")).is_equal(0)
	assert_bool(civ.has_place(node)).is_false()
	assert_int(civ.dynamic_count()).is_equal(dyn0)
	assert_array(hub.player_settlements()).is_empty()
	assert_bool(bool(bk.abandon(gid)["ok"])).is_false()
	# the slot is free again, from either side: giving up through the founding record clears the grid too
	var gid2 := int(bk.claim(_w(spots[1]))["gid"])
	var fid := int(hub.settlement_of_grid(gid2)["fid"])
	assert_bool(fd.abandon(fid)).is_true()
	assert_int(bk.grids.size()).is_equal(0)
	assert_array(hub.player_settlements()).is_empty()


func test_fourth_claim_is_refused_and_leaves_nothing_behind() -> void:
	var hub := _mk()
	var spots := _spots(hub, 4)
	var bk: RefCounted = hub.mod("build_kit")
	var fd: RefCounted = hub.mod("founding")
	var civ: RefCounted = hub.mod("civilization")
	for i in BuildKit.MAX_GRIDS:
		assert_bool(bool(bk.claim(_w(spots[i]))["ok"])).is_true()
	var dyn: int = civ.dynamic_count()
	var r4: Dictionary = bk.claim(_w(spots[3]))
	assert_bool(bool(r4["ok"])).is_false()
	assert_str(String(r4["reason"])).contains("at most 3")
	assert_int(bk.grids.size()).is_equal(3)
	assert_int(fd.active_count("player")).is_equal(3)
	assert_int(civ.dynamic_count()).is_equal(dyn)
	assert_int(hub.player_settlements().size()).is_equal(3)
	# giving one up frees the slot
	bk.abandon(int((hub.player_settlements()[0] as Dictionary)["gid"]))
	assert_bool(bool(bk.claim(_w(spots[3]))["ok"])).override_failure_message("slot not freed").is_true()


func test_ids_survive_save_and_load() -> void:
	var hub := _mk()
	var spots := _spots(hub, 2)
	var bk: RefCounted = hub.mod("build_kit")
	for i in 2:
		bk.claim(_w(spots[i]), "squat", "Home%d" % i)
	var before: Array = hub.player_settlements()
	var hub2: RefCounted = Hub.new()
	for m: String in ["build_kit", "founding", "civilization", "camps"]:   # the modules that carry the three ids
		hub2.mod(m).deserialize(JSON.parse_string(JSON.stringify(hub.mod(m).serialize())))
	var after: Array = hub2.player_settlements()
	assert_int(after.size()).is_equal(2)
	for i in 2:
		for k in ["gid", "fid", "node", "name", "stage", "pop"]:
			assert_that(after[i][k]).is_equal(before[i][k])
		assert_int(int(hub2.mod("founding").get_founding(int(after[i]["fid"]))["gid"])).is_equal(int(after[i]["gid"]))
		assert_bool(hub2.mod("civilization").has_place(String(after[i]["node"]))).is_true()
	# and the unified record still abandons cleanly after a load
	hub2.mod("build_kit").abandon(int(after[0]["gid"]))
	assert_int(hub2.player_settlements().size()).is_equal(1)
	assert_int(hub2.mod("founding").active_count("player")).is_equal(1)
