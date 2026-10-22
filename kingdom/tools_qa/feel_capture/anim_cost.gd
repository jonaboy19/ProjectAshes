extends SceneTree
## CPU cost of the real CharacterAnimator per character (AnimationTree advance + skeleton),
## player graph (with Codex's air/transition state machine) vs NPC/companion graph.
##   Godot --headless --path kingdom -s res://tools_qa/feel_capture/anim_cost.gd
## Numbers are PC CPU only; phone estimate x5 (skill ashes-performance).
const CA := preload("res://scripts/actors/character_animator.gd")
const N := 20
const FRAMES := 240


func _initialize() -> void:
	await process_frame
	for with_air: bool in [false, true]:
		var anims: Array = []
		var root := Node3D.new()
		get_root().add_child(root)
		for i in N:
			var body: Node3D = Assets.character("Knight" if not with_air else "Player", 1.8, ["1H_Sword", "Round_Shield"])
			root.add_child(body)
			body.position = Vector3(i * 2.0, 0, 0)
			var a = CA.new(body, 6.0, -1.0, "Walking_A", "Running_A", "Idle", true, with_air)
			anims.append(a)
			a.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for warm in 30:
			await process_frame
		var usec := 0
		for f in FRAMES:
			var t0 := Time.get_ticks_usec()
			for i in N:
				var a = anims[i]
				a.update(1.0 / 30.0, 3.0 + 3.0 * sin(f * 0.05 + i), Vector3.FORWARD)
				if with_air and f % 60 == 0:
					a.play_air("Jump_Rise")
				elif with_air and f % 60 == 20:
					a.finish_air()
				a.tree.advance(1.0 / 30.0)
			usec += Time.get_ticks_usec() - t0
		print("ANIMCOST %s: %.3f ms per character per frame (PC), ~%.2f ms phone" % [
			"player+air" if with_air else "npc/companion", usec / 1000.0 / FRAMES / N, usec / 1000.0 / FRAMES / N * 5.0])
		root.queue_free()
		await process_frame
	quit(0)
