extends GdUnitTestSuite
## NI-4 + MW-2 (scripts/realm/psyche.gd): memories with emotional weight, witnesses and reliability; per-person mood that decays in closed form;
## appraisal (the same event leaves different people differently); trait drift under the yearly cap; mood feeding goal scores; save and determinism.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Persona := preload("res://scripts/realm/persona.gd")
const Psyche := preload("res://scripts/realm/psyche.gd")
const Minds := preload("res://scripts/realm/minds.gd")
const Core := preload("res://scripts/sim/utility_core.gd")

static var _world := false


func test_empty_psyche_serializes_without_empty_base64_error() -> void:
	var psyche := Psyche.new()
	var data: Dictionary = psyche.serialize()
	assert_int(int(data["z"])).is_equal(0)
	assert_str(String(data["d"])).is_empty()
	psyche.deserialize(data)


func _hub() -> RefCounted:
	if not _world:
		WorldGen.setup(2024)
		_world = true
	WorldSim.day = 600
	var h: RefCounted = Hub.new()
	h.mod("minds").auto_seed = false
	h.mod("faith").auto_seed = false
	return h


## A character with chosen temperament: bold, disc, vol and mercy set directly in the packed person record.
func _person(h: RefCounted, bold: int, disc: int, vol: int, mercy := 128) -> String:
	var ch: String = h.mod("registry").mint("ch")
	var pe: RefCounted = h.mod("persona")
	var o: int = pe.ensure(ch, 0)
	pe._buf[o + Persona.O_BOLD] = bold
	pe._buf[o + Persona.O_DISC] = disc
	pe._buf[o + Persona.O_VOL] = vol
	pe._buf[o + Persona.O_MER] = mercy
	return ch


func test_two_farmers_survive_the_same_raid_and_diverge() -> void:
	var h := _hub()
	var ps: RefCounted = h.mod("psyche")
	var steady := _person(h, 220, 200, 40)
	var fragile := _person(h, 40, 60, 200)
	for ch in [steady, fragile]:
		assert_bool(ps.experience(ch, "raid", 0.8, 1.0, 5, 100)).is_true()
	var a: Dictionary = ps.mood(steady, 100)
	var b: Dictionary = ps.mood(fragile, 100)
	assert_float(b["fear"]).is_greater(a["fear"] + 0.1)
	assert_float(a["confidence"]).is_greater(b["confidence"] + 0.1)
	# the fear outlasts: two months on the steady farmer is back to baseline and the fragile one is not
	var da: PackedFloat32Array = ps.devs(steady, 160)
	var da_fear := float(da[1])
	var db_fear := float(ps.devs(fragile, 160)[1])
	print("NI-4 fear deviation after 60 days: steady ", da_fear, " fragile ", db_fear)
	assert_float(db_fear).is_greater(da_fear * 3.0)
	assert_float(db_fear).is_greater(0.08)
	# the memory is heavier for the one it hurt more
	var ma: Array = ps.memories(steady, 100)
	var mb: Array = ps.memories(fragile, 100)
	assert_int(ma.size()).is_equal(1)
	assert_int(int(mb[0]["weight"])).is_greater(int(ma[0]["weight"]))
	assert_float(ps.scar(fragile, 160)).is_greater(ps.scar(steady, 160))


func test_memory_keeps_witnesses_and_reliability_and_heard_events_weigh_less() -> void:
	var h := _hub()
	var ps: RefCounted = h.mod("psyche")
	var seen := _person(h, 128, 128, 128)
	var told := _person(h, 128, 128, 128)
	ps.experience(seen, "crime", 0.7, 1.0, 6, 50)
	ps.experience(told, "crime", 0.7, 0.45, 1, 50)
	var ms: Dictionary = (ps.memories(seen, 50) as Array)[0]
	var mt: Dictionary = (ps.memories(told, 50) as Array)[0]
	assert_int(int(ms["witnesses"])).is_equal(6)
	assert_float(ms["reliability"]).is_equal_approx(1.0, 0.01)
	assert_float(mt["reliability"]).is_between(0.35, 0.55)
	assert_int(int(ms["weight"])).is_equal(int(mt["weight"]))                    # same event, same person type: the telling changes certainty, not size...
	assert_float(ps.mood(told, 50)["fear"]).is_less(ps.mood(seen, 50)["fear"])  # ...but a second-hand fright frightens less
	assert_bool(ms["bad"]).is_true()
	assert_float(ms["salience"]).is_greater(mt["salience"])


func test_memory_is_bounded_and_insignificant_ones_compress() -> void:
	var h := _hub()
	var ps: RefCounted = h.mod("psyche")
	var ch := _person(h, 128, 128, 128)
	for i in 30:                                             # thirty petty trades: one memory
		ps.experience(ch, "trade", 0.12, 1.0, 1, 10 + i)
	assert_int((ps.memories(ch, 40) as Array).size()).is_equal(1)
	for i in 12:
		ps.experience(ch, ["raid", "death", "battle", "famine", "emergency", "crime"][i % 6], 0.5 + 0.04 * i, 1.0, 3, 50 + i)
	var ms: Array = ps.memories(ch, 70)
	assert_int(ms.size()).is_equal(Psyche.MEM_N)
	assert_int(Psyche.STRIDE).is_less_equal(40)
	assert_int(int(ps.stats["merged"])).is_greater_equal(29)


