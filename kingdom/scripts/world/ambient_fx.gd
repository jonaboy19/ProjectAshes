extends Node3D
## "Living world" ambience near the player: bird flocks, fireflies, butterflies,
## falling leaves, sunbeam dust motes, chimney embers and jumping fish.
##
## Everything that moves is animated on the GPU: flocks are one MultiMesh per
## flock driven by shaders/ambient_bird.gdshader (orbit, wing flap, landing and
## the scatter), the school of fish by shaders/ambient_fish.gdshader, and the rest
## are small GPUParticles3D emitters with procedural draw shaders
## (shaders/ambient_*.gdshader). No textures, no per-bird or per-particle script.
##
## This node only runs a 4 Hz tick: it reads the time of day (WorldSim), the
## weather (group "weather": is_raining(), static wind_strength, its sun) and the
## Quality tier, decides which effects are on, and moves a handful of emitters
## ("patches") to suitable ground near `focus` as the player travels:
##   fireflies   dusk and night, near water, meadows and forest edges
##   butterflies day, open meadows and village gardens
##   leaves      any dry hour, under forest canopy
##   motes       day, around the player; brighten looking towards the sun
##   embers      night, from the chimneys of the village the player is in
##   birds       day: circling flocks, plus landed flocks that burst up when the
##               player runs near (one `scatter_origin` uniform, set here)
##   fish        now and then a fish leaps in the Mere or the Ashrun (tweened
##               shader arc + rings + droplets); a school circles under the pier
## Rain (or snow) switches everything off; wind steers leaves, motes and embers.
##
## Wiring (main.gd): add to the world and keep `focus` updated like the other
## streaming systems. Cost when all on: ~20 small draw calls, a few hundred
## particles (scaled by Quality "particles"), zero per-frame script work except
## one float uniform for ~35 s after a flock scatters.

const WeatherScript := preload("res://scripts/world/weather.gd")
const BIRD_SHADER := preload("res://shaders/ambient_bird.gdshader")
const GLOW_SHADER := preload("res://shaders/ambient_glow.gdshader")
const BUTTERFLY_SHADER := preload("res://shaders/ambient_butterfly.gdshader")
const LEAF_SHADER := preload("res://shaders/ambient_leaf.gdshader")
const FISH_SHADER := preload("res://shaders/ambient_fish.gdshader")
const SPLASH_SHADER := preload("res://shaders/ambient_splash.gdshader")

const TICK := 0.25
## Emitter patches per kind: count (at Quality particles 1.0), relocate beyond
## `far` metres, placed `rmin`..`rmax` from the player, particles per patch.
const PATCHES := {
	"firefly": {"count": 4, "far": 55.0, "rmin": 3.0, "rmax": 34.0, "amount": 26},
	"butterfly": {"count": 3, "far": 50.0, "rmin": 3.0, "rmax": 30.0, "amount": 7},
	"leaves": {"count": 3, "far": 55.0, "rmin": 2.0, "rmax": 32.0, "amount": 12},
}
const FLY_FLOCKS := 3
const FLY_BIRDS := 12
const LAND_FLOCKS := 2
const LAND_BIRDS := 9
const SCATTER_NEAR := 5.0       # any approach this close scatters a landed flock
const SCATTER_RUN := 14.0       # running (faster than RUN_SPEED) this close does too
const RUN_SPEED := 3.5
const SCATTER_LEN := 36.0       # seconds the shader needs for flee + circle + re-land
const EMBERS := 3
const JUMPERS := 2
const SCHOOL_FISH := 10

var focus := Vector3.ZERO
## Optional; found through the "weather" group when left null.
var weather: Node

var _q := 1.0                   # Quality "particles"
var _day := 1.0                 # 0 night .. 1 noon (same curve as main.gd's daylight)
var _dry := 1.0                 # 0 while raining / snowing
var _wind := Vector2.ZERO
var _tick := 0.0
var _slow := 0                  # tick counter for 1 Hz work
var _last_focus := Vector3.INF
var _speed := 0.0
var _rng := RandomNumberGenerator.new()

var _bird_mesh: ArrayMesh
var _fly_mat: ShaderMaterial
var _land_mat: ShaderMaterial
var _flocks: Array[Dictionary] = []        # {node, landed, pos: Vector2, placed}
var _bird_presence := 0.0
var _scatter_age := 1000.0

