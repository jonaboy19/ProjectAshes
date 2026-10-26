extends SceneTree
## Data-integrity scan of every staged AAA clip at 30 fps, matching gameplay's in-place root-position policy.
## Checks finite bone transforms and ankle height only. It does not claim to grade pose quality, contacts, or clipping.
## Godot --headless --path kingdom -s tools_qa/anim/aaa_static_metrics.gd [-- --all]
const MAN := "res://data/anim/aaa_clips.json"
const FLOOR_LIMIT := -0.02


func _initialize() -> void:
	var include_skips := OS.get_cmdline_user_args().has("--all")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAN))["packs"]
	var failures := 0
	var scanned := 0
	print("clip | as | sec | min_ankle_cm | nonfinite | verdict")
	for pack: String in manifest:
		var clips: Dictionary = manifest[pack]
		var wanted: Array = []
		for clip_name: String in clips:
			var status := String(clips[clip_name].get("status", "skip"))
			if include_skips or status == "add" or status == "cmp":
				wanted.append(clip_name)
		if wanted.is_empty():
			continue
		var packed := load(pack) as PackedScene
		if packed == null:
			push_error("missing AAA pack: " + pack)
			failures += wanted.size()
			continue
		var instance := packed.instantiate()
		root.add_child(instance)
		await process_frame
		var skeletons := instance.find_children("*", "Skeleton3D", true, false)
		var players := instance.find_children("*", "AnimationPlayer", true, false)
		if skeletons.is_empty() or players.is_empty():
			push_error("pack has no skeleton or AnimationPlayer: " + pack)
			failures += wanted.size()
			instance.queue_free()
			await process_frame
			continue
		var skeleton := skeletons[0] as Skeleton3D
		var player := players[0] as AnimationPlayer
		var foot_l := skeleton.find_bone("foot_l")
		var foot_r := skeleton.find_bone("foot_r")
		if foot_l < 0 or foot_r < 0:
			push_error("pack has no foot bones: " + pack)
			failures += wanted.size()
			instance.queue_free()
			await process_frame
			continue
		for clip_name in player.get_animation_list():
			if clip_name == "RESET" or not wanted.has(clip_name):
				continue
			var animation := player.get_animation(clip_name).duplicate(true) as Animation
			var decision: Dictionary = clips[clip_name]
			var trim: Array = decision.get("trim", [0.0, animation.length])
			var start := clampf(float(trim[0]), 0.0, animation.length)
			var finish := clampf(float(trim[1]), start, animation.length)
			for track in animation.get_track_count():
				var path := String(animation.track_get_path(track))
				var colon := path.find(":")
				if colon > 0 and path.substr(colon) == ":root" and animation.track_get_type(track) == Animation.TYPE_POSITION_3D:
					animation.track_set_enabled(track, false)
			var audit_library := AnimationLibrary.new()
			audit_library.add_animation(clip_name, animation)
			player.add_animation_library("audit", audit_library)
			player.play("audit/" + clip_name)
			player.pause()
			var frame_start := int(round(start * 30.0))
			var frame_end := int(round(finish * 30.0))
			var has_nan := false
			var min_ankle := INF
			for frame in range(frame_start, frame_end + 1):
				player.seek(frame / 30.0, true)
				skeleton.force_update_all_bone_transforms()
				var left: Vector3 = skeleton.get_bone_global_pose(foot_l).origin
				var right: Vector3 = skeleton.get_bone_global_pose(foot_r).origin
				min_ankle = minf(min_ankle, minf(left.y, right.y))
				for bone in skeleton.get_bone_count():
					var pose := skeleton.get_bone_global_pose(bone)
					if not _finite_vec3(pose.origin) or not _finite_vec3(pose.basis.x) or not _finite_vec3(pose.basis.y) or not _finite_vec3(pose.basis.z):
						has_nan = true
			var verdict := "ok"
			if has_nan or min_ankle < FLOOR_LIMIT:
				verdict = "fail"
				failures += 1
			print("%s | %s | %.2f | %+.1f | %s | %s" % [
				clip_name, decision.get("as", "-"), finish - start, min_ankle * 100.0, has_nan, verdict])
			scanned += 1
			player.remove_animation_library("audit")
		instance.queue_free()
		await process_frame
	print("Scanned %d clips; %d data-integrity failures%s" % [scanned, failures, " (including skips)" if include_skips else ""])
	quit(1 if failures > 0 else 0)


func _finite_vec3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
