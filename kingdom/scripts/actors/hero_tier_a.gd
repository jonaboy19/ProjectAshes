extends RefCounted
## Tier-A hero upgrade (skill ashes-hero-character). Call AFTER HeroOutfit.dress(model):
##   HeroTierA.upgrade(model)
## - swaps the 488-tri G6 head + helmet hair for the Tier-A head (assets/generated/characters/hero_tier_a/hero_head_tier_a.glb,
##   built by tools/blender/hero_tier_a/build_head.py from the MakeHuman face): own 1024 face texture, real eyeballs,
##   lashes/brows cards, scalp cap + 3 layers of hair cards, shape keys Blink_L/R, Smile, Jaw_Open, Brow_Up.
##   The head is RETARGETED at load onto the hero's existing skeleton (per-vertex: target rest * source bind), so the UAL
##   bones are untouched and every Codex clip drives it.
## - face/hands get hero_skin (faked SSS, flush, roughness zones, pores), eyes hero_eye, hair hero_hair (anisotropic).
## - drops HeroOutfit's old hair tufts; adds HeroFaceDriver (blink, expressions, hair/hood/satchel/skirt sway).
## Companions: same call works on any UAL character (G6 or MakeHuman) - the head GLB is the per-character asset.

const HEAD_GLB := "res://assets/generated/characters/hero_tier_a/hero_head_tier_a.glb"
const TEX := "res://assets/generated/characters/hero_tier_a/"
const SH := "res://shaders/hero/"
const Driver := preload("res://scripts/actors/hero_face_driver.gd")


static func upgrade(model: Node3D, head_glb := HEAD_GLB, hair_root := Color(0.17, 0.10, 0.06), hair_tip := Color(0.45, 0.29, 0.16)) -> Node:
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty() or not ResourceLoader.exists(head_glb):
		return null
	var sk := sks[0] as Skeleton3D
	if sk.has_node("HeroFaceDriver"):
		return sk.get_node("HeroFaceDriver")
	var noise: Texture2D = (load("res://scripts/actors/hero_outfit.gd") as GDScript).call("noise_texture")
	# 1. hide the G6 head + hair; skin shader on the hands
	var skin_tint := Color(1.0, 0.94, 0.9)
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		var nm := String(m.name).to_lower()
		if nm.contains("_head_") or nm.contains("_hair_") or nm.contains("eyebrow"):
			m.visible = false
		elif nm.contains("hands"):
			var src := m.get_active_material(0)
			var hm := _mat("hero_skin", noise)
			hm.set_shader_parameter("use_masks", false)
			hm.set_shader_parameter("pore_scale", 40.0)
			if src is BaseMaterial3D:
				hm.set_shader_parameter("albedo_tex", (src as BaseMaterial3D).albedo_texture)
				hm.set_shader_parameter("tint", (src as BaseMaterial3D).albedo_color)
			elif src is ShaderMaterial and (src as ShaderMaterial).get_shader_parameter("albedo_tex"):
				hm.set_shader_parameter("albedo_tex", (src as ShaderMaterial).get_shader_parameter("albedo_tex"))
			m.material_override = hm
	# 2. strip the old hair tufts (UV2.x == HAIR) out of the HeroOutfit mesh
	var outfit: MeshInstance3D = sk.get_node_or_null("HeroOutfit")
	if outfit:
		_strip_material_id(outfit, 5)
	# 3. retarget + attach the Tier-A head parts
	var src_root: Node = (load(head_glb) as PackedScene).instantiate()
	var src_sk := src_root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var parts := {}
	for n in src_root.find_children("*", "MeshInstance3D", true, false):
		var smi := n as MeshInstance3D
		var mi := _retarget(smi, src_sk, sk)
		if mi == null:
			continue
		parts[String(smi.name)] = mi
		var mat: ShaderMaterial
		match String(smi.name):
			"FaceSkin":
				mat = _mat("hero_skin", noise)
				mat.set_shader_parameter("albedo_tex", load(TEX + "hero_face_albedo.png"))
				mat.set_shader_parameter("tint", skin_tint)
			"Eyes":
				mat = _mat("hero_eye", noise)
			"LashesBrows":
				mat = _mat("hero_hair", noise)
				mat.set_shader_parameter("strand_tex", load(TEX + "hero_lash_brow.png"))
				mat.set_shader_parameter("lash", true)
			"HairCards":
				mat = _mat("hero_hair", noise)
				mat.set_shader_parameter("strand_tex", load(TEX + "hero_hair_strands.png"))
			"HairCap":
				mat = _mat("hero_hair", noise)
				mat.set_shader_parameter("cap", true)
		if mat and String(smi.name).begins_with("Hair"):
			mat.set_shader_parameter("root_color", hair_root)
			mat.set_shader_parameter("tip_color", hair_tip)
		mi.material_override = mat
		mi.set_meta("role", "hero_tier_a")
	src_root.free()
	# 4. driver: blink, expressions, secondary motion
	var drv: Node = Driver.new()
	drv.name = "HeroFaceDriver"
	sk.add_child(drv)
	drv.call("setup", sk, parts, outfit)
	return drv


