extends RefCounted
## Benchmark slice, player lane (docs/plans/BENCHMARK_SLICE.md items 2-3): ONE fixed movement route in Ashford recorded the same way
## before and after every change, judged by eye. Bot stage `slice_move` (playtest_bot.gd). Record with Movie Maker:
##   PLAYTEST_MOVIE=1 PLAYTEST_MOVIE_FPS=30 PLAYTEST_STAGES=slice_move godot --path kingdom scenes/main.tscn --resolution 1280x720
##     --fixed-fps 30 --write-movie out.avi -- --quality=low --adult --qa=res://tools_qa/playtest_bot/playtest_bot.gd
## Route (game camera, HUD hidden, 11:00): idle 2 s -> walk start -> walk 8 m -> run 12 m -> 90 deg turn -> run 10 m -> stop -> idle 1.5 s
## -> 180 deg turn in place -> sprint 15 m -> stop -> the hayloft ladder up, top-out, down. Every 0.5 s the clips the animator is
## actually blending are logged (SLICECLIP lines: gait blend position, rate, stance, full/upper one-shots).
const Slice := preload("res://scripts/world/town_kit/slice_dressing.gd")

var b
var player: Node3D


func run(bot: Node) -> void:
	b = bot
	player = b.get("player")
	WorldSim.time_of_day = 11.0
	var hud: Variant = b.get("hud")
	if hud is CanvasLayer:
		(hud as CanvasLayer).visible = false
	var town: Dictionary = Slice.settlement("Ashford")
	await b.teleport(Vector2(town["pos"]) + Vector2(4, 4), 0.0, 2.0)   # streams the town's colliders in before the clear-ground search
	var start := _clear_start(Vector2(town["pos"]))
	await b.teleport(start, 0.0, 1.5)
	var fwd := Vector2(0, 1)
	b.L("SLICEFRAME %d" % Engine.get_frames_drawn())   # movie frame of the route start: the recorder cuts the loading screen here
	_log_loop()
	if OS.get_environment("SLICE_CAM") == "side":
		_side_cam_loop()
	await b.wait(2.0)                                     # idle
	await _go(start + fwd * 8.0, false, 0.0)              # walk start + walk
	await _go(start + fwd * 20.0, true, 0.0)              # run
	var side := Vector2(1, 0)
	await _go(start + fwd * 20.0 + side * 10.0, true, 0.0)   # 90 deg turn + run
	b.release_all()
	await b.wait(1.5)                                     # stop + idle
	await _go(start + fwd * 20.0 + side * 9.0, false, 0.0)   # 180 turn (short step back)
	b.release_all()
	await b.wait(0.8)
	await _go(start + fwd * 20.0 - side * 6.0, true, 0.0)    # sprint
	b.release_all()
	await b.wait(1.5)
	var lad := b.get_tree().root.find_child("HayloftLadder", true, false) as Node3D
	if lad != null:
		var bottom: Vector3 = (lad.get("bottom") as Node3D).global_position
		var top: Vector3 = (lad.get("top") as Node3D).global_position
		var st := Vector2(bottom.x, bottom.z) + Vector2(0.0, 2.5)
		await b.teleport(st, b.yaw_to(st, Vector2(bottom.x, bottom.z)), 1.0)
		await _go(Vector2(bottom.x, bottom.z) + Vector2(0.0, 0.9), false, 0.0)
		b.release_all()
		lad.call("climb", player, true)
		await b.wait_until(func() -> bool: return player.global_position.y > top.y - 0.4, 12.0)
		await b.wait(1.5)
		lad.call("climb", player, false)
		await b.wait_until(func() -> bool: return player.global_position.y < bottom.y + 0.4, 12.0)
		await b.wait(1.5)
	_logging = false
	b.check("slice_move route finished", true)


func _go(target: Vector2, run_: bool, _yaw: float) -> void:
	var d := target - Vector2(player.global_position.x, player.global_position.z)
	if d.length() > 0.5:
		_side_dir = Vector3(-d.y, 0.0, d.x).normalized()      # left of the leg: the camera sees the body side-on
	await b.walk_to(target, 1.0, 20.0, run_, 4.0)


var _logging := true


