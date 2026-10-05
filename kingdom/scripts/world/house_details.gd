extends RefCounted
## Procedural house detailing (docs/design/VERTICAL_SLICE.md P1 "20-30 modular detail props attached procedurally").
## Preload this script; no class_name.
##
## Every lot of a settlement plan gets 2-6 attachments chosen by DISTRICT, WEALTH and the lot's own seed, so two houses
## of the same model read differently: a window box here, a patched roof there, firewood, a shop sign, a laundry line.
## Each attachment is a DETAIL KEY (`DEFS`). A key resolves to a mesh in this order:
##   1. res://assets/generated/details/<key>.glb   <- the hook: drop a better model here and it replaces the stand-in
##   2. the stand-in named in DEFS: an existing building/prop asset, or a procedural mesh built below.
## Hook GLB convention: origin on the ground (floor items) or on the wall plane at the middle of the item (wall items),
## +Z out of the wall / toward the street, +Y up, real metres (see the "Detail prop keys" section of VERTICAL_SLICE.md).
## Meshes are batched with SettlementBuilder._multimesh_cells (one MultiMesh per key per 40 m cell), decals go through
## TownDecals; nothing runs per frame.

const StyleG := preload("res://scripts/style_g.gd")
const Districts := preload("res://scripts/world/districts.gd")
const BuildingProfiles := preload("res://scripts/world/building_profiles.gd")
const DETAIL_DIR := "res://assets/generated/details/"
const GEN := "res://assets/generated/"
const CELL := 40.0

## Slots on a lot, each takes at most one attachment: wall_a / wall_b (left / right of the door on the front wall),
## door_a / door_b (floor beside the door), side (a side wall), yard (ground beside the house), post (a lamp post at the
## kerb), roof (a decal on the roof).
const SLOTS := ["wall_a", "wall_b", "door_a", "door_b", "side", "yard", "post", "roof"]

