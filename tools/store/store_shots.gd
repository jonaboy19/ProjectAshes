extends Node
## Store screenshot driver for Rising Ashes (Google Play / App Store).
##
## Boots the REAL game (res://scenes/main.tscn instanced as a child, like the
## autoplay bot, so no game script changes), stages each shot through the game's
## own systems, and saves PNGs. Runs from outside the Godot project; see
## tools/store/make_screenshots.sh.
##
## Args (after --):  --shots=plaza,guild,...  --outdir=C:/...  --w=1920 --h=1080
##                   --ss=2 (supersampling for HUD-less shots)  --burst=4
## Also pass --quality=ultra --adult --skipintro (read by the game itself).
##
## Debug overlay: the fps/chunks line (HUD `_perf` label) is hidden at runtime.
## The raider-camp skull banner (Label3D "☠ N") is hidden too.

const MAIN := "res://scenes/main.tscn"

var main: Node
var player: Node3D
var hud: Node
var out_dir := ""
var W := 1920
var H := 1080
var SS := 2.0
var BURST := 1
var _cam: Camera3D
var _extra: Array[Node] = []


var _ov := {}


func _args() -> Dictionary:
	var out := _ov.duplicate()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var kv := arg.substr(2).split("=", true, 1)
			if not _ov.has(kv[0]):
				out[kv[0]] = kv[1]
		elif arg.begins_with("--"):
			out[arg.substr(2)] = true
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var a := _args()
	W = int(a.get("w", "1920"))
	H = int(a.get("h", "1080"))
	SS = float(a.get("ss", "2"))
	BURST = int(a.get("burst", "1"))
	out_dir = String(a.get("outdir", "C:/tmp/store_shots"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = Vector2i(W, H)
	get_window().position = Vector2i(0, 0)
	seed(int(a.get("seed", "7")))
	get_tree().create_timer(float(a.get("watchdog", "420")), true, false, true).timeout.connect(func() -> void: print("STORE: watchdog quit"); get_tree().quit(2))
	main = (load(MAIN) as PackedScene).instantiate()
	add_child(main)
	_run(String(a.get("shots", "plaza")).split(","))


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _run(shots: PackedStringArray) -> void:
	var t := Time.get_ticks_msec()
	while main.get("player") == null or not main.player.is_inside_tree():
		await frames(1)
		if Time.get_ticks_msec() - t > 180000:
			print("STORE: player never appeared"); get_tree().quit(1); return
	player = main.player
	hud = main.hud
	while true:
		var ld: Variant = hud.get("_loading")
		if not is_instance_valid(ld) or not ld.visible:
			break
		await frames(1)
	await wait(2.0)
	_fix_sky()
	print("STORE: booted in %.1fs, quality %s" % [(Time.get_ticks_msec() - t) / 1000.0, Quality.tier_name()])
	for tok in shots:
		# "name:key=val:key=val" overrides args for one shot; saved as name-<tag>
		var parts := tok.split(":")
		var s := parts[0]
		_ov = {}
		for i in range(1, parts.size()):
			var kv := parts[i].split("=", true, 1)
			_ov[kv[0]] = kv[1] if kv.size() > 1 else "1"
		await _reset()
		print("STORE: shot ", tok)
		var hud_on: bool = await call("_shot_" + s)
		await _capture(s + ("-" + String(_ov.get("tag", "")) if _ov.has("tag") else ""), hud_on)
	get_tree().quit()


## The imported sky panorama (kloofendal_43d .hdr with size_limit=2048) comes out all black,
## so the sky renders black and the depth fog paints it flat grey. If the imported texture is
## black, feed the sky the source .hdr decoded at runtime instead (presentation only).
func _fix_sky() -> void:
	if _args().has("nosky_fix"):
		return
	var env: Environment = main.get("env")
	if env == null or env.sky == null or not (env.sky.sky_material is PanoramaSkyMaterial):
		return
	var mat := env.sky.sky_material as PanoramaSkyMaterial
	if mat.panorama == null:
		return
	var im := mat.panorama.get_image()
	var peak := 0.0
	for i in 16:
		var c := im.get_pixel(int(im.get_width() * (i + 0.5) / 16.0), int(im.get_height() * 0.25))
		peak = maxf(peak, c.r + c.g + c.b)
	if peak > 0.01:
		print("STORE: sky panorama OK")
		return
	var src := mat.panorama.resource_path
	var raw := Image.load_from_file(ProjectSettings.globalize_path(src))
	if raw == null or raw.is_empty():
		print("STORE: sky fix failed to load ", src)
		return
	if raw.get_width() > 4096:
		raw.resize(4096, 2048, Image.INTERPOLATE_BILINEAR)
	mat.panorama = ImageTexture.create_from_image(raw)
	print("STORE: sky panorama was black; loaded %s at runtime (%dx%d)" % [src, raw.get_width(), raw.get_height()])


func _reset() -> void:
	for n in _extra:
		if is_instance_valid(n):
			n.queue_free()
	_extra.clear()
	var pop: Node = main.get("population")
	if pop:
		pop.set_process(true)
	if InteriorDoor.active != null:
		InteriorDoor.active.leave()
	if _cam and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null
	player.visible = true
	player.set("max_health", 9999)
	player.set("health", 9999)
	hud.visible = true
	Engine.time_scale = 1.0
	Quality.npc_full = int(_args().get("npc_full", "48"))
	player.call("set_view", 1)
	await frames(2)


func _clean_overlays() -> void:
	var perf: Label = hud.get("_perf")
	if perf:
		perf.visible = false
	# World-space name tags (station names, prices, squad flag, enemy levels) clutter store shots.
	for l in main.find_children("*", "Label3D", true, false):
		(l as Label3D).layers = 1 << 19
	if _cam and is_instance_valid(_cam):
		_cam.cull_mask = _cam.cull_mask & ~(1 << 19)
	# Ultra only: volumetric fog also fogs the sky (volumetric_fog_sky_affect defaults to 1),
	# which turns the clear HDRI sky flat grey. Phones never run volumetric fog; show the sky.
	var env: Environment = main.get("env")
	if env:
		env.volumetric_fog_sky_affect = float(_args().get("fogsky", "0.0"))
		env.fog_sky_affect = float(_args().get("fogsky2", "0.4"))
		# Generic per-shot overrides: env_<property>=<value> (e.g. env_fog_enabled=false).
		for k: String in _args():
			if k.begins_with("env_"):
				env.set(k.substr(4), str_to_var(String(_args()[k])))


## Flat villager sprites (PopulationLOD impostors) read as pixelated cut-outs within ~30 m,
## and a busy plaza exhausts the full-model budget long before that. For the capture, freeze
## the crowd LOD and drop the sprites near the camera (`sprite_hide=<m>`, 0 = keep all).
func _hide_near_sprites() -> void:
	var r := float(_args().get("sprite_hide", "32"))
	var pop: Node = main.get("population")
	var cam := get_viewport().get_camera_3d() if _cam == null else _cam
	if r <= 0.0 or pop == null or cam == null:
		return
	pop.set_process(false)
	var zero := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -1000, 0))
	var hidden := 0
	for mm: MultiMesh in (pop.get("_multimeshes") as Dictionary).values():
		for i in mm.visible_instance_count:
			if mm.get_instance_transform(i).origin.distance_to(cam.global_position) < r:
				mm.set_instance_transform(i, zero)
				hidden += 1
	if hidden:
		print("STORE: hid %d villager sprites within %.0f m" % [hidden, r])
	# `clear=<m>`: also hide full-model villagers who wander in front of a staged shot.
	var cr := float(_args().get("clear", "0"))
	if cr > 0.0:
		for v in pop.get_children():
			if v is Villager and (v as Node3D).global_position.distance_to(cam.global_position) < cr:
				(v as Node3D).visible = false


