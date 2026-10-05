extends GdUnitTestSuite
## F2 traversal: obstacle classification per height band, landing / headroom checks, the context-button
## provider and the picker, scripted move timings (the player ends on top and never overlaps the obstacle),
## ledge hang -> climb / drop, ladder over time, and stair step-up.

const Traversal := preload("res://scripts/actors/traversal.gd")
const Picker := preload("res://scripts/interaction/interaction_picker.gd")
const PlayerScript := preload("res://scripts/actors/player.gd")
const LadderScript := preload("res://scripts/interaction/kinds/ladder.gd")

const FWD := Vector3(0.0, 0.0, -1.0)
const DT := 1.0 / 60.0

var _root: Node3D


## A body the Driver can steer (the Player's private state the Driver reads, none of its scene).
class Mover extends CharacterBody3D:
	var _move_speed := 0.0
	var _move_dir := Vector3(0.0, 0.0, -1.0)
	var _trav: RefCounted
	var _pivot: Node3D
	var _model: Node3D


func before_test() -> void:
	_root = auto_free(Node3D.new())
	add_child(_root)
	_box(Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0))       # floor, top at y = 0


func _box(center: Vector3, size: Vector3, rot := Vector3.ZERO) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	_root.add_child(b)
	b.position = center
	b.rotation = rot
	return b


## An obstacle `h` high and `depth` deep whose near face is 1.0 m in front of the origin (towards -Z).
func _obstacle(h: float, depth: float, width := 4.0) -> StaticBody3D:
	return _box(Vector3(0.0, h * 0.5, -1.0 - depth * 0.5), Vector3(width, h, depth))


func _mover() -> Mover:
	var m := Mover.new()
	m.collision_layer = 0
	m.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	m.add_child(cs)
	_root.add_child(m)
	m.global_position = Vector3.ZERO
	return m


func _space() -> PhysicsDirectSpaceState3D:
	return _root.get_world_3d().direct_space_state


func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _probe(can_jump := true) -> Dictionary:
	await _settle()
	return Traversal.probe(_space(), Vector3.ZERO, FWD, [], can_jump)


# --- classification --------------------------------------------------------------------------------------------

func test_classify_pure_bands() -> void:
	assert_str(String(Traversal.classify(0.8, 0.3, true, true))).is_equal("vault")
	assert_str(String(Traversal.classify(0.8, 1.2, true, true))).is_equal("mantle_low")      # deep: mantle, not vault
	assert_str(String(Traversal.classify(1.15, 1.2, true, true))).is_equal("mantle_low")
	assert_str(String(Traversal.classify(1.5, 1.0, true, true))).is_equal("mantle_high")
	assert_str(String(Traversal.classify(2.3, 1.0, true, true, true))).is_equal("ledge")
	assert_str(String(Traversal.classify(2.3, 1.0, true, true, false))).is_equal("none")     # a ledge needs a jump
	assert_str(String(Traversal.classify(2.8, 1.0, true, true))).is_equal("none")            # too tall
	assert_str(String(Traversal.classify(0.3, 1.0, true, true))).is_equal("none")            # a step, not an obstacle
	assert_str(String(Traversal.classify(1.5, 1.0, false, true))).is_equal("none")           # no room on top
	assert_str(String(Traversal.classify(0.8, 0.3, true, false))).is_equal("none")           # no landing, too thin to stand on


func test_probe_thin_low_wall_is_a_vault() -> void:
	_obstacle(0.8, 0.3)
	var r: Dictionary = await _probe()
	assert_str(String(r["kind"])).is_equal("vault")
	assert_float(float(r["height"])).is_equal_approx(0.8, 0.02)
	assert_float(float(r["depth"])).is_equal_approx(0.3, 0.04)
	assert_float(float(r["perp"])).is_equal_approx(1.0, 0.02)
	assert_bool(bool(r["landing_ok"])).is_true()