## key -> {slots, mesh (building key | "gen:<file>" | "proc:<name>" | "decal:<kind>"), scale, rich (-1 poor .. +1 rich
## taste), d (weight by district; unlisted = 0.5), y (wall height of the item's origin), r (ground radius)}.
const DEFS := {
	"chimney_stack": {"slots": ["side"], "mesh": "proc:chimney", "rich": 0.2, "d": {"craft": 1.4, "poor": 0.9, "market": 0.7, "admin": 0.6, "inn": 1.1, "military": 0.8}, "r": 0.7},
	"flower_box": {"slots": ["wall_a", "wall_b"], "mesh": "planter_box", "scale": 0.9, "rich": 0.8, "y": 1.0, "d": {"market": 1.3, "admin": 1.2, "inn": 1.2, "craft": 0.5, "poor": 0.3, "military": 0.2}},
	"flower_planter": {"slots": ["door_a", "door_b"], "mesh": "flower_planter", "rich": 0.7, "d": {"market": 1.0, "admin": 1.2, "inn": 1.0, "craft": 0.3, "poor": 0.4, "military": 0.2}, "r": 0.6},
	"firewood_stack": {"slots": ["side", "door_a", "door_b", "yard"], "mesh": "woodpile", "scale": 0.62, "rich": -0.6, "d": {"poor": 1.5, "craft": 1.4, "inn": 0.9, "military": 0.6, "market": 0.3, "admin": 0.2}, "r": 1.0},
	"shop_sign": {"slots": ["wall_a", "wall_b"], "mesh": "shop_sign", "scale": 0.85, "rich": 0.3, "y": 2.35, "d": {"market": 2.2, "craft": 1.3, "inn": 1.2, "admin": 0.2, "poor": 0.1, "military": 0.1}},
	"damaged_plaster": {"slots": ["wall_a", "wall_b"], "mesh": "proc:plaster_patch", "rich": -0.9, "y": 1.7, "d": {"poor": 1.8, "craft": 0.9, "military": 0.8, "inn": 0.5, "market": 0.3, "admin": 0.1}},
	"shutters_open": {"slots": ["wall_a", "wall_b"], "mesh": "proc:shutters_open", "rich": 0.5, "y": 1.6, "d": {"market": 1.0, "admin": 1.0, "inn": 1.0, "craft": 0.8, "poor": 0.7, "military": 0.6}},
	"shutters_closed": {"slots": ["wall_a", "wall_b"], "mesh": "proc:shutters_closed", "rich": -0.2, "y": 1.6, "d": {"poor": 1.0, "craft": 0.9, "military": 1.0, "market": 0.5, "admin": 0.5, "inn": 0.5}},
	"shutters_painted": {"slots": ["wall_a", "wall_b"], "mesh": "proc:shutters_painted", "rich": 0.6, "y": 1.6, "d": {"market": 1.1, "admin": 0.9, "inn": 1.2, "craft": 0.4, "poor": 0.2, "military": 0.2}},
	"barrel_pair": {"slots": ["door_a", "door_b", "side"], "mesh": "barrel_cluster", "scale": 0.8, "rich": -0.2, "d": {"inn": 1.4, "craft": 1.2, "market": 1.0, "poor": 0.9, "military": 0.8, "admin": 0.3}, "r": 0.9},
	"rain_barrel": {"slots": ["side", "door_a", "door_b"], "mesh": "barrel", "rich": -0.3, "d": {"poor": 1.4, "craft": 1.0, "inn": 0.9, "market": 0.6, "military": 0.6, "admin": 0.3}, "r": 0.4},
	"laundry_line": {"slots": ["yard"], "mesh": "kit:laundry_line", "scale": 1.0, "rich": -0.8, "d": {"poor": 2.2, "craft": 0.6, "inn": 0.4, "military": 0.4, "market": 0.1, "admin": 0.0}, "r": 2.3},
	"fence_run": {"slots": ["yard", "door_a", "door_b"], "mesh": "fence", "rich": -0.1, "d": {"poor": 1.5, "craft": 0.9, "inn": 0.9, "military": 0.5, "market": 0.3, "admin": 0.3}, "r": 1.5},
	"hanging_lantern": {"slots": ["wall_a", "wall_b"], "mesh": "mf_lantern_wall_scroll", "rich": 0.5, "y": 2.15, "d": {"market": 1.2, "admin": 1.4, "inn": 1.5, "military": 1.0, "craft": 0.5, "poor": 0.2}},
	"bench": {"slots": ["door_a", "door_b"], "mesh": "bench", "rich": 0.1, "d": {"inn": 1.5, "admin": 1.2, "market": 0.9, "poor": 0.7, "craft": 0.6, "military": 0.6}, "r": 0.9},
	"hand_cart": {"slots": ["yard", "door_a", "door_b"], "mesh": "hand_cart", "rich": -0.3, "d": {"market": 1.3, "craft": 1.1, "poor": 1.0, "inn": 0.9, "military": 0.3, "admin": 0.1}, "r": 1.1},
	"market_cart": {"slots": ["yard"], "mesh": "cart", "rich": 0.0, "d": {"market": 1.2, "inn": 1.4, "craft": 0.6, "poor": 0.3, "military": 0.2, "admin": 0.1}, "r": 2.0},
	"lamp_post": {"slots": ["post"], "mesh": "lamp_post", "rich": 0.8, "d": {"admin": 1.5, "market": 1.2, "inn": 1.2, "military": 0.9, "craft": 0.4, "poor": 0.1}, "r": 0.5},
	"crate_stack": {"slots": ["door_a", "door_b", "side"], "mesh": "crate_stack", "rich": -0.1, "d": {"market": 1.5, "inn": 1.1, "craft": 1.2, "military": 0.9, "poor": 0.7, "admin": 0.3}, "r": 0.9},
	"sack_pile": {"slots": ["door_a", "door_b", "side"], "mesh": "sack_pile", "scale": 0.8, "rich": -0.2, "d": {"market": 1.3, "inn": 0.9, "craft": 1.0, "poor": 0.8, "military": 0.6, "admin": 0.2}, "r": 0.9},
	"hay_bale": {"slots": ["yard", "side"], "mesh": "hay", "scale": 0.8, "rich": -0.5, "d": {"inn": 1.8, "poor": 1.0, "craft": 0.6, "military": 0.8, "market": 0.2, "admin": 0.0}, "r": 1.0},
	"striped_awning": {"slots": ["wall_a", "wall_b"], "mesh": "proc:awning", "rich": 0.3, "y": 2.35, "d": {"market": 2.0, "inn": 0.9, "craft": 0.3, "admin": 0.2, "poor": 0.0, "military": 0.0}},
	"wall_banner": {"slots": ["wall_a", "wall_b"], "mesh": "wall_banner", "scale": 0.8, "rich": 0.9, "y": 0.5, "d": {"admin": 2.0, "military": 1.6, "market": 0.7, "inn": 0.6, "craft": 0.1, "poor": 0.0}},
	"drying_rack": {"slots": ["yard"], "mesh": "proc:drying_rack", "rich": -0.6, "d": {"craft": 1.8, "poor": 1.0, "military": 0.3, "inn": 0.2, "market": 0.1, "admin": 0.0}, "r": 1.4},
	"weapon_rack": {"slots": ["door_a", "door_b", "yard"], "mesh": "weapon_rack", "rich": 0.0, "d": {"military": 2.4, "craft": 0.5, "admin": 0.4, "inn": 0.1, "market": 0.0, "poor": 0.0}, "r": 1.3},
	"anvil": {"slots": ["door_a", "door_b", "yard"], "mesh": "anvil_stump", "rich": -0.1, "d": {"craft": 2.2, "military": 0.3, "poor": 0.1, "market": 0.1, "inn": 0.0, "admin": 0.0}, "r": 0.7},
	"roof_patch": {"slots": ["roof"], "mesh": "decal:plaster", "rich": -0.9, "d": {"poor": 2.4, "craft": 0.8, "military": 0.6, "inn": 0.4, "market": 0.15, "admin": 0.05}},
	"flower_bed": {"slots": ["yard", "door_a", "door_b"], "mesh": "flower_bed", "scale": 0.8, "rich": 0.8, "d": {"admin": 1.3, "market": 1.0, "inn": 1.0, "craft": 0.2, "poor": 0.15, "military": 0.0}, "r": 1.2},
	"water_trough": {"slots": ["yard", "door_a", "door_b"], "mesh": "water_trough", "rich": -0.1, "d": {"inn": 2.0, "craft": 0.8, "poor": 0.6, "military": 0.8, "market": 0.3, "admin": 0.1}, "r": 1.3},
	# Meshy free pack (Assets.BUILDINGS "mf_*": native size, origin at the base): a lion shop sign for rich market frontages (DEFS stays at 30 keys).
	"shop_sign_lion": {"slots": ["wall_a", "wall_b"], "mesh": "mf_sign_shop_lion", "rich": 0.5, "y": 1.45, "d": {"market": 1.2, "inn": 1.0, "admin": 0.4, "craft": 0.3, "poor": 0.05, "military": 0.05}},
}

