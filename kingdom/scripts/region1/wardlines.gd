class_name Wardlines
extends Region1Sim
## Wardlines (N1 "Wardwright"): the runestone network as a living power grid.
##
## THE RULES (all numbers in data/region1/wardlines.json)
##   1. Five Elder Stones each hold a power BUDGET per day. Nothing else makes power.
##   2. Every runestone needs some power a day to stay lit (ring stones more than road stones).
##   3. Power travels along WARDLINES (links between stones). Each hop wastes 4 percent, so
##      far stones are expensive. Stones are served nearest-first (pinned stones first); when
##      an Elder runs dry the far end of its network fades. That is the whole puzzle.
##   4. A stone follows its feed slowly (days, not seconds): cut a road and it fades over
##      about three days, mend it and it relights.
##   5. Stones also WEAR (condition). Runeward crews repair a few a day, never enough.
##   6. The player can carve one glyph per stone (ward, lure, alarm, bless), drag new links
##      (bounded by length and 4 links per stone), cut links, pin a stone, repair a stone.
##   7. Protection at a point = the strongest stone bubble there (charge x condition x glyph),
##      fading like RARunestoneNetwork.coverage. `coverage_callable()` is hook H3.
##
## Conservation (tested): per Elder, power drawn <= budget; drawn = delivered + lost in
## transit. See `budget_report()`.
##
## Layout: `bind_network(RARunestoneNetwork)` in the game (stone id = network id), or the
## seeded synthetic Valencious layout from wardlines.json (sandbox, tests, no-network mode).
## Pure: no scene tree, no autoloads, no randf (stateless hashed dice, so the same day always
## rolls the same whatever the tick size).

const DATA_PATH := "res://data/region1/wardlines.json"
const SAVE_STATE_VERSION := 1
const GLYPH_NAMES: PackedStringArray = ["none", "ward", "lure", "alarm", "bless"]
const G_NONE := 0
const G_WARD := 1
const G_LURE := 2
const G_ALARM := 3
const G_BLESS := 4
const BAND_DARK := 0
const BAND_CRACKED := 1
const BAND_DIM := 2
const BAND_GLOWING := 3
const BAND_NAMES: PackedStringArray = ["dark", "cracked", "dim", "glowing"]
const COMPASS: PackedStringArray = ["North", "Northeast", "Southeast", "South", "Southwest", "Northwest"]
const EPS := 1e-6

## Built-in fallbacks: the JSON overrides any of these keys (deep merge).
const DEFAULT_CFG := {
	"elder": {"slack": 1.25, "capacity": [], "radius": 240.0, "recovery_per_day": 0.08, "carve_cost": 0.02},
	"demand": {"ring": 1.5, "road": 1.0},
	"links": {"hop_loss": 0.04, "player_loss_mult": 1.5, "max_len": 700.0, "max_degree": 4,
		"auto_range": 320.0, "merge_range": 900.0},
	"charge": {"rise_per_day": 0.35, "fall_per_day": 0.2, "carve_min": 0.25},
	"wear": {"decay_per_day": 0.003, "neglect_after_days": 30.0, "neglect_mult": 1.5, "repair_amount": 0.25,
		"carve_repair": 0.15, "failure_chance_per_day": 0.004, "failure_min": 0.25, "failure_max": 0.55},
	"crew": {"repairs_per_stone_day": 0.012, "min_fed": 0.5, "repair_below": 0.9},
	"bands": {"glowing": 0.75, "dim": 0.45, "cracked": 0.15},
	"glyphs": {
		"none": {"demand": 1.0, "radius": 1.0, "strength": 1.0},
		"ward": {"demand": 1.4, "radius": 1.3, "strength": 1.0},
		"lure": {"demand": 0.3, "radius": 1.0, "strength": 0.0, "lure_radius": 160.0},
		"alarm": {"demand": 1.1, "radius": 1.0, "strength": 0.85, "cooldown_days": 0.25, "listen_radius": 420.0},
		"bless": {"demand": 1.2, "radius": 1.1, "strength": 0.6, "yield_bonus": 0.25},
	},
}

var cfg: Dictionary = {}
## "synthetic" (seeded layout from the JSON), "network" (bound to a RARunestoneNetwork) or "custom".
var layout_source := "synthetic"

# --- static layout (saved) ---
var n := 0
var st_pos := PackedVector2Array()
var st_radius := PackedFloat64Array()
var st_name := PackedStringArray()
var st_road := PackedStringArray()       # road key ("" = village ring or hub stone)
var st_road_name := PackedStringArray()  # display name of the road ("Oakvale")
var st_owner := PackedInt32Array()
var elder_ids := PackedInt32Array()      # stone ids of the Elder Stones
var links: Array[Dictionary] = []        # {a, b, len, kind: "auto"|"player", cut: bool}

# --- dynamic state (saved) ---
var charge := PackedFloat64Array()       # 0..1, follows `fed`
var condition := PackedFloat64Array()    # 0..1 wear
var glyph := PackedInt32Array()          # G_*
var pinned := PackedByteArray()
var last_repair := PackedFloat64Array()  # day_f of the last repair
var alarm_last := PackedFloat64Array()   # day_f of the last alarm this stone raised
var elder_power := PackedFloat64Array()  # 0..1 per elder
var elder_capacity := PackedFloat64Array()
var crew_bank := 0.0
var _last_day := 0

# --- derived (rebuilt, not saved) ---
var fed := PackedFloat64Array()          # delivered / demand this allocation, 0..1
var strength := PackedFloat64Array()     # charge x condition x glyph strength
var band := PackedByteArray()
var supplier := PackedInt32Array()       # elder index feeding each stone, -1 = none
var elder_drawn := PackedFloat64Array()
var elder_of := PackedInt32Array()       # stone id -> elder index or -1
var _adj: Array = []                     # per stone: PackedInt32Array of link indices
var _dist: Array = []                    # per elder: PackedFloat64Array of path length
var _eff: Array = []                     # per elder: PackedFloat64Array of path efficiency
var _par: Array = []                     # per elder: PackedInt32Array of the link each stone is reached by
var _draw_of := PackedFloat64Array()     # power drawn from the Elder for each stone in the last allocation
var _cands: Array = []                   # per stone: PackedInt32Array of elder indices, nearest first
var _order := PackedInt32Array()         # stones in service order
var _rad := PackedFloat64Array()         # effective bubble radius
var _grid: Dictionary = {}
var _cell := 240.0
var _routes_dirty := true
var _alloc_dirty := true
var _road_failing: Dictionary = {}       # road key -> failing stone count
var _strained := PackedByteArray()       # per elder
var _roads: Dictionary = {}              # road key -> PackedInt32Array of stone ids in order
var _bounds := Rect2()
var _report := {}
var _glyph_p: Array = []                 # per G_*: glyph parameter Dictionary
var _hk := PackedFloat64Array()
var _hv := PackedInt32Array()


func _init() -> void:
	module_name = &"wardlines"
	state_version = SAVE_STATE_VERSION


# ============================================================================ setup

func _setup() -> void:
	load_config()
	_clear_layout()
	_generate_synthetic()


