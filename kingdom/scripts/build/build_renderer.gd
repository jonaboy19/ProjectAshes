extends Node3D
## Draws the build-kit settlements (scripts/realm/build_kit.gd) cheaply: per settlement ONE MultiMeshInstance3D per
## (piece kind x LOD x look), so a 2,200-piece town is a few dozen draw calls (docs/design/RETINUE_SETTLEMENT_ASCENSION.md 4.10).
## Finished pieces use the kit materials; plans waiting for a crew draw as translucent blueprints; pieces a crew is raising
## appear bottom-up with the site's progress. One StaticBody3D per settlement carries a box per structural piece.
## Roads are terrain-hugging ribbons (scripts/build/road_tool.gd), one mesh per road tier.

const BuildKit := preload("res://scripts/realm/build_kit.gd")
const KitMeshes := preload("res://scripts/build/kit_meshes.gd")
const RoadTool := preload("res://scripts/build/road_tool.gd")
const LOD1_FROM := 45.0
const LOD1_FROM_HIGH := 70.0
const FAR_END := 400.0
const POLL := 0.5
## Settlement roots sit at the grid origin: pieces reach this far from it.
const GRID_PAD := 64.0
const COLLIDE_LAYERS := ["foundation", "wall", "floor", "stairs", "pillar", "fence"]
const TINTED := ["laundry_line", "meshy_banner_stand_iron_frame", "meshy_stall_potatoes", "meshy_stall_open_roof", "meshy_shed_striped_awning", "hay_cart", "meshy_hay_bale_round", "meshy_hay_bale_rect_a", "barrel_cluster", "storage_crates"]

var kit: RefCounted                      # the build_kit module
var low_tier := false
var with_collision := true
## In the game the kit follows the terrain (WorldGen.height); labs keep their own flat ground.
var use_world_height := true
var _roots: Dictionary = {}              # gid -> Node3D
var _seen_rev := -1
var _t := 0.0
var _progress_sig := ""
## Stats of the last rebuild (lab / bench): {multimeshes, pieces, roads}
var stats := {}


func _ready() -> void:
	if kit == null and Life.get("realm") != null:
		kit = Life.realm.mod("build_kit")
	if kit != null and use_world_height and not WorldGen.settlements.is_empty():
		kit.height_fn = func(x: float, z: float) -> float: return WorldGen.height(x, z)


func _process(delta: float) -> void:
	_cull()
	_t -= delta
	if _t > 0.0 or kit == null:
		return
	_t = POLL
	var sig := _plan_signature()
	if int(kit.get("rev")) != _seen_rev or sig != _progress_sig:
		rebuild_all()


## Cheap fingerprint of every crew site's progress, so pieces appear as the crew works.
func _plan_signature() -> String:
	var parts: PackedStringArray = []
	for gid: int in kit.grids:
		for sk: String in kit.grids[gid]["plans"]:
			var ids: Array = kit.grids[gid]["plans"][sk]
			if not ids.is_empty():
				parts.append("%s:%d" % [sk, int(kit.plan_progress(gid, int(ids[0])) * 20.0)])
	return ",".join(parts)


func rebuild_all() -> void:
	_seen_rev = int(kit.get("rev"))
	_progress_sig = _plan_signature()
	for gid: int in _roots.keys():
		if not kit.grids.has(gid):
			(_roots[gid] as Node).queue_free()
			_roots.erase(gid)
	stats = {"multimeshes": 0, "pieces": 0, "roads": 0}
	for gid: int in kit.grids:
		rebuild(gid)


func rebuild(gid: int) -> void:
	if _roots.has(gid):
		var old: Node = _roots[gid]
		remove_child(old)
		old.free()
	var root := Node3D.new()
	root.name = "Settlement%d" % gid
	root.position = kit.to_world(gid, Vector3.ZERO)
	add_child(root)
	_roots[gid] = root
	var groups := {}        # "kind|look" -> Array[Transform3D]
	var body: StaticBody3D = null
	if with_collision:
		body = StaticBody3D.new()
		body.name = "Collision"
		root.add_child(body)
	var pieces: Dictionary = kit.grids[gid]["pieces"]
	for pid: int in pieces:
		var r: Dictionary = pieces[pid]
		var look := "done"
		if String(r["state"]) == "plan":
			look = "done" if kit.plan_piece_built(gid, pid) else "plan"
		var key := "%s|%s" % [r["kind"], look]
		if not groups.has(key):
			groups[key] = []
		var xf := piece_transform(r)
		(groups[key] as Array).append(xf)
		if body != null and look == "done":
			_add_collider(body, String(r["kind"]), xf)
	var lod1_from := LOD1_FROM if low_tier else LOD1_FROM_HIGH
	for key: String in groups:
		var kind := key.get_slice("|", 0)
		var look := key.get_slice("|", 1)
		var xfs: Array = groups[key]
		stats["pieces"] = int(stats.get("pieces", 0)) + xfs.size()
		if look == "plan":
			_mmi(root, KitMeshes.mesh(kind, 1), xfs, 0.0, FAR_END * 0.5, KitMeshes.ghost_material("blueprint"))
		else:
			var has_lod1 := kind.begins_with("meshy_") and ResourceLoader.exists(BuildKit.mesh_path(kind, 1))
			_mmi(root, KitMeshes.mesh(kind, 0), xfs, 0.0, lod1_from if has_lod1 else FAR_END, null, hash(kind) & 0xffff if kind in TINTED else -1)
			if has_lod1:
				_mmi(root, KitMeshes.mesh(kind, 1), xfs, lod1_from, FAR_END, null)
	_skirts(root, gid)
	_roads(root, gid)


