class_name AshsightController
extends Node3D
## The whole Ashsight moment in one node: replay view (ghosts), world grade, soft camera
## pull-in, slow motion and the scrub bar. This is the only node the game needs to add.
##
##   var ash := AshsightController.new()
##   world.add_child(ash)
##   ash.setup(camera, world_environment.environment)        # once (the Environment is optional)
##   ash.warm()                                              # optional: build the ghost bodies early
##   ash.show_incident(mem, id)                              # the player kneels at a site
##   ash.stop()                                              # or the close button / replay end
##
## Signals: `started`, `ended`, `ghost_tapped(actor_id)`.
## `ash.grade` is the 0..1 amount (the same value that drives the grade pass), in case the
## game wants to duck its own HUD or music with it.
## Detail tier: `detail` -1 = from `Quality` (LOW has no grade pass and fewer particles).
##
## Cost budget (HIGH, 6 ghosts): view.step <= 0.3 ms/frame (measured in `view.last_frame_ms`).

signal started
signal ended
signal ghost_tapped(actor_id: String)

const SLOW_STEPS := [1.0, 0.5, 0.25]

@export var detail := -1
@export var show_hud := true
## Leave Ashsight automatically when the replay ends.
@export var auto_close := true
## "Cinematic" pacing: the quiet stretches before and after the action run faster (about 2x) and
## the blows themselves run in slow motion (0.3x). The player's own speed choice (1x / 0.5x /
## 0.25x on the HUD) multiplies it; `cinematic = false` gives plain 1x.
@export var cinematic := true

var view: AshReplayView
var grade_fx: AshsightGrade
var cam_rig: AshsightCamera
var hud: AshsightHud
var camera: Camera3D
var mem: AshMemory
var incident_id := -1
var active := false
var grade := 0.0

var _slow_i := 0
var _user_speed := 1.0
var _pace := 1.0
var _layer: CanvasLayer
var _resume_after_scrub := false
var _closing := false


func setup(cam: Camera3D, env: Environment = null, ground: Callable = Callable()) -> void:
	camera = cam
	view = AshReplayView.new()
	view.name = "AshReplayView"
	view.ground = ground
	view.pool = AshGhostPool.new()
	view.pool.detail_override = detail
	add_child(view)
	view.finished.connect(_on_replay_finished)
	view.ghost_tapped.connect(func(a: String) -> void: ghost_tapped.emit(a))
	grade_fx = AshsightGrade.new()
	grade_fx.name = "AshsightGrade"
	if detail >= 0:
		grade_fx.detail = detail
	add_child(grade_fx)
	grade_fx.bind_environment(env)
	cam_rig = AshsightCamera.new()
	cam_rig.name = "AshsightCamera"
	add_child(cam_rig)
	cam_rig.finished_out.connect(_on_camera_out)
	if show_hud:
		_layer = CanvasLayer.new()
		_layer.layer = 20
		add_child(_layer)
		hud = AshsightHud.new()
		hud.visible = false
		_layer.add_child(hud)
		hud.seek_requested.connect(func(t: float) -> void: view.seek(t))
		hud.scrub_started.connect(_on_scrub_started)
		hud.scrub_ended.connect(_on_scrub_ended)
		hud.play_toggled.connect(toggle_pause)
		hud.speed_cycled.connect(cycle_slow_motion)
		hud.closed.connect(stop)


## Build the ghosts' bodies ahead of time (one per frame, no hitch). Optional.
func warm() -> void:
	await view.warm()


func show_incident(memory: AshMemory, id: int, speed: float = 1.0) -> bool:
	if view == null or camera == null:
		return false
	mem = memory
	incident_id = id
	if not view.show_incident(memory, id, speed):
		return false
	_closing = false
	active = true
	_slow_i = 0
	_user_speed = speed
	_pace = 1.0
	var info := view.info
	var centre := Vector3(float((info["center"] as Vector2).x), 0.0, float((info["center"] as Vector2).y))
	if view.ground.is_valid():
		centre.y = float(view.ground.call(info["center"]))
	cam_rig.begin(camera, centre)
	if hud != null:
		hud.visible = true
		hud.set_incident(String(info["site"]), "the ashes are still warm  -  %d%%" % int(round(float(info["heat"]) * 100.0)),
			float(info["duration"]), info["marks"], info.get("acts", []))
	started.emit()
	return true


