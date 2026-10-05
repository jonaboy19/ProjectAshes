class_name Ladder
extends Node3D
## A simple vertical move between two markers: "Climb" at the bottom takes the player to the top marker and "Climb"
## at the top takes them back down. Each end is a child Marker3D carrying its own Interactable, so the picker
## offers whichever end the player stands at. A player with a traversal driver (scripts/actors/traversal.gd)
## climbs over time with the ladder clip; any other node is moved at once.

signal climbed(to_top: bool)

var bottom: Marker3D
var top: Marker3D


## A ladder whose bottom is at `bottom_pos` and top at `top_pos` (both global). The top marker is where the
## player is put, so give it a spot on the upper floor, not on the rung.
static func spawn(parent: Node, bottom_pos: Vector3, top_pos: Vector3, label := "Ladder") -> Ladder:
	var l := Ladder.new()
	l.name = label.replace(" ", "")
	parent.add_child(l)
	l.global_position = bottom_pos
	l.bottom.global_position = bottom_pos
	l.top.global_position = top_pos
	l._build_visual(top_pos.y - bottom_pos.y)
	return l


func _init() -> void:
	bottom = Marker3D.new()
	bottom.name = "Bottom"
	add_child(bottom)
	top = Marker3D.new()
	top.name = "Top"
	add_child(top)


func _ready() -> void:
	Interactable.attach(bottom, {"id_fn": func() -> String: return "ladder/%s/bottom" % name, "verb": "Climb", "target": "Ladder",
		"range": 2.2, "do": func(p: Node) -> void: climb(p as Node3D, true)})
	Interactable.attach(top, {"id_fn": func() -> String: return "ladder/%s/top" % name, "verb": "Climb", "target": "Ladder",
		"range": 2.2, "do": func(p: Node) -> void: climb(p as Node3D, false)})


func height() -> float:
	return top.global_position.y - bottom.global_position.y


## Puts the player at the far end. `to_top` true goes up. Returns the destination.
func climb(player: Node3D, to_top: bool) -> Vector3:
	var dest := top.global_position if to_top else bottom.global_position
	if player == null:
		return dest
	# F2: a player with a traversal driver climbs over time (ladder clip, scripted move); anything else is moved at once.
	var trav: Variant = player.get("_trav")
	if trav is Object and (trav as Object).has_method("begin_ladder") \
			and bool((trav as Object).call("begin_ladder", global_position, dest, to_top, func() -> void: climbed.emit(to_top))):
		return dest
	player.global_position = dest
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
	if player.has_method("reset_physics_interpolation"):
		player.call("reset_physics_interpolation")
	climbed.emit(to_top)
	return dest


func _build_visual(h: float) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.4, 0.27, 0.15)
	wood.roughness = 0.95
	var mid := Vector3(0, h * 0.5, 0)
	for sx in [-0.22, 0.22]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.06, h, 0.06)
		rail.mesh = rm
		rail.material_override = wood
		rail.position = mid + Vector3(sx, 0, 0)
		add_child(rail)
	var rungs := int(h / 0.32)
	for i in rungs:
		var rung := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(0.44, 0.04, 0.04)
		rung.mesh = gm
		rung.material_override = wood
		rung.position = Vector3(0, 0.3 + float(i) * 0.32, 0)
		add_child(rung)
