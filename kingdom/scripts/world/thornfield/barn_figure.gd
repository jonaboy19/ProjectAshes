extends Node3D
## Wilm Garrow at the tithe barn after dark: the figure "The Spoiled Barley" asks the player to watch. A real body of
## the named drifter (his WorldSim row is `person`, so the talk system, name tag and relationship memory treat it as
## him; he sits in group "villager"). By day he is the ordinary resident his schedule makes him, and from 20:30 to
## 05:30 his row stays indoors at home while this body stands guard at the barn: pacing the door, kneeling by the
## sacks, and glancing toward the road, so a patient watcher sees him and a careless one is seen.
##
## QuestPump.watch("barn_figure", pos_fn, facing_fn) samples him through `watch_pos()` / `watch_facing()`.
## Night only: invisible and idle by day, so it costs nothing.

const Sites := preload("res://scripts/world/thornfield/sites.gd")
const NIGHT_FROM := 20.5
const NIGHT_TO := 5.5
const NEAR := 190.0
const SPEED := 0.75
const ID := "wilm_garrow"

var person := -1
var stand_at := Vector2.INF
var _a := Vector2.INF
var _b := Vector2.INF
var _goal := Vector2.INF
var _pause := 0.0
var _model: Node3D
var _anim: AnimationPlayer
var _talking := false
var _awake := false
var _heading := 0.0


## Spawns the figure under `parent` for Wilm's row (or a free-standing one when the roster is not bound).
static func spawn(parent: Node, row: int) -> Node3D:
	var f: Node3D = load("res://scripts/world/thornfield/barn_figure.gd").new()
	f.set("person", row)
	parent.add_child(f)
	return f


static func is_night(h: float) -> bool:
	return h >= NIGHT_FROM or h < NIGHT_TO


func _ready() -> void:
	name = "BarnFigure"
	add_to_group("villager")
	add_to_group("barn_figure")
	stand_at = Sites.figure_spot()
	if stand_at != Vector2.INF:
		var b := Sites.brewery()
		var along := Sites.to_world(b, Vector2(1, 0)) - (b["pos"] as Vector2)
		_a = stand_at
		_b = stand_at + along.normalized() * 3.4
		_goal = _b
		global_position = Vector3(_a.x, WorldGen.height(_a.x, _a.y), _a.y)
	_model = Assets.character("Rogue_Hooded", 1.74, [])
	add_child(_model)
	_anim = Assets.animation_player(_model)
	_play("Idle")
	_set_awake(false)


func _set_awake(on: bool) -> void:
	_awake = on
	visible = on
	set_physics_process(on)


func _play(clip: String) -> void:
	if _anim != null and _anim.has_animation(clip) and _anim.current_animation != clip:
		_anim.play(clip)


## Position Vector2 for QuestPump (a far-away point when he is not out).
func watch_pos() -> Vector2:
	return xz() if _awake else Vector2(1.0e7, 1.0e7)


func watch_facing() -> Vector2:
	return Vector2(sin(rotation.y), cos(rotation.y))


func xz() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func talk_begin(player: Node3D) -> void:
	_talking = true
	var to := player.global_position - global_position
	rotation.y = atan2(to.x, to.z)
	_play("Idle")


func talk_end() -> void:
	_talking = false


func _process(_delta: float) -> void:
	# Night check twice a second is plenty; the body is hidden (and its physics process off) the rest of the day.
	if Engine.get_process_frames() % 30 != 0:
		return
	var h: float = WorldSim.time_of_day
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var near := player != null and player.global_position.distance_to(global_position) < NEAR
	var want: bool = is_night(h) and near and stand_at != Vector2.INF
	if want != _awake:
		_set_awake(want)
		if want:
			global_position = Vector3(_a.x, WorldGen.height(_a.x, _a.y), _a.y)
			_goal = _b
			_pause = 2.0


func _physics_process(delta: float) -> void:
	if _talking:
		return
	if _pause > 0.0:
		_pause -= delta
		_play("Idle")
		return
	var here := xz()
	var to := _goal - here
	if to.length() < 0.25:
		# At an end of the beat: stand, look back toward the road, then go the other way.
		_pause = randf_range(4.0, 9.0)
		_goal = _a if _goal == _b else _b
		rotation.y = lerp_angle(rotation.y, _heading + PI * 0.5, 0.8)
		return
	var dir := to.normalized()
	var p := here + dir * SPEED * delta
	global_position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
	_heading = atan2(dir.x, dir.y)
	rotation.y = lerp_angle(rotation.y, _heading, 1.0 - exp(-5.0 * delta))
	_play("Walk")
