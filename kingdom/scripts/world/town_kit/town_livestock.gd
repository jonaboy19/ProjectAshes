extends RefCounted
## A kit town's livestock (its file's `livestock`): farm animals from critter.gd standing where the file says they live, and the
## rail-fence pens around them. AmbientLife.add_groups hands the groups to its own spawn ring (bodies only near the player, freed
## far away), so this costs nothing at distance. The pens are static fence rails built once by the town hub.
##
##   groups {anchor, at, kinds [[kind, n]], radius, tag}    animals; anchors as in town_data.gd (settlement metres / site-local)
##   pens   {anchor, at, size [x, y]}                       four fence sides around a site-local centre, the front side has a gate
## A pen follows its anchor frame's yaw (a settlement-anchored pen lies along the world axes, turned by its own `yaw`).
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


## The fence pieces of every pen of town `tid` as world transforms (no scene needed: tests measure them). Site-anchored pens follow
## the site's yaw; a pen on the settlement anchor lies along the world axes turned by its own `yaw`; a pen centred on wet ground is
## left out. The pen's centre is placed with the anchor frame alone, only the four sides turn with the pen's yaw.
static func pen_transforms(tid: String) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for p: Dictionary in (TownData.town(tid).get("livestock", {}) as Dictionary).get("pens", []):
		var frame := TownPlaces.frame(tid, String(p.get("anchor", "")))
		if frame.is_empty():
			continue
		var centre := TownPlaces.to_world(frame, Vector2(float(p["at"][0]), float(p["at"][1])))
		if WorldGen.near_water(centre.x, centre.y, 3.0):
			continue
		_pen(out, {"pos": centre, "yaw": float(frame["yaw"]) + float(p.get("yaw", 0.0))}, Vector2(float(p["size"][0]), float(p["size"][1])))
	return out


## Rail-fence pens as one MultiMesh (one node, one draw call, whatever the number of rails). Returns the Node3D holding it (empty when
## the town has none).
static func build_pens(tid: String, parent: Node) -> Node3D:
	var root := Node3D.new()
	root.name = tid.capitalize().replace(" ", "") + "Pens"
	parent.add_child(root)
	var mesh: ArrayMesh = Assets.building_mesh("fence")
	if mesh == null or (TownData.town(tid).get("livestock", {}) as Dictionary).get("pens", []).is_empty():
		return root
	var xforms := pen_transforms(tid)
	if xforms.is_empty():
		return root
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "PenFences"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	return root


## The fence pieces of a pen centred on frame["pos"] and turned by frame["yaw"]: four sides, rails facing outwards, the front side
## (local +y) keeps a gate gap.
static func _pen(out: Array[Transform3D], frame: Dictionary, size: Vector2) -> void:
	var yaw: float = frame["yaw"]
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var sides := [[Vector2(-hx, -hz), Vector2(hx, -hz)], [Vector2(hx, -hz), Vector2(hx, hz)],
		[Vector2(hx, hz), Vector2(-hx, hz)], [Vector2(-hx, hz), Vector2(-hx, -hz)]]
	var gate_side := 2
	for si in sides.size():
		var a: Vector2 = sides[si][0]
		var b: Vector2 = sides[si][1]
		var side_len := a.distance_to(b)
		var n := maxi(1, int(ceil(side_len / FENCE_LEN)))
		for k in n:
			if si == gate_side and k == n / 2:
				continue
			var t := (float(k) + 0.5) / float(n)
			var w := TownPlaces.to_world(frame, a.lerp(b, t))
			var dir := b - a
			# The fence mesh runs along its local X; rotate it onto the side's direction in the world.
			var basis := Basis(Vector3.UP, yaw + atan2(-dir.y, dir.x)).scaled_local(Vector3(side_len / float(n) / FENCE_LEN, 1.0, 1.0))
			out.append(Transform3D(basis, Vector3(w.x, WorldGen.height(w.x, w.y), w.y)))
