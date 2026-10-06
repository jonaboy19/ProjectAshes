extends Node
## The local threat of a kit town (its file's `threat`). A den of the town's species lies in the country near the town (an
## existing ecology den is reused, else one is added), and its pack sometimes comes out at night to probe the town's
## `probe_place`: two or three creatures prowl it until dawn, hunting the player if they get close. They are ordinary dens'
## creatures: a kill culls the den (Frontier.ecology.cull) and counts for the Hunt (Life.on_wolf_killed for wolves,
## Life.on_monster_killed for the rest), so `kill {target: species, place}` reaches the quest bus through the hub.
##
## `ambush(prey, count)` is the same animal with `prey` set (wolf.gd `_quarry`): the pack spawns at the forest edge and
## hunts the prey until the player steps in, ignoring runestone ward. Thornfield's grain cart uses it; any special can.
##
## Config keys (all optional, defaults in the consts): species, spawner, group, den_ring [near, far], night [from, to],
## probe_chance, probe_place, probe_near, probe_count [n, n on every third night], probe_from, probe_territory,
## ambush_from, ambush_territory.

const TownData := preload("res://scripts/world/town_kit/town_data.gd")
const TownPlaces := preload("res://scripts/world/town_kit/town_places.gd")
const CreaturePool := preload("res://scripts/core/creature_pool.gd")
## Species the kit can raise as a local threat: both a wolf.gd body and an ecology den row exist for each.
const SPECIES := ["wolf", "corrupted_wolf", "bog_toad", "giant_wasp", "ghoul"]
const DEN_RING := Vector2(170.0, 330.0)
const NIGHT_FROM := 22
const NIGHT_TO := 5
const PROBE_NEAR := 240.0
const PROBE_CHANCE := 55            # percent of nights

var tid := ""
var species := "wolf"
var spawner := ""
var group := ""
var den_ring := DEN_RING
var night_from := NIGHT_FROM
var night_to := NIGHT_TO
var probe_chance := PROBE_CHANCE
var probe_place := ""
var probe_near := PROBE_NEAR
var probe_count := Vector2i(2, 3)
var probe_from := 60.0
var probe_territory := 70.0
var ambush_from := 22.0
var ambush_territory := 120.0
var den_id := -1
var probe_wolves: Array = []
var ambush_wolves: Array = []
var _probe_day := -1                # the night (day number) the probe already came on
var _hour := 12


func configure(town_id: String) -> void:
	tid = town_id
	var c: Dictionary = TownData.town(town_id).get("threat", {})
	species = String(c.get("species", species))
	spawner = String(c.get("spawner", town_id))
	group = String(c.get("group", "%s_threat" % town_id))
	if c.has("den_ring"):
		den_ring = Vector2(float(c["den_ring"][0]), float(c["den_ring"][1]))
	if c.has("night"):
		night_from = int(c["night"][0])
		night_to = int(c["night"][1])
	probe_chance = int(c.get("probe_chance", probe_chance))
	probe_place = String(c.get("probe_place", probe_place))
	probe_near = float(c.get("probe_near", probe_near))
	if c.has("probe_count"):
		probe_count = Vector2i(int(c["probe_count"][0]), int(c["probe_count"][1]))
	probe_from = float(c.get("probe_from", probe_from))
	probe_territory = float(c.get("probe_territory", probe_territory))
	ambush_from = float(c.get("ambush_from", ambush_from))
	ambush_territory = float(c.get("ambush_territory", ambush_territory))


func _ready() -> void:
	name = "Threat_" + tid if tid != "" else "TownThreat"
	ensure_den()
	if WorldSim.has_signal("hour_changed"):
		WorldSim.hour_changed.connect(_on_hour)
	_hour = int(WorldSim.time_of_day)


## The den near the town: id of an alive den of the species within den_ring.y of the town, else a new one in the country.
func ensure_den() -> int:
	var s := TownPlaces.settlement(tid)
	if s.is_empty() or Frontier.ecology == null or not Frontier.ecology.SPECIES.has(species):
		return -1
	var c: Vector2 = s["pos"]
	for d: Dictionary in Frontier.ecology.dens:
		if bool(d["alive"]) and String(d["species"]) == species and (d["pos"] as Vector2).distance_to(c) <= den_ring.y:
			den_id = int(d["id"])
			return den_id
	var pos := den_site(c, den_ring)
	if pos == Vector2.INF:
		return -1
	var den: Dictionary = Frontier.ecology.add_den(species, pos, 6 if species == "wolf" else 3)
	den_id = int(den["id"])
	return den_id


