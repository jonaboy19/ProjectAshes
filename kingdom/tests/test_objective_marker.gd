extends GdUnitTestSuite
## World marker for player-pinned targets only, plus the engaged-only threat plates.

const ObjectiveMarker := preload("res://scripts/ui/objective_marker.gd")
const ThreatPlates := preload("res://scripts/ui/threat_plates.gd")
const HudScript := preload("res://scripts/ui/hud.gd")

const VIEW := Vector2(2340, 1080)
const SAFE := Rect2(0, 0, 2340, 1080)


class Foe extends Node3D:
	var state := 0
	var dead := false
	var level := 4
	var named := ""
	var species := "forest_goblin"
	var health := 15
	var max_health := 30


func test_on_screen_point_is_not_clamped() -> void:
	var r: Dictionary = ObjectiveMarker.place(Vector2(1000, 400), false, VIEW, SAFE)
	assert_bool(bool(r["clamped"])).is_false()
	assert_vector(r["pos"]).is_equal(Vector2(1000, 400))


func test_off_screen_clamps_to_the_edge_with_an_arrow() -> void:
	var r: Dictionary = ObjectiveMarker.place(Vector2(5000, 540), false, VIEW, SAFE)
	assert_bool(bool(r["clamped"])).is_true()
	assert_float((r["pos"] as Vector2).x).is_equal_approx(VIEW.x - ObjectiveMarker.EDGE_PAD, 0.5)
	assert_float(float(r["angle"])).is_equal_approx(0.0, 0.05)       # points right
	var up: Dictionary = ObjectiveMarker.place(Vector2(1170, -4000), false, VIEW, SAFE)
	assert_float((up["pos"] as Vector2).y).is_equal_approx(ObjectiveMarker.EDGE_PAD, 0.5)


func test_clamped_position_stays_inside_the_safe_rect() -> void:
	var safe := Rect2(96, 20, 2100, 1000)
	for p: Vector2 in [Vector2(-900, -900), Vector2(9000, 9000), Vector2(0, 2000), Vector2(1500, -3000)]:
		var r: Dictionary = ObjectiveMarker.place(p, false, VIEW, safe)
		assert_bool(safe.has_point(r["pos"])).is_true()


func test_behind_the_camera_flips_to_the_edge() -> void:
	# A point behind the lens projects mirrored (here left of centre): the arrow must point the other way, to the right.
	var r: Dictionary = ObjectiveMarker.place(Vector2(300, 540), true, VIEW, SAFE)
	assert_bool(bool(r["clamped"])).is_true()
	assert_float((r["pos"] as Vector2).x).is_greater(VIEW.x * 0.5)
	var dead_ahead_behind: Dictionary = ObjectiveMarker.place(VIEW * 0.5, true, VIEW, SAFE)
	assert_bool(bool(dead_ahead_behind["clamped"])).is_true()


func test_distance_and_verb_line() -> void:
	assert_str(ObjectiveMarker.distance_text(42.4)).is_equal("42 m")
	assert_str(ObjectiveMarker.distance_text(1400.0)).is_equal("1.4 km")
	assert_str(ObjectiveMarker.verb_line("Travel", 980.0)).is_equal("Travel · 980 m")
	assert_str(ObjectiveMarker.verb_line("", 12.0)).is_equal("12 m")


func test_pin_and_clear() -> void:
	var m: Control = ObjectiveMarker.new()
	add_child(auto_free(m))
	assert_bool(m.has_pin()).is_false()
	m.set_pin(Vector3(10, 2, 30), "Old tower", "Climb")
	assert_bool(m.has_pin()).is_true()
	assert_str(String(m.pin["verb"])).is_equal("Climb")
	m.set_pin(null)
	assert_bool(m.has_pin()).is_false()
	m.set_pin(Vector3.ONE)
	m.clear_pin()
	assert_bool(m.has_pin()).is_false()


