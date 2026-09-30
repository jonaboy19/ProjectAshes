class_name WeaponTrail
extends Node
## Cheap pooled sword ribbon. One trail node per weapon-carrying character (idle = process off);
## the ribbon mesh itself (one MeshInstance3D + one fixed-size ArrayMesh) comes from a static pool
## shared by all characters, capped by Quality tier (LOW 2 / MEDIUM 4 / HIGH 8 simultaneous).
##
##   var t := WeaponTrail.attach(model, &"fire")
##   t.swing("Sword_Regular_A", 1.7)   # emits over the CombatMarkers trail window, gated by tip speed
##
## Sampling: every rendered frame the blade base + tip are read from the skeleton (after the
## AnimationPlayer, process_priority 100), kept only while tip speed > GATE, aged by scaled delta
## (hit-stop freezes it), and Catmull-Rom subdivided on MEDIUM/HIGH so fast arcs stay curved.
## Render: 3 vertices per column (base / mid / tip) x MAX_COLS, uploaded with
## RenderingServer.mesh_surface_update_{vertex,attribute}_region, 1 draw call per active trail.

const GATE := 3.0                 # m/s tip speed needed to lay ribbon
const MIN_STEP := 0.03            # m: skip samples closer than this (hit-stop / slow tail)
const MAX_RAW := 12               # raw samples kept
const MAX_COLS := 32              # columns in every pooled buffer (HIGH)
const LOW_COLS := 8
const ROWS := 3
const CAPS := [2, 4, 8]           # simultaneous active trails per tier
const ALPHA_TIP := 0.72
const ALPHA_MID := 0.26
const ALPHA_BASE := 0.02
const FALLBACK_WINDOW := 0.5

# ---- static pool ------------------------------------------------------------------------

class Ribbon extends RefCounted:
	var mi: MeshInstance3D
	var mesh: ArrayMesh
	var busy := false


static var _pool: Array[Ribbon] = []
static var _active := 0
static var _mat: ShaderMaterial
static var _holder_node: Node3D
static var _indices: PackedInt32Array
static var _zero_v := PackedByteArray()
static var _zero_c := PackedByteArray()
static var stats := {"skipped_cap": 0, "created": 0}


static func _material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/vfx/weapon_trail.gdshader")
	return _mat


## Persistent parent for all pooled ribbons (outlives any character).
static func _holder() -> Node3D:
	if not is_instance_valid(_holder_node):
		_holder_node = Node3D.new()
		_holder_node.name = "WeaponTrailPool"
		var ml := Engine.get_main_loop()
		if ml is SceneTree:
			(ml as SceneTree).root.add_child.call_deferred(_holder_node)
	return _holder_node


static func _make_ribbon() -> Ribbon:
	if _indices.is_empty():
		var idx := PackedInt32Array()
		for c in MAX_COLS - 1:
			for r in ROWS - 1:
				var a := c * ROWS + r
				var b := (c + 1) * ROWS + r
				idx.append_array([a, a + 1, b, a + 1, b + 1, b])
		_indices = idx
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var verts := PackedVector3Array()
	verts.resize(MAX_COLS * ROWS)
	var cols := PackedColorArray()
	cols.resize(MAX_COLS * ROWS)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	mesh.custom_aabb = AABB(Vector3(-2000, -2000, -2000), Vector3(4000, 4000, 4000))
	mesh.surface_set_material(0, _material())
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	mi.name = "TrailRibbon"
	var r := Ribbon.new()
	r.mi = mi
	r.mesh = mesh
	_holder().add_child(mi)
	_pool.append(r)
	stats["created"] += 1
	return r


static func cap() -> int:
	return CAPS[clampi(ElementFX._tier(), 0, 2)]


## Pre-build pool ribbons (call at load to avoid the first-swing hitch).
static func warmup(count := 8) -> void:
	_material()
	while _pool.size() < count:
		_make_ribbon()


static func _acquire() -> Ribbon:
	if _active >= cap():
		stats["skipped_cap"] += 1
		return null
	for r in _pool:
		if not r.busy:
			r.busy = true
			_active += 1
			return r
	var n := _make_ribbon()
	n.busy = true
	_active += 1
	return n


