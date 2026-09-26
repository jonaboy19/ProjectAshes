class_name BlessingBolt
extends Node3D
## Elemental projectile fired by a blessing. Colour and stats come from blessings.json.

var color := Color.WHITE
var damage := 20
var speed := 20.0
var direction := Vector3.FORWARD
var _life := 1.6


func _ready() -> void:
	var orb := Props.part(self, Props.sphere(0.25, 8, 5), color)
	orb.material_override = Props.mat(color, 3.0)


func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	_life -= delta
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy.global_position.distance_to(global_position - Vector3(0, 0.8, 0)) < 1.1:
			enemy.take_damage(damage, self)
			queue_free()
			return
	if _life <= 0.0:
		queue_free()
