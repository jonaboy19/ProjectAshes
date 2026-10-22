extends GdUnitTestSuite
## CIV-C living ecology: zones, discrete Lotka-Volterra with closed-form-ish catch_up, apex succession, migration,
## monster clans with hidden intent, domestication, adventurer economy, den mirror, saves, cost.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const D := preload("res://scripts/realm/ecology_data.gd")
const CTX := {"season": "summer", "at_war": false, "abs_hours": 0, "gold": 0, "player_pos": Vector3.ZERO, "life": null}


func _norm(d: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


## Deep compare with a float tolerance (a JSON save keeps ~15 digits, which a few days of ticks magnify a little).
func _same(a: Variant, b: Variant, tol := 1e-6) -> bool:
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
		return absf(float(a) - float(b)) <= tol * maxf(1.0, absf(float(a)))
	return a == b


func _mk(events := true) -> RefCounted:
	WorldGen.setup(2024)
	var m: RefCounted = Hub.new().mod("ecology")
	m.events_enabled = events
	m._ensure()
	return m


func _run_days(m: RefCounted, from_day: int, n: int, season := "summer") -> void:
	for d in range(from_day, from_day + n):
		m.tick_day(d, {"season": season, "player_pos": Vector3.ZERO, "life": null})


func _state_vec(m: RefCounted) -> Array:
	var out: Array = []
	for i in m.zone_count():
		out.append_array(m._st[i]["n"])
		out.append(m._st[i]["adv"])
	return out


func test_hub_registers_ecology_and_zones_cover_settlements() -> void:
	WorldGen.setup(2024)
	var hub: RefCounted = Hub.new()
	assert_object(hub.mod("ecology")).is_not_null()
	assert_bool("ecology" in Hub.ORDER).is_true()
	var m: RefCounted = hub.mod("ecology")
	m._ensure()
	assert_int(m.zone_count()).is_equal(WorldGen.settlements.size())
	for s: Dictionary in WorldGen.settlements:
		assert_int(m.zone_index_of_settlement(int(s["id"]))).is_greater_equal(0)
		var pops: Dictionary = m.populations(int(s["id"]))
		assert_int(pops.size()).is_equal(D.SPECIES.size())


func test_deterministic() -> void:
	var a := _mk()
	var b := _mk()
	_run_days(a, 1, 60)
	_run_days(b, 1, 60)
	assert_str(_norm(a.serialize())).is_equal(_norm(b.serialize()))


func test_populations_stay_sane_over_years() -> void:
	var m := _mk()
	m.catch_up(112 * 6, {"player_pos": Vector3.ZERO, "life": null})
	for v: float in _state_vec(m):
		assert_bool(is_nan(v) or is_inf(v) or v < 0.0 or v > 500.0).is_false()
	# Prey stays alive everywhere (floor) and some predators remain in the wild.
	var wolves := 0.0
	for i in m.zone_count():
		wolves += float(m._st[i]["n"][D.WOLF])
		assert_float(m._prey_idx(i)).is_greater(0.02)
	assert_float(wolves).is_greater(5.0)


func test_catch_up_matches_day_by_day() -> void:
	var a := _mk(false)
	var b := _mk(false)
	var days := 84
	for d in range(1, days + 1):
		a.tick_day(d, {"season": a._season_of(d), "player_pos": Vector3.ZERO, "life": null})
	b.catch_up(days, {"player_pos": Vector3.ZERO, "life": null})
	# Per zone: prey index, wolves and adventurers agree within a loose band (larger steps + weekly route planning).
	var worst := 0.0
	for i in a.zone_count():
		var ia: float = a._prey_idx(i)
		var ib: float = b._prey_idx(i)
		worst = maxf(worst, absf(ia - ib) / maxf(ia, 0.1))
		var wa: float = a._st[i]["n"][D.WOLF]
		var wb: float = b._st[i]["n"][D.WOLF]
		assert_float(absf(wa - wb)).is_less(maxf(1.5, 0.3 * wa))
		assert_float(absf(float(a._st[i]["adv"]) - float(b._st[i]["adv"]))).is_less(maxf(3.0, 0.3 * float(a._st[i]["adv"])))
	# 0.2 -> 0.45: the 12 km world change (world_gen.gd) stretches zone distances, so weekly route planning in catch_up differs more from
	# day-by-day flows in the worst zone; the per-zone wolf and adventurer bands above still hold.
	assert_float(worst).is_less(0.45)


func test_catch_up_is_bounded_work() -> void:
	var m := _mk()
	var t0 := Time.get_ticks_usec()
	m.catch_up(112 * 15, {"player_pos": Vector3.ZERO, "life": null})
	var long_us := Time.get_ticks_usec() - t0
	var m2 := _mk()
	t0 = Time.get_ticks_usec()
	m2.catch_up(112, {"player_pos": Vector3.ZERO, "life": null})
	var short_us := Time.get_ticks_usec() - t0
	# 15 years costs at most a small constant factor more than one year (substeps are capped), never 15x.
	assert_float(float(long_us)).is_less(maxf(float(short_us) * 6.0, 120000.0))


func test_save_round_trip() -> void:
	var a := _mk()
	_run_days(a, 1, 50)
	a.learn_intent(0, 1)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(a.serialize()))
	var b := _mk()
	b.deserialize(saved)
	assert_str(_norm(b.serialize())).is_equal(_norm(a.serialize()))
	_run_days(a, 51, 14)
	_run_days(b, 51, 14)
	assert_bool(_same(JSON.parse_string(JSON.stringify(a.serialize())), JSON.parse_string(JSON.stringify(b.serialize())))).is_true()
	assert_int(b.faction_view(0)["known"]).is_equal(1)


