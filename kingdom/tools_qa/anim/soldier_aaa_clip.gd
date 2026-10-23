extends Node3D
## A bandit Soldier swinging at a dummy target with the AAA clips (docs/anim/aaa_wiring/): every attack move in turn, then a block,
## a light hit from the left and from the right, and a guard break. Events go to stdout as "CLIP f=<physics frame> ...".
##   Godot --path kingdom --rendering-method mobile res://tools_qa/anim/soldier_aaa_clip.tscn --write-movie o.png --fixed-fps 30
##         --quit-after 600 -- [--twohand] [--legacy]
## --legacy turns the AAA clips off (the old Sword_Light_n swings) to compare the numbers.

const SoldierScript := preload("res://scripts/army/soldier.gd")

class Dummy extends CharacterBody3D:
	var dead := false
	var hits: Array = []
	func take_damage(amount: int, _from: Node = null, _kb := Vector3.ZERO) -> void:
		hits.append(Engine.get_physics_frames())

var _b: Node3D
var _t: Dummy
var _n := 0
var _next := 30
var _log := []


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--legacy"):
		(load("res://scripts/actors/aaa_clips.gd") as GDScript).set("enabled", false)
	var fl := StaticBody3D.new()
	var sh := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(60, 2, 60)
	sh.shape = bx
	fl.add_child(sh)
	fl.position = Vector3(0, -1, 0)
	var pl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	pl.mesh = pm
	pl.position = Vector3(0, 1.0, 0)
	fl.add_child(pl)
	add_child(fl)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.7, 0.8, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.72)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	add_child(sun)
	_t = Dummy.new()
	_t.add_to_group("player")
	add_child(_t)
	_t.global_position = Vector3(0, 0.1, 2.0)
	var keep: Array[String] = ["2H_Sword"] if OS.get_cmdline_user_args().has("--twohand") else ["Sword"]
	_b = SoldierScript.create(1, "", "Guard", keep)
	add_child(_b)
	_b.global_position = Vector3(0, 0.1, 0)
	_b._attack_cooldown = 999.0
	_b.combat_target = _t
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(3.2, 1.5, 1.0)
	cam.look_at(Vector3(0, 1.0, 0.8))
	cam.current = true


func _physics_process(_d: float) -> void:
	var f := Engine.get_physics_frames()
	_b.set("_busy", 0.0)
	_b.global_position = Vector3(0, 0.1, 0)
	_b.rotation.y = 0.0
	if f < _next:
		return
	var moves: Array = _b._fighter.moves() if _b._fighter != null and _b._fighter.has_method("moves") else []
	_next = f + 100
	match _n % 6:
		0, 1, 2:
			_b.set("_attack_cooldown", 0.0)
			_t.hits.clear()
			_b._attack()
			var mv: Resource = _b.get("_cur_move")
			print("CLIP f=%d attack move=%s clip=%s" % [f, String(mv.id) if mv != null else "-", _b._animator.player.current_animation if _b._animator != null else "?"])
		3:
			_b.set("_guard", 0.0)
			_b.take_damage(3, _t, Vector3(0, 0, 1))
			print("CLIP f=%d take_damage front" % f)
		4:
			_b.break_guard(0.9)
			print("CLIP f=%d break_guard" % f)
		5:
			_b.take_damage(2, _t, Vector3(1, 0, 0))
			print("CLIP f=%d take_damage side" % f)
	_n += 1
