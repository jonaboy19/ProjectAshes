extends GdUnitTestSuite
## WP-06 stress scenario, sim half: caravan + building fire + faction raid + dungeon floor, 48 in-game hours of the realm hub and
## economy (tools_qa/stress/stress_all.gd). Runs the scene in a child Godot so the whole boot is checked for SCRIPT ERROR lines.

const BUDGET_MS := 4.0


func _run_child() -> Array:
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tools_qa/stress/stress_all_cli.tscn"], out, true)
	var text := "\n".join(PackedStringArray(out))
	return [code, text]


func test_48_hours_under_budget_and_clean() -> void:
	var r := _run_child()
	var text: String = r[1]
	assert_int(int(r[0])).is_equal(0)
	assert_bool(text.contains("SCRIPT ERROR")).is_false()
	var line := ""
	for l in text.split("\n"):
		if l.begins_with("STRESS_JSON "):
			line = l.substr(len("STRESS_JSON "))
	assert_str(line).is_not_empty()
	var rep: Dictionary = JSON.parse_string(line)
	assert_bool(bool(rep["ok"])).is_true()
	assert_int(int(rep["hours"])).is_equal(48)
	assert_float(float(rep["avg_ms"])).is_less(BUDGET_MS)
	assert_int(int(rep["frames"])).is_greater(48)
	# the scenario really ran: caravan delivered, fire started, dungeon floor built, every module timed
	assert_str(String(rep["caravan_status"])).is_equal("arrived")
	assert_int(int((rep["events"] as Dictionary)["fire"])).is_greater(0)
	assert_int(int(rep["dungeon_rooms"])).is_greater(0)
	assert_int((rep["per_module"] as Array).size()).is_greater(40)
