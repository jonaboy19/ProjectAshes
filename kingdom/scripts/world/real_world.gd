class_name RealWorld
extends RefCounted
## W6 real-elevation world (docs/world/REAL_WORLD.md): data/world/real/layout.json re-anchors every place of the old 12 km Valencious
## layout onto the 32 km Lake District terrain. Active only with --world_macro=real (WorldMacro.is_real()).
##   remap(old)      old WorldGen position -> new position: exact table hit for the 343 bible places (by old position, 2 m), else the
##                   thin-plate warp fitted on the sub-region anchors (tools/world/real_layout.py). Identity when the mode is off.
##   water_level(p)  real lakes (lake_ids.png, 32 m cells, dilated one cell) and the sea (level 0); NAN elsewhere.
##   in_realm(p)     inside the playable Valencious box (region lock; `unlocked` lifts it).
## Ids, names and road topology never change: only positions move. Read-only after load, thread-safe.

const LAYOUT := "res://data/world/real/layout.json"
const LAKE_IDS := "res://data/world/real/lake_ids.png"
const WORLD_VERSION := 3          # saves made before the real world carry 2 (or nothing)
const LAKE_GRID := 1024
const LAKE_MPP := 32.0
const HALF := 16384.0

## Region lock flag (future content: set true to open the outer realms). Settings: [world] unlock_outer.
static var unlocked := false
static var _loaded := false
static var _mutex := Mutex.new()
static var _box := Rect2(-12000, -7000, 16000, 16000)
static var _exact: Dictionary = {}        # Vector2i(round old x / 2, round old z / 2) -> Vector2 new
static var _by_id: Dictionary = {}        # place id -> Vector2 new
static var _tc := PackedVector2Array()    # TPS centres
static var _tw := PackedVector2Array()    # TPS weights
static var _ta := PackedVector2Array()    # TPS affine rows (a0, ax, az)
static var _lake_ids := PackedByteArray()
static var _lake_level: Dictionary = {}   # id -> level
static var lakes: Array = []
static var _slice: Dictionary = {}       # vertical-slice anchors (MASTER_BACKLOG section 3): ashford, kingsreach, bandit_camp, cave_entrance


## Vertical-slice anchor by name (bandit_camp, cave_entrance, ...) or Vector2.INF. For the slice camp / dungeon-floor-1 entrance owners.
static func slice_anchor(key: String) -> Vector2:
	_ensure()
	return _slice.get(key, Vector2.INF)
static var rivers: Array = []


static func active() -> bool:
	return WorldMacro.is_real()


static func _ensure() -> void:
	if _loaded:
		return
	_mutex.lock()
	if not _loaded:
		_load()
		_loaded = true
	_mutex.unlock()


static func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		unlocked = bool(cf.get_value("world", "unlock_outer", false))
	for a in OS.get_cmdline_user_args():
		if a == "--unlock_outer":
			unlocked = true
	if not FileAccess.file_exists(LAYOUT):
		push_warning("RealWorld: %s missing" % LAYOUT)
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	if not d is Dictionary:
		return
	var b: Array = d["valencious_box"]
	_box = Rect2(float(b[0]), float(b[1]), float(b[2]) - float(b[0]), float(b[3]) - float(b[1]))
	for id: String in d["places"]:
		var p: Dictionary = d["places"][id]
		var o: Array = p["old"]
		var nv := Vector2(float(p["x"]), float(p["z"]))
		_exact[_key(Vector2(float(o[0]), float(o[1])))] = nv
		_by_id[id] = nv
	var t: Dictionary = d["tps"]
	for c: Array in t["centres"]:
		_tc.append(Vector2(float(c[0]), float(c[1])))
	for w: Array in t["w"]:
		_tw.append(Vector2(float(w[0]), float(w[1])))
	for r: Array in t["affine"]:
		_ta.append(Vector2(float(r[0]), float(r[1])))
	lakes = d.get("lakes", [])
	for l: Dictionary in lakes:
		_lake_level[int(l["id"])] = float(l["level"])
	_lake_level[255] = 0.0
	rivers = d.get("rivers", [])
	var sl: Variant = d.get("slice", {})
	if sl is Dictionary:
		for k: String in sl:
			if sl[k] is Array:
				_slice[k] = Vector2(float(sl[k][0]), float(sl[k][1]))
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(LAKE_IDS)) == OK:
		img.convert(Image.FORMAT_L8)
		_lake_ids = img.get_data()


static func _key(p: Vector2) -> Vector2i:
	return Vector2i(roundi(p.x * 0.5), roundi(p.y * 0.5))


## Old position -> new position (identity when the real world is off).
static func remap(p: Vector2) -> Vector2:
	if not active():
		return p
	_ensure()
	var k := _key(p)
	for dz in [0, -1, 1]:
		for dx in [0, -1, 1]:
			var kk := k + Vector2i(dx, dz)
			if _exact.has(kk):
				return _exact[kk]
	return warp(p)


## The smooth thin-plate warp alone (no table).
static func warp(p: Vector2) -> Vector2:
	_ensure()
	if _ta.size() < 3:
		return p
	var out := _ta[0] + _ta[1] * p.x + _ta[2] * p.y
	for i in _tc.size():
		var r := p.distance_to(_tc[i])
		if r > 0.0:
			out += _tw[i] * (r * r * log(r))
	return out


static func place(id: String) -> Variant:
	_ensure()
	return _by_id.get(id, null)


static func box() -> Rect2:
	_ensure()
	return _box


## Inside the playable realm (always true when the real world is off or the outer realms are unlocked).
static func in_realm(p: Vector2, margin := 0.0) -> bool:
	if not active() or unlocked:
		return true
	_ensure()
	return _box.grow(-margin).has_point(p)


## Lake / sea surface at (x, z) or NAN.
static func water_level(x: float, z: float) -> float:
	_ensure()
	if _lake_ids.is_empty():
		return NAN
	var i := int(floorf((x + HALF) / LAKE_MPP))
	var j := int(floorf((z + HALF) / LAKE_MPP))
	if i < 0 or j < 0 or i >= LAKE_GRID or j >= LAKE_GRID:
		return NAN
	var id := _lake_ids[j * LAKE_GRID + i]
	if id == 0:
		return NAN
	return float(_lake_level.get(id, NAN))


## The lake named Emberglass Mere (nearest Ashford): {centre: Vector2, level, area_km2} or {}.
static func mere() -> Dictionary:
	_ensure()
	for l: Dictionary in lakes:
		if String(l.get("name", "")) == "Emberglass Mere":
			return {"centre": Vector2(float(l["centre"][0]), float(l["centre"][1])), "level": float(l["level"]), "area_km2": float(l["area_km2"])}
	return {}