func test_mood_decays_in_closed_form_and_catch_up_changes_nothing() -> void:
	var h := _hub()
	var ps: RefCounted = h.mod("psyche")
	var ch := _person(h, 100, 100, 100)
	ps.experience(ch, "death", 1.0, 1.0, 2, 10)
	var base: Dictionary = ps.mood(ch, 10000)
	var g0: float = ps.mood(ch, 10)["grief"]
	var prev := g0
	for d in [20, 60, 120, 300]:
		var g: float = ps.mood(ch, 10 + d)["grief"]
		assert_float(g).is_less(prev)
		prev = g
	assert_float(prev).is_less(g0 * 0.2)
	assert_float(base["grief"]).is_less(0.01)                # long after, only the baseline is left
	assert_float(ps.mood(ch, 10)["grief"]).is_greater(0.3)
	var before: Dictionary = ps.mood(ch, 200)
	ps.catch_up(150, {})
	assert_dict(ps.mood(ch, 200)).is_equal(before)
	for k in Psyche.DIMS:                                    # always inside 0..1
		assert_float(before[k]).is_between(0.0, 1.0)


func test_values_drift_by_who_you_are_and_never_past_the_yearly_cap() -> void:
	var h := _hub()
	var ps: RefCounted = h.mod("psyche")
	var pe: RefCounted = h.mod("persona")
	var bold := _person(h, 230, 200, 40, 220)
	var meek := _person(h, 30, 60, 200, 30)
	var b0: int = pe.view(bold)["boldness"]
	var m0: int = pe.view(meek)["boldness"]
	ps.experience(bold, "crime", 0.9, 1.0, 4, 100)
	ps.experience(meek, "crime", 0.9, 1.0, 4, 100)
	assert_int(int(pe.view(bold)["boldness"])).is_greater(b0)       # hardened
	assert_int(int(pe.view(meek)["boldness"])).is_less(m0)          # broken
	assert_int(int(pe.view(bold)["mercy"])).is_greater(220 - 1)
	assert_int(int(pe.view(meek)["mercy"])).is_less(30)
	var kinds := ["raid", "battle", "crime", "famine", "emergency", "death"]
	var snap: Dictionary = pe.view(meek)
	for i in 40:                                                    # a terrible year
		ps.experience(meek, kinds[i % 6], 1.0, 1.0, 3, 101 + i * 3)
	var moved := 0
	var after: Dictionary = pe.view(meek)
	for k in Persona.FIELD:
		moved += absi(int(after[k]) - int(snap[k]))
	print("NI-4 drift points in one year: ", moved)
	assert_int(moved).is_less_equal(Persona.DRIFT_CAP)


func test_rumour_memories_feed_the_mood_of_witnesses_and_believers() -> void:
	var h := _hub()
	var rm: RefCounted = h.mod("rumours")
	var ps: RefCounted = h.mod("psyche")
	var w := _person(h, 40, 60, 200)
	var subject: String = h.mod("registry").mint("ch")
	rm.witness(w, "crime", subject, -60.0, 0)
	assert_bool(ps.has(w)).is_true()
	assert_float(float(ps.devs(w, 600)[1])).is_greater(0.05)
	var mem: Array = ps.memories(w, 600)
	assert_int(mem.size()).is_equal(1)
	assert_bool(mem[0]["bad"]).is_true()


func _run_events(h: RefCounted, n: int) -> void:
	var ps: RefCounted = h.mod("psyche")
	var kinds := ["raid", "death", "marriage", "crime", "trade", "battle"]
	for i in n:
		var ch: String = "ch:%d" % (900000 + i % 40)
		ps.experience(ch, kinds[i % 6], 0.2 + 0.1 * float(i % 7), 1.0 if i % 3 != 0 else 0.5, 1 + i % 5, 300 + i)


func test_same_events_give_identical_state_and_save_round_trips() -> void:
	var a := _hub()
	var b := _hub()
	_run_events(a, 200)
	_run_events(b, 200)
	assert_dict(a.mod("psyche").serialize()).is_equal(b.mod("psyche").serialize())
	assert_dict(a.mod("persona").serialize()).is_equal(b.mod("persona").serialize())
	var saved: Dictionary = JSON.parse_string(JSON.stringify(a.mod("psyche").serialize()))
	var c := _hub()
	c.mod("persona").deserialize(JSON.parse_string(JSON.stringify(a.mod("persona").serialize())))
	c.mod("psyche").deserialize(saved)
	for i in 40:
		var ch := "ch:%d" % (900000 + i)
		assert_dict(c.mod("psyche").mood(ch, 700)).is_equal(a.mod("psyche").mood(ch, 700))
		assert_array(c.mod("psyche").memories(ch, 700)).is_equal(a.mod("psyche").memories(ch, 700))
	assert_int(c.mod("psyche").count()).is_equal(a.mod("psyche").count())


