class_name RealInstancer
extends RefCounted
## W6.4: trees, bushes, undergrowth and rocks of the real-world terrain as Terrain3D instancer meshes (GPU MultiMesh per region, streamed
## and freed with the Terrain3D regions, LOD ranges per mesh asset). Filled procedurally per region on the bridge's worker thread from the
## same rules the old scatter used (WorldGen.forest_density x WorldBiomes biome mix, WorldBiomes item tables), plus a tree line under the
## snow and a slope limit. ProtonScatter / ScatterChunk stay for hand-placed set pieces near towns; the old per-chunk tree/undergrowth/rock
## scatter is off in the real world (WorldBiomes.max_height) so nothing doubles.
## Density tiers: Quality "scatter" (0.3 LOW/iGPU .. 1.0) scales the candidate keep chance; LOD0 range shrinks on LOW.

const NATURE := "res://assets/generated/region/nature/"
const R := "region/nature/"
## role -> [candidate spacing m, base keep]
const ROLES := {"tree": [8.0, 1.0], "undergrowth": [6.0, 0.35], "rock": [14.0, 0.5]}

static var _ids: Dictionary = {}       # kind ("region/nature/oak_a") -> mesh id
static var _names: Array[String] = []


## Every region/nature kind the biome tables use, in a fixed order (mesh ids are their index).
static func kinds() -> Array[String]:
	if _names.is_empty():
		var seen := {}
		for role: String in ROLES:
			var by_biome: Dictionary = WorldBiomes.TABLE.get(role, {})
			for b: int in by_biome:
				var e: Dictionary = by_biome[b]
				for band: String in ["low", "high"]:
					for it: Array in e.get(band, []):
						var k := String(it[0])
						if k.begins_with(R) and not seen.has(k) and ResourceLoader.exists(NATURE + k.substr(R.length()) + ".glb"):
							seen[k] = true
		var ks: Array = seen.keys()
		ks.sort()
		for k: String in ks:
			_ids[k] = _names.size()
			_names.append(k)
	return _names


static func mesh_assets(low_tier: bool) -> Array:
	var out: Array = []
	for k in kinds():
		var a := Terrain3DMeshAsset.new()
		a.name = k.substr(R.length())
		a.id = int(_ids[k])
		var tree := not (a.name.begins_with("bush") or a.name.begins_with("fern") or a.name.begins_with("rock") or a.name.begins_with("stump")
			or a.name.begins_with("log") or a.name.begins_with("grass") or a.name.begins_with("flowers") or a.name.begins_with("boulder"))
		var lods := _lod_scene(a.name)
		if REALISTIC.has(a.name) and ResourceLoader.exists(SLICE_TREES + String(REALISTIC[a.name]) + ".gltf"):
			lods = _lod_scene_from(SLICE_TREES + String(REALISTIC[a.name]) + ".gltf")   # benchmark gate: no lollipop trees
		a.scene_file = lods[0]
		var n: int = lods[1]
		var k_low := 0.6 if low_tier else 1.0
		# LOD ranges (m): trees full mesh close, the generated _lod1/_lod2 simplifications out to the far forest; small plants short.
		var ranges: Array = [110.0, 450.0, 2400.0] if tree else [60.0, 160.0, 260.0]
		for li in n:
			var ri := 2 if li == n - 1 else li       # the last LOD always reaches the far range
			a.set("lod%d_range" % li, float(ranges[ri]) * k_low)
		a.last_shadow_lod = 0
		a.fade_margin = 30.0
		a.cast_shadows = 1 if tree else 0
		out.append(a)
	return out


## [PackedScene with LOD0..LODn MeshInstance3D children (from <name>.glb, <name>_lod1.glb, <name>_lod2.glb), LOD count]: the layout
## Terrain3DMeshAsset reads its LODs from (children in order).
## Broadleaf region kinds -> the Blender-generated realistic trees (tools/blender_trees/make_trees.py, LOD0/LOD1/LOD2 children).
const SLICE_TREES := "res://assets/generated/slice_trees/"
const REALISTIC := {"oak_a": "oak_0", "oak_b": "oak_1", "dark_oak": "oak_1", "beech_a": "beech_0", "beech_b": "beech_1", "young_oak": "ash_0"}