var _patches: Array[Dictionary] = []       # {kind, slot, node, pos: Vector2, placed, off_t}
var _proc: Dictionary = {}                 # kind -> ParticleProcessMaterial
var _motes: GPUParticles3D
var _motes_mat: ShaderMaterial
var _embers: Array[GPUParticles3D] = []
var _chimneys: Dictionary = {}             # settlement name -> PackedVector3Array

var _jumpers: Array[Dictionary] = []       # {root, fish, fish_mat, ring, ring_mat, drops, busy}
var _jump_timer := 3.0
var _school: MultiMeshInstance3D


func _ready() -> void:
	_rng.seed = 7219
	_q = _quality()
	var qn := get_node_or_null("/root/Quality")
	if qn and qn.has_signal("changed"):
		qn.changed.connect(_apply_quality)
	_build_birds()
	for kind: String in PATCHES:
		for i in int(PATCHES[kind]["count"]):
			var p := _make_patch(kind)
			add_child(p)
			_patches.append({"kind": kind, "slot": i, "node": p, "pos": Vector2.INF, "placed": false, "off_t": 0.0})
	_build_motes()
	_build_embers()
	_build_fish()
	_apply_quality()
	_update(0.0)


func _process(delta: float) -> void:
	if _scatter_age < SCATTER_LEN + 4.0:
		_scatter_age += delta
		_land_mat.set_shader_parameter("scatter_age", _scatter_age)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	_update(TICK)


# --- State ------------------------------------------------------------------------

func _update(dt: float) -> void:
	if weather == null or not is_instance_valid(weather):
		weather = get_tree().get_first_node_in_group("weather") if is_inside_tree() else null
	var t := _hour()
	_day = clampf(sin((t - 6.0) / 12.0 * PI) * 1.4, 0.0, 1.0)
	var wet := false
	if weather and weather.has_method("is_raining"):
		wet = weather.is_raining() or (weather.has_method("is_snowing") and weather.is_snowing())
	_dry = 0.0 if wet else 1.0
	var wd := WeatherScript.WIND_DIR.normalized()
	_wind = wd * WeatherScript.wind_strength
	if dt > 0.0 and _last_focus.x < 1.0e20:
		_speed = Vector2(focus.x - _last_focus.x, focus.z - _last_focus.z).length() / dt
	_last_focus = focus
	_slow += 1

	_update_birds(dt)
	var budget := 2                 # patch relocations per tick (each samples WorldGen a few times)
	for p in _patches:
		budget = _update_patch(p, dt, budget)
	_update_motes()
	if _slow % 4 == 0:
		_update_embers()
		_update_school()
	_update_fish(dt)


func level(kind: String) -> float:
	match kind:
		"firefly":
			return (1.0 - smoothstep(0.04, 0.22, _day)) * _dry
		"butterfly", "motes":
			return smoothstep(0.35, 0.6, _day) * _dry
		"birds":
			return smoothstep(0.2, 0.4, _day) * _dry
		"embers":
			return (1.0 - smoothstep(0.05, 0.2, _day)) * _dry
		"leaves", "fish":
			return _dry
	return 0.0


func _hour() -> float:
	var ws := get_node_or_null("/root/WorldSim")
	return float(ws.get("time_of_day")) if ws else 12.0


func _quality() -> float:
	var qn := get_node_or_null("/root/Quality")
	if qn and qn.has_method("value"):
		return float(qn.value("particles"))
	return 1.0


func _apply_quality() -> void:
	_q = _quality()
	for c in find_children("*", "GPUParticles3D", true, false):
		(c as GPUParticles3D).amount_ratio = _q
	for f in _flocks:
		var mm: MultiMesh = (f["node"] as MultiMeshInstance3D).multimesh
		mm.visible_instance_count = maxi(4, int(mm.instance_count * _q))
	if _school:
		_school.multimesh.visible_instance_count = maxi(4, int(SCHOOL_FISH * _q))


func _ground(q: Vector2) -> float:
	return WorldGen.height(q.x, q.y)


func _in_town(q: Vector2, mul: float) -> bool:
	var s := WorldGen.nearest_settlement(q)
	return not s.is_empty() and q.distance_to(s["pos"]) < float(s["radius"]) * mul


func _ring_point(rmin: float, rmax: float) -> Vector2:
	var a := _rng.randf() * TAU
	var r := sqrt(_rng.randf_range(rmin * rmin, rmax * rmax))
	return Vector2(focus.x, focus.z) + Vector2(cos(a), sin(a)) * r


