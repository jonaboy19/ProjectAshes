extends SceneTree
## Dev probe: lists the clips a ghost body can play (name, length) so AshGhostClips can be tuned.
##   Godot --headless --path kingdom -s res://tools_qa/region1/clip_probe.gd -- [filter]

func _init() -> void:
	var filt := ""
	for a in OS.get_cmdline_user_args():
		filt = a
	var body: Node3D = Assets.mh_character("villager_man_a", 1.7)
	root.add_child(body)
	var ap := Assets.animation_player(body)
	var names := ap.get_animation_list()
	print("PROBE clips=", names.size())
	for n in names:
		if filt == "" or String(n).to_lower().contains(filt.to_lower()):
			var a := ap.get_animation(n)
			print("PROBE %s %.2f loop=%d" % [n, a.length, a.loop_mode])
	quit()
