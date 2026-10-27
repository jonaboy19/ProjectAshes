class_name WorldBiomes
extends RefCounted
## Biome dressing rules (phase W3 of PA_plans/WORLD_BRIEF.md). Pure data + maths, thread-safe (reads WorldMacro's read-only biome map).
## Biome ids come from data/world/macro/biome_ids.png (order of data/world/valencious_regions.json "biome_ids"):
##   0 grass  1 forest  2 meadow  3 farmland  4 marsh  5 highland  6 rift  7 snow
## With the legacy terrain (--world_macro=noise) `at()` returns LEGACY (-1) and every function here returns the legacy behaviour
## (ScatterChunk.ROLES item lists, GrassField's fixed mix), so the old world is byte-identical.
## Only kinds that already exist are used (assets/generated/region/nature, nature/, floor/ cards). The marsh "reeds" are grass_a / grass_tall
## (there is no reed asset yet).

const LEGACY := -1
const GRASS := 0
const FOREST := 1
const MEADOW := 2
const FARMLAND := 3
const MARSH := 4
const HIGHLAND := 5
const RIFT := 6
const SNOW := 7
const NAMES := ["grass", "forest", "meadow", "farmland", "marsh", "highland", "rift", "snow"]
const R := "region/nature/"

## Spruce/pine take over from the lowland broadleaves above this height (m).
const CONIFER_LINE := 80.0
## Rift and Ashen Scar centres (WorldGen / bible): the "scar slot" thickens rift dressing around them.
const SCAR_SITES := [Vector2(1130.0, 1004.0), Vector2(2718.0, 2654.0)]
const SCAR_RADIUS := 520.0

## Share of the legacy tree density per biome (multiplied into WorldGen.forest_density; zeros stay zero so roads/towns stay clear).
const TREE_MULT := [1.0, 2.2, 0.14, 0.3, 0.3, 0.6, 0.2, 0.35]
## Keep-chance multiplier of the open-ground roles (undergrowth / meadow / rock), per biome.
const KEEP_MULT := {
	"undergrowth": [1.0, 1.3, 0.6, 0.5, 1.2, 0.8, 0.5, 0.4],
	"meadow": [1.0, 0.9, 2.0, 1.0, 2.0, 0.7, 0.25, 0.2],
	"rock": [1.0, 0.6, 0.3, 0.2, 0.4, 3.2, 2.6, 2.2],
}
## Highest ground (m) each role may stand on; legacy is 115 for everything.
const MAX_H := {"tree": [115.0, 115.0, 115.0, 115.0, 115.0, 165.0, 100.0, 150.0],
	"undergrowth": [115.0, 115.0, 115.0, 115.0, 115.0, 150.0, 100.0, 140.0],
	"meadow": [115.0, 115.0, 115.0, 115.0, 115.0, 150.0, 100.0, 140.0],
	"rock": [115.0, 115.0, 115.0, 115.0, 115.0, 260.0, 260.0, 260.0]}

