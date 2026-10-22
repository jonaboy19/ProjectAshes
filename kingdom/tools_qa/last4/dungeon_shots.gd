extends Node
## QA driver: enters one procedural dungeon of a theme and shoots the spawn view (ambient, crystal glow, exit portal).
##   ... -- --adult --quality=low --qa=res://tools_qa/last4/dungeon_shots.gd --theme=crystal [--tag=after]
const DungeonDoor := preload("res://scripts/interiors/dungeon_door.gd")
var main: Node


func run(m: Node) -> void:
	main = m
	var theme := "crystal"
	var tag := "after"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--theme="):
			theme = a.substr(8)
		if a.begins_with("--tag="):
			tag = a.substr(6)
	WorldSim.time_of_day = 12.0
	for i in 20:
		await get_tree().process_frame
	var door := DungeonDoor.new()
	main.world.add_child(door)
	door.global_position = main.player.global_position + Vector3(0, 0, -8)
	door.configure({"dungeon_id": "qa_" + theme, "seed": 11, "theme": theme, "tier": 2, "name": "QA " + theme, "rooms": 5})
	door.enter(main.player)
	await get_tree().create_timer(5.0).timeout
	await _shot("%s_%s_spawn" % [tag, theme])
	main.player.set_camera(main.player._yaw + PI, -0.2)
	await get_tree().create_timer(3.0).timeout
	await _shot("%s_%s_exit" % [tag, theme])
	var roots := main.get_tree().root.find_children("Dungeon_*", "Node3D", true, false)
	for r in roots:
		var n := 0
		for l in r.find_children("*", "Light3D", true, false):
			n += 1
		print("LIGHTS ", r.name, " real lights ", n)
	get_tree().quit(0)


func _shot(name: String) -> void:
	for i in 6:
		await get_tree().process_frame
	var img: Image = main.get_viewport().get_texture().get_image()
	var path := "/tmp/claude-0/shots/last4/%s.png" % name
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("SHOT ", path)