static func _release(r: Ribbon) -> void:
	if r == null or not r.busy:
		return
	r.busy = false
	_active -= 1
	r.mi.visible = false


static func active_count() -> int:
	return _active


## Free pooled nodes (tests / shutdown).
static func free_pool() -> void:
	for r in _pool:
		if is_instance_valid(r.mi):
			r.mi.free()
	_pool.clear()
	if is_instance_valid(_holder_node):
		_holder_node.free()
	_holder_node = null
	_active = 0
	_mat = null


# ---- instance ---------------------------------------------------------------------------

var _sk: Skeleton3D
var _att: Node3D
var _bone := -1
var _l_base := Vector3.ZERO
var _l_tip := Vector3.ZERO
var _element: StringName = &"light"
var _life := 0.14
var _subdiv := true
var _cols_cap := MAX_COLS

var _ribbon: Ribbon
var _clock := 0.0                 # scaled seconds since swing()
var _win_a := 0.0
var _win_b := 0.0
var _armed := false
var _skip := false
var _prev_tip := Vector3.ZERO
var _have_prev := false
var _have_last := false
var _last_tip := Vector3.ZERO
var _bw_base := Vector3.ZERO
var _bw_tip := Vector3.ZERO

var _pb := PackedVector3Array()   # raw samples, oldest first
var _pt := PackedVector3Array()
var _ps := PackedFloat32Array()   # birth clock
var _fv := PackedVector3Array()   # upload buffers (cols_cap * 3)
var _fc := PackedInt32Array()
var _c_core := 0
var _c_mid := 0
var _c_edge := 0
var _written := 0                 # columns of live data written last frame

var t_process_usec := 0           # bench: accumulated _process time
var t_frames := 0
var t_pose_usec := 0              # bench: part of the above spent in the (otherwise unavoidable) skeleton pose flush


## Adds a trail to `model`, finding the blade on the weapon carried at `hand_bone`.
## Returns null when the character holds no weapon there.
static func attach(model: Node3D, element: Variant = &"light", hand_bone := "hand_r") -> WeaponTrail:
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	var sk := found[0] as Skeleton3D
	var t := WeaponTrail.new()
	t.name = "WeaponTrail"
	if not t._find_blade(sk, hand_bone):
		t.free()
		return null
	model.add_child(t)
	t.set_element(element)
	t.process_priority = 100
	t.set_process(false)
	return t


func _find_blade(sk: Skeleton3D, hand_bone: String) -> bool:
	for att in sk.find_children("*", "BoneAttachment3D", true, false):
		var a := att as BoneAttachment3D
		if a.bone_name != hand_bone:
			continue
		for child in a.get_children():
			var prop := child as Node3D
			if prop == null:
				continue
			var box := _box_in(prop, a)
			if box.size == Vector3.ZERO:
				continue
			var ax := 0
			for i in 3:
				if box.size[i] > box.size[ax]:
					ax = i
			var c := box.get_center()
			var lo := c
			var hi := c
			lo[ax] = box.position[ax]
			hi[ax] = box.end[ax]
			var tip := hi if hi.length() > lo.length() else lo
			var grip := lo if tip == hi else hi
			_sk = sk
			_att = a
			_bone = sk.find_bone(hand_bone)
			_l_tip = tip
			_l_base = grip.lerp(tip, 0.28)
			return true
	return false


static func _box_in(node: Node3D, space: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false) + ([node] if node is MeshInstance3D else []):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var cur: Node = m
		while cur != null and cur != space:
			if cur is Node3D:
				xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var b := xf * m.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func set_element(e: Variant) -> void:
	_element = ElementFX.canon(e)
	var p: Dictionary = ElementFX.palette(_element)
	var core: Color = p["core"]
	var mid: Color = p["mid"]
	var edge: Color = p["edge"]
	if _element == &"light":       # neutral / physical: pale steel, not gold
		var steel := Color(0.9, 0.92, 0.95)
		core = core.lerp(steel, 0.5)
		mid = mid.lerp(steel, 0.5)
		edge = edge.lerp(steel, 0.5)
	_c_core = _rgb(core)
	_c_mid = _rgb(mid)
	_c_edge = _rgb(edge)


