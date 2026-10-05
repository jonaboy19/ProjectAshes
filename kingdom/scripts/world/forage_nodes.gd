extends Node3D
## Small things to pick near the player: healing herbs (sold to the herbalist or
## used as a salve), wood mushrooms and firewood on forest floors, wild berry
## bushes in open meadows.
##
## Spots come from a fixed grid: every CELL-metre cell may hold one spot, rolled
## from the cell's coordinates, so the same bush is in the same place every time
## you pass. Only the nearest MAX_NODES spots inside SPAWN get a body, taken from
## a fixed pool, and bodies beyond DESPAWN go back to the pool (the same
## spawn/despawn ring as AmbientLife). A picked spot stays bare for the kind's
## respawn_days in-game days (Gathering.FORAGE).
##
## Each live node carries an enabled Interactable (scripts/interaction/interactable.gd) plus prompt() and
## use(); the player's InteractionController runs use() when the picker chooses it, and the per-frame
## guard stops a double pick.

const Gathering := preload("res://scripts/sim/gathering_items.gd")
const Deposits := preload("res://scripts/world/deposits.gd")
const GatherRun := preload("res://scripts/world/gather_run.gd")
const SeasonsScript := preload("res://scripts/sim/seasons.gd")
const MAX_NODES := 12
const SPAWN := 55.0
const DESPAWN := 80.0
const CELL := 14.0
const REACH := 3.2
const BERRY_MODEL := "res://assets/generated/region/nature/bush_berry_lod1.glb"
const BERRY_MODEL_FULL := "res://assets/generated/region/nature/bush_berry.glb"
const CACHE_LIMIT := 4000

var focus := Vector3.ZERO
## Each spot is a Deposits entry (WorldState overlay "forage/dep/<kind>/<x>_<y>"), gathered through a GatherSession.
var deposits := Deposits.new()
var _panel: Control
var _cells: Dictionary = {}          # cell -> {ok, pos, kind}
var _active: Dictionary = {}         # cell -> ForageNode
var _pool: Array = []
var _timer := 0.0
var _mats: Dictionary = {}
var _meshes: Dictionary = {}
var _berry_scene: PackedScene


class ForageNode extends Node3D:
	var manager: Node
	var cell := Vector2i.ZERO
	var kind := ""
	var _last_frame := -1000

	func prompt() -> String:
		return String(Gathering.FORAGE.get(kind, {}).get("verb", "Gather"))

	func use() -> void:
		var f := Engine.get_process_frames()
		if f - _last_frame < 10:
			return
		_last_frame = f
		manager.collect(self)


func _ready() -> void:
	Gathering.register(Life)
	for i in MAX_NODES:
		var n := ForageNode.new()
		n.manager = self
		n.visible = false
		add_child(n)
		Interactable.attach(n, {"id": "forage/%d" % i, "verb": "Gather", "enabled": false,
			"do": func(_pl: Node) -> void: n.use(),
			"label": func() -> String: return n.prompt()})
		_pool.append(n)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	var p := _center()
	_refresh(p)


func _center() -> Vector2:
	var pl: Variant = Life.player
	if pl is Node3D and is_instance_valid(pl):
		return Vector2((pl as Node3D).global_position.x, (pl as Node3D).global_position.z)
	return Vector2(focus.x, focus.z)


# --- spawn ring -------------------------------------------------------------------

func _refresh(p: Vector2) -> void:
	for c: Vector2i in _active.keys():
		var n: ForageNode = _active[c]
		if Vector2(n.global_position.x, n.global_position.z).distance_to(p) > DESPAWN or _spent(c, n.kind):
			_release(c)
	if _active.size() >= MAX_NODES:
		return
	var want: Array = []
	var r := int(ceil(SPAWN / CELL))
	var here := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var c := here + Vector2i(dx, dz)
			if _active.has(c):
				continue
			var info := _cell(c)
			if not bool(info["ok"]) or not _in_season(info) or _spent(c, String(info["kind"])):
				continue
			var pos: Vector3 = info["pos"]
			var d := Vector2(pos.x, pos.z).distance_to(p)
			if d < SPAWN:
				want.append([d, c])
	want.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for w: Array in want:
		if _active.size() >= MAX_NODES or _pool.is_empty():
			break
		_place(w[1])


