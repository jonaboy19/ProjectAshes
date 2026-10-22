extends GdUnitTestSuite
## Search with claimed hiding spots (scripts/population/search.gd): spots of the smart-object type "search" placed
## around a town, one Search record per alarm event, searchers claim distinct spots (cap 2), check them, give up on
## time, and a crouched player hidden in a spot is found by proximity and light.

const Search := preload("res://scripts/population/search.gd")
const Perception := preload("res://scripts/population/perception.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")

var so: SmartObjects


func before_test() -> void:
	NpcWorld.reset()
	Perception.reset()
	so = NpcWorld.spots()


func _plan() -> Dictionary:
	var lots: Array = []
	for i in 12:
		lots.append({"asset": "barn" if i == 5 else "house_a", "pos": Vector2(20 + i * 9, 10 + (i % 3) * 8), "yaw": float(i) * 0.4})
	return {"lots": lots}


func _stalls() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 6:
		out.append(Vector2(50, 40) + Vector2(cos(float(i)), sin(float(i))) * 9.0)
	return out


func _populate(sid := 0) -> int:
	return Search.populate(so, sid, _plan(), Vector2(50, 40), 12.0, 70.0, _stalls())


# ---------------------------------------------------------------- spots
func test_search_is_a_smart_object_type_and_populate_covers_every_kind() -> void:
	assert_bool(so.types.has("search")).is_true()
	var n := _populate()
	assert_int(n).is_greater(10)
	assert_int(Search.spot_count(0)).is_equal(n)
	var kinds := {}
	for id in Search.spots_near(Vector2(50, 40), 200.0):
		kinds[Search.spot_kind(id)] = true
		assert_str(String(so.spots[id]["type"])).is_equal("search")
	for k in [Search.Kind.DOORWAY, Search.Kind.ALLEY, Search.Kind.BEHIND_STALL, Search.Kind.HAYSTACK, Search.Kind.CRATE]:
		assert_bool(kinds.has(k)).is_true()


func test_populate_is_deterministic_and_idempotent_by_identity() -> void:
	var a := _populate()
	var b := _populate()                    # same stable identities: SmartObjects returns the existing spots
	assert_int(a).is_equal(b)
	assert_int(so.spots.size()).is_equal(a)


# ---------------------------------------------------------------- one record per alarm event
func test_one_search_per_event_and_nearby_alarms_join_it() -> void:
	_populate()
	var a := Search.begin(Vector2(55, 40), 0, 1000, 7)
	assert_int(Search.begin(Vector2(200, 200), 0, 1100, 7)).is_equal(a)          # same event id
	assert_int(Search.begin(Vector2(58, 43), 0, 1200, 9)).is_equal(a)            # within MERGE_R of a live one
	var far := Search.begin(Vector2(400, 400), 0, 1300, 11)
	assert_int(far).is_not_equal(a)
	assert_int(Search.active_count(1500)).is_equal(2)
	assert_bool(Search.is_active(a, 1500)).is_true()


func test_searchers_claim_distinct_spots_capped_at_two() -> void:
	_populate()
	var id := Search.begin(Vector2(55, 40), 0, 0, 1)
	var s1 := Search.claim(id, 101, Vector2(50, 30), so)
	var s2 := Search.claim(id, 102, Vector2(52, 31), so)
	var s3 := Search.claim(id, 103, Vector2(53, 32), so)
	assert_int(s1).is_greater_equal(0)
	assert_int(s2).is_greater_equal(0)
	assert_int(s2).is_not_equal(s1)
	assert_int(s3).is_equal(-1)                                  # the third holds its post
	assert_int(Search.claim(id, 101, Vector2.ZERO, so)).is_equal(s1)      # idempotent
	assert_int(so.occupancy(s1)).is_equal(1)
	assert_int(Search.searchers(id)).is_equal(2)
	# The smart-object claim itself refuses a spot somebody else holds.
	assert_bool(so.claim(s1, 0, 999)).is_false()


func test_check_then_next_spot_and_finished_search_ends() -> void:
	_populate()
	var id := Search.begin(Vector2(55, 40), 0, 0, 1, 6.0)           # a tiny radius: a few spots only
	var total := Search.unchecked(id)
	assert_int(total).is_greater(0)
	var seen := {}
	var guard := 0
	while Search.unchecked(id) > 0 and guard < 60:
		guard += 1
		var sp := Search.claim(id, 101, Vector2(55, 40), so)
		assert_int(sp).is_greater_equal(0)
		assert_bool(seen.has(sp)).is_false()                         # never the same spot twice
		seen[sp] = true
		assert_int(Search.finish_check(101, so)).is_equal(sp)
		assert_int(so.occupancy(sp)).is_equal(0)                     # released for others
	assert_int(seen.size()).is_equal(total)
	assert_int(Search.claim(id, 101, Vector2.ZERO, so)).is_equal(-1)  # nothing left
	var ended := Search.tick(500, so)
	assert_array(ended).contains([id])
	assert_str(Search.state_of(id)).is_equal("done")


func test_searchers_give_up_after_the_time_and_release_their_spots() -> void:
	_populate()
	var id := Search.begin(Vector2(55, 40), 0, 0, 1)
	var sp := Search.claim(id, 101, Vector2(55, 40), so)
	assert_int(Search.tick(int(Search.SEARCH_SECONDS * 1000.0) - 1, so).size()).is_equal(0)
	assert_bool(Search.is_active(id, 1000)).is_true()
	var ended := Search.tick(int(Search.SEARCH_SECONDS * 1000.0) + 1, so)
	assert_array(ended).contains([id])
	assert_str(Search.state_of(id)).is_equal("expired")
	assert_int(Search.search_of(101)).is_equal(0)
	assert_int(so.occupancy(sp)).is_equal(0)
	assert_bool(Search.is_active(id, int(Search.SEARCH_SECONDS * 1000.0) + 2)).is_false()


