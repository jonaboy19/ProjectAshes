class_name ScatterExclusion
extends RefCounted
## "Nothing grows here" for the ProtonScatter forest/undergrowth/rock scatter (terrain_backend = terrain3d), thread-safe.
## Static WorldGen footprints (roads, city streets, settlement discs, site clearings, water) are queried live; dynamic ones
## (build-kit grids, founded settlements, anything else) are registered as discs by BuildKit/Founding via sync_* and `set_zone`.
## Kinds: "tree" (trunks and canopies, widest margins), "rock", "plant" (undergrowth/grass, tight margins).

const ROAD_MARGIN := {"tree": 4.5, "rock": 3.0, "plant": 0.8}      # beyond the road's half width
const STREET_MARGIN := {"tree": 8.0, "rock": 6.0, "plant": 3.0}    # CityPlanner street_distance (INF outside towns)
const SETTLEMENT_MARGIN := {"tree": 14.0, "rock": 10.0, "plant": 0.0}   # beyond the settlement radius (plant: inside it only)
const CLEARING_SCALE := {"tree": 0.9, "rock": 0.8, "plant": 0.55}   # share of a site clearing's radius kept free
const WATER_MARGIN := {"tree": 3.0, "rock": 1.5, "plant": 1.5}
const GRID_MARGIN := {"tree": 24.0, "rock": 16.0, "plant": 8.0}    # beyond BuildKit.GRID_RADIUS
const FOUNDED_RADIUS := 56.0                                        # a founded settlement's footprint before any grid exists
const FOUNDED_MARGIN := {"tree": 24.0, "rock": 16.0, "plant": 8.0}

## Replaced wholesale (never mutated) so worker threads can read the array they got without a lock.
static var _zones: Array = []          # [id: String, centre: Vector2, radius: float, kind_margin: Dictionary]
static var _revision := 0


## Swaps the zone list in, bumping the revision only when something actually changed (callers sync daily).
static func _commit(next: Array) -> void:
	if str(next) == str(_zones):
		return
	_zones = next
	_revision += 1


static func revision() -> int:
	return _revision


static func zone_count() -> int:
	return _zones.size()


## Registers or replaces the disc `id` (e.g. "grid:2"). `margin` is a kind -> metres dictionary beyond `radius`.
static func set_zone(id: String, centre: Vector2, radius: float, margin: Dictionary = GRID_MARGIN) -> void:
	var next: Array = []
	for z: Array in _zones:
		if z[0] != id:
			next.append(z)
	next.append([id, centre, radius, margin])
	_commit(next)


static func clear_zone(id: String) -> void:
	var next: Array = []
	for z: Array in _zones:
		if z[0] != id:
			next.append(z)
	_commit(next)


static func clear_prefix(prefix: String) -> void:
	var next: Array = []
	for z: Array in _zones:
		if not (z[0] as String).begins_with(prefix):
			next.append(z)
	_commit(next)


static func clear_all() -> void:
	_zones = []
	_revision += 1


## BuildKit.grids (gid -> {origin: [x, y, z], ...}).
static func sync_grids(grids: Dictionary, grid_radius: float) -> void:
	var next: Array = []
	for z: Array in _zones:
		if not (z[0] as String).begins_with("grid:"):
			next.append(z)
	for gid: int in grids:
		var o: Array = grids[gid]["origin"]
		next.append(["grid:%d" % gid, Vector2(float(o[0]), float(o[2])), grid_radius, GRID_MARGIN])
	_commit(next)


## Founding records: Array of {pos: [x, z], st: int, end: int}. Records that ended (end >= 0) are free again.
static func sync_founded(records: Array) -> void:
	var next: Array = []
	for z: Array in _zones:
		if not (z[0] as String).begins_with("found:"):
			next.append(z)
	for r: Dictionary in records:
		if int(r.get("end", -1)) >= 0:
			continue
		var p: Array = r["pos"]
		next.append(["found:%d" % int(r.get("id", 0)), Vector2(float(p[0]), float(p[1])), FOUNDED_RADIUS, FOUNDED_MARGIN])
	_commit(next)


## True when nothing of `kind` may stand at (x, z).
static func blocked(x: float, z: float, kind := "tree") -> bool:
	var p := Vector2(x, z)
	for zone: Array in _zones:
		var c: Vector2 = zone[1]
		var m: Dictionary = zone[3]
		var lim: float = float(zone[2]) + float(m.get(kind, 0.0))
		if absf(c.x - x) <= lim and absf(c.y - z) <= lim and p.distance_squared_to(c) <= lim * lim:
			return true
	if WorldGen.near_water(x, z, WATER_MARGIN[kind]):
		return true
	var rinfo: Dictionary = WorldGen.road_info(x, z)
	if float(rinfo["dist"]) < float(rinfo["width"]) * 0.5 + float(ROAD_MARGIN[kind]):
		return true
	if WorldGen.street_distance(x, z) < float(STREET_MARGIN[kind]):
		return true
	var near: Dictionary = WorldGen.nearest_settlement(p)
	if not near.is_empty():
		var d := p.distance_to(near["pos"])
		var r: float = float(near["radius"])
		if kind == "plant":
			if d < r * 0.95:      # grass and undergrowth stop at the walls' inside only
				return true
		elif d < r + float(SETTLEMENT_MARGIN[kind]):
			return true
	for c: Dictionary in WorldGen.clearings:
		if p.distance_to(c["pos"]) < float(c["radius"]) * float(CLEARING_SCALE[kind]):
			return true
	return false
