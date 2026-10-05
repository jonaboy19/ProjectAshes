extends RefCounted
## Cave / dungeon layout + content generator. Pure data from a seed (no nodes, no autoloads), so
## it is deterministic and unit-testable (tests/test_dungeons.gd). dungeon_build.gd turns the result
## into one cheap interior scene when the player enters.
##
## generate(seed, theme, tier, opts) -> Dictionary:
##   id, seed, theme, tier, level_min, level_max, w, h (grid cells of CELL m), cells (PackedByteArray:
##   0 rock, 1 room, 2 corridor, 3 pool), room_of (PackedInt32Array, -1 = none), rooms[], edges[],
##   gates[], spawn (Vector3, local), spawn_cell, boss_room, content: creatures, chests, nodes, lore,
##   plates, traps, lights, clutter, boss.
## Local coordinates: metres, the grid is centred on the origin, floor at y = 0.
##
## Content rules (docs/design/REALM_PLAN.md "Freedom and exploration first"): nothing here is required for
## progress. Gates only ever seal optional vault rooms and their solver (lever, pressure plate, a rune
## you know, a pick) is always on the entrance side. The boss chamber at the far end is optional too.

const CELL := 3.0
const ROCK := 0
const ROOM := 1
const CORR := 2
const POOL := 3

const THEMES := ["cave", "flooded", "crystal", "mine", "hideout", "warren", "crypt"]

## Per theme: display name, room count range, room size range (cells), corridor width, organic walls,
## ceiling height range, wall tint, ambient, fog, lit (0 = dark, 1 = every room has a light), the
## creature pool by tier, the boss, resource kinds and lore topics.
const THEME := {
	"cave": {"name": "Cave", "rooms": [3, 10], "size": [4, 8], "cw": 2, "organic": true, "height": [4.5, 7.0],
		"tint": Color(0.52, 0.48, 0.44), "ambient": Color(0.10, 0.11, 0.14), "fog": Color(0.05, 0.06, 0.08), "lit": 0.0,
		"res": ["glowcap", "healing_herb", "coal"], "light": "glowcap",
		"pool": {1: ["bat", "giant_rat", "spider"], 2: ["bat", "spider", "wolf"], 3: ["spider", "wolf", "bear"], 4: ["spider", "mushroom_king", "bear"]},
		"boss": {"kind": "bear", "name": "Hollowback, the Den Bear", "trophy": "trophy_bear_claw", "scale": 1.5}},
	"flooded": {"name": "Flooded Cave", "rooms": [4, 10], "size": [5, 9], "cw": 2, "organic": true, "height": [4.0, 6.0],
		"tint": Color(0.40, 0.50, 0.52), "ambient": Color(0.07, 0.11, 0.15), "fog": Color(0.03, 0.07, 0.10), "lit": 0.0,
		"res": ["glowcap", "cave_pearl", "healing_herb"], "light": "glowcap",
		"pool": {1: ["bat", "giant_rat", "bog_toad"], 2: ["bog_toad", "spider", "giant_rat"], 3: ["bog_toad", "ghoul", "spider"], 4: ["ghoul", "bog_toad", "rift_slime"]},
		"boss": {"kind": "bog_toad", "name": "Gulpmaw, the Mere King", "trophy": "trophy_toad_crown", "scale": 2.6}},
	"crystal": {"name": "Rift Crystal Cave", "rooms": [4, 10], "size": [5, 9], "cw": 2, "organic": true, "height": [5.0, 8.0],
		"tint": Color(0.42, 0.36, 0.55), "ambient": Color(0.10, 0.07, 0.16), "fog": Color(0.06, 0.03, 0.10), "lit": 0.0,
		"res": ["rift_crystal", "rift_crystal", "silver_ore"], "light": "crystal",
		"pool": {1: ["blight_rat", "bat", "rift_slime"], 2: ["rift_slime", "blight_rat", "spider"], 3: ["rift_slime", "rift_wraith", "ghost_skull"], 4: ["rift_wraith", "ghost_skull", "ghoul"]},
		"boss": {"kind": "rift_wraith", "name": "The Shardbound Horror", "trophy": "trophy_shard_heart", "scale": 2.4}},
	"mine": {"name": "Old Mine", "rooms": [5, 12], "size": [4, 7], "cw": 1, "organic": false, "height": [3.6, 4.6],
		"tint": Color(0.50, 0.42, 0.34), "ambient": Color(0.09, 0.08, 0.08), "fog": Color(0.05, 0.04, 0.04), "lit": 0.6,
		"res": ["iron_ore", "copper_ore", "coal", "silver_ore"], "light": "lantern",
		"pool": {1: ["giant_rat", "bat", "spider"], 2: ["giant_rat", "spider", "goblin"], 3: ["goblin", "ghoul", "spider"], 4: ["ghoul", "goblin", "blight_rat"]},
		"boss": {"kind": "blackcap_brute", "name": "Old Gorm, the Blackcap Brute", "trophy": "trophy_brute_cap", "scale": 1.4}},
	"hideout": {"name": "Bandit Hideout", "rooms": [4, 8], "size": [5, 8], "cw": 2, "organic": false, "height": [3.8, 4.8],
		"tint": Color(0.55, 0.47, 0.38), "ambient": Color(0.10, 0.09, 0.09), "fog": Color(0.05, 0.04, 0.04), "lit": 1.0,
		"res": ["healing_herb"], "light": "torch",
		"pool": {1: ["bandit", "wolf"], 2: ["bandit", "wolf", "bandit"], 3: ["bandit", "orc", "bandit"], 4: ["bandit", "orc", "bandit"]},
		"boss": {"kind": "orc", "name": "Captain Verrick of the Ash Hand", "trophy": "trophy_ash_hand_seal", "scale": 1.1}},
	"warren": {"name": "Goblin Warren", "rooms": [5, 12], "size": [4, 7], "cw": 1, "organic": true, "height": [3.4, 4.6],
		"tint": Color(0.46, 0.42, 0.30), "ambient": Color(0.10, 0.10, 0.07), "fog": Color(0.05, 0.05, 0.03), "lit": 0.4,
		"res": ["glowcap", "coal"], "light": "fire",
		"pool": {1: ["goblin", "giant_rat"], 2: ["goblin", "goblin", "spider"], 3: ["goblin", "orc", "goblin"], 4: ["goblin", "orc", "orc"]},
		"boss": {"kind": "goblin", "name": "Snarl, the Tunnel King", "trophy": "trophy_goblin_crown", "scale": 1.9}},
	"crypt": {"name": "Ancient Crypt", "rooms": [5, 10], "size": [5, 9], "cw": 2, "organic": false, "height": [5.0, 6.5],
		"tint": Color(0.58, 0.58, 0.60), "ambient": Color(0.08, 0.09, 0.12), "fog": Color(0.04, 0.05, 0.08), "lit": 0.6,
		"res": ["silver_ore"], "light": "brazier",
		"pool": {1: ["giant_rat", "skeleton_minion", "bat"], 2: ["ghoul", "skeleton_warrior", "skeleton_minion"], 3: ["skeleton_rogue", "rift_wraith", "ghoul", "skeleton_mage"], 4: ["rift_wraith", "skeleton_warrior", "ghoul", "skeleton_mage"]},
		"boss": {"kind": "troll", "name": "The Barrow Warden", "trophy": "trophy_warden_seal", "scale": 1.0}},
}

