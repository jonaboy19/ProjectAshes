extends GdUnitTestSuite
## The player's technique caster after the move onto AbilityRunner: legacy techniques keep their numbers and feel
## (damage, cost, cooldown, lockout, burn ticks, seal pad rules), and path-tree techniques cast through
## power_paths. Runs the real node in the tree with stub bodies; time is stepped by hand through _physics_process.

const Caster := preload("res://scripts/actors/technique_caster.gd")
const Skills := preload("res://scripts/sim/skills.gd")
const Hub := preload("res://scripts/realm/realm_hub.gd")
const AbilityDef := preload("res://scripts/abilities/ability_def.gd")


class StubPlayer extends Node3D:
	var stamina := 100.0
	var _stamina_delay := 0.0
	var health := 100
	var dead := false

	func facing() -> Vector3:
		return Vector3.FORWARD

	func heal(n: int) -> void:
		health += n

	func set_health(v: int) -> void:
		health = v


class StubEnemy extends Node3D:
	var dead := false
	var hits: Array = []
	var statuses: Array = []

	func take_damage(amount: int, _from: Node = null, _knock := Vector3.ZERO) -> void:
		hits.append(amount)

	func apply_status(s: String, d: float) -> void:
		statuses.append([s, d])


## A caster whose power_paths module is local (the test never touches Life's realm).
class LocalCaster extends "res://scripts/actors/technique_caster.gd":
	var pp_module: RefCounted

	func _pp() -> Object:
		return pp_module

	func _life() -> Node:
		return null


func _tree_row(id: String, extra := {}) -> Dictionary:
	var t := {"id": id, "name": id, "kind": "active", "tier": 1, "resource": "stamina", "cost": 10, "cooldown": 4.0,
		"damage": 30, "shape": "melee", "range": 3.0, "hit_time": 0.25, "anim": "Sword_Attack", "vfx": "", "element": "qi"}
	t.merge(extra, true)
	return t


func _setup(rows: Array, use_local := false) -> Dictionary:
	var s := Skills.new()
	s.add_tree({"id": "testtree", "name": "Test", "category": "martial", "element": "qi", "techniques": rows})
	for r: Dictionary in rows:
		s.grant(String(r["id"]))
	var player := StubPlayer.new()
	add_child(player)
	auto_free(player)
	player.global_position = Vector3.ZERO
	var enemy := StubEnemy.new()
	add_child(enemy)
	auto_free(enemy)
	enemy.add_to_group("team1")
	enemy.global_position = Vector3(0, 0, -2.0)          # straight ahead (facing() is -Z)
	var c: Node = LocalCaster.new() if use_local else Caster.new()
	c.skills = s
	player.add_child(c)
	return {"caster": c, "skills": s, "player": player, "enemy": enemy}


func _run(c: Node, seconds: float, step := 0.016) -> void:
	var t := 0.0
	while t < seconds:
		c._physics_process(step)
		t += step


# --- legacy numbers ---------------------------------------------------------------

func test_melee_technique_pays_cools_down_and_hits_for_the_skills_damage() -> void:
	var w := _setup([_tree_row("t_cut", {"tree": "swordsmanship"})])
	var c: Node = w["caster"]
	var s: Skills = w["skills"]
	var e: StubEnemy = w["enemy"]
	var expect_damage := s.damage_of("t_cut")
	var expect_cd := s.cooldown_of("t_cut")
	var r: Dictionary = c.cast_technique("t_cut")
	assert_bool(r["ok"]).is_true()
	assert_float(w["player"].stamina).is_equal_approx(90.0, 0.001)               # paid on cast
	assert_float(w["player"]._stamina_delay).is_equal_approx(0.8, 0.001)
	assert_float(s.cooldown_left("t_cut")).is_equal_approx(expect_cd, 0.001)
	assert_int(r["damage"]).is_equal(expect_damage)
	assert_bool(e.hits.is_empty()).is_true()                                       # the hit lands after hit_time
	_run(c, 0.2)
	assert_bool(e.hits.is_empty()).is_true()
	_run(c, 0.1)
	assert_array(e.hits).is_equal([expect_damage])
	assert_str(c.cast_technique("t_cut")["reason"]).is_equal("%.1fs" % s.cooldown_left("t_cut"))


