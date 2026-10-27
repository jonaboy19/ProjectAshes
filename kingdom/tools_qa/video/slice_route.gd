extends RefCounted
## Benchmark slice, video QA lane (docs/plans/BENCHMARK_SLICE.md): the SAME route recorded after every push, judged by eye.
## Playtest-bot stage `slice_route`. Record with tools/qa/video/record_slice.sh (Movie Maker, 1280x720, 30 fps, 11:00, HUD
## hidden, game camera). Route (the slice places only):
##   1 Ashford market square: stand and look over the square crowd (idle / walk / conversation NPCs)       0-10 s
##   2 walk across the square into the side street, slow, camera on the street life                        10-26 s
##   3 a conversation group up close (the nearest `conversation` smart spot in the slice town)              26-34 s
##   4 the scenario A house: walk to its door and look in                                                   34-42 s
##   5 countryside: Ashford edge -> field wall / fence -> towards the Kingsreach road bandit camp           42-66 s
## Prints a SLICECFG block first (what the owner actually gets: renderer, quality tier + effective settings, upscaler,
## terrain backend, hero rig, the clips the player animator resolves per state) and SLICESEG lines at segment starts.
const Slice := preload("res://scripts/world/town_kit/slice_dressing.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const CarryErrandScript := preload("res://scripts/living_world/carry_errand.gd")

var b
var player: Node3D


func run(bot: Node) -> void:
	b = bot
	player = b.get("player")
	WorldSim.time_of_day = 11.0
	var hud: Variant = b.get("hud")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	_config_dump()
	b.get_tree().process_frame.connect(_clean_ui)       # gate frames: no HUD, tips, quest popups or subtitles
	if OS.has_environment("SLICE_TPOSE"):
		_tpose_watch()
	if OS.has_environment("SLICE_FOOTLOG"):            # NPC foot-contact hook check (audio lane)
		var n := [0]
		preload("res://scripts/living_world/npc_foot_events.gd").listen(func(body: Node3D, foot: StringName, surf: String, pos: Vector3, sp: float) -> void:
			n[0] += 1
			if n[0] % 10 == 1:
				b.L("FOOT #%d %s %s %s %.2f m/s at %s" % [n[0], body.name, foot, surf, sp, pos]))
	if OS.get_environment("SLICE_LEANS") != "":
		await _lean_check(int(OS.get_environment("SLICE_LEANS")))
		return
	if OS.get_environment("SLICE_CLIPS") != "":
		await _clip_street(OS.get_environment("SLICE_CLIPS"))
		return
	var town: Dictionary = Slice.settlement("Ashford")
	var c: Vector2 = town["pos"]
	var gates: Array = town["plan"]["gates"]
	var g := Vector2(cos(float(gates[0])), sin(float(gates[0]))) if not gates.is_empty() else Vector2(1, 0)
	var side := g.orthogonal()
	var pr := float(town["plan"]["plaza_r"])
	# 1 market square
	_seg("square")
	var a := c + g * (pr + 3.0)
	await b.teleport(a, b.yaw_to(a, c), 2.0)
	b.L("SLICEFRAME %d" % Engine.get_frames_drawn())   # movie frame of the route start: the recorder cuts the loading screen here
	await b.wait(10.0)
	# 2 across the square into the side street (walk)
	_seg("side_street")
	await b.walk_to(c - g * 2.0, 1.0, 20.0, false, 4.0)
	await b.walk_to(c + side * (pr + 14.0), 1.0, 20.0, false, 4.0)
	b.release_all()
	# 3 conversation group
	_seg("conversation")
	var conv := _nearest_spot(["conversation"], c)
	if conv != Vector3.INF:
		var stand := Vector2(conv.x, conv.z) + g * 4.0
		await b.teleport(stand, b.yaw_to(stand, Vector2(conv.x, conv.z)), 1.0)
	await b.wait(8.0)
	# 4 the scenario A house door
	_seg("house")
	var bid := String(Slice.data().get("scenario_a", {}).get("house_bid", ""))
	var door := _building_door(town, bid)
	if door != Vector2.INF:
		var st := door + g * 6.0
		await b.teleport(st, b.yaw_to(st, door), 1.0)
		await b.walk_to(door + g * 1.2, 1.0, 12.0, false, 4.0)
		b.release_all()
	await b.wait(3.0)
	# 5 countryside to the road camp
	_seg("countryside")
	var edge := c + g * (float(town["radius"]) + 8.0)
	var camp := _camp_pos()
	await b.teleport(edge, b.yaw_to(edge, camp if camp != Vector2.INF else edge + g), 1.5)
	var to := camp if camp != Vector2.INF else edge + g * 60.0
	var d := edge.distance_to(to)
	await b.walk_to(edge.lerp(to, minf(1.0, 45.0 / maxf(d, 1.0))), 2.0, 26.0, true, 6.0)
	b.release_all()
	await b.wait(2.0)
	_seg("end")
	b.check("slice_route finished", true)


func _seg(name: String) -> void:
	b.L("SLICESEG t=%.1f %s" % [b.now(), name])


func _nearest_spot(types: Array, near: Vector2) -> Vector3:
	var so: SmartObjects = NpcWorld.smart
	var best := Vector3.INF
	if so == null:
		return best
	var bd := INF
	for sp: Dictionary in so.spots:
		if types.has(String(sp["type"])):
			var o: Vector3 = (sp["xform"] as Transform3D).origin
			var dd := Vector2(o.x, o.z).distance_to(near)
			if dd < bd:
				bd = dd
				best = o
	return best


func _building_door(town: Dictionary, bid: String) -> Vector2:
	for lot: Dictionary in (town["plan"].get("lots", []) as Array):
		if String(lot.get("id", lot.get("bid", ""))) == bid and lot.has("pos"):
			return lot["pos"]
	return Vector2.INF


func _camp_pos() -> Vector2:
	var root: Node = b.get_tree().root
	var camp := root.find_child("Kingsreach Road Camp", true, false) as Node3D
	if camp == null:
		for n in root.find_children("*Camp*", "Node3D", true, false):
			camp = n as Node3D
			break
	return Vector2(camp.global_position.x, camp.global_position.z) if camp != null else Vector2.INF


## What the owner actually gets on this run (printed + the recorder writes it next to the MP4).
func _config_dump() -> void:
	var L := func(k: String, v: Variant) -> void: b.L("SLICECFG %s=%s" % [k, str(v)])
	L.call("renderer", RenderingServer.get_current_rendering_method())
	L.call("adapter", RenderingServer.get_video_adapter_name())
	L.call("quality_tier", str(Quality.tier))
	for k in ["sdfgi", "ssao", "ssil", "ssr", "vol_fog", "fog_mul", "shadow", "scale", "scaling", "taa", "fxaa", "msaa",
			"npc_full", "npc_sprites", "pop_full_range", "pop_sprite_range", "vat_range"]:
		L.call("q." + k, Quality.value(k))
	var vp: Viewport = b.get_viewport()
	var mainvp: Variant = b.get("main")
	if mainvp != null and mainvp.get("viewport") != null:
		vp = (mainvp.get("viewport") as SubViewport)
	L.call("vp.scaling_3d_mode", vp.scaling_3d_mode)
	L.call("vp.scaling_3d_scale", vp.scaling_3d_scale)
	L.call("vp.use_taa", vp.use_taa)
	var env: Environment = vp.world_3d.environment if vp.world_3d and vp.world_3d.environment else null
	if env == null:
		var we: Array = b.get_tree().root.find_children("*", "WorldEnvironment", true, false)
		env = (we[0] as WorldEnvironment).environment if not we.is_empty() else null
	if env:
		L.call("env.sdfgi", env.sdfgi_enabled)
		L.call("env.ssao", env.ssao_enabled)
		L.call("env.ssr", env.ssr_enabled)
		L.call("env.fog", env.fog_enabled)
		L.call("env.vol_fog", env.volumetric_fog_enabled)
		L.call("env.glow", env.glow_enabled)
	L.call("terrain3d", ClassDB.class_exists("Terrain3D") and b.get_tree().root.find_children("*", "Terrain3D", true, false).size() > 0)
	L.call("terrain_args", " ".join(OS.get_cmdline_user_args()))
	if player:
		var mdl: Node = player.get("_model")
		L.call("hero_model", (mdl.get_meta("mh_look", mdl.name) if mdl else "?"))
		var an: Object = player.get("_animator")
		if an != null:
			var tr: AnimationTree = an.get("tree")
			var gait: AnimationNodeBlendSpace1D = ((tr.tree_root as AnimationNodeBlendTree).get_node("gait") as AnimationNodeBlendSpace1D) if tr else null
			if gait:
				var names := []
				for i in gait.get_blend_point_count():
					names.append((gait.get_blend_point_node(i) as AnimationNodeAnimation).animation)
				L.call("anim.gait_points", names)
			for st in ["Idle", "Walk", "Jog_Fwd", "Sprint", "Roll", "Death01", "Sword_Idle"]:
				L.call("anim.resolve." + st, an.call("_clip", st) if an.has_method("_clip") else "?")


## Clip gate in the real street (AAA gate: gameplay distance, real Ashford ground and light): SLICE_CLIPS="a,b,c;d,e,f" -
## one page per ';' (12 s each). The hero stands at the square edge facing the centre (model hidden, game camera); villager
## bodies stand 6-9 m ahead on the real ground (raycast), facing the camera, with their sidecar props, label above.
func _clip_street(spec: String) -> void:
	var town: Dictionary = Slice.settlement("Ashford")
	var c: Vector2 = town["pos"]
	var gates: Array = town["plan"]["gates"]
	var g := Vector2(cos(float(gates[0])), sin(float(gates[0]))) if not gates.is_empty() else Vector2(1, 0)
	var pr := float(town["plan"]["plaza_r"])
	var a := c + g * (pr + 3.0)
	await b.teleport(a, b.yaw_to(a, c), 2.0)
	b.L("SLICEFRAME %d" % Engine.get_frames_drawn())
	var mdl: Node = player.get("_model") if player else null
	if mdl is Node3D:
		(mdl as Node3D).visible = false
	var fwd := (c - a).normalized()
	var side := fwd.orthogonal()
	var page_i := 0
	for page: String in spec.split(";", false):
		_seg("clips_%d %s" % [page_i, page])
		var made: Array[Node3D] = []
		var names := page.split(",", false)
		for i in names.size():
			# item syntax: <clip>[+<upper>][@<prop>:<hand>][>]  (+: runtime upper-body layer like the villager's carry,
			# @: a LifeProps item in that hand, >: walk 7 m across the shot at 1.2 m/s instead of standing)
			var item := String(names[i]).strip_edges()
			var drop := item.ends_with("!")     # !: drop the prop after 4 s (carry errand flee drop)
			item = item.trim_suffix("!")
			var walk := item.ends_with(">")
			item = item.trim_suffix(">")
			var prop_id := ""
			var prop_hand := ""
			if item.contains("@"):
				var pp2 := item.get_slice("@", 1)
				prop_id = pp2.get_slice(":", 0)
				prop_hand = pp2.get_slice(":", 1) if pp2.contains(":") else ""
				item = item.get_slice("@", 0)
			var clip := item
			# open cobbles in the foreground, left and right of the hero (the plaza crowd stands further in)
			var slots := [Vector2(-3.4, 4.0), Vector2(-1.7, 4.6), Vector2(1.7, 4.6), Vector2(3.4, 4.0), Vector2(-2.6, 6.4), Vector2(2.6, 6.4)]
			var sl: Vector2 = slots[i % slots.size()]
			var p2 := a + fwd * sl.y + side * sl.x
			var m := Assets.mh_character("villager_man_a", 1.7)
			player.get_parent().add_child(m)       # the game world lives in a SubViewport: spawn beside the hero
			m.global_position = Vector3(p2.x, _ground_y(p2), p2.y)
			m.rotation.y = atan2(a.x - p2.x, a.y - p2.y)
			var ap := Assets.animation_player(m)
			LifeLibrary.install(ap)
			var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
			if clip.contains("+"):
				clip = LifeLibrary.composite(ap, clip.get_slice("+", 0), clip.get_slice("+", 1))
			if prop_id != "":
				var att := LifeProps.attach(sk, prop_id, prop_hand)
				if drop and att != null:
					var world := player.get_parent()
					b.get_tree().create_timer(4.0).timeout.connect(func() -> void:
						if is_instance_valid(att):
							CarryErrandScript.drop_to_ground(att, world))
			for pp: Dictionary in (LifeLibrary.info(clip).get("props", []) as Array):
				LifeProps.attach(sk, String(pp.get("id", "")), String(pp.get("hand", "")))
			if ap.has_animation(clip):
				ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				ap.play(clip)
				if walk:
					var lo := item.get_slice("+", 0)
					var cs := 0.98 if lo == "Walking_A" else float(LifeLibrary.info(lo).get("speed_mps", 1.25))     # villager WALK_CLIP_SPEED
					ap.speed_scale = 1.2 / maxf(cs, 0.3)
					var from := Vector3(p2.x, m.global_position.y, p2.y) - Vector3(side.x, 0, side.y) * 3.5
					var to := from + Vector3(side.x, 0, side.y) * 7.0
					m.global_position = from
					m.rotation.y = atan2(side.x, side.y)
					var tw := m.create_tween().set_loops()
					tw.tween_property(m, "global_position", to, 7.0 / 1.2)
					tw.tween_callback(func() -> void: m.global_position = from)
			else:
				b.L("CLIPSTREET missing %s" % clip)
			var lb := Label3D.new()
			lb.text = clip.replace("Life_", "")
			lb.font_size = 28
			lb.pixel_size = 0.004
			lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lb.position = Vector3(0, 2.15, 0)
			m.add_child(lb)
			made.append(m)
			b.L("CLIPSTREET %s at %s anim=%s cam=%s" % [clip, m.global_position, ap.current_animation, b.get_viewport().get_camera_3d().global_position if b.get_viewport().get_camera_3d() else Vector3.INF])
		for k in 48:                     # re-hide the hero every step (the player script shows its model again)
			if mdl is Node3D:
				(mdl as Node3D).visible = false
			await b.wait(0.25)
		for m in made:
			m.queue_free()
		page_i += 1
	_seg("end")
	b.check("clip_street finished", true)


func _ground_y(p: Vector2) -> float:
	var space := (player as Node3D).get_world_3d().direct_space_state if player else null
	if space:
		var y0 := (player as Node3D).global_position.y      # from just above the hero's ground: never onto roofs / stalls / bunting
		var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, y0 + 2.0, p.y), Vector3(p.x, y0 - 6.0, p.y))
		q.exclude = [(player as CollisionObject3D).get_rid()] if player is CollisionObject3D else []
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return float((hit["position"] as Vector3).y)
	return WorldGen.height(p.x, p.y)


