extends Node3D
## Far horizon for Region 1 (docs/regions/LOOK_R1.md): the streamed terrain ends 128-320 m from the player
## (Quality view_radius), so hills, the valley walls and the vale beyond used to stop at a blue void.
## This draws the WHOLE world once, cheaply, outside the streamed ring:
##   * one ground mesh on a 48 m grid (~58k tris, one draw call) coloured from WorldGen.color_at weights,
##     water on its level; the part under the streamed chunks is discarded in the shader, so there is no overlap;
##   * canopy blobs (32-tri painted domes) wherever the forest is dense, in 512 m MultiMesh cells with a
##     visibility range, hidden inside the ring (the real trees are there).
## Built on a WorkerThreadPool task (pure WorldGen maths, no resource loading) and turned into meshes on the
## main thread in one go. Per frame: two shader parameters.

const HALF := 4096.0
const CELL := 48.0
const BLOB_STEP := 26.0
const BLOB_CELL := 512.0
const GRASS := Color(0.42, 0.6, 0.22)
const FOREST := Color(0.2, 0.34, 0.14)
const PATH := Color(0.62, 0.52, 0.34)
const ROCK := Color(0.6, 0.55, 0.46)
const COBBLE := Color(0.66, 0.58, 0.46)
const WATER := Color(0.3, 0.56, 0.72)

var _task := -1
var _result: Dictionary = {}
var _ground_mat: ShaderMaterial
var _blob_mat: ShaderMaterial
var _terrain: Node
var _built := false
## LOW keeps the ground and trims the canopy range.
var blob_range := 2200.0
## Biome map (set by Region1Look) for the far ground tint and fields.
var biome: Texture2D:
	set(v):
		biome = v
		if _ground_mat:
			_ground_mat.set_shader_parameter("region_biome", v)


func _ready() -> void:
	name = "Region1Horizon"
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = preload("res://shaders/region1/horizon_ground.gdshader")
	_blob_mat = ShaderMaterial.new()
	_blob_mat.shader = preload("res://shaders/region1/horizon_canopy.gdshader")
	var q := get_node_or_null("/root/Quality")
	if q and int(q.get("view_radius")) <= 2:
		blob_range = 1100.0
	_task = WorkerThreadPool.add_task(_work, false, "region1 horizon")


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func is_built() -> bool:
	return _built


## Blocks until the horizon exists (capture tools, teleports).
func build_now() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_finish()