func _capture(sname: String, hud_on: bool) -> void:
	var burst := int(_args().get("burst", str(BURST)))
	for b in burst:
		_clean_overlays()
		_hide_near_sprites()
		var img: Image
		if hud_on:
			await frames(2)
			img = get_viewport().get_texture().get_image()
		else:
			hud.visible = false
			var vp: SubViewport = main.viewport
			var cont := vp.get_parent() as SubViewportContainer
			cont.stretch = false
			vp.size = Vector2i(int(W * SS), int(H * SS))
			await frames(6)
			img = vp.get_texture().get_image()
			cont.stretch = true
			img.resize(W, H, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGB8)
		var f := out_dir.path_join("%s_%dx%d_%d.png" % [sname, W, H, b])
		img.save_png(f)
		print("STORE: saved ", f)
		if b < burst - 1:
			await wait(float(_args().get("burst_gap", "0.25")))


# --- helpers ---------------------------------------------------------------------

func ground(p: Vector2) -> Vector3:
	return Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


func lot(asset: String) -> Dictionary:
	for l: Dictionary in WorldGen.settlements[0]["plan"]["lots"]:
		if String(l["asset"]).begins_with(asset):
			return l
	return {}


func free_cam(pos: Vector3, look: Vector3, fov := 55.0) -> Camera3D:
	_cam = Camera3D.new()
	main.world.add_child(_cam)
	_cam.global_position = pos
	_cam.look_at(look)
	_cam.fov = fov
	_cam.far = 1500.0
	var pc: Camera3D = player.get("camera")
	if pc and pc.environment:
		_cam.environment = pc.environment
	if pc and pc.attributes:
		_cam.attributes = pc.attributes
	_cam.current = true
	return _cam