# --- Birds ------------------------------------------------------------------------

func _build_birds() -> void:
	_bird_mesh = _make_bird_mesh()
	_fly_mat = ShaderMaterial.new()
	_fly_mat.shader = BIRD_SHADER
	_fly_mat.set_shader_parameter("mode", 0)
	_land_mat = ShaderMaterial.new()
	_land_mat.shader = BIRD_SHADER
	_land_mat.set_shader_parameter("mode", 1)
	_land_mat.set_shader_parameter("bird_scale", 0.8)
	_land_mat.set_shader_parameter("spread", 3.5)
	_fly_mat.set_shader_parameter("bird_scale", 1.3)
	_land_mat.set_shader_parameter("scatter_radius", SCATTER_RUN + 2.0)
	for i in FLY_FLOCKS + LAND_FLOCKS:
		var landed := i >= FLY_FLOCKS
		var n := LAND_BIRDS if landed else FLY_BIRDS
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.instance_count = n
		mm.mesh = _bird_mesh
		for b in n:
			mm.set_instance_transform(b, Transform3D.IDENTITY)
			mm.set_instance_custom_data(b, Color(_rng.randf(), _rng.randf(), _rng.randf(), _rng.randf()))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "LandedFlock%d" % i if landed else "Flock%d" % i
		mmi.multimesh = mm
		mmi.material_override = _land_mat if landed else _fly_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The shader moves birds far from the anchor: orbit, drift, and the flee.
		mmi.custom_aabb = AABB(Vector3(-70, -2, -70), Vector3(140, 60, 140))
		mmi.visibility_range_end = 120.0 if landed else 260.0
		mmi.visible = false
		add_child(mmi)
		_flocks.append({"node": mmi, "landed": landed, "pos": Vector2.INF, "placed": false})


## A 0.6 m silhouette bird: body, tail fan and two two-triangle wings. Vertex
## colour red = wing weight (0 body .. 1 tip) for the shader's flap. Forward +Z.
static func _make_bird_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := [
		# body
		[Vector3(0, 0, 0.17), Vector3(-0.035, 0, 0.0), Vector3(0, 0.0, -0.14)],
		[Vector3(0, 0, 0.17), Vector3(0, 0.0, -0.14), Vector3(0.035, 0, 0.0)],
		# tail
		[Vector3(0, 0, -0.1), Vector3(-0.055, 0, -0.22), Vector3(0.055, 0, -0.22)],
	]
	for sx in [-1.0, 1.0]:
		var rf := Vector3(0.03 * sx, 0, 0.06)
		var rb := Vector3(0.03 * sx, 0, -0.05)
		var mf := Vector3(0.16 * sx, 0, 0.045)
		var tip := Vector3(0.31 * sx, 0, -0.07)
		tris.append([rf, mf, rb])
		tris.append([mf, tip, rb])
	st.set_normal(Vector3.UP)
	for tri: Array in tris:
		for v: Vector3 in tri:
			var w := clampf((absf(v.x) - 0.03) / 0.28, 0.0, 1.0) if absf(v.x) > 0.029 and absf(v.z) < 0.09 else 0.0
			st.set_color(Color(w, 0, 0))
			st.add_vertex(v)
	return st.commit()


func _update_birds(dt: float) -> void:
	var target := level("birds")
	_bird_presence = move_toward(_bird_presence, target, dt * 0.4)
	_fly_mat.set_shader_parameter("presence", _bird_presence)
	_land_mat.set_shader_parameter("presence", _bird_presence)
	_fly_mat.set_shader_parameter("wind", _wind)
	var p2 := Vector2(focus.x, focus.z)
	for f in _flocks:
		var node: MultiMeshInstance3D = f["node"]
		var landed: bool = f["landed"]
		var far := 120.0 if landed else 170.0
		if not f["placed"] or p2.distance_to(f["pos"]) > far:
			# Move only while unseen (off, or far away): a few tries per tick.
			var q := _find_flock_spot(landed)
			if q.x < 1.0e20:
				f["pos"] = q
				f["placed"] = true
				node.global_position = Vector3(q.x, _ground(q), q.y)
		node.visible = f["placed"] and _bird_presence > 0.01
		if landed and f["placed"] and _scatter_age > SCATTER_LEN and _bird_presence > 0.5:
			var d := p2.distance_to(f["pos"])
			if d < SCATTER_NEAR or (d < SCATTER_RUN and _speed > RUN_SPEED):
				scatter(focus)