func test_failures_keep_the_legacy_reasons() -> void:
	var w := _setup([_tree_row("t_cut", {"cost": 200})])
	var c: Node = w["caster"]
	var failed := []
	c.failed.connect(func(id: String, why: String) -> void: failed.append([id, why]))
	assert_str(c.cast_technique("")["reason"]).is_equal("Empty slot.")
	assert_str(c.cast_technique("nope")["reason"]).is_equal("Not learned.")
	assert_str(c.cast_technique("t_cut")["reason"]).is_equal("Not enough stamina.")
	assert_int(failed.size()).is_equal(3)
	assert_float(w["player"].stamina).is_equal(100.0)                              # a failed cast pays nothing


func test_global_lockout_and_single_pending_windup() -> void:
	# Codex (bending-current): the player's runner no longer overlaps windups (runner.overlap_windups = false), so a second
	# technique is refused until the first has released and recovered. The 0.3 s global lockout is unchanged.
	var w := _setup([_tree_row("t_slow", {"hit_time": 0.8, "cost": 5}), _tree_row("t_fast", {"hit_time": 0.1, "cost": 5})])
	var c: Node = w["caster"]
	var e: StubEnemy = w["enemy"]
	assert_bool(c.cast_technique("t_slow")["ok"]).is_true()
	assert_str(c.cast_technique("t_fast")["reason"]).is_equal("Busy.")             # inside the 0.3 s lockout
	_run(c, 0.35)
	assert_bool(c.cast_technique("t_fast")["ok"]).is_false()                       # the slow windup is still unreleased
	_run(c, 0.6)
	assert_int(e.hits.size()).is_equal(1)                                          # only the slow one resolved
	_run(c, 1.2)
	assert_bool(c.cast_technique("t_fast")["ok"]).is_true()                        # free again after the recovery
	_run(c, 0.3)
	assert_int(e.hits.size()).is_equal(2)


func test_burn_ticks_exactly_like_the_old_caster() -> void:
	var w := _setup([_tree_row("t_burn", {"damage": 25, "effect": {"burn": 3.0}, "cooldown": 8.0})])
	var c: Node = w["caster"]
	var e: StubEnemy = w["enemy"]
	var dmg: int = c.cast_technique("t_burn")["damage"]
	_run(c, 0.3)
	assert_array(e.hits).is_equal([dmg])
	var dps := maxi(1, int(round(dmg * 0.08)))
	_run(c, 4.0)
	var ticks := e.hits.size() - 1
	assert_int(ticks).is_between(4, 5)                                             # 0.5 s steps over 3 s, last tick lost
	for i in range(1, e.hits.size()):
		assert_int(e.hits[i]).is_equal(dps)
	assert_bool(c.effects_on(e).active.is_empty()).is_true()
	# Crowd control still reaches actors that support it.
	var w2 := _setup([_tree_row("t_stun", {"effect": {"stun": 1.5, "slow": 2.0}, "cooldown": 8.0})])
	w2["caster"].cast_technique("t_stun")
	_run(w2["caster"], 0.4)
	assert_array(w2["enemy"].statuses).is_equal([["stun", 1.5], ["slow", 2.0]])


func test_buff_goes_to_skills_and_refreshes_by_id() -> void:
	var w := _setup([_tree_row("t_skin", {"shape": "buff", "damage": 0, "effect": {"buff": {"damage_taken": -0.3}, "duration": 8.0}, "cooldown": 1.0, "cost": 0})])
	var c: Node = w["caster"]
	var s: Skills = w["skills"]
	c.cast_technique("t_skin")
	_run(c, 0.5)
	assert_float(s.effects().get("damage_taken", 0.0)).is_equal_approx(-0.3, 0.0001)
	_run(c, 1.2)
	c.cast_technique("t_skin")
	_run(c, 0.5)
	assert_int(s.buffs.size()).is_equal(1)                                        # same id: refreshed, not stacked
	assert_float(s.effects().get("damage_taken", 0.0)).is_equal_approx(-0.3, 0.0001)


