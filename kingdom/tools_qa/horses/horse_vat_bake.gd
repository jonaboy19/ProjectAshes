extends Node
## Bakes distant-horse VAT assets (VatAsset, same format and shader as the living-world crowd) from the HorseRig's LOD2
## mesh and the Horse_Anims clips: res://assets/generated/vat/vat_horse_<coat>.res
##   Godot --path kingdom res://tools_qa/horses/horse_vat_bake.tscn [-- --coats=bay,grey --fps=15]
## (windowed: the coat texture is read back from the imported resource)
## Clip keys are the HorseRig player's names ("horse/Walk" ...) plus plain aliases, so CrowdAnimLOD's hand-off keeps
## the exact clip time both ways.

const OUT_DIR := "res://assets/generated/vat/"
const CLIPS := ["Idle", "Walk", "Trot", "Canter_L", "Gallop_L", "Graze", "Cart_Pull_Walk", "Idle_RestHind", "Drink"]


func _ready() -> void:
	var args := {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var coats := String(args.get("coats", "bay,chestnut,grey,black,dappled")).split(",", false)
	var fps := float(args.get("fps", "15"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	await get_tree().process_frame
	var shared_p: ImageTexture = null
	var shared_n: ImageTexture = null
	for coat in coats:
		var t0 := Time.get_ticks_msec()
		var asset := await bake(coat, fps)
		# every coat has the same mesh + clips: the position / normal textures are saved once and shared
		if shared_p == null:
			ResourceSaver.save(asset.pos_tex, OUT_DIR + "vat_horse_pos.res", ResourceSaver.FLAG_COMPRESS)
			ResourceSaver.save(asset.nrm_tex, OUT_DIR + "vat_horse_nrm.res", ResourceSaver.FLAG_COMPRESS)
			shared_p = load(OUT_DIR + "vat_horse_pos.res")
			shared_n = load(OUT_DIR + "vat_horse_nrm.res")
		asset.pos_tex = shared_p
		asset.nrm_tex = shared_n
		var path := OUT_DIR + "vat_horse_%s.res" % coat
		var err := ResourceSaver.save(asset, path, ResourceSaver.FLAG_COMPRESS)
		print("HORSE_VAT %s verts=%d tris=%d rows=%d tex=%.2f MB %s %d ms" % [coat, asset.vertex_count,
			asset.mesh.surface_get_array_index_len(0) / 3, asset.frame_count, asset.vertex_count * asset.frame_count * 12 / 1048576.0,
			error_string(err), Time.get_ticks_msec() - t0])
	print("HORSE_VAT_DONE")
	get_tree().quit()


func bake(coat: String, fps: float) -> VatAsset:
	var horse := HorseRig.new()
	horse.coat = coat
	horse.quality = 0
	add_child(horse)
	await get_tree().process_frame
	var skeleton := horse.skeleton
	var anim := horse.anim
	anim.root_motion_track = NodePath("")          # bake in place
	var mi: MeshInstance3D = null
	for m: MeshInstance3D in skeleton.find_children("Horse_LOD2*", "MeshInstance3D", true, false):
		mi = m
	var mesh := mi.mesh
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var nv := verts.size()
	var per := bones.size() / maxi(nv, 1)
	var skin := mi.skin
	var bind_bone := PackedInt32Array()
	var bind_pose: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bb := skin.get_bind_bone(b)
		if bb < 0:
			bb = skeleton.find_bone(skin.get_bind_name(b))
		bind_bone.append(bb)
		bind_pose.append(skin.get_bind_pose(b))
	var mat := load("res://assets/generated/horses/horse_coat_%s.tres" % coat) as BaseMaterial3D
	var img: Image = mat.albedo_texture.get_image() if mat and mat.albedo_texture else null
	if img and img.is_compressed():
		img.decompress()
	var cols := PackedColorArray()
	var uv2 := PackedVector2Array()
	for i in nv:
		var c := Color(0.5, 0.35, 0.2)
		if img and not uvs.is_empty():
			var u := uvs[i]
			c = img.get_pixel(clampi(int(fposmod(u.x, 1.0) * img.get_width()), 0, img.get_width() - 1),
				clampi(int(fposmod(u.y, 1.0) * img.get_height()), 0, img.get_height() - 1)).srgb_to_linear()
		c.a = 0.0           # never tinted
		cols.append(c)
		uv2.append(Vector2(float(i), 0.0))
	var base := horse.model.get_child(0) as Node3D
	var to_model := base.global_transform.affine_inverse() * skeleton.global_transform
	var clips := {}
	var rows_p := PackedFloat32Array()
	var rows_n := PackedByteArray()
	var row := 0
	for cn: String in CLIPS:
		var full := HorseRig.LIB + "/" + cn
		if not anim.has_animation(full):
			continue
		var a := anim.get_animation(full)
		var loop := a.loop_mode != Animation.LOOP_NONE
		var n := maxi(2, int(round(a.length * fps)))
		anim.play(full)
		for f in n:
			anim.seek(float(f) * a.length / n, true)
			var xf: Array[Transform3D] = []
			for b in bind_bone.size():
				xf.append(to_model * skeleton.get_bone_global_pose(maxi(bind_bone[b], 0)) * bind_pose[b])
			for i in nv:
				var p := Vector3.ZERO
				var nn := Vector3.ZERO
				for k in per:
					var w := weights[i * per + k]
					if w <= 0.0:
						continue
					var m: Transform3D = xf[bones[i * per + k]]
					p += (m * verts[i]) * w
					nn += (m.basis * normals[i]) * w
				nn = nn.normalized()
				rows_p.append_array([p.x, p.y, p.z, 1.0])
				rows_n.append_array([clampi(int(round((nn.x * 0.5 + 0.5) * 255.0)), 0, 255), clampi(int(round((nn.y * 0.5 + 0.5) * 255.0)), 0, 255),
					clampi(int(round((nn.z * 0.5 + 0.5) * 255.0)), 0, 255), 255])
		var entry := {"row": row, "frames": n, "loop": loop, "length": a.length}
		clips[full] = entry
		clips[cn] = entry
		row += n
	clips["Walk"] = clips.get(HorseRig.LIB + "/Walk", {})
	clips["Idle"] = clips.get(HorseRig.LIB + "/Idle", {})
	var pimg := Image.create_from_data(nv, row, false, Image.FORMAT_RGBAF, rows_p.to_byte_array())
	pimg.convert(Image.FORMAT_RGBAH)
	var nimg := Image.create_from_data(nv, row, false, Image.FORMAT_RGBA8, rows_n)
	var am := ArrayMesh.new()
	var ma := []
	ma.resize(Mesh.ARRAY_MAX)
	ma[Mesh.ARRAY_VERTEX] = verts
	ma[Mesh.ARRAY_NORMAL] = normals
	ma[Mesh.ARRAY_COLOR] = cols
	ma[Mesh.ARRAY_TEX_UV2] = uv2
	ma[Mesh.ARRAY_INDEX] = indices
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ma)
	var asset := VatAsset.new()
	asset.look = "horse_" + coat
	asset.mesh = am
	asset.pos_tex = ImageTexture.create_from_image(pimg)
	asset.nrm_tex = ImageTexture.create_from_image(nimg)
	asset.clips = clips
	asset.fps = fps
	asset.vertex_count = nv
	asset.frame_count = row
	asset.height = 2.0
	asset.source = "HorseRig LOD2 (%s) + Horse_Anims" % coat
	horse.queue_free()
	return asset
