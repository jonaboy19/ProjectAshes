extends RefCounted
## Front doors, interiors and compound colliders of the lot buildings.
## One source of truth for "where is this building's door" (CityPlanner's
## footpaths, VillageServices' keepers, SettlementBuilder's InteriorDoor) and
## for its collision profile (docs/concepts/COLLISION_FACADE_REVIEW.md).
##
## Lot-local space: the fitted mesh is centred on x/z with its base at y = 0 and
## faces +Z (the street), so the front wall is at +size.z / 2 and local +X is the
## lot's side vector (cos yaw, -sin yaw). Preload this script; no class_name.

## Fitted mesh sizes (Assets.BUILDINGS fit, measured from the LOD0 AABBs) for
## callers that never load the meshes (city planning, services). The builder
## passes the real footprint instead.
const SIZE := {
	"inn": Vector3(13.5, 7.98, 12.48),
	"blacksmith": Vector3(11.0, 6.63, 9.18),
	"adventurer_guild": Vector3(16.0, 9.08, 9.52),
	"healer_house": Vector3(8.83, 6.82, 9.5),
	"mhouse_peasant_a": Vector3(7.5, 7.02, 6.69),
	"mhouse_peasant_b": Vector3(8.0, 8.64, 6.92),
	"mhouse_family": Vector3(7.67, 9.06, 9.0),
	"mhouse_trader": Vector3(8.5, 9.77, 7.97),
	"mhouse_manor": Vector3(10.0, 8.62, 6.33),
	"house_town_a": Vector3(7.75, 14.22, 10.49),
	"house_town_b": Vector3(7.74, 14.43, 10.51),
	"house_town_c": Vector3(7.74, 14.28, 10.5),
	"house_town_d": Vector3(7.74, 14.23, 10.51),
}
## Blender village houses (house_1..16) are 5.6-7.6 m deep; this is their typical size.
const HOUSE_SIZE := Vector3(6.7, 7.5, 6.0)

## Hero buildings, read off the facade review (asset-local, metres):
## door_x = centre of the entrance along local X; porch = depth of the open,
## roofed ground in front of the door wall; porch_w = its width; posts = porch
## posts at its outer corners. The entrance wall sits `porch` behind the front.
const HERO := {
	# Recessed entrance under the central gable, slightly left of centre.
	"inn": {"door_x": -0.3, "porch": 1.6, "porch_w": 4.2, "posts": true},
	# Open forge lean-to on the right (+X) half; the gabled left half is solid.
	"blacksmith": {"door_x": 2.6, "porch": 2.2, "porch_w": 3.2, "posts": true},
	# Double door with steps between two posts, left of centre.
	"adventurer_guild": {"door_x": -1.0, "porch": 1.2, "porch_w": 3.2, "posts": true},
	# Awning-covered porch on the left front.
	"healer_house": {"door_x": -0.7, "porch": 2.0, "porch_w": 4.4, "posts": true},
}

const INTERIORS := {
	"inn": "res://scenes/interiors/inn_interior.tscn",
	"blacksmith": "res://scenes/interiors/blacksmith_interior.tscn",
	"adventurer_guild": "res://scenes/interiors/guild_interior.tscn",
	"healer_house": "res://scenes/interiors/healer_interior.tscn",
}
const HOUSE_INTERIOR := "res://scenes/interiors/house_interior.tscn"
const Layouts := preload("res://scripts/interiors/interior_layouts.gd")
## Building assets whose interior is a shop (the trader's house is a shop front), and the ones that are taverns.
const SHOP_BUILDINGS := ["mhouse_trader"]
const TAVERN_BUILDINGS := ["inn"]
const PROMPTS := {"inn": "Enter the inn", "blacksmith": "Enter the smithy",
	"adventurer_guild": "Enter the guild hall", "healer_house": "Enter the healer's house"}