static func _mat(shader: String, noise: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SH + shader + ".gdshader")
	m.set_shader_parameter("noise_tex", noise)
	return m


## Copies a skinned mesh from the head GLB onto `dst` skeleton: v' = sum_i w_i * dst_rest(bone_i) * src_bind_i * v.
## Blend shapes are transformed the same way, so Blink/Smile stay aligned. The skin is rebuilt from dst rest transforms.
static func _retarget(smi: MeshInstance3D, src_sk: Skeleton3D, dst: Skeleton3D) -> MeshInstance3D:
	if smi.mesh == null or smi.skin == null:
		return null
	var skin := smi.skin
	var bind_xf: Array[Transform3D] = []
	var bind_dst: PackedInt32Array = []
	for b in skin.get_bind_count():
		var bn := skin.get_bind_name(b)
		if bn == &"" and skin.get_bind_bone(b) >= 0:
			bn = src_sk.get_bone_name(skin.get_bind_bone(b))
		var di := dst.find_bone(bn)
		bind_dst.append(maxi(di, 0))
		bind_xf.append((dst.get_bone_global_rest(di) if di >= 0 else Transform3D()) * skin.get_bind_pose(b))
	var src_mesh := smi.mesh as ArrayMesh
	var out := ArrayMesh.new()
	for bi in src_mesh.get_blend_shape_count():
		out.add_blend_shape(src_mesh.get_blend_shape_name(bi))
	out.blend_shape_mode = src_mesh.blend_shape_mode
	for si in src_mesh.get_surface_count():
		var arr := src_mesh.surface_get_arrays(si)
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nk := bones.size() / maxi(1, verts.size())
		var xfs: Array[Transform3D] = []
		xfs.resize(verts.size())
		for v in verts.size():
			var acc := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
			var tw := 0.0
			for k in nk:
				var w := weights[v * nk + k]
				if w <= 0.0:
					continue
				var t := bind_xf[bones[v * nk + k]]
				acc.basis = Basis(acc.basis.x + t.basis.x * w, acc.basis.y + t.basis.y * w, acc.basis.z + t.basis.z * w)
				acc.origin += t.origin * w
				tw += w
			xfs[v] = acc if tw > 0.0 else Transform3D()
		arr[Mesh.ARRAY_VERTEX] = _xf_points(verts, xfs)
		if arr[Mesh.ARRAY_NORMAL] != null:
			arr[Mesh.ARRAY_NORMAL] = _xf_dirs(arr[Mesh.ARRAY_NORMAL], xfs)
		if arr[Mesh.ARRAY_TANGENT] != null:
			var tg: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
			for v in verts.size():
				var d := (xfs[v].basis * Vector3(tg[v * 4], tg[v * 4 + 1], tg[v * 4 + 2])).normalized()
				tg[v * 4] = d.x; tg[v * 4 + 1] = d.y; tg[v * 4 + 2] = d.z
			arr[Mesh.ARRAY_TANGENT] = tg
		for i in bones.size():
			bones[i] = bind_dst[bones[i]]
		arr[Mesh.ARRAY_BONES] = bones
		var bsa: Array = []
		for bs in src_mesh.surface_get_blend_shape_arrays(si):
			var b2: Array = bs
			b2[Mesh.ARRAY_VERTEX] = _xf_points(b2[Mesh.ARRAY_VERTEX], xfs)
			if b2[Mesh.ARRAY_NORMAL] != null:
				b2[Mesh.ARRAY_NORMAL] = _xf_dirs(b2[Mesh.ARRAY_NORMAL], xfs)
			if b2[Mesh.ARRAY_TANGENT] != null:
				b2[Mesh.ARRAY_TANGENT] = arr[Mesh.ARRAY_TANGENT]
			bsa.append(b2)
		var fl := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if nk == 8 else 0
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, bsa, {}, fl)
	var mi := MeshInstance3D.new()
	mi.name = "TierA_" + String(smi.name)
	mi.mesh = out
	dst.add_child(mi)
	mi.skeleton = NodePath("..")
	mi.skin = dst.create_skin_from_rest_transforms()
	return mi