static func _lod_scene_from(path: String) -> Array:
	var inst := (load(path) as PackedScene).instantiate()
	var root := Node3D.new()
	var n := 0
	for k in ["LOD0", "LOD1", "LOD2"]:
		for mi: MeshInstance3D in inst.find_children(k + "*", "MeshInstance3D", true, false):
			var c := MeshInstance3D.new()
			c.name = "LOD%d" % n
			c.mesh = mi.mesh
			root.add_child(c)
			c.owner = root
			n += 1
			break
	inst.free()
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	return [ps, maxi(n, 1)]


static func _lod_scene(name: String) -> Array:
	var root := Node3D.new()
	root.name = name
	var n := 0
	for suffix: String in ["", "_lod1", "_lod2"]:
		var path := NATURE + name + suffix + ".glb"
		if not ResourceLoader.exists(path):
			continue
		var inst := (load(path) as PackedScene).instantiate()
		var mis := inst.find_children("*", "MeshInstance3D", true, false)
		if not mis.is_empty():
			var mi := MeshInstance3D.new()
			mi.name = "LOD%d" % n
			mi.mesh = (mis[0] as MeshInstance3D).mesh
			root.add_child(mi)
			mi.owner = root
			n += 1
		inst.free()
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	return [ps, maxi(n, 1)]


## {mesh id: Array[Transform3D]} for the region with world origin `o` and edge `size`. Thread-safe (pure WorldGen / WorldBiomes reads).
static func plan(o: Vector2, size: float, density_mul: float) -> Dictionary:
	kinds()
	var out := {}
	for role: String in ROLES:
		var step: float = ROLES[role][0]
		var keep: float = float(ROLES[role][1]) * density_mul
		var n := int(size / step)
		for j in n:
			for i in n:
				# Full-cell jitter (the 0.15..0.85 jitter read as an orchard grid from the air)
				var x := o.x + (i + WorldBiomes.pick_u(o.x + i * step, o.y + j * step, 7 + role.length())) * step
				var z := o.y + (j + WorldBiomes.pick_u(z_seed(i, j), o.x + i * step, 3 + role.length())) * step
				if preload("res://scripts/world/real_slice.gd").in_corridor(x, z):
					continue          # the slice route is authored (scripts/world/real_slice.gd)
				var biome := WorldBiomes.at(x, z)
				if biome < 0:
					continue
				var p := 0.0
				if role == "rock":
					p = keep * WorldBiomes.keep_mult("rock", biome) * 0.15
				else:
					var f := WorldGen.forest_density(x, z)
					if role == "tree":
						p = WorldBiomes.tree_density(biome, f)
					else:
						p = keep * (0.25 + f) * WorldBiomes.keep_mult(role, biome)
					p *= density_mul if role == "tree" else 1.0
				if p <= 0.0 or WorldBiomes.pick_u(x, z, 11) > p:
					continue
				var h := WorldGen.height(x, z)
				var sl := Terrain3DBridge.snow_line(z)
				if role != "rock" and h > sl - 120.0 - 60.0 * WorldBiomes.pick_u(x, z, 5):
					continue          # tree line under the snow
				var dx := WorldGen.height(x + 2.0, z) - WorldGen.height(x - 2.0, z)
				var dz := WorldGen.height(x, z + 2.0) - WorldGen.height(x, z - 2.0)
				var slope := sqrt(dx * dx + dz * dz) / 4.0
				if slope > (1.4 if role == "rock" else 0.75):
					continue
				if WorldGen.is_water(x, z) or WorldGen.road_distance(x, z) < 6.0:
					continue
				var kind := WorldBiomes.pick(role, biome, h, WorldBiomes.pick_u(x, z, 17))
				if not _ids.has(kind):
					continue
				var s := lerpf(0.8, 1.3, WorldBiomes.pick_u(x, z, 23))
				if REALISTIC.has(kind.substr(R.length())):
					s *= 0.72          # the generated broadleaves are 14-17 m at scale 1
				var yaw := TAU * WorldBiomes.pick_u(x, z, 29)
				var t := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(x, h - 0.15, z))
				var id: int = _ids[kind]
				if not out.has(id):
					out[id] = []
				(out[id] as Array).append(t)
	return out


static func z_seed(i: int, j: int) -> float:
	return float(i * 131 + j * 977)