func _hud() -> CanvasLayer:
	var p := Player.new()
	add_child(auto_free(p))
	var h: CanvasLayer = HudScript.new(p)
	add_child(auto_free(h))
	return h


func test_only_player_pins_reach_the_world_marker() -> void:
	var h := _hud()
	var m: Control = h.objective_marker
	assert_bool(m.has_pin()).is_false()
	# Story leads / tracked quests / guild targets feed the compass only.
	h.story_target = func() -> Variant: return Vector2(400, 400)
	h._refresh_markers()
	h._quest_target()
	assert_bool(m.has_pin()).is_false()
	# The map's marker and a quest's "Pin to World" are the only sources.
	h.set_quest_target(Vector2(120, 80))
	assert_bool(m.has_pin()).is_true()
	h.set_quest_target(null)
	assert_bool(m.has_pin()).is_false()
	h.pin_target(Vector3(5, 1, 5), "Camp", "Scout")
	assert_str(String(m.pin["name"])).is_equal("Camp")
	h.clear_pin()
	assert_bool(m.has_pin()).is_false()


# --- threat plates -------------------------------------------------------------------------

func test_plates_only_for_engaged_or_locked() -> void:
	assert_bool(ThreatPlates.is_engaged(0, 5.0, false, false)).is_false()     # wandering, even when close
	assert_bool(ThreatPlates.is_engaged(1, 12.0, false, false)).is_true()      # alerted
	assert_bool(ThreatPlates.is_engaged(2, 12.0, false, false)).is_true()      # attacking
	assert_bool(ThreatPlates.is_engaged(2, 80.0, false, false)).is_false()     # too far
	assert_bool(ThreatPlates.is_engaged(2, 5.0, false, true)).is_false()       # dead
	assert_bool(ThreatPlates.is_engaged(0, 10.0, true, false)).is_true()       # locked on counts


func test_plates_are_capped_with_locked_first_then_nearest() -> void:
	var rows: Array = []
	for i in 7:
		rows.append({"node": null, "dist": 5.0 + i, "engaged": true, "locked": i == 5})
	rows.append({"node": null, "dist": 1.0, "engaged": false, "locked": false})
	var out: Array = ThreatPlates.select(rows)
	assert_int(out.size()).is_equal(ThreatPlates.MAX_PLATES)
	assert_bool(bool(out[0]["locked"])).is_true()
	assert_float(float(out[1]["dist"])).is_equal(5.0)
	for r: Dictionary in out:
		assert_bool(bool(r["engaged"])).is_true()


func test_plate_info_reads_level_name_and_health() -> void:
	var f := Foe.new()
	auto_free(f)
	var info: Dictionary = ThreatPlates.plate_info(f)
	assert_str(String(info["name"])).is_equal("Forest Goblin")
	assert_int(int(info["level"])).is_equal(4)
	assert_float(float(info["frac"])).is_equal_approx(0.5, 0.001)
	f.named = "Grukk"
	assert_str(String(ThreatPlates.plate_info(f)["name"])).is_equal("Grukk")


func test_plate_scan_picks_engaged_foes_only() -> void:
	var p := Player.new()
	add_child(auto_free(p))
	var plates: Control = ThreatPlates.new()
	plates.player = p
	var calm := Foe.new()
	var angry := Foe.new()
	angry.state = 2
	add_child(auto_free(calm))
	add_child(auto_free(angry))
	plates.candidates_override = [calm, angry]
	add_child(auto_free(plates))
	plates._pick()
	assert_int(plates._picked.size()).is_equal(1)
	assert_object(plates._picked[0]["node"]).is_same(angry)


func test_hud_overlays_are_full_screen_sized() -> void:
	var h := _hud()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float((h.objective_marker as Control).size.x).is_greater(100.0)
	assert_float((h.threat_plates as Control).size.x).is_greater(100.0)
	assert_float((h.technique_wheel as Control).size.x).is_greater(100.0)
