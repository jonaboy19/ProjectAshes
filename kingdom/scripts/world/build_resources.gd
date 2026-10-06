extends Node3D
## Building materials in the wild: trees to fell, rocks to quarry, clay pits and reed beds. Nodes come from a
## fixed grid (scripts/realm/construction.gd node_cell) so the same tree stands in the same place every visit.
## Everything in range is drawn with a few MultiMeshes (one draw call per kind); only the nearest handful get a
## pooled interactable body (an Interactable component, scripts/interaction/). Felled trees leave a stump and regrow, rocks and pits refill after a few days
## (Construction.gathered, saved with the realm). Strikes add up: a tree takes three swings, an axe adds a log
## per swing, a pickaxe a stone.

const D := preload("res://scripts/realm/construction_data.gd")
const Deposits := preload("res://scripts/world/deposits.gd")
const GatherRun := preload("res://scripts/world/gather_run.gd")
## Gather-session kind per node kind.
const SESSION_KIND := {"tree": "tree", "rock": "ore", "clay": "ore", "reeds": "herb"}
const SHOW_R := 70.0
const HIDE_R := 95.0
const POOL := 8
const REACH := 14.0

var focus := Vector3.ZERO
var _cells: Dictionary = {}               # Vector2i -> node_cell dict
var _spots: Array = []                    # pooled ResourceSpot
var _active: Dictionary = {}              # cell key String -> spot
var _mms: Dictionary = {}                 # name -> MultiMeshInstance3D
var _meshes: Dictionary = {}
var _mats: Dictionary = {}
var _timer := 0.0
var _sig := ""
var _last_strike := -1000
var deposits := Deposits.new()
var _panel: Control


class ResourceSpot extends Node3D:
	var manager: Node
	var key := ""
	var kind := ""
	var cell := Vector2i.ZERO

	func prompt() -> String:
		var nd: Dictionary = D.NODES.get(kind, {})
		return String(nd.get("verb", "Gather"))

	func use() -> void:
		manager.strike(self)


func _ready() -> void:
	for i in POOL:
		var s := ResourceSpot.new()
		s.manager = self
		s.visible = false
		add_child(s)
		Interactable.attach(s, {"id": "build_resources/%d" % i, "verb": "Gather", "enabled": false,
			"do": func(_pl: Node) -> void: s.use(),
			"label": func() -> String: return s.prompt()})
		_spots.append(s)


func _cons() -> RefCounted:
	return Life.realm.mod("construction")


func _center() -> Vector2:
	var pl: Variant = Life.player
	if pl is Node3D and is_instance_valid(pl):
		return Vector2((pl as Node3D).global_position.x, (pl as Node3D).global_position.z)
	return Vector2(focus.x, focus.z)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.8
	refresh(_center())


## Rebuilds what is drawn around `p`: call directly in tools and tests.
func refresh(p: Vector2) -> void:
	var cons := _cons()
	var day: int = WorldSim.day
	var r := int(ceil(SHOW_R / D.NODE_CELL))
	var here := Vector2i(floori(p.x / D.NODE_CELL), floori(p.y / D.NODE_CELL))
	var lists := {"tree_a": [], "tree_b": [], "stump": [], "rock": [], "clay": [], "reeds": []}
	var near: Array = []
	var sig_parts := PackedStringArray()
	if _cells.size() > 4000:
		_cells.clear()
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var c := here + Vector2i(dx, dz)
			var info: Dictionary = _cells.get(c, {})
			if info.is_empty():
				info = cons.node_cell(c)
				_cells[c] = info
			if not bool(info["ok"]):
				continue
			var pos: Vector3 = info["pos"]
			var d := Vector2(pos.x, pos.z).distance_to(p)
			if d > SHOW_R:
				continue
			var kind := String(info["kind"])
			var key: String = cons.node_key(c)
			var ready: bool = cons.node_ready(key, kind, day)
			var xf := Transform3D(Basis(Vector3.UP, float(info["yaw"])), pos)
			var scl := float(info["scale"])
			if ready:
				var name := kind
				if kind == "tree":
					name = "tree_a" if (absi(c.x * 7 + c.y * 13) % 3) != 0 else "tree_b"
					scl *= 0.62
				elif kind == "rock":
					scl *= 1.5
				(lists[name] as Array).append(xf.scaled_local(Vector3.ONE * scl))
				if d <= REACH:
					near.append([d, c, key, kind])
			else:
				if kind == "tree":
					(lists["stump"] as Array).append(xf.scaled_local(Vector3.ONE * scl))
			sig_parts.append("%s%d" % [key, 1 if ready else 0])
	var sig := ",".join(sig_parts)
	if sig != _sig:
		_sig = sig
		for name: String in lists:
			_fill(name, lists[name])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var want := {}
	for i in mini(near.size(), POOL):
		want[near[i][2]] = near[i]
	for key: String in _active.keys():
		if not want.has(key):
			_release(key)
	for key: String in want:
		if not _active.has(key):
			_claim(want[key])


func _claim(entry: Array) -> void:
	for s: ResourceSpot in _spots:
		if not s.visible:
			var info: Dictionary = _cells[entry[1]]
			s.key = entry[2]
			s.kind = entry[3]
			s.cell = entry[1]
			s.global_position = info["pos"]
			s.visible = true
			Interactable.set_active(s, true)
			_active[s.key] = s
			return


func _release(key: String) -> void:
	var s: ResourceSpot = _active[key]
	_active.erase(key)
	s.visible = false
	Interactable.set_active(s, false)


func _mm(name: String) -> MultiMeshInstance3D:
	if _mms.has(name):
		return _mms[name]
	var inst := MultiMeshInstance3D.new()
	inst.name = "MM_" + name
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _mesh(name)
	inst.multimesh = mm
	inst.visibility_range_end = HIDE_R + 40.0
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if name.begins_with("tree") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	_mms[name] = inst
	return inst


