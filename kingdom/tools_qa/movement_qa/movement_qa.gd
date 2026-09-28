extends Node
## Movement-feel QA bot for Rising Ashes.
##
## Boots the real game (res://scenes/main.tscn) as a child and drives the player
## through the real input path (InputEventKey with the physical keycodes from
## Game._setup_input / Player._ensure_actions), exactly like tools_qa/autoplay,
## so what gets recorded is what a real keyboard/gamepad player would feel.
##
## Captures a JPG frame strip per scenario to <out>/<scenario>/NN.jpg:
##   walk, run (sprint), stop, turn180, backward, slope, dodge, dash
##
## Run: kingdom/tools_qa/movement_qa/run_movement_qa.sh
## See README.md in this folder.

const MAIN := "res://scenes/main.tscn"
const SHOT_W := 1280
const SHOT_H := 720

var main: Node
var player: Player
var hud: HUD
var out_dir := ""
var t0 := 0
var _log: FileAccess


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	t0 = Time.get_ticks_msec()
	var args := _args()
	out_dir = String(args.get("out", ProjectSettings.globalize_path("res://").path_join("../docs/qa/movement"))).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	_log = FileAccess.open(out_dir.path_join("log.txt"), FileAccess.WRITE)
	get_window().size = Vector2i(SHOT_W, SHOT_H)
	get_window().move_to_center()
	log_line("Rising Ashes movement QA  %s" % Time.get_datetime_string_from_system())
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


# --- scenario capture ---------------------------------------------------------------

var _scn := ""
var _scn_n := 0


func begin_scenario(name: String) -> void:
	_scn = name
	_scn_n = 0
	DirAccess.make_dir_recursive_absolute(out_dir.path_join(name))
	log_line("--- scenario: %s ---" % name)


func shot(label := "") -> void:
	await frames(1)
	_scn_n += 1
	var file := "%02d_%s.jpg" % [_scn_n, label] if label != "" else "%02d.jpg" % _scn_n
	var img := get_viewport().get_texture().get_image()
	img.save_jpg(out_dir.path_join(_scn).path_join(file), 0.88)


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


# --- run -----------------------------------------------------------------------------

func _run() -> void:
	await wait_until_ready()
	WorldSim.time_of_day = 13.0
	Life.life_path.set_age(18, WorldSim.day, WorldSim.time_of_day)
	player.apply_age()
	var home: Dictionary = WorldGen.settlements[0]
	var flat: Vector2 = home["pos"] + Vector2(2, 10)
	main._teleport(flat, 0.0)
	player.set_view(Player.View.THIRD)
	await wait(1.0)
	log_line("teleported to plaza %s" % flat)

	# 1. Walk (tap forward, hold under sprint threshold).
	begin_scenario("01_walk")
	await shot("start")
	key(KEY_W, true)
	for i in 10:
		await wait(0.15)
		await shot()
	key(KEY_W, false)
	log_line("walk end speed=%.2f m/s (WALK const)" % speed())
	await wait(0.6)

	# 2. Run / sprint (Shift+W).
	begin_scenario("02_run")
	await shot("start")
	key(KEY_SHIFT, true)
	key(KEY_W, true)
	for i in 10:
		await wait(0.15)
		await shot()
	log_line("run end speed=%.2f m/s (RUN const)" % speed())

	# 3. Stop: release both, watch it brake instead of skate.
	begin_scenario("03_stop")
	key(KEY_W, false)
	key(KEY_SHIFT, false)
	for i in 8:
		await wait(0.1)
		await shot()
	log_line("stop end speed=%.2f m/s (should reach ~0, no ice-slide)" % speed())
	await wait(0.4)

	# 4. Turn 180 on the spot: face one way, then snap the stick the other way.
	begin_scenario("04_turn180")
	key(KEY_D, true)
	await wait(0.5)
	key(KEY_D, false)
	await wait(0.3)
	await shot("before")
	key(KEY_A, true)
	for i in 8:
		await wait(0.1)
		await shot()
	key(KEY_A, false)
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
	await wait(0.4)

	# 6. Slope: head toward the forest/camp road, which climbs and dips.
	begin_scenario("06_slope")
	var slope_target: Vector2 = home["pos"] + Vector2(90, 40)
	main._teleport(home["pos"] + Vector2(20, 30), 0.0)
	await wait(0.4)
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
	log_line("slope end y=%.2f (no clipping/bouncing expected)" % player.global_position.y)
	await wait(0.4)

	# 7. Plain dodge (Space): short roll, i-frames, no afterimage.
	main._teleport(flat, 0.0)
	await wait(0.6)
	begin_scenario("07_dodge_space")
	await shot("before")
	key(KEY_SPACE, true)
	await frames(1)
	key(KEY_SPACE, false)
	for i in 10:
		await wait(0.06)
		await shot()
	log_line("dodge(space) invulnerable=%.2f dodging_ability=%s" % [player._invulnerable, str(player._dodging_ability)])
	await wait(0.6)

	# 8. Shadow Dash ability (R): fast burst + afterimage VFX + cooldown.
	begin_scenario("08_ability_dash_r")
	await shot("before")
	key(KEY_R, true)
	await frames(1)
	key(KEY_R, false)
	for i in 10:
		await wait(0.06)
		await shot()
	log_line("ability_dash(R) dash_cooldown=%.2f (should be %.1f right after use)" % [player.dash_cooldown, 4.0])
	await wait(0.6)
	# Immediately press again: should be refused (still on cooldown), no VFX/roll.
	key(KEY_R, true)
	await frames(1)
	key(KEY_R, false)
	for i in 4:
		await wait(0.1)
		await shot("cooldown_block")
	log_line("second dash while on cooldown: dodge_state=%s (should stay 0, cooldown blocks it)" % str(player._dodge))

	log_line("DONE")
	get_tree().quit()


func wait_until_ready() -> void:
	while not (main and main.get("player") != null and main.player.is_inside_tree() and main.get("hud") != null and not main.hud._loading.visible):
		await get_tree().process_frame
	player = main.player
	hud = main.hud
