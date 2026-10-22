extends Node3D
## The Thornfield grain cart (quest "Wolves at the Grain Carts"): a real actor with health that the wolves of the pack
## can hunt (Wolf prefers its `prey` meta over the player unless the player is close) and that rolls from the tithe
## barn to the mill once told to. It speaks to the quest bus as the actor `grain_cart_1`:
##   died {actor}              when it is destroyed (Protect and Escort fail)
##   arrive {actor, place}     when it reaches the mill (Escort completes)
##   actor_pos {actor, x, y}   every second it moves (Escort by position)
## Ducks the Wolf contract: `global_position`, `take_damage(amount, from, knockback)`, `dead`, `blocking`.
## No collider on purpose: a world-layer body would sit between a wolf and its target (Tokens.can_hit casts a ray).

signal destroyed(cart: Node3D)
signal arrived(cart: Node3D)

const WAGON := "res://assets/generated/props/covered_wagon.glb"
const SACKS := "res://assets/generated/props/sack_pile.glb"
const SPEED := 2.1
const WAIT_FOR_PLAYER := 28.0
const ARRIVE_RADIUS := 3.0

var actor_id := "grain_cart_1"
var dest_place := "thornfield_mill"
var max_health := 120
var health := 120
var dead := false
var blocking := false
var route: PackedVector2Array = PackedVector2Array()
var moving := false
var finished := false

var _leg := 0
var _pos_acc := 0.0
var _said_wait := false
var _model: Node3D


func _ready() -> void:
	add_to_group("grain_cart")
	name = "GrainCart"
	_model = Node3D.new()
	add_child(_model)
	var wagon := _load(WAGON, 3.2)
	if wagon != null:
		_model.add_child(wagon)
	else:
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.8, 1.0, 3.0)
		box.mesh = bm
		box.position.y = 0.9
		_model.add_child(box)
	var sacks := _load(SACKS, 1.1)
	if sacks != null:
		sacks.position = Vector3(0, 1.0, -0.2)
		_model.add_child(sacks)


## A scene instanced and scaled so its longest side is `size` metres, or null when it is not imported.
static func _load(path: String, size: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var sc: PackedScene = Assets.scene(path)
	if sc == null:
		return null
	var n: Node3D = sc.instantiate()
	var box := Assets.visual_aabb(n)
	var k := size / maxf(maxf(box.size.x, box.size.z), 0.01)
	n.scale = Vector3.ONE * k
	n.position.y = -box.position.y * k
	return n


func place_at(p: Vector2) -> void:
	global_position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


func xz() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func start_route(points: PackedVector2Array) -> void:
	route = points
	_leg = 0
	moving = points.size() > 1
	finished = false


func take_damage(amount: int, _from: Node = null, _knockback := Vector3.ZERO) -> void:
	if dead or amount <= 0:
		return
	health -= amount
	if _model != null:
		var t := create_tween()
		t.tween_property(_model, "rotation:z", 0.05, 0.05)
		t.tween_property(_model, "rotation:z", 0.0, 0.12)
	if health <= 0:
		dead = true
		moving = false
		if _model != null:
			var t2 := create_tween()
			t2.tween_property(_model, "rotation:z", 0.45, 0.6)
		QuestBus.shared().emit_event(&"died", {"actor": actor_id})
		destroyed.emit(self)


func repair() -> void:
	health = max_health


func _physics_process(delta: float) -> void:
	if dead or finished:
		return
	var here := xz()
	if moving and route.size() > 1:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player != null and here.distance_to(Vector2(player.global_position.x, player.global_position.z)) > WAIT_FOR_PLAYER:
			if not _said_wait:
				_said_wait = true
				Game.say("The cart waits for you.")
			return          # an escort goes at the escort's pace: nobody drives off without the player
		_said_wait = false
		var goal := route[mini(_leg + 1, route.size() - 1)]
		var to := goal - here
		if to.length() <= ARRIVE_RADIUS * 0.5:
			_leg += 1
			if _leg + 1 >= route.size():
				_arrive()
				return
		else:
			var step := to.normalized() * SPEED * delta
			var p := here + step
			global_position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
			rotation.y = lerp_angle(rotation.y, atan2(to.x, to.y), 1.0 - exp(-3.0 * delta))
		_pos_acc += delta
		if _pos_acc >= 1.0:
			_pos_acc = 0.0
			var q := xz()
			QuestBus.shared().emit_event(&"actor_pos", {"actor": actor_id, "x": q.x, "y": q.y})


func _arrive() -> void:
	moving = false
	finished = true
	QuestBus.shared().emit_event(&"arrive", {"actor": actor_id, "place": dest_place})
	arrived.emit(self)
