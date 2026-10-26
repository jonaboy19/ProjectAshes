class_name SurfaceQuery
extends RefCounted
## World semantics in one place: what is under / in front of a point.
##   probe(space, from, to, exclude) -> {hit, position, normal, collider, kind, material, slope_deg, walkable,
##                                       climbable, vaultable, ledge, water_depth, footstep}
##   ground(space, pos, exclude)     -> probe straight down from pos + 0.5 m to pos - 2 m (feet / footsteps / foot IK)
##   kind  : ground | wall | ceiling | water   (by normal; water when the point is under WorldGen water)
##   material: grass dirt mud sand snow stone cobble wood leaves metal water (see MATERIALS)
## Material resolution: collider meta "surface" (walks up 4 parents) -> tagged group "surface_<m>" -> terrain body
## (WorldGen paint weights + biome + water) -> node-name heuristic -> "stone".
## Tag new colliders with SurfaceQuery.tag(body, &"wood", {climbable = true}). Pure statics, no autoload, no per-frame cost.

const MATERIALS := [&"grass", &"dirt", &"mud", &"sand", &"snow", &"stone", &"cobble", &"wood", &"leaves", &"metal", &"water"]
## Footstep sound family per material (families that exist in assets/audio/sfx/footsteps).
const FOOTSTEP := {&"grass": "grass", &"dirt": "dirt", &"mud": "dirt", &"sand": "dirt", &"snow": "snow",
	&"stone": "stone", &"cobble": "cobble", &"wood": "wood", &"leaves": "leaves", &"metal": "stone", &"water": "water"}
const WALKABLE_DEG := 45.0      # matches CharacterBody3D floor_max_angle default
const CEILING_Y := -0.5         # normal.y below this is a ceiling
const WADE_DEPTH := 0.08        # water shallower than this is just wet ground
const NAME_HINTS := [["plank", &"wood"], ["wood", &"wood"], ["bridge", &"wood"], ["floor", &"wood"], ["dock", &"wood"],
	["pier", &"wood"], ["timber", &"wood"], ["barrel", &"wood"], ["crate", &"wood"], ["table", &"wood"], ["bench", &"wood"],
	["stair", &"wood"], ["roof", &"wood"], ["fence", &"wood"], ["cobble", &"cobble"], ["street", &"cobble"],
	["metal", &"metal"], ["iron", &"metal"], ["anvil", &"metal"], ["sand", &"sand"], ["snow", &"snow"], ["mud", &"mud"],
	["rock", &"stone"], ["stone", &"stone"], ["wall", &"stone"], ["cave", &"stone"], ["keep", &"stone"], ["tower", &"stone"]]

static var _ray := PhysicsRayQueryParameters3D.new()


## Tag a collider (or any ancestor of one) with a material and optional traversal flags.
static func tag(node: Node, material: StringName, flags := {}) -> void:
	if node == null:
		return
	node.set_meta(&"surface", material)
	for k: String in flags:
		node.set_meta(StringName("surface_" + k), flags[k])


## Material from a free-text hint (asset path / node name), or `fallback`.
static func material_hint(text: String, fallback: StringName = &"stone") -> StringName:
	var t := text.to_lower()
	for hint: Array in NAME_HINTS:
		if t.contains(hint[0]):
			return hint[1]
	return fallback


## ground / wall / ceiling from a surface normal.
static func kind_for_normal(n: Vector3) -> StringName:
	if n.y < CEILING_Y:
		return &"ceiling"
	if n.y >= cos(deg_to_rad(WALKABLE_DEG + 15.0)):
		return &"ground"
	return &"wall"


static func slope_deg(n: Vector3) -> float:
	return rad_to_deg(acos(clampf(n.y, -1.0, 1.0)))


## Terrain material at (x, z) from the same paint weights the ground shader uses, plus biome and water.
static func terrain_material(x: float, z: float) -> StringName:
	var h := WorldGen.height(x, z)
	var depth := WorldGen.water_depth(x, z)
	if depth > WADE_DEPTH:
		return &"water"
	var n := Vector3(WorldGen.height(x - 1.0, z) - WorldGen.height(x + 1.0, z), 2.0,
		WorldGen.height(x, z - 1.0) - WorldGen.height(x, z + 1.0)).normalized()
	var w := WorldGen.color_at(x, z, h, 1.0 - n.y)
	if w.b > 0.5:
		return &"cobble"
	if w.g > 0.6:
		return &"stone"
	var lv := WorldGen.water_level_at(x, z)
	if not is_nan(lv) and h - lv < 1.0:
		return &"sand"     # shore band (color_at paints it as sandy dirt)
	var biome := WorldBiomes.at(x, z) if WorldBiomes.active() else -1
	if biome == WorldBiomes.SNOW:
		return &"snow"
	if biome == WorldBiomes.MARSH:
		return &"mud"
	if w.r > 0.45:
		return &"mud" if _raining() and w.r > 0.6 else &"dirt"
	if w.a > 0.45:
		return &"leaves"
	return &"grass"


static func _raining() -> bool:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return false
	var w := loop.get_first_node_in_group(&"weather")
	return w != null and w.has_method("is_raining") and bool(w.call("is_raining"))


