extends GdUnitTestSuite
## Career call-ups: employer, guild and neighbours come to you when trade trouble
## hits; quality of work, reputation and known fighting ability decide who is asked.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 100, "life": null}
const SMITH_JOB := {"job": "j1", "tpl": "smith", "sid": 3, "title": "Journeyman", "employer": "Harl the Smith", "wage": 10, "rank": 0, "ladder": ["Journeyman"],
	"hired": 0, "since_rank": 0, "shift": [7, 15], "performance": 85.0, "merit": 0.0, "missed": 0, "recent_missed_day": 0, "worked_today": false,
	"days_worked": 0, "owed": 0, "leave_until": -1}


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _cu(job: Dictionary = SMITH_JOB) -> RefCounted:
	WorldGen.setup(2024)
	var hub: RefCounted = Hub.new()
	var c: RefCounted = hub.mod("callups")
	c.set_player({"sid": 3, "age": 20})
	if not job.is_empty():
		hub.mod("city_life")._job = job.duplicate(true)
	return c


func _run(c: RefCounted, days: int, ctx := CTX, decline := true) -> Array:
	var seen: Array = []
	for d in range(1, days + 1):
		c.tick_day(d, ctx)
		for o: Dictionary in c.offers():
			seen.append(o)
			if decline:
				c.decline(String(o["id"]))
	return seen


func test_blacksmith_gets_trade_call_ups() -> void:
	var c := _cu()
	c.hub.mod("education").set_player({"combat": 60.0, "fame": 30.0})
	var seen := _run(c, 250)
	assert_int(seen.size()).is_greater(5)
	var templates := {}
	for o: Dictionary in seen:
		templates[String(o["template"])] = true
	assert_bool(templates.has("stolen_ore")).is_true()
	var ore: Dictionary = seen.filter(func(o: Dictionary) -> bool: return String(o["template"]) == "stolen_ore")[0]
	assert_str(String(ore["npc_name"])).is_equal("Harl the Smith")
	assert_str(String(ore["text"])).contains("ore shipment")
	assert_str(String(ore["role"])).is_equal("combat")
	assert_int(int(ore["reward"]["gold"])).is_greater(20)
	assert_int(int(ore["deadline"])).is_greater(int(ore["day"]))
	assert_str(String(ore["status"])).is_equal("open")
	assert_bool(bool(ore["delivered"])).is_false()
	for k: String in ["id", "npc", "text", "sid", "reward", "deadline"]:
		assert_bool(ore.has(k)).is_true()
	# Nothing from another trade's list: no caravan or dock requests for a smith.
	assert_bool(templates.has("missing_caravan")).is_false()
	assert_bool(templates.has("smugglers")).is_false()


func test_farmers_and_caravan_suppliers_get_their_own_trouble() -> void:
	var farm := SMITH_JOB.duplicate(true)
	farm["tpl"] = "harvest_hand"
	farm["employer"] = "Old Brann"
	var c := _cu(farm)
	c.hub.mod("education").set_player({"combat": 60.0, "fame": 30.0})
	var t := {}
	for o: Dictionary in _run(c, 250):
		t[String(o["template"])] = true
	assert_bool(t.has("wolves_at_farm")).is_true()
	var car := SMITH_JOB.duplicate(true)
	car["tpl"] = "clerk"
	var c2 := _cu(car)
	c2.hub.mod("education").set_player({"combat": 60.0, "fame": 30.0})
	var t2 := {}
	for o: Dictionary in _run(c2, 250):
		t2[String(o["template"])] = true
	assert_bool(t2.has("missing_caravan")).is_true()


func test_quality_of_work_and_reputation_decide_who_is_asked() -> void:
	var good := SMITH_JOB.duplicate(true)
	good["performance"] = 98.0
	var bad := SMITH_JOB.duplicate(true)
	bad["performance"] = 5.0
	var g := _cu(good)
	var b := _cu(bad)
	var ng := _run(g, 300).size()
	var nb := _run(b, 300).size()
	assert_int(ng).is_greater(nb)
	assert_float(g.trust()).is_greater(b.trust() + 0.3)
	# Local reputation counts too.
	var soc: RefCounted = g.hub.mod("society")
	var t0: float = g.trust()
	soc.add_rep("city:3", 50.0)
	assert_float(g.trust()).is_greater(t0)


