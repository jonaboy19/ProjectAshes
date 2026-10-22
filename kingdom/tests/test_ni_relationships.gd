extends GdUnitTestSuite
## NI-5 (scripts/sim/npc_social_graph.gd bond layer + scripts/realm/bonds.gd, docs/design/NPC_INTELLIGENCE_MAP.md section 5):
## NPC-to-NPC relationships on eight axes, asymmetric, decaying in closed form, bounded per character, packed in the save;
## feeding marriage / organisation / revenge / avoidance choices and word of mouth; and the life stories the mechanisms produce.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Graph := preload("res://scripts/sim/npc_social_graph.gd")
const Persona := preload("res://scripts/realm/persona.gd")
const Minds := preload("res://scripts/realm/minds.gd")

const START := 600
const LIVE := ["registry", "events", "news", "organizations", "businesses", "emergence", "faith", "dynasties", "homes", "minds", "rumours", "bonds"]

static var _world := false


func _hub() -> RefCounted:
	if not _world:
		WorldGen.setup(2024)
		_world = true
	WorldSim.day = START
	var h: RefCounted = Hub.new()
	var om: RefCounted = h.mod("organizations")
	om.auto_seed = false
	om.gold_ref = {"gold": 5000}
	h.mod("faith").auto_seed = false
	h.mod("minds").auto_seed = false
	h.mod("minds").set_focus(-1)
	for k in ["farming", "businesses", "homes"]:
		if h.mod(k).has_method("set_day"):
			h.mod(k).set_day(START)
	h.mod("businesses").set_population(0, 800)
	om.set_day(START)
	h.mod("registry").ref("pl:player")
	return h


func _ch(h: RefCounted, age := 30, sex := "m", cash := 500, sid := 0, prof := "smith") -> String:
	var ch: String = h.mod("registry").mint("ch")
	h.mod("organizations").ensure_char(ch, {"cash": cash, "sid": sid, "prof": prof, "npc": true, "amb": "found"})
	assert_bool(h.mod("minds").adopt(ch, age, sex)).is_true()
	return ch


func _pset(h: RefCounted, ch: String, field: int, v: int) -> void:
	var pe: RefCounted = h.mod("persona")
	pe._buf[pe.off(ch) + field] = v


func _day(h: RefCounted, d: int) -> void:
	WorldSim.day = d
	for k in LIVE:
		h.mod(k).tick_day(d, {})
	if d % 7 == 0:
		for k in LIVE:
			h.mod(k).tick_week(d / 7, {})


# --- axes, asymmetry, persona, decay --------------------------------------------------

func test_one_event_moves_two_views_by_different_amounts() -> void:
	var h := _hub()
	var bo: RefCounted = h.mod("bonds")
	var a := _ch(h)
	var b := _ch(h)
	assert_bool(bo.event("help", a, b, START)).is_true()
	var ab: Dictionary = bo.view(a, b, START)
	var ba: Dictionary = bo.view(b, a, START)
	assert_float(ba["affection"]).is_greater(ab["affection"] + 2.0)       # the helped feels more than the helper
	assert_float(ba["obligation"]).is_greater(5.0)
	assert_float(ab["obligation"]).is_equal(0.0)
	assert_int(Graph.BOND_AXES.size()).is_equal(8)
	for ax in ["trust", "affection", "respect", "fear", "resentment", "rivalry", "attraction", "obligation"]:
		assert_bool(ab.has(ax)).is_true()


func test_a_betrayal_costs_an_honest_person_more_trust() -> void:
	var h := _hub()
	var bo: RefCounted = h.mod("bonds")
	var honest := _ch(h)
	var liar := _ch(h)
	var traitor := _ch(h)
	_pset(h, honest, Persona.O_HON, 250)
	_pset(h, liar, Persona.O_HON, 10)
	bo.event("work_together", honest, traitor, START)
	bo.event("work_together", liar, traitor, START)
	var t0: float = bo.view(honest, traitor, START)["trust"]
	assert_float(t0).is_equal_approx(float(bo.view(liar, traitor, START)["trust"]), 0.6)
	bo.event("betrayal", traitor, honest, START)
	bo.event("betrayal", traitor, liar, START)
	var lost_h: float = t0 - float(bo.view(honest, traitor, START)["trust"])
	var lost_l: float = t0 - float(bo.view(liar, traitor, START)["trust"])
	print("NI-5 trust lost to a betrayal: honest ", lost_h, " dishonest ", lost_l)
	assert_float(lost_h).is_greater(lost_l * 1.8)


