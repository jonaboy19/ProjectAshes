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

## W6: the real world draws its whole 32 km at a 160 m grid (same ~42k vertices); canopy blobs cover the Valencious box.
static var HALF := 6144.0
static var CELL := 72.0              # 48 m on the 8 km world: same ~58k triangles over a 2.25x larger map
const BLOB_HALF := 6144.0
const BLOB_STEP := 42.0          # 34 m before the 12 km world (canopy domes are culled by range, so frame cost is unchanged)
const BLOB_CELL := 512.0
const GRASS := Color(0.42, 0.6, 0.22)
const FOREST := Color(0.2, 0.34, 0.14)
const PATH := Color(0.62, 0.52, 0.34)
const ROCK := Color(0.6, 0.55, 0.46)
const COBBLE := Color(0.66, 0.58, 0.46)
const WATER := Color(0.3, 0.56, 0.72)
## Far-ground colour per WorldBiomes id: grass forest meadow farmland marsh highland rift snow.
const BIOME_COL := [Color(0.42, 0.6, 0.22), Color(0.3, 0.46, 0.18), Color(0.46, 0.66, 0.24), Color(0.56, 0.62, 0.28), Color(0.32, 0.44, 0.24),
	Color(0.5, 0.5, 0.3), Color(0.26, 0.2, 0.3), Color(0.88, 0.9, 0.95)]

var _task := -1
var _result: Dictionary = {}
var _ground_mat: ShaderMaterial
var _blob_mat: ShaderMaterial
var _terrain: Node
var _built := false
const MASK_R := 8
const MASK_N := 17
var _mask_img := Image.create(MASK_N, MASK_N, false, Image.FORMAT_R8)
var _mask_tex: ImageTexture
var _mask_sig := 0
var _ground_mask_sig := 0
var _ground_mask_img: Image
var _ground_mask_tex: ImageTexture
## Full-region removal needs a rendered boundary/coverage solution: the first
## matched capture exposed a far-ground gap. Keep it opt-in for investigation.
var _region_ground_mask := OS.get_cmdline_user_args().has("--qa_horizon_region_mask")
## LOW keeps the ground and trims the canopy range.
var blob_range := 1700.0
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
		blob_range = 0.0          # LOW: ground only (canopy domes cost ~3 ms on the LOW A/B, docs/regions/look/PERF.md)
	_mask_tex = ImageTexture.create_from_image(_mask_img)
	for mat: ShaderMaterial in [_ground_mat, _blob_mat]:
		mat.set_shader_parameter("built_mask", _mask_tex)
		mat.set_shader_parameter("mask_cells", float(MASK_N))
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
	# The far mesh gives way only where a streamed chunk is really built (a mask of the chunks around the focus),
	# not over the whole nominal ring: while a fast camera (cutscene, teleport) outruns the streamer, the ring used to
	# show a void with canopy domes hovering over it.
	var chunks: Dictionary = _terrain.get("_chunks")
	var f: Vector3 = _terrain.get("focus")
	var c := Vector2i(floori(f.x / 64.0), floori(f.z / 64.0))
	if _region_ground_mask:
		_update_ground_mask(f)
	# Membership can change without a count change while chunks stream in/out.
	var membership: Array = []
	for key: Vector2i in chunks:
		membership.append([key, is_instance_valid(chunks[key])])
	var sig := hash([c, membership])
	if sig == _mask_sig:
		return
	_mask_sig = sig
	var o := c - Vector2i(MASK_R, MASK_R)
	_mask_img.fill(Color(0, 0, 0))
	for key: Vector2i in chunks:
		var m := key - o
		if m.x >= 0 and m.y >= 0 and m.x < MASK_N and m.y < MASK_N and is_instance_valid(chunks[key]):
			_mask_img.set_pixel(m.x, m.y, Color(1, 0, 0))
	_mask_tex.update(_mask_img)
	var origin := Vector2(o.x * 64.0, o.y * 64.0)
	_blob_mat.set_shader_parameter("mask_origin", origin)
	if not _region_ground_mask or _terrain.get("_bridge") == null:
		_ground_mat.set_shader_parameter("built_mask", _mask_tex)
		_ground_mat.set_shader_parameter("mask_cells", float(MASK_N))
		_ground_mat.set_shader_parameter("mask_origin", origin)


