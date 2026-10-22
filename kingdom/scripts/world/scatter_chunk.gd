class_name ScatterChunk
extends Node3D
## The ProtonScatter-driven forest of one 64 m terrain chunk (terrain_backend = terrain3d). One ProtonScatter node per role
## (trees, woodland undergrowth, meadow plants, rocks), each with a box shape over the chunk and the modifier stack
##   Create Inside (Random) -> ScatterWorldModifier (WorldGen height, forest_density, ScatterExclusion, yaw/scale/sink).
## ProtonScatter decides WHERE and WHICH kind (item proportions); once a node finishes, its transforms are handed to the same
## MultiMesh chains the legacy forest uses (TerrainStreamer.region_tree_chain: LOD0 -> LOD1 -> impostor card, per-extent visibility
## ranges, Quality thinning), so LOD and streaming are unchanged: this node lives and dies with its TerrainStreamer chunk.

const REGION := "region/nature/"
const MARKER := "res://assets/terrain3d/scatter_marker.tres"
const CHUNK := 64.0

## role -> {amount (candidate points), keep (keep chance), items [[kind, proportion]], scale [min, max]}. TUNE on the GPU.
const ROLES := {
	"tree": {"amount": 90, "keep": 1.0, "scale": [0.8, 1.25], "items": [
		[REGION + "oak_a", 22], [REGION + "oak_b", 20], [REGION + "beech_a", 18], [REGION + "spruce_a", 14],
		[REGION + "pine_scots", 14], [REGION + "young_oak", 8], [REGION + "dead_snag", 4]]},
	"undergrowth": {"amount": 70, "keep": 0.3, "scale": [0.8, 1.25], "items": [
		[REGION + "fern_a", 14], [REGION + "fern_b", 14], [REGION + "bush_round", 8], [REGION + "bush_hazel", 10],
		[REGION + "stump_mossy", 3], [REGION + "stump_broken", 3], [REGION + "log_mossy", 3], ["Mushroom_Common", 3]]},
	"meadow": {"amount": 120, "keep": 0.35, "scale": [0.8, 1.25], "items": [
		[REGION + "flowers_warm", 10], [REGION + "flowers_cool", 8], [REGION + "bush_berry", 5], [REGION + "bush_hazel", 4],
		[REGION + "bush_round", 4], [REGION + "grass_tall", 14], [REGION + "fern_b", 4]]},
	"rock": {"amount": 40, "keep": 0.12, "scale": [0.6, 1.4], "items": [
		[REGION + "rock_medium", 2], [REGION + "rock_cluster", 1], [REGION + "rock_slab", 1], [REGION + "boulder_large", 1]]},
}
const SALT := {"tree": 0x5eed, "undergrowth": 0x0a11, "meadow": 0x0be5, "rock": 0x0c0c}
## Kinds that only matter close to the camera (same list as TerrainStreamer.FLOOR_NEAR's prefixes).
const NEAR_ONLY := [REGION + "fern", REGION + "grass_", REGION + "flowers", "Mushroom"]

signal finished                     ## every role has produced its MultiMeshes

var key := Vector2i.ZERO
var roles_done := 0
## kind -> total instance count produced (tests/diagnostics).
var counts: Dictionary = {}
## kind -> Array[Transform3D] (kept for tests; cleared with the node)
var placed: Dictionary = {}
var _scatters: Array[ProtonScatter] = []
var _rules: Dictionary = {}          # role -> ScatterWorldModifier
var _finished_roles: Dictionary = {}


## Adds the scatter nodes for chunk `chunk_key` under `chunk` (call from the main thread).
static func attach(chunk: Node3D, chunk_key: Vector2i) -> ScatterChunk:
	var sc := ScatterChunk.new()
	sc.name = "ScatterChunk"
	sc.key = chunk_key
	chunk.add_child(sc)
	return sc


func _ready() -> void:
	var origin := Vector2(key.x * CHUNK, key.y * CHUNK)
	for role: String in ROLES:
		_scatters.append(_make_scatter(role, origin))
	set_process(true)


## ProtonScatter emits build_completed only when it placed something; a role whose every point was rejected (a chunk inside a town)
## is detected from the modifier's own counters.
func _process(_delta: float) -> void:
	for role: String in _rules:
		if _finished_roles.has(role):
			continue
		var rules: ScatterWorldModifier = _rules[role]
		if rules.runs > 0 and rules.last_kept == 0:
			_role_done(role)


