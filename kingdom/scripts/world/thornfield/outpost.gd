extends Node3D
## The Thornfield Watch Post (F9): a small palisade fort on the road beyond Thornfield, the Soldier career's post.
## WHERE it stands is not decided here: it is read from data/careers/soldier_career.json (posts.outposts[0]: the
## Thornfield settlement plus `offset`, `radius`) through SoldierCareer.resolve_post, so the career and the fort can
## never disagree. The fort layout (data/region1/world/thornfield_wilds.json "outpost") is in the road frame: x across the
## road, z along it, the heading read from the world's road at the spot.
##
##   palisade      one MultiMesh of palisade sections (one draw) with solid runs; a gate gap at each end of the road
##   gates         posts and a lintel at both gaps (one mesh)
##   watchtowers   two (the "watchtower" building)
##   barracks      a house building with an InteriorDoor into the generic house interior ("Enter the Barracks")
##   captain       a Station: the post's captain. `menu_provider` (a Callable) lets the Soldier career supply the menu.
##   muster yard   a DrillYard (straw dummies, rack, hay): the muster spot and the training dummies
##   soldiers      five team-0 guard Soldiers (NpcFighter "guard"): two hold the west gate, three patrol the route
## Built within build_range of the player and freed past free_range.

const Wilds := preload("res://scripts/world/thornfield/wilds.gd")
const Props := preload("res://scripts/world/thornfield/wilds_props.gd")
const Squad := preload("res://scripts/army/squad.gd")
const DrillYard := preload("res://scripts/world/drill_yard.gd")
const KEEP: Array[String] = ["Knight_Helmet", "1H_Sword", "Round_Shield"]
const SECTION := 4.1
const WALL_H := 3.3

## Set by the Soldier career if it wants its own captain menu: Callable() -> {title, body, options}.
static var menu_provider := Callable()

var cfg: Dictionary = {}
var post: Dictionary = {}
var center := Vector2.INF
var heading := Vector2.RIGHT
var built := false
var captain: Node3D
var barracks_door: Node
var muster: Node3D
var dummies: Array = []
var gate_squad: Node
var patrol_squad: Node
var palisade: MultiMeshInstance3D
var _root: Node3D
var _route_i := 0
var _route_wait := 0.0


func _ready() -> void:
	name = "WatchPost"
	cfg = Wilds.data()["outpost"]
	post = Wilds.post()
	if String(post.get("kind", "")) == "outpost":
		center = post["pos"]
		heading = Wilds.road_heading(center)


## World XZ of a fort-local point (x across the road, z along it).
func local(x: float, z: float) -> Vector2:
	var perp := Vector2(heading.y, -heading.x)
	return center + perp * x + heading * z


func local_v(v: Array) -> Vector2:
	return local(float(v[0]), float(v[1]))


## The fort's centre must be the career's post: true when this node stands where soldier_career.json says.
func matches_career() -> bool:
	return center != Vector2.INF and center.is_equal_approx(Wilds.post().get("pos", Vector2.INF))


static func front_yaw(dir: Vector2) -> float:
	return atan2(dir.x, dir.y)


static func along_yaw(dir: Vector2) -> float:
	return atan2(-dir.y, dir.x)


# --- build ---------------------------------------------------------------------------------------------

