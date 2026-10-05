extends RefCounted
## Interior layout kit data (package F6): house x4, shop x3, tavern x2, as plain Dictionaries generated from a few
## helper calls. A layout is pure data (no nodes), so it can be picked, validated and tested without a scene tree;
## scripts/interiors/modular_interior.gd turns one into geometry (scripts/interiors/interior_kit.gd) and furniture.
##
## Floor plan: centred on the origin, floor at y = 0, the entrance in the +Z wall at x = door_x (like the hand-made
## interiors in scenes/interiors/README.md). A prop's local +Z is its front; `y` is its yaw in degrees about Y, so a
## character standing on a prop's waypoint faces Basis(UP, y) * +Z (CharacterBody yaw = deg_to_rad(y)).
##
##   {id, category, title, w, d, h, door_x, windows[{wall, at, w}], partitions[{a, b, h, openings}],
##    loft{x0, x1, z0, z1, y, ladder_bottom, ladder_top} or {}, props[{t, p, y, level, ...}],
##    npcs[{role, look, p, y}], shop_kind, waypoints{bed, table, hearth, counter, seat, bar: [{p, y, so, level}]}}
##
## Prop types: bed cot table chair bench stool chest cupboard barrel crate hearth oven shelf counter bar workbench rug
## form (dress form) loom rack lamp. `use` on a seat says where it belongs ("table" | "hearth" | "bar" | "counter").
## Preload this script; no class_name.

const HOUSE := ["cottage", "two_room", "family_loft", "craftsman"]
const SHOP := ["general_store", "bakery", "tailor"]
const TAVERN := ["tavern_inn", "alehouse"]
const VARIANTS := {"house": HOUSE, "shop": SHOP, "tavern": TAVERN}

const SCENE_DIR := "res://scenes/interiors/modular/"
const CEIL := 2.8              # ground-floor ceiling / loft floor height
const LOFT_HEAD := 2.3         # headroom above a loft floor
const SPAWN_BACK := 1.1        # the player appears this far inside the door

## Footprints (x, z in the prop's own frame) used for placement checks and colliders.
const FOOT := {
	"bed": Vector2(1.0, 2.0), "cot": Vector2(0.8, 1.8), "table": Vector2(1.2, 0.8), "chair": Vector2(0.45, 0.45),
	"bench": Vector2(1.5, 0.4), "stool": Vector2(0.35, 0.35), "chest": Vector2(0.8, 0.5), "cupboard": Vector2(0.9, 0.45),
	"barrel": Vector2(0.55, 0.55), "crate": Vector2(0.6, 0.6), "hearth": Vector2(1.8, 0.7), "oven": Vector2(1.6, 0.9),
	"shelf": Vector2(1.4, 0.3), "counter": Vector2(2.4, 0.7), "bar": Vector2(3.0, 0.7), "workbench": Vector2(1.8, 0.8),
	"form": Vector2(0.5, 0.5), "loom": Vector2(1.1, 0.8), "rack": Vector2(1.2, 0.25), "rug": Vector2(2.0, 1.4), "lamp": Vector2(0.2, 0.2),
}
## Props that do not block movement (so they are left out of overlap checks).
const SOFT := ["rug", "lamp", "chair", "stool", "rack"]

static var _cache := {}


# ------------------------------------------------------------------ picking
## The layout id for a building: a stable hash of (category, building id), so the same house always gets the same
## interior in every session. `building_id` is any stable string ("b<x>_<z>" of the lot).
static func pick(category: String, building_id: String) -> String:
	var list: Array = VARIANTS.get(category, HOUSE)
	return String(list[absi(hash("%s|%s" % [category, building_id])) % list.size()])


static func category_of(id: String) -> String:
	for c: String in VARIANTS:
		if (VARIANTS[c] as Array).has(id):
			return c
	return ""


static func all_ids() -> Array:
	var out: Array = []
	for c: String in ["house", "shop", "tavern"]:
		out.append_array(VARIANTS[c])
	return out


static func scene_path(id: String) -> String:
	return "%s%s.tscn" % [SCENE_DIR, id]