## Recommended character level per danger tier (Region 1 runs 1-60; the game goes on to 500).
const TIER_LEVELS := {1: Vector2i(1, 12), 2: Vector2i(10, 28), 3: Vector2i(25, 45), 4: Vector2i(40, 60)}

const GATE_KINDS := ["lever", "plate", "rune", "collapse"]

const LORE := {
	"cave": [
		["Scratched into the wall", "Someone counted the days here in tally marks. After the ninety-first they stopped, and a second hand wrote: 'the wolves dig under the roots, not over.'", "topic:cave_wolves"],
		["A shepherd's knot-cord", "Knots and notches: a hill family marked which caves hold bears in winter. Every cave on the cord is crossed out but one.", "topic:winter_bears"],
	],
	"flooded": [
		["Waterlogged ledger", "The ink has run, but one line holds: 'the Mere drains into the old tunnels when the thaw is late. Pearls lie where the tunnels bend.'", "topic:mere_tunnels"],
		["Fisher's charm", "A wooden charm carved with a fish and a rune of stillness. The back reads: 'Whisper Hollow hears what the water hears.'", "topic:whisper_hollow"],
	],
	"crystal": [
		["Rift-seam notes", "A Runeward surveyor's page: 'the crystals hum louder where the ward is thin. They grow toward people. Do not sleep here.'", "topic:rift_seep"],
		["Glass-hard inscription", "Violet script fused into the stone: the same three runes the Elder Stones carry, but carved backwards.", "secret:backward_runes"],
	],
	"mine": [
		["Foreman's tally board", "Shifts, carts, and a last entry: 'seam gone bad, sealed east gallery. Crew refused to go back for their picks.'", "topic:old_greyseam"],
		["Miner's letter", "'Tell Mara I found silver behind the fall. The rock sings when the pick hits true. I will be home by the thaw.'", "topic:silver_behind_the_fall"],
	],
	"hideout": [
		["Ash Hand ledger", "Tolls owed and tolls paid, and a column headed 'stones'. Next to three roadside waystones: a name and a price.", "secret:ash_hand_ledger"],
		["Crumpled orders", "'Hit the carts after dusk, when the stones dim. Captain wants the smith's daughter unharmed. Leave no witnesses who know the road.'", "topic:ash_hand_roads"],
	],
	"warren": [
		["Goblin scratchings", "Crude pictures: a crowned goblin, a bigger goblin with a chain, and many small goblins in a line heading out of the ground at night.", "topic:mossfang_tunnels"],
		["Chewed scroll", "A stolen map of the Duskbriar roads, with three caravan stops circled in charcoal.", "topic:duskbriar_roads"],
	],
	"crypt": [
		["Crypt inscription", "'Here lie the wardens of the first stones. Let the flame be kept, or let it sleep. Only the keeper may wake it.'", "topic:first_wardens"],
		["Keeper's epitaph", "'The Dawn Throne had no hand in these stones. The pale ones came later, and they wanted them quiet.'", "secret:dawn_throne_later"],
	],
}


