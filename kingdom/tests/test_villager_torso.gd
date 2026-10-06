extends GdUnitTestSuite
## No adult villager look may render without a top (a Thistledown villager rolled "villager_green_vest": a vest cut so wide
## that the chest and shoulders are bare skin). Headless: reads the mesh and albedo data of every file of every adult look
## (LOD0 and the LOD1 variants LOW uses), no rendering.
##   * MakeHuman atlas models: torso vertices must not sit in the atlas' skin tile (top-left quadrant).
##   * G6 / CDmir part models: a torso garment part ("armor" / "Body" / "OldLady") must exist and not be skin coloured.
##   * Meshy batch 3: skin-like share of the upper-chest triangles must stay under MAX_BARE_CHEST.

const MAX_BARE_CHEST := 0.30       # calibrated: green_vest 0.39-0.40, white_shirt 0.15-0.20 (open collar and neck), the rest < 0.05
const MAX_ATLAS_SKIN := 0.30       # share of lower-chest vertices in the atlas skin tile (necklines on sparse LOD1 meshes: up to 0.21; bare = 0.9)
const CHILD_LOOKS := ["Child_Boy", "Child_Girl", "Player"]


static func _adult_files() -> Array[String]:
	var files: Array[String] = []
	for look: String in Assets.MH_LOOKS:
		if CHILD_LOOKS.has(look):
			continue
		for f: String in Assets.MH_LOOKS[look]:
			if not files.has(f):
				files.append(f)
	return files


static func _skin_like(c: Color) -> bool:
	return c.h > 0.02 and c.h < 0.1 and c.s > 0.2 and c.s < 0.65 and c.v > 0.5


static func _path(f: String, lod: String) -> String:
	return (f if f.contains("/") else Assets.MH_DIR + f) + lod + ".glb"


static func _image(m: BaseMaterial3D) -> Image:
	if m == null or m.albedo_texture == null:
		return null
	var img := m.albedo_texture.get_image()
	if img != null and img.is_compressed():
		img.decompress()
	return img


## Skin-like share (by triangle area) of the Meshy-3 upper chest, between 0.84 and 0.90 of 1.75 m and within 25 cm of the spine.
static func bare_chest_share(path: String) -> float:
	var base: Node3D = (load(path) as PackedScene).instantiate()
	var total := 0.0
	var skin := 0.0
	for mi: MeshInstance3D in base.find_children("*", "MeshInstance3D", true, false):
		var img := _image(mi.mesh.surface_get_material(0) as BaseMaterial3D)
		if img == null:
			continue
		var arr := mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for k in range(0, idx.size(), 3):
			var a := v[idx[k]]
			var b := v[idx[k + 1]]
			var c := v[idx[k + 2]]
			var cen := (a + b + c) / 3.0
			var y := cen.y / 1.75
			if y < 0.84 or y >= 0.90 or absf(cen.x) > 0.25:
				continue
			var area := (b - a).cross(c - a).length()
			var u := (uv[idx[k]] + uv[idx[k + 1]] + uv[idx[k + 2]]) / 3.0
			var px := img.get_pixel(clampi(int(u.x * img.get_width()), 0, img.get_width() - 1), clampi(int(u.y * img.get_height()), 0, img.get_height() - 1))
			total += area
			if _skin_like(px):
				skin += area
	base.free()
	return skin / maxf(total, 0.0001)


## Share of lower-chest vertices (0.60-0.70 of the height, within 15 cm of the spine) whose UV lies in the atlas' skin tile.
static func atlas_skin_share(path: String) -> float:
	var base: Node3D = (load(path) as PackedScene).instantiate()
	var mi: MeshInstance3D = base.find_children("*", "MeshInstance3D", true, false)[0]
	var arr := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var top := mi.mesh.get_aabb().end.y
	var n := 0
	var s := 0
	for i in v.size():
		var y := v[i].y / top
		if y >= 0.60 and y < 0.70 and absf(v[i].x) < 0.15:
			n += 1
			if uv[i].x < 0.5 and uv[i].y < 0.5:
				s += 1
	base.free()
	return float(s) / maxf(float(n), 1.0)


