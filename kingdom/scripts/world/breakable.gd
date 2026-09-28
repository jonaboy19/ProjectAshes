extends StaticBody3D
## A breakable street prop: barrels, crates, baskets, buckets, sacks.
##
## The prop itself stays a MultiMesh instance (settlement clutter) or a plain
## node (region sites); this body is its box collider. When it breaks, the
## instance is hidden (zero-scale transform, or the node made invisible), the
## collider is disabled and 6-10 rigid shards fly away from the hit, freeze
## after SHARD_LIFE seconds and shrink out. A dust puff and a wood crack play.
## Barrels and crates can drop a few coins, an apple or firewood. At most
## MAX_SHARDS shards live at once across the whole world (oldest go first).
## Broken props come back once the player has left (REGEN_DIST for
## REGEN_AWAY_SECONDS) or a game day later when the player is not right there.
##
## Shards are the prop's own mesh cut into a 2 x 2 x 2 grid over its AABB
## (each triangle goes to the cell holding its centroid), cached per mesh,
## topped up with small box splinters in the prop's material. No Blender
## pre-fracture needed. The swap-intact-for-cached-shards idea, the cached
## per-source shard meshes and shapes, and shrinking shards out instead of
## alpha-fading them follow Jummit's godot-destruction-plugin (MIT, see
## CREDITS.md).
##
## Hitting it: take_damage(amount, from, knockback) is duck-typed like
## Wolf / Critter, so anything that hits "breakable" bodies just works. The
## player's melee is shadowed rather than joined: tick() sees a new swing
## (player._swing_id), waits for its hit frame and sweeps nearby breakables
## with player.gd's own reach test (2.6 m, 0.2 facing dot). Breakables never
## join "team1", so main.gd's battle-music check, follower aggro and the
## player's target-assist snap ignore them. SettlementBuilder and
## RegionDressing call tick() every frame; it runs once per frame.
##
## Used through preload (no class_name):
##   const Breakable := preload("res://scripts/world/breakable.gd")
##   var b: StaticBody3D = Breakable.new(); b.setup_instance(mm, i, t, mesh, "barrel")

const MAX_SHARDS := 30
const SHARD_LIFE := 3.0
const SHARD_SHRINK := 0.5
const MIN_SHARDS := 6
const MAX_PER_BREAK := 10
## player.gd melee reach and facing test (see Player._resolve_hit).
const MELEE_REACH := 2.6
const MELEE_DOT := 0.2
## Knockback at or above this breaks any prop in one blow (the stab finisher is 7).
const STRONG_IMPACT := 6.0
const REGEN_DIST := 80.0
const REGEN_AWAY_SECONDS := 5.0
## A day-old break only regrows when the player is at least this far away.
const REGEN_DAY_MIN_DIST := 25.0
## Shards collide with the world (layer 1) but sit on no layer themselves, so
## the player, NPCs and camera never trip over them.
const SHARD_MASK := 1

## kind -> [health, loot table ("" = none), wood?]
const KINDS := {
	"barrel": [14, "barrel", true],
	"crate": [14, "crate", true],
	"crate_stack": [40, "crate_stack", true],
	"sack_pile": [20, "", false],
	"scan/wooden_crate_01": [10, "crate", true],
	"scan/wicker_basket_01": [1, "", true],
	"scan/wooden_bucket_01": [1, "", true],
}
## Loot table -> list of [item, chance, min, max]. "gold" goes to Game.add_gold,
## everything else through Life.give.
const LOOT := {
	"barrel": [["gold", 0.45, 1, 4], ["apple", 0.3, 1, 1], ["firewood", 0.2, 1, 2]],
	"crate": [["gold", 0.4, 2, 5], ["apple", 0.25, 1, 2], ["firewood", 0.35, 1, 2]],
	"crate_stack": [["gold", 0.6, 3, 8], ["apple", 0.4, 1, 2], ["firewood", 0.6, 1, 3]],
}