func build() -> void:
	if built or center == Vector2.INF:
		return
	built = true
	_root = Node3D.new()
	_root.name = "Fort"
	add_child(_root)
	_build_palisade()
	_build_gates()
	var perp := Vector2(heading.y, -heading.x)
	var tower_i := 0
	for t: Array in cfg["watchtower"]:
		tower_i += 1
		var tp := local_v(t)
		var tm := Assets.building_mesh("watchtower")
		var mi := MeshInstance3D.new()
		mi.name = "Watchtower_%d" % tower_i
		mi.mesh = tm
		_root.add_child(mi)
		var low := WorldGen.height(tp.x, tp.y)
		for k in 4:
			low = minf(low, WorldGen.height(tp.x + cos(k * TAU / 4.0) * 2.5, tp.y + sin(k * TAU / 4.0) * 2.5))
		mi.global_transform = Transform3D(Basis(Vector3.UP, front_yaw(center - tp)).scaled(Vector3.ONE * 0.85), Vector3(tp.x, low - 0.08, tp.y))
		Props.solid(mi, Vector3(4.0, 8.0, 4.0))
	_build_barracks()
	_build_captain()
	_build_muster()
	var fire := local_v(cfg["campfire"])
	Props.prop(_root, "campfire", fire, 0.0, 0.8, 0.0, false)
	Props.fire_light(_root, Wilds.ground(fire, 1.2), 1.3, 11.0)
	Props.prop(_root, "notice_board", local(-2.5, -9.0), front_yaw(perp), 0.9)
	Props.prop(_root, "weapon_rack", local(-12.5, -3.0), front_yaw(perp), 1.0)


func _ground_low(p: Vector2, r: float) -> float:
	var low := WorldGen.height(p.x, p.y)
	for k in 4:
		low = minf(low, WorldGen.height(p.x + cos(k * TAU / 4.0) * r, p.y + sin(k * TAU / 4.0) * r))
	return low


## The wall runs as [a, b] local endpoints (the two side walls, the two end walls each split at the gate gap).
func wall_runs() -> Array:
	var hx := float((cfg["half"] as Array)[0])
	var hz := float((cfg["half"] as Array)[1])
	var gap := float(cfg["gate_gap"]) * 0.5
	return [
		[Vector2(-hx, -hz), Vector2(-hx, hz)], [Vector2(hx, -hz), Vector2(hx, hz)],
		[Vector2(-hx, -hz), Vector2(-gap, -hz)], [Vector2(gap, -hz), Vector2(hx, -hz)],
		[Vector2(-hx, hz), Vector2(-gap, hz)], [Vector2(gap, hz), Vector2(hx, hz)],
	]


func _build_palisade() -> void:
	var m := Props.mesh("palisade")
	if m == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	var xf: Array[Transform3D] = []
	for run: Array in wall_runs():
		var a := local(run[0].x, run[0].y)
		var b := local(run[1].x, run[1].y)
		var len := a.distance_to(b)
		var n := maxi(1, int(ceil(len / SECTION)))
		var dir := (b - a).normalized()
		var s := len / (float(n) * SECTION)
		var yaw := along_yaw(dir)
		for i in n:
			var p := a + dir * (len * (float(i) + 0.5) / float(n))
			var low := _ground_low(p, 1.8)
			xf.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, 1.0, 1.0)), Vector3(p.x, low - 0.1, p.y)))
		# the solid run
		var holder := Node3D.new()
		holder.name = "WallRun"
		_root.add_child(holder)
		var mid := (a + b) * 0.5
		holder.global_position = Vector3(mid.x, _ground_low(mid, 2.0) - 0.1, mid.y)
		holder.rotation.y = yaw
		Props.solid(holder, Vector3(len, WALL_H, 0.5))
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	palisade = MultiMeshInstance3D.new()
	palisade.name = "Palisade"
	palisade.multimesh = mm
	palisade.set_meta("sections", xf.size())
	_root.add_child(palisade)


