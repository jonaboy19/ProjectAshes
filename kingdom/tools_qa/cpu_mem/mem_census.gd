extends RefCounted
## Memory census (release QA, cloud lane): what the game's own data holds, by owner, without touching the renderer.
## Sizes are var_to_bytes() lengths of Dictionary / Array / Packed* / String values, a fair proxy for the heap they take
## (objects are not followed except RefCounted modules held by the autoloads, one level down). Three tables:
##   * autoload members (Life, WorldSim, Frontier, Game ...) and the realm modules / sim systems Life holds,
##   * every `static var` in scripts/ and autoload/ (the caches that live for the whole session),
##   * the engine counters (MEMORY_STATIC, objects, nodes, resources, orphans) and the biggest resource types.
## Run from a --qa driver:   var rows := load("res://tools_qa/cpu_mem/mem_census.gd").new().run(tree)   (prints MEMCENSUS lines)
const TOP := 40
var report := {}


func run(tree: SceneTree) -> Dictionary:
	report["engine"] = {
		"memory_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	}
	print("MEMCENSUS engine static=%.0f MB objects=%d nodes=%d resources=%d orphans=%d" % [report["engine"]["memory_static_mb"],
		report["engine"]["objects"], report["engine"]["nodes"], report["engine"]["resources"], report["engine"]["orphan_nodes"]])
	if report["engine"]["orphan_nodes"] > 0:
		print("MEMCENSUS orphan nodes follow (Node.print_orphan_nodes):")
		Node.print_orphan_nodes()
	var rows: Array = []
	for n in ["Life", "WorldSim", "Frontier", "Game", "Audio", "App", "Quality"]:
		var node := tree.root.get_node_or_null(n)
		if node != null:
			_members(node, "autoload " + n, rows, 1)
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	report["members"] = rows.slice(0, TOP)
	for r: Array in report["members"]:
		print("MEMCENSUS member %-58s %9d B" % [r[0], r[1]])
	var st: Array = _statics()
	st.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	report["statics"] = st.slice(0, TOP)
	for r: Array in report["statics"]:
		print("MEMCENSUS static %-62s %9d B" % [r[0], r[1]])
	return report


func _bytes(v: Variant) -> int:
	match typeof(v):
		TYPE_DICTIONARY, TYPE_ARRAY, TYPE_STRING, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, \
		TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_STRING_NAME:
			return var_to_bytes(v).size()
	return 0


func _members(o: Object, label: String, rows: Array, depth: int) -> void:
	for p: Dictionary in o.get_property_list():
		if (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var name := String(p["name"])
		var v: Variant = o.get(name)
		var b := _bytes(v)
		if b > 4096:
			rows.append(["%s.%s" % [label, name], b])
		elif v is RefCounted and depth > 0 and (v as Object).get_script() != null:
			_members(v, "%s.%s" % [label, name], rows, depth - 1)


func _statics() -> Array:
	var out: Array = []
	var files: Array = []
	for dir in ["res://scripts", "res://autoload"]:
		_collect(dir, files)
	var re := RegEx.new()
	re.compile("(?m)^static var (\\w+)")
	for f: String in files:
		var text := FileAccess.get_file_as_string(f)
		if not text.contains("static var "):
			continue
		var script := load(f) as GDScript
		if script == null:
			continue
		for m in re.search_all(text):
			var name := m.get_string(1)
			var v: Variant = script.get(name)
			var b := _bytes(v)
			if b > 4096:
				out.append(["%s::%s" % [f.trim_prefix("res://"), name], b])
	return out


func _collect(dir: String, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		_collect(dir.path_join(sub), out)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
