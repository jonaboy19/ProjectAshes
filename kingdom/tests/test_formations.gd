extends GdUnitTestSuite
## Army formations and morale: slot generation per formation, nearest-slot
## assignment, formation effects, and the thresholds at which units break.

const Formation := preload("res://scripts/army/formation.gd")
const Morale := preload("res://scripts/army/morale.gd")

const COUNTS := [1, 3, 5, 12, 24, 37, 50, 100]


func _min_gap(sl: PackedVector2Array) -> float:
	var best := INF
	for i in sl.size():
		for j in range(i + 1, sl.size()):
			best = minf(best, sl[i].distance_to(sl[j]))
	return best


func _front(sl: PackedVector2Array) -> float:
	var f := -INF
	for p in sl:
		f = maxf(f, p.y)
	return f


func test_every_formation_makes_one_distinct_slot_per_man() -> void:
	for t: int in Formation.Type.values():
		assert_int(Formation.slots(t, 0).size()).is_equal(0)
		for n: int in COUNTS:
			var sl := Formation.slots(t, n)
			var label := "%s x%d" % [Formation.type_name(t), n]
			assert_int(sl.size()).override_failure_message(label).is_equal(n)
			if n > 1:
				assert_float(_min_gap(sl)).override_failure_message(label).is_greater(0.9)


func test_front_rank_fills_first() -> void:
	# Slot 0 is always in the front rank, so a depleted unit still has a front.
	for t: int in Formation.Type.values():
		for n: int in [5, 24, 100]:
			var sl := Formation.slots(t, n)
			assert_float(sl[0].y).override_failure_message("%s x%d" % [Formation.type_name(t), n]) \
				.is_equal_approx(_front(sl), 1.0)    # skirmish jitter


func test_line_is_centred_and_keeps_its_frontage() -> void:
	var sl := Formation.slots(Formation.Type.LINE, 24)
	var c := Vector2.ZERO
	for p in sl:
		c += p
	c /= sl.size()
	assert_float(absf(c.x)).is_less(0.5)
	assert_float(absf(c.y)).is_less(1.0)
	assert_float(Formation.width(sl)).is_greater(Formation.width(Formation.slots(Formation.Type.COLUMN, 24)))
	# A set frontage thins from the back as men fall, not from the wings.
	var full := Formation.slots(Formation.Type.LINE, 30, 10)
	var thinned := Formation.slots(Formation.Type.LINE, 21, 10)
	assert_float(Formation.width(thinned)).is_equal_approx(Formation.width(full), 0.01)
	assert_float(_front(thinned) - _front(full)).is_less(0.01 + Formation.stats(Formation.Type.LINE)["dz"])


func test_column_is_narrow_and_deep() -> void:
	var sl := Formation.slots(Formation.Type.COLUMN, 40)
	var xs := {}
	for p in sl:
		xs[snappedf(p.x, 0.01)] = true
	assert_int(xs.size()).is_less_equal(4)
	assert_float(_front(sl)).is_greater(Formation.width(sl))


func test_wedge_has_a_single_man_at_the_tip() -> void:
	for n: int in [6, 24, 60]:
		var sl := Formation.slots(Formation.Type.WEDGE, n)
		var f := _front(sl)
		var at_tip := 0
		for p in sl:
			if p.y > f - 0.01:
				at_tip += 1
		assert_int(at_tip).is_equal(1)
		assert_float(sl[0].x).is_equal_approx(0.0, 0.01)
		# Each rank back is wider than the one in front.
		var back_width := 0.0
		for p in sl:
			if p.y < f - 1.0:
				back_width = maxf(back_width, absf(p.x))
		assert_float(back_width).is_greater(0.5)


func test_square_is_hollow_and_faces_out_on_every_side() -> void:
	for n: int in [16, 40, 100]:
		var sl := Formation.slots(Formation.Type.SQUARE, n)
		var dx: float = Formation.stats(Formation.Type.SQUARE)["dx"]
		var sides := {"front": 0, "rear": 0, "left": 0, "right": 0}
		var inside := 0
		for p in sl:
			if p.length() < dx * 0.9:
				inside += 1
			var f := Formation.slot_facing(Formation.Type.SQUARE, p)
			if f.y > 0.5:
				sides["front"] += 1
			elif f.y < -0.5:
				sides["rear"] += 1
			elif f.x < -0.5:
				sides["left"] += 1
			elif f.x > 0.5:
				sides["right"] += 1
		if n >= 40:    # small squares close up into a solid knot
			assert_int(inside).override_failure_message("square x%d has men in the middle" % n).is_equal(0)
		for side: String in sides:
			assert_int(sides[side]).override_failure_message("square x%d %s" % [n, side]).is_greater(0)
	# Everyone else faces front.
	assert_vector(Formation.slot_facing(Formation.Type.LINE, Vector2(5, -3))).is_equal(Vector2(0, 1))


