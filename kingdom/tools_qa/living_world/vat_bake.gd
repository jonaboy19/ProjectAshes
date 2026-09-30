extends Node
## VAT baker: turns the game's own skinned villagers (Assets.mh_character, _lod1 models) plus their UAL / life
## clips into VatAsset resources (res://assets/generated/vat/vat_<look>.res) for the far crowd tier.
##
##   Godot --path kingdom res://tools_qa/living_world/vat_bake.tscn -- [--looks=a,b] [--fps=10] [--tris=1100]
## (windowed, not --headless: the albedo atlas is read back from the imported texture)
##
## Per look:
##  1. build the character exactly as the game does, install the life clips (LifeLibrary.install);
##  2. reduce the _lod1 mesh with ImporterMesh.generate_lods (meshoptimizer) to ~target_tris and keep only the
##     vertices the reduced index buffer uses;
##  3. bake albedo into vertex colours: glTF vertex colour x atlas texel at the UV (both linear), alpha = tint mask
##     (0 for vertices driven by the head/neck/hands = skin and hair, 1 for clothing);
##  4. for every clip, sample `fps` rows per second (loops: n rows over exactly the clip length so the last row
##     wraps into the first), CPU-skin the kept vertices with the Skin bind poses (linear blend, same as the GPU)
##     into the model's own space, and write positions (RGBA half) and normals (RGBA8) textures;
##  5. save mesh + textures + clip table in one VatAsset.

const CFG := "res://data/living_world/vat_bake.json"
const OUT_DIR := "res://assets/generated/vat/"
const UNTINTED := ["Head", "neck_01", "hand_", "thumb", "index", "middle", "ring", "pinky"]


