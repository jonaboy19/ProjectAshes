extends RefCounted
## Procedural cave-wall kit: turns a dungeon layout (dungeon_gen.gd) into chunked wall/floor/ceiling
## meshes (one StaticBody3D per 6x6 cell chunk, faceted, triplanar rock texture, vertex-colour shading)
## plus a handful of tiny procedural prop meshes that are drawn with MultiMesh (stalagmites, crystals,
## bones, pebbles, pillars, urns, rubble). No Blender needed: the whole kit is ~60 lines of geometry.
##
## Cost: a 12-room dungeon is about 6-9k triangles and ~40 draw calls before props, so it stays
## inside the 150-draw budget of docs/design/SIM_HIERARCHY.md with creatures and lights on top.

const Gen := preload("res://scripts/interiors/dungeon_gen.gd")
const CHUNK := 8
const TEX := "res://assets/generated/region/textures/"
const PH_ROCK := "res://assets/incoming/polyhaven/textures/rock_face/rock_face_%s_1k.jpg"   # CC0 Poly Haven
const POOL_DEPTH := 0.85

static var _mats: Dictionary = {}


# ---------------------------------------------------------------------------------------------
# noise

static func _h01(ix: int, iz: int, salt: int, seed_value: int) -> float:
	var h: int = (ix * 73856093) ^ (iz * 19349663) ^ (salt * 83492791) ^ (seed_value * 2654435761)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


static func _open(g: Dictionary, x: int, z: int) -> bool:
	var side: int = g["w"]
	if x < 0 or z < 0 or x >= side or z >= side:
		return false
	return (g["cells"] as PackedByteArray)[z * side + x] != Gen.ROCK


static func _kind(g: Dictionary, x: int, z: int) -> int:
	var side: int = g["w"]
	if x < 0 or z < 0 or x >= side or z >= side:
		return Gen.ROCK
	return (g["cells"] as PackedByteArray)[z * side + x]


## Vertical noise of an organic floor in metres (was 0.35: at the camp's horizon the faceted floor edge looked curved and warped).
const FLOOR_BUMP := 0.14


## Vertex position for grid corner (ix, iz) at level 0 (floor), 1 (mid wall), 2 (ceiling).
static func vertex(g: Dictionary, ix: int, iz: int, lvl: int) -> Vector3:
	var side: int = g["w"]
	var sd: int = g["seed"]
	var organic: bool = g["organic"]
	var hr: Array = g["height"]
	var x := (ix - side * 0.5) * Gen.CELL
	var z := (iz - side * 0.5) * Gen.CELL
	# corners touch four cells: pool if any open neighbour is a pool; room-tall if any is a room
	var pool := false
	var room := false
	for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var k := _kind(g, ix + d.x, iz + d.y)
		if k == Gen.POOL:
			pool = true
		elif k == Gen.ROOM:
			room = true
	var y := 0.0
	if organic:
		var rough := 0.46 if lvl == 1 else (0.3 if lvl == 2 else 0.17)    # the floor is jittered least: a wavy floor edge read as a warped horizon
		x += (_h01(ix, iz, 1, sd) - 0.5) * Gen.CELL * rough * 2.0
		z += (_h01(ix, iz, 2, sd) - 0.5) * Gen.CELL * rough * 2.0
		if lvl == 1:
			x += (_h01(ix, iz, 7, sd) - 0.5) * Gen.CELL * 0.55
			z += (_h01(ix, iz, 8, sd) - 0.5) * Gen.CELL * 0.55
	var hmin: float = hr[0]
	var hmax: float = hr[1]
	var ceil_y := hmax if room else (hmin + hmax) * 0.5
	if organic:
		ceil_y = lerpf(hmin, hmax, _h01(ix, iz, 3, sd)) + (0.8 if room else 0.0)
	var floor_y := 0.0
	if organic:
		floor_y = (_h01(ix, iz, 4, sd) - 0.5) * FLOOR_BUMP
	if pool:
		floor_y = -POOL_DEPTH + (_h01(ix, iz, 5, sd) - 0.5) * 0.2
	match lvl:
		0:
			y = floor_y
		1:
			y = lerpf(floor_y, ceil_y, 0.5) + ((_h01(ix, iz, 6, sd) - 0.5) * 0.9 if organic else 0.0)
		_:
			y = ceil_y
	return Vector3(x, y, z)