func test_save_stays_under_60kb_at_a_thousand_characters_and_costs_little() -> void:
	var h := _hub()
	var ps: RefCounted = h.mod("psyche")
	var kinds := ["raid", "death", "marriage", "crime", "trade", "battle", "famine", "birth"]
	var t0 := Time.get_ticks_usec()
	for i in 1000:
		var ch: String = "ch:%d" % (800000 + i)
		for k in 7:
			ps.experience(ch, kinds[(i + k) % 8], 0.3 + 0.1 * float((i * 7 + k) % 6), 1.0, 1 + k, 100 + k * 9)
	var make_us := Time.get_ticks_usec() - t0
	var json := JSON.stringify(h.mod("psyche").serialize())
	var persona_bytes := JSON.stringify(h.mod("persona").serialize()).length()
	print("NI-4 psyche save at 1000 characters: ", json.length(), " bytes (persona ", persona_bytes, "); 7000 experiences ", make_us / 1000, " ms")
	assert_int(json.length()).is_less(60000)
	assert_int(ps.count()).is_equal(1000)
	# reading the mood for decisions
	var t1 := Time.get_ticks_usec()
	var sum := 0.0
	for r in 5:
		for i in 1000:
			sum += ps.devs("ch:%d" % (800000 + i), 200)[0]
	print("NI-4 devs() ", (Time.get_ticks_usec() - t1) / 5000.0, " us per call")
	assert_int(Time.get_ticks_usec() - t1).is_less(400000)
	var t2 := Time.get_ticks_usec()
	for w in 4:
		ps.tick_week(w, {})
	print("NI-4 tick_week x4 (whole table once): ", Time.get_ticks_usec() - t2, " us")


func test_mood_shifts_a_decision() -> void:
	Minds._load_goals()
	var gdef: Array = Minds._gdef
	# a settled, grieving adult who could petition or enlist: anger decides between them
	var calm := PackedFloat32Array()
	calm.resize(Minds.I.COUNT)
	calm[Minds.I.AGE] = 26.0
	calm[Minds.I.AGE21] = 1.0
	calm[Minds.I.OPEN] = 1.0
	calm[Minds.I.TIED] = 0.25
	calm[Minds.I.GRIEF] = 0.7
	calm[Minds.I.PETITION_SCOPE] = 1.0
	calm[Minds.I.WORK_OR_POOR] = 1.0
	calm[Minds.I.ARMS] = 1.0
	calm[Minds.I.MONEY] = 0.5
	var angry := calm.duplicate()
	angry[Minds.I.ANGER_D] = 0.5
	var h := _hub()
	var m1: RefCounted = h.mod("minds")
	var g_calm: int = m1._pick_slow(calm)
	var g_angry: int = m1._pick_slow(angry)
	print("NI-4 goal calm ", Minds.GOALS[g_calm], " angry ", Minds.GOALS[g_angry])
	assert_int(g_angry).is_not_equal(g_calm)
	assert_str(Minds.GOALS[g_angry]).is_equal("petition")
	# the weights are bounded: no mood alone moves a score by more than 0.25
	for gd: Array in gdef:
		var worst := absf(Core.evaluate(gd[1], gd[2], gd[3], angry) - Core.evaluate(gd[1], gd[2], gd[3], calm))
		assert_float(worst).is_less(0.25)


func test_real_minds_read_the_mood_of_a_traumatised_character() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	var ps: RefCounted = h.mod("psyche")
	mn.seed_minds(30)
	var sid := -1
	var best := 0
	var count := {}
	for ch: String in mn.ids():
		count[mn.town_of(ch)] = int(count.get(mn.town_of(ch), 0)) + 1
		if int(count[mn.town_of(ch)]) > best:
			best = int(count[mn.town_of(ch)])
			sid = mn.town_of(ch)
	mn.set_focus(sid)
	var victim: String = mn.in_town(sid)[0]
	var day := 601
	WorldSim.day = day
	ps.experience(victim, "raid", 1.0, 1.0, 4, day)
	ps.experience(victim, "death", 1.0, 1.0, 4, day)
	mn.decide(victim, day)
	var ring: Array = mn._trace.get(victim, [])
	assert_int(ring.size()).is_greater(0)
	var vec: PackedFloat32Array = (ring.back() as Array)[2]
	print("NI-4 inputs seen by minds: stress_d ", vec[Minds.I.STRESS_D], " fear_d ", vec[Minds.I.FEAR_D], " grief_d ", vec[Minds.I.GRIEF_D], " scar ", vec[Minds.I.SCAR])
	assert_float(vec[Minds.I.STRESS_D]).is_greater(0.05)
	assert_float(vec[Minds.I.GRIEF]).is_greater(0.2)
	assert_float(vec[Minds.I.SCAR]).is_greater(0.05)
