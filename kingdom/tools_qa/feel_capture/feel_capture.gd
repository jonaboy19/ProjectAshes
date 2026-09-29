extends Node
## Game-feel capture harness (animation director audit, docs/anim/FEEL_AUDIT.md).
##
## Boots the REAL game (res://scenes/main.tscn as a child, like tools_qa/movement_qa)
## and plays a fixed list of feel scenarios through the real input path. Unlike the
## movement QA bot it waits in RENDERED FRAMES, not wall-clock time, so it is
## deterministic under Godot Movie Maker:
##
##   Godot --path kingdom --write-movie <dir>/feel.avi --fixed-fps 30 \
##       res://tools_qa/feel_capture/feel_capture.tscn -- --adult --skipintro --out=<dir> [--only=01,02]
##
## Every frame carries a small overlay (scenario, frame number, body speed, animation
## speed, facing) so contact sheets are self-describing, and <out>/telemetry.csv
## logs the same values per frame. <out>/scenarios.txt lists each scenario's first
## and last movie frame (split the video with ffmpeg -ss frame/30).
## Never add --headless (black frames).

const MAIN := "res://scenes/main.tscn"
const W := 1280
const H := 720
const FPS := 30.0

var main: Node
var player: Player
var out_dir := ""
var only: PackedStringArray = []
var frame := 0
var scn := "boot"
var _scn_start := 0
var _csv: FileAccess
var _index: FileAccess
var _label: Label
var _flat := Vector2.ZERO
var _look_px := 0.0          # camera yaw drag per frame (pixels), applied in _process


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := _args()
	out_dir = String(args.get("out", ProjectSettings.globalize_path("res://").path_join("../docs/anim/feel/capture"))).simplify_path()
	if args.has("only"):
		only = String(args["only"]).split(",", false)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_csv = FileAccess.open(out_dir.path_join("telemetry.csv"), FileAccess.WRITE)
	_csv.store_line("frame,scenario,x,y,z,real_speed,move_speed,anim_speed,model_yaw_deg,yaw_rate,loco_blend,gait_rate,cam_x,cam_y,cam_z,on_floor,process_ms,render_cam_dist,render_body_x,render_body_z")
	_index = FileAccess.open(out_dir.path_join("scenarios.txt"), FileAccess.WRITE)
	get_window().size = Vector2i(W, H)
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color(1, 1, 0.8))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_label.position = Vector2(12, H - 30)
	layer.add_child(_label)
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


func _process(_delta: float) -> void:
	frame += 1
	if player and is_instance_valid(player):
		if _look_px != 0.0:
			player.add_look(Vector2(_look_px, 0.0))
		_telemetry()


func _telemetry() -> void:
	var real := player.get_real_velocity()
	var rs := Vector2(real.x, real.z).length()
	var anim: CharacterAnimator = player._animator
	var yaw := rad_to_deg(player._model.rotation.y)
	var loco := 0.0
	var rate := 0.0
	if anim and anim.tree:
		loco = float(anim.tree.get("parameters/loco/blend_amount"))
		rate = float(anim.tree.get("parameters/gait_rate/scale"))
	var cp := player.camera.global_position if player.camera else Vector3.ZERO
	var pms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	# What is actually drawn this frame (physics interpolation applied).
	var rb := player._model.get_global_transform_interpolated().origin
	var rc := player.camera.get_global_transform_interpolated().origin if player.camera else rb
	_csv.store_line("%d,%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.1f,%.2f,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%.2f,%.3f,%.3f,%.3f" % [
		frame, scn, player.global_position.x, player.global_position.y, player.global_position.z,
		rs, player._move_speed, anim.shown_speed() if anim else 0.0, yaw, player._yaw_rate, loco, rate,
		cp.x, cp.y, cp.z, 1 if player.is_on_floor() else 0, pms, rb.distance_to(rc), rb.x, rb.z])
	_label.text = "FEEL %s  f%d  t%.2fs | body %.2f m/s  anim %.2f  loco %.2f  rate %.2f | face %.0f°" % [
		scn, frame - _scn_start, (frame - _scn_start) / FPS, rs, anim.shown_speed() if anim else 0.0, loco, rate, yaw]


# --- helpers -------------------------------------------------------------------------

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func tap(code: Key) -> void:
	key(code, true)
	await frames(2)
	key(code, false)


func release_all() -> void:
	for k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_L, KEY_SPACE, KEY_J]:
		key(k, false)
	_look_px = 0.0


