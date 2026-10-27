extends GdUnitTestSuite
## combat_reactions.gd: direction x strength x guard state picks the matching Mixamo set-4 reaction.

const R := preload("res://scripts/combat/combat_reactions.gd")
const Chains := preload("res://scripts/combat/combat_chains.gd")


func test_direction_and_strength() -> void:
	assert_str(R.react("Left", 1.0)).is_equal("Mx4_ReactSmallLeft")
	assert_str(R.react("Back", 3.0)).is_equal("Mx4_ReactLargeBack")
	assert_str(R.react("Front", 5.0, false, 1)).is_equal("Mx4_ShoveReactionStanding")
	assert_str(R.react("??", 1.0)).is_equal("Mx4_ReactSmallFront")


func test_guarding_gets_a_block_react_not_a_flesh_hit() -> void:
	assert_str(R.react("Front", 1.0, true)).is_equal(R.BLOCK_SMALL)
	assert_str(R.react("Front", 6.0, true)).is_equal(R.BLOCK_LARGE)


func test_death_falls_away_from_the_blow() -> void:
	assert_str(R.death("Front")).is_equal("Mx4_DeathReactBackward")
	assert_str(R.death("Back")).is_equal("Mx4_DeathFallingForward")
	assert_str(R.death("Left")).is_equal("Mx4_DeathReactRight")


func test_every_clip_exists_in_the_measured_library() -> void:
	var m := Chains.markers()
	for d: Dictionary in [R.SMALL, R.LARGE]:
		for k in d:
			assert_bool(m.has(String(d[k]))).override_failure_message(String(d[k])).is_true()
	for k in R.DEATH:
		for c in R.DEATH[k]:
			assert_bool(m.has(String(c))).override_failure_message(String(c)).is_true()
	assert_bool(m.has(R.BLOCK_LARGE) and m.has(R.BLOCK_SMALL)).is_true()


func test_player_react_falls_back_without_animator() -> void:
	var PCM := preload("res://scripts/combat/player_combat_motion.gd")
	var n: Node = auto_free(Node.new())
	assert_bool(PCM.react(n, "Front", Vector3.ZERO, false)).is_false()
