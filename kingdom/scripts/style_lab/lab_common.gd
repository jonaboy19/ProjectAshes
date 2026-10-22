extends RefCounted
## Style Lab helpers: texture/noise cache and a BaseMaterial3D -> shader-parameter extractor.
## No class_name (project rule): other lab scripts `preload()` this file.

const PH := "res://assets/incoming/polyhaven/textures/%s/%s_%s_2k.jpg"

static var _tex := {}
static var _noise: NoiseTexture2D
static var _sky_noise: NoiseTexture2D


static func ph(set_name: String, kind: String) -> Texture2D:
	var key := set_name + kind
	if not _tex.has(key):
		_tex[key] = load(PH % [set_name, set_name, kind])
	return _tex[key]


static func noise() -> NoiseTexture2D:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.012
		n.fractal_octaves = 4
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.noise = n
		_noise.generate_mipmaps = true
	return _noise


static func sky_noise() -> NoiseTexture2D:
	if _sky_noise == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.02
		n.fractal_octaves = 5
		n.fractal_gain = 0.55
		_sky_noise = NoiseTexture2D.new()
		_sky_noise.width = 256
		_sky_noise.height = 256
		_sky_noise.seamless = true
		_sky_noise.noise = n
		_sky_noise.generate_mipmaps = true
	return _sky_noise


## Pulls what the style shaders need out of an original material (BaseMaterial3D). Returns {} for others.
static func params(m: Material) -> Dictionary:
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		var cut := 0.0
		if b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			cut = b.alpha_scissor_threshold
		return {
			"tex": b.albedo_texture, "color": b.albedo_color, "vcol": b.vertex_color_use_as_albedo,
			"uv_scale": Vector2(b.uv1_scale.x, b.uv1_scale.y), "uv_offset": Vector2(b.uv1_offset.x, b.uv1_offset.y),
			"cut": cut, "cull_off": b.cull_mode == BaseMaterial3D.CULL_DISABLED,
		}
	return {}


static var _white: ImageTexture


static func white() -> Texture2D:
	if _white == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	return _white


## Fills the common albedo uniforms of a lab shader material from `p` (see params()).
static func apply_albedo(sm: ShaderMaterial, p: Dictionary, tex_param := "albedo_tex", color_param := "albedo_color") -> void:
	sm.set_shader_parameter(tex_param, p["tex"] if p["tex"] != null else white())
	sm.set_shader_parameter(color_param, p["color"])
	sm.set_shader_parameter("use_vertex_color", p["vcol"])
	sm.set_shader_parameter("uv_scale", p["uv_scale"])
	sm.set_shader_parameter("uv_offset", p["uv_offset"])
	sm.set_shader_parameter("alpha_cut", p["cut"])


## Vertex-colour ground for the 12 m street corner: R = mud, B = cobble (same encoding as terrain.gdshader).
static func ground_mesh(size: float, cells: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	var step := size / cells
	var verts: Array[Vector3] = []
	var cols: Array[Color] = []
	for iz in cells + 1:
		for ix in cells + 1:
			var x := -h + ix * step
			var z := -h + iz * step
			verts.append(Vector3(x, 0, z))
			cols.append(ground_color(x, z))
	for iz in cells:
		for ix in cells:
			var i0 := iz * (cells + 1) + ix
			var i1 := i0 + 1
			var i2 := i0 + cells + 1
			var i3 := i2 + 1
			for idx in [i0, i1, i2, i1, i3, i2]:
				st.set_color(cols[idx])
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(verts[idx].x, verts[idx].z) / 4.0)
				st.add_vertex(verts[idx])
	st.generate_tangents()
	return st.commit()


## Cobbles on the front street and the left lane, a worn mud band around them and by the stall and the well.
static func ground_color(x: float, z: float) -> Color:
	var d := minf(0.5 - z, x + 3.6)            # < 0 inside the cobbled streets
	var cobble := 1.0 - smoothstep(-0.1, 0.35, d)
	var mud := (1.0 - smoothstep(0.1, 1.5, d)) * (1.0 - cobble)
	# worn patches: in front of the stall, around the well, under the cart, wheel ruts at the lane mouth
	mud = maxf(mud, (1.0 - smoothstep(0.6, 1.8, Vector2(x - 3.4, z - 0.2).length())) * 0.9)
	mud = maxf(mud, (1.0 - smoothstep(0.5, 1.5, Vector2(x + 4.2, z + 1.0).length())) * 0.85)
	mud = maxf(mud, (1.0 - smoothstep(0.4, 1.3, Vector2(x - 4.2, z - 2.7).length())) * 0.8)
	return Color(clampf(mud, 0.0, 1.0), 0.0, clampf(cobble, 0.0, 1.0), 0.0)


## Soil cut-away skirt around the diorama (4 sides), so each box reads as a small stage.
static func skirt_mesh(size: float, depth: float) -> ArrayMesh:
	var h := size * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector3(-h, 0, h), Vector3(h, 0, h), Vector3(h, 0, -h), Vector3(-h, 0, -h)]
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var n := (b - a).cross(Vector3.DOWN).normalized()
		var top := Color(0.22, 0.34, 0.10)
		var mid := Color(0.34, 0.22, 0.12)
		var low := Color(0.18, 0.12, 0.09)
		var rows := [[0.0, top], [0.12, top], [0.14, mid], [depth * 0.55, mid], [depth, low]]
		for r in rows.size() - 1:
			var y0: float = rows[r][0]
			var y1: float = rows[r + 1][0]
			var c0: Color = rows[r][1]
			var c1: Color = rows[r + 1][1]
			for p in [[a, y0, c0], [b, y0, c0], [a, y1, c1], [b, y0, c0], [b, y1, c1], [a, y1, c1]]:
				st.set_color(p[2])
				st.set_normal(-n)
				st.add_vertex(p[0] + Vector3.DOWN * p[1])
	return st.commit()
