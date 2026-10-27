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
	var env := vp.world_3d.environment if vp.world_3d and vp.world_3d.environment else null
	if env == null:
		var we := b.get_tree().root.find_children("*", "WorldEnvironment", true, false)
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
			var gait: AnimationNodeBlendSpace1D = (tr.tree_root as AnimationNodeBlendTree).get_node("gait") if tr else null
			if gait:
				var names := []
				for i in gait.get_blend_point_count():
					names.append((gait.get_blend_point_node(i) as AnimationNodeAnimation).animation)
				L.call("anim.gait_points", names)
			for st in ["Idle", "Walk", "Jog_Fwd", "Sprint", "Roll", "Death01", "Sword_Idle"]:
				L.call("anim.resolve." + st, an.call("_clip", st) if an.has_method("_clip") else "?")
