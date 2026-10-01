extends RefCounted
## Style Lab: five self-contained looks for the SAME diorama. A style = one Environment + one sun + optional extra
## lights/decals + one material set. `setup()` builds all of it inside a SubViewport (own World3D) and restyles the
## diorama's meshes by role. To apply a style game-wide see docs/design/STYLE_LAB.md (start from env_for()/materials).
##
##   A  baseline   today's materials, sky, AgX grade (copied from main.gd _build_environment at 16 h)
##   B  storybook  toon ramp + ink outline + painted sky + warm LUT
##   C  grounded   PBR (Poly Haven CC0) + SSAO/contact blobs/decals + height fog + desaturated palette
##   D  polished   wrap diffuse + rim + bounce + bloom + saturated palette + skin/cloth/hair shaders
##   E  low-end D  vertex-lit, no bloom/rim/grade pass, 1 shadow split, 0.75 render scale
## No class_name (project rule).

const Common := preload("res://scripts/style_lab/lab_common.gd")
const SH := "res://shaders/style_lab/"
const IDS := ["A", "B", "C", "D", "E", "F", "G"]
const TITLES := {
	"A": "A  Current look (baseline)",
	"B": "B  Storybook painterly",
	"C": "C  Grounded medieval",
	"D": "D  Polished stylised",
	"E": "E  Low-end safe (D lite)",
	"F": "F  Concept target (golden hour)",
	"G": "G  Target 03 recreation (gate market)",
}
const SUN_FORWARD := Vector3(-0.58, -0.60, -0.55)   # late afternoon from the front-right, same in every box

static var _cache := {}


# --- public ---------------------------------------------------------------------------------------------------

## Builds environment + sun + extras for style `id` under `vp` and restyles `dio`. Returns a context dictionary.
static func setup(id: String, vp: SubViewport, dio: Node3D, lamp_pos: Vector3) -> Dictionary:
	var ctx := {"id": id}
	var we := WorldEnvironment.new()
	we.name = "Env" + id
	we.environment = env_for(id)
	vp.add_child(we)
	var sun := _sun(id)
	vp.add_child(sun)
	ctx["env"] = we.environment
	ctx["sun"] = sun
	ctx["we"] = we
	_restyle(id, dio)
	_lamp(id, dio, lamp_pos)
	if id == "C":
		_blobs(dio)
		_decals(dio)
	elif id == "E":
		_blobs(dio)
	if id == "A":
		pass
	return ctx


## Re-applies what the Quality autoload may have overridden (glow, ssao, shadows, MSAA, 3D scale).
static func finalize(id: String, ctx: Dictionary, vp: SubViewport) -> void:
	var env: Environment = ctx["env"]
	var fwd := RenderingServer.get_current_rendering_method() == "forward_plus"
	match id:
		"A":
			pass
		"B":
			env.glow_enabled = true
			env.ssao_enabled = false
		"C":
			env.ssao_enabled = fwd
			env.glow_enabled = false
		"D", "F":
			env.glow_enabled = true
			env.ssao_enabled = false
		"G":
			env.glow_enabled = true
			env.ssao_enabled = fwd
		"E":
			env.glow_enabled = false
			env.ssao_enabled = false
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 0.75
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	var sun: DirectionalLight3D = ctx["sun"]
	if id == "E":
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 30.0
	elif id == "G":
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 110.0
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 40.0
	sun.shadow_enabled = true


# --- environments ---------------------------------------------------------------------------------------------

static func env_for(id: String) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	match id:
		"A": _env_a(env)
		"B": _env_b(env)
		"C": _env_c(env)
		"D": _env_d(env)
		"E": _env_e(env)
		"F": _env_f(env)
		"G": _env_g(env)
	return env


## Copy of main.gd _build_environment() (the shipping look): HDRI sky, AgX, warm ambient, glow, saturation 1.28.
static func _env_a(env: Environment) -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/storybook_sky.gdshader")
	sky_mat.set_shader_parameter("panorama", load("res://assets/generated/sky/kloofendal_43d_clear_puresky_2k.hdr"))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.ambient_light_color = Color("ffe2bd")
	env.ambient_light_sky_contribution = 0.72
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.2
	env.tonemap_white = 7.0
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.0
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.07
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color("c9d4e6")
	env.fog_density = 0.0006
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.28
	env.adjustment_contrast = 1.1