## role -> biome -> {low: items under CONIFER_LINE, high: items above}. items = [[kind, weight], ...]. null = legacy list.
const TABLE := {
	"tree": {
		FOREST: {"low": [[R + "oak_a", 22], [R + "oak_b", 20], [R + "beech_a", 18], [R + "beech_b", 12], [R + "young_oak", 8], [R + "dark_oak", 5], [R + "dead_snag", 2]],
			"high": [[R + "spruce_a", 20], [R + "spruce_b", 14], [R + "pine_scots", 16], [R + "beech_a", 3], [R + "dead_snag", 3]]},
		MEADOW: {"low": [[R + "oak_a", 10], [R + "oak_b", 8], [R + "young_oak", 14], [R + "beech_a", 4]],
			"high": [[R + "pine_scots", 6], [R + "spruce_a", 4], [R + "young_oak", 2]]},
		FARMLAND: {"low": [[R + "oak_a", 8], [R + "oak_b", 6], [R + "young_oak", 12], [R + "beech_a", 3]],
			"high": [[R + "pine_scots", 4], [R + "young_oak", 3]]},
		MARSH: {"low": [[R + "dead_snag", 12], [R + "young_oak", 4], [R + "dark_oak", 2]],
			"high": [[R + "dead_snag", 8], [R + "spruce_a", 2]]},
		HIGHLAND: {"low": [[R + "pine_scots", 14], [R + "spruce_a", 8], [R + "dead_snag", 3], [R + "oak_a", 3]],
			"high": [[R + "pine_scots", 18], [R + "spruce_a", 10], [R + "spruce_b", 6], [R + "dead_snag", 3]]},
		RIFT: {"low": [[R + "dead_snag", 24], [R + "dark_oak", 2]],
			"high": [[R + "dead_snag", 20], [R + "pine_scots", 2]]},
		SNOW: {"low": [[R + "spruce_a", 14], [R + "spruce_b", 8], [R + "pine_scots", 6], [R + "dead_snag", 3]],
			"high": [[R + "spruce_a", 14], [R + "spruce_b", 8], [R + "pine_scots", 6], [R + "dead_snag", 3]]},
	},
	"undergrowth": {
		FOREST: {"low": [[R + "fern_a", 14], [R + "fern_b", 14], [R + "bush_hazel", 8], [R + "bush_dark", 6], [R + "bush_round", 4], [R + "stump_mossy", 3],
			[R + "log_mossy", 4], [R + "stump_broken", 2], ["Mushroom_Common", 4], [R + "log_branchy", 2]]},
		MARSH: {"low": [[R + "fern_a", 12], [R + "fern_b", 12], [R + "grass_a", 14], [R + "log_mossy", 4], [R + "stump_mossy", 4]]},
		HIGHLAND: {"low": [[R + "fern_a", 6], [R + "bush_dark", 6], [R + "log_branchy", 3], [R + "stump_broken", 3]]},
		RIFT: {"low": [[R + "log_branchy", 6], [R + "stump_broken", 6], [R + "bush_dark", 2]]},
		SNOW: {"low": [[R + "bush_dark", 4], [R + "log_branchy", 3], [R + "stump_broken", 2]]},
		MEADOW: {"low": [[R + "bush_hazel", 8], [R + "bush_round", 6], [R + "fern_b", 4], [R + "stump_mossy", 1]]},
		FARMLAND: {"low": [[R + "bush_hazel", 10], [R + "bush_round", 8], [R + "bush_berry", 4], [R + "stump_broken", 1]]},
	},
	"meadow": {
		MEADOW: {"low": [[R + "flowers_warm", 16], [R + "flowers_cool", 14], [R + "grass_tall", 18], [R + "grass_a", 8], [R + "bush_berry", 3], [R + "bush_hazel", 2]]},
		# hedgerow bushes between the fields, a few flowers on the verges
		FARMLAND: {"low": [[R + "bush_hazel", 14], [R + "bush_round", 10], [R + "bush_berry", 6], [R + "grass_tall", 6], [R + "flowers_warm", 4]]},
		MARSH: {"low": [[R + "grass_a", 20], [R + "grass_tall", 14], [R + "fern_b", 8], [R + "fern_a", 6]]},
		FOREST: {"low": [[R + "flowers_warm", 6], [R + "fern_a", 8], [R + "fern_b", 8], [R + "bush_hazel", 4], [R + "grass_tall", 4]]},
		HIGHLAND: {"low": [[R + "grass_tall", 6], [R + "bush_dark", 4], [R + "fern_b", 3], [R + "flowers_cool", 3]]},
		RIFT: {"low": [[R + "grass_a", 3], [R + "log_branchy", 2], [R + "bush_dark", 1]]},
		SNOW: {"low": [[R + "grass_tall", 2], [R + "bush_dark", 2]]},
	},
	"rock": {
		HIGHLAND: {"low": [[R + "rock_cluster", 3], [R + "rock_medium", 3], [R + "boulder_large", 2], [R + "rock_slab", 2]]},
		RIFT: {"low": [[R + "rock_slab", 3], [R + "rock_cluster", 3], [R + "boulder_large", 2], [R + "rock_medium", 2]]},
		SNOW: {"low": [[R + "rock_medium", 3], [R + "boulder_large", 3], [R + "rock_slab", 2], [R + "rock_cluster", 1]]},
	},
}