static func _rgb(c: Color) -> int:
	return (int(clampf(c.r, 0.0, 1.0) * 255.0 + 0.5)) | (int(clampf(c.g, 0.0, 1.0) * 255.0 + 0.5) << 8) \
		| (int(clampf(c.b, 0.0, 1.0) * 255.0 + 0.5) << 16)


## Arm from the marker table: emit between trail_start and trail_end (rate-scaled).
func swing(clip: String, rate := 1.0) -> void:
	var w := CombatMarkers.window_s(clip, "trail", rate)
	if w.x < 0.0:
		_begin(0.0, FALLBACK_WINDOW)     # unknown clip: velocity gate alone decides
	else:
		_begin(w.x, w.y)


func emit_for(seconds: float) -> void:
	_begin(0.0, seconds)


func _begin(a: float, b: float) -> void:
	if _sk == null:
		return
	var tier := clampi(ElementFX._tier(), 0, 2)
	_life = 0.10 if tier == 0 else 0.14
	_subdiv = tier > 0
	_cols_cap = LOW_COLS if tier == 0 else MAX_COLS
	if _fv.size() != _cols_cap * ROWS:
		_fv.resize(_cols_cap * ROWS)
		_fc.resize(_cols_cap * ROWS)
	_clock = 0.0
	_win_a = a
	_win_b = b
	_armed = true
	_skip = false
	_have_prev = false
	_have_last = false
	_pb.clear()
	_pt.clear()
	_ps.clear()
	set_process(true)


func stop(fade := true) -> void:
	_armed = false
	if not fade:
		_pb.clear()
		_pt.clear()
		_ps.clear()
		_finish()


func _finish() -> void:
	if _ribbon:
		_release(_ribbon)
		_ribbon = null
	_armed = false
	_have_prev = false
	set_process(false)


func _exit_tree() -> void:
	if _ribbon:
		_release(_ribbon)
		_ribbon = null


func _blade_world() -> void:
	var xf: Transform3D
	if _bone >= 0 and _sk.is_inside_tree():
		xf = _sk.global_transform * _sk.get_bone_global_pose(_bone)
	else:
		xf = _att.global_transform
	_bw_base = xf * _l_base
	_bw_tip = xf * _l_tip


## Current blade tip in world space (sparks / hit VFX at the blade instead of the enemy centre, P12).
func tip_position() -> Vector3:
	if _sk == null:
		return Vector3.ZERO
	_blade_world()
	return _bw_tip


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	if delta > 0.0:
		_clock += delta
		_step(delta)
	t_process_usec += Time.get_ticks_usec() - t0
	t_frames += 1


func _step(delta: float) -> void:
	# age out
	while _ps.size() > 0 and _clock - _ps[0] >= _life:
		_pb.remove_at(0)
		_pt.remove_at(0)
		_ps.remove_at(0)
	var live := _armed and _clock >= _win_a
	if live and _clock > _win_b:
		_armed = false
		live = false
	if _armed or _ps.size() > 0:
		var tp := Time.get_ticks_usec()
		_blade_world()
		t_pose_usec += Time.get_ticks_usec() - tp
		var tip := _bw_tip
		if live and not _skip:
			var speed := 0.0
			if _have_prev:
				speed = tip.distance_to(_prev_tip) / delta
			if _have_prev and speed > GATE:
				if not _have_last:
					# resumed after a slow gap: don't bridge to old ribbon
					_pb.clear()
					_pt.clear()
					_ps.clear()
				if not _have_last or tip.distance_squared_to(_last_tip) > MIN_STEP * MIN_STEP:
					if _ribbon == null:
						_ribbon = _acquire()
						if _ribbon == null:
							_skip = true
						else:
							_prepare_ribbon()
					if _ribbon:
						if _ps.size() >= MAX_RAW:
							_pb.remove_at(0)
							_pt.remove_at(0)
							_ps.remove_at(0)
						_pb.append(_bw_base)
						_pt.append(tip)
						_ps.append(_clock)
						_last_tip = tip
						_have_last = true
			elif _have_prev:
				_have_last = false
		_prev_tip = tip
		_have_prev = true
	if _ribbon:
		if _ps.size() == 0 and not _armed:
			_finish()
			return
		if _ps.size() > 0:
			_upload()
	elif not _armed and _ps.size() == 0:
		_finish()


