extends RefCounted
## Labyrinth floor generator (Aincrad-style multi-floor dungeons). Pure data from a seed (no nodes, no autoloads, no scene
## access), so it is deterministic and unit-testable headless (tests/test_labyrinth.gd); labyrinth_build.gd turns a layout
## into placeholder geometry + a nav mesh and labyrinth_state.gd tracks what the player has cleared.
##
## generate_floor(labyrinth_id, world_seed, f, opts) -> Dictionary (f is the 0-based floor index):
##   labyrinth, seed, floor (f), number (f + 1), floors, theme, tier, level, w, h (grid cells of CELL m), cells
##   (PackedByteArray: ROCK ROOM CORR PILLAR DOOR), room_of (PackedInt32Array, -1 = none), rooms[], edges[], doors
##   (Vector2i -> edge index), path (room ids start -> safe -> mid-boss -> boss), start_room, safe_room, midboss_room,
##   boss_room, stairs_up, stairs_down, warp_cell, content {creatures, traps, chests, lights, boss, midboss, secrets}.
## Local coordinates: metres, the grid is centred on the origin, floor at y = 0 (cell_to_local()).
##
## Structure rules: the critical chain start -> combat rooms -> SAFE ROOM -> combat -> MID-BOSS -> combat -> BOSS is built
## room by room, so the path exists by construction; the boss room has exactly one entrance, a big door that stays shut until
## the mid-boss is dead; side rooms (treasure, traps, extra combat) hang off the chain; secret rooms sit behind a hidden door
## (searched, or found by a loose-brick tell) and are never needed for progress; loops add shortcuts. Corridors are routed
## around every room box with a one-cell ring, so a corridor touches a room only at its own door.

const Data := preload("res://scripts/dungeon/labyrinth_data.gd")
const Loot := preload("res://scripts/interiors/dungeon_gen.gd")

const CELL := 3.0
const ROCK := 0
const ROOM := 1
const CORR := 2
const PILLAR := 3
const DOOR := 4

const GAP := 3                  # free cells kept between any two room boxes
const MAX_ATTEMPTS := 80
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const ADJ_WORDS := ["Gatekeeper", "Warden", "Chieftain", "Ravager", "Overseer", "Stalker"]


# ---------------------------------------------------------------------------------------------
# public API

static func floor_seed(labyrinth_id: String, world_seed: int, f: int) -> int:
	var salt: int = int(Data.DEFS[labyrinth_id]["seed_salt"]) if Data.DEFS.has(labyrinth_id) else 1
	return _mix(_mix(_mix(world_seed, salt), f + 1), 0x51ED)


static func cell_to_local(layout: Dictionary, c: Vector2i) -> Vector3:
	return Vector3((float(c.x) + 0.5 - float(layout["w"]) * 0.5) * CELL, 0.0, (float(c.y) + 0.5 - float(layout["h"]) * 0.5) * CELL)


static func local_to_cell(layout: Dictionary, p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL + float(layout["w"]) * 0.5)), int(floor(p.z / CELL + float(layout["h"]) * 0.5)))


