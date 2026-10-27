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