func _process(_d: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_finish()
	if not _built:
		return
	if _terrain == null or not is_instance_valid(_terrain):
		_terrain = _find_terrain()
		if _terrain == null:
			return
	var f: Vector3 = _terrain.get("focus")
	var r := int(_terrain.get("view_radius"))
	var c := Vector2i(floori(f.x / 64.0), floori(f.z / 64.0))
	var rmin := Vector2((c.x - r) * 64.0, (c.y - r) * 64.0)
	var rmax := Vector2((c.x + r + 1) * 64.0, (c.y + r + 1) * 64.0)
	_ground_mat.set_shader_parameter("ring_min", rmin)
	_ground_mat.set_shader_parameter("ring_max", rmax)
	_blob_mat.set_shader_parameter("ring_min", rmin - Vector2(6, 6))
	_blob_mat.set_shader_parameter("ring_max", rmax + Vector2(6, 6))


func _find_terrain() -> Node:
	var w := get_parent()
	while w != null:
		for ch in w.get_children():
			if ch is TerrainStreamer:
				return ch
		w = w.get_parent()
	return null


# --- Worker ---------------------------------------------------------------------------

func _work() -> void:
	var n := int(HALF * 2.0 / CELL) + 1
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(n * n)
	cols.resize(n * n)
	var hs := PackedFloat32Array()
	hs.resize(n * n)
	for j in n:
		for i in n:
			var x := -HALF + i * CELL
			var z := -HALF + j * CELL
			hs[j * n + i] = WorldGen.height(x, z)
	for j in n:
		for i in n:
			var x := -HALF + i * CELL
			var z := -HALF + j * CELL
			var h := hs[j * n + i]
			var hx := hs[j * n + mini(i + 1, n - 1)] - hs[j * n + maxi(i - 1, 0)]
			var hz := hs[mini(j + 1, n - 1) * n + i] - hs[maxi(j - 1, 0) * n + i]
			var nrm := Vector3(-hx, 2.0 * CELL, -hz).normalized()
			var w := WorldGen.color_at(x, z, h, 1.0 - nrm.y)
			w.g = maxf(w.g, smoothstep(0.3, 0.5, 1.0 - nrm.y))
			var wg := maxf(0.0, 1.0 - (w.r + w.g + w.b + w.a))
			var tot := wg + w.r + w.g + w.b + w.a + 0.0001
			var col := (GRASS * wg + PATH * w.r + ROCK * w.g + COBBLE * w.b + FOREST * w.a) / tot
			var lv := WorldGen.water_level_at(x, z)
			if not is_nan(lv) and lv > h + 0.1:
				col = WATER
				h = lv
			col.a = 1.0
			verts[j * n + i] = Vector3(x, h, z)
			cols[j * n + i] = col
	var idx := PackedInt32Array()
	idx.resize((n - 1) * (n - 1) * 6)
	var k := 0
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			var b := a + 1
			var c := a + n
			var d := c + 1
			idx[k] = a; idx[k + 1] = b; idx[k + 2] = c
			idx[k + 3] = b; idx[k + 4] = d; idx[k + 5] = c
			k += 6
	# Canopy blobs where the forest is dense.
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var blobs: Dictionary = {}          # Vector2i cell -> PackedFloat32Array [x, y, z, sx, sy, tint] * n
	var bz := -HALF + BLOB_STEP * 0.5
	while bz < HALF:
		var bx := -HALF + BLOB_STEP * 0.5
		while bx < HALF:
			var px := bx + rng.randf_range(-0.4, 0.4) * BLOB_STEP
			var pz := bz + rng.randf_range(-0.4, 0.4) * BLOB_STEP
			var f := WorldGen.forest_density(px, pz)
			if f > 0.3 and rng.randf() < f:
				var key := Vector2i(floori(px / BLOB_CELL), floori(pz / BLOB_CELL))
				if not blobs.has(key):
					blobs[key] = PackedFloat32Array()
				var arr: PackedFloat32Array = blobs[key]
				var s := rng.randf_range(8.5, 13.0)
				arr.append_array(PackedFloat32Array([px, WorldGen.height(px, pz) + s * 0.55, pz, s, s * rng.randf_range(0.7, 1.05), rng.randf()]))
				blobs[key] = arr
			bx += BLOB_STEP
		bz += BLOB_STEP
	_result = {"n": n, "verts": verts, "cols": cols, "idx": idx, "blobs": blobs}


# --- Main thread ----------------------------------------------------------------------

func _finish() -> void:
	if _result.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _result["verts"]
	arrays[Mesh.ARRAY_COLOR] = _result["cols"]
	arrays[Mesh.ARRAY_INDEX] = _result["idx"]
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "HorizonGround"
	mi.mesh = mesh
	mi.material_override = _ground_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.custom_aabb = AABB(Vector3(-HALF, -50, -HALF), Vector3(HALF * 2, 500, HALF * 2))
	add_child(mi)
	var blob := _blob_mesh()
	var count := 0
	var blobs: Dictionary = _result["blobs"]
	for key: Vector2i in blobs:
		var arr: PackedFloat32Array = blobs[key]
		var m := arr.size() / 6
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = blob
		mm.instance_count = m
		for i in m:
			var o := i * 6
			var b := Basis().scaled(Vector3(arr[o + 3], arr[o + 4], arr[o + 3]))
			mm.set_instance_transform(i, Transform3D(b, Vector3(arr[o], arr[o + 1], arr[o + 2])))
			mm.set_instance_custom_data(i, Color(arr[o + 5], 0, 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _blob_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mmi.visibility_range_end = blob_range
		mmi.visibility_range_end_margin = 150.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
		count += m
	_result.clear()
	_built = true
	print("Region1Horizon: ground %dx%d, %d canopy blobs in %d cells" % [mi.mesh.get_faces().size() / 3, 1, count, blobs.size()])


## A painted canopy dome (30 tris): unit radius, 6 sides x 2 bands + a cap, vertex colour dark at the base, sunlit at the top.
static func _blob_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 6
	var rings := [[-0.5, 0.8], [0.15, 1.0], [0.7, 0.55]]
	var pts: Array = []
	for r: Array in rings:
		var ring := []
		for i in sides:
			var a := TAU * i / sides
			ring.append(Vector3(cos(a) * r[1], r[0], sin(a) * r[1]))
		pts.append(ring)
	var top := Vector3(0, 1.0, 0)
	for ri in rings.size() - 1:
		for i in sides:
			var a: Vector3 = pts[ri][i]
			var b: Vector3 = pts[ri][(i + 1) % sides]
			var c: Vector3 = pts[ri + 1][i]
			var d: Vector3 = pts[ri + 1][(i + 1) % sides]
			for v: Vector3 in [a, c, b, b, c, d]:
				st.set_color(Color(0.5 + v.y * 0.5, 0, 0))
				st.set_normal(v.normalized())
				st.add_vertex(v)
	for i in sides:
		var a: Vector3 = pts[rings.size() - 1][i]
		var b: Vector3 = pts[rings.size() - 1][(i + 1) % sides]
		for v: Vector3 in [a, top, b]:
			st.set_color(Color(0.5 + v.y * 0.5, 0, 0))
			st.set_normal(v.normalized())
			st.add_vertex(v)
	return st.commit()