func _ready() -> void:
	var args := {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CFG))
	var fps := float(args.get("fps", cfg.get("fps", 10)))
	var tris := int(args.get("tris", cfg.get("target_tris", 1100)))
	var looks: Dictionary = cfg["looks"]
	var only: PackedStringArray = String(args.get("looks", "")).split(",", false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var total_bytes := 0
	for look: String in looks:
		if not only.is_empty() and not only.has(look):
			continue
		var t0 := Time.get_ticks_msec()
		var asset := bake_look(look, cfg["clip_sets"][looks[look]], fps, tris)
		if asset == null:
			continue
		var path := OUT_DIR + "vat_%s.res" % look
		var err := ResourceSaver.save(asset, path, ResourceSaver.FLAG_COMPRESS)
		var bytes := asset.vertex_count * asset.frame_count * 12
		total_bytes += bytes
		print("VAT %s verts=%d tris=%d frames=%d clips=%d tex=%.2f MB save=%s %d ms" % [look, asset.vertex_count,
			asset.mesh.surface_get_array_index_len(0) / 3, asset.frame_count, asset.clips.size(), bytes / 1048576.0,
			error_string(err), Time.get_ticks_msec() - t0])
	print("VAT_DONE total texture %.2f MB" % (total_bytes / 1048576.0))
	get_tree().quit()


func bake_look(look: String, clip_names: Array, fps: float, target_tris: int) -> VatAsset:
	var model := Assets.mh_character(look, 1.75, [], true)
	add_child(model)
	var base := model.get_child(0) as Node3D
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var anim := Assets.animation_player(model)
	LifeLibrary.install(anim)
	var mi: MeshInstance3D = null
	for n in skeleton.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).skin != null:
			mi = n
			break
	if mi == null:
		push_error("VAT %s: no skinned mesh" % look)
		model.queue_free()
		return null
	var mesh := mi.mesh
	var src_arrays := mesh.surface_get_arrays(0)
	var src_tris := (src_arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	# ---- 2. reduce (generate_lods may rebuild the vertex arrays: use the ones it returns)
	var red := _reduce(src_arrays, target_tris, mesh.surface_get_format(0))
	var arrays: Array = red[0]
	var reduced: PackedInt32Array = red[1]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var per := bones.size() / maxi(verts.size(), 1)

	var used := {}
	var order := PackedInt32Array()
	for i in reduced:
		if not used.has(i):
			used[i] = order.size()
			order.append(i)
	var new_idx := PackedInt32Array()
	new_idx.resize(reduced.size())
	for k in reduced.size():
		new_idx[k] = used[reduced[k]]
	var nv := order.size()

	# ---- 3. albedo -> vertex colours, tint mask from the dominant bone
	var skin := mi.skin
	var bind_bone := PackedInt32Array()
	var bind_pose: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bb := skin.get_bind_bone(b)
		if bb < 0:
			bb = skeleton.find_bone(skin.get_bind_name(b))
		bind_bone.append(bb)
		bind_pose.append(skin.get_bind_pose(b))
	var mat := mi.get_active_material(0) as BaseMaterial3D
	var img: Image = null
	var mat_col := Color.WHITE
	if mat:
		mat_col = mat.albedo_color
		if mat.albedo_texture:
			img = mat.albedo_texture.get_image()
			if img == null:
				img = Image.load_from_file(mat.albedo_texture.resource_path)
			if img:
				if img.is_compressed():
					img.decompress()
				img.convert(Image.FORMAT_RGBA8)
	var out_col := PackedColorArray()
	var out_uv2 := PackedVector2Array()
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	for j in nv:
		var i := order[j]
		var c := cols[i] if not cols.is_empty() else Color.WHITE
		if mat and not mat.vertex_color_use_as_albedo:
			c = Color.WHITE
		var tex := Color.WHITE
		if img and not uvs.is_empty():
			var u := uvs[i]
			var px := clampi(int(fposmod(u.x, 1.0) * img.get_width()), 0, img.get_width() - 1)
			var py := clampi(int(fposmod(u.y, 1.0) * img.get_height()), 0, img.get_height() - 1)
			tex = img.get_pixel(px, py).srgb_to_linear()
		var alb := Color(c.r * tex.r * mat_col.r, c.g * tex.g * mat_col.g, c.b * tex.b * mat_col.b)
		var best := 0
		var best_w := -1.0
		for k in per:
			if weights[i * per + k] > best_w:
				best_w = weights[i * per + k]
				best = bones[i * per + k]
		var bname := skeleton.get_bone_name(bind_bone[best]) if bind_bone[best] >= 0 else ""
		var mask := 1.0
		for key: String in UNTINTED:
			if bname.begins_with(key):
				mask = 0.0
		alb.a = mask
		out_col.append(alb)
		out_uv2.append(Vector2(float(j), 0.0))
		out_v.append(verts[i])
		out_n.append(normals[i])

	# ---- 4. frames
	var to_model := base.global_transform.affine_inverse() * skeleton.global_transform
	var clips := {}
	var rows_p := PackedFloat32Array()
	var rows_n := PackedByteArray()
	var row := 0
	for cn: String in clip_names:
		var clip := cn
		if cn.contains("+"):
			var parts := cn.split("+")
			if not (anim.has_animation(parts[0]) and anim.has_animation(parts[1])):
				push_warning("VAT %s: composite %s skipped (missing clip)" % [look, cn])
				continue
			clip = LifeLibrary.composite(anim, parts[0], parts[1])
		if not anim.has_animation(clip):
			push_warning("VAT %s: clip %s not in the rig, skipped" % [look, cn])
			continue
		var a := anim.get_animation(clip)
		var loop := a.loop_mode != Animation.LOOP_NONE
		var length := a.length
		var n := maxi(2, int(round(length * fps))) if loop else maxi(2, int(round(length * fps)) + 1)
		anim.play(clip)
		for f in n:
			var t := (float(f) * length / n) if loop else (float(f) * length / (n - 1))
			anim.seek(t, true)
			var xf: Array[Transform3D] = []
			for b in bind_bone.size():
				xf.append(to_model * skeleton.get_bone_global_pose(maxi(bind_bone[b], 0)) * bind_pose[b])
			for j in nv:
				var i := order[j]
				var p := Vector3.ZERO
				var nn := Vector3.ZERO
				var v := verts[i]
				var vn := normals[i]
				for k in per:
					var w := weights[i * per + k]
					if w <= 0.0:
						continue
					var m: Transform3D = xf[bones[i * per + k]]
					p += (m * v) * w
					nn += (m.basis * vn) * w
				nn = nn.normalized()
				rows_p.append(p.x)
				rows_p.append(p.y)
				rows_p.append(p.z)
				rows_p.append(1.0)
				rows_n.append(clampi(int(round((nn.x * 0.5 + 0.5) * 255.0)), 0, 255))
				rows_n.append(clampi(int(round((nn.y * 0.5 + 0.5) * 255.0)), 0, 255))
				rows_n.append(clampi(int(round((nn.z * 0.5 + 0.5) * 255.0)), 0, 255))
				rows_n.append(255)
		clips[cn] = {"row": row, "frames": n, "loop": loop, "length": length}
		row += n
	anim.stop()

	# ---- 5. textures + mesh
	var pimg := Image.create_from_data(nv, row, false, Image.FORMAT_RGBAF, rows_p.to_byte_array())
	pimg.convert(Image.FORMAT_RGBAH)
	var nimg := Image.create_from_data(nv, row, false, Image.FORMAT_RGBA8, rows_n)
	var am := ArrayMesh.new()
	var ma := []
	ma.resize(Mesh.ARRAY_MAX)
	ma[Mesh.ARRAY_VERTEX] = out_v
	ma[Mesh.ARRAY_NORMAL] = out_n
	ma[Mesh.ARRAY_COLOR] = out_col
	ma[Mesh.ARRAY_TEX_UV2] = out_uv2
	ma[Mesh.ARRAY_INDEX] = new_idx
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ma)
	var asset := VatAsset.new()
	asset.look = look
	asset.mesh = am
	asset.pos_tex = ImageTexture.create_from_image(pimg)
	asset.nrm_tex = ImageTexture.create_from_image(nimg)
	asset.clips = clips
	asset.fps = fps
	asset.vertex_count = nv
	asset.frame_count = row
	var head := skeleton.find_bone("Head")
	asset.height = (to_model * skeleton.get_bone_global_rest(head)).origin.y * 1.1 if head >= 0 else 1.75
	asset.source = "Assets.mh_character(%s, lod1) + LifeLibrary; %d of %d tris" % [look, new_idx.size() / 3, src_tris]
	model.queue_free()
	return asset


## [arrays, index buffer of the generated LOD closest to target_tris] (the input when it is already small).
func _reduce(arrays: Array, target_tris: int, fmt: int) -> Array:
	var full: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if full.size() / 3 <= target_tris:
		return [arrays, full]
	var im := ImporterMesh.new()
	var a := arrays.duplicate()
	for ch in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3, Mesh.ARRAY_TANGENT]:
		a[ch] = null
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, null, "s", fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	var nargs := 3
	for m in ClassDB.class_get_method_list("ImporterMesh"):
		if m["name"] == "generate_lods":
			nargs = (m["args"] as Array).size()
	if nargs >= 3:
		im.call("generate_lods", 60.0, 25.0, [])
	else:
		im.call("generate_lods", 60.0, [])
	var out_arrays := im.get_surface_arrays(0)
	full = out_arrays[Mesh.ARRAY_INDEX]
	var best := full
	var best_d := absi(full.size() / 3 - target_tris)
	for l in im.get_surface_lod_count(0):
		var idx := im.get_surface_lod_indices(0, l)
		var d := absi(idx.size() / 3 - target_tris)
		if d < best_d:
			best_d = d
			best = idx
	return [out_arrays, best]