static func _lut(shadow: Color, mid: Color, high: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, shadow)
	g.set_color(1, high)
	g.add_point(0.5, mid)
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 64
	return t


static func _sky(top: Color, horizon: Color, ground: Color, cloud: Color, shade: Color, cover: float, soft: float,
		poster := 0.0, glow := 0.35) -> Sky:
	var m := ShaderMaterial.new()
	m.shader = load(SH + "lab_sky.gdshader")
	m.set_shader_parameter("top_color", top)
	m.set_shader_parameter("horizon_color", horizon)
	m.set_shader_parameter("ground_color", ground)
	m.set_shader_parameter("cloud_color", cloud)
	m.set_shader_parameter("cloud_shade", shade)
	m.set_shader_parameter("cloud_cover", cover)
	m.set_shader_parameter("cloud_soft", soft)
	m.set_shader_parameter("posterize", poster)
	m.set_shader_parameter("sun_glow", glow)
	m.set_shader_parameter("cloud_noise", Common.sky_noise())
	var s := Sky.new()
	s.sky_material = m
	s.radiance_size = Sky.RADIANCE_SIZE_32
	return s


static func _env_b(env: Environment) -> void:
	env.sky = _sky(Color("3f78d8"), Color("ffd9a6"), Color("b89a7a"), Color("fffaf0"), Color("e2b9ac"), 0.5, 0.12, 0.85, 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a89ad8")        # lilac shade: the "painted shadow" colour
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color("f6d9b4")
	env.fog_density = 0.0
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.06
	env.adjustment_color_correction = _lut(Color("100628"), Color("7d7297"), Color("fff0d0"))


static func _env_c(env: Environment) -> void:
	env.sky = _sky(Color("5d7088"), Color("b9bcb4"), Color("5a5448"), Color("c9ccce"), Color("7d8794"), 0.78, 0.35, 0.0, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.9
	env.ambient_light_color = Color("c8c2b4")
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.tonemap_white = 5.0
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 3.0
	env.ssao_power = 1.6
	env.ssao_detail = 0.8
	env.ssao_light_affect = 0.35
	env.fog_enabled = true
	env.fog_light_color = Color("a9aca6")
	env.fog_density = 0.003
	env.fog_height = 1.0
	env.fog_height_density = 0.25
	env.fog_sky_affect = 0.4
	env.glow_enabled = false
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9
	env.adjustment_contrast = 1.14
	env.adjustment_color_correction = _lut(Color("0a0d12"), Color("85857c"), Color("f4ecdc"))


static func _env_d(env: Environment) -> void:
	env.sky = _sky(Color("1f5fe0"), Color("7fb4ff"), Color("b8c4a0"), Color("ffffff"), Color("a9c4f2"), 0.46, 0.2, 0.0, 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a9c2ff")
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.08
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.fog_enabled = true
	env.fog_light_color = Color("a9ccff")
	env.fog_density = 0.0018
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.08
	env.adjustment_color_correction = _lut(Color("0b1230"), Color("8c8aa0"), Color("fff6e4"))


static func _env_e(env: Environment) -> void:
	# Cheapest sensible: gradient sky is one tap, colour ambient, filmic tonemap only, no glow, no adjustment pass.
	env.sky = _sky(Color("2a6ae6"), Color("8cbcff"), Color("b8c4a0"), Color("ffffff"), Color("a9c4f2"), 0.4, 0.2, 0.0, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b4c8ff")
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.08
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color("cfe3ff")
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.2


static func _env_f(env: Environment) -> void:
	# Concept target (docs/art/reference 00/01/02): deep blue sky with cumulus, warm low sun, blue-violet shadows,
	# golden aerial haze with distant mountains, strong soft bloom, rich saturation.
	env.sky = _sky(Color("1c4fcf"), Color("ffd8a8"), Color("8a9a6a"), Color("fff3de"), Color("9fb4e0"), 0.5, 0.16, 0.0, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8fa8ff")
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 5.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.14
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color("f1c99a")
	env.fog_density = 0.0042
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.12
	env.adjustment_color_correction = _lut(Color("0a0a2a"), Color("8a7f90"), Color("fff0d0"))


static func _env_g(env: Environment) -> void:
	# Target 03: bright late-afternoon sun, saturated blue sky with big cumulus, light warm haze, crisp shadows.
	env.sky = _sky(Color("2563d8"), Color("cfe4ff"), Color("8a9a6a"), Color("ffffff"), Color("a9c0ea"), 0.55, 0.14, 0.0, 0.45)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("9db5f2")
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 5.5
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.2
	env.ssao_light_affect = 0.2
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color("d9e3f2")
	env.fog_density = 0.0028
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.22
	env.adjustment_contrast = 1.16
	env.adjustment_color_correction = _lut(Color("0b0e2a"), Color("8a8498"), Color("fff3d8"))


static func _sun_dir(id: String) -> Vector3:
	match id:
		"F": return Vector3(-0.72, -0.40, -0.58)
		"G": return Vector3(0.55, -0.62, -0.55)      # from behind-left: shadows fall forward-right as in target 03
	return SUN_FORWARD


static func _sun(id: String) -> DirectionalLight3D:
	var s := DirectionalLight3D.new()
	s.name = "Sun" + id
	s.look_at_from_position(Vector3.ZERO, _sun_dir(id))
	s.shadow_enabled = true
	s.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	s.directional_shadow_max_distance = 40.0
	s.shadow_blur = 1.4
	s.light_angular_distance = 0.6
	match id:
		"A":
			s.light_color = Color("ffcf94")
			s.light_energy = 1.1
		"B":
			s.light_color = Color("ffe2b0")
			s.light_energy = 1.25
			s.shadow_blur = 2.2
		"C":
			s.light_color = Color("ffe6c4")
			s.light_energy = 1.05
			s.shadow_blur = 1.8
		"D":
			s.light_color = Color("ffe8bf")
			s.light_energy = 1.45
			s.shadow_blur = 1.6
		"E":
			s.light_color = Color("ffe8bf")
			s.light_energy = 1.45
			s.shadow_blur = 0.0
		"F":
			s.light_color = Color("ffc27a")
			s.light_energy = 1.9
			s.shadow_blur = 1.8
		"G":
			s.light_color = Color("ffd6a0")
			s.light_energy = 2.7
			s.shadow_blur = 1.0
			s.light_angular_distance = 0.35
	return s


# --- lantern light + glow ------------------------------------------------------------------------------------

static func _lamp(id: String, dio: Node3D, pos: Vector3) -> void:
	var flame := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.2
	sm.radial_segments = 8
	sm.rings = 4
	flame.mesh = sm
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.72, 0.28)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.6, 0.2)
	fm.emission_energy_multiplier = 3.0
	flame.material_override = fm
	flame.position = pos
	flame.set_meta("role", "flame")
	dio.add_child(flame)
	# soft additive glow sprite (one quad, unshaded) in every style: this is the phone-cheap "light"
	var glow := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.5, 1.5)
	glow.mesh = q
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gm.no_depth_test = false
	gm.disable_receive_shadows = true
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.7, 0.35, 0.55))
	grad.set_color(1, Color(1.0, 0.5, 0.2, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	gm.albedo_texture = gt
	gm.albedo_color = Color(1, 1, 1, 0.9 if id != "A" else 0.6)
	glow.material_override = gm
	glow.position = pos
	glow.set_meta("role", "flame")
	dio.add_child(glow)
	# one real omni light on the two rich styles (expensive on phones: per-pixel, no shadow here)
	if id == "C" or id == "D" or id == "F":
		var o := OmniLight3D.new()
		o.light_color = Color(1.0, 0.68, 0.36)
		o.light_energy = 1.6 if id != "C" else 1.2
		o.omni_range = 5.5
		o.omni_attenuation = 1.4
		o.position = pos
		o.shadow_enabled = false
		dio.add_child(o)


# --- contact shadows + decals (C, E) --------------------------------------------------------------------------

static func _blobs(dio: Node3D) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load(SH + "lab_blob.gdshader")
	mat.set_shader_parameter("strength", 0.55)
	for n in dio.get_children():
		var r: float = float(n.get_meta("blob", 0.0))
		if r <= 0.0 or not (n is Node3D):
			continue
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		var box_r := r
		if n.get("scale") is Vector3 and n.get_meta("role", "") in ["house", "wall"]:
			box_r = r * 1.0
		pm.size = Vector2(box_r * 2.6, box_r * 2.6)
		if n.get_meta("role", "") == "house":
			pm.size = Vector2(8.6, 5.0)
		elif n.get_meta("role", "") == "wall":
			pm.size = Vector2(2.4, 9.0)
		q.mesh = pm
		q.material_override = mat
		q.position = (n as Node3D).position + Vector3(0, 0.02, 0)
		q.rotation.y = (n as Node3D).rotation.y
		q.set_meta("role", "blobquad")
		dio.add_child(q)


static func _decals(dio: Node3D) -> void:
	# Procedural mud / moss splats (NoiseTexture2D + gradient alpha). Decals are Mobile + Forward+ only.
	var spots := [
		[Vector3(0.6, 0.0, -1.5), Vector3(4.5, 2.0, 1.6), "mud"],
		[Vector3(3.3, 0.0, 0.9), Vector3(3.2, 2.0, 2.2), "mud"],
		[Vector3(5.2, 0.0, -0.8), Vector3(1.6, 2.0, 6.0), "moss"],
		[Vector3(-4.6, 0.0, -1.3), Vector3(2.4, 2.0, 2.4), "mud"],
		[Vector3(-1.0, 0.0, -3.4), Vector3(3.5, 3.0, 1.2), "moss"],
	]
	for s in spots:
		var d := Decal.new()
		d.size = s[1]
		d.position = s[0] + Vector3(0, 0.6, 0)
		var moss: bool = s[2] == "moss"
		d.texture_albedo = _splat(moss)
		d.modulate = Color(0.75, 0.9, 0.5) if moss else Color(0.85, 0.7, 0.55)
		d.albedo_mix = 0.85
		d.upper_fade = 0.6
		d.lower_fade = 0.6
		d.cull_mask = 1
		dio.add_child(d)


static func _splat(moss: bool) -> Texture2D:
	var key := "splat" + str(moss)
	if _cache.has(key):
		return _cache[key]
	var n := FastNoiseLite.new()
	n.frequency = 0.03 if moss else 0.02
	n.fractal_octaves = 4
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.noise = n
	nt.seamless = false
	var g := Gradient.new()
	if moss:
		g.set_color(0, Color(0.16, 0.22, 0.06, 0.0))
		g.set_color(1, Color(0.30, 0.40, 0.12, 0.9))
		g.add_point(0.5, Color(0.2, 0.28, 0.08, 0.0))
	else:
		g.set_color(0, Color(0.20, 0.13, 0.08, 0.0))
		g.set_color(1, Color(0.26, 0.17, 0.10, 0.95))
		g.add_point(0.45, Color(0.22, 0.14, 0.09, 0.0))
	nt.color_ramp = g
	# fade the edge of the square so the decal has no hard border
	_cache[key] = nt
	return nt


# --- restyle --------------------------------------------------------------------------------------------------

static func _role_of(n: Node) -> String:
	var cur := n
	while cur != null:
		if cur.has_meta("role"):
			return String(cur.get_meta("role"))
		cur = cur.get_parent()
	return ""


static func _restyle(id: String, dio: Node3D) -> void:
	for mi in dio.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var role := _role_of(m)
		if role in ["flame", "blobquad", ""] or m.mesh == null or m.has_meta("keep_material"):
			continue
		for si in m.mesh.get_surface_count():
			var orig: Material = m.get_active_material(si)
			var mat := _material(id, role, orig, m)
			if mat != null:
				m.set_surface_override_material(si, mat)


static func _is_char(role: String) -> bool:
	return role == "hero_old" or role == "hero_new" or role == "villager" or role == "guard"


static func _material(id: String, role: String, orig: Material, mi: MeshInstance3D) -> Material:
	if role == "ground":
		return _ground_mat(id)
	if role == "skirt":
		return _skirt_mat(id)
	if role == "meadow" or role == "mountain":
		var key2 := role + id
		if not _cache.has(key2):
			var sm2 := StandardMaterial3D.new()
			sm2.roughness = 1.0
			sm2.albedo_color = Color(0.30, 0.48, 0.14) if role == "meadow" else Color(0.40, 0.48, 0.66)
			_cache[key2] = sm2
		return _cache[key2]
	if id == "G" and role in ["gate_stone", "iron", "banner", "flag"]:
		return _gate_special(role, orig, mi)
	var p := Common.params(orig)
	if p.is_empty():
		return null                       # ShaderMaterial originals (wind foliage etc.) stay as they are
	var key := "%s|%s|%d|%s|%s" % [id, role, orig.get_instance_id(), mi.name if _is_char(role) else "", _skin_kind(mi)]
	if _cache.has(key):
		return _cache[key]
	var out: Material = null
	match id:
		"A":
			out = null
		"B":
			out = _toon(p, role)
		"C":
			out = _grounded(p, role, orig)
		"D", "F", "G":
			out = _polished(p, role, mi, false, id == "F" or id == "G")
		"E":
			out = _polished(p, role, mi, true)
	_cache[key] = out
	return out


# B ---------------------------------------------------------------------------------------------------------

static func _toon(p: Dictionary, role: String) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	sm.shader = _shader("lab_toon")
	Common.apply_albedo(sm, p)
	sm.set_shader_parameter("paint_noise", Common.noise())
	sm.set_shader_parameter("saturation", 1.22 if role != "tree" else 0.95)
	if _is_char(role):
		sm.set_shader_parameter("mottle", 0.08)
	if p["cut"] <= 0.0:
		var ol := ShaderMaterial.new()
		ol.shader = _shader("lab_outline")
		Common.apply_albedo(ol, p)
		ol.set_shader_parameter("width", 0.0034 if _is_char(role) else 0.0048)
		sm.next_pass = ol
	return sm


# C ---------------------------------------------------------------------------------------------------------

static func _grounded(p: Dictionary, role: String, orig: Material) -> Material:
	var sets := {
		"house": ["damaged_plaster", "medieval_wood"],
		"wall": ["mossy_stone_wall", "medieval_blocks_02"],
		"stall": ["medieval_wood", "brown_planks_05"],
		"wood": ["brown_planks_05", "medieval_wood"],
		"lamp": ["medieval_wood", "medieval_wood"],
	}
	if sets.has(role):
		var sm := ShaderMaterial.new()
		sm.shader = _shader("lab_grounded")
		var a: String = sets[role][0]
		var b: String = sets[role][1]
		Common.apply_albedo(sm, p, "atlas", "atlas_color")
		sm.set_shader_parameter("a_alb", Common.ph(a, "diff"))
		sm.set_shader_parameter("a_nor", Common.ph(a, "nor_gl"))
		sm.set_shader_parameter("a_arm", Common.ph(a, "arm"))
		sm.set_shader_parameter("b_alb", Common.ph(b, "diff"))
		sm.set_shader_parameter("b_nor", Common.ph(b, "nor_gl"))
		sm.set_shader_parameter("b_arm", Common.ph(b, "arm"))
		sm.set_shader_parameter("noise_tex", Common.noise())
		if role == "wall":
			sm.set_shader_parameter("detail", 0.95)
			sm.set_shader_parameter("chroma_keep", 0.3)
			sm.set_shader_parameter("tile_a", 3.2)
			sm.set_shader_parameter("moss", 0.7)
		elif role == "house":
			sm.set_shader_parameter("tile_a", 2.6)
			sm.set_shader_parameter("tile_b", 1.8)
		return sm
	# goods, tree, characters: a muted copy of the original standard material
	var b := (orig as BaseMaterial3D).duplicate() as BaseMaterial3D
	var c: Color = b.albedo_color
	var l := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
	var sat := 0.78 if not _is_char(role) else 0.72
	b.albedo_color = Color(lerpf(l, c.r, sat), lerpf(l, c.g, sat), lerpf(l, c.b, sat), c.a) * Color(0.94, 0.92, 0.88)
	b.roughness = maxf(b.roughness, 0.85)
	b.metallic_specular = 0.2
	b.rim_enabled = false
	return b


# D / E -----------------------------------------------------------------------------------------------------

static func _skin_kind(mi: MeshInstance3D) -> String:
	var n := String(mi.name).to_lower()
	if n.contains("hair") or n.contains("brow") or n.contains("lash") or n.contains("beard"):
		return "2"
	if n.contains("head") or n.contains("hands") or n.contains("body") or n.contains("skin") or n.contains("face") or n.contains("eye"):
		return "0"
	if n.contains("boot") or n.contains("glove") or n.contains("shoe") or n.contains("belt"):
		return "3"
	return "1"


static func _polished(p: Dictionary, role: String, mi: MeshInstance3D, lite: bool, vivid := false) -> ShaderMaterial:
	var sm := ShaderMaterial.new()
	if _is_char(role) and not lite:
		sm.shader = _shader("lab_char")
		sm.set_shader_parameter("kind", int(_skin_kind(mi)))
		Common.apply_albedo(sm, p)
		# G6 modular meshes (human_*) carry dark vertex colours on top of a texture: ignore them; MakeHuman needs them
		sm.set_shader_parameter("use_vertex_color", bool(p["vcol"]) and not String(mi.name).begins_with("human_"))
		if vivid:
			sm.set_shader_parameter("saturation", 1.3)
		return sm
	sm.shader = _shader("lab_polished_lite" if lite else "lab_polished")
	Common.apply_albedo(sm, p)
	match role:
		"tree":
			sm.set_shader_parameter("saturation", 1.15)
			sm.set_shader_parameter("ao_strength", 0.0)
			sm.set_shader_parameter("roughness", 0.9)
		"house", "wall":
			sm.set_shader_parameter("saturation", 1.2)
			sm.set_shader_parameter("ao_height", 1.4)
			sm.set_shader_parameter("ao_strength", 0.38)
		"hero_old", "hero_new", "villager":
			sm.set_shader_parameter("saturation", 1.18)
			sm.set_shader_parameter("ao_strength", 0.0)
	if vivid and role != "tree":
		sm.set_shader_parameter("saturation", 1.38 if role not in ["house", "stall"] else 1.0)
		if role == "house":
			sm.set_shader_parameter("value_gain", 0.9)
			sm.set_shader_parameter("warm_tint", Color(1.0, 0.97, 0.9))
		sm.set_shader_parameter("rim_amount", 0.5)
		sm.set_shader_parameter("bounce", 0.3)
	return sm


# ground / skirt --------------------------------------------------------------------------------------------

static func _skirt_mat(id: String) -> Material:
	var key := "skirt" + id
	if _cache.has(key):
		return _cache[key]
	var m: Material
	if id == "B":
		var sm := ShaderMaterial.new()
		sm.shader = _shader("lab_toon")
		sm.set_shader_parameter("albedo_tex", Common.white())
		sm.set_shader_parameter("use_vertex_color", true)
		sm.set_shader_parameter("paint_noise", Common.noise())
		m = sm
	else:
		var b := StandardMaterial3D.new()
		b.vertex_color_use_as_albedo = true
		b.roughness = 1.0
		m = b
	_cache[key] = m
	return m


static func _ground_mat(id: String) -> Material:
	var key := "ground" + id
	if _cache.has(key):
		return _cache[key]
	var cob_a: Texture2D = load("res://assets/art/textures/cobblestone.png")
	var m: ShaderMaterial = ShaderMaterial.new()
	match id:
		"A":
			# exactly the shipping terrain shader and layer textures (terrain_streamer.gd)
			m.shader = load("res://shaders/terrain.gdshader")
			var layers := {"grass": "leafy_grass", "forest": "forest_ground_04", "path": "grass_path_2",
				"rock": "rocky_terrain_02", "cobble": "cobblestone_floor_01"}
			for layer: String in layers:
				var t: String = layers[layer]
				m.set_shader_parameter(layer + "_albedo", Common.ph(t, "diff"))
				m.set_shader_parameter(layer + "_normal", Common.ph(t, "nor_gl"))
				m.set_shader_parameter(layer + "_arm", Common.ph(t, "arm"))
			m.set_shader_parameter("cobble_albedo", cob_a)
			m.set_shader_parameter("cobble_normal", load("res://assets/art/textures/cobblestone_normal.png"))
			m.set_shader_parameter("cobble_arm", load("res://assets/art/textures/cobblestone_arm.png"))
			var n := FastNoiseLite.new()
			n.frequency = 0.01
			n.fractal_octaves = 3
			var nt := NoiseTexture2D.new()
			nt.width = 512
			nt.height = 512
			nt.noise = n
			nt.generate_mipmaps = true
			m.set_shader_parameter("macro_noise", nt)
			m.set_shader_parameter("tile_size", 4.0)
		"B":
			m.shader = _shader("lab_ground_toon")
			_ground_common(m, cob_a)
			m.set_shader_parameter("saturation", 1.15)
			m.set_shader_parameter("posterize", 0.55)
			m.set_shader_parameter("grass_tint", Color(0.9, 1.1, 0.62))
			m.set_shader_parameter("mud_tint", Color(1.1, 0.95, 0.85))
			m.set_shader_parameter("cobble_tint", Color(1.05, 0.98, 0.9))
		"C":
			m.shader = _shader("lab_ground")
			m.set_shader_parameter("mode", 1)
			var set_names := {"grass": "leafy_grass", "mud": "brown_mud_02", "cobble": "cobblestone_floor_01"}
			for k: String in set_names:
				var t: String = set_names[k]
				m.set_shader_parameter(k + "_a", Common.ph(t, "diff"))
				m.set_shader_parameter(k + "_n", Common.ph(t, "nor_gl"))
				m.set_shader_parameter(k + "_r", Common.ph(t, "arm"))
			m.set_shader_parameter("noise_tex", Common.noise())
			m.set_shader_parameter("saturation", 0.72)
			m.set_shader_parameter("grass_tint", Color(0.75, 0.78, 0.55))
			m.set_shader_parameter("mud_tint", Color(0.8, 0.72, 0.62))
			m.set_shader_parameter("cobble_tint", Color(0.85, 0.82, 0.78))
			m.set_shader_parameter("puddles", 1.0)
			m.set_shader_parameter("tile", 3.0)
		"G":
			m.shader = _shader("lab_ground")
			m.set_shader_parameter("mode", 1)
			var gset := {"grass": "leafy_grass", "mud": "brown_mud_02", "cobble": "cobblestone_floor_01"}
			for k: String in gset:
				var t: String = gset[k]
				m.set_shader_parameter(k + "_a", Common.ph(t, "diff"))
				m.set_shader_parameter(k + "_n", Common.ph(t, "nor_gl"))
				m.set_shader_parameter(k + "_r", Common.ph(t, "arm"))
			m.set_shader_parameter("noise_tex", Common.noise())
			m.set_shader_parameter("tile", 3.2)
			m.set_shader_parameter("saturation", 1.0)
			m.set_shader_parameter("cobble_tint", Color(1.0, 0.96, 0.9))
			m.set_shader_parameter("mud_tint", Color(1.15, 0.95, 0.78))
			m.set_shader_parameter("grass_tint", Color(0.85, 1.15, 0.5))
			m.set_shader_parameter("puddles", 0.0)
		_:
			m.shader = _shader("lab_ground")
			m.set_shader_parameter("mode", 2)
			_ground_common(m, cob_a)
			m.set_shader_parameter("saturation", 1.22)
			m.set_shader_parameter("grass_tint", Color(0.88, 1.12, 0.55))
			m.set_shader_parameter("mud_tint", Color(1.12, 0.92, 0.78))
			m.set_shader_parameter("cobble_tint", Color(1.08, 1.0, 0.9))
			if id == "F":
				m.set_shader_parameter("saturation", 1.4)
				m.set_shader_parameter("grass_tint", Color(0.82, 1.15, 0.45))
	_cache[key] = m
	return m


static func _ground_common(m: ShaderMaterial, cob: Texture2D) -> void:
	m.set_shader_parameter("grass_a", Common.ph("leafy_grass", "diff"))
	m.set_shader_parameter("mud_a", Common.ph("brown_mud_02", "diff"))
	m.set_shader_parameter("cobble_a", cob)
	m.set_shader_parameter("noise_tex", Common.noise())
	m.set_shader_parameter("tile", 3.0)


static func _shader(n: String) -> Shader:
	var key := "sh" + n
	if not _cache.has(key):
		_cache[key] = load(SH + n + ".gdshader")
	return _cache[key]


# G specials: stone gatehouse, iron, lion banners, flags --------------------------------------------------------

static func _gate_special(role: String, orig: Material, _mi: MeshInstance3D) -> Material:
	var key := "gate_" + role
	if _cache.has(key):
		return _cache[key]
	var m: Material
	match role:
		"gate_stone":
			var sh := Shader.new()
			sh.code = (load(SH + "lab_grounded.gdshader") as Shader).code.replace("cull_back", "cull_disabled")
			var sm := ShaderMaterial.new()
			sm.shader = sh
			sm.set_shader_parameter("atlas", Common.white())
			sm.set_shader_parameter("atlas_color", Color(0.9, 0.93, 0.97, 1.0))
			for pre in ["a", "b"]:
				sm.set_shader_parameter(pre + "_alb", Common.ph("castle_wall_slates", "diff"))
				sm.set_shader_parameter(pre + "_nor", Common.ph("castle_wall_slates", "nor_gl"))
				sm.set_shader_parameter(pre + "_arm", Common.ph("castle_wall_slates", "arm"))
			sm.set_shader_parameter("noise_tex", Common.noise())
			sm.set_shader_parameter("tile_a", 4.0)
			sm.set_shader_parameter("tile_b", 4.0)
			sm.set_shader_parameter("detail", 1.0)
			sm.set_shader_parameter("chroma_keep", 0.0)
			sm.set_shader_parameter("saturation", 0.8)
			sm.set_shader_parameter("grime", 0.35)
			sm.set_shader_parameter("moss", 0.12)
			m = sm
		"iron":
			var b := StandardMaterial3D.new()
			b.albedo_color = Color(0.16, 0.15, 0.15)
			b.metallic = 0.7
			b.roughness = 0.5
			m = b
		"banner":
			var b2 := StandardMaterial3D.new()
			b2.albedo_texture = _lion_texture()
			b2.cull_mode = BaseMaterial3D.CULL_DISABLED
			b2.roughness = 0.9
			if orig is BaseMaterial3D:
				b2.albedo_texture = (orig as BaseMaterial3D).albedo_texture if (orig as BaseMaterial3D).albedo_texture else _lion_texture()
			m = b2
		_:
			var f := StandardMaterial3D.new()
			f.albedo_color = Color(0.82, 0.12, 0.1)
			f.cull_mode = BaseMaterial3D.CULL_DISABLED
			f.roughness = 0.9
			m = f
	_cache[key] = m
	return m


static func _lion_texture() -> Texture2D:
	if _cache.has("lion"):
		return _cache["lion"]
	var w := 128
	var h := 320
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.78, 0.1, 0.09))
	var gold := Color(0.95, 0.74, 0.22)
	for x in w:
		for y in h:
			if x < 8 or x > w - 9 or y < 8 or (y > h - 70 and abs(x - w / 2) < (h - y) * 0.9 * 0.5 + 0) and false:
				img.set_pixel(x, y, gold)
	# border
	for x in w:
		for y in 8:
			img.set_pixel(x, y, gold)
	for y in h:
		for x in 8:
			img.set_pixel(x, y, gold)
			img.set_pixel(w - 1 - x, y, gold)
	# swallow-tail bottom: transparent triangle
	for x in w:
		for y in range(h - 44, h):
			var t := float(y - (h - 44)) / 44.0
			if absf(x - w * 0.5) < t * w * 0.5:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	# crest: gold lion-ish emblem (head disc, mane ring, body diamond)
	var cx := w * 0.5
	var cy := h * 0.38
	for x in w:
		for y in h:
			var d := Vector2(x - cx, y - cy)
			var mane := d.length()
			if (mane < 30.0 and mane > 21.0) or mane < 14.0:
				img.set_pixel(x, y, gold)
			elif absf(d.x) + absf(d.y - 52.0) < 34.0:
				img.set_pixel(x, y, gold)
	var t := ImageTexture.create_from_image(img)
	_cache["lion"] = t
	return t
