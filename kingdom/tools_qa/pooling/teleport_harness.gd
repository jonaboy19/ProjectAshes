extends Node
## Teleport memory: the real streamers (terrain, water, settlements, region dressing, camps, ambient life) follow a focus that
## jumps across five far-apart points (the five towns farthest from each other, then back to the first). After each jump the
## scene settles and the harness prints Performance monitors, the static caches and each streamer's live count, so growth
## that outlives the jump shows up as a number that keeps climbing. One JSON line per point, and a summary.
##   godot --headless --fixed-fps 20 res://tools_qa/pooling/teleport_harness.tscn -- [--out=/path.json] [--points=5]
## Run it only with `free -m` showing plenty available (it streams a full 650 m settlement ring five times).

const CellStreamer := preload("res://scripts/core/cell_streamer.gd")
const NodePool := preload("res://scripts/core/node_pool.gd")
const SETTLE_FRAMES := 90

var _out := ""
var _only := ""            # --only=terrain|settlements|region|camps|ambient : run just that streamer (bisecting growth)
var _cycles := 1           # --cycles=N : visit the first --points points N times over (does the second lap grow? it must not)
var _pingpong := false     # --pingpong : jump between the first two points instead of walking the far-point list
var _points := 5
var _terrain: TerrainStreamer
var _water: Node3D
var _settlements: SettlementBuilder
var _region: RegionDressing
var _camps: Node3D
var _ambient: Node3D
var _population: Node3D    # --only=population : PopulationLOD with its impostor baker (the sprite atlas cache)
var _baker: Node
var _world: Node3D
var _frames := 0
var _booted := false
var _rows: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--points="):
			_points = int(a.substr(9))
		elif a.begins_with("--only="):
			_only = a.substr(7)
		elif a.begins_with("--cycles="):
			_cycles = maxi(1, int(a.substr(9)))
		elif a == "--pingpong":
			_pingpong = true


func _process(_d: float) -> void:
	_frames += 1
	if _frames < 3 or _booted:
		return
	_booted = true
	_run()


func _far_points(n: int) -> Array:
	var pts: Array = []
	var first: Vector2 = WorldGen.settlements[0]["pos"]
	pts.append(first)
	while pts.size() < n:
		var best: Vector2 = first
		var bd := -1.0
		for s in WorldGen.settlements:
			var p: Vector2 = s["pos"]
			var d := INF
			for q: Vector2 in pts:
				d = minf(d, p.distance_to(q))
			if d > bd:
				bd = d
				best = p
		pts.append(best)
	return pts


func _focus_all(p: Vector2) -> void:
	var f := Vector3(p.x, WorldGen.height(p.x, p.y) + 0.5, p.y)
	for n: Variant in [_terrain, _water, _settlements, _region, _camps, _ambient, _population]:
		if n != null:
			(n as Node).set("focus", f)
	if _population != null:
		_population.call("refresh")
	CellStreamer.shared().update(f)


func _run() -> void:
	seed(4242)
	_world = Node3D.new()
	get_tree().root.add_child(_world)
	_terrain = TerrainStreamer.new()
	_water = WaterStreamer.new()
	_settlements = SettlementBuilder.new()
	_region = RegionDressing.new()
	_camps = (load("res://scripts/world/monster_camps.gd") as GDScript).new()
	_ambient = (load("res://scripts/world/ambient_life.gd") as GDScript).new()
	if _only == "population":
		_baker = ImpostorBaker.new()
		_world.add_child(_baker)
		for look: String in PopulationLOD.LOOK_MODEL:
			var model: Array = PopulationLOD.LOOK_MODEL[look]
			var keep: Array[String] = []
			keep.assign(model[1])
			await _baker.bake(look, model[0], keep, "Walking_A")
		_population = PopulationLOD.new()
		_world.add_child(_population)
		_population.setup(_baker)
	var all := {"terrain": _terrain, "water": _water, "settlements": _settlements, "region": _region, "camps": _camps, "ambient": _ambient}
	for k: String in all:
		if _only == "" or _only == k:
			_world.add_child(all[k])
	var pts := _far_points(_points)
	if _pingpong:
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[1]
		pts = [a, b, a, b, a, b, a]
	else:
		var lap := pts.duplicate()
		for c in _cycles - 1:
			pts.append_array(lap)
		pts.append(pts[0])
	_row("boot", Vector2.ZERO)
	for i in pts.size():
		var p: Vector2 = pts[i]
		_focus_all(p)
		if _terrain.is_inside_tree():
			_terrain.build_all_now()
		if _water.is_inside_tree():
			_water.call("build_all_now")
		if _settlements.is_inside_tree():
			for k in 4:
				_settlements.update_now()
			_settlements.finish_prop_jobs()
		for k in SETTLE_FRAMES:
			await get_tree().process_frame
			_focus_all(p)
			if k % 10 == 0 and _settlements.is_inside_tree():
				_settlements.update_now()
		var guard := 0
		while _region.is_inside_tree() and not _region._queue.is_empty() and guard < 600:
			await get_tree().process_frame
			guard += 1
		await get_tree().process_frame
		_row("teleport_%d" % (i + 1), p)
	if OS.get_cmdline_user_args().has("--orphans"):
		print_orphan_nodes()
	var json := JSON.stringify(_rows, "  ")
	print("TELEPORT_RESULT ", json)
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		if f:
			f.store_string(json)
			f.close()
	NodePool.clear_all()
	get_tree().quit()


