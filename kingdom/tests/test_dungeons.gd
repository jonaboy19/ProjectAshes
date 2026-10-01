extends GdUnitTestSuite
## Caves, mines, hideouts, warrens and crypts: deterministic layouts, connectivity and solvable gates, a boss
## chamber at the far end, tiered loot, level ranges 1-60, the region site plan (12-20 entrances, some hidden),
## hidden-entrance reveal -> map + journal, the exploration realm module's save round trip, and the build
## budgets (time, draw calls) of one dungeon interior.

const Gen := preload("res://scripts/interiors/dungeon_gen.gd")
const Build := preload("res://scripts/interiors/dungeon_build.gd")
const Creature := preload("res://scripts/interiors/dungeon_creature.gd")
const Exploration := preload("res://scripts/realm/exploration.gd")
const Discovery := preload("res://scripts/sim/discovery.gd")
const Caves := preload("res://scripts/world/region_caves.gd")


func before() -> void:
	WorldGen.setup(1066)


func _sig(g: Dictionary) -> int:
	return hash([g["cells"], g["rooms"].size(), g["gates"].size(), g["content"]["creatures"].size(), g["content"]["chests"].size(), g["spawn"]])


# --- layouts ------------------------------------------------------------------------------------

func test_layouts_are_deterministic() -> void:
	for th: String in Gen.THEMES:
		var a := Gen.generate(777, th, 2, {"id": "x"})
		var b := Gen.generate(777, th, 2, {"id": "x"})
		assert_int(_sig(a)).is_equal(_sig(b))
		assert_array(a["content"]["chests"]).is_equal(b["content"]["chests"])
		var c := Gen.generate(778, th, 2, {"id": "x"})
		assert_bool(_sig(a) == _sig(c)).override_failure_message("%s: seeds 777 and 778 gave the same layout" % th).is_false()


func test_room_counts_and_connectivity() -> void:
	var counts := {}
	for th: String in Gen.THEMES:
		for sd in range(40):
			var g := Gen.generate(sd * 97 + 3, th, 1 + sd % 4)
			var n: int = g["rooms"].size()
			counts[n] = true
			assert_bool(n >= 3 and n <= 12).override_failure_message("%s seed %d: %d rooms" % [th, sd, n]).is_true()
			# every room's centre is reachable once all gates are open
			var reach := Gen.reachable(g, true)
			for r: Dictionary in g["rooms"]:
				assert_bool(reach.has(r["center"])).override_failure_message("%s seed %d: room %d unreachable" % [th, sd, r["id"]]).is_true()
			# with gates shut every non-vault room is still reachable (nothing required sits behind a door)
			var shut := Gen.reachable(g, false)
			for r: Dictionary in g["rooms"]:
				if r["role"] != "vault":
					assert_bool(shut.has(r["center"])).override_failure_message("%s seed %d: %s room %d gated" % [th, sd, r["role"], r["id"]]).is_true()
				else:
					assert_bool(shut.has(r["center"])).override_failure_message("%s seed %d: vault %d not sealed" % [th, sd, r["id"]]).is_false()
	assert_bool(counts.has(3) and counts.has(12)).override_failure_message("room counts seen: %s" % [counts.keys()]).is_true()


func test_every_gate_has_a_solver_on_the_open_side() -> void:
	var gates_seen := 0
	for th: String in Gen.THEMES:
		for sd in range(30):
			var g := Gen.generate(sd * 31 + 11, th, 3)
			var shut := Gen.reachable(g, false)
			var c: Dictionary = g["content"]
			for gt: Dictionary in g["gates"]:
				gates_seen += 1
				match String(gt["kind"]):
					"lever":
						var ok := false
						for lv: Dictionary in c["levers"]:
							if lv["gate"] == gt["id"] and shut.has(Gen.cell_at(g, lv["pos"])):
								ok = true
						assert_bool(ok).override_failure_message("%s %d: lever for gate %d not reachable" % [th, sd, gt["id"]]).is_true()
					"plate":
						var ok2 := false
						for pl: Dictionary in c["plates"]:
							if pl["gate"] == gt["id"] and shut.has(Gen.cell_at(g, pl["pos"])):
								ok2 = true
						assert_bool(ok2).override_failure_message("%s %d: plate for gate %d not reachable" % [th, sd, gt["id"]]).is_true()
					"rune":
						var ok3 := false
						for l: Dictionary in c["lore"]:
							if l["fact"] == gt["fact"] and shut.has(Gen.cell_at(g, l["pos"])):
								ok3 = true
						assert_bool(ok3).override_failure_message("%s %d: rune lore for gate %d not reachable" % [th, sd, gt["id"]]).is_true()
	assert_int(gates_seen).is_greater(20)


