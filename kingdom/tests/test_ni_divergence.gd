extends GdUnitTestSuite
## NI-1 divergence harness (docs/design/NPC_INTELLIGENCE_MAP.md section 5, "NI-1. Divergence test harness").
## Two realm hubs from the same seed live the same days; one of them gets one player choice on day 1. Asserts that NPC-level outcomes
## (goals, memories, opinions, rumour claims) then differ, and that identical inputs give identical state. Cases that need hooks
## which do not exist yet are marked pending with do_skip and the NI item that adds the hook; they are not faked as passes.
## Budget: under 2 s per case in the container (about 60 days over 90 minds).

const Hub := preload("res://scripts/realm/realm_hub.gd")
const UtilityBrain := preload("res://scripts/population/utility_brain.gd")
const LIVE := ["registry", "events", "news", "organizations", "businesses", "emergence", "faith", "dynasties", "homes", "minds", "rumours"]
const START := 600
const DAYS := 60
const MINDS := 90
const FIXTURE := 40
const GOALS_NEEDED := 3

static var _ready_world := false


func _hub() -> RefCounted:
	if not _ready_world:
		WorldGen.setup(2024)
		_ready_world = true
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
	# the player exists, so a player choice can be told as news and remembered
	var reg: RefCounted = h.mod("registry")
	reg.ref("pl:player")
	return h


func _live_day(h: RefCounted, d: int) -> void:
	WorldSim.day = d
	for k in LIVE:
		h.mod(k).tick_day(d, {})
	if d % 7 == 0:
		for k in LIVE:
			h.mod(k).tick_week(d / 7, {})


## Runs `days` days of the living modules. `perturb` (optional) is called once, before day one, with the hub.
func _run(n_minds: int, days: int, perturb := Callable()) -> RefCounted:
	var h := _hub()
	h.mod("minds").seed_minds(n_minds)
	if perturb.is_valid():
		perturb.call(h)
	for i in days:
		_live_day(h, START + 1 + i)
	return h


func _digest(h: RefCounted) -> Dictionary:
	var s := {}
	for k in LIVE:
		s[k] = JSON.stringify(h.mod(k).serialize()).md5_text()
	s["minds_stats"] = JSON.stringify(h.mod("minds").stats).md5_text()
	return s


func _goals(h: RefCounted) -> Dictionary:
	var out := {}
	var mn: RefCounted = h.mod("minds")
	for ch: String in mn.ids():
		out[ch] = mn.goal_of(ch)
	return out


## The town with the most minds (so a crime there has several witnesses).
func _busiest_town(mn: RefCounted) -> int:
	var count := {}
	for ch: String in mn.ids():
		count[mn.town_of(ch)] = int(count.get(mn.town_of(ch), 0)) + 1
	var best := -1
	for sid: int in count:
		if best == -1 or count[sid] > count[best]:
			best = sid
	return best


func _distinct(values: Array) -> int:
	var seen := {}
	for v: Variant in values:
		seen[v] = true
	return seen.size()


# --- determinism ------------------------------------------------------------------------

func test_same_seed_same_inputs_gives_identical_state() -> void:
	var a := _run(MINDS, DAYS)
	var b := _run(MINDS, DAYS)
	assert_dict(_digest(a)).is_equal(_digest(b))
	assert_dict(_goals(a)).is_equal(_goals(b))
	assert_int(int(a.mod("minds").stats["decisions"])).is_greater(100)   # the run actually made decisions


func test_identical_fixture_built_twice_gives_identical_goals() -> void:
	var goals: Array = []
	for run in 2:
		var h := _fixture_hub()
		_live_day(h, START + 1)
		_live_day(h, START + 2)
		_live_day(h, START + 3)
		goals.append(_goals(h))
	assert_dict(goals[0]).is_equal(goals[1])


# --- divergence -------------------------------------------------------------------------

## NI-1 fixture: FIXTURE people with identical age, cash, town, house and no spouse. Only the person id (the seed) differs.
func _fixture_hub() -> RefCounted:
	var h := _hub()
	var om: RefCounted = h.mod("organizations")
	var mn: RefCounted = h.mod("minds")
	var reg: RefCounted = h.mod("registry")
	for i in FIXTURE:
		var ch: String = reg.mint("ch")
		om.ensure_char(ch, {"cash": 500, "sid": 0, "prof": "smith", "npc": true, "amb": "found"})
		mn.adopt(ch, 30, "m", "")
	return h


func test_identical_fixture_reaches_at_least_three_distinct_goals() -> void:
	var h := _fixture_hub()
	var goals_seen: Array = []
	for i in 3:
		_live_day(h, START + 1 + i)
		for ch: String in _goals(h).keys():
			goals_seen.append(_goals(h)[ch])
	assert_int(_distinct(goals_seen)).is_greater_equal(GOALS_NEEDED)