func test_known_fighting_ability_decides_combat_or_support_role() -> void:
	var strong := _cu()
	strong.hub.mod("education").set_player({"combat": 70.0, "fame": 40.0})
	var weak := _cu()
	weak.hub.mod("education").set_player({"combat": 3.0, "fame": 0.0})
	var so := _run(strong, 300).filter(func(o: Dictionary) -> bool: return String(o["template"]) == "stolen_ore")
	var wo := _run(weak, 300).filter(func(o: Dictionary) -> bool: return String(o["template"]) == "stolen_ore")
	assert_int(so.size()).is_greater(0)
	assert_str(String(so[0]["role"])).is_equal("combat")
	if wo.size() > 0:
		assert_str(String(wo[0]["role"])).is_equal("support")
		assert_int(int(wo[0]["reward"]["gold"])).is_less(int(so[0]["reward"]["gold"]))
	# Ability others do not know about does not count: a fighter nobody has seen.
	var hidden := _cu()
	hidden.hub.mod("education").set_player({"combat": 90.0, "fame": 0.0})
	assert_float(hidden.known_ability(3)).is_less(50.0)


func test_wartime_levy_calls_everyone_adult() -> void:
	var c := _cu({})
	var war := CTX.duplicate()
	war["at_war"] = true
	var msgs: Array = c.tick_day(1, war)
	var levy: Array = c.offers().filter(func(o: Dictionary) -> bool: return String(o["template"]) == "militia_levy")
	assert_int(levy.size()).is_equal(1)
	assert_bool(msgs.any(func(m: String) -> bool: return m.contains("levy"))).is_true()
	assert_str(String(levy[0]["from"])).is_equal("authority")
	# Not offered twice, and not to a small child.
	c.tick_day(2, war)
	assert_int(c.offers().filter(func(o: Dictionary) -> bool: return String(o["template"]) == "militia_levy").size()).is_equal(1)
	var kid := _cu({})
	kid.set_player({"age": 9})
	kid.tick_day(1, war)
	assert_int(kid.offers().filter(func(o: Dictionary) -> bool: return String(o["template"]) == "militia_levy").size()).is_equal(0)
	# Refusing the levy costs standing.
	var soc: RefCounted = c.hub.mod("society")
	var grp := "city:%d" % int(levy[0]["sid"])
	var r0: float = soc.rep(grp)
	assert_bool(c.decline(String(levy[0]["id"]))).is_true()
	assert_float(soc.rep(grp)).is_less(r0)
	# Peace: no levy.
	var p := _cu({})
	for d in range(1, 40):
		p.tick_day(d, CTX)
	assert_int(p.offers().filter(func(o: Dictionary) -> bool: return String(o["template"]) == "militia_levy").size()).is_equal(0)


