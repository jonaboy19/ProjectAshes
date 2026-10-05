extends RefCounted
## The hand-tuned Rift near Thornfield (F9). Reads data/region1/world/thornfield_rift.json and returns a layout
## dictionary in exactly the shape dungeon_gen.gd's generate() returns, so dungeon_build.gd, dungeon_root.gd,
## dungeon_thing.gd and the exploration module's persistence (looted chests, opened gates, killed creatures,
## boss_dead) work on it unchanged. Not procedural: rooms, corridors, creatures, chests, lights and the lever
## gate all come from the file. No nodes, no autoloads; tests call generate().
##
## Route (rooms): 0 camp (safe, nothing hostile) -> 1 gallery -> 2 weeping hall (vents, the lever) -> 3 shard nave
## -> [Shardglass Door, a lever gate: the lever is on the entrance side] -> 4 arena (mini-boss).
## Extra content keys beyond dungeon_gen's: content["camp"] (fire, quartermaster, bed cells), content["hazards"]
## (vent positions), content["vent"] (timings), content["safe_rooms"], content["route"].

const Gen := preload("res://scripts/interiors/dungeon_gen.gd")
const PATH := "res://data/region1/world/thornfield_rift.json"
const CELL := Gen.CELL

static var _data: Dictionary = {}                 # path -> parsed file
static var _layout: Dictionary = {}               # path -> built layout