func test_skirmish_is_loose_and_shield_wall_is_tight() -> void:
	var loose := Formation.slots(Formation.Type.SKIRMISH, 30)
	var tight := Formation.slots(Formation.Type.SHIELD_WALL, 30)
	var line := Formation.slots(Formation.Type.LINE, 30)
	assert_float(_min_gap(loose)).is_greater(2.0)
	assert_float(_min_gap(tight)).is_less(_min_gap(line))
	assert_float(Formation.width(loose)).is_greater(Formation.width(line))
	# Repeatable: the same unit forms the same screen every time.
	assert_array(Array(Formation.slots(Formation.Type.SKIRMISH, 30))).is_equal(Array(loose))


func test_assignment_is_one_to_one_and_picks_the_nearest_slot() -> void:
	var slots := Formation.slots(Formation.Type.LINE, 24)
	var men := PackedVector2Array()
	for i in slots.size():
		men.append(slots[slots.size() - 1 - i] + Vector2(0.3, -0.2))    # reversed order, each beside a slot
	var a := Formation.assign(men, slots)
	var used := {}
	for i in a.size():
		used[a[i]] = true
		assert_int(a[i]).is_equal(slots.size() - 1 - i)
	assert_int(used.size()).is_equal(24)
	# Two men who would cross get swapped by the refine pass.
	var two := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	var crossed := PackedVector2Array([Vector2(9, 1), Vector2(1, 1)])
	var b := Formation.assign(crossed, two, 2)
	assert_int(b[0]).is_equal(1)
	assert_int(b[1]).is_equal(0)


func test_pivot_turns_at_a_bounded_rate_and_about_faces() -> void:
	var wide := Formation.slots(Formation.Type.LINE, 100)
	var narrow := Formation.slots(Formation.Type.COLUMN, 12)
	assert_float(Formation.turn_rate(wide)).is_less(Formation.turn_rate(narrow))
	var f := Formation.rotate_toward(Vector3.FORWARD, Vector3.RIGHT, 0.2)
	assert_float(Formation.angle_between(Vector3.FORWARD, f)).is_equal_approx(0.2, 0.001)
	assert_float(Formation.angle_between(Vector3.FORWARD, Vector3.BACK)).is_greater(Formation.ABOUT_FACE)
	# Slots follow the facing: a front slot facing east lies east of the centre.
	var p := Formation.to_world(Vector2(0, 3), Vector3.ZERO, Vector3.RIGHT)
	assert_float(p.x).is_equal_approx(3.0, 0.001)


func test_formation_effects() -> void:
	var s := func(t: int, k: String) -> float: return float(Formation.stats(t)[k])
	var T := Formation.Type
	assert_float(s.call(T.SHIELD_WALL, "defence")).is_greater(s.call(T.LINE, "defence"))
	assert_float(s.call(T.LINE, "defence")).is_greater(s.call(T.SKIRMISH, "defence"))
	assert_float(s.call(T.COLUMN, "speed")).is_greater(s.call(T.LINE, "speed"))
	assert_float(s.call(T.LINE, "speed")).is_greater(s.call(T.SQUARE, "speed"))
	assert_float(s.call(T.SQUARE, "flank")).is_less(s.call(T.LINE, "flank"))
	assert_float(s.call(T.SQUARE, "anti_cav")).is_greater(s.call(T.LINE, "anti_cav"))
	assert_float(s.call(T.COLUMN, "flank")).is_greater(s.call(T.LINE, "flank"))
	assert_float(s.call(T.SKIRMISH, "missile")).is_less(s.call(T.LINE, "missile"))
	assert_float(s.call(T.WEDGE, "charge")).is_greater(s.call(T.LINE, "charge"))
	# Blows from the side and rear hurt more, except against the square.
	var line_front := Formation.incoming_multiplier(T.LINE, Vector3.FORWARD, Vector3.FORWARD)
	var line_flank := Formation.incoming_multiplier(T.LINE, Vector3.FORWARD, Vector3.RIGHT)
	var line_rear := Formation.incoming_multiplier(T.LINE, Vector3.FORWARD, Vector3.BACK)
	assert_float(line_front).is_equal(1.0)
	assert_float(line_flank).is_greater(line_front)
	assert_float(line_rear).is_greater(line_flank)
	assert_float(Formation.incoming_multiplier(T.SQUARE, Vector3.FORWARD, Vector3.BACK)).is_less(line_flank)


func test_names_round_trip() -> void:
	for t: int in Formation.Type.values():
		assert_int(Formation.from_name(Formation.type_name(t))).is_equal(t)
	assert_int(Formation.from_name("shield_wall")).is_equal(Formation.Type.SHIELD_WALL)
	assert_int(Formation.from_name("phalanx")).is_equal(-1)


# --- Morale ---------------------------------------------------------------------

func test_fresh_unit_is_steady() -> void:
	assert_float(Morale.target({})).is_greater_equal(Morale.WAVER_AT)
	assert_bool(Morale.breaks({})).is_false()
	assert_int(Morale.state_for(70.0)).is_equal(Morale.State.STEADY)
	assert_int(Morale.state_for(Morale.WAVER_AT - 1.0)).is_equal(Morale.State.WAVERING)
	assert_int(Morale.state_for(Morale.BREAK_AT)).is_equal(Morale.State.ROUTED)


