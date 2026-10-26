extends GdUnitTestSuite
## Labyrinths (scripts/dungeon/): hand-designed room templates, seeded floor generator (determinism, connectivity,
## guaranteed start -> safe -> mid-boss -> boss path, boss door gating, no overlapping rooms), nav mesh bake, state save/load
## roundtrip, floor unlock progression, difficulty scaling, entrance hooks, and a 100-seed fuzz. All headless, no GPU.

const Data := preload("res://scripts/dungeon/labyrinth_data.gd")
const Gen := preload("res://scripts/dungeon/labyrinth_gen.gd")
const State := preload("res://scripts/dungeon/labyrinth_state.gd")
const Sites := preload("res://scripts/dungeon/labyrinth_sites.gd")
const Build := preload("res://scripts/dungeon/labyrinth_build.gd")
const Creature := preload("res://scripts/interiors/dungeon_creature.gd")

const SEEDS := [1, 7, 42, 1066, 31337, 987654]


# --- templates -----------------------------------------------------------------------------------

func test_templates_are_well_formed() -> void:
	var roles := {}
	for id: String in Data.TEMPLATES:
		var rows: Array = Data.TEMPLATES[id]["rows"]
		var w := (rows[0] as String).length()
		for r: String in rows:
			assert_int(r.length()).override_failure_message("%s: ragged rows" % id).is_equal(w)
		for role: String in Data.TEMPLATES[id]["roles"]:
			roles[role] = true
		# passable cells are one connected blob
		var cells: Array[Vector2i] = []
		for y in rows.size():
			for x in w:
				if not "#L".contains((rows[y] as String)[x]):
					cells.append(Vector2i(x, y))
		var seen := {cells[0]: true}
		var stack: Array[Vector2i] = [cells[0]]
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			for d in Gen.DIRS:
				var n := c + d
				if cells.has(n) and not seen.has(n):
					seen[n] = true
					stack.append(n)
		assert_int(seen.size()).override_failure_message("%s: floor cells are not connected" % id).is_equal(cells.size())
		# every side offers a plain door cell with walkable floor just inside
		for d in Gen.DIRS:
			var ok := false
			var ra := {"rows": rows, "w": w, "h": rows.size(), "x": 0, "y": 0}
			ok = Gen._door_cell(ra, d, Vector2i(0, 0)).x >= 0
			assert_bool(ok).override_failure_message("%s: no door cell on side %s" % [id, str(d)]).is_true()
	for role in ["start", "safe", "combat", "midboss", "boss", "treasure", "trap", "secret"]:
		assert_bool(roles.has(role)).override_failure_message("no template for role %s" % role).is_true()


func test_orient_keeps_shape_and_markers() -> void:
	var rows: Array = Data.TEMPLATES["boss_arena"]["rows"]
	for mode in 8:
		var o: Array = Gen._orient(rows, mode)
		var count := 0
		for r: String in o:
			count += r.count("X") * 100 + r.count("B") * 10 + r.count("S")
		assert_int(count).is_equal(1 * 100 + 1 * 10 + 8)


# --- determinism ---------------------------------------------------------------------------------

func test_same_seed_same_floor() -> void:
	for lid: String in Data.DEFS:
		for sd: int in SEEDS:
			var a := Gen.generate_floor(lid, sd, 2)
			var b := Gen.generate_floor(lid, sd, 2)
			assert_int(Gen.signature(a)).is_equal(Gen.signature(b))
			assert_array(a["content"]["chests"]).is_equal(b["content"]["chests"])
			assert_array(a["content"]["creatures"]).is_equal(b["content"]["creatures"])
	var base := Gen.generate_floor("deepdark", 5, 0)
	assert_bool(Gen.signature(base) == Gen.signature(Gen.generate_floor("deepdark", 6, 0))).is_false()
	assert_bool(Gen.signature(base) == Gen.signature(Gen.generate_floor("deepdark", 5, 1))).is_false()
	assert_bool(Gen.signature(base) == Gen.signature(Gen.generate_floor("ironmarch_deeps", 5, 0))).is_false()


# --- structure -----------------------------------------------------------------------------------

