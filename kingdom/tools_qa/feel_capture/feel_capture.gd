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
var _closeup := false
var _default_hero := false
var _no_procedural := false
var _pose_csv: FileAccess
var _pose_skeleton: Skeleton3D
var _pose_bones: Dictionary = {}
var _capture_failed := false

class ActorContactDriver extends Node:
	var actor: CharacterBody3D
	var target: CharacterBody3D
	var contacted := false
	var direction := Vector3.ZERO
	func _physics_process(delta: float) -> void:
		if not is_instance_valid(actor):
			return
		actor.velocity.x = direction.x
		actor.velocity.z = direction.z
		actor.velocity.y = 0.0 if actor.is_on_floor() else actor.velocity.y - 18.0 * delta
		actor.move_and_slide()
		for collision_index in actor.get_slide_collision_count():
			contacted = contacted or actor.get_slide_collision(collision_index).get_collider() == target


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := _args()
	_closeup = args.has("closeup")
	_default_hero = args.has("default-hero")
	_no_procedural = args.has("no-procedural")
	out_dir = String(args.get("out", ProjectSettings.globalize_path("res://").path_join("../docs/anim/feel/capture"))).simplify_path()
	if args.has("only"):
		only = String(args["only"]).split(",", false)
	DirAccess.make_dir_recursive_absolute(out_dir)
	if args.has("pose-data"):
		_pose_csv = FileAccess.open(out_dir.path_join("pose.csv"), FileAccess.WRITE)
		_pose_csv.store_line("frame,scenario,bone,x,y,z,qx,qy,qz,qw,terrain_gap,pivot_clip,pivot_time")
		RenderingServer.frame_post_draw.connect(_pose_telemetry)
	_csv = FileAccess.open(out_dir.path_join("telemetry.csv"), FileAccess.WRITE)
	_csv.store_line("frame,scenario,x,y,z,real_speed,move_speed,anim_speed,model_yaw_deg,yaw_rate,loco_blend,gait_rate,cam_x,cam_y,cam_z,on_floor,process_ms,render_cam_dist,render_body_x,render_body_z,loco_kind,turn_clip")
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
	_csv.store_line("%d,%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.1f,%.2f,%.3f,%.3f,%.3f,%.3f,%.3f,%d,%.2f,%.3f,%.3f,%.3f,%s,%s" % [
		frame, scn, player.global_position.x, player.global_position.y, player.global_position.z,
		rs, player._move_speed, anim.shown_speed() if anim else 0.0, yaw, player._yaw_rate, loco, rate,
		cp.x, cp.y, cp.z, 1 if player.is_on_floor() else 0, pms, rb.distance_to(rc), rb.x, rb.z,
		str(player.get("_loco_kind")), str(player.get("_turn_clip"))])
	_label.text = "FEEL %s  f%d  t%.2fs | body %.2f m/s  anim %.2f  loco %.2f  rate %.2f | face %.0f°" % [
		scn, frame - _scn_start, (frame - _scn_start) / FPS, rs, anim.shown_speed() if anim else 0.0, loco, rate, yaw]


