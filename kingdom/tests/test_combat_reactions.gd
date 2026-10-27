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


func test_dodge_speed_follows_the_clip_curve_and_distance() -> void:
	var PCM := preload("res://scripts/combat/player_combat_motion.gd")
	var prof := PackedVector3Array()
	for i in 31:
		var t := i / 30.0
		prof.append(Vector3(0, 0, -2.0 * smoothstep(0.0, 1.0, t)))     # 2 m back over 1 s, ease in/out
	var total := 0.0
	var dt := 1.0 / 120.0
	var e := 0.0
	while e < PCM.DODGE_PLAY_S:
		total += PCM.speed_from_profile(prof, 1.0, 1.5, e) * dt
		e += dt
	assert_float(total).is_equal_approx(1.5, 0.12)        # scaled to the dodge distance
	assert_float(PCM.speed_from_profile(prof, 1.0, 1.5, PCM.DODGE_PLAY_S * 0.5)).is_greater(PCM.speed_from_profile(prof, 1.0, 1.5, 0.0))


func test_masked_back_dodge_keeps_travel_and_holds_arms() -> void:
	var PCM := preload("res://scripts/combat/player_combat_motion.gd")
	var src := Animation.new()
	src.length = 1.5
	var r := src.add_track(Animation.TYPE_POSITION_3D)
	src.track_set_path(r, NodePath("Skeleton3D:root"))
	src.position_track_insert_key(r, 0.0, Vector3.ZERO)
	src.position_track_insert_key(r, 0.5, Vector3.ZERO)
	src.position_track_insert_key(r, 1.0, Vector3(0, 0, -1.0))
	src.position_track_insert_key(r, 1.5, Vector3(0, 0, -1.0))
	var a := src.add_track(Animation.TYPE_ROTATION_3D)
	src.track_set_path(a, NodePath("Skeleton3D:upperarm_r"))
	src.rotation_track_insert_key(a, 0.0, Quaternion(Vector3.UP, 1.0))
	var g := Animation.new()
	g.length = 1.0
	var ga := g.add_track(Animation.TYPE_ROTATION_3D)
	g.track_set_path(ga, NodePath("Skeleton3D:upperarm_r"))
	g.rotation_track_insert_key(ga, 0.0, Quaternion(Vector3.RIGHT, 0.5))
	var out := PCM.build_masked(src, g)
	assert_float(out.length).is_less(1.2)                         # trimmed to the travel window
	var t := out.find_track(NodePath("Skeleton3D:upperarm_r"), Animation.TYPE_ROTATION_3D)
	assert_float(out.rotation_track_interpolate(t, 0.2).angle_to(Quaternion(Vector3.RIGHT, 0.5))).is_less(0.01)
	var p := out.find_track(NodePath("Skeleton3D:root"), Animation.TYPE_POSITION_3D)
	var travel := out.position_track_interpolate(p, out.length) - out.position_track_interpolate(p, 0.0)
	assert_float(travel.length()).is_greater(0.8)