static func is_passable(layout: Dictionary, c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= int(layout["w"]) or c.y >= int(layout["h"]):
		return false
	var k: int = (layout["cells"] as PackedByteArray)[c.y * int(layout["w"]) + c.x]
	return k == ROOM or k == CORR or k == DOOR


## Generate floor `f` (0-based) of labyrinth `labyrinth_id`. Same arguments, same layout, always.
## opts: "def" (Dictionary, overrides the labyrinth definition; tests use it for odd floor counts).
static func generate_floor(labyrinth_id: String, world_seed: int, f: int, opts := {}) -> Dictionary:
	var def: Dictionary = opts.get("def", Data.def_of(labyrinth_id))
	assert(not def.is_empty(), "unknown labyrinth %s" % labyrinth_id)
	var base := floor_seed(labyrinth_id, world_seed, f)
	var grow := 0
	var last: Dictionary = {}
	for attempt in MAX_ATTEMPTS:
		if attempt > 0 and attempt % 8 == 0:
			grow += 8
		var rng := RandomNumberGenerator.new()
		rng.seed = _mix(base, attempt + 1)
		var layout := _attempt(rng, def, labyrinth_id, world_seed, f, grow)
		if layout.is_empty():
			continue
		layout["attempt"] = attempt
		var problems := validate(layout)
		if problems.is_empty():
			_fill_content(rng, layout, def)
			return layout
		last = layout
	push_error("labyrinth %s seed %d floor %d: no valid layout in %d attempts (%s)" % [labyrinth_id, world_seed, f, MAX_ATTEMPTS, str(validate(last))])
	return {}


## Problems with a layout (empty = fine). Used by the generator to reject an attempt and by the tests.
static func validate(layout: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var rooms: Array = layout["rooms"]
	var w: int = layout["w"]
	var h: int = layout["h"]
	for i in rooms.size():
		var a: Dictionary = rooms[i]
		var ra := Rect2i(a["x"], a["y"], a["w"], a["h"])
		if ra.position.x < 2 or ra.position.y < 2 or ra.end.x > w - 2 or ra.end.y > h - 2:
			out.append("room %d out of bounds" % i)
		for j in range(i + 1, rooms.size()):
			var b: Dictionary = rooms[j]
			if ra.grow(GAP).intersects(Rect2i(b["x"], b["y"], b["w"], b["h"])):
				out.append("rooms %d and %d overlap" % [i, j])
	# everything reachable with the secret doors open; everything but the secret rooms with them shut
	var open_all := reachable(layout, {"secret": true, "boss_door": true})
	var open_main := reachable(layout, {"secret": false, "boss_door": true})
	for r: Dictionary in rooms:
		if not open_all.has(r["anchor"]):
			out.append("room %d unreachable" % r["id"])
		elif not r["secret"] and not open_main.has(r["anchor"]):
			out.append("room %d only behind a secret door" % r["id"])
		elif r["secret"] and open_main.has(r["anchor"]):
			out.append("secret room %d reachable without finding the door" % r["id"])
	# the boss is shut off until its door opens, and it is the only way in
	var shut := reachable(layout, {"secret": true, "boss_door": false})
	var boss: Dictionary = rooms[layout["boss_room"]]
	if shut.has(boss["anchor"]):
		out.append("boss room reachable around its door")
	if not open_main.has(boss["anchor"]):
		out.append("boss room unreachable")
	# critical order start -> safe -> mid-boss -> boss
	var path: Array = layout["path"]
	if path.size() < 4 or path[0] != layout["start_room"] or path[path.size() - 1] != layout["boss_room"]:
		out.append("bad critical path")
	return out


## Cells reachable from the arrival stairs. open: {"secret": bool, "boss_door": bool}; door cells of a closed kind block.
static func reachable(layout: Dictionary, open := {}) -> Dictionary:
	var seen := {}
	var start: Vector2i = layout["stairs_up"]
	var stack: Array[Vector2i] = [start]
	seen[start] = true
	var doors: Dictionary = layout["doors"]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for d in DIRS:
			var n := c + d
			if seen.has(n) or not is_passable(layout, n):
				continue
			if doors.has(n):
				var e: Dictionary = layout["edges"][doors[n]]
				if e["gate"] == n:
					if e["kind"] == "secret" and not open.get("secret", false):
						continue
					if e["kind"] == "boss_door" and not open.get("boss_door", false):
						continue
			seen[n] = true
			stack.append(n)
	return seen


## Room ids reachable with the given gates open, as a Dictionary id -> true.
static func rooms_reachable(layout: Dictionary, open := {}) -> Dictionary:
	var seen := reachable(layout, open)
	var out := {}
	for r: Dictionary in layout["rooms"]:
		if seen.has(r["anchor"]):
			out[r["id"]] = true
	return out


## One number that changes if anything in the layout or its content changes (determinism tests).
static func signature(layout: Dictionary) -> int:
	var cr: Array = []
	for c: Dictionary in layout["content"]["creatures"]:
		cr.append([c["kind"], c["cell"], c["level"]])
	var ch: Array = []
	for c: Dictionary in layout["content"]["chests"]:
		ch.append([c["cell"], c["loot"]])
	var tr: Array = []
	for t: Dictionary in layout["content"]["traps"]:
		tr.append([t["kind"], t["cell"]])
	var rm: Array = []
	for r: Dictionary in layout["rooms"]:
		rm.append([r["role"], r["template"], r["x"], r["y"], r["w"], r["h"]])
	return hash([layout["cells"], rm, cr, ch, tr, layout["stairs_up"], layout["stairs_down"], layout["content"]["boss"]["name"]])


# ---------------------------------------------------------------------------------------------
# one placement attempt

static func _attempt(rng: RandomNumberGenerator, def: Dictionary, lid: String, world_seed: int, f: int, grow: int) -> Dictionary:
	var floors: int = def["floors"]
	var theme_id: String = Data.theme_of(lid, f) if Data.DEFS.has(lid) else def["theme_cycle"][f % def["theme_cycle"].size()]
	var specs := _plan_rooms(rng, f)
	var w := clampi(28 + specs.size() * 4 + grow, 40, 120)
	var h := w
	# orient + size every room, then place
	for i in specs.size():
		var s: Dictionary = specs[i]
		s["id"] = i
		var tpl: Dictionary = Data.TEMPLATES[s["template"]]
		s["rows"] = _orient(tpl["rows"], rng.randi() % 8)
		s["w"] = (s["rows"][0] as String).length()
		s["h"] = (s["rows"] as Array).size()
		s["x"] = -1
		s["y"] = -1
	if not _place(rng, specs, w, h):
		return {}
	for s: Dictionary in specs:
		s["anchor"] = _anchor_cell(s)
	# edges: chain in order, then each side room to its anchor room
	var edges: Array = []
	for i in range(1, specs.size()):
		var s: Dictionary = specs[i]
		var other: int = s["link"]
		var kind := "open"
		if s["role"] == "boss":
			kind = "boss_door"
		elif s["secret"]:
			kind = "secret"
		elif rng.randf() < 0.5:
			kind = "door"
		edges.append({"id": edges.size(), "a": other, "b": i, "kind": kind, "cells": [], "loop": false, "gate": Vector2i(-1, -1)})
	# corridors
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, w, h)
	grid.cell_size = Vector2(1, 1)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	for s: Dictionary in specs:
		var ring := Rect2i(s["x"], s["y"], s["w"], s["h"]).grow(1)
		for y in range(ring.position.y, ring.end.y):
			for x in range(ring.position.x, ring.end.x):
				grid.set_point_solid(Vector2i(x, y), true)
	var corridor := {}
	var doors := {}
	for e: Dictionary in edges:
		if not _route(grid, specs, e, corridor, doors):
			return {}
	# loops: a few extra shortcuts between nearby ordinary rooms
	var loop_tries := 4
	for _t in loop_tries:
		var a: int = rng.randi() % specs.size()
		var b: int = rng.randi() % specs.size()
		if a == b or _skip_loop(specs[a]) or _skip_loop(specs[b]) or _linked(edges, a, b):
			continue
		if (specs[a]["anchor"] as Vector2i).distance_to(specs[b]["anchor"]) > 34.0 or rng.randf() > 0.55:
			continue
		var le := {"id": edges.size(), "a": a, "b": b, "kind": "open", "cells": [], "loop": true, "gate": Vector2i(-1, -1)}
		if _route(grid, specs, le, corridor, doors, 46):
			edges.append(le)
	# carve cells
	var cells := PackedByteArray()
	cells.resize(w * h)
	var room_of := PackedInt32Array()
	room_of.resize(w * h)
	room_of.fill(-1)
	for s: Dictionary in specs:
		var rows: Array = s["rows"]
		for ry in rows.size():
			var row: String = rows[ry]
			for rx in row.length():
				var idx := (int(s["y"]) + ry) * w + int(s["x"]) + rx
				var ch := row[rx]
				cells[idx] = PILLAR if (ch == "#" or ch == "L") else ROOM
				room_of[idx] = s["id"]
	for c: Vector2i in corridor:
		cells[c.y * w + c.x] = CORR
	for c: Vector2i in doors:
		cells[c.y * w + c.x] = DOOR
	var rooms: Array = []
	for s: Dictionary in specs:
		rooms.append({"id": s["id"], "role": s["role"], "template": s["template"], "rows": s["rows"], "x": s["x"], "y": s["y"],
			"w": s["w"], "h": s["h"], "anchor": s["anchor"], "secret": s["secret"], "side": s["side"], "link": s["link"]})
	var path: Array = []
	for s: Dictionary in specs:
		if not s["side"]:
			path.append(s["id"])
	var layout := {"labyrinth": lid, "seed": world_seed, "floor": f, "number": f + 1, "floors": floors, "theme": theme_id,
		"tier": Data.tier_for(f, floors), "level": Data.level_for(def, f), "w": w, "h": h, "cells": cells, "room_of": room_of,
		"rooms": rooms, "edges": edges, "doors": doors, "path": _critical_path(rooms), "start_room": 0, "safe_room": -1,
		"midboss_room": -1, "boss_room": -1, "exit_room": -1, "stairs_up": Vector2i.ZERO, "stairs_down": Vector2i.ZERO,
		"warp_cell": Vector2i.ZERO, "final": f + 1 >= floors}
	for r: Dictionary in rooms:
		match r["role"]:
			"safe":
				layout["safe_room"] = r["id"]
			"midboss":
				layout["midboss_room"] = r["id"]
			"boss":
				layout["boss_room"] = r["id"]
	# stairs + warp from template markers
	var up := _find_marker(rooms[0], "U")
	var down := _find_marker(rooms[layout["boss_room"]], "X")
	var warp := _find_marker(rooms[layout["safe_room"]], "A")
	if up.is_empty() or down.is_empty() or warp.is_empty():
		return {}
	layout["stairs_up"] = up[0]
	layout["stairs_down"] = down[0]
	layout["warp_cell"] = warp[0]
	return layout


## Specs in chain order (start ... boss) followed by side rooms. side rooms carry `link` = index of the room they hang off.
static func _plan_rooms(rng: RandomNumberGenerator, f: int) -> Array:
	var specs: Array = []
	specs.append(_spec("start", false, false))
	var before_safe := 1 + rng.randi() % 2
	var mid := 1 + rng.randi() % 2 + int(f / 5)
	var after_mid := 1 + rng.randi() % 2
	for _i in before_safe:
		specs.append(_spec("combat", false, false))
	specs.append(_spec("safe", false, false))
	for _i in mid:
		specs.append(_spec("combat", false, false))
	specs.append(_spec("midboss", false, false))
	for _i in after_mid:
		specs.append(_spec("combat", false, false))
	specs.append(_spec("boss", false, false))
	# chain links: each chain room hangs off the previous one
	for i in range(1, specs.size()):
		specs[i]["link"] = i - 1
	var chain_n := specs.size()
	var sides: Array[String] = []
	for _i in 1 + rng.randi() % 2:
		sides.append("treasure")
	for _i in 1 + rng.randi() % 2:
		sides.append("trap")
	for _i in rng.randi() % 3:
		sides.append("combat")
	sides.append("secret")
	if rng.randf() < 0.45:
		sides.append("secret")
	for role in sides:
		var s := _spec(role, true, role == "secret")
		# hang off a chain room that is neither the boss (single entrance) nor the safe room (keep it calm)
		var cand: Array[int] = []
		for i in chain_n - 1:
			if specs[i]["role"] != "safe":
				cand.append(i)
		s["link"] = cand[rng.randi() % cand.size()]
		specs.append(s)
	for s: Dictionary in specs:
		var pool: Array[String] = []
		for tid: String in Data.TEMPLATES:
			if (Data.TEMPLATES[tid]["roles"] as Array).has(s["role"]):
				pool.append(tid)
		pool.sort()
		s["template"] = pool[rng.randi() % pool.size()]
	return specs


static func _spec(role: String, side: bool, secret: bool) -> Dictionary:
	return {"role": role, "side": side, "secret": secret, "link": -1, "template": ""}


## Place rooms so that each sits GAP+ cells from every other and inside the grid. Linked rooms are put near their anchor room.
static func _place(rng: RandomNumberGenerator, specs: Array, w: int, h: int) -> bool:
	for i in specs.size():
		var s: Dictionary = specs[i]
		var placed := false
		for _try in 140:
			var px: int
			var py: int
			if i == 0:
				px = 3 + rng.randi() % maxi(1, int(w / 4))
				py = 3 + rng.randi() % maxi(1, h - 6 - int(s["h"]))
			else:
				var a: Dictionary = specs[s["link"]]
				var dir := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))
				if dir.length() < 0.3:
					dir = Vector2(1, 0)
				dir = dir.normalized()
				var reach := float(a["w"] + s["w"] + a["h"] + s["h"]) * 0.25 + float(GAP) + 3.0 + rng.randf() * 10.0
				var cx := float(a["x"]) + float(a["w"]) * 0.5 + dir.x * reach * 1.4
				var cy := float(a["y"]) + float(a["h"]) * 0.5 + dir.y * reach * 1.4
				px = int(round(cx - float(s["w"]) * 0.5))
				py = int(round(cy - float(s["h"]) * 0.5))
			var r := Rect2i(px, py, s["w"], s["h"])
			if r.position.x < 3 or r.position.y < 3 or r.end.x > w - 3 or r.end.y > h - 3:
				continue
			var clash := false
			for j in i:
				var o: Dictionary = specs[j]
				if r.grow(GAP + 1).intersects(Rect2i(o["x"], o["y"], o["w"], o["h"])):
					clash = true
					break
			if clash:
				continue
			s["x"] = px
			s["y"] = py
			placed = true
			break
		if not placed:
			return false
	return true


