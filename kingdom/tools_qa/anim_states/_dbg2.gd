extends SceneTree
func _initialize(): _go.call_deferred()
func _go():
	var m := Assets.mh_character("villager_man_a", 1.7); root.add_child(m)
	var ap := Assets.animation_player(m); LifeLibrary.install(ap)
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	var ik := ContactIK.new(); sk.add_child(ik)
	ap.play("Life_Mx_Pray_Kneel")
	var bones := ["hand_l","hand_r","middle_03_l","thumb_03_r","pelvis"]
	ik.modification_processed.connect(func():
		var t := []
		for b in bones: t.append(snappedf((sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b)).origin).y, 0.01))
		print("F ", t, " off ", snappedf(ik.pelvis_off,0.001), " lift ", snappedf(ik.last_hand_lift,0.001)))
	for f in [0, 10, 20]:
		ap.seek(f / 30.0, true)
		await process_frame
	quit()
