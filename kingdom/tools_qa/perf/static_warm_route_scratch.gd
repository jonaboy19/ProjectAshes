extends Node
## Scratch A/B wrapper for town_route. Run in a fresh game process per arm.
## Both arms use this same wrapper; treatment adds --prewarm-static.
const Route := preload("res://tools_qa/perf/town_route.gd")
const KEYS := [
	"free:buildings/hut_long_thatch@4.6",
	"dl3:buildings/house_tudor_stone_base@7.40",
	"dl3:buildings/house_gable_porch_b@7.43",
]

func run(m: Node) -> void:
	var warm := OS.get_cmdline_user_args().has("--prewarm-static")
	var before_mem := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var t0 := Time.get_ticks_usec()
	if warm:
		for key: String in KEYS:
			var was_cached := Assets._static_cache.has(key)
			var k0 := Time.get_ticks_usec()
			var instance := Assets.static_model(key)
			var elapsed := Time.get_ticks_usec() - k0
			if instance != null:
				instance.free() # Preserve cached mesh; no scene instance is needed for warm-up.
			print("STATIC_PREWARM key=%s cached_before=%s ms=%.3f" % [key, str(was_cached), elapsed / 1000.0])
	var elapsed_total := Time.get_ticks_usec() - t0
	var after_mem := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	print("STATIC_PREWARM_SUM enabled=%s wall_ms=%.3f static_mem_delta_mb=%.2f" % [str(warm), elapsed_total / 1000.0, (after_mem - before_mem) / 1048576.0])
	var route := Route.new()
	add_child(route)
	route.call("run", m)
