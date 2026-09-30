class_name InteriorDoor
extends Area3D
## A doorway into (or out of) a building interior. Self-contained: drop it on a
## building's front door with a CollisionShape3D child, set `interior_scene`, done.
##
## ENTRANCE (is_exit = false): when the player stands in the area and presses
## "interact", the interior scene is instanced as a sibling of the player,
## `interior_offset` metres above the door (so terrain/water height clamps in the
## player and camera code never fight the floor), the exterior siblings of the
## player are hidden (and optionally paused), the player is moved to the marker
## `spawn_name` and the camera gets the interior's Environment. Only one interior
## exists at a time (InteriorDoor.active); it is freed on exit and the player is
## put back just outside this door.
##
## EXIT (is_exit = true): lives inside the interior scene (node "ExitDoor"); it
## only emits `exit_requested`, which the entrance door that loaded the room
## listens to.
##
## While the player is in range the door joins the "interactable" group and
## offers `prompt()`, so the HUD shows its button like any other station.
##
## Cost: a town builds one door per house, so an idle door does no per-frame
## work at all. Only the door the player stands in processes (and only when no
## external dispatcher handles "interact", see `external_dispatch`), and only the
## active entrance runs the camera ray in _physics_process. Street doors use
## `PLAYER_TRIGGER_LAYER` as their only mask so they never pair with terrain or
## building colliders.

signal player_in_range_changed(in_range: bool)
## The interior was instanced and the player moved inside.
signal interior_entered(interior: Node3D)
## The player came back out; the interior has been freed.
signal interior_exited
## Exit doors: the player asked to leave.
signal exit_requested

## The interior to load (e.g. "res://scenes/interiors/inn_interior.tscn").
@export_file("*.tscn") var interior_scene := ""
## Marker3D in the interior where the player appears.
@export var spawn_name := "PlayerSpawn"
@export var prompt_text := "Enter"
@export var is_exit := false
## Where the interior is placed, relative to this door (world axes).
@export var interior_offset := Vector3(0, 300, 0)
## Where the player is returned, in this door's local space (+Z = out of the door
## when the door node faces the street).
@export var return_offset := Vector3(0, 0, 1.6)
## Hide the player's sibling nodes (terrain, town, sun...) while inside.
@export var hide_exterior := true
## Also stop processing them (saves CPU; off by default so simulations keep running).
@export var pause_exterior := false
## Pull the chase camera in front of interior walls.
@export var camera_collision := true
@export_flags_3d_physics var camera_collision_mask := 1
## Force the third-person view while inside (the town/command zooms don't fit a room).
@export var force_third_person := true

## Physics layer 20: the player carries it (main.gd) so door triggers can mask
## only the player instead of every body on layer 1.
const PLAYER_TRIGGER_LAYER := 1 << 19

static var active: InteriorDoor = null
## True when the game's own interact handler calls use() on the nearest door
## (main.gd does). Doors then never poll input, so one key press can't both
## close a menu / open a service and walk through a door.
static var external_dispatch := false

var interior: Node3D = null
var _player: Node3D = null
var _near := false
var _hidden: Array[Node3D] = []
var _paused: Array[Node] = []
var _cam: Camera3D = null
var _saved_env: Environment = null
var _saved_view := -1


func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	process_physics_priority = 100    # after the player moved its camera
	set_process(false)
	set_physics_process(active == self)


## Makes `player` detectable by street doors that mask PLAYER_TRIGGER_LAYER.
static func tag_player(player: CollisionObject3D) -> void:
	player.collision_layer |= PLAYER_TRIGGER_LAYER


func prompt() -> String:
	# A house lot the player owns or rents (scripts/sim/property.gd) reads
	# "Enter your home" instead of the generic prompt. Guarded so a build
	# without Life.property (or a non-house door with no "lot_pos" meta)
	# behaves exactly as before.
	if not is_exit and has_meta("lot_pos") and "property" in Life and Life.property != null \
			and Life.property.is_yours(get_meta("lot_pos")):
		return "Enter your home"
	return prompt_text


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player = body
		_near = true
		add_to_group("interactable")
		set_process(not external_dispatch)
		player_in_range_changed.emit(true)


func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_near = false
		if is_in_group("interactable"):
			remove_from_group("interactable")
		set_process(false)
		player_in_range_changed.emit(false)


func _process(_delta: float) -> void:
	if external_dispatch:
		set_process(false)
		return
	if not _near or _player == null or not Input.is_action_just_pressed("interact"):
		return
	# Another interactable (an NPC, a station) closer to the player wins the key press.
	if _player.has_method("nearest_interactable"):
		var nearest: Node3D = _player.call("nearest_interactable")
		if nearest != null and nearest != self:
			return
	use()


## Walk through: enter (entrance doors) or ask to leave (exit doors).
func use() -> void:
	if is_exit:
		exit_requested.emit()
	elif active == null:
		enter(_player if _player else get_tree().get_first_node_in_group("player") as Node3D)