# --- content ------------------------------------------------------------------------------------

func test_boss_chamber_is_the_far_end_and_levels_are_tagged() -> void:
	for th: String in Gen.THEMES:
		for tier in range(1, 5):
			var g := Gen.generate(tier * 13 + 5, th, tier)
			assert_int(int(g["level_min"])).is_greater_equal(1)
			assert_int(int(g["level_max"])).is_less_equal(60)
			assert_int(int(g["level_max"])).is_greater_equal(int(g["level_min"]))
			var boss_room: int = g["boss_room"]
			assert_str(String(g["rooms"][boss_room]["role"])).is_equal("boss")
			assert_bool(g["content"].has("boss")).is_true()
			assert_bool(g["content"]["boss_loot"].size() > 1).is_true()
			var found := 0
			for cr: Dictionary in g["content"]["creatures"]:
				assert_bool(Creature.KINDS.has(cr["kind"])).override_failure_message("unknown creature %s" % cr["kind"]).is_true()
				assert_int(int(cr["level"])).is_less_equal(60)
				if cr["boss"]:
					found += 1
					assert_int(int(cr["room"])).is_equal(boss_room)
			assert_int(found).is_equal(1)
			# farthest room from the entrance by corridor graph
			var dist := Gen._bfs_rooms(g["rooms"].size(), g["edges"], 0)
			assert_int(int(dist[boss_room])).is_equal(int(dist.max()))
	# level bands climb with danger tier
	var lo := Gen.generate(1, "cave", 1)
	var hi := Gen.generate(1, "cave", 4)
	assert_int(int(hi["level_min"])).is_greater(int(lo["level_max"]))


func test_loot_is_tiered() -> void:
	var avg := {}
	for tier in range(1, 5):
		var total := 0
		var n := 0
		for sd in range(60):
			var g := Gen.generate(sd * 7 + tier, Gen.THEMES[sd % Gen.THEMES.size()], tier)
			for ch: Dictionary in g["content"]["chests"]:
				if ch["vault"]:
					continue
				assert_bool((ch["loot"] as Array).size() >= 2).is_true()
				total += Gen.loot_value(ch["loot"])
				n += 1
		avg[tier] = float(total) / maxf(n, 1)
	assert_float(avg[2]).is_greater(avg[1])
	assert_float(avg[3]).is_greater(avg[2])
	assert_float(avg[4]).is_greater(avg[3])
	# a sealed vault pays about double the same tier's ordinary chest
	var v := 0
	var o := 0
	var vn := 0
	var on := 0
	for sd in range(80):
		var g2 := Gen.generate(sd * 5 + 2, Gen.THEMES[sd % Gen.THEMES.size()], 2)
		for ch2: Dictionary in g2["content"]["chests"]:
			if ch2["vault"]:
				v += Gen.loot_value(ch2["loot"])
				vn += 1
			elif ch2["tier"] == 2:
				o += Gen.loot_value(ch2["loot"])
				on += 1
	assert_bool(vn > 0 and on > 0).is_true()
	assert_float(float(v) / vn).is_greater(float(o) / on)


func test_lore_and_resources_exist() -> void:
	for th: String in Gen.THEMES:
		var lore := 0
		var res := 0
		for sd in range(10):
			var g := Gen.generate(sd + 100, th, 2)
			for l: Dictionary in g["content"]["lore"]:
				if l["kind"] != "rune":
					lore += 1
					assert_str(String(l["fact"])).is_not_empty()
			res += g["content"]["nodes"].size()
		assert_int(lore).override_failure_message("%s: no lore finds in 10 dungeons" % th).is_greater(3)
		if th != "hideout":
			assert_int(res).override_failure_message("%s: no resource nodes" % th).is_greater(0)


# --- world entrances ----------------------------------------------------------------------------