func test_probe_deep_low_block_is_a_low_mantle() -> void:
	_obstacle(1.0, 1.4)
	var r: Dictionary = await _probe()
	assert_str(String(r["kind"])).is_equal("mantle_low")
	assert_float(float(r["height"])).is_equal_approx(1.0, 0.02)


func test_probe_high_wall_is_a_high_mantle() -> void:
	_obstacle(1.7, 1.0)
	var r: Dictionary = await _probe()
	assert_str(String(r["kind"])).is_equal("mantle_high")


func test_probe_ledge_needs_a_jump_and_is_none_above_the_band() -> void:
	var b := _obstacle(2.3, 1.0)
	var r: Dictionary = await _probe(true)
	assert_str(String(r["kind"])).is_equal("ledge")
	r = await _probe(false)
	assert_str(String(r["kind"])).is_equal("none")
	b.queue_free()
	_obstacle(2.9, 1.0)
	r = await _probe(true)
	assert_str(String(r["kind"])).is_equal("none")


func test_probe_nothing_or_a_kerb_is_none() -> void:
	var r: Dictionary = await _probe()
	assert_str(String(r["kind"])).is_equal("none")
	_obstacle(0.3, 1.0)
	r = await _probe()
	assert_str(String(r["kind"])).is_equal("none")


func test_blocked_landing_is_none() -> void:
	var wall := _obstacle(0.8, 0.3)
	var r: Dictionary = await _probe()
	assert_str(String(r["kind"])).is_equal("vault")
	# A tall crate right behind the wall: nowhere to land.
	_box(Vector3(0.0, 1.0, -2.0), Vector3(4.0, 2.0, 0.6))
	r = await _probe()
	assert_bool(bool(r["landing_ok"])).is_false()
	assert_str(String(r["kind"])).is_equal("none")
	assert_object(wall).is_not_null()


func test_low_ceiling_over_the_top_blocks_a_mantle() -> void:
	_obstacle(1.5, 1.2)
	_box(Vector3(0.0, 2.6, -1.6), Vector3(4.0, 0.2, 1.0))       # slab 1.0 m above the top
	var r: Dictionary = await _probe()
	assert_bool(bool(r["top_clear"])).is_false()
	assert_str(String(r["kind"])).is_equal("none")


# --- context button -------------------------------------------------------------------------------------------

func test_provider_offers_vault_and_picker_prefers_it_over_a_farther_interactable() -> void:
	_obstacle(0.8, 0.3)
	await _settle()
	var m := _mover()
	var drv := Traversal.Driver.new(m)
	var cands := drv.candidates(m.global_position, FWD)
	assert_int(cands.size()).is_equal(1)
	assert_str(String(cands[0]["verb"])).is_equal("Vault")
	var far := {"id": "other/door", "pos": Vector3(0.0, 0.0, 2.6), "verb": "Open", "priority": 0}
	var best := Picker.pick(m.global_position, FWD, [far], [Callable(drv, "candidates")])
	assert_str(String(best["id"])).is_equal("traversal/vault")
	assert_str(String(Interaction.label_of(best)["verb"])).is_equal("Vault")


func test_provider_says_climb_for_mantles_and_ledges_and_nothing_out_of_reach() -> void:
	var b := _obstacle(1.0, 1.4)
	await _settle()
	var m := _mover()
	var drv := Traversal.Driver.new(m)
	assert_str(String(drv.candidates(m.global_position, FWD)[0]["verb"])).is_equal("Climb")
	b.queue_free()
	_obstacle(2.3, 1.0)
	await _settle()
	drv._cache_frame = -100
	assert_str(String(drv.candidates(m.global_position, FWD)[0]["verb"])).is_equal("Climb")
	# Facing away: no obstacle ahead.
	drv._cache_frame = -100
	assert_array(drv.candidates(m.global_position, -FWD)).is_empty()
	# Too far: the wall is 1.0 m ahead of the origin; stand 1.0 m further back.
	m.global_position = Vector3(0.0, 0.0, 1.0)
	drv._cache_frame = -100
	assert_array(drv.candidates(m.global_position, FWD)).is_empty()


