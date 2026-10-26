class_name GroundRealism
extends RefCounted
## Ground-contact realism for the player (PC), next to WallContact (docs/anim/aaa_wiring/):
##   slope lean    the model pitches into a hill a little (uphill leans forward, downhill back), up to 0.08 rad
##   slope slide   standing on a floor steeper than slope_slide.min_deg (and no stairs): downhill acceleration g sin(a) * 0.6,
##                 capped at 7 m/s, steering keeps 30 %, jump still works; stance "slide" while it lasts
##   edge balance  the feet ray hits but both side rays (+-0.25 m) find more than balance.drop of air: a beam or a thin wall
##                 top. Speed capped at 1.2 m/s, arms out (hand IK), a little torso sway
##   ledge stop    walking (not running) toward a drop deeper than ledge_stop.drop: a 0.3 s brake at the edge unless the stick
##                 has been held 0.4 s
## Everything is on the player only (NPCs get no new per-frame work). `pre_move()` runs just before move_and_slide().

const G := 9.8
const WallContactScript := preload("res://scripts/actors/wall_contact.gd")

var sliding := false
var balancing := false
var at_edge := false
var _slide_v := Vector3.ZERO
var _edge_f := 1.0
var _edge_hold := 0.0
var _hands := 0.0
var _t := 0.0
var _lean_pitch := 0.0
var _sway := 0.0
var _stance_set := false
var _ray := PhysicsRayQueryParameters3D.new()
var _rig_ref: WeakRef


func bind_rig(rig: Node) -> void:
	_rig_ref = weakref(rig) if rig != null else null


static func cfg(key: String) -> Dictionary:
	return (load("res://scripts/actors/traversal.gd") as GDScript).call("config").get(key, {})


# --- pure helpers (tests) -----------------------------------------------------------------------------------------------

## Pitch (rad, + = lean forward) for walking over a slope: uphill leans in, downhill leans back.
static func slope_pitch(floor_normal: Vector3, move_dir: Vector3, c := {}) -> float:
	var k: Dictionary = c if not c.is_empty() else cfg("slope_lean")
	var n := Vector3(floor_normal.x, 0.0, floor_normal.z)
	var m := Vector3(move_dir.x, 0.0, move_dir.z)
	if m.length_squared() < 0.0001:
		return 0.0
	return clampf(-n.dot(m.normalized()) * float(k.get("gain", 0.25)), -float(k.get("max", 0.08)), float(k.get("max", 0.08)))


## True when a floor with this normal is steep enough to slide on.
static func slide_slope(floor_normal: Vector3, c := {}) -> bool:
	var s: Dictionary = c if not c.is_empty() else cfg("slope_slide")
	return floor_normal.y > 0.3 and floor_normal.y < cos(deg_to_rad(float(s.get("min_deg", 40.0))))


## Downhill acceleration (m/s^2) on a slope of this normal: g sin(a) * accel_k.
static func slide_accel(floor_normal: Vector3, c := {}) -> float:
	var s: Dictionary = c if not c.is_empty() else cfg("slope_slide")
	var a := acos(clampf(floor_normal.y, -1.0, 1.0))
	return G * sin(a) * float(s.get("accel_k", 0.6))


## Beam vs wall top: the feet ray hit and both side rays dropped by at least `drop` (INF = no ground).
static func balance_on(centre_hit: bool, left_drop: float, right_drop: float, c := {}) -> bool:
	var b: Dictionary = c if not c.is_empty() else cfg("balance")
	var d := float(b.get("drop", 0.3))
	return centre_hit and left_drop >= d and right_drop >= d


## A drop deeper than ledge_stop.drop ahead of a walker.
static func edge_ahead(drop: float, c := {}) -> bool:
	var e: Dictionary = c if not c.is_empty() else cfg("ledge_stop")
	return drop > float(e.get("drop", 1.2))


# --- per-frame --------------------------------------------------------------------------------------------------------

func lean_pitch() -> float:
	return _lean_pitch