## Grass (GrassField): density multiplier, clump mix [share clump, share tall; rest = flowers] and flower-drift multiplier, per biome.
const GRASS_DENSITY := [1.0, 0.55, 1.7, 1.1, 1.35, 0.5, 0.1, 0.04]
const GRASS_MIX := [[0.82, 0.13], [0.78, 0.2], [0.58, 0.2], [0.86, 0.1], [0.45, 0.55], [0.8, 0.18], [0.9, 0.1], [0.9, 0.1]]
const FLOWER_MULT := [1.0, 0.5, 1.7, 1.0, 0.25, 0.4, 0.0, 0.0]
const GRASS_DENSITY_MAX := 1.7
## Quality "grass_mul" (PC_HIGH 1.5, PC_ULTRA 2.0) as seen by GrassField's worker thread; TerrainStreamer sets it on the main thread.
static var grass_scale := 1.0


## The biome at (x, z): LEGACY while the Valencious macro is off or not loaded.
static func at(x: float, z: float) -> int:
	if not WorldMacro.is_loaded() or not WorldMacro.wants():
		return LEGACY
	return clampi(WorldMacro.biome_at(x, z), 0, 7)


static func active() -> bool:
	return WorldMacro.is_loaded() and WorldMacro.wants()


static func name_of(biome: int) -> String:
	return NAMES[biome] if biome >= 0 and biome < NAMES.size() else "legacy"


## 0..1 closeness to a rift/scar site (the "scar slot": more dead wood and rock right around the breaches).
static func scar_boost(x: float, z: float) -> float:
	var best := 0.0
	if _scar.is_empty():
		_scar = [RealWorld.remap(SCAR_SITES[0]), RealWorld.remap(SCAR_SITES[1])]   # W6: re-anchored (identity off the real world)
	for p: Vector2 in _scar:
		best = maxf(best, 1.0 - smoothstep(SCAR_RADIUS * 0.3, SCAR_RADIUS, Vector2(x, z).distance_to(p)))
	return best


## Tree density after the biome: min(1, forest_density * mult). Legacy: unchanged.
static func tree_density(biome: int, density: float) -> float:
	if biome < 0:
		return density
	return minf(1.0, density * float(TREE_MULT[biome]))


static func keep_mult(role: String, biome: int) -> float:
	if biome < 0 or not KEEP_MULT.has(role):
		return 1.0
	return float((KEEP_MULT[role] as Array)[biome])


static func max_height(role: String, biome: int) -> float:
	if biome < 0:
		return 115.0
	if WorldMacro.is_real():
		# W6: real fells reach 1 250 m; a 115 m cap left the real-terrain aerials almost treeless. Tree line ~150 m under the
		# northern snow (the scatter's per-instance snow test does the rest).
		# W6.4: trees, undergrowth and rocks come from the Terrain3D instancer (RealInstancer) in the real world; the chunk scatter keeps
		# only the meadow role (flowers, tall grass) so nothing is placed twice.
		return -1.0e9 if role in ["tree", "undergrowth", "rock"] else 420.0
	return float((MAX_H[role] as Array)[biome])


## Item list [[kind, weight], ...] of `role` in `biome` at ground height `h`; empty array = use the legacy ScatterChunk.ROLES list.
static func items(role: String, biome: int, h: float) -> Array:
	if biome < 0 or not TABLE.has(role):
		return []
	var by_biome: Dictionary = TABLE[role]
	if not by_biome.has(biome):
		return []
	var entry: Dictionary = by_biome[biome]
	if h >= (260.0 if WorldMacro.is_real() else CONIFER_LINE) and entry.has("high"):   # W6: broadleaf vales, conifers on the fell sides
		return entry["high"]
	return entry["low"]


