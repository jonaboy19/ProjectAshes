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
const Ground := preload("res://scripts/world/town_kit/town_ground.gd")
const FENCE_LEN := 3.1
## QA switch for before / after shots: `-- --legacy-pens` puts every pen and animal group back where the town file says, steep or wet or not.
static var legacy_pens := OS.get_cmdline_user_args().has("--legacy-pens")
const PEN_SEARCH_STEP := 4.0         # m between rings when a pen has to move off a slope / out of water
const PEN_SEARCH_RINGS := 10         # up to 40 m from where the file put it


## [{pos: Vector2, kinds: [[kind, n]], radius: float, tag: String}] in world XZ. Settlement-anchored groups that would stand in water are dropped.
static func groups(tid: String) -> Array:
	var out: Array = []
	for g: Dictionary in (TownData.town(tid).get("livestock", {}) as Dictionary).get("groups", []):
		var pos := TownPlaces.resolve(tid, g)
		if pos == Vector2.INF:
			continue
		# Offsets from an anchor are guesses: a group that would stand in water or on a steep slope moves to the nearest level, dry
		# ground (town_ground.gd), and is dropped when there is none within 36 m.
		if legacy_pens:
			var fr: Dictionary = (TownData.town(tid).get("anchors", {}) as Dictionary).get(String(g.get("anchor", "")), {})
			if not (String(fr.get("kind", "")) == "settlement" and WorldGen.near_water(pos.x, pos.y, 3.0)):
				out.append({"pos": pos, "kinds": g["kinds"], "radius": float(g["radius"]), "tag": String(g.get("tag", ""))})
			continue
		var pen := _pen_of(tid, g)
		if not pen.is_empty():
			pos = (pen["pos"] as Vector2)          # the animals follow their pen
		else:
			pos = Ground.settle(tid, pos, Ground.group_ok, 0.0, 6.0, 6)
			if pos == Vector2.INF:
				continue
		out.append({"pos": pos, "kinds": g["kinds"], "radius": float(g["radius"]), "tag": String(g.get("tag", ""))})
	return out


## The placed pen ({pos, yaw}) around group `g` (a pen with the same anchor and `at`), {} when it has none or the pen was left out.
static func _pen_of(tid: String, g: Dictionary) -> Dictionary:
	for p: Dictionary in (TownData.town(tid).get("livestock", {}) as Dictionary).get("pens", []):
		if String(p.get("anchor", "")) == String(g.get("anchor", "")) and p.get("at") == g.get("at"):
			return pen_spot(tid, p)
	return {}


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
		var spot := pen_spot(tid, p)
		if spot.is_empty():
			continue
		_pen(out, spot, Vector2(float(p["size"][0]), float(p["size"][1])))
	return out


## Where pen `p` of town `tid` really stands: {pos, yaw}, or {} when the pen is left out. The file's spot is kept when the ground under the
## whole footprint is level enough (town_ground.gd PEN_MAX_RELIEF), dry and off the road; otherwise the pen moves to the nearest spot that is
## (rings of 4 m up to 32 m, clear of the town's buildings), and a pen with no such spot is skipped: a rail fence on a 10 m slope floats on
## one side and is buried on the other (Skarholm).
static func pen_spot(tid: String, p: Dictionary) -> Dictionary:
	var frame := TownPlaces.frame(tid, String(p.get("anchor", "")))
	if frame.is_empty():
		return {}
	var size := Vector2(float(p["size"][0]), float(p["size"][1]))
	var yaw: float = float(frame["yaw"]) + float(p.get("yaw", 0.0))
	var centre := TownPlaces.to_world(frame, Vector2(float(p["at"][0]), float(p["at"][1])))
	if legacy_pens:
		return {} if WorldGen.near_water(centre.x, centre.y, 3.0) else {"pos": centre, "yaw": yaw}
	var ok := func(c: Vector2) -> bool:
		return not WorldGen.near_water(c.x, c.y, Ground.WET) and Ground.pen_ok(c, size, yaw) and not Ground.rect_on_road(c, size, yaw) \
				and pieces_ok(c, yaw, size)
	var half := maxf(size.x, size.y) * 0.5
	var at := Ground.settle(tid, centre, ok, half, PEN_SEARCH_STEP, PEN_SEARCH_RINGS)
	if at == Vector2.INF:
		return {}
	return {"pos": at, "yaw": yaw}


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


## Every fence piece of a pen at `c` stands on level ground along its own length (ends within PEN_MAX_PIECE_DROP) and off the road.
static func pieces_ok(c: Vector2, yaw: float, size: Vector2) -> bool:
	var tmp: Array[Transform3D] = []
	_pen(tmp, {"pos": c, "yaw": yaw}, size)
	for xf: Transform3D in tmp:
		if piece_drop(xf) > Ground.PEN_MAX_PIECE_DROP or Ground.on_road(Vector2(xf.origin.x, xf.origin.z), 0.0):
			return false
	return true


## Height difference between the two ends of one fence piece.
static func piece_drop(xf: Transform3D) -> float:
	var along := xf.basis.x.normalized() * (FENCE_LEN * 0.5)
	return absf(WorldGen.height(xf.origin.x - along.x, xf.origin.z - along.z) - WorldGen.height(xf.origin.x + along.x, xf.origin.z + along.z))


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