## Main entry. opts: rooms (int override, 3-12), id (string), level (Vector2i override).
static func generate(seed_value: int, theme: String, tier: int, opts: Dictionary = {}) -> Dictionary:
	if not THEME.has(theme):
		theme = "cave"
	tier = clampi(tier, 1, 4)
	var T: Dictionary = THEME[theme]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, theme, tier, "dg"])
	var id := String(opts.get("id", "d%d" % (absi(seed_value) % 100000)))
	var trange: Array = T["rooms"]
	var n := int(opts.get("rooms", rng.randi_range(int(trange[0]), int(trange[1]))))
	n = clampi(n, 3, 12)
	var lv: Vector2i = TIER_LEVELS[tier]
	if opts.has("level"):
		lv = opts["level"]
	var span := lv.y - lv.x
	var lvl_min := clampi(lv.x + rng.randi_range(0, maxi(span / 4, 1)), 1, 60)
	var lvl_max := clampi(lv.y - rng.randi_range(0, maxi(span / 4, 1)), lvl_min, 60)

	var size: Array = T["size"]
	var side := int(ceil(sqrt(float(n)) * float(int(size[1]) + 4))) + 10
	var rooms: Array[Dictionary] = []
	var tries := 0
	while rooms.size() < n:
		tries += 1
		if tries > 1500:
			side += 8
			tries = 0
			rooms.clear()
		var rw := rng.randi_range(int(size[0]), int(size[1]))
		var rh := rng.randi_range(int(size[0]), int(size[1]))
		var boss_room := rooms.size() == n - 1 and n >= 4
		if boss_room:
			rw = mini(rw + 3, int(size[1]) + 4)
			rh = mini(rh + 3, int(size[1]) + 4)
		var rx := rng.randi_range(3, side - rw - 3)
		var rz := rng.randi_range(3, side - rh - 3)
		var r := Rect2i(rx, rz, rw, rh)
		var ok := true
		for o: Dictionary in rooms:
			if (o["rect"] as Rect2i).grow(4).intersects(r):
				ok = false
				break
		if ok:
			rooms.append({"id": rooms.size(), "rect": r, "center": r.position + r.size / 2, "role": "chamber", "deg": 0})
	var cells := PackedByteArray()
	cells.resize(side * side)
	var room_of := PackedInt32Array()
	room_of.resize(side * side)
	room_of.fill(-1)
	# --- rooms ---------------------------------------------------------------------------------
	var organic: bool = T["organic"]
	for rm: Dictionary in rooms:
		var r: Rect2i = rm["rect"]
		var c := Vector2(r.position) + Vector2(r.size) * 0.5
		for z in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var open := true
				if organic:
					var dx := (x + 0.5 - c.x) / (r.size.x * 0.5)
					var dz := (z + 0.5 - c.y) / (r.size.y * 0.5)
					var nz := 0.5 + 0.5 * sin(x * 1.7 + rm["id"] * 3.1) * cos(z * 1.3 + rm["id"])
					open = dx * dx + dz * dz < 0.80 + 0.45 * nz
				elif theme == "crypt" or theme == "hideout":
					# chamfered corners
					var ex := mini(x - r.position.x, r.end.x - 1 - x)
					var ez := mini(z - r.position.y, r.end.y - 1 - z)
					open = ex + ez >= 1
				if open:
					cells[z * side + x] = ROOM
					room_of[z * side + x] = rm["id"]
		# the centre cross is always open so corridors can attach
		var cc: Vector2i = rm["center"]
		for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = cc + d
			if r.has_point(q):
				cells[q.y * side + q.x] = ROOM
				room_of[q.y * side + q.x] = rm["id"]
	# --- connections: minimum spanning tree, then a few loops ----------------------------------
	var edges: Array[Dictionary] = []
	var in_tree := {0: true}
	while in_tree.size() < n:
		var best := [-1, -1, 1.0e9]
		for a in in_tree:
			for b in range(n):
				if in_tree.has(b):
					continue
				var d := float((rooms[a]["center"] as Vector2i).distance_squared_to(rooms[b]["center"]))
				if d < best[2]:
					best = [a, b, d]
		in_tree[best[1]] = true
		edges.append({"a": best[0], "b": best[1], "loop": false, "gate": -1})
	if n >= 6:
		var extra: Array = []
		for a in range(n):
			for b in range(a + 1, n):
				if _edge_has(edges, a, b):
					continue
				extra.append([float((rooms[a]["center"] as Vector2i).distance_squared_to(rooms[b]["center"])), a, b])
		extra.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
		var loops := mini(n / 4, extra.size())
		for i in loops:
			edges.append({"a": extra[i][1], "b": extra[i][2], "loop": true, "gate": -1})
	for e: Dictionary in edges:
		rooms[e["a"]]["deg"] += 1
		rooms[e["b"]]["deg"] += 1
	# Graph distance from the entrance (room 0): the farthest room holds the boss.
	var dist := _bfs_rooms(n, edges, 0)
	var boss_id := 0
	for i in range(n):
		if dist[i] > dist[boss_id] or (dist[i] == dist[boss_id] and i > boss_id and rooms[i]["deg"] <= rooms[boss_id]["deg"]):
			boss_id = i
	if boss_id == 0:
		boss_id = n - 1
	# --- gates: lock optional dead-end vaults --------------------------------------------------
	var leaves: Array[int] = []
	for i in range(1, n):
		if rooms[i]["deg"] == 1 and i != boss_id:
			leaves.append(i)
	var gate_count := 0 if n < 5 else (1 if n < 8 else (2 if n < 11 else 3))
	gate_count = mini(gate_count, leaves.size())
	var gates: Array[Dictionary] = []
	var gate_leaves: Array[int] = []
	_shuffle(leaves, rng)
	var corr_width: int = int(T["cw"])
	# carve all corridors; gated ones are a single cell wide so a door fits
	for i in gate_count:
		gate_leaves.append(leaves[i])
	for e: Dictionary in edges:
		var cw := corr_width
		var leaf := -1
		for gl in gate_leaves:
			if (e["a"] == gl or e["b"] == gl) and not e["loop"]:
				leaf = gl
		if leaf >= 0:
			cw = 1
		var path := _carve(cells, room_of, side, rooms[e["a"]]["center"], rooms[e["b"]]["center"], cw, organic, rng)
		e["path"] = path
		e["leaf"] = leaf
		# flooded caves: the tunnels themselves carry water in places (marked later)
	# --- pools (flooded) ------------------------------------------------------------------------
	if theme == "flooded":
		for rm: Dictionary in rooms:
			if rm["id"] == 0:
				continue
			var cc: Vector2i = rm["center"]
			var rad := rng.randi_range(1, maxi(int(minf(rm["rect"].size.x, rm["rect"].size.y)) / 3, 1))
			for z in range(cc.y - rad, cc.y + rad + 1):
				for x in range(cc.x - rad, cc.x + rad + 1):
					if Vector2(x - cc.x, z - cc.y).length() <= rad + 0.3 and cells[z * side + x] == ROOM and room_of[z * side + x] == rm["id"]:
						cells[z * side + x] = POOL
	# --- finalise gates (only where sealing really cuts the vault off) -------------------------
	var blocked := {}
	for e: Dictionary in edges:
		if e["leaf"] < 0:
			continue
		var gc := _gate_cell(e["path"], rooms[e["leaf"]]["rect"], cells, side)
		if gc.x < 0:
			continue
		blocked[gc] = true
		e["gate_cell"] = gc
	# A gated vault is sealed only if flood fill from the entrance with every gate blocked cannot reach it.
	var open_reach := _flood(cells, side, rooms[0]["center"], blocked)
	var solver_rooms: Array[int] = []
	for i in range(n):
		var cc2: Vector2i = rooms[i]["center"]
		if open_reach.has(cc2) and i != 0 and i != boss_id and not gate_leaves.has(i):
			solver_rooms.append(i)
	if solver_rooms.is_empty():
		solver_rooms.append(0)
	for e: Dictionary in edges:
		if e["leaf"] < 0 or not e.has("gate_cell"):
			continue
		var leaf_center: Vector2i = rooms[e["leaf"]]["center"]
		if open_reach.has(leaf_center):
			continue      # a loop or a neighbouring corridor bypasses the door: leave it open
		var kind: String = GATE_KINDS[rng.randi() % GATE_KINDS.size()]
		if theme == "crypt" and rng.randf() < 0.6:
			kind = "rune"
		elif theme == "mine" and rng.randf() < 0.5:
			kind = "collapse"
		var gid := gates.size()
		var gcell: Vector2i = e["gate_cell"]
		var path: Array = e["path"]
		var idx := path.find(gcell)
		var nxt: Vector2i = path[clampi(idx + 1, 0, path.size() - 1)] if idx >= 0 else gcell
		var prv: Vector2i = path[clampi(idx - 1, 0, path.size() - 1)] if idx >= 0 else gcell
		var axis := "x" if absi(nxt.x - prv.x) >= absi(nxt.y - prv.y) else "z"
		var sroom: int = solver_rooms[rng.randi() % solver_rooms.size()]
		gates.append({"id": gid, "cell": gcell, "axis": axis, "kind": kind, "room": e["leaf"], "solver_room": sroom,
			"fact": "cave:%s:rune%d" % [id, gid], "key": "g%d" % gid})
		rooms[e["leaf"]]["role"] = "vault"
		e["gate"] = gid
	# --- roles ---------------------------------------------------------------------------------
	rooms[0]["role"] = "entrance"
	rooms[boss_id]["role"] = "boss"
	var free_leaves: Array[int] = []
	for i in range(1, n):
		if rooms[i]["role"] == "chamber" and rooms[i]["deg"] == 1:
			free_leaves.append(i)
	var others: Array[int] = []
	for i in range(1, n):
		if rooms[i]["role"] == "chamber":
			others.append(i)
	var lore_room := -1
	var res_room := -1
	var den_room := -1
	if not free_leaves.is_empty():
		lore_room = free_leaves[0]
	elif not others.is_empty():
		lore_room = others[0]
	if lore_room >= 0:
		rooms[lore_room]["role"] = "lore"
	for i in others:
		if rooms[i]["role"] == "chamber":
			if res_room < 0:
				res_room = i
				rooms[i]["role"] = "resource"
			elif den_room < 0 and n >= 6:
				den_room = i
				rooms[i]["role"] = "den"
	# solver rooms must exist: a solver item (lever/plate/rune stone) needs an ordinary room
	var content := {"creatures": [], "chests": [], "nodes": [], "lore": [], "plates": [], "traps": [],
		"levers": [], "lights": [], "clutter": [], "runes": [], "props": []}
	var used := {}
	var uid := [0]
	var gen := {"rng": rng, "used": used, "uid": uid, "cells": cells, "room_of": room_of, "side": side, "rooms": rooms}
	# --- entrance ------------------------------------------------------------------------------
	var spawn_cell: Vector2i = rooms[0]["center"]
	var ex := _pick_wall(gen, 0, true)
	if ex != {}:
		spawn_cell = ex["cell"]
		content["exit"] = {"pos": ex["pos"], "yaw": ex["yaw"]}
	else:
		content["exit"] = {"pos": _cell_pos(side, spawn_cell) + Vector3(0, 0, -1.2), "yaw": 0.0}
	used[spawn_cell] = true
	used[rooms[0]["center"]] = true
	# a free light for a dark dungeon sits at the entrance
	if T["lit"] < 0.5:
		var tc := _pick_wall(gen, 0, true)
		if tc != {}:
			content["props"].append({"id": _uid(uid, "p"), "kind": "torch_cache", "pos": tc["pos"], "yaw": tc["yaw"], "room": 0})
	# --- per room content ----------------------------------------------------------------------
	var creature_budget: int = [4, 7, 10, 13][tier - 1]
	var pool: Array = T["pool"][tier]
	for rm: Dictionary in rooms:
		var rid: int = rm["id"]
		var role: String = rm["role"]
		var area := _room_area(cells, room_of, side, rid)
		_room_lights(gen, content, T, rid, role, rng)
		if role != "entrance":
			_room_clutter(gen, content, T, theme, rid, rng)
		match role:
			"entrance":
				pass
			"boss":
				_boss(gen, content, T, theme, tier, lvl_max, rid, rng)
			"vault":
				_chest(gen, content, rid, mini(tier + 1, 4), true, rng, "Sealed vault chest")
				_guard(gen, content, pool, rid, 1, lvl_min, lvl_max, rng, false)
			"lore":
				_lore(gen, content, theme, id, rid, rng)
				_chest(gen, content, rid, tier, false, rng, "Cache")
			"resource":
				_resources(gen, content, T, theme, rid, rng, 3 + tier / 2)
				_guard(gen, content, pool, rid, mini(1 + tier / 2, 3), lvl_min, lvl_max, rng, false)
			"den":
				var dpool: Array = [pool[rng.randi() % pool.size()]]
				var den_n := clampi(area / 12, 2, 3 + tier / 2)
				_guard(gen, content, dpool, rid, den_n, lvl_min, lvl_max, rng, true)
				_chest(gen, content, rid, tier, false, rng, "Hoard")
			_:
				var cnt := rng.randi_range(1, 1 + (tier + 1) / 2)
				_guard(gen, content, pool, rid, mini(cnt, maxi(area / 10, 1)), lvl_min, lvl_max, rng, false)
				if rng.randf() < 0.35:
					_chest(gen, content, rid, maxi(tier - 1, 1), false, rng, "Cache")
				if rng.randf() < 0.45:
					_resources(gen, content, T, theme, rid, rng, 2)
				if tier >= 2 and rng.randf() < 0.4:
					_trap(gen, content, rid, tier, rng)
	# cap creature counts for mobile: the boss and den stay, extras are dropped from the tail
	var non_boss: Array = []
	for c: Dictionary in content["creatures"]:
		if not bool(c.get("boss", false)):
			non_boss.append(c)
	while non_boss.size() > creature_budget:
		var victim: Dictionary = non_boss.pop_back()
		content["creatures"].erase(victim)
	# --- puzzle elements for each gate ---------------------------------------------------------
	for gt: Dictionary in gates:
		var sr: int = gt["solver_room"]
		match String(gt["kind"]):
			"lever":
				var p := _pick_cell(gen, sr, 1)
				content["levers"].append({"id": _uid(uid, "l"), "gate": gt["id"], "pos": _cell_pos(side, p), "room": sr})
			"plate":
				var p2 := _pick_cell(gen, sr, 1)
				content["plates"].append({"id": _uid(uid, "pl"), "gate": gt["id"], "pos": _cell_pos(side, p2), "room": sr, "kind": "gate"})
			"rune":
				var p3 := _pick_wall(gen, sr, false)
				var pos3: Vector3 = _cell_pos(side, _pick_cell(gen, sr, 1)) if p3 == {} else p3["pos"]
				var yaw3: float = 0.0 if p3 == {} else float(p3["yaw"])
				content["lore"].append({"id": _uid(uid, "r"), "pos": pos3, "yaw": yaw3, "room": sr, "title": "Carved rune",
					"text": "A rune cut deep into the stone, in the old Elder script. Tracing it, you understand how it opens the sealed door.",
					"fact": gt["fact"], "fact_text": "You know the rune that opens the sealed door in %s." % T["name"].to_lower(), "kind": "rune"})
			"collapse":
				if theme == "mine":
					_chest_item(gen, content, sr, "pickaxe", 1, rng)
	# --- the Elder-rune leaf also hints at a neighbour (filled by region_caves with real ids) ------
	var spawn := _cell_pos(side, spawn_cell)
	var out := {"id": id, "seed": seed_value, "theme": theme, "tier": tier, "level_min": lvl_min, "level_max": lvl_max,
		"name": String(T["name"]), "w": side, "h": side, "cells": cells, "room_of": room_of, "rooms": rooms,
		"edges": edges, "gates": gates, "spawn": spawn, "spawn_cell": spawn_cell, "boss_room": boss_id,
		"content": content, "organic": organic, "height": T["height"], "tint": T["tint"], "ambient": T["ambient"],
		"fog": T["fog"], "dark": float(T["lit"]) < 0.5, "light_kind": T["light"]}
	return out


