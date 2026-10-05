extends GdUnitTestSuite
## Crime witnessing as a task (scripts/population/witness.gd): who SAW the culprit comes from perception (light,
## stance, distance, cone), the crime commits to Society only when a witness reaches a guard or after the timeout,
## and silenced / outrun witnesses leave it unreported. Evidence registry (scripts/population/evidence.gd).

const Witness := preload("res://scripts/population/witness.gd")
const Evidence := preload("res://scripts/population/evidence.gd")
const Perception := preload("res://scripts/population/perception.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const Hub := preload("res://scripts/realm/realm_hub.gd")


class FakeSociety extends RefCounted:
	var calls: Array = []
	var evidence: Array = []

	func commit_crime(kind: String, sid: int, witnesses: Variant = 0, opts: Dictionary = {}) -> Dictionary:
		calls.append({"kind": kind, "sid": sid, "witnesses": witnesses, "opts": opts})
		return {"ok": true, "kind": kind, "noticed": (witnesses as Array).size()}

	func add_evidence(crime: String, type: String, strength: float, sid: int) -> String:
		evidence.append([crime, type, strength, sid])
		return "e%d" % evidence.size()


func before_test() -> void:
	NpcWorld.reset()
	Perception.reset()
	Witness.reset()
	Evidence.reset()


func _w(person: int, vis := 0.6, guard := false) -> Dictionary:
	return {"id": "anon:0:%d" % person, "person": person, "vis": vis, "guard": guard}


# ---------------------------------------------------------------- the reporting task
func test_a_witness_who_reaches_a_guard_commits_the_crime_once() -> void:
	var soc := FakeSociety.new()
	var id := Witness.begin("robbery", 0, Vector2(5, 5), [_w(1), _w(2)], 1000, soc)
	assert_int(id).is_greater(0)
	assert_str(Witness.status(id)).is_equal("pending")
	assert_int(soc.calls.size()).is_equal(0)         # nothing committed while they are still running
	assert_bool(Witness.is_running(1)).is_true()
	assert_bool(Witness.deliver(1, 4000, soc)).is_true()
	assert_str(Witness.status(id)).is_equal("committed")
	assert_int(soc.calls.size()).is_equal(1)
	# The second witness arriving later must not commit again.
	Witness.deliver(2, 6000, soc)
	Witness.tick(60000, soc)
	assert_int(soc.calls.size()).is_equal(1)
	assert_array(soc.calls[0]["witnesses"]).is_equal(["anon:0:1"])


func test_silenced_or_outrun_witnesses_leave_the_crime_unreported() -> void:
	var soc := FakeSociety.new()
	var id := Witness.begin("murder", 0, Vector2.ZERO, [_w(1), _w(2), _w(3)], 0, soc)
	assert_bool(Witness.silence(1, 2000, soc)).is_true()       # killed
	assert_bool(Witness.abandon(2, 3000, soc)).is_true()       # fled and hid
	assert_str(Witness.status(id)).is_equal("pending")          # one still running
	Witness.silence(3, 4000, soc)                               # knocked out
	assert_str(Witness.status(id)).is_equal("unreported")
	Witness.tick(10 * 60 * 1000, soc)                           # no timeout rescue either
	assert_int(soc.calls.size()).is_equal(0)
	assert_bool(Witness.deliver(1, 5000, soc)).is_false()


func test_timeout_commits_when_a_witness_is_still_running() -> void:
	var soc := FakeSociety.new()
	var id := Witness.begin("assault", 0, Vector2.ZERO, [_w(1)], 1000, soc)
	Witness.tick(1000 + Witness.TIMEOUT_MS - 1, soc)
	assert_str(Witness.status(id)).is_equal("pending")
	Witness.tick(1000 + Witness.TIMEOUT_MS, soc)
	assert_str(Witness.status(id)).is_equal("committed")
	assert_int(soc.calls.size()).is_equal(1)


func test_guards_who_saw_it_report_at_once_and_unseen_means_no_case() -> void:
	var soc := FakeSociety.new()
	var id := Witness.begin("pickpocket", 0, Vector2.ZERO, [_w(1, 0.5, true)], 0, soc)
	assert_str(Witness.status(id)).is_equal("committed")
	# Heard-only people (vis below the seen threshold) are not witnesses: no case, nothing committed.
	assert_int(Witness.begin("pickpocket", 0, Vector2.ZERO, [_w(2, 0.05)], 0, soc)).is_equal(0)
	assert_int(soc.calls.size()).is_equal(1)


func test_society_gets_real_ids_and_visibility_not_the_flat_roll() -> void:
	WorldGen.setup(WorldSim.SEED)
	var soc: RefCounted = Hub.new().mod("society")
	var before := (soc.get("crimes") as Array).size()
	var id := Witness.begin("robbery", 0, Vector2.ZERO, [_w(1, 0.9), _w(2, 0.2), _w(3, 0.5)], 0, soc)
	for p in [1, 2, 3]:
		Witness.deliver(p, 100, soc)
	assert_str(Witness.status(id)).is_equal("committed")
	var crimes: Array = soc.get("crimes")
	assert_int(crimes.size()).is_equal(before + 1)
	# Everyone given to Society was seen (perception decided), none lost to a flat 0.55 night roll.
	assert_int(int(Witness.last_result["witnesses"])).is_equal(int(Witness.last_result["noticed"]))


# ---------------------------------------------------------------- the scenario: day vs night crouched
func _witnesses_of_theft(hour: float, stance: float) -> int:
	Perception.set_environment(hour)
	var crime := Vector2(0, 0)
	var light := Perception.light_at(crime, 0)
	var seen := 0
	for i in 12:
		var ang := float(i) / 12.0 * TAU
		var d := 3.0 + float(i) * 1.6                    # 3 .. 20.6 m, all looking at the thief
		var pos := Vector2(cos(ang), sin(ang)) * d
		var facing := (crime - pos).normalized()
		if Witness.sight(pos, facing, 1.0, crime, light, stance) >= Witness.SEEN_VIS:
			seen += 1
	return seen


func test_theft_in_daylight_has_more_witnesses_than_crouched_at_night() -> void:
	var day := _witnesses_of_theft(13.0, Perception.STANCE_WALK)
	var night_crouch := _witnesses_of_theft(1.0, Perception.STANCE_CROUCH)
	var night_walk := _witnesses_of_theft(1.0, Perception.STANCE_WALK)
	print("SCENARIO witnesses: daylight walking %d, night walking %d, night crouched %d" % [day, night_walk, night_crouch])
	assert_int(day).is_greater(night_walk)
	assert_int(night_walk).is_greater_equal(night_crouch)
	assert_int(day).is_greater(night_crouch + 4)
	# A torch at the scene brings the witnesses back.
	Perception.register_light(Vector2(0, 1), 12.0, 0.6)
	assert_int(_witnesses_of_theft(1.0, Perception.STANCE_CROUCH)).is_greater(night_crouch)


func test_scenario_witness_stopped_before_the_guard_records_no_crime() -> void:
	WorldGen.setup(WorldSim.SEED)
	var soc: RefCounted = Hub.new().mod("society")
	var crimes: Array = soc.get("crimes")
	var before := crimes.size()
	var rep_before := int(soc.call("crim_rep", "city:0") * 100.0)
	# Two witnesses saw the theft by daylight; the thief catches and silences both before either reaches the watch.
	var id := Witness.begin("robbery", 0, Vector2(2, 2), [_w(10), _w(11)], 0, soc)
	assert_str(Witness.status(id)).is_equal("pending")
	Witness.silence(10, 3000, soc)
	Witness.silence(11, 4000, soc)
	Witness.tick(60000, soc)
	assert_str(Witness.status(id)).is_equal("unreported")
	assert_int((soc.get("crimes") as Array).size()).is_equal(before)
	assert_int(int(soc.call("crim_rep", "city:0") * 100.0)).is_equal(rep_before)
	# The same crime with one witness reaching the guard IS recorded.
	var id2 := Witness.begin("robbery", 0, Vector2(2, 2), [_w(12)], 0, soc)
	Witness.deliver(12, 5000, soc)
	assert_str(Witness.status(id2)).is_equal("committed")
	assert_int((soc.get("crimes") as Array).size()).is_equal(before + 1)


# ---------------------------------------------------------------- evidence
func test_crimes_leave_traces_and_each_person_discovers_each_once() -> void:
	var ids := Evidence.leave_traces("murder", Vector2(10, 10), 0, 0)
	assert_int(ids.size()).is_equal(2)
	assert_int(Evidence.count).is_equal(2)
	assert_int(Evidence.leave_traces("pickpocket", Vector2(0, 0), 0, 0).size()).is_equal(1)
	var found := Evidence.nearest_unseen(Vector2(12, 10), 12.0, 7)
	assert_int(found).is_greater(0)
	Evidence.mark_seen(found, 7)
	var next := Evidence.nearest_unseen(Vector2(12, 10), 12.0, 7)
	assert_int(next).is_not_equal(found)
	Evidence.mark_seen(next, 7)
	assert_int(Evidence.nearest_unseen(Vector2(12, 10), 12.0, 7)).is_equal(0)
	assert_int(Evidence.nearest_unseen(Vector2(12, 10), 12.0, 8)).is_greater(0)     # someone else still can
	assert_int(Evidence.nearest_unseen(Vector2(300, 300), 12.0, 9)).is_equal(0)


func test_discovery_feeds_society_once_and_reaction_delay_is_bounded() -> void:
	var soc := FakeSociety.new()
	var id := Evidence.add(Evidence.Kind.BODY, Vector2.ZERO, 3, 0, "c1")
	assert_str(Evidence.feed(id, soc)).is_not_empty()
	assert_str(Evidence.feed(id, soc)).is_empty()
	assert_int(soc.evidence.size()).is_equal(1)
	assert_str(soc.evidence[0][1]).is_equal("blood")
	for p in 40:
		var d := Evidence.reaction_delay_ms(p, id)
		assert_int(d).is_greater_equal(Evidence.DELAY_MIN_MS)
		assert_int(d).is_less(Evidence.DELAY_MIN_MS + Evidence.DELAY_SPAN_MS)
	assert_int(Evidence.reaction_delay_ms(5, id)).is_equal(Evidence.reaction_delay_ms(5, id))


func test_registry_is_bounded_prunes_and_round_trips() -> void:
	for i in Evidence.MAX + 10:
		Evidence.add(Evidence.Kind.BLOOD, Vector2(float(i), 0), 0, i)
	assert_int(Evidence.count).is_equal(Evidence.MAX)
	var rows := Evidence.serialize()
	assert_int(rows.size()).is_equal(Evidence.MAX)
	Evidence.reset()
	Evidence.deserialize(JSON.parse_string(JSON.stringify(rows)), 0)
	assert_int(Evidence.count).is_equal(Evidence.MAX)
	Evidence.deserialize(["junk", [99, 0, 0, 0], 5], 0)      # garbage ignored
	assert_int(Evidence.count).is_equal(0)
	Evidence.add(Evidence.Kind.BODY, Vector2.ZERO, 0, 0)
	Evidence.add(Evidence.Kind.BLOOD, Vector2.ZERO, 0, 0)
	assert_int(Evidence.prune(Evidence.LIFETIME_MS / 2 + 1)).is_equal(1)      # blood dries first
	assert_int(Evidence.prune(Evidence.LIFETIME_MS + 1)).is_equal(1)