static func data(path := PATH) -> Dictionary:
	if not _data.has(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_data[path] = d if d is Dictionary else {}
	return _data[path]


static func dungeon_id(path := PATH) -> String:
	return String(data(path).get("id", "thornfield_rift"))


## The cached layout of a hand-tuned file (built once; callers must not mutate it). The default is the Rift.
static func layout(path := PATH) -> Dictionary:
	if not _layout.has(path):
		_layout[path] = generate(path)
	return _layout[path]


static func cell_pos(side: int, x: float, y: float) -> Vector3:
	return Vector3((x - side * 0.5 + 0.5) * CELL, 0.0, (y - side * 0.5 + 0.5) * CELL)


## {pos, yaw, cell} for [cell x, cell y, dir x, dir y]: on the wall face, +Z facing into the room (gen's _pick_wall).
static func wall_spot(side: int, w: Array) -> Dictionary:
	var d := Vector3(float(w[2]), 0.0, float(w[3]))
	var pos := cell_pos(side, float(w[0]), float(w[1])) + d * (CELL * 0.5 - 0.35)
	var inward := -d
	return {"pos": pos, "yaw": atan2(inward.x, inward.z), "cell": Vector2i(int(w[0]), int(w[1]))}


static func generate(path := PATH) -> Dictionary:
	var D := data(path)
	var side := int(D["side"])
	var theme := String(D["theme"])
	var T: Dictionary = Gen.THEME[theme]
	var cells := PackedByteArray()
	cells.resize(side * side)
	var room_of := PackedInt32Array()
	room_of.resize(side * side)
	room_of.fill(-1)
	var rooms: Array[Dictionary] = []
	# --- rooms -----------------------------------------------------------------------------------
	for rd: Dictionary in D["rooms"]:
		var rr: Array = rd["rect"]
		var r := Rect2i(int(rr[0]), int(rr[1]), int(rr[2]), int(rr[3]))
		var chamfer := int(rd.get("chamfer", 0))
		for z in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var ex := mini(x - r.position.x, r.end.x - 1 - x)
				var ez := mini(z - r.position.y, r.end.y - 1 - z)
				if ex + ez < chamfer:
					continue
				cells[z * side + x] = Gen.ROOM
				room_of[z * side + x] = int(rd["id"])
		rooms.append({"id": int(rd["id"]), "rect": r, "center": r.position + r.size / 2, "role": _gen_role(String(rd["role"])), "deg": 0,
			"name": String(rd["name"]), "safe": bool(rd.get("safe", false))})
	# --- corridors ---------------------------------------------------------------------------------
	var edges: Array[Dictionary] = []
	for cd: Dictionary in D["corridors"]:
		var pts: Array[Vector2i] = []
		for p: Array in cd["path"]:
			pts.append(Vector2i(int(p[0]), int(p[1])))
		var cells_path := _carve(cells, side, pts, int(cd["width"]))
		edges.append({"a": int(cd["a"]), "b": int(cd["b"]), "loop": false, "gate": int(cd.get("gate", -1)), "path": cells_path,
			"leaf": int(cd["b"]) if cd.has("gate") else -1})
		rooms[int(cd["a"])]["deg"] += 1
		rooms[int(cd["b"])]["deg"] += 1
	# --- gates -------------------------------------------------------------------------------------
	var gates: Array[Dictionary] = []
	for gd: Dictionary in D.get("gates", []):
		var gc: Array = gd["cell"]
		gates.append({"id": int(gd["id"]), "cell": Vector2i(int(gc[0]), int(gc[1])), "axis": String(gd["axis"]), "kind": String(gd["kind"]),
			"room": int(gd["room"]), "solver_room": int(gd["solver_room"]), "fact": "cave:%s:rune%d" % [String(D["id"]), int(gd["id"])],
			"key": "g%d" % int(gd["id"]), "name": String(gd.get("name", "Sealed door"))})
		rooms[int(gd["room"])]["role"] = "boss"
	# --- content -----------------------------------------------------------------------------------
	var content := {"creatures": [], "chests": [], "nodes": [], "lore": [], "plates": [], "traps": [], "levers": [], "lights": [],
		"clutter": [], "runes": [], "props": []}
	var uid := 0
	var ex_cell: Array = D["exit"]["cell"]
	var ex_dir: Array = D["exit"]["dir"]
	var exit_spot := wall_spot(side, [ex_cell[0], ex_cell[1], ex_dir[0], ex_dir[1]])
	content["exit"] = {"pos": exit_spot["pos"], "yaw": exit_spot["yaw"]}
	var el := String(D.get("element", ""))
	var lv: Array = D["level"]
	for c: Dictionary in D.get("creatures", []):
		var cc: Array = c["cell"]
		content["creatures"].append({"id": String(c["id"]), "kind": String(c["kind"]), "pos": cell_pos(side, float(cc[0]), float(cc[1])), "room": int(c["room"]),
			"level": int(c["level"]), "asleep": bool(c.get("asleep", false)), "boss": false, "yaw": float(int(String(c["id"]).hash()) % 628) / 100.0, "element": el})
	var boss_room := -1
	if D.has("boss"):
		var b: Dictionary = D["boss"]
		var bc: Array = b["cell"]
		content["creatures"].append({"id": String(b["id"]), "kind": String(b["kind"]), "pos": cell_pos(side, float(bc[0]), float(bc[1])), "room": int(b["room"]),
			"level": int(b["level"]), "asleep": true, "boss": true, "name": String(b["name"]), "scale": float(b["scale"]), "trophy": String(b["trophy"]),
			"yaw": 0.0, "element": el, "hp_mul": float(b["hp_mul"])})
		content["boss"] = {"id": String(b["id"]), "kind": String(b["kind"]), "name": String(b["name"]), "trophy": String(b["trophy"]), "room": int(b["room"]),
			"level": int(b["level"]), "tier": int(D["tier"]), "theme": theme}
		content["boss_loot"] = _loot(b["loot"])
		boss_room = int(b["room"])
	for k: Dictionary in D.get("chests", []):
		var ws := wall_spot(side, k["wall"])
		content["chests"].append({"id": String(k["id"]), "pos": ws["pos"], "yaw": ws["yaw"], "tier": int(k["tier"]), "room": int(k["room"]),
			"vault": bool(k["vault"]), "label": String(k["label"]), "loot": _loot(k["loot"])})
	for n: Dictionary in D.get("nodes", []):
		var wn := wall_spot(side, n["wall"])
		var inward := Vector3(sin(float(wn["yaw"])), 0, cos(float(wn["yaw"])))
		content["nodes"].append({"id": String(n["id"]), "kind": String(n["kind"]), "pos": (wn["pos"] as Vector3) + inward * 0.3, "yaw": float(wn["yaw"]),
			"room": int(n["room"]), "count": int(n["count"]), "needs_pick": bool(n["needs_pick"])})
	for j: Dictionary in D.get("lore", []):
		var jc: Array = j["cell"]
		content["lore"].append({"id": String(j["id"]), "pos": cell_pos(side, float(jc[0]), float(jc[1])), "yaw": 0.0, "room": int(j["room"]),
			"title": String(j["title"]), "text": String(j["text"]), "fact": String(j["fact"]), "fact_text": String(j["text"]), "kind": String(j["kind"])})
	for l: Dictionary in D.get("levers", []):
		var lc: Array = l["cell"]
		content["levers"].append({"id": String(l["id"]), "gate": int(l["gate"]), "pos": cell_pos(side, float(lc[0]), float(lc[1])), "room": int(l["room"])})
	var hazards: Array = []
	for h: Dictionary in D.get("hazards", []):
		var hc: Array = h["cell"]
		hazards.append({"id": String(h["id"]), "kind": String(h["kind"]), "pos": cell_pos(side, float(hc[0]), float(hc[1])), "room": int(h["room"])})
	content["hazards"] = hazards
	content["vent"] = (D.get("vent", {}) as Dictionary).duplicate()
	# lights
	for li: Dictionary in D.get("lights", []):
		uid += 1
		var kind := String(li["kind"])
		var entry := {"id": "t%d" % uid, "kind": kind, "room": int(li["room"])}
		if li.has("cell"):
			var c2: Array = li["cell"]
			entry["pos"] = cell_pos(side, float(c2[0]), float(c2[1]))
			entry["yaw"] = 0.0
		else:
			var w2 := wall_spot(side, li["wall"])
			entry["pos"] = w2["pos"]
			entry["yaw"] = w2["yaw"]
		match kind:
			"crystal":
				entry["color"] = Color(0.7, 0.4, 1.0)
				entry["range"] = 10.0
				entry["energy"] = 2.4
			"brazier":
				entry["color"] = Color(1.0, 0.72, 0.42)
				entry["range"] = 11.0
				entry["energy"] = 1.7
			"lantern":
				entry["color"] = Color(1.0, 0.62, 0.30)
				entry["range"] = 9.0
				entry["energy"] = 1.5
			_:
				entry["color"] = Color(1.0, 0.58, 0.28)
				entry["range"] = 12.0
				entry["energy"] = 1.9
		if li.has("color"):
			var col: Array = li["color"]
			entry["color"] = Color(float(col[0]), float(col[1]), float(col[2]))
			entry["range"] = float(li.get("range", entry["range"]))
			entry["energy"] = float(li.get("energy", entry["energy"]))
		content["lights"].append(entry)
	# the camp: lanterns, a free torch, crates (the Rift has one; a nook has lanterns of its own in "lights")
	if D.has("camp"):
		var camp: Dictionary = D["camp"]
		for lan: Array in camp["lanterns"]:
			uid += 1
			var wl := wall_spot(side, lan)
			content["lights"].append({"id": "t%d" % uid, "kind": "lantern", "pos": wl["pos"], "yaw": wl["yaw"], "color": Color(1.0, 0.62, 0.30),
				"range": 9.0, "energy": 1.5, "room": 0})
		var tc := wall_spot(side, camp["torch_cache"])
		content["props"].append({"id": "p1", "kind": "torch_cache", "pos": tc["pos"], "yaw": tc["yaw"], "room": 0})
		for cl: Array in camp["clutter"]:
			content["clutter"].append({"kind": String(cl[0]), "pos": cell_pos(side, float(cl[1]), float(cl[2])), "yaw": float(cl[1]) * 1.7, "scale": 1.0, "room": 0})
		var fire: Array = camp["fire"]
		var qm: Array = camp["quartermaster"]
		var bed: Array = camp["bed"]
		content["camp"] = {"fire": cell_pos(side, float(fire[0]), float(fire[1])), "quartermaster": cell_pos(side, float(qm[0]), float(qm[1])),
			"bed": cell_pos(side, float(bed[0]), float(bed[1]))}
	for cl2: Array in D.get("clutter", []):
		content["clutter"].append({"kind": String(cl2[0]), "pos": cell_pos(side, float(cl2[1]), float(cl2[2])), "yaw": float(cl2[1]) * 2.3, "scale": float(cl2[3]),
			"room": int(room_of[int(float(cl2[2])) * side + int(float(cl2[1]))])})
	content["safe_rooms"] = D.get("safe_rooms", [0] if D.has("camp") else [])
	content["route"] = D.get("route", [0, 1, 2, 3, 4])
	var spawn_cell := Vector2i(int(ex_cell[0]), int(ex_cell[1]))
	var level_min := int(lv[0])
	var level_max := int(lv[1])
	return {"id": String(D["id"]), "seed": int(D["seed"]), "theme": theme, "tier": int(D["tier"]), "level_min": level_min, "level_max": level_max,
		"name": String(D["name"]), "w": side, "h": side, "cells": cells, "room_of": room_of, "rooms": rooms, "edges": edges, "gates": gates,
		"spawn": cell_pos(side, float(spawn_cell.x), float(spawn_cell.y)), "spawn_cell": spawn_cell, "boss_room": boss_room, "content": content,
		"organic": bool(D["organic"]), "height": D["height"], "tint": T["tint"], "ambient": T["ambient"], "fog": T["fog"], "dark": bool(D.get("dark", true)),
		"light_kind": T["light"], "hand_tuned": true}


static func _gen_role(r: String) -> String:
	match r:
		"entrance":
			return "entrance"
		"boss":
			return "boss"
	return "chamber"


static func _loot(list: Array) -> Array:
	var out: Array = []
	for e: Array in list:
		out.append([String(e[0]), int(e[1])])
	return out


static func _carve(cells: PackedByteArray, side: int, pts: Array[Vector2i], width: int) -> Array:
	var path: Array = []
	for i in range(pts.size() - 1):
		var p: Vector2i = pts[i]
		var q: Vector2i = pts[i + 1]
		var step := Vector2i(signi(q.x - p.x), signi(q.y - p.y))
		if step == Vector2i.ZERO:
			continue
		var cur := p
		while cur != q:
			if path.is_empty() or path[path.size() - 1] != cur:
				path.append(cur)
			cur += step
		if path[path.size() - 1] != q:
			path.append(q)
	for c: Vector2i in path:
		for dx in range(width):
			for dz in range(width):
				var x := c.x + dx
				var z := c.y + dz
				if x < 1 or z < 1 or x >= side - 1 or z >= side - 1:
					continue
				if cells[z * side + x] == Gen.ROCK:
					cells[z * side + x] = Gen.CORR
	return path


## The shortest chain of rooms from `a` to `b` over the corridor graph (room ids), [] when not connected.
static func room_path(g: Dictionary, a: int, b: int) -> Array:
	var prev := {a: -1}
	var queue := [a]
	while not queue.is_empty():
		var cur: int = queue.pop_front()
		if cur == b:
			break
		for e: Dictionary in g["edges"]:
			var nxt := -1
			if int(e["a"]) == cur:
				nxt = int(e["b"])
			elif int(e["b"]) == cur:
				nxt = int(e["a"])
			if nxt >= 0 and not prev.has(nxt):
				prev[nxt] = cur
				queue.append(nxt)
	if not prev.has(b):
		return []
	var out: Array = []
	var at := b
	while at != -1:
		out.push_front(at)
		at = int(prev[at])
	return out


## Room id at a layout-local position, -1 outside every room.
static func room_at(g: Dictionary, p: Vector3) -> int:
	var c := Gen.cell_at(g, p)
	var side := int(g["w"])
	if c.x < 0 or c.y < 0 or c.x >= side or c.y >= side:
		return -1
	return int((g["room_of"] as PackedInt32Array)[c.y * side + c.x])
