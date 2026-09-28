class_name Critter
extends Node3D
## An ordinary animal (CC0, incoming/animals): wanders around a home spot,
## grazes or pecks, and the skittish ones bolt when the player comes close.
## No physics or navigation: it follows the terrain, like wolves and soldiers,
## so dozens cost almost nothing.

const DIR := "res://assets/incoming/animals/"
const MOVE_ACCELERATION := 3.2
const MOVE_BRAKING := 5.5
## Reliable ground speeds from docs/qa/anim_qa_report.md. Entries with a zero
## measurement are intentionally omitted: the tiny, stylized cycles need visual
## authoring rather than a misleading speed inferred from bad foot contacts.
const ANIM_GROUND_SPEEDS := {
	"dog": {"Walk": 0.70, "Run": 1.71},
	"sheepdog": {"Walk": 0.71, "Run": 1.73},
	"cow": {"Walk": 1.06, "Run": 4.99},
	"ox": {"Walk": 1.01, "Run": 4.64},
	"sheep": {"Run": 1.92},
	"pig": {"Run": 1.29},
	"horse": {"Walk": 1.41, "Run": 5.86},
	"horse_grey": {"Walk": 1.36, "Run": 5.68},
	"horse_draft": {"Walk": 1.53, "Run": 6.41},
	"donkey": {"Walk": 1.30},
	"deer": {"Walk": 1.06, "Run": 2.4},
	"stag": {"Walk": 1.31, "Run": 2.8},
	"fox": {"Walk": 0.44, "Run": 1.87},
	"goat": {"Walk": 0.76},
}
## Deer/stag Run: planted-foot probe of the Run clip (2026-09-28), scaled by the
## same factor that maps the probe's Walk onto the QA report's Walk value.
## kind -> [file, walk speed, run speed, wander radius, skittish distance (0 = tame)]
## Flee bursts last two seconds. Deer and stag bolt at 6.0 / 6.2 m/s, just under
## the player's 6.5 m/s run (player.gd), so a hunter who keeps after them closes
## in slowly between bursts; everything else is slower still.
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
	"deer": ["quaternius/deer.glb", 0.9, 6.0, 18.0, 16.0],
	"stag": ["quaternius/stag.glb", 0.9, 6.2, 18.0, 18.0],
	"fox": ["res://assets/generated/animals/fox_gallop.glb", 0.8, 5.0, 14.0, 9.0],
}

var kind := "chicken"
var home := Vector2.ZERO
var _anim: AnimationPlayer
var _target := Vector2.ZERO
var _pause := 0.0
var _fleeing := 0.0
var _cfg: Array
var _move_speed := 0.0
var _idle_clip := "Idle"


func _ready() -> void:
	_cfg = KINDS[kind]
	var path := String(_cfg[0])
	if not path.begins_with("res://"):
		path = DIR + path
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
		_pause = maxf(_pause - delta, 0.0)
		if _pause == 0.0:
			_pick()
	var to := _target - here
	var distance := to.length()
	if _pause <= 0.0 and distance < 0.15:
		# Arrived: idle or graze a while.
		_pause = randf_range(2.0, 7.0)
		_idle_clip = "Eat" if randf() < 0.5 else "Idle"
	var wants_to_move := _pause <= 0.0 and distance >= 0.15
	var target_speed: float = 0.0
	if wants_to_move:
		target_speed = _cfg[2] if _fleeing > 0.0 else _cfg[1]
	var response := MOVE_ACCELERATION if target_speed > _move_speed else MOVE_BRAKING
	_move_speed = move_toward(_move_speed, target_speed, response * delta)
	if _move_speed > 0.02 and distance > 0.02:
		var step_speed := minf(_move_speed, distance / maxf(delta, 0.001))
		var step := to / distance * step_speed * delta
		var p := here + step
		global_position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.y), 1.0 - exp(-8.0 * delta))
		var gait := "Run" if _fleeing > 0.0 else "Walk"
		var authored_speed := float(ANIM_GROUND_SPEEDS.get(kind, {}).get(gait, 0.0))
		var rate := step_speed / authored_speed if authored_speed > 0.0 else 1.0
		_play(gait, clampf(rate, 0.35, 2.5))
	elif _move_speed <= 0.02:
		_play(_idle_clip)


func _play(n: String, rate := 1.0) -> void:
	if _anim == null:
		return
	_anim.speed_scale = rate
	if _anim.has_animation(n) and _anim.current_animation != n:
		_anim.play(n, 0.2)
	elif n == "Eat" and not _anim.has_animation("Eat") and _anim.has_animation("Idle"):
		_anim.play("Idle", 0.2)