static var _all: Array = []                # every breakable in the tree
static var _broken: Array = []
static var _shards: Array = []             # live shards, oldest first
static var _chunk_cache := {}              # Mesh -> Array of [ArrayMesh, centre, size]
static var _splinter_cache := {}           # Mesh -> [BoxMesh, BoxShape3D]
static var _dust_mesh: QuadMesh
static var _dust_ramp: Gradient
static var _dust_curve: Curve
static var _tick_frame := -1
static var _seen_swing := -1
static var _regen_timer := 0.0
static var _rng := RandomNumberGenerator.new()

var kind := ""
var health := 1
var broken := false
var dead := false                   # mirrors broken for scanners that skip e.get("dead")
var radius := 0.4
var mesh: Mesh
var multimesh: MultiMesh
var instance := -1
var instance_transform := Transform3D()
var visual: Node3D                  # region props: the node to hide
var _shape: CollisionShape3D
var hidden_transform := false      # true while the MultiMesh instance is zero-scaled
var _away := 0.0
var _broke_hours := 0.0


static func is_breakable(k: String) -> bool:
	return KINDS.has(k)


## Settlement clutter: collider for MultiMesh instance `index`, placed at `t`
## (the instance transform, in the MultiMesh's space, which is also this body's
## parent space). `t` is passed in rather than read back: the headless / dummy
## renderer doesn't keep MultiMesh transforms.
func setup_instance(mm: MultiMesh, index: int, t: Transform3D, prop_mesh: Mesh, prop_kind: String) -> void:
	multimesh = mm
	instance = index
	instance_transform = t
	_setup(prop_mesh, prop_kind, instance_transform)


## Region props: collider over `node`, whose visual bounds (node space) are `box`.
## Add the body to `node` afterwards.
func setup_node(node: Node3D, box: AABB, prop_kind: String) -> void:
	visual = node
	var mi := _first_mesh(node)
	_setup(mi.mesh if mi else null, prop_kind, Transform3D.IDENTITY, box)


func _setup(prop_mesh: Mesh, prop_kind: String, t: Transform3D, box := AABB()) -> void:
	mesh = prop_mesh
	kind = prop_kind
	name = "Breakable_" + prop_kind.get_file()
	health = int(KINDS.get(prop_kind, [1])[0])
	if box.size == Vector3.ZERO and mesh:
		box = mesh.get_aabb()
	var sc := t.basis.get_scale()
	_shape = CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(maxf(box.size.x * sc.x * 0.9, 0.1), maxf(box.size.y * sc.y, 0.1), maxf(box.size.z * sc.z * 0.9, 0.1))
	_shape.shape = b
	add_child(_shape)
	transform = Transform3D(t.basis.orthonormalized(), t * box.get_center())
	radius = maxf(b.size.x, b.size.z) * 0.5
	add_to_group("breakable")


func _enter_tree() -> void:
	if not _all.has(self):
		_all.append(self)


func _exit_tree() -> void:
	_all.erase(self)
	_broken.erase(self)


## Duck-typed like Wolf.take_damage / Critter.take_damage.
func take_damage(amount: int, from: Node = null, knockback := Vector3.ZERO) -> void:
	if broken or amount <= 0:
		return
	health -= amount
	var hit := global_position - (knockback.normalized() * radius if knockback != Vector3.ZERO else Vector3.ZERO)
	if health <= 0 or knockback.length() >= STRONG_IMPACT:
		shatter(hit, maxf(knockback.length(), 3.0), from)
	else:
		_wobble()
		_sfx("hit_wood", -3.0)
		_dust(global_position, 5)


## Breaks the prop now: hides it, disables the collider, throws shards away from
## `hit` (world), puffs dust, cracks, and drops loot if `from` is the player.
## Returns the number of shards spawned.
func shatter(hit: Vector3, force := 3.0, from: Node = null) -> int:
	if broken:
		return 0
	broken = true
	dead = true
	health = 0
	_shape.set_deferred("disabled", true)
	_hide()
	_broke_hours = _now_hours()
	_away = 0.0
	if not _broken.has(self):
		_broken.append(self)
	var n := _spawn_shards(hit, force)
	var wood: bool = KINDS.get(kind, [0, "", true])[2]
	_sfx("hit_wood" if wood else "hit", 0.0)
	if wood:
		_sfx("chop_wood", -5.0)
	_dust(global_position, 14)
	if from and from.is_in_group("player"):
		give_loot(roll_loot(kind, _rng))
	return n


