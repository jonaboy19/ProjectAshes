extends Node
## In-game combat capture (docs/anim/COMBAT_AUDIT.md). Boots the REAL game (main.tscn) and plays
## fixed combat scenarios through the real input path, waiting in rendered frames so a run is
## deterministic under Godot Movie Maker (30 fps):
##
##   Godot --path kingdom --rendering-method mobile --write-movie <dir>/combat.avi --fixed-fps 30 \
##       res://tools_qa/combat_audit/combat_capture.tscn -- --adult --skipintro --out=<dir> [--only=c01,c04]
##
## <out>/telemetry.csv logs, every frame: player blade tip position and speed (from the sword
## prop on hand_r), the upper-body clip and swing timers, Engine.time_scale (hit-stop), camera
## FOV/offset (shake), and for the nearest enemy its state, wind-up, clip and distance. This is
## what proves (or disproves) that damage, hit-stop, sparks and the slash arc land on the blade's
## fast frames. <out>/scenarios.txt lists each scenario's first/last movie frame.
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
var _tip_prev := Vector3.INF
var _blade_bone := -1
var _blade_tip := Vector3.ZERO
var _sk: Skeleton3D
var _enemies: Array = []
var _last_swing_id := -1
var _style := "sword"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := _args()
	out_dir = String(args.get("out", "user://combat_capture")).simplify_path()
	if args.has("only"):
		only = String(args["only"]).split(",", false)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_csv = FileAccess.open(out_dir.path_join("telemetry.csv"), FileAccess.WRITE)
	_csv.store_line("frame,scenario,sf,px,pz,yaw,tip_x,tip_y,tip_z,tip_speed,upper_clip,upper_active,full_active,swing,swing_elapsed,swing_id,time_scale,cam_fov,cam_h,cam_v,enemy,e_state,e_winding,e_busy,e_clip,e_clip_pos,e_dist,player_hp,flinch")
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
		_telemetry()


func _find_blade() -> void:
	_sk = player._model.find_children("*", "Skeleton3D", true, false)[0]
	for att in _sk.find_children("*", "BoneAttachment3D", true, false):
		var a := att as BoneAttachment3D
		if a.bone_name != "hand_r" or a.get_child_count() == 0:
			continue
		var prop := a.get_child(0) as Node3D
		var box := AABB()
		var first := true
		for mi in prop.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var xf := Transform3D.IDENTITY
			var c: Node = m
			while c != null and c != a:
				if c is Node3D:
					xf = (c as Node3D).transform * xf
				c = c.get_parent()
			var b := xf * m.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var ax := 0
		for i in 3:
			if box.size[i] > box.size[ax]:
				ax = i
		var lo := box.get_center()
		var hi := lo
		lo[ax] = box.position[ax]
		hi[ax] = box.end[ax]
		_blade_tip = hi if hi.length() > lo.length() else lo
		_blade_bone = _sk.find_bone("hand_r")
		return


func _tip() -> Vector3:
	if _blade_bone < 0:
		return Vector3.ZERO
	return _sk.global_transform * _sk.get_bone_global_pose(_blade_bone) * _blade_tip