func log_line(t: String) -> void:
	print("FEELCAP [f%d] %s" % [frame, t])


func want(id: String) -> bool:
	if only.is_empty():
		return true
	for o in only:
		if id.begins_with(o):
			return true
	return false


func begin(id: String) -> void:
	release_all()
	scn = id
	_scn_start = frame
	log_line("BEGIN %s" % id)


func finish() -> void:
	release_all()
	_index.store_line("%s %d %d" % [scn, _scn_start, frame])
	_index.flush()
	_csv.flush()
	log_line("END %s (%d frames)" % [scn, frame - _scn_start])
	scn = "gap"
	_scn_start = frame


func ground(p: Vector2) -> Vector3:
	return Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


func teleport(p: Vector2, yaw: float, settle := 20) -> void:
	main._teleport(p, yaw)
	player.set_camera(yaw, -0.28)
	await frames(settle)


## Camera yaw that looks from the player toward `p` (player.set_camera convention).
func yaw_to(p: Vector3) -> float:
	var to := p - player.global_position
	return atan2(-to.x, -to.z)


func _ground_clear(p: Vector2, radius: float) -> bool:
	var space := get_viewport().find_world_3d().direct_space_state
	var from3 := ground(p) + Vector3.UP
	for i in 12:
		var ang := TAU * i / 12.0
		var q := PhysicsRayQueryParameters3D.create(from3, from3 + Vector3(cos(ang), 0.0, sin(ang)) * radius, 1)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and absf((hit["normal"] as Vector3).y) < 0.6:
			return false
	return true


func _gate_dir() -> Vector2:
	var s: Dictionary = WorldGen.settlements[0]
	var a := 0.0
	if s.has("plan") and not (s["plan"]["gates"] as Array).is_empty():
		a = float(s["plan"]["gates"][0])
	return Vector2(cos(a), sin(a))


## Open, fairly flat ground outside the home village (walk down the gate road).
func _find_flat(min_dist: float, need_wild := false) -> Vector2:
	var s: Dictionary = WorldGen.settlements[0]
	var c: Vector2 = s["pos"]
	var d := float(s.get("radius", 60.0)) + min_dist
	var dir := _gate_dir()
	var best := c + dir * d
	for attempt in 40:
		for side in [0.0, 0.5, -0.5, 1.0, -1.0]:
			var p: Vector2 = c + dir.rotated(side) * d
			var slope := absf(WorldGen.height(p.x + 4, p.y) - WorldGen.height(p.x - 4, p.y)) \
					+ absf(WorldGen.height(p.x, p.y + 4) - WorldGen.height(p.x, p.y - 4))
			if WorldGen.is_water(p.x, p.y) or slope > 1.2:
				continue
			if need_wild and Frontier.runestones.coverage(p) > 0.02:
				continue
			await teleport(p, 0.0, 6)
			if _ground_clear(p, 9.0):
				return p
		d += 20.0
	return best


# --- run -----------------------------------------------------------------------------

func _run() -> void:
	while not (main and main.get("player") != null and main.player.is_inside_tree() and main.get("hud") != null and not main.hud._veil()):
		await get_tree().process_frame
	player = main.player
	WorldSim.time_of_day = 13.0
	Life.life_path.set_age(18, WorldSim.day, WorldSim.time_of_day)
	player.apply_age()
	player.set_view(Player.View.THIRD)
	log_line("Quality tier=%d npc_full=%d" % [Quality.tier, Quality.npc_full])
	_flat = await _find_flat(25.0)
	await teleport(_flat, 0.0, 45)
	log_line("flat ground %s" % _flat)

	if want("01"): await _s01_start_stop_walk()
	if want("02"): await _s02_start_stop_run()
	if want("03"): await _s03_turn_in_place()
	if want("04"): await _s04_pivot_180()
	if want("05"): await _s05_gait_changes()
	if want("06"): await _s06_curve_run()
	if want("07"): await _s07_slope()
	if want("08"): await _s08_camera_collision()
	if want("09"): await _s09_combo_air()
	if want("10") or want("11") or want("12") or want("13"): await _s10_13_combat()
	if want("14"): await _s14_talk()
	if want("15"): await _s15_crowd()
	if want("16"): await _s16_wolves()
	if want("17"): await _s17_horse()
	if want("18"): await _s18_swim()
	log_line("DONE")
	_index.close()
	_csv.close()
	get_tree().quit(0)