func test_critical_path_start_safe_midboss_boss() -> void:
	for lid: String in Data.DEFS:
		for sd: int in SEEDS:
			for f in 3:
				var L := Gen.generate_floor(lid, sd, f)
				assert_bool(L.is_empty()).is_false()
				var path: Array = L["path"]
				var roles: Array = []
				for rid: int in path:
					roles.append(L["rooms"][rid]["role"])
				assert_str(roles[0]).is_equal("start")
				assert_str(roles[roles.size() - 1]).is_equal("boss")
				var si := roles.find("safe")
				var mi := roles.find("midboss")
				assert_bool(si > 0 and mi > si and mi < roles.size() - 1).override_failure_message("%s %d f%d order %s" % [lid, sd, f, str(roles)]).is_true()
				# consecutive critical rooms share an edge (corridor) so the path exists on the grid too
				for i in range(path.size() - 1):
					var linked := false
					for e: Dictionary in L["edges"]:
						if e["a"] == path[i] and e["b"] == path[i + 1]:
							linked = true
					assert_bool(linked).override_failure_message("%s %d f%d: no corridor %d -> %d" % [lid, sd, f, path[i], path[i + 1]]).is_true()
				assert_int(L["start_room"]).is_equal(path[0])
				assert_int(L["boss_room"]).is_equal(path[path.size() - 1])
				assert_int(L["safe_room"]).is_equal(path[si])
				assert_int(L["midboss_room"]).is_equal(path[mi])


func test_connectivity_and_boss_door() -> void:
	for sd: int in SEEDS:
		for f in 4:
			var L := Gen.generate_floor("deepdark", sd, f)
			var main := Gen.rooms_reachable(L, {"secret": false, "boss_door": true})
			var all := Gen.rooms_reachable(L, {"secret": true, "boss_door": true})
			var shut := Gen.rooms_reachable(L, {"secret": true, "boss_door": false})
			var secret_n := 0
			for r: Dictionary in L["rooms"]:
				assert_bool(all.has(r["id"])).is_true()
				if r["secret"]:
					secret_n += 1
					assert_bool(main.has(r["id"])).override_failure_message("secret room %d visible without searching" % r["id"]).is_false()
				else:
					assert_bool(main.has(r["id"])).is_true()
			assert_int(secret_n).is_between(1, 2)
			# boss: unreachable until the big door opens, reachable after; only one door into it
			assert_bool(shut.has(L["boss_room"])).is_false()
			assert_bool(main.has(L["boss_room"])).is_true()
			var boss_doors := 0
			for e: Dictionary in L["edges"]:
				if e["a"] == L["boss_room"] or e["b"] == L["boss_room"]:
					boss_doors += 1
					assert_str(e["kind"]).is_equal("boss_door")
			assert_int(boss_doors).is_equal(1)
			# stairs down sit in the boss room, stairs up in the first room
			assert_int(L["room_of"][L["stairs_down"].y * L["w"] + L["stairs_down"].x]).is_equal(L["boss_room"])
			assert_int(L["room_of"][L["stairs_up"].y * L["w"] + L["stairs_up"].x]).is_equal(L["start_room"])
			assert_int(L["room_of"][L["warp_cell"].y * L["w"] + L["warp_cell"].x]).is_equal(L["safe_room"])


func test_no_overlapping_rooms_and_corridors_clear_of_rooms() -> void:
	for sd: int in SEEDS:
		var L := Gen.generate_floor("ironmarch_deeps", sd, 3)
		var rooms: Array = L["rooms"]
		for i in rooms.size():
			var a := Rect2i(rooms[i]["x"], rooms[i]["y"], rooms[i]["w"], rooms[i]["h"])
			assert_bool(a.position.x >= 2 and a.position.y >= 2 and a.end.x <= L["w"] - 2 and a.end.y <= L["h"] - 2).is_true()
			for j in range(i + 1, rooms.size()):
				var b := Rect2i(rooms[j]["x"], rooms[j]["y"], rooms[j]["w"], rooms[j]["h"])
				assert_bool(a.intersects(b)).override_failure_message("rooms %d/%d overlap" % [i, j]).is_false()
				assert_bool(a.grow(Gen.GAP).intersects(b)).override_failure_message("rooms %d/%d closer than the gap" % [i, j]).is_false()
		# a corridor cell only ever touches a room through one of that room's door cells
		var w: int = L["w"]
		for y in L["h"]:
			for x in w:
				if L["cells"][y * w + x] != Gen.CORR:
					continue
				for d in Gen.DIRS:
					var n := Vector2i(x, y) + d
					if n.x < 0 or n.y < 0 or n.x >= w or n.y >= L["h"]:
						continue
					var k: int = L["cells"][n.y * w + n.x]
					if k == Gen.ROOM or k == Gen.PILLAR:
						assert_bool(false).override_failure_message("corridor (%d,%d) leaks into room cell %s" % [x, y, str(n)]).is_true()


