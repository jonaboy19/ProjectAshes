extends Node3D
## Dynamic weather and atmosphere: clear, cloudy, overcast, rain (light rain),
## storm, fog (morning mist) and a region-gated snow (off by default).
##
## Art direction first, rendering second: weather is mostly a re-grade of what
## the scene already draws (fog density / colour, sky energy, how much fog
## greys the sky, sun energy and shadow softness, ambient, a touch of exposure
## and saturation), plus one camera-following GPUParticles3D for rain, a small
## ring of splash ripples, a shadowless flash light for lightning and two shader
## uniforms (foliage `weather_wind`, terrain `wetness`).
##
## Wiring (main.gd): add to the world, then setup(env, sun, player.camera).
## main.gd rewrites sun / ambient / fog colour / sky energy every frame for the
## day-night cycle; this node runs after it (it is a descendant of main, so it
## processes later in the same frame) and applies its multipliers on top of
## whatever base value it finds, so both systems compose without knowing each
## other. Without main.gd (tests, tools) the first values seen are the base.
##
## Picking: a seeded Markov chain gives each in-game day a weather, biased by
## WorldSim.season when that exists. The day is then shaped into a few segments
## (morning mist before a fair day, afternoon storms, rain clearing late...).
## Changes blend over 60-120 s. set_weather() overrides until the next segment.
##
## Cost: blends, schedule, materials and audio update at 10 Hz. Per frame only
## the particle emitters follow the camera and ~12 environment floats are
## re-applied (main.gd overwrites them each frame anyway).

## New target weather (the blend towards it has just started).
signal weather_changed(weather_name: String)
## A lightning strike was just seen; the thunder should be heard after `delay` seconds.
signal thunder(delay: float)

const InteriorDoorScript := preload("res://scripts/interiors/interior_door.gd")
const RAIN_SHADER := preload("res://shaders/rain_streak.gdshader")
const RIPPLE_SHADER := preload("res://shaders/rain_ripple.gdshader")
const TREE_WIND_SHADER := preload("res://shaders/tree_wind.gdshader")
const ASSETS_SCRIPT := "res://scripts/world/assets.gd"
const REGION_MATERIALS := [
	"res://assets/generated/region/nature/rg_foliage.tres",
	"res://assets/generated/region/nature/rg_foliage_ground.tres",
	"res://assets/generated/region/nature/rg_bark.tres",
	"res://assets/generated/region/nature/rg_moss.tres",
	"res://assets/generated/region/nature/rg_rock.tres",
]

const STATES := ["clear", "cloudy", "overcast", "rain", "storm", "fog", "snow"]
const ALIASES := {"light_rain": "rain", "light rain": "rain", "mist": "fog", "sunny": "clear"}
const TICK := 0.1
const RAIN_AMOUNT_HIGH := 1500
const RAIN_AMOUNT_LOW := 400
const RIPPLE_AMOUNT_HIGH := 96
const RIPPLE_AMOUNT_LOW := 32
const SPEED_OF_SOUND := 343.0
const WIND_DIR := Vector2(1.0, 0.35)   # same as the foliage shaders' default wind_direction

