extends GdUnitTestSuite
## Ashsight (L11): the event ring buffer and flagged sites, 1 Hz sampling within 60 m, the
## cooling timer, replay accuracy (within 1 m of the true paths), pooled ghosts and the
## per-frame cost budget.

const State := preload("res://scripts/region1/region1_state.gd")
const GhostScene := preload("res://scenes/region1/ash_ghost.tscn")


func before_test() -> void:
	State.clear()


func after_test() -> void:
	State.clear()


func _mem() -> AshMemory:
	return AshMemory.new().setup(1) as AshMemory


# --- ring buffer / sites ------------------------------------------------------------------

func test_incidents_need_a_flagged_site_unless_forced() -> void:
	var m := _mem()
	assert_int(m.begin_incident(&"raid", Vector2(500, 500), 0.0)).is_equal(-1)
	assert_int(m.events.size()).is_equal(1)   # still logged in the light event ring
	m.flag_site("Farm", Vector2(500, 500))
	var id := m.begin_incident(&"raid", Vector2(520, 500), 0.0)   # within 80 m of the site
	assert_int(id).is_greater(0)
	assert_str(String(m.incident(id)["site"])).is_equal("Farm")
	assert_int(m.begin_incident(&"raid", Vector2(9000, 9000), 0.0, {}, true)).is_greater(0)   # forced
	# a second raid start at the same place joins the open incident
	assert_int(m.begin_incident(&"raid", Vector2(505, 500), 5.0)).is_equal(id)
	assert_int(m.incidents.size()).is_equal(2)


func test_incident_ring_buffer_evicts_the_coldest() -> void:
	var m := _mem()
	m.flag_site("Stone", Vector2.ZERO, 5000.0)
	var first := -1
	for i in AshMemory.MAX_INCIDENTS + 6:
		var id := m.begin_incident(&"death", Vector2(i * 100.0, 0), float(i))
		m.end_incident(id, float(i) + 1.0)
		if i == 0:
			first = id
		m.tick(0.05)   # older incidents are colder
	assert_int(m.incidents.size()).is_equal(AshMemory.MAX_INCIDENTS)
	assert_bool(m.incident(first).is_empty()).is_true()   # the oldest (coldest) went first
	var ev_fill := AshMemory.MAX_EVENTS + 20
	for i in ev_fill:
		m.begin_incident(&"fire", Vector2(-9999, -9999), 0.0)
	assert_int(m.events.size()).is_equal(AshMemory.MAX_EVENTS)


func test_sampling_is_1hz_within_60m_and_capped() -> void:
	var m := _mem()
	m.flag_site("Stone", Vector2.ZERO)
	var id := m.begin_incident(&"raid", Vector2.ZERO, 10.0)
	var near := {"id": "a", "role": "bandit", "pos": Vector2(30, 0)}
	var far := {"id": "b", "role": "bandit", "pos": Vector2(70, 0)}
	assert_bool(m.sample(10.0, [near, far])).is_true()
	assert_bool(m.sample(10.4, [near, far])).is_false()   # too soon: ignored
	assert_bool(m.sample(11.0, [near, far])).is_true()
	assert_bool(m.sample(11.5, [near, far])).is_false()
	var actors: Dictionary = m.incident(id)["actors"]
	assert_bool(actors.has("a")).is_true()
	assert_bool(actors.has("b")).is_false()   # 70 m away: not sampled
	assert_int((actors["a"]["t"] as Array).size()).is_equal(2)
	assert_float(float((actors["a"]["t"] as Array)[1])).is_equal_approx(1.0, 0.0001)
	# no more than MAX_ACTORS tracked, no more than MAX_SAMPLES samples each
	var crowd: Array = []
	for i in 30:
		crowd.append({"id": "c%d" % i, "role": "villager", "pos": Vector2(i, 0)})
	m.sample(20.0, crowd)
	assert_int((m.incident(id)["actors"] as Dictionary).size()).is_equal(AshMemory.MAX_ACTORS)
	for i in AshMemory.MAX_SAMPLES + 20:
		m.sample(30.0 + i, [near])
	assert_int((m.incident(id)["actors"]["a"]["t"] as Array).size()).is_less_equal(AshMemory.MAX_SAMPLES)


func test_open_incident_stops_recording_after_the_window() -> void:
	var m := _mem()
	m.flag_site("Stone", Vector2.ZERO)
	var id := m.begin_incident(&"sabotage", Vector2.ZERO, 0.0)
	m.sample(1.0, [{"id": "x", "role": "bandit", "pos": Vector2(3, 3)}])
	m.sample(AshMemory.RECORD_WINDOW_S + 5.0, [{"id": "x", "role": "bandit", "pos": Vector2(3, 3)}])
	assert_bool(bool(m.incident(id)["open"])).is_false()
	assert_int((m.incident(id)["actors"]["x"]["t"] as Array).size()).is_equal(1)


