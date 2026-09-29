extends Node
## Cape (or banner / tabard / long hair sheet) on a UAL character with SpringBoneSimulator3D.
## The UAL skeleton has no cloth bones, so this adds a small chain grid at runtime:
##   - `columns` chains of `segments` bones each, parented to `anchor` (spine_03), hanging down the back
##   - a skinned ArrayMesh (double sided, one draw call, ~50 tris) bound to those bones
##   - one SpringBoneSimulator3D (one setting per chain) + a body collision capsule so the cloth
##     does not sink into the back while the character leans / runs
## Everything is created in code, so any humanoid with the standard bone names gets a cape.
##
##   const Cape := preload("res://tools_qa/anim_tech/lib/cape.gd")
##   var cape := Cape.attach(model, Color(0.75, 0.12, 0.15))     # returns the Cape node (or null)
##   cape.wind = Vector3(2, 0, 0)         # external force (m/s^2-ish), e.g. from a wind zone
##   cape.active = false                  # LOD: springs off AND mesh hidden (or swap to a static cape)
## Tuning (stiffness / drag / gravity) are exported; defaults give a heavy-cloth look that trails
## behind at a jog and swings forward when the character stops.
## Modifier order: put it LAST (after IK / lean / look-at) so it reacts to their final pose;
## `attach` appends it to the skeleton, and ProceduralRig keeps its own springs before/after.

const U := preload("res://tools_qa/anim_tech/lib/at_util.gd")

@export var anchor_bone := "spine_03"
@export var columns := 3
@export var segments := 4
@export var seg_len := 0.2            # m per segment (skeleton space)
@export var width := 0.52
@export var back_offset := 0.13       # m behind the anchor bone
@export var stiffness := 0.7
@export var drag := 0.18
@export var gravity := 1.0
@export var radius := 0.05
@export var wind := Vector3.ZERO:
	set(v):
		wind = v
		if _sim:
			_sim.external_force = v
var active := true:
	set(v):
		active = v
		if _sim:
			_sim.active = v
		if _mesh:
			_mesh.visible = v
var _sk: Skeleton3D
var _sim: SpringBoneSimulator3D
var _mesh: MeshInstance3D


static func attach(model: Node3D, color := Color(0.75, 0.12, 0.15)) -> Node:
	var sk := U.skeleton_of(model)
	if sk == null or sk.find_bone("spine_03") < 0:
		return null
	var c: Node = (load("res://tools_qa/anim_tech/lib/cape.gd") as GDScript).new()
	c.name = "Cape"
	sk.add_child(c)
	c._build(sk, color)
	return c


func _build(sk: Skeleton3D, color: Color) -> void:
	_sk = sk
	var anchor := sk.find_bone(anchor_bone)
	var a_rest := sk.get_bone_global_rest(anchor)
	# skeleton-space top-centre of the cape, behind the anchor (model faces +Z, so back is -Z)
	var top := a_rest.origin + Vector3(0.0, 0.03, -back_offset)
	var names: Array[String] = []          # bone names in chain order: chain0 seg0..n, chain1 ...
	var origins: Array[Vector3] = []
	var xs: Array[float] = []
	for c in columns:
		var x := (float(c) / maxf(columns - 1, 1) - 0.5) * (width * (columns - 1) / float(columns))
		xs.append(x)
		var parent := anchor
		var parent_global := a_rest
		for s in segments:
			var n := "cape_%d_%d" % [c, s]
			var o := top + Vector3(x, -seg_len * s, 0.0)
			sk.add_bone(n)
			var b := sk.find_bone(n)
			sk.set_bone_parent(b, parent)
			var g := Transform3D(Basis.IDENTITY, o)
			sk.set_bone_rest(b, parent_global.affine_inverse() * g)
			sk.reset_bone_pose(b)
			parent = b
			parent_global = g
			names.append(n)
			origins.append(o)
	_build_mesh(names, origins, xs, color)
	_sim = SpringBoneSimulator3D.new()
	_sim.name = "CapeSprings"
	_sim.setting_count = columns
	for c in columns:
		_sim.set_root_bone_name(c, names[c * segments])
		_sim.set_end_bone_name(c, names[c * segments + segments - 1])
		_sim.set_extend_end_bone(c, true)
		_sim.set_end_bone_direction(c, SkeletonModifier3D.BONE_DIRECTION_MINUS_Y)
		_sim.set_end_bone_length(c, seg_len)
		_sim.set_radius(c, radius)
		_sim.set_stiffness(c, stiffness)
		_sim.set_drag(c, drag)
		_sim.set_gravity(c, gravity)
		_sim.set_gravity_direction(c, Vector3.DOWN)
		_sim.set_rotation_axis(c, SkeletonModifier3D.ROTATION_AXIS_ALL)
	_sim.external_force = wind
	# body collider: capsule down the spine so the cloth rests on the back instead of inside it
	var col := SpringBoneCollisionCapsule3D.new()
	col.name = "BackCollider"
	col.bone_name = "spine_02"
	col.radius = 0.15
	col.height = 0.55
	col.position_offset = Vector3(0.0, 0.0, 0.0)
	_sim.add_child(col)
	_sk.add_child(_sim)


func _build_mesh(names: Array[String], origins: Array[Vector3], xs: Array[float], color: Color) -> void:
	var rows := segments + 1
	var cols := columns * 2 + 1                       # vertex columns (extra between chains)
	var top: Vector3 = origins[0]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var half := width * 0.5 + 0.02
	var sp := absf(xs[1] - xs[0]) if xs.size() > 1 else width
	for r in rows:
		for c in cols:
			var x := lerpf(-half, half, float(c) / (cols - 1))
			var y := top.y - seg_len * r
			verts.append(Vector3(x + (xs[0] - xs[0]), y, top.z))
			normals.append(Vector3(0, 0, -1))
			# weights: each chain contributes by horizontal distance, bone = the segment at this row
			var w: Array[float] = []
			var tot := 0.0
			for k in columns:
				var v := maxf(1.0 - absf(x - xs[k]) / (sp + 0.001), 0.0)
				w.append(v)
				tot += v
			var ids: Array[int] = []
			var ws: Array[float] = []
			for k in columns:
				if w[k] > 0.0:
					ids.append(k * segments + mini(r, segments - 1))
					ws.append(w[k] / tot)
			while ids.size() < 4:
				ids.append(0)
				ws.append(0.0)
			for i in 4:
				bones.append(ids[i])
				weights.append(ws[i])
	var idx := PackedInt32Array()
	for r in rows - 1:
		for c in cols - 1:
			var i0 := r * cols + c
			idx.append_array([i0, i0 + 1, i0 + cols, i0 + 1, i0 + cols + 1, i0 + cols])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var skin := Skin.new()
	for i in names.size():
		skin.add_named_bind(names[i], Transform3D(Basis.IDENTITY, -origins[i]))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.85
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mesh.surface_set_material(0, mat)
	_mesh = MeshInstance3D.new()
	_mesh.name = "CapeMesh"
	_mesh.mesh = mesh
	_mesh.skin = skin
	_sk.add_child(_mesh)
	_mesh.skeleton = _mesh.get_path_to(_sk)
	_mesh.extra_cull_margin = 2.0


func _exit_tree() -> void:
	for n: Node in [_sim, _mesh]:
		if is_instance_valid(n):
			n.queue_free()
