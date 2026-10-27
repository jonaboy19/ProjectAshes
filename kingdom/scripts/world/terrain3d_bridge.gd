class_name Terrain3DBridge
extends Node3D
## Terrain3D (TokisanGames, MIT) as the ground renderer, fed from WorldGen (terrain_backend = terrain3d, see TerrainBackend).
##
## WorldGen.height stays the single source of truth: this node only bakes it (and WorldGen.color_at's material weights) into
## Terrain3D region maps, streamed around the focus like TerrainStreamer's chunks (heights on WorkerThreadPool, at most one region
## added per frame). Nothing else reads Terrain3D for gameplay: navigation, building placement, founding, saves and collision keep
## calling WorldGen.height (collision still comes from TerrainStreamer's per-chunk trimesh, built from the same function).
##
## Layout: vertex spacing 1.5 m x 256 px = 384 m regions. Terrain3D addresses 32 x 32 region locations (-16..15), which at 384 m is
## exactly the 12 km world (-6144..6144), so the whole map fits without a second terrain node.
## Control map: 5 texture slots (below). Each pixel blends the two heaviest of {grass, forest, path, rock, cobble} (base + overlay + blend),
## i.e. the legacy vertex-colour channels (r path, g rock, b cobble, a forest) become the control map.

const SPACING := 1.5
const REGION_SIZE := 256
const REGION_M := SPACING * REGION_SIZE
## W6 real world: 768 m regions so the 32 x 32 Terrain3D locations cover +-12.3 km (the whole Valencious box).
## 3 m spacing x 256 px on every tier (the source is 8 m data; 1.5 m x 512 px baked in ~20 s a region, 3 m in ~5 s, and suits the
## iGPU target, docs/plans/ART_DIRECTION.md). `--t3d_fine` keeps 1.5 m x 512 px for close-up captures on a strong GPU.
static var spacing_rt := SPACING


static func configure_spacing() -> void:
	spacing_rt = SPACING
	if WorldMacro.is_real() and not OS.get_cmdline_user_args().has("--t3d_fine"):
		spacing_rt = 3.0


static func region_size() -> int:
	if not WorldMacro.is_real():
		return REGION_SIZE
	return 256 if spacing_rt > SPACING else 512


static func region_m() -> float:
	return spacing_rt * region_size()


## Snow line: 180 m in the old worlds; real world by altitude and latitude (north = -z snowier), as in the mock-up.
static func snow_line(z: float) -> float:
	if not WorldMacro.is_real():
		return SNOW_LINE
	# 520 m at Ashford's latitude, 300 m on the northern border (z = -7000, the Northern Ridge tops are 450-650 m), 150 m in Frostcrown.
	return 520.0 - 220.0 * clampf(-z / 7000.0, 0.0, 1.0) - 150.0 * clampf((-z - 7000.0) / 9000.0, 0.0, 1.0) + 100.0 * clampf(z / 9000.0, 0.0, 1.0)


const FIRST_LOC := -16
const LAST_LOC := 15

## Texture slot ids; packed textures come from tools_qa/terrain3d/pack_ground_textures.gd (existing Poly Haven CC0 PBR sets).
## Slots 0-4 are the legacy ground; 5-9 (W1d) are painted only with the Valencious macro (biome_ids/splat_weights): meadow, farmland,
## marsh mud, rift ash (violet-black), snow/scree. Packed by tools_qa/terrain3d/pack_ground_textures.gd.
const SLOTS := ["grass", "forest", "path", "rock", "cobble", "meadow", "farmland", "marsh", "rift", "snow", "highland"]
const SNOW_LINE := 180.0
const TEX_DIR := "res://assets/terrain3d/ground/"
## Texture repeat per metre (legacy terrain.gdshader tile_size = 4 m -> 0.25), per slot. TUNE on the GPU.
const UV_SCALE := {"grass": 0.25, "forest": 0.22, "path": 0.25, "rock": 0.2, "cobble": 0.3, "meadow": 0.25, "farmland": 0.2, "marsh": 0.22, "rift": 0.2, "snow": 0.18, "highland": 0.22}
## Per slot: [normal_depth, ao_strength, roughness_offset]. TUNE on the GPU.
const SLOT_LOOK := {"grass": [0.9, 0.6, 0.0], "forest": [1.0, 0.7, 0.0], "path": [0.8, 0.5, 0.0], "rock": [1.2, 0.8, 0.0], "cobble": [0.9, 0.6, 0.0], "meadow": [0.8, 0.6, 0.0], "farmland": [0.9, 0.7, 0.0], "marsh": [0.9, 0.6, 0.0], "rift": [1.2, 0.8, 0.0], "snow": [0.7, 0.4, 0.0], "highland": [1.0, 0.7, 0.0]}
const GRASS_TINT := Color(0.88, 1.0, 0.76)     # legacy grass_tint (0.85, 1.0, 0.7) softened: the colour map multiplies albedo