func _s01_start_stop_walk() -> void:
	await teleport(_flat, 0.0)
	begin("01_start_stop_walk")
	await frames(15)
	key(KEY_W, true)
	await frames(60)
	key(KEY_W, false)
	await frames(40)
	finish()


func _s02_start_stop_run() -> void:
	await teleport(_flat, PI * 0.5)
	begin("02_start_stop_run")
	await frames(15)
	key(KEY_SHIFT, true)
	key(KEY_W, true)
	await frames(75)
	key(KEY_W, false)
	key(KEY_SHIFT, false)
	await frames(45)
	finish()


## From idle: quick 90° (tap D) then 180° (tap S) direction changes on the spot.
func _s03_turn_in_place() -> void:
	await teleport(_flat, 0.0)
	begin("03_turn_in_place")
	await frames(15)
	key(KEY_D, true)
	await frames(8)
	key(KEY_D, false)
	await frames(35)
	key(KEY_S, true)
	await frames(8)
	key(KEY_S, false)
	await frames(40)
	finish()


## Running, then the stick reverses: brake, plant, pivot, set off.
func _s04_pivot_180() -> void:
	await teleport(_flat, -PI * 0.5)
	begin("04_pivot_180_run")
	await frames(10)
	key(KEY_SHIFT, true)
	key(KEY_W, true)
	await frames(55)
	key(KEY_W, false)
	key(KEY_S, true)
	await frames(50)
	key(KEY_S, false)
	key(KEY_SHIFT, false)
	await frames(35)
	# Walking reversal too.
	key(KEY_W, true)
	await frames(40)
	key(KEY_W, false)
	key(KEY_S, true)
	await frames(45)
	finish()


func _s05_gait_changes() -> void:
	await teleport(_flat, PI)
	begin("05_walk_run_walk")
	await frames(10)
	key(KEY_W, true)
	await frames(45)
	key(KEY_SHIFT, true)
	await frames(50)
	key(KEY_SHIFT, false)
	await frames(45)
	key(KEY_SHIFT, true)
	await frames(30)
	key(KEY_SHIFT, false)
	key(KEY_W, false)
	await frames(35)
	finish()


## Sustained run while the camera swings: the body carves an arc (lean, turn rate).
func _s06_curve_run() -> void:
	await teleport(_flat, PI * 0.25)
	begin("06_curve_run")
	key(KEY_SHIFT, true)
	key(KEY_W, true)
	await frames(20)
	_look_px = 9.0
	await frames(50)
	_look_px = -12.0
	await frames(40)
	_look_px = 0.0
	await frames(15)
	finish()


func _s07_slope() -> void:
	var best := _flat
	var best_rise := -1.0
	var from := _flat
	for r in [0.0, 60.0, 120.0]:
		for i in 16:
			var a := TAU * i / 16.0
			var base: Vector2 = _flat + _gate_dir() * r
			var tgt: Vector2 = base + Vector2(cos(a), sin(a)) * 25.0
			if WorldGen.is_water(tgt.x, tgt.y):
				continue
			var rise := WorldGen.height(tgt.x, tgt.y) - WorldGen.height(base.x, base.y)
			if rise > best_rise:
				best_rise = rise
				best = tgt
				from = base
	await teleport(from, yaw_to(ground(best)), 30)
	player.set_camera(yaw_to(ground(best)), -0.18)
	log_line("slope rise %.1f m over 25 m" % best_rise)
	begin("07_slope_up_down")
	await frames(10)
	key(KEY_W, true)
	await frames(80)
	key(KEY_SHIFT, true)
	await frames(30)
	key(KEY_SHIFT, false)
	key(KEY_W, false)
	await frames(10)
	# Turn around and come down.
	key(KEY_S, true)
	await frames(15)
	key(KEY_S, false)
	player.set_camera(yaw_to(ground(from)), -0.18)
	key(KEY_W, true)
	key(KEY_SHIFT, true)
	await frames(60)
	finish()


## Walk along the village edge with houses between the camera and the body.
func _s08_camera_collision() -> void:
	var s: Dictionary = WorldGen.settlements[0]
	var c: Vector2 = s["pos"]
	await teleport(c + _gate_dir() * 6.0, 0.0, 40)
	# Look toward the nearest building so the camera must dodge it while orbiting.
	begin("08_camera_orbit_collision")
	key(KEY_W, true)
	await frames(30)
	key(KEY_W, false)
	_look_px = 14.0
	await frames(70)
	_look_px = 0.0
	key(KEY_W, true)
	key(KEY_D, true)
	await frames(45)
	key(KEY_D, false)
	key(KEY_W, false)
	_look_px = -14.0
	await frames(50)
	finish()


