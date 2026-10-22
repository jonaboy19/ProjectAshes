extends SceneTree
# Tiny render test for RenderDoc / profiling: loads GLBs (args after --) and sways them for 25 s.
#   godot --path <any project> --rendering-driver vulkan -s godot_rd_scene.gd -- a.glb b.glb c.glb
var t := 0.0
var root3d: Node3D
func _initialize():
	root3d = Node3D.new(); root.add_child(root3d)
	var cam = Camera3D.new(); root3d.add_child(cam); cam.look_at_from_position(Vector3(0, 6, 22), Vector3(0, 3, 0))
	var sun = DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 30, 0); sun.shadow_enabled = true; root3d.add_child(sun)
	var x = -10.0
	for f in OS.get_cmdline_user_args():
		var st = GLTFState.new(); var d = GLTFDocument.new()
		if d.append_from_file(f, st) == OK:
			var n = d.generate_scene(st); n.position = Vector3(x, 0, 0); root3d.add_child(n)
		x += 10.0
func _process(dt):
	t += dt
	root3d.rotation.y = sin(t) * 0.3
	return t > 25.0