func test_cost_per_pump_job() -> void:
	var m := _mk()
	var samples := {}
	var days := 28
	for d in range(1, days + 1):
		var chunks: Array = m.tick_day_chunks(d, CTX)
		var ci := 0
		for c: Callable in chunks:
			var t := Time.get_ticks_usec()
			c.call()
			var dt := Time.get_ticks_usec() - t
			if not samples.has(ci):
				samples[ci] = []
			(samples[ci] as Array).append(dt)
			ci += 1
	# The 0.6 ms pump budget applies per job. CI boxes are shared and noisy, so judge the lower quartile of each job
	# (contention only ever adds time) and give the single worst a generous ceiling.
	var worst_q := 0
	var worst := 0
	for k: int in samples:
		var arr: Array = samples[k]
		arr.sort()
		worst_q = maxi(worst_q, int(arr[arr.size() / 4]))
		worst = maxi(worst, int(arr[arr.size() - 1]))
	print("ecology chunk worst lower-quartile %d us, single worst %d us" % [worst_q, worst])
	assert_int(worst_q).is_less(600)
	assert_int(worst).is_less(40000)


func test_apex_removal_booms_prey_then_a_worse_predator_moves_in() -> void:
	var m := _mk()
	# Pick a wild zone, give it a bear, let the system settle, then kill the bear.
	var zi := -1
	for i in m.zone_count():
		if float(m._zones[i]["wild"]) >= 0.5 and m.apex_count_z(i) < 0.4 and float(m._zones[i]["cap_dist"]) > 1600.0:
			zi = i
			break
	assert_int(zi).is_greater_equal(0)
	var sid := int(m._zones[zi]["sid"])
	(m._st[zi]["n"] as Array)[D.BEAR] = 1.0
	for _k in 120:
		m._step_zone(zi, 1.0, "summer", false)
	var suppressed: float = m._prey_idx(zi)
	assert_str(m.kill_apex(sid)).is_equal("bear")
	for _k in 90:
		m._step_zone(zi, 1.0, "summer", false)
	var boomed: float = m._prey_idx(zi)
	assert_float(boomed).is_greater(suppressed * 1.6)
	# Weeks pass; the vacancy and the boom draw a new apex in (worse than a bear, or a bear again).
	var arrived := ""
	for w in 900:
		for _d in 7:
			m._step_zone(zi, 1.0, "summer", false)
		m._day += 7
		m._apex_week(zi, 1.0, "t", m._day)
		if m.apex_count_z(zi) > 0.4:
			arrived = String(m._st[zi]["lastA"])
			break
	assert_str(arrived).is_not_empty()
	var found := false
	for e: Dictionary in m.news_events(0, 1):
		if String(e["kind"]) == "apex_arrival" and int(e["zone"]) == zi:
			found = true
	assert_bool(found).is_true()


func test_worse_species_chain() -> void:
	assert_str(String(D.WORSE["bear"])).is_equal("troll")
	assert_str(String(D.WORSE["troll"])).is_equal("wyvern")
	assert_float(D.THREAT[D.WYVERN]).is_greater(D.THREAT[D.TROLL])
	assert_float(D.THREAT[D.TROLL]).is_greater(D.THREAT[D.BEAR])


