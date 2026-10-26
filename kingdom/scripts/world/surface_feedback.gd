class_name SurfaceFeedback
extends RefCounted
## Per-material footstep / landing feedback built on SurfaceQuery: the right sound family plus a small
## dust / snow / mud / water puff. One call per footfall:
##   SurfaceFeedback.footstep(body, foot_pos, volume_db, speed)   -> the SQ.ground() dictionary it used
##   SurfaceFeedback.land(body, pos, fall_speed)                  -> heavier puff + louder step
## Puffs are skipped beyond PUFF_RANGE of the camera and capped per second, so NPC crowds stay cheap.

const SQ := preload("res://scripts/world/surface_query.gd")
const K := preload("res://scripts/vfx/vfx_kit.gd")
const PUFF_RANGE := 18.0
const MAX_PUFFS_PER_SEC := 12
## material -> [colour, particle count, upward speed]; absent = no puff (grass, leaves, wood, stone).
const PUFF := {
	&"dirt": [Color(0.55, 0.45, 0.33, 0.55), 5, 0.6],
	&"sand": [Color(0.82, 0.74, 0.55, 0.55), 6, 0.7],
	&"mud": [Color(0.30, 0.24, 0.17, 0.8), 5, 1.2],
	&"snow": [Color(0.95, 0.97, 1.0, 0.8), 7, 0.9],
	&"water": [Color(0.80, 0.90, 1.0, 0.75), 9, 2.2],
}

static var _window_start := 0.0
static var _window_count := 0
static var last := {}


static func footstep(body: Node3D, pos: Vector3, volume_db := 0.0, speed := 3.0) -> Dictionary:
	var g := _query(body, pos)
	last = g
	var fam: String = g["footstep"]
	var audio := _audio(body)
	if audio != null:
		audio.call("play_footstep", pos, fam, volume_db + (3.0 if fam == "water" else 0.0))
	_puff(body, pos, g["material"], clampf(speed / 4.0, 0.5, 1.5))
	return g


static func land(body: Node3D, pos: Vector3, fall_speed: float) -> Dictionary:
	var g := _query(body, pos)
	var k := clampf(fall_speed / 8.0, 0.6, 2.5)
	var audio := _audio(body)
	if audio != null:
		audio.call("play_footstep", pos, g["footstep"], 2.0 + 3.0 * k)
	_puff(body, pos, g["material"], k * 1.6)
	return g


static func _query(body: Node3D, pos: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = null
	var ex: Array = []
	if body != null and body.is_inside_tree():
		space = body.get_world_3d().direct_space_state
		if body is CollisionObject3D:
			ex = [(body as CollisionObject3D).get_rid()]
	return SQ.ground(space, pos, ex)


static func _audio(body: Node) -> Node:
	if body == null or not body.is_inside_tree():
		return null
	var a := body.get_tree().root.get_node_or_null(^"Audio")
	return a if a != null and a.has_method("play_footstep") else null


static func _puff(body: Node3D, pos: Vector3, material: StringName, k: float) -> void:
	if not PUFF.has(material) or body == null or not body.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var cam := body.get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_squared_to(pos) > PUFF_RANGE * PUFF_RANGE:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _window_start > 1.0:
		_window_start = now
		_window_count = 0
	if _window_count >= MAX_PUFFS_PER_SEC:
		return
	_window_count += 1
	var spec: Array = PUFF[material]
	var p := K.pal_from(spec[0])
	var up: float = spec[2]
	K.emit(body.get_parent(), pos + Vector3.UP * 0.04, {"amount": int(round(float(spec[1]) * k)), "life": 0.55,
		"v": Vector2(up * 0.5, up) * k, "spread": 75.0, "gravity": Vector3(0, -3.0 if material != &"water" else -9.0, 0),
		"damping": Vector2(2, 4), "size": Vector2(0.06, 0.16) * k, "mat": K.sprite_mat(K.SMOKE_PUFF, p, 0.8)})
