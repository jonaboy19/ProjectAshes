class_name AshsightCamera
extends Node
## Soft camera pull-in for Ashsight: eases the game camera in to frame the incident, follows
## the action while the replay runs, and eases back out at the end.
##
## Uses the installed Phantom Camera addon (docs/addons/README.md): a PhantomCameraHost on the
## camera, a "restore" pcam holding the player's view, and a higher-priority "ashsight" pcam
## (SIMPLE follow + look-at on a focus node, damped) that the host blends to with a sine tween.
## Without the addon (or with `use_phantom = false`) it falls back to a simple damped move of
## the Camera3D itself, so nothing depends on it.
##
##   cam.begin(camera3d)                     player kneels: remember the view, pull in
##   cam.update(points, dt)                  every frame: ghost positions (Vector3s)
##   cam.end()                               ease back out (call `finished_out` when done)
##
## Hand-over rule for the camera owner: while `active` is true, do not write the camera's
## transform (the host does). When `active` turns false the game camera code resumes.

signal finished_out

const PCAM_SCRIPT := "res://addons/phantom_camera/scripts/phantom_camera/phantom_camera_3d.gd"
const HOST_SCRIPT := "res://addons/phantom_camera/scripts/phantom_camera_host/phantom_camera_host.gd"
const PCAM_PRIORITY := 40

## Distance = clamp(spread * DIST_PER_SPREAD + DIST_BASE, DIST_MIN, DIST_MAX)
const DIST_PER_SPREAD := 1.0
const DIST_BASE := 3.5
const DIST_MIN := 6.5
const DIST_MAX := 34.0
const PITCH_DEG := 19.0
## Ghosts count less the farther they are from the incident (full weight inside NEAR_R, a quarter
## at FAR_R), so arrivals and escapes still pull the view without dragging it away from the action.
const NEAR_R := 14.0
const FAR_R := 46.0
## On a beat (a blow, a fall) the camera dollies in to this fraction of its distance.
const BEAT_DIST := 0.62

@export var use_phantom := true
@export var blend_in := 1.3
@export var blend_out := 1.6

var active := false
var camera: Camera3D
var focus: Node3D

var _pcam: Node
var _restore: Node
var _host: Node
var _yaw := 0.0
var _dist := 18.0
var _focus_target := Vector3.ZERO
var _centre := Vector3.ZERO
var _beat := 0.0
var _ends_in := -1.0
var _fallback := false
var _saved_xform := Transform3D.IDENTITY
var _fb_t := 0.0
var _fb_from := Transform3D.IDENTITY


func phantom_available() -> bool:
	return use_phantom and ResourceLoader.exists(PCAM_SCRIPT) and ResourceLoader.exists(HOST_SCRIPT) \
		and get_tree().root.has_node("PhantomCameraManager")


## `yaw`: horizontal angle to look from (radians, 0 = looking down -Z); NAN keeps the player's.
func begin(cam: Camera3D, centre: Vector3, yaw: float = NAN) -> void:
	if cam == null:
		return
	camera = cam
	active = true
	_ends_in = -1.0
	_saved_xform = cam.global_transform
	if is_nan(yaw):
		var f := -cam.global_transform.basis.z
		f.y = 0.0
		_yaw = atan2(-f.x, -f.z) if f.length() > 0.01 else 0.0
	else:
		_yaw = yaw
	_dist = maxf(DIST_MIN, _saved_xform.origin.distance_to(centre) * 0.9)
	_centre = centre
	_focus_target = centre
	if focus == null:
		focus = Node3D.new()
		focus.name = "AshsightFocus"
		add_child(focus)
	focus.global_position = centre
	_fallback = not phantom_available()
	if _fallback:
		_fb_t = 0.0
		_fb_from = cam.global_transform
		return
	var pcam_cls: GDScript = load(PCAM_SCRIPT)
	var host_cls: GDScript = load(HOST_SCRIPT)
	# host on the camera (reuse one the game already has)
	for c in cam.get_children():
		if c.get_script() == host_cls:
			_host = c
	if _host == null:
		_host = host_cls.new()
		_host.name = "AshsightHost"
		cam.add_child(_host)
	# the player's view, held while we are away
	_restore = pcam_cls.new()
	_restore.name = "AshsightRestore"
	_restore.set("priority", 0)
	_restore.set("tween_resource", _tween(blend_out))
	get_tree().root.add_child(_restore)
	(_restore as Node3D).global_transform = _saved_xform
	# the Ashsight view: follows the focus node, looks at it
	_pcam = pcam_cls.new()
	_pcam.name = "AshsightPCam"
	_pcam.set("follow_mode", 2)            # SIMPLE
	_pcam.set("follow_target", focus)
	_pcam.set("follow_offset", _offset())
	_pcam.set("follow_damping", true)
	_pcam.set("follow_damping_value", Vector3(0.35, 0.35, 0.35))
	_pcam.set("look_at_mode", 2)           # SIMPLE
	_pcam.set("look_at_target", focus)
	_pcam.set("look_at_damping", true)
	_pcam.set("look_at_damping_value", 0.3)
	_pcam.set("tween_resource", _tween(blend_in))
	_pcam.set("priority", 0)
	get_tree().root.add_child(_pcam)
	(_pcam as Node3D).global_transform = _saved_xform
	# let the host settle on the restore pcam this frame, then blend to ours
	await get_tree().process_frame
	if active and _pcam != null:
		_restore.set("priority", 1)
		await get_tree().process_frame
		if active and _pcam != null:
			_pcam.set("priority", PCAM_PRIORITY)