# --- seals / chant ----------------------------------------------------------------

func _magic_row(extra := {}) -> Dictionary:
	return _tree_row("t_nova", {"resource": "magicules", "cost": 0.0, "shape": "aoe", "radius": 5.0, "seals": ["rat", "tiger"],
		"cooldown": 6.0, "element": "fire"}).merged(extra, true)


func test_a_beginner_cannot_cast_a_chant_gated_spell_without_the_seal_pad() -> void:
	var w := _setup([_magic_row()])
	var c: Node = w["caster"]
	var e: StubEnemy = w["enemy"]
	var started := []
	c.seals_started.connect(func(id: String, seq: Array) -> void: started.append([id, seq]))
	var r: Dictionary = c.cast_technique("t_nova")        # the keyboard path: no seals asked for
	assert_bool(r.get("sealing", false)).is_true()        # but a beginner must chant: the pad opens instead
	assert_bool(c.is_sealing()).is_true()
	assert_array(started).is_equal([["t_nova", ["rat", "tiger"]]])
	assert_bool(e.hits.is_empty()).is_true()
	assert_float(w["skills"].cooldown_left("t_nova")).is_equal(0.0)                # nothing paid or cooling yet
	c.input_seal("rat")
	assert_int(c.seal_progress()).is_equal(1)
	c.input_seal("tiger")
	assert_bool(c.is_sealing()).is_false()
	assert_float(w["skills"].cooldown_left("t_nova")).is_greater(0.0)              # committed on release
	_run(c, 0.4)
	assert_int(e.hits.size()).is_equal(1)
	assert_int(e.hits[0]).is_equal(int(round(w["skills"].damage_of("t_nova") * 1.15)))   # seal bonus, as before


func test_wrong_seal_and_timeout_fizzle_with_a_two_second_rest() -> void:
	var w := _setup([_magic_row()])
	var c: Node = w["caster"]
	var ended := []
	c.seals_ended.connect(func(id: String, ok: bool) -> void: ended.append([id, ok]))
	c.cast_technique("t_nova")
	c.input_seal("boar")
	assert_array(ended).is_equal([["t_nova", false]])
	assert_float(w["skills"].cooldown_left("t_nova")).is_equal_approx(2.0, 0.001)
	_run(c, 2.1)
	c.cast_technique("t_nova")
	assert_bool(c.is_sealing()).is_true()
	_run(c, Caster.SEAL_TIME + 0.2)
	assert_bool(c.is_sealing()).is_false()
	assert_float(w["skills"].cooldown_left("t_nova")).is_greater(1.5)
	assert_bool(w["enemy"].hits.is_empty()).is_true()
	c.cast_technique("t_nova")                                  # cooling: refused
	assert_bool(c.is_sealing()).is_false()
	_run(c, 2.1)
	c.cast_technique("t_nova")
	c.cancel_seals()                                            # walking away costs nothing
	assert_bool(c.is_sealing()).is_false()
	assert_float(w["skills"].cooldown_left("t_nova")).is_equal(0.0)


