class_name FlipbookFX
extends RefCounted
## Baked flipbook (sprite sheet) effects: one billboard quad + one shared material per sheet, no particles.
## Sheets live in assets/vfx/flipbooks/ (see LICENSE.md there; made by tools/vfx/*.py), shader is
## shaders/vfx_flipbook/flipbook.gdshader.
##
##   FlipbookFX.play(&"fire_burst", world_pos)                 # one-shot at a point (bottom of the sprite sits on pos)
##   FlipbookFX.play(&"smoke_puff", pos, 1.5, Color(0.6,0.8,1.0))   # scale, tint (recolour any sheet per element)
##   FlipbookFX.attach(&"magic_swirl", node, 1.2)              # looping sheet that follows a node; returns the quad
##
## Quads are pooled (up to POOL_MAX idle per sheet) and return themselves when the one-shot ends.
## Cost: 1 quad = 1 draw call, 1 texture fetch pair per pixel (frame blend). The only per-play CPU work is one tween.

const DIR := "res://assets/vfx/flipbooks/"
const SHADER := preload("res://shaders/vfx_flipbook/flipbook.gdshader")
const POOL_MAX := 6

## file, cols, rows, frames, duration (s), size (m), energy, loop, lift (fraction of size the quad centre sits above pos)
const CATALOG := {
	&"fire_burst": {"file": "fire_burst.png", "cols": 4, "rows": 4, "frames": 16, "dur": 0.85, "size": 2.6, "energy": 1.15, "loop": false, "lift": 0.42},
	&"smoke_puff": {"file": "smoke_puff.png", "cols": 8, "rows": 8, "frames": 64, "dur": 2.2, "size": 2.6, "energy": 1.0, "loop": false, "lift": 0.42},
	&"dust_burst": {"file": "dust_burst.png", "cols": 8, "rows": 8, "frames": 64, "dur": 1.7, "size": 3.2, "energy": 1.0, "loop": false, "lift": 0.36},
	&"water_splash": {"file": "water_splash.png", "cols": 4, "rows": 4, "frames": 16, "dur": 0.9, "size": 2.4, "energy": 1.05, "loop": false, "lift": 0.40},
	&"lightning_sheet": {"file": "lightning_sheet.png", "cols": 4, "rows": 4, "frames": 16, "dur": 0.8, "size": 4.0, "energy": 1.3, "loop": false, "lift": 0.40},
	&"magic_swirl": {"file": "magic_swirl.png", "cols": 4, "rows": 4, "frames": 16, "dur": 1.2, "size": 2.2, "energy": 1.2, "loop": true, "lift": 0.5},
}

static var _mats: Dictionary = {}
static var _quad: QuadMesh
static var _pool: Dictionary = {}


static func material_for(kind: StringName) -> ShaderMaterial:
	if _mats.has(kind):
		return _mats[kind]
	var c: Dictionary = CATALOG[kind]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("atlas", load(DIR + String(c["file"])))
	m.set_shader_parameter("hframes", int(c["cols"]))
	m.set_shader_parameter("vframes", int(c["rows"]))
	m.set_shader_parameter("frame_count", int(c["frames"]))
	m.set_shader_parameter("fps", float(c["frames"]) / float(c["dur"]))
	m.set_shader_parameter("loop_anim", bool(c["loop"]))
	m.set_shader_parameter("energy", float(c["energy"]))
	_mats[kind] = m
	return m


static func _take(kind: StringName, parent: Node) -> MeshInstance3D:
	var arr: Array = _pool.get(kind, [])
	var q: MeshInstance3D = null
	while not arr.is_empty() and q == null:
		var cand: MeshInstance3D = arr.pop_back()
		if is_instance_valid(cand):
			q = cand
	if q == null:
		if _quad == null:
			_quad = QuadMesh.new()
			_quad.size = Vector2.ONE
		q = MeshInstance3D.new()
		q.mesh = _quad
		q.material_override = material_for(kind)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.extra_cull_margin = 16.0
	if q.get_parent() != parent:
		if q.get_parent():
			q.get_parent().remove_child(q)
		parent.add_child(q)
	q.visible = true
	return q


static func _give_back(kind: StringName, q: MeshInstance3D) -> void:
	if not is_instance_valid(q):
		return
	q.visible = false
	var arr: Array = _pool.get(kind, [])
	if arr.size() < POOL_MAX:
		arr.append(q)
		_pool[kind] = arr
	else:
		q.queue_free()


static func _set_progress(p: float, q: MeshInstance3D) -> void:
	if is_instance_valid(q):
		q.set_instance_shader_parameter("hold", p)


## One-shot (or a loop for looping sheets) at `pos`. Returns the quad (free to reposition/scale).
static func play(kind: StringName, pos: Vector3, scale := 1.0, tint := Color.WHITE, parent: Node = null) -> MeshInstance3D:
	if parent == null:
		var ml := Engine.get_main_loop() as SceneTree
		parent = ml.current_scene if ml else null
	if parent == null or not CATALOG.has(kind):
		return null
	var c: Dictionary = CATALOG[kind]
	var q := _take(kind, parent)
	var s: float = float(c["size"]) * scale
	q.scale = Vector3(s, s, s)
	q.global_position = pos + Vector3(0, s * float(c["lift"]), 0)
	q.set_instance_shader_parameter("hold", 0.0)
	# tint is per material (shared); recolouring per instance would need a material copy. Only allocate one if asked.
	if tint != Color.WHITE:
		var m := (q.material_override as ShaderMaterial).duplicate() as ShaderMaterial
		m.set_shader_parameter("tint", tint)
		q.material_override = m
	elif q.material_override != material_for(kind):
		q.material_override = material_for(kind)
	var tw := q.create_tween()
	tw.tween_method(_set_progress.bind(q), 0.0, 1.0, float(c["dur"]))
	if bool(c["loop"]):
		tw.set_loops()
	else:
		tw.tween_callback(_give_back.bind(kind, q))
	return q


## Looping (or held-last-frame) sheet parented to `node`; call `queue_free()` on the returned quad to stop it.
static func attach(kind: StringName, node: Node3D, scale := 1.0, tint := Color.WHITE) -> MeshInstance3D:
	var q := play(kind, node.global_position, scale, tint, node)
	if q:
		q.position = Vector3(0, float(CATALOG[kind]["size"]) * scale * float(CATALOG[kind]["lift"]), 0)
	return q
