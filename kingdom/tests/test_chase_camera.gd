extends GdUnitTestSuite
## Responsive chase camera model (scripts/actors/chase_camera.gd) and its player.gd wiring.

const ChaseCamera := preload("res://scripts/actors/chase_camera.gd")


func _run(c: RefCounted, ctx: Dictionary, seconds: float) -> void:
	for i in int(seconds * 60.0):
		c.step(1.0 / 60.0, ctx)


func test_rests_at_base_fov() -> void:
	var c := ChaseCamera.new()
	_run(c, {}, 1.0)
	assert_float(c.fov_base()).is_equal_approx(ChaseCamera.BASE_FOV, 0.01)
	assert_float(c.dist_offset()).is_equal_approx(0.0, 0.01)


func test_sprint_widens_fov_and_pulls_back_smoothly() -> void:
	var c := ChaseCamera.new()
	var ctx := {"sprinting": true, "speed_k": 1.0}
	c.step(1.0 / 60.0, ctx)
	assert_float(c.fov_offset()).is_between(0.0, 1.0)           # eased, never a snap
	_run(c, ctx, 2.0)
	assert_float(c.fov_offset()).is_greater(ChaseCamera.SPRINT_FOV * 0.9)
	assert_float(c.dist_offset()).is_greater(ChaseCamera.SPRINT_DIST * 0.9)
	_run(c, {}, 0.3)
	assert_float(c.fov_offset()).is_greater(1.0)                # release eases away
	_run(c, {}, 3.0)
	assert_float(c.fov_offset()).is_less(0.3)


func test_walking_does_not_widen() -> void:
	var c := ChaseCamera.new()
	_run(c, {"sprinting": true, "speed_k": 0.2}, 2.0)
	assert_float(c.fov_offset()).is_less(0.5)


func test_dash_and_gallop_push_harder_than_sprint() -> void:
	var s := ChaseCamera.new()
	var d := ChaseCamera.new()
	var g := ChaseCamera.new()
	_run(s, {"sprinting": true, "speed_k": 1.0}, 2.0)
	_run(d, {"dashing": true}, 2.0)
	_run(g, {"gallop": true}, 2.0)
	assert_float(d.fov_offset()).is_greater(s.fov_offset())
	assert_float(g.fov_offset()).is_greater(s.fov_offset())
	assert_float(d.dist_offset()).is_greater(s.dist_offset())


func test_open_ground_and_rooftop_frame_higher() -> void:
	var open := ChaseCamera.new()
	var roof := ChaseCamera.new()
	var base := ChaseCamera.new()
	_run(open, {"open": true}, 3.0)
	_run(roof, {"rooftop": true}, 3.0)
	_run(base, {}, 3.0)
	assert_float(open.lift()).is_greater(base.lift() + 0.05)     # AAA pass: OPEN_LIFT 0.3 -> 0.1 (tighter framing)
	assert_float(roof.lift()).is_greater(open.lift())
	assert_float(roof.dist_offset()).is_greater(open.dist_offset())
	assert_float(open.pitch_offset()).is_less(0.0)       # looks a little further down


func test_combat_is_lower_and_tighter_and_beats_open() -> void:
	var c := ChaseCamera.new()
	_run(c, {"open": true, "combat": true}, 3.0)
	assert_float(c.dist_offset()).is_less(0.0)
	assert_float(c.lift()).is_less(0.0)
	assert_float(c.fov_offset()).is_less(0.0)


func test_locked_ignores_open_framing() -> void:
	var c := ChaseCamera.new()
	_run(c, {"open": true, "locked": true}, 3.0)
	assert_float(c.lift()).is_less_equal(0.01)


func test_accessibility_strength_zero_means_no_motion() -> void:
	var c := ChaseCamera.new()
	_run(c, {"sprinting": true, "speed_k": 1.0, "dashing": true, "open": true, "strength": 0.0}, 2.0)
	assert_float(c.fov_offset()).is_equal_approx(0.0, 0.01)
	assert_float(c.dist_offset()).is_equal_approx(0.0, 0.01)
	assert_float(c.lift()).is_equal_approx(0.0, 0.01)


func test_lock_frame_keeps_both_in_view() -> void:
	var near: Dictionary = ChaseCamera.lock_frame(2.0)
	var mid: Dictionary = ChaseCamera.lock_frame(8.0)
	var far: Dictionary = ChaseCamera.lock_frame(40.0)
	assert_float(float(mid["dist"])).is_greater(float(near["dist"]))
	assert_float(float(far["dist"])).is_greater(float(mid["dist"]))
	assert_float(float(far["dist"])).is_less_equal(3.4)           # bounded so collision still has room
	assert_float(float(far["shift"])).is_less_equal(2.2)
	assert_float(float(mid["shift"])).is_greater(float(near["shift"]))
	assert_float(float(ChaseCamera.lock_frame(-5.0)["dist"])).is_equal(0.0)


