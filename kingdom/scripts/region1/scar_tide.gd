extends Region1Sim
## Mechanic N2, the Scar Tide (package L9, written with C4): Rift corruption that spreads over a
## 32 m grid covering the whole 12 x 12 km map, cell by cell, on a daily clock.
##
##   * Spread: every day each cell on the front may infect one 4-neighbour. The chance follows the
##     season (summer fastest, winter asleep: the containment window) and is cut by Wardlines
##     coverage: a cell covered at or above `block_cov` (a glowing stone) is NEVER entered, weaker
##     coverage slows the tide proportionally. Water stops it. Burned cells are immune for a while.
##   * Fire: `burn(pos, radius, power)` scorches cells clean (they come back only after
##     `immune_days`). `harvest(pos, radius)` cuts scar crystals and scarbloom.
##   * Mutation: `variant_for(species, pos)` (hook H4, monster_ecology.variant_for) turns wolves on
##     infected cells into their rift variant.
##   * Output: `mask_image()` is an R8 image, 1 texel per cell, sampled by the terrain shader as the
##     global `scar_mask` (hook H5). `extent()` is the infected cell count (economy price input).
##
## Pure sim: no scene tree. Wardlines coverage, water and the calendar arrive as Callables
## (`coverage`, `blocked`, `season_cb`) that the game glue sets; without them the tide is unhindered.
## Tuning and mutation tables: data/region1/scar_tide.json. Tick cost is proportional to the front
## (a few hundred cells at most), far under 2 ms.

const N := 384                 # 12288 m / 32 m (256 for the 8 km world; saves resample, see restore)
const CELL := 32.0
const HALF := 6144.0
const DATA_PATH := "res://data/region1/scar_tide.json"
const SAVE_STATE_VERSION := 1
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const F_CRYSTAL := 1
const F_BLOOM := 2

var cfg: Dictionary = {}
var cells := PackedByteArray()        ## intensity 0..255 (0 = clean)
var flags := PackedByteArray()        ## F_CRYSTAL | F_BLOOM
var immune: Dictionary = {}           ## cell index -> sim day until which it cannot be infected
var outbreaks: Dictionary = {}        ## name -> [x, z] seeded by the story or the seasons
var contained_total := 0
var harvested_crystals := 0
var harvested_bloom := 0
var infected := 0
## Callable(Vector2) -> float 0..1, Wardlines.coverage_at. Unset = no wards.
var coverage: Callable = Callable()
## Callable(Vector2) -> bool, true = the tide cannot enter (water, town squares).
var blocked: Callable = Callable()
## Callable() -> int 0..3 (spring..winter). Unset = derived from `start_day + day_f`.
var season_cb: Callable = Callable()
var start_day := 0
var ward_pressed: Array[Vector2] = []  ## where the front pushed on a glowing stone today

var _front: Dictionary = {}           ## infected cells that may still spread (index -> true)
var _growing: Dictionary = {}         ## cells still rising to full intensity
var _last_day := 0
var _mask_dirty := true
var _mask: Image


func _init() -> void:
	module_name = &"scar_tide"
	state_version = SAVE_STATE_VERSION


func _setup() -> void:
	cfg = _read_cfg()
	cells.resize(N * N)
	cells.fill(0)
	flags.resize(N * N)
	flags.fill(0)
	immune.clear()
	outbreaks.clear()
	_front.clear()
	_growing.clear()
	contained_total = 0
	harvested_crystals = 0
	harvested_bloom = 0
	infected = 0
	_last_day = 0
	_mask_dirty = true
	ward_pressed.clear()
	# The Ashen Scar itself is the first seed; the story adds outbreaks near Greenhollow and Greyseam.
	var o: Array = cfg.get("origin", [1380.0, 980.0])
	seed_at(Vector2(float(o[0]), float(o[1])), float(cfg.get("initial_radius_cells", 2.5)), "ashen_scar")


static func _read_cfg() -> Dictionary:
	if FileAccess.file_exists(DATA_PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if d is Dictionary:
			return d
	return {}


func _c(key: String, fallback: float) -> float:
	return float(cfg.get(key, fallback))


# --- grid -----------------------------------------------------------------------------

static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x + HALF) / CELL), floori((p.y + HALF) / CELL))