## Burst any landed flock within ~16 m of `origin` into the air (also usable by
## gameplay: a shout, an explosion, an arrow landing).
func scatter(origin: Vector3) -> void:
	_scatter_age = 0.0
	_land_mat.set_shader_parameter("scatter_origin", origin)
	_land_mat.set_shader_parameter("scatter_age", 0.0)


func _find_flock_spot(landed: bool) -> Vector2:
	for i in 4:
		var q := _ring_point(22.0, 65.0) if landed else _ring_point(40.0, 110.0)
		var sd := WorldGen.shore_distance(q.x, q.y)
		if landed:
			# Landed birds need bare ground to be seen (tall meadow grass hides
			# them): the beach band of the Mere and the Ashrun, or a country road.
			if _in_town(q, 1.1):
				continue
			if not (sd > 1.2 and sd < 5.0) and WorldGen.road_distance(q.x, q.y) > 2.5:
				continue
			var h := _ground(q)
			if absf(_ground(q + Vector2(2.5, 0)) - h) > 0.35 or absf(_ground(q + Vector2(0, 2.5)) - h) > 0.35:
				continue
		elif sd < 3.0 or _in_town(q, 0.5):
			continue
		return q
	return Vector2.INF


# --- Particle patches -------------------------------------------------------------

func _make_patch(kind: String) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = kind.capitalize() + "Patch"
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.local_coords = false
	p.emitting = false
	p.visible = false
	p.amount = int(PATCHES[kind]["amount"])
	p.visibility_range_end = 60.0
	p.visibility_range_end_margin = 8.0
	p.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if not _proc.has(kind):
		_proc[kind] = _make_proc(kind)
	p.process_material = _proc[kind]
	match kind:
		"firefly":
			p.lifetime = 6.0
			p.visibility_aabb = AABB(Vector3(-10, -3, -10), Vector3(20, 7, 20))
			var quad := QuadMesh.new()
			quad.size = Vector2(0.26, 0.26)
			quad.material = _glow_mat(Color(0.78, 1.0, 0.35), 2.6, 1.0, 45.0)
			p.draw_pass_1 = quad
		"butterfly":
			p.lifetime = 9.0
			p.visibility_aabb = AABB(Vector3(-9, -2, -9), Vector3(18, 5, 18))
			var plane := PlaneMesh.new()
			plane.size = Vector2(0.13, 0.1)
			plane.subdivide_width = 1
			var m := ShaderMaterial.new()
			m.shader = BUTTERFLY_SHADER
			plane.material = m
			p.draw_pass_1 = plane
		"leaves":
			p.lifetime = 9.5
			p.visibility_aabb = AABB(Vector3(-12, -10, -12), Vector3(24, 13, 24))
			var leaf := QuadMesh.new()
			leaf.size = Vector2(0.12, 0.14)
			var lm := ShaderMaterial.new()
			lm.shader = LEAF_SHADER
			leaf.material = lm
			p.draw_pass_1 = leaf
	return p


