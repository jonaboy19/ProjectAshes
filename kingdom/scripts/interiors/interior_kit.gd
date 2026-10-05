extends RefCounted
## InteriorKit (package F6): the building blocks of the modular interiors. Everything is an axis box (or a box turned
## about Y) baked into ONE vertex-coloured mesh per material, so a whole room (shell, openings, furniture) costs
## four draw calls: "solid" (vertex colours), "glass" (window panes, emissive, driven by the time of day),
## "fire" (hearth and oven glow) and "lamp" (hanging lamps), all emissive. Colliders are plain boxes collected beside the geometry.
##
##   var kit := InteriorKit.new()
##   kit.box(centre, size, colour [, material, yaw])
##   kit.wall(a, b, height, thickness, openings, colour)     # 2D a..b on the floor plan, openings cut gaps
##   kit.build(parent) -> {"solid": MeshInstance3D, ...}      # also adds the StaticBody3D "Colliders"
##
## Preload this script; no class_name.

const WALL_T := 0.22

var _surf := {}          # material key -> {v, n, c, i}
var colliders: Array = []   # [centre: Vector3, size: Vector3, yaw: float]
var materials := {}      # material key -> StandardMaterial3D (after build)
var box_count := 0


## One box. `yaw` turns it about Y around its centre. Faces are shaded a little (top light, bottom dark) so flat
## colours still read as volumes under the low ambient of an interior.
func box(centre: Vector3, size: Vector3, col: Color, mat := "solid", yaw := 0.0) -> void:
	var s: Dictionary = _surf.get(mat, {})
	if s.is_empty():
		s = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
		_surf[mat] = s
	var h := size * 0.5
	var basis := Basis(Vector3.UP, yaw)
	var faces := [
		[Vector3.UP, 1.12, [Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3.DOWN, 0.55, [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z)]],
		[Vector3.FORWARD, 0.88, [Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z)]],
		[Vector3.BACK, 0.96, [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3.LEFT, 0.8, [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z)]],
		[Vector3.RIGHT, 0.8, [Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z)]],
	]
	var verts: PackedVector3Array = s["v"]
	var norms: PackedVector3Array = s["n"]
	var cols: PackedColorArray = s["c"]
	var idx: PackedInt32Array = s["i"]
	for f: Array in faces:
		var base := verts.size()
		var n: Vector3 = basis * (f[0] as Vector3)
		var shade: float = f[1]
		for corner: Vector3 in f[2]:
			verts.append(centre + basis * corner)
			norms.append(n)
			cols.append(Color(col.r * shade, col.g * shade, col.b * shade, col.a))
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	s["v"] = verts
	s["n"] = norms
	s["c"] = cols
	s["i"] = idx
	box_count += 1


## A box that also blocks: furniture, walls, floors.
func solid(centre: Vector3, size: Vector3, col: Color, mat := "solid", yaw := 0.0) -> void:
	box(centre, size, col, mat, yaw)
	collider(centre, size, yaw)


func collider(centre: Vector3, size: Vector3, yaw := 0.0) -> void:
	colliders.append([centre, size, yaw])


## A wall along the floor-plan line a..b (Vector2: x, z) from `y0` up to `y1`. `openings` = [{at: metres along a..b,
## w: width, y0, y1}] cut gaps; the wood above and below a gap is still built. Collision is the full length except
## where an opening reaches the floor (a doorway), so doorways stay walkable.
func wall(a: Vector2, b: Vector2, y1: float, col: Color, openings: Array = [], thick := WALL_T, y0 := 0.0) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.05:
		return
	dir /= length
	var yaw := -atan2(dir.y, dir.x)
	var cuts: Array = openings.duplicate()
	cuts.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["at"]) < float(q["at"]))
	var t := 0.0
	for o: Dictionary in cuts:
		var o0 := clampf(float(o["at"]) - float(o["w"]) * 0.5, 0.0, length)
		var o1 := clampf(float(o["at"]) + float(o["w"]) * 0.5, 0.0, length)
		if o0 > t:
			_wall_piece(a, dir, t, o0, y0, y1, thick, col, yaw, true)
		var oy0 := float(o.get("y0", 0.0))
		var oy1 := float(o.get("y1", 2.1))
		if oy0 > y0 + 0.02:
			_wall_piece(a, dir, o0, o1, y0, oy0, thick, col, yaw, true)
		if oy1 < y1 - 0.02:
			_wall_piece(a, dir, o0, o1, oy1, y1, thick, col, yaw, oy0 > y0 + 0.02)
		t = maxf(t, o1)
	if t < length:
		_wall_piece(a, dir, t, length, y0, y1, thick, col, yaw, true)


func _wall_piece(a: Vector2, dir: Vector2, t0: float, t1: float, y0: float, y1: float, thick: float, col: Color, yaw: float, blocks: bool) -> void:
	if t1 - t0 < 0.02 or y1 - y0 < 0.02:
		return
	var mid := a + dir * ((t0 + t1) * 0.5)
	var centre := Vector3(mid.x, (y0 + y1) * 0.5, mid.y)
	var size := Vector3(t1 - t0, y1 - y0, thick)
	if blocks:
		solid(centre, size, col, "solid", yaw)
	else:
		box(centre, size, col, "solid", yaw)


## The mesh instances (one per material) under `parent`, and a StaticBody3D "Colliders" with the boxes.
## Glass and fire get emissive materials (kept in `materials` so the light driver can change them).
func build(parent: Node3D) -> Dictionary:
	var out := {}
	for key: String in _surf:
		var s: Dictionary = _surf[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s["v"]
		arrays[Mesh.ARRAY_NORMAL] = s["n"]
		arrays[Mesh.ARRAY_COLOR] = s["c"]
		arrays[Mesh.ARRAY_INDEX] = s["i"]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.92
		match key:
			"glass":
				m.emission_enabled = true
				m.emission = Color(1.0, 0.95, 0.8)
				m.emission_energy_multiplier = 1.4
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			"lamp":
				m.emission_enabled = true
				m.emission = Color(1.0, 0.8, 0.45)
				m.emission_energy_multiplier = 1.8
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			"fire":
				m.emission_enabled = true
				m.emission = Color(1.0, 0.55, 0.2)
				m.emission_energy_multiplier = 2.2
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.surface_set_material(0, m)
		materials[key] = m
		var mi := MeshInstance3D.new()
		mi.name = "Kit_" + key
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		out[key] = mi
	if not colliders.is_empty():
		var body := StaticBody3D.new()
		body.name = "Colliders"
		parent.add_child(body)
		for c: Array in colliders:
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = c[1]
			cs.shape = bs
			cs.position = c[0]
			cs.rotation.y = float(c[2])
			body.add_child(cs)
	return out