func _build_gates() -> void:
	var parts: Array = []
	var wood := Color(0.34, 0.24, 0.15)
	var gap := float(cfg["gate_gap"]) * 0.5
	# built in a local frame at the fort centre; the mesh node is rotated to the road
	for g: Array in cfg["gates"]:
		var gz := float(g[1])
		for sx in [-1.0, 1.0]:
			parts.append([Vector3(sx * (gap + 0.25), 2.6, gz), Vector3(0.5, 5.2, 0.5), 0.0, wood])
		parts.append([Vector3(0.0, 5.0, gz), Vector3(gap * 2.0 + 1.4, 0.45, 0.5), 0.0, wood])
		parts.append([Vector3(0.0, 4.2, gz), Vector3(gap * 2.0, 0.2, 0.2), 0.0, Color(0.5, 0.12, 0.1)])
	var mi := MeshInstance3D.new()
	mi.name = "Gates"
	mi.mesh = Props.boxes_mesh(parts)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(mi)
	# local +x = perpendicular of the heading, local +z = the heading: rotate so local +z points along `heading`
	mi.global_transform = Transform3D(Basis(Vector3.UP, front_yaw(heading)), Vector3(center.x, _ground_low(center, 2.0) - 0.1, center.y))
	mi.set_meta("gate_count", (cfg["gates"] as Array).size())


func _build_barracks() -> void:
	var b: Dictionary = cfg["barracks"]
	var p := local_v(b["at"])
	var perp := Vector2(heading.y, -heading.x)
	var face := perp * (1.0 if float(b["yaw_deg"]) > 0.0 else -1.0)
	var yaw := front_yaw(face)
	var mi := MeshInstance3D.new()
	mi.name = "Barracks"
	mi.mesh = Assets.building_mesh("house_3")
	_root.add_child(mi)
	var low := _ground_low(p, 3.0)
	mi.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, low - 0.1, p.y))
	Props.solid(mi, Vector3(6.4, 6.0, 8.0), Vector3(0, 0, 0))
	var door := InteriorDoor.new()
	door.name = "BarracksDoor"
	door.interior_scene = String(b["interior"])
	door.prompt_text = "Enter the %s" % String(b["name"])
	door.collision_layer = 0
	door.collision_mask = InteriorDoor.PLAYER_TRIGGER_LAYER
	door.set_meta("building_owner", "public")
	door.set_meta("outpost_barracks", true)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(2.2, 2.2, 1.6)
	shape.position.y = 1.1
	door.add_child(shape)
	_root.add_child(door)
	var dp := p + face * 4.4
	door.global_position = Vector3(dp.x, WorldGen.height(dp.x, dp.y), dp.y)
	door.rotation.y = yaw
	barracks_door = door


func _build_captain() -> void:
	var c: Dictionary = cfg["captain"]
	var p := local_v(c["at"])
	var st := Station.new(String(c["name"]), "Report", Callable())
	st.name = "Captain"
	st.menu = captain_menu
	st.set_meta("post_id", String(post.get("id", "")))
	st.add_to_group("outpost_captain")
	_root.add_child(st)
	st.global_position = Wilds.ground(p)
	var toward := local(float((c["at"] as Array)[0]) + 3.0, float((c["at"] as Array)[1]) + 1.0) - p
	st.rotation.y = atan2(toward.x, toward.y)
	var body := Assets.character("Knight", 1.78, [])
	if body != null:
		st.add_child(body)
		var ap := Assets.animation_player(body)
		if ap:
			ap.play("Idle" if ap.has_animation("Idle") else ap.get_animation_list()[0])
	captain = st


## The captain's menu: the Soldier career's own when it registered `menu_provider`, else a plain notice of the post.
func captain_menu() -> Dictionary:
	if menu_provider.is_valid():
		return menu_provider.call()
	var c: Dictionary = cfg["captain"]
	var m: Dictionary = Wilds.post()
	return {"title": "%s, %s" % [String(c["name"]), String(c["title"])],
		"body": "\"%s. Muster is at dawn in the yard. Wolves at the hedgerows, cutthroats off the road. The Watch always has room for a steady spear.\"" % String(m.get("name", "The Watch Post")),
		"options": []}