## Load tuning: built-in defaults, then wardlines.json on top.
func load_config(path: String = DATA_PATH) -> void:
	var c: Dictionary = DEFAULT_CFG.duplicate(true)
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			c = _merge(c, parsed)
	configure(c)


## Replace the tuning dictionary (tests use this to make small worlds).
func configure(c: Dictionary) -> void:
	cfg = c
	_glyph_p.clear()
	for g in GLYPH_NAMES:
		_glyph_p.append(_cd("glyphs", g, {}))
	_alloc_dirty = true


func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	for k in b:
		if a.has(k) and typeof(a[k]) == TYPE_DICTIONARY and typeof(b[k]) == TYPE_DICTIONARY:
			a[k] = _merge(a[k], b[k])
		else:
			a[k] = b[k]
	return a


func _cd(section: String, key: String, fallback: Variant) -> Variant:
	var s: Variant = cfg.get(section, {})
	return s.get(key, fallback) if typeof(s) == TYPE_DICTIONARY else fallback


func _cf(section: String, key: String) -> float:
	return float(_cd(section, key, 0.0))


func _clear_layout() -> void:
	n = 0
	st_pos = PackedVector2Array()
	st_radius = PackedFloat64Array()
	st_name = PackedStringArray()
	st_road = PackedStringArray()
	st_road_name = PackedStringArray()
	st_owner = PackedInt32Array()
	elder_ids = PackedInt32Array()
	links = []
	charge = PackedFloat64Array()
	condition = PackedFloat64Array()
	glyph = PackedInt32Array()
	pinned = PackedByteArray()
	last_repair = PackedFloat64Array()
	alarm_last = PackedFloat64Array()
	elder_power = PackedFloat64Array()
	elder_capacity = PackedFloat64Array()
	crew_bank = 0.0
	_last_day = 0
	_road_failing.clear()


## Use your own stones. Each entry: {pos: Vector2, radius, name, road: "" or road key,
## road_name, owner}. `links_in` are [a, b] pairs; empty = auto links (roads chained, rings
## joined, components merged). Elders get capacity from `elder.slack`.
func set_layout(stones: Array, elders: PackedInt32Array, links_in: Array = [], source := "custom") -> void:
	_clear_layout()
	layout_source = source
	for s: Dictionary in stones:
		st_pos.append(s["pos"])
		st_radius.append(float(s.get("radius", 110.0)))
		st_name.append(String(s.get("name", "Runestone %d" % (st_pos.size()))))
		st_road.append(String(s.get("road", "")))
		st_road_name.append(String(s.get("road_name", "")))
		st_owner.append(int(s.get("owner", -1)))
	n = st_pos.size()
	elder_ids = elders
	if links_in.is_empty():
		_auto_links()
	else:
		for l: Array in links_in:
			_add_link_raw(int(l[0]), int(l[1]), "auto")
	_init_dynamic()
	_finalize_layout()


## Copy a RARunestoneNetwork (stone id = index). `elders` empty = pick 5 spread-out stones.
func bind_network(net: RARunestoneNetwork, elders: PackedInt32Array = PackedInt32Array()) -> void:
	var arr: Array = []
	for s: Dictionary in net.stones:
		var road_to := String(s.get("road_to", ""))
		var owner := int(s.get("owner", -1))
		arr.append({"pos": s["pos"], "radius": float(s["radius"]), "name": String(s["name"]),
			"road": ("%d>%s" % [owner, road_to]) if bool(s.get("road", false)) and road_to != "" else "",
			"road_name": road_to, "owner": owner})
	if elders.is_empty():
		elders = _pick_elders(arr, 5)
	set_layout(arr, elders, [], "network")
	# adopt the network's current wear
	for i in n:
		var s: Dictionary = net.stones[i]
		condition[i] = float(s["condition"])
		charge[i] = clampf(float(s["power"]), 0.0, 1.0)
	_alloc_dirty = true
	_allocate()
	_refresh_all()
	_snap_bands()


## Write charge and condition back so the old network's own rumours and failing events agree.
func push_to_network(net: RARunestoneNetwork) -> void:
	for i in mini(n, net.stones.size()):
		net.stones[i]["power"] = charge[i]
		net.stones[i]["condition"] = condition[i]