## The spot a grid cell holds (or {ok: false}); deterministic per cell.
func _cell(c: Vector2i) -> Dictionary:
	if _cells.has(c):
		return _cells[c]
	if _cells.size() > CACHE_LIMIT:
		_cells.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(c.x, c.y, 7717))
	var out := {"ok": false}
	var q := (Vector2(c) + Vector2(rng.randf_range(0.15, 0.85), rng.randf_range(0.15, 0.85))) * CELL
	var forest := WorldGen.forest_density(q.x, q.y)
	var chance := 0.42 if forest >= 0.35 else 0.22
	if rng.randf() < chance and _spot_ok(q):
		var kind := Gathering.forage_kind(forest, rng.randf())
		# Fixed per-cell luck so a few mushroom patches also hold outside
		# autumn ("mostly in autumn"), without the spot flickering day to day.
		out = {"ok": true, "kind": kind, "pos": Vector3(q.x, WorldGen.height(q.x, q.y), q.y),
			"yaw": rng.randf() * TAU, "off_season": rng.randf() < 0.2}
	_cells[c] = out
	return out


## Berries only grow in summer/autumn; mushrooms are mostly an autumn thing,
## with a few patches (see "off_season" above) fruiting year-round.
func _in_season(info: Dictionary) -> bool:
	var kind := String(info.get("kind", ""))
	if kind != "berries" and kind != "mushroom":
		return true
	var cal_day: int = WorldSim.seasons.current_day() if WorldSim.seasons else int(WorldSim.day)
	if SeasonsScript.forage_in_season(kind, cal_day):
		return true
	return kind == "mushroom" and bool(info.get("off_season", false))


func _spot_ok(q: Vector2) -> bool:
	if WorldGen.is_water(q.x, q.y) or WorldGen.near_water(q.x, q.y, 2.0):
		return false
	if WorldGen.road_distance(q.x, q.y) < 5.0:
		return false
	var near := WorldGen.nearest_settlement(q)
	if not near.is_empty() and q.distance_to(near["pos"]) < float(near["radius"]) * 1.15:
		return false
	return true


func _place(c: Vector2i) -> void:
	var info := _cell(c)
	var n: ForageNode = _pool.pop_back()
	n.cell = c
	n.kind = String(info["kind"])
	for child in n.get_children():
		if child is Node3D:
			(child as Node3D).visible = child.name == n.kind
	if not n.has_node(n.kind):
		var v := _visual(n.kind)
		v.name = n.kind
		n.add_child(v)
	n.global_position = info["pos"]
	n.rotation.y = float(info["yaw"])
	n.visible = true
	Interactable.set_active(n, true)
	_active[c] = n


func _release(c: Vector2i) -> void:
	var n: ForageNode = _active[c]
	_active.erase(c)
	n.visible = false
	Interactable.set_active(n, false)
	_pool.append(n)


# --- picking ------------------------------------------------------------------------

static func dep_id(c: Vector2i, kind: String) -> String:
	return "forage/dep/%s/%d_%d" % [kind, c.x, c.y]


## Deposit definition of a forage kind: cap from the kind's max pick, regrown in its respawn_days.
static func dep_def(kind: String) -> Dictionary:
	var f: Dictionary = Gathering.FORAGE.get(kind, {})
	if f.is_empty():
		return {}
	var cap := int(f["max"]) + 2
	return Deposits.make_def("tree" if kind == "firewood" else "herb", String(f["item"]),
		{"cap": cap, "regrow": float(cap) / float(maxi(1, int(f["respawn_days"]))), "level": 1})


func _spent(c: Vector2i, kind: String) -> bool:
	var def := dep_def(kind)
	return def.is_empty() or deposits.is_depleted(dep_id(c, kind), def, WorldSim.day)


func collect(n: ForageNode) -> void:
	if _panel != null or not _active.has(n.cell) or _active[n.cell] != n:
		return
	var def := dep_def(n.kind)
	if def.is_empty():
		return
	var id := dep_id(n.cell, n.kind)
	var node := deposits.node(id, def, WorldSim.day)
	var tier := 1 if n.kind == "firewood" and GatherRun.has_tool("wood_axe") else 0
	_panel = GatherRun.open(self, node, String(Gathering.FORAGE[n.kind]["verb"]), tier,
		hash(Vector3i(n.cell.x, n.cell.y, Engine.get_process_frames())), _on_gathered.bind(n.cell, n.kind))
	if _panel == null:
		_release(n.cell)


func _on_gathered(res: Dictionary, cell: Vector2i, kind: String) -> void:
	_panel = null
	var n: int = deposits.commit(dep_id(cell, kind), dep_def(kind), res, WorldSim.day)
	if n > 0:
		var text := "Picked %d %s." % [n, Life.item_name(String(res["item"]))]
		text += GatherRun.deliver(res, n)
		Life.record(String(Gathering.FORAGE_TAGS.get(kind, "gathered_herbs")), 0.5)
		var lvl := GatherRun.skill_level(String(res.get("skill", "")))
		if GatherRun.grant_xp(res) > lvl:
			text += "  Your %s improves!" % String(res["skill"])
		Game.say(text)
	if _active.has(cell) and _spent(cell, kind):
		_release(cell)


