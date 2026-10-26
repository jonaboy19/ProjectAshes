extends GdUnitTestSuite
## WallContact.classify (pure) and the hand choice. Head-on at a standstill braces, an angled push glances, a sprint into the
## wall is an impact, walking away does nothing and a wall out of arm's reach gives no hand.

const Wall := preload("res://scripts/actors/wall_contact.gd")

const N := Vector3(0.0, 0.0, 1.0)            # the wall faces +Z, so the body walks toward -Z into it
const HEAD_ON := Vector3(0.0, 0.0, -1.0)


func test_head_on_standstill_is_brace() -> void:
	assert_str(String(Wall.classify(HEAD_ON, N, 0.0, 0.0))).is_equal("brace")
	assert_str(String(Wall.classify(HEAD_ON, N, 0.2, 0.05))).is_equal("brace")


func test_head_on_walk_with_room_is_approach_and_far_is_none() -> void:
	assert_str(String(Wall.classify(HEAD_ON, N, 1.4, 0.3))).is_equal("approach")
	assert_str(String(Wall.classify(HEAD_ON, N, 1.4, 0.05))).is_equal("glance")      # touching but still moving (a ramp, a slow slide): not blocked
	assert_str(String(Wall.classify(HEAD_ON, N, 1.4, 3.0))).is_equal("none")
	assert_str(String(Wall.classify(HEAD_ON, N, 0.0, 0.12))).is_equal("brace")       # stopped at the stop gap: braced, not still approaching
	assert_str(String(Wall.classify(HEAD_ON, N, 7.0, 0.8))).is_equal("none")          # a sprint does not ease down: it hits the wall


func test_forty_five_degrees_is_glance() -> void:
	var d := Vector3(1.0, 0.0, -1.0).normalized()
	assert_str(String(Wall.classify(d, N, 2.0, 0.0))).is_equal("glance")


func test_sprint_head_on_is_impact() -> void:
	assert_str(String(Wall.classify(HEAD_ON, N, 0.0, 0.05, 7.0))).is_equal("impact")
	assert_str(String(Wall.classify(HEAD_ON, N, 0.0, 0.05, 5.0))).is_equal("brace")        # a slower approach only braces


func test_walking_away_or_along_the_wall_is_none() -> void:
	assert_str(String(Wall.classify(-HEAD_ON, N, 2.0, 0.0))).is_equal("none")
	assert_str(String(Wall.classify(Vector3(1.0, 0.0, 0.0), N, 2.0, 0.0))).is_equal("none")
	assert_str(String(Wall.classify(Vector3.ZERO, N, 0.0, 0.0))).is_equal("none")


func test_hands_need_the_wall_inside_arms_reach() -> void:
	# reach is the shoulder-to-wall distance in metres (reach_min 0.3 .. reach_max 0.7); a body pressed to the wall is 0.35 away
	assert_array(Wall.hands_for(0.0, 0.2)).is_equal([0.0, 0.0])      # too close to reach out
	assert_array(Wall.hands_for(0.0, 0.9)).is_equal([0.0, 0.0])      # out of reach
	assert_array(Wall.hands_for(0.0, 0.55)).is_equal([1.0, 1.0])     # head-on: both hands
	assert_array(Wall.hands_for(0.8, 0.55)).is_equal([1.0, 0.0])     # wall on the left: the left hand
	assert_array(Wall.hands_for(-0.8, 0.55)).is_equal([0.0, 1.0])


func test_config_matches_the_json() -> void:
	var c: Dictionary = Wall.config()
	assert_float(float(c["impact_speed"])).is_equal(6.0)
	assert_float(float(c["reach_min"])).is_equal(0.3)
	assert_float(float(c["reach_max"])).is_equal(0.7)
	assert_float(float(c["blend_in"])).is_equal(0.15)


func test_a_slope_steeper_than_the_floor_limit_is_a_wall_but_a_walkable_one_is_not() -> void:
	var steep := Vector3(sin(deg_to_rad(45.0)), cos(deg_to_rad(45.0)), 0.0)        # exactly the CharacterBody floor limit
	var walkable := Vector3(sin(deg_to_rad(30.0)), cos(deg_to_rad(30.0)), 0.0)
	assert_bool(Wall._is_wall(steep)).is_true()
	assert_bool(Wall._is_wall(Vector3.RIGHT)).is_true()
	assert_bool(Wall._is_wall(walkable)).is_false()
	assert_bool(Wall._is_wall(Vector3.UP)).is_false()
	assert_bool(Wall._is_wall(Vector3.DOWN)).is_false()          # a ceiling
