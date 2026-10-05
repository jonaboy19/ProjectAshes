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
## Grade constants (one place; bake_style_g.gd re-bakes env_*.tres from apply_environment).
const AMBIENT_HEX := "aab8ee"
const FOG_HEX := "e9d6ae"
const LUT_SHADOW := "0c1640"
const LUT_MID := "8a8a94"
const LUT_HIGH := "fff0d0"

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


static func make_sky(noise: Texture2D = null, game := false) -> Sky:
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
	if game:
		s.process_mode = Sky.PROCESS_MODE_INCREMENTAL      # the sun moves: spread the (tiny) radiance update over frames
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
static func apply_environment(env: Environment, tier := "high", game := false) -> void:
	env.background_mode = Environment.BG_SKY
	env.sky = make_sky(null, game)
	# fake GI, part 1: ambient is the sky colour, slightly warmed so shadows stay blue-violet but never cold grey
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("aab8ee")
	env.ambient_light_energy = 0.48            # deeper shadows (local GPU pass 2026-10-01; was 0.66)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
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
	env.fog_light_color = Color("e2dccc")            # slightly warm haze (was cool d9e3f2)
	env.fog_density = 0.0030
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = tier != "low"
	env.adjustment_saturation = 1.22
	env.adjustment_contrast = 1.6     # pass 3: contrast metric 0.19 -> target 0.23
	env.adjustment_color_correction = lut(Color("0c1640"), Color("8a8a94"), Color("fff4e2"))   # pass 3: cooler highs (warmth 1.45 -> 1.34); mids 8a88a4 -> 8a8a94: less pink
	if game:
		_game_environment(env, tier)



## Game-only differences: the world is km wide, the lab 45 m (thinner fog, volumetric fog tuned for Ultra).
## Quality (autoload) owns SSAO/glow/shadows per tier and is re-applied after this by its node-added hook.
static func _game_environment(env: Environment, tier: String) -> void:
	# AAA presentation pass 2026-10-06 (docs/art/AAA_PRESENTATION_REVIEW.md, phone review): less saturation and exposure, a
	# controlled bloom (the SOFTLIGHT glow washed the S22 frame out), shadows still cool but no longer navy, and more depth haze.
	env.set_meta("game_look", true)
	env.tonemap_exposure = 0.86
	env.glow_intensity = 0.28
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.25
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.32
	env.adjustment_color_correction = lut(Color("231d28"), Color("8e8a88"), Color("fff2dc"))
	env.fog_density = 0.0027
	env.fog_aerial_perspective = 0.45
	env.fog_sky_affect = 0.0
	env.volumetric_fog_albedo = Color("f2e2c0")
	env.volumetric_fog_density = 0.0015
	env.volumetric_fog_length = 64.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0


## Quality tier index (LOW 0, MEDIUM 1, HIGH 2, ULTRA 3) -> Style G tier name.
static func tier_name(quality_tier: int) -> String:
	return "low" if quality_tier <= 0 else ("medium" if quality_tier == 1 else "high")


## Current game tier from the Quality autoload ("high" when there is none, e.g. in tools).
static func current_tier() -> String:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var q: Node = (loop as SceneTree).root.get_node_or_null("Quality")
		if q != null and "tier" in q:
			return tier_name(int(q.get("tier")))
	return "high"


