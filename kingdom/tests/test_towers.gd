extends GdUnitTestSuite
## Dungeon towers (docs/design/DUNGEON_TOWERS.md): seeded labyrinth floors (deterministic, connected, boss reachable), theme
## and level data, gate/stairway rules, first clear only once (player relic vs party), NPC parties racing up the tower,
## boss knowledge, death costs, save round-trip (through JSON) and the floor build time/draw budget.

const Hub := preload("res://scripts/realm/realm_hub.gd")
const TowerData := preload("res://scripts/world/towers/tower_data.gd")
const FG := preload("res://scripts/world/towers/floor_gen.gd")
const FloorBoss := preload("res://scripts/world/towers/floor_boss.gd")
const TowerRun := preload("res://scripts/world/towers/tower_run.gd")
const TID := "ashfall_spire"
const CTX := {"player_pos": Vector2(0, 0), "season": "spring", "at_war": false, "abs_hours": 0.0, "gold": 500}


func _towers() -> RefCounted:
	WorldGen.setup(2024)
	var hub := Hub.new()
	return hub.mod("towers")


func _canon(v: Variant) -> Variant:
	if v is Dictionary:
		var o := {}
		for k: Variant in v:
			o[str(k)] = _canon(v[k])
		return o
	if v is Array:
		var a: Array = []
		for x: Variant in v:
			a.append(_canon(x))
		return a
	if v is int or v is float:
		return snappedf(float(v), 0.0001)
	return v


# ---------------------------------------------------------------- data

func test_data_levels_floors_and_bosses() -> void:
	assert_int(TowerData.floor_count(TID)).is_equal(20)
	assert_int(TowerData.floor_level(TID, 1)).is_equal(5)
	assert_int(TowerData.floor_level(TID, 20)).is_equal(60)
	var last := 0
	for f in range(1, 21):
		var info := TowerData.floor_info(TID, f)
		assert_bool(TowerData.THEMES.has(info["theme"])).is_true()
		assert_int(int(info["level"])).is_greater_equal(last)
		last = int(info["level"])
		for pid: String in info["boss"]["patterns"]:
			assert_bool(TowerData.PATTERNS.has(pid)).is_true()
		assert_bool(String(info["boss"]["name"]) != "").is_true()
	var themes := {}
	for f in range(1, 21):
		themes[TowerData.floor_info(TID, f)["theme"]] = true
	assert_int(themes.size()).is_equal(6)


# ---------------------------------------------------------------- layouts

func test_layouts_are_deterministic_connected_and_boss_reachable() -> void:
	for f in range(1, 21):
		var a := FG.layout(TID, f)
		var b := FG.layout(TID, f)
		assert_bool(a["open"] == b["open"]).is_true()
		assert_bool(a["safe_cell"] == b["safe_cell"] and a["door_cell"] == b["door_cell"]).is_true()
		assert_bool(a["mobs"] == b["mobs"] and a["chests"] == b["chests"] and a["traps"] == b["traps"]).is_true()
		assert_bool(FG.consistent(a)).is_true()
		assert_bool(FG.fully_connected(a)).is_true()
		assert_bool(FG.boss_reachable(a)).is_true()
		var d: Dictionary = a["dist"]
		for ch: Dictionary in a["chests"]:
			assert_bool(d.has(ch["cell"])).is_true()
		assert_bool(d.has(a["safe_cell"])).is_true()
		assert_bool((a["boss_block"] as Rect2i).has_point(a["safe_cell"])).is_false()
		assert_bool(a["safe_cell"] != a["start"]).is_true()
	assert_bool(FG.layout(TID, 3)["open"] != FG.layout(TID, 4)["open"]).is_true()


func test_layout_has_safe_zone_boss_door_stairs_and_content() -> void:
	for f in [1, 7, 13, 20]:
		var L := FG.layout(TID, f)
		assert_int((L["mobs"] as Array).size()).is_greater(5)
		assert_int((L["chests"] as Array).size()).is_greater(2)
		assert_int((L["traps"] as Array).size()).is_greater(2)
		# no mob or trap in the safe zone or the start room
		for m: Dictionary in L["mobs"]:
			assert_bool(m["cell"] != L["safe_cell"] and m["cell"] != L["start"]).is_true()
		for t: Dictionary in L["traps"]:
			assert_bool(t["cell"] != L["safe_cell"] and t["cell"] != L["start"]).is_true()
		# the stairs room is inside the arena, the door leads into it
		assert_bool((L["boss_block"] as Rect2i).has_point(L["stairs_cell"])).is_true()
		assert_bool((L["boss_block"] as Rect2i).has_point(L["arena_cell"])).is_true()
		assert_bool(L["door_cell"] != L["arena_cell"]).is_true()