## Puts the prop back (intact, full health, solid).
func restore() -> void:
	if not broken:
		return
	broken = false
	dead = false
	health = int(KINDS.get(kind, [1])[0])
	_shape.set_deferred("disabled", false)
	if multimesh and instance >= 0 and instance < multimesh.instance_count:
		multimesh.set_instance_transform(instance, instance_transform)
		hidden_transform = false
	if visual and is_instance_valid(visual):
		visual.visible = true
	_broken.erase(self)


func _hide() -> void:
	if multimesh and instance >= 0 and instance < multimesh.instance_count:
		multimesh.set_instance_transform(instance, Transform3D(Basis.from_scale(Vector3.ZERO), instance_transform.origin))
		hidden_transform = true
	if visual and is_instance_valid(visual):
		visual.visible = false


## World transform of the prop mesh's own space.
func _mesh_to_world() -> Transform3D:
	if visual and is_instance_valid(visual):
		var mi := _first_mesh(visual)
		return mi.global_transform if mi else visual.global_transform
	var p := get_parent() as Node3D
	var base := p.global_transform if p and p.is_inside_tree() else Transform3D.IDENTITY
	return base * instance_transform


## Knock the intact instance about for 0.15 s on a hit that doesn't break it.
func _wobble() -> void:
	if not is_inside_tree():
		return
	var axis := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
	if axis == Vector3.ZERO:
		axis = Vector3.RIGHT
	var rock := func(v: float) -> void:
		if broken:
			return
		var w := sin(v * PI) * 0.12
		if multimesh and instance >= 0:
			multimesh.set_instance_transform(instance, Transform3D(Basis(axis, w) * instance_transform.basis, instance_transform.origin))
		elif visual and is_instance_valid(visual):
			visual.rotation.x = w * axis.x
			visual.rotation.z = w * axis.z
	create_tween().tween_method(rock, 0.0, 1.0, 0.15)


# --- shards -----------------------------------------------------------------

func _spawn_shards(hit: Vector3, force: float) -> int:
	var parent := get_parent()
	if parent == null or not is_inside_tree():
		return 0
	var chunks: Array = chunks_for(mesh) if mesh else []
	var world := _mesh_to_world()
	var sc := world.basis.get_scale()
	var rot := Basis(world.basis.orthonormalized())
	var pieces: Array = chunks.slice(0, MAX_PER_BREAK)
	# Top up with splinters: at least MIN_SHARDS, two extra when there's room.
	var extra := clampi(pieces.size() + 2, MIN_SHARDS, MAX_PER_BREAK) - pieces.size()
	var spl := _splinter_for(mesh)
	var box := mesh.get_aabb() if mesh else AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 0.8, 0.6))
	for i in extra:
		var at := box.position + Vector3(_rng.randf(), _rng.randf(), _rng.randf()) * box.size
		pieces.append([spl[0], at, spl[1].size])
	var count := 0
	for piece: Array in pieces:
		var body := RigidBody3D.new()
		body.collision_layer = 0
		body.collision_mask = SHARD_MASK
		var size: Vector3 = piece[2] * sc
		body.mass = clampf(size.x * size.y * size.z * 400.0, 0.2, 4.0)
		var mi := MeshInstance3D.new()
		mi.mesh = piece[0]
		mi.scale = sc
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var shp := BoxShape3D.new()
		shp.size = (size * 0.8).max(Vector3.ONE * 0.04)
		cs.shape = shp
		body.add_child(cs)
		var centre: Vector3 = world * (piece[1] as Vector3)
		var spin := Basis.IDENTITY if piece[0] is ArrayMesh else Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, 0.0))
		_track_shard(body)
		parent.add_child(body)
		body.global_transform = Transform3D(rot * spin, centre)
		var away := centre - hit
		away.y = maxf(away.y, 0.0)
		var dir := (away.normalized() + Vector3.UP * 0.7 + Vector3(_rng.randf_range(-0.3, 0.3), 0.0, _rng.randf_range(-0.3, 0.3))).normalized()
		# Velocities rather than impulses: a body's mass isn't applied until it's
		# synced to the physics server, so impulses right after add_child scale wrong.
		body.linear_velocity = dir * force * _rng.randf_range(0.8, 1.3)
		body.angular_velocity = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 6.0
		var tw := body.create_tween()
		tw.tween_interval(SHARD_LIFE)
		tw.tween_callback(func() -> void: body.freeze = true)
		tw.tween_property(mi, "scale", Vector3.ZERO, SHARD_SHRINK)
		tw.tween_callback(body.queue_free)
		count += 1
	return count