# ---------------------------------------------------------------------------------------------
# geometry helpers

static func cell_pos(g: Dictionary, c: Vector2i) -> Vector3:
	return _cell_pos(int(g["w"]), c)


static func _cell_pos(side: int, c: Vector2i) -> Vector3:
	return Vector3((c.x - side * 0.5 + 0.5) * CELL, 0.0, (c.y - side * 0.5 + 0.5) * CELL)


static func cell_at(g: Dictionary, p: Vector3) -> Vector2i:
	var side := int(g["w"])
	return Vector2i(int(floor(p.x / CELL + side * 0.5)), int(floor(p.z / CELL + side * 0.5)))


static func is_open(g: Dictionary, c: Vector2i) -> bool:
	var side := int(g["w"])
	if c.x < 0 or c.y < 0 or c.x >= side or c.y >= side:
		return false
	return (g["cells"] as PackedByteArray)[c.y * side + c.x] != ROCK


static func _edge_has(edges: Array, a: int, b: int) -> bool:
	for e: Dictionary in edges:
		if (e["a"] == a and e["b"] == b) or (e["a"] == b and e["b"] == a):
			return true
	return false


static func _bfs_rooms(n: int, edges: Array, from: int) -> Array:
	var dist: Array = []
	dist.resize(n)
	dist.fill(-1)
	dist[from] = 0
	var queue := [from]
	while not queue.is_empty():
		var a: int = queue.pop_front()
		for e: Dictionary in edges:
			var b := -1
			if e["a"] == a:
				b = e["b"]
			elif e["b"] == a:
				b = e["a"]
			if b >= 0 and dist[b] < 0:
				dist[b] = dist[a] + 1
				queue.append(b)
	return dist


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