func test_pressing_the_candidate_starts_the_traversal() -> void:
	_obstacle(1.0, 1.4)
	await _settle()
	var m := _mover()
	var drv := Traversal.Driver.new(m)
	var c: Dictionary = drv.candidates(m.global_position, FWD)[0]
	assert_bool(Interaction.run(c, m)).is_true()
	assert_bool(drv.busy()).is_true()
	assert_str(String(drv.kind)).is_equal("mantle_low")


func test_register_provider_adds_and_removes_the_callable() -> void:
	var m := _mover()
	var drv := Traversal.Driver.new(m)
	drv.register_provider()
	assert_bool(Interaction.providers.has(Callable(drv, "candidates"))).is_true()
	drv.unregister_provider()
	assert_bool(Interaction.providers.has(Callable(drv, "candidates"))).is_false()


# --- scripted moves -------------------------------------------------------------------------------------------

func _run_until_idle(drv: Traversal.Driver, limit := 600) -> float:
	var n := 0
	while drv.tick(DT, Vector3.ZERO) and n < limit:
		n += 1
	return float(n) * DT


## True when a body-sized capsule at `pos` (slightly shrunk and lifted) overlaps no static geometry.
func _capsule_clear(pos: Vector3) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.33
	cap.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, pos + Vector3.UP * (0.85 + 0.03))
	q.collision_mask = 1
	return _space().intersect_shape(q, 1).is_empty()


func test_mantle_low_ends_on_top_in_the_authored_time() -> void:
	_obstacle(1.0, 1.4)
	var r: Dictionary = await _probe()
	var m := _mover()
	var drv := Traversal.Driver.new(m)
	assert_bool(drv.begin(r, 0.0)).is_true()
	assert_int(m.collision_mask).is_equal(0)               # scripted: collisions off, no gravity
	var secs := _run_until_idle(drv)
	assert_float(secs).is_equal_approx(1.33, 0.06)
	assert_float(m.global_position.y).is_equal_approx(1.0, 0.02)
	assert_float(m.global_position.z).is_less(-1.0 - 0.3)    # past the face, over the top
	assert_float(m.global_position.z).is_greater(-1.0 - 1.4)
	assert_int(m.collision_mask).is_equal(1)               # restored


func test_mantle_high_ends_on_top_in_the_authored_time() -> void:
	_obstacle(1.7, 1.0)
	var r: Dictionary = await _probe()
	var m := _mover()
	var drv := Traversal.Driver.new(m)
	assert_bool(drv.begin(r, 0.0)).is_true()
	assert_str(String(drv.kind)).is_equal("mantle_high")
	var secs := _run_until_idle(drv)
	assert_float(secs).is_equal_approx(1.8, 0.06)
	assert_float(m.global_position.y).is_equal_approx(1.7, 0.02)


func test_vault_carries_momentum_and_lands_beyond() -> void:
	_obstacle(0.9, 0.3)
	var r: Dictionary = await _probe(false)
	var m := _mover()
	var drv := Traversal.Driver.new(m)
	assert_bool(drv.begin(r, 6.5)).is_true()
	assert_str(String(drv.kind)).is_equal("vault")
	var secs := _run_until_idle(drv)
	assert_float(secs).is_less(1.2)
	assert_float(m.global_position.y).is_equal_approx(0.0, 0.03)
	assert_float(m.global_position.z).is_equal_approx(-1.0 - 0.3 - 0.55, 0.06)   # landing spot beyond the wall
	assert_float(m.velocity.length()).is_greater(2.0)                            # exits with speed
	assert_float(m.velocity.dot(FWD)).is_greater(2.0)


func test_a_standing_vault_is_slower_than_a_running_one() -> void:
	_obstacle(0.9, 0.3)
	var r: Dictionary = await _probe(false)
	var slow := Traversal.plan_for(r, Vector3.ZERO, 0.0)
	var fast := Traversal.plan_for(r, Vector3.ZERO, 6.5)
	assert_float(float(fast["duration"])).is_less(float(slow["duration"]))