## Per state: multipliers on the scene's base values (1 = unchanged) and levels.
## fog/vfog: fog densities. hfog: added height-fog density. fog_desat / fog_bright /
## fog_tint: grade of the fog colour. sky_fog: how far fog greys the sky (0 = base,
## 1 = fully). sky: sky energy. sun: sun energy. shadow: sun shadow opacity.
## ambient, exposure, sat: ambient energy, tonemap exposure, saturation.
## wind: foliage sway. rain / snow: particle intensity. lightning: strike rate.
## wet: terrain soak target (wetness itself rises and dries slowly).
const PROFILES := {
	"clear": {"fog": 1.0, "vfog": 1.0, "hfog": 0.0, "fog_desat": 0.0, "fog_bright": 1.0, "fog_tint": Color(1, 1, 1),
		"sky_fog": 0.0, "sky": 1.0, "sun": 1.0, "shadow": 1.0, "ambient": 1.0, "exposure": 1.0, "sat": 1.0,
		"wind": 1.0, "rain": 0.0, "snow": 0.0, "lightning": 0.0, "wet": 0.0},
	"cloudy": {"fog": 1.4, "vfog": 1.2, "hfog": 0.0, "fog_desat": 0.2, "fog_bright": 0.97, "fog_tint": Color(0.97, 0.99, 1.03),
		"sky_fog": 0.15, "sky": 0.88, "sun": 0.78, "shadow": 0.85, "ambient": 1.0, "exposure": 1.03, "sat": 0.97,
		"wind": 1.25, "rain": 0.0, "snow": 0.0, "lightning": 0.0, "wet": 0.0},
	"overcast": {"fog": 2.6, "vfog": 1.6, "hfog": 0.0, "fog_desat": 0.55, "fog_bright": 0.9, "fog_tint": Color(0.93, 0.96, 1.04),
		"sky_fog": 0.45, "sky": 0.62, "sun": 0.42, "shadow": 0.55, "ambient": 0.92, "exposure": 1.08, "sat": 0.9,
		"wind": 1.4, "rain": 0.0, "snow": 0.0, "lightning": 0.0, "wet": 0.0},
	"rain": {"fog": 4.5, "vfog": 2.2, "hfog": 0.0008, "fog_desat": 0.65, "fog_bright": 0.8, "fog_tint": Color(0.9, 0.95, 1.05),
		"sky_fog": 0.6, "sky": 0.5, "sun": 0.3, "shadow": 0.45, "ambient": 0.82, "exposure": 1.1, "sat": 0.88,
		"wind": 1.7, "rain": 0.55, "snow": 0.0, "lightning": 0.0, "wet": 0.8},
	"storm": {"fog": 6.5, "vfog": 2.8, "hfog": 0.001, "fog_desat": 0.75, "fog_bright": 0.62, "fog_tint": Color(0.82, 0.88, 1.0),
		"sky_fog": 0.7, "sky": 0.36, "sun": 0.18, "shadow": 0.4, "ambient": 0.66, "exposure": 1.06, "sat": 0.82,
		"wind": 2.4, "rain": 1.0, "snow": 0.0, "lightning": 1.0, "wet": 1.0},
	"fog": {"fog": 14.0, "vfog": 4.0, "hfog": 0.004, "fog_desat": 0.35, "fog_bright": 1.04, "fog_tint": Color(1.06, 1.03, 0.97),
		"sky_fog": 0.85, "sky": 0.8, "sun": 0.55, "shadow": 0.6, "ambient": 0.96, "exposure": 1.02, "sat": 0.93,
		"wind": 0.45, "rain": 0.0, "snow": 0.0, "lightning": 0.0, "wet": 0.0},
	"snow": {"fog": 4.0, "vfog": 2.0, "hfog": 0.0015, "fog_desat": 0.7, "fog_bright": 1.05, "fog_tint": Color(0.95, 0.98, 1.06),
		"sky_fog": 0.6, "sky": 0.7, "sun": 0.45, "shadow": 0.5, "ambient": 1.12, "exposure": 1.0, "sat": 0.85,
		"wind": 1.3, "rain": 0.0, "snow": 0.8, "lightning": 0.0, "wet": 0.0},
}

## Markov chain: row = today's weather, columns = tomorrow's (STATES order).
## Snow's column is 0 here; in snow regions precipitation turns to snow instead.
const CHAIN := {
	"clear":    [0.45, 0.30, 0.08, 0.05, 0.02, 0.10, 0.0],
	"cloudy":   [0.28, 0.30, 0.20, 0.12, 0.03, 0.07, 0.0],
	"overcast": [0.15, 0.25, 0.25, 0.22, 0.08, 0.05, 0.0],
	"rain":     [0.15, 0.25, 0.25, 0.20, 0.08, 0.07, 0.0],
	"storm":    [0.22, 0.25, 0.25, 0.18, 0.05, 0.05, 0.0],
	"fog":      [0.40, 0.30, 0.15, 0.08, 0.02, 0.05, 0.0],
	"snow":     [0.10, 0.20, 0.35, 0.10, 0.0, 0.05, 0.20],
}
## Column multipliers per season (WorldSim.season, if the sim ever gets one).
const SEASON_BIAS := {
	"spring": {"rain": 1.4, "cloudy": 1.2, "fog": 1.1},
	"summer": {"clear": 1.4, "storm": 1.6, "fog": 0.6, "rain": 0.8},
	"autumn": {"fog": 1.6, "rain": 1.3, "overcast": 1.2, "clear": 0.8},
	"winter": {"overcast": 1.4, "fog": 1.3, "clear": 0.7, "storm": 0.3, "snow": 2.0},
}
const SEASON_NAMES := ["spring", "summer", "autumn", "winter"]

