extends RefCounted
## STYLE G ("Kingsreach gate market", docs/art/reference/03_TARGET_gate_market_detailed.webp): the ONE look of Rising Ashes.
## Single source of truth for the Environment, sun, fill, shadow tiers, palette and per-role materials.
## Skills: .claude/skills/ashes-style-g (recipe), -assets, -qa. Baked copies: resources/style_g/*.tres (tools_qa/style_lab/bake_style_g.gd).
## No class_name (project rule): `const StyleG := preload("res://scripts/style_g.gd")`.
##
##   StyleG.apply_environment(env, "high")        # fill an existing Environment (game: main.gd _build_environment)
##   StyleG.apply_sun(sun, "high")                # colour, energy, shadows of the key light
##   StyleG.make_fill()                           # warm bounce light (no shadow) from below/side; add once
##   StyleG.material_for("gate_stone")            # role -> Material (orig = the asset's BaseMaterial3D for atlas roles)

const SH := "res://shaders/style_lab/"
const PH := "res://assets/incoming/polyhaven/textures/%s/%s_%s_%s.jpg"

const TIERS := ["high", "medium", "low"]

## Palette (hex) of the style. Use these for any new colour; never pure black/white/grey.
const PALETTE := {
	"stone": "c9bfa8", "stone_shadow": "8f8aa0", "cobble": "c8b48a", "timber": "4a3220", "timber_light": "7a5330",
	"plaster": "efe3c8", "roof_slate": "5d7391", "roof_terracotta": "b4532f", "awning_red": "c8281e", "awning_white": "f4ecd8",
	"awning_green": "3f8a3c", "banner_red": "c71a17", "banner_gold": "f2bd38", "foliage": "5f9a2e", "foliage_rim": "b7d44a",
	"ivy": "3f7a24", "flower_red": "d8342b", "flower_pink": "e8789a", "flower_yellow": "f5c93a", "flower_purple": "8a62c8",
	"iron": "2a2827", "wood_crate": "9a6a38", "sack": "d9c28f", "hero_tunic": "4d7538", "hero_vest": "5c381f",
}

# --- Environment -------------------------------------------------------------------------------------------------

static func make_environment(tier := "high") -> Environment:
	var env := Environment.new()
	apply_environment(env, tier)
	return env


static func lut(shadow: Color, mid: Color, high: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, shadow)
	g.set_color(1, high)
	g.add_point(0.5, mid)
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 64
	return t


static func make_sky(noise: Texture2D = null) -> Sky:
	var m := ShaderMaterial.new()
	m.shader = load(SH + "lab_sky.gdshader")
	m.set_shader_parameter("top_color", Color("2563d8"))
	m.set_shader_parameter("horizon_color", Color("d8e6ff"))
	m.set_shader_parameter("ground_color", Color("8a9a6a"))
	m.set_shader_parameter("cloud_color", Color("ffffff"))
	m.set_shader_parameter("cloud_shade", Color("b4c4e8"))
	m.set_shader_parameter("cloud_cover", 0.55)
	m.set_shader_parameter("cloud_soft", 0.14)
	m.set_shader_parameter("posterize", 0.0)
	m.set_shader_parameter("sun_glow", 0.5)
	m.set_shader_parameter("cloud_noise", noise if noise else _noise())
	var s := Sky.new()
	s.sky_material = m
	s.radiance_size = Sky.RADIANCE_SIZE_32
	return s


static func _noise() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = 0.02
	n.fractal_octaves = 5
	n.fractal_gain = 0.55
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	return t


## Sets every Style-G property on `env`. Tier differences: HIGH = SSAO + glow + LUT; MEDIUM = no SSAO; LOW (Compatibility
## renderer) = no SSAO, no glow, no adjustment pass (the grade is baked into material saturation, see material_for).
static func apply_environment(env: Environment, tier := "high") -> void:
	env.background_mode = Environment.BG_SKY
	env.sky = make_sky()
	# fake GI, part 1: ambient is the sky colour, slightly warmed so shadows stay blue-violet but never cold grey
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("aab8ee")
	env.ambient_light_energy = 0.66
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.tonemap_white = 5.5
	env.ssao_enabled = tier == "high"
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.8
	env.ssao_light_affect = 0.2
	env.glow_enabled = tier != "low"
	env.glow_intensity = 0.5
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color("ecdcbc")            # slightly warm haze (was cool d9e3f2)
	env.fog_density = 0.0030
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = tier != "low"
	env.adjustment_saturation = 1.22
	env.adjustment_contrast = 1.3
	env.adjustment_color_correction = lut(Color("0a1240"), Color("8a88a4"), Color("fff0d0"))