func test_moves_never_overlap_the_obstacle() -> void:
	var cases := [[0.9, 0.3, 6.5], [0.9, 0.3, 0.0], [1.0, 1.4, 0.0], [1.7, 1.0, 0.0]]
	for cse in cases:
		var b := _obstacle(cse[0], cse[1])
		var r: Dictionary = await _probe(false)
		assert_str(String(r["kind"])).is_not_equal("none")
		var plan := Traversal.plan_for(r, Vector3.ZERO, cse[2])
		var t := 0.0
		var dur: float = plan["duration"]
		var worst := 0
		while t <= dur + 0.0001:
			if not _capsule_clear(Traversal.pose(plan, t)):
				worst += 1
			t += 0.02
		assert_int(worst).override_failure_message("capsule overlapped the %s obstacle %d times" % [str(cse), worst]).is_equal(0)
		assert_bool(_capsule_clear(plan["end"])).is_true()
		b.queue_free()
		await _settle()


func test_ledge_grab_hangs_then_climbs_to_the_top() -> void:
	_obstacle(2.3, 1.2)
	var r: Dictionary = await _probe(true)
	assert_str(String(r["kind"])).is_equal("ledge")
	var m := _mover()
	var drv := Traversal.Driver.new(m)
	assert_bool(drv.begin(r, 0.0)).is_true()
	var n := 0
	while not drv.hanging() and n < 300:
		drv.tick(DT, Vector3.ZERO)
		n += 1
	assert_bool(drv.hanging()).is_true()
	assert_float(float(n) * DT).is_equal_approx(1.33, 0.06)
	assert_float(m.global_position.z).is_equal_approx(-1.0 + 0.2, 0.03)          # 0.2 m from the face
	assert_float(m.global_position.y).is_equal_approx(2.3 - 2.12, 0.03)           # hands on the top
	# Hanging holds the body: gravity off, still there after a second.
	for _i in 60:
		drv.tick(DT, Vector3.ZERO)
	assert_bool(drv.hanging()).is_true()
	assert_float(m.global_position.y).is_equal_approx(2.3 - 2.12, 0.03)
	drv.request_climb()
	var secs := _run_until_idle(drv)
	assert_float(secs).is_equal_approx(1.53, 0.08)
	assert_float(m.global_position.y).is_equal_approx(2.3, 0.02)
	assert_float(m.global_position.z).is_less(-1.0 - 0.2)
	assert_int(m.collision_mask).is_equal(1)


func test_ledge_drop_releases_the_body_away_from_the_wall() -> void:
	_obstacle(2.3, 1.2)
	var r: Dictionary = await _probe(true)
	var m := _mover()
	var drv := Traversal.Driver.new(m)
	drv.begin(r, 0.0)
	var n := 0
	while not drv.hanging() and n < 300:
		drv.tick(DT, Vector3.ZERO)
		n += 1
	drv.request_drop()
	var secs := _run_until_idle(drv)
	assert_float(secs).is_equal_approx(0.2, 0.05)
	assert_bool(drv.busy()).is_false()
	assert_float(m.global_position.z).is_greater(-1.0 + 0.35)       # clear of the wall (capsule radius)
	assert_float(m.velocity.z).is_greater(0.5)                      # moving away
	assert_int(m.collision_mask).is_equal(1)


func test_pulling_back_on_the_stick_drops() -> void:
	_obstacle(2.3, 1.2)
	var r: Dictionary = await _probe(true)
	var m := _mover()
	var drv := Traversal.Driver.new(m)
	drv.begin(r, 0.0)
	var n := 0
	while not drv.hanging() and n < 300:
		drv.tick(DT, Vector3.ZERO)
		n += 1
	for _i in 30:
		drv.tick(DT, Vector3.ZERO)
	for _i in 30:
		drv.tick(DT, -FWD)               # stick away from the wall
	assert_bool(drv.hanging()).is_false()


