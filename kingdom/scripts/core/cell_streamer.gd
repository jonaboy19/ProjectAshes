extends RefCounted
## One streaming manager over a 64 m cell grid (F12). Preload, no class_name:
##   const CellStreamer := preload("res://scripts/core/cell_streamer.gd")
##   var cs := CellStreamer.shared()          # main.gd calls cs.update(focus) every frame
##
## Every subsystem that streams something around the player is a PROFILE with three distances per quality tier
## (the one place they are set, PROFILES below; the terrain ring comes straight from Quality's "view_radius"):
##   full  inside this the cell is FULL (hero LOD, collision, full bodies)
##   load  inside this it is at least LOW (mid detail: built, batched, sprites)
##   hyst  extra metres a cell keeps its tier before it drops, so a player standing on a boundary never makes
##         a cell flicker; beyond load + hyst it is UNLOADED (freed, asleep)
## Existing streamers keep their internals but read their radii from distance()/radius_cells(), and register as
## listeners:
##   watch(profile, cb)               cb(cell: Vector2i, tier, old_tier) for every cell whose tier changed (grid users)
##   add_site(profile, id, pos, cb)   cb(id, tier, old_tier) for one world position (a spawner, a dressing site, a
##                                    gather node). The tier follows the site's exact distance, so a spawner is
##                                    asleep (UNLOADED) exactly when it is out of range.
## update() is cheap (sites are a short list, grid watchers a small window) and only recomputes after the focus moved
## MOVE_EPS metres, a quality change, or a new registration.

enum Tier { UNLOADED, LOW, FULL }

const CELL := 64.0
const MOVE_EPS := 3.0
## Per profile, per quality tier (LOW, MEDIUM, HIGH, ULTRA): metres. "terrain" load is Quality view_radius x CELL.
const PROFILES := {
	"terrain": {"full": [64.0, 64.0, 64.0, 64.0], "load": [], "hyst": 64.0},
	"settlement": {"full": [70.0, 70.0, 70.0, 70.0], "load": [650.0, 650.0, 650.0, 650.0], "hyst": 200.0},
	"dressing": {"full": [55.0, 55.0, 55.0, 55.0], "load": [240.0, 240.0, 240.0, 240.0], "hyst": 90.0},
	"population": {"full": [45.0, 45.0, 45.0, 45.0], "load": [220.0, 220.0, 220.0, 220.0], "hyst": 10.0},
	"gather": {"full": [24.0, 24.0, 24.0, 24.0], "load": [55.0, 55.0, 55.0, 55.0], "hyst": 25.0},
	"ambient": {"full": [40.0, 40.0, 40.0, 40.0], "load": [110.0, 110.0, 110.0, 110.0], "hyst": 60.0},
	"camps": {"full": [100.0, 100.0, 100.0, 100.0], "load": [260.0, 260.0, 260.0, 260.0], "hyst": 160.0},
}

static var _shared: RefCounted

## -1: follow Quality (tier plus the settings screen's overrides); LOW..ULTRA: a fixed tier (tests, previews).
var quality_tier := -1
var focus := Vector2(1.0e9, 1.0e9)
var updates := 0
var notifications := 0

var _cell_tiers := {}            # profile -> {Vector2i: Tier} (only cells that are not UNLOADED)
var _watchers := {}              # profile -> Array of [id, Callable]
var _sites := {}                 # profile -> {id: {"pos": Vector2, "cb": Callable, "tier": Tier, "cell": Vector2i}}
var _site_cells := {}            # profile -> {Vector2i: {id: true}}   (only cells that hold sites)
var _awake_sites := {}           # profile -> {id: true}               (sites whose tier is not UNLOADED)
var _next_watch := 1
var _dirty := true
var _last_key := ""


static func shared() -> RefCounted:
	if _shared == null:
		_shared = (load("res://scripts/core/cell_streamer.gd") as GDScript).new()
	return _shared


static func reset_shared() -> void:
	_shared = null


# --- distances (the one place) -----------------------------------------------------------------------

func _qt() -> int:
	if quality_tier >= 0:
		return clampi(quality_tier, 0, 3)
	var q := _quality()
	return clampi(int(q.get("tier")), 0, 3) if q != null else 2


static func _quality() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree and (loop as SceneTree).root != null:
		return (loop as SceneTree).root.get_node_or_null("Quality")
	return null


## Terrain ring (chunks) for the quality tier: Quality's view_radius, with the settings screen's overrides when following Quality.
func view_radius() -> int:
	if quality_tier < 0:
		var q := _quality()
		if q != null:
			return int(q.call("value", "view_radius"))
	return int(preload("res://scripts/core/quality.gd").TIERS[_qt()]["view_radius"])


## "full", "load", "hyst" or "free" (load + hyst) in metres for `profile` at the current quality tier.
func distance(profile: String, key: String) -> float:
	var def: Dictionary = PROFILES[profile]
	if key == "free":
		return distance(profile, "load") + float(def["hyst"])
	if key == "hyst":
		return float(def["hyst"])
	if profile == "terrain" and key == "load":
		return float(view_radius()) * CELL
	return float((def[key] as Array)[_qt()])