## Door cells (on each room's border) + an A* corridor between the two cells just outside them. Marks `corridor` / `doors`.
static func _route(grid: AStarGrid2D, specs: Array, e: Dictionary, corridor: Dictionary, doors: Dictionary, max_len := 100000) -> bool:
	var a: Dictionary = specs[e["a"]]
	var b: Dictionary = specs[e["b"]]
	var ca: Vector2i = a["anchor"]
	var cb: Vector2i = b["anchor"]
	var delta := cb - ca
	var axes: Array[Vector2i] = []
	if absi(delta.x) >= absi(delta.y):
		axes = [Vector2i(signi(delta.x) if delta.x != 0 else 1, 0), Vector2i(0, signi(delta.y) if delta.y != 0 else 1)]
	else:
		axes = [Vector2i(0, signi(delta.y)), Vector2i(signi(delta.x) if delta.x != 0 else 1, 0)]
	# try the dominant axis first (a leaves along it, b is entered from the opposite side), then the other one
	for dir in axes:
		var da := _door_cell(a, dir, cb)
		var db := _door_cell(b, -dir, ca)
		if da.x < 0 or db.x < 0:
			continue
		var sa := da + dir
		var sb := db - dir
		var was_a := grid.is_point_solid(sa)
		var was_b := grid.is_point_solid(sb)
		grid.set_point_solid(sa, false)
		grid.set_point_solid(sb, false)
		var path := grid.get_id_path(sa, sb)
		if path.is_empty() or path.size() > max_len:
			grid.set_point_solid(sa, was_a)
			grid.set_point_solid(sb, was_b)
			continue
		var cells: Array = []
		for p: Vector2i in path:
			cells.append(p)
			corridor[p] = true
			grid.set_point_weight_scale(p, 0.4)
		e["cells"] = cells
		e["door_a"] = da
		e["door_b"] = db
		if e["kind"] == "boss_door":
			e["gate"] = db
		elif e["kind"] == "secret":
			e["gate"] = da
		doors[da] = e["id"]
		doors[db] = e["id"]
		return true
	return false


