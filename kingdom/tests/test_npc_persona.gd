extends GdUnitTestSuite
## NI-2 person record (scripts/realm/persona.gd): determinism, bounds, culture biases without determining, drift cap, save round trip and size.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Persona := preload("res://scripts/realm/persona.gd")
const UtilityBrain := preload("res://scripts/population/utility_brain.gd")

static var _world := false


func _hub() -> RefCounted:
	if not _world:
		WorldGen.setup(2024)
		_world = true
	return Hub.new()


func _make(h: RefCounted, n: int, culture := "") -> Array:
	var reg: RefCounted = h.mod("registry")
	var pe: RefCounted = h.mod("persona")
	var out: Array = []
	for i in n:
		var ch: String = reg.mint("ch")
		pe.ensure(ch, i % 8, 1 + i % 3, "", -1, culture)
		out.append(ch)
	return out


func test_same_seed_gives_identical_records() -> void:
	var a := _hub()
	var b := _hub()
	_make(a, 60)
	_make(b, 60)
	assert_bool(a.mod("persona").buf() == b.mod("persona").buf()).is_true()
	assert_dict(a.mod("persona").serialize()).is_equal(b.mod("persona").serialize())


func test_record_fits_the_budget_and_has_every_field() -> void:
	assert_int(Persona.STRIDE).is_less_equal(40)
	var h := _hub()
	var chs := _make(h, 5)
	var v: Dictionary = h.mod("persona").view(chs[0])
	for k in ["birth_sid", "culture", "languages", "education", "intelligence", "boldness", "warmth", "discipline", "volatility", "honesty", "loyalty",
			"piety", "ambition", "mercy", "pride", "traits", "skills"]:
		assert_bool(v.has(k)).is_true()
	assert_array(v["languages"]).contains(["common"])
	assert_int(h.mod("persona").buf().size()).is_equal(5 * Persona.STRIDE)


func test_culture_shifts_the_mean_but_ranges_overlap() -> void:
	var h := _hub()
	var pe: RefCounted = h.mod("persona")
	var cal := _make(h, 300, "caldric")
	var urr := _make(h, 300, "urrokai")
	var mean_c := 0.0
	var mean_u := 0.0
	var max_c := 0
	var min_u := 255
	for i in 300:
		var pc: int = pe.view(cal[i])["piety"]
		var pu: int = pe.view(urr[i])["piety"]
		mean_c += pc
		mean_u += pu
		max_c = maxi(max_c, pc)
		min_u = mini(min_u, pu)
	assert_float(mean_u / 300.0 - mean_c / 300.0).is_greater(5.0)       # the culture leans
	assert_float(mean_u / 300.0 - mean_c / 300.0).is_less(40.0)         # but only leans
	assert_int(min_u).is_less(max_c)                                   # a devout caldric and a lax urrokai both exist
	assert_int(max_c).is_greater(200)
	assert_int(min_u).is_less(60)


func test_same_culture_different_people_differ() -> void:
	var h := _hub()
	var chs := _make(h, 80, "caldric")
	var seen := {}
	for ch: String in chs:
		seen[h.mod("persona").view(ch)["ambition"]] = true
	assert_int(seen.size()).is_greater(30)


func test_children_lean_towards_the_parent() -> void:
	var h := _hub()
	var pe: RefCounted = h.mod("persona")
	var reg: RefCounted = h.mod("registry")
	var pa: String = reg.mint("ch")
	pe.ensure(pa, 0)
	var near := 0.0
	var far := 0.0
	var pv: int = pe.view(pa)["mercy"]
	for i in 120:
		var kid: String = reg.mint("ch")
		pe.ensure(kid, 0, 1, pa)
		near += absf(float(int(pe.view(kid)["mercy"]) - pv))
		var kid2: String = reg.mint("ch")
		pe.ensure(kid2, 0, 1)
		far += absf(float(int(pe.view(kid2)["mercy"]) - pv))
	assert_float(near).is_less(far)