func test_content_sits_on_free_floor() -> void:
	for lid: String in Data.DEFS:
		for sd: int in SEEDS:
			var L := Gen.generate_floor(lid, sd, 4)
			var used := {}
			var all: Array = []
			all.append_array(L["content"]["creatures"])
			all.append_array(L["content"]["chests"])
			all.append_array(L["content"]["traps"])
			for it: Dictionary in all:
				var c: Vector2i = it["cell"]
				assert_bool(Gen.is_passable(L, c)).override_failure_message("%s: %s on a wall" % [lid, str(it["id"])]).is_true()
				assert_bool(used.has(c)).override_failure_message("%s: two things on %s" % [lid, str(c)]).is_false()
				used[c] = true
				assert_bool(L["doors"].has(c)).is_false()
				assert_bool(c == L["stairs_up"] or c == L["stairs_down"] or c == L["warp_cell"]).is_false()
			assert_bool(L["content"]["boss"].is_empty()).is_false()
			assert_bool(L["content"]["midboss"].is_empty()).is_false()
			assert_int(L["content"]["secrets"].size()).is_greater(0)
			# no monsters in the safe room or the arrival room
			for c: Dictionary in L["content"]["creatures"]:
				assert_bool(c["room"] != L["safe_room"] and c["room"] != L["start_room"]).is_true()
			# secret rooms hold a better chest than a plain combat room
			for ch: Dictionary in L["content"]["chests"]:
				assert_bool(ch["loot"].size() > 0).is_true()


func test_creature_kinds_exist() -> void:
	for tid: String in Data.THEMES:
		var th: Dictionary = Data.THEMES[tid]
		for tier: int in th["pool"]:
			for k: String in th["pool"][tier]:
				assert_bool(Creature.KINDS.has(k)).override_failure_message("%s tier %d: unknown creature %s" % [tid, tier, k]).is_true()
		for b: Array in th["bosses"]:
			assert_bool(Creature.KINDS.has(b[2])).override_failure_message("%s boss %s: unknown kind %s" % [tid, b[0], b[2]]).is_true()
		for t: String in th["traps"]:
			assert_bool(Data.TRAPS.has(t)).is_true()
	for id: String in Data.DEFS:
		for t: String in Data.DEFS[id]["theme_cycle"]:
			assert_bool(Data.THEMES.has(t)).override_failure_message("%s: unknown theme %s" % [id, t]).is_true()


# --- difficulty ----------------------------------------------------------------------------------

func test_difficulty_scales_with_depth() -> void:
	var lvl_prev := -1
	var tier_prev := 0
	for f in 10:
		var L := Gen.generate_floor("deepdark", 99, f)
		assert_int(L["level"]).is_greater(lvl_prev)
		assert_int(L["tier"]).is_greater_equal(tier_prev)
		lvl_prev = L["level"]
		tier_prev = L["tier"]
	var shallow := 0
	var deep := 0
	var hp_a := 0.0
	var hp_b := 0.0
	for sd in 12:
		shallow += Gen.generate_floor("deepdark", sd, 0)["content"]["creatures"].size()
		deep += Gen.generate_floor("deepdark", sd, 8)["content"]["creatures"].size()
		hp_a += Gen.generate_floor("deepdark", sd, 0)["content"]["boss"]["hp_mult"]
		hp_b += Gen.generate_floor("deepdark", sd, 8)["content"]["boss"]["hp_mult"]
	assert_int(deep).is_greater(shallow)
	assert_float(hp_b).is_greater(hp_a)
	# the boss is stronger than the mid-boss on the same floor
	var L2 := Gen.generate_floor("rift_ruins", 3, 3)
	assert_float(L2["content"]["boss"]["hp_mult"]).is_greater(L2["content"]["midboss"]["hp_mult"])
	assert_int(Data.tier_for(0, 10)).is_equal(1)
	assert_int(Data.tier_for(9, 10)).is_equal(4)