static func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL - HALF, (c.y + 0.5) * CELL - HALF)


static func index_of(c: Vector2i) -> int:
	return c.y * N + c.x


static func in_grid(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < N and c.y < N


func intensity_at(p: Vector2) -> float:
	var c := cell_of(p)
	return float(cells[index_of(c)]) / 255.0 if in_grid(c) else 0.0


func is_infected(p: Vector2) -> bool:
	return intensity_at(p) >= 0.3


func extent() -> int:
	return infected


## Infected cells whose centre lies within `radius` metres of `pos`.
func count_near(pos: Vector2, radius: float) -> int:
	var n := 0
	for c in _cells_in(pos, radius):
		if cells[index_of(c)] >= 100:
			n += 1
	return n


func _cells_in(pos: Vector2, radius: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo := cell_of(pos - Vector2(radius, radius))
	var hi := cell_of(pos + Vector2(radius, radius))
	for y in range(maxi(lo.y, 0), mini(hi.y, N - 1) + 1):
		for x in range(maxi(lo.x, 0), mini(hi.x, N - 1) + 1):
			var c := Vector2i(x, y)
			if cell_center(c).distance_to(pos) <= radius + CELL * 0.5:
				out.append(c)
	return out


## Nearest infected front cell centre within `max_dist` of `pos`, or Vector2.INF.
func nearest_front(pos: Vector2, max_dist: float) -> Vector2:
	var best := Vector2.INF
	var best_d := max_dist
	for c in _cells_in(pos, max_dist):
		var i := index_of(c)
		if cells[i] >= 60 and _front.has(i):
			var d := cell_center(c).distance_to(pos)
			if d < best_d:
				best_d = d
				best = cell_center(c)
	return best


## Centres of the front cells (for the map overlay and the compass hints). Capped.
func front_points(limit := 400) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i: int in _front:
		out.append(cell_center(Vector2i(i % N, i / N)))
		if out.size() >= limit:
			break
	return out


# --- seeding --------------------------------------------------------------------------

## Infect a disc of cells (an outbreak). Returns the number of newly infected cells.
func seed_at(pos: Vector2, radius_cells: float, outbreak_name := "") -> int:
	if outbreak_name != "":
		outbreaks[outbreak_name] = [pos.x, pos.y]
	var made := 0
	var r := radius_cells * CELL
	for c in _cells_in(pos, r):
		if cell_center(c).distance_to(pos) > r:
			continue
		if _infect(index_of(c), 200):
			made += 1
	_mask_dirty = true
	if made > 0:
		emit_event(&"outbreak", {"name": outbreak_name, "cells": made, "x": pos.x, "y": pos.y,
			"rumour": "The Scar has broken out near %s." % outbreak_name.replace("_", " ")})
	return made


func _infect(i: int, start: int) -> bool:
	if cells[i] > 0:
		return false
	cells[i] = start
	infected += 1
	_front[i] = true
	if start < 255:
		_growing[i] = true
	var dice := _dice(0, i, 9)
	var f := 0
	if dice < _c("crystal_chance", 0.12):
		f |= F_CRYSTAL
	elif dice > 1.0 - _c("bloom_chance", 0.1):
		f |= F_BLOOM
	flags[i] = f
	return true


func _dice(day: int, idx: int, salt: int) -> float:
	return float(hash([seed_value, day, idx, salt]) & 0xFFFFFF) / 16777216.0


# --- simulation -----------------------------------------------------------------------

func season() -> int:
	if season_cb.is_valid():
		return clampi(int(season_cb.call()), 0, 3)
	return posmod(floori((start_day + day_f) / 28.0), 4)


func season_spread_mult() -> float:
	var m: Array = cfg.get("season_spread", [0.8, 1.5, 1.0, 0.0])
	return float(m[season()])


func _step(dt: float) -> void:
	# Fresh cells darken to full strength over a few days.
	var rise := _c("rise_per_day", 55.0) * dt
	for i: int in _growing.keys():
		var v := mini(255, int(cells[i]) + int(ceil(rise)))
		cells[i] = v
		if v >= 255:
			_growing.erase(i)
		_mask_dirty = true
	while _last_day < floori(day_f):
		_last_day += 1
		_daily(_last_day)


func _daily(day: int) -> void:
	ward_pressed.clear()
	# Expired immunity.
	for i: int in immune.keys():
		if float(immune[i]) <= day_f:
			immune.erase(i)
	if day_f < _c("spread_after_day", 20.0):
		return
	var mult := season_spread_mult()
	if mult <= 0.0:
		return
	var base := _c("base_spread", 0.35) * mult
	var block_cov := _c("block_cov", 0.72)
	var new_cells: Array[int] = []
	var dead_front: Array[int] = []
	for i: int in _front:
		var c := Vector2i(i % N, i / N)
		var open_neighbours := 0
		for d in 4:
			var nc: Vector2i = c + DIRS[d]
			if not in_grid(nc):
				continue
			var ni := index_of(nc)
			if cells[ni] > 0:
				continue
			var centre := cell_center(nc)
			if immune.has(ni) or (blocked.is_valid() and bool(blocked.call(centre))):
				continue
			open_neighbours += 1
			var cov := float(coverage.call(centre)) if coverage.is_valid() else 0.0
			if cov >= block_cov:
				if ward_pressed.size() < 6:
					ward_pressed.append(centre)
				continue          # the tide never crosses a glowing stone
			var p := base * (1.0 - cov / block_cov)
			if _dice(day, i, d) < p:
				new_cells.append(ni)
		if open_neighbours == 0:
			dead_front.append(i)
	for i in dead_front:
		_front.erase(i)
	var made := 0
	for ni in new_cells:
		if _infect(ni, int(_c("start_intensity", 40.0))):
			made += 1
	if made > 0:
		_mask_dirty = true
		emit_event(&"spread", {"cells": made, "total": infected})
	if not ward_pressed.is_empty():
		var pts: Array = []
		for p in ward_pressed:
			pts.append([p.x, p.y])
		emit_event(&"ward_pressure", {"points": pts})


# --- player actions -------------------------------------------------------------------

## Burn the Scar back: every infected cell within `radius` loses `power` x 255 intensity
## (full power scorches it clean and immune for `immune_days`). Returns the cells cleared.
func burn(pos: Vector2, radius: float, power := 1.0) -> int:
	var cleared := 0
	var r := maxf(radius, CELL * 0.6)
	for c in _cells_in(pos, r):
		var i := index_of(c)
		if cells[i] == 0:
			continue
		var d := cell_center(c).distance_to(pos)
		var fall := 1.0 - clampf((d - r * 0.5) / maxf(r * 0.8, 1.0), 0.0, 0.85)
		var v := int(cells[i]) - int(round(power * 255.0 * fall))
		if v <= 0:
			_clear_cell(i)
			cleared += 1
		else:
			cells[i] = v
	if cleared > 0 or power > 0.0:
		_mask_dirty = true
	if cleared > 0:
		contained_total += cleared
		emit_event(&"contained", {"cells": cleared, "x": pos.x, "y": pos.y, "total": contained_total,
			"rumour": "Fire has driven the Scar back."})
	return cleared


func _clear_cell(i: int) -> void:
	if cells[i] > 0:
		infected = maxi(0, infected - 1)
	cells[i] = 0
	flags[i] = 0
	_front.erase(i)
	_growing.erase(i)
	immune[i] = day_f + _c("immune_days", 6.0)
	# Its infected neighbours are front again (they may try to retake it after the immunity).
	var c := Vector2i(i % N, i / N)
	for d in 4:
		var nc: Vector2i = c + DIRS[d]
		if in_grid(nc) and cells[index_of(nc)] > 0:
			_front[index_of(nc)] = true


## Cut crystals and scarbloom from the cells around `pos`. Returns {"crystals": n, "bloom": m}.
func harvest(pos: Vector2, radius: float) -> Dictionary:
	var crystals := 0
	var bloom := 0
	for c in _cells_in(pos, radius):
		var i := index_of(c)
		if cells[i] < 120:
			continue
		var f := int(flags[i])
		if f & F_CRYSTAL:
			crystals += 1
			flags[i] = f & ~F_CRYSTAL
			cells[i] = maxi(60, int(cells[i]) - 30)
		elif f & F_BLOOM:
			bloom += 1
			flags[i] = f & ~F_BLOOM
	if crystals + bloom > 0:
		harvested_crystals += crystals
		harvested_bloom += bloom
		_mask_dirty = true
		emit_event(&"harvested", {"crystals": crystals, "bloom": bloom, "x": pos.x, "y": pos.y})
	return {"crystals": crystals, "bloom": bloom}


## Price input for economy.scar_price_mult: a big Scar floods the market, a burned-back one makes the goods dear.
func price_mult() -> float:
	var cap := _c("price_full_cells", 500.0)
	return lerpf(float(cfg.get("price_scarce", 1.9)), float(cfg.get("price_flood", 0.55)), clampf(float(infected) / cap, 0.0, 1.0))


# --- mutation (hook H4) ---------------------------------------------------------------

## Callable for RAMonsterEcology.variant_override: wolves standing in the Scar become rift wolves.
func variant_for(species: String, pos: Vector2) -> String:
	var mut: Dictionary = cfg.get("mutations", {"wolf": "corrupted_wolf"})
	if mut.has(species) and intensity_at(pos) >= _c("mutate_threshold", 0.35):
		return String(mut[species])
	return species


# --- output ---------------------------------------------------------------------------

func mask_dirty() -> bool:
	return _mask_dirty


## R8 image (N x N) for the terrain's `scar_mask` global. Cheap: one byte copy.
func mask_image() -> Image:
	if _mask == null or _mask_dirty:
		_mask = Image.create_from_data(N, N, false, Image.FORMAT_R8, cells)
		_mask_dirty = false
	return _mask


# --- persistence ----------------------------------------------------------------------

func _save_state() -> Dictionary:
	var flat: Array = []
	var fl: Array = []
	for i in N * N:
		if cells[i] > 0:
			flat.append(i)
			flat.append(int(cells[i]))
			if flags[i] != 0:
				fl.append(i)
				fl.append(int(flags[i]))
	var imm: Array = []
	for i: int in immune:
		imm.append(i)
		imm.append(snappedf(float(immune[i]), 1e-6))
	return {"cells": flat, "flags": fl, "immune": imm, "outbreaks": outbreaks.duplicate(true),
		"contained": contained_total, "crystals": harvested_crystals, "bloom": harvested_bloom,
		"last_day": _last_day, "start_day": start_day}


func _load_state(d: Dictionary) -> void:
	cfg = _read_cfg()
	cells.resize(N * N)
	cells.fill(0)
	flags.resize(N * N)
	flags.fill(0)
	_front.clear()
	_growing.clear()
	immune.clear()
	infected = 0
	var flat: Array = d.get("cells", [])
	var k := 0
	while k + 1 < flat.size():
		var i := int(flat[k])
		cells[i] = int(flat[k + 1])
		infected += 1
		_front[i] = true
		if cells[i] < 255:
			_growing[i] = true
		k += 2
	var fl: Array = d.get("flags", [])
	k = 0
	while k + 1 < fl.size():
		flags[int(fl[k])] = int(fl[k + 1])
		k += 2
	var imm: Array = d.get("immune", [])
	k = 0
	while k + 1 < imm.size():
		immune[int(imm[k])] = float(imm[k + 1])
		k += 2
	outbreaks = (d.get("outbreaks", {}) as Dictionary).duplicate(true)
	contained_total = int(d.get("contained", 0))
	harvested_crystals = int(d.get("crystals", 0))
	harvested_bloom = int(d.get("bloom", 0))
	_last_day = int(d.get("last_day", floori(day_f)))
	start_day = int(d.get("start_day", 0))
	_mask_dirty = true


func summary() -> String:
	return "scar_tide day=%.1f infected=%d front=%d contained=%d harvested=%d/%d" % [day_f, infected, _front.size(),
		contained_total, harvested_crystals, harvested_bloom]


func debug_image(px: int = 256) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	img.fill(Color(0.12, 0.16, 0.1))
	var s := float(px) / float(N)
	for i in N * N:
		if cells[i] > 0:
			var v := float(cells[i]) / 255.0
			var col := Color(0.35 + 0.4 * v, 0.1, 0.55 + 0.3 * v)
			var x0 := int((i % N) * s)
			var y0 := int((i / N) * s)
			for yy in maxi(1, int(ceil(s))):
				for xx in maxi(1, int(ceil(s))):
					if x0 + xx < px and y0 + yy < px:
						img.set_pixel(x0 + xx, y0 + yy, col)
	return img