func _build_muster() -> void:
	var mu: Dictionary = cfg["muster"]
	var p := local_v(mu["at"])
	var dy := DrillYard.new()
	dy.name = "MusterYard"
	dy.spot = p
	dy.yaw = front_yaw(local(float((mu["at"] as Array)[0]) - 3.0, float((mu["at"] as Array)[1])) - p)
	_root.add_child(dy)
	dy.hud = Interaction.hud(self)
	dy.build_now()
	muster = dy
	dy.set_meta("muster_pos", p)
	dummies.clear()
	var dm: Node = dy.get("_root")
	var ref := Props.mesh("scarecrow")
	if dm != null and ref != null:
		for n: Node in dm.get_children():
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).mesh.get_aabb().size.is_equal_approx(ref.get_aabb().size):
				dummies.append(n)


func muster_pos() -> Vector2:
	return local_v(cfg["muster"]["at"])


# --- soldiers -------------------------------------------------------------------------------------------

func spawn_garrison() -> Array:
	if center == Vector2.INF or not soldiers().is_empty():
		return soldiers()
	var total := int(cfg["soldiers"])
	var patrol := int(cfg["patrol"])
	var gate := total - patrol
	var gp := Wilds.ground(local(float(-3.0), float((cfg["gates"] as Array)[0][1]) + 2.5))
	gate_squad = _squad(gp)
	gate_squad.call("add_soldiers", gate, gp)
	var route: Array = cfg["route"]
	var start := Wilds.ground(local_v(route[0]))
	patrol_squad = _squad(start)
	patrol_squad.call("add_soldiers", patrol, start)
	_route_i = 0
	for s: Variant in soldiers():
		(s as Node).set_meta("outpost", String(post.get("id", "")))
	return soldiers()


func _squad(anchor: Vector3) -> Node:
	var sq := Squad.new().setup(0, "soldier", "Knight", KEEP)
	sq.anchor = anchor
	sq.aggro_radius = 22.0
	add_child(sq)
	return sq


func soldiers() -> Array:
	var out: Array = []
	for sq: Variant in [gate_squad, patrol_squad]:
		if sq != null and is_instance_valid(sq):
			for s: Variant in (sq.get("soldiers") as Array):
				if is_instance_valid(s) and not bool((s as Node).get("dead")):
					out.append(s)
	return out


func despawn_garrison() -> void:
	for sq: Variant in [gate_squad, patrol_squad]:
		if sq != null and is_instance_valid(sq):
			for s: Variant in (sq.get("soldiers") as Array).duplicate():
				if is_instance_valid(s):
					(s as Node).queue_free()
			(sq as Node).queue_free()
	gate_squad = null
	patrol_squad = null


## The patrol: when the squad stands idle (order HOLD) it walks to the next waypoint of the route; a fight (CHARGE)
## is left alone. Called every 2 s by the hub.
func patrol_tick(dt: float) -> void:
	if patrol_squad == null or not is_instance_valid(patrol_squad) or int(patrol_squad.call("alive")) <= 0:
		return
	if int(patrol_squad.get("order")) != Squad.Order.HOLD:
		return
	_route_wait -= dt
	if _route_wait > 0.0:
		return
	var route: Array = cfg["route"]
	_route_i = (_route_i + 1) % route.size()
	var wp := Wilds.ground(local_v(route[_route_i]))
	patrol_squad.call("move_to", wp)
	_route_wait = 4.0


func free_fort() -> void:
	despawn_garrison()
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	palisade = null
	captain = null
	muster = null
	barracks_door = null
	dummies.clear()
	built = false


func refresh(pp: Vector2, dt := 2.0) -> void:
	if center == Vector2.INF:
		return
	var d := pp.distance_to(center)
	if not built and d < float(cfg["build_range"]):
		build()
	elif built and d > float(cfg["free_range"]) and InteriorDoor.active == null:
		free_fort()
		return
	if built and d < float(cfg["build_range"]) * 0.8:
		if soldiers().is_empty() and (gate_squad == null):
			spawn_garrison()
		patrol_tick(dt)
	elif built and gate_squad != null and d > float(cfg["build_range"]):
		despawn_garrison()