## Same distances for an explicit quality tier (tests, the settings preview).
func distance_at(profile: String, key: String, qtier: int) -> float:
	var saved := quality_tier
	quality_tier = qtier
	var d := distance(profile, key)
	quality_tier = saved
	return d


## Whole cells covered by the load distance (the chunk ring of a streamer).
func radius_cells(profile: String, key := "load") -> int:
	return int(ceil(distance(profile, key) / CELL))


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))


# --- tier rule -----------------------------------------------------------------------------------------

## The hysteresis rule: a cell reaches FULL / LOW at the full / load distance and only drops at + hyst.
func tier_for(profile: String, dist: float, current: int) -> int:
	var f := distance(profile, "full")
	var l := distance(profile, "load")
	var h := distance(profile, "hyst")
	if dist <= (f + h if current == Tier.FULL else f):
		return Tier.FULL
	if dist <= (l + h if current >= Tier.LOW else l):
		return Tier.LOW
	return Tier.UNLOADED


static func box_distance(cell: Vector2i, p: Vector2) -> float:
	var lo := Vector2(cell) * CELL
	var dx := maxf(maxf(lo.x - p.x, p.x - (lo.x + CELL)), 0.0)
	var dz := maxf(maxf(lo.y - p.y, p.y - (lo.y + CELL)), 0.0)
	return sqrt(dx * dx + dz * dz)


func cell_tier(profile: String, cell: Vector2i) -> int:
	return int((_cell_tiers.get(profile, {}) as Dictionary).get(cell, Tier.UNLOADED))


func cells_in_tier(profile: String, tier: int) -> int:
	var n := 0
	for t: int in (_cell_tiers.get(profile, {}) as Dictionary).values():
		if t == tier:
			n += 1
	return n


# --- listeners ---------------------------------------------------------------------------------------------

## cb(cell: Vector2i, tier: int, old_tier: int) per changed cell of `profile`. Returns an id for unwatch().
func watch(profile: String, cb: Callable) -> int:
	assert(PROFILES.has(profile))
	var id := _next_watch
	_next_watch += 1
	if not _watchers.has(profile):
		_watchers[profile] = []
	(_watchers[profile] as Array).append([id, cb])
	_dirty = true
	return id


func unwatch(id: int) -> void:
	for p: String in _watchers:
		var arr: Array = _watchers[p]
		for i in range(arr.size() - 1, -1, -1):
			if int(arr[i][0]) == id:
				arr.remove_at(i)


## A world position that wants to know when it wakes (LOW / FULL) and sleeps (UNLOADED): cb(id, tier, old_tier).
## If the focus is known and the site is already in range it is told straight away.
func add_site(profile: String, id: Variant, pos: Vector2, cb: Callable) -> void:
	assert(PROFILES.has(profile))
	if not _sites.has(profile):
		_sites[profile] = {}
	(_sites[profile] as Dictionary)[id] = {"pos": pos, "cb": cb, "tier": Tier.UNLOADED, "cell": cell_of(pos)}
	_index_site(profile, id, cell_of(pos))
	if focus.x < 1.0e8:
		_update_site(profile, id)


func move_site(profile: String, id: Variant, pos: Vector2) -> void:
	var s: Dictionary = (_sites.get(profile, {}) as Dictionary).get(id, {})
	if not s.is_empty():
		_unindex_site(profile, id, s["cell"])
		s["pos"] = pos
		s["cell"] = cell_of(pos)
		_index_site(profile, id, s["cell"])
		_update_site(profile, id)


func remove_site(profile: String, id: Variant) -> void:
	var s: Dictionary = (_sites.get(profile, {}) as Dictionary).get(id, {})
	if not s.is_empty():
		_unindex_site(profile, id, s["cell"])
	(_sites.get(profile, {}) as Dictionary).erase(id)
	(_awake_sites.get(profile, {}) as Dictionary).erase(id)


func _index_site(profile: String, id: Variant, cell: Vector2i) -> void:
	if not _site_cells.has(profile):
		_site_cells[profile] = {}
	var cells: Dictionary = _site_cells[profile]
	if not cells.has(cell):
		cells[cell] = {}
	(cells[cell] as Dictionary)[id] = true


func _unindex_site(profile: String, id: Variant, cell: Vector2i) -> void:
	var cells: Dictionary = _site_cells.get(profile, {})
	if cells.has(cell):
		(cells[cell] as Dictionary).erase(id)
		if (cells[cell] as Dictionary).is_empty():
			cells.erase(cell)


func site_tier(profile: String, id: Variant) -> int:
	var s: Dictionary = (_sites.get(profile, {}) as Dictionary).get(id, {})
	return int(s.get("tier", Tier.UNLOADED))