## Registers a new shard, freeing the oldest ones beyond MAX_SHARDS.
static func _track_shard(body: Node) -> void:
	_shards = _shards.filter(func(s: Variant) -> bool: return is_instance_valid(s) and not (s as Node).is_queued_for_deletion())
	while _shards.size() >= MAX_SHARDS:
		var old: Node = _shards.pop_front()
		if old.is_inside_tree():
			old.get_parent().remove_child(old)
		old.queue_free()
	_shards.append(body)
	body.tree_exiting.connect(func() -> void: _shards.erase(body))


static func live_shard_count() -> int:
	_shards = _shards.filter(func(s: Variant) -> bool: return is_instance_valid(s) and not (s as Node).is_queued_for_deletion())
	return _shards.size()


## Frees every live shard (tests, scene changes).
static func clear_shards() -> void:
	for s in _shards:
		if is_instance_valid(s):
			(s as Node).queue_free()
	_shards.clear()


## The prop mesh cut into up to 8 pieces: each triangle goes to the 2 x 2 x 2
## AABB cell holding its centroid. Each piece is re-centred on its own bounds so
## it tumbles about its middle. Returns [[ArrayMesh, centre, size], ...].
static func chunks_for(src: Mesh) -> Array:
	if src == null:
		return []
	if _chunk_cache.has(src):
		return _chunk_cache[src]
	var box := src.get_aabb()
	var inv := Vector3(2.0 / maxf(box.size.x, 0.0001), 2.0 / maxf(box.size.y, 0.0001), 2.0 / maxf(box.size.z, 0.0001))
	# Pass 1: each triangle's cell, per surface. (Packed arrays are values, so
	# pass 2 builds each cell's arrays in locals instead of inside containers.)
	var surfs: Array = []       # [surface index, arrays, PackedInt32Array tri corners, PackedByteArray tri cells]
	for s in src.get_surface_count():
		if src is ArrayMesh and (src as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var a := src.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(v.size() - v.size() % 3)
			for i in idx.size():
				idx[i] = i
		var tri_cell := PackedByteArray()
		tri_cell.resize(idx.size() / 3)
		for t in tri_cell.size():
			var cen := (v[idx[t * 3]] + v[idx[t * 3 + 1]] + v[idx[t * 3 + 2]]) / 3.0
			var g := (cen - box.position) * inv
			tri_cell[t] = clampi(int(g.x), 0, 1) + clampi(int(g.y), 0, 1) * 2 + clampi(int(g.z), 0, 1) * 4
		surfs.append([s, a, idx, tri_cell])
	var out: Array = []
	for cell in 8:
		var am := ArrayMesh.new()
		var lo := Vector3.INF
		var hi := -Vector3.INF
		var parts: Array = []    # [surface index, verts, normals, uvs]
		for sf: Array in surfs:
			var a: Array = sf[1]
			var idx: PackedInt32Array = sf[2]
			var tri_cell: PackedByteArray = sf[3]
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var nr: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var has_n := nr.size() == v.size()
			var has_uv := uv.size() == v.size()
			var pv := PackedVector3Array()
			var pn := PackedVector3Array()
			var pu := PackedVector2Array()
			for t in tri_cell.size():
				if tri_cell[t] != cell:
					continue
				for k in 3:
					var i := idx[t * 3 + k]
					pv.append(v[i])
					lo = lo.min(v[i])
					hi = hi.max(v[i])
					if has_n:
						pn.append(nr[i])
					if has_uv:
						pu.append(uv[i])
			if not pv.is_empty():
				parts.append([sf[0], pv, pn, pu])
		if parts.is_empty():
			continue
		var centre := (lo + hi) * 0.5
		for part: Array in parts:
			var pv: PackedVector3Array = part[1]
			for i in pv.size():
				pv[i] -= centre
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = pv
			if (part[2] as PackedVector3Array).size() == pv.size():
				arrays[Mesh.ARRAY_NORMAL] = part[2]
			if (part[3] as PackedVector2Array).size() == pv.size():
				arrays[Mesh.ARRAY_TEX_UV] = part[3]
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			am.surface_set_material(am.get_surface_count() - 1, src.surface_get_material(int(part[0])))
		out.append([am, centre, (hi - lo).max(Vector3.ONE * 0.02)])
	_chunk_cache[src] = out
	return out


## A thin plank splinter in the prop's first material, sized to the prop.
static func _splinter_for(src: Mesh) -> Array:
	if _splinter_cache.has(src):
		return _splinter_cache[src]
	var ext := 0.6
	var mat: Material = null
	if src:
		ext = maxf(src.get_aabb().size.x, maxf(src.get_aabb().size.y, src.get_aabb().size.z))
		mat = src.surface_get_material(0) if src.get_surface_count() > 0 else null
	if mat == null:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.45, 0.32, 0.2)
		sm.roughness = 0.9
		mat = sm
	var bm := BoxMesh.new()
	bm.size = Vector3(ext * 0.07, ext * 0.05, ext * 0.35).max(Vector3.ONE * 0.02)
	bm.material = mat
	var shp := BoxShape3D.new()
	shp.size = bm.size
	_splinter_cache[src] = [bm, shp]
	return _splinter_cache[src]


