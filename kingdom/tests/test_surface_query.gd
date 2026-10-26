extends GdUnitTestSuite

const SQ := preload("res://scripts/world/surface_query.gd")
## SurfaceQuery: normal classification, material resolution (tags, groups, name hints), flags, footstep families.


func test_kind_by_normal() -> void:
	assert_str(String(SQ.kind_for_normal(Vector3.UP))).is_equal("ground")
	assert_str(String(SQ.kind_for_normal(Vector3(0, 0.8, 0.6).normalized()))).is_equal("ground")
	assert_str(String(SQ.kind_for_normal(Vector3(1, 0.1, 0).normalized()))).is_equal("wall")
	assert_str(String(SQ.kind_for_normal(Vector3.DOWN))).is_equal("ceiling")


func test_slope_degrees() -> void:
	assert_float(SQ.slope_deg(Vector3.UP)).is_equal_approx(0.0, 0.01)
	assert_float(SQ.slope_deg(Vector3(0, 1, 1).normalized())).is_equal_approx(45.0, 0.01)


func test_name_hints() -> void:
	assert_str(String(SQ.material_hint("res://kit/Bridge_Planks.glb"))).is_equal("wood")
	assert_str(String(SQ.material_hint("Crate_01"))).is_equal("wood")
	assert_str(String(SQ.material_hint("anvil"))).is_equal("metal")
	assert_str(String(SQ.material_hint("whatever", &"dirt"))).is_equal("dirt")


func test_tag_meta_wins_and_is_inherited() -> void:
	var root := Node3D.new()
	var body := StaticBody3D.new()
	body.name = "StoneWall"
	root.add_child(body)
	auto_free(root)
	SQ.tag(root, &"wood", {climbable = true, vaultable = true})
	assert_str(String(SQ.material_of(body))).is_equal("wood")
	var d := SQ.describe({"position": Vector3(0, 1000, 0), "normal": Vector3.RIGHT, "collider": body})
	assert_str(String(d["kind"])).is_equal("wall")
	assert_bool(d["climbable"]).is_true()
	assert_bool(d["vaultable"]).is_true()
	assert_str(d["footstep"]).is_equal("wood")


func test_group_tag() -> void:
	var body := StaticBody3D.new()
	body.add_to_group(&"surface_snow")
	auto_free(body)
	assert_str(String(SQ.material_of(body))).is_equal("snow")


func test_untagged_wall_climbable_by_material() -> void:
	var body := StaticBody3D.new()
	body.name = "Rock_big"
	auto_free(body)
	var wall := SQ.describe({"position": Vector3(0, 1000, 0), "normal": Vector3.LEFT, "collider": body})
	assert_bool(wall["climbable"]).is_true()
	var floor_d := SQ.describe({"position": Vector3(0, 1000, 0), "normal": Vector3.UP, "collider": body})
	assert_bool(floor_d["walkable"]).is_true()
	assert_bool(floor_d["climbable"]).is_false()


func test_no_hit_is_safe_default() -> void:
	var d := SQ.describe({})
	assert_bool(d["hit"]).is_false()
	assert_str(String(d["kind"])).is_equal("ground")


func test_every_material_has_a_footstep_family() -> void:
	for m: StringName in SQ.MATERIALS:
		assert_bool(SQ.FOOTSTEP.has(m)).is_true()


func test_ground_probe_hits_a_tagged_floor() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 0.2, 4)
	cs.shape = box
	body.add_child(cs)
	SQ.tag(body, &"wood")
	add_child(body)
	auto_free(body)
	body.global_position = Vector3(0, 1000, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var g := SQ.ground(body.get_world_3d().direct_space_state, Vector3(0, 1000.2, 0))
	assert_bool(g["hit"]).is_true()
	assert_str(String(g["material"])).is_equal("wood")
	assert_str(String(g["kind"])).is_equal("ground")


func test_footprint_material_table() -> void:
	var FX := preload("res://scripts/world/surface_feedback.gd")
	assert_bool(FX.PRINT.has(&"snow")).is_true()
	assert_bool(FX.PRINT.has(&"mud")).is_true()
	assert_bool(FX.PRINT.has(&"grass")).is_false()
	assert_int(FX.PRINT_POOL).is_less_equal(64)


func test_wet_surfaces_slide_earlier() -> void:
	assert_float(SQ.slide_min_deg(&"stone", 0.0)).is_equal(40.0)
	assert_float(SQ.slide_min_deg(&"stone", 1.0)).is_equal(26.0)
	assert_float(SQ.slide_min_deg(&"mud", 0.0)).is_less(40.0)
	assert_float(SQ.slide_min_deg(&"dirt", 1.0)).is_equal(40.0)


func test_campfire_weather_response() -> void:
	var CF := preload("res://scripts/world/campfire.gd")
	assert_float(CF.flame_strength(1.0, 1.0)).is_less(CF.flame_strength(0.0, 1.0))
	assert_float(CF.flame_strength(0.0, 2.5)).is_greater(1.0)
	assert_float(CF.wind_push(2.4).length()).is_greater(CF.wind_push(1.0).length())


func test_well_action() -> void:
	var W := preload("res://scripts/interaction/kinds/well.gd")
	assert_str(W.action_for(40.0, 0)).is_equal("drink")
	assert_str(W.action_for(95.0, 0)).is_equal("fill")
	assert_str(W.action_for(95.0, 3)).is_equal("drink")


func test_rain_masks_sounds() -> void:
	var P := preload("res://scripts/population/perception.gd")
	P.rain_mask_override = 0.6
	assert_float(P.rain_mask()).is_equal(0.6)
	P.rain_mask_override = -1.0


func test_weapon_impact_table() -> void:
	var SI := preload("res://scripts/combat/surface_impact.gd")
	assert_str(String(SI.impact_for(&"wood")[0])).is_equal("hit_wood")
	assert_str(String(SI.impact_for(&"metal")[0])).is_equal("hit_metal")
	assert_str(String(SI.impact_for(&"unknown")[0])).is_equal("block")
