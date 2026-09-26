class_name Squad
extends Node3D
## Formation-level AI. The squad decides where the block of men stands and
## which way it faces; each soldier only walks to its slot and fights whatever
## is nearest. One brain per hundred men, not a hundred brains.

signal wiped_out(squad: Squad)
signal strength_changed(alive: int)

enum Order { FOLLOW, HOLD, CHARGE }

const SPACING := 1.8

var team := 0
var order := Order.HOLD
var soldiers: Array[Soldier] = []
var anchor := Vector3.ZERO
var facing := Vector3.FORWARD
## FOLLOW keeps the block behind this node (the player).
var leader: Player
## Enemy squads charge when a hostile comes this close to the anchor.
var aggro_radius := 0.0

var banner: Label3D
var _look := ""
var _file := ""
var _keep: Array[String] = []


func setup(team_id: int, look: String, file: String, keep: Array[String]) -> Squad:
	team = team_id
	_look = look
	_file = file
	_keep = keep
	return self


func _ready() -> void:
	# Screen-constant banner so formations stay readable in town/command view.
	banner = Label3D.new()
	banner.fixed_size = true
	banner.pixel_size = 0.0022
	banner.font_size = 36
	banner.outline_size = 10
	banner.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	banner.no_depth_test = true
	banner.modulate = Color("7fb2ff") if team == 0 else Color("ff6b5b")
	add_child(banner)


func add_soldiers(count: int, near: Vector3) -> void:
	for i in count:
		var s := Soldier.create(team, _look, _file, _keep)
		s.squad = self
		get_parent().add_child(s)
		var p := near + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		p.y = WorldGen.height(p.x, p.z)
		s.global_position = p
		s.died.connect(_on_soldier_died)
		soldiers.append(s)
	strength_changed.emit(soldiers.size())


func alive() -> int:
	return soldiers.size()


func command(new_order: Order) -> void:
	order = new_order
	if order == Order.HOLD and leader:
		anchor = leader.global_position
		facing = leader.forward()


func _physics_process(delta: float) -> void:
	if soldiers.is_empty():
		return
	if aggro_radius > 0.0 and order != Order.CHARGE:
		for enemy in get_tree().get_nodes_in_group("team%d" % (1 - team)):
			if (enemy as Node3D).global_position.distance_to(anchor) < aggro_radius:
				order = Order.CHARGE
				break
	if order == Order.FOLLOW and leader:
		var fwd: Vector3 = leader.forward()
		fwd.y = 0.0
		fwd = fwd.normalized()
		var want := leader.global_position - fwd * 4.5
		anchor = anchor.lerp(want, clampf(delta * 3.0, 0.0, 1.0)) if anchor.distance_to(want) < 30.0 else want
		facing = facing.lerp(fwd, clampf(delta * 2.0, 0.0, 1.0)).normalized()
	_update_banner()
	var cols := maxi(1, ceili(sqrt(soldiers.size() * 2.0)))
	var right := facing.cross(Vector3.UP).normalized()
	for i in soldiers.size():
		var row := i / cols
		var col := i % cols
		var slot := anchor + right * (col - (cols - 1) * 0.5) * SPACING - facing * row * SPACING
		slot.y = WorldGen.height(slot.x, slot.z)
		soldiers[i].slot_target = slot


func _update_banner() -> void:
	var center := Vector3.ZERO
	for s in soldiers:
		center += s.global_position
	center /= soldiers.size()
	banner.global_position = center + Vector3(0, 4.0, 0)
	var cam := get_viewport().get_camera_3d()
	banner.visible = cam != null and cam.global_position.distance_to(center) > 22.0
	banner.text = "%s %d" % ["⚑" if team == 0 else "☠", soldiers.size()]


func _on_soldier_died(s: Soldier) -> void:
	soldiers.erase(s)
	strength_changed.emit(soldiers.size())
	if soldiers.is_empty():
		banner.visible = false
		wiped_out.emit(self)