func test_accept_complete_fail_and_expire() -> void:
	var c := _cu()
	c.hub.mod("education").set_player({"combat": 60.0, "fame": 30.0})
	var first := {}
	for d in range(1, 100):
		c.tick_day(d, CTX)
		if not c.offers().is_empty():
			first = c.offers()[0]
			break
	assert_bool(first.is_empty()).is_false()
	var soc: RefCounted = c.hub.mod("society")
	var r0: float = soc.rep("city:3")
	var acc: Dictionary = c.accept(String(first["id"]))
	assert_bool(bool(acc["ok"])).is_true()
	assert_int(c.active().size()).is_equal(1)
	assert_int(c.offers().size()).is_equal(0)
	assert_bool(bool(c.accept(String(first["id"]))["ok"])).is_false()
	var done: Dictionary = c.complete(String(first["id"]), 1.0)
	assert_bool(bool(done["ok"])).is_true()
	assert_int(c.take_pending_gold()).is_equal(int(first["reward"]["gold"]))
	assert_float(soc.rep("city:3")).is_greater(r0)
	assert_bool(bool(c.complete(String(first["id"]))["ok"])).is_false()
	# Failing loses trust and hurts the trade.
	var second := {}
	for d in range(first["day"] + 4, 400):
		c.tick_day(d, CTX)
		if not c.offers().is_empty():
			second = c.offers()[0]
			break
	assert_bool(second.is_empty()).is_false()
	c.accept(String(second["id"]))
	var r1: float = soc.rep("city:3")
	var f: Dictionary = c.fail(String(second["id"]))
	assert_bool(bool(f["ok"])).is_true()
	assert_float(soc.rep("city:3")).is_less(r1)
	# An employer's request that fails also dents the job record.
	var ore: Dictionary = c._make_offer("stolen_ore", 50, 3, c.profile(), c._rng("t", 0, "x"))
	c.offers_list.append(ore)
	c.accept(String(ore["id"]))
	var perf0: float = c.hub.mod("city_life").job()["performance"]
	c.fail(String(ore["id"]))
	assert_float(float(c.hub.mod("city_life").job()["performance"])).is_less(perf0)
	# Unanswered offers lapse by their deadline.
	var third := {}
	for d in range(second["day"] + 4, 600):
		c.tick_day(d, CTX)
		if not c.offers().is_empty():
			third = c.offers()[0]
			break
	assert_bool(third.is_empty()).is_false()
	for d in range(int(third["deadline"]) + 1, int(third["deadline"]) + 3):
		c.tick_day(d, CTX)
	assert_bool(c.offers().filter(func(o: Dictionary) -> bool: return String(o["id"]) == String(third["id"])).is_empty()).is_true()


func test_delivered_flag_and_limits() -> void:
	var c := _cu()
	for d in range(1, 120):
		c.tick_day(d, CTX)
		assert_int(c.offers().size()).is_less_equal(3)
		if not c.offers().is_empty():
			break
	assert_bool(c.offers().is_empty()).is_false()
	var id: String = String(c.offers()[0]["id"])
	c.mark_delivered(id)
	assert_bool(bool(c.offer(id)["delivered"])).is_true()


func test_unemployed_still_get_neighbour_requests_less_often() -> void:
	var emp := _cu()
	var un := _cu({})
	var ne := _run(emp, 300).size()
	var nu := _run(un, 300).size()
	assert_int(nu).is_greater(0)
	assert_int(ne).is_greater(nu)
	for o: Dictionary in _run(_cu({}), 200):
		assert_str(String(o["from"])).is_not_equal("employer" if String(o["npc_name"]) == "Harl the Smith" else "")


func test_determinism_round_trip_catch_up_and_perf() -> void:
	var a := _cu()
	var b := _cu()
	for c in [a, b]:
		c.hub.mod("education").set_player({"combat": 50.0, "fame": 20.0})
		for d in range(1, 70):
			c.tick_day(d, CTX)
	assert_str(JSON.stringify(a.serialize())).is_equal(JSON.stringify(b.serialize()))
	var json := JSON.stringify(a.serialize())
	var c2: RefCounted = Hub.new().mod("callups")
	c2.deserialize(JSON.parse_string(json))
	assert_str(_norm(c2.serialize())).is_equal(_norm(JSON.parse_string(json)))
	assert_int(c2.offers().size()).is_equal(a.offers().size())
	var x := _cu()
	var y := _cu()
	assert_array(x.catch_up(60, CTX)).is_equal(y.catch_up(60, CTX))
	assert_str(JSON.stringify(x.serialize())).is_equal(JSON.stringify(y.serialize()))
	assert_bool(x.offers().size() + x.active().size() <= 3).is_true()
	var z := _cu()
	z.tick_day(1, CTX)
	var t0 := Time.get_ticks_usec()
	for h in 24:
		z.tick_hour(h, CTX)
	z.tick_day(2, CTX)
	assert_int(Time.get_ticks_usec() - t0).is_less(20000)
	var t1 := Time.get_ticks_usec()
	x.catch_up(3000, CTX)
	assert_int(Time.get_ticks_usec() - t1).is_less(20000)