## Follow the seeded daily schedule. Off = only set_weather() changes anything.
@export var auto := true
@export var weather_seed := 1066
## Region gate for snow: when on, rain and storm days fall as snow. Off by default.
@export var snow_allowed := false
@export var blend_min := 60.0
@export var blend_max := 120.0
## Play Audio "thunder" after each strike's delay (in addition to the signal).
@export var play_thunder_audio := true

## Global wind multiplier any script (grass, cloth, banners, particles) can read:
## preload("res://scripts/world/weather.gd").wind_strength. 1 = calm default.
static var wind_strength := 1.0
## Current terrain soak 0..1 (also on the terrain material as `wetness`).
static var wetness := 0.0

var env: Environment
var sun: DirectionalLight3D
var camera: Camera3D
## Returns ground height at (x, z); defaults to WorldGen.height.
var ground_height := Callable()

var params: Dictionary = PROFILES["clear"].duplicate()
var _state := "clear"
var _from: Dictionary = PROFILES["clear"].duplicate()
var _to: Dictionary = PROFILES["clear"]
var _blend_t := 1.0
var _blend_len := 0.0
var _tick_acc := 0.0
var _segment_key := ""
var _adopt_segment := false
var _chain: Dictionary = {1: "clear"}   # day -> weather (day 1 is the bright first morning)

var _base: Dictionary = {}               # "env:prop" -> base value seen from the scene
var _wrote: Dictionary = {}              # "env:prop" -> value we last wrote
var _rain: GPUParticles3D
var _rain_mat: ShaderMaterial
var _rain_proc: ParticleProcessMaterial
var _ripples: GPUParticles3D
var _ripple_mat: ShaderMaterial
var _flash_light: DirectionalLight3D
var _flash_t := -1.0
var _flash_gain := 0.0
var _flash_sky := 0.0
var _next_strike := 8.0
var _strike_rng := RandomNumberGenerator.new()
var _rain_off_timer := 0.0
var _last_cam_pos := Vector3.INF
var _cam_vel := Vector3.ZERO
var _particle_scale := 1.0
var _rain_amount := RAIN_AMOUNT_HIGH
var _ripple_amount := RIPPLE_AMOUNT_HIGH
var _flatness := 1.0
var _ground_cache := 0.0

var _materials_wind: Array[ShaderMaterial] = []
var _materials_wet: Array[ShaderMaterial] = []
var _known_leaf_count := -1
var _rescan_timer := 0.0
var _sent_wind := -1.0
var _sent_wet := -1.0
var _audio_kind := "?"


func _ready() -> void:
	_strike_rng.seed = hash([weather_seed, "lightning"])
	_build_particles()
	_build_flash()
	var q := _autoload("Quality")
	if q:
		if q.has_signal("changed"):
			q.changed.connect(_on_quality_changed)
		_on_quality_changed()


## Hand over the scene's environment (Environment or WorldEnvironment), sun and camera.
func setup(environment: Variant, sun_light: DirectionalLight3D, cam: Camera3D = null) -> void:
	if environment is WorldEnvironment:
		env = (environment as WorldEnvironment).environment
	else:
		env = environment as Environment
	sun = sun_light
	camera = cam
	_base.clear()
	_wrote.clear()
	_rescan_materials()


# ------------------------------------------------------------------ public API

func current_name() -> String:
	return _state


## Blend to `weather_name` over `blend_seconds` (<= 0 snaps). Overrides the daily
## schedule until its next segment starts.
func set_weather(weather_name: String, blend_seconds := 90.0) -> void:
	var n := weather_name.to_lower()
	n = ALIASES.get(n, n)
	if not PROFILES.has(n):
		push_warning("Weather: unknown state '%s'" % weather_name)
		return
	if n == "snow" and not snow_allowed:
		n = "overcast"
	_adopt_segment = true
	_start_blend(n, blend_seconds)


func is_raining() -> bool:
	return float(params["rain"]) > 0.3


func is_snowing() -> bool:
	return float(params["snow"]) > 0.3


## 0..1 current rain intensity (0.55 light rain, 1 storm).
func rain_amount() -> float:
	return float(params["rain"])


## Multiplier for how far noise carries (stealth): rain and wind cover footsteps.
func noise_mult() -> float:
	var r := float(params["rain"])
	var w := clampf((float(params["wind"]) - 1.0) / 1.4, 0.0, 1.0)
	return clampf(1.0 - 0.4 * r - 0.1 * w, 0.4, 1.0)


## Multiplier for fire spread / burn damage: rain and soaked ground dampen fire.
func fire_mult() -> float:
	return clampf(1.0 - 0.55 * float(params["rain"]) - 0.2 * wetness, 0.25, 1.0)


