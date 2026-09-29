extends Node
## Movement-feel QA bot for Rising Ashes.
##
## Boots the real game (res://scenes/main.tscn) as a child and drives the player
## through the real input path (InputEventKey with the physical keycodes from
## Game._setup_input / Player._ensure_actions), exactly like tools_qa/autoplay,
## so what gets recorded is what a real keyboard/gamepad player would feel.
##
## v2 (2026-09-28): the v1 harness spawned at a fixed offset from the village
## plaza that happened to land the player against a market stall, so
## walk/run/stop never actually moved (every frame identical) and the camera's
## own wall-avoidance ray pulled it into the character's head on the 180 turn.
## v2 instead finds real open ground along the village's own gate/road
## direction (WorldGen.settlements[0].plan.gates[0]), verifies nothing is
## within OPEN_CLEARANCE with a ring of raycasts, and after every scenario
## ASSERTS the player actually displaced by at least MOVED_FRACTION of the
## naive expected distance (speed * time). A failed assertion is logged as
## "FAIL" (not just noted) so a broken test can't pass silently again.
##
## Captures a JPG frame strip per scenario to <out>/<scenario>/NN.jpg and logs
## measured speed every frame to log.txt.
##
## Run: kingdom/tools_qa/movement_qa/run_movement_qa.sh
## See README.md in this folder.

const MAIN := "res://scenes/main.tscn"
const SHOT_W := 1280
const SHOT_H := 720
## A spawn point must have nothing (wall, stall, prop) within this radius.
const OPEN_CLEARANCE := 10.0
## A scenario's real displacement must reach at least this fraction of the
## naive expected distance (top speed * elapsed time) or it's logged FAIL.
const MOVED_FRACTION := 0.6