static func piece_transform(r: Dictionary) -> Transform3D:
	var p: Array = r["p"]
	var deg := float(r["rot"]) * (90.0 if String(r["slot"]) != "free" else 1.0)
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(deg)), Vector3(float(p[0]), float(p[1]), float(p[2])))
	# Deeper storybook eaves: roof slopes stretch 18 % past the eave (about ridge z = -1), the eave hangs out ~0.35 m more.
	if String(BuildKit.def(String(r["kind"])).get("layer", "")) == "roof":
		xf = xf * Transform3D(Basis.IDENTITY.scaled(Vector3(1, 1, 1.18)), Vector3(0, 0, 0.18))
	return xf


func _mmi(root: Node3D, mesh: Mesh, xfs: Array, near: float, far: float, override: Material, tint_seed := -1) -> void:
	if mesh == null or xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = tint_seed >= 0
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	# Distance-cull fix: give the MultiMesh an explicit AABB (its lazily computed one put every piece out of range in the lab).
	var box := AABB()
	var mb := mesh.get_aabb()
	for i in xfs.size():
		var wb: AABB = (xfs[i] as Transform3D) * mb
		box = wb if i == 0 else box.merge(wb)
	mm.custom_aabb = box
	if tint_seed >= 0:
		# cloth, banners, laundry, hay: each copy gets its own dye / sun-fade so rows never look stamped
		var rng := RandomNumberGenerator.new()
		rng.seed = tint_seed
		for i in xfs.size():
			var h := rng.randf()
			mm.set_instance_color(i, Color.from_hsv(h, 0.25, 1.0).lerp(Color.WHITE, 0.45) * rng.randf_range(0.85, 1.05))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.custom_aabb = mm.custom_aabb
	# Node visibility ranges culled whole kit MultiMeshes at 35 m in the lab (even with explicit AABBs), so LOD and distance
	# culling are done per settlement in _cull() instead: near/far are kept as metadata.
	mi.set_meta("near", near)
	mi.set_meta("far", far)
	if override != null:
		mi.material_override = override
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	stats["multimeshes"] = int(stats.get("multimeshes", 0)) + 1


func _add_collider(body: StaticBody3D, kind: String, xf: Transform3D) -> void:
	var d := BuildKit.def(kind)
	var layer := String(d.get("layer", ""))
	if not layer in COLLIDE_LAYERS:
		return
	var fp: Array = d.get("fp", [1, 1])
	var boxes: Array = []        # [size, centre]
	match layer:
		"foundation":
			boxes.append([Vector3(2.0 * int(fp[0]), 1.0, 2.0 * int(fp[1])), Vector3(int(fp[0]) - 1, 0.0, int(fp[1]) - 1) * 0.0])
		"floor":
			boxes.append([Vector3(2, 0.15, 2), Vector3(0, -0.075, 0)])
		"wall", "fence":
			var w := 2.0 * int(fp[0])
			var h := 3.0 if layer == "wall" and not bool(d.get("low", false)) else 1.2
			if bool(d.get("doorway", false)) or kind.contains("gate"):
				var side := (w - 1.2) * 0.5
				boxes.append([Vector3(side, h, 0.3), Vector3(-w * 0.5 + side * 0.5, h * 0.5, 0)])
				boxes.append([Vector3(side, h, 0.3), Vector3(w * 0.5 - side * 0.5, h * 0.5, 0)])
				boxes.append([Vector3(1.2, 0.6, 0.3), Vector3(0, h - 0.3, 0)])
			else:
				boxes.append([Vector3(w, h, 0.3), Vector3(0, h * 0.5, 0)])
		"pillar":
			boxes.append([Vector3(0.3, 3.0, 0.3), Vector3(0, 1.5, 0)])
		"stairs":
			var ramp := CollisionShape3D.new()
			var cp := ConvexPolygonShape3D.new()
			cp.points = PackedVector3Array([Vector3(-1, 0, 2), Vector3(1, 0, 2), Vector3(-1, 0, -2), Vector3(1, 0, -2), Vector3(-1, 3, -2), Vector3(1, 3, -2)])
			ramp.shape = cp
			ramp.transform = xf
			body.add_child(ramp)
	for b: Array in boxes:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b[0]
		cs.shape = bs
		cs.transform = xf * Transform3D(Basis.IDENTITY, b[1])
		body.add_child(cs)