func _pose_telemetry() -> void:
	if _pose_csv == null or not is_processing() or not is_instance_valid(player):
		return
	if not is_instance_valid(_pose_skeleton):
		var found := player._body_node.find_children("*", "Skeleton3D", true, false)
		if found.is_empty():
			return
		_pose_skeleton = found[0] as Skeleton3D
		_pose_bones.clear()
		for name: String in ["foot_l", "foot_r", "hand_r"]:
			var index := _pose_skeleton.find_bone(name)
			if index >= 0:
				_pose_bones[name] = index
	for name: String in _pose_bones:
		# Final bone pose after modifiers, under interpolated skeleton transform.
		# Bone-local render interpolation is not exposed; this is a pose diagnostic.
		var pose := _pose_skeleton.get_global_transform_interpolated() * _pose_skeleton.get_bone_global_pose(_pose_bones[name])
		var p := pose.origin
		var q := pose.basis.orthonormalized().get_rotation_quaternion()
		# _pivoting is the fallback brake state; authored pivots use _pivot_clip.
		var clip := player._pivot_clip
		var clock := player._animator.air_clip_time(clip) if not clip.is_empty() else -1.0
		_pose_csv.store_line("%d,%s,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%s,%.6f" % [frame, scn, name, p.x, p.y, p.z, q.x, q.y, q.z, q.w, p.y - WorldGen.height(p.x, p.z), clip, clock])


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
	if is_instance_valid(player):
		player.touch_move = Vector2.ZERO
	for k in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SHIFT, KEY_L, KEY_SPACE, KEY_J, KEY_K]:
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
	if _default_hero:
		Life.appearance = {}
		player.apply_appearance()
		log_line("Appearance fixture: default Style G hero")
	if _closeup and player.camera:
		player.camera.fov = 35.0
		log_line("Closeup fixture: 35 degree camera FOV")
	WorldSim.time_of_day = 13.0
	Life.life_path.set_age(18, WorldSim.day, WorldSim.time_of_day)
	player.apply_age()
	if _no_procedural:
		var modifiers := player._body_node.find_children("*", "SkeletonModifier3D", true, false)
		for modifier: SkeletonModifier3D in modifiers:
			modifier.active = false
		log_line("Pose isolation: disabled %d procedural skeleton modifiers" % modifiers.size())
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
	if want("19"): await _s19_jumps()
	if want("20"): await _s20_fall_land()
	if want("21") or want("22"): await _s21_22_parry_heavy_hit()
	if want("23"): await _s23_companions()
	if want("24"): await _s24_pivot_interruptions()
	if want("25"): await _s25_pivot_wall()
	if want("26"): await _s26_pivot_directions()
	if want("27"): await _s27_actor_contact()
	if want("28"): await _s28_wolf_pack_close()
	log_line("DONE")
	# quit() is deferred; stop the next frame from writing the closed CSV.
	set_process(false)
	if _pose_csv:
		RenderingServer.frame_post_draw.disconnect(_pose_telemetry)
		_pose_csv.close()
		_pose_csv = null
	_index.close()
	_csv.close()
	get_tree().quit(1 if _capture_failed else 0)


## Close wolf pack for the P2b clips: two wolves 6-7 m away, facing away from the player (so they must turn in place),
## provoked, while the player holds still; then the player steps back to draw a lunge. Logs the wolf's clip every 6 frames.
func _s28_wolf_pack_close() -> void:
	var wild := await _find_flat(160.0, true)
	await teleport(wild, 0.0, 30)
	var fwd := Vector2(-sin(player._yaw), -cos(player._yaw))
	var pack: Array = []
	for i in 2:
		var w := Wolf.new()
		w.species = "wolf"
		var at: Vector2 = wild + fwd * 7.0 + fwd.orthogonal() * (i * 2.0 - 1.0) * 1.6
		w.home = at
		w.territory = 200.0
		main.world.add_child(w)
		w.global_position = ground(at)
		w.rotation.y = atan2(fwd.x, fwd.y) + (0.0 if i == 0 else PI * 0.5)    # one faces away from the player, one sideways
		w._provoked = 20.0
		pack.append(w)
	player.health = player.max_health
	player.set_camera(yaw_to((pack[0] as Node3D).global_position) + 1.1, -0.2)
	begin("28_wolf_pack_close")
	for i in 60:
		await frames(6)
		for w in pack:
			if is_instance_valid(w) and w._anim:
				var to_p: Vector3 = player.global_position - w.global_position
				log_line("wolf%d clip=%s state=%d spin=%d lunge=%.2f d=%.2f yaw_err=%.0f busy=%.2f wind=%.2f" % [pack.find(w), w._anim.current_animation, w.state, w._spin_deg, w._lunge_t, w.global_position.distance_to(player.global_position), rad_to_deg(angle_difference(w.rotation.y, atan2(to_p.x, to_p.z))), w._busy, w._winding])
		player.health = player.max_health
	finish()
	for w in pack:
		if is_instance_valid(w):
			w.queue_free()