func face_player(target: Vector3, pitch := -0.15) -> void:
	var d := target - player.global_position
	player.call("set_camera", atan2(-d.x, -d.z), pitch)


func npc(look: String, pos: Vector3, face: Vector3, anim := "Idle", h := 1.78) -> Node3D:
	var c := Assets.character(look, h)
	main.world.add_child(c)
	c.global_position = pos
	c.look_at(Vector3(face.x, pos.y, face.z), Vector3.UP, true)
	var ap := Assets.animation_player(c)
	if ap:
		var names := ap.get_animation_list()
		var pick := anim
		if not ap.has_animation(pick):
			for n in names:
				if anim.to_lower() in String(n).to_lower():
					pick = n
					break
		if ap.has_animation(pick):
			ap.play(pick)
			ap.seek(randf() * 2.0, true)
	_extra.append(c)
	return c


func hour(h: float) -> void:
	WorldSim.time_of_day = h


func teleport(p: Vector2) -> void:
	main.call("_teleport", p, 0.0)


# --- shots (return true to keep the HUD) -------------------------------------------

## Ashford's plaza: well, market stalls, villagers, warm afternoon light.
func _shot_plaza() -> bool:
	hour(float(_args().get("hour", "16.4")))
	var a := _args()
	var at := Vector2(float(a.get("px", "2.0")), float(a.get("pz", "12.0")))
	teleport(at + Vector2(0, -3))
	player.visible = false
	await wait(6.0)
	var cy := WorldGen.height(at.x, at.y)
	free_cam(Vector3(at.x, cy + float(a.get("cy", "3.2")), at.y), Vector3(float(a.get("lx", "0")), cy + 1.4, float(a.get("lz", "-6"))), float(a.get("fov", "58")))
	await wait(2.0)
	return false