## Order matters: the draw order of DEFS keys is the iteration order (stable), never Dictionary hashing.
static var _keys: Array = DEFS.keys().filter(func(k: String) -> bool: return not (k.begins_with("kit_") and OS.get_cmdline_user_args().has("--medievaloff")))
static var _mesh_cache: Dictionary = {}


## Detail key list (QA, docs, tests).
static func keys() -> Array:
	return _keys


## Mesh for a detail key: the hook GLB if the local session added one, else the stand-in. null for decal keys.
static func mesh_for(key: String) -> Mesh:
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var def: Dictionary = DEFS[key]
	var m: Mesh = null
	var hook := DETAIL_DIR + key + ".glb"
	if ResourceLoader.exists(hook):
		m = Assets.merged_mesh(hook)
	if m == null:
		var spec := String(def["mesh"])
		if spec.begins_with("proc:"):
			m = _proc(spec.substr(5))
		elif spec.begins_with("decal:"):
			m = null
		elif spec.begins_with("kit:"):
			m = load("res://scripts/build/kit_meshes.gd").mesh(spec.substr(4))      # shared textured kit materials
		elif spec.begins_with("gen:"):
			m = Assets.merged_mesh(GEN + spec.substr(4) + ".glb")
		else:
			m = Assets.building_mesh(spec)
	_mesh_cache[key] = m
	return m


