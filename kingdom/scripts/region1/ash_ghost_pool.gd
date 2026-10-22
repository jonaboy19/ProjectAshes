class_name AshGhostPool
extends Node3D
## A fixed pool of Ashsight ghosts: instantiated once (a small scene each), given a real
## humanoid body once (UAL characters through `Assets`), recycled forever, never allocated
## during a replay. When it runs dry `acquire()` returns null and the caller simply skips that
## actor (a replay never has more than a handful: AshMemory.MAX_ACTORS caps it).
##
## Bodies are built in `warm()`, one ghost per frame so nothing hitches (call it when Region 1
## loads or when Ashsight is first offered; a ghost without a body yet shows the robed
## placeholder). `set_detail()` / `detail` pick the visual tier from `Quality` (LOW keeps a
## single cheap shader pass and few particles).

signal warmed

const GHOST_SCENE := preload("res://scenes/region1/ash_ghost.tscn")
const BANDIT_BODY := "res://assets/incoming/ai3d/meshy/armored/bandit"
const VILLAGER_BODIES := ["villager_man_a", "villager_woman_a", "villager_farmer", "villager_woman_b"]

@export var capacity := 8
## How many of the bodies are bandits; the rest are villagers.
@export var bandit_bodies := 5
## -1 = read `Quality` (LOW 0, MEDIUM 1, HIGH/ULTRA 2). Set 0..2 to force a tier.
@export var detail_override := -1

var detail := 2
var warmed_up := false
var _free: Array[AshGhost] = []
var _all: Array[AshGhost] = []
var _body_role: Dictionary = {}   # AshGhost -> "bandit" | "villager"


func _ready() -> void:
	detail = tier_from_quality() if detail_override < 0 else detail_override
	for i in capacity:
		var g := GHOST_SCENE.instantiate() as AshGhost
		g.detail = detail
		add_child(g)
		g.set_detail(detail)
		g.deactivate()
		_free.append(g)
		_all.append(g)


## 0 LOW, 1 MEDIUM, 2 HIGH from the `Quality` autoload (HIGH when it is missing).
static func tier_from_quality() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return 2
	var q := tree.root.get_node_or_null("Quality")
	if q == null:
		return 2
	var t := int(q.get("tier"))
	return 0 if t <= 0 else (1 if t == 1 else 2)


## Give every ghost its real body, one per frame. Awaitable: `await pool.warm()`.
func warm() -> void:
	if warmed_up:
		return
	var vi := 0
	for i in _all.size():
		var g := _all[i]
		var bandit := i < bandit_bodies
		var body: Node3D
		if bandit:
			body = Assets.mh_character(BANDIT_BODY, 1.85)
		else:
			body = Assets.mh_character(VILLAGER_BODIES[vi % VILLAGER_BODIES.size()], 1.68)
			vi += 1
		g.set_model(body, 1.85 if bandit else 1.68)
		g.prewarm_clips()
		_body_role[g] = "bandit" if bandit else "villager"
		if is_inside_tree():
			await get_tree().process_frame
	await _prewarm_draw()
	warmed_up = true
	warmed.emit()


## Draw every ghost once, fully transparent, in front of the camera so the shaders and the pipeline
## are compiled now and not on the first frame of the first replay (about 5 ms otherwise).
func _prewarm_draw() -> void:
	if not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := cam.global_position - cam.global_transform.basis.z * 4.0
	var mem_entry := {"heading": 0.0, "alpha": 0.0, "ash": 0.0, "speed": 0.0}
	for g in _all:
		g.activate("bandit")
		g.stop_particles()
		g.apply(mem_entry, at, 0.0, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	for g in _all:
		g.deactivate()


func set_detail(d: int) -> void:
	detail = clampi(d, 0, 2)
	for g in _all:
		g.set_detail(detail)


func acquire(role: String = "") -> AshGhost:
	if _free.is_empty():
		return null
	# prefer a ghost whose body matches the role
	var pick := -1
	for i in range(_free.size() - 1, -1, -1):
		if String(_body_role.get(_free[i], "")) == role:
			pick = i
			break
	var g: AshGhost = _free.pop_at(pick) if pick >= 0 else _free.pop_back()
	g.activate(role)
	return g


func release(g: AshGhost) -> void:
	if g == null or not g.active:
		return
	g.deactivate()
	_free.append(g)


func release_all() -> void:
	for g in _all:
		release(g)


func free_count() -> int:
	return _free.size()


func active_count() -> int:
	return _all.size() - _free.size()
