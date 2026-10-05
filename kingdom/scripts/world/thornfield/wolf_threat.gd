extends Node
## The wolves of Thornfield. A wolf den lies in the forest near the town (an existing ecology den is reused, else one
## is added), and its pack sometimes comes out at night to probe the farms: two or three wolves (Wolf, species "wolf")
## prowl the fields around the Brewery until dawn, hunting the player if they get close. They are ordinary dens'
## wolves: a kill culls the den (Frontier.ecology.cull) and counts for the Hunt (Life.on_wolf_killed).
##
## The grain-cart ambush (quest "Wolves at the Grain Carts") is the same animal with `prey` set to the cart
## (wolf.gd `_quarry`): `ambush(cart, count)` spawns the pack at the forest edge, hunting the cart until the player
## steps in, ignoring runestone ward (a hungry pack at the hedge does not read the stones).

const Sites := preload("res://scripts/world/thornfield/sites.gd")
const CreaturePool := preload("res://scripts/core/creature_pool.gd")
const DEN_RING := Vector2(170.0, 330.0)
const NIGHT_FROM := 22
const NIGHT_TO := 5
const PROBE_NEAR := 240.0
const PROBE_CHANCE := 55            # percent of nights

var den_id := -1
var probe_wolves: Array = []
var ambush_wolves: Array = []
var _probe_day := -1                # the night (day number) the probe already came on
var _hour := 12


func _ready() -> void:
	name = "WolfThreat"
	ensure_den()
	if WorldSim.has_signal("hour_changed"):
		WorldSim.hour_changed.connect(_on_hour)
	_hour = int(WorldSim.time_of_day)


## The den near Thornfield: id of an alive wolf den within DEN_RING.y of the town, else a new one in the forest.
func ensure_den() -> int:
	var s := Sites.settlement()
	if s.is_empty() or Frontier.ecology == null:
		return -1
	var c: Vector2 = s["pos"]
	for d: Dictionary in Frontier.ecology.dens:
		if bool(d["alive"]) and String(d["species"]) == "wolf" and (d["pos"] as Vector2).distance_to(c) <= DEN_RING.y:
			den_id = int(d["id"])
			return den_id
	var pos := den_site(c)
	if pos == Vector2.INF:
		return -1
	var den: Dictionary = Frontier.ecology.add_den("wolf", pos, 6)
	den_id = int(den["id"])
	return den_id


## The most forested dry spot on the ring around the town (deterministic), away from roads and runestone cover.
static func den_site(c: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_f := 0.0
	var a := 0.0
	while a < TAU:
		var d := DEN_RING.x
		while d <= DEN_RING.y:
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
	if h == NIGHT_TO:
		_dawn()


func night_now() -> bool:
	return _hour >= NIGHT_FROM or _hour < NIGHT_TO


## One poll (the hub calls this twice a second): starts a probe on a night that has one, once the player is near.
func tick(player_pos: Vector2) -> void:
	_prune()
	if night_now() and probe_wolves.is_empty() and _probe_day != WorldSim.day:
		var fields := Sites.place_pos("thornfield_fields")
		if fields != Vector2.INF and player_pos.distance_to(fields) < PROBE_NEAR:
			_probe_day = WorldSim.day
			if posmod(hash(WorldSim.day * 7 + 3), 100) < PROBE_CHANCE:
				probe(fields, 2 + (1 if WorldSim.day % 3 == 0 else 0))


## Spawns `count` wolves that prowl `target` (the fields). Returns the bodies.
func probe(target: Vector2, count: int) -> Array:
	var out: Array = []
	var from := _edge_toward(target, 60.0)
	for i in count:
		var w := _wolf(from + Vector2(randf_range(-4, 4), randf_range(-4, 4)), target, 70.0)
		probe_wolves.append(w)
		out.append(w)
	return out


## The cart ambush: `count` wolves at the forest edge, hunting `cart`.
func ambush(cart: Node3D, count: int) -> Array:
	var out: Array = []
	var cp := Vector2(cart.global_position.x, cart.global_position.z)
	var from := _edge_toward(cp, 22.0)
	for i in count:
		var w := _wolf(from + Vector2(randf_range(-3, 3), randf_range(-3, 3)), cp, 120.0)
		w.set_meta("prey", cart)
		w.set("_provoked", 99999.0)           # the pack is committed: attack range is the provoked range, day or night
		w.set_meta("thornfield_ambush", true)
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
	var w: Wolf = CreaturePool.wolf("thornfield", "wolf")
	probe_wolves.erase(w)            # a recycled body may still sit in a stale list
	ambush_wolves.erase(w)
	w.den_id = den_id
	w.home = home
	w.territory = territory
	add_child(w)
	w.global_position = Vector3(at.x, WorldGen.height(at.x, at.y), at.y)
	# Wolves read the runestone cover as a reason to leave: these come from outside it and go where the prey is.
	var sp: Dictionary = (w.get("_sp") as Dictionary).duplicate()
	sp["ward"] = "ignore"
	w.set("_sp", sp)
	w.add_to_group("thornfield_wolf")
	w.died.connect(func(dead_wolf: Wolf) -> void:
		if dead_wolf.den_id >= 0 and Frontier.ecology != null:
			Frontier.ecology.cull(dead_wolf.den_id, 1)
		Life.on_wolf_killed(dead_wolf.global_position, dead_wolf.den_id, ""))
	return w


func _prune() -> void:
	probe_wolves = probe_wolves.filter(func(w: Variant) -> bool: return is_instance_valid(w) and not bool(w.dead))
	ambush_wolves = ambush_wolves.filter(func(w: Variant) -> bool: return is_instance_valid(w) and not bool(w.dead))


## Dawn: surviving probe wolves slink home (those out of the player's sight are freed).
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
