extends GdUnitTestSuite
## F10 the Soulbeast: wild state machine (notice, warn, lunge, attack, flee), trust gains and losses with stage
## thresholds, bonding, follow offsets and the teleport threshold, commands, downed and revive, the save round trip,
## the wolf aura, LOD distances and a body smoke test.

const Brain := preload("res://scripts/actors/soulbeast_brain.gd")
const Save := preload("res://scripts/actors/soulbeast_save.gd")
const Aura := preload("res://scripts/actors/soulbeast_aura.gd")
const Beast := preload("res://scripts/actors/soulbeast.gd")
const Hub := preload("res://scripts/realm/realm_hub.gd")
const S := Brain.State


func _wild(hour := 20.0) -> RefCounted:
	var b: RefCounted = Brain.new(7)
	b.hour = hour
	b.den = Vector2(100, 100)
	b.at_den = true
	return b


## Runs `seconds` of thinks at 4 Hz.
func _run(b: RefCounted, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		b.think_wild(0.25)
		t += 0.25


func _bonded() -> RefCounted:
	var b: RefCounted = Brain.new(3)
	b.trust = 90.0
	assert_bool(b.bond("Ember")).is_true()
	return b


# --- wild state machine ------------------------------------------------------------------------------
func test_idles_roams_and_sleeps_by_day() -> void:
	var night := _wild(23.0)
	night.seen = false
	night.at_den = false
	_run(night, 12.0)
	assert_int(night.state).is_equal(S.ROAM)          # awake at night: leaves its idle to roam
	var day := _wild(12.0)
	day.state = S.IDLE
	_run(day, 3.0)
	assert_int(day.state).is_equal(S.SLEEP)           # nocturnal: asleep at its den by day
	var away := _wild(12.0)
	away.at_den = false
	_run(away, 3.0)
	assert_int(away.state).is_equal(S.RETURN)         # by day away from the den: it goes home first


func test_eats_when_hungry_and_food_near() -> void:
	var b := _wild(22.0)
	b.hunger = 0.9
	b.food_near = true
	b.at_den = false
	for i in 40:
		b.think_wild(0.25)
		if b.state == S.EAT:
			break
	assert_int(b.state).is_equal(S.EAT)
	assert_int(b.eat_phase()).is_equal(0)             # still walking to the food
	b.at_goal = true
	_run(b, 1.0)
	assert_int(b.eat_phase()).is_equal(1)             # sniffs first
	_run(b, 1.5)
	assert_int(b.eat_phase()).is_equal(2)             # then eats
	for i in 60:
		b.think_wild(0.25)
		if b.ate:
			break
	assert_bool(b.ate).is_true()
	assert_float(b.hunger).is_equal(0.0)


func test_notice_warn_lunge_then_attack() -> void:
	var b := _wild(22.0)
	b.state = S.IDLE
	b.at_den = false
	b.seen = true
	b.dist = 9.0
	b.player_speed = 2.0
	b.think_wild(0.25)
	assert_int(b.state).is_equal(S.NOTICE)
	_run(b, Brain.NOTICE_TIME + 0.5)
	assert_int(b.state).is_equal(S.WARN)              # growls inside its warn range
	b.dist = 4.5                                       # the trespass goes on, closer
	var lunged := false
	for i in 40:
		b.think_wild(0.25)
		lunged = lunged or b.lunged
		if b.state == S.LUNGE:
			break
	assert_int(b.state).is_equal(S.LUNGE)
	assert_bool(lunged).is_true()                      # the warning lunge, before any bite
	assert_float(b.provoked).is_equal(0.0)
	for i in 20:
		b.think_wild(0.25)
		if b.state == S.ATTACK:
			break
	assert_int(b.state).is_equal(S.ATTACK)             # still inside after the warning: it attacks


func test_backing_off_after_a_warning_ends_it() -> void:
	var b := _wild(22.0)
	b.at_den = false
	b.seen = true
	b.dist = 4.5
	b.player_speed = 2.0
	for i in 40:
		b.think_wild(0.25)
		if b.state == S.LUNGE:
			break
	assert_int(b.state).is_equal(S.LUNGE)
	b.dist = 9.0                                       # the player retreats
	_run(b, 2.0)
	assert_int(b.state).is_not_equal(S.ATTACK)
	assert_int(b.state).is_not_equal(S.LUNGE)
	b.seen = false
	b.dist = 40.0
	_run(b, 4.0)
	assert_int(b.state).is_not_equal(S.WARN)


func test_a_calm_crouched_approach_buys_time() -> void:
	var calm := _wild(22.0)
	calm.at_den = false
	calm.seen = true
	calm.dist = 8.0
	calm.player_crouch = true
	calm.player_speed = 1.0
	var rash := _wild(22.0)
	rash.at_den = false
	rash.seen = true
	rash.dist = 8.0
	rash.player_speed = 2.0
	_run(calm, 6.0)
	_run(rash, 6.0)
	assert_float(calm._escalate).is_less(rash._escalate)


func test_sleeper_wakes_only_when_close_or_loud() -> void:
	var b := _wild(12.0)
	b.state = S.SLEEP
	b.seen = true
	b.dist = 9.0
	b.player_speed = 2.0
	b.think_wild(0.25)
	assert_int(b.state).is_equal(S.SLEEP)              # 9 m is outside a sleeper's 5.6 m
	b.dist = 3.0
	b.think_wild(0.25)
	assert_int(b.state).is_equal(S.NOTICE)
	assert_float(b.notice_range(1.0)).is_equal(Brain.SEEN_RANGE)


func test_flees_when_badly_hurt_then_returns_home() -> void:
	var b := _wild(22.0)
	b.at_den = false
	b.seen = true
	b.dist = 5.0
	b.hurt(int(b.max_hp * 0.8))
	assert_float(b.hp_frac()).is_less(Brain.FLEE_HP)
	b.think_wild(0.25)
	assert_int(b.state).is_equal(S.FLEE)
	b.dist = 40.0
	b.think_wild(0.25)
	assert_int(b.state).is_equal(S.RETURN)
	b.at_den = true
	b.think_wild(0.25)
	assert_int(b.state).is_equal(S.SLEEP)              # lies up at the den to heal
	assert_int(b.hp).is_greater(0)


func test_hit_by_player_turns_it_hostile() -> void:
	var b := _wild(22.0)
	b.trust = 40.0
	b.at_den = false
	b.dist = 6.0
	b.on_aggression(true)
	assert_float(b.trust).is_equal(15.0)
	b.think_wild(0.25)
	assert_int(b.state).is_equal(S.ATTACK)


func test_curious_approaches_sniffs_and_accepting_lets_you_near() -> void:
	var c := _wild(22.0)
	c.trust = 35.0
	c.at_den = false
	c.seen = true
	c.player_speed = 1.0
	c.dist = 8.0
	_run(c, 0.5)
	assert_int(c.state).is_equal(S.APPROACH)
	c.dist = 2.5
	_run(c, 0.5)
	assert_int(c.state).is_equal(S.SNIFF)
	var a := _wild(22.0)
	a.trust = 60.0
	a.at_den = false
	a.seen = true
	a.player_speed = 1.0
	a.dist = 6.0
	_run(a, 0.5)
	assert_int(a.state).is_equal(S.APPROACH)
	a.dist = 1.5
	_run(a, 0.5)
	assert_int(a.state).is_equal(S.SNIFF)             # stands beside you
	a.player_armed = true                              # a drawn weapon spoils it
	a.dist = 5.0
	_run(a, 0.5)
	assert_int(a.state).is_equal(S.WARN)


func test_wild_beast_fights_a_hostile_near_its_den() -> void:
	var b := _wild(22.0)
	b.has_target = true
	b.think_wild(0.25)
	assert_int(b.state).is_equal(S.FIGHT)
	b.has_target = false
	b.think_wild(0.25)
	assert_int(b.state).is_equal(S.IDLE)


# --- trust -----------------------------------------------------------------------------------------
func test_stage_thresholds() -> void:
	assert_int(Brain.stage_for(0.0)).is_equal(Brain.Stage.WARY)
	assert_int(Brain.stage_for(24.9)).is_equal(Brain.Stage.WARY)
	assert_int(Brain.stage_for(25.0)).is_equal(Brain.Stage.CURIOUS)
	assert_int(Brain.stage_for(49.9)).is_equal(Brain.Stage.CURIOUS)
	assert_int(Brain.stage_for(50.0)).is_equal(Brain.Stage.ACCEPTING)
	assert_int(Brain.stage_for(99.0)).is_equal(Brain.Stage.ACCEPTING)
	assert_int(Brain.stage_for(10.0, true)).is_equal(Brain.Stage.BONDED)


func test_food_raises_trust_with_a_repeat_cooldown() -> void:
	var b: RefCounted = Brain.new()
	var first: float = b.offer_food(2.0, 100.0)
	assert_float(first).is_equal_approx(Brain.GAIN_FOOD * 1.2, 0.01)
	var again: float = b.offer_food(1.0, 110.0)         # inside the cooldown: worth less
	assert_float(again).is_equal_approx(Brain.GAIN_FOOD_REPEAT, 0.01)
	var later: float = b.offer_food(1.0, 300.0)
	assert_float(later).is_equal_approx(Brain.GAIN_FOOD, 0.01)


func test_calm_approach_and_time_nearby_gain_trust_up_to_a_cap() -> void:
	var crouch: RefCounted = Brain.new()
	crouch.dist = 5.0
	crouch.player_crouch = true
	crouch.player_speed = 0.8
	var walk: RefCounted = Brain.new()
	walk.dist = 5.0
	walk.player_speed = 2.0
	for i in 20:
		crouch.tick_proximity(1.0)
		walk.tick_proximity(1.0)
	assert_float(crouch.trust).is_greater(walk.trust)
	assert_float(walk.trust).is_greater(0.0)
	var far: RefCounted = Brain.new()
	far.dist = 40.0
	far.tick_proximity(100.0)
	assert_float(far.trust).is_equal(0.0)
	var patient: RefCounted = Brain.new()
	patient.dist = 5.0
	patient.player_crouch = true
	patient.player_speed = 0.5
	for i in 400:
		patient.tick_proximity(1.0)
	assert_float(patient.trust).is_equal(Brain.PASSIVE_CAP)   # time alone never makes it bond-ready


func test_sprinting_and_aggression_lose_trust() -> void:
	var b: RefCounted = Brain.new()
	b.trust = 50.0
	b.dist = 8.0
	b.player_speed = 6.5
	b.tick_proximity(5.0)
	assert_float(b.trust).is_equal_approx(50.0 - Brain.LOSS_SPRINT * 5.0, 0.01)
	b.player_speed = 1.0
	b.player_armed = true
	var before: float = b.trust
	b.tick_proximity(2.0)
	assert_float(b.trust).is_less(before)
	b.player_armed = false
	b.on_aggression(false)
	assert_float(b.trust).is_less(before - 5.0)
	b.trust = 40.0
	b.on_aggression(true)
	assert_float(b.trust).is_equal(40.0 - Brain.LOSS_HIT)
	b.trust = 5.0
	b.on_aggression(true)
	assert_float(b.trust).is_equal(0.0)                # never below zero


func test_helping_in_a_fight_and_a_peaceful_day() -> void:
	var b: RefCounted = Brain.new()
	b.on_helped()
	assert_float(b.trust).is_equal(Brain.GAIN_HELP)
	b.tick_day()
	assert_float(b.trust).is_equal(Brain.GAIN_HELP + Brain.GAIN_DAY_PEACEFUL)
	b.on_aggression(true)
	var t: float = b.trust
	b.tick_day()                                       # a day with a blow in it: trust only decays
	assert_float(b.trust).is_less(t + 0.01)


# --- bonding ---------------------------------------------------------------------------------------
func test_bond_needs_trust_and_sets_state() -> void:
	var b: RefCounted = Brain.new()
	b.trust = Brain.BOND_TRUST - 1.0
	assert_bool(b.can_bond()).is_false()
	assert_bool(b.bond("Ember")).is_false()
	b.trust = Brain.BOND_TRUST
	assert_bool(b.can_bond()).is_true()
	assert_bool(b.bond("  Ember ")).is_true()
	assert_bool(b.bonded).is_true()
	assert_str(b.soul_name).is_equal("Ember")
	assert_int(b.stage()).is_equal(Brain.Stage.BONDED)
	assert_int(b.state).is_equal(S.FOLLOW)
	assert_bool(b.bond("Other")).is_false()            # already bonded
	b.add_trust(-50.0)
	assert_float(b.trust).is_equal(100.0)              # a bond does not erode from trust events


# --- companion: follow offsets, catch-up, teleport -------------------------------------------------
func test_follow_offsets_trail_behind_and_to_the_side() -> void:
	var moving: Vector2 = Brain.slot_offset(0, true)
	var standing: Vector2 = Brain.slot_offset(0, false)
	assert_float(moving.y).is_greater(standing.y)       # farther back while walking
	assert_float(Brain.slot_offset(0, true).x * Brain.slot_offset(1, true).x).is_less(0.0)   # opposite sides
	assert_float(Brain.slot_offset(2, true).y).is_greater(Brain.slot_offset(0, true).y)      # next row
	var p: Vector2 = Brain.follow_point(Vector2(10, 10), 0.0, true, 0)    # player faces +Z
	assert_float(p.y).is_less(10.0)                     # behind a player facing +Z
	assert_float(absf(p.x - 10.0)).is_equal_approx(1.6, 0.01)
	var q: Vector2 = Brain.follow_point(Vector2(10, 10), PI * 0.5, true, 0)  # now faces +X
	assert_float(q.x).is_less(10.0)
	assert_float(q.distance_to(Vector2(10, 10))).is_equal_approx(p.distance_to(Vector2(10, 10)), 0.01)


func test_follow_speed_and_catchup() -> void:
	assert_float(Brain.follow_speed(0.3, 5.0)).is_equal(0.0)
	assert_float(Brain.follow_speed(2.0, 0.0)).is_between(Brain.WALK_SPEED, 3.0)
	assert_float(Brain.follow_speed(2.0, 6.0)).is_greater(5.0)               # keeps pace at a run
	assert_float(Brain.follow_speed(6.0, 6.5)).is_less_equal(Brain.RUN_SPEED)
	assert_float(Brain.follow_speed(Brain.CATCHUP_DIST + 5.0, 6.5)).is_greater(Brain.RUN_SPEED)   # sprints to catch up
	assert_float(Brain.follow_speed(60.0, 6.5)).is_less_equal(Brain.CATCHUP_SPEED)


func test_teleport_threshold() -> void:
	assert_bool(Brain.needs_teleport(Brain.TELEPORT_DIST - 1.0, 0.0)).is_false()
	assert_bool(Brain.needs_teleport(Brain.TELEPORT_DIST + 1.0, 0.0)).is_true()
	assert_bool(Brain.needs_teleport(5.0, Brain.TELEPORT_JUMP + 1.0)).is_true()   # fast travel
	assert_bool(Brain.needs_teleport(5.0, 6.0)).is_false()


func test_waits_outside_an_interior_and_follows_out() -> void:
	var b := _bonded()
	b.dist = 4.0
	b.player_inside = true
	b.think_ally(0.25)
	assert_int(b.state).is_equal(S.WAIT)
	b.player_inside = false
	b.think_ally(0.25)
	assert_int(b.state).is_equal(S.FOLLOW)


# --- companion: fighting and the killing blow --------------------------------------------------------
func test_fights_beside_the_player_and_returns_after() -> void:
	var b := _bonded()
	b.dist = 5.0
	b.has_target = true
	b.think_ally(0.25)
	assert_int(b.state).is_equal(S.FIGHT)
	b.has_target = false
	b.think_ally(0.25)
	assert_int(b.state).is_equal(S.FOLLOW)
	b.dist = 60.0                                       # a foe far from the player is not worth the leash
	b.has_target = true
	b.think_ally(0.25)
	assert_int(b.state).is_equal(S.FOLLOW)


func test_it_rarely_takes_the_killing_blow() -> void:
	var b := _bonded()
	assert_int(b.clamp_damage(10, 40, 0.5)).is_equal(10)          # a blow that does not kill is untouched
	assert_int(b.clamp_damage(10, 10, 0.9)).is_equal(9)           # would kill: leaves it standing
	assert_int(b.clamp_damage(10, 1, 0.9)).is_equal(0)
	assert_int(b.clamp_damage(10, 10, 0.05)).is_equal(10)         # the rare steal
	var steals := 0
	var killing := 0
	for i in 1000:
		killing += 1
		if b.clamp_damage(10, 8, b.rand()) >= 8:
			steals += 1
	assert_float(float(steals) / float(killing)).is_between(0.08, 0.22)


# --- commands --------------------------------------------------------------------------------------
func test_commands_stay_follow_attack() -> void:
	var b := _bonded()
	assert_bool(b.give_command(Brain.Cmd.STAY)).is_true()
	assert_int(b.state).is_equal(S.STAY)
	b.dist = 3.0
	b.has_target = true
	b.think_ally(0.25)
	assert_int(b.state).is_equal(S.STAY)                # an order to stay beats a fight
	assert_bool(b.give_command(Brain.Cmd.FOLLOW)).is_true()
	assert_int(b.state).is_equal(S.FOLLOW)
	assert_bool(b.give_command(Brain.Cmd.ATTACK)).is_true()
	assert_int(b.state).is_equal(S.FIGHT)
	b.has_target = false
	assert_bool(b.give_command(Brain.Cmd.ATTACK)).is_false()    # nothing to attack
	b.think_ally(0.25)
	assert_int(b.command).is_equal(Brain.Cmd.FOLLOW)
	var wild: RefCounted = Brain.new()
	assert_bool(wild.give_command(Brain.Cmd.STAY)).is_false()   # only a bonded beast obeys


func test_context_button_cycles_commands() -> void:
	var b := _bonded()
	assert_int(b.next_command()).is_equal(Brain.Cmd.STAY)
	b.give_command(Brain.Cmd.STAY)
	assert_int(b.next_command()).is_equal(Brain.Cmd.FOLLOW)
	b.give_command(Brain.Cmd.FOLLOW)
	b.has_target = true
	assert_int(b.next_command()).is_equal(Brain.Cmd.ATTACK)


# --- downed and revive -----------------------------------------------------------------------------
func test_downed_at_zero_hp_then_revived_by_interaction() -> void:
	var b := _bonded()
	assert_bool(b.hurt(b.max_hp + 5)).is_true()
	assert_bool(b.downed).is_true()
	assert_int(b.hp).is_equal(0)
	b.think_ally(0.25)
	assert_int(b.state).is_equal(S.DOWNED)
	assert_bool(b.give_command(Brain.Cmd.STAY)).is_false()       # cannot be ordered while down
	assert_bool(b.hurt(5)).is_false()                            # nor hurt again
	assert_bool(b.revive()).is_true()
	assert_bool(b.downed).is_false()
	assert_int(b.hp).is_equal(int(round(b.max_hp * Brain.DOWNED_REVIVE_HP)))
	assert_int(b.state).is_equal(S.FOLLOW)
	assert_bool(b.revive()).is_false()                           # nothing to revive


func test_resting_revives_heals_and_feeds() -> void:
	var b := _bonded()
	b.hurt(b.max_hp + 1)
	b.hunger = 0.9
	b.on_rest(8.0)
	assert_bool(b.downed).is_false()
	assert_int(b.hp).is_equal(b.max_hp)
	assert_float(b.hunger).is_equal(0.0)
	var c := _bonded()
	c.hp = 10
	c.on_rest(1.0)                                               # a short rest heals some
	assert_int(c.hp).is_greater(10)
	assert_int(c.hp).is_less(c.max_hp + 1)


func test_wild_beast_is_never_killed() -> void:
	var b := _wild()
	assert_bool(b.hurt(9999)).is_false()
	assert_bool(b.downed).is_false()
	assert_int(b.hp).is_equal(1)
	assert_int(b.state).is_equal(S.FLEE)


func test_companion_sleeps_and_eats_when_the_player_rests() -> void:
	var b := _bonded()
	b.dist = 2.0
	b.player_speed = 0.0
	b.hunger = 0.1
	b.hp = b.max_hp - 5
	for i in 120:                                                # 30 s of a still player
		b.think_ally(0.25)
	assert_int(b.state).is_equal(S.SLEEP)
	b.player_speed = 3.0
	b.think_ally(0.25)
	assert_int(b.state).is_equal(S.FOLLOW)


# --- save ------------------------------------------------------------------------------------------
func test_save_round_trip_through_json() -> void:
	var b := _bonded()
	b.pos = Vector2(12.5, -40.25)
	b.den = Vector2(300.0, 410.5)
	b.hp = 33
	b.give_command(Brain.Cmd.STAY)
	b.hunger = 0.4
	var d: Dictionary = JSON.parse_string(JSON.stringify(b.to_dict()))
	var r: RefCounted = Brain.new()
	r.from_dict(d)
	assert_bool(r.bonded).is_true()
	assert_str(r.soul_name).is_equal("Ember")
	assert_float(r.trust).is_equal(100.0)
	assert_int(r.hp).is_equal(33)
	assert_int(r.max_hp).is_equal(b.max_hp)
	assert_vector(r.pos).is_equal_approx(Vector2(12.5, -40.25), Vector2(0.01, 0.01))
	assert_vector(r.den).is_equal_approx(Vector2(300.0, 410.5), Vector2(0.01, 0.01))
	assert_int(r.command).is_equal(Brain.Cmd.STAY)
	assert_int(r.state).is_equal(S.STAY)
	var wild: RefCounted = Brain.new()
	wild.trust = 42.0
	var w: RefCounted = Brain.new()
	w.from_dict(JSON.parse_string(JSON.stringify(wild.to_dict())))
	assert_float(w.trust).is_equal(42.0)
	assert_bool(w.bonded).is_false()
	assert_int(w.state).is_equal(S.IDLE)


func test_save_round_trip_through_the_followers_module() -> void:
	WorldGen.setup(2024)
	var hub: RefCounted = Hub.new()
	var fm: RefCounted = hub.mod("followers")
	var b := _bonded()
	b.den = Vector2(55, 66)
	b.hp = 20
	b.hurt(20)                                                   # down at 0 HP, saved downed
	Save.store(fm, b)
	assert_str(fm.creature("soulbeast")["status"]).is_equal("tamed")
	var blob: Dictionary = JSON.parse_string(JSON.stringify(hub.serialize()))
	var hub2: RefCounted = Hub.new()
	hub2.deserialize(blob)
	var r: RefCounted = Brain.new()
	assert_bool(Save.load_into(hub2.mod("followers"), r)).is_true()
	assert_bool(r.bonded).is_true()
	assert_str(r.soul_name).is_equal("Ember")
	assert_bool(r.downed).is_true()
	assert_int(r.hp).is_equal(0)
	assert_vector(r.den).is_equal_approx(Vector2(55, 66), Vector2(0.01, 0.01))
	var fresh: RefCounted = Brain.new()
	assert_bool(Save.load_into(Hub.new().mod("followers"), fresh)).is_false()
	var wildb: RefCounted = Brain.new()
	wildb.trust = 30.0
	Save.store(fm, wildb)
	assert_str(fm.creature("soulbeast")["status"]).is_equal("taming")
	assert_float(fm.creature("soulbeast")["trust"]).is_equal_approx(0.3, 0.001)


func test_realm_followers_taming_is_untouched_by_the_soulbeast_entry() -> void:
	WorldGen.setup(2024)
	var fm: RefCounted = Hub.new().mod("followers")
	Save.store(fm, _bonded())
	assert_bool(fm.tamed().size() == 1).is_true()
	assert_bool(fm.start_taming("other_wolf", "wolf")).is_true()


# --- aura and LOD ------------------------------------------------------------------------------------
func test_wild_wolves_are_wary_near_a_bonded_soulbeast() -> void:
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = Vector3(100, 0, 100)
	Aura.clear()
	assert_float(Aura.wary_factor(Vector3(105, 0, 100))).is_equal(1.0)
	Aura.set_companion(holder, true)
	assert_float(Aura.wary_factor(Vector3(105, 0, 100))).is_equal(Aura.WARY)
	assert_float(Aura.wary_factor(Vector3(200, 0, 100))).is_equal(1.0)
	Aura.set_companion(holder, false)
	assert_float(Aura.wary_factor(Vector3(105, 0, 100))).is_equal(1.0)
	Aura.clear()
	holder.queue_free()


func test_lod_uses_the_population_distances() -> void:
	assert_int(Beast.lod_for(PopulationLOD.FULL_RANGE - 1.0)).is_equal(0)
	assert_int(Beast.lod_for(PopulationLOD.FULL_RANGE + 1.0)).is_equal(1)
	assert_int(Beast.lod_for(PopulationLOD.SPRITE_RANGE + 1.0)).is_equal(2)
	assert_float(Beast.think_period(0)).is_less(Beast.think_period(1))
	assert_float(Beast.think_period(1)).is_less(Beast.think_period(2))


# --- body smoke -----------------------------------------------------------------------------------------
func test_body_spawns_and_snapshots() -> void:
	WorldGen.setup(2024)
	var beast: Node3D = Beast.new()
	add_child(beast)
	beast.setup(Vector2(120, 80))
	assert_bool(beast.is_in_group("team1")).is_true()            # wild: the player's blows reach it
	assert_bool(beast.is_in_group("soulbeast")).is_true()
	assert_int(beast.max_health).is_greater(0)
	beast.brain.trust = 90.0
	assert_str(beast.bond_with(null, false)).is_not_empty()
	assert_bool(beast.is_in_group("team0")).is_true()            # bonded: an ally, off the enemy list
	assert_bool(beast.is_in_group("team1")).is_false()
	assert_bool(Aura.active()).is_true()
	beast.take_damage(beast.max_health + 10, null)
	assert_bool(beast.dead).is_true()
	assert_bool(beast.is_in_group("team0")).is_false()
	assert_bool(Aura.active()).is_false()
	beast.on_player_rest(8.0)
	assert_bool(beast.dead).is_false()
	assert_int(beast.health).is_equal(beast.max_health)
	var snap: Dictionary = beast.snapshot()
	assert_bool(bool(snap["bonded"])).is_true()
	beast.queue_free()


func test_den_is_dry_and_near_thornfield() -> void:
	WorldGen.setup(2024)
	var Director := preload("res://scripts/world/soulbeast_director.gd")
	var t: Dictionary = Director.thornfield()
	assert_bool(t.is_empty()).is_false()
	var den: Vector2 = Director.find_den(t["pos"], float(t["radius"]))
	assert_bool(den != Vector2.INF).is_true()
	assert_bool(WorldGen.is_water(den.x, den.y)).is_false()
	var d: float = den.distance_to(t["pos"])
	assert_float(d).is_greater(float(t["radius"]))
	assert_float(d).is_less(float(t["radius"]) + 210.0)