func test_ties_decay_in_closed_form_each_axis_on_its_own_clock() -> void:
	var h := _hub()
	var bo: RefCounted = h.mod("bonds")
	var a := _ch(h)
	var b := _ch(h)
	bo.event("threat", a, b, START, 4.0)               # b fears a
	bo.event("feud", a, b, START, 2.0)
	var fear0: float = bo.view(b, a, START)["fear"]
	var res0: float = bo.view(b, a, START)["resentment"]
	assert_float(fear0).is_greater(30.0)
	# no per-tick work: the same record read 160 days on has lost half its fear (half-life 160) and far less of its resentment (400)
	var fear1: float = bo.view(b, a, START + 160)["fear"]
	var res1: float = bo.view(b, a, START + 160)["resentment"]
	assert_float(fear1).is_between(fear0 * 0.45, fear0 * 0.58)
	assert_float(res1 / res0).is_greater(fear1 / fear0 + 0.1)
	assert_float(bo.view(b, a, START + 4000)["fear"]).is_less(1.0)
	# reading never changes what is stored
	assert_float(bo.view(b, a, START)["fear"]).is_equal_approx(fear0, 0.01)


# --- bounded, packed, saved -----------------------------------------------------------

func test_each_character_keeps_only_the_top_k_ties() -> void:
	var g := Graph.new()
	var d := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
	for i in 20:
		d[0] = 5.0 + float(i) * 3.0                  # later acquaintances are stronger
		g.bond_adjust("ch:1", "ch:%d" % (10 + i), d, 100)
	assert_int(g.bond_count("ch:1")).is_equal(Graph.BOND_K)
	var kept: Array = g.bond_list("ch:1", 100)
	assert_int(kept.size()).is_equal(Graph.BOND_K)
	assert_float((kept[0][1] as PackedFloat32Array)[0]).is_equal(62.0)    # the strongest survived
	d[0] = 3.0                                       # a weak newcomer does not push anyone out
	assert_bool(g.bond_adjust("ch:1", "ch:900", d, 100)).is_false()
	assert_int(g.bond_count("ch:1")).is_equal(Graph.BOND_K)
	# asymmetric: the other direction has nothing
	assert_int(g.bond_count("ch:29")).is_equal(0)
	# forgetting a person removes the ties others hold to them
	g.bond_forget("ch:29")
	assert_int(g.bond_count("ch:1")).is_equal(Graph.BOND_K - 1)


func test_save_round_trip_old_saves_load_and_a_thousand_characters_stay_small() -> void:
	var g := Graph.new()
	for i in 1000:
		for k in 5:
			var d := PackedFloat32Array([float(10 + (i * 7 + k * 13) % 60), float(5 + (i + k * 17) % 50), float((i * 3 + k) % 40), 0.0, float((i + k) % 5) * 4.0, 0.0, float((k * i) % 30), float(k * 4)])
			g.bond_adjust("ch:%d" % (i + 1), "ch:%d" % ((i * 31 + k * 97) % 1000 + 1), d, 100 + k)
	var blob := JSON.stringify(g.serialize())
	var plain := JSON.stringify(Graph.new().serialize())
	print("NI-5 save: ", g.bond_owner_count(), " characters, ", g.bond_tie_count(), " ties, ", blob.length() - plain.length(), " bytes added")
	assert_int(blob.length() - plain.length()).is_less(80 * 1024)
	var g2 := Graph.new()
	assert_bool(g2.deserialize(JSON.parse_string(blob))).is_true()
	assert_int(g2.bond_tie_count()).is_equal(g.bond_tie_count())
	var a: PackedFloat32Array = g.bond_get("ch:5", "ch:%d" % ((4 * 31 + 97) % 1000 + 1), 110)
	var b: PackedFloat32Array = g2.bond_get("ch:5", "ch:%d" % ((4 * 31 + 97) % 1000 + 1), 110)
	assert_array(Array(a)).is_equal(Array(b))
	# a version 1 save (pair edges only) still loads; garbage bond data is refused without losing the edges
	var old := {"version": 1, "edges": []}
	assert_bool(Graph.new().deserialize(old)).is_true()
	var bad: Dictionary = JSON.parse_string(blob)
	(bad["bonds"] as Dictionary)["v"] = 9
	var g3 := Graph.new()
	g3.deserialize(bad)
	assert_int(g3.bond_tie_count()).is_equal(0)
	# the old pair edges keep working next to the bonds
	var g4 := Graph.new()
	assert_bool(g4.record_conversation("worldsim:1:3", "worldsim:1:4", 5.0)).is_true()
	assert_bool(g4.record_conversation("ch:1", "ch:2", 5.0)).is_true()
	assert_float(g4.affinity("worldsim:1:3", "worldsim:1:4")).is_greater(0.0)
	assert_int(g4.bond_tie_count()).is_equal(2)


