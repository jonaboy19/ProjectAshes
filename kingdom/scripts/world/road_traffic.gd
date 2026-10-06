extends Node3D
## Ambient traffic near the player: carts, riders and a day patrol of guards
## moving along kingdom and rural roads at a walking pace, in the spirit of
## ambient_life.gd's spawn ring. Cheap: at most MAX_GROUPS near the player,
## each just a node lerping along a straight road segment, no physics and no
## per-node AI.

const Assets := preload("res://scripts/world/assets.gd")
const WAGON := "res://assets/generated/props/covered_wagon.glb"
const CARAVAN_WAGON := "res://assets/generated/region/road/caravan_wagon.glb"
const SPAWN := 130.0
const DESPAWN := 220.0
const MAX_GROUPS := 6
const RESPAWN_CHECK := 5.0
const SPEED := {"wagon": 1.6, "rider": 4.2, "patrol": 1.3}

var focus := Vector3.ZERO
var _groups: Array[Dictionary] = []   # {a, b, t, speed, node}
var _timer := 0.0


func _process(delta: float) -> void:
	var p := Vector2(focus.x, focus.z)
	for g in _groups.duplicate():
		_advance(g, delta, p)
	_timer -= delta
	if _timer <= 0.0:
		_timer = RESPAWN_CHECK
		if _groups.size() < MAX_GROUPS:
			_maybe_spawn(p)


func _advance(g: Dictionary, delta: float, focus_p: Vector2) -> void:
	var a: Vector2 = g["a"]
	var b: Vector2 = g["b"]
	var length := maxf(a.distance_to(b), 1.0)
	g["t"] = float(g["t"]) + float(g["speed"]) * delta / length
	if float(g["t"]) >= 1.0:
		_free_group(g)
		return
	var pos: Vector2 = a.lerp(b, float(g["t"]))
	if focus_p.distance_to(pos) > DESPAWN:
		_free_group(g)
		return
	var node: Node3D = g["node"]
	if is_instance_valid(node):
		node.global_position = Vector3(pos.x, WorldGen.height(pos.x, pos.y), pos.y)
		var dir := (b - a).normalized()
		node.rotation.y = atan2(dir.x, dir.y)


func _free_group(g: Dictionary) -> void:
	if is_instance_valid(g["node"]):
		g["node"].queue_free()
	_groups.erase(g)


func _maybe_spawn(p: Vector2) -> void:
	var road := _pick_road_near(p)
	if road.is_empty():
		return
	var kind := _pick_kind(String(road["tier"]))
	if kind == "":
		return
	var flip := randf() < 0.5
	var a: Vector2 = road["b"] if flip else road["a"]
	var b: Vector2 = road["a"] if flip else road["b"]
	var node := _build_visual(kind)
	if node == null:
		return
	if kind != "patrol":
		node.add_to_group("vehicle")     # NpcWorld.mover_push: villagers step out of a wagon's or rider's way
	add_child(node)
	_groups.append({"a": a, "b": b, "t": randf_range(0.0, 0.8), "speed": float(SPEED.get(kind, 1.6)) * float(road.get("speed", 1.0)), "node": node})


func _pick_road_near(p: Vector2) -> Dictionary:
	var out: Array = []
	for r in WorldGen.roads:
		var tier := WorldGen.road_tier(r.x, r.y)
		if tier == "frontier" and randf() < 0.4:
			continue      # frontier roads carry traffic too (the new land is mostly frontier road), just less of it
		var a: Vector2 = WorldGen.settlements[r.x]["pos"]
		var b: Vector2 = WorldGen.settlements[r.y]["pos"]
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) < SPAWN:
			out.append({"a": a, "b": b, "tier": tier})
	out.append_array(_kit_roads(p))
	return out[randi() % out.size()] if not out.is_empty() else {}


## Build-kit hook: dirt and cobbled roads drawn in build mode carry carts too, at the road's `speed` field in
## data/build_kit/pieces.json (build_kit.traffic_segments(): short chords near the player). Runs on the 5 s respawn check only.
func _kit_roads(p: Vector2) -> Array:
	var realm: Variant = Life.get("realm")
	var kit: Variant = (realm as RefCounted).call("mod", "build_kit") if realm is RefCounted and (realm as RefCounted).has_method("mod") else null
	if not (kit is RefCounted) or not (kit as RefCounted).has_method("traffic_segments"):
		return []
	return (kit as RefCounted).call("traffic_segments", p, SPAWN)


func _pick_kind(tier: String) -> String:
	var hour := WorldSim.time_of_day
	var daytime := hour >= 6.0 and hour < 19.0
	if tier == "kingdom" and daytime and randf() < 0.3:
		return "patrol"
	var roll := randf()
	if roll < 0.45:
		return "wagon"
	if roll < 0.85:
		return "rider"
	return ""


func _build_visual(kind: String) -> Node3D:
	match kind:
		"wagon":
			var path := WAGON if ResourceLoader.exists(WAGON) else CARAVAN_WAGON
			if not ResourceLoader.exists(path):
				return null
			return Assets.scene(path).instantiate()
		"rider":
			var c := Critter.new()
			c.kind = "horse"
			return c
		"patrol":
			var root := Node3D.new()
			for i in randi_range(3, 4):
				var guard := Assets.character("Guard", 1.8, [])
				guard.position = Vector3(0.6 * (i - 1.5), 0.0, -0.6 * i)
				root.add_child(guard)
			return root
	return null