func test_drift_is_capped_per_game_year_and_returns_next_year() -> void:
	var h := _hub()
	var pe: RefCounted = h.mod("persona")
	var ch: String = _make(h, 1)[0]
	var start: int = pe.view(ch)["pride"]
	var moved := 0
	for i in 50:
		moved += absi(pe.nudge(ch, Persona.O_PRI, 3, 400))
	assert_int(moved).is_equal(Persona.DRIFT_CAP)
	assert_int(int(pe.view(ch)["pride"]) - start).is_less_equal(Persona.DRIFT_CAP)
	var next := absi(pe.nudge(ch, Persona.O_PRI, 3, 400 + Persona.YEAR))
	assert_int(next).is_greater(0)


func test_experience_moves_values_and_stays_in_bounds() -> void:
	var h := _hub()
	var pe: RefCounted = h.mod("persona")
	var ch: String = _make(h, 1)[0]
	var before: int = pe.view(ch)["ambition"]
	pe.experience(ch, "business", true, 500)
	assert_int(int(pe.view(ch)["ambition"])).is_greater(before)
	for d in range(0, 400 * 20, Persona.YEAR):
		pe.experience(ch, "business", true, d)
	assert_int(int(pe.view(ch)["ambition"])).is_less_equal(255)


func test_unknown_ids_have_no_record_and_never_error() -> void:
	var h := _hub()
	var pe: RefCounted = h.mod("persona")
	assert_int(pe.ensure("not-an-id", 0)).is_equal(-1)
	assert_int(pe.off("ch:99")).is_equal(-1)
	assert_dict(pe.view("ch:99")).is_empty()
	assert_dict(pe.personality("ch:99")).is_empty()


func test_save_round_trip_through_json_and_size_at_1000_characters() -> void:
	var h := _hub()
	var pe: RefCounted = h.mod("persona")
	var chs := _make(h, 1000)
	pe.nudge(chs[7], Persona.O_MER, -5, 100)
	var text := JSON.stringify(pe.serialize())
	assert_int(text.length()).is_less(50000)
	print("NI-2 persona save at 1000 characters: ", text.length(), " bytes of JSON")
	var h2 := _hub()
	var pe2: RefCounted = h2.mod("persona")
	pe2.deserialize(JSON.parse_string(text))
	assert_int(pe2.count()).is_equal(1000)
	assert_bool(pe2.buf() == pe.buf()).is_true()
	for i in [0, 7, 500, 999]:
		assert_dict(pe2.view(chs[i])).is_equal(pe.view(chs[i]))
	# a dropped person leaves a free slot that is reused and survives the round trip
	pe.drop(chs[3])
	pe2.deserialize(JSON.parse_string(JSON.stringify(pe.serialize())))
	assert_bool(pe2.has(chs[3])).is_false()
	assert_int(pe2.count()).is_equal(999)


func test_an_old_save_without_the_block_recreates_the_same_person() -> void:
	var h := _hub()
	var pe: RefCounted = h.mod("persona")
	var ch: String = _make(h, 1)[0]
	var before: Dictionary = pe.view(ch)
	pe.deserialize({})                                  # a pre-NI-2 save has no persona block
	assert_bool(pe.has(ch)).is_false()
	pe.ensure(ch, 0, 1)                                 # minds makes it on first use, from the same seed
	assert_dict(pe.view(ch)).is_equal(before)


func test_empty_persona_serializes_without_empty_base64_error() -> void:
	var pe := Persona.new()
	var data: Dictionary = pe.serialize()
	assert_str(String(data["ids"])).is_empty()
	assert_str(String(data["b"])).is_empty()
	pe.deserialize(data)
	assert_int(pe.count()).is_equal(0)


func test_utility_brain_personality_is_a_view_of_the_record() -> void:
	var h := _hub()
	var pe: RefCounted = h.mod("persona")
	var ch: String = _make(h, 1)[0]
	var v: Dictionary = pe.view(ch)
	var p: Dictionary = pe.personality(ch)
	assert_float(float(p["courage"])).is_equal_approx(float(v["boldness"]) / 255.0, 0.001)
	assert_float(float(p["lazy"])).is_equal_approx(1.0 - float(v["discipline"]) / 255.0, 0.001)
	for k: String in ["sociable", "lazy", "pious", "greedy", "courage"]:
		assert_float(float(p[k])).is_between(0.0, 1.0)
	# nobody but registry characters has a record: an unknown row keeps the seeded personality
	assert_dict(UtilityBrain.persona_traits(-1)).is_empty()