## Every UI layer off except the one that shows the game view (the world renders into a SubViewport shown by a container).
func _clean_ui() -> void:
	for cl: Node in b.get_tree().root.find_children("*", "CanvasLayer", true, false):
		if cl is CanvasLayer and (cl as CanvasLayer).visible and cl.find_children("*", "SubViewportContainer", true, false).is_empty():
			(cl as CanvasLayer).visible = false


## Wall-lean gate on the real house fronts: the nearest `n` wall_lean_* spots to the Ashford square; per spot the hero stands
## 4.5 m out, three-quarter on, and a villager body plays the spot's lean clip at the spot's exact transform.
func _lean_check(n: int) -> void:
	var town: Dictionary = Slice.settlement("Ashford")
	var c: Vector2 = town["pos"]
	await b.teleport(c, 0.0, 2.0)
	b.L("SLICEFRAME %d" % Engine.get_frames_drawn())
	var so: SmartObjects = NpcWorld.smart
	var cands := []
	for i in so.spots.size():
		var sp: Dictionary = so.spots[i]
		if String(sp["type"]).begins_with("wall_lean"):
			var o: Vector3 = (sp["xform"] as Transform3D).origin
			cands.append([Vector2(o.x, o.z).distance_to(c), i])
	cands.sort()
	var mdl: Node = player.get("_model") if player else null
	for j in mini(n, cands.size()):
		var sid := int(cands[j][1])
		if not NpcWorld.fit_wall_lean(so, sid, (player as Node3D).get_world_3d().direct_space_state):
			b.L("LEANGAP spot %d: no wall found, skipped" % sid)
			continue
		var sp: Dictionary = so.spots[sid]
		var x: Transform3D = sp["xform"]
		var typ := String(sp["type"])
		var clip: String = (so.types[typ]["activity"]["loop"] as Array)[0]
		var away := Vector2(x.basis.z.x, x.basis.z.z) if typ == "wall_lean_back" else Vector2(x.basis.x.x, x.basis.x.z)
		var side := Vector2(-away.y, away.x)
		var o2 := Vector2(x.origin.x, x.origin.z)
		var st := o2 + away * 3.0 + side * 1.5
		# offset check: from the spot at shoulder height toward the wall, where is the real surface?
		var want := 0.17 if typ == "wall_lean_back" else 0.33
		var from := x.origin + Vector3(0, 1.2, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from - Vector3(away.x, 0, away.y) * 3.0)
		var hit := (player as Node3D).get_world_3d().direct_space_state.intersect_ray(q)
		var gap := from.distance_to(hit["position"]) if not hit.is_empty() else INF
		b.L("LEANGAP %s want %.2f m, wall at %.2f m (%s)" % [typ, want, gap, hit.get("collider", "none")])
		await b.teleport(st, b.yaw_to(st, o2), 1.5)
		var m := Assets.mh_character("villager_man_a", 1.7)
		player.get_parent().add_child(m)
		m.global_transform = x
		var ap := Assets.animation_player(m)
		LifeLibrary.install(ap)
		if ap.has_animation(clip):
			ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			ap.play(clip)
		var cam := Camera3D.new()          # side-on gate camera (the follow camera puts the hero in front of the spot)
		player.get_parent().add_child(cam)
		var wall_n := Vector3(away.x, 0, away.y)
		cam.global_position = x.origin + wall_n * 2.4 + Vector3(side.x, 0, side.y) * 1.3 + Vector3(0, 1.35, 0)
		cam.look_at(x.origin + Vector3(0, 1.0, 0))
		cam.fov = 50.0
		cam.make_current()
		_seg("lean_%d %s %s at %s" % [j, typ, clip, x.origin])
		for k in 24:
			if mdl is Node3D:
				(mdl as Node3D).visible = false
			await b.wait(0.25)
		m.queue_free()
		cam.queue_free()
	_seg("end")
	b.check("lean check finished", true)


