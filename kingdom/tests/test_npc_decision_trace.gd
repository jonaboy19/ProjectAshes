extends GdUnitTestSuite
## NI-3 shared scorer + decision trace: utility_core agrees with the brain's table, goals come from data, traces exist for the near tier only.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Core := preload("res://scripts/sim/utility_core.gd")
const UtilityBrain := preload("res://scripts/population/utility_brain.gd")
const LIVE := ["registry", "events", "news", "organizations", "businesses", "emergence", "faith", "dynasties", "homes", "minds", "rumours"]
const START := 600

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
	for k in ["farming", "businesses", "homes"]:
		if h.mod(k).has_method("set_day"):
			h.mod(k).set_day(START)
	h.mod("businesses").set_population(0, 800)
	om.set_day(START)
	return h


func _day(h: RefCounted, d: int) -> void:
	WorldSim.day = d
	for k in LIVE:
		h.mod(k).tick_day(d, {})


func _town(mn: RefCounted) -> int:
	var best := -1
	var n := 0
	for ch: String in mn.ids():
		var s: int = mn.town_of(ch)
		if mn.town_count(s) > n:
			n = mn.town_count(s)
			best = s
	return best


func test_core_curves_match_the_brain() -> void:
	for kind in 5:
		for x in [0.0, 0.3, 0.7, 1.0]:
			assert_float(UtilityBrain.curve(kind, x, 0.8, 0.2)).is_equal(Core.curve(kind, x, 0.8, 0.2))


func test_core_product_equals_the_brain_score_for_every_act() -> void:
	var ctx := UtilityBrain.make_context(13.0, {"hungry": 0.8, "tired": 0.2})
	for a: int in UtilityBrain.ACTIONS:
		var def: Array = UtilityBrain.ACTIONS[a]
		var direct: float = Core.product(def[0], def[1], ctx)
		var score: float = UtilityBrain.score(a, ctx)
		if a != UtilityBrain.Act.FLEE and a != UtilityBrain.Act.WATCH:
			assert_float(score).is_equal(direct)


func test_core_evaluate_gates_and_terms() -> void:
	var gates := Core.pack([[0, Core.OP_GE, 5.0], [1, Core.OP_EQ, 1.0]])
	var terms := Core.pack([[2, Core.Resp.LINEAR, 1.0, 0.0, 0.5], [3, Core.Resp.LINEAR, 1.0, 0.0, -0.1]])
	var inp := PackedFloat32Array([6.0, 1.0, 0.4, 1.0])
	assert_float(Core.evaluate(0.2, gates, terms, inp)).is_equal_approx(0.2 + 0.2 - 0.1, 0.0001)
	inp[0] = 4.0
	assert_float(Core.evaluate(0.2, gates, terms, inp)).is_equal(Core.GATE_FAIL)
	assert_int(Core.top_term(terms, PackedFloat32Array([6.0, 1.0, 0.4, 1.0]))).is_equal(0)


func test_goals_come_from_the_data_file() -> void:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/npc/goals.json"))
	assert_bool(doc is Dictionary).is_true()
	var ids: Array = []
	for g: Dictionary in doc["goals"]:
		ids.append(g["id"])
		assert_bool(preload("res://scripts/realm/minds.gd").GOALS.has(g["id"])).is_true()
	assert_int(ids.size()).is_equal(11)                                      # every goal but idle
	var inputs: Array = []
	for k: String in preload("res://scripts/realm/minds.gd").I.keys():
		inputs.append(k.to_lower())
	for g: Dictionary in doc["goals"]:
		for r: Array in g["gates"]:
			assert_bool(inputs.has(r[0])).is_true()
		for r: Array in g["terms"]:
			assert_bool(inputs.has(r[0])).is_true()


func test_trace_is_near_tier_only_bounded_and_explains_each_candidate() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	mn.seed_minds(60)
	var sid := _town(mn)
	mn.set_focus(sid)
	for i in 6:
		_day(h, START + 1 + i)
	var some := 0
	for ch: String in mn.ids():
		var tr: Array = mn.trace(ch)
		if mn.town_of(ch) != sid:
			assert_array(tr).is_empty()
			continue
		assert_int(tr.size()).is_less_equal(3)
		if tr.size() > 1:
			assert_int(int(tr[0]["day"])).is_greater(int(tr[1]["day"]))            # newest first
		for e: Dictionary in tr:
			var prev := 1.0e9
			for row: Dictionary in e["scores"]:
				assert_float(float(row["score"])).is_less_equal(prev)              # best candidate first
				prev = float(row["score"])
				assert_str(String(row["why"])).is_not_empty()
			if not (e["scores"] as Array).is_empty() and String(e["goal"]) != "idle":
				assert_str(String((e["scores"] as Array)[0]["goal"])).is_equal(String(e["goal"]))   # the chosen goal led the list
			some += 1
	assert_int(some).is_greater(0)


func test_tracing_never_changes_what_people_decide() -> void:
	var goals: Array = []
	for on in [true, false]:
		var h := _hub()
		var mn: RefCounted = h.mod("minds")
		mn.trace_on = on
		mn.seed_minds(60)
		mn.set_focus(_town(mn))
		for i in 5:
			_day(h, START + 1 + i)
		var g := {}
		for ch: String in mn.ids():
			g[ch] = mn.goal_of(ch)
		goals.append(g)
		if not on:
			for ch: String in mn.ids():
				assert_array(mn.trace(ch)).is_empty()
	assert_dict(goals[0]).is_equal(goals[1])


func test_a_remembered_crime_makes_a_witness_fearful_and_a_bold_one_less_so() -> void:
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	mn.seed_minds(40)
	var sid := _town(mn)
	mn.set_focus(sid)
	h.mod("registry").ref("pl:player")
	_day(h, START + 1)
	var rm: RefCounted = h.mod("rumours")
	var pl: String = h.mod("registry").lookup("pl:player")
	var w: String = mn.in_town(sid)[0]
	var before: Vector3 = rm.felt(w, pl)
	rm.note_player("crime", sid, -45.0, [w])
	var after: Vector3 = rm.felt(w, pl)
	assert_float(before.x).is_equal(0.0)
	assert_float(after.x).is_less(-20.0)
	assert_float(after.z).is_greater(0.3)


func test_compiled_goal_table_agrees_with_the_interpreted_one() -> void:
	# utility_core.compile writes straight-line code from the same tables; it must pick what Core.evaluate picks, on any input.
	var Minds := preload("res://scripts/realm/minds.gd")
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	mn._load_goals()
	assert_object(Minds._gfast).is_not_null()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var inp := PackedFloat32Array()
	inp.resize(Minds.I.COUNT)
	var picked := {}
	for n in 3000:
		for k in Minds.I.COUNT:
			inp[k] = [0.0, 1.0, rng.randf(), rng.randf() * 100.0, rng.randf_range(-0.1, 0.1), float(rng.randi_range(0, 400))][rng.randi() % 6]
		inp[Minds.I.AGE] = float(rng.randi_range(10, 80))
		var best := 0
		var bs: float = Minds._gthr
		for gd: Array in Minds._gdef:
			var u: float = Core.evaluate(gd[1], gd[2], gd[3], inp)
			if u > bs and u > Core.GATE_FAIL:
				bs = u
				best = gd[0]
		assert_int(int(Minds._gfast.pick(inp))).is_equal(best)
		picked[best] = true
	assert_int(picked.size()).is_greater(4)           # the random inputs actually reach several goals
