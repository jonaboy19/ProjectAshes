extends Node3D
## Region 1 L3 render check for an interior scene that no world door points at yet (the main.gd
## `--shot=interior_<name>` route needs an InteriorDoor in the world; C1 places those).
##
##   Godot --path kingdom res://tools_qa/region1/interior_shot.tscn --resolution 1600x900 -- \
##       --scene=res://scenes/interiors/chapel_interior.tscn --out=<dir>/interior_chapel [--npcs]
##
## Writes <out>_preview.png (the scene's PreviewCamera), <out>_spawn.png (eye height at PlayerSpawn looking
## into the room, FOV 75, like the game camera) and <out>_room.png (a raised corner view), then prints the
## draw-call / primitive counts of the spawn view. Never pass --headless.

var scene_path := "res://scenes/interiors/chapel_interior.tscn"
var out_base := ""
var room: Node3D
var cam: Camera3D
var step := 0
var frames := 0
var stats := {}
var sp: Node3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="): scene_path = a.substr(8)
		elif a.begins_with("--out="): out_base = a.substr(6)
	var ps := load(scene_path) as PackedScene
	room = ps.instantiate() as Node3D
	room.set("spawn_npcs", OS.get_cmdline_user_args().has("--npcs"))
	add_child(room)
	if out_base == "":
		out_base = "user://" + scene_path.get_file().get_basename()
	DirAccess.make_dir_recursive_absolute(out_base.get_base_dir())
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.current = false
	add_child(cam)


func _shoot(suffix: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [out_base, suffix])
	print("SAVED %s_%s.png" % [out_base, suffix])


func _process(_dt: float) -> void:
	frames += 1
	if frames < 30:
		return
	match step:
		0:
			_shoot("preview")
			sp = room.get_node("PlayerSpawn") as Node3D
			cam.global_transform = Transform3D(sp.global_basis, sp.global_position + Vector3(0, 1.6, 0))
			cam.current = true
			(room.get_node("PreviewCamera") as Camera3D).current = false
			step = 1; frames = 0
		1:
			_shoot("spawn")
			var rid := get_viewport().get_viewport_rid()
			stats = {
				"draw_calls": RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
				"primitives": RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
				"objects": RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
			}
			print("STATS ", stats)
			var lights := room.find_children("*", "OmniLight3D", true, false)
			var shadowed := 0
			for l in lights:
				if (l as Light3D).shadow_enabled:
					shadowed += 1
			print("LIGHTS omni=", lights.size(), " shadowed=", shadowed)
			print("COLLIDERS ", room.get_node("Colliders").get_child_count(), " NPC markers ", room.find_children("NPC_*", "Marker3D", true, false).size())
			# raised corner view
			var back: Vector3 = -sp.global_basis.z
			cam.global_position = sp.global_position + Vector3(0, 3.6, 0) + Vector3(sp.global_basis.x.x * 3.0, 0, sp.global_basis.x.z * 3.0)
			cam.look_at(sp.global_position + back * 6.0 + Vector3(0, 1.4, 0))
			step = 2; frames = 0
		2:
			_shoot("room")
			get_tree().quit()
