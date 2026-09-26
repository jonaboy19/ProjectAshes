extends GdUnitTestSuite
## Vertical-slice life systems: careers with real vacancies, needs, market, save/load.


func _guard_org() -> RACareers:
	var c := RACareers.new(1)
	c.add_org("guard", "the Guard", 0, "Captain", Vector3(0, 0, 50), Vector2(7, 19), 3, [
		{"title": "Captain", "wage": 30, "count": 1, "merit": 400},
		{"title": "Sergeant", "wage": 18, "count": 2, "merit": 120},
		{"title": "Guard", "wage": 9, "count": 3, "merit": 0},
	])
	return c


func test_can_only_join_an_open_seat() -> void:
	var c := _guard_org()
	var s := c.seat("guard", "Guard")
	s["holders"].append_array([10, 11, 12])
	assert_str(c.apply("guard", "Guard", 0, 1)).contains("No Guard seat")
	s["holders"].erase(12)
	assert_str(c.apply("guard", "Guard", 0, 1)).is_empty()
	assert_bool(c.is_employed()).is_true()
	assert_int(c.open_count(s)).is_equal(0)


func test_rank_needs_merit_not_level() -> void:
	var c := _guard_org()
	assert_str(c.check_application("guard", "Sergeant", 50)).contains("needs 120 merit")
	assert_str(c.check_application("guard", "Sergeant", 130)).is_empty()


func test_wages_need_attendance_and_strikes_dismiss() -> void:
	var c := _guard_org()
	c.apply("guard", "Guard", 0, 1)
	c.log_attendance(10.0)
	assert_int(c.pay_day()["paid"]).is_equal(9)
	for k in RACareers.STRIKES_TO_DISMISS:
		assert_int(c.pay_day()["paid"]).is_equal(0)
	assert_bool(c.is_employed()).is_false()
	assert_int(c.open_count(c.seat("guard", "Guard"))).is_equal(3)


func test_seniority_backfills_and_juniors_hire() -> void:
	var c := _guard_org()
	c.seat("guard", "Captain")["holders"].append(1)
	c.seat("guard", "Guard")["holders"].append_array([5, 6])
	c.tick_day(func(_o: Dictionary) -> int: return 99, 0.0, 1.0)
	# Both sergeant seats were empty: guards moved up, then one new guard was hired.
	assert_int(c.seat("guard", "Sergeant")["holders"].size()).is_equal(2)
	assert_array(c.seat("guard", "Guard")["holders"]).contains([99])


func test_careers_roundtrip() -> void:
	var c := _guard_org()
	c.seat("guard", "Guard")["holders"].append(7)
	c.apply("guard", "Guard", 0, 3)
	var data: Variant = JSON.parse_string(JSON.stringify(c.serialize()))
	var d := _guard_org()
	d.deserialize(data)
	assert_bool(d.is_employed()).is_true()
	assert_array(d.seat("guard", "Guard")["holders"]).contains_exactly([7, RACareers.PLAYER])


func test_needs_fall_and_recover() -> void:
	var n := RANeeds.new()
	n.food = 50.0
	n.rest = 50.0
	n.tick(10.0)
	assert_float(n.food).is_less(50.0)
	assert_float(n.rest).is_less(50.0)
	var tired := n.rest
	n.sleep(n.hours_to_rest(1.0), 1.0)
	assert_float(n.rest).is_equal(100.0)
	assert_float(tired).is_less(n.rest)
	n.food = 0.0
	assert_float(n.starvation()).is_greater(0.0)
	assert_float(n.stamina_regen()).is_less(1.0)


func test_market_prices_follow_stock() -> void:
	var m := RAMarket.new()
	m.add_good("bread", 2, 10)
	var normal := m.price("bread")
	m.stock["bread"] = 2
	assert_int(m.price("bread")).is_greater(normal)
	m.stock["bread"] = 30
	assert_int(m.price("bread")).is_less_equal(normal)
	m.purse = 0
	assert_int(m.sell("bread")).is_equal(-1)


func test_life_inventory_and_save_roundtrip() -> void:
	var life: Node = Engine.get_main_loop().root.get_node("Life")
	life.give("wolf_pelt", 3)
	var pelts: int = life.count("wolf_pelt")
	var gold_before: int = Game.gold
	var snap: Dictionary = JSON.parse_string(JSON.stringify(life.snapshot()))
	life.take("wolf_pelt", pelts)
	Game.gold = 0
	assert_int(life.count("wolf_pelt")).is_equal(0)
	life.restore(snap)
	assert_int(life.count("wolf_pelt")).is_equal(pelts)
	assert_int(Game.gold).is_equal(gold_before)