func _log_loop() -> void:
	while _logging and is_instance_valid(player):
		var an: Object = player.get("_animator")
		if an != null:
			var tr: AnimationTree = an.get("tree")
			var pos := float(tr.get("parameters/gait/blend_position"))
			var pts: Array = an.get("_pt_speed")
			var names := []
			var gait: AnimationNodeBlendSpace1D = (tr.tree_root as AnimationNodeBlendTree).get_node("gait")
			for i in gait.get_blend_point_count():
				names.append((gait.get_blend_point_node(i) as AnimationNodeAnimation).animation)
			b.L("SLICECLIP t=%.1f speed=%.2f gait_pos=%.2f rate=%.2f loco=%.2f stance=%s pts=%s %s" % [b.now(),
					Vector2((player as CharacterBody3D).velocity.x, (player as CharacterBody3D).velocity.z).length(), pos,
					float(tr.get("parameters/gait_rate/scale")), float(tr.get("parameters/loco/blend_amount")), str(an.call("stance")),
					str(pts), str(names)])
		if int(b.now() * 2.0) % 4 == 0:
			_near_meshes()
		await b.wait(0.5)


## NEARMESH lines: every visible mesh whose bounds come within 1.5 m of the player's hips (occluder hunt: a prop riding along).
func _near_meshes() -> void:
	var pp := player.global_position + Vector3(0, 0.9, 0)
	for n in b.get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var bb := mi.global_transform * mi.get_aabb()
		if bb.size.length() > 40.0 or bb.size.length() < 0.4:
			continue
		var d := Vector3(clampf(pp.x, bb.position.x, bb.end.x), clampf(pp.y, bb.position.y, bb.end.y), clampf(pp.z, bb.position.z, bb.end.z)).distance_to(pp)
		if d < 1.5:
			b.L("NEARMESH t=%.1f d=%.2f size=%s centre_off=%s player_child=%s path=%s" % [b.now(), d, bb.size.snapped(Vector3.ONE * 0.01),
					(bb.get_center() - player.global_position).snapped(Vector3.ONE * 0.01), player.is_ancestor_of(mi), str(mi.get_path()).right(110)])


## Route start on open ground near the town: the whole route footprint (x -6..+10, z 0..20 m from the start, plus a 2 m margin) must be
## free of static props, walls and NPC bodies at knee-to-head height, so the bot never runs into a hay bale or a rune stone.
func _clear_start(centre: Vector2) -> Vector2:
	var space := (player as Node3D).get_world_3d().direct_space_state
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.4, 24.0)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.exclude = [(player as CollisionObject3D).get_rid()]
	for r: float in [18.0, 26.0, 34.0, 44.0, 56.0, 70.0]:
		for k in 12:
			var a := TAU * float(k) / 12.0
			var st := centre + Vector2(cos(a), sin(a)) * r
			var c := st + Vector2(2.0, 10.0)
			var hs: Array = [WorldGen.height(st.x, st.y), WorldGen.height(c.x, c.y), WorldGen.height(st.x + 10.0, st.y + 20.0), WorldGen.height(st.x - 6.0, st.y + 20.0)]
			if hs.max() - hs.min() > 1.2:
				continue                                  # too steep: the box would hit the terrain itself
			q.transform = Transform3D(Basis.IDENTITY, Vector3(c.x, float(hs.max()) + 1.0, c.y))
			var hits := space.intersect_shape(q, 8)
			var blocked := false
			for h: Dictionary in hits:
				var col: Object = h.get("collider")
				if col != null and not String(col.get_class()).contains("Terrain") and not String((col as Node).name).contains("Terrain"):
					blocked = true
					break
			if not blocked:
				b.L("SLICEROUTE start (%.1f, %.1f) r=%.0f a=%.0f deg" % [st.x, st.y, r, rad_to_deg(a)])
				return st
	b.L("SLICEROUTE no clear ground found; falling back to the town square")
	return centre + Vector2(4, 4)


## SLICE_CAM=side: a review camera 4.5 m to the side of the current leg at hip height, so starts, stops and turns in place show
## the feet (stepping around vs spinning on the spot). It follows the player smoothly and is made current every frame.
var _side_dir := Vector3(1, 0, 0)
var _cam: Camera3D


func _side_cam_loop() -> void:
	_cam = Camera3D.new()
	_cam.fov = 45.0
	player.get_parent().add_child(_cam)          # the game renders in a SubViewport: the camera must live in the player's world
	var at := player.global_position
	while _logging and is_instance_valid(player):
		await RenderingServer.frame_pre_draw      # after every node's _process: the player camera cannot take the view back
		at = at.lerp(player.global_position, 0.12)
		var want := at + _side_dir * 4.5 + Vector3(0, 1.0, 0)
		_cam.global_position = _cam.global_position.lerp(want, 0.08) if _cam.global_position.distance_to(want) < 6.0 else want
		_cam.look_at(at + Vector3(0, 0.85, 0))
		_cam.make_current()
	_cam.queue_free()