## Regions kept around the focus (Chebyshev, in regions): 1 -> 3x3 (1.15 km span), 2 -> 5x5. Quality scales it.
var region_radius := 1
const MAX_IN_FLIGHT := 3

var terrain: Terrain3D
var focus := Vector3.ZERO
var _tasks: Dictionary = {}          # Vector2i -> task id
var _maps: Dictionary = {}           # Vector2i -> Array[Image] (finished, guarded by _mutex)
var _mutex := Mutex.new()
var _loc_idle := Vector2i(1 << 30, 0)
var _assets_frame := -1             # process frame at which the texture assets may be set (GPU only, see _ready)
var _regions: Dictionary = {}        # Vector2i -> Terrain3DRegion currently added
var _awaiting_camera := true


func _ready() -> void:
	configure_spacing()
	if WorldMacro.is_real():
		RealInstancer.kinds()          # W6.4: mesh id table built on the main thread before any worker plans instances
		var q: Node = get_tree().root.get_node_or_null("Quality") if is_inside_tree() else null
		_inst_mul = clampf(float(q.call("value", "scatter")) if q and q.has_method("value") else 1.0, 0.25, 1.0)
	terrain = Terrain3D.new()
	terrain.name = "Terrain3D"
	terrain.vertex_spacing = spacing_rt
	terrain.region_size = region_size()
	terrain.collision_mode = 0                # DISABLED: TerrainStreamer's trimesh bodies (same WorldGen.height) stay the physics ground
	terrain.render_layers = 1 | TownDecals.GROUND_LAYER      # ground decals (ruts, puddles) project onto it, as onto the legacy chunks
	add_child(terrain)
	# Main adds the player after it finishes the first terrain build, so a viewport camera may not exist yet.
	# Do not let Terrain3D's first physics tick stop itself while it tries to acquire a camera.
	terrain.set_physics_process(false)
	_configure_material()
	# Terrain3D 1.0.2 on Godot 4.6.3 (Forward+, RTX 4070 Laptop) crashes with signal 11 when texture assets and the first region are set in the
	# frame the node enters the tree ("Width must be equal or greater than 1 for all textures"; found by W1 GPU captures, tools_qa/terrain3d/gpu_probe.gd).
	# Regions first, assets two frames later. Headless (no GPU) has no such problem, so tests get them at once.
	if DisplayServer.get_name() == "headless":
		terrain.assets = _make_assets()
	else:
		_assets_frame = Engine.get_process_frames() + 2


func _configure_material() -> void:
	var mat := terrain.material
	if mat:
		mat.world_background = 0               # NONE beyond the streamed regions
		mat.texture_filtering = 0              # LINEAR
	var look := Terrain3DLook.apply(terrain)     # W3: weather / season / snow / scar-tide on the Terrain3D ground
	if look:
		add_child(look)
	if mat and WorldMacro.is_real():
		# W6.4: Terrain3D's own macro variation + softer blending (owner: big contrasty blotches, 6 m steps). Built-in params of the
		# Terrain3D shader that our override keeps: two low-frequency tint fields break tiling and large flat areas.
		var nt := NoiseTexture2D.new()
		nt.width = 512
		nt.height = 512
		nt.seamless = true
		var fn := FastNoiseLite.new()
		fn.seed = 1066
		fn.frequency = 0.02
		fn.fractal_octaves = 4
		nt.noise = fn
		mat.set_shader_param("noise_texture", nt)
		mat.set_shader_param("enable_macro_variation", true)
		mat.set_shader_param("macro_variation1", Color(0.9, 0.97, 0.86))
		mat.set_shader_param("macro_variation2", Color(1.0, 0.95, 0.88))
		mat.set_shader_param("noise1_scale", 0.02)
		mat.set_shader_param("noise2_scale", 0.05)
		mat.set_shader_param("blend_sharpness", 0.22)
		mat.set_shader_param("enable_projection", true)          # steep-face projection for the crags
		mat.set_shader_param("projection_threshold", 0.7)


