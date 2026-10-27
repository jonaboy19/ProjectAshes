extends GdUnitTestSuite
## Academies list for adults: every visible school appears nearest first with its open routes; the exam opens at 10 + 10 gold.

const AV := preload("res://scripts/realm/academy_view.gd")
const Hub := preload("res://scripts/realm/realm_hub.gd")


func test_schools_nearest_first_with_routes() -> void:
	WorldGen.setup(WorldSim.SEED)
	var hub: RefCounted = Hub.new()
	var ed: RefCounted = hub.mod("education")
	ed.call("set_player", {"age": 20, "gold": 100})
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	var rows := AV.schools(ed, home, 50)
	assert_int(rows.size()).is_greater(0)
	for i in rows.size() - 1:
		assert_float(float(rows[i]["dist"])).is_less_equal(float(rows[i + 1]["dist"]))
	assert_str(String(rows[0]["label"])).is_not_empty()
	var any_exam := false
	for r: Dictionary in rows:
		for rt: Dictionary in r["routes"]:
			any_exam = any_exam or String(rt["route"]) == "exam"
	assert_bool(any_exam).is_true()
