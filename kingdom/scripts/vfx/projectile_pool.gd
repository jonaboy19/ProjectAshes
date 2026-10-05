extends Node3D
## Pooled projectile bodies shared by the bow (arrows) and technique_caster.gd (orbs). Every node is built once in
## the constructor and only ever shown / hidden / moved afterwards: no per-shot new or free, and the caps hold.
## Arrows fly here (gravity, a world ray per step, a segment test against the target group) and then stick in the
## surface for a moment before going back to the pool; orbs are flown by their owner and returned with release_node().
## Caps (data/combat/player_weapons.json "pool"): when every arrow slot is busy the oldest stuck arrow is recycled,
## then the oldest flying one; orbs are never taken from a live cast (acquire_orb returns null, the cast still hits).
## Preload, no class_name:
##   const ProjectilePool := preload("res://scripts/vfx/projectile_pool.gd")
##   ProjectilePool.at(world_node).fire_arrow(origin, dir, speed, {...})

const WeaponRules := preload("res://scripts/combat/weapon_rules.gd")

const NODE_NAME := "ProjectilePool"
const WORLD_MASK := 1
const ARROW_HIT_RADIUS := 0.55
const ORB_LEAK_LIFE := 12.0        # an orb nobody released within this long goes back by itself
const PARK := Vector3(0, -500, 0)

signal arrow_hit(target: Node3D, damage: int, at: Vector3)
signal arrow_stuck(at: Vector3, on_body: bool)

## Test seam: Callable(from: Vector3, to: Vector3) -> Dictionary like intersect_ray ({} = nothing in the way).
var ray_fn := Callable()
var arrow_cap := 24
var orb_cap := 16
var stick_time := 3.0
var stick_time_body := 0.6
var arrow_life := 3.5

var _slots: Array[Dictionary] = []
var _serial := 0
var _arrow_mesh: Mesh
var _arrow_mat: StandardMaterial3D
var _orb_mesh: Mesh


## The pool under `world` (built on first use).
static func at(world: Node) -> Node3D:
	var found := world.get_node_or_null(NODE_NAME)
	if found:
		return found
	var pool: Node3D = (load("res://scripts/vfx/projectile_pool.gd") as GDScript).new()
	pool.name = NODE_NAME
	world.add_child(pool)
	return pool


func _init(arrows := -1, orbs := -1) -> void:
	top_level = true                  # slot positions are world positions whatever the parent does
	var c := WeaponRules.cfg("pool")
	arrow_cap = int(c["arrows"]) if arrows < 0 else arrows
	orb_cap = int(c["orbs"]) if orbs < 0 else orbs
	stick_time = float(c["stick_time"])
	stick_time_body = float(c["stick_time_body"])
	arrow_life = float(c["arrow_life"])
	_build()


func _build() -> void:
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.012
	shaft.bottom_radius = 0.012
	shaft.height = 0.7
	shaft.radial_segments = 5
	shaft.rings = 1
	_arrow_mesh = shaft
	_arrow_mat = StandardMaterial3D.new()
	_arrow_mat.albedo_color = Color(0.62, 0.5, 0.34)
	_arrow_mat.roughness = 0.9
	var head := CylinderMesh.new()
	head.top_radius = 0.0
	head.bottom_radius = 0.03
	head.height = 0.1
	head.radial_segments = 5
	head.rings = 1
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	sphere.radial_segments = 12
	sphere.rings = 6
	_orb_mesh = sphere
	for i in arrow_cap:
		var holder := Node3D.new()
		var s := MeshInstance3D.new()
		s.mesh = _arrow_mesh
		s.material_override = _arrow_mat
		s.rotation = Vector3(PI * 0.5, 0.0, 0.0)          # the cylinder's Y axis becomes the flight (-Z) axis
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(s)
		var h := MeshInstance3D.new()
		h.mesh = head
		h.material_override = _arrow_mat
		h.position = Vector3(0, 0, -0.4)
		h.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(h)
		_register(holder, "arrow")
	for i in orb_cap:
		var mi := MeshInstance3D.new()
		mi.mesh = _orb_mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_register(mi, "orb")


