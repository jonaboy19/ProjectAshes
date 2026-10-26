extends GdUnitTestSuite
## Masters tab model: local masters who teach a craft, current apprenticeship progress, apply -> lessons -> learned.

const AV := preload("res://scripts/realm/apprentice_view.gd")
const Society := preload("res://scripts/realm/society.gd")


func _soc() -> RefCounted:
	WorldGen.setup(WorldSim.SEED)
	var s: RefCounted = Society.new()
	s.call("_ensure_npcs")
	return s


func test_craft_map() -> void:
	assert_str(AV.craft_for("smith")).is_equal("smithing")
	assert_str(AV.craft_for("lord")).is_equal("")


func test_masters_are_local_teachers_best_first() -> void:
	var s := _soc()
	var best_sid := 0
	var best := []
	for sett: Dictionary in WorldGen.settlements:
		(s.get("player") as Dictionary)["sid"] = int(sett["id"])
		var m := AV.masters(s)
		if m.size() > best.size():
			best = m
			best_sid = int(sett["id"])
	assert_int(best.size()).is_greater(0)
	for m: Dictionary in best:
		assert_int(int(m["tier"])).is_greater_equal(3)
		assert_str(String(m["craft"])).is_not_empty()
		assert_int(int((s.get("npcs")[String(m["id"])] as Dictionary)["sid"])).is_equal(best_sid)
	for i in best.size() - 1:
		assert_int(int(best[i]["tier"])).is_greater_equal(int(best[i + 1]["tier"]))


func test_current_progress() -> void:
	var s := _soc()
	assert_dict(AV.current(s)).is_empty()
	var id: String = (s.get("npcs") as Dictionary).keys()[0]
	s.set("apprenticeship", {"master": id, "craft": "smithing", "days": 10, "need": 40, "skill": 0.0, "missed": 2})
	var c := AV.current(s)
	assert_float(float(c["progress"])).is_equal_approx(0.25, 0.001)
	assert_int(int(c["missed"])).is_equal(2)