## Region gate: e.g. RegionSites / biome code calls this when entering the mountains.
func set_snow_region(on: bool) -> void:
	if snow_allowed == on:
		return
	snow_allowed = on
	_chain = {1: "clear"}
	_segment_key = "region"   # re-evaluate on the next tick, with a normal blend
	if not on and _state == "snow":
		_start_blend("overcast", blend_min)


## Deterministic weather of an in-game day (Markov chain from day 1).
func weather_for_day(day: int) -> String:
	if _chain.has(day):
		return _chain[day]
	var last := 1
	for d: int in _chain:
		if d < day and d > last:
			last = d
	var s: String = _chain[last]
	for d in range(last + 1, day + 1):
		s = _next_day(s, d)
		_chain[d] = s
	return s


## The day's segments: [[start_hour, state], ...] sorted by hour.
func schedule_for_day(day: int) -> Array:
	var s := weather_for_day(day)
	if day <= 1:
		return [[0.0, s]]    # the first morning of a new life is always bright
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([weather_seed, day, "shape"])
	var roll := rng.randf()
	match s:
		"fog":
			return [[0.0, "cloudy"], [4.5, "fog"], [rng.randf_range(9.0, 10.5), "clear" if roll < 0.6 else "cloudy"]]
		"clear", "cloudy":
			if roll < 0.25:     # morning mist burning off
				return [[0.0, s], [4.5, "fog"], [rng.randf_range(8.0, 9.5), s]]
			return [[0.0, s]]
		"storm":
			var start := rng.randf_range(12.0, 16.0)
			return [[0.0, "overcast"], [start, "storm"], [start + rng.randf_range(2.5, 4.5), _wet("rain")]]
		"rain":
			if roll < 0.35:     # clearing in the afternoon
				return [[0.0, _wet("rain")], [rng.randf_range(14.0, 17.0), "cloudy"]]
			if roll < 0.6:      # grey morning, rain later
				return [[0.0, "overcast"], [rng.randf_range(10.0, 13.0), _wet("rain")]]
			return [[0.0, _wet("rain")]]
		_:
			return [[0.0, s]]


func scheduled_state(day: int, hour: float) -> String:
	var segs := schedule_for_day(day)
	var out: String = segs[0][1]
	for seg: Array in segs:
		if hour >= float(seg[0]):
			out = seg[1]
	return out


# ------------------------------------------------------------------ frame loop

func _process(delta: float) -> void:
	_tick_acc += delta
	if _tick_acc >= TICK:
		step(_tick_acc)
		_tick_acc = 0.0
	if _flash_t >= 0.0:
		_update_flash(delta)
	_follow_camera(delta)
	_apply_environment()


## One 10 Hz update (public so tests can drive time without frames).
func step(dt: float) -> void:
	if auto:
		_update_schedule()
	if _blend_t < 1.0:
		_blend_t = 1.0 if _blend_len <= 0.0 else minf(1.0, _blend_t + dt / _blend_len)
		var k := smoothstep(0.0, 1.0, _blend_t)
		for key: String in _to:
			params[key] = _lerp(_from[key], _to[key], k)
	# Ground soaks up in ~40 s of rain and dries over ~4 minutes.
	var target := float(params["wet"])
	var rate := 1.0 / 40.0 if target > wetness else 1.0 / 240.0
	wetness = move_toward(wetness, target, rate * dt)
	wind_strength = float(params["wind"])
	if float(params["hfog"]) > 0.0 or float(params["rain"]) > 0.02:
		_ground_cache = _ground_y()
	_rescan_timer -= dt
	if _rescan_timer <= 0.0:
		_rescan_timer = 2.0
		_rescan_materials()
	_push_materials()
	_update_particles_state(dt)
	_update_lightning(dt)
	_update_audio()
	_apply_environment()


func _start_blend(n: String, seconds: float) -> void:
	_from = params.duplicate()
	_to = PROFILES[n]
	_blend_len = maxf(seconds, 0.0)
	_blend_t = 0.0
	if _blend_len <= 0.0:
		_blend_t = 1.0
		params = PROFILES[n].duplicate()
	var changed := n != _state
	_state = n
	if changed:
		weather_changed.emit(n)


