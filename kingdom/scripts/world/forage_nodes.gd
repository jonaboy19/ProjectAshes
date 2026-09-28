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
## Each live node is in the "interactable" group with prompt() and use(), so the
## HUD shows the button. This manager polls "interact" itself while the player
## stands by one of its nodes, so it works without a dispatcher in main.gd; if
## main.gd also calls use(), the per-frame guard stops a double pick.

const Gathering := preload("res://scripts/sim/gathering_items.gd")
const MAX_NODES := 12
const SPAWN := 55.0
const DESPAWN := 80.0
const CELL := 14.0
const REACH := 3.2
const BERRY_MODEL := "res://assets/generated/region/nature/bush_berry_lod1.glb"
const BERRY_MODEL_FULL := "res://assets/generated/region/nature/bush_berry.glb"
const CACHE_LIMIT := 4000

var focus := Vector3.ZERO
## cell -> day it was picked
var harvested: Dictionary = {}
var _cells: Dictionary = {}          # cell -> {ok, pos, kind}
var _active: Dictionary = {}         # cell -> ForageNode
var _pool: Array = []
var _timer := 0.0
var _menu_was_open := false
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
		_pool.append(n)


func _process(delta: float) -> void:
	_poll_interact()
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
	var day: int = WorldSim.day
	for c: Vector2i in harvested.keys():
		var info := _cell(c)
		var wait := int(Gathering.FORAGE.get(String(info.get("kind", "")), {}).get("respawn_days", 1))
		if day - int(harvested[c]) >= wait:
			harvested.erase(c)
	for c: Vector2i in _active.keys():
		var n: ForageNode = _active[c]
		if Vector2(n.global_position.x, n.global_position.z).distance_to(p) > DESPAWN or harvested.has(c):
			_release(c)
	if _active.size() >= MAX_NODES:
		return
	var want: Array = []
	var r := int(ceil(SPAWN / CELL))
	var here := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var c := here + Vector2i(dx, dz)
			if _active.has(c) or harvested.has(c):
				continue
			var info := _cell(c)
			if not bool(info["ok"]):
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
		out = {"ok": true, "kind": kind, "pos": Vector3(q.x, WorldGen.height(q.x, q.y), q.y),
			"yaw": rng.randf() * TAU}
	_cells[c] = out
	return out


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
		(child as Node3D).visible = child.name == n.kind
	if not n.has_node(n.kind):
		var v := _visual(n.kind)
		v.name = n.kind
		n.add_child(v)
	n.global_position = info["pos"]
	n.rotation.y = float(info["yaw"])
	n.visible = true
	n.add_to_group("interactable")
	_active[c] = n


func _release(c: Vector2i) -> void:
	var n: ForageNode = _active[c]
	_active.erase(c)
	n.visible = false
	if n.is_in_group("interactable"):
		n.remove_from_group("interactable")
	_pool.append(n)


# --- picking ------------------------------------------------------------------------

func collect(n: ForageNode) -> void:
	if not _active.has(n.cell) or _active[n.cell] != n:
		return
	var f: Dictionary = Gathering.FORAGE.get(n.kind, {})
	if f.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(n.cell.x, n.cell.y, WorldSim.day))
	var amount := rng.randi_range(int(f["min"]), int(f["max"]))
	var item := String(f["item"])
	Life.give(item, amount)
	Life.record(String(Gathering.FORAGE_TAGS.get(n.kind, "gathered_herbs")), 0.5)
	Game.say("Picked %d %s." % [amount, Life.item_name(item)])
	harvested[n.cell] = WorldSim.day
	_release(n.cell)


## Self-dispatch of the interact key while standing by one of our nodes.
func _poll_interact() -> void:
	var menu_open := _menu_open()
	var was := _menu_was_open
	_menu_was_open = menu_open
	if menu_open or was or _active.is_empty():
		return
	var pl: Variant = Life.player
	if not (pl is Node3D) or not is_instance_valid(pl) or not Input.is_action_just_pressed("interact"):
		return
	if not (pl as Node3D).has_method("nearest_interactable"):
		return
	var target: Variant = (pl as Node3D).call("nearest_interactable")
	if target is ForageNode and (target as ForageNode).manager == self:
		(target as ForageNode).use()


func _menu_open() -> bool:
	var scene := get_tree().current_scene
	var hud: Variant = scene.get("hud") if scene else null
	return hud is Object and is_instance_valid(hud) and (hud as Object).has_method("is_menu_open") \
		and bool((hud as Object).call("is_menu_open"))


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