func _telemetry() -> void:
	var anim: CharacterAnimator = player._animator
	var tip := _tip()
	var ts := Engine.time_scale
	var tip_speed := 0.0
	if _tip_prev != Vector3.INF:
		tip_speed = (tip - _tip_prev).length() * FPS   # per rendered frame (hit-stop shows as ~0)
	_tip_prev = tip
	var upper := String(anim._upper_anim.animation) if anim else ""
	var ua := bool(anim.tree.get("parameters/upper/active")) if anim else false
	var fa := bool(anim.tree.get("parameters/full/active")) if anim else false
	var cam := player.camera
	var e: Node3D = null
	var ed := INF
	for en in _enemies:
		if is_instance_valid(en) and not en.get("dead"):
			var d := (en as Node3D).global_position.distance_to(player.global_position)
			if d < ed:
				ed = d
				e = en
	var e_state := ""
	var e_wind := 0.0
	var e_busy := 0.0
	var e_clip := ""
	var e_pos := 0.0
	if e:
		e_state = str(e.get("state"))
		e_wind = float(e.get("_winding")) if e.get("_winding") != null else 0.0
		e_busy = float(e.get("_busy")) if e.get("_busy") != null else 0.0
		var ap: AnimationPlayer = e.get("_anim")
		if ap:
			e_clip = String(ap.current_animation)
			e_pos = ap.current_animation_position if ap.is_playing() else 0.0
	var sf := frame - _scn_start
	_csv.store_line("%d,%s,%d,%.3f,%.3f,%.1f,%.3f,%.3f,%.3f,%.2f,%s,%d,%d,%.3f,%.3f,%d,%.3f,%.2f,%.3f,%.3f,%s,%s,%.3f,%.3f,%s,%.3f,%.2f,%d,%.3f" % [
		frame, scn, sf, player.global_position.x, player.global_position.z, rad_to_deg(player._model.rotation.y),
		tip.x, tip.y, tip.z, tip_speed, upper, 1 if ua else 0, 1 if fa else 0, player._swing, player._swing_elapsed,
		player._swing_id, ts, cam.fov if cam else 0.0, cam.h_offset if cam else 0.0, cam.v_offset if cam else 0.0,
		e.name if e else "", e_state, e_wind, e_busy, e_clip, e_pos, ed if e else -1.0, player.health, player._flinch])
	var tag := ""
	if ts < 0.5:
		tag = "  HITSTOP"
	if e and e_wind > 0.0:
		tag += "  ENEMY WINDUP %.2f" % e_wind
	_label.text = "COMBAT %s  f%d | tip %.1f m/s | %s %s%s" % [scn, sf, tip_speed, upper if ua else "-", ("swing %.2f" % player._swing_elapsed) if player._swing > 0.0 else "", tag]


# --- helpers ------------------------------------------------------------------------------

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


func log_line(t: String) -> void:
	print("COMBATCAP [f%d] %s" % [frame, t])


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
	player.set_camera(yaw, -0.22)
	await frames(settle)


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


func _find_flat(min_dist: float) -> Vector2:
	var s: Dictionary = WorldGen.settlements[0]
	var c: Vector2 = s["pos"]
	var d := float(s.get("radius", 60.0)) + min_dist
	var a := 0.0
	if s.has("plan") and not (s["plan"]["gates"] as Array).is_empty():
		a = float(s["plan"]["gates"][0])
	var dir := Vector2(cos(a), sin(a))
	var best := c + dir * d
	for attempt in 40:
		for side in [0.0, 0.5, -0.5, 1.0, -1.0]:
			var p: Vector2 = c + dir.rotated(side) * d
			var slope := absf(WorldGen.height(p.x + 4, p.y) - WorldGen.height(p.x - 4, p.y)) \
					+ absf(WorldGen.height(p.x, p.y + 4) - WorldGen.height(p.x, p.y - 4))
			if WorldGen.is_water(p.x, p.y) or slope > 1.0:
				continue
			if Frontier.runestones.coverage(p) > 0.02:
				continue
			await teleport(p, 0.0, 6)
			if _ground_clear(p, 9.0):
				return p
		d += 20.0
	return best


func _fwd() -> Vector2:
	return Vector2(-sin(player._yaw), -cos(player._yaw))


func _spawn_monster(species: String, at: Vector2) -> CampMonster:
	var m := CampMonster.new()
	m.species = species
	m.home = at
	m.home_radius = 30.0
	main.world.add_child(m)
	m.global_position = ground(at)
	_enemies.append(m)
	return m


func _spawn_wolf(at: Vector2) -> Node3D:
	var w := Wolf.new()
	w.species = "wolf"
	w.home = at
	w.territory = 200.0
	main.world.add_child(w)
	w.global_position = ground(at)
	w._provoked = 8.0
	_enemies.append(w)
	return w


func _spawn_bandit(at: Vector2) -> Node3D:
	var s := Soldier.create(1, "Bandit", "Bandit", ["1H_Sword", "Round_Shield"])
	main.world.add_child(s)
	s.global_position = ground(at)
	_enemies.append(s)
	return s


func _clear_enemies() -> void:
	for e in _enemies:
		if is_instance_valid(e):
			e.queue_free()
	_enemies.clear()
	await frames(3)