func _fill(name: String, xforms: Array) -> void:
	var inst := _mm(name)
	var mm := inst.multimesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	inst.visible = not xforms.is_empty()


func _mat(key: String, col: Color, rough := 0.95) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = rough
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_mats[key] = m
	return _mats[key]


func _mesh(name: String) -> Mesh:
	if _meshes.has(name):
		return _meshes[name]
	var m: Mesh = null
	match name:
		"tree_a":
			m = Assets.nature_mesh("CommonTree_3")
		"tree_b":
			m = Assets.nature_mesh("Pine_3")
		"rock":
			m = Assets.nature_mesh("Rock_Medium_3")
		"stump":
			var c := CylinderMesh.new()
			c.top_radius = 0.32
			c.bottom_radius = 0.42
			c.height = 0.5
			c.radial_segments = 8
			c.rings = 1
			c.material = _mat("stump", Color(0.42, 0.29, 0.17))
			m = _lift(c, 0.25)
		"clay":
			var c := CylinderMesh.new()
			c.top_radius = 1.1
			c.bottom_radius = 1.3
			c.height = 0.2
			c.radial_segments = 9
			c.rings = 1
			c.material = _mat("clay", Color(0.66, 0.4, 0.26), 0.7)
			m = _lift(c, 0.06)
		"reeds":
			m = _reed_mesh()
	if m == null:
		var b := BoxMesh.new()
		b.size = Vector3(0.6, 0.6, 0.6)
		m = b
	_meshes[name] = m
	return m


func _lift(m: Mesh, y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(m, 0, Transform3D(Basis.IDENTITY, Vector3(0, y, 0)))
	var out := st.commit()
	out.surface_set_material(0, m.surface_get_material(0) if m.surface_get_material(0) != null else (m as PrimitiveMesh).material)
	return out


## A clump of reed stalks: thin cones leaning every which way.
func _reed_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 11:
		var c := CylinderMesh.new()
		c.top_radius = 0.01
		c.bottom_radius = 0.035
		c.height = rng.randf_range(1.3, 1.9)
		c.radial_segments = 4
		c.rings = 1
		var lean := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.25))
		var pos := Vector3(rng.randf_range(-0.7, 0.7), c.height * 0.5, rng.randf_range(-0.7, 0.7))
		st.append_from(c, 0, Transform3D(lean, pos))
	var out := st.commit()
	out.surface_set_material(0, _mat("reed", Color(0.52, 0.56, 0.24), 0.9))
	return out


# --- gathering --------------------------------------------------------------------------

func _has_tool(tool: String) -> bool:
	if tool == "":
		return false
	if Life.count(tool) > 0:
		return true
	var eq: Variant = Life.get("equipment")
	return eq is Object and String((eq as Object).call("item_in", "main_hand")) == tool


## Deposit of a node kind: units = hp * per + finish bonus, regrown over the kind's regrow days.
static func dep_def(kind: String) -> Dictionary:
	var nd: Dictionary = D.NODES.get(kind, {})
	if nd.is_empty():
		return {}
	var cap := int(nd["hp"]) * (int(nd["per"]) + int(nd["bonus"])) + int(nd["finish"])
	return Deposits.make_def(String(SESSION_KIND.get(kind, "ore")), String(nd["item"]),
		{"cap": cap, "regrow": float(cap) / float(maxi(1, int(nd["regrow"]))), "level": 1})


func strike(s: ResourceSpot) -> void:
	var f := Engine.get_process_frames()
	if is_instance_valid(_panel) or f - _last_strike < 12:
		return
	_last_strike = f
	var cons := _cons()
	var nd: Dictionary = D.NODES.get(s.kind, {})
	if nd.is_empty() or not cons.node_ready(s.key, s.kind, WorldSim.day):
		return
	var def := dep_def(s.kind)
	var id := "build/dep/%s/%d_%d" % [s.kind, s.cell.x, s.cell.y]
	var tier := 1 if _has_tool(String(nd["tool"])) else 0
	_panel = GatherRun.open(self, deposits.node(id, def, WorldSim.day), String(nd["verb"]), tier,
		hash([s.cell.x, s.cell.y, WorldSim.day, f]), _on_gathered.bind(s.key, s.kind, id, tier))
	if _panel == null:
		_spend(s.key, s.kind)


## The deposit is empty: the world node shows as spent (stump, bare rock) until Construction regrows it.
func _spend(key: String, kind: String) -> void:
	var cons := _cons()
	cons.gathered[key] = {"hp": 0, "day": WorldSim.day, "t": WorldSim.day}
	_sig = ""
	refresh(_center())


func _on_gathered(res: Dictionary, key: String, kind: String, id: String, tier: int) -> void:
	_panel = null
	var def := dep_def(kind)
	var n: int = deposits.commit(id, def, res, WorldSim.day)
	var nd: Dictionary = D.NODES[kind]
	if n > 0:
		var text := "+%d %s" % [n, Life.item_name(String(res["item"]))]
		text += GatherRun.deliver(res, n)
		var disc := String(nd["skill"])
		if disc != "":
			Life.mastery.gain(disc, 0.03, WorldSim.day)
		Life.record("chopped_wood" if kind == "tree" else ("mined" if kind == "rock" else "foraged"), 0.3)
		if tier == 0 and String(nd["tool"]) != "":
			text += "  (%s would help.)" % ("An axe" if kind == "tree" else "A pickaxe")
		Game.say(text)
		Audio.play_ui("pickup")
	if deposits.is_depleted(id, def, WorldSim.day):
		_spend(key, kind)
