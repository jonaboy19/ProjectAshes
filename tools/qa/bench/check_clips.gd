extends SceneTree
## Checks that every UAL clip (Assets.UAL_FILES, incl. the extra _library clips)
## resolves on the game's humanoid bodies: counts clips and unresolved tracks,
## and reports the memory the clip library costs.
##   godot --headless --path kingdom -s <abs>/tools/qa/bench/check_clips.gd

const BODIES := ["villager_man_a", "res://assets/incoming/characters/g6-ual/g6_m_villager_tunic",
	"res://assets/incoming/characters/cdmir-ual/cdmir_monk", "res://assets/incoming/ai3d/meshy/armored/guard"]


func _initialize() -> void:
	var assets: Script = load("res://scripts/world/assets.gd")
	var mem0 := OS.get_static_memory_usage()
	var failures := 0
	for body: String in BODIES:
		var file := body
		if file.begins_with("res://") and not ResourceLoader.exists(file + ".glb"):
			print("skip (missing) ", file)
			continue
		var t0 := Time.get_ticks_msec()
		var root: Node3D = assets.mh_character(file, 1.75)
		var ms := Time.get_ticks_msec() - t0
		get_root().add_child(root)
		var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
		var base := ap.get_node(ap.root_node)
		var clips := ap.get_animation_list()
		var unresolved := 0
		var looping := 0
		var tracks := 0
		for c in clips:
			var a := ap.get_animation(c)
			if a.loop_mode != Animation.LOOP_NONE:
				looping += 1
			for t in a.get_track_count():
				tracks += 1
				var p := a.track_get_path(t)
				var node := base.get_node_or_null(NodePath(p.get_concatenated_names()))
				if node == null:
					unresolved += 1
				elif node is Skeleton3D and p.get_subname_count() > 0 and (node as Skeleton3D).find_bone(p.get_subname(0)) < 0:
					unresolved += 1
		var extra := 0
		for c in ["Bow_Pull_Back", "Dodge_left", "Climb_Ladder", "Salute", "G6_idle_combat_two_handed_melee", "Fishing_Cast", "TreeChopping"]:
			if ap.has_animation(c):
				extra += 1
		print("%s: %d clips (%d looping), %d tracks, %d unresolved, sample extras found %d/7, built in %d ms" % [
			file.get_file(), clips.size(), looping, tracks, unresolved, extra, ms])
		failures += unresolved
		root.queue_free()
	print("Clip libraries: +%.1f MB static memory" % ((OS.get_static_memory_usage() - mem0) / 1048576.0))
	print("CHECK_CLIPS ", "OK" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
