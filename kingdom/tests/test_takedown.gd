extends GdUnitTestSuite
## Knock-out / kill path (scripts/combat/takedown.gd, villager.gd go_down): a silent takedown from behind needs an
## unaware victim within reach, silences a witness so the crime stays unreported, and either way leaves a body as
## Evidence that others can find. Kills leave a BODY and blood; KOs wake up.

const Takedown := preload("res://scripts/combat/takedown.gd")
const Witness := preload("res://scripts/population/witness.gd")
const Evidence := preload("res://scripts/population/evidence.gd")
const Perception := preload("res://scripts/population/perception.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const Cls := Perception.Cls

const VICTIM := Vector2(10, 10)
const FACING := Vector2(0, 1)           # looking +z


class FakeSociety extends RefCounted:
	var calls: Array = []
	var evidence: Array = []

	func commit_crime(kind: String, sid: int, witnesses: Variant = 0, opts: Dictionary = {}) -> Dictionary:
		calls.append({"kind": kind, "sid": sid, "witnesses": witnesses, "opts": opts})
		return {"ok": true, "kind": kind}

	func add_evidence(crime: String, type: String, strength: float, sid: int) -> String:
		evidence.append([crime, type, strength, sid])
		return "e%d" % evidence.size()


func before_test() -> void:
	NpcWorld.reset()
	Takedown.reset()


# ---------------------------------------------------------------- the rules
func test_takedown_needs_reach_behind_and_an_unaware_victim() -> void:
	var behind := VICTIM + Vector2(0, -1.2)
	var front := VICTIM + Vector2(0, 1.2)
	var side := VICTIM + Vector2(1.2, 0)
	assert_bool(Takedown.can_takedown(behind, VICTIM, FACING, Cls.CALM)).is_true()
	assert_bool(Takedown.can_takedown(behind, VICTIM, FACING, Cls.NOTICE)).is_true()       # glanced round, saw nothing
	assert_bool(Takedown.can_takedown(front, VICTIM, FACING, Cls.CALM)).is_false()         # seen coming
	assert_bool(Takedown.can_takedown(side, VICTIM, FACING, Cls.CALM)).is_false()
	assert_bool(Takedown.can_takedown(behind + Vector2(0, -1.5), VICTIM, FACING, Cls.CALM)).is_false()   # out of reach
	assert_bool(Takedown.can_takedown(behind, VICTIM, FACING, Cls.SUSPICIOUS)).is_false()  # already uneasy
	assert_bool(Takedown.can_takedown(behind, VICTIM, FACING, Cls.ALARMED)).is_false()
	# a guard must be fully calm
	assert_bool(Takedown.can_takedown(behind, VICTIM, FACING, Cls.NOTICE, true)).is_false()
	assert_bool(Takedown.can_takedown(behind, VICTIM, FACING, Cls.CALM, true)).is_true()
	assert_int(Takedown.hp_for(true, 3)).is_greater(Takedown.hp_for(false, 3))


# ---------------------------------------------------------------- silencing a witness
func test_knocking_out_the_only_witness_leaves_the_crime_unreported_but_a_body_behind() -> void:
	var soc := FakeSociety.new()
	var case_id := Witness.begin("robbery", 0, Vector2(8, 8), [{"id": "anon:0:7", "person": 7, "vis": 0.7, "guard": false}], 0, soc)
	assert_str(Witness.status(case_id)).is_equal("pending")
	var eid := Takedown.down(7, Takedown.Kind.KO, VICTIM, 0, 1000, soc)
	assert_str(Witness.status(case_id)).is_equal("unreported")
	Witness.tick(10 * 60 * 1000, soc)
	assert_int(soc.calls.size()).is_equal(0)                         # nothing ever committed
	assert_bool(Takedown.is_down(7)).is_true()
	assert_bool(Takedown.is_dead(7)).is_false()
	assert_int(Evidence.kind_of(eid)).is_equal(Evidence.Kind.KO)
	assert_vector(Evidence.pos_of(eid)).is_equal(VICTIM)


func test_a_kill_leaves_a_body_and_blood_and_silences_too() -> void:
	var soc := FakeSociety.new()
	var case_id := Witness.begin("assault", 0, Vector2(8, 8), [{"id": "anon:0:9", "person": 9, "vis": 0.9, "guard": false}], 0, soc)
	var eid := Takedown.down(9, Takedown.Kind.KILL, VICTIM, 0, 2000, soc)
	assert_str(Witness.status(case_id)).is_equal("unreported")
	assert_bool(Takedown.is_dead(9)).is_true()
	assert_int(Evidence.kind_of(eid)).is_equal(Evidence.Kind.BODY)
	assert_int(Evidence.count).is_equal(2)                           # BODY + BLOOD
	assert_int(Takedown.down(9, Takedown.Kind.KILL, VICTIM, 0, 2100, soc)).is_equal(eid)       # idempotent
	assert_int(Evidence.count).is_equal(2)


func test_a_witness_who_survives_still_reports() -> void:
	var soc := FakeSociety.new()
	var case_id := Witness.begin("robbery", 0, Vector2(8, 8), [
		{"id": "anon:0:7", "person": 7, "vis": 0.7, "guard": false}, {"id": "anon:0:8", "person": 8, "vis": 0.7, "guard": false}], 0, soc)
	Takedown.down(7, Takedown.Kind.KO, VICTIM, 0, 1000, soc)
	assert_str(Witness.status(case_id)).is_equal("pending")
	Witness.deliver(8, 3000, soc)
	assert_str(Witness.status(case_id)).is_equal("committed")


# ---------------------------------------------------------------- the body is evidence
func test_a_body_is_found_once_per_finder_and_raises_alarm_fields() -> void:
	var eid := Takedown.down(7, Takedown.Kind.KO, VICTIM, 0, 0)
	assert_int(Evidence.nearest_unseen(VICTIM + Vector2(5, 0), 12.0, 21)).is_equal(eid)
	Evidence.mark_seen(eid, 21)
	assert_int(Evidence.nearest_unseen(VICTIM + Vector2(5, 0), 12.0, 21)).is_equal(0)
	assert_int(Evidence.nearest_unseen(VICTIM + Vector2(5, 0), 12.0, 22)).is_equal(eid)
	var soc := FakeSociety.new()
	assert_str(Evidence.feed(eid, soc)).is_not_empty()               # discovery goes to Society
	assert_str(soc.evidence[0][1]).is_equal("blood")


func test_knocked_out_people_wake_and_their_body_goes() -> void:
	var eid := Takedown.down(7, Takedown.Kind.KO, VICTIM, 0, 1000)
	assert_array(Takedown.tick(1000 + int(Takedown.KO_SECONDS * 1000.0) - 1)).is_empty()
	assert_bool(Evidence.exists(eid)).is_true()
	assert_array(Takedown.tick(1000 + int(Takedown.KO_SECONDS * 1000.0))).is_equal([7])
	assert_bool(Takedown.is_down(7)).is_false()
	assert_bool(Evidence.exists(eid)).is_false()
	# the dead never wake
	Takedown.down(8, Takedown.Kind.KILL, VICTIM, 0, 0)
	assert_array(Takedown.tick(99999999)).is_empty()
	assert_bool(Takedown.wake(8)).is_false()
	assert_bool(Takedown.is_dead(8)).is_true()


func test_the_dead_stay_dead_across_a_save() -> void:
	Takedown.down(8, Takedown.Kind.KILL, VICTIM, 3, 0)
	Takedown.down(9, Takedown.Kind.KO, VICTIM, 3, 0)
	var rows := Takedown.serialize()
	assert_int(rows.size()).is_equal(1)
	Takedown.reset()
	Evidence.reset()
	Takedown.deserialize(rows, 0)
	assert_bool(Takedown.is_dead(8)).is_true()
	assert_bool(Takedown.is_down(9)).is_false()
	assert_bool(Evidence.exists(Takedown.evidence_of(8))).is_true()
	Takedown.deserialize("junk")
	assert_int(Takedown.down_count()).is_equal(0)


# ---------------------------------------------------------------- the whole chain on a real body
func test_a_real_villager_is_taken_down_from_behind_and_dies_to_blows() -> void:
	WorldGen.setup(WorldSim.SEED)
	var keep: Array[String] = []
	var v: Villager = auto_free(Villager.create(3, "Guard", keep))
	add_child(v)
	await get_tree().process_frame
	assert_bool(v.is_in_group("villager")).is_true()
	var attacker: Node3D = auto_free(Node3D.new())
	attacker.add_to_group("player")
	add_child(attacker)
	# stand directly behind them
	var f := v.perception_facing()
	attacker.global_position = v.global_position - Vector3(f.x, 0, f.y) * 1.2
	v.take_damage(14, attacker, Vector3.ZERO)
	assert_bool(v.is_down()).is_true()
	assert_bool(v.is_dead()).is_false()                              # non-lethal
	assert_bool(v.is_in_group("villager")).is_false()
	assert_bool(Takedown.is_down(3)).is_true()
	assert_int(Evidence.kind_of(Takedown.evidence_of(3))).is_equal(Evidence.Kind.KO)
	# a bystander who was not looking (nobody here): no case. Now wake and kill face to face.
	v.wake_up()
	assert_bool(v.is_down()).is_false()
	assert_bool(v.is_in_group("villager")).is_true()
	attacker.global_position = v.global_position + Vector3(f.x, 0, f.y) * 1.2      # in front: seen coming
	var hits := 0
	while not v.is_dead() and hits < 20:
		v.take_damage(14, attacker, Vector3.ZERO)
		hits += 1
	assert_bool(v.is_dead()).is_true()
	assert_int(hits).is_greater(1)                                   # a blow hurts before it kills
	assert_bool(Takedown.is_dead(3)).is_true()
	assert_int(Evidence.kind_of(Takedown.evidence_of(3))).is_equal(Evidence.Kind.BODY)