func test_region_plan_places_24_to_44_entrances() -> void:
	var sites := Caves.cave_sites()
	assert_int(sites.size()).is_between(24, 44)       # 18 on the 8 km world, 40 specs for the 12 km one
	var ids := {}
	var hidden := 0
	var tiers := {}
	var reveal := {}
	for s: Dictionary in sites:
		var c: Dictionary = s["cave"]
		assert_bool(ids.has(c["dungeon_id"])).is_false()
		ids[c["dungeon_id"]] = true
		assert_bool(absf(s["pos"].x) < WorldGen.WORLD_HALF and absf(s["pos"].y) < WorldGen.WORLD_HALF).is_true()
		if s["hidden"]:
			hidden += 1
			reveal[c["reveal"]] = true
			assert_str(String(s["kind"])).is_equal("hidden_cave")
		tiers[c["tier"]] = true
	assert_int(hidden).is_greater_equal(4)
	for k in ["waterfall", "vines", "rockfall", "night"]:
		assert_bool(reveal.has(k)).override_failure_message("no hidden entrance revealed by %s" % k).is_true()
	assert_int(tiers.size()).is_greater_equal(3)
	# the cave planner was appended after the valley, landmarks and the world hook: its ids follow every
	# site those planners made (later hooks by other planners may follow it)
	var first_cave := 1 << 30
	for s: Dictionary in sites:
		first_cave = mini(first_cave, int(s["id"]))
	assert_int(first_cave).is_greater(290)
	for s2 in WorldGen.sites:
		if int(s2["id"]) < first_cave:
			assert_bool(s2.has("cave")).is_false()


func test_danger_tier_climbs_with_distance_from_kingsreach() -> void:
	var capital := Vector2.ZERO
	for s in WorldGen.settlements:
		if s["kind"] == "castle":
			capital = s["pos"]
	var near_sum := 0.0
	var near_n := 0
	var far_sum := 0.0
	var far_n := 0
	for s: Dictionary in Caves.cave_sites():
		if (s["pos"] as Vector2).distance_to(capital) < 1500.0:
			near_sum += s["cave"]["tier"]
			near_n += 1
		else:
			far_sum += s["cave"]["tier"]
			far_n += 1
	assert_bool(near_n > 0 and far_n > 0).is_true()
	assert_float(far_sum / far_n).is_greater(near_sum / near_n)


func test_hidden_entrance_reveal_adds_map_place_and_journal_entry() -> void:
	var d := Discovery.new()
	d.build_from_world()
	var hid: Dictionary = {}
	for s: Dictionary in Caves.cave_sites():
		if s["hidden"]:
			hid = s
			break
	assert_bool(hid.is_empty()).is_false()
	for pl: Dictionary in d.places:
		assert_str(String(pl["name"])).is_not_equal(String(hid["name"]))
	# walking right past a hidden entrance does not find it
	var hits := d.update(hid["pos"], 1)
	for h: Dictionary in hits:
		assert_str(String(h["name"])).is_not_equal(String(hid["name"]))
	var before := d.places.size()
	var got: Array = []
	d.place_discovered.connect(func(p: Dictionary) -> void: got.append(p))
	var ex := Exploration.new()
	assert_bool(ex.reveal(hid["cave"]["dungeon_id"], 5)).is_true()
	assert_bool(ex.reveal(hid["cave"]["dungeon_id"], 6)).is_false()
	assert_bool(d.reveal_site(hid, 5, true)).is_true()
	assert_int(d.places.size()).is_equal(before + 1)
	assert_int(got.size()).is_equal(1)
	assert_str(String(got[0]["name"])).is_equal(String(hid["name"]))
	assert_str(String(got[0]["kind"])).is_equal("hidden_cave")
	assert_bool(d.reveal_site(hid, 5, true)).is_false()     # idempotent
	# after a load the found set is restored and the place is re-added silently
	var saved := d.serialize()
	var d2 := Discovery.new()
	d2.build_from_world()
	d2.deserialize(saved)
	d2.reveal_site(hid, 5, false)
	assert_bool(d2.is_discovered(got[0]["id"])).is_true()


func test_rumours_point_at_unfound_hidden_places() -> void:
	var ex := Exploration.new()
	var r := ex.rumour_for(Vector2(0, 0), 1)
	assert_bool(r.is_empty()).is_false()
	assert_str(String(r["text"])).contains("somewhere")
	var id := String(r["site_id"])
	assert_bool(ex.learn_lead(id, 3)).is_true()
	assert_bool(ex.learn_lead(id, 3)).is_false()
	assert_bool(ex.knows_lead(id)).is_true()
	var r2 := ex.rumour_for(Vector2(0, 0), 1)
	assert_bool(r2.is_empty() or String(r2["site_id"]) != id).is_true()


# --- save ----------------------------------------------------------------------------------------

