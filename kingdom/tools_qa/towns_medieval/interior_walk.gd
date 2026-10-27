extends Node
## Benchmark slice: Movie Maker recording of the scenario-A interior. Enters the house through its real InteriorDoor (town-kit
## building id, default the scenario house from data/world/slice_dressing.json), then pans an eye-height camera around the room.
##   godot --path kingdom --resolution 1280x720 --fixed-fps 30 --write-movie <out.avi> -- --adult --quality=high
##       --qa=res://tools_qa/towns_medieval/interior_walk.gd [--bid=ashford_house_1] [--hour=19] [--secs=16]
## Prints "FLY_START <frame>" / "FLY_END <frame>" like flythrough.gd.

var main: Node


func run(m: Node) -> void:
	main = m
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	var sd: Dictionary = preload("res://scripts/world/town_kit/slice_dressing.gd").data().get("scenario_a", {})
	var bid := String(args.get("bid", sd.get("house_bid", "ashford_house_1")))
	var hour := float(args.get("hour", "19.0"))
	var secs := float(args.get("secs", "16"))
	main.hud.visible = false
	var town: Dictionary = preload("res://scripts/world/town_kit/slice_dressing.gd").settlement(String(sd.get("town", "Ashford")))
	var c: Vector2 = town["pos"]
	main.call("_teleport", c + Vector2(6, 6), 0.0)
	for i in 5:
		main.settlements.update_now()
	main.settlements.finish_prop_jobs()
	for i in 30:
		await get_tree().process_frame
	var door: InteriorDoor = null
	for n in main.world.find_children("*", "InteriorDoor", true, false):
		if String((n as Node).get_meta("bid", "")) == bid:
			door = n
			break
	if door == null:
		print("INTERIOR no door for ", bid)
		get_tree().quit(1)
		return
	main.call("_teleport", Vector2(door.global_position.x, door.global_position.z), 0.0)
	await get_tree().process_frame
	door.enter(main.player)
	for i in 60:
		WorldSim.time_of_day = hour
		await get_tree().process_frame
	var room: Node3D = door.interior
	main.player.visible = false
	var spawn := room.find_child("PlayerSpawn", true, false) as Node3D
	var eye: Vector3 = (spawn.global_position if spawn else room.global_position) + Vector3(0, 1.65, 0)
	var base_yaw := spawn.global_rotation.y if spawn else 0.0
	var cam := Camera3D.new()
	cam.fov = 75.0
	room.add_child(cam)
	cam.current = true
	cam.global_position = eye
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false     # footage of the world only: no work dialogs, prompts or tags (UI is judged separately)
	for ch in main.get_children():
		if ch is Control and not (ch is SubViewportContainer):
			(ch as Control).visible = false
	print("FLY_START ", Engine.get_frames_drawn())
	var frames := int(secs * 30.0)
	for f in frames:
		var t := float(f) / float(frames - 1)
		var yaw := lerpf(-0.9, 0.9, t * t * (3.0 - 2.0 * t))      # sweep the room from the door
		var fwd := Vector3(-sin(base_yaw), 0.0, -cos(base_yaw))
		cam.global_position = eye + fwd * 0.8 * t
		cam.global_rotation = Vector3(-0.12, base_yaw + yaw, 0.0)
		WorldSim.time_of_day = hour
		_hide_ui()      # dialogs and prompts that open during the walk
		await get_tree().process_frame
	print("FLY_END ", Engine.get_frames_drawn())
	get_tree().quit(0)


func _hide_ui() -> void:
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	for ch in main.get_children():
		if ch is Control and not (ch is SubViewportContainer):
			(ch as Control).visible = false
