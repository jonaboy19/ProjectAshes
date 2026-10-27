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
	var start := Vector2(town["pos"]) + Vector2(4, 4)
	await b.teleport(start, 0.0, 1.5)
	var fwd := Vector2(0, 1)
	_log_loop()
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
		await b.wait(0.5)