## Farthest-point sampling: first the stone with the lowest id, then repeatedly the stone
## farthest from those chosen. Deterministic, spreads the hubs over the map.
func _pick_elders(arr: Array, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if arr.is_empty():
		return out
	out.append(0)
	while out.size() < mini(count, arr.size()):
		var best := -1
		var best_d := -1.0
		for i in arr.size():
			var d := INF
			for e in out:
				d = minf(d, (arr[i]["pos"] as Vector2).distance_squared_to(arr[e]["pos"]))
			if d > best_d:
				best_d = d
				best = i
		out.append(best)
	return out


func _generate_synthetic() -> void:
	layout_source = "synthetic"
	var lay: Dictionary = cfg.get("layout", {})
	var hubs: Array = lay.get("hubs", [])
	if hubs.is_empty():
		_finalize_layout()
		return
	var spacing: Dictionary = lay.get("spacing", {"kingdom": 180.0, "rural": 195.0, "frontier": 420.0})
	var road_r := float(lay.get("road_stone_radius", 110.0))
	var ring_mult := float(lay.get("ring_stone_radius_mult", 1.45))
	var stones: Array = []
	var elders := PackedInt32Array()
	var hub_index := {}
	var ring_first := {}
	for hi in hubs.size():
		var h: Dictionary = hubs[hi]
		hub_index[String(h["name"])] = hi
		var c := Vector2(float(h["x"]), float(h["y"]))
		var r := float(h["r"])
		if bool(h.get("elder", false)):
			elders.append(stones.size())
			stones.append({"pos": c, "radius": _cf("elder", "radius"), "name": "%s Elder Stone" % h["name"],
				"owner": hi})
		var rn := int(h.get("ring", 4))
		var a0 := rng.randf() * TAU
		ring_first[hi] = stones.size()
		for k in rn:
			var ang := a0 + TAU * k / float(rn) + rng.randf_range(-0.12, 0.12)
			var nm := "%s %s Stone" % [h["name"], COMPASS[k % 6]]
			stones.append({"pos": c + Vector2(cos(ang), sin(ang)) * (r + 18.0 + rng.randf_range(-4.0, 4.0)),
				"radius": r * ring_mult, "name": nm, "owner": hi})
	for road: Dictionary in lay.get("roads", []):
		var ai: int = hub_index[String(road["a"])]
		var bi: int = hub_index[String(road["b"])]
		var a := Vector2(float(hubs[ai]["x"]), float(hubs[ai]["y"]))
		var b := Vector2(float(hubs[bi]["x"]), float(hubs[bi]["y"]))
		var tier := String(road.get("tier", "rural"))
		var sp := float(spacing.get(tier, 195.0))
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var perp := Vector2(-dir.y, dir.x)
		var ra := float(hubs[ai]["r"]) * 1.8
		var rb := float(hubs[bi]["r"]) * 1.8
		var to_name := String(hubs[bi]["name"])
		var key := "%d>%s" % [ai, to_name]
		var t := ra + sp * 0.5
		var k := 1
		while t < length - rb:
			stones.append({"pos": a + dir * t + perp * rng.randf_range(-6.0, 6.0), "radius": road_r,
				"name": "%s Road Stone %d" % [to_name, k], "road": key, "road_name": to_name, "owner": ai})
			k += 1
			t += sp * rng.randf_range(0.94, 1.06)
	set_layout(stones, elders, [], "synthetic")


# ============================================================================ links

func _add_link_raw(a: int, b: int, kind: String) -> int:
	if a == b or a < 0 or b < 0 or a >= n or b >= n:
		return -1
	var li := _find_link(a, b)
	if li >= 0:
		return li
	links.append({"a": mini(a, b), "b": maxi(a, b), "len": st_pos[a].distance_to(st_pos[b]),
		"kind": kind, "cut": false})
	return links.size() - 1


func _find_link(a: int, b: int) -> int:
	var lo := mini(a, b)
	var hi := maxi(a, b)
	for i in links.size():
		if links[i]["a"] == lo and links[i]["b"] == hi:
			return i
	return -1


func _rebuild_adj() -> void:
	_adj.clear()
	_adj.resize(n)
	for i in n:
		_adj[i] = PackedInt32Array()
	for li in links.size():
		var l: Dictionary = links[li]
		if bool(l["cut"]):
			continue
		_push(_adj, l["a"], li)
		_push(_adj, l["b"], li)


func degree(id: int) -> int:
	var d := 0
	for l in links:
		if not bool(l["cut"]) and (l["a"] == id or l["b"] == id):
			d += 1
	return d


## Live links of a stone: [{other, kind, len, index}]
func links_of(id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for li in links.size():
		var l: Dictionary = links[li]
		if bool(l["cut"]) or (l["a"] != id and l["b"] != id):
			continue
		out.append({"other": l["b"] if l["a"] == id else l["a"], "kind": l["kind"], "len": l["len"], "index": li})
	return out


## Roads chained in id order, rings joined to their nearest neighbours, ends joined to the
## nearest hub stone, isolated pieces merged into one graph.
func _auto_links() -> void:
	links = []
	var by_road: Dictionary = {}
	for i in n:
		if st_road[i] != "":
			if not by_road.has(st_road[i]):
				by_road[st_road[i]] = PackedInt32Array()
			_push(by_road, st_road[i], i)
	# rings: every non-road stone links to its 2 nearest same-owner non-road stones
	for i in n:
		if st_road[i] != "":
			continue
		var near: Array = []
		for j in n:
			if j != i and st_road[j] == "" and st_owner[j] == st_owner[i]:
				near.append([st_pos[i].distance_squared_to(st_pos[j]), j])
		near.sort()
		for k in mini(2, near.size()):
			_add_link_raw(i, near[k][1], "auto")
	# roads: chain, then join both ends to the nearest non-road stone
	for key: String in by_road:
		var ids: PackedInt32Array = by_road[key]
		for k in range(1, ids.size()):
			_add_link_raw(ids[k - 1], ids[k], "auto")
		var first := ids[0]
		var last := ids[ids.size() - 1]
		var from_hub := _nearest_hub_stone(st_pos[first], st_owner[first], true)
		if from_hub >= 0:
			_add_link_raw(first, from_hub, "auto")
		var to_hub := _nearest_hub_stone(st_pos[last], -1, false)
		if to_hub >= 0 and st_pos[last].distance_to(st_pos[to_hub]) <= _cf("links", "merge_range"):
			_add_link_raw(last, to_hub, "auto")
	_merge_components()


func _nearest_hub_stone(p: Vector2, owner: int, need_owner: bool) -> int:
	var best := -1
	var best_d := INF
	for j in n:
		if st_road[j] != "":
			continue
		if need_owner and st_owner[j] != owner:
			continue
		var d := p.distance_squared_to(st_pos[j])
		if d < best_d:
			best_d = d
			best = j
	return best


func _components() -> PackedInt32Array:
	var comp := PackedInt32Array()
	comp.resize(n)
	comp.fill(-1)
	var nb: Array = []
	nb.resize(n)
	for i in n:
		nb[i] = PackedInt32Array()
	for l in links:
		_push(nb, l["a"], l["b"])
		_push(nb, l["b"], l["a"])
	var c := 0
	for i in n:
		if comp[i] >= 0:
			continue
		var stack := PackedInt32Array([i])
		comp[i] = c
		while not stack.is_empty():
			var u := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			for v in (nb[u] as PackedInt32Array):
				if comp[v] < 0:
					comp[v] = c
					stack.append(v)
		c += 1
	return comp


func _merge_components() -> void:
	var guard := 0
	while guard < 64:
		guard += 1
		var comp := _components()
		var cmax := -1
		for c in comp:
			cmax = maxi(cmax, c)
		if cmax <= 0:
			return
		# attach the smallest other component to its nearest outside stone
		var best_a := -1
		var best_b := -1
		var best_d := INF
		for i in n:
			if comp[i] == 0:
				continue
			for j in n:
				if comp[j] == comp[i]:
					continue
				var d := st_pos[i].distance_squared_to(st_pos[j])
				if d < best_d:
					best_d = d
					best_a = i
					best_b = j
		if best_a < 0 or sqrt(best_d) > _cf("links", "merge_range"):
			return
		_add_link_raw(best_a, best_b, "auto")


func _init_dynamic() -> void:
	charge = PackedFloat64Array()
	charge.resize(n)
	charge.fill(1.0)
	condition = charge.duplicate()
	glyph = PackedInt32Array()
	glyph.resize(n)
	pinned = PackedByteArray()
	pinned.resize(n)
	last_repair = PackedFloat64Array()
	last_repair.resize(n)
	alarm_last = PackedFloat64Array()
	alarm_last.resize(n)
	alarm_last.fill(-99.0)
	elder_power = PackedFloat64Array()
	elder_power.resize(elder_ids.size())
	elder_power.fill(1.0)


## Everything derived from the static layout and the links. Elder capacity is set here
## (nearest-Elder share x slack) unless the config fixes it.
func _finalize_layout() -> void:
	elder_of = PackedInt32Array()
	elder_of.resize(n)
	elder_of.fill(-1)
	for e in elder_ids.size():
		elder_of[elder_ids[e]] = e
	_build_grid()
	_build_roads()
	_rebuild_adj()
	_rebuild_routes()
	elder_capacity = PackedFloat64Array()
	elder_capacity.resize(elder_ids.size())
	var fixed: Array = _cd("elder", "capacity", [])
	var share := PackedFloat64Array()
	share.resize(elder_ids.size())
	for v in n:
		if elder_of[v] >= 0 or _cands[v].is_empty():
			continue
		var e: int = _cands[v][0]
		share[e] += _demand(v) / maxf(_eff[e][v], 0.05)
	var slack := _cf("elder", "slack")
	for e in elder_ids.size():
		elder_capacity[e] = float(fixed[e]) if e < fixed.size() else share[e] * slack
	_strained = PackedByteArray()
	_strained.resize(elder_ids.size())
	fed = PackedFloat64Array()
	fed.resize(n)
	strength = PackedFloat64Array()
	strength.resize(n)
	_rad = PackedFloat64Array()
	_rad.resize(n)
	band = PackedByteArray()
	band.resize(n)
	supplier = PackedInt32Array()
	supplier.resize(n)
	supplier.fill(-1)
	elder_drawn = PackedFloat64Array()
	elder_drawn.resize(elder_ids.size())
	_allocate()
	for i in n:
		charge[i] = fed[i] if elder_of[i] < 0 else 1.0
	_refresh_all()
	_snap_bands()


func _build_grid() -> void:
	_grid.clear()
	if n == 0:
		_bounds = Rect2()
		return
	var max_r := 1.0
	var lo := st_pos[0]
	var hi := st_pos[0]
	for i in n:
		var gm := 1.0
		for g: Dictionary in _glyph_p:
			gm = maxf(gm, float(g.get("radius", 1.0)))
		max_r = maxf(max_r, st_radius[i] * gm)
		lo = Vector2(minf(lo.x, st_pos[i].x), minf(lo.y, st_pos[i].y))
		hi = Vector2(maxf(hi.x, st_pos[i].x), maxf(hi.y, st_pos[i].y))
	_cell = max_r
	_bounds = Rect2(lo, hi - lo).grow(max_r * 0.5)
	for i in n:
		var key := _cell_of(st_pos[i])
		if not _grid.has(key):
			_grid[key] = PackedInt32Array()
		_push(_grid, key, i)


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / _cell), floori(p.y / _cell))