static func _carve(cells: PackedByteArray, room_of: PackedInt32Array, side: int, a: Vector2i, b: Vector2i, width: int, organic: bool, rng: RandomNumberGenerator) -> Array:
	var pts: Array[Vector2i] = [a]
	if organic and absi(a.x - b.x) > 4 and absi(a.y - b.y) > 4:
		var mx := (a.x + b.x) / 2 + rng.randi_range(-2, 2)
		pts.append(Vector2i(mx, a.y))
		pts.append(Vector2i(mx, b.y))
	elif rng.randf() < 0.5:
		pts.append(Vector2i(b.x, a.y))
	else:
		pts.append(Vector2i(a.x, b.y))
	pts.append(b)
	var path: Array = []
	for i in range(pts.size() - 1):
		var p: Vector2i = pts[i]
		var q: Vector2i = pts[i + 1]
		var step := Vector2i(signi(q.x - p.x), signi(q.y - p.y))
		if step == Vector2i.ZERO:
			continue
		# a leg is axis aligned by construction
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
				if cells[z * side + x] == ROCK:
					cells[z * side + x] = CORR
	return path


## First corridor cell outside `rect` when walking from the room: where a door fits.
static func _gate_cell(path: Array, rect: Rect2i, cells: PackedByteArray, side: int) -> Vector2i:
	if path.is_empty():
		return Vector2i(-1, -1)
	var start := 0
	var ends: Vector2i = path[0]
	if not rect.has_point(ends):
		start = path.size() - 1
	var dir := 1 if start == 0 else -1
	var i := start
	while i >= 0 and i < path.size():
		var c: Vector2i = path[i]
		if not rect.has_point(c) and cells[c.y * side + c.x] == CORR:
			# one more cell of breathing room so the door is in the tunnel, not in the room's mouth
			var j := i + dir
			if j >= 0 and j < path.size() and not rect.has_point(path[j]) and cells[(path[j] as Vector2i).y * side + (path[j] as Vector2i).x] == CORR:
				return path[j]
			return c
		i += dir
	return Vector2i(-1, -1)