func test_wiping_out_wolves_lets_corrupted_wolves_spread() -> void:
	var m := _mk()
	var zi := -1
	for i in m.zone_count():
		if float(m._zones[i]["rift"]) > 0.6 and float(m._zones[i]["wild"]) > 0.4:
			zi = i
			break
	assert_int(zi).is_greater_equal(0)
	m.set_rift(0.9)
	var n: Array = m._st[zi]["n"]
	# With wolves present corrupted wolves are held down; remove the wolves and they spread.
	n[D.WOLF] = 9.0
	n[D.CORR] = 1.0
	var with_wolves := 0.0
	var probe: RefCounted = _mk()
	probe.set_rift(0.9)
	(probe._st[zi]["n"] as Array)[D.WOLF] = 9.0
	(probe._st[zi]["n"] as Array)[D.CORR] = 1.0
	for _k in 200:
		probe._step_zone(zi, 1.0, "summer", false)
	with_wolves = probe._st[zi]["n"][D.CORR]
	n[D.WOLF] = 0.0
	for _k in 200:
		m._step_zone(zi, 1.0, "summer", false)
	assert_float(float(m._st[zi]["n"][D.CORR])).is_greater(with_wolves + 0.5)


func test_winter_migration_brings_wolves_into_a_village_zone_and_villagers_see_them() -> void:
	var m := _mk()
	var human := -1
	var best_supply := 0.0
	for i in m.zone_count():
		var z: Dictionary = m._zones[i]
		if float(z["wild"]) >= 0.5:
			continue
		# The wolves pushed this way in winter: the wolves of every wilder neighbour whose least wild way out is this zone
		# (the 12 km world has many more zones, so take the best-fed village zone rather than the first one found).
		var supply := 0.0
		for j: int in z["neigh"]:
			if float(m._zones[j]["wild"]) > float(z["wild"]) + 0.3 and float((m._st[j]["n"] as Array)[D.WOLF]) > 3.0:
				var out_to: int = m._best_nb(m._zones[j]["neigh"], func(k: int) -> float: return -float(m._zones[k]["wild"]))
				if out_to == i:
					supply += float((m._st[j]["n"] as Array)[D.WOLF])
		if supply > best_supply:
			best_supply = supply
			human = i
	assert_int(human).is_greater_equal(0)
	# A hard winter in the wild zones beside it: the migration mechanic is under test, not how many wolves the map starts with
	# (a village zone in the 12 km world loses what trickles in to its hunters, so the push has to be a real one).
	for j: int in m._zones[human]["neigh"]:
		if float(m._zones[j]["wild"]) > float(m._zones[human]["wild"]) + 0.3 and int(m._best_nb(m._zones[j]["neigh"], func(k: int) -> float: return -float(m._zones[k]["wild"]))) == human:
			(m._st[j]["n"] as Array)[D.WOLF] = 40.0
	(m._st[human]["n"] as Array)[D.WOLF] = 0.0
	(m._st[human]["seen"] as Dictionary).erase("wolf")
	for week in 8:
		m._plan_routes("winter")
		for _d in 7:
			for i in m.zone_count():
				m._step_zone(i, 1.0, "winter")
		m._day += 7
		for i in m.zone_count():
			m._detect(i)
	assert_float(float(m._st[human]["n"][D.WOLF])).is_greater(0.8)
	var told := false
	for e: Dictionary in m.news_events(0, 1):
		if String(e["kind"]) in ["sighting", "migration"] and int(e["zone"]) == human:
			told = true
	assert_bool(told).is_true()
	assert_bool("wolf" in m.species_seen(int(m._zones[human]["sid"]))).is_true()


func test_clan_intent_is_hidden_until_learned_and_clans_trade_or_raid() -> void:
	var m := _mk()
	var v0: Dictionary = m.faction_view(0)
	assert_str(String(v0["intent"])).is_equal("unknown")
	assert_int(int(v0["known"])).is_equal(0)
	var acted := 0
	for d in range(1, 200):
		m.tick_day(d, {"season": m._season_of(d), "player_pos": Vector3.ZERO, "life": null})
	for e: Dictionary in m.news_events(0, 1):
		if String(e["kind"]) in ["monster_trade", "monster_raid"]:
			acted += 1
	assert_int(acted).is_greater(0)
	# Hidden: nobody's exact intent is exposed without learning it.
	for v: Dictionary in m.factions():
		if int(v["known"]) < 2:
			assert_bool(String(v["intent"]) in D.FACTION_INTENTS).is_false()
	assert_bool(m.learn_intent(1, 2)).is_true()
	assert_bool(String(m.faction_view(1)["intent"]) in D.FACTION_INTENTS).is_true()
	# A changed decision hides it again at the next decision.
	m._factions.list[1]["intent"] = "hold"
	m._factions._decide(m._factions.list[1], 500)
	if String(m._factions.list[1]["intent"]) != "hold":
		assert_int(int(m._factions.list[1]["known"])).is_equal(0)