func test_floors_are_themed() -> void:
	var seen := {}
	for f in 10:
		var L := Gen.generate_floor("deepdark", 11, f)
		assert_str(L["theme"]).is_equal(Data.theme_of("deepdark", f))
		seen[L["theme"]] = true
	assert_int(seen.size()).is_greater_equal(4)


# --- nav mesh + geometry -------------------------------------------------------------------------

func test_navmesh_bakes_and_covers_rooms() -> void:
	for sd: int in [3, 1066]:
		var L := Gen.generate_floor("deepdark", sd, 1)
		var nm := Build.bake_navmesh(L)
		assert_int(nm.get_polygon_count()).is_greater(0)
		assert_int(nm.get_vertices().size()).is_greater(3)
		for r: Dictionary in L["rooms"]:
			var p := Gen.cell_to_local(L, r["anchor"])
			assert_bool(Build.nav_contains(nm, p)).override_failure_message("nav mesh misses room %d (%s)" % [r["id"], r["role"]]).is_true()
		for key in ["stairs_up", "stairs_down", "warp_cell"]:
			assert_bool(Build.nav_contains(nm, Gen.cell_to_local(L, L[key]))).is_true()
		# a wall cell must not be walkable
		var wall := Vector2i(0, 0)
		assert_bool(Build.nav_contains(nm, Gen.cell_to_local(L, wall))).is_false()


func test_collision_boxes_cover_floor_and_wall() -> void:
	var L := Gen.generate_floor("ironmarch_deeps", 21, 2)
	var floor_cells := 0
	var covered := 0
	for y in L["h"]:
		for x in L["w"]:
			if Gen.is_passable(L, Vector2i(x, y)):
				floor_cells += 1
	for r in Build.merge_rects(L, func(c: Vector2i) -> bool: return Gen.is_passable(L, c)):
		covered += r.size.x * r.size.y
	assert_int(covered).is_equal(floor_cells)
	var walls := 0
	for b: Dictionary in Build.collision_boxes(L):
		if b["wall"]:
			walls += 1
	assert_int(walls).is_greater(0)


func test_build_floor_scene_tags_surfaces() -> void:
	var L := Gen.generate_floor("ironmarch_deeps", 5, 0)
	var root: Node3D = auto_free(Build.build_floor(L))
	var floor_body: StaticBody3D = root.get_node("Floor")
	var wall_body: StaticBody3D = root.get_node("Walls")
	assert_str(String(floor_body.get_meta(&"surface"))).is_equal("wood")        # mine floors are timber
	assert_str(String(wall_body.get_meta(&"surface"))).is_equal("stone")
	assert_int(floor_body.get_child_count()).is_greater(0)
	assert_object(root.get_node("Nav")).is_not_null()
	assert_int(root.get_node("Markers/Creatures").get_child_count()).is_equal(L["content"]["creatures"].size())
	assert_int(root.get_node("Markers/Chests").get_child_count()).is_equal(L["content"]["chests"].size())
	var gates := 0
	for e: Dictionary in L["edges"]:
		if e["kind"] == "boss_door" or e["kind"] == "secret":
			gates += 1
			assert_object(root.get_node("Gate_e%d" % e["id"])).is_not_null()
	assert_int(gates).is_greater(1)
	assert_int(root.get_meta(&"layout_seed")).is_equal(5)
	# the mesh is two merged meshes, not one node per wall
	var meshes := 0
	for n in root.get_children():
		if n is MeshInstance3D:
			meshes += 1
	assert_int(meshes).is_equal(2)


# --- state: progression + save/load --------------------------------------------------------------

func test_floor_unlock_progression() -> void:
	var s := State.new("deepdark", 77)
	assert_bool(s.is_floor_unlocked(1)).is_true()
	assert_bool(s.is_floor_unlocked(2)).is_false()
	assert_bool(s.enter_floor(2)).is_false()
	assert_bool(s.can_open_boss_door(1)).is_false()
	s.kill_midboss(1)
	assert_bool(s.can_open_boss_door(1)).is_true()
	assert_bool(s.stairs_down_open(1)).is_false()
	assert_int(s.kill_boss(1)).is_equal(2)
	assert_bool(s.is_floor_unlocked(2)).is_true()
	assert_bool(s.stairs_down_open(1)).is_true()
	assert_bool(s.enter_floor(2, 5)).is_true()
	assert_int(s.deepest).is_equal(2)
	# killing the same boss again unlocks nothing new; the last floor unlocks nothing and clears the labyrinth
	assert_int(s.kill_boss(1)).is_equal(0)
	for n in range(2, s.floor_count() + 1):
		s.kill_boss(n)
	assert_bool(s.labyrinth_cleared()).is_true()
	assert_int(s.floors_unlocked).is_equal(s.floor_count())
	assert_bool(s.is_floor_unlocked(s.floor_count() + 1)).is_false()