## Deterministic kind pick for one scatter point. `u` in [0,1) must come from the point (see pick_u), so a rejected neighbour never shifts survivors.
## Returns "" when the biome has no table for the role (legacy list applies).
static func pick(role: String, biome: int, h: float, u: float) -> String:
	var list := items(role, biome, h)
	if list.is_empty():
		return ""
	var total := 0
	for it: Array in list:
		total += int(it[1])
	var r := u * float(total)
	for it: Array in list:
		r -= float(it[1])
		if r < 0.0:
			return String(it[0])
	return String((list[list.size() - 1] as Array)[0])


## Stable pseudo-random 0..1 from a world position and a salt.
static func pick_u(x: float, z: float, salt: int) -> float:
	var h := hash(Vector3i(roundi(x * 8.0), roundi(z * 8.0), salt))
	return float(h & 0xffffff) / 16777216.0


static func grass_density(biome: int) -> float:
	return 1.0 if biome < 0 else float(GRASS_DENSITY[biome])


static func flower_mult(biome: int) -> float:
	return 1.0 if biome < 0 else float(FLOWER_MULT[biome])


## Grass kind for roll `r` in [0,1): "grass_clump" / "grass_clump_tall" / "flowers_a".
static func grass_kind(biome: int, r: float) -> String:
	var mix: Array = GRASS_MIX[maxi(biome, 0)]
	if r < float(mix[0]):
		return "grass_clump"
	if r < float(mix[0]) + float(mix[1]):
		return "grass_clump_tall"
	return "flowers_a"


# ---- soft ground weights (Terrain3D control + colour map, W3) -------------------------------------------------------------------------
## data/world/macro/biome_soft_{a,b}.png (tools/world/make_biome_soft.py): per-biome weights blurred by a 150 m Gaussian, 48 m cells, sampled
## bilinearly at a noise-warped position, so ground and tint never meet along a hard biome border.
const SOFT_A := "res://data/world/macro/biome_soft_a.png"
const SOFT_B := "res://data/world/macro/biome_soft_b.png"
const SOFT_N := 256
const HALF := 6144.0
const WARP_M := 70.0
## Ground mix of each biome over [grass(rest), forest litter, meadow, farmland, marsh, rift, snow, highland]. Grass/meadow stay the base
## everywhere except real forest floor, marsh, rift and snow; farmland dirt is a soft patch (<= 25 %).
const MIX_FOREST := 0.45
const MIX_FARM := 0.15
const MIX_MARSH := 0.7
const MIX_RIFT := 0.8
const MIX_SNOW := 0.8
const MIX_HIGH := 0.6
## Colour-map tint per biome (multiplies the albedo): lush Style G green on open ground, deeper under trees, dry gold on the highlands.
const TINT := [Color(0.86, 1.0, 0.73), Color(0.84, 1.0, 0.68), Color(0.88, 1.0, 0.71), Color(0.95, 1.0, 0.77),
	Color(0.88, 1.0, 0.8), Color(1.0, 1.0, 0.84), Color(1.0, 0.96, 1.0), Color(1.0, 1.0, 1.0)]    # <= 1: the 8-bit colour map cannot brighten

static var _soft := PackedByteArray()        # SOFT_N^2 * 8
static var _soft_ok := false
static var _half := HALF
static var _scar: Array = []
static var _soft_real := false
static var _soft_mutex := Mutex.new()
static var _warp: FastNoiseLite