func _build_roads() -> void:
	_roads.clear()
	for i in n:
		if st_road[i] == "":
			continue
		if not _roads.has(st_road[i]):
			_roads[st_road[i]] = PackedInt32Array()
		_push(_roads, st_road[i], i)


# ============================================================================ routing

func _heap_push(k: float, v: int) -> void:
	_hk.append(k)
	_hv.append(v)
	var i := _hk.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if _hk[p] <= _hk[i]:
			break
		var tk := _hk[p]
		_hk[p] = _hk[i]
		_hk[i] = tk
		var tv := _hv[p]
		_hv[p] = _hv[i]
		_hv[i] = tv
		i = p


func _heap_pop() -> int:
	var top := _hv[0]
	var last := _hk.size() - 1
	_hk[0] = _hk[last]
	_hv[0] = _hv[last]
	_hk.resize(last)
	_hv.resize(last)
	var i := 0
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var m := i
		if l < last and _hk[l] < _hk[m]:
			m = l
		if r < last and _hk[r] < _hk[m]:
			m = r
		if m == i:
			break
		var tk := _hk[m]
		_hk[m] = _hk[i]
		_hk[i] = tk
		var tv := _hv[m]
		_hv[m] = _hv[i]
		_hv[i] = tv
		i = m
	return top


## Shortest path (by length) from every Elder over live links; remembers each stone's
## path efficiency, its Elders nearest-first, and the service order.
func _rebuild_routes() -> void:
	if _adj.size() != n:
		_rebuild_adj()
	var loss := _cf("links", "hop_loss")
	var ploss := loss * _cf("links", "player_loss_mult")
	_dist = []
	_eff = []
	_par = []
	for e in elder_ids.size():
		var dist := PackedFloat64Array()
		dist.resize(n)
		dist.fill(INF)
		var eff := PackedFloat64Array()
		eff.resize(n)
		var par := PackedInt32Array()
		par.resize(n)
		par.fill(-1)
		var start := elder_ids[e]
		dist[start] = 0.0
		eff[start] = 1.0
		_hk.clear()
		_hv.clear()
		_heap_push(0.0, start)
		while not _hk.is_empty():
			var top_k := _hk[0]
			var u := _heap_pop()
			if top_k > dist[u]:
				continue
			for li in (_adj[u] as PackedInt32Array):
				var l: Dictionary = links[li]
				var v: int = l["b"] if l["a"] == u else l["a"]
				var nd: float = top_k + float(l["len"])
				if nd < dist[v] - EPS:
					dist[v] = nd
					eff[v] = eff[u] * (1.0 - (ploss if l["kind"] == "player" else loss))
					par[v] = li
					_heap_push(nd, v)
		_dist.append(dist)
		_eff.append(eff)
		_par.append(par)
	_cands = []
	_cands.resize(n)
	var min_d := PackedFloat64Array()
	min_d.resize(n)
	for v in n:
		var cs: Array = []
		for e in elder_ids.size():
			if _dist[e][v] < INF:
				cs.append([_dist[e][v], e])
		cs.sort()
		var pa := PackedInt32Array()
		for c in cs:
			pa.append(c[1])
		_cands[v] = pa
		min_d[v] = cs[0][0] if not cs.is_empty() else INF
	_build_order(min_d)
	_routes_dirty = false
	_alloc_dirty = true


func _build_order(min_d: PackedFloat64Array) -> void:
	var ids: Array = []
	for v in n:
		if elder_of[v] < 0:
			ids.append(v)
	# pinned first, then nearest to an Elder, then id
	ids.sort_custom(func(a: int, b: int) -> bool:
		if pinned[a] != pinned[b]:
			return pinned[a] > pinned[b]
		if not is_equal_approx(min_d[a], min_d[b]):
			return min_d[a] < min_d[b]
		return a < b)
	_order = PackedInt32Array(ids)


func _demand(v: int) -> float:
	if elder_of.size() > v and elder_of[v] >= 0:
		return 0.0
	var base := _cf("demand", "road") if st_road[v] != "" else _cf("demand", "ring")
	return base * float(_glyph_p[glyph[v]].get("demand", 1.0))


## Hand out each Elder's budget: stones in service order take from their nearest Elder that
## still has power (a dry Elder passes them to the next one). Delivered = drawn x path
## efficiency. Conserved: drawn = delivered + loss.
func _allocate() -> void:
	if _routes_dirty:
		_rebuild_routes()
	var ne := elder_ids.size()
	var remaining := PackedFloat64Array()
	remaining.resize(ne)
	for e in ne:
		remaining[e] = elder_capacity[e] * elder_power[e]
	elder_drawn.fill(0.0)
	var total_demand := 0.0
	var delivered_total := 0.0
	var starved := PackedByteArray()
	starved.resize(ne)
	fed.fill(0.0)
	supplier.fill(-1)
	_draw_of = PackedFloat64Array()
	_draw_of.resize(n)
	for i in ne:
		fed[elder_ids[i]] = 1.0
	for v in _order:
		var d := _demand(v)
		total_demand += d
		if d <= 0.0:
			fed[v] = 1.0
			continue
		for e: int in (_cands[v] as PackedInt32Array):
			if remaining[e] <= EPS:
				starved[e] = 1
				continue
			var eff: float = _eff[e][v]
			var cost := d / maxf(eff, 0.05)
			var draw := minf(cost, remaining[e])
			if draw < cost - EPS:
				starved[e] = 1
			remaining[e] -= draw
			elder_drawn[e] += draw
			_draw_of[v] = draw
			var got := draw * eff
			delivered_total += got
			fed[v] = clampf(got / d, 0.0, 1.0)
			supplier[v] = e
			break
	var supply := 0.0
	var drawn := 0.0
	for e in ne:
		supply += elder_capacity[e] * elder_power[e]
		drawn += elder_drawn[e]
	_report = {"supply": supply, "drawn": drawn, "delivered": delivered_total,
		"loss": drawn - delivered_total, "unspent": supply - drawn, "demand": total_demand,
		"unmet": maxf(0.0, total_demand - delivered_total)}
	for e in ne:
		_report["strained_%d" % e] = starved[e] == 1
	_starved = starved
	_alloc_dirty = false