func test_build_budget_draws_lights_and_time() -> void:
	for f in [1, 2, 3, 4, 5, 6, 13]:
		var L := FG.layout(TID, f)
		var t0 := Time.get_ticks_usec()
		var b := FG.build(L)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		var root: Node3D = b["root"]
		assert_float(ms).is_less(450.0)
		assert_int(FG.draw_estimate(root)).is_less_equal(150)
		assert_int(int(b["lights"])).is_less_equal(FG.MAX_LIGHTS)
		assert_bool((b["points"] as Array).size() > 8).is_true()
		var kinds := {}
		for p: Dictionary in b["points"]:
			kinds[p["kind"]] = true
		for k in ["stairs_down", "gate", "rest", "merchant", "boss_door", "stairs_up", "chest", "trap", "boss_spawn"]:
			assert_bool(kinds.has(k)).is_true()
		root.free()


func test_door_opens_and_closes() -> void:
	var L := FG.layout(TID, 2)
	var b := FG.build(L)
	var door: Node3D = b["door"]
	assert_int((door.get_node("DoorBody") as StaticBody3D).collision_layer).is_equal(1)
	FG.open_door(door)
	assert_int((door.get_node("DoorBody") as StaticBody3D).collision_layer).is_equal(0)
	FG.close_door(door)
	assert_int((door.get_node("DoorBody") as StaticBody3D).collision_layer).is_equal(1)
	(b["root"] as Node3D).free()


# ---------------------------------------------------------------- gates and first clear

func test_gate_and_stairway_rules() -> void:
	var t := _towers()
	assert_bool(t.is_floor_open(TID, 1)).is_true()
	assert_bool(t.is_floor_open(TID, 2)).is_false()
	assert_bool(t.is_floor_open(TID, 21)).is_false()
	assert_bool(t.activate_gate(TID, 1)).is_true()
	assert_bool(t.activate_gate(TID, 1)).is_false()            # once
	assert_bool(t.activate_gate(TID, 2)).is_false()            # sealed: no gate
	assert_bool(t.can_teleport_to(TID, 1)).is_true()
	assert_bool(t.can_teleport_to(TID, 2)).is_false()
	assert_int(t.stairs_up_target(TID, 1)).is_equal(0)
	t.boss_defeated(TID, 1, "player")
	assert_bool(t.is_floor_open(TID, 2)).is_true()
	assert_int(t.stairs_up_target(TID, 1)).is_equal(2)
	assert_bool(t.can_teleport_to(TID, 2)).is_false()          # open but not yet attuned
	assert_bool(t.activate_gate(TID, 2)).is_true()
	assert_bool(t.can_teleport_to(TID, 2)).is_true()
	assert_bool(t.is_floor_open(TID, 3)).is_false()
	var menu: Array = t.teleport_menu(TID)
	assert_int(menu.size()).is_equal(2)
	assert_bool(menu[0]["cleared"]).is_true()
	assert_bool(menu[1]["cleared"]).is_false()


func test_first_clear_happens_once_and_gives_the_relic_once() -> void:
	var t := _towers()
	var r1: Dictionary = t.boss_defeated(TID, 1, "player")
	assert_bool(r1["first_clear"]).is_true()
	assert_bool(r1["player_first"]).is_true()
	assert_bool(not (r1["relic"] as Dictionary).is_empty()).is_true()
	assert_int(int(r1["fame"])).is_greater(0)
	assert_str(String(r1["text"])).contains("falls on floor 1")
	assert_int(t.relics.size()).is_equal(1)
	var r2: Dictionary = t.boss_defeated(TID, 1, "player", true)
	assert_bool(r2["first_clear"]).is_false()
	assert_bool((r2["relic"] as Dictionary).is_empty()).is_true()
	assert_int(int(r2["fame"])).is_equal(0)
	assert_int(t.relics.size()).is_equal(1)
	assert_int(int(t.stats["rematches"])).is_equal(1)
	assert_int(t.highest_cleared(TID)).is_equal(1)
	assert_int((t.announcements as Array).size()).is_equal(1)


