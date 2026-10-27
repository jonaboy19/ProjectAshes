extends GdUnitTestSuite
## WP-16: healer, scholar, priest and assassin careers - each with a join path and an independent path.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Mastery := preload("res://scripts/sim/mastery.gd")
const TradeRanks := preload("res://scripts/sim/trade_ranks.gd")
const Posts := preload("res://scripts/sim/career_posts.gd")


func _careers() -> RACareers:
	var c := RACareers.new(7)
	Posts.register_healer_org(c, 0, Vector3(5, 5, 10))
	Posts.register_guild_org(c, 0, Vector3(9, 9, 10))
	return c


func _injured() -> RAInjuries:
	var inj := RAInjuries.new()
	inj.add("broken_arm", 1)
	return inj


# ---- healer
func test_healer_join_gives_staff_discount() -> void:
	var c := _careers()
	var inj := _injured()
	var base: int = Posts.healer_menu(inj, c)[0]["cost"]
	assert_str(c.apply(Posts.HEALER_ORG, "Herbalist's Apprentice", 0, 1)).is_empty()
	assert_bool(Posts.holds_healer_seat(c)).is_true()
	var staff: int = Posts.healer_menu(inj, c)[0]["cost"]
	assert_int(staff).is_less(base)
	assert_str(c.apply(Posts.HEALER_ORG, "Village Herbalist", 0, 2)).contains("merit")


func test_healer_independent_path_by_mastery() -> void:
	var m := Mastery.new()
	assert_str(Posts.healer_rank(m)).is_equal("herbalist")
	assert_bool(Posts.can_practise(_careers(), m)).is_false()
	m.gain("herbalism", 5000.0, 1)
	m.gain("healing", 5000.0, 1)
	assert_str(Posts.healer_rank(m)).is_equal("healer")
	assert_bool(Posts.can_practise(_careers(), m)).is_true()


func test_healer_seats_limited() -> void:
	var c := _careers()
	assert_str(c.apply(Posts.HEALER_ORG, "Herbalist's Apprentice", 0, 1)).is_empty()
	c.resign()
	assert_int(c.open_count(c.seat(Posts.HEALER_ORG, "Herbalist's Apprentice"))).is_equal(2)


# ---- scholar
func test_scholar_self_taught_path() -> void:
	var m := Mastery.new()
	assert_bool(Posts.is_scholar(null, m)["scholar"]).is_false()
	m.gain("scholarship", 5000.0, 1)
	var r: Dictionary = Posts.is_scholar(null, m)
	assert_bool(r["scholar"]).is_true()
	assert_str(r["path"]).is_equal("self_taught")


func test_scholar_join_via_education() -> void:
	WorldGen.setup(2024)
	var e: RefCounted = Hub.new().mod("education")
	e.set_player({"home_sid": 5, "sid": 5, "age": 9, "gold": 200})
	var r: Dictionary = Posts.scholar_join(e, "no_such_school", "exam")
	assert_bool(r["ok"]).is_false()
	assert_bool(Posts.is_scholar(e, Mastery.new())["scholar"]).is_false()


# ---- priest
func _faith() -> RefCounted:
	return Hub.new().mod("faith")


func test_priest_join_and_orders() -> void:
	var fa := _faith()
	fa.set_belief("ch:1", "runes", 80.0)
	assert_bool(Posts.check_order(fa, "ch:1", "wed")["ok"]).is_false()   # not ordained
	assert_bool(Posts.priest_join(fa, "ch:1", "parish")["ok"]).is_true()
	assert_bool(Posts.check_order(fa, "ch:1", "wed")["ok"]).is_true()
	var f: Dictionary = Posts.check_order(fa, "ch:1", "desecrate")
	assert_bool(f["ok"]).is_false()
	assert_bool(f["forbidden"]).is_true()


func test_hedge_priest_independent_path() -> void:
	var fa := _faith()
	fa.set_belief("ch:2", "dawn", 50.0)
	assert_bool(Posts.check_order(fa, "ch:2", "bless")["ok"]).is_true()
	assert_bool(Posts.check_order(fa, "ch:2", "wed")["ok"]).is_false()
	fa.set_belief("ch:3", "folk", 50.0)
	assert_bool(Posts.check_order(fa, "ch:3", "bless")["ok"]).is_false()


func test_breaking_forbidden_order_costs_belief() -> void:
	var fa := _faith()
	fa.set_belief("ch:4", "runes", 80.0)
	var lost: int = Posts.break_order(fa, "ch:4", "take_bribe", 5)
	assert_int(lost).is_equal(Posts.FORBIDDEN_BELIEF_LOSS)
	assert_int(Posts.break_order(fa, "ch:4", "bless", 5)).is_equal(0)


# ---- assassin
func _ranks(level: int) -> RefCounted:
	var t := TradeRanks.new()
	t.ranks["thief"] = level
	return t


func test_no_contracts_for_novice_thief() -> void:
	assert_int(Posts.contracts(_ranks(0), _careers(), 3).size()).is_equal(0)


func test_freelance_path_pays_less_than_guild() -> void:
	var c := _careers()
	var free: Array = Posts.contracts(_ranks(1), c, 10)
	assert_int(free.size()).is_greater(0)
	assert_str(free[0]["path"]).is_equal("freelance")
	# Master Thief without a Knife seat is still freelance; with it, the guild board opens.
	assert_str(Posts.contracts(_ranks(2), c, 10)[0]["path"]).is_equal("freelance")
	assert_str(c.apply(Posts.GUILD_ORG, "Knife", 0, 10)).is_empty()
	var guild: Array = Posts.contracts(_ranks(2), c, 10)
	assert_str(guild[0]["path"]).is_equal("guild")
	assert_int(guild.size()).is_greater(free.size())


func test_contracts_deterministic_and_takeable() -> void:
	var c := _careers()
	var a: Array = Posts.contracts(_ranks(1), c, 4)
	assert_str(JSON.stringify(a)).is_equal(JSON.stringify(Posts.contracts(_ranks(1), c, 4)))
	assert_str(Posts.can_take_contract(_ranks(1), c, a[0]["id"], 4)).is_empty()
	assert_str(Posts.can_take_contract(_ranks(1), c, "nope", 4)).is_not_empty()