static func rss_mb() -> float:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return 0.0
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("VmRSS:"):
			return float(line.split(" ", false)[1]) / 1024.0
	return 0.0


## Entry counts of the static caches a streamed world fills (the ones that could outlive the cells that made them).
func _cache_sizes() -> Dictionary:
	var TownIdentity_: GDScript = load("res://scripts/world/town_identity.gd")
	var HouseDetails_: GDScript = load("res://scripts/world/house_details.gd")
	var CharacterMerge_: GDScript = load("res://scripts/world/character_merge.gd")
	var Assets_: GDScript = load("res://scripts/world/assets.gd")
	var pools := {"pools": NodePool.shared_pools().size(), "idle": 0, "live": 0}
	for k: String in NodePool.shared_pools():
		var st: Dictionary = NodePool.shared_pools()[k].stats()
		pools["idle"] += int(st["idle"])
		pools["live"] += int(st["live"])
	return {
		"town_identity": [(TownIdentity_.get("_cache") as Dictionary).size(), (TownIdentity_.get("_mesh_cache") as Dictionary).size(),
			(TownIdentity_.get("_mat_cache") as Dictionary).size(), (TownIdentity_.get("_fit_cache") as Dictionary).size()],
		"assets": [(Assets_.get("_mesh_cache") as Dictionary).size(), (Assets_.get("_building_cache") as Dictionary).size(),
			(Assets_.get("_materials") as Dictionary).size(), (Assets_.get("_static_cache") as Dictionary).size()],
		"house_details_meshes": (HouseDetails_.get("_mesh_cache") as Dictionary).size(),
		"character_merge": (CharacterMerge_.get("_cache") as Dictionary).size(),
		"node_pools": pools,
	}


func _row(label: String, p: Vector2) -> void:
	var P := Performance
	var row := {
		"label": label, "at": [snappedf(p.x, 1.0), snappedf(p.y, 1.0)],
		"objects": int(P.get_monitor(P.OBJECT_COUNT)), "nodes": int(P.get_monitor(P.OBJECT_NODE_COUNT)),
		"resources": int(P.get_monitor(P.OBJECT_RESOURCE_COUNT)), "orphans": int(P.get_monitor(P.OBJECT_ORPHAN_NODE_COUNT)),
		"static_mb": snappedf(P.get_monitor(P.MEMORY_STATIC) / 1048576.0, 0.1),
		"tex_mb": snappedf(P.get_monitor(P.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"buf_mb": snappedf(P.get_monitor(P.RENDER_BUFFER_MEM_USED) / 1048576.0, 0.1),
		"video_mb": snappedf(P.get_monitor(P.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"rss_mb": snappedf(rss_mb(), 1.0),
		"terrain_chunks": _terrain.loaded_count(), "settlements": _settlements._built.size(), "dressing_sites": _region.built_count(),
		"dressing_bake_cache": _region._bake_cache.size(),
		"terrain_plans": _terrain._plans.size(),
		"caches": _cache_sizes(),
		"population": [_population.full_count, _population.sprite_count, _population._sprite_cache.size()] if _population != null else [],
		"cell_teleports": CellStreamer.shared().teleports,
	}
	_rows.append(row)
	print("TELEPORT_ROW ", JSON.stringify(row))