func stop() -> void:
	if not active or _closing:
		return
	_closing = true
	view.stop()   # the grade eases out on its own (view.grade)
	cam_rig.end()
	if hud != null:
		hud.visible = false
	active = false
	ended.emit()


func toggle_pause() -> void:
	if view.cursor != null:
		view.cursor.playing = not view.cursor.playing
		if view.cursor.finished():
			view.cursor.seek(0.0)
			view.cursor.playing = true


func cycle_slow_motion() -> void:
	_slow_i = (_slow_i + 1) % SLOW_STEPS.size()
	set_speed(SLOW_STEPS[_slow_i])


## The player's speed (1, 0.5, 0.25). The effective speed is this times the cinematic pace.
func set_speed(s: float) -> void:
	_user_speed = s
	_slow_i = maxi(0, SLOW_STEPS.find(s))
	view.set_speed(_user_speed * _pace)


func speed() -> float:
	return _user_speed


func _on_scrub_started() -> void:
	if view.cursor != null:
		_resume_after_scrub = view.cursor.playing
		view.cursor.playing = false


func _on_scrub_ended() -> void:
	if view.cursor != null and _resume_after_scrub:
		view.cursor.playing = true


func _on_replay_finished() -> void:
	if auto_close and active:
		stop()


func _on_camera_out() -> void:
	pass


## The aftermath: after the last blow (or, with no beats recorded, the last quarter).
func _in_tail() -> bool:
	if view.cursor == null:
		return false
	var acts: Array = view.info.get("acts", [])
	var real := acts.filter(func(a: Dictionary) -> bool: return StringName(a["kind"]) != &"chisel")
	if real.is_empty():
		return view.cursor.t > float(view.info.get("duration", 0.0)) * 0.75
	return view.cursor.t > float((real[real.size() - 1] as Dictionary)["t"]) + 2.5


func _apply_pace(dt: float) -> void:
	var t := view.cursor.t
	var acts: Array = view.info.get("acts", [])
	var target := 1.0
	if not acts.is_empty():
		var first := float((acts[0] as Dictionary)["t"])
		var last := float((acts[acts.size() - 1] as Dictionary)["t"])
		if t < first - 3.5:
			target = 2.1       # quiet lead-in
		elif t > last + 3.0:
			target = 1.7       # the flight
		for a: Dictionary in acts:
			var kind := StringName(a["kind"])
			if (kind == &"attack" or kind == &"death") and absf(float(a["t"]) - t) < 0.9:
				target = 0.3   # the blow
	_pace = move_toward(_pace, target, dt * 4.0)
	view.set_speed(_user_speed * _pace)


## How much of a beat (an attack / hit / fall) is happening at the replay cursor: {k: 0..1, at: world point or INF}.
func _beat_now() -> Dictionary:
	var out := {"k": 0.0, "at": Vector3.INF}
	if view.cursor == null:
		return out
	var t := view.cursor.t
	var sum := Vector3.ZERO
	var n := 0
	var k := 0.0
	for a: Dictionary in view.info.get("acts", []):
		var d := absf(float(a["t"]) - t)
		if d < 1.6 and StringName(a["kind"]) != &"chisel":
			var pos := view.ghost_position(String(a["actor"]))
			if pos != Vector3.INF:
				sum += pos
				n += 1
				k = maxf(k, 1.0 - d / 1.6)
	if n > 0:
		out["k"] = smoothstep(0.0, 0.6, k)
		out["at"] = sum / float(n) + Vector3(0, 1.0, 0)
	return out


func _process(dt: float) -> void:
	if view == null:
		return
	grade = view.grade
	grade_fx.set_amount(grade)
	if active:
		var pts := view.ghost_points()
		if not pts.is_empty():
			var beat := _beat_now()
			var tail := _in_tail()
			if tail and not view.ghost_points("bandit").is_empty():
				pts = view.ghost_points("bandit")   # the culprits leaving: where the trail leads
			cam_rig.update(pts, dt, float(beat["k"]), beat["at"], tail)
			grade_fx.follow(cam_rig.focus.global_position if cam_rig.focus != null else pts[0])
		if cinematic and view.cursor != null:
			_apply_pace(dt)
		if hud != null and view.cursor != null:
			hud.set_state(view.cursor.t, view.cursor.playing, _user_speed)
	elif grade <= 0.001:
		grade_fx.reset()
