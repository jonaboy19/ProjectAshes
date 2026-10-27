extends GdUnitTestSuite
## WP-10: finished buildings wear (cond), become repair jobs, ruins stop sheltering, the settlement mends from its store,
## the player can repair by hand, old saves (no cond) read as sound, and the unified settlement row carries tier + condition.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const D := preload("res://scripts/realm/construction_data.gd")


func _mod() -> RefCounted:
	WorldGen.setup(2024)
	var m: RefCounted = Hub.new().mod("construction")
	m.bag = {}
	m.gold_ref = {"gold": 1000}
	return m


## One finished lean-to (kit-style entry, no crew needed) plus its holding id.
func _with_hut(m: RefCounted) -> int:
	m.sync_kit([{"pos": Vector2(100, 100), "key": "k1", "kind": "lean_to", "beds": 0, "store": 0}], [])
	return int(m.sites.keys()[0])


func _days(m: RefCounted, n: int) -> void:
	for _i in n:
		m.tick_day(0, {})


func test_finished_building_is_sound_then_wears() -> void:
	var m := _mod()
	var id := _with_hut(m)
	assert_float(m.condition_of(m.sites[id])).is_equal(1.0)
	_days(m, 10)
	assert_float(m.condition_of(m.sites[id])).is_less(1.0)
	assert_float(m.condition_of(m.sites[id])).is_greater(0.9)


func test_worn_building_is_a_repair_job_and_ruin_shelters_nobody() -> void:
	var m := _mod()
	var id := _with_hut(m)
	var hid := int(m.sites[id]["holding"])
	var beds0: int = m.beds_of(hid)
	assert_array(m.repair_jobs()).is_empty()
	m.sites[id]["cond"] = 0.5
	var jobs: Array = m.repair_jobs()
	assert_int(jobs.size()).is_equal(1)
	assert_int(int(jobs[0]["site"])).is_equal(id)
	assert_bool(bool(jobs[0]["ruined"])).is_false()
	assert_dict(jobs[0]["needs"]).is_not_empty()
	m.sites[id]["cond"] = 0.05
	assert_bool(bool(m.repair_jobs()[0]["ruined"])).is_true()
	assert_int(m.beds_of(hid)).is_less_equal(beds0)
	assert_dict(m.roles_of(hid)).is_empty()


func test_player_repair_needs_materials_then_restores() -> void:
	var m := _mod()
	var id := _with_hut(m)
	m.sites[id]["cond"] = 0.3
	var r: Dictionary = m.repair(id)
	assert_bool(bool(r["ok"])).is_false()
	var needs: Dictionary = m.repair_needs(id)
	for item: String in needs:
		m.bag[item] = int(needs[item])
	r = m.repair(id)
	assert_bool(bool(r["ok"])).is_true()
	assert_float(m.condition_of(m.sites[id])).is_equal(1.0)
	for item: String in needs:
		assert_int(int(m.bag[item])).is_equal(0)
	assert_bool(bool(m.repair(id)["ok"])).is_false()


func test_settlement_repairs_itself_from_its_store() -> void:
	var m := _mod()
	var id := _with_hut(m)
	var hid := int(m.sites[id]["holding"])
	m.sites[id]["cond"] = 0.55
	_days(m, 1)
	assert_float(m.condition_of(m.sites[id])).is_less(0.6)   # empty store: nobody mends it
	var needs: Dictionary = m.repair_needs(id)
	for item: String in needs:
		m.holdings[hid]["store"][item] = int(needs[item]) + 1
	_days(m, 1)
	assert_float(m.condition_of(m.sites[id])).is_equal(1.0)
	for item: String in needs:
		assert_int(m.store_count(hid, item)).is_equal(1)


func test_condition_survives_save_and_old_saves_read_sound() -> void:
	var m := _mod()
	var id := _with_hut(m)
	m.sites[id]["cond"] = 0.42
	var m2 := _mod()
	m2.deserialize(JSON.parse_string(JSON.stringify(m.serialize())))
	assert_float(m2.condition_of(m2.sites[id])).is_equal_approx(0.42, 0.001)
	var old: Dictionary = JSON.parse_string(JSON.stringify(m.serialize()))
	(old["sites"][str(id)] as Dictionary).erase("cond")
	var m3 := _mod()
	m3.deserialize(old)
	assert_float(m3.condition_of(m3.sites[id])).is_equal(1.0)
	assert_array(m3.repair_jobs()).is_empty()


func test_holding_info_reports_condition_and_repairs() -> void:
	var m := _mod()
	var id := _with_hut(m)
	var hid := int(m.sites[id]["holding"])
	m.sites[id]["cond"] = 0.4
	var info: Dictionary = m.holding_info(hid)
	assert_float(float(info["condition"])).is_equal_approx(0.4, 0.001)
	assert_int(int(info["repairs"])).is_equal(1)
