extends GdUnitTestSuite
## Market goods kit, village plaza cobbles and the decal library: the pieces exist, the composed layouts stay
## inside the mobile triangle budget and are one surface (one draw), village squares are paved with the same
## cobble channel as the towns', and the decal library files import.

const STALL_TRI_BUDGET := 8000       # composed counter + hanging + ground goods of one stall
const SIDE_TRI_BUDGET := 3000
const SHOP_TRI_BUDGET := 3000


func before() -> void:
	WorldGen.setup(1066)


func test_kit_is_present_and_has_the_pieces() -> void:
	assert_bool(MarketGoods.available()).is_true()
	var names := MarketGoods.piece_names()
	assert_int(names.size()).is_greater_equal(50)
	for n in ["crate_apples", "barrel_apples", "bread", "cheese_round", "fish", "vase_big", "sack_grain", "candle_a", "book_stack_a", "axe", "lantern_hang", "sausage_hang"]:
		assert_bool(names.has(n)).override_failure_message("missing piece %s" % n).is_true()


func test_layouts_are_single_surface_and_light() -> void:
	var ids: Array[String] = []
	for t in MarketGoods.THEMES:
		ids.append("stall_" + t)
		ids.append("stall_" + t + "_lite")
	ids.append_array(["side_a", "side_b"])
	ids.append_array(MarketGoods.SHOPS)
	for id in ids:
		var m := MarketGoods.layout(id)
		assert_object(m).override_failure_message("layout %s missing" % id).is_not_null()
		assert_int(m.get_surface_count()).is_equal(1)
		var budget := STALL_TRI_BUDGET if id.begins_with("stall_") else (SIDE_TRI_BUDGET if id.begins_with("side_") else SHOP_TRI_BUDGET)
		assert_int(MarketGoods.tri_count(id)).override_failure_message("%s: %d tris" % [id, MarketGoods.tri_count(id)]).is_less(budget)
		# Stall dressing sits on the counter and in front of it: never below the ground or above the awning beam.
		var box := m.get_aabb()
		assert_float(box.position.y).is_greater_equal(-0.01)
		assert_float(box.end.y).is_less(2.0)


func test_full_stall_layouts_stay_in_front_of_the_awning_zone() -> void:
	for t in MarketGoods.THEMES:
		var box := MarketGoods.layout("stall_" + t).get_aabb()
		# ground goods reach out at most ~2 m in front (FRONT_RECT is z 1.15 .. 1.95) and never behind the counter
		assert_float(box.end.z).is_less(2.3)
		assert_float(box.position.z).is_greater(-0.2)
		assert_float(box.size.x).is_less(4.2)


func test_village_squares_are_cobbled() -> void:
	var seen := 0
	for s: Dictionary in WorldGen.settlements:
		if s["kind"] != "village":
			continue
		seen += 1
		var c: Vector2 = s["pos"]
		var pr: float = s["plan"]["plaza_r"]
		# the middle of the square and a point most of the way to the rim are paved (channel B) ...
		for d: float in [pr * 0.3, pr * 0.8]:
			var p := c + Vector2(cos(0.9), sin(0.9)) * d
			var w := WorldGen.color_at(p.x, p.y, WorldGen.height(p.x, p.y), 0.0)
			assert_float(w.b).override_failure_message("%s: no cobble %.1f m from the centre (b=%.2f)" % [s["name"], d, w.b]).is_greater(0.9)
		# ... and the paving gives way to grass well before the houses (no bare dirt ring).
		var far := c + Vector2(cos(0.9), sin(0.9)) * (pr + 10.0)
		if CityPlanner.street_distance(s["plan"], far) > 3.0 and CityPlanner.path_distance(s["plan"], far) > 2.0:
			var wf := WorldGen.color_at(far.x, far.y, WorldGen.height(far.x, far.y), 0.0)
			assert_float(wf.b).is_less(0.05)
	assert_int(seen).is_greater(0)


