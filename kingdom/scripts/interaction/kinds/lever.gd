class_name Lever
extends Node3D
## A wall lever: "Pull" flips it and tells whatever is wired to it. Wire with the `toggled` signal or `on_pull`
## (Callable(is_on: bool)). A `once` lever stays pulled. State is in `pulled`; saving it is the world-state
## package's job (see ashes-world-interaction: levers are 1-DOF state with targets).

signal toggled(is_on: bool)

var pulled := false
var once := false
var lever_id := ""
var on_pull := Callable()
var _stick: Node3D


static func spawn(parent: Node, pos: Vector3, id: String, yaw := 0.0, is_once := false) -> Lever:
	var l := Lever.new()
	l.lever_id = id
	l.once = is_once
	l.name = "Lever_" + id.replace("/", "_")
	parent.add_child(l)
	l.global_position = pos
	l.rotation.y = yaw
	return l


func _ready() -> void:
	_build_visual()
	Interactable.attach(self, {"id_fn": func() -> String: return "lever/%s" % lever_id, "verb": "Pull", "target": "Lever",
		"range": 2.4, "can": func(_p: Node) -> bool: return not (once and pulled),
		"do": func(_p: Node) -> void: pull(),
		"label": func() -> Dictionary: return {"verb": "Pull", "target": "Lever"}})


## Flips the lever. Returns the new state.
func pull() -> bool:
	if once and pulled:
		return pulled
	pulled = not pulled
	if _stick != null:
		var tw := create_tween()
		tw.tween_property(_stick, "rotation:z", -0.8 if pulled else 0.8, 0.25)
	Game.say("The lever clunks %s." % ("down" if pulled else "back up"))
	toggled.emit(pulled)
	if on_pull.is_valid():
		on_pull.call(pulled)
	return pulled


func _build_visual() -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.25, 0.25, 0.27)
	iron.metallic = 0.4
	iron.roughness = 0.6
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.25, 0.3, 0.08)
	base.mesh = bm
	base.material_override = iron
	add_child(base)
	_stick = Node3D.new()
	_stick.rotation.z = 0.8
	add_child(_stick)
	var stick := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.05, 0.4, 0.05)
	stick.mesh = sm
	stick.material_override = iron
	stick.position = Vector3(0, 0.2, 0.07)
	_stick.add_child(stick)