## Is this key a decal (no mesh)?
static func is_decal(key: String) -> bool:
	return String(DEFS[key]["mesh"]).begins_with("decal:") and not ResourceLoader.exists(DETAIL_DIR + key + ".glb")


## Pick the attachments of one lot: Array of {key, slot, x, z, y, yaw, scale} in LOT-LOCAL metres (x side, z toward the
## street measured from the lot centre, y above the lot's ground, yaw relative to the lot).
static func choose(lot: Dictionary, size: Vector3, rng: RandomNumberGenerator) -> Array:
	var asset := String(lot["asset"])
	var dk := String(lot.get("district", "market"))
	var wealth := float(lot.get("wealth", 0.5))
	var tone := wealth * 2.0 - 1.0
	var hero := asset in ["inn", "blacksmith", "adventurer_guild", "healer_house", "mhouse_manor"]
	var front := size.z * (BuildingProfiles.HERO_WALL if BuildingProfiles.HERO.has(asset) else BuildingProfiles.HOUSE_WALL)
	var door_x := BuildingProfiles.door_local(asset, size).x
	var n := 2 + int(round(wealth * 2.0)) + rng.randi_range(0, 2)
	if hero:
		n += 1
	var used := {}
	var out: Array = []
	var forced: Array = _forced(asset, lot)
	for key: String in forced:
		_try_attach(out, used, key, dk, size, front, door_x, rng, true)
	var guard := 0
	while out.size() < n and guard < 40:
		guard += 1
		# Weighted pick over every key that still has a free slot.
		var total := 0.0
		var weights: Array = []
		for key: String in _keys:
			var w := _weight(key, dk, tone)
			weights.append(w)
			total += w
		var roll := rng.randf() * total
		var chosen := ""
		for i in _keys.size():
			roll -= float(weights[i])
			if roll <= 0.0:
				chosen = _keys[i]
				break
		if chosen != "":
			_try_attach(out, used, chosen, dk, size, front, door_x, rng, false)
	return out


## Attachments a building always has.
static func _forced(asset: String, lot: Dictionary) -> Array:
	match asset:
		"inn":
			return ["shop_sign", "hanging_lantern", "water_trough"]
		"blacksmith":
			return ["anvil", "chimney_stack", "firewood_stack"]
		"mhouse_manor":
			return ["wall_banner", "lamp_post"]
		"adventurer_guild":
			return ["wall_banner"]
		"healer_house":
			return ["flower_box", "flower_planter"]
	return []


static func _weight(key: String, dk: String, tone: float) -> float:
	var def: Dictionary = DEFS[key]
	var base: float = (def["d"] as Dictionary).get(dk, 0.5)
	return maxf(0.02, base * (1.0 + float(def["rich"]) * tone * 0.9))