## Terrain3D ground spans a larger footprint than the vegetation/collision chunks.
## Give ground its own mask; canopy must still wait for real vegetation chunks.
func _update_ground_mask(focus: Vector3) -> void:
	var bridge := _terrain.get("_bridge") as Terrain3DBridge
	if bridge == null:
		return
	var center := Terrain3DBridge.region_of(focus.x, focus.z)
	# The bridge retains radius + 1; one extra region covers center alignment.
	var radius := bridge.region_radius + 2
	var regions: Array[Vector2i] = []
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var loc := center + Vector2i(dx, dz)
			var at := Terrain3DBridge.region_origin(loc)
			if bridge.has_region_at(at.x + 1.0, at.y + 1.0):
				regions.append(loc)
	var sig := hash([center, radius, regions])
	if sig == _ground_mask_sig:
		return
	_ground_mask_sig = sig
	var cells_per_region := int(Terrain3DBridge.region_m() / 64.0)
	var count := (radius * 2 + 1) * cells_per_region
	var origin_region := center - Vector2i(radius, radius)
	_ground_mask_img = Image.create(count, count, false, Image.FORMAT_R8)
	_ground_mask_img.fill(Color.BLACK)
	for loc: Vector2i in regions:
		var cell := (loc - origin_region) * cells_per_region
		_ground_mask_img.fill_rect(Rect2i(cell, Vector2i(cells_per_region, cells_per_region)), Color.WHITE)
	if _ground_mask_tex == null or _ground_mask_tex.get_width() != count:
		_ground_mask_tex = ImageTexture.create_from_image(_ground_mask_img)
	else:
		_ground_mask_tex.update(_ground_mask_img)
	_ground_mat.set_shader_parameter("built_mask", _ground_mask_tex)
	_ground_mat.set_shader_parameter("mask_cells", float(count))
	_ground_mat.set_shader_parameter("mask_origin", Vector2(origin_region) * Terrain3DBridge.region_m())


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
	HALF = 16384.0 if WorldMacro.is_real() else 6144.0
	CELL = 160.0 if WorldMacro.is_real() else 72.0
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
			if CELL > 100.0:
				# W6: the 160 m grid would cut straight across the real valleys and poke through the streamed Terrain3D ground:
				# sit each vertex on the lowest ground of its cell (and 5 m under it) so the far mesh always stays beneath.
				var lo := hs[j * n + i]
				for o: Vector2 in [Vector2(-0.5, 0), Vector2(0.5, 0), Vector2(0, -0.5), Vector2(0, 0.5), Vector2(-0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5), Vector2(0.5, -0.5)]:
					lo = minf(lo, WorldGen.height(x + o.x * CELL, z + o.y * CELL))
				hs[j * n + i] = lo - 5.0
	var lvs := PackedFloat32Array()
	lvs.resize(n * n)
	for j in n:
		for i in n:
			lvs[j * n + i] = WorldGen.water_level_at(-HALF + i * CELL, -HALF + j * CELL)
	var raised := _raised_water(lvs, hs, n)
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
			if WorldBiomes.active():
				# W5: colour from the SOFT biome field (150 m blends) instead of color_at's hard 12 m biome ids, which drew hard-edged polygon patches
				# at distance. Road / rock / cobble weights still win where they exist.
				var sw := WorldBiomes.soft_weights(x, z)
				var bc := Color(0, 0, 0)
				for bi in 8:
					bc += (BIOME_COL[bi] as Color) * sw[bi]
				var open := clampf(1.0 - (w.r + w.g + w.b), 0.0, 1.0)
				col = col.lerp(PATH, 0.0).lerp(bc, open * 0.9)
				if WorldMacro.is_real():
					# W6: the same layering as the streamed ground (Terrain3DBridge.real_layers) so far fells match near ones.
					var sw2 := WorldBiomes.soft_weights(x, z)
					var mm := WorldBiomes.ground_mix(sw2, 0.5)
					var ly := Terrain3DBridge.real_layers(x, z, h, 1.0 - nrm.y, mm, 1.0, Terrain3DBridge.snow_line(z))
					# Colours sampled to match the streamed Terrain3D slots under the real-world grade (no pastel far fells).
					col = col.lerp(Color(0.36, 0.5, 0.2), 0.6)
					col = col.lerp(BIOME_COL[2], clampf(float(ly[0]), 0.0, 1.0) * 0.5)
					col = col.lerp(Color(0.3, 0.36, 0.18), clampf(float(ly[6]), 0.0, 1.0) * 0.6)
					col = col.lerp(Color(0.5, 0.47, 0.36), clampf(float(ly[5]), 0.0, 1.0) * 0.7)
					col = col.lerp(Color(0.45, 0.44, 0.42), clampf(float(ly[7]), 0.0, 1.0))
					col = col.lerp(Color(0.86, 0.9, 0.96), clampf(float(ly[4]), 0.0, 1.0))
			var lv := lvs[j * n + i]
			if not is_nan(lv) and lv > h + 0.1:
				# Water only where the whole neighbourhood is water or higher ground (see _water_interior): a river is far
				# narrower than this 72 m grid, so a lone raised vertex used to become a flat blue slab hanging over the lower
				# ground beside it. Shore vertices keep their ground height and only tint, a soft edge.
				if raised[j * n + i] == 1:
					col = WATER
					h = lv
				else:
					col = col.lerp(WATER, 0.45)
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
	var real := WorldMacro.is_real()
	var area := RealWorld.box() if real else Rect2(-BLOB_HALF, -BLOB_HALF, BLOB_HALF * 2.0, BLOB_HALF * 2.0)
	var bz := area.position.y + BLOB_STEP * 0.5
	while bz < area.end.y:
		var bx := area.position.x + BLOB_STEP * 0.5
		while bx < area.end.x:
			var px := bx + rng.randf_range(-0.4, 0.4) * BLOB_STEP
			var pz := bz + rng.randf_range(-0.4, 0.4) * BLOB_STEP
			var f := WorldGen.forest_density(px, pz)
			if real and f > 0.0:   # W6: the biome mix and the tree line decide the far woods too
				var hh := WorldGen.height(px, pz)
				f = WorldBiomes.tree_density(WorldBiomes.at(px, pz), f) * (1.0 - smoothstep(Terrain3DBridge.snow_line(pz) - 220.0, Terrain3DBridge.snow_line(pz) - 120.0, hh))
			if f > 0.3 and rng.randf() < f:
				var key := Vector2i(floori(px / BLOB_CELL), floori(pz / BLOB_CELL))
				if not blobs.has(key):
					blobs[key] = PackedFloat32Array()
				var arr: PackedFloat32Array = blobs[key]
				var s := rng.randf_range(8.5, 13.0)
				# Seat on the horizon mesh itself (48 m grid), not the exact ground: over bowls and rims the two differ by
				# tens of metres and the domes hovered ("void" frames in the Hidden Vale cutscene).
				var gy := _grid_h(hs, n, px, pz)
				arr.append_array(PackedFloat32Array([px, minf(gy, WorldGen.height(px, pz)) + s * 0.3, pz, s, s * rng.randf_range(0.7, 1.05), rng.randf()]))
				blobs[key] = arr
			bx += BLOB_STEP
		bz += BLOB_STEP
	_result = {"n": n, "verts": verts, "cols": cols, "idx": idx, "blobs": blobs}


