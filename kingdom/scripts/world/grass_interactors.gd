extends Node
## Feeds the grass and water shaders with up to MAX things that touch them:
## the player first, then the nearest embodied villagers, combatants (wolves,
## soldiers, beasts) and ambient critters. Grass bends away and flattens under
## them; water rings out where they wade or swim.
##
## The data lives in shader globals so every grass chunk and water chunk reads
## the same values with one set per frame. The globals are added at runtime
## (RenderingServer.global_shader_parameter_add), so project.godot needs no
## [shader_globals] entry; ensure_globals() is safe to call any number of times.
##   ashes_interactor_0 .. _7 : vec4(world x, y (feet), z, radius in metres)
##   ashes_interactor_count   : int, how many of the slots are live
## (Godot 4.6 does not allow global uniform arrays, hence eight vec4 slots.)
##
## GrassField spawns one of these on first use (ensure_running), so main.gd does
## not have to. It is plain Node work: one group scan every RESCAN seconds,
## then MAX global sets per frame.

const MAX := 8
const SLOT := "ashes_interactor_%d"
const COUNT := &"ashes_interactor_count"
## Candidates further than this from the player are ignored.
const REACH := 32.0
const RESCAN := 0.25
const PLAYER_RADIUS := 0.9
const VILLAGER_RADIUS := 0.7
const COMBATANT_RADIUS := 0.85
const CRITTER_RADIUS := 0.55
## Critter.kind -> trample radius (m). Anything missing uses CRITTER_RADIUS.
const KIND_RADIUS := {
	"horse": 1.1, "cow": 1.15, "ox": 1.15, "stag": 0.9, "deer": 0.85, "sheep": 0.8,
	"pig": 0.75, "goat": 0.7, "boar": 0.85, "bear": 1.2, "dog": 0.5, "sheepdog": 0.5,
	"fox": 0.45, "cat": 0.35, "rabbit": 0.3, "hen": 0.3, "chicken": 0.3, "duck": 0.35,
	"goose": 0.4,
}

## Seconds between slow ticks (see on_slow_tick).
const SLOW_TICK := 0.5

static var _globals_added := false
static var _slow_ticks: Array[Callable] = []
static var _instance: Node = null

var _player: Node3D = null
var _others: Array[Node3D] = []
var _radii: Array[float] = []
var _scan_timer := 0.0
var _ambient: Node = null
var _last_count := -1
var _slot_last := PackedVector4Array()      # what each slot held when it was last sent (NaN = never)
var _slot_names: Array[String] = []
var _slow_timer := 0.0


static func _static_init() -> void:
	# Register as soon as the script loads, before any grass or water material
	# is drawn, so the shaders never read a missing global.
	ensure_globals()