func test_one_shot_events_for_fire_and_death() -> void:
	var m := _mem()
	m.flag_site("Farm", Vector2.ZERO)
	var id := m.record_event(&"death", Vector2(4, 4), 50.0, [{"id": "v", "role": "villager", "pos": Vector2(4, 4)}])
	assert_int(id).is_greater(0)
	assert_bool(bool(m.incident(id)["open"])).is_false()
	assert_int(m.positions_at(id, 0.0).size()).is_equal(1)
	assert_int(m.record_event(&"fire", Vector2(900, 900), 51.0)).is_equal(-1)   # nowhere near a flagged site


# --- cooling --------------------------------------------------------------------------------

func test_cooling_timer_fades_and_removes_evidence() -> void:
	var m := _mem()
	m.flag_site("Stone", Vector2.ZERO)
	var raid := m.record_event(&"raid", Vector2.ZERO, 0.0, [{"id": "a", "role": "bandit", "pos": Vector2(1, 1)}])
	var fire := m.record_event(&"fire", Vector2(10, 0), 0.0, [{"id": "f", "role": "villager", "pos": Vector2(10, 0)}])
	assert_float(m.heat(raid)).is_equal_approx(1.0, 0.0001)
	assert_bool(m.readable(raid)).is_true()
	m.tick(1.0)
	assert_float(m.heat(raid)).is_equal_approx(1.0 - 1.0 / 3.0, 0.001)
	assert_float(m.heat(fire)).is_equal_approx(0.5, 0.001)          # fires cool faster (2 days)
	assert_float(m.heat_at(Vector2(5, 0))).is_greater(0.6)
	assert_int(m.incidents_near(Vector2.ZERO, 20.0).size()).is_equal(2)
	assert_int(m.incidents_near(Vector2.ZERO, 20.0)[0]).is_equal(raid)   # hottest first
	var cooled := []
	m.incident_cooled.connect(func(id: int) -> void: cooled.append(id))
	m.tick(1.0)
	assert_array(cooled).is_equal([fire])
	assert_bool(m.readable(fire)).is_false()
	assert_bool(m.readable(raid)).is_true()
	assert_object(m.replay(fire)).is_null()   # cold ashes cannot be replayed
	m.tick(1.5)
	assert_bool(m.readable(raid)).is_false()
	assert_int(m.incidents.size()).is_equal(0)
	assert_float(m.heat_at(Vector2.ZERO)).is_equal(0.0)


func test_open_incident_is_not_dropped_while_recording() -> void:
	var m := _mem()
	m.flag_site("Stone", Vector2.ZERO)
	var id := m.begin_incident(&"fire", Vector2.ZERO, 0.0)
	m.tick(0.5)
	assert_bool(m.readable(id)).is_true()


# --- replay accuracy ----------------------------------------------------------------------

func test_fake_raid_replays_within_one_metre() -> void:
	var m := _mem()
	var id := AshFakeRaid.record_into(m, 4321.5)   # an arbitrary clock offset
	assert_int(id).is_greater(0)
	var info := m.replay_info(id)
	assert_int((info["actors"] as Array).size()).is_equal(6)   # 4 bandits + 2 villagers
	assert_float(float(info["duration"])).is_equal_approx(AshFakeRaid.DURATION, 0.01)
	assert_int((info["marks"] as Array).size()).is_equal(AshFakeRaid.MARKS.size())
	var r := AshFakeRaid.max_replay_error(m, id, 0.05)
	assert_int(int(r["samples"])).is_greater(600)
	assert_float(float(r["max_error"])).is_less(1.0)
	print("ashsight replay: max error %.3f m (%s), %d comparisons" % [r["max_error"], r["worst_actor"], r["samples"]])


func test_replay_survives_a_json_save_round_trip() -> void:
	var m := _mem()
	State.register_sim(m)
	var id := AshFakeRaid.record_into(m)
	m.tick(0.5)
	var digest := m.digest()
	var text := JSON.stringify(State.snapshot())
	State.clear()
	var fresh := AshMemory.new().setup(9) as AshMemory
	State.register_sim(fresh)
	State.restore(JSON.parse_string(text))
	assert_str(fresh.digest()).is_equal(digest)
	assert_float(fresh.heat(id)).is_equal_approx(m.heat(id), 0.0001)
	assert_float(float(AshFakeRaid.max_replay_error(fresh, id, 0.1)["max_error"])).is_less(1.0)
	assert_int(fresh.sites.size()).is_equal(1)