func _register(node: Node3D, kind: String) -> void:
	node.visible = false
	node.position = PARK
	add_child(node)
	_slots.append({"node": node, "kind": kind, "state": "free", "serial": 0, "age": 0.0, "timer": 0.0,
		"pos": PARK, "vel": Vector3.ZERO, "damage": 0, "knockback": 0.0, "shooter": null, "group": "team1",
		"gravity": 5.5})


# --- counts (tests, debug) ---------------------------------------------------------------------

func capacity(kind: String) -> int:
	return arrow_cap if kind == "arrow" else orb_cap


func in_use(kind: String) -> int:
	var n := 0
	for s: Dictionary in _slots:
		if s["kind"] == kind and s["state"] != "free":
			n += 1
	return n


func stuck_count() -> int:
	var n := 0
	for s: Dictionary in _slots:
		if s["state"] == "stuck":
			n += 1
	return n


func slot_count() -> int:
	return _slots.size()


## Every node the pool ever owns: constant for the life of the pool (the "no growth" invariant).
func node_total() -> int:
	return get_child_count()


# --- acquire / release -------------------------------------------------------------------------

## A free slot of `kind`; arrows recycle the oldest stuck, then the oldest flying one. {} = none (orbs only).
func acquire(kind: String) -> Dictionary:
	var pick := -1
	var oldest := -1
	var oldest_stuck := -1
	for i in _slots.size():
		var s: Dictionary = _slots[i]
		if s["kind"] != kind:
			continue
		if s["state"] == "free":
			pick = i
			break
		if kind == "arrow":
			if s["state"] == "stuck" and (oldest_stuck < 0 or int(s["serial"]) < int(_slots[oldest_stuck]["serial"])):
				oldest_stuck = i
			if oldest < 0 or int(s["serial"]) < int(_slots[oldest]["serial"]):
				oldest = i
	if pick < 0:
		pick = oldest_stuck if oldest_stuck >= 0 else oldest
	if pick < 0:
		return {}
	var slot: Dictionary = _slots[pick]
	_serial += 1
	slot["serial"] = _serial
	slot["state"] = "fly"
	slot["age"] = 0.0
	slot["timer"] = 0.0
	(slot["node"] as Node3D).visible = true
	return slot


func release(slot: Dictionary) -> void:
	if slot.is_empty():
		return
	slot["state"] = "free"
	slot["shooter"] = null
	var n := slot["node"] as Node3D
	n.visible = false
	n.position = PARK


## A pooled glowing orb for a technique projectile, or null when all are in flight. Return it with release_node().
func acquire_orb(color: Color, emission := 3.0) -> Node3D:
	var slot := acquire("orb")
	if slot.is_empty():
		return null
	var mat := ((slot["node"] as MeshInstance3D).material_override) as StandardMaterial3D
	mat.albedo_color = color.lightened(0.3)
	mat.emission = color
	mat.emission_energy_multiplier = emission
	return slot["node"]


## True when `node` was a pool node (now released); false for any other node, which the caller frees itself.
func release_node(node: Node) -> bool:
	for s: Dictionary in _slots:
		if s["node"] == node:
			release(s)
			return true
	return false


# --- arrows ----------------------------------------------------------------------------------

## Launches an arrow. opts: damage, knockback, shooter (Node, excluded from hits), group (hit group, "team1"),
## gravity, life. Returns the slot (inspect "pos" / "vel" / "state" in tests).
func fire_arrow(origin: Vector3, dir: Vector3, speed: float, opts := {}) -> Dictionary:
	var slot := acquire("arrow")
	if slot.is_empty():
		return {}
	slot["pos"] = origin
	slot["vel"] = dir.normalized() * speed
	slot["damage"] = int(opts.get("damage", 10))
	slot["knockback"] = float(opts.get("knockback", 2.0))
	slot["shooter"] = opts.get("shooter", null)
	slot["group"] = String(opts.get("group", "team1"))
	slot["gravity"] = float(opts.get("gravity", WeaponRules.cfg("bow")["gravity"]))
	slot["timer"] = float(opts.get("life", arrow_life))
	_orient(slot)
	return slot