static func _soft_load() -> void:
	_soft_mutex.lock()
	if not _soft_ok:
		var real := WorldMacro.is_real()   # W6: the real world has its own 32 km soft field (tools/world/real_layout.py)
		_half = 16384.0 if real else HALF
		_soft_real = real
		_scar = []
		var a := Image.load_from_file(ProjectSettings.globalize_path("res://data/world/real/biome_soft_a.png" if real else SOFT_A))
		var b := Image.load_from_file(ProjectSettings.globalize_path("res://data/world/real/biome_soft_b.png" if real else SOFT_B))
		if a != null and b != null and a.get_size() == Vector2i(SOFT_N, SOFT_N):
			a.convert(Image.FORMAT_RGBA8)
			b.convert(Image.FORMAT_RGBA8)
			var da := a.get_data()
			var db := b.get_data()
			_soft.resize(SOFT_N * SOFT_N * 8)
			for i in SOFT_N * SOFT_N:
				for c in 4:
					_soft[i * 8 + c] = da[i * 4 + c]
					_soft[i * 8 + 4 + c] = db[i * 4 + c]
		_warp = FastNoiseLite.new()
		_warp.seed = 1066
		_warp.frequency = 0.0035
		_soft_ok = true
	_soft_mutex.unlock()


## Smooth biome weights (8 floats summing ~1) at (x, z). All zero when the macro is not loaded.
static func soft_weights(x: float, z: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(8)
	if not active():
		return out
	if not _soft_ok or _soft_real != WorldMacro.is_real():
		_soft_ok = false
		_soft_load()
	if _soft.is_empty():
		var b := at(x, z)
		out[b] = 1.0
		return out
	var wx := x + _warp.get_noise_2d(x, z) * WARP_M
	var wz := z + _warp.get_noise_2d(x + 311.0, z - 177.0) * WARP_M
	var cell := _half * 2.0 / SOFT_N
	var u := clampf((wx + _half) / cell - 0.5, 0.0, SOFT_N - 1.001)
	var v := clampf((wz + _half) / cell - 0.5, 0.0, SOFT_N - 1.001)
	var iu := int(u)
	var iv := int(v)
	var fu := u - iu
	var fv := v - iv
	for c in 8:
		var p00 := float(_soft[(iv * SOFT_N + iu) * 8 + c])
		var p10 := float(_soft[(iv * SOFT_N + iu + 1) * 8 + c])
		var p01 := float(_soft[((iv + 1) * SOFT_N + iu) * 8 + c])
		var p11 := float(_soft[((iv + 1) * SOFT_N + iu + 1) * 8 + c])
		out[c] = lerpf(lerpf(p00, p10, fu), lerpf(p01, p11, fu), fv) / 255.0
	return out


## Ground slot weights for the Terrain3D control map: [forest litter, meadow, farmland, marsh, rift, snow, highland] (grass = the rest).
## `patch` 0..1 is a low-frequency noise value that breaks the mixes into soft patches.
static func ground_mix(sw: PackedFloat32Array, patch: float) -> PackedFloat32Array:
	var m := PackedFloat32Array()
	m.resize(7)
	var vary := 0.7 + 0.6 * patch
	m[0] = sw[FOREST] * MIX_FOREST * vary
	m[1] = sw[MEADOW] * 0.8 + sw[GRASS] * 0.15 + sw[FARMLAND] * 0.35 + sw[HIGHLAND] * 0.1 + sw[FOREST] * 0.0
	m[2] = sw[FARMLAND] * MIX_FARM * smoothstep(0.35, 0.7, patch) * 1.6
	m[3] = sw[MARSH] * MIX_MARSH
	m[4] = sw[RIFT] * MIX_RIFT
	m[5] = sw[SNOW] * MIX_SNOW
	m[6] = sw[HIGHLAND] * MIX_HIGH * vary
	return m


static func tint(sw: PackedFloat32Array) -> Color:
	var c := Color(0, 0, 0, 0)
	var t := 0.0
	for i in 8:
		c += (TINT[i] as Color) * sw[i]
		t += sw[i]
	return (c / t) if t > 0.001 else Color(1, 1, 1, 1)
