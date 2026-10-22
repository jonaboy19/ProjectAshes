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


func _ready() -> void:
	terrain = Terrain3D.new()
	terrain.name = "Terrain3D"
	terrain.vertex_spacing = SPACING
	terrain.region_size = REGION_SIZE
	terrain.collision_mode = 0                # DISABLED: TerrainStreamer's trimesh bodies (same WorldGen.height) stay the physics ground
	terrain.render_layers = 1 | TownDecals.GROUND_LAYER      # ground decals (ruts, puddles) project onto it, as onto the legacy chunks
	add_child(terrain)
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
		assets.set_texture(i, ta)
	return assets


# --- region maths (thread-safe: reads WorldGen's static data only) -----------------------------------

static func region_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / REGION_M), floori(z / REGION_M))


static func region_origin(loc: Vector2i) -> Vector2:
	return Vector2(loc.x * REGION_M, loc.y * REGION_M)


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
	var free := clampf(1.0 - w.r - w.b - w.g, 0.0, 1.0)      # roads, cobble and rock faces keep priority
	var snow := smoothstep(SNOW_LINE - 6.0, SNOW_LINE + 10.0, h) * (1.0 - smoothstep(0.55, 0.85, slope))
	return [m[1] * free, m[2] * free, m[3] * free, m[4] * free, maxf(m[5], snow) * free, m[6] * free, m[0] * free]   # last = forest litter (-> w.a)


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
	var n := REGION_SIZE
	var stride := n + 2
	var hb := PackedFloat32Array()
	hb.resize(stride * stride)          # one pixel of halo each side for the slope (colour/material weights)
	for j in stride:
		for i in stride:
			hb[j * stride + i] = WorldGen.height(o.x + (i - 1) * SPACING, o.y + (j - 1) * SPACING)
	var hbytes := PackedByteArray()
	hbytes.resize(n * n * 4)
	var cbytes := PackedByteArray()
	cbytes.resize(n * n * 4)
	for j in n:
		for i in n:
			var c := (j + 1) * stride + i + 1
			var h := hb[c]
			hbytes.encode_float((j * n + i) * 4, h)
			var normal_y := 2.0 * SPACING / Vector3(hb[c - 1] - hb[c + 1], 2.0 * SPACING, hb[c - stride] - hb[c + stride]).length()
			var wx := o.x + i * SPACING
			var wz := o.y + j * SPACING
			var w := WorldGen.color_at(wx, wz, h, 1.0 - normal_y)
			var ex: Array = []
			if WorldMacro.active:
				ex = macro_extras(wx, wz, h, 1.0 - normal_y, w)
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
				var t := WorldBiomes.tint(WorldBiomes.soft_weights(o.x + i * SPACING, o.y + j * SPACING))
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
	if _assets_frame >= 0 and Engine.get_process_frames() >= _assets_frame and terrain.data != null and terrain.data.get_region_count() > 0:
		terrain.assets = _make_assets()
		_assets_frame = -1
	update_streaming()


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


func _add_region(loc: Vector2i, maps: Array) -> void:
	var r := Terrain3DRegion.new()
	r.region_size = REGION_SIZE
	r.vertex_spacing = SPACING
	r.location = loc
	r.height_map = maps[0]
	r.control_map = maps[1]
	r.color_map = maps[2]
	r.calc_height_range()
	terrain.data.add_region(r, true)
	_regions[loc] = r


## Builds every region around `at` right now (spawn/teleport), in parallel on the worker pool.
func build_all_now(at: Vector3) -> void:
	focus = at
	var center := region_of(at.x, at.z)
	var todo: Array = []
	for m: Array in _wanted(center):
		var loc: Vector2i = m[1]
		if not _regions.has(loc):
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