static func _xf_points(p: PackedVector3Array, xfs: Array[Transform3D]) -> PackedVector3Array:
	var o := PackedVector3Array()
	o.resize(p.size())
	for i in p.size():
		o[i] = xfs[i] * p[i]
	return o


static func _xf_dirs(p: PackedVector3Array, xfs: Array[Transform3D]) -> PackedVector3Array:
	var o := PackedVector3Array()
	o.resize(p.size())
	for i in p.size():
		o[i] = (xfs[i].basis * p[i]).normalized()
	return o


## Removes every triangle whose UV2.x == id from a non-indexed SurfaceTool mesh (HeroOutfit).
static func _strip_material_id(mi: MeshInstance3D, id: int) -> void:
	var src := mi.mesh as ArrayMesh
	var arr := src.surface_get_arrays(0)
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2] if arr[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	if uv2.is_empty() or arr[Mesh.ARRAY_INDEX] != null:
		return
	var keep := PackedInt32Array()
	for t in uv2.size() / 3:
		if int(round(uv2[t * 3].x)) != id:
			keep.append(t)
	var per := {Mesh.ARRAY_VERTEX: 1, Mesh.ARRAY_NORMAL: 1, Mesh.ARRAY_TANGENT: 4, Mesh.ARRAY_COLOR: 1, Mesh.ARRAY_TEX_UV: 1,
		Mesh.ARRAY_TEX_UV2: 1, Mesh.ARRAY_BONES: 4, Mesh.ARRAY_WEIGHTS: 4}
	for k in per:
		var a = arr[k]
		if a == null:
			continue
		var n: int = per[k]
		var o = a.duplicate()
		o.resize(keep.size() * 3 * n)
		var j := 0
		for t in keep:
			for q in 3 * n:
				o[j] = a[t * 3 * n + q]
				j += 1
		arr[k] = o
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mi.mesh = m


## Tier-A material pass for a single-atlas Meshy character already re-rigged to UAL (the chosen hero base
## assets/generated/characters/hero_tier_a/hero_meshy.glb, built by tools/blender/hero_tier_a/smooth_lods.py) or any
## Tier-B companion from meshy_dl3/characters_ual. Classifies the atlas per texel (skin / hair / linen / wool / leather /
## metal) in hero_character.gdshader. No bone or mesh changes; returns the material (shared per atlas texture).
static var _char_mats := {}
static func upgrade_meshy(model: Node3D, saturation := 0.92) -> ShaderMaterial:
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return null
	var sk := sks[0] as Skeleton3D
	var head := sk.find_bone("Head")
	var neck_y := sk.get_bone_global_rest(head).origin.y - 0.1 if head >= 0 else 1.45
	var noise: Texture2D = (load("res://scripts/actors/hero_outfit.gd") as GDScript).call("noise_texture")
	var out: ShaderMaterial = null
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null or m.mesh.get_surface_count() == 0:
			continue
		var src := m.get_active_material(0)
		var tex: Texture2D = (src as BaseMaterial3D).albedo_texture if src is BaseMaterial3D else null
		if tex == null:
			continue
		var key := "%d|%.2f|%.3f" % [tex.get_instance_id(), saturation, neck_y]
		if not _char_mats.has(key):
			var sm := _mat("hero_character", noise)
			sm.set_shader_parameter("albedo_tex", tex)
			sm.set_shader_parameter("neck_y", neck_y)
			sm.set_shader_parameter("saturation", saturation)
			sm.set_shader_parameter("detail_scale", float(tex.get_width()) / 2048.0)
			_char_mats[key] = sm
		out = _char_mats[key]
		m.material_override = out
	return out


## Full Tier-A Meshy hero: material pass + hood/satchel/strap/belt from HeroOutfit + blink lids + sway driver.
static func dress_meshy_hero(model: Node3D) -> Node:
	upgrade_meshy(model)
	var outfit: MeshInstance3D = (load("res://scripts/actors/hero_outfit.gd") as GDScript).call("dress", model, ["satchel", "strap", "belt"])   # fitted hood: WIP (shards at the chest), off
	var sk := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var parts := {}
	for n in model.find_children("*Lids*", "MeshInstance3D", true, false):
		parts["Lids"] = n
		var lm := ShaderMaterial.new()
		lm.shader = load(SH + "hero_lid.gdshader")
		var cm := (n as MeshInstance3D).material_override as ShaderMaterial
		if cm:
			lm.set_shader_parameter("albedo_tex", cm.get_shader_parameter("albedo_tex"))
		(n as MeshInstance3D).material_override = lm
		(n as MeshInstance3D).visible = false
	var drv: Node = Driver.new()
	drv.name = "HeroFaceDriver"
	sk.add_child(drv)
	drv.call("setup", sk, parts, outfit)
	return drv