func _make_proc(kind: String) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.turbulence_enabled = true
	match kind:
		"firefly":
			m.emission_box_extents = Vector3(7, 0.7, 7)
			m.direction = Vector3.UP
			m.spread = 180.0
			m.initial_velocity_min = 0.05
			m.initial_velocity_max = 0.2
			m.gravity = Vector3.ZERO
			m.turbulence_noise_strength = 1.0
			m.turbulence_noise_scale = 2.5
			m.turbulence_noise_speed_random = 0.3
			m.turbulence_influence_min = 0.04
			m.turbulence_influence_max = 0.1
			m.scale_min = 0.7
			m.scale_max = 1.2
			m.color_ramp = _fade_ramp(Color(1, 1, 1), 0.2, 0.75)
		"butterfly":
			m.emission_box_extents = Vector3(5, 0.35, 5)
			m.direction = Vector3(1, 0.2, 0)
			m.spread = 180.0
			m.initial_velocity_min = 0.4
			m.initial_velocity_max = 0.9
			m.gravity = Vector3.ZERO
			m.damping_min = 0.0
			m.damping_max = 0.1
			m.turbulence_noise_strength = 2.0
			m.turbulence_noise_scale = 1.6
			m.turbulence_noise_speed = Vector3(0.1, 0.25, 0.1)
			m.turbulence_influence_min = 0.15
			m.turbulence_influence_max = 0.3
			m.particle_flag_rotate_y = true
			m.angle_min = -180.0
			m.angle_max = 180.0
			m.scale_curve = _grow_shrink(0.1, 0.9)
			var g := Gradient.new()
			g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
			g.offsets = PackedFloat32Array([0.0, 0.3, 0.5, 0.7, 0.85])
			g.colors = PackedColorArray([Color(0.98, 0.96, 0.9), Color(1.0, 0.84, 0.25),
				Color(0.98, 0.52, 0.16), Color(0.45, 0.62, 0.98), Color(0.95, 0.72, 0.85)])
			var gt := GradientTexture1D.new()
			gt.gradient = g
			m.color_initial_ramp = gt
		"leaves":
			m.emission_box_extents = Vector3(6, 1.2, 6)
			m.direction = Vector3.DOWN
			m.spread = 25.0
			m.initial_velocity_min = 0.45
			m.initial_velocity_max = 0.7
			m.gravity = Vector3(0, -0.08, 0)
			m.turbulence_noise_strength = 1.0
			m.turbulence_noise_scale = 3.0
			m.turbulence_influence_min = 0.05
			m.turbulence_influence_max = 0.12
			m.scale_min = 0.8
			m.scale_max = 1.3
			m.scale_curve = _grow_shrink(0.04, 0.9)
			var lg := Gradient.new()
			lg.offsets = PackedFloat32Array([0.0, 0.35, 0.6, 0.8, 1.0])
			lg.colors = PackedColorArray([Color(0.36, 0.5, 0.18), Color(0.55, 0.6, 0.2),
				Color(0.85, 0.66, 0.22), Color(0.86, 0.42, 0.16), Color(0.6, 0.3, 0.14)])
			var lgt := GradientTexture1D.new()
			lgt.gradient = lg
			m.color_initial_ramp = lgt
	return m


func _update_patch(p: Dictionary, dt: float, budget: int) -> int:
	var kind: String = p["kind"]
	var node: GPUParticles3D = p["node"]
	var lv := level(kind)
	var cfg: Dictionary = PATCHES[kind]
	var allowed := int(p["slot"]) < maxi(1, int(round(int(cfg["count"]) * _q)))
	var on := lv > 0.01 and allowed
	var p2 := Vector2(focus.x, focus.z)
	if on and (not p["placed"] or p2.distance_to(p["pos"]) > float(cfg["far"])):
		p["placed"] = false
		if budget > 0:
			budget -= 1
			var q := _find_patch_spot(kind, float(cfg["rmin"]), float(cfg["rmax"]))
			if q.x < 1.0e20:
				p["pos"] = q
				p["placed"] = true
				node.global_position = Vector3(q.x, _ground(q) + _patch_lift(kind), q.y)
				node.restart()
	on = on and p["placed"]
	if on:
		node.emitting = true
		node.visible = true
		node.amount_ratio = _q * lv
		p["off_t"] = 0.0
	else:
		node.emitting = false
		p["off_t"] = float(p["off_t"]) + dt
		if float(p["off_t"]) > node.lifetime + 0.5:
			node.visible = false
	if kind == "leaves" and on:
		(node.process_material as ParticleProcessMaterial).gravity = Vector3(_wind.x * 0.35, -0.08, _wind.y * 0.35)
	return budget


func _patch_lift(kind: String) -> float:
	match kind:
		"firefly":
			return 1.0
		"butterfly":
			return 0.75
		"leaves":
			return 6.8
	return 1.0


func _find_patch_spot(kind: String, rmin: float, rmax: float) -> Vector2:
	for i in 3:
		var q := _ring_point(rmin, rmax)
		var ok := false
		var sd := WorldGen.shore_distance(q.x, q.y)
		if sd < 1.5:
			continue
		match kind:
			"firefly":
				if sd < 14.0:
					ok = true
				else:
					var f := WorldGen.forest_density(q.x, q.y)
					ok = (f > 0.1 and f < 0.55) or (f < 0.05 and not _in_town(q, 1.0) and WorldGen.road_distance(q.x, q.y) > 8.0)
			"butterfly":
				if WorldGen.forest_density(q.x, q.y) < 0.08:
					if _in_town(q, 1.5):
						ok = WorldGen.street_distance(q.x, q.y) > 4.0      # gardens, not the street
					else:
						ok = WorldGen.road_distance(q.x, q.y) > 5.0
			"leaves":
				ok = WorldGen.forest_density(q.x, q.y) > 0.4
		if ok:
			return q
	return Vector2.INF