## T-pose detector (QA): every second, every VISIBLE humanoid skeleton whose upper arms sit exactly at their rest pose
## (nothing animates them: no clip, an inactive tree, or clips missing from the rig) is reported once with its owner.
func _tpose_watch() -> void:
	var seen := {}
	while is_instance_valid(b):
		for skn: Node in b.get_tree().root.find_children("*", "Skeleton3D", true, false):
			var sk := skn as Skeleton3D
			if sk == null or not sk.is_visible_in_tree() or seen.has(sk.get_instance_id()):
				continue
			var ul := sk.find_bone("upperarm_l")
			var ur := sk.find_bone("upperarm_r")
			if ul < 0 or ur < 0:
				continue
			var rest_l := sk.get_bone_rest(ul).basis.get_rotation_quaternion()
			var rest_r := sk.get_bone_rest(ur).basis.get_rotation_quaternion()
			if sk.get_bone_pose_rotation(ul).angle_to(rest_l) > 0.02 or sk.get_bone_pose_rotation(ur).angle_to(rest_r) > 0.02:
				continue
			var actor: Node = sk
			while actor != null and actor.get_script() == null:
				actor = actor.get_parent()
			var aps := (actor if actor else sk).find_children("*", "AnimationPlayer", true, false)
			var ap: AnimationPlayer = aps[0] if not aps.is_empty() else null
			var trees := (actor if actor else sk).find_children("*", "AnimationTree", true, false)
			seen[sk.get_instance_id()] = true
			b.L("TPOSE %s script=%s pos=%s ap_cur='%s' ap_playing=%s tree=%s look=%s" % [actor.name if actor else "?",
				(actor.get_script() as Script).resource_path if actor and actor.get_script() else "?", sk.global_position,
				ap.current_animation if ap else "-", ap.is_playing() if ap else false,
				("active" if (trees[0] as AnimationTree).active else "INACTIVE") if not trees.is_empty() else "none",
				sk.get_parent().name])
		await b.wait(1.0)
