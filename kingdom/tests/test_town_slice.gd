extends GdUnitTestSuite
## Towns medieval pass: vertical-slice dressing (data/world/slice_dressing.json) and the drawn wagon.

const Slice := preload("res://scripts/world/town_kit/slice_dressing.gd")
const RoadTraffic := preload("res://scripts/world/road_traffic.gd")
const SQ := preload("res://scripts/world/surface_query.gd")


func before() -> void:
	WorldGen.setup(1066)


func test_road_camp_beside_the_kingsreach_road() -> void:
	var p := Slice.road_camp_pos()
	assert_bool(p != Vector2.INF).is_true()
	var a: Vector2 = Slice.settlement("Ashford")["pos"]
	var b: Vector2 = Slice.settlement("Kingsreach")["pos"]
	var q := Geometry2D.get_closest_point_to_segment(p, a, b)
	assert_float(p.distance_to(q)).is_between(40.0, 70.0)
	var found := false
	for site in RegionSites.plan(1066):
		if String(site.get("name", "")) == "Kingsreach Road Camp":
			found = true
	assert_bool(found).is_true()


func test_scenario_a_ladder_and_vaultable_fence() -> void:
	var root := Node3D.new()
	add_child(root)
	var out := Slice.build_scenario_a(root, Slice.settlement("Ashford"))
	assert_bool(out.has("ladder") and out.has("fence")).is_true()
	var lad: Ladder = out["ladder"]
	assert_float(lad.top.global_position.y - lad.bottom.global_position.y).is_greater(2.5)
	var vault := 0
	for b in (out["fence"] as Node).find_children("*", "StaticBody3D", true, false):
		if bool(b.get_meta(&"surface_vaultable", false)):
			vault += 1
	assert_int(vault).is_greater(0)
	root.queue_free()


func test_draught_wagon_has_wheels_and_horse() -> void:
	var rt: Node3D = auto_free(RoadTraffic.new())
	add_child(rt)
	var w: Node3D = rt._draught()
	rt.add_child(w)
	assert_int((w.get_meta("wheels") as Array).size()).is_equal(4)
	assert_bool(w.has_meta("horse")).is_true()


## Interior beds use the "bed" smart-object frame (data/living_world/smart_objects.json): root on the floor at the slot,
## bed centre 0.82 m behind it, head end toward (0.80, 0.60) in slot space. Kit beds have their headboard at local -Z.
func test_interior_bed_stand_matches_the_bed_clip_frame() -> void:
	var IA := preload("res://scripts/interiors/indoor_actor.gd")
	for yaw: float in [0.0, 90.0, 215.0]:
		var c := Vector3(1.5, 2.8 + 0.42, -2.0)
		var sx: Transform3D = IA.bed_stand({"p": c, "y": yaw})
		assert_float(sx.origin.y).is_equal_approx(2.8, 0.001)
		var back := sx.origin + sx.basis * Vector3(0, 0, -0.82)
		assert_float(Vector2(back.x, back.z).distance_to(Vector2(c.x, c.z))).is_less(0.01)
		var head_slot := sx.basis * Vector3(0.8, 0, 0.6)
		var head_bed := Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 0, -1)
		assert_float(head_slot.dot(head_bed)).is_greater(0.999)