func test_decal_library_imports() -> void:
	assert_bool(TownDecals.available()).is_true()
	for kind: String in TownDecals.KINDS:
		var d := TownDecals.make(kind, Vector3.ONE, TownDecals.WALL_LAYER)
		assert_object(d.texture_albedo).override_failure_message("decal %s has no albedo" % kind).is_not_null()
		assert_bool(d.distance_fade_enabled).is_true()
		assert_float(d.distance_fade_begin + d.distance_fade_length).is_less_equal(40.0)
		d.free()
	# wall decals look into the wall: local Y = outward normal, image up = world up
	var b := TownDecals.wall_basis(Vector3(0, 0, 1))
	assert_vector(b.y).is_equal_approx(Vector3(0, 0, 1), Vector3(0.001, 0.001, 0.001))
	assert_vector(-b.z).is_equal_approx(Vector3.UP, Vector3(0.001, 0.001, 0.001))
	assert_float(b.determinant()).is_equal_approx(1.0, 0.001)


func test_settlement_dressing_is_render_only_and_within_budget() -> void:
	var town: Dictionary = WorldGen.settlements[1]        # Kingsreach, the walled capital
	var builder := SettlementBuilder.new()
	add_child(builder)
	builder.focus = Vector3(town["pos"].x, 0.0, town["pos"].y)
	for _i in 6:                 # one settlement per call
		builder.update_now()
	builder.finish_prop_jobs()   # the district props stream over frames in the game
	assert_bool(builder._built.has(town["id"])).is_true()
	var root: Node3D = builder._built[town["id"]]
	# every goods MultiMesh: no shadows, culled early, shared material
	var goods := 0
	for mmi in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mesh := (mmi as MultiMeshInstance3D).multimesh.mesh
		if mesh != null and mesh.get_surface_count() == 1 and mesh.surface_get_material(0) == MarketGoods.material():
			goods += 1
			assert_int((mmi as MultiMeshInstance3D).cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			assert_float((mmi as MultiMeshInstance3D).visibility_range_end).is_less_equal(80.0)
	assert_int(goods).is_greater(0)
	# decals (none on LOW): ground decals <= CHUNK_CAP per 64 m chunk, every decal fades out by 40 m
	var chunks := {}
	var walls := 0
	for d in root.find_children("*", "Decal", true, false):
		var dec := d as Decal
		assert_float(dec.distance_fade_begin + dec.distance_fade_length).is_less_equal(40.0)
		if dec.cull_mask == TownDecals.GROUND_LAYER:
			var k := Vector2i(floori(dec.global_position.x / 64.0), floori(dec.global_position.z / 64.0))
			chunks[k] = int(chunks.get(k, 0)) + 1
			assert_int(chunks[k]).is_less_equal(TownDecals.CHUNK_CAP)
		else:
			walls += 1
	# budget numbers for docs/qa/PERFORMANCE.md
	var goods_inst := 0
	var goods_tris := 0
	var mmis := 0
	for mmi in root.find_children("*", "MultiMeshInstance3D", true, false):
		mmis += 1
		var mesh2 := (mmi as MultiMeshInstance3D).multimesh.mesh
		if mesh2 != null and mesh2.get_surface_count() == 1 and mesh2.surface_get_material(0) == MarketGoods.material():
			goods_inst += (mmi as MultiMeshInstance3D).multimesh.instance_count
			goods_tris += (mmi as MultiMeshInstance3D).multimesh.instance_count * (mesh2.surface_get_array_index_len(0) / 3)
	print("PERF Kingsreach: %d MultiMeshInstance3D, goods: %d MMIs' instances %d, %d tris total; decals %d (ground chunks %s)" % [mmis, goods, goods_inst, goods_tris, root.find_children("*", "Decal", true, false).size(), chunks])
	if Quality.tier != Quality.LOW:
		assert_int(root.find_children("*", "Decal", true, false).size()).is_greater(0)
	else:
		assert_int(root.find_children("*", "Decal", true, false).size()).is_equal(0)
	builder.queue_free()
