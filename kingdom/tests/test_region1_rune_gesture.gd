extends GdUnitTestSuite
## Rune gesture recognizer (scripts/region1/rune_gesture.gd + data/region1/glyphs.json):
## accuracy on noisy synthetic finger strokes (jitter, drift, scale, rotation, order, direction),
## invariances, rejection of scribbles, speed, learning and saving.

const Gesture := preload("res://scripts/region1/rune_gesture.gd")
const State := preload("res://scripts/region1/region1_state.gd")

const PER_GLYPH := 40


func before_test() -> void:
	State.clear()


func after_test() -> void:
	State.clear()


func _noisy(g, id: String, seed_value: int, count: int, o := {}) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array = []
	for i in count:
		out.append(g.synthesize(id, rng, o))
	return out


func _accuracy(g, o: Dictionary, seed_base: int) -> Dictionary:
	var hits := {}
	var conf := {}
	var wrong: Array = []
	for gi in g.glyph_ids.size():
		var id = g.glyph_ids[gi]
		var ok := 0
		for strokes: Array in _noisy(g, id, seed_base + gi, PER_GLYPH, o):
			var r = g.recognize(strokes)
			if r["accepted"] and r["id"] == id:
				ok += 1
			else:
				wrong.append("%s -> %s (%s sim %.3f)" % [id, r["id"], r["reason"], r["sim"]])
		hits[id] = ok
		conf[id] = float(ok) / PER_GLYPH
	return {"hits": hits, "rate": conf, "wrong": wrong}


func test_data_loads_four_glyphs() -> void:
	var g := Gesture.new()
	assert_array(Array(g.glyph_ids)).contains_exactly(["ward", "lure", "alarm", "bless"])
	assert_int(g.template_count()).is_between(20, 60)
	for id in g.glyph_ids:
		var info = g.glyph_info(id)
		assert_str(String(info["meaning"])).is_not_empty()
		assert_int(g.glyph_strokes(id).size()).is_between(1, 2)     # drawable on a phone


func test_recognition_at_least_95_percent_on_40_noisy_strokes_per_glyph() -> void:
	var g := Gesture.new()
	var r := _accuracy(g, {}, 1000)
	for id in g.glyph_ids:
		assert_int(r["hits"][id]).is_greater_equal(38)      # 38/40 = 95%
	if not (r["wrong"] as Array).is_empty():
		print("RUNE misses: ", r["wrong"])


func test_still_good_when_twice_as_sloppy() -> void:
	var g := Gesture.new()
	var r := _accuracy(g, {"jitter": 0.06, "wobble": 0.07, "overshoot": 0.1, "offset": 0.08, "aniso": 0.2}, 2000)
	var total := 0
	for id in g.glyph_ids:
		total += int(r["hits"][id])
	print("RUNE sloppy x2: ", r["hits"], " total ", total, "/", PER_GLYPH * g.glyph_ids.size())
	assert_int(total).is_greater_equal(int(0.85 * PER_GLYPH * g.glyph_ids.size()))


func test_canonical_shapes_are_perfect_and_clearly_distinct() -> void:
	var g := Gesture.new()
	for id in g.glyph_ids:
		var strokes: Array = []
		for s in g.glyph_strokes(id):
			strokes.append(_scaled(s, 200.0))
		var r = g.recognize(strokes)
		assert_str(r["id"]).is_equal(id)
		assert_float(r["sim"]).is_greater(0.985)
		var second := 0.0
		for other in r["scores"]:
			if other != id:
				second = maxf(second, float(r["scores"][other]))
		assert_float(second).is_less(0.85)      # no two glyphs look alike to the matcher


