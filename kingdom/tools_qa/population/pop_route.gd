extends "res://tools_qa/perf/town_route.gd"
## NPC spawn / LOD pop QA route: the perf town walk (Ashford plaza -> Kingsreach gate -> market) with FREE-LOOK sweeps
## (the camera swings +-150 deg around the walking direction, so residents enter and leave the view constantly) and
## screenshots every --shot_every seconds into --shots=<dir>. Run with --pop-log for the PopVisibilityLog counts.
##   godot --path kingdom --resolution 1280x720 -- --adult --qa=res://tools_qa/population/pop_route.gd --seconds=90 \
##         --pop-log --shots=C:/tmp/pop [--no-vis-gate]

var _shots := ""
var _shot_every := 8.0
var _shot_t := 0.0
var _shot_n := 0


func run(m: Node) -> void:
	super.run(m)
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
		elif a.begins_with("--shot_every="):
			_shot_every = float(a.substr(13))
	if _shots != "":
		DirAccess.make_dir_recursive_absolute(_shots)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if legs.is_empty() or main == null or main.player == null:
		return
	var from: Vector2 = legs[leg][0]
	var to: Vector2 = legs[leg][1]
	var d := to - from
	main.player.set_camera(atan2(-d.x, -d.y) + sin(t * 0.55) * 2.6, -0.12)


func _process(delta: float) -> void:
	super._process(delta)
	if _shots == "" or t < 8.0:
		return
	_shot_t += delta
	if _shot_t >= _shot_every:
		_shot_t = 0.0
		var img := get_viewport().get_texture().get_image()
		var lg: String = legs[leg][2] if legs.size() > 0 and (legs[leg] as Array).size() > 2 else str(leg)
		img.save_jpg("%s/pop_%02d_%s.jpg" % [_shots, _shot_n, lg], 0.85)
		_shot_n += 1