# --- Motes and embers -------------------------------------------------------------

func _build_motes() -> void:
	_motes = GPUParticles3D.new()
	_motes.name = "Motes"
	_motes.amount = 70
	_motes.lifetime = 7.0
	_motes.local_coords = false
	_motes.emitting = false
	_motes.visible = false
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.visibility_aabb = AABB(Vector3(-14, -5, -14), Vector3(28, 10, 28))
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(9, 2.2, 9)
	m.direction = Vector3.UP
	m.spread = 180.0
	m.initial_velocity_min = 0.02
	m.initial_velocity_max = 0.08
	m.gravity = Vector3(0, 0.01, 0)
	m.turbulence_enabled = true
	m.turbulence_noise_scale = 4.0
	m.turbulence_influence_min = 0.02
	m.turbulence_influence_max = 0.05
	m.scale_min = 0.6
	m.scale_max = 1.4
	m.color_ramp = _fade_ramp(Color(1, 1, 1), 0.25, 0.7)
	_motes.process_material = m
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	_motes_mat = _glow_mat(Color(1.0, 0.9, 0.62), 1.1, 0.0, 16.0)
	_motes_mat.set_shader_parameter("sun_boost", 5.0)
	_motes_mat.set_shader_parameter("near_fade", 0.3)
	quad.material = _motes_mat
	_motes.draw_pass_1 = quad
	add_child(_motes)


func _update_motes() -> void:
	var lv := level("motes")
	_motes.emitting = lv > 0.01
	if lv > 0.01:
		_motes.visible = true
		_motes.amount_ratio = _q * lv
		_motes.global_position = focus + Vector3(0, 1.6, 0)
		(_motes.process_material as ParticleProcessMaterial).gravity = Vector3(_wind.x * 0.04, 0.01, _wind.y * 0.04)
		var sun: Node3D = weather.get("sun") if weather else null
		if sun:
			_motes_mat.set_shader_parameter("sun_dir", sun.global_transform.basis.z.normalized())
	elif _motes.visible and not _motes.emitting and _day < 0.2:
		_motes.visible = false


