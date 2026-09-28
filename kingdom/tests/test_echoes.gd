extends GdUnitTestSuite
## Echoes (scripts/sim/echoes.gd): imprints of powerful souls, limited attunement,
## passive modifiers, a cooldown-gated active call, and Inner World gating.

const Echoes := preload("res://scripts/sim/echoes.gd")


func test_data_has_at_least_twelve_echo_types() -> void:
	var e := Echoes.new()
	assert_int(e.known_types().size()).is_greater_equal(12)
	assert_bool(e._types.has("troll_echo")).is_true()
	assert_bool(e._types.has("bear_echo")).is_true()
	assert_bool(e._types.has("wyvern_echo")).is_true()
	assert_bool(e._types.has("corrupted_wolf_echo")).is_true()


func test_add_echo_records_source_and_day() -> void:
	var e := Echoes.new()
	var r := e.add_echo("troll_echo", "the den-lord troll", 12, 1.0)
	assert_int(e.echoes.size()).is_equal(1)
	assert_str(r["source_name"]).is_equal("the den-lord troll")
	assert_int(r["day"]).is_equal(12)
	assert_bool(e.has_echo(int(r["id"]))).is_true()


func test_attune_limits_grow_with_tier() -> void:
	assert_int(Echoes.attune_limit(1)).is_equal(1)
	assert_int(Echoes.attune_limit(3)).is_equal(2)
	assert_int(Echoes.attune_limit(9)).is_equal(5)
	var e := Echoes.new()
	var a := e.add_echo("troll_echo", "Troll A", 1)
	var b := e.add_echo("bear_echo", "Bear B", 1)
	assert_bool(e.attune(int(a["id"]), 1)["ok"]).is_true()
	var refused := e.attune(int(b["id"]), 1)
	assert_bool(refused["ok"]).is_false()
	assert_str(refused["text"]).contains("only hold")
	assert_bool(e.attune(int(b["id"]), 3)["ok"]).is_true()
	assert_int(e.attuned.size()).is_equal(2)


func test_attune_refuses_unknown_or_duplicate() -> void:
	var e := Echoes.new()
	assert_bool(e.attune(999, 5)["ok"]).is_false()
	var a := e.add_echo("wyvern_echo", "Wyvern", 1)
	e.attune(int(a["id"]), 5)
	assert_bool(e.attune(int(a["id"]), 5)["ok"]).is_false()


func test_modifiers_sum_across_attuned_echoes() -> void:
	var e := Echoes.new()
	var a := e.add_echo("troll_echo", "Troll", 1)
	var b := e.add_echo("bear_echo", "Bear", 1)
	e.attune(int(a["id"]), 5)
	e.attune(int(b["id"]), 5)
	var mods := e.modifiers()
	var expect_regen: float = e.type_info("troll_echo")["modifiers"]["health_regen"]
	assert_float(mods["health_regen"]).is_equal_approx(expect_regen, 0.0001)
	assert_bool(mods.has("carry_weight")).is_true()
	# Unattuning drops its contribution.
	e.unattune(int(a["id"]))
	assert_bool(e.modifiers().has("health_regen")).is_false()


func test_corrupted_wolf_echo_gives_night_sight_and_beast_fear() -> void:
	var e := Echoes.new()
	var a := e.add_echo("corrupted_wolf_echo", "Corrupted Wolf", 1)
	e.attune(int(a["id"]), 3)
	var mods := e.modifiers()
	assert_float(mods["night_sight"]).is_equal_approx(1.0, 0.0001)
	assert_float(mods["beast_fear"]).is_equal_approx(0.2, 0.0001)


func test_echo_call_requires_attunement_and_respects_cooldown() -> void:
	var e := Echoes.new()
	var a := e.add_echo("troll_echo", "Troll", 1)
	var not_attuned := e.echo_call(int(a["id"]), 1)
	assert_bool(not_attuned["ok"]).is_false()
	e.attune(int(a["id"]), 5)
	var first := e.echo_call(int(a["id"]), 1)
	assert_bool(first["ok"]).is_true()
	assert_int(first["cooldown_days"]).is_equal(int(e.type_info("troll_echo")["active"]["cooldown_days"]))
	var again_too_soon := e.echo_call(int(a["id"]), 2)
	assert_bool(again_too_soon["ok"]).is_false()
	var ready_day := int(first["available_again_day"])
	var again := e.echo_call(int(a["id"]), ready_day)
	assert_bool(again["ok"]).is_true()


func test_inner_world_gated_by_tier() -> void:
	var e := Echoes.new()
	assert_bool(e.inner_world_unlocked(8)).is_false()
	assert_bool(e.inner_world_unlocked(9)).is_true()
	var locked := e.inner_world_state(8)
	assert_bool(locked["unlocked"]).is_false()
	assert_array(locked["landmarks"]).is_empty()


func test_inner_world_state_reflects_attuned_echoes_and_bonds() -> void:
	var e := Echoes.new()
	var a := e.add_echo("mentor_echo", "Old Kessa", 1)
	e.attune(int(a["id"]), 9)
	var bonds := [{"kind": "person", "target_name": "Edda Brook"}, {"kind": "monster", "target_name": "Fenra"}]
	var state := e.inner_world_state(9, "the Path of Ember", bonds)
	assert_bool(state["unlocked"]).is_true()
	assert_str(state["biome"]).contains("the Path of Ember")
	assert_int(state["landmarks"].size()).is_equal(1)
	assert_str(state["landmarks"][0]).contains("Old Kessa")
	assert_int(state["residents"].size()).is_equal(1)
	assert_str(state["residents"][0]["name"]).is_equal("Edda Brook")


func test_echoes_roundtrip() -> void:
	var e := Echoes.new()
	var a := e.add_echo("troll_echo", "Troll", 1)
	var b := e.add_echo("mentor_echo", "Kessa", 2)
	e.attune(int(a["id"]), 5)
	e.echo_call(int(a["id"]), 2)
	var d := Echoes.new()
	d.deserialize(JSON.parse_string(JSON.stringify(e.serialize())))
	assert_int(d.echoes.size()).is_equal(2)
	assert_int(d.attuned.size()).is_equal(1)
	assert_bool(d.attuned.has(int(a["id"]))).is_true()
	assert_int(d.last_call_day[int(a["id"])]).is_equal(2)
	# Cooldown state carried over: calling again too soon is still refused.
	assert_bool(d.echo_call(int(a["id"]), 3)["ok"]).is_false()
	assert_str(d.echo(int(b["id"]))["source_name"]).is_equal("Kessa")
