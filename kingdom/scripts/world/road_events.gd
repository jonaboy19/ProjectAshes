extends Node3D
## Light roadside danger for bandits, who are human and ignore runestones
## entirely (see wolf.gd / monster.gd for the ward_response monsters read
## instead). A few times per in-game day, on a rural or frontier road and
## never inside a settlement, 2-4 raiders (the same Squad/soldier setup as
## the raider camp, main.gd) appear near the player but out of sight and
## ambush travellers. Cheap: one ambush group at a time, checked on a slow
## timer, no per-frame work.

const Squad := preload("res://scripts/army/squad.gd")
const CasterSpawns := preload("res://scripts/combat/caster_spawns.gd")
const CHECK_INTERVAL := 20.0
const MAX_ROAD_DISTANCE := 40.0       # only while actually near a road
const SETTLEMENT_MARGIN := 2.0        # x radius: never spawn this close to a settlement
const SPAWN_RANGE := Vector2(35.0, 85.0)
## Roughly this many ambushes across a full in-game day, scaled by time-of-day danger.
const AMBUSHES_PER_DAY := 3.0
## War makes roads more dangerous (soldiers gone, bandits bolder). A caller
## (life.gd's hook: `road_events.danger_mult = 1.6 if war.is_at_war() else 1.0`)
## can raise this; it multiplies straight onto the per-tick ambush chance.
var danger_mult := 1.0
const AMBUSH_LOOK := "raider"
const AMBUSH_FILE := "Barbarian"
const AMBUSH_KEEP: Array[String] = ["1H_Axe", "Barbarian_Round_Shield", "Barbarian_Hat"]

var focus := Vector3.ZERO
var _timer := 0.0
var _active: Array = []      # [{squad, camp}]


func _process(delta: float) -> void:
	_ash_timer -= delta
	if _ash_timer <= 0.0:
		_ash_timer = 1.0
		_ash_sample()   # Region1 hook C6
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
			AshMemory.close(int(a.get("ash_id", -1)))   # Region1 hook C6
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
	if randf() > per_tick * Frontier.danger_mult(WorldSim.time_of_day) * danger_mult * (1.6 if Life.war.is_at_war() else 1.0):
		return
	_spawn_ambush(p)


var _ash_timer := 1.0


## Region1 hook C6: once a second, record the bandits and the player near each open ambush (AshMemory keeps its own gate).
func _ash_sample() -> void:
	for a: Dictionary in _active:
		if int(a.get("ash_id", -1)) < 0 or not is_instance_valid(a["squad"]):
			continue
		var actors := []
		for s in (a["squad"] as Squad).soldiers:
			if is_instance_valid(s):
				actors.append({"id": s.get_instance_id(), "role": "bandit", "pos": Vector2(s.global_position.x, s.global_position.z)})
		actors.append({"id": "player", "role": "villager", "pos": Vector2(focus.x, focus.z)})
		AshMemory.sample_now(actors)


## An ambush on demand (realm_encounters.gd road events and night camps): the same raiders, `count` of them.
func force_ambush(near_p: Vector2, count := 3) -> void:
	_spawn_ambush(near_p, count)


## Places the ambush just off the road, in cover, out of the player's sight.
func _spawn_ambush(near_p: Vector2, count := 0) -> void:
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
	var n_amb := count if count > 0 else randi_range(2, 4)
	squad.add_soldiers(n_amb, base, CasterSpawns.mix("road_ambush", n_amb, randi()))
	_active.append({"squad": squad, "camp": camp})
	# Region1 hook C6 (docs/regions/REGION_1_PLAN.md): the ambush spot is a flagged site, the raid an Ashsight incident
	AshMemory.flag_site_static("Roadside ambush", Vector2(base.x, base.z))
	_active[_active.size() - 1]["ash_id"] = AshMemory.open(&"raid", Vector2(base.x, base.z))