## A plain-floor cell on the `dir` side of the room's border, as close as possible to the line towards `target`.
## Returns (-1, -1) if the side has none.
static func _door_cell(r: Dictionary, dir: Vector2i, target: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1.0e9
	var rows: Array = r["rows"]
	var rw: int = r["w"]
	var rh: int = r["h"]
	var cells: Array[Vector2i] = []
	if dir.x != 0:
		var cx := rw - 1 if dir.x > 0 else 0
		for ry in rh:
			cells.append(Vector2i(cx, ry))
	else:
		var cy := rh - 1 if dir.y > 0 else 0
		for rx in rw:
			cells.append(Vector2i(rx, cy))
	for lc in cells:
		if (rows[lc.y] as String)[lc.x] != ".":
			continue
		var wc := Vector2i(int(r["x"]) + lc.x, int(r["y"]) + lc.y)
		# the cell just inside must be walkable as well, otherwise the door opens onto a pillar
		var inside := wc - dir
		var lin := Vector2i(inside.x - int(r["x"]), inside.y - int(r["y"]))
		if lin.x < 0 or lin.y < 0 or lin.x >= rw or lin.y >= rh:
			continue
		var ich := (rows[lin.y] as String)[lin.x]
		if ich == "#" or ich == "L":
			continue
		var d := (wc.x - target.x) * (wc.x - target.x) + (wc.y - target.y) * (wc.y - target.y)
		if float(d) < best_d:
			best_d = float(d)
			best = wc
	return best


static func _skip_loop(s: Dictionary) -> bool:
	return s["role"] == "boss" or s["secret"] or s["role"] == "safe" or s["role"] == "start"


static func _linked(edges: Array, a: int, b: int) -> bool:
	for e: Dictionary in edges:
		if (e["a"] == a and e["b"] == b) or (e["a"] == b and e["b"] == a):
			return true
	return false


static func _critical_path(rooms: Array) -> Array:
	var out: Array = []
	for r: Dictionary in rooms:
		if not r["side"]:
			out.append(r["id"])
	return out


## Passable cell nearest the room centre (world cell coords).
static func _anchor_cell(s: Dictionary) -> Vector2i:
	var rows: Array = s["rows"]
	var cx := float(s["w"]) * 0.5 - 0.5
	var cy := float(s["h"]) * 0.5 - 0.5
	var best := Vector2i.ZERO
	var best_d := 1.0e9
	for ry in rows.size():
		var row: String = rows[ry]
		for rx in row.length():
			var ch := row[rx]
			if ch == "#" or ch == "L":
				continue
			var d := (float(rx) - cx) * (float(rx) - cx) + (float(ry) - cy) * (float(ry) - cy)
			if d < best_d:
				best_d = d
				best = Vector2i(rx, ry)
	return Vector2i(int(s["x"]) + best.x, int(s["y"]) + best.y)


## World cells of template marker `ch` in a room, in row-major order.
static func _find_marker(r: Dictionary, ch: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rows: Array = r["rows"]
	for ry in rows.size():
		var row: String = rows[ry]
		for rx in row.length():
			if row[rx] == ch:
				out.append(Vector2i(int(r["x"]) + rx, int(r["y"]) + ry))
	return out


## Mirror / rotate a template: mode bit 0 flips x, bit 1 flips y, bit 2 transposes.
static func _orient(rows: Array, mode: int) -> Array:
	var grid: Array = []
	for r: String in rows:
		var line: Array = []
		for i in r.length():
			line.append(r[i])
		grid.append(line)
	if mode & 4:
		var t: Array = []
		for x in (grid[0] as Array).size():
			var line: Array = []
			for y in grid.size():
				line.append(grid[y][x])
			t.append(line)
		grid = t
	if mode & 1:
		for line: Array in grid:
			line.reverse()
	if mode & 2:
		grid.reverse()
	var out: Array = []
	for line: Array in grid:
		out.append("".join(PackedStringArray(line)))
	return out


# ---------------------------------------------------------------------------------------------
# content: creatures, traps, chests, lights, bosses

static func _fill_content(rng: RandomNumberGenerator, layout: Dictionary, def: Dictionary) -> void:
	var f: int = layout["floor"]
	var theme: Dictionary = Data.THEMES[layout["theme"]]
	var tier: int = layout["tier"]
	var scale := Data.scale_for(f)
	var level: int = layout["level"]
	var rooms: Array = layout["rooms"]
	var creatures: Array = []
	var traps: Array = []
	var chests: Array = []
	var lights: Array = []
	var secrets: Array = []
	var n_c := 0
	var n_t := 0
	var n_ch := 0
	var protected := {}     # cells that must stay clear: doors, stairs, warp, outward door cells
	for c: Vector2i in layout["doors"]:
		protected[c] = true
		for d in DIRS:
			protected[c + d] = true
	protected[layout["stairs_up"]] = true
	protected[layout["stairs_down"]] = true
	protected[layout["warp_cell"]] = true
	var boss: Dictionary = {}
	var midboss: Dictionary = {}
	for r: Dictionary in rooms:
		var rid: int = r["id"]
		var role: String = r["role"]
		var spawns := _find_marker(r, "S")
		var chest_slots := _find_marker(r, "C")
		var trap_slots := _find_marker(r, "T")
		var bspot := _find_marker(r, "B")
		for c in _find_marker(r, "L"):
			lights.append({"cell": c, "room": rid, "kind": "brazier"})
		if role == "safe":
			for c in _find_marker(r, "A"):
				lights.append({"cell": c, "room": rid, "kind": "warp_stone"})
		if r["secret"]:
			secrets.append(rid)
		# monsters
		var want := 0
		match role:
			"combat":
				want = 2 + int(scale * 1.5) + rng.randi() % 3
			"trap":
				want = 1 + rng.randi() % 2
			"treasure":
				want = 1 + int(scale * 0.5)
			"midboss":
				want = 2 + int(scale)
			"boss":
				want = 3 + int(scale * 1.5)
			"secret":
				want = rng.randi() % 2
		if role == "midboss" or role == "boss":
			var is_boss := role == "boss"
			var info := _boss_entry(rng, theme, f, tier, level, is_boss)
			var spot: Vector2i = bspot[0] if not bspot.is_empty() else (r["anchor"] as Vector2i)
			info["cell"] = spot
			info["room"] = rid
			info["id"] = "f%d_%s" % [f + 1, "boss" if is_boss else "midboss"]
			creatures.append(info)
			protected[spot] = true
			if is_boss:
				boss = info
			else:
				midboss = info
		var slots: Array[Vector2i] = spawns.duplicate()
		_shuffle(rng, slots)
		var picks := mini(want, slots.size())
		if picks < want and role != "secret":
			# not enough slots: scatter the rest on free floor cells of the room
			var extra := _free_cells(r, protected)
			_shuffle(rng, extra)
			for c in extra:
				if slots.size() >= want:
					break
				if not slots.has(c):
					slots.append(c)
			picks = mini(want, slots.size())
		for i in picks:
			var cell: Vector2i = slots[i]
			if protected.has(cell):
				continue
			var elite := rng.randf() < minf(0.05 + 0.02 * float(f), 0.35)
			var use_tier := mini(tier + (1 if elite else 0), 4)
			var pool: Array = theme["pool"][use_tier]
			var kind: String = pool[rng.randi() % pool.size()]
			creatures.append({"id": "f%d_c%d" % [f + 1, n_c], "kind": kind, "cell": cell, "room": rid, "level": level + rng.randi_range(-1, 1) + (2 if elite else 0),
				"elite": elite, "boss": false, "hp_mult": 1.8 if elite else 1.0, "dmg_mult": 1.2 if elite else 1.0, "name": ""})
			n_c += 1
			protected[cell] = true
		# traps
		var rtrap := trap_slots.duplicate()
		for c in rtrap:
			if protected.has(c):
				continue
			traps.append(_trap(rng, theme, f, n_t, c, rid, scale))
			n_t += 1
			protected[c] = true
		# chests
		var mult := scale
		var cslots: Array[Vector2i] = chest_slots.duplicate()
		if role == "boss" or role == "midboss":
			cslots = _free_cells_near(r, bspot[0] if not bspot.is_empty() else r["anchor"], protected, 3.0, 2 if role == "boss" else 1)
			mult *= 3.0 if role == "boss" else 1.6
		elif role == "secret":
			mult *= 2.5
		elif role == "treasure":
			mult *= 1.8
		elif role == "combat" and cslots.size() > 1:
			cslots = [cslots[rng.randi() % cslots.size()]]
		for c in cslots:
			if protected.has(c):
				continue
			var locked: bool = (role == "treasure" or role == "secret") and rng.randf() < 0.4
			chests.append({"id": "f%d_ch%d" % [f + 1, n_ch], "cell": c, "room": rid, "role": role, "tier": mini(tier + (1 if role == "secret" else 0), 4),
				"locked": locked, "loot": Loot.roll_loot(rng, mini(tier + (1 if role == "secret" else 0), 4), mult)})
			n_ch += 1
			protected[c] = true
	# corridor traps: deeper floors get more
	var corridor_traps := int(round(float(f) * 0.5 + 1.0 + rng.randf() * 2.0))
	var cand: Array[Vector2i] = []
	for e: Dictionary in layout["edges"]:
		var cells: Array = e["cells"]
		for i in range(3, cells.size() - 3):
			var c: Vector2i = cells[i]
			if not protected.has(c) and layout["room_of"][c.y * int(layout["w"]) + c.x] == -1:
				cand.append(c)
	_shuffle(rng, cand)
	for i in mini(corridor_traps, cand.size()):
		traps.append(_trap(rng, theme, f, n_t, cand[i], -1, scale))
		n_t += 1
	layout["content"] = {"creatures": creatures, "traps": traps, "chests": chests, "lights": lights, "boss": boss, "midboss": midboss, "secrets": secrets}
	# a loose-brick tell next to each secret door (placed on the corridor side, the cell before the door)
	for e: Dictionary in layout["edges"]:
		if e["kind"] == "secret":
			var cells: Array = e["cells"]
			e["tell"] = cells[mini(1, cells.size() - 1)]


static func _boss_entry(rng: RandomNumberGenerator, theme: Dictionary, f: int, tier: int, level: int, is_boss: bool) -> Dictionary:
	var m := Data.boss_mult(f, is_boss)
	if is_boss:
		var bosses: Array = theme["bosses"]
		var b: Array = bosses[(f / 3 + rng.randi() % 2) % bosses.size()]
		return {"kind": b[2], "name": b[0], "title": b[1], "scale": float(b[3]) + 0.04 * float(f), "patterns": b[4], "boss": true, "midboss": false,
			"level": level + 4, "hp_mult": m.x, "dmg_mult": m.y, "elite": true}
	var pool: Array = theme["pool"][mini(tier + 1, 4)]
	var kind: String = pool[rng.randi() % pool.size()]
	return {"kind": kind, "name": "%s %s" % [ADJ_WORDS[rng.randi() % ADJ_WORDS.size()], kind.capitalize().replace("_", " ")], "title": "Guardian of the way down",
		"scale": 1.45, "patterns": ["charge", "stomp"], "boss": false, "midboss": true, "level": level + 2, "hp_mult": m.x, "dmg_mult": m.y, "elite": true}


static func _trap(rng: RandomNumberGenerator, theme: Dictionary, f: int, n: int, cell: Vector2i, room: int, scale: float) -> Dictionary:
	var kinds: Array = theme["traps"]
	var kind: String = kinds[rng.randi() % kinds.size()]
	var t: Dictionary = Data.TRAPS[kind]
	return {"id": "f%d_t%d" % [f + 1, n], "kind": kind, "cell": cell, "room": room, "dmg": snappedf(float(t["dmg"]) * scale, 0.1),
		"detect": minf(float(t["detect"]) + 0.02 * float(f), 0.95), "disarm": t["disarm"], "radius": t["radius"]}


static func _free_cells(r: Dictionary, protected: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rows: Array = r["rows"]
	for ry in rows.size():
		var row: String = rows[ry]
		for rx in row.length():
			if row[rx] == "." or row[rx] == "S":
				var c := Vector2i(int(r["x"]) + rx, int(r["y"]) + ry)
				if not protected.has(c):
					out.append(c)
	return out


## `count` free cells of the room nearest `centre` (within `radius`).
static func _free_cells_near(r: Dictionary, centre: Vector2i, protected: Dictionary, radius: float, count: int) -> Array[Vector2i]:
	var all := _free_cells(r, protected)
	var near: Array[Vector2i] = []
	for c in all:
		var d := Vector2(c - centre).length()
		if d >= 1.5 and d <= radius + 2.0:
			near.append(c)
	near.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return Vector2(a - centre).length() < Vector2(b - centre).length() or (Vector2(a - centre).length() == Vector2(b - centre).length() and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	var out: Array[Vector2i] = []
	for i in mini(count, near.size()):
		out.append(near[i])
	return out


static func _shuffle(rng: RandomNumberGenerator, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


static func _mix(a: int, b: int) -> int:
	var h: int = (a * 0x9E3779B1 + b * 0x85EBCA6B + 0x27D4EB2F) & 0x7FFFFFFF
	h = ((h >> 13) ^ h) * 0x45D9F3B & 0x7FFFFFFF
	h = ((h >> 15) ^ h) & 0x7FFFFFFF
	return h
