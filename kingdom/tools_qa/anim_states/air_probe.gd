extends SceneTree
func _initialize() -> void:
	_r.call_deferred()
func _r() -> void:
	var m: Node3D = Assets.mh_character("player_young", 1.8)
	root.add_child(m)
	await process_frame
	var ap: AnimationPlayer = Assets.animation_player(m)
	for c in ["Jump_Start", "Jump_Rise", "Jump_Fall", "Idle"]:
		if not ap.has_animation(c):
			print("AIR missing ", c); continue
		var a := ap.get_animation(c)
		print("AIR ", c, " tracks=", a.get_track_count(), " meta=", a.has_meta(&"air_arms"))
		for t in a.get_track_count():
			var p := String(a.track_get_path(t))
			if p.ends_with(":upperarm_l") and a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				var q: Quaternion = a.track_get_key_value(t, a.track_get_key_count(t) / 2)
				print("   ", p, " mid ", q, " enabled=", a.track_is_enabled(t))
	quit()