## Guild hall: the Adventurers' Guild with its blue banners (3/4 street view).
func _shot_guild() -> bool:
	hour(float(_args().get("hour", "15.8")))
	var l := lot("adventurer_guild")
	var yaw: float = l["yaw"]
	var look: Vector2 = l["pos"]
	var dir := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(dir.y, -dir.x)
	var a := _args()
	teleport(look + dir * 9.0 + side * 1.5)
	await wait(5.0)
	var gy := WorldGen.height(look.x, look.y)
	var cp := look + dir * float(a.get("gd", "15.0")) + side * float(a.get("gs", "7.5"))
	free_cam(Vector3(cp.x, gy + float(a.get("gh", "3.4")), cp.y), Vector3(look.x, gy + float(a.get("gl", "4.2")), look.y), float(a.get("fov", "60")))
	# The player walks up to the door.
	player.global_position = ground(look + dir * 7.0 + side * 1.0)
	player.rotation.y = atan2(-dir.x, -dir.y)
	await wait(1.5)
	return false


## Inside the inn: fire, tables, the innkeeper behind the bar.
func _shot_inn() -> bool:
	hour(20.5)
	var l := lot("inn")
	var holder := Node3D.new()
	main.world.add_child(holder)
	_extra.append(holder)
	var door := InteriorDoor.new()
	door.interior_scene = "res://scenes/interiors/inn_interior.tscn"
	holder.add_child(door)
	var yaw: float = l["yaw"]
	door.global_position = ground(l["pos"] + Vector2(sin(yaw), cos(yaw)) * 3.6)
	door.rotation.y = yaw
	teleport(Vector2(door.global_position.x, door.global_position.z))
	await wait(1.0)
	var env: Environment = player.get("camera").environment
	door.enter(player)
	await frames(3)
	var room: Node3D = door.interior
	# Populate the markers the room ships with (the game doesn't spawn them yet).
	for m in room.find_children("NPC_*", "Marker3D", true, false):
		var mk := m as Marker3D
		var look: String = mk.get_meta("look", "Rogue_Hooded")
		var fwd := -mk.global_transform.basis.z
		npc(look, mk.global_position, mk.global_position + fwd, String(mk.get_meta("anim", "Idle")), float(mk.get_meta("height", 1.75)))
	# Two more patrons by the tables.
	var r := room.global_transform
	npc("Mage", r * Vector3(0.9, 0, -2.6), r * Vector3(-1.3, 0, -2.2), "Idle")
	npc("Barbarian", r * Vector3(-2.0, 0, -0.9), r * Vector3(-2.8, 0, -4.2), "Idle")
	var a := _args()
	# The room's own preview camera framing.
	var pc := Transform3D(Basis(Vector3(0.64681, 1.496e-09, 0.76265), Vector3(0.10215, 0.99099, -0.086631), Vector3(-0.75578, 0.13394, 0.64098)), Vector3(-5.3, 2.4, 4.3))
	var ct := r * pc
	var cam := free_cam(ct.origin, ct.origin - ct.basis.z, 61.6)
	cam.global_transform = ct
	if a.has("icx"):
		cam.global_position = r * Vector3(float(a["icx"]), float(a.get("icy", "1.7")), float(a["icz"]))
		cam.look_at(r * Vector3(float(a.get("ilx", "0")), float(a.get("ily", "1.2")), float(a.get("ilz", "-3"))))
		cam.fov = float(a.get("fov", "62"))
	cam.environment = player.get("camera").environment
	player.visible = a.has("showplayer")
	await wait(2.5)
	return false