func _update_schedule() -> void:
	var ws := _autoload("WorldSim")
	if ws == null:
		return
	var day := int(ws.get("day"))
	var hour := float(ws.get("time_of_day"))
	var segs := schedule_for_day(day)
	var idx := 0
	for i in segs.size():
		if hour >= float(segs[i][0]):
			idx = i
	var key := "%d:%d" % [day, idx]
	if key == _segment_key:
		return
	var first := _segment_key == ""
	_segment_key = key
	if _adopt_segment:
		_adopt_segment = false   # a manual set_weather() holds until the next segment
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([weather_seed, key])
	_start_blend(segs[idx][1], 0.0 if first else rng.randf_range(blend_min, blend_max))


func _next_day(today: String, day: int) -> String:
	var row: Array = CHAIN.get(today, CHAIN["clear"])
	var bias: Dictionary = SEASON_BIAS.get(_season(), {})
	var weights: Array[float] = []
	var total := 0.0
	for i in STATES.size():
		var w := float(row[i]) * float(bias.get(STATES[i], 1.0))
		if STATES[i] == "snow" and not snow_allowed:
			w = 0.0
		weights.append(w)
		total += w
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([weather_seed, day])
	var r := rng.randf() * total
	for i in STATES.size():
		r -= weights[i]
		if r <= 0.0 and weights[i] > 0.0:
			return _wet(STATES[i])
	return "clear"


## In snow regions precipitation falls as snow.
func _wet(s: String) -> String:
	if snow_allowed and (s == "rain" or s == "storm"):
		return "snow"
	return s


func _season() -> String:
	var ws := _autoload("WorldSim")
	if ws == null or not ("season" in ws):
		return ""
	var s: Variant = ws.get("season")
	if s is int:
		return SEASON_NAMES[posmod(s, 4)]
	return String(s).to_lower()


# ------------------------------------------------------------------ environment

func _apply_environment() -> void:
	if env:
		var p := params
		_mul(env, "fog_density", p["fog"])
		_mul(env, "volumetric_fog_density", p["vfog"])
		_add(env, "fog_height_density", p["hfog"])
		if float(p["hfog"]) > 0.0:
			env.fog_height = _ground_cache + 5.0
		_mul(env, "background_energy_multiplier", p["sky"], _flash_sky)
		_mul(env, "ambient_light_energy", p["ambient"], _flash_sky * 0.5)
		_mul(env, "tonemap_exposure", p["exposure"])
		if env.adjustment_enabled:
			_mul(env, "adjustment_saturation", p["sat"])
		var sky_base := float(_base_of(env, "fog_sky_affect"))
		_write(env, "fog_sky_affect", lerpf(sky_base, 1.0, p["sky_fog"]))
		var fog_base: Color = _base_of(env, "fog_light_color")
		var l := fog_base.get_luminance()
		var grey := Color(l, l, l) * (p["fog_tint"] as Color)
		var c := fog_base.lerp(grey, p["fog_desat"]) * float(p["fog_bright"])
		c.a = 1.0
		_write(env, "fog_light_color", c)
	if sun:
		_mul(sun, "light_energy", p_sun())
		_mul(sun, "shadow_opacity", params["shadow"])


func p_sun() -> float:
	return float(params["sun"])


## Remembers the scene's own value of obj.prop: whatever is there now unless it is
## the value we wrote last (then nobody else touched it and the old base stands).
func _base_of(obj: Object, prop: String) -> Variant:
	var key := _key(obj, prop)
	var cur: Variant = obj.get(prop)
	if not _base.has(key) or not _same(cur, _wrote.get(key)):
		_base[key] = cur
	return _base[key]


## "<instance id>:<property>", built once per pair (CPU pass 2026-10-06: _apply_environment runs every frame and formatted
## three of these strings for each of its dozen properties).
var _keys: Dictionary = {}


func _key(obj: Object, prop: String) -> String:
	var id := obj.get_instance_id()
	var per: Variant = _keys.get(id)
	if per == null:
		per = {}
		_keys[id] = per
	var k: Variant = (per as Dictionary).get(prop)
	if k == null:
		k = "%d:%s" % [id, prop]
		(per as Dictionary)[prop] = k
	return k


func _write(obj: Object, prop: String, v: Variant) -> void:
	_base_of(obj, prop)
	obj.set(prop, v)
	_wrote[_key(obj, prop)] = obj.get(prop)


func _mul(obj: Object, prop: String, m: float, extra := 0.0) -> void:
	_write(obj, prop, float(_base_of(obj, prop)) * m + extra)


func _add(obj: Object, prop: String, a: float) -> void:
	_write(obj, prop, float(_base_of(obj, prop)) + a)


static func _same(a: Variant, b: Variant) -> bool:
	if a is float and b is float:
		return is_equal_approx(a, b)
	if a is Color and b is Color:
		return (a as Color).is_equal_approx(b)
	return false