## The layout dictionary for an id (cached; treat as read-only). Empty for an unknown id.
static func layout(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var l: Dictionary = {}
	match id:
		"cottage": l = _cottage()
		"two_room": l = _two_room()
		"family_loft": l = _family_loft()
		"craftsman": l = _craftsman()
		"general_store": l = _general_store()
		"bakery": l = _bakery()
		"tailor": l = _tailor()
		"tavern_inn": l = _tavern_inn()
		"alehouse": l = _alehouse()
	if not l.is_empty():
		_finish(l)
	_cache[id] = l
	return l


# ------------------------------------------------------------------ geometry helpers
static func spawn_point(l: Dictionary) -> Vector3:
	return Vector3(float(l["door_x"]), 0.0, float(l["d"]) * 0.5 - SPAWN_BACK)


## The exit trigger box: centre (local) and size. Deep enough to contain the spawn point (the playtest bug was a
## 1 m deep box centred on the door, 1.1 m from the spawn).
static func exit_box(l: Dictionary) -> AABB:
	var d := float(l["d"])
	var depth := 3.0
	var z1 := d * 0.5 + 0.25
	return AABB(Vector3(float(l["door_x"]) - 1.2, 0.0, z1 - depth), Vector3(2.4, 2.2, depth))


## Footprint rectangle (room frame) of a prop, rotated: the axis-aligned bounds of its turned footprint.
static func footprint(p: Dictionary) -> Rect2:
	var f: Vector2 = FOOT.get(String(p["t"]), Vector2(0.5, 0.5))
	if p.has("w"):
		f.x = float(p["w"])
	if p.has("dd"):
		f.y = float(p["dd"])
	var yaw := deg_to_rad(float(p.get("y", 0.0)))
	var hx := absf(cos(yaw)) * f.x * 0.5 + absf(sin(yaw)) * f.y * 0.5
	var hz := absf(sin(yaw)) * f.x * 0.5 + absf(cos(yaw)) * f.y * 0.5
	var c: Vector2 = p["p"]
	return Rect2(c - Vector2(hx, hz), Vector2(hx, hz) * 2.0)


## The area just inside the door that must stay free (the spawn and the exit trigger).
static func door_zone(l: Dictionary) -> Rect2:
	var d := float(l["d"])
	return Rect2(float(l["door_x"]) - 0.9, d * 0.5 - 1.7, 1.8, 1.7)


static func front(yaw_deg: float, dist: float) -> Vector2:
	var y := deg_to_rad(yaw_deg)
	return Vector2(sin(y), cos(y)) * dist


## Problems with a layout as strings (empty = fine): props outside the room, overlapping blocking props, anything in
## the door zone, a missing essential. Used by tests/test_buildings_live.gd.
static func problems(l: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var w := float(l["w"])
	var d := float(l["d"])
	var room := Rect2(-w * 0.5, -d * 0.5, w, d)
	var props: Array = l["props"]
	var zone := door_zone(l)
	for i in props.size():
		var p: Dictionary = props[i]
		var t := String(p["t"])
		var r := footprint(p)
		if int(p.get("level", 0)) == 0:
			if not room.grow(0.03).encloses(r):
				out.append("%s#%d (%s) leaves the room" % [t, i, l["id"]])
			if not SOFT.has(t) and zone.intersects(r):
				out.append("%s#%d (%s) blocks the door zone" % [t, i, l["id"]])
		if SOFT.has(t):
			continue
		for j in range(i + 1, props.size()):
			var q: Dictionary = props[j]
			if SOFT.has(String(q["t"])) or int(q.get("level", 0)) != int(p.get("level", 0)):
				continue
			if r.grow(-0.03).intersects(footprint(q)):
				out.append("%s#%d overlaps %s#%d (%s)" % [t, i, q["t"], j, l["id"]])
	return out


# ------------------------------------------------------------------ layout assembly
static func _base(id: String, cat: String, title: String, w: float, d: float, door_x: float) -> Dictionary:
	return {"id": id, "category": cat, "title": title, "w": w, "d": d, "h": CEIL, "door_x": door_x,
		"windows": [], "partitions": [], "loft": {}, "props": [], "npcs": [], "shop_kind": ""}


static func _add(l: Dictionary, t: String, x: float, z: float, yaw := 0.0, extra := {}) -> void:
	var p := {"t": t, "p": Vector2(x, z), "y": yaw}
	p.merge(extra, true)
	(l["props"] as Array).append(p)


static func _win(l: Dictionary, wall: String, at: float, w := 1.1, y0 := 1.0, y1 := 2.0) -> void:
	(l["windows"] as Array).append({"wall": wall, "at": at, "w": w, "y0": y0, "y1": y1})


static func _part(l: Dictionary, a: Vector2, b: Vector2, door_at := -1.0, door_w := 1.0, h := CEIL) -> void:
	var ops: Array = []
	if door_at >= 0.0:
		ops.append({"at": door_at, "w": door_w, "y0": 0.0, "y1": 2.1})
	(l["partitions"] as Array).append({"a": a, "b": b, "h": h, "openings": ops})


static func _loft(l: Dictionary, x0: float, x1: float, z0: float, z1: float, ladder_bottom: Vector3, ladder_top: Vector3) -> void:
	l["loft"] = {"x0": x0, "x1": x1, "z0": z0, "z1": z1, "y": CEIL, "ladder_bottom": ladder_bottom, "ladder_top": ladder_top}
	l["h"] = CEIL + LOFT_HEAD


## Derives the indoor waypoints (where household members stand, sit or lie) from the props, so a prop and the acts
## done at it can never disagree. `so` names the smart-object type the act could use (data/living_world/smart_objects.json).
static func _finish(l: Dictionary) -> void:
	var wp := {"bed": [], "table": [], "hearth": [], "counter": [], "seat": [], "bar": []}
	var loft_y := float(l["loft"].get("y", 0.0)) if not (l["loft"] as Dictionary).is_empty() else 0.0
	var seat_n := 0
	for p: Dictionary in l["props"]:
		var t := String(p["t"])
		var pos: Vector2 = p["p"]
		var yaw := float(p.get("y", 0.0))
		var lvl := int(p.get("level", 0))
		var y := loft_y if lvl > 0 else 0.0
		match t:
			"bed", "cot":
				(wp["bed"] as Array).append({"p": Vector3(pos.x, y + 0.42, pos.y), "y": yaw, "so": "bed", "level": lvl})
			"chair", "bench", "stool":
				var use := String(p.get("use", "table"))
				var at := Vector3(pos.x, y, pos.y)
				var e := {"p": at, "y": yaw, "so": "bench" if t == "bench" else ("tavern_table" if use == "bar" else "kitchen_table"), "level": lvl, "use": use}
				(wp["seat"] as Array).append(e)
				seat_n += 1
				match use:
					"hearth": (wp["hearth"] as Array).append(e)
					"bar": (wp["bar"] as Array).append(e)
					_: (wp["table"] as Array).append(e)
			"hearth", "oven":
				var f := front(yaw, 1.1)
				(wp["hearth"] as Array).append({"p": Vector3(pos.x + f.x, y, pos.y + f.y), "y": yaw + 180.0, "so": "cook_pot", "level": lvl, "use": "hearth"})
			"counter", "bar":
				var back := front(yaw, -0.95)
				(wp["counter"] as Array).append({"p": Vector3(pos.x + back.x, y, pos.y + back.y), "y": yaw, "so": "shop_counter" if t == "counter" else "bar_counter", "level": lvl, "use": "counter"})
	l["waypoints"] = wp


# ------------------------------------------------------------------ houses
static func _cottage() -> Dictionary:
	var l := _base("cottage", "house", "One-room cottage", 5.0, 4.4, 1.2)
	_win(l, "N", -1.0)
	_win(l, "W", 0.3)
	_win(l, "E", -0.8)
	_add(l, "hearth", 1.2, -1.8, 0)
	_add(l, "chair", 2.0, -0.7, 200, {"use": "hearth"})
	_add(l, "chair", 0.4, -0.6, 160, {"use": "hearth"})
	_add(l, "bed", -1.8, -1.05, 0)
	_add(l, "cot", -0.6, -1.2, 0)
	_add(l, "table", -1.3, 0.8, 0, {"w": 1.2, "dd": 0.8})
	_add(l, "chair", -1.3, 1.45, 180, {"use": "table"})
	_add(l, "chair", -1.3, 0.15, 0, {"use": "table"})
	_add(l, "stool", -0.45, 0.8, 270, {"use": "table"})
	_add(l, "chest", -2.05, 1.7, 90, {"slot": "chest"})
	_add(l, "cupboard", 2.2, -0.1, 270, {"slot": "cupboard"})
	_add(l, "rug", -0.4, 0.9, 0)
	_add(l, "lamp", -0.4, 0.8, 0)
	return l


static func _two_room() -> Dictionary:
	var l := _base("two_room", "house", "Two-room house", 7.0, 5.0, 2.0)
	_win(l, "N", 2.4)
	_win(l, "N", -2.2)
	_win(l, "E", -0.4)
	_win(l, "W", 0.0)
	_win(l, "S", -2.3)
	_part(l, Vector2(0.4, -2.5), Vector2(0.4, 2.5), 2.5, 1.0)   # doorway in the middle (z = 0.0)
	# kitchen / living room (east)
	_add(l, "hearth", 2.6, -2.1, 0)
	_add(l, "chair", 1.7, -1.0, 150, {"use": "hearth"})
	_add(l, "chair", 3.0, -1.0, 210, {"use": "hearth"})
	_add(l, "table", 2.8, 0.1, 0, {"w": 1.4, "dd": 0.9})
	_add(l, "chair", 2.8, 0.85, 180, {"use": "table"})
	_add(l, "chair", 2.8, -0.65, 0, {"use": "table"})
	_add(l, "bench", 1.6, -0.1, 90, {"use": "table"})
	_add(l, "cupboard", 3.28, 1.5, 270, {"slot": "cupboard"})
	_add(l, "shelf", 0.8, -2.2, 0)
	_add(l, "rug", 2.7, 0.1, 0, {"w": 1.6, "dd": 1.2})
	_add(l, "lamp", 2.8, 0.1, 0)
	# bedroom (west)
	_add(l, "bed", -2.7, -1.35, 0)
	_add(l, "bed", -1.4, -1.35, 0)
	_add(l, "chest", -3.0, 1.5, 90, {"slot": "chest"})
	_add(l, "cupboard", -1.0, 2.2, 180, {"slot": "wardrobe"})
	_add(l, "stool", -0.4, -0.4, 0, {"use": "table"})
	return l


static func _family_loft() -> Dictionary:
	var l := _base("family_loft", "house", "Family house with loft", 7.0, 6.0, -1.5)
	_loft(l, -3.4, 3.4, -2.9, -0.9, Vector3(-3.25, 0.0, -0.3), Vector3(-3.0, CEIL + 0.12, -1.2))
	_win(l, "N", 2.0, 1.1, 3.4, 4.3)
	_win(l, "N", -2.0, 1.1, 3.4, 4.3)
	_win(l, "E", 0.8)
	_win(l, "W", 1.6)
	_win(l, "S", 2.2)
	_add(l, "hearth", 2.2, -2.6, 0)
	_add(l, "chair", 1.2, -1.4, 160, {"use": "hearth"})
	_add(l, "chair", 3.1, -1.4, 200, {"use": "hearth"})
	_add(l, "table", 1.0, 0.6, 0, {"w": 1.8, "dd": 0.9})
	_add(l, "chair", 0.4, 1.35, 180, {"use": "table"})
	_add(l, "chair", 1.6, 1.35, 180, {"use": "table"})
	_add(l, "chair", 0.4, -0.15, 0, {"use": "table"})
	_add(l, "chair", 1.6, -0.15, 0, {"use": "table"})
	_add(l, "bench", 2.9, 0.6, 270, {"use": "table"})
	_add(l, "bed", -2.9, -1.9, 0)                        # parents, under the loft
	_add(l, "cupboard", 3.28, 1.8, 270, {"slot": "cupboard"})
	_add(l, "chest", 2.9, 2.5, 180, {"slot": "chest"})
	_add(l, "shelf", -0.5, -2.85, 0)
	_add(l, "rug", 1.0, 0.7, 0)
	_add(l, "lamp", 1.0, 0.6, 0)
	# loft: the children, and a trunk
	_add(l, "bed", -2.4, -1.9, 0, {"level": 1})
	_add(l, "bed", -1.2, -1.9, 0, {"level": 1})
	_add(l, "cot", 0.0, -1.9, 0, {"level": 1})
	_add(l, "chest", 2.8, -2.4, 270, {"level": 1, "slot": "loft_chest"})
	return l


static func _craftsman() -> Dictionary:
	var l := _base("craftsman", "house", "Craftsman's house", 8.0, 6.0, -2.0)
	_win(l, "N", -2.4)
	_win(l, "N", 2.4)
	_win(l, "W", 0.5)
	_win(l, "E", 0.5)
	_win(l, "S", 1.8)
	_part(l, Vector2(1.0, -3.0), Vector2(1.0, -0.4), -1.0, 1.0, 1.15)    # low screen round the workshop corner
	# living side (west)
	_add(l, "hearth", -2.6, -2.6, 0)
	_add(l, "chair", -3.4, -1.3, 150, {"use": "hearth"})
	_add(l, "chair", -1.8, -1.3, 210, {"use": "hearth"})
	_add(l, "table", -2.6, 0.5, 0, {"w": 1.6, "dd": 0.9})
	_add(l, "chair", -3.0, 1.25, 180, {"use": "table"})
	_add(l, "chair", -2.2, 1.25, 180, {"use": "table"})
	_add(l, "chair", -2.6, -0.25, 0, {"use": "table"})
	_add(l, "bed", -0.1, -1.9, 0)
	_add(l, "cot", -0.1, 1.2, 90)
	_add(l, "cupboard", -3.76, 1.7, 90, {"slot": "cupboard"})
	_add(l, "chest", 0.2, 2.5, 180, {"slot": "chest"})
	_add(l, "rug", -2.6, 0.5, 0)
	_add(l, "lamp", -2.6, 0.5, 0)
	# workshop corner (north-east)
	_add(l, "workbench", 2.9, -2.45, 0)
	_add(l, "rack", 2.3, -2.87, 0)
	_add(l, "crate", 3.55, -1.4, 0, {"slot": "planks"})
	_add(l, "barrel", 3.55, -0.7, 0, {"slot": "barrel"})
	_add(l, "stool", 2.9, -1.55, 0, {"use": "table"})
	return l


# ------------------------------------------------------------------ shops
static func _general_store() -> Dictionary:
	var l := _base("general_store", "shop", "General store", 6.5, 5.2, 1.6)
	l["shop_kind"] = "general_store"
	_win(l, "N", -1.5)
	_win(l, "W", 0.2)
	_win(l, "E", 0.4)
	_win(l, "S", -1.5)
	_add(l, "counter", -0.4, -0.4, 0, {"w": 3.0})
	l["npcs"].append({"role": "merchant", "look": "Merchant", "p": Vector2(-0.4, -1.3), "y": 0.0})
	_add(l, "shelf", -2.0, -2.35, 0)
	_add(l, "shelf", -0.4, -2.35, 0)
	_add(l, "shelf", 1.2, -2.35, 0)
	_add(l, "hearth", 2.55, -2.2, 0, {"w": 1.2})
	_add(l, "bed", 2.55, -0.6, 0)                           # the shopkeeper's cot behind the counter
	_add(l, "chest", -2.7, -1.2, 90, {"slot": "strongbox"})
	_add(l, "crate", -2.75, 0.4, 90, {"slot": "stock_crate"})
	_add(l, "barrel", -2.7, 1.2, 0, {"slot": "barrel"})
	_add(l, "bench", -1.7, 1.9, 0, {"use": "table"})
	_add(l, "chair", 2.5, 1.4, 160, {"use": "hearth"})
	_add(l, "chair", 0.4, -1.4, 0, {"use": "counter"})
	_add(l, "rug", 0.4, 1.0, 0)
	_add(l, "lamp", 0.2, 0.6, 0)
	return l


static func _bakery() -> Dictionary:
	var l := _base("bakery", "shop", "Bakery", 7.0, 6.0, 2.0)
	l["shop_kind"] = "baker"
	_win(l, "N", 1.8)
	_win(l, "W", -0.5)
	_win(l, "E", 0.0)
	_win(l, "S", -1.8)
	_add(l, "oven", -2.0, -2.5, 0, {"w": 2.2, "dd": 1.0})
	_add(l, "counter", 1.6, -0.6, 0, {"w": 2.0})
	l["npcs"].append({"role": "merchant", "look": "Merchant", "p": Vector2(1.6, -1.55), "y": 0.0})
	_add(l, "table", -1.2, -0.6, 0, {"w": 1.6, "dd": 0.9})
	_add(l, "stool", -1.2, 0.1, 180, {"use": "table"})
	_add(l, "stool", -1.2, -1.3, 0, {"use": "table"})
	_add(l, "shelf", 3.35, -2.0, 270)
	_add(l, "shelf", 0.2, -2.85, 0, {"w": 1.4})
	_add(l, "crate", -3.05, 0.6, 90, {"slot": "flour"})
	_add(l, "barrel", -3.05, 1.5, 0, {"slot": "barrel"})
	_add(l, "chest", -3.05, 2.4, 0, {"slot": "strongbox"})
	_add(l, "cot", 3.05, 0.4, 0)                             # baker's cot at the back of the shop floor
	_add(l, "bench", -0.4, 2.3, 0, {"use": "table"})
	_add(l, "chair", 3.0, -2.3, 180, {"use": "hearth"})
	_add(l, "rug", -0.5, 1.2, 0)
	_add(l, "lamp", 0.5, 0.2, 0)
	return l


static func _tailor() -> Dictionary:
	var l := _base("tailor", "shop", "Tailor's shop", 6.5, 5.5, -1.7)
	l["shop_kind"] = "tailor"
	_win(l, "N", 1.6)
	_win(l, "E", 0.0)
	_win(l, "W", 0.6)
	_win(l, "S", 1.9)
	_add(l, "counter", 1.4, 0.0, 0, {"w": 2.2})
	l["npcs"].append({"role": "merchant", "look": "Merchant", "p": Vector2(1.4, -0.95), "y": 0.0})
	_add(l, "loom", -2.4, -1.9, 0)
	_add(l, "shelf", 0.4, -2.55, 0)
	_add(l, "shelf", 2.0, -2.55, 0)
	_add(l, "form", -0.6, -0.6, 20)
	_add(l, "form", -1.4, 0.2, 340)
	_add(l, "table", -2.5, 0.3, 90, {"w": 1.4, "dd": 0.8})
	_add(l, "chair", -1.9, 0.3, 270, {"use": "table"})
	_add(l, "chair", -2.9, 0.3, 90, {"use": "table"})
	_add(l, "hearth", 2.9, -1.6, 270, {"w": 1.2})
	_add(l, "cot", 2.75, 1.7, 0)
	_add(l, "chest", -2.9, 2.0, 90, {"slot": "cloth_trunk"})
	_add(l, "cupboard", 0.5, 2.5, 180, {"slot": "cabinet"})
	_add(l, "chair", 2.2, -1.6, 90, {"use": "hearth"})
	_add(l, "rug", 0.4, 1.1, 0)
	_add(l, "lamp", 0.4, 0.8, 0)
	return l


# ------------------------------------------------------------------ taverns
static func _tavern_inn() -> Dictionary:
	var l := _base("tavern_inn", "tavern", "Tavern hall", 10.0, 8.0, 0.0)
	l["shop_kind"] = "tavern"
	_loft(l, 2.0, 4.9, -3.9, 0.3, Vector3(3.4, 0.0, 1.0), Vector3(3.4, CEIL + 0.12, 0.0))
	_win(l, "N", -3.2, 1.2, 1.0, 2.0)
	_win(l, "W", 2.0)
	_win(l, "W", -2.0)
	_win(l, "S", -3.0)
	_win(l, "S", 3.2)
	_win(l, "E", 2.2, 1.0, 3.4, 4.3)
	_add(l, "bar", -0.6, -2.8, 0, {"w": 3.6})
	l["npcs"].append({"role": "innkeeper", "look": "Merchant", "p": Vector2(0.1, -3.55), "y": 0.0})
	_add(l, "barrel", -2.9, -3.55, 0, {"slot": "ale_a"})
	_add(l, "barrel", -2.2, -3.55, 0, {"slot": "ale_b"})
	_add(l, "cupboard", -4.5, -3.0, 0, {"slot": "pantry"})
	_add(l, "hearth", -4.62, 0.4, 90, {"w": 2.2})
	_add(l, "chair", -3.5, -0.6, 270, {"use": "hearth"})
	_add(l, "chair", -3.5, 1.4, 270, {"use": "hearth"})
	_add(l, "table", -1.8, -0.5, 0, {"w": 2.4, "dd": 0.9})
	_add(l, "bench", -1.8, 0.3, 180, {"use": "bar", "w": 2.2})
	_add(l, "bench", -1.8, -1.3, 0, {"use": "bar", "w": 2.2})
	_add(l, "table", -2.4, 1.8, 0, {"w": 2.4, "dd": 0.9})
	_add(l, "bench", -2.4, 2.6, 180, {"use": "bar", "w": 2.2})
	_add(l, "bench", -2.4, 1.0, 0, {"use": "bar", "w": 2.2})
	_add(l, "stool", -0.3, -1.9, 0, {"use": "bar"})
	_add(l, "stool", 0.5, -1.9, 0, {"use": "bar"})
	_add(l, "crate", 4.6, 2.5, 180, {"slot": "cellar_crate"})
	_add(l, "rug", -1.8, 0.9, 0, {"w": 3.0, "dd": 2.6})
	_add(l, "lamp", -1.8, 0.7, 0)
	# guest rooms in the loft
	_add(l, "bed", 2.6, -3.0, 0, {"level": 1})
	_add(l, "bed", 3.8, -3.0, 0, {"level": 1})
	_add(l, "chest", 4.5, -1.2, 270, {"level": 1, "slot": "guest_chest"})
	return l


static func _alehouse() -> Dictionary:
	var l := _base("alehouse", "tavern", "Alehouse", 7.0, 6.0, 1.6)
	l["shop_kind"] = "tavern"
	_win(l, "N", 1.6)
	_win(l, "W", 0.5)
	_win(l, "S", -1.8)
	_win(l, "E", 1.6)
	_add(l, "bar", -1.7, -2.0, 0, {"w": 3.0})
	l["npcs"].append({"role": "innkeeper", "look": "Merchant", "p": Vector2(-1.7, -2.7), "y": 0.0})
	_add(l, "barrel", -3.0, -2.7, 0, {"slot": "ale_a"})
	_add(l, "barrel", -0.3, -2.7, 0, {"slot": "ale_b"})
	_add(l, "hearth", 3.15, -0.6, 270, {"w": 1.8})
	_add(l, "chair", 2.2, -1.5, 90, {"use": "hearth"})
	_add(l, "chair", 2.2, 0.3, 90, {"use": "hearth"})
	_add(l, "table", -1.9, 0.1, 0, {"w": 1.8, "dd": 0.85})
	_add(l, "bench", -1.9, 0.85, 180, {"use": "bar", "w": 1.7})
	_add(l, "bench", -1.9, -0.65, 0, {"use": "bar", "w": 1.7})
	_add(l, "table", -1.2, 1.9, 0, {"w": 1.2, "dd": 0.8})
	_add(l, "stool", -1.9, 1.9, 90, {"use": "bar"})
	_add(l, "stool", -0.5, 1.9, 270, {"use": "bar"})
	_add(l, "bed", 2.4, -2.45, 90)
	_add(l, "chest", -3.2, 1.0, 90, {"slot": "strongbox"})
	_add(l, "crate", -3.1, 2.3, 0, {"slot": "cellar_crate"})
	_add(l, "rug", -1.9, 0.9, 0)
	_add(l, "lamp", -1.9, 0.2, 0)
	return l