func test_replay_cursor_plays_seeks_and_finishes() -> void:
	var m := _mem()
	var id := AshFakeRaid.record_into(m)
	var rp := m.replay(id, 2.0)
	assert_object(rp).is_not_null()
	assert_int(rp.frame().size()).is_greater(3)   # everyone is in range at the start
	rp.advance(1.0)
	assert_float(rp.t).is_equal_approx(2.0, 0.0001)   # speed 2
	rp.seek(11.0)
	assert_float(rp.progress()).is_between(0.3, 0.6)
	rp.advance(100.0)
	assert_bool(rp.finished()).is_true()
	assert_int(rp.frame().size()).is_equal(0)   # everyone has faded out by the end
	rp.looping = true
	rp.playing = true
	rp.advance(0.5)
	assert_bool(rp.finished()).is_false()


func test_actors_out_of_range_are_hidden_and_fade_in_and_out() -> void:
	var m := _mem()
	m.flag_site("Stone", Vector2.ZERO)
	var id := m.begin_incident(&"raid", Vector2.ZERO, 0.0)
	for s in 6:
		m.sample(float(s), [{"id": "w", "role": "villager", "pos": Vector2(float(s) * 4.0, 0.0)}])
	m.end_incident(id, 6.0)
	var mid := m.positions_at(id, 2.5)
	assert_int(mid.size()).is_equal(1)
	assert_float(float(mid[0]["alpha"])).is_equal(1.0)
	assert_float((mid[0]["pos"] as Vector2).x).is_equal_approx(10.0, 0.05)
	assert_float(float(m.positions_at(id, -0.35)[0]["alpha"])).is_between(0.3, 0.7)   # fading in
	assert_int(m.positions_at(id, -1.0).size()).is_equal(0)
	assert_int(m.positions_at(id, 20.0).size()).is_equal(0)
	# a hole in the record (actor left sight for 10 s): hidden inside the gap
	var m2 := _mem()
	m2.flag_site("Stone", Vector2.ZERO)
	var id2 := m2.begin_incident(&"raid", Vector2.ZERO, 0.0)
	m2.sample(0.0, [{"id": "w", "role": "villager", "pos": Vector2(0, 0)}])
	m2.sample(10.0, [{"id": "w", "role": "villager", "pos": Vector2(20, 0)}])
	assert_int(m2.positions_at(id2, 5.0).size()).is_equal(0)
	assert_int(m2.positions_at(id2, 0.2).size()).is_equal(1)


func test_trail_returns_the_raw_path() -> void:
	var m := _mem()
	var id := AshFakeRaid.record_into(m)
	var tr := m.trail(id, "b1")
	assert_int(tr.size()).is_greater(15)
	assert_float(tr[0].distance_to(AshFakeRaid.position_of("b1", 0.0))).is_less(0.05)


# --- ghost scene, pool and budget -------------------------------------------------------------

func test_ghost_scene_pool_reuses_instances() -> void:
	var pool := AshGhostPool.new()
	pool.capacity = 4
	add_child(pool)
	await get_tree().process_frame
	assert_int(pool.free_count()).is_equal(4)
	var g1: AshGhost = pool.acquire("bandit")
	var g2: AshGhost = pool.acquire("villager")
	assert_object(g1).is_not_null()
	assert_int(pool.free_count()).is_equal(2)
	pool.release(g1)
	assert_int(pool.free_count()).is_equal(3)
	assert_object(pool.acquire("bandit")).is_same(g1)   # recycled, not re-instantiated
	pool.acquire("bandit")
	pool.acquire("bandit")
	assert_object(pool.acquire("bandit")).is_null()     # exhausted: never allocates more
	assert_bool(g2.visible).is_true()
	pool.queue_free()


func test_replay_view_frame_cost_is_within_budget() -> void:
	var m := _mem()
	var id := AshFakeRaid.record_into(m)
	var view := AshReplayView.new()
	add_child(view)
	await get_tree().process_frame
	assert_bool(view.show_incident(m, id)).is_true()
	view.set_process(false)   # drive by hand so the numbers are the view's own cost
	var us := 0
	var frames := 0
	for i in 26 * 30:
		var t0 := Time.get_ticks_usec()
		view.step(1.0 / 30.0)
		us += Time.get_ticks_usec() - t0
		frames += 1
	var avg_ms := float(us) / 1000.0 / float(frames)
	print("ashsight view: %.4f ms/frame avg over %d frames (%d ghosts max), worst %.4f ms" % [avg_ms, frames, view.max_active, view.worst_frame_ms])
	assert_float(avg_ms).is_less(0.3)
	assert_int(view.max_active).is_between(4, 6)
	view.queue_free()