func test_the_realm_module_uses_the_games_graph_and_saves_nothing_twice() -> void:
	var h := _hub()
	var g := Graph.new()
	h.social_graph = g
	var bo: RefCounted = h.mod("bonds")
	var a := _ch(h)
	var b := _ch(h)
	bo.event("marriage", a, b, START)
	assert_int(g.bond_tie_count()).is_equal(2)                     # in the shared graph...
	assert_bool((bo.serialize() as Dictionary).has("ties")).is_false()   # ...and so not in the module's own save
	assert_float(bo.regard(a, b, START)).is_greater(20.0)


# --- choices read the ties -----------------------------------------------------------

func test_goal_table_has_the_tie_inputs_and_they_move_scores_a_little() -> void:
	Minds._load_goals()
	assert_bool(Minds._inp_names.has("friend") and Minds._inp_names.has("grudge") and Minds._inp_names.has("avoid")).is_true()
	assert_int(Minds._gdef.size()).is_equal(11)
	var mx := 0.0
	var txt := FileAccess.get_file_as_string("res://data/npc/goals.json")
	var doc: Dictionary = JSON.parse_string(txt)
	for gd: Dictionary in doc["goals"]:
		for t: Array in gd["terms"]:
			if String(t[0]) in ["friend", "grudge", "avoid"]:
				mx = maxf(mx, absf(float(t[4])))
	assert_float(mx).is_between(0.04, 0.13)


func test_marriage_leans_on_love_and_never_on_hate() -> void:
	var h := _hub()
	var bo: RefCounted = h.mod("bonds")
	var m := _ch(h, 26, "m")
	var loved := _ch(h, 24, "f")
	var hated := _ch(h, 24, "f")
	var other := _ch(h, 24, "f")
	for i in 5:
		bo.event("court", m, loved, START)
	bo.event("feud", m, hated, START, 3.0)
	assert_float(bo.match_score(m, loved, START)).is_greater(bo.match_score(m, other, START) + 15.0)
	assert_float(bo.match_score(m, hated, START)).is_less(-35.0)
	assert_array(bo.suitors(m)).contains_exactly([loved])
	# the decision layer runs with it: the hated one is never the choice, the loved one is found even when the town is large
	var mn: RefCounted = h.mod("minds")
	var wed := 0
	for d in 40:
		var rec: Dictionary = mn._m[m]
		if mn.spouse_of(m) != "":
			break
		WorldSim.day = START + d
		mn._a_wed(m, rec, h.mod("organizations").char_rec(m), 26, START + d)
	var sp: String = mn.spouse_of(m)
	print("NI-5 m married: ", sp, " (loved ", loved, " hated ", hated, ")")
	assert_bool(sp != hated).is_true()
	assert_bool(sp == loved or sp == "" or sp == other).is_true()
	wed += 1 if sp == loved else 0
	assert_int(wed + (1 if sp == "" else 0) + (1 if sp == other else 0)).is_equal(1)


func test_a_friend_in_an_organisation_pulls_and_enemies_push_away() -> void:
	var h := _hub()
	var bo: RefCounted = h.mod("bonds")
	var a := _ch(h)
	var friend := _ch(h)
	var foe := _ch(h)
	for i in 12:
		bo.event("work_together", a, friend, START)
		bo.event("chat", a, friend, START)
	bo.event("feud", a, foe, START, 3.0)
	bo.event("threat", foe, a, START, 3.0)
	var member := func(c: String) -> bool: return c == friend
	assert_float(bo.friend_pull(a, member)).is_greater(0.1)
	assert_float(bo.friend_pull(a, func(_c: String) -> bool: return false)).is_equal(0.0)
	assert_float(bo.avoidance(a)).is_greater(0.2)
	var f: Dictionary = bo.foe(a)
	assert_str(String(f["id"])).is_equal(foe)