# --- lights ------------------------------------------------------------------------------------------------------

const SUN_FORWARD := Vector3(0.55, -0.62, -0.55)     # from behind-left: shadows fall forward-right as in target 03
const SUN_COLOR := "ffd6a0"
const SUN_ENERGY := 2.7

## Shadow settings per tier: [mode, max_distance, atlas 4096/2048/1024 is a project setting (shadow_atlas)].
const SHADOW := {
	"high": {"mode": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "dist": 110.0},
	"medium": {"mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "dist": 70.0},
	"low": {"mode": DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, "dist": 45.0},
}


static func apply_sun(s: DirectionalLight3D, tier := "high") -> void:
	if s.is_inside_tree():
		s.look_at(s.global_position + SUN_FORWARD)
	else:
		s.look_at_from_position(Vector3.ZERO, SUN_FORWARD)
	s.light_color = Color(SUN_COLOR)
	s.light_energy = SUN_ENERGY
	s.shadow_enabled = true
	s.shadow_blur = 1.0
	s.light_angular_distance = 0.35
	s.directional_shadow_mode = SHADOW[tier]["mode"]
	s.directional_shadow_max_distance = SHADOW[tier]["dist"]


static func make_sun(tier := "high") -> DirectionalLight3D:
	var s := DirectionalLight3D.new()
	s.name = "SunG"
	apply_sun(s, tier)
	return s


## Fake GI part 2: warm golden bounce (sunlit cobbles/plaster) as a shadowless directional light travelling UP and
## back toward the sun, so it fills jetty undersides, awnings and the shadow side of walls.
static func make_fill() -> DirectionalLight3D:
	var f := DirectionalLight3D.new()
	f.name = "BounceG"
	f.look_at_from_position(Vector3.ZERO, Vector3(-0.45, 0.55, 0.45))
	f.light_color = Color("ffb870")
	f.light_energy = 0.3
	f.shadow_enabled = false
	f.light_specular = 0.0
	return f


# --- materials ----------------------------------------------------------------------------------------------------

static var _cache := {}
static var _tex := {}
static var _white_tex: ImageTexture


static func ph(set_name: String, kind: String, res := "2k") -> Texture2D:
	var key := set_name + kind + res
	if not _tex.has(key):
		var p := PH % [set_name, set_name, kind, res]
		if not ResourceLoader.exists(p):
			p = PH % [set_name, set_name, kind, "2k"]
		_tex[key] = load(p)
	return _tex[key]


static func white() -> Texture2D:
	if _white_tex == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex


## albedo texture / colour / vertex colour / uv of a BaseMaterial3D (what the polished shader needs). {} for others.
static func params(m: Material) -> Dictionary:
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		var cut := 0.0
		if b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			cut = b.alpha_scissor_threshold
		return {"tex": b.albedo_texture, "color": b.albedo_color, "vcol": b.vertex_color_use_as_albedo,
			"uv_scale": Vector2(b.uv1_scale.x, b.uv1_scale.y), "uv_offset": Vector2(b.uv1_offset.x, b.uv1_offset.y), "cut": cut}
	return {}


static func _shader(n: String) -> Shader:
	var key := "sh" + n
	if not _cache.has(key):
		_cache[key] = load(SH + n + ".gdshader")
	return _cache[key]


static func is_char(role: String) -> bool:
	return role in ["hero_new", "villager", "guard"]


## Role -> Material. Roles: ground, gate_stone, iron, banner, flag (no `orig` needed); house, stall, goods, wood, lamp,
## tree, flowers, ivy, hero_new, villager, guard (pass the asset's own material as `orig`; `skin_kind` 0 skin/1 cloth/2 hair/3 leather
## for characters). `tier` low swaps in lab_polished_lite (per-vertex lighting).
static func material_for(role: String, orig: Material = null, skin_kind := 1, tier := "high", use_vcol := true) -> Material:
	var key := "%s|%s|%d|%d|%s" % [role, orig.get_instance_id() if orig else 0, skin_kind, int(use_vcol), tier]
	if _cache.has(key):
		return _cache[key]
	var m: Material
	match role:
		"ground": m = _ground()
		"gate_stone": m = _gate_stone()
		"gate_trim":                     # dressed limestone for voussoirs/quoins: clean light blocks (polished shader, AO from height)
			var gb := StandardMaterial3D.new()
			gb.albedo_color = Color("dccfb4")
			m = _polished("house", gb, 1, tier, false)
			(m as ShaderMaterial).set_shader_parameter("saturation", 0.8)
			(m as ShaderMaterial).set_shader_parameter("value_gain", 1.0)
		"iron":
			var b := StandardMaterial3D.new()
			b.albedo_color = Color(PALETTE["iron"])
			b.metallic = 0.7
			b.roughness = 0.5
			m = b
		"banner":
			var b2 := StandardMaterial3D.new()
			b2.albedo_texture = lion_texture()
			if orig is BaseMaterial3D and (orig as BaseMaterial3D).albedo_texture:
				b2.albedo_texture = (orig as BaseMaterial3D).albedo_texture
			b2.cull_mode = BaseMaterial3D.CULL_DISABLED
			b2.roughness = 0.9
			m = b2
		"flag":
			var f := StandardMaterial3D.new()
			f.albedo_color = Color(PALETTE["banner_red"])
			f.cull_mode = BaseMaterial3D.CULL_DISABLED
			f.roughness = 0.9
			m = f
		_:
			m = _polished(role, orig, skin_kind, tier, use_vcol)
	_cache[key] = m
	return m


static func _polished(role: String, orig: Material, skin_kind: int, tier: String, use_vcol := true) -> Material:
	var p := params(orig) if orig else {"tex": null, "color": Color.WHITE, "vcol": true, "uv_scale": Vector2.ONE, "uv_offset": Vector2.ZERO, "cut": 0.0}
	if p.is_empty():
		return null
	var sm := ShaderMaterial.new()
	if is_char(role):
		sm.shader = _shader("lab_char")
		sm.set_shader_parameter("kind", skin_kind)
		sm.set_shader_parameter("saturation", 1.3)
	else:
		sm.shader = _shader("lab_polished_lite" if tier == "low" else "lab_polished")
	sm.set_shader_parameter("albedo_tex", p["tex"] if p["tex"] != null else white())
	sm.set_shader_parameter("albedo_color", p["color"])
	sm.set_shader_parameter("use_vertex_color", p["vcol"])
	sm.set_shader_parameter("uv_scale", p["uv_scale"])
	sm.set_shader_parameter("uv_offset", p["uv_offset"])
	if is_char(role):
		sm.set_shader_parameter("use_vertex_color", p["vcol"] and use_vcol)
		return sm
	if p["cut"] > 0.0:
		sm.set_shader_parameter("alpha_cut", p["cut"])
	# table per role (Style G values); ground_bounce/bounce = golden bounce from the cobbles
	sm.set_shader_parameter("ground_bounce", Color(1.0, 0.70, 0.36))
	sm.set_shader_parameter("sky_bounce", Color(0.55, 0.66, 0.98))
	sm.set_shader_parameter("rim_amount", 0.5)
	sm.set_shader_parameter("bounce", 0.36)
	match role:
		"tree":
			sm.set_shader_parameter("saturation", 1.15)
			sm.set_shader_parameter("ao_strength", 0.0)
			sm.set_shader_parameter("roughness", 0.9)
			sm.set_shader_parameter("rim_amount", 0.35)
			sm.set_shader_parameter("bounce", 0.3)
		"house":
			sm.set_shader_parameter("saturation", 1.0)
			sm.set_shader_parameter("value_gain", 0.9)
			sm.set_shader_parameter("warm_tint", Color(1.0, 0.97, 0.9))
			sm.set_shader_parameter("ao_height", 1.6)
			sm.set_shader_parameter("ao_strength", 0.5)
		"stall":
			sm.set_shader_parameter("saturation", 1.0)
			sm.set_shader_parameter("ao_strength", 0.4)
		"ivy":
			sm.set_shader_parameter("saturation", 0.95)
			sm.set_shader_parameter("value_gain", 0.78)
			sm.set_shader_parameter("ao_strength", 0.0)
			sm.set_shader_parameter("rim_amount", 0.2)
			sm.set_shader_parameter("bounce", 0.25)
		"flowers":
			sm.set_shader_parameter("saturation", 1.15)
			sm.set_shader_parameter("ao_strength", 0.0)
		_:
			sm.set_shader_parameter("saturation", 1.12)       # wood, goods, lamp, banner poles: warm but NOT orange
			sm.set_shader_parameter("ao_strength", 0.35)
			sm.set_shader_parameter("bounce", 0.3)
	return sm


## Double-sided variant of a shader (leaf cards, banners, gate walls with hand-built winding).
static func double_sided(sm: ShaderMaterial) -> ShaderMaterial:
	var d := sm.duplicate() as ShaderMaterial
	var sh := Shader.new()
	sh.code = sm.shader.code.replace("cull_back", "cull_disabled")
	d.shader = sh
	return d


static func _ground() -> Material:
	var m := ShaderMaterial.new()
	m.shader = _shader("lab_ground")
	m.set_shader_parameter("mode", 1)
	for k: String in {"grass": "leafy_grass", "mud": "brown_mud_02", "cobble": "cobblestone_floor_01"}:
		var t: String = {"grass": "leafy_grass", "mud": "brown_mud_02", "cobble": "cobblestone_floor_01"}[k]
		m.set_shader_parameter(k + "_a", ph(t, "diff"))
		m.set_shader_parameter(k + "_n", ph(t, "nor_gl"))
		m.set_shader_parameter(k + "_r", ph(t, "arm"))
	m.set_shader_parameter("noise_tex", _noise_cached())
	m.set_shader_parameter("tile", 3.2)
	m.set_shader_parameter("saturation", 1.0)
	m.set_shader_parameter("cobble_tint", Color(1.04, 0.95, 0.84))     # golden cobbles
	m.set_shader_parameter("mud_tint", Color(1.15, 0.95, 0.78))
	m.set_shader_parameter("grass_tint", Color(0.85, 1.15, 0.5))
	m.set_shader_parameter("puddles", 0.0)
	return m


static var _nz: NoiseTexture2D


static func _noise_cached() -> NoiseTexture2D:
	if _nz == null:
		var n := FastNoiseLite.new()
		n.frequency = 0.012
		n.fractal_octaves = 4
		_nz = NoiseTexture2D.new()
		_nz.width = 256
		_nz.height = 256
		_nz.seamless = true
		_nz.noise = n
		_nz.generate_mipmaps = true
	return _nz


static func _gate_stone() -> Material:
	var sh := Shader.new()
	sh.code = _shader("lab_grounded").code.replace("cull_back", "cull_disabled")
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("atlas", white())
	sm.set_shader_parameter("atlas_color", Color(0.95, 0.94, 0.92, 1.0))     # near-neutral limestone: the warm sun does the warming (a warm tint turns the slate texture brown)
	for pre in ["a", "b"]:
		sm.set_shader_parameter(pre + "_alb", ph("castle_wall_slates", "diff"))
		sm.set_shader_parameter(pre + "_nor", ph("castle_wall_slates", "nor_gl"))
		sm.set_shader_parameter(pre + "_arm", ph("castle_wall_slates", "arm"))
	sm.set_shader_parameter("noise_tex", _noise_cached())
	sm.set_shader_parameter("tile_a", 4.0)
	sm.set_shader_parameter("tile_b", 4.0)
	sm.set_shader_parameter("detail", 1.0)
	sm.set_shader_parameter("chroma_keep", 0.0)
	sm.set_shader_parameter("saturation", 0.8)
	sm.set_shader_parameter("grime", 0.35)
	sm.set_shader_parameter("moss", 0.12)
	return sm


static func lion_texture() -> Texture2D:
	if _cache.has("lion"):
		return _cache["lion"]
	var w := 128
	var h := 320
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(PALETTE["banner_red"]))
	var gold := Color(PALETTE["banner_gold"])
	for x in w:
		for y in 8:
			img.set_pixel(x, y, gold)
	for y in h:
		for x in 8:
			img.set_pixel(x, y, gold)
			img.set_pixel(w - 1 - x, y, gold)
	for x in w:
		for y in range(h - 44, h):
			var t := float(y - (h - 44)) / 44.0
			if absf(x - w * 0.5) < t * w * 0.5:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
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
	var tex := ImageTexture.create_from_image(img)
	_cache["lion"] = tex
	return tex