static func _flood(cells: PackedByteArray, side: int, from: Vector2i, blocked: Dictionary) -> Dictionary:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = c + d
			if q.x < 0 or q.y < 0 or q.x >= side or q.y >= side or seen.has(q) or blocked.has(q):
				continue
			if cells[q.y * side + q.x] == ROCK:
				continue
			seen[q] = true
			queue.append(q)
	return seen


## Every open cell reachable from the entrance with `gates_open` true (else with gates blocked).
static func reachable(g: Dictionary, gates_open := true) -> Dictionary:
	var blocked := {}
	if not gates_open:
		for gt: Dictionary in g["gates"]:
			blocked[gt["cell"]] = true
	return _flood(g["cells"], int(g["w"]), g["spawn_cell"], blocked)


static func _room_area(cells: PackedByteArray, room_of: PackedInt32Array, side: int, rid: int) -> int:
	var n := 0
	for i in range(room_of.size()):
		if room_of[i] == rid and cells[i] != ROCK:
			n += 1
	return n


# ---------------------------------------------------------------------------------------------
# content helpers

static func _uid(uid: Array, prefix: String) -> String:
	uid[0] += 1
	return "%s%d" % [prefix, uid[0]]


## A free, open, non-pool cell of the room; `margin` = how many open neighbours in a ring it needs.
static func _pick_cell(gen: Dictionary, rid: int, margin: int) -> Vector2i:
	var rng: RandomNumberGenerator = gen["rng"]
	var cells: PackedByteArray = gen["cells"]
	var room_of: PackedInt32Array = gen["room_of"]
	var side: int = gen["side"]
	var used: Dictionary = gen["used"]
	var r: Rect2i = gen["rooms"][rid]["rect"]
	var cand: Array[Vector2i] = []
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := z * side + x
			if room_of[i] != rid or cells[i] != ROOM or used.has(Vector2i(x, z)):
				continue
			var ok := true
			for dz in range(-margin, margin + 1):
				for dx in range(-margin, margin + 1):
					if cells[(z + dz) * side + x + dx] == ROCK:
						ok = false
			if ok:
				cand.append(Vector2i(x, z))
	if cand.is_empty():
		var c: Vector2i = gen["rooms"][rid]["center"]
		used[c] = true
		return c
	var pick: Vector2i = cand[rng.randi() % cand.size()]
	used[pick] = true
	return pick


## A floor cell against a wall: {pos (on the wall face), yaw (facing into the room), cell}. {} if none.
static func _pick_wall(gen: Dictionary, rid: int, allow_used: bool) -> Dictionary:
	var rng: RandomNumberGenerator = gen["rng"]
	var cells: PackedByteArray = gen["cells"]
	var room_of: PackedInt32Array = gen["room_of"]
	var side: int = gen["side"]
	var used: Dictionary = gen["used"]
	var r: Rect2i = gen["rooms"][rid]["rect"]
	var cand: Array = []
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := z * side + x
			if room_of[i] != rid or cells[i] != ROOM:
				continue
			if used.has(Vector2i(x, z)) and not allow_used:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if cells[(z + d.y) * side + x + d.x] == ROCK:
					# the other three neighbours open keeps it reachable
					var open_n := 0
					for d2: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						if cells[(z + d2.y) * side + x + d2.x] != ROCK:
							open_n += 1
					if open_n >= 3:
						cand.append([Vector2i(x, z), d])
	if cand.is_empty():
		return {}
	var pick: Array = cand[rng.randi() % cand.size()]
	var c: Vector2i = pick[0]
	var d: Vector2i = pick[1]
	used[c] = true
	var centre := _cell_pos(side, c)
	var pos := centre + Vector3(d.x, 0, d.y) * (CELL * 0.5 - 0.35)
	# yaw so the object's +Z points into the room (away from the wall)
	var inward := Vector3(-d.x, 0, -d.y)
	return {"pos": pos, "yaw": atan2(inward.x, inward.z), "cell": c}


static func _room_lights(gen: Dictionary, content: Dictionary, T: Dictionary, rid: int, role: String, rng: RandomNumberGenerator) -> void:
	var kind: String = T["light"]
	var side: int = gen["side"]
	var uid: Array = gen["uid"]
	var lit := float(T["lit"])
	var centre: Vector2i = gen["rooms"][rid]["center"]
	var cpos := _cell_pos(side, centre)
	match kind:
		"glowcap":
			if rid == 0 or rng.randf() < 0.55 or role == "lore":
				var p := _pick_wall(gen, rid, true)
				if p != {}:
					content["lights"].append({"id": _uid(uid, "g"), "kind": "glowcap", "pos": p["pos"] + Vector3(0, 0.3, 0), "yaw": p["yaw"],
						"color": Color(0.35, 0.95, 0.75) if T["name"] != "Flooded Cave" else Color(0.3, 0.75, 1.0), "range": 7.0, "energy": 1.1, "room": rid})
		"crystal":
			var k := 1 + (1 if rng.randf() < 0.6 else 0)
			for i in k:
				var p := _pick_wall(gen, rid, true)
				if p != {}:
					content["lights"].append({"id": _uid(uid, "g"), "kind": "crystal", "pos": p["pos"] + Vector3(0, 0.0, 0), "yaw": p["yaw"],
						"color": Color(0.7, 0.4, 1.0), "range": 10.0, "energy": 2.4, "room": rid})
		_:
			if rid == 0 or rng.randf() < lit:
				var k2 := 2 if (role in ["entrance", "boss", "lore", "vault"] or kind == "torch") else 1
				for i in k2:
					var p := _pick_wall(gen, rid, true)
					if p != {}:
						var col := Color(1.0, 0.62, 0.30)
						if kind == "brazier":
							col = Color(1.0, 0.72, 0.42) if role != "vault" else Color(0.5, 0.75, 1.0)
						content["lights"].append({"id": _uid(uid, "t"), "kind": kind, "pos": p["pos"] + Vector3(0, 0, 0), "yaw": p["yaw"],
							"color": col, "range": 10.0 if kind != "lantern" else 9.0, "energy": 1.5, "room": rid})
	if kind == "fire" and (role == "den" or role == "boss" or rng.randf() < 0.3):
		content["lights"].append({"id": _uid(uid, "f"), "kind": "campfire", "pos": cpos + Vector3(1.2, 0, 1.2), "yaw": 0.0,
			"color": Color(1.0, 0.55, 0.25), "range": 11.0, "energy": 1.8, "room": rid})
	if T["name"] == "Bandit Hideout" and role in ["chamber", "den", "resource"] and rng.randf() < 0.5:
		content["lights"].append({"id": _uid(uid, "f"), "kind": "campfire", "pos": cpos + Vector3(-1.5, 0, 1.0), "yaw": 0.0,
			"color": Color(1.0, 0.55, 0.25), "range": 11.0, "energy": 1.8, "room": rid})