## Walls stop this far inside the fitted AABB (eaves, trim and props overhang).
const HERO_WALL := 0.46
const HOUSE_WALL := 0.43
## Height where porch roofs and eaves start (clear of the player's head and jumps).
const EAVE_H := 2.7
## The door trigger: 2 x 2.2 x 2 m box in front of the entrance (README).
const DOOR_DEPTH := 2.0

static var _shapes := {}      # "asset|size" -> Array of [BoxShape3D, Vector3 centre]
static var _door_shape: BoxShape3D


static func is_house(asset: String) -> bool:
	return asset.begins_with("house_") or asset.begins_with("mhouse_")


static func is_enterable(asset: String) -> bool:
	return INTERIORS.has(asset) or is_house(asset)


## The interior scene of a building asset. With a stable `building_id` (see `building_id`) houses, shops and the
## inn get a generated layout variant (scripts/interiors/interior_layouts.gd) picked from that id, so the same
## building always has the same interior; without one (or for the smithy, guild hall and healer) the hand-made
## scene is used.
static func interior_scene(asset: String, building_id := "") -> String:
	if building_id != "":
		var layout := layout_for(asset, building_id)
		if layout != "":
			return Layouts.scene_path(layout)
	return INTERIORS.get(asset, HOUSE_INTERIOR if is_house(asset) else "")


## "house" | "shop" | "tavern" for assets that use generated layouts, "" for the rest.
static func layout_category(asset: String) -> String:
	if SHOP_BUILDINGS.has(asset):
		return "shop"
	if TAVERN_BUILDINGS.has(asset):
		return "tavern"
	if is_house(asset):
		return "house"
	return ""


## The generated layout id of a building ("" when it keeps its hand-made interior).
static func layout_for(asset: String, building_id: String) -> String:
	var cat := layout_category(asset)
	return Layouts.pick(cat, building_id) if cat != "" and building_id != "" else ""


## Stable id of a lot from its plan position: the same plan always gives the same ids.
static func building_id(lot_pos: Vector2) -> String:
	return "b%d_%d" % [roundi(lot_pos.x), roundi(lot_pos.y)]


static func prompt(asset: String) -> String:
	return PROMPTS.get(asset, "Enter the house")


static func size_of(asset: String) -> Vector3:
	return SIZE.get(asset, HOUSE_SIZE)


## Lot-local centre of the door trigger, on the ground just outside the
## entrance (the threshold players and footpaths use). `size` = fitted mesh
## size; Vector3.ZERO uses the measured table.
static func door_local(asset: String, size := Vector3.ZERO) -> Vector3:
	if size == Vector3.ZERO:
		size = size_of(asset)
	if HERO.has(asset):
		var p: Dictionary = HERO[asset]
		var x0 := _porch_x0(p, size)
		var x1 := _porch_x1(p, size)
		var door_x := clampf(float(p["door_x"]), x0 + 0.9, x1 - 0.9)
		return Vector3(door_x, 0.0, size.z * HERO_WALL - float(p["porch"]) + DOOR_DEPTH * 0.5)
	var wall := HOUSE_WALL if is_house(asset) else HERO_WALL
	return Vector3(0.0, 0.0, size.z * wall + DOOR_DEPTH * 0.5)


## Door threshold in world XZ for a planned lot {asset, pos, yaw}.
static func door_point(lot: Dictionary, size := Vector3.ZERO) -> Vector2:
	var d := door_local(String(lot["asset"]), size)
	return _to_world(lot, d.x, d.z)


## A spot beside the entrance, off the door line and out of the porch, for a
## keeper who greets people outside. side = +1 / -1 picks the lot side.
static func keeper_point(lot: Dictionary, side := 1.0) -> Vector2:
	var asset := String(lot["asset"])
	var size := size_of(asset)
	var d := door_local(asset, size)
	var front := size.z * (HERO_WALL if HERO.has(asset) else HOUSE_WALL)
	return _to_world(lot, d.x + side * 3.6, front + 1.3)


