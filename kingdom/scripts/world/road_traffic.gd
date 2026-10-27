extends Node3D
## Ambient traffic near the player: carts, riders and a day patrol of guards
## moving along kingdom and rural roads at a walking pace, in the spirit of
## ambient_life.gd's spawn ring. Cheap: at most MAX_GROUPS near the player,
## each just a node lerping along a straight road segment, no physics and no
## per-node AI.

const Assets := preload("res://scripts/world/assets.gd")
const WAGON := "res://assets/generated/props/covered_wagon.glb"
const CARAVAN_WAGON := "res://assets/generated/region/road/caravan_wagon.glb"
## Towns medieval pass: a drawn wagon with separate wheels (tools/blender_towns/draught_wagon.py), a horse walking between the
## shafts and a seated driver; it halts to unload when it reaches the town at the end of its road.
const DRAUGHT := "res://assets/generated/town_small/draught_wagon.glb"
const WHEEL_R := 0.6
const UNLOAD_AT := 34.0      # metres from the destination town's centre
const UNLOAD_SECS := 25.0
const SPAWN := 130.0
const DESPAWN := 220.0
const MAX_GROUPS := 6
const RESPAWN_CHECK := 5.0
const SPEED := {"wagon": 1.6, "rider": 4.2, "patrol": 1.3, "pilgrims": 1.0}
## Region 1 (C10 follow-up): a small band of pilgrims walks the road to the Eastern Gate in daylight, the way the Church realms'
## faithful come to be turned back. One band at a time, the same four bodies reused (pooled), existing characters only.
const PILGRIM_GATE_ID := "eastern_gate"
const PILGRIM_MAX := 1                    ## bands walking at once
const PILGRIM_LOOKS := ["Monk", "Elder_Woman", "Elder_Man", "Monk"]
const PILGRIM_HOURS := Vector2(7.0, 17.0)
const PILGRIM_CHANCE := 0.5               ## per 5 s check with the player near the road and no band out
const PILGRIM_CLIPS := ["Life_Walk_Careful", "Walking_A", "Walk"]

var focus := Vector3.ZERO
var _groups: Array[Dictionary] = []   # {a, b, t, speed, node}
var _timer := 0.0
var _pilgrim_pool: Array[Node3D] = []   # bands that finished their walk, waiting to be reused (hidden, not freed)
var pilgrim_builder: Callable = Callable()   # tests: a stand-in for the four character bodies


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
	var node0: Node3D = g["node"]
	var halted := float(g.get("halt", 0.0)) > 0.0
	if halted:
		g["halt"] = float(g["halt"]) - delta
		if float(g["halt"]) <= 0.0:
			g["halt"] = -1.0           # unloaded: drive on (and out of town on the next road)
			_drive(node0, float(g["speed"]))
		return
	g["t"] = float(g["t"]) + float(g["speed"]) * delta / length
	if is_instance_valid(node0) and node0.has_meta("wheels"):
		for w: Node3D in node0.get_meta("wheels"):
			w.rotate_x(float(g["speed"]) * delta / WHEEL_R)
		if float(g.get("halt", 0.0)) == 0.0 and a.lerp(b, float(g["t"])).distance_to(b) < UNLOAD_AT:
			g["halt"] = UNLOAD_SECS
			_drive(node0, 0.0)
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
		if String(g.get("kind", "")) == "pilgrims":
			_park_pilgrims(g["node"])      # pooled: the four bodies are kept for the next band
		else:
			g["node"].queue_free()
	_groups.erase(g)


func _maybe_spawn(p: Vector2) -> void:
	if _maybe_spawn_pilgrims(p, pilgrim_segment(WorldGen.sites, WorldGen.settlements), randf()):
		return
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


## The pilgrims' walk: from the settlement nearest the Eastern Gate to the gate itself, as {a, b}; {} when the world has no such gate.
static func pilgrim_segment(sites: Array, settlements: Array) -> Dictionary:
	var gate: Vector2 = Vector2.INF
	for s: Dictionary in sites:
		if String(s.get("r1id", "")) == PILGRIM_GATE_ID:
			gate = s["pos"]
			break
	if gate == Vector2.INF or settlements.is_empty():
		return {}
	var best: Vector2 = Vector2.INF
	var best_d := INF
	for st: Dictionary in settlements:
		var d: float = (st["pos"] as Vector2).distance_to(gate)
		if d < best_d:
			best_d = d
			best = st["pos"]
	return {"a": best, "b": gate} if best != Vector2.INF and best_d > 40.0 else {}