func test_the_move_cannot_be_interrupted_by_a_second_request() -> void:
	_obstacle(1.0, 1.4)
	var r: Dictionary = await _probe()
	var m := _mover()
	var drv := Traversal.Driver.new(m)
	assert_bool(drv.begin(r, 0.0)).is_true()
	assert_bool(drv.begin(r, 0.0)).is_false()
	assert_bool(drv.on_jump_pressed()).is_false()
	drv.request_drop()                   # only a hanging body can drop
	drv.tick(DT, Vector3.ZERO)
	assert_bool(drv.busy()).is_true()
	assert_str(String(drv.kind)).is_equal("mantle_low")


# --- triggers -------------------------------------------------------------------------------------------------

func test_sprinting_into_a_vaultable_obstacle_vaults_automatically_and_the_setting_turns_it_off() -> void:
	_obstacle(0.9, 0.3)
	await _settle()
	var m := _mover()
	m._move_speed = 6.5
	var drv := Traversal.Driver.new(m)
	drv._settings_age = 0.0
	drv.auto_vault = false
	assert_bool(drv.tick(DT, FWD)).is_false()
	drv.auto_vault = true
	assert_bool(drv.tick(DT, FWD)).is_true()
	assert_str(String(drv.kind)).is_equal("vault")


func test_walking_into_a_vaultable_obstacle_does_not_auto_vault() -> void:
	_obstacle(0.9, 0.3)
	await _settle()
	var m := _mover()
	m._move_speed = 2.4
	var drv := Traversal.Driver.new(m)
	drv._settings_age = 0.0
	assert_bool(drv.tick(DT, FWD)).is_false()


func test_jump_near_a_ledge_mantles_instead_of_jumping() -> void:
	_obstacle(1.7, 1.0)
	await _settle()
	var m := _mover()
	var drv := Traversal.Driver.new(m)
	assert_bool(drv.on_jump_pressed()).is_true()
	assert_str(String(drv.kind)).is_equal("mantle_high")


func test_jump_with_nothing_ahead_is_not_consumed() -> void:
	await _settle()
	var m := _mover()
	var drv := Traversal.Driver.new(m)
	assert_bool(drv.on_jump_pressed()).is_false()


func test_player_jump_near_a_mantle_ledge_runs_the_traversal() -> void:
	var p: Node3D = auto_free(PlayerScript.new())
	_root.add_child(p)
	p.set_physics_process(false)
	p.global_position = Vector3.ZERO
	# The player model faces +Z.
	_box(Vector3(0.0, 0.5, 1.7), Vector3(4.0, 1.0, 1.4))
	await _settle()
	assert_object(p._trav).is_not_null()
	assert_bool(Interaction.providers.has(p._trav._provider)).is_true()
	p.jump()
	assert_bool(p._trav.busy()).is_true()
	assert_float(p._jump_buffer).is_equal(0.0)          # the press was spent on the mantle, not a jump
	var n := 0
	while p._trav.tick(DT, Vector3.ZERO) and n < 400:
		n += 1
	assert_float(p.global_position.y).is_equal_approx(1.0, 0.03)
	assert_int(p.collision_mask).is_equal(1 | 2 | 4)


# --- ladders --------------------------------------------------------------------------------------------------

func test_ladder_climbs_over_time_for_a_player_with_a_driver() -> void:
	var m := _mover()
	var drv := Traversal.Driver.new(m)
	m._trav = drv
	var ladder: Node3D = LadderScript.spawn(_root, Vector3(0.0, 0.0, -2.0), Vector3(0.0, 3.0, -3.0))
	var done := []
	ladder.climbed.connect(func(up: bool) -> void: done.append(up))
	m.global_position = Vector3(0.0, 0.0, -1.2)
	ladder.climb(m, true)
	assert_bool(drv.busy()).is_true()
	assert_float(m.global_position.y).is_equal_approx(0.0, 0.01)       # not teleported
	var secs := 0.0
	var mid_y := 0.0
	while drv.tick(DT, Vector3.ZERO) and secs < 10.0:
		secs += DT
		if absf(secs - 1.5) < DT * 0.6:
			mid_y = m.global_position.y
	assert_float(secs).is_greater(2.0)                                 # 3 m at ~1.2 m/s plus align and exit
	assert_float(mid_y).is_between(0.2, 2.8)
	assert_vector(m.global_position).is_equal_approx(Vector3(0.0, 3.0, -3.0), Vector3.ONE * 0.02)
	assert_array(done).is_equal([true])


