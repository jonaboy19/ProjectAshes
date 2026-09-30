extends Node
const FG := preload("res://scripts/world/towers/floor_gen.gd")
const TowerData := preload("res://scripts/world/towers/tower_data.gd")
var out_dir := "/tmp/claude-0/shots/towers"
var floors := [1, 2, 3, 4, 5, 6]
var cam: Camera3D
var holder: Node3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_dir = a.substr(6)
		elif a.begins_with("--floors="):
			floors = []
			for x in a.substr(9).split(",", false):
				floors.append(int(x))
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _save(name: String) -> void:
	await _wait(4)
	var img := get_tree().root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("SAVED ", name, " draws=", get_tree().root.get_viewport().get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME))


func _run() -> void:
	holder = Node3D.new()
	add_child(holder)
	cam = Camera3D.new()
	cam.far = 400.0
	holder.add_child(cam)
	cam.current = true
	for f in floors:
		var L := FG.layout("ashfall_spire", f)
		var b := FG.build(L)
		holder.add_child(b["root"])
		cam.environment = FG.environment(String(L["theme"]))
		var sun := DirectionalLight3D.new()
		sun.light_energy = 0.0
		var start := FG.cell_center(L["start"])
		var m := FG.open_mask(L, L["start"])
		var dir := Vector3(1, 0, 0) if (m & FG.E) else Vector3(0, 0, 1)
		cam.global_position = start + Vector3(-2.0, 2.4, -2.0) - dir * 1.5 * 0.0
		cam.look_at(start + dir * 16.0 + Vector3(0, 1.3, 0))
		cam.fov = 72.0
		await _wait(20)
		await _save("fl_%02d_%s" % [f, L["theme"]])
		# safe room
		var sp := FG.cell_center(L["safe_cell"])
		var sm := FG.open_mask(L, L["safe_cell"])
		var sd := Vector3.ZERO
		for d in 4:
			if sm & FG.BITS[d]:
				sd = Vector3(FG.DIRS[d].x, 0, FG.DIRS[d].y)
		cam.global_position = sp + sd * 3.4 + Vector3(0, 2.3, 0) + Vector3(sd.z, 0, sd.x).abs() * 0.0
		cam.look_at(sp + Vector3(0, 0.8, 0))
		await _wait(10)
		if f == 1 or f == 6:
			await _save("fl_%02d_safe" % f)
		# boss arena from the door
		var dp := FG.door_pos(L)
		var dd: int = L["door_dir"]
		var door_dir := Vector3(FG.DIRS[dd].x, 0, FG.DIRS[dd].y)
		var arena := FG.cell_center(L["boss_cell"])
		cam.global_position = dp + door_dir * 4.0 + Vector3(0, 2.6, 0)
		cam.look_at(arena + Vector3(0, 2.0, 0))
		if f == 1 or f == 6:
			# open the door for the view
			FG.open_door(b["door"])
			await _wait(10)
			await _save("fl_%02d_arena" % f)
		# the door from outside
		cam.global_position = dp - door_dir * 6.5 + Vector3(0, 2.3, 0)
		cam.look_at(dp + Vector3(0, 3.0, 0))
		FG.close_door(b["door"])
		await _wait(10)
		if f == 1 or f == 4:
			await _save("fl_%02d_door" % f)
		(b["root"] as Node3D).queue_free()
		await _wait(2)
	print("FLOOR SHOTS DONE")
	get_tree().quit(0)