var _starved := PackedByteArray()


## Power flowing through each live link, for the ward map layer: [{a, b, flow, kind, len}],
## biggest first. flow = power that enters the link (after the losses so far) summed over every
## stone fed through it, so the links next to an Elder are thick and the tips are thin.
func flow_edges() -> Array[Dictionary]:
	if _alloc_dirty:
		_allocate()
	var flow: Dictionary = {}
	for v in n:
		var e := supplier[v]
		if e < 0 or _draw_of[v] <= 0.0:
			continue
		var x := v
		var guard := 0
		while x != elder_ids[e] and guard < n:
			guard += 1
			var li: int = _par[e][x]
			if li < 0:
				break
			flow[li] = float(flow.get(li, 0.0)) + _draw_of[v] * float(_eff[e][x])
			var l: Dictionary = links[li]
			x = l["b"] if l["a"] == x else l["a"]
	var out: Array[Dictionary] = []
	for li: int in flow:
		var l: Dictionary = links[li]
		out.append({"a": l["a"], "b": l["b"], "flow": flow[li], "kind": l["kind"], "len": l["len"]})
	out.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return p["flow"] > q["flow"])
	return out


## Budget books. drawn = delivered + loss; drawn <= supply (Elder budget x power).
func budget_report() -> Dictionary:
	if _alloc_dirty:
		_allocate()
	return _report.duplicate()


## One row per Elder: {id, name, power, capacity, budget, drawn, load, stones}.
func elder_status() -> Array[Dictionary]:
	if _alloc_dirty:
		_allocate()
	var out: Array[Dictionary] = []
	for e in elder_ids.size():
		var count := 0
		for v in n:
			if supplier[v] == e:
				count += 1
		var budget := elder_capacity[e] * elder_power[e]
		out.append({"index": e, "id": elder_ids[e], "name": st_name[elder_ids[e]], "power": elder_power[e],
			"capacity": elder_capacity[e], "budget": budget, "drawn": elder_drawn[e],
			"load": elder_drawn[e] / maxf(budget, EPS), "stones": count})
	return out


# ============================================================================ coverage

func _refresh_stone(i: int) -> void:
	var g: Dictionary = _glyph_p[glyph[i]]
	if elder_of[i] >= 0:
		strength[i] = elder_power[elder_of[i]]
		_rad[i] = st_radius[i]
	else:
		strength[i] = charge[i] * condition[i] * float(g.get("strength", 1.0))
		_rad[i] = st_radius[i] * float(g.get("radius", 1.0))


func _refresh_all() -> void:
	for i in n:
		_refresh_stone(i)


## Protection at a world point, 0..1: the strongest stone bubble there. Same falloff as
## RARunestoneNetwork.coverage. This is what hook H3 plugs into Frontier.
func coverage_at(p: Vector2) -> float:
	var c := _cell_of(p)
	var best := 0.0
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var ids: Variant = _grid.get(Vector2i(c.x + dx, c.y + dy))
			if ids == null:
				continue
			for i: int in (ids as PackedInt32Array):
				var s := strength[i]
				if s <= best:
					continue
				var r := _rad[i]
				var d := p.distance_to(st_pos[i])
				if d >= r:
					continue
				var v := s * (1.0 - smoothstep(r * 0.55, r, d))
				if v > best:
					best = v
	return best


func coverage_callable() -> Callable:
	return coverage_at


## Crop yield multiplier at a point from bless glyphs (1.0 = none).
func bless_at(p: Vector2) -> float:
	var bonus := float(_glyph_p[G_BLESS].get("yield_bonus", 0.25))
	var best := 0.0
	for i in n:
		if glyph[i] != G_BLESS:
			continue
		var d := p.distance_to(st_pos[i])
		var r := _rad[i]
		if d >= r:
			continue
		best = maxf(best, charge[i] * condition[i] * (1.0 - smoothstep(r * 0.55, r, d)))
	return 1.0 + bonus * best


## Lure stones that are lit: [{id, pos, radius, power}] for the monster ecology to chase.
func lure_points() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lr := float(_glyph_p[G_LURE].get("lure_radius", 160.0))
	for i in n:
		if glyph[i] == G_LURE and charge[i] * condition[i] > 0.15:
			out.append({"id": i, "pos": st_pos[i], "radius": lr, "power": charge[i] * condition[i]})
	return out


## The road's protection along its whole length: {min, mean, samples} (used by tests and
## the rumour text). Samples every `step` metres along the chain of stones.
func road_coverage(key: String, step := 40.0) -> Dictionary:
	var ids: PackedInt32Array = _roads.get(key, PackedInt32Array())
	if ids.size() < 2:
		return {"min": 0.0, "mean": 0.0, "samples": 0}
	var lo := 1.0
	var sum := 0.0
	var cnt := 0
	for k in range(1, ids.size()):
		var a := st_pos[ids[k - 1]]
		var b := st_pos[ids[k]]
		var segs := maxi(1, int(a.distance_to(b) / step))
		for s in segs + 1:
			var c := coverage_at(a.lerp(b, float(s) / float(segs)))
			lo = minf(lo, c)
			sum += c
			cnt += 1
	return {"min": lo, "mean": sum / maxf(1.0, cnt), "samples": cnt}


func road_keys() -> PackedStringArray:
	var ks := PackedStringArray(_roads.keys())
	ks.sort()
	return ks


func road_name(key: String) -> String:
	var ids: PackedInt32Array = _roads.get(key, PackedInt32Array())
	return st_road_name[ids[0]] if not ids.is_empty() else key


func road_stones(key: String) -> PackedInt32Array:
	return _roads.get(key, PackedInt32Array())


func stone_count() -> int:
	return n


func stone_info(id: int) -> Dictionary:
	return {"id": id, "name": st_name[id], "pos": st_pos[id], "radius": _rad[id], "road": st_road[id],
		"owner": st_owner[id], "elder": elder_of[id] >= 0, "glyph": GLYPH_NAMES[glyph[id]],
		"charge": charge[id], "condition": condition[id], "fed": fed[id], "strength": strength[id],
		"band": BAND_NAMES[band[id]], "pinned": pinned[id] == 1, "supplier": supplier[id],
		"demand": _demand(id)}


func stone_strength(id: int) -> float:
	return strength[id]


func stone_band(id: int) -> int:
	return band[id]


func nearest_stone(p: Vector2, max_dist := 1e9) -> int:
	var best := -1
	var best_d := max_dist * max_dist
	for i in n:
		var d := p.distance_squared_to(st_pos[i])
		if d < best_d:
			best_d = d
			best = i
	return best


func glyph_name(id: int) -> String:
	return GLYPH_NAMES[glyph[id]]


## Fraction of non-Elder stones that are dim or better (0..1): one number for "how safe".
func health() -> float:
	var ok := 0
	var cnt := 0
	for i in n:
		if elder_of[i] >= 0:
			continue
		cnt += 1
		if band[i] >= BAND_DIM:
			ok += 1
	return float(ok) / maxf(1.0, cnt)


