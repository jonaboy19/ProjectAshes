extends RefCounted
## Villagers going through street doors (package F6). When a villager reaches the door of the building it is going
## into (or comes out of one) near the player, the door opens, they step through and it shuts, instead of the body
## popping out of existence.
##
##   DoorPass.begin(villager, entering) -> bool   # true when a door was found and the passage is animated
##   DoorPass.swing(door)                          # the leaf: a slab that swings open and shut, then frees itself
##
## The building meshes have the door baked in, so the leaf is a thin slab created only while a door moves and freed
## afterwards; with nobody within WATCH_RANGE of the player nothing is created. Preload this script; no class_name.

const WATCH_RANGE := 28.0       # only animate where the player can see it
const FIND_RANGE := 7.0         # the door must be this close to the villager
const SWING := 0.55
const HOLD := 0.7
const STEP_IN := 1.4            # metres a villager walks towards the door while entering

static var _mat: StandardMaterial3D


## Nearest entrance door within `radius` of `p` (XZ), or null.
static func nearest_door(tree: SceneTree, p: Vector3, radius := FIND_RANGE) -> Node3D:
	var best: Node3D = null
	var best_d := radius * radius
	for d: Node in tree.get_nodes_in_group("entrance_door"):
		var n := d as Node3D
		if n == null or not n.is_inside_tree():
			continue
		var dx := n.global_position.x - p.x
		var dz := n.global_position.z - p.z
		var dd := dx * dx + dz * dz
		if dd < best_d:
			best_d = dd
			best = n
	return best


## Pure: is a passage worth animating? (player close enough and the villager is not already a long way off)
static func worth_animating(player_dist: float, door_dist: float) -> bool:
	return player_dist <= WATCH_RANGE and door_dist <= FIND_RANGE


## Opens the nearest door for `v` and walks it towards the threshold; when entering, the body is hidden at the end of
## the step. Returns false (do nothing special) when no door is near or the player is far away.
static func begin(v: Node3D, entering: bool) -> bool:
	if v == null or not v.is_inside_tree():
		return false
	var tree := v.get_tree()
	var player := tree.get_first_node_in_group("player") as Node3D
	var pdist := v.global_position.distance_to(player.global_position) if player != null else 9999.0
	if pdist > WATCH_RANGE:
		return false
	var door := nearest_door(tree, v.global_position)
	if door == null or not worth_animating(pdist, v.global_position.distance_to(door.global_position)):
		return false
	if door.has_method("npc_pass"):
		door.call("npc_pass")
	if entering:
		var to := door.global_position
		to.y = v.global_position.y
		var dir := to - v.global_position
		dir.y = 0.0
		var step := minf(dir.length(), STEP_IN)
		var dest := v.global_position + (dir.normalized() * step if dir.length() > 0.01 else Vector3.ZERO)
		var tw := v.create_tween()
		tw.tween_property(v, "global_position", dest, SWING + 0.2)
		tw.finished.connect(func() -> void:
			if is_instance_valid(v) and bool(v.get("_indoors")):
				v.visible = false)
	return true


static func _wood() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_color = Color(0.30, 0.19, 0.10)
		_mat.roughness = 0.95
	return _mat


## Swings a door leaf open, holds, closes, frees it. `door` is an InteriorDoor whose local +Z points out of the
## building; the hinge sits on the wall line one metre behind the trigger centre.
static func swing(door: Node3D) -> void:
	if door == null or not door.is_inside_tree() or door.has_node("NpcLeaf"):
		return
	var pivot := Node3D.new()
	pivot.name = "NpcLeaf"
	door.add_child(pivot)
	pivot.position = Vector3(-0.5, 0.0, -1.0)
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 2.0, 0.06)
	slab.mesh = bm
	slab.material_override = _wood()
	slab.position = Vector3(0.5, 1.0, 0.0)
	slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(slab)
	var tw := pivot.create_tween()
	tw.tween_property(pivot, "rotation:y", 1.5, SWING)
	tw.tween_interval(HOLD)
	tw.tween_property(pivot, "rotation:y", 0.0, SWING)
	tw.finished.connect(func() -> void:
		if is_instance_valid(pivot):
			pivot.queue_free())
