extends Node3D
## Light roadside danger for bandits, who are human and ignore runestones
## entirely (see wolf.gd / monster.gd for the ward_response monsters read
## instead). A few times per in-game day, on a rural or frontier road and
## never inside a settlement, 2-4 raiders (the same Squad/soldier setup as
## the raider camp, main.gd) appear near the player but out of sight and
## ambush travellers. Cheap: one ambush group at a time, checked on a slow
## timer, no per-frame work.

const Squad := preload("res://scripts/army/squad.gd")
const CHECK_INTERVAL := 20.0
const MAX_ROAD_DISTANCE := 40.0       # only while actually near a road
const SETTLEMENT_MARGIN := 2.0        # x radius: never spawn this close to a settlement
const SPAWN_RANGE := Vector2(35.0, 85.0)
## Roughly this many ambushes across a full in-game day, scaled by time-of-day danger.
const AMBUSHES_PER_DAY := 3.0
const AMBUSH_LOOK := "raider"
const AMBUSH_FILE := "Barbarian"
const AMBUSH_KEEP: Array[String] = ["1H_Axe", "Barbarian_Round_Shield", "Barbarian_Hat"]

var focus := Vector3.ZERO
var _timer := 0.0
var _active: Array = []      # [{squad, camp}]


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_INTERVAL
	_cleanup()
	if _active.is_empty():
		_maybe_spawn()


func _cleanup() -> void:
	for a: Dictionary in _active.duplicate():
		var squad: Squad = a["squad"]
		if not is_instance_valid(squad) or squad.alive() <= 0:
			if is_instance_valid(a["camp"]):
				(a["camp"] as Node3D).queue_free()
			_active.erase(a)


func _maybe_spawn() -> void:
	var p := Vector2(focus.x, focus.z)
	var info := WorldGen.road_info(p.x, p.y)
	if String(info["tier"]) == "kingdom" or float(info["dist"]) > MAX_ROAD_DISTANCE:
		return         # kingdom roads are patrolled and safe; only rural/frontier roads ambush
	var near := WorldGen.nearest_settlement(p)
	if not near.is_empty() and p.distance_to(near["pos"]) < float(near["radius"]) * SETTLEMENT_MARGIN:
		return         # never inside a settlement
	var per_tick := AMBUSHES_PER_DAY * (CHECK_INTERVAL / WorldSim.DAY_LENGTH)
	if randf() > per_tick * Frontier.danger_mult(WorldSim.time_of_day):
		return
	_spawn_ambush(p)


## Places the ambush just off the road, in cover, out of the player's sight.
func _spawn_ambush(near_p: Vector2) -> void:
	var along := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	var spot := near_p + along * randf_range(SPAWN_RANGE.x, SPAWN_RANGE.y)
	var hidden := spot
	for i in 6:
		var side := spot + along.rotated(PI * 0.5 * (1.0 if i % 2 == 0 else -1.0)) * (8.0 + i * 5.0)
		if WorldGen.forest_density(side.x, side.y) > 0.3:
			hidden = side
			break
	var base := Vector3(hidden.x, WorldGen.height(hidden.x, hidden.y), hidden.y)
	var camp := Node3D.new()
	camp.name = "RoadAmbush"
	add_child(camp)
	var squad := Squad.new().setup(1, AMBUSH_LOOK, AMBUSH_FILE, AMBUSH_KEEP)
	squad.anchor = base
	squad.aggro_radius = 28.0
	add_child(squad)
	squad.add_soldiers(randi_range(2, 4), base)
	_active.append({"squad": squad, "camp": camp})