## Material of a collider: explicit tag, then terrain, then name heuristic.
static func material_of(collider: Object, at := Vector3.ZERO) -> StringName:
	var node := collider as Node
	var depth := 0
	while node != null and depth < 5:
		if node.has_meta(&"surface"):
			return StringName(node.get_meta(&"surface"))
		for m: StringName in MATERIALS:
			if node.is_in_group(StringName("surface_" + m)):
				return m
		if _is_terrain(node):
			return terrain_material(at.x, at.z)
		node = node.get_parent()
		depth += 1
	node = collider as Node
	if node == null:
		return terrain_material(at.x, at.z)
	return material_hint(String(node.name) + " " + (String(node.get_parent().name) if node.get_parent() else ""))


static func _is_terrain(node: Node) -> bool:
	if node.is_in_group(&"terrain"):
		return true
	var cls := node.get_class()
	if cls == "Terrain3D" or cls == "HeightMapShape3D":
		return true
	# TerrainStreamer chunks: <chunk>/Body with a sibling "Ground" mesh.
	return node.name == &"Body" and node.get_parent() != null and node.get_parent().has_node(^"Ground")


static func _flag(collider: Object, key: StringName, fallback: bool) -> bool:
	var node := collider as Node
	var depth := 0
	while node != null and depth < 5:
		if node.has_meta(key):
			return bool(node.get_meta(key))
		node = node.get_parent()
		depth += 1
	return fallback


## Full description of one hit (or of the terrain at `to` when nothing was hit and WorldGen is live).
static func describe(hit: Dictionary) -> Dictionary:
	var out := {"hit": not hit.is_empty(), "position": Vector3.ZERO, "normal": Vector3.UP, "collider": null,
		"kind": &"ground", "material": &"grass", "slope_deg": 0.0, "walkable": true, "climbable": false,
		"vaultable": false, "ledge": false, "water_depth": 0.0, "footstep": "grass"}
	if hit.is_empty():
		return out
	var p: Vector3 = hit["position"]
	var n: Vector3 = hit["normal"]
	var col: Object = hit.get("collider")
	out["position"] = p
	out["normal"] = n
	out["collider"] = col
	out["kind"] = kind_for_normal(n)
	out["slope_deg"] = slope_deg(n)
	out["walkable"] = out["kind"] == &"ground" and float(out["slope_deg"]) <= WALKABLE_DEG
	var mat := material_of(col, p)
	var lv := WorldGen.water_level_at(p.x, p.z)
	if not is_nan(lv) and lv > p.y:
		out["water_depth"] = lv - p.y
		if lv - p.y > WADE_DEPTH:
			out["kind"] = &"water" if out["kind"] == &"ground" else out["kind"]
			mat = &"water"
	out["material"] = mat
	out["footstep"] = FOOTSTEP.get(mat, "stone")
	var is_wall: bool = out["kind"] == &"wall"
	out["climbable"] = _flag(col, &"surface_climbable", is_wall and mat in [&"stone", &"wood", &"cobble"])
	out["vaultable"] = _flag(col, &"surface_vaultable", false)
	out["ledge"] = _flag(col, &"surface_ledge", false)
	return out


## Ray from -> to, described.
static func probe(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array = [], mask := 0xFFFFFFFF) -> Dictionary:
	if space == null:
		return describe({})
	_ray.from = from
	_ray.to = to
	_ray.exclude = exclude
	_ray.collision_mask = mask
	_ray.hit_from_inside = false
	return describe(space.intersect_ray(_ray))


## What the feet stand on at `pos` (ray from 0.5 m above to 2 m below). Falls back to pure terrain without physics.
static func ground(space: PhysicsDirectSpaceState3D, pos: Vector3, exclude: Array = [], mask := 0xFFFFFFFF) -> Dictionary:
	var d := probe(space, pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 2.0, exclude, mask)
	if not d["hit"]:
		var m := terrain_material(pos.x, pos.z)
		d["material"] = m
		d["footstep"] = FOOTSTEP.get(m, "grass")
		d["water_depth"] = WorldGen.water_depth(pos.x, pos.z)
	return d


## Ledge test in front of a body: a wall within `reach` whose top (free space above) is within `max_h` of the feet.
## Returns {} or {top: Vector3, height: float, wall: Dictionary}. Helper for traversal / AI.
static func ledge_ahead(space: PhysicsDirectSpaceState3D, feet: Vector3, dir: Vector3, exclude: Array = [],
		reach := 0.8, max_h := 2.4) -> Dictionary:
	var f := Vector3(dir.x, 0.0, dir.z).normalized()
	if f == Vector3.ZERO:
		return {}
	var wall := probe(space, feet + Vector3.UP * 0.6, feet + Vector3.UP * 0.6 + f * reach, exclude)
	if not wall["hit"] or wall["kind"] != &"wall":
		return {}
	var over: Vector3 = wall["position"] + f * 0.25
	var top := probe(space, Vector3(over.x, feet.y + max_h + 0.3, over.z), Vector3(over.x, feet.y + 0.3, over.z), exclude)
	if not top["hit"] or top["kind"] != &"ground":
		return {}
	var p: Vector3 = top["position"]
	return {"top": p, "height": p.y - feet.y, "wall": wall, "surface": top}