## Whether a band may set out: daylight, none out already (PILGRIM_MAX), the player near the road.
static func pilgrims_may_start(hour: float, active: int, focus_p: Vector2, seg: Dictionary, near := SPAWN) -> bool:
	if seg.is_empty() or active >= PILGRIM_MAX or hour < PILGRIM_HOURS.x or hour >= PILGRIM_HOURS.y:
		return false
	return focus_p.distance_to(Geometry2D.get_closest_point_to_segment(focus_p, seg["a"], seg["b"])) < near


func _pilgrims_active() -> int:
	var n := 0
	for g: Dictionary in _groups:
		if String(g.get("kind", "")) == "pilgrims":
			n += 1
	return n


func _maybe_spawn_pilgrims(p: Vector2, seg: Dictionary, roll: float) -> bool:
	if not pilgrims_may_start(WorldSim.time_of_day, _pilgrims_active(), p, seg) or roll > PILGRIM_CHANCE:
		return false
	var node := _take_pilgrims()
	if node == null:
		return false
	add_child_if_needed(node)
	var speed := float(SPEED["pilgrims"])
	_groups.append({"a": seg["a"], "b": seg["b"], "t": randf_range(0.0, 0.5), "speed": speed, "node": node, "kind": "pilgrims"})
	return true


func add_child_if_needed(node: Node3D) -> void:
	if node.get_parent() != self:
		add_child(node)
	node.visible = true
	node.process_mode = Node.PROCESS_MODE_INHERIT


## A band from the pool, or a new one when the pool is empty.
func _take_pilgrims() -> Node3D:
	while not _pilgrim_pool.is_empty():
		var n: Node3D = _pilgrim_pool.pop_back()
		if is_instance_valid(n):
			return n
	if pilgrim_builder.is_valid():
		return pilgrim_builder.call()
	return _build_pilgrims()


func _park_pilgrims(node: Node3D) -> void:
	node.visible = false
	node.process_mode = Node.PROCESS_MODE_DISABLED
	_pilgrim_pool.append(node)


func _build_pilgrims() -> Node3D:
	var root := Node3D.new()
	root.name = "Pilgrims"
	for i in PILGRIM_LOOKS.size():
		var body := Assets.character(String(PILGRIM_LOOKS[i]), 1.7, [])
		if body == null:
			continue
		body.position = Vector3(0.9 * float(i % 2) - 0.45, 0.0, -1.1 * float(i))
		root.add_child(body)
		var ap := Assets.animation_player(body)
		if ap != null:
			for clip: String in PILGRIM_CLIPS:
				if ap.has_animation(clip):
					var anim := ap.get_animation(clip)
					if anim != null:
						anim.loop_mode = Animation.LOOP_LINEAR
					ap.play(clip)
					break
	if root.get_child_count() == 0:
		root.free()
		return null
	return root


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
			if ResourceLoader.exists(DRAUGHT):
				return _draught()
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


func _draught() -> Node3D:
	var root := Node3D.new()
	var w: Node3D = Assets.scene(DRAUGHT).instantiate()
	root.add_child(w)
	var wheels: Array[Node3D] = []
	for n in ["wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr"]:
		var wn := w.find_child(n, true, false) as Node3D
		if wn:
			wheels.append(wn)
	root.set_meta("wheels", wheels)
	var horse := Critter.new()
	horse.kind = "horse"
	horse.claimed = true          # no wandering, no mounting: it is in harness
	horse.position = Vector3(0.0, 0.0, 3.0)
	root.add_child(horse)
	horse.remove_from_group.call_deferred("interactable")
	root.set_meta("horse", horse)
	var driver := Assets.character("Trader", 1.75, [])
	if driver:
		driver.position = Vector3(0.0, 0.88, 1.2)
		root.add_child(driver)
		var ap := Assets.animation_player(driver)
		if ap:
			for clip in ["Sitting_Idle", "Sit_Chair_Idle", "Life_Mx_Sit_Floor"]:
				if ap.has_animation(clip):
					ap.play(clip)
					break
	_drive.call_deferred(root, SPEED["wagon"])
	return root


## Walk cycle at the wagon's speed (Critter._play scales the clip to its measured ground speed), idle when halted.
func _drive(root: Node3D, speed: float) -> void:
	if not is_instance_valid(root) or not root.has_meta("horse"):
		return
	var h: Critter = root.get_meta("horse")
	if not is_instance_valid(h):
		return
	if speed > 0.05:
		h._play("Walk", speed / float(Critter.ANIM_GROUND_SPEEDS["horse"]["Walk"]))
	else:
		h._play("Idle")