func _make_scatter(role: String, origin: Vector2) -> ProtonScatter:
	var spec: Dictionary = ROLES[role]
	var s := ProtonScatter.new()
	s.name = "Scatter_" + role
	s.global_seed = hash(key) ^ int(SALT[role])
	s.enable_updates_in_game = false
	s.use_chunks = false
	# Run the modifier stack on the main thread: the threaded path touches the scene tree/RenderingDevice off-thread (signal 11 when rendering).
	s.dbg_disable_thread = true
	s.force_rebuild_on_load = false   # we drive the stack ourselves (_start): ProtonScatter's own output stage builds throw-away MultiMeshes
	s.show_output_in_tree = false
	var items: Array = spec["items"]
	for i in items.size():
		var it := ProtonScatterItem.new()
		it.name = "i%d" % i
		it.source = 1
		it.path = MARKER
		it.proportion = int(items[i][1])
		it.set_meta("kind", String(items[i][0]))
		s.add_child(it)
	var shape := ProtonScatterShape.new()
	shape.name = "Shape"
	var box := ProtonScatterBoxShape.new()
	box.size = Vector3(CHUNK, 2.0, CHUNK)
	shape.shape = box
	shape.position = Vector3(origin.x + CHUNK * 0.5, 0.0, origin.y + CHUNK * 0.5)
	s.add_child(shape)
	var create := preload("res://addons/proton_scatter/src/modifiers/create_inside_random.gd").new()
	create.amount = int(spec["amount"])
	var rules := ScatterWorldModifier.new()
	rules.role = role
	rules.keep_chance = float(spec["keep"])
	rules.scale_min = float((spec["scale"] as Array)[0])
	rules.scale_max = float((spec["scale"] as Array)[1])
	rules.salt = int(SALT[role]) * 31
	_rules[role] = rules
	var stack := ProtonScatterModifierStack.new()
	stack.add(create)
	stack.add(rules)
	s.modifier_stack = stack
	add_child(s)
	_start.call_deferred(s, role)
	return s


## Runs the modifier stack on the main thread and takes the transforms directly (no ProtonScatter MultiMesh/collision output,
## which hit RenderingDevice buffers and the scene tree and crashed the renderer).
func _start(s: ProtonScatter, role: String) -> void:
	if not is_instance_valid(s) or not s.is_inside_tree():
		return
	var stack := s.modifier_stack
	if stack.transforms_ready.is_connected(s._on_transforms_ready):
		stack.transforms_ready.disconnect(s._on_transforms_ready)
	s._discover_items()
	s.domain.discover_shapes(s)
	stack.transforms_ready.connect(_on_built.bind(s, role), CONNECT_ONE_SHOT)
	stack.start_update(s, s.domain)


func _on_built(tl, s: ProtonScatter, role: String) -> void:
	# ProtonScatter hands transform i of the final list to the item whose proportion block it falls in (same rule as its own
	# _update_multimeshes); read the list itself, not the MultiMesh (a headless/dummy renderer does not keep instance data).
	var by_kind: Dictionary = {}
	var all: Array = tl.list if tl else []
	if WorldBiomes.active():
		_split_by_biome(role, all, s, by_kind)
	else:
		var offset := 0
		for item in s.items:
			var count := int(round(float(item.proportion) / s.total_item_proportion * all.size()))
			var kind: String = item.get_meta("kind")
			var list: Array[Transform3D] = by_kind.get(kind, [] as Array[Transform3D])
			for i in count:
				if offset + i >= all.size():
					break
				list.append(item.process_transform(all[offset + i]))
			by_kind[kind] = list
			offset += count
	var holder: Node3D = get_parent() if get_parent() else self
	for kind: String in by_kind:
		var list: Array[Transform3D] = by_kind[kind]
		if list.is_empty():
			continue
		counts[kind] = int(counts.get(kind, 0)) + list.size()
		var bucket: Array = placed.get_or_add(kind, [])
		bucket.append_array(list)
		_render(holder, kind, list)
	_role_done(role)


## Valencious macro on: the kind of every point comes from the biome under it (WorldBiomes tables, by ground height) instead of from its
## index in the list. Biomes without a table for the role fall back to the legacy proportions of the role. Deterministic per point.
func _split_by_biome(role: String, all: Array, s: ProtonScatter, by_kind: Dictionary) -> void:
	var legacy: Array = ROLES[role]["items"]
	var legacy_total := 0
	for it: Array in legacy:
		legacy_total += int(it[1])
	var salt := int(SALT[role])
	for t: Transform3D in all:
		var x := t.origin.x
		var z := t.origin.z
		var biome := WorldBiomes.at(x, z)
		var u := WorldBiomes.pick_u(x, z, salt)
		var kind := WorldBiomes.pick(role, biome, WorldGen.height(x, z), u)
		if kind == "":
			var r := u * float(legacy_total)
			kind = String((legacy[legacy.size() - 1] as Array)[0])
			for it: Array in legacy:
				r -= float(it[1])
				if r < 0.0:
					kind = String(it[0])
					break
		(by_kind.get_or_add(kind, [] as Array[Transform3D]) as Array[Transform3D]).append(t)


func _role_done(role: String) -> void:
	if _finished_roles.has(role):
		return
	_finished_roles[role] = true
	roles_done += 1
	if roles_done >= ROLES.size():
		set_process(false)
		finished.emit()


static func _render(parent: Node3D, kind: String, list: Array[Transform3D]) -> void:
	# Same rule as the legacy forest: kinds with an impostor file (_lod2) get the full LOD0 -> LOD1 -> card chain, the rest one mesh.
	if kind.begins_with(REGION) and ResourceLoader.exists("res://assets/generated/" + kind + "_lod2.glb"):
		TerrainStreamer.region_tree_chain(parent, kind, list)
		return
	var mmi := TerrainStreamer._multimesh(parent, Assets.nature_mesh(kind), list)
	if mmi:
		for near: String in NEAR_ONLY:
			if kind.begins_with(near):
				mmi.visibility_range_end = 55.0
				break
