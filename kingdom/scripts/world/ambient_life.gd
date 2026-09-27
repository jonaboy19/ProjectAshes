class_name AmbientLife
extends Node3D
## Places ordinary animals where they belong, near the player only:
## hens and a dog or cat about the homes, horses at the inn and stable, cattle,
## sheep and pigs by the fields, ducks and geese on the lake shore, deer,
## rabbits and foxes in the woods. Groups get bodies inside SPAWN and are freed
## beyond DESPAWN, so the living world costs nothing far away.

const SPAWN := 110.0
const DESPAWN := 170.0
const WILD_RINGS := 3          # wildlife groups kept around the player in forests

var focus := Vector3.ZERO
var _groups: Array[Dictionary] = []    # {pos, kinds: [[kind, n]], radius, nodes: Array}
var _wild: Array[Dictionary] = []
var _timer := 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for s in WorldGen.settlements:
		var plan: Dictionary = s.get("plan", {})
		for lot: Dictionary in plan.get("lots", []):
			var asset := String(lot["asset"])
			var yaw: float = lot["yaw"]
			var back: Vector2 = lot["pos"] - Vector2(sin(yaw), cos(yaw)) * 6.5
			if asset.begins_with("house") or asset.begins_with("mhouse"):
				var roll := rng.randf()
				if roll < 0.3:
					_group(back, [["chicken", rng.randi_range(3, 5)], ["rooster", 1]], 4.0)
				elif roll < 0.4:
					_group(back, [["cat" if rng.randf() < 0.5 else "cat_ginger", 1]], 5.0)
				elif roll < 0.48:
					_group(back, [["dog", 1]], 8.0)
				elif roll < 0.52:
					_group(back, [["pig", rng.randi_range(2, 3)]], 4.0)
			elif asset == "inn" or asset == "stable":
				var front: Vector2 = lot["pos"] + Vector2(sin(yaw), cos(yaw)) * 7.0 + Vector2(cos(yaw), -sin(yaw)) * 5.0
				_group(front, [["horse", 1], ["horse_grey" if rng.randf() < 0.5 else "donkey", 1]], 3.0)
		# Livestock in the pastures around the village.
		var c: Vector2 = s["pos"]
		var r: float = s["radius"]
		for i in 3:
			var a := rng.randf() * TAU
			var p := c + Vector2(cos(a), sin(a)) * r * rng.randf_range(1.25, 1.7)
			if WorldGen.road_distance(p.x, p.y) < 12.0 or WorldGen.near_water(p.x, p.y, 6.0):
				continue
			match i:
				0: _group(p, [["cow", rng.randi_range(3, 5)], ["ox", 1]], 12.0)
				1: _group(p, [["sheep", rng.randi_range(6, 9)], ["sheepdog", 1]], 12.0)
				_: _group(p, [["goat", rng.randi_range(3, 5)]], 8.0)
		_group(c + Vector2(4, 6), [["pigeon", rng.randi_range(4, 7)]], 6.0)
	# Waterfowl on the lake shore.
	var lc: Vector2 = WorldGen.lake_center
	if lc.x < 1.0e5:
		for i in 4:
			var a := TAU * i / 4.0 + 0.4
			var p := lc + Vector2(cos(a), sin(a)) * (WorldGen.lake_radius + 4.0)
			_group(p, [["duck", rng.randi_range(3, 5)], ["goose", rng.randi_range(0, 2)]], 6.0)


func _group(pos: Vector2, kinds: Array, radius: float) -> void:
	_groups.append({"pos": pos, "kinds": kinds, "radius": radius, "nodes": []})


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	var p := Vector2(focus.x, focus.z)
	for g in _groups:
		_update_group(g, p)
	_update_wild(p)


func _update_group(g: Dictionary, p: Vector2) -> void:
	var d := p.distance_to(g["pos"])
	var nodes: Array = g["nodes"]
	if d < SPAWN and nodes.is_empty():
		for pair: Array in g["kinds"]:
			for k in int(pair[1]):
				var cr := Critter.new()
				cr.kind = pair[0]
				cr.home = g["pos"]
				add_child(cr)
				var r: float = g["radius"]
				var q: Vector2 = g["pos"] + Vector2(randf_range(-r, r), randf_range(-r, r)) * 0.6
				cr.global_position = Vector3(q.x, WorldGen.height(q.x, q.y), q.y)
				nodes.append(cr)
	elif d > DESPAWN and not nodes.is_empty():
		for n in nodes:
			if is_instance_valid(n):
				n.queue_free()
		nodes.clear()


## Wildlife: a few groups in woodland around the player, re-rolled as they move.
func _update_wild(p: Vector2) -> void:
	for g in _wild.duplicate():
		if p.distance_to(g["pos"]) > DESPAWN:
			for n in g["nodes"]:
				if is_instance_valid(n):
					n.queue_free()
			_wild.erase(g)
	var tries := 6
	while _wild.size() < WILD_RINGS and tries > 0:
		tries -= 1
		var a := randf() * TAU
		var q := p + Vector2(cos(a), sin(a)) * randf_range(45.0, 95.0)
		if WorldGen.forest_density(q.x, q.y) < 0.35 or WorldGen.near_water(q.x, q.y, 4.0):
			continue
		var near := WorldGen.nearest_settlement(q)
		if not near.is_empty() and q.distance_to(near["pos"]) < float(near["radius"]) * 1.3:
			continue
		var roll := randf()
		var kinds: Array = [["deer", randi_range(2, 4)], ["stag", 1]] if roll < 0.4 else \
			([["rabbit", randi_range(2, 4)]] if roll < 0.75 else ([["fox", 1]] if roll < 0.9 else [["crow", randi_range(3, 5)]]))
		var g := {"pos": q, "kinds": kinds, "radius": 14.0, "nodes": []}
		_wild.append(g)
		_update_group(g, p)