func _exit_tree() -> void:
	for key: Vector2i in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[key])
	_tasks.clear()


# --- assets ---------------------------------------------------------------------------------------

static func _make_assets() -> Terrain3DAssets:
	var assets := Terrain3DAssets.new()
	for i in SLOTS.size():
		var name: String = SLOTS[i]
		var ta := Terrain3DTextureAsset.new()
		ta.name = name
		ta.id = i
		ta.albedo_texture = load(TEX_DIR + name + "_alb_h.png")
		ta.normal_texture = load(TEX_DIR + name + "_nrm_r.png")
		ta.uv_scale = float(UV_SCALE[name])
		var look: Array = SLOT_LOOK[name]
		ta.normal_depth = float(look[0])
		ta.ao_strength = float(look[1])
		ta.roughness = float(look[2])
		if name == "grass":
			ta.albedo_color = GRASS_TINT
		elif name == "snow" and WorldMacro.is_real():
			ta.albedo_color = Color(1.15, 1.35, 1.75)   # W6: the scree-grey snow read as sand on the real fells; lift it to snow white
		assets.set_texture(i, ta)
	if WorldMacro.is_real():
		var ml: Array = RealInstancer.mesh_assets(_inst_mul < 0.5)
		for i in ml.size():
			assets.set_mesh_asset(i, ml[i])
	return assets


# --- region maths (thread-safe: reads WorldGen's static data only) -----------------------------------

static func region_of(x: float, z: float) -> Vector2i:
	var rm := region_m()
	return Vector2i(floori(x / rm), floori(z / rm))


static func region_origin(loc: Vector2i) -> Vector2:
	var rm := region_m()
	return Vector2(loc.x * rm, loc.y * rm)


static func in_world(loc: Vector2i) -> bool:
	return loc.x >= FIRST_LOC and loc.x <= LAST_LOC and loc.y >= FIRST_LOC and loc.y <= LAST_LOC


## The control-map word for material weights (Terrain3D layout: base <<27, overlay <<22, blend <<14).
static func control_word(w: Color, ex: Array = []) -> int:
	var wt := [maxf(0.0, 1.0 - clampf(w.a + w.r + w.g + w.b + _sum(ex), 0.0, 1.0)), w.a, w.r, w.g, w.b]   # grass, forest, path, rock, cobble
	wt.append_array(ex)                                  # meadow, farmland, marsh, rift, snow (macro only)
	var n := wt.size()
	var a := 0
	for i in n:
		if wt[i] > wt[a]:
			a = i
	var b := 0 if a != 0 else 1
	for i in n:
		if i != a and wt[i] > wt[b]:
			b = i
	var wa: float = wt[a]
	var wb: float = wt[b]
	if wb < 0.02:
		return (a << 27) | (a << 22)                     # one material, no blend
	# Terrain3D blends base -> overlay by `blend` (0 = all base, 255 = all overlay): base = the lighter material, overlay = the heavier.
	var blend := int(roundf(255.0 * wa / (wa + wb)))
	# Keep grass in the base layer whenever it is one of the selected pair. Swapping
	# Grass between base and overlay as weights cross made the same soft biome
	# boundary render differently on either side. Reversing the blend preserves the
	# two selected weights while giving the shader a stable base for ground layers.
	if a == 0:
		return (b << 22) | ((255 - blend) << 14)
	return (b << 27) | (a << 22) | (blend << 14)


static func _sum(ex: Array) -> float:
	var t := 0.0
	for v in ex:
		t += float(v)
	return t


