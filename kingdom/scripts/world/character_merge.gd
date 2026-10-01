extends RefCounted
const StyleG := preload("res://scripts/style_g.gd")

## Draw-call cut for modular characters (G6 villagers, CDmir monk, two-surface MakeHuman guards): the 2-6 skinned
## parts (hair, head, hands, armour, boots...) become ONE skinned surface with ONE material (a small texture atlas
## built from the parts' own albedo textures, shelf packed). The skeleton is untouched, so every clip and blend
## works as before; the bone indices of each part are remapped onto one merged Skin. Cached per outfit file and
## tier, so the atlas is built once per outfit combo. Town clothing tints (TownIdentity.tint_model) keep working:
## they duplicate the (cached) merged StandardMaterial3D with albedo_color x tint, one per colour.
## NOT used for the hero (HeroOutfit/CharacterCreation call Assets.mh_character without merge, their look is owned
## by the local PC session) nor for the baked VAT crowd.
##
## merge() returns false and leaves the parts alone whenever a part is not mergeable (transparency, emission,
## normal map, 8-bone weights, a non-identity part transform, no UVs...).

static var _cache: Dictionary = {}          # "<key>|<tier>" -> {mesh, skin, mat} or false (not mergeable)
static var stats := {"built": 0, "reused": 0, "skipped": 0, "parts_removed": 0}


static func merge(skeleton: Skeleton3D, key: String) -> bool:
	var parts: Array[MeshInstance3D] = []
	var surfaces := 0
	var tier0: String = StyleG.current_tier()
	for c in skeleton.get_children():
		var mi := c as MeshInstance3D
		if mi != null and mi.mesh != null:
			if tier0 != "high":
				mi.mesh = _prune_emblems(mi.mesh)
			parts.append(mi)
			surfaces += mi.mesh.get_surface_count()
	if parts.is_empty() or surfaces <= 1:
		return false
	var tier: String = StyleG.current_tier()
	var ck := "%s|%s" % [key, tier]
	var entry: Variant = _cache.get(ck)
	if entry == null:
		entry = _build(parts, skeleton, tier)
		_cache[ck] = entry
		if entry is Dictionary:
			stats["built"] += 1
		else:
			stats["skipped"] += 1
	elif entry is Dictionary:
		stats["reused"] += 1
	if not (entry is Dictionary):
		return false
	var first := parts[0]
	first.mesh = entry["mesh"]
	first.skin = entry["skin"]
	first.name = "merged"
	for i in range(1, parts.size()):
		skeleton.remove_child(parts[i])
		parts[i].free()
		stats["parts_removed"] += 1
	return true