# --- visuals ------------------------------------------------------------------------

func _mat(key: String, col: Color) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.9
		_mats[key] = m
	return _mats[key]


func _mesh(key: String, make: Callable) -> Mesh:
	if not _meshes.has(key):
		_meshes[key] = make.call()
	return _meshes[key]


func _part(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = DESPAWN
	return mi


func _visual(kind: String) -> Node3D:
	var root := Node3D.new()
	match kind:
		"berries":
			if _berry_scene == null:
				var path := BERRY_MODEL if ResourceLoader.exists(BERRY_MODEL) else BERRY_MODEL_FULL
				if ResourceLoader.exists(path):
					_berry_scene = load(path)
			if _berry_scene:
				var bush: Node3D = _berry_scene.instantiate()
				var box := Assets.visual_aabb(bush)
				bush.scale = Vector3.ONE * (0.9 / maxf(box.size.y, 0.01))
				root.add_child(bush)
			else:
				var leaf := _mesh("bush", func() -> Mesh:
					var s := SphereMesh.new()
					s.radius = 0.45
					s.height = 0.7
					s.radial_segments = 8
					s.rings = 4
					return s)
				root.add_child(_part(leaf, _mat("leaf", Color(0.2, 0.36, 0.16)), Vector3(0, 0.35, 0)))
			var berry := _mesh("berry", func() -> Mesh:
				var s := SphereMesh.new()
				s.radius = 0.045
				s.height = 0.09
				s.radial_segments = 6
				s.rings = 3
				return s)
			for i in 7:
				var a := TAU * i / 7.0
				root.add_child(_part(berry, _mat("berry", Color(0.62, 0.08, 0.16)),
					Vector3(cos(a) * 0.36, 0.35 + 0.18 * sin(a * 2.0), sin(a) * 0.36)))
		"mushroom":
			var stem := _mesh("stem", func() -> Mesh:
				var c := CylinderMesh.new()
				c.top_radius = 0.025
				c.bottom_radius = 0.035
				c.height = 0.14
				c.radial_segments = 6
				c.rings = 1
				return c)
			var cap := _mesh("cap", func() -> Mesh:
				var s := SphereMesh.new()
				s.radius = 0.08
				s.height = 0.08
				s.is_hemisphere = true
				s.radial_segments = 8
				s.rings = 3
				return s)
			for i in 3:
				var off := Vector3(cos(i * 2.1) * 0.12, 0, sin(i * 2.1) * 0.12) * (0.0 if i == 0 else 1.0)
				var k := 1.0 - i * 0.22
				root.add_child(_part(stem, _mat("stem", Color(0.88, 0.84, 0.72)), off + Vector3(0, 0.07 * k, 0), Vector3.ZERO, Vector3.ONE * k))
				root.add_child(_part(cap, _mat("cap", Color(0.55, 0.28, 0.14)), off + Vector3(0, 0.14 * k, 0), Vector3.ZERO, Vector3.ONE * k))
		"herb":
			var blade := _mesh("blade", func() -> Mesh:
				var c := CylinderMesh.new()
				c.top_radius = 0.0
				c.bottom_radius = 0.03
				c.height = 0.34
				c.radial_segments = 4
				c.rings = 1
				return c)
			var bloom := _mesh("bloom", func() -> Mesh:
				var s := SphereMesh.new()
				s.radius = 0.035
				s.height = 0.07
				s.radial_segments = 6
				s.rings = 3
				return s)
			for i in 6:
				var a := TAU * i / 6.0
				var tilt := Vector3(sin(a) * 0.35, 0, cos(a) * 0.35)
				root.add_child(_part(blade, _mat("herb", Color(0.3, 0.52, 0.24)), Vector3(cos(a) * 0.05, 0.16, sin(a) * 0.05), tilt))
				if i % 2 == 0:
					root.add_child(_part(bloom, _mat("bloom", Color(0.66, 0.52, 0.86)), Vector3(cos(a) * 0.12, 0.32, sin(a) * 0.12)))
		"firewood":
			var log_mesh := _mesh("log", func() -> Mesh:
				var c := CylinderMesh.new()
				c.top_radius = 0.06
				c.bottom_radius = 0.07
				c.height = 0.7
				c.radial_segments = 7
				c.rings = 1
				return c)
			var bark := _mat("bark", Color(0.36, 0.25, 0.16))
			root.add_child(_part(log_mesh, bark, Vector3(-0.08, 0.07, 0), Vector3(0, 0, PI * 0.5)))
			root.add_child(_part(log_mesh, bark, Vector3(0.08, 0.07, 0.02), Vector3(0, 0.15, PI * 0.5)))
			root.add_child(_part(log_mesh, bark, Vector3(0, 0.19, 0), Vector3(0, -0.2, PI * 0.5)))
	return root