func test_raid_uses_settlement_defense_and_aftermath() -> void:
	WorldGen.setup(2024)
	var hub: RefCounted = Hub.new()
	var m: RefCounted = hub.mod("ecology")
	m._ensure()
	var sid := 3
	var weak: float = m.defense_of(sid)
	m.raid_lands(sid, 0.5)
	assert_float(m.defense_of(sid)).is_greater(weak)     # the place is on guard afterwards
	assert_bool(hub.mod("settlements").emergencies(sid).size() > 0).is_true()


func test_adventurer_economy_follows_danger_and_collapses_when_cleared() -> void:
	var m := _mk()
	var zi := -1
	for i in m.zone_count():
		if float(m._zones[i]["wild"]) > 0.5 and float(m._zones[i]["dungeon"]) < 1.0:
			zi = i
			break
	assert_int(zi).is_greater_equal(0)
	var sid := int(m._zones[zi]["sid"])
	var n: Array = m._st[zi]["n"]
	n[D.WYVERN] = 2.0
	n[D.WOLF] = 9.0
	for _k in 160:
		m._step_zone(zi, 1.0, "summer", false)
	var busy: float = m.adventurers(sid)
	var inn_busy: float = m.services(sid)["inn"]
	assert_float(busy).is_greater(4.0)
	assert_float(inn_busy).is_greater(1.0)
	assert_bool(m.bounties(sid).size() > 0).is_true()
	# Clear the danger.
	n[D.WYVERN] = 0.0
	n[D.WOLF] = 0.0
	n[D.CORR] = 0.0
	for _k in 120:
		m._step_zone(zi, 1.0, "summer", false)
	assert_float(m.adventurers(sid)).is_less(busy * 0.3)
	assert_float(m.services(sid)["inn"]).is_less(inn_busy * 0.5)
	assert_bool(m.bounties(sid).is_empty()).is_true()


func test_domestication_is_slow_and_needs_the_species() -> void:
	var m := _mk()
	var zi := 0
	var sid := int(m._zones[zi]["sid"])
	(m._st[zi]["n"] as Array)[D.BOAR] = 12.0
	m._st[zi]["dom"] = {}
	m._domestication(zi, 112.0)        # one year
	var year1: float = m.domestication(sid)["boar"]["familiarity"]
	assert_float(year1).is_between(0.005, 0.25)
	m._domestication(zi, 112.0 * 10.0)
	var year11: float = m.domestication(sid)["boar"]["familiarity"]
	assert_float(year11).is_greater(year1 * 3.0)
	assert_float(m.domestic_bonus(sid, "farming")).is_greater(0.2)
	# Without the species the tech decays.
	(m._st[zi]["n"] as Array)[D.BOAR] = 0.0
	m._domestication(zi, 112.0 * 3.0)
	assert_float(float(m.domestication(sid)["boar"]["familiarity"])).is_less(year11 * 0.9)


func test_danger_comes_from_a_named_pack() -> void:
	var m := _mk()
	var t: Array = m.territories()
	assert_bool(t.size() > 0).is_true()
	var pack: Dictionary = t[0]
	var at: Dictionary = m.danger_at(pack["nest"])
	assert_float(float(at["total"])).is_greater(0.0)
	assert_str(String(at["sources"][0]["name"])).contains(String(m._zones[int(pack["zone"])]["name"]))
	# Far from every nest (or safe town centre) there is no pack to blame.
	var safe: Dictionary = m.danger_at(Vector2(99999.0, 99999.0))
	assert_float(float(safe["total"])).is_less(1.0)


func test_news_events_are_plain_text_with_ids() -> void:
	var m := _mk()
	m.catch_up(112, {"player_pos": Vector3.ZERO, "life": null})
	var ev: Array = m.news_events(0, 1)
	assert_bool(ev.size() > 0).is_true()
	var last := 0
	for e: Dictionary in ev:
		assert_int(int(e["id"])).is_greater(last)
		last = int(e["id"])
		assert_str(String(e["text"])).is_not_empty()
		assert_bool(int(e["importance"]) >= 1 and int(e["importance"]) <= 3).is_true()
	assert_int(m.news_events(9999999).size()).is_equal(0)