## Clutter = MultiMesh instances (stalagmites, rocks, bones, crates...) kept out of walkways.
static func _room_clutter(gen: Dictionary, content: Dictionary, T: Dictionary, theme: String, rid: int, rng: RandomNumberGenerator) -> void:
	var r: Rect2i = gen["rooms"][rid]["rect"]
	var side: int = gen["side"]
	var cells: PackedByteArray = gen["cells"]
	var room_of: PackedInt32Array = gen["room_of"]
	var kinds: Array = []
	match theme:
		"cave", "flooded": kinds = ["stalagmite", "rock", "rock", "pebbles"]
		"crystal": kinds = ["crystal", "crystal", "rock", "stalagmite"]
		"mine": kinds = ["rock", "crate", "barrel", "pebbles"]
		"hideout": kinds = ["crate", "barrel", "crate", "bones"]
		"warren": kinds = ["bones", "rock", "pebbles", "barrel"]
		"crypt": kinds = ["pillar", "urn", "bones", "rubble"]
	var count := clampi(int(_room_area(cells, room_of, side, rid) * 0.35), 3, 14)
	for i in count:
		# hug walls: pick a wall cell rather than the middle of the room
		var w := _pick_wall(gen, rid, true)
		if w == {}:
			continue
		var kind: String = kinds[rng.randi() % kinds.size()]
		var inward := Vector3(sin(float(w["yaw"])), 0, cos(float(w["yaw"])))
		var pos: Vector3 = (w["pos"] as Vector3) + inward * rng.randf_range(0.2, 1.2) + inward.cross(Vector3.UP) * rng.randf_range(-1.0, 1.0)
		content["clutter"].append({"kind": kind, "pos": pos, "yaw": rng.randf() * TAU, "scale": rng.randf_range(0.7, 1.4), "room": rid})


static func _guard(gen: Dictionary, content: Dictionary, pool: Array, rid: int, count: int, lmin: int, lmax: int, rng: RandomNumberGenerator, asleep: bool) -> void:
	var side: int = gen["side"]
	var uid: Array = gen["uid"]
	for i in count:
		var kind: String = pool[rng.randi() % pool.size()]
		var p := _pick_cell(gen, rid, 1)
		content["creatures"].append({"id": _uid(uid, "m"), "kind": kind, "pos": _cell_pos(side, p), "room": rid,
			"level": rng.randi_range(lmin, lmax), "asleep": asleep or (kind == "bat" and rng.randf() < 0.5), "boss": false,
			"yaw": rng.randf() * TAU})


static func _boss(gen: Dictionary, content: Dictionary, T: Dictionary, theme: String, tier: int, lmax: int, rid: int, rng: RandomNumberGenerator) -> void:
	var side: int = gen["side"]
	var uid: Array = gen["uid"]
	var b: Dictionary = T["boss"]
	var centre: Vector2i = gen["rooms"][rid]["center"]
	gen["used"][centre] = true
	var boss_level := mini(lmax + 2 + tier, 60)
	content["creatures"].append({"id": "boss", "kind": b["kind"], "pos": _cell_pos(side, centre), "room": rid, "level": boss_level,
		"asleep": true, "boss": true, "name": b["name"], "scale": float(b["scale"]), "trophy": b["trophy"], "yaw": rng.randf() * TAU})
	content["boss"] = {"id": "boss", "kind": b["kind"], "name": b["name"], "trophy": b["trophy"], "room": rid, "level": boss_level,
		"tier": tier, "theme": theme}
	# the reward chest appears where the boss falls (dungeon_build spawns it); its loot is rolled now
	content["boss_loot"] = roll_loot(rng, mini(tier + 1, 4), 1.5)
	# a torch or two so the chamber reads as a place, plus a few cracked pillars
	for k in 2:
		var w := _pick_wall(gen, rid, true)
		if w != {}:
			content["lights"].append({"id": _uid(uid, "t"), "kind": "brazier" if theme in ["crypt", "hideout", "mine"] else "campfire",
				"pos": w["pos"], "yaw": w["yaw"], "color": Color(1.0, 0.55, 0.3) if theme != "crystal" else Color(0.75, 0.45, 1.0),
				"range": 12.0, "energy": 1.8, "room": rid})


static func _chest(gen: Dictionary, content: Dictionary, rid: int, tier: int, vault: bool, rng: RandomNumberGenerator, label: String) -> void:
	var w := _pick_wall(gen, rid, false)
	var side: int = gen["side"]
	var pos: Vector3
	var yaw := 0.0
	if w == {}:
		pos = _cell_pos(side, _pick_cell(gen, rid, 1))
	else:
		pos = w["pos"]
		yaw = w["yaw"]
	var cid := _uid(gen["uid"], "k")
	content["chests"].append({"id": cid, "pos": pos, "yaw": yaw, "tier": clampi(tier, 1, 4), "room": rid, "vault": vault,
		"label": label, "loot": roll_loot(rng, clampi(tier, 1, 4), 2.0 if vault else 1.0)})