func _s27_actor_contact() -> void:
	for moving: bool in [false, true]:
		# Acquire an embodied resident inside its actual LOD range first.
		var town: Vector2 = WorldGen.settlements[0]["pos"]
		await teleport(town, 0.0, 90)
		var actor: Villager = null
		var nearest := INF
		for candidate in get_tree().get_nodes_in_group("villager"):
			if candidate is Villager and is_instance_valid(candidate._shape):
				var distance: float = candidate.global_position.distance_squared_to(player.global_position)
				if distance < nearest:
					nearest = distance
					actor = candidate
		if actor == null:
			_capture_failed = true
			log_line("FAIL: no real villager available for contact fixture")
			return
		var original := actor.global_transform
		var original_velocity := actor.velocity
		var processing := actor.is_physics_processing()
		var disabled := actor._shape.disabled
		var lod_owner := actor.get_parent()
		var lod_processing := lod_owner.is_processing()
		lod_owner.set_process(false)
		actor.set_physics_process(false)
		actor._shape.set_deferred("disabled", false)
		await frames(2)
		# main._teleport refreshes LOD synchronously even when its process is paused.
		# Relocate the owned body first so that refresh sees it at the new focus.
		actor.global_position = ground(_flat) + Vector3.RIGHT * 4.0
		actor.global_position.y = WorldGen.height(actor.global_position.x, actor.global_position.z)
		WorldSim.set_external_position_owner(actor.person, actor.get_instance_id(), true, actor.sim_position(), true)
		actor.reset_physics_interpolation()
		await teleport(_flat, 0.0, 0)
		await frames(30)
		begin("27_actor_contact_%s" % ("moving" if moving else "stationary"))
		key(KEY_SHIFT, true)
		key(KEY_W, true)
		await frames(55)
		if not is_instance_valid(actor):
			_capture_failed = true
			log_line("FAIL: villager removed during contact fixture")
			lod_owner.set_process(lod_processing)
			finish()
			return
		var approach := player._move_dir.normalized()
		actor.global_position = player.global_position + approach * 0.8
		actor.global_position.y = WorldGen.height(actor.global_position.x, actor.global_position.z)
		actor.reset_physics_interpolation()
		actor.velocity = Vector3.ZERO
		var driver := ActorContactDriver.new()
		driver.actor = actor
		driver.target = player
		driver.direction = -approach * 0.6 if moving else Vector3.ZERO
		main.add_child(driver)
		key(KEY_W, false)
		key(KEY_S, true)
		var contacted := false
		var minimum := INF
		for i in 35:
			await frames(1)
			if not is_instance_valid(actor):
				break
			for collision_index in player.get_slide_collision_count():
				contacted = contacted or player.get_slide_collision(collision_index).get_collider() == actor
			contacted = contacted or driver.contacted
			var separation := player.global_position - actor.global_position
			minimum = minf(minimum, Vector2(separation.x, separation.z).length())
		if not is_instance_valid(actor):
			_capture_failed = true
			log_line("FAIL: villager removed while sampling contact")
			driver.set_physics_process(false)
			driver.queue_free()
			lod_owner.set_process(lod_processing)
			finish()
			return
		var actor_capsule := actor._shape.shape as CapsuleShape3D
		var clearance := player._capsule.radius + actor_capsule.radius
		if not contacted or minimum < clearance - 0.035:
			_capture_failed = true
			log_line("FAIL: actor contacted=%s min_spacing=%.3f required=%.3f" % [contacted, minimum, clearance])
		else:
			log_line("Actor contact confirmed; min_spacing=%.3f required=%.3f" % [minimum, clearance])
		driver.set_physics_process(false)
		driver.queue_free()
		actor.global_transform = original
		WorldSim.set_external_position_owner(actor.person, actor.get_instance_id(), true, actor.sim_position(), true)
		actor.velocity = original_velocity
		actor.reset_physics_interpolation()
		actor._shape.set_deferred("disabled", disabled)
		actor.set_physics_process(processing)
		lod_owner.set_process(lod_processing)
		finish()
		await frames(2)


func _s26_pivot_directions() -> void:
	for side: float in [-0.12, 0.12]:
		await teleport(_flat, 0.0, 30)
		begin("26_pivot_%s" % ("left" if side < 0 else "right"))
		key(KEY_SHIFT, true)
		key(KEY_W, true)
		await frames(55)
		key(KEY_W, false)
		player.touch_move = Vector2(side, 1.0).normalized()
		await frames(3)
		var expected := "Loco_Pivot180_Run_L" if side < 0 else "Loco_Pivot180_Run_R"
		if player._pivot_clip != expected:
			_capture_failed = true
			log_line("FAIL: expected %s, entered %s" % [expected, player._pivot_clip])
			finish()
			return
		log_line("Direction fixture entered %s" % expected)
		await frames(40)
		var error := absf(angle_difference(player._model.rotation.y, atan2(side, 1.0)))
		if not player._pivot_clip.is_empty() or error > 0.05:
			_capture_failed = true
			log_line("FAIL: pivot did not finish aligned; heading_error=%.3f" % error)
		else:
			log_line("Direction fixture finished aligned; heading_error=%.3f" % error)
		finish()


