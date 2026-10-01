extends GdUnitTestSuite
## Town districts, house detail keys and the outside-the-walls identity sites (docs/design/VERTICAL_SLICE.md P1).

const Districts := preload("res://scripts/world/districts.gd")
const HouseDetails := preload("res://scripts/world/house_details.gd")


func before() -> void:
	WorldGen.setup(1066)


func _thornfield() -> Dictionary:
	for s in WorldGen.settlements:
		if s["name"] == "Thornfield":
			return s
	return {}


func test_every_town_is_zoned() -> void:
	for s in WorldGen.settlements:
		var plan: Dictionary = s["plan"]
		assert_bool(plan.has("district_anchors")).is_true()
		for lot: Dictionary in plan["lots"]:
			assert_bool(Districts.KINDS.has(lot["district"])).override_failure_message("%s lot %s" % [s["name"], lot]).is_true()
			assert_float(float(lot["wealth"])).is_between(0.0, 1.0)


func test_thornfield_has_six_readable_districts() -> void:
	var s := _thornfield()
	assert_bool(s.is_empty()).is_false()
	var count := {}
	for lot: Dictionary in s["plan"]["lots"]:
		count[lot["district"]] = int(count.get(lot["district"], 0)) + 1
	for dk: String in Districts.KINDS:
		assert_int(int(count.get(dk, 0))).override_failure_message("Thornfield has no %s lots: %s" % [dk, count]).is_greater(2)


func test_district_at_matches_the_lots() -> void:
	var s := _thornfield()
	for lot: Dictionary in s["plan"]["lots"]:
		assert_str(Districts.district_at(lot["pos"])).is_equal(lot["district"])
		assert_str(CityPlanner.district_at(s["plan"], lot["pos"])).is_equal(lot["district"])
	# The countryside is no district.
	assert_str(Districts.district_at(Vector2(s["pos"]) + Vector2(float(s["radius"]) * 3.0, 0.0))).is_equal("")


func test_districts_prefer_their_buildings() -> void:
	var s := _thornfield()
	var poor_town := 0
	var market_town := 0
	for lot: Dictionary in s["plan"]["lots"]:
		if lot["district"] == Districts.MARKET and String(lot["asset"]).begins_with("house_town"):
			market_town += 1
		if lot["district"] == Districts.POOR and String(lot["asset"]).begins_with("house_town"):
			poor_town += 1
	assert_int(market_town).is_greater(poor_town)


func test_detail_keys_are_20_to_30_and_resolve() -> void:
	var keys := HouseDetails.keys()
	assert_int(keys.size()).is_between(20, 30)
	for k: String in keys:
		if HouseDetails.is_decal(k):
			continue
		assert_object(HouseDetails.mesh_for(k)).override_failure_message("detail key %s has no mesh" % k).is_not_null()


func test_houses_choose_different_details() -> void:
	var s := _thornfield()
	var seen := {}
	var rng := RandomNumberGenerator.new()
	for lot: Dictionary in s["plan"]["lots"]:
		rng.seed = int(lot["seed"])
		var picks := []
		for e: Dictionary in HouseDetails.choose(lot, Vector3(7, 7, 6), rng):
			picks.append(e["key"])
		picks.sort()
		seen[str(picks)] = true
	assert_int(seen.size()).is_greater(30)


func test_outer_identity_sites() -> void:
	var idents := {}
	for st in WorldGen.sites:
		if st.has("ident"):
			idents[st["ident"]] = int(idents.get(st["ident"], 0)) + 1
			assert_str(st["kind"]).is_equal("roadside")
	for k in ["ward_marker", "checkpoint", "warning_post", "cracked_stone", "caravan"]:
		assert_bool(idents.has(k)).override_failure_message("missing %s sites: %s" % [k, idents]).is_true()


func _dp_count(root: Node3D) -> int:
	var holder := root.get_node_or_null("DistrictProps")
	return 0 if holder == null else holder.find_children("*", "MultiMeshInstance3D", true, false).size()


## The town's district props are built over frames (per-frame budget), with the very same result as the all-at-once build.
func test_district_props_build_is_time_sliced_and_identical() -> void:
	var s := _thornfield()
	var sb := SettlementBuilder.new()
	add_child(sb)
	auto_free(sb)
	var root: Node3D = sb._build(s, false)
	assert_bool(bool(root.get_meta("props_pending", false))).is_true()
	assert_int(sb._prop_jobs.size()).is_equal(1)
	assert_int(_dp_count(root)).is_equal(0)           # nothing of it exists yet: no hitch in the build frame
	var job = sb._prop_jobs[0]
	var steps := 0
	while not job.step(1.0) and steps < 20000:
		steps += 1
	assert_bool(job.done).is_true()
	assert_int(steps).is_greater(5)                    # really spread out
	assert_bool(bool(root.get_meta("props_pending", false))).is_false()
	var sliced := _dp_count(root)
	assert_int(sliced).is_greater(20)
	var root2: Node3D = sb._build(s, true)             # tests and the world lint build synchronously
	assert_bool(bool(root2.get_meta("props_pending", false))).is_false()
	assert_int(_dp_count(root2)).is_equal(sliced)
	assert_int(root2.find_children("*", "Decal", true, false).size()).is_equal(root.find_children("*", "Decal", true, false).size())
	assert_int(root2.get_child_count()).is_equal(root.get_child_count())


func test_finish_prop_jobs_completes_pending_towns() -> void:
	var s := _thornfield()
	var sb := SettlementBuilder.new()
	add_child(sb)
	auto_free(sb)
	var root: Node3D = sb._build(s, false)
	sb.finish_prop_jobs()
	assert_bool(bool(root.get_meta("props_pending", false))).is_false()
	assert_int(sb._prop_jobs.size()).is_equal(0)
	assert_int(_dp_count(root)).is_greater(20)