func _s09_combo_air() -> void:
	await teleport(_flat, 0.3)
	player.stamina = Player.MAX_STAMINA
	begin("09_combo_4hit_idle")
	await frames(10)
	for i in 4:
		await tap(KEY_J)
		await frames(11)
	await frames(40)
	# Running swing: legs keep going while the arms attack.
	key(KEY_W, true)
	key(KEY_SHIFT, true)
	await frames(25)
	await tap(KEY_J)
	await frames(25)
	key(KEY_W, false)
	key(KEY_SHIFT, false)
	await frames(30)
	finish()


func _spawn_orc(at: Vector2) -> CampMonster:
	var m := CampMonster.new()
	m.species = "orc"
	m.home = at
	m.home_radius = 30.0
	main.world.add_child(m)
	m.global_position = ground(at)
	return m


func _s10_13_combat() -> void:
	var wild := await _find_flat(140.0, true)
	await teleport(wild, 0.0, 30)
	var fwd := Vector2(-sin(player._yaw), -cos(player._yaw))
	var orc := _spawn_orc(wild + fwd * 5.0)
	player.set_camera(yaw_to(orc.global_position) + 1.0, -0.22)   # side-on: both bodies readable
	player.stamina = Player.MAX_STAMINA
	player.health = player.max_health
	await frames(40)
	log_line("orc at %.1f m, state %d" % [orc.global_position.distance_to(player.global_position), orc.state])
	if want("10"):
		begin("10_combo_on_orc")
		for i in 4:
			await tap(KEY_J)
			await frames(12)
		await frames(45)
		finish()
	if want("11"):
		player.stamina = Player.MAX_STAMINA
		begin("11_block_orc")
		key(KEY_L, true)
		await frames(110)
		key(KEY_L, false)
		await frames(15)
		finish()
	if want("12"):
		player.stamina = Player.MAX_STAMINA
		begin("12_dodge")
		await tap(KEY_SPACE)          # backward roll (no stick)
		await frames(30)
		key(KEY_D, true)
		await frames(2)
		await tap(KEY_SPACE)          # side roll
		await frames(10)
		key(KEY_D, false)
		await frames(25)
		key(KEY_W, true)
		await frames(2)
		await tap(KEY_SPACE)          # forward roll, then keep running
		await frames(30)
		key(KEY_W, false)
		await frames(25)
		finish()
	if want("13"):
		player.stamina = Player.MAX_STAMINA
		player.health = player.max_health
		if is_instance_valid(orc) and not orc.dead:
			player.set_camera(yaw_to(orc.global_position) + 1.0, -0.22)
		begin("13_get_hit_idle")
		await frames(150)
		player.health = player.max_health
		finish()
	if is_instance_valid(orc):
		orc.queue_free()


func _s14_talk() -> void:
	var s: Dictionary = WorldGen.settlements[0]
	await teleport(s["pos"], 0.0, 60)
	var best: Node3D = null
	var bd := INF
	for v in get_tree().get_nodes_in_group("villager"):
		var n := v as Node3D
		if n == null or not n.visible:
			continue
		var d := n.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = n
	if best == null:
		log_line("no villager for talk")
		return
	var off := Vector2(best.global_position.x - player.global_position.x, best.global_position.z - player.global_position.z)
	var stand := Vector2(best.global_position.x, best.global_position.z) - off.normalized() * 2.2
	await teleport(stand, 0.0, 10)
	player.set_camera(yaw_to(best.global_position), -0.2)
	begin("14_talk_npc")
	key(KEY_W, true)
	await frames(8)
	key(KEY_W, false)
	await frames(20)
	await tap(KEY_E)
	await frames(90)
	await tap(KEY_E)
	await frames(8)
	if main.hud.is_menu_open():
		main.hud.close_menu()
	await frames(20)
	finish()


