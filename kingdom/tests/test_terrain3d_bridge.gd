extends GdUnitTestSuite
## terrain_backend = terrain3d: the Terrain3D + ProtonScatter addons load, Terrain3D's ground matches WorldGen.height, ProtonScatter's
## forest respects roads / settlements / build-kit grids / founded settlements, and the legacy backend is untouched (the default).
## Docs: docs/LOCAL_SESSION_HANDOFF.md ("Terrain3D + ProtonScatter backend").

const Hub := preload("res://scripts/realm/realm_hub.gd")
const BuildKit := preload("res://scripts/realm/build_kit.gd")


func before() -> void:
	WorldGen.setup(1066)


func before_test() -> void:
	ScatterExclusion.clear_all()
	TerrainBackend.override = ""


func after_test() -> void:
	ScatterExclusion.clear_all()
	TerrainBackend.override = ""


func _bridge_at(at: Vector3) -> Terrain3DBridge:
	var b := Terrain3DBridge.new()
	b.region_radius = 0                   # just the region under `at`: ~3 s of WorldGen maths on the worker pool
	add_child(b)
	b.build_all_now(at)
	return b


# --- addons ---------------------------------------------------------------------------------------

func test_addons_load_headless() -> void:
	assert_bool(ClassDB.class_exists("Terrain3D")).is_true()
	assert_bool(ClassDB.class_exists("Terrain3DRegion")).is_true()
	assert_bool(ClassDB.class_exists("Terrain3DAssets")).is_true()
	var scatter := ProtonScatter.new()               # a GDScript addon: its class_name is global, ClassDB does not list it
	assert_object(scatter).is_not_null()
	scatter.free()
	assert_bool(TerrainBackend.available()).is_true()
	var cfg := ConfigFile.new()
	assert_int(cfg.load("res://addons/terrain_3d/plugin.cfg")).is_equal(OK)
	assert_str(String(cfg.get_value("plugin", "version"))).is_equal("1.0.2")
	assert_int(cfg.load("res://addons/proton_scatter/plugin.cfg")).is_equal(OK)
	assert_str(String(cfg.get_value("plugin", "version"))).is_equal("4.2.0")


func test_terrain3d_waits_for_the_runtime_camera_before_physics() -> void:
	var bridge := Terrain3DBridge.new()
	bridge.region_radius = 0
	add_child(bridge)
	assert_bool(bridge.terrain.is_physics_processing()).is_false()
	var camera := Camera3D.new()
	camera.current = true
	add_child(camera)
	await get_tree().process_frame
	assert_bool(bridge.terrain.is_physics_processing()).is_true()
	assert_bool(bridge.terrain.get_camera() == camera).is_true()
	camera.queue_free()
	bridge.queue_free()


func test_addon_licences_are_mit_and_credited() -> void:
	for path: String in ["res://addons/terrain_3d/LICENSE.txt", "res://addons/proton_scatter/LICENSE"]:
		var text := FileAccess.get_file_as_string(path)
		assert_bool(text.begins_with("MIT License")).override_failure_message(path).is_true()
	var credits := FileAccess.get_file_as_string("res://CREDITS.md")
	assert_bool(credits.contains("Terrain3D") and credits.contains("ProtonScatter")).is_true()


func test_terrain3d_binaries_cover_linux_windows_macos() -> void:
	var text := FileAccess.get_file_as_string("res://addons/terrain_3d/terrain.gdextension")
	for needle: String in ["linux.release.x86_64", "windows.release.x86_64", "macos.release"]:
		assert_bool(text.contains(needle)).override_failure_message(needle).is_true()
	assert_bool(FileAccess.file_exists("res://addons/terrain_3d/bin/libterrain.linux.release.x86_64.so")).is_true()
	assert_bool(FileAccess.file_exists("res://addons/terrain_3d/bin/libterrain.windows.release.x86_64.dll")).is_true()


# --- the flag -------------------------------------------------------------------------------------

func test_backend_defaults_to_legacy() -> void:
	assert_str(TerrainBackend.mode()).is_equal(TerrainBackend.LEGACY)
	assert_bool(TerrainBackend.is_terrain3d()).is_false()
	TerrainBackend.override = "terrain3d"
	assert_bool(TerrainBackend.is_terrain3d()).is_true()
	TerrainBackend.override = "nonsense"
	assert_str(TerrainBackend.mode()).is_equal(TerrainBackend.LEGACY)