func _s25_pivot_wall() -> void:
	await teleport(_flat, 0.0, 30)
	begin("25_pivot_wall")
	key(KEY_SHIFT, true)
	key(KEY_W, true)
	await frames(55)
	var approach := player._move_dir.normalized()
	var origin := player.global_position
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 3.0, 0.25)
	var shape := CollisionShape3D.new()
	shape.shape = box
	wall.add_child(shape)
	var mesh := MeshInstance3D.new()
	var visual := BoxMesh.new()
	visual.size = box.size
	mesh.mesh = visual
	wall.add_child(mesh)
	main.add_child(wall)
	wall.global_position = origin + approach * 0.8 + Vector3.UP * 1.5
	wall.rotation.y = atan2(approach.x, approach.z)
	key(KEY_W, false)
	key(KEY_S, true)
	var entered := false
	var cancelled := false
	var contacted := false
	var peak_forward := 0.0
	for i in 24:
		await frames(1)
		entered = entered or not player._pivot_clip.is_empty()
		cancelled = cancelled or (entered and player._pivot_clip.is_empty())
		for collision_index in player.get_slide_collision_count():
			contacted = contacted or player.get_slide_collision(collision_index).get_collider() == wall
		peak_forward = maxf(peak_forward, (player.global_position - origin).dot(approach))
	# Near face is 0.675 m from origin; include the actual capsule radius.
	var safe_forward := 0.675 - player._capsule.radius + 0.03
	if not entered or not contacted or not cancelled or peak_forward >= safe_forward:
		_capture_failed = true
		log_line("FAIL: wall pivot entered=%s contacted=%s cancelled=%s peak_forward=%.3f" % [entered, contacted, cancelled, peak_forward])
	else:
		log_line("Wall pivot cancelled without crossing wall; peak_forward=%.3f" % peak_forward)
	finish()
	wall.queue_free()
	await frames(2)


func _s24_pivot_interruptions() -> void:
	for action: String in ["release", "attack", "dodge", "jump", "block"]:
		await teleport(_flat, 0.0, 30)
		player.stamina = player.MAX_STAMINA
		begin("24_pivot_interrupt_%s" % action)
		key(KEY_SHIFT, true)
		key(KEY_W, true)
		await frames(55)
		key(KEY_W, false)
		key(KEY_S, true)
		await frames(6)
		if player._pivot_clip.is_empty():
			_capture_failed = true
			log_line("FAIL: interruption fixture did not enter authored pivot")
			finish()
			return
		log_line("Interrupt %s entered %s" % [action, player._pivot_clip])
		match action:
			"release": key(KEY_S, false)
			"attack": await tap(KEY_J)
			"dodge": await tap(KEY_K)
			"jump": await tap(KEY_SPACE)
			"block": key(KEY_L, true)
		await frames(8)
		if not player._pivot_clip.is_empty():
			_capture_failed = true
			log_line("FAIL: authored pivot survived interruption: %s" % action)
			finish()
			return
		log_line("Interrupt %s cancelled authored pivot" % action)
		await frames(35)
		finish()


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
		await tap(KEY_K)          # backward roll (no stick)
		await frames(30)
		key(KEY_D, true)
		await frames(2)
		await tap(KEY_K)          # side roll
		await frames(10)
		key(KEY_D, false)
		await frames(25)
		key(KEY_W, true)
		await frames(2)
		await tap(KEY_K)          # forward roll, then keep running
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


# --- Codex integration review (docs/anim/CODEX_INTEGRATION_REVIEW.md) -----------------

## Standing jump, running jump (sprint), and jump spam on landing (buffer).
func _s19_jumps() -> void:
	await teleport(_flat, 0.0)
	begin("19_jumps")
	await frames(15)
	await tap(KEY_SPACE)               # standing jump
	await frames(45)
	key(KEY_SHIFT, true)
	key(KEY_W, true)
	await frames(40)
	await tap(KEY_SPACE)               # running jump
	await frames(40)
	key(KEY_W, false)
	key(KEY_SHIFT, false)
	await frames(40)
	for i in 4:                        # spam: buffered re-jumps
		await tap(KEY_SPACE)
		await frames(9)
	await frames(50)
	finish()