func _band_of(s: float) -> int:
	if s >= _cf("bands", "glowing"):
		return BAND_GLOWING
	if s >= _cf("bands", "dim"):
		return BAND_DIM
	if s >= _cf("bands", "cracked"):
		return BAND_CRACKED
	return BAND_DARK


# ============================================================================ simulation

func _step(dt: float) -> void:
	# Elders recover their power.
	var rec := _cf("elder", "recovery_per_day") * dt
	for e in elder_power.size():
		if elder_power[e] < 1.0:
			elder_power[e] = minf(1.0, elder_power[e] + rec)
			_alloc_dirty = true
	if _alloc_dirty:
		_allocate()
	# Charges follow the feed; wear ticks down.
	var rise := _cf("charge", "rise_per_day") * dt
	var fall := _cf("charge", "fall_per_day") * dt
	var decay := _cf("wear", "decay_per_day") * dt
	var late_after := _cf("wear", "neglect_after_days")
	var late_mult := _cf("wear", "neglect_mult")
	for i in n:
		if elder_of[i] >= 0:
			charge[i] = 1.0
			continue
		charge[i] = clampf(charge[i] + clampf(fed[i] - charge[i], -fall, rise), 0.0, 1.0)
		var wear := decay * (late_mult if day_f - last_repair[i] > late_after else 1.0)
		condition[i] = maxf(0.0, condition[i] - wear)
	# Daily events (failures, crews).
	while _last_day < floori(day_f):
		_last_day += 1
		_daily(_last_day)
	_quantize()
	_refresh_all()
	_update_states(true)


## Round the saved floats to 1e-6 so memory equals what JSON round-trips (Godot prints
## doubles with limited digits): a restored sim then continues bit-identically.
func _quantize() -> void:
	for i in n:
		charge[i] = snappedf(charge[i], 1e-6)
		condition[i] = snappedf(condition[i], 1e-6)
	for e in elder_power.size():
		elder_power[e] = snappedf(elder_power[e], 1e-6)
	crew_bank = snappedf(crew_bank, 1e-6)


## Stateless dice: the same (seed, day, stone, salt) always rolls the same, whatever the tick size.
func _dice(day: int, id: int, salt: int) -> float:
	return float(hash([seed_value, day, id, salt]) & 0xFFFFFF) / 16777216.0


func _daily(day: int) -> void:
	var chance := _cf("wear", "failure_chance_per_day")
	var fmin := _cf("wear", "failure_min")
	var fmax := _cf("wear", "failure_max")
	for i in n:
		if elder_of[i] >= 0:
			continue
		if _dice(day, i, 1) < chance:
			var hit := fmin + (fmax - fmin) * _dice(day, i, 2)
			condition[i] = maxf(0.0, condition[i] - hit)
			emit_event(&"stone_failed", {"id": i, "name": st_name[i], "condition": condition[i],
				"rumour": "%s cracked in the night." % st_name[i]})
	# Runeward crews: the weakest fed stone below the repair line, ties to the lowest id.
	crew_bank += _cf("crew", "repairs_per_stone_day") * float(n)
	var min_fed := _cf("crew", "min_fed")
	var below := _cf("crew", "repair_below")
	while crew_bank >= 1.0:
		crew_bank -= 1.0
		var pick := -1
		var lowest := below
		for i in n:
			if elder_of[i] < 0 and fed[i] >= min_fed and condition[i] < lowest:
				lowest = condition[i]
				pick = i
		if pick < 0:
			crew_bank = 0.0
			break
		repair(pick, _cf("wear", "repair_amount"), true)


## Recompute bands and emit change events. `quiet` = false suppresses nothing; the
## flag only marks whether this comes from a tick (events are always sent when something changes).
func _update_states(_from_tick: bool) -> void:
	var changed := false
	for i in n:
		var nb := _band_of(charge[i] * condition[i]) if elder_of[i] < 0 else BAND_GLOWING
		if nb == band[i]:
			continue
		var old := band[i]
		band[i] = nb
		changed = true
		if nb == BAND_DARK:
			emit_event(&"stone_dark", {"id": i, "name": st_name[i], "road": st_road_name[i],
				"rumour": "%s has gone dark." % st_name[i]})
		elif old == BAND_DARK or (old <= BAND_CRACKED and nb >= BAND_DIM):
			emit_event(&"stone_lit", {"id": i, "name": st_name[i], "road": st_road_name[i],
				"rumour": "%s glows again." % st_name[i]})
	if changed:
		_update_roads()
	for e in elder_ids.size():
		var s := _starved.size() > e and _starved[e] == 1
		if s != (_strained[e] == 1):
			_strained[e] = 1 if s else 0
			var nm := st_name[elder_ids[e]]
			if s:
				emit_event(&"elder_strained", {"elder": e, "name": nm,
					"rumour": "%s is stretched thin, the far stones are fading." % nm})
			else:
				emit_event(&"elder_calm", {"elder": e, "name": nm,
					"rumour": "%s has power to spare again." % nm})


func _update_roads() -> void:
	var failing: Dictionary = {}
	for key: String in _roads:
		var c := 0
		for i in (_roads[key] as PackedInt32Array):
			if band[i] <= BAND_CRACKED:
				c += 1
		failing[key] = c
	var min_n := int(_cd("rumour", "road_min_stones", 1))
	for key: String in failing:
		var c: int = failing[key]
		var old: int = _road_failing.get(key, 0)
		if c == old:
			continue
		var nm := road_name(key)
		if c >= min_n:
			emit_event(&"road_rumour", {"road": key, "name": nm, "failing": c, "was": old,
				"rumour": _road_text(nm, c)})
		elif old >= min_n:
			emit_event(&"road_clear", {"road": key, "name": nm,
				"rumour": "The road to %s is safe again, the stones are glowing." % nm})
	_road_failing = failing


func _road_text(nm: String, c: int) -> String:
	if c == 1:
		return "Don't take the road to %s, a stone there stopped glowing." % nm
	return "Don't take the road to %s, %d stones there stopped glowing." % [nm, c]


## Current gossip: one line per road with failing stones (same voice as RARunestoneNetwork.rumours).
func rumours() -> Array[String]:
	var out: Array[String] = []
	var min_n := int(_cd("rumour", "road_min_stones", 1))
	for key in road_keys():
		var c: int = _road_failing.get(key, 0)
		if c >= min_n:
			out.append(_road_text(road_name(key), c))
	return out


func _snap_bands() -> void:
	for i in n:
		band[i] = _band_of(charge[i] * condition[i]) if elder_of[i] < 0 else BAND_GLOWING
	_road_failing.clear()
	for key: String in _roads:
		var c := 0
		for i in (_roads[key] as PackedInt32Array):
			if band[i] <= BAND_CRACKED:
				c += 1
		_road_failing[key] = c
	for e in elder_ids.size():
		_strained[e] = 1 if _starved.size() > e and _starved[e] == 1 else 0


# ============================================================================ player actions

func _dirty_alloc() -> void:
	_quantize()
	_alloc_dirty = true
	_allocate()
	_refresh_all()
	_update_states(false)


func _dirty_graph() -> void:
	_rebuild_adj()
	_routes_dirty = true
	_rebuild_routes()
	_dirty_alloc()