func _build_embers() -> void:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 14.0
	m.initial_velocity_min = 0.7
	m.initial_velocity_max = 1.5
	m.gravity = Vector3(0, 0.15, 0)
	m.turbulence_enabled = true
	m.turbulence_noise_scale = 1.5
	m.turbulence_influence_min = 0.1
	m.turbulence_influence_max = 0.25
	m.scale_min = 0.5
	m.scale_max = 1.1
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.1, 0.6, 1.0])
	g.colors = PackedColorArray([Color(1, 0.8, 0.4, 0), Color(1, 0.7, 0.3, 1), Color(1, 0.35, 0.1, 0.8), Color(0.8, 0.15, 0.05, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	var mat := _glow_mat(Color(1.0, 0.55, 0.2), 3.2, 0.45, 70.0)
	mat.set_shader_parameter("blink_speed", 9.0)
	quad.material = mat
	for i in EMBERS:
		var p := GPUParticles3D.new()
		p.name = "Embers%d" % i
		p.amount = 8
		p.lifetime = 2.6
		p.local_coords = false
		p.emitting = false
		p.visible = false
		p.process_material = m
		p.draw_pass_1 = quad
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 8, 6))
		p.visibility_range_end = 80.0
		add_child(p)
		_embers.append(p)


func _update_embers() -> void:
	var lv := level("embers")
	var pts := PackedVector3Array()
	if lv > 0.01:
		var p2 := Vector2(focus.x, focus.z)
		var s := WorldGen.nearest_settlement(p2)
		if not s.is_empty() and p2.distance_to(s["pos"]) < float(s["radius"]) * 1.8:
			pts = _chimney_points(s)
	# Nearest few chimneys within 70 m.
	var best: Array = []
	for c in pts:
		var d := c.distance_squared_to(focus)
		if d < 4900.0:
			best.append([d, c])
	best.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in _embers.size():
		var e := _embers[i]
		if i < best.size():
			var at: Vector3 = best[i][1]
			if e.global_position.distance_squared_to(at) > 0.01 or not e.emitting:
				e.global_position = at
				e.visible = true
				e.emitting = true
			e.amount_ratio = _q * lv
		else:
			e.emitting = false


## Chimney tops of a built settlement, read once from SettlementBuilder's smoke
## emitters (direct children of the settlement's root, named after it).
func _chimney_points(s: Dictionary) -> PackedVector3Array:
	var key := String(s["name"])
	if _chimneys.has(key):
		return _chimneys[key]
	var out := PackedVector3Array()
	var world := get_parent()
	if world == null:
		return out
	for sb in world.get_children():
		if not sb.has_signal("settlement_built"):
			continue
		var root := sb.get_node_or_null(NodePath(key))
		if root == null:
			return out                      # not built yet: try again later
		if bool(root.get_meta("props_pending", false)):
			return out                      # district props (chimney smoke) still streaming in: do not cache yet
		for c in root.get_children():
			if c is GPUParticles3D and (c as GPUParticles3D).lifetime == 7.0 and (c as GPUParticles3D).amount == 16:
				out.append((c as Node3D).global_position + Vector3(0, 0.3, 0))
		_chimneys[key] = out
		return out
	return out


# --- Fish -------------------------------------------------------------------------

func _build_fish() -> void:
	for i in JUMPERS:
		var root := Node3D.new()
		root.name = "FishJump%d" % i
		root.visible = false
		add_child(root)
		var body := PlaneMesh.new()
		body.size = Vector2(0.28, 1.0)
		body.subdivide_depth = 6
		var fm := ShaderMaterial.new()
		fm.shader = FISH_SHADER
		fm.set_shader_parameter("jump", true)
		var fish := MeshInstance3D.new()
		fish.mesh = body
		fish.material_override = fm
		fish.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fish.custom_aabb = AABB(Vector3(-1, -1, -1.5), Vector3(2, 3, 3))
		root.add_child(fish)
		var ring_mesh := PlaneMesh.new()
		ring_mesh.size = Vector2(4, 4)
		var rm := ShaderMaterial.new()
		rm.shader = SPLASH_SHADER
		var ring := MeshInstance3D.new()
		ring.mesh = ring_mesh
		ring.material_override = rm
		ring.position.y = 0.03
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)
		var drops := GPUParticles3D.new()
		drops.one_shot = true
		drops.emitting = false
		drops.explosiveness = 0.95
		drops.amount = 14
		drops.lifetime = 0.8
		drops.local_coords = false
		drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drops.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 3, 4))
		var dm := ParticleProcessMaterial.new()
		dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		dm.emission_sphere_radius = 0.12
		dm.direction = Vector3.UP
		dm.spread = 30.0
		dm.initial_velocity_min = 1.4
		dm.initial_velocity_max = 2.6
		dm.gravity = Vector3(0, -9.8, 0)
		dm.scale_min = 0.6
		dm.scale_max = 1.2
		dm.color_ramp = _fade_ramp(Color(1, 1, 1), 0.02, 0.6)
		drops.process_material = dm
		var dq := QuadMesh.new()
		dq.size = Vector2(0.07, 0.07)
		dq.material = _glow_mat(Color(0.8, 0.9, 1.0), 0.7, 0.0, 70.0)
		drops.draw_pass_1 = dq
		root.add_child(drops)
		_jumpers.append({"root": root, "fish": fish, "fish_mat": fm, "ring_mat": rm, "drops": drops, "busy": false})


func _update_fish(dt: float) -> void:
	_jump_timer -= dt
	if _jump_timer > 0.0:
		return
	if level("fish") < 0.5:
		_jump_timer = 2.0
		return
	var free: Dictionary = {}
	for j in _jumpers:
		if not j["busy"]:
			free = j
			break
	if free.is_empty():
		_jump_timer = 0.5
		return
	for i in 4:
		var q := _ring_point(9.0, 50.0)
		var lv := WorldGen.water_level_at(q.x, q.y)
		if is_nan(lv) or lv - _ground(q) < 0.9:
			continue
		var flow := WorldGen.water_flow(q.x, q.y)
		var yaw := atan2(flow.x, flow.y) if flow.length() > 0.2 else _rng.randf() * TAU
		_launch(free, Vector3(q.x, lv, q.y), yaw)
		_jump_timer = _rng.randf_range(2.5, 7.0) / maxf(_q, 0.5)
		return
	_jump_timer = 1.5                        # no water in reach: look again soon


## One leap: the fish arcs over ~1.3 m in 0.85 s; rings where it leaves and
## where it re-enters, a spray of droplets at both. Tweens drive the shader
## uniforms, so nothing runs in script per frame.
func jump_fish_at(at: Vector3, yaw := 0.0) -> void:
	for j in _jumpers:
		if not j["busy"]:
			_launch(j, at, yaw)
			return