func test_fov_impulse_adds_on_top_and_decays() -> void:
	var c := ChaseCamera.new()
	_run(c, {"sprinting": true, "speed_k": 1.0}, 2.0)
	var base := c.fov_base()
	c.add_fov_impulse(4.0)
	assert_float(c.fov_total()).is_equal_approx(base + 4.0, 0.2)
	assert_float(c.fov_base()).is_equal_approx(base, 0.01)       # the base is untouched by the punch
	_run(c, {"sprinting": true, "speed_k": 1.0}, 1.5)
	assert_float(c.impulse()).is_less(0.2)


func test_fov_impulse_is_clamped() -> void:
	var c := ChaseCamera.new()
	c.add_fov_impulse(500.0)
	assert_float(c.impulse()).is_equal(ChaseCamera.IMPULSE_MAX)
	c.add_fov_impulse(-500.0)
	assert_float(c.impulse()).is_equal(ChaseCamera.IMPULSE_MIN)
	assert_float(c.fov_total()).is_less_equal(ChaseCamera.MAX_FOV)


func test_cast_camera_pushes_in_and_returns() -> void:
	var c := ChaseCamera.new()
	assert_bool(c.begin_cast()).is_true()
	assert_bool(c.begin_cast()).is_false()                        # one at a time
	var lowest := 0.0
	var closest := 0.0
	for i in 70:
		c.step(1.0 / 60.0, {})
		lowest = minf(lowest, c.fov_offset())
		closest = minf(closest, c.dist_offset())
	assert_float(lowest).is_less(-3.0)
	assert_float(closest).is_less(-0.8)
	_run(c, {}, 0.5)
	assert_bool(c.casting()).is_false()
	assert_float(c.fov_offset()).is_equal_approx(0.0, 0.05)


func test_cast_camera_is_skippable_and_toggleable() -> void:
	var c := ChaseCamera.new()
	c.begin_cast()
	_run(c, {}, 0.3)
	c.cancel_cast()
	assert_bool(c.casting()).is_false()
	assert_float(c.fov_offset()).is_equal_approx(0.0, 0.001)
	c.cast_enabled = false
	assert_bool(c.begin_cast()).is_false()


func test_big_technique_rule() -> void:
	assert_bool(ChaseCamera.is_big_technique({"tier": 3, "cooldown": 4.0})).is_true()
	assert_bool(ChaseCamera.is_big_technique({"tier": 1, "cooldown": 12.0})).is_true()
	assert_bool(ChaseCamera.is_big_technique({"tier": 1, "cooldown": 2.5})).is_false()
	assert_bool(ChaseCamera.is_big_technique({})).is_false()


# --- player wiring ------------------------------------------------------------------------

func test_player_exposes_fov_api_and_keeps_collision_stack() -> void:
	var p := Player.new()
	add_child(auto_free(p))
	assert_bool(p.has_method("add_fov_impulse")).is_true()
	assert_bool(p.has_method("locked_target")).is_true()
	assert_object(p.locked_target()).is_null()
	for i in 30:
		p._update_camera(1.0 / 60.0)
	assert_float(p.camera.fov).is_equal_approx(ChaseCamera.BASE_FOV, 0.6)
	assert_float(float(p.camera.get_meta("fov_base"))).is_equal_approx(ChaseCamera.BASE_FOV, 0.6)
	# The occlusion pass and foliage fade are still part of the camera step.
	assert_bool(p._camera_arm is SpringArm3D).is_true()
	assert_int(p._camera_arm.collision_mask).is_equal(Player.CAMERA_MASK)


func test_player_impulse_rides_above_base() -> void:
	var p := Player.new()
	add_child(auto_free(p))
	for i in 20:
		p._update_camera(1.0 / 60.0)
	var base := p.camera.fov
	p._chase.add_fov_impulse(5.0)
	for i in 4:
		p._update_camera(1.0 / 60.0)
	assert_float(p.camera.fov).is_greater(base + 1.0)
	assert_float(float(p.camera.get_meta("fov_base"))).is_equal_approx(base, 0.6)


func test_talk_framing_lifts_the_talkers_into_the_top_of_the_frame() -> void:
	# The bottom-sheet conversation covers the lower third: the lens tips down and the pivot sinks a little, so faces and
	# upper bodies sit in the top 60% (visual pass 2026-10; see tools_qa/visual_pass/talk_standalone.gd).
	var c := ChaseCamera.new()
	assert_float(c.talk_tilt()).is_equal(0.0)
	c.begin_talk()
	c.step(1.0, {})
	assert_float(c.talk_tilt()).is_equal_approx(ChaseCamera.TALK_TILT, 0.001)
	assert_float(c.talk_tilt()).is_between(0.08, 0.25)           # enough to clear the sheet, never a dutch-angle lurch
	assert_float(c.lift()).is_less(0.0)                          # the pivot sinks: the talkers ride higher
	c.end_talk()
	c.step(1.0, {})
	assert_float(c.talk_tilt()).is_equal_approx(0.0, 0.001)


func test_talk_framing_off_means_no_tilt() -> void:
	var c := ChaseCamera.new()
	c.talk_enabled = false
	c.begin_talk()
	c.step(1.0, {})
	assert_float(c.talk_tilt()).is_equal(0.0)