## Called after the planar velocity is set, before move_and_slide(). Returns the velocity to use.
func pre_move(body: CharacterBody3D, dir: Vector3, delta: float, running: bool, wall: RefCounted) -> Vector3:
	var v := body.velocity
	_t += delta
	var on_floor := body.is_on_floor()
	var enabled := _enabled(body)
	# slope lean
	var fn := body.get_floor_normal() if on_floor else Vector3.UP
	var want_pitch := slope_pitch(fn, dir) if (on_floor and enabled) else 0.0
	_lean_pitch = lerpf(_lean_pitch, want_pitch, 1.0 - exp(-8.0 * delta))
	if not enabled:
		_end_slide(body)
		_set_balance(body, false, delta)
		_edge_f = 1.0
		return v
	var planar := Vector2(v.x, v.z)
	# slope slide
	var sc := cfg("slope_slide")
	# Pushing up a steep ramp climbs it slowly as before (no slide: stick-vs-slide jitter at the foot); let go and it slides.
	var down := Vector3(fn.x, 0.0, fn.z)
	var uphill: bool = dir.length() > 0.1 and down.length() > 0.01 and dir.normalized().dot(-down.normalized()) > 0.3
	if on_floor and slide_slope(fn, sc) and not uphill:
		var a := slide_accel(fn, sc)
		_slide_v += down.normalized() * a * delta
		var cap := float(sc.get("cap", 7.0))
		if _slide_v.length() > cap:
			_slide_v = _slide_v.normalized() * cap
		if not sliding:
			sliding = true
			_stance(body, "slide")
			_rig_off(true)
		planar *= float(sc.get("steer", 0.3))
		planar += Vector2(_slide_v.x, _slide_v.z)
		v.x = planar.x
		v.z = planar.y
		return v
	if sliding or _slide_v.length_squared() > 0.0001:
		# off the slope: the slide speed bleeds off into the ordinary movement
		_end_slide(body)
		_slide_v = _slide_v.move_toward(Vector3.ZERO, 14.0 * delta)
		planar += Vector2(_slide_v.x, _slide_v.z)
	# braced against a wall: only a fraction of the slide along it survives (head-on = none, so the legs idle)
	if wall != null and wall.state == WallContactScript.BRACE and wall.normal != Vector3.ZERO:
		var t2 := Vector2(-wall.normal.z, wall.normal.x)
		var along := planar.dot(t2)
		planar += t2 * along * (wall.slide_scale() - 1.0)
	var f := 1.0
	# wall dead ahead: stop short of it
	var wcap: float = wall.limit_speed(planar.length()) if wall != null else planar.length()
	if wcap < planar.length() and planar.length() > 0.01:
		f = minf(f, wcap / planar.length())
	# balance on a beam / thin wall top
	var bal := false
	if on_floor and dir.length() > 0.01 or (on_floor and balancing):
		bal = _balance_probe(body, dir)
	_set_balance(body, bal, delta)
	if bal and planar.length() > 0.01:
		f = minf(f, float(cfg("balance").get("speed_cap", 1.2)) / planar.length())
	# walking toward a deep drop
	var edge := false
	if on_floor and not running and not bal and dir.length() > 0.5 and not (wall != null and wall.state != WallContactScript.NONE):
		edge = edge_ahead(_drop_ahead(body, dir))
	var ec := cfg("ledge_stop")
	if edge:
		_edge_hold += delta
		at_edge = true
		if _edge_hold < float(ec.get("hold", 0.4)):
			_edge_f = move_toward(_edge_f, 0.0, delta / maxf(float(ec.get("brake", 0.3)), 0.05))
		else:
			_edge_f = move_toward(_edge_f, 1.0, delta / 0.15)
	else:
		_edge_hold = 0.0
		at_edge = false
		_edge_f = move_toward(_edge_f, 1.0, delta / 0.15)
	f = minf(f, _edge_f)
	v.x = planar.x * f
	v.z = planar.y * f
	return v