static func _build(parts: Array[MeshInstance3D], skeleton: Skeleton3D, tier: String) -> Variant:
	var items: Array = []            # {arrays, mat, tex_key, skin, aabb}
	var aabb := AABB()
	var first_aabb := true
	for mi in parts:
		if not mi.transform.is_equal_approx(Transform3D.IDENTITY) or mi.skin == null:
			return false
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null or mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or mat.emission_enabled \
					or mat.normal_enabled or mat.metallic_texture != null or mat.roughness_texture != null \
					or mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				return false
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			if verts.is_empty() or bones.size() != verts.size() * 4 or uv.size() != verts.size() or arrays[Mesh.ARRAY_INDEX] == null:
				return false
			var tex := mat.albedo_texture
			var tk := "col" + mat.albedo_color.to_html()
			if tex != null:
				tk = (tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id())) + "|" + mat.albedo_color.to_html()
			items.append({"arrays": arrays, "mat": mat, "tex": tex, "tk": tk, "skin": mi.skin})
		var pa := mi.mesh.get_aabb()
		aabb = pa if first_aabb else aabb.merge(pa)
		first_aabb = false
	# --- unified skin (bind poses by bone name; a clash means the parts do not share one rig) ---
	var skin := Skin.new()
	var name_to_idx := {}
	var remaps: Array = []
	for it in items:
		var ps: Skin = it["skin"]
		var remap := PackedInt32Array()
		for j in ps.get_bind_count():
			var bn := String(ps.get_bind_name(j))
			if bn == "":
				bn = skeleton.get_bone_name(ps.get_bind_bone(j))
			var pose := ps.get_bind_pose(j)
			if not name_to_idx.has(bn):
				name_to_idx[bn] = skin.get_bind_count()
				skin.add_named_bind(bn, pose)
			elif not skin.get_bind_pose(name_to_idx[bn]).is_equal_approx(pose):
				return false
			remap.append(name_to_idx[bn])
		remaps.append(remap)
	# --- atlas ---
	var cap := 1024 if tier == "high" else 512
	var tiles := {}                                   # tk -> {img, rect}
	for it in items:
		if tiles.has(it["tk"]):
			continue
		var img: Image = null
		var tex: Texture2D = it["tex"]
		if tex != null:
			img = tex.get_image()
		if img == null or img.is_empty():
			img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
			img.fill(Color.WHITE)
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var side := maxi(img.get_width(), img.get_height())
		if side > cap:
			var k := float(cap) / float(side)
			img.resize(maxi(int(img.get_width() * k), 4), maxi(int(img.get_height() * k), 4), Image.INTERPOLATE_LANCZOS)
		var col: Color = (it["mat"] as BaseMaterial3D).albedo_color
		if not col.is_equal_approx(Color.WHITE):
			for y in img.get_height():
				for x in img.get_width():
					img.set_pixel(x, y, img.get_pixel(x, y) * col)
		tiles[it["tk"]] = {"img": img, "rect": Rect2i()}
	var order: Array = tiles.keys()
	order.sort_custom(func(a, b): return tiles[a]["img"].get_height() > tiles[b]["img"].get_height())
	var width := 2048 if tier == "high" else 1024
	var x := 0
	var y := 0
	var row_h := 0
	for k in order:
		var im: Image = tiles[k]["img"]
		if x + im.get_width() > width:
			x = 0
			y += row_h
			row_h = 0
		tiles[k]["rect"] = Rect2i(x, y, im.get_width(), im.get_height())
		x += im.get_width()
		row_h = maxi(row_h, im.get_height())
	var atlas_h := y + row_h
	var atlas := Image.create(width, atlas_h, false, Image.FORMAT_RGBA8)
	for k in order:
		var im2: Image = tiles[k]["img"]
		atlas.blit_rect(im2, Rect2i(0, 0, im2.get_width(), im2.get_height()), (tiles[k]["rect"] as Rect2i).position)
	atlas.convert(Image.FORMAT_RGB8)
	atlas.generate_mipmaps()
	var atlas_tex := ImageTexture.create_from_image(atlas)
	# --- geometry ---
	var o_v := PackedVector3Array()
	var o_n := PackedVector3Array()
	var o_t := PackedFloat32Array()
	var o_c := PackedColorArray()
	var o_uv := PackedVector2Array()
	var o_b := PackedInt32Array()
	var o_w := PackedFloat32Array()
	var o_i := PackedInt32Array()
	var all_tangent := true
	for it in items:
		if it["arrays"][Mesh.ARRAY_TANGENT] == null:
			all_tangent = false
	var biggest := 0
	var biggest_n := -1
	for n in items.size():
		var verts: PackedVector3Array = items[n]["arrays"][Mesh.ARRAY_VERTEX]
		var arrays: Array = items[n]["arrays"]
		var base_v := o_v.size()
		var rect: Rect2i = tiles[items[n]["tk"]]["rect"]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var inset_x := 1.5 / float(rect.size.x)       # 1.5 texel gutter so bilinear never reads the neighbour tile
		var inset_y := 1.5 / float(rect.size.y)
		for u in uv:
			var cx := clampf(u.x, inset_x, 1.0 - inset_x)
			var cy := clampf(u.y, inset_y, 1.0 - inset_y)
			o_uv.append(Vector2((rect.position.x + cx * rect.size.x) / float(width), (rect.position.y + cy * rect.size.y) / float(atlas_h)))
		o_v.append_array(verts)
		o_n.append_array(arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else _fill_up(verts.size()))
		if all_tangent:
			o_t.append_array(arrays[Mesh.ARRAY_TANGENT])
		if arrays[Mesh.ARRAY_COLOR] != null:
			o_c.append_array(arrays[Mesh.ARRAY_COLOR])
		else:
			var white := PackedColorArray()
			white.resize(verts.size())
			white.fill(Color.WHITE)
			o_c.append_array(white)
		var rm: PackedInt32Array = remaps[n]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		for b in bones:
			o_b.append(rm[b])
		o_w.append_array(arrays[Mesh.ARRAY_WEIGHTS])
		for ix in arrays[Mesh.ARRAY_INDEX] as PackedInt32Array:
			o_i.append(ix + base_v)
		if verts.size() > biggest_n:
			biggest_n = verts.size()
			biggest = n
	var out_arrays := []
	out_arrays.resize(Mesh.ARRAY_MAX)
	out_arrays[Mesh.ARRAY_VERTEX] = o_v
	out_arrays[Mesh.ARRAY_NORMAL] = o_n
	if all_tangent:
		out_arrays[Mesh.ARRAY_TANGENT] = o_t
	out_arrays[Mesh.ARRAY_COLOR] = o_c
	out_arrays[Mesh.ARRAY_TEX_UV] = o_uv
	out_arrays[Mesh.ARRAY_BONES] = o_b
	out_arrays[Mesh.ARRAY_WEIGHTS] = o_w
	out_arrays[Mesh.ARRAY_INDEX] = o_i
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_arrays)
	mesh.custom_aabb = aabb
	mesh.resource_name = "merged_char"
	# One material: the biggest part's settings, the atlas as albedo (tints multiply albedo_color later).
	var mat := (items[biggest]["mat"] as BaseMaterial3D).duplicate() as BaseMaterial3D
	mat.albedo_texture = atlas_tex
	mat.albedo_color = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	for it in items:
		if (it["mat"] as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED:
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.resource_name = "merged_char_atlas"
	mesh.surface_set_material(0, mat)
	return {"mesh": mesh, "skin": skin, "mat": mat}


static func _fill_up(n: int) -> PackedVector3Array:
	var a := PackedVector3Array()
	a.resize(n)
	a.fill(Vector3.UP)
	return a


static var _pruned := {}          # original mesh id -> {orig, mesh}


## LOW/MEDIUM: a tiny alpha-blended quad on a body mesh (the guard's tabard crest, 4 vertices) costs a whole extra draw and
## shadow draw per guard. Rebuilds the mesh without it (cached per source mesh); the opaque surfaces are untouched.
static func _prune_emblems(src: Mesh) -> Mesh:
	if src.get_surface_count() < 2:
		return src
	var cached: Variant = _pruned.get(src.get_instance_id())
	if cached != null:
		return cached["mesh"]
	var drop := []
	for i in src.get_surface_count():
		var m := src.surface_get_material(i) as BaseMaterial3D
		if m != null and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and src.surface_get_array_len(i) <= 16:
			drop.append(i)
	var out: Mesh = src
	if not drop.is_empty() and drop.size() < src.get_surface_count():
		var am := ArrayMesh.new()
		for i in src.get_surface_count():
			if drop.has(i):
				continue
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(i))
			am.surface_set_material(am.get_surface_count() - 1, src.surface_get_material(i))
		am.custom_aabb = src.get_aabb()
		out = am
	_pruned[src.get_instance_id()] = {"orig": src, "mesh": out}
	return out
