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
	# Field walls and hedgerows round every settlement, nearest Ashford first, one settlement per frame (never a blocking bake).
	add_child(preload("res://scripts/world/real_slice.gd").new())   # benchmark slice countryside route (authored)
	_field_meshes()
	_field_queue = WorldGen.settlements.duplicate()
	_field_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["pos"] as Vector2).length() < (b["pos"] as Vector2).length())


var _field_queue: Array = []
var _wall_mesh: Mesh
const STONE_DIR := "res://assets/incoming/polyhaven/textures/mossy_stone_wall/mossy_stone_wall_"


## A 4 m Lake District dry-stone wall segment: battered (wider at the foot), ~3 courses of irregular flat stones plus a row of
## upright cap stones, one ArrayMesh with the Poly Haven CC0 mossy stone wall material. Seamless end to end along x.
static func _drystone_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1883
	var y := 0.0
	for course in 3:
		var hgt := rng.randf_range(0.24, 0.3)
		var half_d := lerpf(0.36, 0.26, course / 2.0)
		var x := -2.0
		while x < 2.0:
			var w := minf(rng.randf_range(0.35, 0.7), 2.0 - x)
			_stone(st, Vector3(x + w * 0.5, y + hgt * 0.5, rng.randf_range(-0.03, 0.03)), Vector3(w * 0.96, hgt * 0.94, half_d * 2.0), rng)
			x += w
		y += hgt
	var cx := -2.0
	while cx < 2.0:
		var w2 := minf(rng.randf_range(0.18, 0.28), 2.0 - cx)
		_stone(st, Vector3(cx + w2 * 0.5, y + 0.14, 0.0), Vector3(w2 * 0.9, 0.3, 0.36), rng)
		cx += w2
	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(STONE_DIR + "diff_2k.jpg")
	mat.normal_enabled = true
	mat.normal_texture = load(STONE_DIR + "nor_gl_2k.jpg")
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.9, 0.9, 0.9)
	mat.albedo_color = Color(0.82, 0.82, 0.8)
	mesh.surface_set_material(0, mat)
	return mesh


## One roughly box-shaped stone (corners jittered) into `st`.
static func _stone(st: SurfaceTool, c: Vector3, s: Vector3, rng: RandomNumberGenerator) -> void:
	var v: Array[Vector3] = []
	for i in 8:
		var p := Vector3(-0.5 if i & 1 == 0 else 0.5, -0.5 if i & 2 == 0 else 0.5, -0.5 if i & 4 == 0 else 0.5) * s
		p += Vector3(rng.randf_range(-0.04, 0.04), rng.randf_range(-0.03, 0.03), rng.randf_range(-0.04, 0.04))
		v.append(c + p)
	for f: Array in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		st.add_vertex(v[f[0]]); st.add_vertex(v[f[1]]); st.add_vertex(v[f[2]])
		st.add_vertex(v[f[0]]); st.add_vertex(v[f[2]]); st.add_vertex(v[f[3]])
var _hedge_mesh: BoxMesh
var _bush_mesh: SphereMesh


## Lake District field pattern: a slightly rotated grid of 60-110 m fields on gentle open ground around a settlement; each field edge is a
## dry-stone wall (grey, 1.1 m) or a hedgerow (green, 1.8 m, with bushes); gaps at roads, water, forest and steep ground.
func _field_meshes() -> void:
	if _wall_mesh == null:
		_wall_mesh = _drystone_mesh()
		_hedge_mesh = BoxMesh.new()
		_hedge_mesh.size = Vector3(4.0, 1.8, 1.4)
		_hedge_mesh.material = _mat(Color(0.2, 0.36, 0.15))
		_bush_mesh = SphereMesh.new()
		_bush_mesh.radius = 1.3
		_bush_mesh.height = 2.2
		_bush_mesh.radial_segments = 8
		_bush_mesh.rings = 4
		_bush_mesh.material = _mat(Color(0.24, 0.4, 0.17))


func _fields(st: Dictionary) -> void:
	var c: Vector2 = st["pos"]
	var r_in := float(st["radius"]) * 1.9
	var r_out := r_in + 650.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([1066, String(st["name"]), "fields"])
	var ang := rng.randf_range(-0.5, 0.5)
	var ax := Vector2(cos(ang), sin(ang))
	var ay := ax.orthogonal()
	var walls: Array[Transform3D] = []
	var hedges: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	var size := 85.0
	var k := int(r_out / size) + 1
	for gy in range(-k, k + 1):
		for gx in range(-k, k + 1):
			for side in 2:
				var a := c + ax * gx * size + ay * gy * size
				var dir := ax if side == 0 else ay
				var hedge := rng.randf() < 0.35
				var steps := int(size / 4.0)
				for s in steps:
					var p := a + dir * (s * 4.0 + 2.0)
					var d := p.distance_to(c)
					if d < r_in or d > r_out:
						continue
					if preload("res://scripts/world/real_slice.gd").in_corridor(p.x, p.y, 6.0) or WorldGen.road_distance(p.x, p.y) < 8.0 or WorldGen.is_water(p.x, p.y) or WorldGen.forest_density(p.x, p.y) > 0.45:
						continue
					var h := WorldGen.height(p.x, p.y)
					var h2 := WorldGen.height(p.x + dir.x * 4.0, p.y + dir.y * 4.0)
					if absf(h2 - h) > 2.6:
						continue
					var yaw := -atan2(dir.y, dir.x)
					var t := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, h + (-0.08 if not hedge else 0.8), p.y))
					if hedge:
						hedges.append(t)
						if rng.randf() < 0.25:
							bushes.append(Transform3D(Basis.from_scale(Vector3.ONE * rng.randf_range(0.8, 1.5)), Vector3(p.x, h + 1.2, p.y)))
					else:
						walls.append(t)
	_done = [walls, hedges, bushes]