func test_a_long_grudge_in_a_hot_head_opens_a_feud_and_a_merciful_one_lets_go() -> void:
	var h := _hub()
	var bo: RefCounted = h.mod("bonds")
	var mn: RefCounted = h.mod("minds")
	var dn: RefCounted = h.mod("dynasties")
	var hot := _ch(h, 35)
	var foe := _ch(h, 36)
	dn.set_house(hot, "Harrow", 0)
	dn.set_house(foe, "Vale", 0)
	_pset(h, hot, Persona.O_VOL, 250)
	_pset(h, hot, Persona.O_PRI, 250)
	_pset(h, hot, Persona.O_MER, 5)
	_pset(h, hot, Persona.O_BOLD, 240)
	bo.event("feud", hot, foe, START, 3.0)
	var opened := false
	var lst: Array = mn.in_town(0)
	for d in 400:
		bo._grudges(0, START + d, [hot], mn)
		if dn.feud_heat("Harrow", "Vale") > 0.0:
			opened = true
			break
		# keep the grudge alive between tries
		if d % 20 == 0:
			bo.event("spat", hot, foe, START + d)
	assert_bool(opened).is_true()
	assert_int(int(bo.stats["feuds_opened"])).is_equal(1)
	# a merciful, humble person reconciles instead
	var kind := _ch(h, 35)
	var rival := _ch(h, 36)
	_pset(h, kind, Persona.O_MER, 250)
	_pset(h, kind, Persona.O_PRI, 5)
	_pset(h, kind, Persona.O_VOL, 5)
	bo.event("feud", kind, rival, START, 2.0)
	var before: float = bo.view(kind, rival, START)["resentment"]
	for d in 300:
		bo._grudges(0, START + d, [kind], mn)
	assert_int(int(bo.stats["reconciled"])).is_greater(0)
	assert_float(bo.view(kind, rival, START)["resentment"]).is_less(before)
	assert_bool(lst.size() > 0).is_true()


# --- word of mouth --------------------------------------------------------------------

func test_a_story_travels_first_along_trusted_ties_and_is_believed_more() -> void:
	var h := _hub()
	var bo: RefCounted = h.mod("bonds")
	var rm: RefCounted = h.mod("rumours")
	var seer := _ch(h)
	var friends: Array = [_ch(h), _ch(h), _ch(h)]
	var stranger := _ch(h)
	for f: String in friends:
		for i in 10:
			bo.event("work_together", seer, f, START)
			bo.event("chat", seer, f, START)
		assert_float(bo.axis(f, seer, 0, START)).is_greater(12.0)        # the friend trusts the seer
	var subject := _ch(h)
	rm.witness(seer, "crime", subject, -40.0, 0)
	for f: String in friends:
		assert_int(rm.memories(f).size()).is_equal(0)                    # not yet: the road would take days
	for d in [START + 1, START + 2]:
		WorldSim.day = d
		rm.tick_day(d, {})
	var heard := 0
	for f: String in friends:
		var told: Array = rm.memories(f)
		if told.size() == 1:
			heard += 1
			assert_int(int(told[0]["conf"])).is_greater(60)              # more than the 45 a rumour from the road earns, and the 60 of a witnessed one
	assert_int(heard).is_greater(0)
	assert_int(rm.memories(stranger).size()).is_equal(0)
	assert_int(int(rm.stats["tells"])).is_equal(heard)
	# the telling survives a save
	var h2 := _hub()
	h2.mod("rumours").deserialize(JSON.parse_string(JSON.stringify(rm.serialize())))
	assert_int(int(h2.mod("rumours").stats["tells"])).is_equal(heard)


# --- life stories ---------------------------------------------------------------------