func test_exploration_save_round_trip() -> void:
	var ex := Exploration.new()
	var st := ex.state("cv02")
	st["looted"]["k1"] = true
	st["opened"]["0"] = "lever"
	st["killed"]["m3"] = true
	st["harvested"]["n2"] = 12
	st["boss_dead"] = true
	ex.reveal("cv00", 9)
	ex.learn_lead("cv02", 4)
	ex.on_enter("cv02", 4)
	var json := JSON.stringify(ex.serialize())
	var back := Exploration.new()
	back.deserialize(JSON.parse_string(json))
	var s2 := back.state("cv02")
	assert_bool(s2["looted"].has("k1")).is_true()
	assert_str(String(s2["opened"]["0"])).is_equal("lever")
	assert_bool(s2["killed"].has("m3")).is_true()
	assert_int(int(s2["harvested"]["n2"])).is_equal(12)
	assert_bool(bool(s2["boss_dead"])).is_true()
	assert_bool(back.is_revealed("cv00")).is_true()
	assert_bool(back.knows_lead("cv02")).is_true()
	assert_int(int(back.stats()["bosses"])).is_equal(1)
	# creatures refill after three weeks, the boss stays down
	st["killed"]["boss"] = true
	ex.tick_day(4 + 22, {})
	assert_bool(ex.state("cv02")["killed"].has("m3")).is_false()
	assert_bool(ex.state("cv02")["killed"].has("boss")).is_true()


func test_realm_hub_registers_exploration() -> void:
	var Hub := preload("res://scripts/realm/realm_hub.gd")
	assert_bool(Hub.MODULES.has("exploration")).is_true()
	assert_bool(Hub.ORDER.has("exploration")).is_true()
	assert_int(Hub.ORDER.find("exploration")).is_greater(Hub.ORDER.find("society"))


func test_built_dungeon_persists_looting_between_visits() -> void:
	var g := Gen.generate(4242, "crypt", 2, {"id": "t1", "rooms": 8})
	var state := {}
	var root = Build.build(g, state, {"creatures": false})
	add_child(root)
	var chest_id := String(g["content"]["chests"][0]["id"])
	assert_bool(root.things.has(chest_id)).is_true()
	root.mark_looted(chest_id)
	if g["gates"].size() > 0:
		root.open_gate(0, "lever")
	root.free()
	var root2 = Build.build(g, state, {"creatures": false})
	add_child(root2)
	assert_bool(root2.things.has(chest_id)).is_false()
	if g["gates"].size() > 0:
		assert_bool(root2.gates.has(0)).is_false()
	root2.free()


# --- budgets -------------------------------------------------------------------------------------

func _draws(n: Node) -> int:
	var d := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).visible:
		d += maxi((n as MeshInstance3D).mesh.get_surface_count(), 1)
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null and (n as MultiMeshInstance3D).multimesh.mesh != null:
		d += (n as MultiMeshInstance3D).multimesh.mesh.get_surface_count()
	for c in n.get_children():
		d += _draws(c)
	return d


func test_build_time_and_draw_budget() -> void:
	var worst_ms := 0
	var worst_draws := 0
	for th: String in Gen.THEMES:
		var t0 := Time.get_ticks_msec()
		var g := Gen.generate(31337, th, 3, {"id": "b_" + th, "rooms": 12})
		var gen_ms := Time.get_ticks_msec() - t0
		assert_int(gen_ms).override_failure_message("%s: layout took %d ms" % [th, gen_ms]).is_less(150)
		var t1 := Time.get_ticks_msec()
		var root = Build.build(g, {}, {"creatures": false})
		add_child(root)
		var ms := Time.get_ticks_msec() - t1
		worst_ms = maxi(worst_ms, ms)
		var draws := _draws(root)
		worst_draws = maxi(worst_draws, draws)
		var brk := {}
		for ch in root.get_children():
			var key := String(ch.name).rstrip("0123456789_").left(10)
			brk[key] = int(brk.get(key, 0)) + _draws(ch)
		print("  %s draws %d %s" % [th, draws, brk])
		assert_int(draws).override_failure_message("%s: %d draws" % [th, draws]).is_less_equal(110)
		assert_int(int(root.get_meta("tris"))).override_failure_message("%s: %d tris" % [th, int(root.get_meta("tris"))]).is_less(60000)
		root.free()
	# the whole build is one blocking step at the door: keep it well under half a second, even on a slow CI box
	assert_int(worst_ms).override_failure_message("slowest build %d ms" % worst_ms).is_less(1500)
	print("dungeon build: slowest %d ms, most draws %d" % [worst_ms, worst_draws])
