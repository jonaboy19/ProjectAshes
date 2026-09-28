extends GdUnitTestSuite
## War between Caldrenn and a neighbour: tension building to a deterministic
## declaration, the front, daily battles, exhaustion into a treaty, the
## at_war toggle, player hooks and save round trips.

const WarSim := preload("res://scripts/sim/war_sim.gd")

const HOT_CTX := {"feud_count": 2, "rift_instability": 0.9, "season": "spring"}
const COLD_CTX := {"feud_count": 0, "rift_instability": 0.0, "season": "spring"}


func _tick_until(ws: RefCounted, days: int, ctx: Dictionary, want_war: bool) -> int:
	for d in days:
		ws.tick_day(d, ctx)
		if ws.is_at_war() == want_war:
			return d
	return -1


func test_tension_declares_war_deterministically_for_a_seed() -> void:
	WorldGen.setup(2024)
	var a := WarSim.new(777)
	var b := WarSim.new(777)
	var day_a := _tick_until(a, 80, HOT_CTX, true)
	var day_b := _tick_until(b, 80, HOT_CTX, true)
	assert_int(day_a).is_greater(0)
	assert_int(day_a).is_equal(day_b)
	assert_str(a.enemy_id()).is_equal(b.enemy_id())
	assert_str(JSON.stringify(a.serialize())).is_equal(JSON.stringify(b.serialize()))


func test_peacetime_tension_decays_and_never_declares_war() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(11)
	for d in 200:
		ws.tick_day(d, COLD_CTX)
	assert_bool(ws.is_at_war()).is_false()
	for id in WarSim.WAR_CANDIDATES:
		assert_float(ws.tension_of(id)).is_less(WarSim.TENSION_WAR_THRESHOLD)


func test_front_has_two_or_three_border_regions() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	_tick_until(ws, 80, HOT_CTX, true)
	var front: Array = ws.front()
	assert_int(front.size()).is_between(2, 3)
	var names := {}
	for f: Dictionary in front:
		assert_bool(f.has("pos")).is_true()
		names[f["name"]] = true
	assert_int(names.size()).is_equal(front.size())    # distinct regions


func test_daily_battles_cause_casualties() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	_tick_until(ws, 80, HOT_CTX, true)
	var before := ws.casualties()
	ws.tick_day(1000, HOT_CTX)
	var after := ws.casualties()
	assert_int(int(after["caldrenn"])).is_greater(int(before["caldrenn"]))
	assert_int(int(after["enemy"])).is_greater(int(before["enemy"]))


func test_exhaustion_ends_the_war_with_a_treaty() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	var declared := _tick_until(ws, 80, HOT_CTX, true)
	assert_int(declared).is_greater(0)
	var ended := _tick_until(ws, 200, HOT_CTX, false)
	assert_int(ended).is_greater(declared)
	assert_bool(ws.is_at_war()).is_false()
	assert_int(ws.chronicle.size()).is_greater(0)


func test_at_war_toggles_across_a_full_war() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	assert_bool(ws.is_at_war()).is_false()
	_tick_until(ws, 80, HOT_CTX, true)
	assert_bool(ws.is_at_war()).is_true()
	_tick_until(ws, 200, HOT_CTX, false)
	assert_bool(ws.is_at_war()).is_false()


func test_battle_at_front_and_contract_hooks_only_during_war() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	assert_dict(ws.battle_at_front()).is_empty()
	assert_dict(ws.contract_for_merchant(1)).is_empty()
	assert_float(ws.crop_requisition_fraction()).is_equal(0.0)
	_tick_until(ws, 80, HOT_CTX, true)
	var battle := ws.battle_at_front()
	assert_bool(battle.has("pos")).is_true()
	assert_int(int(battle["size"])).is_greater(0)
	assert_bool(ws.contract_for_merchant(5).has("good")).is_true()
	assert_float(ws.crop_requisition_fraction()).is_greater(0.0)


func test_news_and_rumours_report_the_war() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	_tick_until(ws, 80, HOT_CTX, true)
	assert_int(ws.news().size()).is_greater(0)
	var rum := ws.rumours()
	assert_bool(rum.any(func(l: String) -> bool: return l.contains(WarSim.display_name(ws.enemy_id())))).is_true()


func test_serialise_roundtrip() -> void:
	WorldGen.setup(2024)
	var ws := WarSim.new(777)
	_tick_until(ws, 80, HOT_CTX, true)
	ws.tick_day(1000, HOT_CTX)
	var copy := WarSim.new(1)
	copy.deserialize(ws.serialize())
	assert_bool(copy.is_at_war()).is_equal(ws.is_at_war())
	assert_str(copy.enemy_id()).is_equal(ws.enemy_id())
	assert_str(JSON.stringify(copy.serialize())).is_equal(JSON.stringify(ws.serialize()))