func _tween(seconds: float) -> Resource:
	var tr_script: GDScript = load("res://addons/phantom_camera/scripts/resources/tween_resource.gd")
	var t: Resource = tr_script.new()
	t.set("duration", seconds)
	t.set("transition", 1)   # SINE
	t.set("ease", 2)         # EASE_IN_OUT
	return t


func _offset() -> Vector3:
	var p := deg_to_rad(PITCH_DEG)
	var horiz := _dist * cos(p)
	# yaw 0 looks down -Z, so the camera sits on +Z
	return Vector3(sin(_yaw) * horiz, _dist * sin(p), cos(_yaw) * horiz)


## Frame these world points (the visible ghosts). Call every frame while active.
## `beat` 0..1: how much a blow / fall is happening right now; `beat_point` where (world).
## `tail`: the aftermath (after the last blow): follow `points` (the culprits leaving) and ignore the
## incident centre, so the replay ends on where the trail leads.
func update(points: Array[Vector3], dt: float, beat: float = 0.0, beat_point: Vector3 = Vector3.INF, tail: bool = false) -> void:
	if not active or camera == null or points.is_empty():
		return
	var c := Vector3.ZERO
	var w := 0.0
	var spread := 3.0
	if tail:
		for p in points:
			c += p
		w = float(points.size())
		c /= w
		for p in points:
			spread = maxf(spread, Vector2(p.x - c.x, p.z - c.z).length())
	else:
		c = _centre * 2.0
		w = 2.0
		for p in points:
			var d := Vector2(p.x - _centre.x, p.z - _centre.z).length()
			var k := 1.0 - 0.75 * smoothstep(NEAR_R, FAR_R, d)
			c += p * k
			w += k
		c /= w
		for p in points:
			var d2 := Vector2(p.x - c.x, p.z - c.z).length()
			var far := Vector2(p.x - _centre.x, p.z - _centre.z).length()
			if far < FAR_R:
				spread = maxf(spread, d2)
	var want := clampf(spread * DIST_PER_SPREAD + DIST_BASE + (2.5 if tail else 0.0), DIST_MIN, DIST_MAX)
	_beat = lerpf(_beat, beat, clampf(dt * 3.0, 0.0, 1.0))
	if beat_point != Vector3.INF:
		c = c.lerp(beat_point, _beat * 0.75)
	want = lerpf(want, maxf(DIST_MIN, want * BEAT_DIST), _beat)
	_dist = lerpf(_dist, want, clampf(dt * 1.6, 0.0, 1.0))
	_focus_target = _focus_target.lerp(c + Vector3(0, 0.3, 0), clampf(dt * (1.6 if tail else 2.6), 0.0, 1.0))
	if focus != null:
		focus.global_position = _focus_target
	if _fallback:
		_fb_t = minf(1.0, _fb_t + dt / maxf(blend_in, 0.01))
		var k := _fb_t * _fb_t * (3.0 - 2.0 * _fb_t)
		var target := Transform3D(Basis(), _focus_target + _offset())
		target = target.looking_at(_focus_target, Vector3.UP)
		camera.global_transform = _fb_from.interpolate_with(target, k)
	elif _pcam != null:
		_pcam.set("follow_offset", _offset())


func end() -> void:
	if not active:
		return
	if _fallback:
		active = false
		camera.global_transform = _saved_xform
		finished_out.emit()
		return
	if _pcam != null:
		_pcam.set("priority", 0)
	_ends_in = blend_out + 0.25


func _process(dt: float) -> void:
	if _ends_in >= 0.0:
		_ends_in -= dt
		if _ends_in < 0.0:
			_release()


func _release() -> void:
	_ends_in = -1.0
	active = false
	for n in [_pcam, _restore]:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	_pcam = null
	_restore = null
	if _host != null and is_instance_valid(_host) and _host.name == &"AshsightHost":
		_host.queue_free()
	_host = null
	finished_out.emit()