## The most forested dry spot on the ring around the town (deterministic), away from roads and runestone cover.
static func den_site(c: Vector2, ring := DEN_RING) -> Vector2:
	var best := Vector2.INF
	var best_f := 0.0
	var a := 0.0
	while a < TAU:
		var d := ring.x
		while d <= ring.y:
			var p := c + Vector2(cos(a), sin(a)) * d
			if not WorldGen.near_water(p.x, p.y, 8.0) and WorldGen.road_distance(p.x, p.y) > 40.0:
				var f := WorldGen.forest_density(p.x, p.y)
				if Frontier.runestones.coverage(p) > 0.1:
					f *= 0.4
				if f > best_f:
					best_f = f
					best = p
			d += 40.0
		a += TAU / 24.0
	return best


func _on_hour(h: int) -> void:
	_hour = h
	if h == night_to:
		_dawn()


func night_now() -> bool:
	return _hour >= night_from or _hour < night_to


## One poll (the hub calls this twice a second): starts a probe on a night that has one, once the player is near.
func tick(player_pos: Vector2) -> void:
	_prune()
	if night_now() and probe_wolves.is_empty() and _probe_day != WorldSim.day and probe_place != "":
		var fields := TownPlaces.place_pos(tid, probe_place)
		if fields != Vector2.INF and player_pos.distance_to(fields) < probe_near:
			_probe_day = WorldSim.day
			if posmod(hash(WorldSim.day * 7 + 3), 100) < probe_chance:
				probe(fields, probe_count.x + (1 if WorldSim.day % 3 == 0 else 0) * maxi(0, probe_count.y - probe_count.x))


## Spawns `count` creatures that prowl `target` (the probe place). Returns the bodies.
func probe(target: Vector2, count: int) -> Array:
	var out: Array = []
	var from := _edge_toward(target, probe_from)
	for i in count:
		var w := _wolf(from + Vector2(randf_range(-4, 4), randf_range(-4, 4)), target, probe_territory)
		probe_wolves.append(w)
		out.append(w)
	return out


## The ambush: `count` creatures at the forest edge, hunting `prey`.
func ambush(prey: Node3D, count: int) -> Array:
	var out: Array = []
	var cp := Vector2(prey.global_position.x, prey.global_position.z)
	var from := _edge_toward(cp, ambush_from)
	for i in count:
		var w := _wolf(from + Vector2(randf_range(-3, 3), randf_range(-3, 3)), cp, ambush_territory)
		w.set_meta("prey", prey)
		w.set("_provoked", 99999.0)           # the pack is committed: attack range is the provoked range, day or night
		w.set_meta("%s_ambush" % tid, true)
		ambush_wolves.append(w)
		out.append(w)
	return out


## A point `dist` metres from `target` toward the den (the forest side), or on the far side of the target when there is no den.
func _edge_toward(target: Vector2, dist: float) -> Vector2:
	var dir := Vector2(0, -1)
	var den := _den_pos()
	if den != Vector2.INF and den.distance_to(target) > 1.0:
		dir = (den - target).normalized()
	return target + dir * dist


func _den_pos() -> Vector2:
	if den_id < 0 or Frontier.ecology == null or den_id >= Frontier.ecology.dens.size():
		return Vector2.INF
	return Frontier.ecology.dens[den_id]["pos"]


func _wolf(at: Vector2, home: Vector2, territory: float) -> Node3D:
	var w: Wolf = CreaturePool.wolf(spawner, species)
	probe_wolves.erase(w)            # a recycled body may still sit in a stale list
	ambush_wolves.erase(w)
	w.den_id = den_id
	w.home = home
	w.territory = territory
	add_child(w)
	w.global_position = Vector3(at.x, WorldGen.height(at.x, at.y), at.y)
	# Creatures read the runestone cover as a reason to leave: these come from outside it and go where the prey is.
	var sp: Dictionary = (w.get("_sp") as Dictionary).duplicate()
	sp["ward"] = "ignore"
	w.set("_sp", sp)
	w.add_to_group(group)
	var sname := species
	w.died.connect(func(dead_wolf: Wolf) -> void:
		if dead_wolf.den_id >= 0 and Frontier.ecology != null:
			Frontier.ecology.cull(dead_wolf.den_id, 1)
		if sname == "wolf":
			Life.on_wolf_killed(dead_wolf.global_position, dead_wolf.den_id, "")
		else:
			Life.on_monster_killed(sname))
	return w


func _prune() -> void:
	probe_wolves = probe_wolves.filter(func(w: Variant) -> bool: return is_instance_valid(w) and not bool(w.dead))
	ambush_wolves = ambush_wolves.filter(func(w: Variant) -> bool: return is_instance_valid(w) and not bool(w.dead))


## Dawn: surviving probe creatures slink home (those out of the player's sight are freed).
func _dawn() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	for w: Variant in probe_wolves:
		if not is_instance_valid(w):
			continue
		if player == null or (w as Node3D).global_position.distance_to(player.global_position) > 70.0:
			CreaturePool.give_back(w)
	probe_wolves.clear()


func clear_ambush() -> void:
	for w: Variant in ambush_wolves:
		if is_instance_valid(w) and not bool(w.dead):
			CreaturePool.give_back(w)
	ambush_wolves.clear()