## Combat at the Mossfang goblin warren, mid-swing.
func _shot_goblins() -> bool:
	hour(float(_args().get("hour", "17.0")))
	var w: Dictionary = Life.lore.place("mossfang_warren")
	var wc: Vector2 = w["pos"]
	teleport(wc + Vector2(float(_args().get("gox", "-14")), float(_args().get("goz", "8"))))
	main.camps.spawn_all_near(player.global_position)
	await wait(1.0)
	var monsters: Array = []
	for m in main.camps.get_children():
		if m is CampMonster:
			monsters.append(m)
	monsters.sort_custom(func(x: Node3D, y: Node3D) -> bool:
		return x.global_position.distance_to(player.global_position) < y.global_position.distance_to(player.global_position))
	var fwd := (ground(wc) - player.global_position).normalized()
	for i in mini(3, monsters.size()):
		var m: Node3D = monsters[i]
		var sides: Array[float] = [0.0, 1.8, -1.9]
		var off: Vector3 = Vector3(fwd.x, 0, fwd.z) * (2.2 + i * 1.3) + Vector3(-fwd.z, 0, fwd.x) * sides[i]
		var p: Vector3 = player.global_position + off
		m.global_position = ground(Vector2(p.x, p.z))
	face_player(player.global_position + fwd * 5.0, -0.12)
	player.rotation.y = atan2(-fwd.x, -fwd.z)
	await wait(0.6)
	shoulder_cam(Vector3(fwd.x, 0, fwd.z).normalized())
	for i in 3:
		player.call("attack")
		await wait(0.35)
	player.call("attack")
	await wait(float(_args().get("swing_t", "0.12")))
	return true


## Wolves in the forest near a den, dusk.
func _shot_wolves() -> bool:
	hour(float(_args().get("hour", "17.5")))
	var den: Dictionary = Frontier.ecology.dens[0]
	var ws: Dictionary = Frontier.runestones.stones[0]
	var dir: Vector2 = (den["pos"] - ws["pos"]).normalized()
	var sp: Vector2 = den["pos"] - dir * float(_args().get("back", "30.0"))
	teleport(sp)
	main.frontier.focus = Vector3(den["pos"].x, 0, den["pos"].y)
	main.frontier.set("_timer", 0.0)
	main.frontier._process(0.0)
	await wait(0.5)
	var side := Vector2(-dir.y, dir.x)
	var k := 0
	for wlf in get_tree().get_nodes_in_group("team1"):
		if wlf is Wolf and k < 4:
			var sides: Array[float] = [0.0, 2.2, -2.0, 3.5]
			var q: Vector2 = sp + dir * (3.0 + k * 1.5) + side * sides[k]
			wlf.global_position = ground(q)
			k += 1
	face_player(ground(sp + dir * 5.0), -0.1)
	await wait(0.4)
	shoulder_cam(Vector3(dir.x, 0, dir.y))
	for i in 3:
		player.call("attack")
		await wait(0.35)
	player.call("attack")
	await wait(float(_args().get("swing_t", "0.12")))
	return true


## Night: the plaza under lamp light.
func _shot_night() -> bool:
	hour(float(_args().get("hour", "21.8")))
	var a := _args()
	var at := Vector2(float(a.get("px", "-3.0")), float(a.get("pz", "10.0")))
	teleport(at + Vector2(0, -2))
	player.visible = false
	await wait(6.0)
	var cy := WorldGen.height(at.x, at.y)
	free_cam(Vector3(at.x, cy + float(a.get("cy", "2.4")), at.y), Vector3(float(a.get("lx", "2")), cy + 2.0, float(a.get("lz", "-6"))), float(a.get("fov", "60")))
	await wait(2.0)
	return false


## A runestone at the edge of its protection, with the HUD's danger readout.
func _shot_runestone() -> bool:
	hour(float(_args().get("hour", "18.6")))
	var a := _args()
	var idx := int(a.get("stone", "1"))
	var st: Dictionary = Frontier.runestones.stones[idx]
	var sp: Vector2 = st["pos"]
	var ang := float(a.get("ang", "0.8"))
	var dist := float(a.get("dist", "6.0"))
	var p := sp + Vector2(cos(ang), sin(ang)) * dist
	teleport(p)
	await wait(4.0)
	var to := (ground(sp) - player.global_position)
	to.y = 0
	to = to.normalized()
	player.rotation.y = atan2(-to.x, -to.z)
	face_player(ground(sp) + Vector3(0, 1.5, 0), float(a.get("pitch", "-0.08")))
	shoulder_cam(to)
	await wait(1.5)
	return true