var main: Node
var player: Player
var hud: HUD
var out_dir := ""
var t0 := 0
var _log: FileAccess
var _fail_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	t0 = Time.get_ticks_msec()
	var args := _args()
	out_dir = String(args.get("out", ProjectSettings.globalize_path("res://").path_join("../docs/qa/movement"))).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_log = FileAccess.open(out_dir.path_join("log.txt"), FileAccess.WRITE)
	get_window().size = Vector2i(SHOT_W, SHOT_H)
	get_window().move_to_center()
	log_line("Rising Ashes movement QA v2  %s" % Time.get_datetime_string_from_system())
	main = (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	_run()


func _args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
		elif arg.begins_with("--"):
			out[arg.substr(2)] = true
	return out


func now() -> float:
	return (Time.get_ticks_msec() - t0) / 1000.0


func log_line(text: String) -> void:
	var line := "[%7.2f] %s" % [now(), text]
	print("MOVEQA ", line)
	if _log:
		_log.store_line(line)
		_log.flush()


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func wait(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func tap_key(code: Key) -> void:
	key(code, true)
	await frames(2)
	key(code, false)


# --- open-ground spawn finder --------------------------------------------------------

## Ring of raycasts from `p` (world x/z) at chest height: true if nothing
## (wall, stall, prop, fence) is hit within `radius`. A near-flat hit
## (normal.y close to 1) is ground/terrain, not an obstruction.
func _ground_clear(p: Vector2, radius: float) -> bool:
	var space := get_viewport().find_world_3d().direct_space_state
	var y := WorldGen.height(p.x, p.y) + 1.0
	var from3 := Vector3(p.x, y, p.y)
	for i in 10:
		var ang := TAU * i / 10.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var q := PhysicsRayQueryParameters3D.create(from3, from3 + dir * radius, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var n: Vector3 = hit.get("normal", Vector3.UP)
			if absf(n.y) < 0.6:
				return false
	return true


## Open ground on the road just outside the home village's own gate, walking
## further down the road until OPEN_CLEARANCE is satisfied. Falls back to the
## plaza centre (still checked) if the settlement has no plan yet.
func _find_open_spawn() -> Vector2:
	var s: Dictionary = WorldGen.settlements[0]
	var center: Vector2 = s["pos"]
	var gate_angle := 0.0
	if s.has("plan") and not (s["plan"]["gates"] as Array).is_empty():
		gate_angle = float(s["plan"]["gates"][0])
	var dist: float = float(s.get("radius", 60.0)) + 25.0
	for attempt in 6:
		var p := center + Vector2(cos(gate_angle), sin(gate_angle)) * dist
		if _ground_clear(p, OPEN_CLEARANCE):
			log_line("open ground found at %s (gate_angle=%.2f, dist=%.1f, attempt %d)" % [p, gate_angle, dist, attempt + 1])
			return p
		dist += 15.0
	log_line("WARNING: no fully clear spot found after 6 attempts, using last candidate anyway")
	return center + Vector2(cos(gate_angle), sin(gate_angle)) * dist


# --- scenario capture ---------------------------------------------------------------

var _scn := ""
var _scn_n := 0
var _scn_start_pos := Vector3.ZERO
var _scn_start_t := 0.0


func begin_scenario(name: String) -> void:
	_scn = name
	_scn_n = 0
	_scn_start_pos = player.global_position
	_scn_start_t = now()
	DirAccess.make_dir_recursive_absolute(out_dir.path_join(name))
	log_line("--- scenario: %s ---" % name)


func shot(label := "") -> void:
	await frames(1)
	_scn_n += 1
	var file := "%02d_%s.jpg" % [_scn_n, label] if label != "" else "%02d.jpg" % _scn_n
	var img := get_viewport().get_texture().get_image()
	img.save_jpg(out_dir.path_join(_scn).path_join(file), 0.88)
	log_line("  frame %s speed=%.2f m/s pos=%s y=%.2f" % [file, speed(), _pos2(), player.global_position.y])


## Holds `code` for `sec` seconds, taking `n` evenly spaced shots.
func hold_and_shoot(code: Key, sec: float, n: int) -> void:
	key(code, true)
	var step := sec / float(n)
	for i in n:
		await wait(step)
		await shot()
	key(code, false)
	await frames(2)


func speed() -> float:
	var v: Vector3 = player.velocity
	return Vector2(v.x, v.z).length()


func _pos2() -> Vector2:
	return Vector2(player.global_position.x, player.global_position.z)


## Compares real displacement since begin_scenario() to a naive expected
## distance (expected_speed * elapsed seconds). Logs PASS/FAIL; FAIL bumps
## _fail_count so the run's exit summary can't be missed.
func assert_moved(expected_speed: float) -> void:
	var elapsed := now() - _scn_start_t
	var actual := _pos2().distance_to(Vector2(_scn_start_pos.x, _scn_start_pos.z))
	var expected := expected_speed * elapsed
	var ok := actual >= expected * MOVED_FRACTION
	if not ok:
		_fail_count += 1
	log_line("  [%s] displacement=%.2fm expected>=%.2fm (%.0f%% of naive %.2fm over %.2fs)" %
			["PASS" if ok else "FAIL", actual, expected * MOVED_FRACTION, MOVED_FRACTION * 100.0, expected, elapsed])


func assert_true(cond: bool, label: String) -> void:
	if not cond:
		_fail_count += 1
	log_line("  [%s] %s" % ["PASS" if cond else "FAIL", label])


# --- run -----------------------------------------------------------------------------

func _run() -> void:
	await wait_until_ready()
	WorldSim.time_of_day = 13.0
	Life.life_path.set_age(18, WorldSim.day, WorldSim.time_of_day)
	player.apply_age()

	var flat := _find_open_spawn()
	main._teleport(flat, 0.0)
	player.set_view(Player.View.THIRD)
	await wait(1.0)
	log_line("teleported to open ground %s" % flat)

	# 1. Walk (tap forward, hold under sprint threshold).
	begin_scenario("01_walk")
	await shot("start")
	key(KEY_W, true)
	for i in 10:
		await wait(0.15)
		await shot()
	key(KEY_W, false)
	assert_moved(Player.WALK)
	await wait(0.6)

	# 2. Run / sprint (Shift+W).
	begin_scenario("02_run")
	await shot("start")
	key(KEY_SHIFT, true)
	key(KEY_W, true)
	for i in 10:
		await wait(0.15)
		await shot()
	assert_moved(Player.RUN)

	# 3. Stop: release both, watch it brake instead of skate.
	begin_scenario("03_stop")
	var stop_from := speed()
	key(KEY_W, false)
	key(KEY_SHIFT, false)
	for i in 8:
		await wait(0.1)
		await shot()
	assert_true(speed() < 0.5, "stop end speed=%.2f m/s < 0.5 (was %.2f, no ice-slide)" % [speed(), stop_from])
	await wait(0.4)

	# 4. Turn 180 on the spot: face one way, then snap the stick the other way.
	begin_scenario("04_turn180")
	key(KEY_D, true)
	await wait(0.5)
	key(KEY_D, false)
	await wait(0.3)
	await shot("before")
	var facing_before: Vector3 = player.facing()
	key(KEY_A, true)
	for i in 8:
		await wait(0.1)
		await shot()
	key(KEY_A, false)
	assert_true(facing_before.dot(player.facing()) < 0.0,
			"facing reversed (before.dot(after)=%.2f, expect <0)" % facing_before.dot(player.facing()))
	await wait(0.4)

	# 5. Walk backwards: hold S, watch the character turn to face travel
	#    and walk "forward" in the new facing (no moonwalk / sideways skid).
	begin_scenario("05_backward")
	await shot("start")
	key(KEY_S, true)
	for i in 10:
		await wait(0.15)
		await shot()
	key(KEY_S, false)
	assert_moved(Player.WALK)
	await wait(0.4)

	# 6. Strafe: hold block (forces facing to hold) and step sideways (D) so
	#    travel is perpendicular to facing.
	begin_scenario("06_strafe")
	await shot("start")
	key(KEY_L, true)      # block: forces _strafing = true
	await frames(2)
	key(KEY_D, true)
	for i in 10:
		await wait(0.15)
		await shot()
	key(KEY_D, false)
	key(KEY_L, false)
	assert_moved(Player.WALK * 0.5)   # blocking caps speed to WALK * 0.5
	await wait(0.4)

	# 7. Slope: from the open-ground spawn, run up the steepest nearby heading.
	#    (Was: a fixed village offset that landed on flat ground against a house, and
	#    begin_scenario ran BEFORE the teleport so "displacement" counted the jump.)
	var slope_start := flat
	var slope_target := flat
	var best_rise := -1.0
	for i in 16:
		var a := TAU * i / 16.0
		var tgt := flat + Vector2(cos(a), sin(a)) * 30.0
		var rise := absf(WorldGen.height(tgt.x, tgt.y) - WorldGen.height(flat.x, flat.y))
		if rise > best_rise:
			best_rise = rise
			slope_target = tgt
	main._teleport(slope_start, 0.0)
	await wait(0.4)
	begin_scenario("07_slope")
	log_line("  slope heading: %.1f m height change over 30 m" % best_rise)
	var to := slope_target - Vector2(player.global_position.x, player.global_position.z)
	player.set_camera(atan2(-to.x, -to.y), -0.2)
	await shot("start")
	key(KEY_SHIFT, true)
	key(KEY_W, true)
	for i in 14:
		await wait(0.2)
		await shot()
		var here := Vector2(player.global_position.x, player.global_position.z)
		to = slope_target - here
		player.set_camera(atan2(-to.x, -to.y), player._pitch)
	key(KEY_W, false)
	key(KEY_SHIFT, false)
	assert_moved(Player.RUN * 0.5)   # slope + steering losses: looser bound than flat ground
	assert_true(player.is_on_floor() or player._air_time < Player.COYOTE_TIME,
			"grounded at slope end (no bounce/launch), air_time=%.2f" % player._air_time)
	await wait(0.4)

	# 8. Wall / fence collision: sprint straight into the village wall and
	#    confirm the body stops cleanly (no jitter, no bounce-back).
	begin_scenario("08_wall_collision")
	var s2: Dictionary = WorldGen.settlements[0]
	var gate_angle := 0.0
	if s2.has("plan") and not (s2["plan"]["gates"] as Array).is_empty():
		gate_angle = float(s2["plan"]["gates"][0])
	# Approach angle offset from the gate so we hit solid wall, not the gap.
	var wall_angle := gate_angle + 0.6
	var wall_dir := Vector2(cos(wall_angle), sin(wall_angle))
	var approach: Vector2 = s2["pos"] + wall_dir * (float(s2.get("radius", 60.0)) + 20.0)
	main._teleport(approach, 0.0)
	await wait(0.4)
	# Face and camera toward the wall (back along wall_dir, into the settlement).
	player.set_camera(atan2(wall_dir.x, wall_dir.y), -0.1)
	await shot("before")
	key(KEY_SHIFT, true)
	key(KEY_W, true)
	var speeds: Array[float] = []
	for i in 24:
		await wait(0.1)
		await shot()
		speeds.append(speed())
	key(KEY_W, false)
	key(KEY_SHIFT, false)
	# Jitter check: once against the wall (last third of samples), consecutive
	# frame-to-frame speed deltas should stay small, not oscillate (bounce).
	var tail: Array[float] = speeds.slice(speeds.size() - 8)
	var max_jump := 0.0
	for i in range(1, tail.size()):
		max_jump = maxf(max_jump, absf(tail[i] - tail[i - 1]))
	assert_true(max_jump < 2.0, "no bounce against wall: max frame-to-frame speed jump=%.2f m/s (<2.0)" % max_jump)
	await wait(0.4)

	# 9. Crowd: walk through a knot of villagers in the plaza; watch for
	#    getting stuck or shoved off course.
	begin_scenario("09_crowd")
	main._teleport(s2["pos"], 0.0)
	await wait(0.6)
	player.set_camera(0.0, -0.15)
	await shot("start")
	key(KEY_W, true)
	for i in 16:
		await wait(0.15)
		await shot()
	key(KEY_W, false)
	log_line("  crowd walk end pos=%s (villagers nearby=%d)" % [_pos2(), get_tree().get_nodes_in_group("villager").size()])
	await wait(0.4)

	# 10. Plain dodge (Space): short roll, i-frames, no afterimage.
	main._teleport(flat, 0.0)
	await wait(0.6)
	begin_scenario("10_dodge_space")
	await shot("before")
	key(KEY_SPACE, true)
	await frames(1)
	key(KEY_SPACE, false)
	for i in 10:
		await wait(0.06)
		await shot()
	assert_moved((Player.DODGE_SPEED_MIN + Player.DODGE_SPEED_MAX) * 0.5 * 0.5)
	log_line("dodge(space) invulnerable=%.2f dodging_ability=%s" % [player._invulnerable, str(player._dodging_ability)])
	await wait(0.6)

	# 11. Shadow Dash ability (R): fast burst + afterimage VFX + cooldown.
	begin_scenario("11_ability_dash_r")
	await shot("before")
	key(KEY_R, true)
	await frames(1)
	key(KEY_R, false)
	for i in 10:
		await wait(0.06)
		await shot()
	assert_moved((Player.DASH_SPEED_MIN + Player.DASH_SPEED_MAX) * 0.5 * 0.5)
	log_line("ability_dash(R) dash_cooldown=%.2f (should be %.1f right after use)" % [player.dash_cooldown, Player.DASH_COOLDOWN])
	await wait(0.6)
	# Immediately press again: should be refused (still on cooldown), no VFX/roll.
	key(KEY_R, true)
	await frames(1)
	key(KEY_R, false)
	for i in 4:
		await wait(0.1)
		await shot("cooldown_block")
	assert_true(player._dodge <= 0.0, "second dash refused while on cooldown (dodge_state=%.2f, expect 0)" % player._dodge)

	log_line("DONE  failures=%d" % _fail_count)
	get_tree().quit(1 if _fail_count > 0 else 0)


func wait_until_ready() -> void:
	while not (main and main.get("player") != null and main.player.is_inside_tree() and main.get("hud") != null and not main.hud._veil()):
		await get_tree().process_frame
	player = main.player
	hud = main.hud