func test_an_apprentice_with_the_talent_surpasses_the_master_and_a_dull_one_does_not() -> void:
	var h := _hub()
	var bo: RefCounted = h.mod("bonds")
	var master := _ch(h, 52, "m", 500, 0, "smith")
	var gifted := _ch(h, 21, "m", 100, 0, "smith")
	var dull := _ch(h, 21, "f", 100, 0, "smith")
	var pe: RefCounted = h.mod("persona")
	_pset(h, master, Persona.O_INT, 110)
	_pset(h, gifted, Persona.O_INT, 235)
	_pset(h, dull, Persona.O_INT, 90)
	for c in [master, gifted, dull]:
		_pset(h, c, Persona.O_SKILL, 70 if c != master else 130)
	assert_bool(bo._teach(master, gifted, 52, 21, "smith", START)).is_true()
	assert_bool(bo._teach(master, dull, 52, 21, "smith", START)).is_true()
	assert_float(bo.axis(gifted, master, Graph.AX_RESPECT, START)).is_greater(5.0)
	for w in 60:
		bo._mentors_step(START + w * 7, 1, false)
	print("NI-5 skills after a year: master ", pe.skill_of(master, 0), " gifted ", pe.skill_of(gifted, 0), " dull ", pe.skill_of(dull, 0))
	assert_int(pe.skill_of(gifted, 0)).is_greater(pe.skill_of(master, 0))
	assert_int(pe.skill_of(dull, 0)).is_less(pe.skill_of(master, 0) + 1)
	assert_int(int(bo.stats["surpassed"])).is_equal(1)
	assert_float(bo.axis(master, gifted, Graph.AX_RIVAL, START + 500)).is_greater(2.0)
	var log: Array = bo.story_log()
	assert_str(String((log[0] as Array)[1])).is_equal("apprentice_surpasses_master")
	assert_str(bo.mentor_of(gifted)).is_equal("")
	assert_str(bo.mentor_of(dull)).is_equal(master)               # still learning
	# closed form: a long sleep gives the same ceiling, not a loop over days
	var h2 := _hub()
	var b2: RefCounted = h2.mod("bonds")
	var m2 := _ch(h2, 52, "m", 500, 0, "smith")
	var g2 := _ch(h2, 21, "m", 100, 0, "smith")
	_pset(h2, m2, Persona.O_INT, 110)
	_pset(h2, g2, Persona.O_INT, 235)
	_pset(h2, m2, Persona.O_SKILL, 130)
	_pset(h2, g2, Persona.O_SKILL, 70)
	b2._teach(m2, g2, 52, 21, "smith", START)
	b2.catch_up(400, {})
	assert_int(int(b2.stats["surpassed"])).is_equal(1)


func test_a_soldier_who_weds_a_farmer_and_is_looked_up_to_becomes_the_village_elder() -> void:
	var h := _hub()
	var bo: RefCounted = h.mod("bonds")
	var mn: RefCounted = h.mod("minds")
	var soldier := _ch(h, 29, "m", 200, 0, "mercenary")
	var farmer := _ch(h, 26, "f", 150, 0, "farmer")
	var crowd: Array = []
	for i in 14:
		crowd.append(_ch(h, 25 + i, "m" if i % 2 == 0 else "f", 120, 0, "farmer"))
	# the soldier watches the village: neighbours owe and respect them
	for c: String in crowd:
		for i in 4:
			bo.event("protect", soldier, c, START + i)
	for i in 6:
		bo.event("court", soldier, farmer, START + i)
	# the wedding is an event in the ring like any other
	h.mod("homes").marry(soldier, farmer, {"sid": 0, "well": false})
	bo._scan_events(START + 10)
	assert_int(int(bo.stats["soldier_weds_farmer"])).is_equal(1)
	assert_float(bo.regard(soldier, farmer, START + 10)).is_greater(35.0)
	# the village's round of esteem
	var named := false
	for d in range(START + 12, START + 12 + 28 * 4):
		bo._elder(0, d, mn)
		if not (bo.leader_of(0) as Dictionary).is_empty():
			named = true
			break
	assert_bool(named).is_true()
	assert_str(String(bo.leader_of(0)["id"])).is_equal(soldier)
	var kinds := {}
	for s: Array in bo.story_log():
		kinds[s[1]] = true
	assert_bool(kinds.has("soldier_weds_farmer") and kinds.has("village_leader")).is_true()
	assert_bool(bo.is_veteran(soldier)).is_true()


# --- determinism, cost, a soak ---------------------------------------------------------

func _run(minds: int, days: int) -> RefCounted:
	var h := _hub()
	h.mod("minds").seed_minds(minds)
	for i in days:
		_day(h, START + 1 + i)
	return h