# --- day / night ----------------------------------------------------------------------------------------------------
# Style G is the 15:00 look. The other hours interpolate the SAME palette (sun, ambient, haze, sky gradient, bounce) so
# morning, golden hour, dusk and night stay in the family: warm key, violet shadows, never grey. Keys are in "solar hours":
# 6 = sunrise, 18 = sunset (see solar_hour(): the seasons' day length is squeezed into that range).
# Columns: hour, sun colour, sun energy, ambient colour, ambient energy, fog colour, sky top, sky horizon, sky ground,
# cloud, cloud shade, fill energy, background energy, sun glow, sun elevation (rad).
const DAY_KEYS := [
	[0.0, "7f98e8", 0.40, "3a4a9a", 0.34, "1a2142", "060b22", "141c44", "0a0f22", "6f7fb0", "232d5a", 0.0, 0.45, 0.0, 0.62],
	[4.8, "7f98e8", 0.34, "3e4e9c", 0.34, "202850", "0a1236", "27305e", "10152c", "7a86b8", "2a3466", 0.0, 0.50, 0.0, 0.50],
	[5.8, "ff9a5a", 0.75, "7d78b8", 0.45, "e0a07a", "34408a", "f0a070", "4a4a52", "ffb890", "7a6ca8", 0.08, 0.90, 0.9, 0.10],
	[7.0, "ffb878", 1.9, "98a2dc", 0.56, "f2c898", "2c58c8", "f4d0a8", "7a8a60", "fff0e0", "b0b8e0", 0.20, 1.0, 0.7, 0.30],
	[9.5, "ffcf94", 2.5, "a2b2e8", 0.62, "f0d6a8", "2461d4", "dee4f8", "88985f", "ffffff", "b2c2e8", 0.26, 1.0, 0.55, 0.62],
	[12.0, "ffd89c", 2.8, "a8b8ee", 0.64, "eedcb4", "2563d8", "d8e6ff", "8a9a6a", "ffffff", "b4c4e8", 0.28, 1.0, 0.5, 0.82],
	[15.0, SUN_COLOR, SUN_ENERGY, AMBIENT_HEX, 0.56, FOG_HEX, "2563d8", "d8e6ff", "8a9a6a", "ffffff", "b4c4e8", 0.30, 1.0, 0.5, 0.70],
	[17.0, "ffb064", 2.3, "b0a8e0", 0.58, "f4cc90", "2c58cc", "f8d4a0", "8a9060", "fff0dc", "c0b4dc", 0.30, 1.0, 0.7, 0.42],
	[18.0, "ff8c48", 1.2, "9a8cd0", 0.50, "f0a070", "35459a", "ff9a60", "6a5a4a", "ffb488", "8a6ca4", 0.18, 0.95, 1.0, 0.14],
	[18.8, "ff6a40", 0.45, "5e5aa8", 0.40, "b4688a", "1e2868", "d0627a", "3a3446", "e08a8a", "4e4488", 0.04, 0.80, 0.8, 0.07],
	[19.8, "8fa4ff", 0.42, "3e4e9c", 0.34, "26305a", "0a1238", "2a346a", "10152c", "7a86b8", "2a3466", 0.0, 0.55, 0.0, 0.40],
	[24.0, "7f98e8", 0.40, "3a4a9a", 0.34, "1a2142", "060b22", "141c44", "0a0f22", "6f7fb0", "232d5a", 0.0, 0.45, 0.0, 0.62],
]
## A lerp-able copy of DAY_KEYS with Colors parsed once.
static var _keys: Array = []


static func _day_keys() -> Array:
	if _keys.is_empty():
		for k: Array in DAY_KEYS:
			var row: Array = []
			for v: Variant in k:
				row.append(Color(v) if v is String else v)
			_keys.append(row)
	return _keys


## Hours of the clock -> solar hours (6 = sunrise, 18 = sunset) for any day length (Seasons.daylight_of).
static func solar_hour(t: float, sunrise := 6.0, sunset := 18.0) -> float:
	t = fposmod(t, 24.0)
	sunrise = clampf(sunrise, 3.0, 10.0)
	sunset = clampf(sunset, sunrise + 6.0, 22.0)
	if t >= sunrise and t <= sunset:
		return 6.0 + (t - sunrise) / (sunset - sunrise) * 12.0
	var night_len := 24.0 - (sunset - sunrise)
	var dt := t - sunset if t > sunset else t + 24.0 - sunset
	return fposmod(18.0 + dt / night_len * 12.0, 24.0)


## The G palette at a clock time: Dictionary of every column (see DAY_KEYS) as Colors/floats. `hour` is a SOLAR hour.
static func palette_at(hour: float) -> Dictionary:
	var keys := _day_keys()
	hour = fposmod(hour, 24.0)
	var a: Array = keys[0]
	var b: Array = keys[keys.size() - 1]
	for i in keys.size() - 1:
		if hour >= float(keys[i][0]) and hour <= float(keys[i + 1][0]):
			a = keys[i]
			b = keys[i + 1]
			break
	var span := maxf(float(b[0]) - float(a[0]), 0.0001)
	var f := smoothstep(0.0, 1.0, (hour - float(a[0])) / span)
	var out := {}
	var names := ["hour", "sun_color", "sun_energy", "ambient_color", "ambient_energy", "fog", "sky_top", "sky_horizon",
		"sky_ground", "cloud", "cloud_shade", "fill_energy", "bg_energy", "sun_glow", "sun_elev"]
	for i in names.size():
		var va: Variant = a[i]
		var vb: Variant = b[i]
		out[names[i]] = (va as Color).lerp(vb, f) if va is Color else lerpf(float(va), float(vb), f)
	return out