static func _lerp(a: Variant, b: Variant, k: float) -> Variant:
	if a is Color:
		return (a as Color).lerp(b, k)
	return lerpf(a, b, k)


# ------------------------------------------------------------------ materials

## Picks up the shared wind / terrain materials as they come into existence.
func _rescan_materials() -> void:
	for path: String in REGION_MATERIALS:
		if ResourceLoader.has_cached(path):
			var m := load(path) as ShaderMaterial
			if m and not _materials_wind.has(m):
				_materials_wind.append(m)
				_sent_wind = -1.0
	if ResourceLoader.has_cached(ASSETS_SCRIPT):
		var leaves: Variant = (load(ASSETS_SCRIPT) as Script).get("_leaf_materials")
		if leaves is Dictionary and (leaves as Dictionary).size() != _known_leaf_count:
			_known_leaf_count = (leaves as Dictionary).size()
			for m: Variant in (leaves as Dictionary).values():
				if m is ShaderMaterial and (m as ShaderMaterial).shader == TREE_WIND_SHADER and not _materials_wind.has(m):
					_materials_wind.append(m)
					_sent_wind = -1.0
	var host := get_parent()
	if host:
		for n in host.get_children():
			if "_ground_material" in n:
				var gm := n.get("_ground_material") as ShaderMaterial
				if gm and not _materials_wet.has(gm):
					_materials_wet.append(gm)
					_sent_wet = -1.0


## Extra materials to drive: `weather_wind` (foliage) or `wetness` (terrain).
func register_material(mat: ShaderMaterial, wet := false) -> void:
	if wet and not _materials_wet.has(mat):
		_materials_wet.append(mat)
		_sent_wet = -1.0
	elif not wet and not _materials_wind.has(mat):
		_materials_wind.append(mat)
		_sent_wind = -1.0


func _push_materials() -> void:
	if absf(wind_strength - _sent_wind) > 0.005:
		_sent_wind = wind_strength
		for m in _materials_wind:
			m.set_shader_parameter("weather_wind", wind_strength)
	if absf(wetness - _sent_wet) > 0.005 or (wetness == 0.0 and _sent_wet != 0.0):
		_sent_wet = wetness
		for m in _materials_wet:
			m.set_shader_parameter("wetness", wetness)


# ------------------------------------------------------------------ rain & ripples

func _build_particles() -> void:
	_rain_proc = ParticleProcessMaterial.new()
	_rain_proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_proc.emission_box_extents = Vector3(14, 1, 14)
	_rain_proc.direction = Vector3(0, -1, 0)
	_rain_proc.spread = 2.0
	_rain_proc.initial_velocity_min = 15.0
	_rain_proc.initial_velocity_max = 19.0
	_rain_proc.gravity = Vector3(0, -6, 0)
	_rain_proc.particle_flag_align_y = true
	_rain_proc.collision_mode = ParticleProcessMaterial.COLLISION_DISABLED
	_rain_mat = ShaderMaterial.new()
	_rain_mat.shader = RAIN_SHADER
	var quad := QuadMesh.new()
	quad.material = _rain_mat
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = RAIN_AMOUNT_HIGH
	_rain.lifetime = 1.1
	_rain.local_coords = false
	_rain.emitting = false
	_rain.visible = false
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.visibility_aabb = AABB(Vector3(-16, -24, -16), Vector3(32, 30, 32))
	_rain.process_material = _rain_proc
	_rain.draw_pass_1 = quad
	add_child(_rain)

	var rp := ParticleProcessMaterial.new()
	rp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	rp.emission_ring_axis = Vector3.UP
	rp.emission_ring_height = 0.0
	rp.emission_ring_radius = 6.0
	rp.emission_ring_inner_radius = 0.8
	rp.gravity = Vector3.ZERO
	rp.initial_velocity_min = 0.0
	rp.initial_velocity_max = 0.0
	rp.scale_min = 0.5
	rp.scale_max = 1.1
	_ripple_mat = ShaderMaterial.new()
	_ripple_mat.shader = RIPPLE_SHADER
	var disc := QuadMesh.new()
	disc.orientation = PlaneMesh.FACE_Y
	disc.size = Vector2(0.55, 0.55)
	disc.material = _ripple_mat
	_ripples = GPUParticles3D.new()
	_ripples.name = "RainRipples"
	_ripples.amount = RIPPLE_AMOUNT_HIGH
	_ripples.lifetime = 0.55
	_ripples.local_coords = false
	_ripples.emitting = false
	_ripples.visible = false
	_ripples.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ripples.visibility_aabb = AABB(Vector3(-8, -1, -8), Vector3(16, 2, 16))
	_ripples.process_material = rp
	_ripples.draw_pass_1 = disc
	add_child(_ripples)


