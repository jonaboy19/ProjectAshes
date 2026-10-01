extends RefCounted
## Headless timing of DistrictProps (town build hitch). Prints build ms (whole call) per town, and for the time-sliced
## builder the slice count and the longest slice.
##   $G --headless --path . -s res://tools_qa/districts/district_build_prof.gd -- [--towns=Thornfield,Kingsreach]

func run(tree: SceneTree, towns: Array) -> void:
	WorldGen.setup(1066)
	var sb: Node3D = load("res://scripts/world/settlement_builder.gd").new()
	tree.root.add_child(sb)
	var dp = load("res://scripts/world/district_props.gd")
	for s: Dictionary in WorldGen.settlements:
		if not towns.has(s["name"]):
			continue
		sb._build(s)   # warm caches (meshes, footprints) like a running game
		var holder := Node3D.new()
		tree.root.add_child(holder)
		var t0 := Time.get_ticks_usec()
		var job = dp.build(sb, holder, s, s["plan"], false)
		var first := (Time.get_ticks_usec() - t0) / 1000.0
		var slices := 1
		var worst := first
		if job != null:
			while not job.done:
				var t1 := Time.get_ticks_usec()
				job.step(3.0)
				var d := (Time.get_ticks_usec() - t1) / 1000.0
				worst = maxf(worst, d)
				slices += 1
		var total := (Time.get_ticks_usec() - t0) / 1000.0
		print("DPROF %s total=%.1f ms first_call=%.1f ms slices=%d worst_slice=%.1f ms mmi=%d" % [s["name"], total, first, slices, worst, holder.find_children("*", "MultiMeshInstance3D", true, false).size()])
		if job != null:
			var pw := []
			for k in job.phase_worst:
				pw.append("%d:%.1f" % [k, job.phase_worst[k]])
			print("DPROF phases(worst unit ms) ", " ".join(pw))
		holder.queue_free()