static func _chest_item(gen: Dictionary, content: Dictionary, rid: int, item: String, n: int, rng: RandomNumberGenerator) -> void:
	_chest(gen, content, rid, 1, false, rng, "Old toolbox")
	var last: Dictionary = content["chests"][content["chests"].size() - 1]
	(last["loot"] as Array).append([item, n])


static func _resources(gen: Dictionary, content: Dictionary, T: Dictionary, theme: String, rid: int, rng: RandomNumberGenerator, count: int) -> void:
	var kinds: Array = T["res"]
	var side: int = gen["side"]
	for i in count:
		var kind: String = kinds[rng.randi() % kinds.size()]
		var w := _pick_wall(gen, rid, true)
		var pos: Vector3
		var yaw := rng.randf() * TAU
		if w == {}:
			pos = _cell_pos(side, _pick_cell(gen, rid, 1))
		else:
			pos = w["pos"] + Vector3(sin(float(w["yaw"])), 0, cos(float(w["yaw"]))) * 0.3
			yaw = w["yaw"]
		content["nodes"].append({"id": _uid(gen["uid"], "n"), "kind": kind, "pos": pos, "yaw": yaw, "room": rid,
			"count": rng.randi_range(1, 3), "needs_pick": kind in ["iron_ore", "copper_ore", "coal", "silver_ore", "rift_crystal"]})


static func _lore(gen: Dictionary, content: Dictionary, theme: String, did: String, rid: int, rng: RandomNumberGenerator) -> void:
	var lib: Array = LORE[theme]
	var e: Array = lib[rng.randi() % lib.size()]
	var w := _pick_wall(gen, rid, false)
	var side: int = gen["side"]
	var pos: Vector3 = w["pos"] if w != {} else _cell_pos(side, _pick_cell(gen, rid, 1))
	content["lore"].append({"id": _uid(gen["uid"], "j"), "pos": pos, "yaw": float(w["yaw"]) if w != {} else 0.0, "room": rid,
		"title": e[0], "text": e[1], "fact": e[2], "fact_text": e[1], "kind": "journal" if theme in ["mine", "hideout", "flooded"] else "inscription"})


static func _trap(gen: Dictionary, content: Dictionary, rid: int, tier: int, rng: RandomNumberGenerator) -> void:
	var p := _pick_cell(gen, rid, 1)
	content["traps"].append({"id": _uid(gen["uid"], "tr"), "pos": _cell_pos(gen["side"], p), "room": rid, "damage": 8 + tier * 6, "kind": "spikes"})


# ---------------------------------------------------------------------------------------------
# loot

## item -> [price, weight pool min tier]. Rolled deterministically from a rng so a chest's contents
## are fixed by the dungeon seed. Budget per tier grows roughly 4x from tier 1 to tier 4.
const LOOT := [
	["apple", 1, 1, 1, 3], ["bandage", 4, 1, 1, 3], ["healing_herb", 3, 1, 1, 4], ["coal", 2, 1, 2, 5], ["mushroom", 2, 1, 1, 4],
	["arrowheads", 5, 1, 1, 6], ["iron_ore", 3, 1, 2, 5], ["copper_ore", 2, 1, 2, 5], ["stone", 1, 1, 1, 6], ["leather", 6, 1, 1, 3],
	["healing_salve", 14, 2, 1, 2], ["antidote", 12, 2, 1, 2], ["iron_ingot", 10, 2, 1, 4], ["silver_ore", 14, 2, 1, 3], ["cave_pearl", 18, 2, 1, 2],
	["stamina_draught", 22, 3, 1, 2], ["rift_crystal", 30, 3, 1, 3], ["copper_ring", 16, 3, 1, 1], ["iron_dagger", 18, 3, 1, 1], ["iron_helm", 30, 3, 1, 1],
	["iron_sword", 45, 4, 1, 1], ["old_relic", 70, 4, 1, 1], ["ancient_coin", 25, 4, 2, 5], ["rift_crystal", 30, 4, 2, 3], ["silver_ore", 14, 4, 2, 4],
]
const TIER_VALUE := {1: [12, 30], 2: [40, 90], 3: [110, 220], 4: [260, 520]}
const TIER_GOLD := {1: [4, 14], 2: [14, 40], 3: [40, 110], 4: [110, 300]}


## [[item, count], ...] plus a ["gold", n] entry. `mult` scales the value budget (vaults, boss chests).
static func roll_loot(rng: RandomNumberGenerator, tier: int, mult := 1.0) -> Array:
	tier = clampi(tier, 1, 4)
	var band: Array = TIER_VALUE[tier]
	var budget := rng.randf_range(float(band[0]), float(band[1])) * mult
	var pool: Array = []
	for e: Array in LOOT:
		# an item drops from its own tier up to two tiers above (so tier 4 chests still hold bandages now and then)
		if tier >= int(e[2]) and tier <= int(e[2]) + 2:
			pool.append(e)
	var out: Array = []
	var guard := 0
	while budget > 0.0 and guard < 12 and not pool.is_empty():
		guard += 1
		var e: Array = pool[rng.randi() % pool.size()]
		var n := rng.randi_range(int(e[3]), int(e[4]))
		var cost := float(e[1]) * n
		if cost > budget * 1.35 and n > 1:
			n = maxi(1, int(budget / float(e[1])))
			cost = float(e[1]) * n
		budget -= cost
		var merged := false
		for o: Array in out:
			if o[0] == e[0]:
				o[1] += n
				merged = true
		if not merged:
			out.append([e[0], n])
	var gr: Array = TIER_GOLD[tier]
	out.append(["gold", int(rng.randi_range(int(gr[0]), int(gr[1])) * mult)])
	return out


## Coin value of a loot list (for tests and the map legend).
static func loot_value(loot: Array) -> int:
	var v := 0
	for e: Array in loot:
		if e[0] == "gold":
			v += int(e[1])
			continue
		for l: Array in LOOT:
			if l[0] == e[0]:
				v += int(l[1]) * int(e[1])
				break
	return v
