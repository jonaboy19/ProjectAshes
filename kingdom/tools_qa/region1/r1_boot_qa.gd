extends Node
## Smoke test of the Region 1 glue inside the real game (xvfb, never --headless):
##   xvfb-run -a godot --path kingdom scenes/main.tscn --rendering-driver vulkan -- --skipintro --qa=res://tools_qa/region1/r1_boot_qa.gd
func run(main: Node) -> void:
	await get_tree().create_timer(3.0).timeout
	var g: Node = main.region1
	print("R1 glue: ", g != null)
	print("R1 modules: ", Region1State.modules())
	var wl := Region1State.sim(&"wardlines") as Wardlines
	print("R1 wardlines n=%d elders=%d source=%s health=%.2f" % [wl.n, wl.elder_ids.size(), wl.layout_source, wl.health()])
	print("R1 override on: ", Frontier.runestones.coverage_override.is_valid())
	var scar := Region1State.sim(&"scar_tide")
	print("R1 scar: ", scar.summary())
	print("R1 story active: ", g.story.story.active_steps())
	print("R1 npcs: ", g.story.npc_count())
	get_tree().quit()