## Adds the shader globals once per process. Skips any the project already
## declares in project.godot, so moving them there later does not double-add.
static func ensure_globals() -> void:
	if _globals_added or Engine.has_meta(&"ashes_interactor_globals"):
		_globals_added = true
		return
	_globals_added = true
	Engine.set_meta(&"ashes_interactor_globals", true)
	for i in MAX:
		var slot := SLOT % i
		if not ProjectSettings.has_setting("shader_globals/" + slot):
			RenderingServer.global_shader_parameter_add(slot, RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
	if not ProjectSettings.has_setting("shader_globals/" + String(COUNT)):
		RenderingServer.global_shader_parameter_add(COUNT, RenderingServer.GLOBAL_VAR_TYPE_INT, 0)


## Makes sure one feeder node is alive in the tree (called by GrassField).
static func ensure_running() -> void:
	ensure_globals()
	if _instance != null and is_instance_valid(_instance):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var feeder: Node = (load("res://scripts/world/grass_interactors.gd") as GDScript).new()
	feeder.name = "GrassInteractors"
	_instance = feeder
	tree.root.add_child.call_deferred(feeder)


## Registers a callable to run at 2 Hz while the feeder is alive (GrassField
## uses it to follow Weather.wind_strength without a node of its own).
static func on_slow_tick(fn: Callable) -> void:
	if not _slow_ticks.has(fn):
		_slow_ticks.append(fn)


func _ready() -> void:
	if _instance != null and _instance != self and is_instance_valid(_instance):
		queue_free()   # someone added a second one by hand
		return
	_instance = self
	process_priority = 100   # after actors have moved this frame


func _exit_tree() -> void:
	if _instance == self:
		_instance = null
		RenderingServer.global_shader_parameter_set(COUNT, 0)


func _process(delta: float) -> void:
	_slow_timer -= delta
	if _slow_timer <= 0.0:
		_slow_timer = SLOW_TICK
		for fn in _slow_ticks:
			if fn.is_valid():
				fn.call()
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Node3D
		_others.clear()
		_ambient = null
		if _player == null:
			_publish_count(0)
			return
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = RESCAN
		_rescan()
	var n := 0
	_set_slot(n, _player.global_position, PLAYER_RADIUS)
	n += 1
	for i in _others.size():
		var o := _others[i]
		if not is_instance_valid(o) or not o.is_inside_tree() or not o.visible:
			continue
		_set_slot(n, o.global_position, _radii[i])
		n += 1
		if n >= MAX:
			break
	_publish_count(n)


func _set_slot(i: int, p: Vector3, r: float) -> void:
	# CPU pass 2026-10-06: a slot whose value did not change since the last frame (a player standing still, a resting villager) is
	# not sent to the renderer again, and the slot names are built once instead of formatting a string per slot per frame.
	var v := Vector4(p.x, p.y, p.z, r)
	if _slot_last.size() != MAX:
		_slot_last.resize(MAX)
		_slot_last.fill(Vector4(NAN, NAN, NAN, NAN))
		for k in MAX:
			_slot_names.append(SLOT % k)
	if _slot_last[i] == v:
		return
	_slot_last[i] = v
	RenderingServer.global_shader_parameter_set(_slot_names[i], v)


func _publish_count(n: int) -> void:
	if n != _last_count:
		_last_count = n
		RenderingServer.global_shader_parameter_set(COUNT, n)


## Picks the MAX - 1 nearest bodies to the player (not the player itself).
func _rescan() -> void:
	var here := _player.global_position
	var found: Array = []   # [distance², node, radius]
	var seen := {}
	var reach2 := REACH * REACH
	for v in get_tree().get_nodes_in_group("villager"):
		_consider(v, VILLAGER_RADIUS, here, reach2, found, seen)
	for c in get_tree().get_nodes_in_group("combatant"):
		_consider(c, COMBATANT_RADIUS, here, reach2, found, seen)
	if _ambient == null or not is_instance_valid(_ambient):
		_ambient = _find_ambient()
	if _ambient != null:
		for c in _ambient.get_children():
			var kind: Variant = c.get("kind")
			if kind == null:
				continue
			_consider(c, float(KIND_RADIUS.get(String(kind), CRITTER_RADIUS)), here, reach2, found, seen)
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	_others.clear()
	_radii.clear()
	for f: Array in found:
		if _others.size() >= MAX - 1:
			break
		_others.append(f[1])
		_radii.append(f[2])


func _consider(node: Node, radius: float, here: Vector3, reach2: float, found: Array, seen: Dictionary) -> void:
	var n3 := node as Node3D
	if n3 == null or n3 == _player or seen.has(n3) or not n3.is_inside_tree():
		return
	seen[n3] = true
	var d2 := n3.global_position.distance_squared_to(here)
	if d2 < reach2:
		found.append([d2, n3, radius])


## AmbientLife (main.gd adds it next to the player under the world node) owns
## the critters; they join no group, so look for their parent once.
func _find_ambient() -> Node:
	var world := _player.get_parent()
	if world == null:
		return null
	for c in world.get_children():
		if c.get_script() != null and (c.get_script() as Script).resource_path.ends_with("ambient_life.gd"):
			return c
	return null