## Applies the palette for a clock time to the sun, fill and environment (and the sky shader). `hour` = SOLAR hour.
## Only writes what the game's cycle already wrote (sun colour/energy/rotation, ambient, fog colour, background energy)
## plus the sky colours and the bounce fill, so weather.gd (which scales those on top) keeps working.
## Returns the palette. Sun rotation: azimuth sweeps east -> west over the day like the old cycle; elevation from the palette.
static func apply_daylight(env: Environment, sun: DirectionalLight3D, fill: DirectionalLight3D, hour: float, clock := -1.0) -> Dictionary:
	var p := palette_at(hour)
	var clk := clock if clock >= 0.0 else hour
	if sun:
		var az := PI * 0.25 + (clk - 12.0) / 12.0 * PI * 0.5
		sun.rotation = Vector3(-float(p["sun_elev"]), az, 0.0)
		sun.light_color = p["sun_color"]
		sun.light_energy = float(p["sun_energy"])
		if fill:
			# the bounce travels back up toward the sun: mirror of the key's forward vector, flattened a little
			var f := -sun.global_transform.basis.z if sun.is_inside_tree() else -Basis.from_euler(sun.rotation).z
			var up := Vector3(-f.x * 0.8, absf(f.y) * 0.8 + 0.25, -f.z * 0.8).normalized()
			fill.transform = Transform3D(Basis.looking_at(up, Vector3.UP if absf(up.y) < 0.99 else Vector3.RIGHT), fill.transform.origin)
			fill.light_energy = float(p["fill_energy"])
	if env:
		var amb: Color = p["ambient_color"]
		if env.has_meta("game_look"):
			amb = amb.lerp(Color("c4b4a4"), 0.5 * clampf(float(p["sun_energy"]) / 2.5, 0.0, 1.0))     # day only (night stays moonlit blue); pass 3: warm-neutral shadow side (blue-grey patches on the ground read flat)
		env.ambient_light_color = amb
		env.ambient_light_energy = float(p["ambient_energy"])
		if env.has_meta("game_look"):
			# AAA pass 5: night read murky on the phone (NPCs black silhouettes): a moonlit floor for the ambient
			env.ambient_light_energy = maxf(float(p["ambient_energy"]), 0.85)
		env.fog_light_color = p["fog"]
		env.background_energy_multiplier = float(p["bg_energy"])
		var sm := env.sky.sky_material as ShaderMaterial if env.sky else null
		if sm:
			sm.set_shader_parameter("top_color", p["sky_top"])
			sm.set_shader_parameter("horizon_color", p["sky_horizon"])
			sm.set_shader_parameter("ground_color", p["sky_ground"])
			sm.set_shader_parameter("cloud_color", p["cloud"])
			sm.set_shader_parameter("cloud_shade", p["cloud_shade"])
			sm.set_shader_parameter("sun_glow", float(p["sun_glow"]))
			sm.set_shader_parameter("sun_color", p["sun_color"])
	return p


# --- lights ------------------------------------------------------------------------------------------------------

const SUN_FORWARD := Vector3(0.55, -0.62, -0.55)     # from behind-left: shadows fall forward-right as in target 03
const SUN_COLOR := "ffe0bc"     # 2026-10-01 pass 2: warmth 1.46 -> toward 1.34
const SUN_ENERGY := 3.0

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


