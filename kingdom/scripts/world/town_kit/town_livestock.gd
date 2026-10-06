extends RefCounted
## A kit town's livestock (its file's `livestock`): farm animals from critter.gd standing where the file says they live, and the
## rail-fence pens around them. AmbientLife.add_groups hands the groups to its own spawn ring (bodies only near the player, freed
## far away), so this costs nothing at distance. The pens are static fence rails built once by the town hub.
##
##   groups {anchor, at, kinds [[kind, n]], radius, tag}    animals; anchors as in town_data.gd (settlement metres / site-local)
##   pens   {anchor, at, size [x, y]}                       four fence sides around a site-local centre, the front side has a gate
## Pens only make sense on a site anchor (they follow its yaw); a settlement-anchored pen is laid along the world axes.
## Preload, no class_name; every function is static.

const TownData := preload("res://scripts/world/town_kit/town_data.gd")
const TownPlaces := preload("res://scripts/world/town_kit/town_places.gd")
const FENCE_LEN := 3.1


## [{pos: Vector2, kinds: [[kind, n]], radius: float, tag: String}] in world XZ. Settlement-anchored groups that would stand in water are dropped.
static func groups(tid: String) -> Array:
	var out: Array = []
	for g: Dictionary in (TownData.town(tid).get("livestock", {}) as Dictionary).get("groups", []):
		var pos := TownPlaces.resolve(tid, g)
		if pos == Vector2.INF:
			continue
		var frame: Dictionary = (TownData.town(tid).get("anchors", {}) as Dictionary).get(String(g.get("anchor", "")), {})
		if String(frame.get("kind", "")) == "settlement" and WorldGen.near_water(pos.x, pos.y, 3.0):
			continue          # offsets from the town centre are guesses: keep them out of water (site anchors are laid out dry)
		out.append({"pos": pos, "kinds": g["kinds"], "radius": float(g["radius"]), "tag": String(g.get("tag", ""))})
	return out


## AmbientLife._group for every group of town `tid` (or of every kit town when tid is ""). Returns how many were added.
static func add_groups(ambient: Node, tid := "") -> int:
	var n := 0
	for t: String in ([tid] if tid != "" else TownData.ids()):
		for g: Dictionary in groups(t):
			ambient.call("_group", g["pos"], g["kinds"], float(g["radius"]))
			n += 1
	return n


## Rail-fence pens as world-space fence pieces. Returns the Node3D holding them (empty when the town has none).
static func build_pens(tid: String, parent: Node) -> Node3D:
	var root := Node3D.new()
	root.name = tid.capitalize().replace(" ", "") + "Pens"
	parent.add_child(root)
	var pens: Array = (TownData.town(tid).get("livestock", {}) as Dictionary).get("pens", [])
	if pens.is_empty():
		return root
	var mesh: ArrayMesh = Assets.building_mesh("fence")
	if mesh == null:
		return root
	for p: Dictionary in pens:
		var site := TownPlaces.anchor_site(tid, String(p.get("anchor", "")))
		if site.is_empty():
			continue
		var size := Vector2(float(p["size"][0]), float(p["size"][1]))
		_pen(root, mesh, site, Vector2(float(p["at"][0]), float(p["at"][1])), size)
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
			var w := TownPlaces.to_world(site, local)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.name = "PenFence"
			root.add_child(mi)
			mi.global_position = Vector3(w.x, WorldGen.height(w.x, w.y), w.y)
			var dir := b - a
			# The fence mesh runs along its local X; rotate it onto the side's direction in the world.
			mi.rotation.y = yaw + atan2(-dir.y, dir.x)
			mi.scale = Vector3(side_len / float(n) / FENCE_LEN, 1.0, 1.0)
