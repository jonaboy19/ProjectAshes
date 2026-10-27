extends Node3D
## W6 fantasy pass on the real-world terrain (docs/world/REAL_WORLD.md): lore landmarks as sculpted set pieces, placed on the
## re-anchored sites (RealWorld/WorldGen data, nothing hand-positioned in metres here except offsets):
##   Wyrm's Ribs      giant bone arcs breaking out of the ridge
##   The Rift          a violet glowing scar with floating shards of rock above it
##   The Ashen Scar    ember-glowing ground, sparks of light
##   Sleeping Flame    an eternal flame on the shrine
##   Mistwood          giant ancient trees with glowing undergrowth
##   Frostcrown edge   frost crystals on the snowy northern heights
##   Waterfalls        white falls on every steep river step (Hollin Falls included)
## Built once at _ready from WorldGen data (a few hundred meshes, visibility-ranged). Only with --world_macro=real.

const RANGE := 2600.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "RealLandmarks"
	_rng.seed = 1066
	if not RealWorld.active():
		return
	_ribs(_site("site:The Wyrm's Ribs"))
	_glow(_site("site:The Rift"), Color(0.62, 0.25, 1.0), 120.0, true)
	_glow(_site("site:The Ashen Scar"), Color(1.0, 0.42, 0.12), 160.0, false)
	_flame(_site("site:Shrine of the Sleeping Flame"))
	_giants(_site("lore:mistwood"))
	_crystals()
	_waterfalls()


## Per-biome colour grade (docs/plans/ART_DIRECTION.md: per-biome fog + grade profiles). Biome under the camera -> Environment adjustment
## (saturation, contrast, brightness) and a fog tint, eased over ~3 s. Cheap: one biome lookup twice a second. Weather keeps owning fog density.
## [saturation, contrast, brightness, fog tint]
const GRADE := [[1.08, 1.04, 1.0, Color(0.78, 0.86, 0.95)], [1.12, 1.08, 0.97, Color(0.62, 0.78, 0.7)], [1.1, 1.02, 1.02, Color(0.85, 0.9, 0.9)],
	[1.06, 1.03, 1.02, Color(0.92, 0.88, 0.78)], [0.88, 1.0, 0.96, Color(0.7, 0.76, 0.7)], [0.98, 1.1, 1.0, Color(0.86, 0.82, 0.76)],
	[1.0, 1.12, 0.94, Color(0.72, 0.55, 0.9)], [0.85, 1.06, 1.05, Color(0.82, 0.9, 1.0)]]
var _g_t := 0.0
var _g_target: Array = GRADE[0]
var _g_cur := Vector3(1.0, 1.0, 1.0)
var _g_fog := Color(0.78, 0.86, 0.95)


func _process(delta: float) -> void:
	if not RealWorld.active():
		return
	var env: Environment = get_viewport().find_world_3d().environment if get_viewport() and get_viewport().find_world_3d() else null
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if env == null or cam == null:
		return
	_g_t -= delta
	if _g_t <= 0.0:
		_g_t = 0.5
		var b := WorldBiomes.at(cam.global_position.x, cam.global_position.z)
		_g_target = GRADE[clampi(b, 0, 7)]
	var k := clampf(delta / 3.0, 0.0, 1.0)
	_g_cur = _g_cur.lerp(Vector3(_g_target[0], _g_target[1], _g_target[2]), k)
	_g_fog = _g_fog.lerp(_g_target[3], k)
	env.adjustment_enabled = true
	env.adjustment_saturation = _g_cur.x
	env.adjustment_contrast = _g_cur.y
	env.adjustment_brightness = _g_cur.z
	env.fog_light_color = env.fog_light_color.lerp(_g_fog, 0.35)


func _site(id: String) -> Vector2:
	var p: Variant = RealWorld.place(id)
	return p if p != null else Vector2.INF


func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