func test_losses_break_a_unit_and_officers_steady_it() -> void:
	assert_bool(Morale.breaks({"casualties": 0.3})).is_false()
	assert_bool(Morale.breaks({"casualties": 0.6})).is_true()
	# A captain in earshot holds the same men at 60% losses...
	var officer := RAMilitary.steadiness("captain")
	assert_bool(Morale.breaks({"casualties": 0.6, "officer": officer})).is_false()
	# ...but nobody holds a unit that has lost four in five.
	assert_bool(Morale.breaks({"casualties": Morale.SHATTER_LOSSES, "officer": 99.0})).is_true()
	# Losing men fast is worse than losing them slowly.
	assert_float(Morale.target({"casualties": 0.3, "shock": 0.3})).is_less(Morale.target({"casualties": 0.3}))


func test_flanked_line_breaks_where_a_square_holds() -> void:
	var line: Dictionary = Formation.stats(Formation.Type.LINE)
	var square: Dictionary = Formation.stats(Formation.Type.SQUARE)
	var hit := {"casualties": 0.3, "flank": 0.5, "rear": 0.5}
	var in_line := hit.merged({"exposure_flank": line["flank"], "exposure_rear": line["rear"]})
	var in_square := hit.merged({"exposure_flank": square["flank"], "exposure_rear": square["rear"]})
	assert_bool(Morale.breaks(in_line)).is_true()
	assert_bool(Morale.breaks(in_square)).is_false()
	# The same losses from the front alone don't break the line.
	assert_bool(Morale.breaks({"casualties": 0.3})).is_false()


func test_outnumbered_units_break() -> void:
	assert_bool(Morale.breaks({"outnumber": 3.0})).is_false()
	assert_bool(Morale.breaks({"casualties": 0.3, "outnumber": 4.0})).is_true()
	# The penalty is capped: a hundred to one is no worse than four to one.
	assert_float(Morale.target({"outnumber": 100.0})).is_equal(Morale.target({"outnumber": 4.0}))
	# Horse against a square: no penalty; against a line of swordsmen: some.
	assert_float(Morale.target({"cavalry": 1.0, "anti_cav": 1.2})).is_equal(Morale.target({}))
	assert_float(Morale.target({"cavalry": 1.0, "anti_cav": 0.2})).is_less(Morale.target({}))


func test_routed_men_run_then_rally_when_no_longer_pursued() -> void:
	var m := Morale.new(70.0)
	var t := 0.0
	var hurt := {"casualties": 0.55}
	while not m.is_broken() and t < 30.0:
		m.update(0.5, hurt, true)
		t += 0.5
	assert_bool(m.is_broken()).is_true()
	assert_float(t).is_less(10.0)
	# While chased they don't recover.
	for i in 40:
		m.update(0.5, hurt, true)
	assert_bool(m.is_broken()).is_true()
	# Left alone they rally, but not before MIN_ROUT_TIME has passed.
	var calm := 0.0
	while m.is_broken() and calm < 60.0:
		m.update(0.5, hurt, false)
		calm += 0.5
	assert_bool(m.is_broken()).is_false()
	assert_int(m.rallies).is_equal(1)
	assert_float(calm).is_greater_equal(1.0)
	# A rallied unit is jumpier.
	assert_float(Morale.target({"rallies": 1})).is_less(Morale.target({}))


func test_shattered_units_only_rally_to_an_officer() -> void:
	var m := Morale.new(70.0)
	var gone := {"casualties": 0.85}
	m.update(0.5, gone, true)
	assert_int(m.state).is_equal(Morale.State.SHATTERED)
	for i in 120:
		m.update(0.5, gone, false)
	assert_bool(m.is_broken()).is_true()
	assert_int(m.rallies).is_equal(0)
	# An officer standing among them gets them to rally.
	var with_officer := gone.merged({"officer": RAMilitary.steadiness("captain")})
	for i in 120:
		m.update(0.5, with_officer, false, true)
		if not m.is_broken():
			break
	assert_bool(m.is_broken()).is_false()
	assert_int(m.rallies).is_equal(1)


func test_unit_types_and_officers_from_the_ladder() -> void:
	assert_array(RAMilitary.available_unit_types(false)).not_contains(["cavalry"])
	assert_array(RAMilitary.available_unit_types(true)).contains(["sabre", "spear", "crossbow", "cavalry"])
	for id: String in RAMilitary.UNIT_TYPES:
		for n: String in RAMilitary.unit_type(id)["formations"]:
			assert_int(Formation.from_name(n)).override_failure_message("%s drills %s" % [id, n]).is_greater_equal(0)
	assert_float(RAMilitary.unit_type("spear")["anti_cavalry"]).is_greater(RAMilitary.unit_type("sabre")["anti_cavalry"])
	assert_float(RAMilitary.steadiness("soldier")).is_equal(0.0)
	assert_float(RAMilitary.steadiness("captain")).is_greater(RAMilitary.steadiness("tenwarden"))
	assert_float(RAMilitary.steadiness("field_general")).is_greater(RAMilitary.steadiness("captain"))
	assert_float(RAMilitary.officer_radius("field_general")).is_greater(RAMilitary.officer_radius("tenwarden"))