func _roads(root: Node3D, gid: int) -> void:
	var by_tier := {}
	for road: Dictionary in kit.grids[gid]["roads"]:
		var pts: Array = []
		for a: Array in road["pts"]:
			pts.append(Vector3(float(a[0]), float(a[1]), float(a[2])))
		var tier := String(road["tier"])
		if not by_tier.has(tier):
			by_tier[tier] = []
		(by_tier[tier] as Array).append(pts)
	var origin: Vector3 = kit.to_world(gid, Vector3.ZERO)
	for tier: String in by_tier:
		var rd := BuildKit.road_def(tier)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for pts: Array in by_tier[tier]:
			var m := RoadTool.ribbon(pts, float(rd.get("width", 3.0)), kit.height_fn, origin)
			st.append_from(m, 0, Transform3D.IDENTITY)
		var mesh := st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var mat := KitMeshes.kit_material("kit_cobble" if String(rd.get("mat", "")) == "cobble" else "kit_dirt")
		mesh.surface_set_material(0, road_material(mat))
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = FAR_END
		root.add_child(mi)
		stats["roads"] = int(stats.get("roads", 0)) + 1


static var _road_mats := {}


static func road_material(m: Material) -> Material:
	if _road_mats.has(m):
		return _road_mats[m]
	var out: Material = m
	if m is BaseMaterial3D:
		out = m.duplicate()
		(out as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	elif m is ShaderMaterial:
		out = load("res://scripts/style_g.gd").double_sided(m as ShaderMaterial)
	_road_mats[m] = out
	return out


## Mud and cobble skirt round every foundation footprint: a soft disc (vertex alpha fades into the grass) per cell, one MultiMesh.
func _skirts(root: Node3D, gid: int) -> void:
	var xfs: Array = []
	for pid: int in kit.grids[gid]["pieces"]:
		var r: Dictionary = kit.grids[gid]["pieces"][pid]
		if String(BuildKit.def(String(r["kind"])).get("layer", "")) == "foundation":
			var p: Array = r["p"]
			var g := float(kit.height_fn.call(float(p[0]) + root.position.x, float(p[2]) + root.position.z)) - root.position.y
			xfs.append(Transform3D(Basis(Vector3.UP, float(pid) * 1.7), Vector3(float(p[0]), g + 0.03, float(p[2]))))
	if xfs.is_empty():
		return
	_mmi(root, skirt_mesh(), xfs, 0.0, FAR_END * 0.5, null)


static var _skirt: ArrayMesh


static func skirt_mesh() -> ArrayMesh:
	if _skirt != null:
		return _skirt
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 14
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var r0 := 2.6 + sin(i * 2.3) * 0.35
		var r1 := 2.6 + sin((i + 1) * 2.3) * 0.35
		for v: Array in [[Vector3.ZERO, 1.0], [Vector3(cos(a1) * r1, 0, sin(a1) * r1), 0.0], [Vector3(cos(a0) * r0, 0, sin(a0) * r0), 0.0]]:
			st.set_color(Color(1, 1, 1, v[1]))
			st.set_uv(Vector2((v[0] as Vector3).x, (v[0] as Vector3).z) * 0.35)
			st.set_normal(Vector3.UP)
			st.add_vertex(v[0])
	_skirt = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://scripts/style_g.gd").ph("brown_mud_02", "diff", "1k")
	m.albedo_color = Color("b8a080")
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_skirt.surface_set_material(0, m)
	return _skirt


## Per-settlement LOD + distance cull (cheap: a few dozen nodes per settlement, run every frame).
func _cull() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	for gid: int in _roots:
		var root: Node3D = _roots[gid]
		var d := cam.global_position.distance_to(root.global_position)
		root.visible = d < FAR_END + GRID_PAD
		if not root.visible:
			continue
		for mi in root.get_children():
			if mi is GeometryInstance3D and mi.has_meta("far"):
				var lo := float(mi.get_meta("near"))
				var hi := float(mi.get_meta("far"))
				(mi as GeometryInstance3D).visible = d >= lo and d < hi