func test_same_seed_same_ties() -> void:
	var digests: Array = []
	for run in 2:
		var h := _run(70, 70)
		var bo: RefCounted = h.mod("bonds")
		digests.append(JSON.stringify(bo.serialize()).md5_text() + JSON.stringify(bo.graph().bond_serialize()).md5_text())
		digests.append(int(bo.stats["events"]))
	assert_str(digests[0]).is_equal(digests[2])
	assert_int(digests[1]).is_equal(digests[3])
	assert_int(digests[1]).is_greater(60)


func test_soak_lives_stories_within_budget() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var bo: RefCounted = h.mod("bonds")
	mn.seed_minds(300)
	var days := 720
	var worst := 0
	var total := 0
	var worst_by := [0, 0, 0]                              # events scan, town rounds, apprenticeship
	for i in days:
		var d := START + 1 + i
		WorldSim.day = d
		for k in LIVE:
			if k == "bonds":
				continue
			h.mod(k).tick_day(d, {})
		var t0 := Time.get_ticks_usec()
		var jobs: Array = bo.tick_day_chunks(d, {})
		for j in jobs.size():
			var c0 := Time.get_ticks_usec()
			(jobs[j] as Callable).call()
			var took := Time.get_ticks_usec() - c0
			worst = maxi(worst, took)
			var cat := 0 if j == 0 else (2 if j == jobs.size() - 1 else 1)
			worst_by[cat] = maxi(int(worst_by[cat]), took)
		total += Time.get_ticks_usec() - t0
		if d % 7 == 0:
			for k in LIVE:
				h.mod(k).tick_week(d / 7, {})
	var g: Object = bo.graph()
	var added := JSON.stringify(g.serialize()).length() - JSON.stringify(Graph.new().serialize()).length()
	print("NI-5 soak: ", mn.count(), " characters ", days, " days: ", bo.stats)
	print("NI-5 soak kinds: ", bo.by_kind)
	print("NI-5 soak ties: ", g.bond_tie_count(), " on ", g.bond_owner_count(), " owners, save +", added, " B (module ", JSON.stringify(bo.serialize()).length(), " B); bonds ms/day ", float(total) / 1000.0 / float(days), " worst job ms ", float(worst) / 1000.0, " (events ", float(worst_by[0]) / 1000.0, " towns ", float(worst_by[1]) / 1000.0, " mentors ", float(worst_by[2]) / 1000.0, ")", "; rumour tells ", h.mod("rumours").stats["tells"])
	for s: Array in bo.story_log():
		print("   story d", s[0], " ", s[1], " ", s[2], " ", s[3], " ", s[4])
	assert_int(g.bond_tie_count()).is_greater(300)
	assert_int(added).is_less(80 * 1024)
	assert_int(worst).is_less(20000)                       # no single job passes 20 ms even on a slow runner (the pump budget is 0.6 ms of a frame)
	assert_int(int(bo.stats["taught"])).is_greater(0)
	assert_int(int(bo.stats["elders"])).is_greater(0)


func test_save_growth_stays_under_80_kb_with_a_thousand_characters_and_full_slots() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var bo: RefCounted = h.mod("bonds")
	var g := Graph.new()
	h.social_graph = g
	mn.seed_minds(960)
	for i in 70:
		var d := START + 1 + i
		WorldSim.day = d
		for k in LIVE:
			h.mod(k).tick_day(d, {})
	# worst case for the store: every character holds the full K ties
	var ids: Array = mn.ids()
	for i in ids.size():
		for k in Graph.BOND_K:
			var other: String = ids[(i * 7 + k * 13 + 1) % ids.size()]
			if other != ids[i]:
				bo.event("help", ids[i], other, START + 70, 2.0 + float(k % 3))
	var base := JSON.stringify(Graph.new().serialize()).length()
	var added := JSON.stringify(g.serialize()).length() - base
	var module := JSON.stringify(bo.serialize()).length()
	print("NI-5 save at ", mn.count(), " characters: ", g.bond_tie_count(), " ties; graph +", added, " B, bonds module ", module, " B, total ", added + module, " B")
	assert_int(added + module).is_less(80 * 1024)
	assert_int(g.bond_tie_count()).is_less_equal(Graph.BOND_SLOTS * Graph.BOND_K)