func _prepare_ribbon() -> void:
	var mi := _ribbon.mi
	mi.top_level = true
	mi.visible = true
	# clear stale data from a previous owner
	if _zero_v.is_empty():
		_zero_v.resize(MAX_COLS * ROWS * 12)
		_zero_c.resize(MAX_COLS * ROWS * 4)
	RenderingServer.mesh_surface_update_vertex_region(_ribbon.mesh.get_rid(), 0, 0, _zero_v)
	RenderingServer.mesh_surface_update_attribute_region(_ribbon.mesh.get_rid(), 0, 0, _zero_c)
	_written = 0


## Builds every column straight into the upload buffers (newest column first) and returns the
## column count. Inlined on purpose: this is the hot loop.
func _upload() -> void:
	var n := _ps.size()
	var inv_life := 1.0 / _life
	var cap_c := _cols_cap
	var m := 0
	var i := n - 1
	var c_edge := _c_edge
	var c_mid := _c_mid
	var c_core := _c_core
	while i >= 0 and m < cap_c:
		var ba := _pb[i]
		var ta := _pt[i]
		var sa := _ps[i]
		var f := 1.0 - (_clock - sa) * inv_life
		f = f * f if f > 0.0 else 0.0
		var o := m * ROWS
		_fv[o] = ba
		_fv[o + 1] = ba + (ta - ba) * 0.55
		_fv[o + 2] = ta
		_fc[o] = c_edge | (int(ALPHA_BASE * f * 255.0) << 24)
		_fc[o + 1] = c_mid | (int(ALPHA_MID * f * 255.0) << 24)
		_fc[o + 2] = c_core | (int(ALPHA_TIP * f * 255.0) << 24)
		m += 1
		if i == 0:
			break
		if _subdiv:
			var bb := _pb[i - 1]
			var tb := _pt[i - 1]
			var b_pre := _pb[i + 1] if i + 1 < n else ba
			var t_pre := _pt[i + 1] if i + 1 < n else ta
			var b_post := _pb[i - 2] if i >= 2 else bb
			var t_post := _pt[i - 2] if i >= 2 else tb
			var sb := _ps[i - 1]
			var dsub := ta.distance_to(tb)
			var ns := 2 if dsub < 0.45 else (4 if dsub < 1.0 else 6)   # 2 sub-samples normally; more on huge strides
			var inv := 1.0 / float(ns + 1)
			for k in ns:
				if m >= cap_c:
					break
				var w := (k + 1) * inv
				var bp := ba.cubic_interpolate(bb, b_pre, b_post, w)
				var tp := ta.cubic_interpolate(tb, t_pre, t_post, w)
				var fs := 1.0 - (_clock - lerpf(sa, sb, w)) * inv_life
				fs = fs * fs if fs > 0.0 else 0.0
				var oo := m * ROWS
				_fv[oo] = bp
				_fv[oo + 1] = bp + (tp - bp) * 0.55
				_fv[oo + 2] = tp
				_fc[oo] = c_edge | (int(ALPHA_BASE * fs * 255.0) << 24)
				_fc[oo + 1] = c_mid | (int(ALPHA_MID * fs * 255.0) << 24)
				_fc[oo + 2] = c_core | (int(ALPHA_TIP * fs * 255.0) << 24)
				m += 1
		i -= 1
	if m == 0:
		return
	# collapse remaining previously-used columns onto the last live one, fully transparent
	var end := mini(maxi(_written, m), cap_c)
	var o2 := (m - 1) * ROWS
	for c in range(m, end):
		var oo := c * ROWS
		_fv[oo] = _fv[o2]
		_fv[oo + 1] = _fv[o2 + 1]
		_fv[oo + 2] = _fv[o2 + 2]
		_fc[oo] = 0
		_fc[oo + 1] = 0
		_fc[oo + 2] = 0
	_written = m
	var rid := _ribbon.mesh.get_rid()
	RenderingServer.mesh_surface_update_vertex_region(rid, 0, 0, _fv.to_byte_array())
	RenderingServer.mesh_surface_update_attribute_region(rid, 0, 0, _fc.to_byte_array())