## Weathering strength per role (lab_polished `weather`): relief, grime from the foot, streaks, worn seams.
## Pack: assets/generated/style_g/weather_pack.png (tools_qa/style_lab/make_weather_pack.py).
const WEATHER := {"house": 1.0, "timber": 0.5, "plaster": 1.0, "stone": 0.9, "roof": 0.6, "cloth": 0.3, "awning": 0.3, "cobble": 0.4, "foliage": 0.0, "stall": 0.8, "wood": 0.5, "lamp": 0.5, "goods": 0.25, "tree": 0.0, "ivy": 0.0, "flowers": 0.0, "banner": 0.0, "flag": 0.0}
static var _weather_tex: Texture2D


static func weather_pack() -> Texture2D:
	if _weather_tex == null:
		_weather_tex = load("res://assets/generated/style_g/weather_pack.png")
	return _weather_tex


static func white() -> Texture2D:
	if _white_tex == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	return _white_tex


## albedo texture / colour / vertex colour / uv of a BaseMaterial3D (what the polished shader needs). {} for others.
static func params(m: Material) -> Dictionary:
	m = source_of(m)
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		var cut := 0.0
		if b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			cut = b.alpha_scissor_threshold
		return {"tex": b.albedo_texture, "color": b.albedo_color, "vcol": b.vertex_color_use_as_albedo, "vsrgb": b.vertex_color_is_srgb,
			"uv_scale": Vector2(b.uv1_scale.x, b.uv1_scale.y), "uv_offset": Vector2(b.uv1_offset.x, b.uv1_offset.y), "cut": cut}
	return {}


## A material this kit made remembers the asset material it came from (meta "g_src"), so restyling twice is a no-op.
static func source_of(m: Material) -> Material:
	if m is ShaderMaterial and (m as ShaderMaterial).has_meta("g_src"):
		return (m as ShaderMaterial).get_meta("g_src")
	return m


## True for a material this kit made (do not restyle again).
static func is_styled(m: Material) -> bool:
	return m is ShaderMaterial and (m as ShaderMaterial).has_meta("g_src")


## Game mode (set once by main.gd): AO ramp from height above each instance's origin (terrain is not at y = 0) and
## sRGB-baked vertex / instance colours (town tints) are converted like StandardMaterial3D did.
static var game_mode := false


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
	orig = source_of(orig) if orig else null
	var key := "%s|%s|%d|%d|%s|%d" % [role, _look_key(orig), skin_kind, int(use_vcol), tier, int(game_mode)]
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


## Two asset materials that render the same (name, albedo texture, colour, vertex-colour flags) share ONE Style G material,
## so the same look from different GLBs batches into the same draw call.
static func _look_key(m: Material) -> String:
	if m == null:
		return "0"
	if m is BaseMaterial3D:
		var b := m as BaseMaterial3D
		var tex := "-"
		if b.albedo_texture:
			tex = b.albedo_texture.resource_path if b.albedo_texture.resource_path != "" else str(b.albedo_texture.get_instance_id())
		return "%s|%s|%s|%d%d|%d|%d|%.2f" % [b.resource_name, tex, b.albedo_color.to_html(), int(b.vertex_color_use_as_albedo),
			int(b.vertex_color_is_srgb), b.transparency, b.cull_mode, b.alpha_scissor_threshold]
	return str(m.get_instance_id())