var _task := -1
var _done: Array = []


## Background dressing step (main thread): start the next settlement's field layout on a worker, add the finished one's meshes.
func _dress_step() -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _done.size() == 3:
			_mmi(_wall_mesh, _done[0], 900.0)
			_mmi(_hedge_mesh, _done[1], 900.0)
			_mmi(_bush_mesh, _done[2], 700.0)
		_done = []
	if not _field_queue.is_empty():
		_task = WorkerThreadPool.add_task(_fields.bind(_field_queue.pop_front()), false, "real fields")


func _mmi(mesh: Mesh, ts: Array[Transform3D], range_end: float) -> void:
	if ts.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = ts.size()
	for i in ts.size():
		mm.set_instance_transform(i, ts[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.visibility_range_end = range_end
	add_child(mi)


## Per-biome colour grade (docs/plans/ART_DIRECTION.md: per-biome fog + grade profiles). Biome under the camera -> Environment adjustment
## (saturation, contrast, brightness) and a fog tint, eased over ~3 s. Cheap: one biome lookup twice a second. Weather keeps owning fog density.
## [saturation, contrast, brightness, fog tint]
## Fog tints kept cool blue-grey (the warm beige fog turned far fells pastel pink); the marsh greener, the rift violet.
const GRADE := [[1.08, 1.05, 1.0, Color(0.7, 0.8, 0.92)], [1.12, 1.08, 0.97, Color(0.62, 0.76, 0.78)], [1.1, 1.04, 1.0, Color(0.72, 0.82, 0.92)],
	[1.06, 1.04, 1.0, Color(0.74, 0.8, 0.88)], [0.9, 1.0, 0.96, Color(0.66, 0.76, 0.72)], [1.0, 1.1, 1.0, Color(0.72, 0.78, 0.88)],
	[1.0, 1.12, 0.94, Color(0.72, 0.55, 0.9)], [0.85, 1.08, 1.02, Color(0.78, 0.86, 1.0)]]
var _g_t := 0.0
var _g_target: Array = GRADE[0]
var _g_cur := Vector3(1.0, 1.0, 1.0)
var _g_fog := Color(0.78, 0.86, 0.95)


func _process(delta: float) -> void:
	if not RealWorld.active():
		return
	_dress_step()
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
	# Kilometre-scale views: the 12 km world's depth fog (0.0021) hid everything past 1 km. Base 0.2x, then per biome.
	var b2 := clampi(WorldBiomes.at(cam.global_position.x, cam.global_position.z), 0, 7)
	_fog_mul = lerpf(_fog_mul, 0.2 * float(FOG_BIOME[b2]), k)
	WEATHER.region_fog_mul = _fog_mul


const WEATHER := preload("res://scripts/world/weather.gd")
## Fog per biome (x the real-world base): grass forest meadow farmland marsh highland rift snow.
const FOG_BIOME := [1.0, 1.25, 1.0, 1.0, 2.2, 0.8, 1.8, 1.1]
var _fog_mul := 0.2


func _exit_tree() -> void:
	WEATHER.region_fog_mul = 1.0
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


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
		if emit >= 2.0:
			m.disable_fog = true      # magic light stays vivid through the aerial fog (the Rift column read grey)
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
	l.distance_fade_enabled = true
	l.distance_fade_begin = 900.0
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
	col_mesh.material = _mat(col, 5.0, 0.35)
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
		# An old-giant silhouette: a clustered, irregular crown (9 lobes from the trunk top down to mid-height) and branch limbs,
		# not one flattened dome (owner: "look like mushrooms").
		for li in 9:
			var lobe := SphereMesh.new()
			var lr := h * _rng.randf_range(0.14, 0.24)
			lobe.radius = lr
			lobe.height = lr * 1.7
			lobe.radial_segments = 10
			lobe.rings = 6
			lobe.material = leaf
			var a := TAU * li / 9.0 + _rng.randf() * 0.5
			var out := h * (0.12 if li == 0 else _rng.randf_range(0.18, 0.32))
			var up := h * (1.02 if li == 0 else _rng.randf_range(0.62, 0.95))
			_put(lobe, g + Vector3(cos(a) * out, up, sin(a) * out))
			if li > 0:
				var limb := CylinderMesh.new()
				limb.top_radius = 0.5
				limb.bottom_radius = 1.1
				limb.height = out * 1.2
				limb.material = bark
				var dir := Vector3(cos(a) * out, up - h * 0.55, sin(a) * out)
				var mid := g + Vector3(0, h * 0.55, 0) + dir * 0.5
				var bas := Basis(Quaternion(Vector3.UP, dir.normalized()))
				_put(limb, mid, bas)
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