func _s15_crowd() -> void:
	var s: Dictionary = WorldGen.settlements[0]
	var c: Vector2 = s["pos"]
	await teleport(c - _gate_dir() * 4.0, 0.0, 90)
	player.set_view(Player.View.THIRD)
	# Look at the densest knot of embodied residents within 30 m.
	var best := c + _gate_dir() * 12.0
	var best_n := -1
	for v in get_tree().get_nodes_in_group("villager"):
		var vp := (v as Node3D).global_position
		if vp.distance_to(player.global_position) > 30.0:
			continue
		var n := 0
		for w in get_tree().get_nodes_in_group("villager"):
			if (w as Node3D).global_position.distance_to(vp) < 6.0:
				n += 1
		if n > best_n:
			best_n = n
			best = Vector2(vp.x, vp.z)
	var to2 := best - Vector2(player.global_position.x, player.global_position.z)
	await teleport(best - to2.normalized() * 7.0, 0.0, 30)
	player.set_camera(yaw_to(ground(best)), -0.3)
	log_line("crowd knot of %d at %s" % [best_n, best])
	begin("15_crowd_plaza")
	await frames(60)
	_look_px = 6.0
	await frames(90)
	_look_px = 0.0
	await frames(30)
	finish()


func _s16_wolves() -> void:
	var wild := await _find_flat(160.0, true)
	await teleport(wild, 0.0, 30)
	var fwd := Vector2(-sin(player._yaw), -cos(player._yaw))
	var pack: Array = []
	for i in 3:
		var w := Wolf.new()
		w.species = "wolf"
		var at: Vector2 = wild + fwd * 22.0 + fwd.orthogonal() * (i - 1) * 3.0
		w.home = at
		w.territory = 200.0
		main.world.add_child(w)
		w.global_position = ground(at)
		w._provoked = 8.0
		pack.append(w)
	player.health = player.max_health
	player.set_camera(yaw_to(ground(wild + fwd * 20.0)), -0.2)
	begin("16_wolves_chase_attack")
	await frames(60)
	for w in pack:
		log_line("wolf valid=%s pos=%s d=%.1f state=%s" % [is_instance_valid(w), (w as Node3D).global_position if is_instance_valid(w) else Vector3.ZERO, (w as Node3D).global_position.distance_to(player.global_position) if is_instance_valid(w) else -1.0, str(w.state) if is_instance_valid(w) else "-"])
		if is_instance_valid(w):
			log_line("  wolf model=%s vis=%s kind=%s aabb_nodes=%d" % [str(w._model), str(w.is_visible_in_tree()), w._kind, (w as Node).find_children("*", "MeshInstance3D", true, false).size()])
	# Back-pedal a little so they chase, then stand and take them.
	key(KEY_S, true)
	await frames(30)
	key(KEY_S, false)
	player.set_camera(yaw_to((pack[1] as Node3D).global_position), -0.22)
	for i in 6:
		await frames(15)
		await tap(KEY_J)
	await frames(60)
	player.health = player.max_health
	finish()
	for w in pack:
		if is_instance_valid(w):
			w.queue_free()


func _s17_horse() -> void:
	var s: Dictionary = WorldGen.settlements[0]
	await teleport(s["pos"], 0.0, 60)
	var horse: Node3D = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.has_method("rideable") and n.call("rideable"):
			var d := (n as Node3D).global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				horse = n
	if horse == null:
		log_line("no horse found")
		return
	var hp := Vector2(horse.global_position.x, horse.global_position.z)
	await teleport(hp + Vector2(1.6, 0.0), 0.0, 10)
	player.toggle_mount(horse)
	await frames(10)
	player.set_camera(player._mount.yaw + PI if player._mount else 0.0, -0.25)
	begin("17_horse_ride")
	key(KEY_W, true)
	await frames(60)
	key(KEY_SHIFT, true)
	await frames(60)
	_look_px = 8.0
	await frames(30)
	_look_px = 0.0
	key(KEY_SHIFT, false)
	key(KEY_W, false)
	await frames(50)
	finish()
	player.toggle_mount()
	await frames(10)


func _s18_swim() -> void:
	var lc := WorldGen.lake_center
	if lc.x > 1.0e5:
		log_line("no lake")
		return
	var dir := (Vector2.ZERO - lc).normalized()
	var shore := lc
	for r in range(int(WorldGen.lake_radius * 0.5), int(WorldGen.lake_radius * 2.0), 4):
		var p := lc + dir * r
		if not WorldGen.is_water(p.x, p.y):
			shore = p + dir * 6.0
			break
	await teleport(shore, 0.0, 40)
	player.set_camera(yaw_to(ground(lc)), -0.25)
	begin("18_swim")
	key(KEY_W, true)
	await frames(150)
	key(KEY_W, false)
	await frames(40)
	finish()
