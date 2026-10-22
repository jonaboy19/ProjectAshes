extends SceneTree
## Measures where the hero's face features sit in the 2048 atlas (docs/art/FACES.md): brow rects are known (hero_character.gdshader),
## the eye line / mouth centre are derived from them (anthropometric offsets), and the UV box of the vertices around each is printed.
## "$GODOT" --headless --path kingdom -s res://tools_qa/hero/face_uv_probe.gd > face_uv.txt
const GLB := "res://assets/generated/characters/hero_tier_a/hero_meshy3.glb"
const BROWS := [Rect2(750, 510, 65, 100), Rect2(440, 1335, 60, 37)]


func _in_brows(q: Vector2) -> bool:
	for r: Rect2 in BROWS:
		if r.has_point(q):
			return true
	return false


func _initialize() -> void:
	var n: Node = (load(GLB) as PackedScene).instantiate()
	get_root().add_child(n)
	var sk := n.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hb := sk.find_bone("Head")
	print("HEAD_REST_ORIGIN ", sk.get_bone_global_rest(hb).origin, " basis_y ", sk.get_bone_global_rest(hb).basis.y)
	for mi in n.find_children("*Lids*", "MeshInstance3D", true, false):
		print("MESH Lids ", mi.name)
	var body: MeshInstance3D = null
	for mi in n.find_children("*base_body*", "MeshInstance3D", true, false):
		print("BODY_CAND ", mi.name, " vis_begin=", (mi as MeshInstance3D).visibility_range_begin)
		if body == null and (mi as MeshInstance3D).visibility_range_begin == 0.0:
			body = mi
	if body == null:
		print("NO_BODY")
		quit()
		return
	print("BODY ", body.name, " xf=", body.transform)
	var arr := body.mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var sum := Vector3.ZERO
	var nsum := Vector3.ZERO
	var cnt := 0
	for i in vs.size():
		if _in_brows(uvs[i] * 2048.0):
			sum += vs[i]
			nsum += ns[i]
			cnt += 1
	if cnt == 0:
		print("NO_BROW_VERTS")
		quit()
		return
	var b := sum / cnt
	print("BROW_VERTS ", cnt, " mean=", b, " normal=", (nsum / cnt).normalized())
	# the two brow rects belong to two brows (left/right): split by x sign
	var left := Vector3.ZERO
	var right := Vector3.ZERO
	var lc := 0
	var rc := 0
	for i in vs.size():
		if _in_brows(uvs[i] * 2048.0):
			if vs[i].x >= b.x:
				left += vs[i]
				lc += 1
			else:
				right += vs[i]
				rc += 1
	print("BROW_L ", left / maxf(lc, 1), " BROW_R ", right / maxf(rc, 1))
	var up := Vector3.UP
	var mouth_c := b - up * 0.075
	mouth_c.x = (left / maxf(lc, 1) + right / maxf(rc, 1)).x * 0.5
	var eye_l := left / maxf(lc, 1) - up * 0.02
	var eye_r := right / maxf(rc, 1) - up * 0.02
	print("MOUTH_CENTRE ", mouth_c)
	var fwd := (nsum / cnt).normalized()
	for pair: Array in [["MOUTH", mouth_c, 0.018], ["EYE_L", eye_l, 0.012], ["EYE_R", eye_r, 0.012]]:
		var c: Vector3 = pair[1]
		var r: float = pair[2]
		var x0 := 1e9
		var x1 := -1e9
		var y0 := 1e9
		var y1 := -1e9
		var k := 0
		for i in vs.size():
			if vs[i].distance_to(c) <= r and ns[i].dot(fwd) > 0.3:       # front-facing only (skip the back of the head)
				var q := uvs[i] * 2048.0
				x0 = minf(x0, q.x)
				x1 = maxf(x1, q.x)
				y0 = minf(y0, q.y)
				y1 = maxf(y1, q.y)
				k += 1
		print("%s_VERTS %d" % [pair[0], k])
		# diagnostics: UV points of those vertices bucketed in 64-texel cells (shows whether they sit on one island)
		var cells := {}
		for i in vs.size():
			if vs[i].distance_to(c) <= r and ns[i].dot(fwd) > 0.3:
				var cell := Vector2i(int(uvs[i].x * 2048.0 / 64.0), int(uvs[i].y * 2048.0 / 64.0))
				cells[cell] = int(cells.get(cell, 0)) + 1
		print("%s_CELLS64 %s" % [pair[0], str(cells)])
		if k > 0:
			print("%s_RECT %d %d %d %d" % [pair[0], floori(x0), ceili(x1), floori(y0), ceili(y1)])
	quit()