# ---------------------------------------------------------------------------------------------
# chunked level mesh

class Acc:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()


static func _tri(acc: Acc, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-9:
		return
	n = n.normalized()
	# Godot's front face is clockwise: emit (a, c, b) while `n` stays the counter-clockwise normal.
	acc.verts.append(a)
	acc.verts.append(c)
	acc.verts.append(b)
	acc.norms.append(n)
	acc.norms.append(n)
	acc.norms.append(n)
	acc.cols.append(ca)
	acc.cols.append(cc)
	acc.cols.append(cb)


## Wall strip given as (a_low, a_high, b_high, b_low); wound so the face looks into the open cell.
static func _wall(acc: Acc, al: Vector3, ah: Vector3, bh: Vector3, bl: Vector3, cal: Color, cah: Color, cbh: Color, cbl: Color) -> void:
	_quad(acc, al, bl, bh, ah, cal, cbl, cbh, cah)


static func _quad(acc: Acc, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_tri(acc, a, b, c, ca, cb, cc)
	_tri(acc, a, c, d, ca, cc, cd)


## Returns [{key: Vector2i, floor: ArrayMesh, shell: ArrayMesh, faces: PackedVector3Array}] covering the whole layout.
static func build_chunks(g: Dictionary) -> Array:
	var side: int = g["w"]
	var sd: int = g["seed"]
	var tint: Color = g["tint"] * 1.55
	var organic: bool = g["organic"]
	var shells := {}
	for z in range(side):
		for x in range(side):
			var k := _kind(g, x, z)
			if k == Gen.ROCK:
				continue
			var ck := Vector2i(x / CHUNK, z / CHUNK)
			if not shells.has(ck):
				shells[ck] = Acc.new()
			var sa: Acc = shells[ck]
			var fa: Acc = sa
			var f00 := vertex(g, x, z, 0)
			var f10 := vertex(g, x + 1, z, 0)
			var f11 := vertex(g, x + 1, z + 1, 0)
			var f01 := vertex(g, x, z + 1, 0)
			var c00 := vertex(g, x, z, 2)
			var c10 := vertex(g, x + 1, z, 2)
			var c11 := vertex(g, x + 1, z + 1, 2)
			var c01 := vertex(g, x, z + 1, 2)
			var shade := 0.82 + 0.3 * _h01(x, z, 11, sd)
			var fcol := tint * shade * Color(1.12, 0.98, 0.84)
			if k == Gen.POOL:
				fcol = Color(0.45, 0.5, 0.52) * shade
			fcol.a = 1.0
			_quad(fa, f00, f01, f11, f10, fcol, fcol, fcol, fcol)
			var ccol := tint * 0.55 * (0.85 + 0.25 * _h01(x, z, 12, sd))
			ccol.a = 1.0
			_quad(sa, c00, c10, c11, c01, ccol, ccol, ccol, ccol)
			# walls: for each closed neighbour, a two-row strip facing into this cell
			var sides := [
				[Vector2i(0, -1), 0, 1],   # -z edge: corners (x,z)-(x+1,z)
				[Vector2i(1, 0), 1, 2],    # +x edge: (x+1,z)-(x+1,z+1)
				[Vector2i(0, 1), 2, 3],    # +z edge: (x+1,z+1)-(x,z+1)
				[Vector2i(-1, 0), 3, 0],   # -x edge: (x,z+1)-(x,z)
			]
			var corners := [Vector2i(x, z), Vector2i(x + 1, z), Vector2i(x + 1, z + 1), Vector2i(x, z + 1)]
			for s: Array in sides:
				var nb: Vector2i = Vector2i(x, z) + (s[0] as Vector2i)
				if _open(g, nb.x, nb.y):
					continue
				var ca_: Vector2i = corners[s[1]]
				var cb_: Vector2i = corners[s[2]]
				var a0 := vertex(g, ca_.x, ca_.y, 0)
				var b0 := vertex(g, cb_.x, cb_.y, 0)
				var a2 := vertex(g, ca_.x, ca_.y, 2)
				var b2 := vertex(g, cb_.x, cb_.y, 2)
				var low := tint * (0.78 + 0.25 * _h01(ca_.x, ca_.y, 13, sd))
				low.a = 1.0
				var high := tint * (0.5 + 0.2 * _h01(cb_.x, cb_.y, 14, sd))
				high.a = 1.0
				if organic:
					var a1 := vertex(g, ca_.x, ca_.y, 1)
					var b1 := vertex(g, cb_.x, cb_.y, 1)
					var mid := tint * (0.66 + 0.2 * _h01(ca_.x, cb_.y, 15, sd))
					mid.a = 1.0
					_wall(sa, a0, a1, b1, b0, low, mid, mid, low)
					_wall(sa, a1, a2, b2, b1, mid, high, high, mid)
				else:
					_wall(sa, a0, a2, b2, b0, low, high, high, low)
	var out: Array = []
	var mats := materials(g["theme"])
	for ck: Vector2i in shells:
		var acc: Acc = shells[ck]
		out.append({"key": ck, "mesh": _to_mesh(acc, mats["shell"]), "faces": acc.verts})
	return out


static func _to_mesh(acc: Acc, mat: Material) -> ArrayMesh:
	var m := ArrayMesh.new()
	if acc.verts.is_empty():
		return m
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = acc.verts
	arr[Mesh.ARRAY_NORMAL] = acc.norms
	arr[Mesh.ARRAY_COLOR] = acc.cols
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.surface_set_material(0, mat)
	return m


static func triangle_count(chunks: Array) -> int:
	var n := 0
	for c: Dictionary in chunks:
		n += (c["faces"] as PackedVector3Array).size() / 3
	return n


# ---------------------------------------------------------------------------------------------
# materials

static func _tex(name: String) -> Texture2D:
	var p := TEX + name + ".png"
	return load(p) as Texture2D if ResourceLoader.exists(p) else null


static func _std(tex: Texture2D, scale: float, rough := 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC   # grazing floors smeared into streaks
	m.roughness = rough
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


static func materials(theme: String) -> Dictionary:
	if _mats.has(theme):
		return _mats[theme]
	var shell_tex := "rock"
	if theme == "crypt":
		shell_tex = "ruin_stone"
	var out := {"shell": _std(_tex(shell_tex), 0.4)}      # fallback: 0.22 stretched one texel over ~5 cm of floor
	if shell_tex == "rock" and ResourceLoader.exists(PH_ROCK % "diff"):
		# ashes-environment-look: real triplanar rock (albedo + normal + ARM, world space) instead of
		# the stretched albedo-only shell. Vertex colour (theme tint, AO) still multiplies in.
		var cave := ShaderMaterial.new()
		cave.shader = preload("res://shaders/environment/cave_rock.gdshader")
		cave.set_shader_parameter("rock_albedo", load(PH_ROCK % "diff"))
		cave.set_shader_parameter("rock_normal", load(PH_ROCK % "nor_gl"))
		cave.set_shader_parameter("rock_arm", load(PH_ROCK % "arm"))
		cave.set_shader_parameter("macro_rock", _tex("rock"))
		out["shell"] = cave
	var kit := StandardMaterial3D.new()
	kit.vertex_color_use_as_albedo = true
	kit.roughness = 0.9
	kit.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	out["kit"] = kit
	var glow := StandardMaterial3D.new()
	glow.vertex_color_use_as_albedo = true
	glow.emission_enabled = true
	glow.emission = Color(1, 1, 1)
	glow.emission_energy_multiplier = 1.6
	glow.roughness = 0.3
	glow.albedo_color = Color(1, 1, 1)
	out["glow"] = glow
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.12, 0.30, 0.38, 0.62)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.08
	water.metallic = 0.3
	water.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	water.cull_mode = BaseMaterial3D.CULL_DISABLED
	out["water"] = water
	_mats[theme] = out
	return out


# ---------------------------------------------------------------------------------------------
# tiny prop meshes (vertex coloured, MultiMesh friendly)

static var _prop_cache: Dictionary = {}


static func prop_mesh(kind: String, theme: String) -> ArrayMesh:
	var key := kind + "/" + theme
	if _prop_cache.has(key):
		return _prop_cache[key]
	var acc := Acc.new()
	var glow := false
	match kind:
		"stalagmite":
			_cone(acc, 0.0, 0.0, 0.0, 0.45, 1.7, 5, Color(0.55, 0.5, 0.46), Color(0.42, 0.38, 0.36))
			_cone(acc, 0.5, 0.2, 0.0, 0.25, 0.9, 5, Color(0.5, 0.46, 0.42), Color(0.4, 0.36, 0.34))
		"crystal":
			glow = true
			_cone(acc, 0.0, 0.0, 0.0, 0.3, 1.5, 5, Color(0.6, 0.35, 1.0), Color(0.9, 0.7, 1.0))
			_cone(acc, 0.35, 0.1, 0.0, 0.2, 0.9, 5, Color(0.5, 0.3, 0.9), Color(0.85, 0.6, 1.0))
			_cone(acc, -0.3, 0.15, 0.0, 0.17, 0.7, 5, Color(0.55, 0.4, 1.0), Color(0.8, 0.7, 1.0))
		"glowcap":
			glow = true
			_cone(acc, 0.0, 0.0, 0.0, 0.2, 0.35, 6, Color(0.3, 0.9, 0.7), Color(0.6, 1.0, 0.85))
			_cone(acc, 0.3, 0.1, 0.0, 0.14, 0.25, 6, Color(0.25, 0.8, 0.65), Color(0.6, 1.0, 0.85))
			_cone(acc, -0.2, 0.25, 0.0, 0.1, 0.2, 6, Color(0.3, 0.85, 0.7), Color(0.7, 1.0, 0.9))
		"rock":
			_blob(acc, Vector3.ZERO, Vector3(0.9, 0.55, 0.8), Color(0.5, 0.47, 0.44), 11)
			_blob(acc, Vector3(0.7, 0, 0.3), Vector3(0.5, 0.35, 0.5), Color(0.44, 0.42, 0.4), 12)
		"pebbles":
			_blob(acc, Vector3(0, 0, 0), Vector3(0.22, 0.12, 0.2), Color(0.5, 0.48, 0.45), 21)
			_blob(acc, Vector3(0.3, 0, 0.1), Vector3(0.16, 0.09, 0.15), Color(0.45, 0.43, 0.4), 22)
			_blob(acc, Vector3(-0.2, 0, 0.25), Vector3(0.14, 0.08, 0.13), Color(0.52, 0.5, 0.46), 23)
		"bones":
			_box(acc, Vector3(0, 0.05, 0), Vector3(0.5, 0.06, 0.08), 0.3, Color(0.85, 0.82, 0.72))
			_box(acc, Vector3(0.15, 0.05, 0.12), Vector3(0.4, 0.06, 0.08), -0.5, Color(0.8, 0.77, 0.68))
			_blob(acc, Vector3(-0.3, 0.08, -0.1), Vector3(0.14, 0.11, 0.12), Color(0.88, 0.85, 0.75), 31)
		"crate":
			_box(acc, Vector3(0, 0.35, 0), Vector3(0.7, 0.7, 0.7), 0.0, Color(0.5, 0.36, 0.22))
			_box(acc, Vector3(0, 0.36, 0), Vector3(0.74, 0.12, 0.74), 0.0, Color(0.36, 0.26, 0.16))
		"barrel":
			_cyl(acc, Vector3.ZERO, 0.33, 0.85, 8, Color(0.46, 0.32, 0.2))
			_cyl(acc, Vector3(0, 0.25, 0), 0.355, 0.08, 8, Color(0.25, 0.22, 0.2))
			_cyl(acc, Vector3(0, 0.6, 0), 0.355, 0.08, 8, Color(0.25, 0.22, 0.2))
		"pillar":
			_cyl(acc, Vector3.ZERO, 0.5, 3.6, 6, Color(0.66, 0.65, 0.62))
			_box(acc, Vector3(0, 0.15, 0), Vector3(1.1, 0.3, 1.1), 0.0, Color(0.58, 0.57, 0.55))
			_box(acc, Vector3(0, 3.5, 0), Vector3(1.1, 0.25, 1.1), 0.0, Color(0.58, 0.57, 0.55))
		"urn":
			_cyl(acc, Vector3.ZERO, 0.3, 0.75, 7, Color(0.55, 0.42, 0.3))
			_cyl(acc, Vector3(0, 0.6, 0), 0.18, 0.3, 7, Color(0.5, 0.38, 0.27))
		"rubble":
			_blob(acc, Vector3.ZERO, Vector3(0.6, 0.3, 0.5), Color(0.6, 0.6, 0.58), 41)
			_box(acc, Vector3(0.5, 0.15, 0.1), Vector3(0.5, 0.3, 0.4), 0.6, Color(0.62, 0.62, 0.6))
			_box(acc, Vector3(-0.4, 0.12, -0.2), Vector3(0.4, 0.25, 0.35), -0.4, Color(0.56, 0.56, 0.55))
		"flame":
			glow = true
			_cone(acc, 0.0, 0.0, 0.0, 0.11, 0.42, 5, Color(1.0, 0.55, 0.15), Color(1.0, 0.9, 0.5))
		"bracket":
			_cyl(acc, Vector3(0, 0, 0), 0.04, 0.9, 5, Color(0.3, 0.2, 0.12))
		"firepit":
			for i in 6:
				var a := TAU * i / 6.0
				_blob(acc, Vector3(cos(a) * 0.55, 0, sin(a) * 0.55), Vector3(0.22, 0.16, 0.22), Color(0.45, 0.43, 0.4), 60 + i)
			_box(acc, Vector3(0, 0.12, 0), Vector3(0.9, 0.12, 0.14), 0.5, Color(0.3, 0.2, 0.12))
			_box(acc, Vector3(0, 0.12, 0), Vector3(0.9, 0.12, 0.14), -0.6, Color(0.27, 0.18, 0.11))
		_:
			_box(acc, Vector3(0, 0.2, 0), Vector3(0.4, 0.4, 0.4), 0.0, Color(0.6, 0.6, 0.6))
	var m := _to_mesh(acc, materials(theme)["glow" if glow else "kit"])
	_prop_cache[key] = m
	return m


static func _cone(acc: Acc, cx: float, cz: float, y0: float, r: float, h: float, sides: int, base: Color, tip: Color) -> void:
	var top := Vector3(cx + r * 0.1, y0 + h, cz)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := Vector3(cx + cos(a0) * r, y0, cz + sin(a0) * r)
		var p1 := Vector3(cx + cos(a1) * r, y0, cz + sin(a1) * r)
		_tri(acc, p0, top, p1, base, tip, base)


static func _cyl(acc: Acc, at: Vector3, r: float, h: float, sides: int, col: Color) -> void:
	var dark := col * 0.8
	dark.a = 1.0
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var p0 := at + Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := at + Vector3(cos(a1) * r, 0, sin(a1) * r)
		var q0 := p0 + Vector3(0, h, 0)
		var q1 := p1 + Vector3(0, h, 0)
		_quad(acc, p0, q0, q1, p1, dark, col, col, dark)
		_tri(acc, at + Vector3(0, h, 0), q1, q0, col, col, col)


static func _box(acc: Acc, c: Vector3, s: Vector3, yaw: float, col: Color) -> void:
	var b := Basis(Vector3.UP, yaw)
	var h := s * 0.5
	var p: Array[Vector3] = []
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				p.append(c + b * Vector3(h.x * sx, h.y * sy, h.z * sz))
	# indices: x-major (sx,sy,sz) => 0..7
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	var dark := col * 0.75
	dark.a = 1.0
	for f: Array in faces:
		_quad(acc, p[f[0]], p[f[1]], p[f[2]], p[f[3]], dark, col, col, dark)
	# fix winding for faces that came out inward: re-emit doubled-sided is wasteful; normals are flipped if needed
	_ensure_outward(acc, c)


## Flip triangles of the most recent box/blob whose normal points at `centre` (cheap winding fix).
static func _ensure_outward(acc: Acc, centre: Vector3) -> void:
	var n := acc.verts.size()
	var i := maxi(n - 36, 0)
	while i + 2 < n:
		var tri_c := (acc.verts[i] + acc.verts[i + 1] + acc.verts[i + 2]) / 3.0
		if acc.norms[i].dot(tri_c - centre) < 0.0:
			var tmp := acc.verts[i + 1]
			acc.verts[i + 1] = acc.verts[i + 2]
			acc.verts[i + 2] = tmp
			var tc := acc.cols[i + 1]
			acc.cols[i + 1] = acc.cols[i + 2]
			acc.cols[i + 2] = tc
			var nn := -acc.norms[i]
			acc.norms[i] = nn
			acc.norms[i + 1] = nn
			acc.norms[i + 2] = nn
		i += 3


static func _blob(acc: Acc, at: Vector3, r: Vector3, col: Color, salt: int) -> void:
	# a faceted icosphere-ish lump: two rings of 6 plus caps
	var ring0: Array[Vector3] = []
	var ring1: Array[Vector3] = []
	for i in 6:
		var a := TAU * i / 6.0
		var j := 0.85 + 0.3 * _h01(i, salt, 3, 9)
		ring0.append(at + Vector3(cos(a) * r.x * j, r.y * 0.25, sin(a) * r.z * j))
		ring1.append(at + Vector3(cos(a + 0.5) * r.x * 0.55, r.y * 0.85, sin(a + 0.5) * r.z * 0.55))
	var top := at + Vector3(0, r.y * (1.0 + 0.1 * _h01(salt, 1, 2, 3)), 0)
	var base := at + Vector3(0, 0, 0)
	var dark := col * 0.72
	dark.a = 1.0
	var start := acc.verts.size()
	for i in 6:
		var i2 := (i + 1) % 6
		_quad(acc, ring0[i], ring1[i], ring1[i2], ring0[i2], dark, col, col, dark)
		_tri(acc, ring1[i], top, ring1[i2], col, col, col)
		_tri(acc, base, ring0[i2], ring0[i], dark, dark, dark)
	# outward winding
	var i3 := start
	var centre := at + Vector3(0, r.y * 0.4, 0)
	while i3 + 2 < acc.verts.size():
		var tri_c := (acc.verts[i3] + acc.verts[i3 + 1] + acc.verts[i3 + 2]) / 3.0
		if acc.norms[i3].dot(tri_c - centre) < 0.0:
			var tmp := acc.verts[i3 + 1]
			acc.verts[i3 + 1] = acc.verts[i3 + 2]
			acc.verts[i3 + 2] = tmp
			var tc := acc.cols[i3 + 1]
			acc.cols[i3 + 1] = acc.cols[i3 + 2]
			acc.cols[i3 + 2] = tc
			var nn := -acc.norms[i3]
			acc.norms[i3] = nn
			acc.norms[i3 + 1] = nn
			acc.norms[i3 + 2] = nn
		i3 += 3


## A box mesh with the kit material (chest body, door leaf...). Not batched, used a few times.
static func box_mesh(size: Vector3, col: Color, theme: String) -> ArrayMesh:
	var acc := Acc.new()
	_box(acc, Vector3(0, size.y * 0.5, 0), size, 0.0, col)
	return _to_mesh(acc, materials(theme)["kit"])


## Chest as two meshes (body, lid) so a chest costs two draws and the lid can swing open.
static func chest_meshes(vault: bool, theme: String) -> Array:
	var wood := Color(0.42, 0.28, 0.16) if not vault else Color(0.3, 0.3, 0.36)
	var trim := Color(0.22, 0.2, 0.2) if not vault else Color(0.78, 0.62, 0.22)
	var body := Acc.new()
	_box(body, Vector3(0, 0.25, 0), Vector3(0.95, 0.5, 0.62), 0.0, wood)
	_box(body, Vector3(0, 0.3, 0), Vector3(1.0, 0.1, 0.66), 0.0, trim)
	var lid := Acc.new()
	_box(lid, Vector3(0, 0.11, 0.3), Vector3(0.95, 0.22, 0.62), 0.0, wood)
	_box(lid, Vector3(0, 0.11, 0.3), Vector3(0.12, 0.26, 0.66), 0.0, trim)
	var m: Dictionary = materials(theme)
	return [_to_mesh(body, m["kit"]), _to_mesh(lid, m["kit"])]


static func box_acc_mesh(boxes: Array, theme: String) -> ArrayMesh:
	var acc := Acc.new()
	for b: Array in boxes:
		_box(acc, b[0], b[1], float(b[2]), b[3])
	return _to_mesh(acc, materials(theme)["kit"])