## Macro biome extras for a ground sample: [meadow, farmland, marsh, rift ash, snow, highland, forest litter] (empty without the macro, so legacy words are unchanged).
## W3: weights come from WorldBiomes' soft (>= 150 m, noise-warped) biome field, not the 12 m splat, so grass/meadow stay the base nearly everywhere
## and farmland dirt / forest litter are only soft patches. `w.a` (forest litter) is rewritten here too.
static func macro_extras(x: float, z: float, h: float, slope: float, w: Color) -> Array:
	var sw := WorldBiomes.soft_weights(x, z)
	var patch := 0.5 + 0.5 * _patch_noise().get_noise_2d(x, z)
	var m := WorldBiomes.ground_mix(sw, patch)
	var free := clampf(1.0 - w.r - w.b - (0.0 if WorldMacro.is_real() else w.g), 0.0, 1.0)      # roads, cobble and rock faces keep priority (W6: real rock comes from real_layers)
	var sl := snow_line(z)
	if WorldMacro.is_real():
		return real_layers(x, z, h, slope, m, free, sl)
	var snow := smoothstep(sl - 6.0, sl + 10.0, h) * (1.0 - smoothstep(0.55, 0.85, slope))
	return [m[1] * free, m[2] * free, m[3] * free, m[4] * free, maxf(m[5], snow) * free, m[6] * free, m[0] * free]   # last = forest litter (-> w.a)


## W6 real world ground layering (owner review: hard green/tan blobs). On top of the soft biome mix: grass/meadow in the valley floors,
## heather-brown highland on the fell sides (slope, noise-broken edge), scree/rock on steep faces, snow above a noisy snow line that
## creeps lower in gullies (slope) - so materials follow the land like the Lake District fells instead of the biome cells.
static func real_layers(x: float, z: float, h: float, slope: float, m: PackedFloat32Array, free: float, sl: float) -> Array:
	var n1 := _patch_noise().get_noise_2d(x * 3.1, z * 3.1)            # ~50 m breakup
	var n2 := _patch_noise().get_noise_2d(x * 0.9 + 400.0, z * 0.9)     # ~180 m breakup
	var fell := smoothstep(0.16, 0.42, slope + n1 * 0.08 + n2 * 0.05) * smoothstep(60.0, 160.0, h + n2 * 40.0)
	var crag := smoothstep(0.62, 0.95, slope + n1 * 0.1)
	var snow_edge := sl + n1 * 35.0 + n2 * 25.0 - slope * 40.0
	var snow := smoothstep(snow_edge - 12.0, snow_edge + 12.0, h) * (1.0 - smoothstep(0.7, 0.95, slope))
	var valley := 1.0 - fell
	# Fell sides stay green (grass + bracken-brown litter); the pale highland ground only in the alpine band below the snow.
	var alpine := smoothstep(sl - 170.0, sl - 40.0, h + n2 * 30.0)
	var n3 := _patch_noise().get_noise_2d(x * 9.0 + 77.0, z * 9.0)       # ~18 m low-contrast detail
	var meadow := (m[1] + valley * (0.15 + 0.1 * n2 + 0.08 * n3)) * valley
	var high := maxf(m[6] * 0.4, alpine * 0.8) * (1.0 - snow) * (0.4 + 0.6 * fell)
	var marsh := m[3] * valley
	var farm := m[2] * valley
	var forest := maxf(m[0] * 0.7, fell * (0.18 + 0.08 * n3)) * (1.0 - crag) * (1.0 - snow) * (1.0 - alpine)   # softer, smaller-scale litter
	return [meadow * free, farm * free, marsh * free, m[4] * free, snow * free, high * free, forest * free, crag]


## W6.4 instancer: per-region transforms planned on the workers, added once the mesh assets are live (they go in two frames after
## the first region on a GPU). Terrain3D stores instances per region, so removing a region frees its trees too.
static var _inst_mul := 1.0
var _inst: Dictionary = {}          # Vector2i -> {mesh id: Array[Transform3D]} (guarded by _mutex)
var _inst_ready: Array = []


func _flush_instances() -> void:
	if _inst_ready.is_empty() or terrain == null or terrain.assets == null or terrain.assets.get_mesh_count() == 0:
		return
	var plan: Dictionary = _inst_ready.pop_front()
	for id: int in plan:
		var ts: Array[Transform3D] = []
		ts.assign(plan[id])
		terrain.instancer.add_transforms(id, ts)


static var _patch: FastNoiseLite


static func _patch_noise() -> FastNoiseLite:
	if _patch == null:
		_patch = FastNoiseLite.new()
		_patch.seed = 4077
		_patch.frequency = 0.006
	return _patch