func test_party_first_clear_opens_stairs_but_takes_the_relic() -> void:
	var t := _towers()
	var r: Dictionary = t.boss_defeated(TID, 1, "Dawnbreakers")
	assert_bool(r["first_clear"]).is_true()
	assert_bool(r["player_first"]).is_false()
	assert_bool((r["relic"] as Dictionary).is_empty()).is_true()
	assert_bool(t.is_floor_open(TID, 2)).is_true()
	assert_bool(t.boss_dead(TID, 1)).is_true()
	assert_bool(t.player_cleared(TID, 1)).is_false()
	# the player's later kill is a repeat: no relic, but it counts as theirs
	var mine: Dictionary = t.boss_defeated(TID, 1, "player")
	assert_bool(mine["first_clear"]).is_false()
	assert_bool(mine["player_first"]).is_false()
	assert_bool(t.player_cleared(TID, 1)).is_true()
	assert_int(t.relics.size()).is_equal(0)


func test_clear_adds_a_rumour_and_a_fame_relic_item() -> void:
	var hub := Hub.new()
	WorldGen.setup(2024)
	var t: RefCounted = hub.mod("towers")
	var soc: RefCounted = hub.mod("society")
	var before := (soc.rumour_list as Array).size()
	t.boss_defeated(TID, 2, "player")
	assert_int((soc.rumour_list as Array).size()).is_equal(before + 1)
	assert_str(String(soc.rumour_list[-1]["deed"])).is_equal("tower_clear")
	t.boss_defeated(TID, 2, "player", true)
	assert_int((soc.rumour_list as Array).size()).is_equal(before + 1)     # no second rumour
	var rel: Dictionary = TowerData.relic(TID, 2)
	assert_str(String(rel["id"])).is_equal("tower_relic_ashfall_spire_2")
	assert_bool(float(rel["value"]) > 0.0).is_true()


# ---------------------------------------------------------------- knowledge

func test_boss_patterns_are_learned_over_attempts_and_by_scouting() -> void:
	var hub := Hub.new()
	WorldGen.setup(2024)
	var t: RefCounted = hub.mod("towers")
	var soc: RefCounted = hub.mod("society")
	var pats: Array = TowerData.floor_info(TID, 5)["boss"]["patterns"]
	assert_int(t.known_patterns(TID, 5).size()).is_equal(0)
	var seen := {}
	for i in pats.size():
		var learned: String = t.record_attempt(TID, 5, true)
		assert_bool(learned != "").is_true()
		assert_bool(seen.has(learned)).is_false()
		seen[learned] = true
		assert_int(t.known_patterns(TID, 5).size()).is_equal(i + 1)
		assert_bool(soc.knows("tower:%s:5:%s" % [TID, learned])).is_true()
	assert_str(t.record_attempt(TID, 5, true)).is_equal("")
	assert_int(t.attempts_on(TID, 5)).is_equal(pats.size() + 1)
	# scouting teaches everything at once and costs gold the caller pays
	var rep: Dictionary = t.scout_report(TID, 9)
	assert_bool(rep["ok"]).is_true()
	assert_int(t.known_patterns(TID, 9).size()).is_equal((TowerData.floor_info(TID, 9)["boss"]["patterns"] as Array).size())
	assert_bool(t.has_scouted(TID, 9)).is_true()
	assert_bool(t.has_scouted(TID, 10)).is_false()
	assert_int(t.scout_cost(TID, 9)).is_greater(t.scout_cost(TID, 2))
	# party attempts do not teach the player's own patterns
	var before: int = t.known_patterns(TID, 12).size()
	t.record_attempt(TID, 12, false)
	assert_int(t.known_patterns(TID, 12).size()).is_equal(before)
	assert_int(t.attempts_on(TID, 12)).is_equal(1)


# ---------------------------------------------------------------- npc parties

