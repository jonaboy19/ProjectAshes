extends SceneTree
## One-off investigation tool: dumps node identity + transform info for the
## two worst grounding-report floaters so we can see what they actually are
## before writing a fix. Not part of the regular QA scan.

var main: Control
var out_dir := ""
var phase := "boot"
var t := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			if kv[0] == "out":
				out_dir = kv[1]
	if out_dir == "":
		out_dir = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	change_scene_to_file("res://scenes/main.tscn")


func _process(delta: float) -> bool:
	t += delta
	match phase:
		"boot":
			main = current_scene as Control
			if main and main.get("player") and main.player.is_inside_tree() and main.hud and not main.hud._veil():
				phase = "goto1"
				t = 0.0
			elif t > 40.0:
				print("DBG boot timed out")
				quit()
		"goto1":
			# village_plaza: home settlement pos
			var wg: Script = load("res://scripts/world/world_gen.gd")
			var home: Vector2 = wg.settlements[0]["pos"]
			main._teleport(home, 0.0)
			if main.settlements:
				main.settlements.set_process(false)
			if main.region:
				main.region.set_process(false)
			t = 0.0
			phase = "settle1"
		"settle1":
			if t > 1.5:
				_dump_chunk()
				phase = "goto2"
				t = 0.0
		"goto2":
			# Stand 8 m off to the side of the target instead of on top of it --
			# teleporting exactly onto it means the PLAYER's own mesh always
			# "matches" the nearby-position search below, which is a false lead.
			main._teleport(Vector2(190.0, 128.0), 0.0)
			t = 0.0
			phase = "settle2"
		"settle2":
			if t > 1.5:
				_dump_mesh1453()
				quit()
				return true
	return false


func _dump_chunk() -> void:
	var world: Node = main.get_node_or_null("World")
	if world == null:
		world = main
	var chunk := world.find_child("Chunk_-3_0", true, false)
	var lines := PackedStringArray()
	lines.append("=== Chunk_-3_0 dump ===")
	if chunk == null:
		lines.append("Chunk_-3_0 not found")
	else:
		var wg: Script = load("res://scripts/world/world_gen.gd")
		for c in chunk.get_children():
			if c is MultiMeshInstance3D:
				var mmi := c as MultiMeshInstance3D
				var mm := mmi.multimesh
				var mesh_path := (mm.mesh.resource_path if mm and mm.mesh else "?")
				lines.append("-- child %s  mesh=%s  count=%d visible_count=%d visible_in_tree=%s" % [
					c.name, mesh_path, mm.instance_count if mm else -1,
					mm.visible_instance_count if mm else -1, str(mmi.is_visible_in_tree())])
				if mm:
					var box := mm.mesh.get_aabb() if mm.mesh else AABB()
					lines.append("   mesh aabb pos=%s size=%s" % [box.position, box.size])
					var n_show: int = mini(mm.instance_count, 5)
					for i in n_show:
						var xf := mmi.global_transform * mm.get_instance_transform(i)
						var o := xf.origin
						var ground: float = wg.height(o.x, o.z)
						lines.append("   inst %d pos=%s ground_h=%.2f gap=%.2f" % [i, o, ground, o.y - ground])
	var f := FileAccess.open(out_dir + "/chunk_dump.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	print("\n".join(lines))


func _dump_mesh1453() -> void:
	var world: Node = main.get_node_or_null("World")
	if world == null:
		world = main
	var lines := PackedStringArray()
	lines.append("=== mesh @1453/1454 search near (189.9, *, 120.0) ===")
	_walk(world, lines)
	var f := FileAccess.open(out_dir + "/mesh1453_dump.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	print("\n".join(lines))


func _walk(n: Node, lines: PackedStringArray) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.is_inside_tree():
			var o := mi.global_position
			if absf(o.x - 190.0) < 4.0 and absf(o.z - 120.0) < 4.0:
				var path := str(mi.get_path())
				var owner_name: String = (mi.owner.name if mi.owner else "no-owner")
				var parent_chain := ""
				var has_charbody := false
				var p := mi.get_parent()
				var depth := 0
				while p and depth < 8:
					parent_chain += " < " + p.name + "(" + p.get_class() + ")"
					if p is CharacterBody3D:
						has_charbody = true
					p = p.get_parent()
					depth += 1
				var mesh_path := (mi.mesh.resource_path if mi.mesh else "?")
				var box := mi.mesh.get_aabb() if mi.mesh else AABB()
				lines.append("FOUND %s  name=%s  pos=%s  owner=%s  mesh=%s  aabb_pos=%s aabb_size=%s  script=%s  has_charbody=%s  parents=%s" % [
					path, mi.name, o, owner_name, mesh_path, box.position, box.size,
					(mi.get_script().resource_path if mi.get_script() else "none"), str(has_charbody), parent_chain])
	for c in n.get_children():
		_walk(c, lines)
