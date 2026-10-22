extends RefCounted
## Pools for the bodies the world spawners create and free all night: wolves and beasts (wolf.gd), camp monsters
## (monster.gd) and ambient critters (critter.gd). One shared NodePool per (spawner, species) so a stale reference
## held by one spawner can never point at a body another spawner is using. Preload, no class_name:
##   const CreaturePool := preload("res://scripts/core/creature_pool.gd")
##   var w: Node = CreaturePool.wolf("thornfield", "wolf")     # set den/home, add_child, w.global_position = ...
##   CreaturePool.give_back(w)                                # instead of w.queue_free()
## Bodies past a pool's cap are plain new()/queue_free() ones, never stolen from the world.
## Turn it off for A/B runs: NodePool.enabled = false (plain new() / queue_free()).

const NodePool := preload("res://scripts/core/node_pool.gd")
const WOLF_CAP := 24
const MONSTER_CAP := 24
const CRITTER_CAP := 96


static func wolf(spawner: String, species: String) -> Node:
	return _take("wolf:%s:%s" % [spawner, species], WOLF_CAP, func() -> Node:
		var w: Node = (load("res://scripts/actors/wolf.gd") as GDScript).new()
		w.set("species", species)
		return w)


static func monster(spawner: String, species: String) -> Node:
	return _take("monster:%s:%s" % [spawner, species], MONSTER_CAP, func() -> Node:
		var m: Node = (load("res://scripts/actors/monster.gd") as GDScript).new()
		m.set("species", species)
		return m)


static func critter(spawner: String, kind: String) -> Node:
	return _take("critter:%s:%s" % [spawner, kind], CRITTER_CAP, func() -> Node:
		var c: Node = (load("res://scripts/actors/critter.gd") as GDScript).new()
		c.set("kind", kind)
		return c)


## Pool hand-back for a body of any origin (non-pooled nodes are queue_free()d). Invalid nodes are ignored.
static func give_back(node: Variant) -> void:
	if is_instance_valid(node) and node is Node:
		NodePool.recycle(node)


static func _take(key: String, cap: int, make: Callable) -> Node:
	if not NodePool.enabled:
		NodePool.plain_allocs += 1
		return make.call()
	var n: Node = NodePool.shared(key, make, cap, false).acquire()      # never steal a live creature: over the cap it is a plain body
	if n == null:
		NodePool.plain_allocs += 1
		return make.call()
	return n


## Sums of every creature pool, for the QA harness and the debug overlay.
static func totals() -> Dictionary:
	var out := {"created": 0, "acquires": 0, "releases": 0, "reuses": 0, "steals": 0, "live": 0, "idle": 0, "total": 0, "pools": 0}
	for k: String in NodePool.shared_pools():
		var s: Dictionary = NodePool.shared_pools()[k].stats()
		out["pools"] += 1
		for f in ["created", "acquires", "releases", "reuses", "steals", "live", "idle", "total"]:
			out[f] += int(s[f])
	return out
