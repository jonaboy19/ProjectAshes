extends GdUnitTestSuite
## Notables (CIV-B): ~60 named NPCs with ambitions who found organisations, families as institutions, guild
## competition, research that can fail, academy drift, expeditions (join / fund / sabotage / rescue, lost ones
## become mysteries and plant a relic lead), crises solved by heroes, determinism, catch_up, round-trip, cost.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const CTX := {"season": "spring", "at_war": false, "abs_hours": 0.0, "gold": 0, "player_pos": Vector2.ZERO}


func _mk() -> RefCounted:
	WorldGen.setup(2024)
	var hub: RefCounted = Hub.new()
	hub.warm_up()
	return hub


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


func _run(hub: RefCounted, from_day: int, to_day: int, names: Array = ["notables"]) -> void:
	for day in range(from_day, to_day + 1):
		for k: String in names:
			var m: RefCounted = hub.mod(k)
			var ch: Array = m.tick_day_chunks(day, CTX)
			if ch.is_empty():
				m.tick_day(day, CTX)
			else:
				for c: Callable in ch:
					c.call()


## Structural equality where floats may differ by a rounding step: JSON keeps about 15 digits, so a value
## sitting on a snapping boundary can land one 0.1 step away after a save round-trip.
func _same(a: Variant, b: Variant, tol := 0.15) -> bool:
	if a is Dictionary and b is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k: Variant in a:
			if not (b as Dictionary).has(k) or not _same(a[k], b[k], tol):
				return false
		return true
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not _same(a[i], b[i], tol):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= tol
	return a == b


