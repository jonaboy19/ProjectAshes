extends RefCounted
## Thornfield's livestock: farm animals from critter.gd standing where the farm says they live, and the rail-fence pens
## around them. AmbientLife.add_groups hands the groups to its own spawn ring (bodies only near the player, freed far
## away), so this costs nothing at distance. The pens are static fence rails built once by the hub.
##
## Farm (RegionSites._farmstead, site-local metres): pig sty, chicken coop, a sheep pen in the north-east corner, and
## three cows grazing beside the barn. The Brewery landmark gets a dog by the granary and hens about the yard.

const Sites := preload("res://scripts/world/thornfield/sites.gd")
const PEN_SIZE := Vector2(11.0, 8.0)
const SHEEP_PEN_AT := Vector2(23.0, -15.0)
const PIG_PEN_AT := Sites.PIG_STY_AT + Vector2(0.0, 5.0)
const FENCE_LEN := 3.1


## [{pos: Vector2, kinds: [[kind, n]], radius: float, tag: String}] in world XZ.
static func groups() -> Array:
	var out: Array = []
	var f := Sites.farm()
	if not f.is_empty():
		out.append({"pos": Sites.to_world(f, Sites.PIG_STY_AT + Vector2(0.0, 3.5)), "kinds": [["pig", 3]], "radius": 3.2, "tag": "pigs"})
		out.append({"pos": Sites.to_world(f, Sites.COOP_AT + Vector2(-1.0, 3.0)), "kinds": [["chicken", 6], ["rooster", 1]], "radius": 4.5, "tag": "hens"})
		out.append({"pos": Sites.to_world(f, SHEEP_PEN_AT), "kinds": [["sheep", 6], ["sheepdog", 1]], "radius": 8.0, "tag": "sheep"})
		out.append({"pos": Sites.to_world(f, Sites.FARM_BARN_AT + Vector2(14.0, 8.0)), "kinds": [["cow", 3]], "radius": 9.0, "tag": "cows"})
	var b := Sites.brewery()
	if not b.is_empty():
		out.append({"pos": Sites.to_world(b, Sites.BARN_DOOR + Vector2(-5.0, 4.0)), "kinds": [["dog", 1], ["chicken", 3]], "radius": 5.0, "tag": "yard"})
	return out


## AmbientLife._group for every Thornfield group (called at the end of AmbientLife._ready).
static func add_groups(ambient: Node) -> int:
	var n := 0
	for g: Dictionary in groups():
		ambient.call("_group", g["pos"], g["kinds"], float(g["radius"]))
		n += 1
	return n


## Rail-fence pens (sheep, pigs) as world-space fence pieces. Returns the Node3D holding them.
static func build_pens(parent: Node) -> Node3D:
	var root := Node3D.new()
	root.name = "ThornfieldPens"
	parent.add_child(root)
	var f := Sites.farm()
	if f.is_empty():
		return root
	var mesh: ArrayMesh = Assets.building_mesh("fence")
	if mesh == null:
		return root
	_pen(root, mesh, f, SHEEP_PEN_AT, PEN_SIZE)
	_pen(root, mesh, f, PIG_PEN_AT, Vector2(7.0, 6.0))
	return root


## The four sides of a pen centred at site-local `c`; the pieces are laid along each side, rails facing outwards.
static func _pen(root: Node3D, mesh: ArrayMesh, site: Dictionary, c: Vector2, size: Vector2) -> void:
	var yaw: float = site["yaw"]
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var sides := [[Vector2(-hx, -hz), Vector2(hx, -hz)], [Vector2(hx, -hz), Vector2(hx, hz)],
		[Vector2(hx, hz), Vector2(-hx, hz)], [Vector2(-hx, hz), Vector2(-hx, -hz)]]
	var gate_side := 2          # the front side keeps a gap for the gate
	for si in sides.size():
		var a: Vector2 = sides[si][0]
		var b: Vector2 = sides[si][1]
		var side_len := a.distance_to(b)
		var n := maxi(1, int(ceil(side_len / FENCE_LEN)))
		for k in n:
			if si == gate_side and k == n / 2:
				continue
			var t := (float(k) + 0.5) / float(n)
			var local := c + a.lerp(b, t)
			var w := Sites.to_world(site, local)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.name = "PenFence"
			root.add_child(mi)
			mi.global_position = Vector3(w.x, WorldGen.height(w.x, w.y), w.y)
			var dir := b - a
			# The fence mesh runs along its local X; rotate it onto the side's direction in the world.
			mi.rotation.y = yaw + atan2(-dir.y, dir.x)
			mi.scale = Vector3(side_len / float(n) / FENCE_LEN, 1.0, 1.0)