func test_optional_seals_on_non_magic_techniques_still_fire_at_once() -> void:
	var w := _setup([_tree_row("t_qi_nova", {"resource": "qi", "cost": 5, "shape": "aoe", "radius": 5.0, "seals": ["rat"], "cooldown": 6.0})])
	var c: Node = w["caster"]
	w["skills"].qi = 50.0
	var r: Dictionary = c.cast_technique("t_qi_nova")
	assert_bool(r["ok"]).is_true()
	assert_bool(r.get("sealing", false)).is_false()
	assert_bool(c.is_sealing()).is_false()
	assert_int(r["damage"]).is_equal(w["skills"].damage_of("t_qi_nova"))           # no seal bonus without the pad
	assert_float(w["skills"].qi).is_equal_approx(45.0, 0.001)
	# The touch button path (with_seals) still opens the pad for the bonus.
	var w2 := _setup([_tree_row("t_qi_nova", {"resource": "qi", "cost": 5, "shape": "aoe", "radius": 5.0, "seals": ["rat"], "cooldown": 6.0})])
	w2["skills"].qi = 50.0
	var r2: Dictionary = w2["caster"].cast_slot(0, true)
	assert_bool(r2.get("sealing", false)).is_true()
	w2["caster"].input_seal("rat")
	assert_float(w2["skills"].cooldown_left("t_qi_nova")).is_greater(0.0)


# --- path-tree techniques ----------------------------------------------------------

func test_path_tree_technique_casts_through_power_paths() -> void:
	var w := _setup([], true)
	var c: Node = w["caster"]
	var pp: RefCounted = Hub.new().mod("power_paths")
	pp.learn("sect", "academy")
	pp.add_teacher("sect_elder")
	assert_bool(pp.learn_technique("st_palm", {"realms": {"sect": {"realm": 1, "stage": 3}}})["ok"]).is_true()
	c.pp_module = pp
	var before: float = pp.resource("sect")["cur"]
	var r: Dictionary = c.cast_ability("st_palm")
	assert_bool(r["ok"]).is_true()
	assert_float(pp.resource("sect")["cur"]).is_equal_approx(before - 8.0, 0.001)    # the path pool paid
	assert_float(pp.strain("sect")).is_greater(0.0)                                  # meridian strain
	assert_int(r["damage"]).is_equal(24)
	assert_float(w["skills"].cooldown_left("st_palm")).is_equal_approx(2.4, 0.001)
	_run(c, 0.4)
	assert_array(w["enemy"].hits).is_equal([24])
	assert_str(c.cast_ability("st_palm")["reason"]).is_not_equal("")                 # cooling down
	assert_str(c.cast_ability("st_step")["reason"]).is_equal("Not learned.")         # not a known technique


func test_path_tree_chant_spells_open_the_pad_and_pay_on_release() -> void:
	var w := _setup([], true)
	var c: Node = w["caster"]
	var pp: RefCounted = Hub.new().mod("power_paths")
	pp.learn("magic", "academy")
	assert_bool(pp.learn_technique("mg_spark", {"realms": {"magic": {"realm": 1, "stage": 4}}, "manuals": ["m_mg1"]})["ok"]).is_true()
	c.pp_module = pp
	var mana_before: float = pp.resource("magic")["cur"]
	var r: Dictionary = c.cast_ability("mg_spark")
	assert_bool(r.get("sealing", false)).is_true()
	assert_float(pp.resource("magic")["cur"]).is_equal_approx(mana_before, 0.001)    # nothing spent while chanting
	for seal: String in ["tiger", "rat"]:
		c.input_seal(seal)
	assert_float(pp.resource("magic")["cur"]).is_less(mana_before)
	_run(c, 0.5)
	assert_int(w["enemy"].hits.size()).is_equal(1)


func test_path_tree_self_effects_become_effects_on_the_caster() -> void:
	var w := _setup([], true)
	var c: Node = w["caster"]
	var pp: RefCounted = Hub.new().mod("power_paths")
	pp.learn("knight", "academy")
	pp.add_teacher("drill_sergeant")
	assert_bool(pp.learn_technique("kn_brace", {"realms": {"knight": {"realm": 1, "stage": 3}}})["ok"]).is_true()
	c.pp_module = pp
	assert_bool(c.cast_ability("kn_brace")["ok"]).is_true()
	_run(c, 0.4)
	assert_bool(c.runner.effects.has("brace")).is_true()
	assert_int(c.mitigate(40)).is_equal(30)                                         # damage_taken -25 percent
	_run(c, 4.5)
	assert_bool(c.runner.effects.has("brace")).is_false()                           # expired
	assert_int(c.mitigate(40)).is_equal(40)
