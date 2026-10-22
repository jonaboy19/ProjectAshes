extends GdUnitTestSuite
## The heavy day ticks (settlements, city_life, society, factions) are split into per-step chunks that
## the hub queues as separate pump() jobs; the result must equal the same ticks run in one call.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 0, "player_pos": Vector3.ZERO, "life": null}
const CHUNKED := ["settlements", "city_life", "society", "factions"]


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _mk() -> RefCounted:
	WorldGen.setup(2024)
	var hub: RefCounted = Hub.new()
	hub.warm_up()
	return hub


func test_modules_offer_chunks() -> void:
	var hub := _mk()
	for k: String in CHUNKED:
		var chunks: Array = hub.mod(k).tick_day_chunks(3, CTX)
		assert_bool(chunks.size() >= 3).override_failure_message("%s should offer several chunks" % k).is_true()
	# settlements: one chunk per settlement
	assert_int(hub.mod("settlements").tick_day_chunks(3, CTX).size()).is_equal(WorldGen.settlements.size())


func test_chunked_pump_equals_direct_ticks() -> void:
	var a := _mk()
	var b := _mk()
	for day in [7, 8, 9]:
		for k: String in CHUNKED:
			a.mod(k).tick_day(day, CTX)
		for k: String in CHUNKED:
			b._queue.append([k, "tick_day", day, CTX])
		var jobs := 0
		while not b._queue.is_empty():
			b.pump()
			jobs += 1
			assert_int(jobs).is_less(100000)
	for k: String in CHUNKED:
		assert_str(_norm(b.mod(k).serialize())).is_equal(_norm(a.mod(k).serialize()))


func test_pump_runs_chunks_as_separate_jobs() -> void:
	var hub := _mk()
	hub._queue.append(["city_life", "tick_day", 5, CTX])
	var out: Array = hub._run_job(hub._queue.pop_front())
	assert_array(out).is_empty()                       # expansion only, nothing ran yet
	assert_bool(hub._queue.size() >= 3).is_true()
	hub.drain()
	assert_bool(hub._queue.is_empty()).is_true()
