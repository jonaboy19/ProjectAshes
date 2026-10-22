extends Node
## Memory probe (cloud lane, headless): boots the main scene, streams Ashford for a fixed time and prints one MEMBUDGET JSON line.
##   godot --headless --path kingdom -- --adult --quality=high [--ram8] --qa=res://tools_qa/perf/mem_budget.gd [--seconds=20] [--out=/p.json]
## Run it twice (without and with --ram8) to compare. Static/peak are the engine heap (MB). Texture and video memory are the
## RenderingServer's and read 0 on the headless dummy renderer: VRAM must be measured on a local PC (see ashes-handoff).
var main: Node
var dur := 20.0
var out := ""
var t := 0.0


func run(m: Node) -> void:
	main = m
	for raw_a in Array(OS.get_cmdline_user_args()):
		var a := String(raw_a)
		if a.begins_with("--seconds="):
			dur = float(a.get_slice("=", 1))
		elif a.begins_with("--out="):
			out = a.get_slice("=", 1)
	main.call("_teleport", (WorldGen.settlements[0]["pos"] as Vector2) + Vector2(10, 0), 0.0)


func _process(delta: float) -> void:
	t += delta
	if t < dur:
		return
	set_process(false)
	var mb := 1.0 / 1048576.0
	var r := {
		"ram8": Quality.ram8, "tier": Quality.tier_name(), "profile": Quality.profile, "seconds": dur,
		"static_mb": snappedf(OS.get_static_memory_usage() * mb, 0.1),
		"static_peak_mb": snappedf(OS.get_static_memory_peak_usage() * mb, 0.1),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"texture_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) * mb, 0.1),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) * mb, 0.1),
		"npc_full": Quality.npc_full, "npc_sprites": Quality.npc_sprites, "view_radius": Quality.view_radius,
	}
	var js := JSON.stringify(r)
	print("MEMBUDGET ", js)
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string(js)
	get_tree().quit()