## Drag a wardline between two stones. Rules: not the same stone, not too long, both stones
## below max_degree live links. An old cut link between them is simply mended.
func add_link(a: int, b: int) -> Dictionary:
	if a == b or a < 0 or b < 0 or a >= n or b >= n:
		return {"ok": false, "reason": "bad_stones"}
	var li := _find_link(a, b)
	if li >= 0 and not bool(links[li]["cut"]):
		return {"ok": false, "reason": "exists"}
	var length := st_pos[a].distance_to(st_pos[b])
	if length > _cf("links", "max_len"):
		return {"ok": false, "reason": "too_far", "len": length, "max": _cf("links", "max_len")}
	var md := int(_cd("links", "max_degree", 4))
	if degree(a) >= md or degree(b) >= md:
		return {"ok": false, "reason": "too_many_links"}
	if li >= 0:
		links[li]["cut"] = false
	else:
		links.append({"a": mini(a, b), "b": maxi(a, b), "len": length, "kind": "player", "cut": false})
	_dirty_graph()
	emit_event(&"link_made", {"a": a, "b": b, "len": length,
		"rumour": "The Runewards ran a new wardline from %s to %s." % [st_name[a], st_name[b]]})
	return {"ok": true, "len": length}


## Cut a wardline (sabotage, or deliberately starving a stretch to leave a gap).
func cut_link(a: int, b: int) -> bool:
	var li := _find_link(a, b)
	if li < 0 or bool(links[li]["cut"]):
		return false
	links[li]["cut"] = true
	_dirty_graph()
	emit_event(&"link_cut", {"a": a, "b": b, "rumour": "The wardline between %s and %s was cut." % [
		st_name[a], st_name[b]]})
	return true


func mend_link(a: int, b: int) -> bool:
	var li := _find_link(a, b)
	if li < 0 or not bool(links[li]["cut"]):
		return false
	links[li]["cut"] = false
	_dirty_graph()
	emit_event(&"link_mended", {"a": a, "b": b, "rumour": "The wardline between %s and %s was mended." % [
		st_name[a], st_name[b]]})
	return true


## Carve a glyph ("none", "ward", "lure", "alarm", "bless"). The stone must hold a spark and
## have an Elder feeding it; the carving spends a breath of that Elder's power and tends the stone.
func carve(id: int, glyph_id: String) -> Dictionary:
	if id < 0 or id >= n:
		return {"ok": false, "reason": "bad_stone"}
	var gi := GLYPH_NAMES.find(glyph_id)
	if gi < 0:
		return {"ok": false, "reason": "unknown_glyph"}
	if elder_of[id] >= 0:
		return {"ok": false, "reason": "elder_stone"}
	if charge[id] < _cf("charge", "carve_min"):
		return {"ok": false, "reason": "too_dim"}
	var e := supplier[id]
	if e < 0:
		return {"ok": false, "reason": "unfed"}
	var cost := _cf("elder", "carve_cost")
	if elder_power[e] < cost:
		return {"ok": false, "reason": "elder_spent"}
	elder_power[e] -= cost
	glyph[id] = gi
	condition[id] = minf(1.0, condition[id] + _cf("wear", "carve_repair"))
	last_repair[id] = day_f
	_dirty_alloc()
	emit_event(&"glyph_carved", {"id": id, "name": st_name[id], "glyph": glyph_id,
		"rumour": "A %s glyph was carved on %s." % [glyph_id, st_name[id]] if glyph_id != "none"
			else "The glyph on %s was scraped off." % st_name[id]})
	return {"ok": true, "glyph": glyph_id, "cost": cost}


## Pinned stones are served first when an Elder runs short.
func set_pinned(id: int, on: bool) -> void:
	if id < 0 or id >= n or (pinned[id] == 1) == on:
		return
	pinned[id] = 1 if on else 0
	_routes_dirty = true
	_rebuild_routes()
	_dirty_alloc()


func repair(id: int, amount := -1.0, by_crew := false) -> void:
	if id < 0 or id >= n:
		return
	var a := amount if amount >= 0.0 else _cf("wear", "repair_amount")
	condition[id] = minf(1.0, condition[id] + a)
	last_repair[id] = day_f
	if not by_crew:
		emit_event(&"stone_repaired", {"id": id, "name": st_name[id], "condition": condition[id]})


func damage_stone(id: int, amount: float) -> void:
	if id < 0 or id >= n or elder_of[id] >= 0:
		return
	condition[id] = maxf(0.0, condition[id] - amount)
	emit_event(&"stone_damaged", {"id": id, "name": st_name[id], "condition": condition[id]})
	_refresh_stone(id)
	_update_states(false)


## Something (the Scar, a raid) presses on every stone in a circle. Returns how many.
func pressure(pos: Vector2, radius: float, amount: float) -> int:
	var hit := 0
	for i in n:
		if elder_of[i] < 0 and st_pos[i].distance_to(pos) <= radius:
			condition[i] = maxf(0.0, condition[i] - amount)
			hit += 1
	if hit > 0:
		_refresh_all()
		_update_states(false)
	return hit


func drain_elder(index: int, amount: float) -> void:
	if index < 0 or index >= elder_power.size():
		return
	elder_power[index] = maxf(0.0, elder_power[index] - amount)
	emit_event(&"elder_drained", {"elder": index, "name": st_name[elder_ids[index]], "power": elder_power[index]})
	_dirty_alloc()


## Tell the alarm stones a threat appeared at `pos`. Every lit alarm stone that "hears" it
## (within its listen radius, off cooldown) raises an `alarm` event. Returns how many rang.
func notify_threat(pos: Vector2, level := 1.0) -> int:
	var listen := float(_glyph_p[G_ALARM].get("listen_radius", 420.0))
	var cool := float(_glyph_p[G_ALARM].get("cooldown_days", 0.25))
	var rang := 0
	for i in n:
		if glyph[i] != G_ALARM or charge[i] * condition[i] < 0.15:
			continue
		if st_pos[i].distance_to(pos) > listen or day_f - alarm_last[i] < cool:
			continue
		alarm_last[i] = day_f
		rang += 1
		emit_event(&"alarm", {"id": i, "name": st_name[i], "pos_x": pos.x, "pos_y": pos.y, "level": level,
			"rumour": "The alarm stone at %s is ringing, something is near." % st_name[i]})
	return rang


# ============================================================================ persistence

func _fa(p: PackedFloat64Array) -> Array:
	return Array(p)


func _save_state() -> Dictionary:
	_quantize()
	var xs: Array = []
	var ys: Array = []
	for p in st_pos:
		xs.append(p.x)
		ys.append(p.y)
	var lk: Array = []
	for l in links:
		lk.append([l["a"], l["b"], l["len"], l["kind"], 1 if bool(l["cut"]) else 0])
	return {
		"source": layout_source,
		"x": xs, "y": ys, "r": _fa(st_radius), "name": Array(st_name), "road": Array(st_road),
		"road_name": Array(st_road_name), "owner": Array(st_owner), "elders": Array(elder_ids),
		"links": lk,
		"charge": _fa(charge), "cond": _fa(condition), "glyph": Array(glyph), "pin": Array(pinned),
		"rep": _fa(last_repair), "alarm": _fa(alarm_last),
		"power": _fa(elder_power), "cap": _fa(elder_capacity), "crew": crew_bank, "last_day": _last_day,
	}