# --- stair step-up --------------------------------------------------------------------------------------------

func _step_h(h: float, depth := 1.0, width := 4.0, rot := Vector3.ZERO) -> float:
	var b := _box(Vector3(0.0, h * 0.5, -0.5 - depth * 0.5), Vector3(width, h, depth), rot)
	await _settle()
	var out := Traversal.step_height(_space(), Vector3.ZERO, FWD, 0.5, [])
	b.queue_free()
	await _settle()
	return out


func test_step_up_accepts_0_3_m() -> void:
	assert_float(await _step_h(0.3)).is_equal_approx(0.3, 0.01)


func test_step_up_rejects_0_5_m() -> void:
	assert_float(await _step_h(0.5)).is_equal(0.0)


func test_step_up_limit_is_the_configured_height() -> void:
	assert_float(await _step_h(0.34)).is_equal_approx(0.34, 0.01)
	assert_float(await _step_h(0.38)).is_equal(0.0)


func test_step_up_rejects_thin_planks_and_steep_ramps() -> void:
	assert_float(await _step_h(0.2, 0.12)).is_equal(0.0)               # 12 cm deep
	assert_float(await _step_h(0.2, 1.0, 0.2)).is_equal(0.0)           # 20 cm wide post
	# A 40 degree ramp: the top is steeper than the walkable limit.
	var ramp := _box(Vector3(0.0, 0.0, -1.2), Vector3(4.0, 0.1, 2.0), Vector3(deg_to_rad(40.0), 0.0, 0.0))
	await _settle()
	assert_float(Traversal.step_height(_space(), Vector3.ZERO, FWD, 0.6, [])).is_equal(0.0)
	ramp.queue_free()


func test_step_up_refuses_when_there_is_no_head_room() -> void:
	_box(Vector3(0.0, 0.15, -1.0), Vector3(4.0, 0.3, 1.0))
	_box(Vector3(0.0, 1.0, -0.2), Vector3(4.0, 0.2, 0.4))              # low beam over the spot
	await _settle()
	# The beam (y 0.9 to 1.1) sits inside the raised capsule's volume.
	assert_float(Traversal.step_height(_space(), Vector3.ZERO, FWD, 0.5, [])).is_equal(0.0)


func test_step_assist_lifts_the_body_and_eases_the_camera() -> void:
	_box(Vector3(0.0, 0.15, -1.0), Vector3(4.0, 0.3, 1.0))
	await _settle()
	var m := _mover()
	m.global_position = Vector3(0.0, 0.0, -0.15)      # pressed against the step: capsule radius 0.35 from its face
	m.floor_snap_length = 0.35
	var pivot := Node3D.new()
	m.add_child(pivot)
	pivot.position.y = 1.55
	m._pivot = pivot
	var drv := Traversal.Driver.new(m)
	# Not grounded yet in this bare scene: ground the body with a tiny slide.
	m.velocity = Vector3(0.0, -1.0, 0.0)
	m.move_and_slide()
	var before := m.global_position.y
	var h := drv.step_assist(DT, FWD, 2.0)
	if m.is_on_floor():
		assert_float(h).is_equal_approx(0.3, 0.03)
		assert_float(m.global_position.y).is_equal_approx(before + h + 0.005, 0.002)
		assert_float(pivot.position.y).is_equal_approx(1.55 - h, 0.002)     # camera pivot starts lowered, eases up
		for _i in 30:
			drv.tick(DT, Vector3.ZERO)
		assert_float(pivot.position.y).is_equal_approx(1.55 - h, 0.002)     # (the Player's camera code lerps it back)
	else:
		fail("the test body should be on the floor")