## Which grid vertices are drawn raised to the water level: wet ones whose 8 neighbours are all raised themselves or ground at least as
## high as this vertex's water level (minus 0.5 m). Iterated until stable, so a raised vertex never has a lower dry or shore
## neighbour to hang over (a river is far narrower than this 72 m grid: its lone wet vertices stay on the ground and only tint).
static func _raised_water(lvs: PackedFloat32Array, hs: PackedFloat32Array, n: int) -> PackedByteArray:
	var r := PackedByteArray()
	r.resize(n * n)
	for k in n * n:
		r[k] = 1 if (not is_nan(lvs[k]) and lvs[k] > hs[k] + 0.1) else 0
	var changed := true
	while changed:
		changed = false
		for j in n:
			for i in n:
				var k := j * n + i
				if r[k] == 0:
					continue
				for dj in range(-1, 2):
					for di in range(-1, 2):
						var q := clampi(j + dj, 0, n - 1) * n + clampi(i + di, 0, n - 1)
						if r[q] == 0 and hs[q] < lvs[k] - 0.5:
							r[k] = 0
							changed = true
	return r


## Bilinear height of the horizon grid at (x, z).
static func _grid_h(hs: PackedFloat32Array, n: int, x: float, z: float) -> float:
	var fx := clampf((x + HALF) / CELL, 0.0, n - 1.001)
	var fz := clampf((z + HALF) / CELL, 0.0, n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	return lerpf(lerpf(hs[iz * n + ix], hs[iz * n + ix + 1], tx), lerpf(hs[(iz + 1) * n + ix], hs[(iz + 1) * n + ix + 1], tx), tz)


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
	if blob_range <= 0.0:
		(_result["blobs"] as Dictionary).clear()
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
	var rings := [[-1.0, 0.75], [0.15, 1.0], [0.7, 0.55]]
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