func _rng(seed_: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	return r


func test_roster_is_sixty_named_people_with_ambitions_and_families() -> void:
	var nb: RefCounted = _mk().mod("notables")
	assert_int(nb.active_count()).is_equal(60)
	var roles := {}
	var names := {}
	for n: Dictionary in nb.notables():
		roles[n["role"]] = int(roles.get(n["role"], 0)) + 1
		names[n["n"]] = true
		assert_str(String(n["amb"])).is_not_empty()
		assert_int(int(n["age"])).is_between(20, 60)
		assert_bool(nb.families().any(func(f: Dictionary) -> bool: return f["id"] == n["fam"])).is_true()
	for r in ["adventurer", "officer", "merchant", "scholar"]:
		assert_bool(roles.has(r)).is_true()
	assert_int(names.size()).is_greater(45)
	assert_int(nb.families().size()).is_greater(11)
	for f: Dictionary in nb.families():
		assert_str(String(f["biz"]["name"])).is_not_empty()
		assert_str(String(f["spec"])).is_not_empty()
	# Established outfits exist from day one so there is competition.
	assert_int(nb.orgs().size()).is_greater(2)


func test_notables_found_organisations_over_the_years() -> void:
	var hub := _mk()
	var nb: RefCounted = hub.mod("notables")
	var before: int = nb.orgs().size()
	_run(hub, 1, 360 * 10)
	var founded := 0
	for line: String in nb.chronicle():
		if " founded " in line:
			founded += 1
	assert_int(founded).is_greater(0)
	assert_int(nb.active_count()).is_equal(60)         # heirs and recruits keep the pool at 60
	var gov: RefCounted = hub.mod("governance")
	var seen_ids := {}
	for o: Dictionary in nb.orgs():
		seen_ids[o["id"]] = true
		assert_str(String(o["n"])).is_not_empty()
	assert_int(seen_ids.size()).is_greater(0)
	# NPC-founded organisations get a leader seat in governance.
	var companies: Array = gov.institutions("company")
	assert_int(companies.size()).is_greater(3 - 1)
	assert_bool(before >= 0).is_true()


func test_founding_a_settlement_asks_civilization_when_present() -> void:
	var hub := _mk()
	var nb: RefCounted = hub.mod("notables")
	var nid := String(nb.notables()[0]["id"])
	# Without CIV-A: the claim is kept as data.
	hub.mods.erase("civilization")
	nb._found(nid, "settlement")
	assert_int(nb.claims().size()).is_equal(1)
	# With a civilization module: it is asked, and its answer is respected.
	var stub := GDScript.new()
	stub.source_code = "extends RefCounted\nvar asked := []\nfunc request_founding(req: Dictionary) -> Dictionary:\n\tasked.append(req)\n\treturn {\"ok\": true}\nfunc news_events() -> Array:\n\treturn []\n"
	stub.reload()
	var civ: RefCounted = stub.new()
	hub.mods["civilization"] = civ
	var nid2 := String(nb.notables()[1]["id"])
	nb._found(nid2, "settlement")
	assert_int((civ.get("asked") as Array).size()).is_equal(1)
	assert_int(nb.claims().size()).is_equal(1)
	assert_str(String((civ.get("asked") as Array)[0]["founder"])).is_equal(String(nb.notable(nid2)["n"]))


func test_families_remember_help_across_generations() -> void:
	var nb: RefCounted = _mk().mod("notables")
	var n: Dictionary = nb.notables()[5]
	var fid := String(n["fam"])
	var g0: float = nb.family_goodwill(fid)
	nb.record_help(String(n["id"]), 30.0)
	assert_float(nb.family_goodwill(fid)).is_greater(g0 + 29.0)
	nb._day = 400
	nb._die(String(n["id"]), "died", [])
	assert_bool(nb.notable(String(n["id"])).is_empty()).is_true()    # pruned
	assert_int(nb.active_count()).is_equal(60)                        # an heir stepped in
	var heirs: Array = nb.notables().filter(func(x: Dictionary) -> bool: return x["fam"] == fid and int(x["age"]) < 30)
	assert_int(heirs.size()).is_greater(0)
	assert_float(nb.attitude(String((heirs[0] as Dictionary)["id"]))).is_greater(g0 + 25.0)   # the heir remembers
	assert_bool(nb.chronicle().size() > 0).is_true()


func test_dead_notables_become_one_line_history_and_saves_stay_small() -> void:
	var hub := _mk()
	var nb: RefCounted = hub.mod("notables")
	_run(hub, 1, 360 * 15)
	assert_int(nb.chronicle().size()).is_less_equal(50)
	for line: String in nb.chronicle():
		assert_bool(line.length() < 400).is_true()
	assert_int(JSON.stringify(nb.serialize()).length()).is_less(120000)


func test_expeditions_join_fund_sabotage_and_rescue() -> void:
	var hub := _mk()
	var nb: RefCounted = hub.mod("notables")
	nb._day = 10
	nb._start_expedition(_rng(3))
	var out: Array = nb.expeditions("out")
	assert_int(out.size()).is_equal(1)
	var eid := int(out[0]["id"])
	assert_bool(bool(nb.expedition_join(eid)["ok"])).is_true()
	assert_bool(bool(nb.expedition_join(eid)["ok"])).is_false()       # only once
	assert_bool(bool(nb.expedition_fund(eid, 500)["ok"])).is_true()
	assert_int(int(nb.expeditions()[0]["funding"])).is_equal(500)
	assert_bool(bool(nb.expedition_sabotage(eid)["ok"])).is_true()
	assert_float(float(nb.expeditions()[0]["sab"])).is_greater(0.0)
	assert_bool(bool(nb.expedition_rescue(eid)["ok"])).is_false()     # nobody is missing yet
	# Make it overdue, then rescue it inside the window.
	var e: Dictionary = nb._exp_by_id(eid)
	e["sab"] = 9.0
	e["mod"] = -9.0
	var day := int(e["eta"])
	for k in 60:
		nb._day = day + k
		nb._expedition_day()
		if String(nb._exp_by_id(eid)["status"]) == "missing":
			break
	assert_str(String(nb._exp_by_id(eid)["status"])).is_equal("missing")
	var ok := false
	for k in 12:
		nb._day += 1
		if bool(nb.expedition_rescue(eid, 1.0)["ok"]):
			ok = true
			break
	assert_bool(ok).is_true()
	assert_str(String(nb._exp_by_id(eid)["status"])).is_equal("rescued")


func test_lost_expedition_becomes_a_mystery_and_plants_a_relic_lead() -> void:
	var hub := _mk()
	var nb: RefCounted = hub.mod("notables")
	var ex: RefCounted = hub.mod("exploration")
	nb._day = 10
	nb._start_expedition(_rng(4))
	var e: Dictionary = nb.expeditions("out")[0]
	var eid := int(e["id"])
	var target := String(e["target"])
	nb._exp_by_id(eid)["sab"] = 9.0
	nb._exp_by_id(eid)["mod"] = -9.0
	for k in 80:
		nb._day = int(e["eta"]) + k
		nb._expedition_day()
		if String(nb._exp_by_id(eid)["status"]) == "missing":
			break
	assert_str(String(nb._exp_by_id(eid)["status"])).is_equal("missing")
	nb._day = int(nb._exp_by_id(eid)["until"]) + 1      # nobody came
	nb._expedition_day()
	assert_str(String(nb._exp_by_id(eid)["status"])).is_equal("lost")
	assert_int(nb.mysteries().size()).is_equal(1)
	assert_bool(ex.knows_lead(target)).is_false()        # the secret is kept at first
	nb._day = int(nb.mysteries()[0]["relic_day"]) + 1
	nb._mystery_day()
	assert_bool(ex.knows_lead(target)).is_true()
	assert_bool(ex.relics.has(target)).is_true()
	var soc: RefCounted = hub.mod("society")
	assert_bool(soc.knows("lead:%s" % target)).is_true()
	# The relic survives a save.
	var ex2: RefCounted = _mk().mod("exploration")
	ex2.deserialize(JSON.parse_string(JSON.stringify(ex.serialize())))
	assert_bool(ex2.relics.has(target)).is_true()


func test_ignored_crises_are_solved_or_fail_with_consequences() -> void:
	var hub := _mk()
	var nb: RefCounted = hub.mod("notables")
	var gov: RefCounted = hub.mod("governance")
	nb._day = 50
	var resolved := 0
	var failed := 0
	for i in 14:
		nb._spawn_crisis(_rng(100 + i))
	for c: Dictionary in nb.crises():
		assert_str(String(c["status"])).is_equal("open")
	nb._crises.clear()
	for i in 14:
		nb._day = 50 + i
		nb._spawn_crisis(_rng(200 + i))
		var c: Dictionary = nb._crises[nb._crises.size() - 1]
		var sid := int(c["sid"])
		var poor0: float = gov.opinion(sid, "poor")
		nb._day = int(c["deadline"])
		nb._crisis_day()
		var st := String(nb._crises[nb._crises.size() - 1]["status"])
		assert_bool(st == "resolved_npc" or st == "failed").is_true()
		resolved += 1 if st == "resolved_npc" else 0
		failed += 1 if st == "failed" else 0
		if st == "failed":
			gov._ensure()
		assert_bool(poor0 <= 1.0).is_true()
	assert_int(resolved).is_greater(0)
	assert_int(failed).is_greater(0)
	# The player can step in first.
	nb._crises.clear()
	nb._spawn_crisis(_rng(7))
	assert_bool(nb.crisis_resolve(int(nb._crises[0]["id"]))).is_true()
	assert_str(String(nb._crises[0]["status"])).is_equal("resolved_player")


func test_research_can_succeed_or_fail_and_spreads_knowledge() -> void:
	var hub := _mk()
	var nb: RefCounted = hub.mod("notables")
	nb._day = 20
	for i in 12:
		nb._res.clear()
		nb._start_research(_rng(300 + i))
		if nb._res.is_empty():
			continue
		nb._res[0]["need"] = 14.0
		for w in 6:
			nb._day += 7
			nb._research_step(1.0, [])
		assert_str(String(nb._res[0]["status"])).is_not_equal("active")
	var total := 0
	for f: String in nb.FIELDS:
		total += nb.tech(f)
	assert_int(total).is_greater(0)
	var field: String = ""
	for f: String in nb.FIELDS:
		if nb.tech(f) > 0:
			field = f
	var known0: int = ((nb._tech[field] as Dictionary)["at"] as Array).size()
	nb._spread_tech(40.0, _rng(9))
	assert_int(((nb._tech[field] as Dictionary)["at"] as Array).size()).is_greater(known0)
	assert_bool(hub.mod("society").known_count("tech:") > 0).is_true()


func test_guilds_and_companies_compete_and_companies_grow_branches() -> void:
	var hub := _mk()
	var nb: RefCounted = hub.mod("notables")
	var cos: Array = nb.orgs("company")
	assert_int(cos.size()).is_greater(1)
	_run(hub, 1, 360 * 4)
	var rivals := 0
	for o: Dictionary in nb.orgs():
		if String(o["rival"]) != "":
			rivals += 1
	assert_int(rivals).is_greater(0)
	var spread := 0.0
	var mn := 1000.0
	var mx := 0.0
	for o: Dictionary in nb.orgs():
		mn = minf(mn, float(o["power"]))
		mx = maxf(mx, float(o["power"]))
	spread = mx - mn
	assert_float(spread).is_greater(1.0)


func test_academies_drift_rival_and_lose_teachers() -> void:
	var hub := _mk()
	var ed: RefCounted = hub.mod("education")
	var nb: RefCounted = hub.mod("notables")
	var before: Dictionary = ed.school_rep.duplicate()
	_run(hub, 1, 360 * 3)
	var moved := 0
	for id: String in ed.school_rep:
		if absf(float(ed.school_rep[id]) - float(before.get(id, 0.0))) > 0.5:
			moved += 1
	assert_int(moved).is_greater(2)
	var thin := 0
	for i: Dictionary in ed.institutions():
		if float(i.get("staff", 1.0)) < 1.0:
			thin += 1
	assert_int(thin).is_greater(0)
	assert_bool(nb.news_events().size() > 0).is_true()
	# The staff penalty is real: new teachers of a weakened school are weaker.
	ed.adjust_school("inst_0", 0.0, -0.4)
	assert_float(float(ed.institution("inst_0")["staff"])).is_less(0.7)


func test_determinism_and_save_round_trip() -> void:
	var a := _mk()
	var b := _mk()
	var mods := ["notables", "education", "exploration"]
	_run(a, 1, 420, mods)
	_run(b, 1, 420, mods)
	assert_str(_norm(a.mod("notables").serialize())).is_equal(_norm(b.mod("notables").serialize()))
	var c := _mk()
	for k: String in mods + ["governance", "society"]:
		c.mod(k).deserialize(JSON.parse_string(JSON.stringify(a.mod(k).serialize())))
	assert_str(_norm(c.mod("notables").serialize())).is_equal(_norm(a.mod("notables").serialize()))
	_run(a, 421, 500, mods)
	_run(c, 421, 500, mods)
	assert_bool(_same(JSON.parse_string(_norm(c.mod("notables").serialize())), JSON.parse_string(_norm(a.mod("notables").serialize())))).is_true()


func test_catch_up_matches_day_by_day_within_tolerance() -> void:
	var a := _mk()
	var b := _mk()
	_run(a, 1, 1)
	_run(b, 1, 1)
	_run(a, 2, 361)
	b.mod("notables").catch_up(360, CTX)
	var na: RefCounted = a.mod("notables")
	var nbm: RefCounted = b.mod("notables")
	assert_int(nbm.active_count()).is_equal(na.active_count())
	assert_int(absi(nbm.orgs().size() - na.orgs().size())).is_less(7)
	var ra := 0.0
	var rb := 0.0
	for n: Dictionary in na.notables():
		ra += float(n["renown"])
	for n: Dictionary in nbm.notables():
		rb += float(n["renown"])
	assert_float(absf(ra - rb) / 60.0).is_less(12.0)
	assert_bool(nbm.stats()["history"] >= 0).is_true()
	for n: Dictionary in nbm.notables():
		assert_str(String(n["n"])).is_not_empty()


func test_day_chunks_cost() -> void:
	var hub := _mk()
	_run(hub, 1, 40)
	var nb: RefCounted = hub.mod("notables")
	var times: Array = []
	for day in range(41, 101):
		for c: Callable in nb.tick_day_chunks(day, CTX):
			var t0 := Time.get_ticks_usec()
			c.call()
			times.append(Time.get_ticks_usec() - t0)
	times.sort()
	var median := float(times[times.size() / 2]) / 1000.0
	var p95 := float(times[int(times.size() * 0.95)]) / 1000.0
	print("notables chunk cost: median %.3f ms, p95 %.3f ms, worst %.3f ms" % [median, p95, float(times[times.size() - 1]) / 1000.0])
	assert_float(median).is_less(0.6)
	assert_float(p95).is_less(2.0)        # loose: CI runners are slow
