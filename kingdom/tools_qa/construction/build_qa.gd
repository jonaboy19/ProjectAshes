extends Node
## QA driver for the construction system: godot --path kingdom -- --shot=none --qa=res://tools_qa/construction/build_qa.gd
## Saves /tmp/claude-0/shots/build_*.png (gathering, ghost, site stages with workers, menu tiers, finished upgrade).

const D := preload("res://scripts/realm/construction_data.gd")
const OUT := "/tmp/claude-0/shots/build_%s.png"
var main: Node
var cons: RefCounted
var spot := Vector2.ZERO


func _shot(name: String, wait := 1.0) -> void:
	await get_tree().create_timer(wait).timeout
	var img := main.get_viewport().get_texture().get_image()
	img.save_png(OUT % name)
	print("saved ", name)


var cam: Camera3D


func _look(from: Vector2, at: Vector2, pitch := -0.25) -> void:
	main.call("_teleport", from, 0.0)
	var d := at - from
	main.player.set_camera(atan2(-d.x, -d.y), pitch)
	main.player.visible = false
	if cam == null:
		cam = Camera3D.new()
		cam.fov = 60.0
		main.world.add_child(cam)
	var gy := WorldGen.height(from.x, from.y) + 2.6
	cam.global_position = Vector3(from.x, gy + 1.5, from.y)
	cam.look_at(Vector3(at.x, WorldGen.height(at.x, at.y) + 1.5, at.y))
	cam.current = true
	main.terrain.focus = main.player.global_position
	main.terrain.build_all_now()
	main.region.focus = main.player.global_position
	main.region.build_all_now()


func _flat() -> Vector2:
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	for r in range(180, 700, 40):
		for a in range(0, 360, 20):
			var p := home + Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a))) * r
			var ok := true
			for i in 9:
				if cons.can_place_here("keep", p + Vector2(13.0 * i, 0), 0.0) != "":
					ok = false
					break
			if ok:
				return p
	return Vector2.INF


func _at(i: int, row := 0) -> Vector2:
	return spot + Vector2(13.0 * i, 0) + Vector2(0, 0)


func _force(kind: String, p: Vector2, yaw := 0.0) -> int:
	var r: Dictionary = cons.place(kind, p, yaw)
	if not bool(r["ok"]):
		print("FORCE FAIL ", kind, " ", r["reason"])
		return 0
	var s: Dictionary = cons.sites[int(r["id"])]
	for item: String in s["need"]:
		s["have"][item] = s["need"][item]
	cons._complete(s)
	return int(r["id"])


func _site(kind: String, p: Vector2, frac: float, crew: int, haulers := 0, yaw := 0.0) -> int:
	var r: Dictionary = cons.place(kind, p, yaw)
	if not bool(r["ok"]):
		print("SITE FAIL ", kind, " ", r["reason"])
		return 0
	var id := int(r["id"])
	var s: Dictionary = cons.sites[id]
	for item: String in s["need"]:
		s["have"][item] = s["need"][item] if frac > 0.6 else int(ceil(s["need"][item] * 0.6))
	s["progress"] = float(s["total"]) * frac
	for i in crew:
		var w: Dictionary = cons._new_worker("hired", ["Osric", "Mabel", "Master Hale", "Wren"][i % 4], 0.8 if i == 2 else 0.35, 4, "build")
		cons._attach(w, id)
	for i in haulers:
		var h: Dictionary = cons._new_worker("hired", "Carter %d" % i, 0.3, 3, "haul")
		cons._attach(h, id)
	return id


