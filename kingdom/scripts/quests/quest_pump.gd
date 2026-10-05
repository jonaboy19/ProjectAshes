extends Node
## Feeds the quest bus from the running game: WorldSim hours (Wait, Protect), the player's position every half
## second (GoTo, Escort), and the watch samples for Observe (distance + Perception line of sight to the watched
## figure). Add one to the scene with QuestPump.attach(parent). Other systems fire their own events on
## QuestBus.shared() (kill, talk, interact, died, item, deliver, ...).
##
## Watched figures are registered with `watch(target_id, pos_fn, facing_fn)` (Callables returning Vector2).

const Observe := preload("res://scripts/quests/objectives/observe.gd")
const SAMPLE_EVERY := 0.5

var _acc := 0.0
var _watched: Dictionary = {}     # target id -> {pos: Callable, facing: Callable}


static var _live: Node = null       # the one pump of the running world (two pumps double every hours / observe event)


## The world's QuestPump. Village services and the Thornfield hub both ask for one: the second call gets the first's.
static func attach(parent: Node) -> Node:
	if _live != null and is_instance_valid(_live) and _live.is_inside_tree() and not _live.is_queued_for_deletion():
		return _live
	var p: Node = load("res://scripts/quests/quest_pump.gd").new()
	p.name = "QuestPump"
	parent.add_child(p)
	_live = p
	return p


func _ready() -> void:
	var ws := get_node_or_null("/root/WorldSim")
	if ws != null and ws.has_signal("hour_changed"):
		ws.hour_changed.connect(_on_hour)
	QuestHub.runner()


func _exit_tree() -> void:
	if _live == self:
		_live = null


func watch(target: String, pos_fn: Callable, facing_fn: Callable) -> void:
	_watched[target] = {"pos": pos_fn, "facing": facing_fn}


func unwatch(target: String) -> void:
	_watched.erase(target)


func _on_hour(hour: int) -> void:
	QuestBus.shared().emit_event(&"hours", {"amount": 1.0, "hour": float(hour)})


func _process(delta: float) -> void:
	_acc += delta
	if _acc < SAMPLE_EVERY:
		return
	var dt := _acc
	_acc = 0.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var bus := QuestBus.shared()
	bus.emit_event(&"position", {"x": pp.x, "y": pp.y})
	var ws := get_node_or_null("/root/WorldSim")
	var hour := float(ws.get("time_of_day")) if ws != null else 12.0
	for target: String in _watched:
		var w: Dictionary = _watched[target]
		var tpos: Vector2 = w["pos"].call()
		var facing: Vector2 = w["facing"].call()
		var stance := 0.6 if bool(player.get("crouching")) else 1.0
		var light: float = load("res://scripts/population/perception.gd").light_at(pp)
		var unseen := Observe.is_unseen(tpos, facing, pp, light, stance)
		bus.emit_event(&"observe", {"target": target, "dist": pp.distance_to(tpos), "unseen": unseen, "dt": dt, "hour": hour})