## [height, control, colour] images of region `loc`. Pixel (i, j) sits at world origin + (i, j) * SPACING exactly.
static func build_maps(loc: Vector2i) -> Array[Image]:
	var o := region_origin(loc)
	var n := region_size()
	var stride := n + 2
	var hb := PackedFloat32Array()
	hb.resize(stride * stride)          # one pixel of halo each side for the slope (colour/material weights)
	for j in stride:
		for i in stride:
			hb[j * stride + i] = WorldGen.height(o.x + (i - 1) * spacing_rt, o.y + (j - 1) * spacing_rt)
	var hbytes := PackedByteArray()
	hbytes.resize(n * n * 4)
	var cbytes := PackedByteArray()
	cbytes.resize(n * n * 4)
	# W6 note: control words on every second pixel baked ~3x faster but stepped visibly (6 m blocks) from the air: full 3 m lattice now.
	var half_ctl := false
	for j in n:
		for i in n:
			var c := (j + 1) * stride + i + 1
			var h := hb[c]
			hbytes.encode_float((j * n + i) * 4, h)
			if half_ctl and ((i | j) & 1) != 0:
				cbytes.encode_u32((j * n + i) * 4, cbytes.decode_u32(((j & ~1) * n + (i & ~1)) * 4))
				continue
			var normal_y := 2.0 * spacing_rt / Vector3(hb[c - 1] - hb[c + 1], 2.0 * spacing_rt, hb[c - stride] - hb[c + stride]).length()
			var wx := o.x + i * spacing_rt
			var wz := o.y + j * spacing_rt
			var w := WorldGen.color_at(wx, wz, h, 1.0 - normal_y)
			var ex: Array = []
			if WorldMacro.active:
				ex = macro_extras(wx, wz, h, 1.0 - normal_y, w)
				if ex.size() == 8:
					# W6: color_at's rock weight is tuned for the 0-300 m world (every real fell side came out rock): the real world
					# takes its rock from real_layers' crag/scree on genuinely steep faces only.
					w.g = float(ex.pop_back())
				w.a = float(ex.pop_back())               # forest litter weight from the soft biome field
			cbytes.encode_u32((j * n + i) * 4, control_word(w, ex))
	var himg := Image.create_from_data(n, n, false, Image.FORMAT_RF, hbytes)
	var cimg := Image.create_from_data(n, n, false, Image.FORMAT_RF, cbytes)
	var col := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	col.fill(Color(1.0, 1.0, 1.0, 0.5))
	if WorldMacro.active:
		# W3: lush Style G tint from the soft biome field, one sample per 4 px (bilinear in the shader's colour map)
		for j in range(0, n, 4):
			for i in range(0, n, 4):
				var t := WorldBiomes.tint(WorldBiomes.soft_weights(o.x + i * spacing_rt, o.y + j * spacing_rt))
				for dj in 4:
					for di in 4:
						if i + di < n and j + dj < n:
							col.set_pixel(i + di, j + dj, Color(t.r, t.g, t.b, 0.5))
	return [himg, cimg, col]


# --- streaming --------------------------------------------------------------------------------------

func _wanted(center: Vector2i) -> Array:
	var out: Array = []
	for dz in range(-region_radius, region_radius + 1):
		for dx in range(-region_radius, region_radius + 1):
			var loc := center + Vector2i(dx, dz)
			if in_world(loc):
				out.append([dx * dx + dz * dz, loc])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return out


func _process(_delta: float) -> void:
	_flush_instances()
	if _assets_frame >= 0 and Engine.get_process_frames() >= _assets_frame and terrain.data != null and terrain.data.get_region_count() > 0:
		terrain.assets = _make_assets()
		_assets_frame = -1
	_track_camera()
	update_streaming()


## Terrain3D positions its clip-map (LOD rings, geomorph distance, tile culling) around the camera it holds. It grabs one once and then keeps
## it: after a camera switch (player camera -> cutscene / free / capture camera) it stayed on the old or a null camera, so the near LOD0
## tiles sat around the wrong point and the ground next to the real camera vanished (W5: the Rift Marches ground view, a tilted plane over
## fog). Always follow the viewport's current camera.
func _track_camera() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or terrain == null:
		return
	if terrain.get_camera() != cam:
		terrain.set_camera(cam)
	if _awaiting_camera:
		terrain.set_physics_process(true)
		_awaiting_camera = false


