extends GdUnitTestSuite
## Combat event bus (combat_events.gd) for foley/VFX listeners, and the surface pick.

const CE := preload("res://scripts/combat/combat_events.gd")


func test_bus_delivers_events() -> void:
	var got := []
	var cb := func(e: Dictionary) -> void: got.append(e)
	CE.bus().hit.connect(cb)
	CE.emit("hit", {"weight": "heavy", "surface": "flesh"})
	CE.bus().hit.disconnect(cb)
	assert_int(got.size()).is_equal(1)
	assert_str(String(got[0]["surface"])).is_equal("flesh")


func test_weights_and_surfaces() -> void:
	assert_str(CE.weight_name(0)).is_equal("light")
	assert_str(CE.weight_name(2)).is_equal("finisher")
	assert_str(CE.body_surface(["Leather_Vest"])).is_equal("leather")
	assert_str(CE.body_surface(["Chainmail", "Leather_Belt"])).is_equal("metal")
	assert_str(CE.body_surface([])).is_equal("flesh")


func test_swing_kind_from_measured_clip_and_surface_of_actor() -> void:
	assert_str(CE.swing_kind("Mx_SnS_Slash_3")).is_equal("thrust")
	assert_str(CE.swing_kind("Mx_SnS_Slash_5")).is_equal("slash")
	assert_str(CE.swing_kind("no_such_clip")).is_equal("slash")
	assert_str(CE.surface_of(null)).is_equal("flesh")
	var n: Node = auto_free(Node.new())
	assert_str(CE.surface_of(n)).is_equal("flesh")


func test_player_hit_reports_victims_and_dodge_emits() -> void:
	var p: Node3D = auto_free(preload("res://scripts/actors/player.gd").new())
	add_child(p)
	p.stamina = 100.0
	var got := []
	var cb := func(e: Dictionary) -> void: got.append(e)
	CE.bus().dodge.connect(cb)
	p._start_dodge(false)
	CE.bus().dodge.disconnect(cb)
	assert_int(got.size()).is_equal(1)
	assert_str(String(got[0]["kind"])).is_equal("back")
	assert_array(p._last_hit_victims).is_empty()