## "" when the part model has a non-skin torso garment, else the reason.
static func part_model_problem(path: String) -> String:
	var base: Node3D = (load(path) as PackedScene).instantiate()
	var torso: MeshInstance3D = null
	var skin_img: Image = null
	for mi: MeshInstance3D in base.find_children("*", "MeshInstance3D", true, false):
		var n := String(mi.name)
		if n.contains("armor") or n == "Body" or n == "OldLady":
			torso = mi
		elif n.to_lower().contains("head"):
			skin_img = _image(mi.mesh.surface_get_material(0) as BaseMaterial3D)
	var problem := ""
	if torso == null:
		problem = "no torso part"
	else:
		var m := torso.mesh.surface_get_material(0) as BaseMaterial3D
		var img := _image(m)
		if img == null:
			problem = "torso part has no texture"
		else:
			var a := Vector3.ZERO
			var arr := torso.mesh.surface_get_arrays(0)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var n := 0
			var s := 0
			for i in v.size():
				var y := v[i].y / 1.75
				if y > 0.55 and y < 0.72 and absf(v[i].x) < 0.14:
					n += 1
					var px := img.get_pixel(clampi(int(uv[i].x * img.get_width()), 0, img.get_width() - 1), clampi(int(uv[i].y * img.get_height()), 0, img.get_height() - 1)) * m.albedo_color
					if px.get_luminance() > 0.62 and _skin_like(px):
						s += 1
			if n == 0:
				problem = "torso part has no chest vertices"
			elif float(s) / float(n) > 0.5:
				problem = "torso part is skin coloured (%d of %d)" % [s, n]
	base.free()
	return problem


func test_every_adult_look_has_a_torso_garment_at_every_lod() -> void:
	var checked := 0
	for f: String in _adult_files():
		for lod: String in ["", "_lod1"]:
			var path := _path(f, lod)
			if not ResourceLoader.exists(path):
				continue
			checked += 1
			if f.contains("meshy_dl3"):
				var share := bare_chest_share(path)
				assert_float(share).override_failure_message("%s: %.2f of the upper chest is bare skin" % [path, share]).is_less(MAX_BARE_CHEST)
			elif f.contains("g6-ual") or f.contains("cdmir-ual"):
				assert_str(part_model_problem(path)).override_failure_message(path).is_empty()
			elif f.begins_with("res://assets/incoming/ai3d"):
				pass                         # armoured guards and mercenaries: plate and mail, checked by the armour tests
			else:
				var share := atlas_skin_share(path)
				assert_float(share).override_failure_message("%s: %.2f of the chest is in the skin tile" % [path, share]).is_less(MAX_ATLAS_SKIN)
	assert_int(checked).is_greater(40)


func test_the_bare_chested_vest_stays_out_of_every_adult_pool() -> void:
	for look: String in Assets.MH_LOOKS:
		for f: String in Assets.MH_LOOKS[look]:
			assert_bool(f.contains("villager_green_vest")).override_failure_message("%s still lists the bare-chested vest" % look).is_false()


func test_the_chest_metric_still_flags_the_vest() -> void:
	# The metric must be able to see the defect it guards against: the vest model is over the limit at both LODs.
	for lod: String in ["", "_lod1"]:
		var path := Assets.MESHY3 + "villager_green_vest" + lod + ".glb"
		assert_float(bare_chest_share(path)).is_greater(MAX_BARE_CHEST)


func test_look_pools_are_non_empty_and_exist() -> void:
	for look: String in Assets.MH_LOOKS:
		assert_int((Assets.MH_LOOKS[look] as Array).size()).override_failure_message(look).is_greater(0)
		for f: String in Assets.MH_LOOKS[look]:
			assert_bool(ResourceLoader.exists(_path(f, ""))).override_failure_message(_path(f, "")).is_true()
