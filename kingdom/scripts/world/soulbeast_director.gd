extends Node
## F10: owns the one Soulbeast of a game. Finds its den at Thornfield's forest edge, spawns the beast (restored from
## the followers save when there is one), places the den's "Leave food" interactable, writes the beast into the save
## every few seconds and on exit, counts days, and tells a bonded beast when the player rested (a world-clock jump).
## Added to the world once by main.gd.

const Beast := preload("res://scripts/actors/soulbeast.gd")
const Save := preload("res://scripts/actors/soulbeast_save.gd")

const SAVE_EVERY := 15.0
const REST_JUMP_HOURS := 0.5     # the same skip threshold PopulationLOD uses
const DEN_MIN_DENSITY := 0.5

var beast: Node3D
var den_node: Node3D
var _acc := 0.0
var _day := -1
var _last_time := -1.0


func _ready() -> void:
	call_deferred("_spawn")


## Den site: the densest woodland 70-200 m past the village edge that is dry, found on a fixed ring search so the
## same world always gives the same den. Returns Vector2.INF when the world has no settlement yet.
static func find_den(village_pos: Vector2, village_radius: float) -> Vector2:
	var best := Vector2.INF
	var best_score := -1.0
	var r := village_radius + 70.0
	while r <= village_radius + 200.0:
		for i in 24:
			var a := float(i) / 24.0 * TAU
			var q := village_pos + Vector2(cos(a), sin(a)) * r
			if WorldGen.is_water(q.x, q.y):
				continue
			var dense := WorldGen.forest_density(q.x, q.y)
			if dense < DEN_MIN_DENSITY:
				continue
			var score := dense - (r - village_radius) * 0.0015      # prefer the forest edge near the village
			if score > best_score:
				best_score = score
				best = q
		r += 20.0
	if best == Vector2.INF:        # no real forest: the first dry spot on the ring
		for i in 24:
			var a2 := float(i) / 24.0 * TAU
			var q2 := village_pos + Vector2(cos(a2), sin(a2)) * (village_radius + 90.0)
			if not WorldGen.is_water(q2.x, q2.y):
				return q2
	return best


static func thornfield() -> Dictionary:
	for s in WorldGen.settlements:
		if String(s["name"]) == "Thornfield":
			return s
	return WorldGen.settlements[0] if not WorldGen.settlements.is_empty() else {}


func _spawn() -> void:
	var t := thornfield()
	if t.is_empty():
		return
	var fm: RefCounted = Life.realm.mod("followers") if Life.realm != null else null
	var den := find_den(t["pos"], float(t["radius"]))
	if den == Vector2.INF:
		return
	beast = Beast.new()
	beast.name = "Soulbeast"
	var saved := {}
	var probe: RefCounted = Beast.Brain.new()
	if fm != null and Save.load_into(fm, probe):
		saved = probe.to_dict()
	get_parent().add_child(beast)
	beast.setup(den, saved)
	_make_den(den)
	_day = WorldSim.day
	_last_time = WorldSim.time_of_day


func _make_den(den: Vector2) -> void:
	den_node = Node3D.new()
	den_node.name = "SoulbeastDen"
	get_parent().add_child(den_node)
	den_node.global_position = Vector3(den.x, WorldGen.height(den.x, den.y), den.y)
	den_node.add_to_group("soulbeast_den")
	Interactable.attach(den_node, {"id": "soulbeast/den", "verb": "Leave food", "target": "Soulbeast den",
		"range": 4.0, "priority": 1,
		"can": func(_p: Node) -> bool: return beast != null and is_instance_valid(beast) and not beast.brain.bonded \
			and beast._pick_food() != "",
		"do": func(p: Node) -> void: Game.say(beast.offer_food(p))})


func _process(delta: float) -> void:
	if beast == null or not is_instance_valid(beast):
		return
	var tod := WorldSim.time_of_day
	var jump := fposmod(tod - _last_time, 24.0)
	if _last_time >= 0.0 and jump > REST_JUMP_HOURS and jump < 14.0:
		beast.on_player_rest(jump)            # sleeping or waiting moved the clock on
	_last_time = tod
	if WorldSim.day != _day:
		_day = WorldSim.day
		beast.on_day()
	_acc += delta
	if _acc >= SAVE_EVERY:
		_acc = 0.0
		save()


func save() -> void:
	if beast == null or not is_instance_valid(beast) or Life.realm == null:
		return
	beast.snapshot()           # refreshes brain.pos
	Save.store(Life.realm.mod("followers"), beast.brain)


func _exit_tree() -> void:
	save()