func test_npc_parties_progress_race_and_are_deterministic() -> void:
	var a := _towers()
	var b := _towers()
	for d in range(1, 81):
		a.tick_day(d, CTX)
		b.tick_day(d, CTX)
	assert_bool(_canon(a.serialize()) == _canon(b.serialize())).is_true()
	assert_int(a.parties.size()).is_equal(4)
	var best := 0
	for p: Dictionary in a.parties:
		best = maxi(best, maxi(int(p["floor"]), int(p["best"])))
	assert_int(best).is_greater(1)
	# they race the player: a party first clear opens stairs without any player action
	assert_int(a.world_highest(TID)).is_greater(0)
	assert_bool(a.is_floor_open(TID, a.world_highest(TID) + 1)).is_true()
	assert_bool(a.is_floor_open(TID, a.world_highest(TID) + 2)).is_false()
	assert_int(a.highest_cleared(TID)).is_equal(0)
	assert_int((a.announcements as Array).size()).is_greater(0)
	# not a runaway: nobody has finished a 20 floor tower in 80 days at these levels
	assert_int(a.world_highest(TID)).is_less(20)


func test_camp_adventurers_and_catch_up_stay_cheap() -> void:
	var t := _towers()
	t.catch_up(400, CTX)
	var t0 := Time.get_ticks_usec()
	t.catch_up(400, CTX)
	assert_float(float(Time.get_ticks_usec() - t0) / 1000.0).is_less(400.0)
	var any_camp := false
	for d in range(500, 560):
		t.tick_day(d, CTX)
		if not (t.camp_adventurers(TID) as Array).is_empty():
			any_camp = true
			break
	assert_bool(any_camp).is_true()
	for a: Dictionary in t.camp_adventurers(TID):
		assert_bool(String(a["name"]) != "" and String(a["job"]) != "").is_true()


# ---------------------------------------------------------------- death

func test_death_costs_loot_and_gold_but_is_not_permadeath() -> void:
	var t := _towers()
	t.begin_run(TID)
	t.add_run_loot("iron_ingot", 10)
	t.add_run_loot("bandage", 4)
	t.add_run_loot("", 0, 120)
	var loss: Dictionary = t.death_losses(500)
	assert_int(int(loss["gold"])).is_equal(50)
	assert_int(int((loss["items"] as Dictionary).get("iron_ingot", 0))).is_between(3, 4)
	assert_int(int((loss["items"] as Dictionary).get("bandage", 0))).is_between(1, 2)
	assert_bool(["bruised_ribs", "deep_cut"].has(loss["injury"])).is_true()
	assert_int(int(t.stats["deaths"])).is_equal(1)
	# the run is empty after a death, and banking empties it too
	assert_int((t.run["items"] as Dictionary).size()).is_equal(0)
	t.begin_run(TID)
	t.add_run_loot("stone", 5)
	t.bank_run()
	assert_int((t.death_losses(0)["items"] as Dictionary).size()).is_equal(0)


func test_nothing_is_lost_when_the_run_is_banked() -> void:
	var t := _towers()
	t.begin_run(TID)
	t.add_run_loot("iron_ingot", 10)
	t.bank_run()
	var loss: Dictionary = t.death_losses(100)
	assert_int((loss["items"] as Dictionary).size()).is_equal(0)


# ---------------------------------------------------------------- save

func test_save_round_trip_through_json() -> void:
	var t := _towers()
	t.boss_defeated(TID, 1, "player")
	t.activate_gate(TID, 1)
	t.activate_gate(TID, 2)
	t.record_attempt(TID, 2, true)
	t.begin_run(TID)
	t.add_run_loot("bandage", 3, 10)
	for d in range(1, 30):
		t.tick_day(d, CTX)
	var snap: Dictionary = t.serialize()
	var parsed: Variant = JSON.parse_string(JSON.stringify(snap))
	var u := Hub.new().mod("towers")
	u.deserialize(parsed)
	assert_bool(_canon(u.serialize()) == _canon(snap)).is_true()
	assert_bool(u.player_cleared(TID, 1)).is_true()
	assert_bool(u.can_teleport_to(TID, 2)).is_true()
	assert_bool(u.is_floor_open(TID, 2)).is_true()
	assert_int(u.known_patterns(TID, 2).size()).is_equal(1)
	assert_int(int((u.run["items"] as Dictionary).get("bandage", 0))).is_equal(3)
	# and it keeps ticking identically from the loaded state
	for d in range(30, 40):
		t.tick_day(d, CTX)
		u.tick_day(d, CTX)
	assert_bool(_canon(u.serialize()) == _canon(t.serialize())).is_true()