static func _polished(role: String, orig: Material, skin_kind: int, tier: String, use_vcol := true) -> Material:
	var p := params(orig) if orig else {"tex": null, "color": Color.WHITE, "vcol": true, "uv_scale": Vector2.ONE, "uv_offset": Vector2.ZERO, "cut": 0.0}
	if p.is_empty():
		return null
	var sm := ShaderMaterial.new()
	if is_char(role):
		sm.shader = _shader("lab_char")
		sm.set_shader_parameter("kind", skin_kind)
		sm.set_shader_parameter("saturation", 1.1)   # pass 6: 1.3 made clothes candy-bright (target 03 crowd is muted)
	else:
		sm.shader = _shader("lab_polished_lite" if tier == "low" else "lab_polished")
	sm.set_shader_parameter("albedo_tex", p["tex"] if p["tex"] != null else white())
	sm.set_shader_parameter("albedo_color", p["color"])
	sm.set_shader_parameter("use_vertex_color", p["vcol"])
	sm.set_meta("g_src", orig if orig else StandardMaterial3D.new())
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
	sm.set_shader_parameter("weather_tex", weather_pack())
	sm.set_shader_parameter("weather", WEATHER.get(role, 0.6))
	if game_mode:
		sm.set_shader_parameter("local_ao", true)
		sm.set_shader_parameter("vcol_srgb", p["vsrgb"] if p["vcol"] else true)
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
			sm.set_shader_parameter("vao_strength", 1.0)
			# AAA pass 2: Meshy thatch and plaster glinted like crystal close up (spec + rim on faceted normals): matte houses
			sm.set_shader_parameter("spec", 0.08)
			sm.set_shader_parameter("roughness", 0.95)
			sm.set_shader_parameter("bump_amount", 0.12)
			sm.set_shader_parameter("rim_amount", 0.12)
			sm.set_shader_parameter("normal_soften", 0.55)
		"stall":
			sm.set_shader_parameter("saturation", 0.82)      # richer, calmer cloth (target awnings are faded, not candy)
			sm.set_shader_parameter("value_gain", 0.93)
			sm.set_shader_parameter("warm_tint", Color(1.02, 0.97, 0.88))
			sm.set_shader_parameter("ao_strength", 0.4)
		"timber":                       # frames, beams, posts, crates, fences: grain readable, not orange
			sm.set_shader_parameter("saturation", 1.06)
			sm.set_shader_parameter("value_gain", 0.96)
			sm.set_shader_parameter("ao_strength", 0.45)
			sm.set_shader_parameter("roughness", 0.85)
			sm.set_shader_parameter("bounce", 0.28)
		"plaster":                      # warm cream, weathered by the height AO, never white
			sm.set_shader_parameter("saturation", 0.95)
			sm.set_shader_parameter("value_gain", 0.94)
			sm.set_shader_parameter("warm_tint", Color(1.0, 0.97, 0.9))
			sm.set_shader_parameter("ao_height", 1.6)
			sm.set_shader_parameter("ao_strength", 0.5)
		"stone":                        # walls, plinths, wells, chimneys (atlas stone, polished shader)
			sm.set_shader_parameter("saturation", 0.88)
			sm.set_shader_parameter("value_gain", 0.95)
			sm.set_shader_parameter("ao_height", 1.8)
			sm.set_shader_parameter("ao_strength", 0.5)
		"roof":                         # slate blue / terracotta: keep the chroma, soften the rim
			sm.set_shader_parameter("saturation", 1.06)
			sm.set_shader_parameter("value_gain", 0.95)
			sm.set_shader_parameter("ao_strength", 0.15)
			sm.set_shader_parameter("rim_amount", 0.3)
			# AAA pass 2: thatch and slate read as crystal up close (specular on the per-face Meshy normals + bump);
			# roofs are matte: near-zero spec, full roughness, very little bump.
			sm.set_shader_parameter("roughness", 0.97)
			sm.set_shader_parameter("spec", 0.04)
			sm.set_shader_parameter("bump_amount", 0.05)
			sm.set_shader_parameter("normal_soften", 0.55)
		"cobble":                       # paving props and plinth caps
			sm.set_shader_parameter("saturation", 1.0)
			sm.set_shader_parameter("warm_tint", Color(1.04, 0.97, 0.86))
			sm.set_shader_parameter("ao_strength", 0.4)
		"awning", "cloth":              # striped awnings, bunting, wall banners: saturated cloth, soft sheen, sun-faded
			sm.set_shader_parameter("saturation", 1.1)
			sm.set_shader_parameter("value_gain", 0.97)
			sm.set_shader_parameter("ao_strength", 0.25)
			sm.set_shader_parameter("roughness", 0.92)
			sm.set_shader_parameter("bounce", 0.3)
		"foliage":                      # hedges, bushes, vines on the ground
			sm.set_shader_parameter("saturation", 1.1)
			sm.set_shader_parameter("value_gain", 0.92)
			sm.set_shader_parameter("ao_strength", 0.0)
			sm.set_shader_parameter("roughness", 0.9)
			sm.set_shader_parameter("rim_amount", 0.35)
			sm.set_shader_parameter("bounce", 0.28)
		"goods":                        # market goods: less orange, per-piece variation from COLOR.a (see MarketGoods.layout)
			sm.set_shader_parameter("saturation", 0.9)            # local pass 6: was 1.0 (orange sacks in the foreground)
			sm.set_shader_parameter("value_gain", 0.92)
			sm.set_shader_parameter("ao_strength", 0.3)
			sm.set_shader_parameter("bounce", 0.2)
			sm.set_shader_parameter("ground_bounce", Color(0.95, 0.74, 0.5))
			if game_mode:                  # lab goods meshes have COLOR.a = 1 (no per-piece random): a uniform hue shift turned every barrel/sack yellow
				sm.set_shader_parameter("hue_var", 0.5)
				sm.set_shader_parameter("val_var", 0.28)
		"ivy":
			sm.set_shader_parameter("saturation", 0.8)             # pass 6: was 0.95 (neon)
			sm.set_shader_parameter("value_gain", 0.72)
			sm.set_shader_parameter("ao_strength", 0.0)
			sm.set_shader_parameter("rim_amount", 0.2)
			sm.set_shader_parameter("bounce", 0.25)
		"flowers":
			sm.set_shader_parameter("saturation", 1.15)
			sm.set_shader_parameter("ao_strength", 0.0)
		_:
			sm.set_shader_parameter("saturation", 0.9 if role in ["wood", "goods"] else 1.12)   # pass 6: barrels/crates still orange at 1.0
			sm.set_shader_parameter("value_gain", 0.9 if role in ["wood", "goods"] else 1.04)
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
	m.set_shader_parameter("cobble_tint", Color(1.0, 0.95, 0.82))     # golden cobbles (pass 3: less orange) (0.84 blue read pink)
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
	sm.set_shader_parameter("normal_depth", 1.7)                  # gate block relief (pass 2)
	sm.set_shader_parameter("b_alb", ph("medieval_blocks_02", "diff"))   # second layer: bigger dressed blocks, breaks the slate rhythm
	sm.set_shader_parameter("b_nor", ph("medieval_blocks_02", "nor_gl"))
	sm.set_shader_parameter("b_arm", ph("medieval_blocks_02", "arm"))
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


