extends GdUnitTestSuite
## Ready v1 C13: the danger tiers file matches the threat badge, every fight in it names a real archetype, the recommended
## level is the level the enemy is spawned at or below, and wounded beasts flee slower than the player's run.
## The win-rate band itself is checked by tools_qa/v1/duel_sim.gd (minutes of simulation, not a unit test).

const TIERS_PATH := "res://data/region1/danger_tiers.json"
const Stats := preload("res://scripts/combat/combat_stats.gd")


func _cfg() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(TIERS_PATH))


func test_tiers_drive_the_threat_badge() -> void:
	var rows: Array = _cfg()["tiers"]
	assert_int(rows.size()).is_equal(5)
	var last := -1.0
	for r: Dictionary in rows:
		assert_float(float(r["from"])).is_greater(last)
		last = float(r["from"])
		assert_str(RAThreatMap.describe(float(r["from"]))).is_equal(String(r["label"]))
		assert_int(RAThreatMap.shield(float(r["from"]))).is_equal(int(r["shield"]))
	assert_str(RAThreatMap.describe(9.9)).is_equal("Safe")
	assert_str(RAThreatMap.describe(79.9)).is_equal("Perilous")
	assert_int(RAThreatMap.shield(100.0)).is_equal(4)


func test_recommended_levels_rise_with_the_tier() -> void:
	var rows: Array = _cfg()["tiers"]
	var by_id := {}
	var prev := 0
	for r: Dictionary in rows:
		assert_int(int(r["level"])).is_greater_equal(prev)
		prev = int(r["level"])
		by_id[r["id"]] = r
	var fights: Dictionary = _cfg()["fights"]
	for k: String in fights:
		var f: Dictionary = fights[k]
		assert_bool(Stats.has(String(f["arch"]))).is_true()
		assert_bool(by_id.has(f["tier"])).is_true()
		assert_int(int(f["recommended_level"])).is_greater_equal(int(by_id[f["tier"]]["level"]) - 1)
		assert_int(int(f["enemy_level"])).is_less_equal(int(f["recommended_level"]))


func test_target_band_is_70_to_85() -> void:
	var band: Array = _cfg()["target_win"]
	assert_float(float(band[0])).is_equal(0.70)
	assert_float(float(band[1])).is_equal(0.85)


func test_wounded_beasts_flee_slower_than_the_player_runs() -> void:
	var run := 6.5
	for line: String in FileAccess.get_file_as_string("res://scripts/actors/player.gd").split("\n"):
		if line.begins_with("const RUN :="):
			run = float(line.split(" ")[3])
	var rx := RegEx.create_from_string('(?s)"flee": ([0-9.]+), "limp": ([0-9.]+),[^}]*?"flee_below": ([0-9]+)')
	var n := 0
	for m in rx.search_all(FileAccess.get_file_as_string("res://scripts/actors/wolf.gd")):
		if int(m.get_string(3)) > 0:
			n += 1
			assert_float(float(m.get_string(1))).is_less(run)
			assert_float(float(m.get_string(2))).is_less(float(m.get_string(1)))
	assert_int(n).is_greater(0)