func test_join_extends_the_deadline() -> void:
	_populate()
	var id := Search.begin(Vector2(55, 40), 0, 0, 1)
	Search.begin(Vector2(56, 40), 0, 30000, 2)
	assert_array(Search.tick(60000, so)).is_empty()                  # 30 s + 45 s > 60 s
	assert_array(Search.tick(80000, so)).contains([id])


# ---------------------------------------------------------------- hiding and finding the player
func test_player_hides_only_crouched_and_close_to_a_spot() -> void:
	_populate()
	var sp: int = Search.spots_near(Vector2(50, 40), 200.0)[0]
	var at := Search.spot_pos(sp)
	assert_int(Search.hidden_spot(at + Vector2(0.5, 0), true)).is_equal(sp)
	assert_int(Search.hidden_spot(at + Vector2(0.5, 0), false)).is_equal(-1)      # standing is not hiding
	assert_int(Search.hidden_spot(at + Vector2(6, 0), true)).is_equal(-1)


func test_hidden_player_is_nearly_invisible_to_sight() -> void:
	_populate()
	var sp: int = Search.spots_near(Vector2(50, 40), 200.0)[0]
	NpcWorld.set_player_hide_spot(sp)
	assert_float(NpcWorld.player_stance()).is_equal(Perception.STANCE_HIDDEN)
	Perception.set_environment(13.0)
	var npc := Vector2(0, 0)
	var target := Vector2(0, 7.0)
	var open := Perception.vis(npc, Vector2(0, 1), target, 1.0, Perception.STANCE_CROUCH)
	var hidden := Perception.vis(npc, Vector2(0, 1), target, 1.0, NpcWorld.player_stance())
	assert_float(hidden).is_less(open * 0.6)
	assert_float(hidden).is_less(0.2)
	NpcWorld.set_player_hide_spot(-1)
	assert_float(NpcWorld.player_stance()).is_equal(Perception.stance_term(false, false, false))


func test_found_by_checking_or_by_walking_close_in_light() -> void:
	_populate()
	var sp: int = Search.spots_near(Vector2(50, 40), 200.0)[0]
	var at := Search.spot_pos(sp)
	# checking the spot finds anyone inside, light or not
	assert_bool(Search.found(sp, at + Vector2(1.5, 0), 0.1, true)).is_true()
	assert_bool(Search.found(sp, at + Vector2(3.0, 0), 0.1, true)).is_false()      # not at the spot
	# walking by: needs to be close AND lit
	assert_bool(Search.found(sp, at + Vector2(1.0, 0), 1.0, false)).is_true()
	assert_bool(Search.found(sp, at + Vector2(1.0, 0), 0.1, false)).is_false()     # dark: passes by
	assert_bool(Search.found(sp, at + Vector2(3.5, 0), 1.0, false)).is_false()     # too far even in daylight
	assert_bool(Search.found(sp, at + Vector2(6.0, 0), 1.0, true)).is_false()
	# light helps at the margin
	assert_bool(Search.found(sp, at + Vector2(2.0, 0), 1.0, false)).is_true()
	assert_bool(Search.found(sp, at + Vector2(2.0, 0), 0.2, false)).is_false()


# ---------------------------------------------------------------- the world hook the brain uses
func test_search_goal_claims_a_spot_and_holds_when_capped() -> void:
	_populate()
	Perception.bind(201, 1.2, true)
	Perception.bind(202, 1.2, true)
	Perception.bind(203, 1.2, true)
	var g1 := NpcWorld.search_goal(201, Vector2(50, 30), Vector2(55, 40), 0)
	var g2 := NpcWorld.search_goal(202, Vector2(52, 30), Vector2(55, 40), 0)
	var g3 := NpcWorld.search_goal(203, Vector2(53, 30), Vector2(55, 40), 0)
	assert_int(g1.size()).is_equal(2)
	assert_int(g2.size()).is_equal(2)
	assert_bool((g1[0] as Vector2).is_equal_approx(g2[0])).is_false()
	assert_array(g3).is_empty()                                            # hold
	assert_int(Search.active_count(Time.get_ticks_msec())).is_equal(1)     # one record for the event
	assert_array(NpcWorld.search_goal(201, Vector2.ZERO, Vector2.INF, 0)).is_empty()


# ---------------------------------------------------------------- persistence
func test_save_round_trip_of_live_searches() -> void:
	_populate()
	Search.begin(Vector2(55, 40), 0, 1000, 5)
	Search.begin(Vector2(300, 300), 0, 1000, 6)
	var rows := Search.serialize(11000)
	assert_int(rows.size()).is_equal(2)
	Search.searches.clear()
	Search.deserialize(rows, 20000)
	assert_int(Search.active_count(20001)).is_equal(2)
	assert_bool(Search.is_active(Search.begin(Vector2(55, 40), 0, 20002, 5), 20003)).is_true()
	assert_int(Search.active_count(20003)).is_equal(2)                    # joined, not duplicated
	Search.deserialize("garbage", 0)
	assert_int(Search.searches.size()).is_equal(0)