# --- game integration: restyle asset meshes by role ---------------------------------------------------------------------

## Ordered [token, role] checks on an asset key or GLB file name (first match wins; lower case, ":lodN" and "_lodN" ignored).
const ASSET_ROLE_TOKENS := [
	["stall", "stall"], ["stand", "stall"], ["lamp", "lamp"], ["banner", "cloth"], ["bunting", "cloth"], ["sign", "cloth"],
	["flower", "flowers"], ["wall", "stone"], ["gate", "stone"], ["well", "stone"], ["bridge", "stone"], ["milestone", "stone"],
	["house", "house"], ["barn", "house"], ["granary", "house"], ["mill", "house"], ["chapel", "house"], ["temple", "house"],
	["castle", "house"], ["keep", "house"], ["tower", "house"], ["inn", "house"], ["guild", "house"], ["blacksmith", "house"],
	["healer", "house"], ["stable", "house"], ["hut", "house"], ["fort", "house"], ["manor", "house"], ["sawmill", "house"],
	["shrine", "stone"], ["ruin", "stone"],
	["church", "house"], ["lantern", "lamp"], ["sconce", "lamp"], ["torch_stake", "timber"], ["torch", "lamp"], ["tapestry", "cloth"], ["pillar", "stone"], ["arch_", "stone"], ["_arch", "stone"],
]


static func role_for_asset(key: String) -> String:
	var k := key.get_slice(":lod", 0).to_lower()
	for pair: Array in ASSET_ROLE_TOKENS:
		if k.contains(String(pair[0])):
			return pair[1]
	return "timber"


## Material resource names of the Blender sets (RG_* region kit, RA_* village kit) -> role; "" = use the asset's default role.
static func role_for_material(name: String) -> String:
	var n := name.to_lower()
	if n.contains("roof") or n.contains("shingle") or n.contains("slate") or n.contains("thatch") or n.contains("hay"):
		return "roof"
	if n.contains("plaster"):
		return "plaster"
	if n.contains("stone") or n.contains("cliff") or n.contains("rock") or n.contains("ruin") or n.contains("moss"):
		return "stone"
	if n.contains("canvas") or n.contains("cloth") or n.contains("hide") or n.contains("paper"):
		return "cloth"
	if n.contains("timber") or n.contains("plank") or n.contains("log") or n.contains("wood"):
		return "timber"
	if n.contains("soil") or n.contains("path") or n.contains("cobble"):
		return "cobble"
	if n.contains("plant") or n.contains("crop") or n.contains("meadow"):
		return "foliage"
	if n.contains("iron") or n.contains("metal"):
		return "iron_polished"
	return ""


