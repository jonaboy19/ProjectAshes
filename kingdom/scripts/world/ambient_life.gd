class_name AmbientLife
extends Node3D
## Places ordinary animals where they belong, near the player only:
## hens and a dog or cat about the homes, horses at the inn and stable, cattle,
## sheep and pigs by the fields, ducks and geese on the lake shore, deer,
## rabbits and foxes in the woods. Groups get bodies inside SPAWN and are freed
## beyond DESPAWN, so the living world costs nothing far away.
## Now and then a wild group is a beast instead (Wolf controller with another
## species): boars rooting in the woods, a lone bear in dense forest, and, once
## the CC0 Quaternius monsters are imported, blight rats and a fungal brute in
## the deepest forest. They defend themselves and fight with the same attack
## tokens and wind-ups as wolves.
## Wild deer, stags, rabbits and foxes are huntable (Critter.take_damage); boars
## drop pork and a tusk. A ForageNodes child keeps a few herbs, mushrooms,
## berries and firewood to pick around the player.

const Gathering := preload("res://scripts/sim/gathering_items.gd")
const ForageNodes := preload("res://scripts/world/forage_nodes.gd")
const SPAWN := 110.0
const SMALL_FLOCK := ["chicken", "pigeon", "duck", "goose"]
const DESPAWN := 170.0
const WILD_RINGS := 3          # wildlife groups kept around the player in forests
const Models := preload("res://scripts/actors/creature_models.gd")
## Beast kinds (spawned as Wolf with this species) -> home territory radius.
const BEASTS := {"boar": 45.0, "bear": 60.0, "blight_rat": 35.0, "fungal_brute": 30.0}

var focus := Vector3.ZERO
var _groups: Array[Dictionary] = []    # {pos, kinds: [[kind, n]], radius, nodes: Array}
var _wild: Array[Dictionary] = []
var _timer := 0.0
var forage: Node3D


func _ready() -> void:
	Gathering.register(Life)
	forage = ForageNodes.new()
	forage.name = "ForageNodes"
	add_child(forage)
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
	# Every waystation (coach inn, roadhouse, wayside inn) ties up a horse or two: in the 12 km world a horse is the fast way
	# across (player.toggle_mount, mount_controller.gd). Own RNG so nothing above changes.
	var wrng := RandomNumberGenerator.new()
	wrng.seed = 5151
	for site in WorldGen.sites:
		if String(site["kind"]) == "waystation":
			var wyaw := float(site["yaw"])
			var wp: Vector2 = site["pos"]
			var tied := wp + Vector2(sin(wyaw), cos(wyaw)) * 9.0 + Vector2(cos(wyaw), -sin(wyaw)) * 8.0
			_group(tied, [["horse", 1], ["horse_grey", 1]] if wrng.randf() < 0.5 else [["horse", 1]], 3.0)
	# Meshy free / Quaternius extras (own RNG stream, appended after everything above): a white horse at the Crownstead and Highwatch
	# stables, huskies at the northern camps (Grimfen Pass, Frostmere).
	var xrng := RandomNumberGenerator.new()
	xrng.seed = 5152
	for site in WorldGen.sites:
		var nm := String(site["name"])
		var sp: Vector2 = site["pos"]
		var syaw := float(site["yaw"])
		var side := Vector2(cos(syaw), -sin(syaw))
		if nm == "Crownstead Steward's Hall" or nm == "Highwatch Keep":
			_group(sp + Vector2(sin(syaw), cos(syaw)) * 14.0 + side * 12.0, [["horse_white", 1]], 3.0)
		elif nm == "Grimfen Pass" or nm == "Frostmere Smokehouse":
			_group(sp + Vector2(sin(syaw), cos(syaw)) * 9.0 + side * (xrng.randf_range(4.0, 8.0)), [["husky", 2]], 5.0)
	# Waterfowl on the lake shore.
	var lc: Vector2 = WorldGen.lake_center
	if lc.x < 1.0e5:
		for i in 4:
			var a := TAU * i / 4.0 + 0.4
			var p := lc + Vector2(cos(a), sin(a)) * (WorldGen.lake_radius + 4.0)
			_group(p, [["duck", rng.randi_range(3, 5)], ["goose", rng.randi_range(0, 2)]], 6.0)
	preload("res://scripts/world/thornfield/livestock.gd").add_groups(self)   # F8: Thornfield's pigs, hens, sheep, cows and yard dog