## A knight of the player's squad, close up.
func _shot_knight() -> bool:
	hour(float(_args().get("hour", "16.6")))
	var a := _args()
	var at := Vector2(float(a.get("px", "-6.0")), float(a.get("pz", "14.0")))
	teleport(at)
	Game.rank = 2
	main.call("_recruit", 4)
	await wait(1.0)
	var all_s: Array = main.army.soldiers
	var soldiers: Array = all_s.slice(maxi(0, all_s.size() - 4))
	var fwd := Vector3(0, 0, -1)
	for i in soldiers.size():
		var s: Node3D = soldiers[i]
		var q := at + Vector2([0.0, -1.6, 1.7, -3.2][i % 4], [0.0, -1.8, -2.1, -3.6][i % 4]) + Vector2(0, -3)
		s.global_position = ground(q)
	main.army.order = Squad.Order.HOLD
	await wait(2.5)
	var s0: Node3D = soldiers[0]
	var sy := s0.global_position
	player.visible = false
	# The leader (hidden) stands at the camera, so the squad looks toward the lens.
	player.global_position = ground(Vector2(sy.x, sy.z + 7.0))
	await wait(1.5)
	# Pick the soldier closest to the group centre and frame him from the front.
	var c := Vector3.ZERO
	for s in soldiers:
		c += (s as Node3D).global_position
	c /= soldiers.size()
	var best: Node3D = soldiers[0]
	for s in soldiers:
		if (s as Node3D).global_position.distance_to(c) < best.global_position.distance_to(c):
			best = s
	var f := Vector3(float(a.get("kfx", "0")), 0, float(a.get("kfz", "1"))).normalized()
	var rt := f.cross(Vector3.UP).normalized()
	var bp := best.global_position
	for s in soldiers:
		(s as Node3D).rotation.y = atan2(f.x, f.z) + PI + randf_range(-0.25, 0.25)
	best.rotation.y = atan2(f.x, f.z) + PI + float(a.get("kyaw", "0.35"))
	free_cam(bp + f * float(a.get("kd", "2.6")) + rt * float(a.get("ks", "0.7")) + Vector3(0, float(a.get("ky", "1.6")), 0), bp + rt * float(a.get("kls", "0.35")) + Vector3(0, float(a.get("kly", "1.4")), 0), float(a.get("fov", "38")))
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = float(a.get("dof", "6.0"))
	attrs.dof_blur_far_transition = 8.0
	attrs.dof_blur_amount = 0.06
	_cam.attributes = attrs
	await wait(1.0)
	return false


## High aerial over Ashford and its fields.
func _shot_aerial() -> bool:
	hour(float(_args().get("hour", "16.8")))
	var a := _args()
	teleport(Vector2(10, 10))
	player.visible = false
	main.terrain.view_radius = 6
	var gy := WorldGen.height(0, 0)
	free_cam(Vector3(float(a.get("ax", "95")), gy + float(a.get("ay", "62")), float(a.get("az", "105"))), Vector3(float(a.get("alx", "0")), gy, float(a.get("alz", "-5"))), float(a.get("fov", "55")))
	main.terrain.focus = Vector3(20, 0, 20)
	main.terrain.build_all_now()
	await wait(6.0)
	return false


## Over-the-shoulder camera behind the player, looking along `fwd` (keeps the HUD).
func shoulder_cam(fwd: Vector3) -> void:
	var a := _args()
	var right := fwd.cross(Vector3.UP).normalized()
	var p := player.global_position
	var cp := p - fwd * float(a.get("cb", "4.2")) + right * float(a.get("cs", "1.3")) + Vector3(0, float(a.get("ch", "2.3")), 0)
	free_cam(cp, p + fwd * float(a.get("cl", "4.0")) + Vector3(0, 1.1, 0), float(a.get("fov", "60")))