func test_a_player_crime_in_town_leaves_different_memories_and_opinions_in_its_witnesses() -> void:
	var plan := {"witnesses": [], "sid": -1}
	var perturb := func(h: RefCounted) -> void:
		var mn: RefCounted = h.mod("minds")
		var sid: int = _busiest_town(mn)
		var ids: Array = mn.in_town(sid)
		plan["sid"] = sid
		plan["witnesses"] = ids.slice(0, mini(8, ids.size()))
		h.mod("rumours").note_player("crime", sid, -45.0, plan["witnesses"])
	var base := _run(MINDS, DAYS)
	var hit := _run(MINDS, DAYS, perturb)
	var witnesses: Array = plan["witnesses"]
	assert_int(witnesses.size()).is_greater(0)
	var rm_base: RefCounted = base.mod("rumours")
	var rm_hit: RefCounted = hit.mod("rumours")
	var pl := String(hit.mod("registry").lookup("pl:player"))
	var changed_memory := 0
	var changed_opinion := 0
	for w: String in witnesses:
		if JSON.stringify(rm_base.memories(w)) != JSON.stringify(rm_hit.memories(w)):
			changed_memory += 1
		if absf(rm_base.opinion(w, pl, int(plan["sid"])) - rm_hit.opinion(w, pl, int(plan["sid"]))) > 0.001:
			changed_opinion += 1
	print("NI-1 witnesses ", witnesses.size(), " changed memory ", changed_memory, " changed opinion ", changed_opinion)
	assert_int(changed_memory).is_greater_equal(1)
	assert_int(changed_opinion).is_greater_equal(1)


func test_a_player_crime_changes_at_least_three_npc_goals() -> void:
	# NI-3: minds._choose scores the town's view of the player and the bad news a character remembers (fear), through data/npc/goals.json.
	var perturb := func(h: RefCounted) -> void:
		var mn: RefCounted = h.mod("minds")
		var sid: int = _busiest_town(mn)
		h.mod("rumours").note_player("crime", sid, -45.0, mn.in_town(sid).slice(0, 8))
	var base := _goals(_run(MINDS, DAYS))
	var hit := _goals(_run(MINDS, DAYS, perturb))
	var changed := 0
	for ch: String in base.keys():
		if hit.has(ch) and hit[ch] != base[ch]:
			changed += 1
	print("NI-1 goals changed by one player crime: ", changed, " of ", base.size())
	assert_int(changed).is_greater_equal(GOALS_NEEDED)


# --- utility brain (passes today) -------------------------------------------------------

func test_utility_brain_different_personalities_choose_different_acts_in_the_same_situation() -> void:
	# Passes on current code: the personality traits feed the response-curve scorer directly. Sweep a few situations
	# (hour x need profile); each one must give the same act for the same traits, and some situation must split the 40 people.
	var situations := [{}, {"hungry": 0.9}, {"tired": 0.9}, {"partner": 1.0, "lonely": 0.9}, {"money": 0.9}, {"faithless": 0.9}, {"thirst": 0.9}, {"rest": 0.1}]
	var best_spread := 0
	var best_case := ""
	for over: Dictionary in situations:
		for hour: float in [6.0, 9.0, 13.0, 19.0, 22.0]:
			var acts: Array = []
			for p in range(40):
				var tr: Dictionary = UtilityBrain.personality(p)
				var act: int = UtilityBrain.best(UtilityBrain.make_context(hour, over, tr))
				assert_int(UtilityBrain.best(UtilityBrain.make_context(hour, over, tr))).is_equal(act)   # same traits, same act
				acts.append(act)
			var spread := _distinct(acts)
			if spread > best_spread:
				best_spread = spread
				best_case = "%s @ %.0fh" % [str(over), hour]
	print("NI-1 utility_brain widest split: ", best_spread, " acts in ", best_case)
	assert_int(best_spread).is_greater_equal(2)


# --- pending: hooks that do not exist yet ----------------------------------------------

func test_person_record_has_birth_culture_and_intelligence() -> void:
	# NI-2: realm/persona.gd holds the record (the registry keeps only the id and the saved trait words, persona is the source of truth).
	var h := _hub()
	var ch: String = h.mod("minds").ensure_row(5)
	assert_str(ch).is_not_empty()
	var person: Dictionary = h.mod("persona").view(ch)
	assert_bool(person.has("birth_sid")).is_true()
	assert_bool(person.has("culture")).is_true()
	assert_bool(person.has("intelligence")).is_true()
	assert_int(int(person["birth_sid"])).is_greater_equal(0)
	assert_str(String(person["culture"])).is_not_empty()
	assert_array(h.mod("registry").traits_of(ch)).is_equal(person["traits"])


func test_decision_trace_names_the_inputs_of_each_goal() -> void:
	# NI-3: the near tier (the town the player is in) keeps its last decisions with the candidates and the input that drove each score.
	var h := _hub()
	var mn: RefCounted = h.mod("minds")
	mn.seed_minds(20)
	var sid: int = _busiest_town(mn)
	mn.set_focus(sid)
	for i in 4:
		_live_day(h, START + 1 + i)
	var near: Array = mn.in_town(sid)
	assert_int(near.size()).is_greater(0)
	var traced := 0
	for ch: String in near:
		var trace: Array = mn.trace(ch)
		if trace.is_empty():
			continue
		traced += 1
		assert_int(trace.size()).is_less_equal(3)
		var last: Dictionary = trace[0]
		assert_bool(last.has("goal") and last.has("scores") and last.has("day")).is_true()
		for row: Dictionary in last["scores"]:
			assert_str(String(row["why"])).is_not_empty()
			assert_bool(row.has("goal") and row.has("score")).is_true()
	assert_int(traced).is_greater(0)
	# far characters keep no trace
	mn.set_focus(-1)
	for ch: String in mn.ids():
		if mn.town_of(ch) != sid:
			assert_array(mn.trace(ch)).is_empty()