## Meshy free pack farm animals stand in for part of the herd and the flock: every other cow wears one of three coats, every other
## hen or rooster is the rigged Meshy bird (docs/qa/ASSET_AUDIT.md). Deterministic per animal index and group position.
const COW_COATS := ["cow", "cow_brown_a", "cow_spotted", "cow_brown_b"]


static func _variant(kind: String, k: int, at: Vector2) -> String:
	var h := absi(int(at.x * 0.37) + int(at.y * 0.53)) + k
	if kind == "cow":
		return COW_COATS[h % COW_COATS.size()]
	if kind == "chicken" and h % 2 == 1:
		return "hen_meshy"
	if kind == "rooster" and h % 2 == 0:
		return "rooster_meshy"
	return kind


func _group(pos: Vector2, kinds: Array, radius: float) -> void:
	_groups.append({"pos": pos, "kinds": kinds, "radius": radius, "nodes": []})


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	forage.set("focus", focus)
	var p := Vector2(focus.x, focus.z)
	for g in _groups:
		_update_group(g, p)
	_update_wild(p)


func _update_group(g: Dictionary, p: Vector2) -> void:
	var d := p.distance_to(g["pos"])
	var nodes: Array = g["nodes"]
	if d < SPAWN and nodes.is_empty():
		for pair: Array in g["kinds"]:
			var want := int(pair[1])
			if SMALL_FLOCK.has(pair[0]):
				# Perf: fewer hens/doves on weaker tiers (each is a skinned, animated model).
				want = maxi(1, roundi(want * clampf(float(Quality.value("scatter")) + 0.15, 0.3, 1.0)))
			for k in want:
				if BEASTS.has(pair[0]):
					_spawn_beast(g, String(pair[0]), nodes)
					continue
				var cr := Critter.new()
				cr.kind = _variant(String(pair[0]), k, g["pos"])
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
		var kinds := _beast_kinds(q)
		if kinds.is_empty():
			var roll := randf()
			kinds = [["deer", randi_range(2, 4)], ["stag", 1]] if roll < 0.4 else \
				([["rabbit", randi_range(2, 4)]] if roll < 0.75 else ([["fox", 1]] if roll < 0.9 else [["crow", randi_range(3, 5)]]))
		var g := {"pos": q, "kinds": kinds, "radius": 14.0, "nodes": []}
		_wild.append(g)
		_update_group(g, p)


## Roughly one wild group in five is a beast, rarer and tougher in denser forest,
## never inside runestone protection. Empty when the roll gives ordinary wildlife.
func _beast_kinds(q: Vector2) -> Array:
	if Frontier.runestones.coverage(q) > 0.4 or preload("res://scripts/world/hidden_valley.gd").protected_ground(q):   # Hidden valley hook: no beasts in the vale
		return []
	var dense := WorldGen.forest_density(q.x, q.y)
	var roll := randf()
	if roll < 0.10:
		return [["boar", randi_range(1, 3)]]
	if roll < 0.14 and dense > 0.55:
		return [["bear", 1]]
	if roll < 0.18 and dense > 0.6 and Models.has("blight_rat"):
		return [["blight_rat", randi_range(2, 3)]]
	if roll < 0.21 and dense > 0.65 and Models.has("fungal_brute"):
		return [["fungal_brute", 1]]
	return []


func _spawn_beast(g: Dictionary, kind: String, nodes: Array) -> void:
	if not Models.has(kind):
		return
	var b := Wolf.new()
	b.species = kind
	b.home = g["pos"]
	b.territory = float(BEASTS[kind])
	add_child(b)
	if b.is_queued_for_deletion():
		return
	var r: float = g["radius"]
	var q: Vector2 = g["pos"] + Vector2(randf_range(-r, r), randf_range(-r, r)) * 0.5
	b.global_position = Vector3(q.x, WorldGen.height(q.x, q.y), q.y)
	b.died.connect(func(dead_b: Wolf) -> void:
		Life.on_monster_killed(dead_b.species)
		var got := Gathering.give_drops(Life, dead_b.species)
		if got != "":
			Game.say("%s butchered. %s" % [dead_b.species.capitalize(), got]))
	nodes.append(b)