static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		return n as MeshInstance3D
	for ch in n.get_children():
		var m := _first_mesh(ch)
		if m:
			return m
	return null


# --- loot ---------------------------------------------------------------------

## Pure roll: item -> amount (empty when nothing drops or the kind has no loot).
static func roll_loot(prop_kind: String, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	var table_name: String = KINDS.get(prop_kind, [0, ""])[1]
	if table_name == "" or not LOOT.has(table_name):
		return out
	for entry: Array in LOOT[table_name]:
		if rng.randf() < float(entry[1]):
			out[entry[0]] = rng.randi_range(int(entry[2]), int(entry[3]))
	return out


## Hands a roll to the player: gold via Game.add_gold, items via Life.give.
static func give_loot(loot: Dictionary) -> void:
	if loot.is_empty():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var game = tree.root.get_node_or_null("/root/Game")
	var life = tree.root.get_node_or_null("/root/Life")
	var parts: PackedStringArray = []
	for item: String in loot:
		var n: int = loot[item]
		if item == "gold":
			if game:
				game.add_gold(n)
				parts.append("%d gold" % n)
		elif life:
			life.give(item, n)
			parts.append("%s ×%d" % [String(life.item_name(item)), n] if n > 1 else String(life.item_name(item)))
	if game and game.has_method("say") and not parts.is_empty():
		game.say("Found " + ", ".join(parts) + ".")


# --- driver -------------------------------------------------------------------

## Called every frame by SettlementBuilder and RegionDressing (runs once per
## frame whoever calls): watches the player's swings and regrows broken props.
static func tick(delta: float) -> void:
	var frame := Engine.get_process_frames()
	if frame == _tick_frame:
		return
	_tick_frame = frame
	if _all.is_empty():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var player := tree.get_first_node_in_group("player") as Node3D
	if player == null:
		return
	_watch_swing(tree, player)
	_regen_timer -= delta
	if _regen_timer <= 0.0 and not _broken.is_empty():
		_regen_timer = 1.0
		_regen(player.global_position, 1.0)


## A new swing (player._swing_id changed): if a breakable is in range, sweep at
## the swing's hit frame, the same moment player.gd resolves its own hit.
static func _watch_swing(tree: SceneTree, player: Node3D) -> void:
	var sid: Variant = player.get("_swing_id")
	if not sid is int or int(sid) == _seen_swing:
		return
	_seen_swing = int(sid)
	var swing: Variant = player.get("_swing")
	if not swing is float or float(swing) <= 0.0:
		return
	var near := false
	for b in _all:
		if not b.broken and (b as Node3D).global_position.distance_squared_to(player.global_position) < 36.0:
			near = true
			break
	if not near:
		return
	var hit_at: Variant = player.get("_swing_hit")
	var elapsed: Variant = player.get("_swing_elapsed")
	var wait := 0.0
	if hit_at is float and elapsed is float:
		wait = maxf(float(hit_at) - float(elapsed), 0.0)
	tree.create_timer(wait).timeout.connect(_sweep.bind(weakref(player), int(sid)))


static func _sweep(player_ref: WeakRef, sid: int) -> void:
	var player = player_ref.get_ref()
	if player == null or not (player is Node3D) or not player.is_inside_tree() or player.get("dead"):
		return
	if player.get("_swing_id") != sid:
		return   # cancelled (dodge) before its hit frame
	var fwd: Vector3 = player.facing() if player.has_method("facing") else -(player as Node3D).global_basis.z
	if player.get("view") == 0 and player.has_method("forward"):
		fwd = player.forward()     # View.FIRST
	var damage := 14
	var knock := 1.5
	var combo: Variant = player.get("_combo")
	var table: Variant = player.get_script().get_script_constant_map().get("COMBO") if player.get_script() else null
	if combo is int and table is Array and int(combo) < (table as Array).size():
		var step: Dictionary = table[combo]
		damage = int(step.get("damage", 14))
		knock = float(step.get("knockback", 1.5))
	var hits := 0
	for b in _all.duplicate():
		if b.broken:
			continue
		var to: Vector3 = (b as Node3D).global_position - player.global_position
		to.y = 0.0
		var d := to.length()
		if d < MELEE_REACH + float(b.radius) * 0.5 and (d < 0.01 or fwd.dot(to / d) > MELEE_DOT):
			b.take_damage(damage, player, (to / maxf(d, 0.01)) * knock)
			hits += 1
	if hits > 0 and player.has_method("_hit_stop"):
		player.call("_hit_stop", 0.04)


## Regrow props the player has walked away from, or that broke a day ago.
static func _regen(at: Vector3, dt: float) -> void:
	var now := _now_hours()
	for b in _broken.duplicate():
		if not is_instance_valid(b):
			_broken.erase(b)
			continue
		var d := (b as Node3D).global_position.distance_to(at)
		if d > REGEN_DIST:
			b._away += dt
		else:
			b._away = 0.0
		if b._away >= REGEN_AWAY_SECONDS or (now - float(b._broke_hours) >= 24.0 and d > REGEN_DAY_MIN_DIST):
			b.restore()


static func _now_hours() -> float:
	var tree := Engine.get_main_loop() as SceneTree
	var ws = tree.root.get_node_or_null("/root/WorldSim") if tree else null
	if ws == null:
		return 0.0
	return float(ws.day) * 24.0 + float(ws.time_of_day)


# --- feedback -----------------------------------------------------------------

func _sfx(sound: String, db: float) -> void:
	var audio = get_node_or_null("/root/Audio")
	if audio and is_inside_tree():
		audio.play_sfx(sound, global_position, db, 0.1)


## Soft brown dust puff (CPU particles: no GPU particle shader to compile on
## first break; same unshaded alpha billboard material setup as chimney smoke).
func _dust(at: Vector3, amount: int) -> void:
	var parent := get_parent()
	if parent == null or not is_inside_tree():
		return
	if _dust_mesh == null:
		_dust_mesh = QuadMesh.new()
		_dust_mesh.size = Vector2(0.7, 0.7)
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var r := Vector2(x - 15.5, y - 15.5).length() / 16.0
				img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - r, 0.0, 1.0), 1.6)))
		m.albedo_texture = ImageTexture.create_from_image(img)
		_dust_mesh.material = m
		_dust_ramp = Gradient.new()
		_dust_ramp.set_color(0, Color(0.62, 0.53, 0.42, 0.55))
		_dust_ramp.set_color(1, Color(0.7, 0.64, 0.56, 0.0))
		_dust_curve = Curve.new()
		_dust_curve.add_point(Vector2(0, 0.5))
		_dust_curve.add_point(Vector2(1, 1.8))
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 0.9
	p.mesh = _dust_mesh
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = maxf(radius, 0.2)
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, 0.3, 0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.scale_amount_curve = _dust_curve
	p.color_ramp = _dust_ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.get_tree().create_timer(1.4).timeout.connect(p.queue_free)