func _refill() -> void:
	player.stamina = Player.MAX_STAMINA
	player.health = player.max_health


## Side-on camera: yaw 90° off the line to the enemy so both bodies and the blade arc read.
func _side_cam(target: Node3D, off := 1.35) -> void:
	player.set_camera(yaw_to(target.global_position) + off, -0.18)


# --- run -----------------------------------------------------------------------------------

func _run() -> void:
	while not (main and main.get("player") != null and main.player.is_inside_tree() and main.get("hud") != null and not main.hud._veil()):
		await get_tree().process_frame
	player = main.player
	WorldSim.time_of_day = 13.0
	Life.life_path.set_age(18, WorldSim.day, WorldSim.time_of_day)
	player.apply_age()
	player.set_view(Player.View.THIRD)
	# Full-motion combat A/B: --classic-combat = the old in-place swings; --style=greatsword|axe|sword; HUD hidden for review movies.
	var args := _args()
	if args.has("classic-combat"):
		(load("res://scripts/combat/combat_chains.gd") as GDScript).set("enabled", false)
		(load("res://scripts/combat/combat_motion.gd") as GDScript).set("enabled", false)
	_style = String(args.get("style", "sword"))
	if args.has("nohud"):
		main.hud.visible = false
		_label.visible = false
	_find_blade()
	log_line("Quality tier=%d blade_bone=%d tip=%s" % [Quality.tier, _blade_bone, _blade_tip])
	if String(_args().get("spot", "")) != "":
		# a fixed spot (e.g. the slice copse clearing on the real terrain: --world_macro=real --spot=360,152)
		var sp := String(_args()["spot"]).split(",")
		_flat = Vector2(float(sp[0]), float(sp[1]))
	else:
		_flat = await _find_flat(140.0)
	await teleport(_flat, 0.0, 40)
	log_line("flat ground %s" % _flat)
	if want("c01"): await _c01_combo_air()
	if want("c02"): await _c02_combo_orc()
	if want("c03"): await _c03_run_attack()
	if want("c04"): await _c04_parry_orc()
	if want("c05"): await _c05_block_orc()
	if want("c06"): await _c06_enemy_attacks("goblin")
	if want("c07"): await _c06_enemy_attacks("orc")
	if want("c08"): await _c06_enemy_attacks("troll")
	if want("c09"): await _c09_wolf()
	if want("c10"): await _c10_bandit()
	if want("c11"): await _c11_kill_goblin()
	if want("c12"): await _c12_dodge()
	if want("fm01"): await _fm01_duel()
	if want("fm02"): await _fm02_three()
	log_line("ALL DONE")
	_csv.flush()
	get_tree().quit()


func _c01_combo_air() -> void:
	await teleport(_flat, 0.3, 20)
	_refill()
	player.set_camera(player._yaw + 1.35, -0.16)   # side view of the player
	begin("c01_combo_4hit_idle")
	await frames(8)
	for i in 4:
		await tap(KEY_J)
		await frames(11)
	await frames(40)
	finish()


func _c02_combo_orc() -> void:
	await teleport(_flat, 0.0, 20)
	var orc := _spawn_monster("orc", _flat + _fwd() * 2.6)
	_refill()
	await frames(20)
	_side_cam(orc)
	begin("c02_combo_on_orc")
	for i in 4:
		await tap(KEY_J)
		await frames(12)
	await frames(45)
	finish()
	await _clear_enemies()


func _c03_run_attack() -> void:
	await teleport(_flat, 0.0, 20)
	_refill()
	player.set_camera(player._yaw + 1.4, -0.16)
	begin("c03_run_attack")
	key(KEY_W, true)
	key(KEY_SHIFT, true)
	await frames(24)
	await tap(KEY_J)
	await frames(14)
	await tap(KEY_J)
	await frames(24)
	key(KEY_W, false)
	key(KEY_SHIFT, false)
	await frames(30)
	finish()