func _on_quality_changed() -> void:
	var q := _autoload("Quality")
	var p := 1.0
	if q and q.has_method("value"):
		p = float(q.call("value", "particles"))
	_particle_scale = clampf((p - 0.35) / 0.65, 0.0, 1.0)
	var amount := int(round(lerpf(RAIN_AMOUNT_LOW, RAIN_AMOUNT_HIGH, _particle_scale)))
	var ripple := int(round(lerpf(RIPPLE_AMOUNT_LOW, RIPPLE_AMOUNT_HIGH, _particle_scale)))
	if amount != _rain_amount and _rain:
		_rain_amount = amount
		_rain.amount = amount      # restarts the system; only on a quality change
	if ripple != _ripple_amount and _ripples:
		_ripple_amount = ripple
		_ripples.amount = ripple


func rain_particle_amount() -> int:
	return _rain_amount


func is_outdoors() -> bool:
	return InteriorDoorScript.active == null


func _active_camera() -> Camera3D:
	if camera and is_instance_valid(camera) and camera.is_inside_tree() and camera.current:
		return camera
	var vp := get_viewport()
	var c := vp.get_camera_3d() if vp else null
	return c if c else (camera if camera and is_instance_valid(camera) and camera.is_inside_tree() else null)


## 10 Hz: intensity, wind slant, tint, on/off.
func _update_particles_state(dt: float) -> void:
	var rain := float(params["rain"])
	var snow := float(params["snow"])
	var fall := maxf(rain, snow)
	var on := fall > 0.02 and is_outdoors()
	var snowing := snow > rain
	if on:
		_rain_off_timer = 1.5
		if not _rain.emitting:
			_rain.visible = true
			_rain.emitting = true
		_rain.amount_ratio = clampf(fall, 0.0, 1.0)
		_rain_mat.set_shader_parameter("snow", 1.0 if snowing else 0.0)
		var slant := 0.08 * wind_strength * (4.0 if snowing else 1.0)
		var d := WIND_DIR.normalized() * slant
		_rain_proc.direction = Vector3(d.x, -1.0, d.y).normalized()
		_rain_proc.initial_velocity_min = 1.2 if snowing else 15.0
		_rain_proc.initial_velocity_max = 2.0 if snowing else 19.0
		_rain_proc.gravity = Vector3(d.x * 3.0, -1.0, d.y * 3.0) if snowing else Vector3(0, -6, 0)
		_rain.lifetime = 7.0 if snowing else 1.1
		# Drops pick up the light: bright by day, faint silver at night, dimmer in storms.
		var light := 0.6
		if sun:
			light = clampf(float(_base_of(sun, "light_energy")) / 1.7, 0.25, 1.0)
		var alpha := (0.55 if snowing else 0.3) * lerpf(0.55, 1.0, light)
		var tint := Color(0.78, 0.82, 0.9).lerp(Color(0.95, 0.97, 1.0), 1.0 if snowing else 0.0) * lerpf(0.45, 1.0, light)
		tint.a = alpha
		_rain_mat.set_shader_parameter("tint", tint)
		var ripple_on := rain > 0.05 and not snowing and _flatness > 0.5
		_ripples.visible = ripple_on
		_ripples.emitting = ripple_on
		_ripples.amount_ratio = clampf(rain * _flatness, 0.0, 1.0)
		var rt := Color(0.85, 0.9, 1.0) * lerpf(0.5, 1.0, light)
		rt.a = 0.45 * lerpf(0.6, 1.0, light)
		_ripple_mat.set_shader_parameter("tint", rt)
	else:
		if _rain.emitting:
			_rain.emitting = false
		_ripples.emitting = false
		if not is_outdoors():
			_rain.visible = false
			_ripples.visible = false
		elif _rain_off_timer > 0.0:
			_rain_off_timer -= dt
			if _rain_off_timer <= 0.0:
				_rain.visible = false
				_ripples.visible = false