func test_rotation_and_scale_invariance() -> void:
	var g := Gesture.new()
	for id in g.glyph_ids:
		var base = g.synthesize(id, _rng(5), {"rotation": 0.0, "scale": 200.0, "keep_order": true,
			"keep_direction": true, "jitter": 0.0, "wobble": 0.0, "overshoot": 0.0, "offset": 0.0, "aniso": 0.0,
			"origin": Vector2(300, 300)})
		var r0 = g.recognize(base)
		for ang in [0.7, 1.9, -2.6, 3.1]:
			for sc in [0.15, 4.0]:
				var moved: Array = []
				for s: PackedVector2Array in base:
					var m := PackedVector2Array()
					for p in s:
						m.append((p - Vector2(300, 300)).rotated(ang) * sc + Vector2(500, 120))
					moved.append(m)
				var r = g.recognize(moved)
				assert_str(r["id"]).is_equal(id)
				assert_float(r["sim"]).is_equal_approx(r0["sim"], 0.01)


func _scaled(s: PackedVector2Array, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in s:
		out.append(p * k)
	return out


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func test_any_stroke_order_and_direction_and_start() -> void:
	var g := Gesture.new()
	# bless: 2 orders x 4 direction combinations, all clean
	var bless = g.glyph_strokes("bless")
	for order in [[0, 1], [1, 0]]:
		for d0 in 2:
			for d1 in 2:
				var strokes: Array = []
				var dirs := [d0, d1]
				for j in 2:
					var s: PackedVector2Array = _scaled(bless[order[j]], 150.0)
					if dirs[j] == 1:
						s = Gesture._reversed(s)
					strokes.append(s)
				assert_str(g.recognize(strokes)["id"]).is_equal("bless")
	# ward drawn from each corner and edge midpoint, both ways round
	var ring = g.glyph_strokes("ward")[0]
	var dense := Gesture.resample(_scaled(ring, 180.0), 81)
	dense.resize(80)
	for start in 8:
		for dir in [1, -1]:
			var s := PackedVector2Array()
			for i in 81:
				s.append(dense[(start * 10 + i * dir + 160) % 80])
			var r = g.recognize([s])
			assert_str(r["id"]).is_equal("ward")
			assert_bool(r["accepted"]).is_true()


func test_scribbles_and_junk_are_rejected() -> void:
	var g := Gesture.new()
	var rng := _rng(77)
	assert_str(g.recognize([])["reason"]).is_equal("no_strokes")
	assert_str(g.recognize([PackedVector2Array([Vector2(5, 5), Vector2(8, 6), Vector2(6, 9)])])["reason"]).is_equal("too_small")
	# a tap-tap-tap-tap of 4 strokes
	var four: Array = []
	for i in 4:
		four.append(PackedVector2Array([Vector2(i * 80, 0), Vector2(i * 80 + 50, 60)]))
	assert_str(g.recognize(four)["reason"]).is_equal("too_many_strokes")
	# random walks and one straight line must (almost) never turn into a rune
	var accepted := 0
	for i in 40:
		var pts := PackedVector2Array()
		var p := Vector2(400, 400)
		var dir := rng.randf() * TAU
		for k in 60:
			dir += rng.randfn(0.0, 0.9)
			p += Vector2.from_angle(dir) * 12.0
			pts.append(p)
		if g.recognize([pts])["accepted"]:
			accepted += 1
	print("RUNE random walks accepted: ", accepted, "/40")
	assert_int(accepted).is_less_equal(6)
	assert_bool(g.recognize([PackedVector2Array([Vector2(0, 0), Vector2(300, 20), Vector2(600, 0)])])["accepted"]).is_false()


func test_each_match_is_under_one_millisecond() -> void:
	var g := Gesture.new()
	var all: Array = []
	for gi in g.glyph_ids.size():
		all.append_array(_noisy(g, g.glyph_ids[gi], 3000 + gi, 100))
	var times: Array = []
	for strokes: Array in all:
		times.append(int(g.recognize(strokes)["us"]))
	times.sort()
	var mean := 0.0
	for t: int in times:
		mean += t
	mean /= times.size()
	var p95: int = times[int(times.size() * 0.95)]
	print("RUNE match us: mean %.0f  p50 %d  p95 %d  p99 %d  max %d" % [mean, times[times.size() / 2], p95,
		times[int(times.size() * 0.99)], times[times.size() - 1]])
	assert_float(mean).is_less(1000.0)
	assert_int(p95).is_less(1000)


func test_assist_relaxes_the_threshold() -> void:
	var g := Gesture.new()
	var found := false
	var rng := _rng(11)
	for i in 400:
		var strokes = g.synthesize("ward", rng, {"jitter": 0.11, "wobble": 0.12, "aniso": 0.3})
		var r0 = g.recognize(strokes, 0.0)
		if r0["reason"] == "low" and r0["id"] == "ward":
			var r1 = g.recognize(strokes, 1.0)
			assert_bool(r1["accepted"]).is_equal(float(r1["sim"]) >= 0.86 - float(g.opts["assist_relax"]) and float(r1["margin"]) >= float(g.opts["min_margin"]))
			if r1["accepted"]:
				found = true
				break
	assert_bool(found).is_true()


func test_learning_a_personal_style_and_saving_it() -> void:
	var g := Gesture.new()
	var before = g.template_count()
	# a lopsided "kite" ward that the stock templates read poorly
	var kite := PackedVector2Array([Vector2(100, 0), Vector2(190, 70), Vector2(100, 260), Vector2(10, 70), Vector2(100, 0)])
	var r0 = g.recognize([kite])
	assert_bool(g.learn("ward", [kite])).is_true()
	assert_int(g.template_count()).is_equal(before + 1)
	assert_float(g.recognize([kite])["sim"]).is_greater_equal(float(r0["sim"]))
	assert_bool(g.learn("ward", [PackedVector2Array([Vector2(0, 0), Vector2(400, 0)])])).is_false()   # not a ward: refused
	g.register_state()
	var snap: Dictionary = JSON.parse_string(JSON.stringify(State.snapshot()))
	var g2 := Gesture.new()
	g2.register_state()          # a fresh recognizer takes over the registry slot
	State.restore(snap)
	assert_int(g2.user_sample_count()).is_equal(1)
	assert_int(g2.template_count()).is_equal(before + 1)
	assert_float(g2.recognize([kite])["sim"]).is_equal_approx(g.recognize([kite])["sim"], 1e-6)
	g2.forget_user_samples()
	assert_int(g2.template_count()).is_equal(before)


func test_deterministic() -> void:
	var g := Gesture.new()
	var a = g.recognize(_noisy(g, "alarm", 42, 1)[0])
	var b = g.recognize(_noisy(g, "alarm", 42, 1)[0])
	assert_float(a["sim"]).is_equal(b["sim"])
	assert_str(a["id"]).is_equal(b["id"])


func test_max_rotation_can_be_limited() -> void:
	var g := Gesture.new()
	g.opts["max_rotation_deg"] = 20.0
	g.rebuild()
	var alarm = g.synthesize("alarm", _rng(3), {"rotation": 0.0, "keep_direction": true, "keep_order": true,
		"jitter": 0.0, "wobble": 0.0, "overshoot": 0.0, "offset": 0.0, "aniso": 0.0, "scale": 200.0})
	var straight = g.recognize(alarm)
	var turned: Array = []
	for s: PackedVector2Array in alarm:
		var m := PackedVector2Array()
		for p in s:
			m.append(p.rotated(1.2))
		turned.append(m)
	assert_float(g.recognize(turned)["sim"]).is_less(float(straight["sim"]) - 0.05)


func test_accuracy_is_stable_across_seeds() -> void:
	var g = Gesture.new()
	var rates: Array = []
	for base in [11, 222, 3333, 44444, 555555, 6666666]:
		var r := _accuracy(g, {}, base)
		var total := 0
		for id in g.glyph_ids:
			total += int(r["hits"][id])
		rates.append(float(total) / (PER_GLYPH * g.glyph_ids.size()))
	print("RUNE rates across seeds: ", rates)
	for rate: float in rates:
		assert_float(rate).is_greater_equal(0.95)
