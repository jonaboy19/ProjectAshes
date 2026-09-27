class_name Critter
extends Node3D
## An ordinary animal (CC0, incoming/animals): wanders around a home spot,
## grazes or pecks, and the skittish ones bolt when the player comes close.
## No physics or navigation: it follows the terrain, like wolves and soldiers,
## so dozens cost almost nothing.

const DIR := "res://assets/incoming/animals/"
## kind -> [file, walk speed, run speed, wander radius, skittish distance (0 = tame)]
const KINDS := {
	"chicken": ["procedural/chicken.glb", 0.6, 2.2, 5.0, 2.5],
	"rooster": ["procedural/rooster.glb", 0.6, 2.2, 5.0, 2.5],
	"duck": ["procedural/duck.glb", 0.5, 1.8, 8.0, 4.0],
	"goose": ["procedural/goose.glb", 0.55, 1.8, 8.0, 3.0],
	"pigeon": ["procedural/pigeon.glb", 0.4, 1.6, 6.0, 3.0],
	"crow": ["procedural/crow.glb", 0.4, 1.6, 8.0, 5.0],
	"rabbit": ["procedural/rabbit.glb", 0.7, 5.0, 10.0, 7.0],
	"dog": ["quaternius/dog.glb", 1.1, 4.0, 12.0, 0.0],
	"sheepdog": ["quaternius/sheepdog.glb", 1.1, 4.0, 14.0, 0.0],
	"cat": ["quaternius/cat.glb", 0.5, 2.5, 6.0, 1.5],
	"cat_ginger": ["quaternius/cat_ginger.glb", 0.5, 2.5, 6.0, 1.5],
	"cow": ["quaternius/cow.glb", 0.7, 2.0, 9.0, 0.0],
	"ox": ["quaternius/ox.glb", 0.7, 2.0, 7.0, 0.0],
	"sheep": ["quaternius/sheep.glb", 0.6, 2.4, 9.0, 3.0],
	"pig": ["quaternius/pig.glb", 0.6, 2.2, 6.0, 2.0],
	"goat": ["quaternius/goat.glb", 0.7, 2.8, 8.0, 3.0],
	"horse": ["quaternius/horse_riding.glb", 0.9, 5.0, 4.0, 0.0],
	"horse_grey": ["quaternius/horse_grey.glb", 0.9, 5.0, 4.0, 0.0],
	"horse_draft": ["quaternius/horse_draft.glb", 0.8, 4.0, 4.0, 0.0],
	"donkey": ["quaternius/donkey.glb", 0.7, 3.0, 4.0, 0.0],
	"deer": ["quaternius/deer.glb", 0.9, 7.0, 18.0, 16.0],
	"stag": ["quaternius/stag.glb", 0.9, 7.0, 18.0, 18.0],
	"fox": ["quaternius/fox.glb", 0.8, 5.0, 14.0, 9.0],
}

var kind := "chicken"
var home := Vector2.ZERO
var _anim: AnimationPlayer
var _target := Vector2.ZERO
var _pause := 0.0
var _fleeing := 0.0
var _cfg: Array


func _ready() -> void:
	_cfg = KINDS[kind]
	var path := DIR + String(_cfg[0])
	if not ResourceLoader.exists(path):
		queue_free()
		return
	var model: Node3D = (load(path) as PackedScene).instantiate()
	add_child(model)
	_anim = Assets.animation_player(model)
	if _anim:
		for a in ["Idle", "Walk", "Run", "Eat", "Walk_Slow"]:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	rotation.y = randf() * TAU
	_pause = randf_range(0.0, 4.0)
	_pick()


func _pick() -> void:
	var r: float = _cfg[3]
	var a := randf() * TAU
	_target = home + Vector2(cos(a), sin(a)) * randf_range(0.5, r)


func _physics_process(delta: float) -> void:
	var here := Vector2(global_position.x, global_position.z)
	var shy: float = _cfg[4]
	if shy > 0.0 and _fleeing <= 0.0:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player and here.distance_to(Vector2(player.global_position.x, player.global_position.z)) < shy:
			var away := (here - Vector2(player.global_position.x, player.global_position.z)).normalized()
			_target = here + away * shy * 1.6
			_fleeing = 2.0
			_pause = 0.0
	_fleeing -= delta
	if _pause > 0.0:
		_pause -= delta
		if _pause <= 0.0:
			_pick()
		return
	var to := _target - here
	var speed: float = _cfg[2] if _fleeing > 0.0 else _cfg[1]
	if to.length() < 0.25:
		# Arrived: idle or graze a while.
		_pause = randf_range(2.0, 7.0)
		_play("Eat" if randf() < 0.5 else "Idle")
		return
	var step := to.normalized() * minf(speed * delta, to.length())
	var p := here + step
	global_position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.y), 8.0 * delta)
	_play("Run" if _fleeing > 0.0 else "Walk")


func _play(n: String) -> void:
	if _anim and _anim.has_animation(n) and _anim.current_animation != n:
		_anim.play(n, 0.2)
	elif _anim and n == "Eat" and not _anim.has_animation("Eat") and _anim.has_animation("Idle"):
		_anim.play("Idle", 0.2)