func test_den_mirror_follows_zones_and_kills_flow_back() -> void:
	WorldGen.setup(2024)
	var hub: RefCounted = Hub.new()
	var m: RefCounted = hub.mod("ecology")
	var eco := RAMonsterEcology.new(5)
	var z := 4
	var zp: Vector2 = WorldGen.settlements[z]["pos"]
	var d0 := eco.add_den("wolf", zp + Vector2(300, 0), 8)
	m._ensure()
	m.bind_frontier(eco)
	assert_bool(m.is_bound_to(eco)).is_true()
	var zi: int = m.zone_of(d0["pos"])
	assert_float(float(m._st[zi]["n"][D.WOLF])).is_equal_approx(8.0, 0.01)
	# A kill in the world lowers the zone's population.
	eco.cull(int(d0["id"]), 3)
	m._sync_dens()
	assert_float(float(m._st[zi]["n"][D.WOLF])).is_equal_approx(5.0, 0.6)
	# Zone growth is written back to the dens (new dens appear when a den would exceed its size).
	(m._st[zi]["n"] as Array)[D.WOLF] = 30.0
	m._sync_dens()
	var total := 0
	var alive := 0
	for den: Dictionary in eco.dens:
		if den["species"] == "wolf" and den["alive"]:
			total += int(den["population"])
			alive += 1
	assert_int(total).is_equal(30)
	assert_int(alive).is_greater(1)
	# An apex kill (den culled to zero) removes the apex from the zone.
	var bear := eco.spawn_apex("bear", zp + Vector2(-400, 0), 1)
	m._sync_dens()
	var bz: int = m.zone_of(bear["pos"])
	assert_float(m.apex_count_z(bz)).is_greater(0.4)
	eco.cull(int(bear["id"]), 1)
	m._sync_dens()
	assert_float(m.apex_count_z(bz)).is_less(0.4)
	# Rebinding to a new ecology object (new game) adopts its dens afresh.
	var eco2 := RAMonsterEcology.new(6)
	eco2.add_den("wolf", zp + Vector2(200, 100), 5)
	m.bind_frontier(eco2)
	assert_float(float(m._st[m.zone_of(Vector2(zp.x + 200, zp.y + 100))]["n"][D.WOLF])).is_equal_approx(5.0, 0.01)


func test_threat_map_territory_hook() -> void:
	WorldGen.setup(2024)
	var m: RefCounted = Hub.new().mod("ecology")
	m._ensure()
	var eco := RAMonsterEcology.new(1)
	var map := RAThreatMap.new(RARunestoneNetwork.new(), eco)
	var before: float = map.evaluate(m._factions.fpos(m._factions.list[0]))["total"]
	m.bind_frontier(eco, map)
	var after: Dictionary = map.evaluate(m._factions.fpos(m._factions.list[0]))
	assert_float(float(after["total"])).is_greater(before)
	var named := false
	for l: Array in after["lines"]:
		if String(l[0]).contains("clan") or String(l[0]).contains("host"):
			named = true
	assert_bool(named).is_true()


func test_camp_hooks_default_safe_and_follow_clan() -> void:
	var m := _mk()
	assert_bool(m.camp_active("no_such_camp")).is_true()
	assert_float(m.camp_strength("no_such_camp")).is_equal(1.0)
	var pid := String(m._factions.list[0]["place"])
	assert_bool(m.camp_active(pid)).is_true()
	var s0: float = m.camp_strength(pid)
	m.camp_loss(pid, 4)
	assert_float(m.camp_strength(pid)).is_less(s0)
	m._factions.list[0]["status"] = "marching"
	assert_bool(m.camp_active(pid)).is_false()


func test_news_module_ingests_ecology_events() -> void:
	WorldGen.setup(2024)
	var hub: RefCounted = Hub.new()
	var m: RefCounted = hub.mod("ecology")
	m._ensure()
	var sid := int(m._zones[2]["sid"])
	m._news_add("apex_arrival", "A wyvern pair has nested above %s." % m._zname(2), 2, 3)
	assert_int(int(m._seq)).is_equal(1)
	assert_int(m.news_events(1).size()).is_equal(0)
	assert_int(m.news_events(0).size()).is_equal(1)          # importance 3 passes the default filter
	m._news_add("monster_trade", "Goblin traders at the market.", 2, 1)
	assert_int(m.news_events(0).size()).is_equal(1)          # importance 1 is flavour only
	assert_int(m.news_events(0, 1).size()).is_equal(2)
	var news: RefCounted = hub.mod("news")
	if news == null:
		return          # CIV-B's module is not part of this checkout
	news.tick_day(40, CTX)
	var seen := false
	for it: Dictionary in news.items_at(sid, 40):
		if String(it["kind"]) == "apex_arrival":
			seen = true
	assert_bool(seen).is_true()