func _load_state(d: Dictionary) -> void:
	load_config()
	if d.is_empty() or not d.has("x"):
		_clear_layout()
		_generate_synthetic()
		_last_day = floori(day_f)
		return
	_clear_layout()
	layout_source = String(d.get("source", "custom"))
	var xs: Array = d["x"]
	var ys: Array = d["y"]
	for i in xs.size():
		st_pos.append(Vector2(float(xs[i]), float(ys[i])))
	n = st_pos.size()
	st_radius = PackedFloat64Array(d["r"])
	st_name = PackedStringArray(d["name"])
	st_road = PackedStringArray(d["road"])
	st_road_name = PackedStringArray(d["road_name"])
	st_owner = PackedInt32Array(d["owner"])
	elder_ids = PackedInt32Array(d["elders"])
	links = []
	for l: Array in d["links"]:
		links.append({"a": int(l[0]), "b": int(l[1]), "len": float(l[2]), "kind": String(l[3]), "cut": int(l[4]) == 1})
	# derived structures first, then the saved dynamic values on top
	elder_of = PackedInt32Array()
	elder_of.resize(n)
	elder_of.fill(-1)
	for e in elder_ids.size():
		elder_of[elder_ids[e]] = e
	glyph = PackedInt32Array(d["glyph"])
	pinned = PackedByteArray(d["pin"])
	_build_grid()
	_build_roads()
	_rebuild_adj()
	_rebuild_routes()
	charge = PackedFloat64Array(d["charge"])
	condition = PackedFloat64Array(d["cond"])
	last_repair = PackedFloat64Array(d["rep"])
	alarm_last = PackedFloat64Array(d["alarm"])
	elder_power = PackedFloat64Array(d["power"])
	elder_capacity = PackedFloat64Array(d["cap"])
	crew_bank = float(d.get("crew", 0.0))
	_last_day = int(d.get("last_day", floori(day_f)))
	_strained = PackedByteArray()
	_strained.resize(elder_ids.size())
	fed = PackedFloat64Array()
	fed.resize(n)
	strength = PackedFloat64Array()
	strength.resize(n)
	_rad = PackedFloat64Array()
	_rad.resize(n)
	band = PackedByteArray()
	band.resize(n)
	supplier = PackedInt32Array()
	supplier.resize(n)
	supplier.fill(-1)
	elder_drawn = PackedFloat64Array()
	elder_drawn.resize(elder_ids.size())
	_allocate()
	_refresh_all()
	_snap_bands()


# ============================================================================ debug picture

func summary() -> String:
	var dark := 0
	var dim := 0
	for i in n:
		if elder_of[i] >= 0:
			continue
		if band[i] == BAND_DARK:
			dark += 1
		elif band[i] <= BAND_DIM:
			dim += 1
	var rep := budget_report()
	return "%s stones=%d dark=%d dim/cracked=%d health=%.0f%% budget %.0f/%.0f loss %.1f" % [
		super.summary(), n, dark, dim, health() * 100.0, rep["drawn"], rep["supply"], rep["loss"]]


## Coverage over the map (blue glow on parchment), links (gold; cut = red; player = teal),
## stones by band and Elders as gold rings.
func debug_image(px: int = 512) -> Image:
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	img.fill(Color(0.93, 0.88, 0.76))
	if n == 0:
		return img
	var b := _bounds
	var side := maxf(b.size.x, b.size.y)
	var org := b.position - Vector2(side - b.size.x, side - b.size.y) * 0.5
	var k := float(px) / side
	var res := maxi(2, px / 4)
	var glow := Image.create(res, res, false, Image.FORMAT_RGB8)
	for gy in res:
		for gx in res:
			var w := org + Vector2((gx + 0.5) / res, (gy + 0.5) / res) * side
			var c := coverage_at(w)
			var bg := Color(0.93, 0.88, 0.76)
			glow.set_pixel(gx, gy, bg.lerp(Color(0.25, 0.55, 0.95), clampf(c * 0.85, 0.0, 0.85)))
	glow.resize(px, px, Image.INTERPOLATE_BILINEAR)
	img.blit_rect(glow, Rect2i(0, 0, px, px), Vector2i.ZERO)
	for l in links:
		var pa := (st_pos[l["a"]] - org) * k
		var pb := (st_pos[l["b"]] - org) * k
		var col := Color(0.5, 0.36, 0.1, 0.9)
		if bool(l["cut"]):
			col = Color(0.85, 0.15, 0.1)
		elif l["kind"] == "player":
			col = Color(0.0, 0.6, 0.6)
		_line(img, pa, pb, col, bool(l["cut"]))
	for i in n:
		var p := (st_pos[i] - org) * k
		if elder_of[i] >= 0:
			_disc(img, p, 7.0, Color(0.95, 0.75, 0.15))
			_disc(img, p, 4.5, Color(1.0, 1.0, 0.9))
			continue
		var cols: Array[Color] = [Color(0.1, 0.05, 0.1), Color(0.9, 0.45, 0.1), Color(0.75, 0.85, 0.95), Color(0.2, 0.85, 1.0)]
		_disc(img, p, 3.0, Color(0.2, 0.15, 0.1))
		_disc(img, p, 2.2, cols[band[i]])
		if glyph[i] != G_NONE:
			var gc: Array[Color] = [Color.WHITE, Color(0.2, 0.4, 1.0), Color(0.9, 0.2, 0.7), Color(1.0, 0.85, 0.1), Color(0.3, 0.8, 0.3)]
			_ring(img, p, 5.0, gc[glyph[i]])
	return img


func _disc(img: Image, c: Vector2, r: float, col: Color) -> void:
	var w := img.get_width()
	for y in range(maxi(0, int(c.y - r)), mini(img.get_height(), int(c.y + r) + 1)):
		for x in range(maxi(0, int(c.x - r)), mini(w, int(c.x + r) + 1)):
			if Vector2(x + 0.5, y + 0.5).distance_to(c) <= r:
				img.set_pixel(x, y, col)


func _ring(img: Image, c: Vector2, r: float, col: Color) -> void:
	var w := img.get_width()
	for y in range(maxi(0, int(c.y - r - 1)), mini(img.get_height(), int(c.y + r) + 2)):
		for x in range(maxi(0, int(c.x - r - 1)), mini(w, int(c.x + r) + 2)):
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d <= r and d >= r - 1.4:
				img.set_pixel(x, y, col)


func _line(img: Image, a: Vector2, b: Vector2, col: Color, dashed: bool) -> void:
	var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
	var w := img.get_width()
	var h := img.get_height()
	for s in steps + 1:
		if dashed and (s / 3) % 2 == 1:
			continue
		var p := a.lerp(b, float(s) / maxf(1.0, steps))
		var x := int(p.x)
		var y := int(p.y)
		if x >= 0 and y >= 0 and x < w and y < h:
			img.set_pixel(x, y, col)


## Append to a PackedInt32Array stored in a Dictionary/Array (a cast would append to a copy).
func _push(container: Variant, key: Variant, v: int) -> void:
	var a: PackedInt32Array = container[key]
	a.append(v)
	container[key] = a
