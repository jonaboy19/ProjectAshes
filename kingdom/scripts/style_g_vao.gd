extends RefCounted
## Style G vertex AO bake (2026-10-01): writes ambient occlusion into COLOR.a of a static mesh so the polished
## shaders (`vao_strength`) darken jetty undersides, window reveals, eaves and the crease where timber meets plaster.
## Method: voxelise the mesh's own triangles (0.25 m grid), then from each vertex march 12 hemisphere rays 6 cells.
## COLOR.rgb is kept (white when the mesh had no vertex colours). Cached per source mesh; ~0.5-2 s per 13k-tri house
## in GDScript, so bake at load / in tools, never per frame.
##   mesh = StyleGVao.baked(mesh)

const CELL := 0.25
const STEPS := 6
const DIRS := 12

static var _cache := {}


static func baked(src: Mesh) -> Mesh:
	if src == null:
		return src
	var key := src.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var aabb := src.get_aabb().grow(CELL * 2.0)
	var dim := Vector3i(ceili(aabb.size.x / CELL), ceili(aabb.size.y / CELL), ceili(aabb.size.z / CELL))
	if dim.x * dim.y * dim.z > 4_000_000:
		_cache[key] = src
		return src
	var grid := PackedByteArray()
	grid.resize(dim.x * dim.y * dim.z)
	var surfaces := []
	for si in src.get_surface_count():
		var a := src.surface_get_arrays(si)
		surfaces.append(a)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var n := idx.size() if idx.size() > 0 else v.size()
		for t in range(0, n, 3):
			var p0 := v[idx[t] if idx.size() > 0 else t]
			var p1 := v[idx[t + 1] if idx.size() > 0 else t + 1]
			var p2 := v[idx[t + 2] if idx.size() > 0 else t + 2]
			var span := maxf((p1 - p0).length(), (p2 - p0).length())
			var k := clampi(ceili(span / (CELL * 0.7)), 1, 40)
			for i in k + 1:
				for j in k + 1 - i:
					var p := p0 + (p1 - p0) * (float(i) / k) + (p2 - p0) * (float(j) / k)
					var c := Vector3i(((p - aabb.position) / CELL).floor())
					grid[(c.z * dim.y + c.y) * dim.x + c.x] = 1
	var dirs := []
	var golden := PI * (3.0 - sqrt(5.0))
	for i in DIRS:
		var y := 1.0 - (float(i) + 0.5) / DIRS          # upper hemisphere of the local frame
		var r := sqrt(1.0 - y * y)
		dirs.append(Vector3(cos(golden * i) * r, y, sin(golden * i) * r))
	var out := ArrayMesh.new()
	for si in surfaces.size():
		var a: Array = surfaces[si]
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var cols: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		if cols.size() != v.size():
			cols = PackedColorArray()
			cols.resize(v.size())
			cols.fill(Color.WHITE)
		for vi in v.size():
			var nn := nrm[vi] if nrm.size() == v.size() else Vector3.UP
			var b := Basis.looking_at(nn if absf(nn.y) < 0.99 else Vector3(0.01, nn.y, 0.0), Vector3.UP if absf(nn.y) < 0.99 else Vector3.FORWARD)
			var o := v[vi] + nn * (CELL * 0.8)
			var open := 0.0
			for d: Vector3 in dirs:
				var w := b * Vector3(d.x, d.z, -d.y)         # local +y -> -z (looking_at forward) = along the normal
				var hit := false
				for s in range(1, STEPS + 1):
					var p := o + w * (CELL * s)
					var c := Vector3i(((p - aabb.position) / CELL).floor())
					if c.x < 0 or c.y < 0 or c.z < 0 or c.x >= dim.x or c.y >= dim.y or c.z >= dim.z:
						break
					if grid[(c.z * dim.y + c.y) * dim.x + c.x] != 0:
						hit = true
						break
				if not hit:
					open += 1.0
			var col := cols[vi]
			col.a = clampf(0.35 + 0.65 * open / DIRS, 0.0, 1.0)
			cols[vi] = col
		a[Mesh.ARRAY_COLOR] = cols
		var lods := {}
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], lods)
		out.surface_set_material(si, src.surface_get_material(si))
	_cache[key] = out
	return out