## True when a spawner at this site should be asleep (no focus yet counts as awake: nothing to compare with).
func asleep(profile: String, id: Variant) -> bool:
	return focus.x < 1.0e8 and site_tier(profile, id) == Tier.UNLOADED


## Spawner helper: registers `holder` (the spawner's own record) as a site of `profile` on first use and returns its
## tier, or -1 when the manager has not been fed THIS focus (a standalone test, a cutscene camera): the caller then
## keeps its own distance check. The tier is kept in holder["tier"] by the site callback.
func spawner_tier(profile: String, holder: Dictionary, pos: Vector2, own_focus: Vector2) -> int:
	if not holder.has("_site_id"):
		var id := _next_watch
		_next_watch += 1
		holder["_site_id"] = id
		holder["tier"] = Tier.UNLOADED
		add_site(profile, id, pos, Callable(self, "_set_holder_tier").bind(holder))
		_dirty = true
	if focus.x > 1.0e8 or focus.distance_to(own_focus) > 8.0:
		return -1
	return int(holder["tier"])


func release_spawner(profile: String, holder: Dictionary) -> void:
	if holder.has("_site_id"):
		remove_site(profile, holder["_site_id"])
		holder.erase("_site_id")


func _set_holder_tier(_id: Variant, t: int, _old: int, holder: Dictionary) -> void:
	holder["tier"] = t


func site_count(profile: String) -> int:
	return (_sites.get(profile, {}) as Dictionary).size()


# --- update ---------------------------------------------------------------------------------------------------

## Per frame from main.gd. Returns true when a recompute ran.
func update(world_focus: Vector3) -> bool:
	var f := Vector2(world_focus.x, world_focus.z)
	var key := "%d/%d/%d" % [_qt(), view_radius(), 0]
	if not _dirty and key == _last_key and f.distance_to(focus) < MOVE_EPS:
		return false
	_last_key = key
	_dirty = false
	focus = f
	updates += 1
	for profile: String in PROFILES:
		if _watchers.has(profile) and not (_watchers[profile] as Array).is_empty():
			_update_cells(profile)
		if _sites.has(profile):
			_update_sites(profile)
	return true


func _update_cells(profile: String) -> void:
	var tiers: Dictionary = _cell_tiers.get(profile, {})
	var wr := int(ceil(distance(profile, "free") / CELL)) + 1
	var c0 := cell_of(focus)
	var todo := {}
	for dz in range(-wr, wr + 1):
		for dx in range(-wr, wr + 1):
			todo[Vector2i(c0.x + dx, c0.y + dz)] = true
	for k: Vector2i in tiers.keys():
		todo[k] = true
	var changes: Array = []
	for cell: Vector2i in todo:
		var old := int(tiers.get(cell, Tier.UNLOADED))
		var t := tier_for(profile, box_distance(cell, focus), old)
		if t == old:
			continue
		if t == Tier.UNLOADED:
			tiers.erase(cell)
		else:
			tiers[cell] = t
		changes.append([cell, t, old])
	_cell_tiers[profile] = tiers
	for ch: Array in changes:
		for w: Array in (_watchers[profile] as Array).duplicate():
			notifications += 1
			(w[1] as Callable).call(ch[0], ch[1], ch[2])


## Only sites in the window around the focus, plus the awake ones (which may have just left it), are looked at.
func _update_sites(profile: String) -> void:
	var cells: Dictionary = _site_cells.get(profile, {})
	var todo := {}
	for id: Variant in (_awake_sites.get(profile, {}) as Dictionary):
		todo[id] = true
	var wr := int(ceil(distance(profile, "free") / CELL)) + 1
	var c0 := cell_of(focus)
	if cells.size() <= (2 * wr + 1) * (2 * wr + 1):
		for cell: Vector2i in cells:
			if absi(cell.x - c0.x) <= wr and absi(cell.y - c0.y) <= wr:
				for id: Variant in (cells[cell] as Dictionary):
					todo[id] = true
	else:
		for dz in range(-wr, wr + 1):
			for dx in range(-wr, wr + 1):
				var cell := Vector2i(c0.x + dx, c0.y + dz)
				if cells.has(cell):
					for id: Variant in (cells[cell] as Dictionary):
						todo[id] = true
	for id: Variant in todo:
		_update_site(profile, id)


func _update_site(profile: String, id: Variant) -> void:
	var s: Dictionary = (_sites.get(profile, {}) as Dictionary).get(id, {})
	if s.is_empty() or focus.x > 1.0e8:
		return
	var old := int(s["tier"])
	var t := tier_for(profile, focus.distance_to(s["pos"]), old)
	if t == old:
		return
	s["tier"] = t
	if t == Tier.UNLOADED:
		(_awake_sites.get(profile, {}) as Dictionary).erase(id)
	else:
		if not _awake_sites.has(profile):
			_awake_sites[profile] = {}
		(_awake_sites[profile] as Dictionary)[id] = true
	notifications += 1
	var cb: Callable = s["cb"]
	if cb.is_valid():
		cb.call(id, t, old)