func _enabled(body: CharacterBody3D) -> bool:
	if bool(body.get("dead")) or bool(body.get("swimming")) or body.get("_mount") != null:
		return false
	var trav: Variant = body.get("_trav")
	if trav != null and trav.has_method("busy") and bool(trav.call("busy")):
		return false
	return float(body.get("_dodge")) <= 0.0


func _stance(body: CharacterBody3D, name: String) -> void:
	var an: Variant = body.get("_animator")
	if an == null or not an.has_method("set_stance"):
		return
	if name != "" and String(an.call("stance")) != "":
		return                                          # crouch / swim / ride own the stance
	if name == "" and not _stance_set:
		return
	an.call("set_stance", name)
	_stance_set = name != ""


func _end_slide(body: CharacterBody3D) -> void:
	if sliding:
		sliding = false
		_stance(body, "")
		_rig_off(false)


## Foot IK off while sliding (the planted-foot assumption is wrong on a slide).
func _rig_off(on: bool) -> void:
	var rig = _rig_ref.get_ref() if _rig_ref != null else null
	if rig != null and is_instance_valid(rig):
		rig.set("external_off", on)


func _ray_down(body: CharacterBody3D, from: Vector3, length: float) -> float:
	var space := body.get_world_3d().direct_space_state
	_ray.from = from
	_ray.to = from + Vector3.DOWN * length
	_ray.collision_mask = 1
	_ray.exclude = [body.get_rid()]
	var hit := space.intersect_ray(_ray)
	if hit.is_empty():
		return INF
	return from.y - (hit["position"] as Vector3).y


func _drop_ahead(body: CharacterBody3D, dir: Vector3) -> float:
	var e := cfg("ledge_stop")
	var p := body.global_position + dir.normalized() * float(e.get("ahead", 0.4)) + Vector3.UP * 0.3
	var d := _ray_down(body, p, 3.0)
	return INF if d == INF else d - 0.3


func _balance_probe(body: CharacterBody3D, dir: Vector3) -> bool:
	var b := cfg("balance")
	var fwd := dir.normalized() if dir.length() > 0.01 else (body.get("_model") as Node3D).global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := Vector3.UP.cross(fwd) * float(b.get("side", 0.25))
	var p := body.global_position + Vector3.UP * 0.3
	var c := _ray_down(body, p, 1.0)
	var l := _ray_down(body, p + side, 1.6) - 0.3
	var r := _ray_down(body, p - side, 1.6) - 0.3
	var centre := c != INF and c < 0.5
	return balance_on(centre, l if l != INF else 9.0, r if r != INF else 9.0, b)


func _set_balance(body: CharacterBody3D, on: bool, delta: float) -> void:
	balancing = on
	var want := 1.0 if on else 0.0
	_hands = move_toward(_hands, want, delta / 0.2)
	var sway_goal := sin(_t * 2.4) * float(cfg("balance").get("sway", 0.04)) * want
	_sway = lerpf(_sway, sway_goal, 1.0 - exp(-6.0 * delta))
	var rig = _rig_ref.get_ref() if _rig_ref != null else null
	if rig == null or not is_instance_valid(rig):
		return
	rig.call("set_torso_yaw_offset", _sway, 1)
	if _hands > 0.001 or on:
		var b := cfg("balance")
		var model := body.get("_model") as Node3D
		var fwd := model.global_basis.z.normalized()
		var left := Vector3.UP.cross(fwd)
		var k := _body_k(body)
		var base := body.global_position + Vector3.UP * float(b.get("arm_h", 1.3)) * k
		var lat := float(b.get("arm_lateral", 0.6)) * k
		rig.call("set_hand_brace", 0, base + left * lat, Vector3.ZERO, _hands * 0.9)
		rig.call("set_hand_brace", 1, base - left * lat, Vector3.ZERO, _hands * 0.9)


## Visual body scale of the player (a child is 0.58 of an adult; the capsule itself is not scaled).
static func _body_k(body: Node) -> float:
	var m: Variant = body.get("_model")
	return maxf((m as Node3D).scale.y, 0.1) if m is Node3D else 1.0
