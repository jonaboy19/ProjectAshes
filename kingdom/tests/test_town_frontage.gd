extends GdUnitTestSuite
## Towns medieval pass: street frontage infill keeps old saves valid. Every planned lot (index, asset, position, yaw, district)
## is identical with and without the infill, infill lots only come after them, never overlap a building, and Property skips them.

const SEED := 1066


func _plans(enabled: bool) -> Array:
	CityPlanner.frontage_enabled = enabled
	WorldGen.setup(SEED)
	var out := []
	for s in WorldGen.settlements:
		out.append((s["plan"] as Dictionary).duplicate(true))
	CityPlanner.frontage_enabled = true
	return out


func test_prefix_identical_and_appended() -> void:
	var base := _plans(false)
	var dense := _plans(true)
	var added := 0
	for i in base.size():
		var a: Array = base[i]["lots"]
		var b: Array = dense[i]["lots"]
		assert_int(b.size()).is_greater_equal(a.size())
		for j in a.size():
			assert_str(String(b[j]["asset"])).is_equal(String(a[j]["asset"]))
			var planned_pos: Vector2 = b[j].get("moved_from", b[j]["pos"])     # a lot moved for a lane link keeps its planned position
			assert_bool(planned_pos.is_equal_approx(a[j]["pos"])).is_true()
			assert_float(float(b[j]["yaw"])).is_equal_approx(float(a[j]["yaw"]), 0.0001)
			assert_str(String(b[j].get("district", ""))).is_equal(String(a[j].get("district", "")))
			assert_bool(bool(b[j].get("infill", false))).is_false()
		for j in range(a.size(), b.size()):
			assert_bool(bool(b[j].get("infill", false))).is_true()
		added += b.size() - a.size()
	assert_int(added).is_greater(50)     # the pass does something


func test_infill_never_overlaps() -> void:
	WorldGen.setup(SEED)
	for s in WorldGen.settlements:
		var lots: Array = s["plan"]["lots"]
		for j in lots.size():
			if not bool(lots[j].get("infill", false)):
				continue
			var pj := CityPlanner._lot_poly(lots[j]["pos"], lots[j]["yaw"], String(lots[j]["asset"]))
			for k in lots.size():
				if k == j or (lots[k]["pos"] as Vector2).distance_to(lots[j]["pos"]) > 20.0:
					continue
				var pk := CityPlanner._lot_poly(lots[k]["pos"], lots[k]["yaw"], String(lots[k]["asset"]))
				assert_float(CityPlanner._poly_gap(pj, pk)).is_greater(0.0)     # poor rows stand eave to eave (0.05 m)