func test_warp_stones_and_gates() -> void:
	var s := State.new("rift_ruins", 5)
	assert_bool(s.can_warp_to(1)).is_false()
	s.touch_warp_stone(1)
	assert_bool(s.can_warp_to(1)).is_true()
	s.touch_warp_stone(3)
	assert_bool(s.can_warp_to(3)).is_false()        # touched but floor 3 never unlocked
	assert_array(s.warp_targets()).is_equal([1])
	var L := s.layout(1)
	assert_bool(Gen.rooms_reachable(L, s.open_gates(1, L)).has(L["boss_room"])).is_false()
	s.kill_midboss(1)
	assert_bool(Gen.rooms_reachable(L, s.open_gates(1, L)).has(L["boss_room"])).is_true()
	# finding a secret door opens the secret room for this save only
	var sec := -1
	for e: Dictionary in L["edges"]:
		if e["kind"] == "secret":
			sec = e["id"]
			break
	var secret_room: int = L["edges"][sec]["b"]
	assert_bool(Gen.rooms_reachable(L, s.open_gates(1, L)).has(secret_room)).is_false()
	s.find_secret(1, sec)
	assert_bool(Gen.rooms_reachable(L, s.open_gates(1, L)).has(secret_room)).is_true()


func test_state_save_load_roundtrip() -> void:
	var s := State.new("ironmarch_deeps", 424242)
	s.kill_midboss(1)
	s.kill_boss(1)
	s.enter_floor(2, 9)
	s.touch_warp_stone(2)
	s.open_chest(1, "f1_ch3")
	s.open_chest(2, "f2_ch0")
	s.disarm_trap(2, "f2_t1")
	s.find_secret(2, 7)
	s.kill_creature(2, "f2_c4", 10)
	s.kill_creature(2, "f2_boss", 10)
	var json := JSON.stringify(s.serialize())
	var parsed: Variant = JSON.parse_string(json)
	assert_bool(parsed is Dictionary).is_true()
	var t := State.from_dict(parsed)
	assert_str(t.labyrinth_id).is_equal("ironmarch_deeps")
	assert_int(t.world_seed).is_equal(424242)
	assert_int(t.floors_unlocked).is_equal(2)
	assert_int(t.deepest).is_equal(2)
	assert_bool(t.boss_dead(1)).is_true()
	assert_bool(t.midboss_dead(1)).is_true()
	assert_bool(t.can_warp_to(2)).is_true()
	assert_bool(t.chest_open(1, "f1_ch3")).is_true()
	assert_bool(t.chest_open(2, "f2_ch0")).is_true()
	assert_bool(t.chest_open(1, "f1_ch0")).is_false()
	assert_bool(t.trap_disarmed(2, "f2_t1")).is_true()
	assert_bool(t.secret_found(2, 7)).is_true()
	assert_bool(t.creature_dead(2, "f2_c4", 12)).is_true()
	assert_bool(t.creature_dead(2, "f2_c4", 10 + State.REPOPULATE_DAYS)).is_false()     # monsters come back
	assert_bool(t.creature_dead(2, "f2_boss", 999)).is_true()                          # bosses do not
	assert_str(JSON.stringify(t.serialize())).is_equal(json)
	# same seed rebuilds the same floors after the reload
	assert_int(Gen.signature(t.layout(2))).is_equal(Gen.signature(s.layout(2)))
	# bad / future saves are ignored
	var u := State.new("deepdark", 1)
	u.deserialize({"version": 99, "id": "deepdark", "seed": 5})
	assert_int(u.world_seed).is_equal(1)