func test_legacy_streamer_has_no_terrain3d_and_keeps_its_ground_meshes() -> void:
	var t := TerrainStreamer.new()
	add_child(t)
	assert_bool(t._t3d).is_false()
	assert_object(t._bridge).is_null()
	t.view_radius = 1
	t.focus = Vector3(0, 0, 0)
	t.build_all_now()
	assert_int(t.loaded_count()).is_equal(9)
	for key: Vector2i in t._chunks:
		var chunk: Node3D = t._chunks[key]
		assert_object(chunk.get_node_or_null("Ground")).is_not_null()
		assert_object(chunk.get_node_or_null("GroundFar")).is_not_null()
		assert_object(chunk.get_node_or_null("ScatterChunk")).is_null()
	assert_object(t.get_node_or_null("Terrain3DBridge")).is_null()
	t.free()


func test_legacy_chunk_plan_is_deterministic_and_complete() -> void:
	var t := TerrainStreamer.new()
	var a := t._plan_chunk(Vector2i(3, -2))
	var b := t._plan_chunk(Vector2i(3, -2))
	assert_int((a["ground"][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(33 * 33)
	assert_int((a["ground"][Mesh.ARRAY_COLOR] as PackedColorArray).size()).is_equal(33 * 33)
	assert_array(a["ground_lod"]).is_not_empty()
	assert_bool(hash(a["faces"]) == hash(b["faces"])).is_true()
	assert_bool(a["forest"].hash() == b["forest"].hash()).is_true()
	# vertices are exactly WorldGen.height (what navigation/building/collision all read)
	var v: PackedVector3Array = a["ground"][Mesh.ARRAY_VERTEX]
	for i in [0, 100, 500, 1088]:
		assert_float(v[i].y).is_equal_approx(WorldGen.height(v[i].x, v[i].z), 0.0001)
	t.free()


# --- height parity --------------------------------------------------------------------------------

func _parity(b: Terrain3DBridge, centre: Vector2, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var o := Terrain3DBridge.region_origin(Terrain3DBridge.region_of(centre.x, centre.y))
	var checked := 0
	var over := 0
	var worst := 0.0
	var worst_lattice := 0.0
	for i in 1500:
		var x := o.x + rng.randf_range(2.0, Terrain3DBridge.REGION_M - 2.0)
		var z := o.y + rng.randf_range(2.0, Terrain3DBridge.REGION_M - 2.0)
		var e := absf(b.sampled_height(x, z) - WorldGen.height(x, z))
		checked += 1
		worst = maxf(worst, e)
		if e > 0.1:
			over += 1
		var lx := o.x + floorf((x - o.x) / Terrain3DBridge.SPACING) * Terrain3DBridge.SPACING
		var lz := o.y + floorf((z - o.y) / Terrain3DBridge.SPACING) * Terrain3DBridge.SPACING
		worst_lattice = maxf(worst_lattice, absf(b.sampled_height(lx, lz) - WorldGen.height(lx, lz)))
	# On the pixel lattice Terrain3D IS WorldGen.height (float32 round trip); between pixels it interpolates, which differs
	# only on the sharpest creases (the 160 m ridged mountains; away from roads/settlements/water): >= 99 % of random points within 0.1 m,
	# none past 0.6 m. Tighter would need sub-metre pixels (4x the memory and bake time).
	assert_float(worst_lattice).is_less(0.001)
	assert_int(checked).is_equal(1500)
	assert_float(float(over) / checked).override_failure_message("%d of %d points off by > 0.1 m (worst %.3f)" % [over, checked, worst]).is_less(0.01)
	assert_float(worst).is_less(0.6)


func test_terrain3d_height_matches_worldgen_in_the_valley() -> void:
	var b := _bridge_at(Vector3(0, 0, 0))
	assert_int(b.region_count()).is_equal(1)
	_parity(b, Vector2.ZERO, 11)
	b.free()


func test_terrain3d_height_matches_worldgen_in_the_outer_world() -> void:
	var far: Vector2 = WorldGen.settlements[WorldGen.settlements.size() - 1]["pos"]
	var b := _bridge_at(Vector3(far.x, 0, far.y))
	assert_bool(b.has_region_at(far.x, far.y)).is_true()
	_parity(b, far, 23)
	b.free()


func test_the_world_edge_fits_the_region_grid() -> void:
	assert_int(Terrain3DBridge.region_of(-WorldGen.WORLD_HALF, -WorldGen.WORLD_HALF).x).is_equal(Terrain3DBridge.FIRST_LOC)
	assert_int(Terrain3DBridge.region_of(WorldGen.WORLD_HALF - 1.0, WorldGen.WORLD_HALF - 1.0).y).is_equal(Terrain3DBridge.LAST_LOC)
	assert_bool(Terrain3DBridge.in_world(Vector2i(16, 0))).is_false()


# --- paint (control map) --------------------------------------------------------------------------

func test_control_words_roundtrip_through_terrain3d_encoding() -> void:
	# pure grass, pure forest, a path/grass blend, a cobble/rock blend
	var cases := [Color(0, 0, 0, 0), Color(0, 0, 0, 1), Color(0.5, 0, 0, 0), Color(0, 0.3, 0.6, 0)]
	for w: Color in cases:
		var word := Terrain3DBridge.control_word(w)
		assert_int(Terrain3DUtil.get_base(word)).is_between(0, 4)
		assert_int(Terrain3DUtil.get_overlay(word)).is_between(0, 4)
		assert_int(Terrain3DUtil.get_blend(word)).is_between(0, 255)
		# our hand-packed bits are exactly what Terrain3D's own encoders produce
		var again := Terrain3DUtil.enc_base(Terrain3DUtil.get_base(word)) | Terrain3DUtil.enc_overlay(Terrain3DUtil.get_overlay(word)) \
			| Terrain3DUtil.enc_blend(Terrain3DUtil.get_blend(word))
		assert_int(again).is_equal(word)
		assert_bool(Terrain3DUtil.is_auto(word)).is_false()
		assert_bool(Terrain3DUtil.is_hole(word)).is_false()
	assert_int(Terrain3DUtil.get_base(Terrain3DBridge.control_word(Color(0, 0, 0, 0)))).is_equal(0)                  # grass
	assert_int(Terrain3DUtil.get_overlay(Terrain3DBridge.control_word(Color(0, 0, 0, 1)))).is_equal(1)               # forest floor
	var path := Terrain3DBridge.control_word(Color(0.8, 0, 0, 0))
	assert_int(Terrain3DUtil.get_overlay(path)).is_equal(2)                                                          # dirt path outweighs the grass left over
	assert_int(Terrain3DUtil.get_blend(path)).is_greater(128)
	assert_int(Terrain3DUtil.get_base(Terrain3DBridge.control_word(Color(0, 0, 1, 0)))).is_equal(4)                  # cobble street


func test_grass_keeps_a_stable_base_across_weight_crossing() -> void:
	# The same Grass/Forest mix should not swap Terrain3D's base and overlay as
	# their relative weights cross; blend direction changes while the ratio stays.
	var grass_heavy := Terrain3DBridge.control_word(Color(0, 0, 0, 0.25))
	var forest_heavy := Terrain3DBridge.control_word(Color(0, 0, 0, 0.75))
	for word: int in [grass_heavy, forest_heavy]:
		assert_int(Terrain3DUtil.get_base(word)).is_equal(0)     # Grass
		assert_int(Terrain3DUtil.get_overlay(word)).is_equal(1)  # Forest floor
	assert_int(Terrain3DUtil.get_blend(grass_heavy)).is_equal(64)
	assert_int(Terrain3DUtil.get_blend(forest_heavy)).is_equal(191)


func test_town_plaza_is_painted_cobble() -> void:
	var b := _bridge_at(Vector3(0, 0, 0))
	var seen_cobble := false
	var p: Vector2 = WorldGen.settlements[0]["pos"]
	for dx in range(-12, 13, 3):
		for dz in range(-12, 13, 3):
			var at := Vector3(p.x + dx, 0, p.y + dz)
			var w := WorldGen.color_at(at.x, at.z, 0.0, 0.0)
			if w.b > 0.9:
				seen_cobble = seen_cobble or b.terrain.data.get_control_base_id(at) == 4 or b.terrain.data.get_control_overlay_id(at) == 4
	assert_bool(seen_cobble).override_failure_message("no cobble pixel near Ashford's centre").is_true()
	b.free()


func test_texture_slots_use_the_existing_ground_sets() -> void:
	var b := _bridge_at(Vector3(0, 0, 0))
	assert_int(b.terrain.assets.get_texture_count()).is_equal(Terrain3DBridge.SLOTS.size())   # 10 since W1d (5 legacy + meadow, farmland, marsh, rift, snow)
	for i in Terrain3DBridge.SLOTS.size():
		var ta: Terrain3DTextureAsset = b.terrain.assets.get_texture(i)
		assert_str(ta.name).is_equal(Terrain3DBridge.SLOTS[i])
		assert_object(ta.albedo_texture).is_not_null()
		assert_object(ta.normal_texture).is_not_null()
	b.free()


# --- exclusion zones ------------------------------------------------------------------------------

func test_exclusion_roads_streets_settlements_and_water() -> void:
	var s: Dictionary = WorldGen.settlements[0]
	var c: Vector2 = s["pos"]
	for kind: String in ["tree", "rock", "plant"]:
		assert_bool(ScatterExclusion.blocked(c.x, c.y, kind)).override_failure_message("settlement centre " + kind).is_true()
	# a road: midpoint of the first road segment is never a tree
	var ra: Vector2 = WorldGen._road_a[0]
	var rb: Vector2 = WorldGen._road_b[0]
	var mid := (ra + rb) * 0.5
	assert_bool(ScatterExclusion.blocked(mid.x, mid.y, "tree")).is_true()
	assert_bool(ScatterExclusion.blocked(mid.x, mid.y, "plant")).is_true()
	# open wild ground far from everything is not blocked
	var found := false
	for i in 400:
		var x := -5800.0 + i * 29.0
		var z := 5200.0 - i * 3.0
		if WorldGen.road_distance(x, z) > 80.0 and not WorldGen.near_water(x, z, 30.0) and WorldGen.street_distance(x, z) == INF \
				and WorldGen.nearest_settlement(Vector2(x, z)).is_empty() == false \
				and Vector2(x, z).distance_to(WorldGen.nearest_settlement(Vector2(x, z))["pos"]) > 600.0:
			found = true
			assert_bool(ScatterExclusion.blocked(x, z, "tree")).is_false()
			break
	assert_bool(found).is_true()


func test_exclusion_dynamic_zones_and_revision() -> void:
	var rev := ScatterExclusion.revision()
	ScatterExclusion.set_zone("t:1", Vector2(5000, 5000), 30.0)
	assert_int(ScatterExclusion.revision()).is_greater(rev)
	assert_bool(ScatterExclusion.blocked(5000.0 + 40.0, 5000.0, "tree")).is_true()      # 30 + 24 m tree margin
	assert_bool(ScatterExclusion.blocked(5000.0 + 80.0, 5000.0, "tree")).is_false()
	assert_bool(ScatterExclusion.blocked(5000.0 + 36.0, 5000.0, "plant")).is_true()     # 30 + 8
	assert_bool(ScatterExclusion.blocked(5000.0 + 45.0, 5000.0, "plant")).is_false()
	var r2 := ScatterExclusion.revision()
	ScatterExclusion.set_zone("t:1", Vector2(5000, 5000), 30.0)       # same again: no churn... (replaced, bumps once)
	ScatterExclusion.clear_zone("t:1")
	assert_int(ScatterExclusion.zone_count()).is_equal(0)
	assert_int(ScatterExclusion.revision()).is_greater(r2)
	assert_bool(ScatterExclusion.blocked(5000.0 + 10.0, 5000.0, "tree")).is_false()


func test_build_kit_grids_and_founded_settlements_register_zones() -> void:
	WorldGen.setup(2024)
	var hub: RefCounted = Hub.new()
	var k: RefCounted = hub.mod("build_kit")
	k.height_fn = func(_x: float, _z: float) -> float: return 0.0
	var r: Dictionary = k.ensure_grid(Vector3(5100, 0, 5100), "Test")
	assert_bool(bool(r["ok"])).is_true()
	assert_int(ScatterExclusion.zone_count()).is_equal(1)
	assert_bool(ScatterExclusion.blocked(5100.0 + BuildKit.GRID_RADIUS - 2.0, 5100.0, "tree")).is_true()
	assert_bool(ScatterExclusion.blocked(5100.0 + BuildKit.GRID_RADIUS + 60.0, 5100.0, "tree")).is_false()
	# a saved game restores the zones
	var saved: Dictionary = k.serialize()
	var saved_grids: Dictionary = saved["grids"]
	var saved_grid: Dictionary = saved_grids[saved_grids.keys()[0]]
	assert_str(String(saved_grid["packed"])).is_empty()
	ScatterExclusion.clear_all()
	k.deserialize(saved)
	assert_int(ScatterExclusion.zone_count()).is_equal(1)
	# founding records: active ones block, ended ones do not
	var f: RefCounted = hub.mod("founding")
	f.deserialize({"f": [{"id": 7, "pos": [-5000.0, -5000.0], "end": -1}, {"id": 8, "pos": [-4000.0, 5000.0], "end": 12}], "next": 9})
	assert_bool(ScatterExclusion.blocked(-5000.0, -5000.0, "tree")).is_true()
	assert_bool(ScatterExclusion.blocked(-4000.0, 5000.0, "tree")).is_false()
	WorldGen.setup(1066)


# --- ProtonScatter forest -------------------------------------------------------------------------

func _forested_chunk() -> Vector2i:
	var best := Vector2i.ZERO
	var best_d := 0.0
	for cz in range(-12, 13):
		for cx in range(-12, 13):
			var key := Vector2i(cx * 3 + 40, cz * 3 - 20)
			var cx_m := key.x * 64.0 + 32.0
			var cz_m := key.y * 64.0 + 32.0
			var d := WorldGen.forest_density(cx_m, cz_m)
			if d > best_d and WorldGen.road_distance(cx_m, cz_m) > 150.0:
				best_d = d
				best = key
	return best


## ProtonScatter frees its helper nodes with queue_free: let that frame pass so gdUnit's orphan check sees a clean scene.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _scatter_chunk(key: Vector2i) -> ScatterChunk:
	var holder := Node3D.new()
	add_child(holder)
	var sc := ScatterChunk.attach(holder, key)
	await sc.finished
	return sc


func test_scatter_forest_places_trees_on_worldgen_ground() -> void:
	var key := _forested_chunk()
	var sc: ScatterChunk = await _scatter_chunk(key)
	var trees := 0
	var any := 0
	for kind: String in sc.placed:
		for t: Transform3D in sc.placed[kind]:
			any += 1
			var h := WorldGen.height(t.origin.x, t.origin.z)
			assert_float(t.origin.y).is_between(h - 0.71, h - 0.14)       # legacy sink: 0.15 + <= 0.55 on slopes
			assert_int(floori(t.origin.x / 64.0)).is_equal(key.x)
			assert_int(floori(t.origin.z / 64.0)).is_equal(key.y)
		if (kind as String).contains("oak") or (kind as String).contains("spruce") or (kind as String).contains("beech") or (kind as String).contains("pine"):
			trees += (sc.placed[kind] as Array).size()
	assert_int(trees).override_failure_message("forested chunk %s produced no trees" % key).is_greater(5)
	assert_int(any).is_greater(trees)
	# the legacy MultiMesh chains exist beside it, so LOD/streaming are the legacy ones
	var chains := 0
	for ch in sc.get_parent().get_children():
		if ch is MultiMeshInstance3D:
			chains += 1
	assert_int(chains).is_greater(0)
	sc.get_parent().free()
	await _settle()


## kind -> count and every transform, in a canonical order (roles finish in thread order, so the dictionary order varies).
func _norm(sc: ScatterChunk) -> String:
	var kinds: Array = sc.placed.keys()
	kinds.sort()
	var out := ""
	for k: String in kinds:
		var origins: Array = []
		for t: Transform3D in sc.placed[k]:
			origins.append("%.3f,%.3f,%.3f" % [t.origin.x, t.origin.y, t.origin.z])
		origins.sort()
		out += k + ":" + ";".join(origins) + "|"
	return out


func test_scatter_forest_is_deterministic() -> void:
	var key := _forested_chunk()
	var a: ScatterChunk = await _scatter_chunk(key)
	var b: ScatterChunk = await _scatter_chunk(key)
	assert_int(a.counts.size()).is_greater(0)
	assert_str(_norm(a)).is_equal(_norm(b))
	a.get_parent().free()
	b.get_parent().free()
	await _settle()


func test_scatter_forest_keeps_clear_of_zones_roads_and_settlements() -> void:
	var key := _forested_chunk()
	var c := Vector2(key.x * 64.0 + 32.0, key.y * 64.0 + 32.0)
	# Without a zone the chunk has trees near its centre ...
	var free: ScatterChunk = await _scatter_chunk(key)
	var near_before := 0
	for kind: String in free.placed:
		for t: Transform3D in free.placed[kind]:
			if Vector2(t.origin.x, t.origin.z).distance_to(c) < 26.0:
				near_before += 1
	assert_int(near_before).is_greater(0)
	free.get_parent().free()
	# ... and none once a build-kit grid / founded settlement claims the middle (radius 20 + margins).
	ScatterExclusion.set_zone("grid:1", c, 20.0)
	var sc: ScatterChunk = await _scatter_chunk(key)
	var total := 0
	for kind: String in sc.placed:
		for t: Transform3D in sc.placed[kind]:
			total += 1
			var d := Vector2(t.origin.x, t.origin.z).distance_to(c)
			var role := "tree" if (kind.contains("oak") or kind.contains("spruce") or kind.contains("beech") or kind.contains("pine") or kind.contains("snag")) \
				else ("rock" if (kind.contains("rock") or kind.contains("boulder")) else "plant")
			assert_bool(ScatterExclusion.blocked(t.origin.x, t.origin.z, role)).override_failure_message("%s placed in an exclusion zone" % kind).is_false()
			assert_float(d).is_greater(20.0 + float(ScatterExclusion.GRID_MARGIN[role]) - 0.01)
	assert_int(total).is_greater(0)
	sc.get_parent().free()
	await _settle()


func test_scatter_world_modifier_rejects_road_and_town_points_directly() -> void:
	var m := ScatterWorldModifier.new()
	m.role = "tree"
	var c: Vector2 = WorldGen.settlements[0]["pos"]
	assert_bool(m.allows(c.x, c.y)).is_false()
	var ra: Vector2 = WorldGen._road_a[0]
	var rb: Vector2 = WorldGen._road_b[0]
	var mid := (ra + rb) * 0.5
	assert_bool(m.allows(mid.x, mid.y)).is_false()
	var list := preload("res://addons/proton_scatter/src/common/transform_list.gd").new()
	for i in 50:
		list.list.append(Transform3D(Basis.IDENTITY, Vector3(c.x + i, 0.0, c.y + i * 0.5)))   # all inside Ashford
	m._process_transforms(list, null, 5)
	assert_int(list.list.size()).is_equal(0)


# --- end to end: the streamer in terrain3d mode ---------------------------------------------------

func test_streamer_in_terrain3d_mode_has_terrain_scatter_and_collision_but_no_legacy_ground() -> void:
	TerrainBackend.override = "terrain3d"
	var t := TerrainStreamer.new()
	add_child(t)
	assert_bool(t._t3d).is_true()
	assert_object(t._bridge).is_not_null()
	t._bridge.region_radius = 0
	t.view_radius = 1
	t.focus = Vector3(300, 0, 300)
	t.build_all_now()
	assert_int(t.loaded_count()).is_equal(9)
	assert_int(t._bridge.region_count()).is_equal(1)
	var any_body := false
	for key: Vector2i in t._chunks:
		var chunk: Node3D = t._chunks[key]
		assert_object(chunk.get_node_or_null("Ground")).is_null()
		assert_object(chunk.get_node_or_null("GroundFar")).is_null()
		assert_object(chunk.get_node_or_null("ScatterChunk")).is_not_null()
		if chunk.get_node_or_null("Body"):
			any_body = true
			# collision faces still follow WorldGen.height exactly
			var faces: PackedVector3Array = chunk.get_meta("faces")
			assert_float(faces[7].y).is_equal_approx(WorldGen.height(faces[7].x, faces[7].z), 0.0001)
	assert_bool(any_body).is_true()
	TerrainBackend.override = ""
	t.free()