## Drop from 2.5 m (soft/hard land) and 7 m (roll / fall damage), standing and running.
func _s20_fall_land() -> void:
	for h: float in [2.5, 7.0]:
		await teleport(_flat, 0.0, 15)
		player.health = player.max_health
		begin("20_fall_%dm" % int(h))
		player.global_position += Vector3.UP * h
		player.velocity = Vector3.ZERO
		await frames(70)
		finish()
	await teleport(_flat, 0.0, 15)
	begin("20_fall_run_4m")
	key(KEY_W, true)
	key(KEY_SHIFT, true)
	await frames(20)
	player.global_position += Vector3.UP * 4.0
	await frames(60)
	key(KEY_W, false)
	key(KEY_SHIFT, false)
	await frames(30)
	finish()
	player.health = player.max_health


## 21: block raised 3 frames before a hit lands (parry). 22: heavy hits from four sides, then a guard break.
func _s21_22_parry_heavy_hit() -> void:
	var wild := await _find_flat(140.0, true)
	await teleport(wild, 0.0, 30)
	var fwd := Vector2(-sin(player._yaw), -cos(player._yaw))
	var orc := _spawn_orc(wild + fwd * 2.0)
	orc.set_physics_process(false)
	player.set_camera(yaw_to(orc.global_position) + 1.0, -0.22)
	player.stamina = Player.MAX_STAMINA
	player.health = player.max_health
	await frames(20)
	if want("21"):
		begin("21_parry")
		for i in 2:
			key(KEY_L, true)
			await frames(3)
			player.take_damage(12, orc, (player.global_position - orc.global_position).normalized() * 2.0)
			await frames(40)
			key(KEY_L, false)
			await frames(15)
		await frames(20)
		finish()
	if want("22"):
		player.health = player.max_health * 4
		begin("22_hit_reactions")
		for ang: float in [0.0, PI * 0.5, PI, -PI * 0.5]:
			var src := Node3D.new()
			main.world.add_child(src)
			var d := Vector3(-sin(player._yaw + ang), 0, -cos(player._yaw + ang))
			src.global_position = player.global_position + d * 1.5
			player.take_damage(4, src, -d * 1.0)          # light
			await frames(30)
			player.take_damage(int(player.max_health * 0.15), src, -d * 5.0, true)   # heavy
			await frames(45)
			src.queue_free()
		player.stamina = 1.0                          # guard break
		key(KEY_L, true)
		await frames(10)
		player.take_damage(20, orc, Vector3.ZERO)
		await frames(50)
		key(KEY_L, false)
		await frames(20)
		player.health = player.max_health
		finish()
	if is_instance_valid(orc):
		orc.queue_free()


## Companions: four knights follow a walk and a sprint, then stop with the player; combo finisher on an orc next to them.
func _s23_companions() -> void:
	await teleport(_flat, 0.0, 15)
	var sq: Squad = main.army
	sq.add_soldiers(4, player.global_position + Vector3(0, 0, 3))
	sq.command(Squad.Order.FOLLOW)
	await frames(60)
	for so in sq.soldiers:
		log_line("knight at %.1f m vis=%s" % [so.global_position.distance_to(player.global_position), so.is_visible_in_tree()])
	if not sq.soldiers.is_empty():
		player.set_camera(yaw_to(sq.soldiers[0].global_position), -0.45)   # knights in view; S walks the player toward the lens, they follow
	begin("23_companions_follow_stop")
	key(KEY_S, true)
	await frames(80)
	key(KEY_SHIFT, true)
	await frames(60)
	key(KEY_SHIFT, false)
	key(KEY_S, false)
	await frames(90)
	for so in sq.soldiers:
		log_line("after stop knight at %.1f m" % so.global_position.distance_to(player.global_position))
	finish()
	var fwd := Vector2(-sin(player._yaw), -cos(player._yaw))
	var here := Vector2(player.global_position.x, player.global_position.z)
	var orc := _spawn_orc(here + fwd * 6.0)
	player.stamina = Player.MAX_STAMINA
	player.set_camera(yaw_to(orc.global_position) + 1.2, -0.25)
	begin("23_companions_fight")
	for i in 4:
		await tap(KEY_J)
		await frames(12)
	await frames(120)
	finish()
	if is_instance_valid(orc):
		orc.queue_free()