## Per frame: keep the emitters around the camera (world-space particles stay put).
func _follow_camera(delta: float) -> void:
	if not _rain.visible and not _ripples.visible:
		_last_cam_pos = Vector3.INF
		return
	var cam := _active_camera()
	if cam == null:
		return
	var cp := cam.global_position
	if _last_cam_pos != Vector3.INF and delta > 0.0:
		_cam_vel = _cam_vel.lerp((cp - _last_cam_pos) / delta, minf(1.0, delta * 4.0))
	_last_cam_pos = cp
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() * 5.0 if fwd.length_squared() > 0.0001 else Vector3.ZERO
	var lead := _cam_vel * 0.6
	lead.y = 0.0
	_rain.global_position = cp + Vector3(0, 9.0, 0) + fwd + lead
	if _ripples.visible:
		var gp := cp + fwd * 0.4 + lead * 0.5
		_ripples.global_position = Vector3(gp.x, _height_at(gp.x, gp.z) + 0.03, gp.z)


func _height_at(x: float, z: float) -> float:
	if ground_height.is_valid():
		return float(ground_height.call(x, z))
	return WorldGen.height(x, z)


func _ground_y() -> float:
	var cam := _active_camera()
	if cam == null:
		return global_position.y
	var p := cam.global_position
	# Ripples only on reasonably flat ground (they are flat quads at one height).
	var h := _height_at(p.x, p.z)
	var slope := absf(_height_at(p.x + 3.0, p.z) - h) + absf(_height_at(p.x, p.z + 3.0) - h)
	_flatness = clampf(1.0 - (slope - 0.6) / 1.2, 0.0, 1.0)
	return h


# ------------------------------------------------------------------ lightning

func _build_flash() -> void:
	_flash_light = DirectionalLight3D.new()
	_flash_light.name = "LightningFlash"
	_flash_light.shadow_enabled = false
	_flash_light.light_color = Color(0.78, 0.84, 1.0)
	_flash_light.light_energy = 0.0
	_flash_light.light_specular = 0.6
	_flash_light.visible = false
	add_child(_flash_light)


func _update_lightning(dt: float) -> void:
	var rate := float(params["lightning"])
	if rate < 0.3 or not is_outdoors():
		return
	_next_strike -= dt * rate
	if _next_strike <= 0.0:
		_next_strike = _strike_rng.randf_range(7.0, 22.0)
		strike(_strike_rng.randf_range(300.0, 4000.0))


## A lightning strike `distance` metres away: flash now, thunder signal with the
## sound's travel time.
func strike(distance: float) -> void:
	var near := 1.0 - clampf(distance / 4000.0, 0.0, 1.0)
	_flash_gain = lerpf(0.9, 3.2, near)
	_flash_t = 0.0
	var az := _strike_rng.randf() * TAU
	_flash_light.rotation = Vector3(-_strike_rng.randf_range(0.7, 1.2), az, 0.0)
	_flash_light.visible = true
	var delay := distance / SPEED_OF_SOUND
	thunder.emit(delay)
	if play_thunder_audio and is_inside_tree():
		var audio := _autoload("Audio")
		if audio and audio.has_method("has_sound") and bool(audio.call("has_sound", "thunder")):
			var vol := lerpf(-12.0, 0.0, near)
			get_tree().create_timer(delay).timeout.connect(func() -> void:
				if is_instance_valid(audio) and is_outdoors():
					audio.call("play_sfx", "thunder", null, vol, 0.1))


## Per frame only while a flash is live (~0.45 s): a bright strike and two flickers.
func _update_flash(delta: float) -> void:
	_flash_t += delta
	var t := _flash_t
	var e := maxf(_pulse(t, 0.0, 0.07), maxf(_pulse(t, 0.13, 0.06) * 0.55, _pulse(t, 0.27, 0.12) * 0.3))
	_flash_light.light_energy = e * _flash_gain
	_flash_sky = e * _flash_gain * 0.35
	if t > 0.45:
		_flash_t = -1.0
		_flash_sky = 0.0
		_flash_light.light_energy = 0.0
		_flash_light.visible = false


static func _pulse(t: float, start: float, length: float) -> float:
	if t < start or t > start + length:
		return 0.0
	var k := (t - start) / length
	return minf(k * 6.0, 1.0) * (1.0 - k)


# ------------------------------------------------------------------ audio

func _update_audio() -> void:
	var kind := ""
	if float(params["lightning"]) > 0.5:
		kind = "storm"
	elif float(params["rain"]) > 0.25:
		kind = "rain"
	elif float(params["snow"]) > 0.3 or float(params["wind"]) > 1.9:
		kind = "wind"
	if kind == _audio_kind:
		return
	_audio_kind = kind
	var audio := _autoload("Audio")
	if audio and audio.has_method("set_weather"):
		audio.call("set_weather", kind)


func _autoload(n: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(n) if tree and tree.root else null