## Frees far regions, queues missing ones on workers, adds at most one finished region. Returns true while work remains.
func update_streaming() -> bool:
	if terrain == null or terrain.data == null:
		return false
	var center := region_of(focus.x, focus.z)
	if center == _loc_idle and _tasks.is_empty():
		return false
	for loc: Vector2i in _regions.keys():
		if maxi(absi(loc.x - center.x), absi(loc.y - center.y)) > region_radius + 1:
			terrain.data.remove_region(_regions[loc], true)
			_regions.erase(loc)
	for key: Vector2i in _tasks.keys():
		if WorkerThreadPool.is_task_completed(_tasks[key]):
			WorkerThreadPool.wait_for_task_completion(_tasks[key])
			_tasks.erase(key)
	var added := false
	var pending := false
	for m: Array in _wanted(center):
		var loc: Vector2i = m[1]
		if _regions.has(loc):
			continue
		pending = true
		var maps := _take(loc)
		if not maps.is_empty():
			if not added:
				_add_region(loc, maps)
				added = true
			else:
				_put(loc, maps)             # keep it for next frame
		elif _tasks.size() < MAX_IN_FLIGHT and not _tasks.has(loc):
			_tasks[loc] = WorkerThreadPool.add_task(_worker.bind(loc), false, "terrain3d region")
	if not pending and _tasks.is_empty():
		_loc_idle = center
	return pending


func _worker(loc: Vector2i) -> void:
	var maps := build_maps(loc)
	if WorldMacro.is_real():
		var inst := RealInstancer.plan(region_origin(loc), region_m(), _inst_mul)
		_mutex.lock()
		_inst[loc] = inst
		_mutex.unlock()
	_put(loc, maps)


func _put(loc: Vector2i, maps: Array) -> void:
	_mutex.lock()
	_maps[loc] = maps
	_mutex.unlock()


func _take(loc: Vector2i) -> Array:
	_mutex.lock()
	var m: Array = _maps.get(loc, [])
	_maps.erase(loc)
	_mutex.unlock()
	return m


## [regions added, total main-thread microseconds in add_region, worst single add] (perf QA: the "region bake hitch").
static var add_stats := [0, 0, 0]


func _add_region(loc: Vector2i, maps: Array) -> void:
	var t0 := Time.get_ticks_usec()
	var r := Terrain3DRegion.new()
	r.region_size = region_size()
	r.vertex_spacing = spacing_rt
	r.location = loc
	r.height_map = maps[0]
	r.control_map = maps[1]
	r.color_map = maps[2]
	r.calc_height_range()
	terrain.data.add_region(r, true)
	_regions[loc] = r
	_mutex.lock()
	if _inst.has(loc):
		_inst_ready.append(_inst[loc])
		_inst.erase(loc)
	_mutex.unlock()
	var dt := Time.get_ticks_usec() - t0
	add_stats = [int(add_stats[0]) + 1, int(add_stats[1]) + dt, maxi(int(add_stats[2]), dt)]


## Builds every region around `at` right now (spawn/teleport), in parallel on the worker pool.
func build_all_now(at: Vector3) -> void:
	focus = at
	var center := region_of(at.x, at.z)
	var todo: Array = []
	for m: Array in _wanted(center):
		var loc: Vector2i = m[1]
		if not _regions.has(loc):
			# W6: the real world only blocks on the regions within 300 m of the spawn; the rest of the ring streams in behind (fast start).
			if WorldMacro.is_real() and Rect2(region_origin(loc), Vector2.ONE * region_m()).grow(300.0).has_point(Vector2(at.x, at.z)) == false:
				continue
			todo.append(loc)
	var ids: Array[int] = []
	for loc: Vector2i in todo:
		if _tasks.has(loc):
			WorkerThreadPool.wait_for_task_completion(_tasks[loc])
			_tasks.erase(loc)
		var ld := loc
		ids.append(WorkerThreadPool.add_task(_worker.bind(ld), true, "terrain3d region (sync)"))
	for id in ids:
		WorkerThreadPool.wait_for_task_completion(id)
	for loc: Vector2i in todo:
		var maps := _take(loc)
		if not maps.is_empty():
			_add_region(loc, maps)
	_loc_idle = Vector2i(1 << 30, 0)
	update_streaming()


func region_count() -> int:
	return _regions.size()


func has_region_at(x: float, z: float) -> bool:
	return _regions.has(region_of(x, z))


## Terrain3D's own interpolated height (NAN where no region is loaded). Gameplay must use WorldGen.height instead.
func sampled_height(x: float, z: float) -> float:
	return terrain.data.get_height(Vector3(x, 0.0, z)) if terrain != null and terrain.data != null else NAN