func _orient(slot: Dictionary) -> void:
	var n := slot["node"] as Node3D
	n.position = slot["pos"]
	var v: Vector3 = slot["vel"]
	if v.length() > 0.01:
		var up := Vector3.UP if absf(v.normalized().y) < 0.98 else Vector3.RIGHT
		n.basis = Basis.looking_at(v.normalized(), up)


func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	for s: Dictionary in _slots:
		match s["state"]:
			"fly":
				if s["kind"] == "arrow":
					_fly(s, delta)
				else:
					s["age"] = float(s["age"]) + delta
					if float(s["age"]) > ORB_LEAK_LIFE:
						release(s)
			"stuck":
				s["timer"] = float(s["timer"]) - delta
				if float(s["timer"]) <= 0.0:
					release(s)


func _fly(s: Dictionary, delta: float) -> void:
	var from: Vector3 = s["pos"]
	var v: Vector3 = s["vel"]
	v.y -= float(s["gravity"]) * delta
	var to := from + v * delta
	s["vel"] = v
	s["timer"] = float(s["timer"]) - delta
	var hit := _ray(from, to, s)
	# Bodies first, along the segment actually flown (up to the wall when there is one).
	var seg_end: Vector3 = hit["position"] if not hit.is_empty() else to
	var victim := _victim(from, seg_end, s)
	if victim == null and not hit.is_empty():
		var col: Variant = hit.get("collider")
		if col is Node3D and (col as Node).is_in_group(String(s["group"])) and (col as Node).has_method("take_damage"):
			victim = col      # the ray struck the body's own collider first
	if victim != null:
		var push := Vector3(v.x, 0.0, v.z).normalized() * float(s["knockback"])
		var dmg := int(s["damage"])
		var who: Variant = s["shooter"] if is_instance_valid(s["shooter"]) else null     # the archer may be gone by now
		victim.call("take_damage", dmg, who, push)
		arrow_hit.emit(victim, dmg, seg_end)
		s["pos"] = victim.global_position + Vector3(0, 1.0, 0) if victim.is_inside_tree() else seg_end
		_stick(s, stick_time_body, true)
		return
	if not hit.is_empty():
		s["pos"] = (hit["position"] as Vector3) + v.normalized() * 0.18      # buried a little in the surface
		_stick(s, stick_time, false)
		return
	s["pos"] = to
	_orient(s)
	if float(s["timer"]) <= 0.0:
		release(s)


func _stick(s: Dictionary, seconds: float, on_body: bool) -> void:
	s["state"] = "stuck"
	s["timer"] = seconds
	s["vel"] = Vector3.ZERO
	(s["node"] as Node3D).position = s["pos"]
	arrow_stuck.emit(s["pos"], on_body)


func _ray(from: Vector3, to: Vector3, s: Dictionary) -> Dictionary:
	if ray_fn.is_valid():
		return ray_fn.call(from, to)
	if not is_inside_tree():
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	var shooter: Variant = s["shooter"]
	if is_instance_valid(shooter) and shooter is CollisionObject3D:
		q.exclude = [(shooter as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


func _victim(from: Vector3, to: Vector3, s: Dictionary) -> Node3D:
	if not is_inside_tree():
		return null
	var best: Node3D = null
	var best_t := INF
	for n in get_tree().get_nodes_in_group(String(s["group"])):
		var e := n as Node3D
		if e == null or e == s["shooter"] or not is_instance_valid(e) or not e.has_method("take_damage"):
			continue
		var dead: Variant = e.get("dead")
		if dead is bool and dead:
			continue
		var c := e.global_position + Vector3(0, 0.9, 0)
		var p := Geometry3D.get_closest_point_to_segment(c, from, to)
		if Vector2(c.x - p.x, c.z - p.z).length() <= ARROW_HIT_RADIUS and absf(c.y - p.y) < 1.1:
			var t := from.distance_to(p)
			if t < best_t:
				best_t = t
				best = e
	return best