static func _to_world(lot: Dictionary, x: float, z: float) -> Vector2:
	var yaw: float = lot["yaw"]
	var fwd := Vector2(sin(yaw), cos(yaw))
	var side := Vector2(fwd.y, -fwd.x)
	return (lot["pos"] as Vector2) + side * x + fwd * z


static func _porch_x0(p: Dictionary, size: Vector3) -> float:
	var hw := size.x * HERO_WALL
	return clampf(float(p["door_x"]) - float(p["porch_w"]) * 0.5, -hw, hw - 2.0)


static func _porch_x1(p: Dictionary, size: Vector3) -> float:
	var hw := size.x * HERO_WALL
	return clampf(float(p["door_x"]) + float(p["porch_w"]) * 0.5, _porch_x0(p, size) + 2.0, hw)


## Compound collider for one lot: a StaticBody3D in lot-local space (the
## caller sets its transform to the lot's). Box shapes are shared by every lot
## of the same asset and size.
static func make_body(asset: String, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	for e: Array in _profile(asset, size):
		var cs := CollisionShape3D.new()
		cs.shape = e[0]
		cs.position = e[1]
		body.add_child(cs)
	return body


## Shared 2 x 2.2 x 2 m door trigger shape.
static func door_shape() -> BoxShape3D:
	if _door_shape == null:
		_door_shape = BoxShape3D.new()
		_door_shape.size = Vector3(2.0, 2.2, DOOR_DEPTH)
	return _door_shape


## [[BoxShape3D, centre]] per asset:
## - hero buildings: main body up to the entrance wall, solid wall strips either
##   side of the porch, two porch posts, and the porch roof / upper storey above
##   EAVE_H, so the porch and door gap stay walkable (4-6 boxes);
## - houses: walls inset from the eaves plus an eave box above head height (2);
## - anything else: the old single 92 % box.
static func _profile(asset: String, size: Vector3) -> Array:
	var key := "%s|%s" % [asset, size]
	if _shapes.has(key):
		return _shapes[key]
	var out: Array = []
	var h := size.y
	if HERO.has(asset):
		var p: Dictionary = HERO[asset]
		var hw := size.x * HERO_WALL
		var hd := size.z * HERO_WALL
		var back := hd - float(p["porch"])        # the entrance wall
		var x0 := _porch_x0(p, size)
		var x1 := _porch_x1(p, size)
		_box(out, Vector3(-hw, 0, -hd), Vector3(hw, h, back))
		if x0 - (-hw) > 0.2:
			_box(out, Vector3(-hw, 0, back), Vector3(x0, h, hd))
		if hw - x1 > 0.2:
			_box(out, Vector3(x1, 0, back), Vector3(hw, h, hd))
		if bool(p["posts"]):
			for px: float in [x0 + 0.2, x1 - 0.2]:
				_box(out, Vector3(px - 0.18, 0, hd - 0.4), Vector3(px + 0.18, EAVE_H, hd - 0.04))
		_box(out, Vector3(x0, EAVE_H, back), Vector3(x1, h, hd))
	elif is_house(asset):
		var ww := size.x * HOUSE_WALL
		var wd := size.z * HOUSE_WALL
		_box(out, Vector3(-ww, 0, -wd), Vector3(ww, h, wd))
		var ew := size.x * 0.48
		var ed := size.z * 0.48
		_box(out, Vector3(-ew, EAVE_H, -ed), Vector3(ew, h * 0.75, ed))
	else:
		_box(out, Vector3(-size.x * 0.46, 0, -size.z * 0.46), Vector3(size.x * 0.46, h, size.z * 0.46))
	_shapes[key] = out
	return out


static func _box(out: Array, lo: Vector3, hi: Vector3) -> void:
	var s := hi - lo
	if s.x <= 0.05 or s.y <= 0.05 or s.z <= 0.05:
		return
	var b := BoxShape3D.new()
	b.size = s
	out.append([b, (lo + hi) * 0.5])