func test_hub_registers_the_module_and_serializes_it() -> void:
	WorldGen.setup(2024)
	var hub := Hub.new()
	assert_bool(hub.mod("towers") != null).is_true()
	assert_bool((hub.serialize() as Dictionary).has("towers")).is_true()


# ---------------------------------------------------------------- planner and loot

func test_planner_places_the_spire_near_kingsreach_on_dry_ground() -> void:
	WorldGen.setup(2024)
	var found: Dictionary = {}
	for s: Dictionary in WorldGen.sites:
		if String(s.get("kind", "")) == "dungeon_tower":
			found = s
	assert_bool(not found.is_empty()).is_true()
	assert_str(String(found["tower"])).is_equal(TID)
	var k := Vector2.ZERO
	for st: Dictionary in WorldGen.settlements:
		if String(st["name"]) == "Kingsreach":
			k = st["pos"]
	var d := (found["pos"] as Vector2).distance_to(k)
	assert_float(d).is_between(1200.0, 2500.0)
	assert_bool(WorldGen.near_water((found["pos"] as Vector2).x, (found["pos"] as Vector2).y, 100.0)).is_false()
	assert_float(float(found["clear"])).is_greater(100.0)
	# deterministic for a seed
	var again := preload("res://scripts/world/towers/tower_planner.gd").sites(2024, WorldGen.sites.filter(func(s: Dictionary) -> bool: return s["kind"] != "dungeon_tower"))
	assert_int(again.size()).is_equal(1)
	assert_vector(again[0]["pos"]).is_equal(found["pos"])


func test_loot_fallback_items_exist() -> void:
	var items: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	for tier in [1, 2, 3, 4, 6]:
		var table: Array = TowerRun.loot_table_for(tier, "ruins")
		assert_int(table.size()).is_greater(3)
		for id: String in table:
			assert_bool((items as Dictionary).has(id)).is_true()


# ---------------------------------------------------------------- boss brain (no scene needed)

func test_boss_phases_enrage_and_pattern_unlocks() -> void:
	var info: Dictionary = TowerData.floor_info(TID, 10)["boss"]
	var b := FloorBoss.new()
	b.setup(info, true, 10, TID, [], 7)
	assert_int(b.max_health).is_equal(TowerData.boss_hp(10))
	assert_int(b._available().size()).is_equal(2)
	var phases: Array[int] = []
	b.phase_changed.connect(func(p: int) -> void: phases.append(p))
	var enraged := [false]
	b.enraged.connect(func() -> void: enraged[0] = true)
	b.take_damage(int(b.max_health * 0.3), null, Vector3.ZERO)
	assert_int(b.phase).is_equal(1)
	b.take_damage(int(b.max_health * 0.1), null, Vector3.ZERO)
	assert_int(b.phase).is_equal(2)
	assert_bool(b._available().size() > 2).is_true()
	b.take_damage(int(b.max_health * 0.3), null, Vector3.ZERO)
	assert_int(b.phase).is_equal(3)
	assert_int(b._available().size()).is_equal((info["patterns"] as Array).size())
	assert_bool(enraged[0]).is_false()
	b.take_damage(int(b.max_health * 0.2), null, Vector3.ZERO)
	assert_bool(b.is_enraged).is_true()
	assert_bool(enraged[0]).is_true()
	assert_array(phases).is_equal([2, 3])
	var died := [false]
	b.died.connect(func(_w: Node3D) -> void: died[0] = true)
	b.take_damage(b.max_health, null, Vector3.ZERO)
	assert_bool(b.dead).is_true()
	assert_bool(died[0]).is_true()
	b.free()


func test_known_patterns_get_a_longer_warning() -> void:
	var info: Dictionary = TowerData.floor_info(TID, 4)["boss"]
	var b := FloorBoss.new()
	b.setup(info, true, 4, TID, [], 3)
	assert_bool(b.is_pattern_known("slam")).is_false()
	b.learn("slam")
	assert_bool(b.is_pattern_known("slam")).is_true()
	b.learn("slam")
	assert_int(b.known.size()).is_equal(1)
	b.free()
