extends SceneTree
## Boot-loop probe: boots the game once and prints BOOT_OK only if a world really exists.
## Run: godot --path kingdom -s res://tools_qa/boot_loop/boot_loop.gd -- [--frontend|--menu] [--secs=25]
##   (default)   main.tscn directly (the QA launch path).
##   --frontend  the loading screen that threaded-loads main.tscn, then the world.
##   --menu      the real player path: boot.tscn -> splash (key press) -> main menu ->
##               Continue (latest save) -> loading screen -> world.
## Exit code 0 + "BOOT_OK" = a world was built and ran for --secs; 3 = timeout, no world.
## A hard crash gives 0xC0000005 (-1073741819), which the caller counts.

var mode := "direct"
var secs := 25.0
var main: Node
var _t := 0.0
var _world_t := -1.0
var _done := false
var _menu_stage := 0
var _menu_t := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--frontend":
			mode = "frontend"
		elif a == "--menu":
			mode = "menu"
		elif a.begins_with("--secs="):
			secs = float(a.substr(7))
	match mode:
		"frontend":
			load("res://scripts/ui/frontend/loading_screen.gd").open(root)
		"menu":
			change_scene_to_file("res://scenes/boot.tscn")
		_:
			var scene: PackedScene = load("res://scenes/main.tscn")
			main = scene.instantiate()
			root.add_child(main)


func _find_menu(n: Node) -> Node:
	var s := n.get_script() as Script
	if s and s.resource_path.ends_with("frontend/main_menu.gd"):
		return n
	for c in n.get_children():
		var r := _find_menu(c)
		if r:
			return r
	return null


func _drive_menu(delta: float) -> void:
	_menu_t += delta
	if _menu_stage == 0 and _menu_t > 3.5:
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.keycode = KEY_ENTER
		ev.physical_keycode = KEY_ENTER
		Input.parse_input_event(ev)
		_menu_stage = 1
		_menu_t = 0.0
	elif _menu_stage == 1 and _menu_t > 1.5:
		var m: Node = _find_menu(root)
		if m:
			var life := root.get_node_or_null("Life")
			var id: String = life.saves.latest_id() if life else ""
			print("MENU reached; continue id='%s'" % id)
			if id != "":
				m.call("_start_load", id)
				_menu_stage = 2
			else:
				print("BOOT_NO_SAVE")
				_done = true
				quit(4)
		elif _menu_t > 15.0:
			_menu_t = 0.0
			var ev := InputEventKey.new()
			ev.pressed = true
			ev.keycode = KEY_ENTER
			Input.parse_input_event(ev)


func _process(delta: float) -> bool:
	if _done:
		return false
	_t += delta
	if mode == "menu" and _menu_stage < 2:
		_drive_menu(delta)
	if main == null and current_scene != null and current_scene.name == "Main":
		main = current_scene
	if main == null and mode != "direct":
		var n := root.get_node_or_null("Main")
		if n:
			main = n
	var ready_world := false
	if main != null and is_instance_valid(main) and "terrain" in main and main.terrain != null:
		ready_world = main.terrain.loaded_count() > 8
	if ready_world and _world_t < 0.0:
		_world_t = _t
		print("BOOT_WORLD at %.1fs" % _t)
	if _world_t >= 0.0 and _t - _world_t >= secs:
		_done = true
		print("BOOT_OK")
		_shutdown()
	elif _t > 240.0:
		_done = true
		print("BOOT_TIMEOUT")
		_shutdown(3)
	return false


func _shutdown(code := 0) -> void:
	if main and is_instance_valid(main):
		main.queue_free()
	for i in 10:
		await process_frame
	quit(code)