## Raise the guard just before the orc's strike lands (inside PARRY_WINDOW).
func _c04_parry_orc() -> void:
	await teleport(_flat, 0.0, 20)
	var orc := _spawn_monster("orc", _flat + _fwd() * 2.2)
	orc.state = CampMonster.State.ATTACK
	orc._foe = player
	_refill()
	await frames(10)
	_side_cam(orc)
	begin("c04_parry_riposte_orc")
	var parried := false
	for i in 150:
		await frames(1)
		var w := float(orc._winding)
		if not parried and w > 0.0 and w < 0.12:
			key(KEY_L, true)
			parried = true
			await frames(8)
			key(KEY_L, false)
			await frames(2)
			await tap(KEY_J)          # riposte (parry bonus damage)
			await frames(40)
			break
	finish()
	await _clear_enemies()


func _c05_block_orc() -> void:
	await teleport(_flat, 0.0, 20)
	var orc := _spawn_monster("orc", _flat + _fwd() * 2.2)
	orc.state = CampMonster.State.ATTACK
	orc._foe = player
	_refill()
	await frames(10)
	_side_cam(orc)
	begin("c05_block_orc")
	key(KEY_L, true)
	await frames(120)
	key(KEY_L, false)
	await frames(10)
	finish()
	await _clear_enemies()


## Stand still and take the enemy's attacks: wind-up readability, contact, the player's hit reaction.
func _c06_enemy_attacks(species: String) -> void:
	await teleport(_flat, 0.0, 20)
	var m := _spawn_monster(species, _flat + _fwd() * (2.4 if species != "troll" else 3.2))
	m.state = CampMonster.State.ATTACK
	m._foe = player
	_refill()
	await frames(10)
	_side_cam(m)
	begin("c%s_%s_attacks" % ["06" if species == "goblin" else ("07" if species == "orc" else "08"), species])
	for i in 130:
		await frames(1)
		if player.health < player.max_health * 0.5:
			player.health = player.max_health
	finish()
	await _clear_enemies()


func _c09_wolf() -> void:
	await teleport(_flat, 0.0, 20)
	var w := _spawn_wolf(_flat + _fwd() * 6.0)
	_refill()
	await frames(10)
	_side_cam(w, 1.2)
	begin("c09_wolf_bite")
	for i in 120:
		await frames(1)
		if i == 70:
			await tap(KEY_J)
		if player.health < player.max_health * 0.5:
			player.health = player.max_health
	finish()
	await _clear_enemies()


func _c10_bandit() -> void:
	await teleport(_flat, 0.0, 20)
	var b := _spawn_bandit(_flat + _fwd() * 3.0)
	_refill()
	await frames(10)
	_side_cam(b)
	begin("c10_bandit_duel")
	for i in 8:
		await frames(14)
		await tap(KEY_J)
		if player.health < player.max_health * 0.5:
			player.health = player.max_health
	await frames(40)
	finish()
	await _clear_enemies()


func _c11_kill_goblin() -> void:
	await teleport(_flat, 0.0, 20)
	var g := _spawn_monster("goblin", _flat + _fwd() * 2.3)
	g.named = "Capture"            # named monsters die instead of yielding
	_refill()
	await frames(10)
	_side_cam(g)
	begin("c11_kill_goblin_death")
	for i in 4:
		await tap(KEY_J)
		await frames(12)
	await frames(70)
	finish()
	await _clear_enemies()


func _c12_dodge() -> void:
	await teleport(_flat, 0.0, 20)
	_refill()
	player.set_camera(player._yaw + 1.4, -0.16)
	begin("c12_dodge")
	await tap(KEY_SPACE)
	await frames(26)
	key(KEY_D, true)
	await frames(2)
	await tap(KEY_SPACE)
	await frames(10)
	key(KEY_D, false)
	await frames(24)
	key(KEY_W, true)
	await frames(2)
	await tap(KEY_SPACE)
	await frames(8)
	await tap(KEY_J)                # roll-attack cancel
	await frames(20)
	key(KEY_W, false)
	await frames(24)
	finish()


# --- full-motion review duels (combat-motion worker) -----------------------------------------

var _rcam: Camera3D
var _rcam_side := 1.0