func test_registry_roundtrip_and_enter() -> void:
	var reg := Sites.new(1066)
	assert_int(reg.enter("deepdark")).is_equal(1)
	assert_int(reg.enter("deepdark", 2)).is_equal(0)
	assert_int(reg.enter("nonsense")).is_equal(0)
	reg.state("deepdark").kill_boss(1)
	assert_int(reg.enter("deepdark", 2, 3)).is_equal(2)
	reg.state("rift_ruins").touch_warp_stone(1)
	var data: Dictionary = JSON.parse_string(JSON.stringify(reg.serialize()))
	var reg2 := Sites.new(0)
	reg2.deserialize(data)
	assert_int(reg2.world_seed).is_equal(1066)
	assert_bool(reg2.state("deepdark").is_floor_unlocked(2)).is_true()
	assert_bool(reg2.state("rift_ruins").can_warp_to(1)).is_true()
	assert_int(reg2.state("deepdark").world_seed).is_equal(reg.state("deepdark").world_seed)


# --- entrance hooks ------------------------------------------------------------------------------

func test_entrance_hooks_match_world_sites() -> void:
	assert_str(Sites.labyrinth_for_site({"name": "Deepdark Warren", "kind": "goblin_warren"})).is_equal("deepdark")
	assert_str(Sites.labyrinth_for_site({"name": "Deepvein Mine", "kind": "mine"})).is_equal("ironmarch_deeps")
	assert_str(Sites.labyrinth_for_site({"name": "Coldseam Delve", "kind": "old_mine"})).is_equal("ironmarch_deeps")
	assert_str(Sites.labyrinth_for_site({"name": "Riftglass Cavern", "kind": "cave"})).is_equal("rift_ruins")
	assert_str(Sites.labyrinth_for_site({"name": "Old Ruin", "kind": "rift_ruins"})).is_equal("rift_ruins")
	assert_str(Sites.labyrinth_for_site({"name": "Ashford Inn", "kind": "inn"})).is_equal("")
	var plan := Sites.plan([{"name": "Ashford", "kind": "town"}, {"name": "Deepvein Mine", "kind": "mine"}, {"name": "Ironroot Mine", "kind": "mine"}, {"name": "Deepdark Warren", "kind": "camp"}])
	assert_int(plan.size()).is_equal(2)
	assert_str(plan[0]["labyrinth"]).is_equal("ironmarch_deeps")
	assert_str(plan[0]["name"]).is_equal("Deepvein Mine")        # first match wins
	for id: String in Data.DEFS:
		var info := Sites.entrance_info(id)
		assert_int(info["floors"]).is_greater(3)
		assert_int(info["level_max"]).is_greater(info["level_min"])


func test_real_world_sites_reach_a_labyrinth() -> void:
	WorldGen.setup(1066)
	var plan := Sites.plan(WorldGen.sites)
	var got := {}
	for p: Dictionary in plan:
		got[p["labyrinth"]] = p["name"]
	# the ironmarch mines and the rift caverns exist as world sites today; Deepdark is a camp in layout.json only
	assert_bool(got.has("ironmarch_deeps")).override_failure_message("no mine site matched: %s" % str(got)).is_true()
	assert_bool(got.has("rift_ruins")).override_failure_message("no rift site matched: %s" % str(got)).is_true()


# --- fuzz ----------------------------------------------------------------------------------------

func test_fuzz_100_seeds() -> void:
	var ids := Data.DEFS.keys()
	var fails: Array = []
	for i in 100:
		var lid: String = ids[i % ids.size()]
		var f: int = (i * 7) % int(Data.DEFS[lid]["floors"])
		var sd := 1000 + i * 7919
		var L := Gen.generate_floor(lid, sd, f)
		if L.is_empty():
			fails.append("%s seed %d floor %d: no layout" % [lid, sd, f])
			continue
		var problems := Gen.validate(L)
		if not problems.is_empty():
			fails.append("%s seed %d floor %d: %s" % [lid, sd, f, str(problems)])
		# deterministic on a second run
		if Gen.signature(L) != Gen.signature(Gen.generate_floor(lid, sd, f)):
			fails.append("%s seed %d floor %d: not deterministic" % [lid, sd, f])
		var main := Gen.rooms_reachable(L, {"secret": false, "boss_door": true})
		if not main.has(L["boss_room"]) or not main.has(L["safe_room"]) or not main.has(L["midboss_room"]):
			fails.append("%s seed %d floor %d: critical room unreachable" % [lid, sd, f])
	assert_array(fails).is_empty()