func run(m: Node) -> void:
	main = m
	cons = Life.realm.mod("construction")
	await get_tree().create_timer(1.0).timeout
	WorldSim.time_of_day = 10.0
	m.hud.visible = false
	for item: String in D.MATERIALS:
		Life.give(item, 200)
	Life.give("wood_axe", 1)
	Game.add_gold(500)
	# --- 1 gathering: a shore with clay and reeds, trees and rocks about
	var br: Node3D = m.build_resources
	var home: Vector2 = WorldGen.settlements[0]["pos"]
	var best := Vector2.INF
	var best_score := -1
	for r in range(150, 800, 50):
		for a in range(0, 360, 12):
			var p := home + Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a))) * r
			var have := {}
			for dx in range(-2, 3):
				for dz in range(-2, 3):
					var c := Vector2i(floori(p.x / D.NODE_CELL) + dx, floori(p.y / D.NODE_CELL) + dz)
					var info: Dictionary = cons.node_cell(c)
					if bool(info["ok"]):
						have[String(info["kind"])] = int(have.get(String(info["kind"]), 0)) + 1
			var slope := absf(WorldGen.height(p.x + 8, p.y) - WorldGen.height(p.x - 8, p.y)) + absf(WorldGen.height(p.x, p.y + 8) - WorldGen.height(p.x, p.y - 8))
			if slope > 3.0:
				continue
			var score := have.size() * 10 + int(have.get("clay", 0)) + int(have.get("reeds", 0))
			if score > best_score:
				best_score = score
				best = p
	print("kind scan best ", best, " score ", best_score)
	var stand := best
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			var c := Vector2i(floori(best.x / D.NODE_CELL) + dx, floori(best.y / D.NODE_CELL) + dz)
			var info: Dictionary = cons.node_cell(c)
			if bool(info["ok"]) and String(info["kind"]) in ["tree", "rock"]:
				stand = Vector2(info["pos"].x, info["pos"].z)
	_look(stand + Vector2(3, 11), stand, -0.2)
	br.focus = m.player.global_position
	br.refresh(stand)
	await get_tree().create_timer(1.0).timeout
	var sp: Variant = null
	for s in br._active.values():
		if String(s.kind) in ["tree", "rock"]:
			sp = s
			break
	if sp != null:
		for _i in 3:
			br._last_strike = -1000
			br.strike(sp)
			await get_tree().create_timer(0.2).timeout
	print("inventory logs ", Life.count("log"), " stone ", Life.count("stone"))
	await _shot("gather", 1.0)
	# --- 2 ghost
	spot = _flat()
	print("flat spot ", spot)
	if spot == Vector2.INF:
		get_tree().quit()
		return
	_force("campfire", _at(0))
	_force("storage_pile", _at(1))
	_look(_at(3) + Vector2(-9, 12), _at(3), -0.3)
	m.hud.visible = true
	var BuildMenu := load("res://scripts/ui/build_menu.gd")
	var menu: Control = BuildMenu.open_for(m.hud)
	menu.call("set_mode", "settle")
	var cp: RefCounted = menu._cp
	cp.tier = 1
	menu.call("_refresh_list")
	cp.begin_place("hut")
	cp.dragged = true
	cp._pos = _at(3)
	await _shot("ghost", 1.2)
	# --- 3 menu tiers
	cp.cancel_place()
	cp.tier = 2
	menu.call("_refresh_list")
	await _shot("menu_tier2", 0.6)
	cp.tier = 1
	menu.call("_refresh_list")
	await _shot("menu_tier1", 0.6)
	menu.call("close")
	# --- 4 three stages with workers
	m.hud.visible = false
	var a := _site("hut", _at(3), 0.2, 2, 1)
	var b := _site("hut", _at(4), 0.55, 3, 1)
	var c2 := _site("hut", _at(5), 0.9, 2)
	_look(_at(4) + Vector2(2, 20), _at(4), -0.22)
	m.construction_view.focus = m.player.global_position
	m.construction_view.build_all_now()
	await get_tree().create_timer(4.0).timeout
	await _shot("stages", 1.0)
	_look(_at(3) + Vector2(-7, 9), _at(3) + Vector2(1, 0), -0.25)
	m.construction_view.build_all_now()
	await _shot("stages_close", 2.0)
	# --- 5 site panel
	m.hud.visible = true
	var menu2: Control = BuildMenu.open_for(m.hud)
	menu2.call("show_site", b)
	await _shot("site_panel", 0.8)
	menu2.call("close")
	# --- 6 finished upgrade: hut -> timber house
	m.hud.visible = false
	cons.known["build:carpentry"] = true
	var hut := _force("hut", _at(8))
	var wb := _force("workbench", _at(6))
	var sh := _force("sawhorse", _at(7))
	print("bench ", wb, " saw ", sh)
	var up: Dictionary = cons.upgrade(hut, "timber_house")
	print("upgrade ", up)
	if bool(up["ok"]):
		var us: Dictionary = cons.sites[int(up["id"])]
		for item: String in us["need"]:
			us["have"][item] = us["need"][item]
		us["progress"] = float(us["total"]) * 0.6
		var w: Dictionary = cons._new_worker("hired", "Master Hale", 0.8, 14, "build")
		cons._attach(w, int(up["id"]))
		_look(_at(8) + Vector2(-8, 11), _at(8), -0.25)
		m.construction_view.build_all_now()
		await _shot("upgrade_mid", 2.0)
		cons.advance(200, {})
		m.construction_view.build_all_now()
		await _shot("upgrade_done", 1.5)
	get_tree().quit()