## Wait n frames: the player's own camera sits behind the player looking at `target` (so W walks at the foe), while a
## separate review camera films a side-on two-shot of both bodies (smoothed). The player cannot die in a review movie.
func _hold(target: Node3D, n: int, _off := 0.0) -> void:
	if _rcam == null:
		_rcam = Camera3D.new()
		_rcam.fov = 50.0
		main.world.add_child(_rcam)
	for i in n:
		player.health = maxi(player.health, int(player.max_health * 0.6))
		player.stamina = maxf(player.stamina, 40.0)
		if is_instance_valid(target):
			player.set_camera(yaw_to(target.global_position), -0.2)
			var a := player.global_position
			var b := target.global_position
			var mid := (a + b) * 0.5
			var line := b - a
			line.y = 0.0
			var side := Vector3(-line.z, 0, line.x).normalized() * _rcam_side
			var wide := _off > 1.0          # group fights: higher and further back so circling fighters do not block the lens
			var want := mid + side * maxf(7.5 if wide else 4.2, line.length() * 1.3) - line.normalized() * (2.5 if wide else 0.0) + Vector3.UP * (3.2 if wide else 2.0)     # above roadside grass
			_rcam.global_position = want if not _rcam.current else _rcam.global_position.lerp(want, 0.08)
			_rcam.current = true
			_rcam.look_at(mid + Vector3.UP * 0.9)
		await get_tree().process_frame


func _attack_dir(target: Node3D, dir_key: Key, gap: int) -> void:
	if dir_key != KEY_NONE:
		key(dir_key, true)
	await frames(2)
	await tap(KEY_J)
	if dir_key != KEY_NONE:
		key(dir_key, false)
	await _hold(target, gap)


## Player vs one bandit: lock on, walk in, light chain (the swings travel into the bandit), guard the reply,
## directional cuts, heavy, then let the bandit press.
func _fm01_duel() -> void:
	await teleport(_flat, 0.0, 20)
	player.combat_style = _style
	var b := _spawn_bandit(_flat + _fwd() * 6.0)
	_refill()
	await frames(10)
	begin("fm01_duel_" + _style)
	await _hold(b, 20)
	key(KEY_W, true)
	await _hold(b, 30)                     # approach
	key(KEY_W, false)
	log_line("stance=%s sheathed=%s" % [player._animator.stance(), str(player._rig.get("sheathed") if player._rig else "?")])
	for i in 4:                            # light chain from ~3 m: each step closes in
		await tap(KEY_J)
		await _hold(b, 16)
	await _hold(b, 20)
	key(KEY_L, true)                       # guard the reply
	await _hold(b, 45)
	key(KEY_L, false)
	for i in 6:                            # parry attempts: fresh guard presses land some blows in the parry window
		key(KEY_L, true)
		await _hold(b, 7)
		key(KEY_L, false)
		await _hold(b, 9)
	await _attack_dir(b, KEY_A, 18)        # directional cuts
	await _attack_dir(b, KEY_D, 18)
	await _attack_dir(b, KEY_S, 24)
	key(KEY_S, true)                       # back off, then lunge back in
	await _hold(b, 25)
	key(KEY_S, false)
	key(KEY_J, true)                       # heavy (hold)
	await _hold(b, 18)
	key(KEY_J, false)
	await _hold(b, 40)
	if player.health < player.max_health * 0.4:
		player.health = player.max_health
	await _hold(b, 60)                     # bandit presses
	finish()
	await _clear_enemies()


## Player vs three bandits: spacing, turning to the next foe, swings travelling between them.
func _fm02_three() -> void:
	await teleport(_flat, 0.0, 20)
	player.combat_style = _style
	var f := _fwd()
	var side := Vector2(f.y, -f.x)
	var bs: Array = [_spawn_bandit(_flat + f * 5.0), _spawn_bandit(_flat + f * 4.0 + side * 3.5), _spawn_bandit(_flat + f * 4.0 - side * 3.5)]
	_refill()
	await frames(10)
	begin("fm02_three_" + _style)
	await _hold(bs[0], 20, 1.6)
	for round in 3:
		for i in 3:
			await tap(KEY_J)
			await _hold(bs[0], 15, 1.6)
		key(KEY_L, true)
		await _hold(bs[0], 30, 1.6)
		key(KEY_L, false)
		await _hold(bs[0], 10, 1.6)
		player.health = maxi(player.health, player.max_health / 2)
	finish()
	await _clear_enemies()