## Surfaces that must keep their own material: lit windows and lamps (emission), glass/water (transparent).
static func keeps_material(m: Material) -> bool:
	if not (m is BaseMaterial3D):
		return true
	var b := m as BaseMaterial3D
	if b.emission_enabled or b.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA or b.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return true
	var n := b.resource_name.to_lower()
	return n.contains("glass") or n.contains("water") or n.contains("winlit") or n.contains("lamp")


## Restyles every surface of an asset mesh (in place) with the Style G material of its role. Atlas albedo, vertex colours and
## MultiMesh instance colours (town tints) keep working: the surface material reads COLOR like the old vertex-colour copy.
## Idempotent. `mesh` comes from Assets.building_mesh (cached once per key and LOD).
static func restyle_mesh(mesh: ArrayMesh, key: String, tier := "", role := "") -> ArrayMesh:
	if mesh == null:
		return mesh
	if tier == "":
		tier = current_tier()
	if role == "":
		role = role_for_asset(key)
	for i in mesh.get_surface_count():
		var orig := mesh.surface_get_material(i)
		if orig == null or is_styled(orig) or keeps_material(orig):
			continue
		var b := orig as BaseMaterial3D
		var src: Material = orig
		var fmt_col := (mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) != 0
		if not b.vertex_color_use_as_albedo and not fmt_col:
			src = _vcol_copy(b)                     # no baked colours: let instance colours tint it (town identity)
		var r := role
		var by_name := role_for_material(b.resource_name)
		if by_name != "":
			r = by_name
		if r == "iron_polished":
			r = "timber"
		var m: Material
		if role == "stone" and tier != "low" and key.get_slice(":lod", 0).begins_with("wall"):
			m = _gate_stone_game()
		else:
			m = material_for(r, src, 1, tier, true)
		if m is ShaderMaterial and b.cull_mode == BaseMaterial3D.CULL_DISABLED and not (m as ShaderMaterial).shader.code.contains("cull_disabled"):
			var dk := "ds|%d" % m.get_instance_id()          # leaf cards / banners are double sided
			if not _cache.has(dk):
				_cache[dk] = double_sided(m as ShaderMaterial)
			m = _cache[dk]
		if m != null:
			mesh.surface_set_material(i, m)
	if tier != "high":
		load("res://scripts/world/surface_collapse.gd").collapse(mesh, tier)      # LOW/MEDIUM: fewer surfaces = fewer draws
	return mesh


static func _vcol_copy(b: BaseMaterial3D) -> BaseMaterial3D:
	var k := "vcc%d" % b.get_instance_id()
	if not _cache.has(k):
		var c := b.duplicate() as BaseMaterial3D
		c.vertex_color_use_as_albedo = true
		c.vertex_color_is_srgb = true
		_cache[k] = c
	return _cache[k]


## Town walls and gates: the castle_wall_slates triplanar stone of the lab gate (MEDIUM/HIGH; LOW uses the atlas stone).
static func _gate_stone_game() -> Material:
	if not _cache.has("gate_stone_game"):
		_cache["gate_stone_game"] = _gate_stone()
	return _cache["gate_stone_game"]


## Role material for a mesh built in code with vertex colours (awnings, bunting, house-detail stand-ins, town banners).
## `srgb`: the mesh bakes sRGB colours (TownIdentity / HouseDetails do; the lab kit bakes linear).
static func vertex_color_material(role := "timber", srgb := true, tier := "") -> Material:
	if tier == "":
		tier = current_tier()
	var k := "vcm|%s|%d|%s|%d" % [role, int(srgb), tier, int(game_mode)]
	if not _cache.has(k):
		var base := StandardMaterial3D.new()
		base.vertex_color_use_as_albedo = true
		base.vertex_color_is_srgb = srgb
		_cache[k] = material_for(role, base, 1, tier, true)
	return _cache[k]