static func _try_attach(out: Array, used: Dictionary, key: String, dk: String, size: Vector3, front: float, door_x: float,
		rng: RandomNumberGenerator, force: bool) -> void:
	var def: Dictionary = DEFS[key]
	# One of each key per lot, and one thing per slot.
	for e: Dictionary in out:
		if e["key"] == key:
			return
	var slots: Array = (def["slots"] as Array).duplicate()
	# Shuffle the slot order deterministically.
	for i in range(slots.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = slots[i]
		slots[i] = slots[j]
		slots[j] = t
	for slot: String in slots:
		if used.has(slot):
			continue
		var e := _place(key, slot, size, front, door_x, rng)
		used[slot] = true
		out.append(e)
		return


## Lot-local placement of `key` in `slot`. Left/right is random per lot (sgn), so facades mirror.
static func _place(key: String, slot: String, size: Vector3, front: float, door_x: float, rng: RandomNumberGenerator) -> Dictionary:
	var def: Dictionary = DEFS[key]
	var sgn := 1.0 if rng.randf() < 0.5 else -1.0
	var sc := float(def.get("scale", 1.0)) * rng.randf_range(0.92, 1.08)
	var e := {"key": key, "slot": slot, "x": 0.0, "z": 0.0, "y": float(def.get("y", 0.0)), "yaw": 0.0, "scale": sc,
		"r": float(def.get("r", 0.6))}
	var hx := size.x * 0.5
	match slot:
		"wall_a", "wall_b":
			var side := -1.0 if slot == "wall_a" else 1.0
			# Windows sit about a third of the way out from the door; clear of the door itself.
			var x := door_x + side * clampf(size.x * 0.27, 1.5, 2.6)
			e["x"] = clampf(x, -hx * 0.78, hx * 0.78)
			e["z"] = front + 0.04
			e["wall"] = true
		"door_a", "door_b":
			var side2 := -1.0 if slot == "door_a" else 1.0
			e["x"] = door_x + side2 * rng.randf_range(2.1, 2.7)
			e["z"] = front + 0.9 + rng.randf_range(0.0, 0.4)
			e["yaw"] = rng.randf_range(-0.25, 0.25)
		"side":
			# Against a side wall (chimney, rain barrel, firewood).
			e["x"] = sgn * (hx + (0.3 if key == "chimney_stack" else 0.7))
			e["z"] = rng.randf_range(-0.25, 0.25) * size.z
			e["yaw"] = PI * 0.5 * sgn
			e["wall"] = key == "chimney_stack"
		"yard":
			e["x"] = sgn * (hx + float(def.get("r", 1.0)) + 0.9 + rng.randf_range(0.0, 0.8))
			e["z"] = rng.randf_range(-0.3, 0.45) * size.z
			e["yaw"] = PI * 0.5 + rng.randf_range(-0.3, 0.3) if key in ["laundry_line", "fence_run", "drying_rack"] else rng.randf() * TAU
		"post":
			e["x"] = door_x + sgn * 3.4
			e["z"] = front + 2.6
		"roof":
			e["x"] = rng.randf_range(-0.22, 0.22) * size.x
			e["z"] = rng.randf_range(-0.1, 0.25) * size.z
			e["y"] = size.y * 0.78
	return e


# --- Procedural stand-ins -------------------------------------------------------------------------------------------

static var _mat: Material


## Style G role "timber" with sRGB vertex colours (the stand-ins bake their own colours and town tints).
static func _material() -> Material:
	if _mat == null:
		_mat = StyleG.vertex_color_material("timber", true)
	return _mat


static func _box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color) -> void:
	var h := s * 0.5
	var v := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	# Quads (counter-clockwise from outside): -z, +z, -x, +x, -y, +y
	var faces := [[0, 3, 2, 1], [4, 5, 6, 7], [0, 4, 7, 3], [1, 2, 6, 5], [0, 1, 5, 4], [3, 7, 6, 2]]
	for f: Array in faces:
		var shade := 1.0
		# A touch of per-face shading baked into the colour, so flat boxes still read as boxes under flat lighting.
		if f[0] == 0 and f[1] == 4:
			shade = 0.86
		elif f[0] == 1:
			shade = 0.92
		elif f[0] == 0 and f[1] == 1:
			shade = 0.7
		var cc := Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(cc)
			st.add_vertex(c + v[f[idx]])