func enter(player: Node3D) -> void:
	if player == null or active != null or not _can_enter():
		return
	_player = player
	interior = _make_interior()
	if interior == null:
		return
	# Standalone-only nodes: the preview camera and the scene's own WorldEnvironment
	# (its Environment goes on the player's camera instead, so the world's stays untouched).
	var env: Environment = null
	for we in interior.find_children("*", "WorldEnvironment", true, false):
		env = (we as WorldEnvironment).environment
		we.get_parent().remove_child(we)
		we.free()
	for c in interior.find_children("*", "Camera3D", true, false):
		c.get_parent().remove_child(c)
		c.free()
	interior.set_meta("embedded", true)
	var host := player.get_parent()
	host.add_child(interior)
	interior.global_transform = Transform3D(Basis.IDENTITY, global_position + interior_offset)
	active = self
	set_physics_process(camera_collision)
	if hide_exterior:
		for c in host.get_children():
			if c == player or c == interior or not (c is Node3D) or c.is_ancestor_of(self):
				continue
			var n := c as Node3D
			if n.visible:
				n.visible = false
				_hidden.append(n)
			if pause_exterior and n.process_mode != Node.PROCESS_MODE_DISABLED:
				n.process_mode = Node.PROCESS_MODE_DISABLED
				_paused.append(n)
		# Our own building is an ancestor of this door: hide it without pausing us.
		var up := get_parent()
		while up != null and up != host:
			if up is Node3D and (up as Node3D).visible and up.get_parent() == host:
				(up as Node3D).visible = false
				_hidden.append(up)
			up = up.get_parent()
	_cam = player.get("camera") as Camera3D if "camera" in player else get_viewport().get_camera_3d()
	if _cam and env:
		_saved_env = _cam.environment
		_cam.environment = env
	if force_third_person and "view" in player and player.has_method("set_view"):
		_saved_view = int(player.get("view"))
		player.call("set_view", 1)
	var spawn := interior.find_child(spawn_name, true, false) as Node3D
	var at: Transform3D = spawn.global_transform if spawn else interior.global_transform
	_place_player(at.origin, at.basis.get_euler().y)
	for d in interior.find_children("*", "Area3D", true, false):
		if d is InteriorDoor and (d as InteriorDoor).is_exit:
			(d as InteriorDoor).exit_requested.connect(leave)
	interior_entered.emit(interior)


## Hook for doors whose room is built in code (scripts/interiors/dungeon_door.gd): can this door open now?
func _can_enter() -> bool:
	return interior_scene != ""


## Hook: the interior root to place. Default: instance `interior_scene`.
func _make_interior() -> Node3D:
	var packed := Assets.scene(interior_scene)
	if packed == null:
		push_warning("InteriorDoor: cannot load %s" % interior_scene)
		return null
	return packed.instantiate() as Node3D


func leave() -> void:
	if active != self:
		return
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
	for n in _paused:
		if is_instance_valid(n):
			n.process_mode = Node.PROCESS_MODE_INHERIT
	_hidden.clear()
	_paused.clear()
	if _cam and is_instance_valid(_cam):
		_cam.environment = _saved_env
	if _saved_view >= 0 and is_instance_valid(_player):
		_player.call("set_view", _saved_view)
	_saved_view = -1
	if is_instance_valid(interior):
		interior.queue_free()
	interior = null
	active = null
	set_physics_process(false)
	if is_instance_valid(_player):
		var out := global_transform * return_offset
		var away := (out - global_position)
		# Face away from the door (camera yaw: forward = (-sin, 0, -cos)).
		_place_player(out, atan2(-away.x, -away.z) if away.length() > 0.01 else global_rotation.y)
	interior_exited.emit()


func _place_player(pos: Vector3, yaw: float) -> void:
	_player.global_position = pos
	if "velocity" in _player:
		_player.set("velocity", Vector3.ZERO)
	if _player.has_method("set_camera"):
		_player.call("set_camera", yaw, -0.28)
	if _player is CharacterBody3D:
		(_player as CharacterBody3D).reset_physics_interpolation()


func _physics_process(_delta: float) -> void:
	if active != self or not camera_collision or _cam == null or not is_instance_valid(_cam):
		return
	# The chase camera sits a few metres behind the player; keep it inside the room.
	var pivot := _cam.get_parent() as Node3D
	if pivot == null:
		return
	var from := pivot.global_position
	var to := _cam.global_position
	var q := PhysicsRayQueryParameters3D.create(from, to, camera_collision_mask)
	if _player is CollisionObject3D:
		q.exclude = [(_player as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var dir := (to - from).normalized()
		_cam.global_position = (hit["position"] as Vector3) - dir * 0.25 + (hit["normal"] as Vector3) * 0.05
