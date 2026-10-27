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

## Materials that keep a footprint, and how dark it is.
const PRINT := {&"snow": Color(0.62, 0.68, 0.80, 0.85), &"mud": Color(0.16, 0.12, 0.08, 0.75), &"sand": Color(0.50, 0.42, 0.30, 0.6)}
const PRINT_POOL := 48           # ring buffer of Decal nodes shared by everyone
const PRINT_LIFE := 25.0         # seconds before a print has faded out

static var _prints: Array[Decal] = []
static var _print_i := 0
static var _print_tex: Texture2D
static var _side := 1.0
static var _window_start := 0.0
static var _window_count := 0
static var last := {}


static func footstep(body: Node3D, pos: Vector3, volume_db := 0.0, speed := 3.0) -> Dictionary:
	var g := _query(body, pos)
	last = g
	var fam: String = g["footstep"]
	var audio := _audio(body)
	if audio != null:
		audio.call("play_footstep", pos, fam, volume_db + (3.0 if fam == "water" else 0.0), body)   # body: positional NPC feet
	_puff(body, pos, g["material"], clampf(speed / 4.0, 0.5, 1.5))
	if g["hit"]:
		_footprint(body, g["position"], g["normal"], g["material"])
	return g


static func land(body: Node3D, pos: Vector3, fall_speed: float) -> Dictionary:
	var g := _query(body, pos)
	var k := clampf(fall_speed / 8.0, 0.6, 2.5)
	var audio := _audio(body)
	if audio != null:
		audio.call("play_footstep", pos, g["footstep"], 2.0 + 3.0 * k, body)
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


## Pooled decal footprint (left/right alternating) on snow, mud and sand near the camera.
static func _footprint(body: Node3D, at: Vector3, normal: Vector3, material: StringName) -> void:
	if not PRINT.has(material) or body == null or not body.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var cam := body.get_viewport().get_camera_3d()
	if cam != null and cam.global_position.distance_squared_to(at) > PUFF_RANGE * PUFF_RANGE:
		return
	var parent := body.get_parent()
	var d: Decal
	if _prints.size() < PRINT_POOL:
		d = Decal.new()
		d.size = Vector3(0.16, 0.4, 0.32)
		d.texture_albedo = _tex()
		d.distance_fade_enabled = true
		d.distance_fade_begin = 14.0
		d.distance_fade_length = 4.0
		_prints.append(d)
	else:
		d = _prints[_print_i]
		_print_i = (_print_i + 1) % PRINT_POOL
		if not is_instance_valid(d):
			return
	if d.get_parent() != parent:
		if d.get_parent() != null:
			d.get_parent().remove_child(d)
		parent.add_child(d)
	var vel: Variant = body.get("velocity")
	var fwd: Vector3 = vel if vel is Vector3 else Vector3.ZERO
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		fwd = -body.global_transform.basis.z
	fwd = fwd.normalized()
	var right := fwd.cross(normal).normalized()
	_side = -_side
	d.global_transform = Transform3D(Basis(right, normal, -fwd).orthonormalized(), at + right * 0.11 * _side)
	d.modulate = PRINT[material]
	var tw := d.create_tween()
	d.albedo_mix = 1.0
	tw.tween_property(d, "albedo_mix", 0.0, PRINT_LIFE).set_delay(PRINT_LIFE * 0.4)


static func _tex() -> Texture2D:
	if _print_tex != null:
		return _print_tex
	var w := 32
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var v := (y + 0.5) / h * 2.0 - 1.0
			var sole := Vector2(u / 0.8, (v + 0.25) / 0.7).length()       # fore-foot
			var heel := Vector2(u / 0.65, (v - 0.62) / 0.3).length()        # heel
			var a := maxf(1.0 - smoothstep(0.75, 1.0, sole), 1.0 - smoothstep(0.75, 1.0, heel))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_print_tex = ImageTexture.create_from_image(img)
	return _print_tex


static func print_count() -> int:
	return _prints.size()
