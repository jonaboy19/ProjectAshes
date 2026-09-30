extends SceneTree
## Captures the in-game world map (standalone + Map tab) for docs/ui/world_map/.
##   Godot --path kingdom --resolution 2400x1080 -s res://tools_qa/map/map_capture.gd -- --adult --out=<dir> --tag=wide
## Never pass --headless. Runs ~700 frames, then quits (also guarded by a wall-clock watchdog).

var out_dir := ""
var tag := "wide"
var frame := 0
var hud: Node
var wm: Control
var t0 := 0
var perf_t := 0
var use_layer := false
var fc := Vector2.ZERO
var fz := 0.0
var no_fog := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_dir = a.substr(6)
		elif a.begins_with("--tag="): tag = a.substr(6)
		elif a == "--layer": use_layer = true
		elif a == "--nofog": no_fog = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	t0 = Time.get_ticks_msec()
	var ps := load("res://scenes/main.tscn") as PackedScene
	root.add_child.call_deferred(ps.instantiate())


func _find_hud(n: Node) -> Node:
	if n.has_method("show_menu") and n.has_method("toggle_map"):
		return n
	for c in n.get_children():
		var r := _find_hud(c)
		if r: return r
	return null


func _focus(p: Vector2, z: float) -> void:
	fc = p
	fz = z
	wm.call("focus_on", p, z)


func _shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var p := "%s/%s_%s.png" % [out_dir, name, tag]
	img.save_png(p)
	print("SAVED ", p, " ", img.get_size())


func _process(_dt: float) -> bool:
	frame += 1
	if frame > 905 and frame < 1115 and wm != null and not wm.visible:
		print("map was closed by the game, reopening at frame ", frame)
		wm.call("open")
		if fz > 0.0:
			_focus(fc, fz)
	if Time.get_ticks_msec() - t0 > 420000:
		print("WATCHDOG quit")
		quit(1)
		return true
	if frame == 900:
		hud = _find_hud(root)
		if hud == null:
			print("NO HUD"); quit(1); return true
		wm = hud.get("world_map")
		print("hud ok, map baked=", wm.call("is_baked"))
		if use_layer:
			var L := load("res://scripts/ui/map_parchment_layer.gd")
			var lay: Control = L.new()
			wm.call("add_layer", lay)
			lay.set("fog_enabled", not no_fog)
		wm.set("discovery", hud.call("get_discovery"))
		wm.call("open")
	elif frame == 940 and not wm.call("is_baked"):
		frame = 939     # wait for the bake
		return false
	elif frame == 1000:
		_shot("01_full")
		perf_t = Time.get_ticks_msec()
	elif frame > 1000 and frame < 1060 and perf_t > 0 and frame <= 1004:
		wm.queue_redraw()
	elif frame == 1005:
		print("PERF 5 forced-redraw frames ms=", Time.get_ticks_msec() - perf_t)
		_focus(Vector2(0, 0), 0.5)
	elif frame == 1015:
		_shot("02_zoom_ashford")
		_focus(Vector2(560, -420), 0.7)
	elif frame == 1025:
		_shot("03_zoom_kingsreach")
		# marker + tapped place card
		_focus(Vector2(280, -200), 0.3)
		wm.call("place_marker", Vector2(120, -300))
		var disc: RefCounted = wm.get("discovery")
		for pl in disc.places:
			if String(pl["name"]) == "Kingsreach":
				wm.call("_select", pl)
	elif frame == 1040:
		_shot("04_marker_card")
		# reveal everything, full view: the "all discovered" look
		var disc2: RefCounted = wm.get("discovery")
		for pl in disc2.places:
			disc2.discover(pl["id"], 1)
		wm.call("_select", {})
		wm.call("refresh")
		wm.call("fit_region")
	elif frame == 1060:
		_shot("05_full_all_discovered")
		_focus(Vector2(0, 0), 0.16)
	elif frame == 1070:
		_shot("06_mid_all_discovered")
		wm.call("close")
		wm.set("discovery", hud.call("get_discovery"))
		wm.call("open") if false else null
		var GM := load("res://scripts/ui/gamemenu/game_menu.gd")
		GM.call("open", hud, "map")
	elif frame == 1120:
		_shot("07_menu_map_tab")
	elif frame == 1130:
		quit(0)
		return true
	return false