func _launch(j: Dictionary, at: Vector3, yaw: float) -> void:
	var root: Node3D = j["root"]
	var fm: ShaderMaterial = j["fish_mat"]
	var rm: ShaderMaterial = j["ring_mat"]
	var drops: GPUParticles3D = j["drops"]
	var fish: MeshInstance3D = j["fish"]
	j["busy"] = true
	root.global_position = at
	root.rotation = Vector3(0, yaw, 0)
	root.visible = true
	fish.visible = true
	var length := _rng.randf_range(0.9, 1.6)
	var height := _rng.randf_range(0.45, 0.8)
	var dur := 0.55 + height * 0.45
	var a := Vector3(0, -0.25, -length * 0.5)
	var b := Vector3(0, -0.25, length * 0.5)
	fm.set_shader_parameter("jump_from", a)
	fm.set_shader_parameter("jump_to", b)
	fm.set_shader_parameter("jump_height", height + 0.25)
	fm.set_shader_parameter("progress", 0.0)
	var ring_len := 2.4
	rm.set_shader_parameter("ring_a", Vector2(a.x, a.z))
	rm.set_shader_parameter("ring_b", Vector2(b.x, b.z))
	rm.set_shader_parameter("delay", dur / ring_len)
	rm.set_shader_parameter("age", 0.0)
	drops.amount_ratio = _q
	drops.position = Vector3(a.x, 0.05, a.z)
	drops.restart()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(fm, "shader_parameter/progress", 1.0, dur)
	tw.tween_property(rm, "shader_parameter/age", 1.0, ring_len)
	tw.tween_callback(func() -> void:
		fish.visible = false
		drops.position = Vector3(b.x, 0.05, b.z)
		drops.restart()).set_delay(dur)
	tw.chain().tween_callback(func() -> void:
		root.visible = false
		j["busy"] = false)


## A small school circling under the clear water off the pier (same shore
## search as scripts/world/lakeside.gd). Only drawn within ~45 m.
func _update_school() -> void:
	if _school != null:
		return
	var c: Vector2 = WorldGen.lake_center
	if c.x > 1.0e5 or WorldGen.settlements.is_empty():
		_school = MultiMeshInstance3D.new()      # no lake: mark as done
		return
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	var out := (home - c).normalized()
	var shore := c
	var t := 0.0
	while t < WorldGen.lake_radius * 2.0:
		var q := c + out * t
		if not WorldGen.is_water(q.x, q.y):
			shore = q
			break
		t += 2.0
	var into := -out
	var side := Vector2(into.y, -into.x)
	var spot := shore + into * 12.0 - side * 3.0
	var depth := WorldGen.lake_level - _ground(spot)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.instance_count = SCHOOL_FISH
	var body := PlaneMesh.new()
	body.size = Vector2(0.28, 1.0)
	body.subdivide_depth = 6
	mm.mesh = body
	for i in SCHOOL_FISH:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf(), _rng.randf(), _rng.randf()))
	_school = MultiMeshInstance3D.new()
	_school.name = "FishSchool"
	_school.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = FISH_SHADER
	_school.material_override = m
	_school.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_school.custom_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 2, 8))
	_school.visibility_range_end = 45.0
	_school.visible = depth > 0.8
	add_child(_school)
	_school.global_position = Vector3(spot.x, WorldGen.lake_level - clampf(depth * 0.45, 0.45, 0.9), spot.y)
	_school.multimesh.visible_instance_count = maxi(4, int(SCHOOL_FISH * _q))


# --- Helpers ----------------------------------------------------------------------

func _glow_mat(tint: Color, energy: float, blink: float, far: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = GLOW_SHADER
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("blink", blink)
	m.set_shader_parameter("far_fade", far)
	return m


static func _fade_ramp(c: Color, fade_in: float, fade_out: float) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, fade_in, fade_out, 1.0])
	g.colors = PackedColorArray([Color(c, 0.0), c, c, Color(c, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


static func _grow_shrink(grow: float, shrink: float) -> CurveTexture:
	var cv := Curve.new()
	cv.add_point(Vector2(0.0, 0.0))
	cv.add_point(Vector2(grow, 1.0))
	cv.add_point(Vector2(shrink, 1.0))
	cv.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = cv
	return ct
