extends SceneTree
## Foot-slide / contact metric for a UAL clip-library GLB (root-motion track ENABLED, so travel is included).
## For each clip, samples foot_l/foot_r world positions at 30 fps, marks contact frames (foot ball height
## close to the lowest it ever gets in the clip and vertical speed small) and reports the mean and max
## horizontal speed (m/s) of the planted foot. ~0 = planted. Also reports root travel and lowest foot height.
##   godot --headless --path kingdom -s tools/anim/foot_slide.gd -- --glb=res://assets/incoming/mocap/cmu/clips/UAL_CMU_Bending.glb
func _initialize() -> void:
	var glb := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--glb="): glb = a.substr(6)
	var ps: PackedScene = load(glb)
	var inst: Node = ps.instantiate()
	root.add_child(inst)
	await process_frame
	await process_frame
	var sk: Skeleton3D = _find(inst)
	var ap: AnimationPlayer = _find_ap(inst)
	var fl := sk.find_bone("foot_l"); var fr := sk.find_bone("foot_r")
	print("clip | sec | travel_m | contact% | slide_mean m/s | slide_max m/s | min_foot_y")
	for n in ap.get_animation_list():
		if n == "RESET": continue
		var anim := ap.get_animation(n)
		ap.play(n); ap.pause()
		var dt := 1.0 / 30.0
		var steps := int(anim.length / dt)
		var P: Array = []
		for i in range(steps + 1):
			ap.seek(i * dt, true)
			sk.force_update_all_bone_transforms()
			var a: Vector3 = sk.get_bone_global_pose(fl).origin
			var b: Vector3 = sk.get_bone_global_pose(fr).origin
			P.append([a, b])
		var miny := 9.0
		for p in P:
			miny = minf(miny, minf(p[0].y, p[1].y))
		var tot := 0; var cont := 0; var sum := 0.0; var mx := 0.0
		for i in range(1, P.size()):
			for f in range(2):
				var cur: Vector3 = P[i][f]; var prev: Vector3 = P[i - 1][f]
				tot += 1
				if cur.y < miny + 0.06 and absf(cur.y - prev.y) / dt < 0.25:
					var v := Vector2(cur.x - prev.x, cur.z - prev.z).length() / dt
					cont += 1; sum += v; mx = maxf(mx, v)
		var trav := Vector2(P[-1][0].x - P[0][0].x, P[-1][0].z - P[0][0].z).length()
		print("%s | %.2f | %.2f | %d | %.2f | %.2f | %.3f" % [n, anim.length, trav, int(100.0 * cont / maxi(tot, 1)), sum / maxi(cont, 1), mx, miny])
	quit()
func _find(n: Node) -> Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var r := _find(c)
		if r: return r
	return null
func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer: return n
	for c in n.get_children():
		var r := _find_ap(c)
		if r: return r
	return null