static func _finish(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	var m := st.commit()
	m.surface_set_material(0, _material())
	return m


## Stand-in meshes. Origin: ground for floor items, wall plane for wall items (see the hook convention above).
static func _proc(name: String) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone := Color(0.62, 0.54, 0.44)
	var dark := Color(0.30, 0.20, 0.12)
	var wood := Color(0.50, 0.34, 0.20)
	match name:
		"chimney":
			# A stone chimney breast against the side wall: base, shaft, cap with a flue pot. Local +Z is out of the wall.
			_box(st, Vector3(0, 1.4, 0.4), Vector3(1.1, 2.8, 0.8), stone)
			_box(st, Vector3(0, 3.35, 0.4), Vector3(0.8, 1.2, 0.7), stone * 0.95)
			_box(st, Vector3(0, 4.05, 0.4), Vector3(1.0, 0.22, 0.9), stone * 0.8)
			_box(st, Vector3(0, 4.3, 0.4), Vector3(0.38, 0.4, 0.38), Color(0.62, 0.34, 0.22))
		"shutters_open":
			# Two leaves folded back against the wall either side of a (virtual) window 1.1 m wide.
			for sx: float in [-1.0, 1.0]:
				_box(st, Vector3(sx * 0.82, 0.0, 0.05), Vector3(0.42, 1.2, 0.07), Color(0.34, 0.5, 0.36))
				_box(st, Vector3(sx * 0.82, 0.0, 0.1), Vector3(0.3, 0.07, 0.03), Color(0.2, 0.3, 0.22))
		"shutters_closed":
			_box(st, Vector3(0, 0.0, 0.05), Vector3(1.15, 1.2, 0.07), Color(0.42, 0.28, 0.17))
			for i in 5:
				_box(st, Vector3(0, -0.45 + i * 0.22, 0.1), Vector3(1.08, 0.05, 0.03), Color(0.3, 0.19, 0.11))
		"shutters_painted":
			for sx: float in [-1.0, 1.0]:
				_box(st, Vector3(sx * 0.82, 0.0, 0.05), Vector3(0.42, 1.2, 0.07), Color(0.26, 0.42, 0.7))
				_box(st, Vector3(sx * 0.82, 0.0, 0.1), Vector3(0.3, 0.07, 0.03), Color(0.95, 0.85, 0.55))
			_box(st, Vector3(0, -0.66, 0.06), Vector3(1.3, 0.1, 0.12), wood)
		"plaster_patch":
			# Flaking plaster: a pale ragged patch with the lath and old brick showing through, a hand's breadth proud of the wall.
			_box(st, Vector3(0.0, 0.0, 0.02), Vector3(1.5, 1.1, 0.04), Color(0.6, 0.45, 0.32))
			_box(st, Vector3(-0.15, 0.1, 0.045), Vector3(1.0, 0.72, 0.03), Color(0.62, 0.36, 0.26))
			_box(st, Vector3(0.45, -0.28, 0.05), Vector3(0.5, 0.4, 0.03), Color(0.9, 0.84, 0.7))
			_box(st, Vector3(-0.5, 0.3, 0.055), Vector3(0.42, 0.28, 0.03), Color(0.46, 0.3, 0.2))
			_box(st, Vector3(0.1, -0.1, 0.06), Vector3(0.36, 0.5, 0.025), Color(0.7, 0.52, 0.34))
		"lantern":
			# A bracket arm and a little lantern cage with a warm glass pane.
			_box(st, Vector3(0.0, 0.18, 0.28), Vector3(0.07, 0.07, 0.56), dark)
			_box(st, Vector3(0.0, 0.0, 0.0), Vector3(0.1, 0.5, 0.08), dark)
			_box(st, Vector3(0.0, -0.1, 0.56), Vector3(0.26, 0.3, 0.26), Color(1.0, 0.8, 0.42))
			_box(st, Vector3(0.0, 0.08, 0.56), Vector3(0.32, 0.07, 0.32), dark)
			_box(st, Vector3(0.0, -0.27, 0.56), Vector3(0.3, 0.05, 0.3), dark)
		"awning":
			# A striped canopy over a shop window: red and cream slats sloping out from the wall.
			for i in 7:
				var col := Color(0.78, 0.18, 0.16) if i % 2 == 0 else Color(0.95, 0.9, 0.78)
				_box(st, Vector3(-1.05 + i * 0.35, 0.0, 0.5), Vector3(0.35, 0.05, 1.0), col)
			_box(st, Vector3(0, -0.12, 1.0), Vector3(2.45, 0.22, 0.05), Color(0.78, 0.18, 0.16))
		"drying_rack":
			# Two posts and a rail with hides or cloth hung over it.
			for sx: float in [-1.15, 1.15]:
				_box(st, Vector3(sx, 0.85, 0.0), Vector3(0.1, 1.7, 0.1), wood)
			_box(st, Vector3(0, 1.65, 0.0), Vector3(2.4, 0.08, 0.08), wood)
			for i in 4:
				var cc: Color = [Color(0.62, 0.42, 0.26), Color(0.78, 0.7, 0.55), Color(0.5, 0.33, 0.2), Color(0.7, 0.55, 0.38)][i]
				_box(st, Vector3(-0.85 + i * 0.58, 1.15, 0.0), Vector3(0.46, 0.95, 0.05), cc)
	return _finish(st)