static func _mat(col: Color, emit := 0.0, alpha := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.roughness = 0.8
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	return m


func _put(mesh: Mesh, at: Vector3, basis := Basis(), range_end := RANGE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(basis, at)
	mi.visibility_range_end = range_end
	add_child(mi)
	return mi


func _light(at: Vector3, col: Color, energy: float, rng_m: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	l.position = at
	l.visibility_range_end = 900.0
	add_child(l)


## Nine curved ribs (arched capsule chains) along the ridge, tallest in the middle.
func _ribs(c: Vector2) -> void:
	if c == Vector2.INF:
		return
	var bone := _mat(Color(0.86, 0.82, 0.72))
	for k in 9:
		var t := (k - 4) / 4.0
		var base := c + Vector2(t * 110.0, 0.0)
		var hgt := 34.0 * (1.0 - 0.45 * t * t)
		var seg := CapsuleMesh.new()
		seg.radius = 1.6 - 0.5 * absf(t)
		seg.height = hgt / 5.0
		seg.material = bone
		for side in [-1.0, 1.0]:
			for s in 6:
				var a := float(s) / 6.0 * PI * 0.5
				var off := Vector3(0.0, sin(a) * hgt, side * (1.0 - cos(a)) * hgt * 0.55)
				var g := _ground(base)
				var bas := Basis(Vector3.RIGHT, side * a * 0.9)
				_put(seg, g + off + Vector3(0, -2.0, 0), bas)


## A glowing breach: emissive ground disc, a light column and (for the Rift) floating rock shards.
func _glow(c: Vector2, col: Color, r: float, shards: bool) -> void:
	if c == Vector2.INF:
		return
	var g := _ground(c)
	var disc := CylinderMesh.new()
	disc.top_radius = r * 0.35
	disc.bottom_radius = r * 0.35
	disc.height = 0.3
	disc.material = _mat(col, 2.5, 0.75)
	_put(disc, g + Vector3(0, 0.6, 0), Basis.from_scale(Vector3(1.8, 1.0, 0.45)))
	var col_mesh := CylinderMesh.new()
	col_mesh.top_radius = 3.0
	col_mesh.bottom_radius = 9.0
	col_mesh.height = 140.0
	col_mesh.material = _mat(col, 3.0, 0.18)
	_put(col_mesh, g + Vector3(0, 70.0, 0))
	_light(g + Vector3(0, 12.0, 0), col, 6.0, 140.0)
	if shards:
		var rock := _mat(Color(0.22, 0.18, 0.26))
		for i in 7:
			var m := SphereMesh.new()
			var s := _rng.randf_range(6.0, 16.0)
			m.radius = s
			m.height = s * 1.3
			m.radial_segments = 7
			m.rings = 4
			m.material = rock
			var ang := TAU * i / 7.0
			_put(m, g + Vector3(cos(ang) * r * 0.6, _rng.randf_range(35.0, 85.0), sin(ang) * r * 0.6),
				Basis.from_euler(Vector3(_rng.randf(), _rng.randf() * TAU, _rng.randf())))


func _flame(c: Vector2) -> void:
	if c == Vector2.INF:
		return
	var g := _ground(c)
	var f := SphereMesh.new()
	f.radius = 1.4
	f.height = 4.0
	f.material = _mat(Color(1.0, 0.55, 0.15), 6.0, 0.85)
	_put(f, g + Vector3(0, 3.0, 0))
	_light(g + Vector3(0, 4.0, 0), Color(1.0, 0.55, 0.2), 4.0, 45.0)


## Ancient giant trees and glowing undergrowth in Mistwood.
func _giants(c: Vector2) -> void:
	if c == Vector2.INF:
		return
	var bark := _mat(Color(0.28, 0.2, 0.14))
	var leaf := _mat(Color(0.16, 0.34, 0.2))
	var glow := _mat(Color(0.35, 0.95, 0.85), 3.0)
	for i in 9:
		var p := c + Vector2(_rng.randf_range(-900, 900), _rng.randf_range(-900, 900))
		if WorldGen.is_water(p.x, p.y):
			continue
		var g := _ground(p)
		var h := _rng.randf_range(48.0, 70.0)
		var trunk := CylinderMesh.new()
		trunk.top_radius = 2.2
		trunk.bottom_radius = 4.5
		trunk.height = h
		trunk.material = bark
		_put(trunk, g + Vector3(0, h * 0.5 - 1.0, 0))
		var crown := SphereMesh.new()
		crown.radius = h * 0.42
		crown.height = h * 0.5
		crown.material = leaf
		_put(crown, g + Vector3(0, h, 0))
		for k in 6:
			var mush := SphereMesh.new()
			mush.radius = 0.6
			mush.height = 0.5
			mush.material = glow
			var a := TAU * k / 6.0
			var q := p + Vector2(cos(a), sin(a)) * _rng.randf_range(6.0, 14.0)
			_put(mush, _ground(q) + Vector3(0, 0.2, 0), Basis(), 400.0)


## Frost crystals on the snowy heights of the northern realm edge.
func _crystals() -> void:
	var b := RealWorld.box()
	var ice := _mat(Color(0.6, 0.9, 1.0), 1.6, 0.8)
	var placed := 0
	var tries := 0
	while placed < 16 and tries < 600:
		tries += 1
		var p := Vector2(_rng.randf_range(b.position.x, b.end.x), _rng.randf_range(b.position.y, b.position.y + 3500.0))
		var h := WorldGen.height(p.x, p.y)
		if h < Terrain3DBridge.snow_line(p.y) + 20.0:
			continue
		for k in 3:
			var pr := PrismMesh.new()
			pr.size = Vector3(3.0, _rng.randf_range(9.0, 18.0), 3.0)
			pr.material = ice
			_put(pr, Vector3(p.x + k * 3.0, h + 4.0, p.y + k * 2.0), Basis.from_euler(Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3))))
		placed += 1


## Waterfalls where a river drops more than 5 m within ~50 m (inside the realm), plus Hollin Falls.
func _waterfalls() -> void:
	var water := _mat(Color(0.85, 0.95, 1.0), 0.6, 0.7)
	var spots: Array = []
	for r: Dictionary in WorldGen.rivers:
		var pts: PackedVector2Array = r["points"]
		var lv: PackedFloat32Array = r["level"]
		for i in range(0, pts.size() - 4, 3):
			var drop := lv[i] - lv[i + 3]
			if drop > 5.0 and RealWorld.in_realm(pts[i], 200.0):
				spots.append([drop, pts[i], pts[i + 3], float(r["width"][i])])
	spots.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var hf := _site("site:Hollin Falls")
	if hf != Vector2.INF:
		spots.push_front([14.0, hf, hf + Vector2(0, 20), 6.0])
	for s: Array in spots.slice(0, 12):
		var a: Vector2 = s[1]
		var b2: Vector2 = s[2]
		var top := WorldGen.height(a.x, a.y)
		var bot := WorldGen.height(b2.x, b2.y)
		var hgt := maxf(top - bot, 6.0)
		var q := QuadMesh.new()
		q.size = Vector2(maxf(float(s[3]), 5.0), hgt)
		q.material = water
		var dir := (b2 - a).normalized()
		var bas := Basis.looking_at(Vector3(dir.x, 0, dir.y), Vector3.UP)
		_put(q, Vector3((a.x + b2.x) * 0.5, bot + hgt * 0.5, (a.y + b2.y) * 0.5), bas, 1500.0)
