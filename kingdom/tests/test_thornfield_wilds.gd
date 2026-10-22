extends GdUnitTestSuite
## F9: the wilds, the Rift and the outpost around Thornfield. The safety/danger gradient (road and runestones safe by day,
## off-road and night not), the bandit camp (roster, bandit-owned strongbox), the hidden places and gather nodes, the
## hand-tuned Rift (entrance -> safe camp -> 3 encounters -> lever gate -> boss -> exit, persistence, draw budget), and the
## Watch Post at the Soldier career's position.

const Wilds := preload("res://scripts/world/thornfield/wilds.gd")
const Sites := preload("res://scripts/world/thornfield/sites.gd")
const WildsHub := preload("res://scripts/world/thornfield/wilds_hub.gd")
const BanditCamp := preload("res://scripts/world/thornfield/bandit_camp.gd")
const HiddenPlaces := preload("res://scripts/world/thornfield/hidden_places.gd")
const GatherNodes := preload("res://scripts/world/thornfield/gather_nodes.gd")
const RiftLayout := preload("res://scripts/world/thornfield/rift_layout.gd")
const RiftDoor := preload("res://scripts/world/thornfield/rift_door.gd")
const RiftExtras := preload("res://scripts/world/thornfield/rift_extras.gd")
const RiftEntrance := preload("res://scripts/world/thornfield/rift_entrance.gd")
const Outpost := preload("res://scripts/world/thornfield/outpost.gd")
const Props := preload("res://scripts/world/thornfield/wilds_props.gd")
const Ownership := preload("res://scripts/sim/ownership.gd")
const Career := preload("res://scripts/sim/soldier_career.gd")
const Gen := preload("res://scripts/interiors/dungeon_gen.gd")
const Build := preload("res://scripts/interiors/dungeon_build.gd")
const WorldState := preload("res://scripts/world/world_state.gd")
const Squad := preload("res://scripts/army/squad.gd")
const Rings := preload("res://scripts/vfx/telegraph_rings.gd")

var _hour_before := 12.0
var _cover_before := Callable()


func before() -> void:
	WorldGen.setup(WorldSim.SEED)


func before_test() -> void:
	_hour_before = WorldSim.time_of_day
	_cover_before = Frontier.runestones.coverage_override
	WorldState.shared().call("clear")


func after_test() -> void:
	WorldSim.time_of_day = _hour_before
	Frontier.runestones.coverage_override = _cover_before
	WorldState.shared().call("clear")


## A point on the road outside the town's radius (the zone there is "road", not "town").
func _road_spot() -> Vector2:
	var c := Wilds.anchor()
	var r := float(Sites.settlement()["radius"]) + 45.0
	var best := Vector2.INF
	var best_d := 1.0e9
	var a := 0.0
	while a < 360.0:
		var p := c + Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a))) * r
		var d := WorldGen.road_distance(p.x, p.y)
		if d < best_d:
			best_d = d
			best = p
		a += 2.0
	return best


## Deep wilds: the ruined shrine, far from any road, in the forest.
func _wild_spot() -> Vector2:
	return Wilds.at(Wilds.hidden_def("ruined_shrine")["offset"])


func _player_at(p: Vector2) -> Node3D:
	var n := Node3D.new()
	var sc := GDScript.new()
	sc.source_code = "extends Node3D\nvar crouching := false\nvar dead := false\nvar hits := 0\nfunc take_damage(a: int, _f: Node = null, _k := Vector3.ZERO) -> void:\n\thits += a\n"
	sc.reload()
	n.set_script(sc)
	n.add_to_group("player")
	add_child(n)
	n.global_position = Vector3(p.x, 0.0, p.y)
	return auto_free(n)


# --- 1. the gradient -------------------------------------------------------------------------------------

func test_danger_is_higher_off_road_and_at_night_than_on_the_road_by_day() -> void:
	var road := _road_spot()
	var wild := _wild_spot()
	assert_float(WorldGen.road_distance(road.x, road.y)).is_less(10.0)
	assert_float(WorldGen.road_distance(wild.x, wild.y)).is_greater(40.0)
	var road_day := Wilds.danger(road, 12.0)
	var wild_day := Wilds.danger(wild, 12.0)
	var road_night := Wilds.danger(road, 3.0)
	var wild_night := Wilds.danger(wild, 3.0)
	assert_float(wild_day).is_greater(road_day)
	assert_float(road_night).is_greater(road_day)
	assert_float(wild_night).is_greater(wild_day)
	assert_float(wild_night).is_greater(road_night)
	assert_float(wild_night).is_greater(road_day * 5.0)
	assert_float(Wilds.safety(road)).is_greater(Wilds.safety(wild))
	assert_str(Wilds.zone(road)).is_equal("road")
	assert_str(Wilds.zone(wild)).is_equal("wilds")
	assert_str(Wilds.zone(Wilds.anchor())).is_equal("town")
	assert_str(Wilds.level_name(road_day)).is_equal("safe")
	assert_str(Wilds.level_name(wild_night)).is_equal("deadly")


func test_the_danger_value_follows_the_game_clock_and_the_runestones() -> void:
	var wild := _wild_spot()
	WorldSim.time_of_day = 12.0
	var noon := Wilds.danger(wild)
	WorldSim.time_of_day = 2.0
	var deep_night := Wilds.danger(wild)
	assert_float(deep_night).is_greater(noon * 2.5)
	# a runestone ward over the same spot makes it safer
	WorldSim.time_of_day = 12.0
	Frontier.runestones.coverage_override = func(p: Vector2) -> float: return 1.0 if p.distance_to(wild) < 100.0 else 0.0
	assert_float(Wilds.danger(wild)).is_less(noon * 0.5)
	assert_float(Wilds.safety(wild)).is_greater(0.7)


func test_wolves_and_ambushes_rise_with_the_danger() -> void:
	var road := _road_spot()
	var wild := _wild_spot()
	assert_int(Wilds.wolf_pack_size(Wilds.danger(road, 12.0))).is_equal(0)
	assert_int(Wilds.wolf_pack_size(Wilds.danger(wild, 12.0))).is_equal(0)
	assert_int(Wilds.wolf_pack_size(Wilds.danger(wild, 21.0))).is_greater_equal(2)
	assert_int(Wilds.wolf_pack_size(Wilds.danger(wild, 3.0))).is_greater_equal(Wilds.wolf_pack_size(Wilds.danger(wild, 18.0)))
	assert_int(Wilds.wolf_pack_size(Wilds.danger(road, 3.0))).is_equal(0)
	assert_int(Wilds.ambush_size(Wilds.danger(road, 3.0))).is_equal(0)
	assert_int(Wilds.ambush_size(Wilds.danger(wild, 3.0))).is_greater_equal(2)
	assert_int(Wilds.ambush_size(Wilds.danger(wild, 12.0))).is_equal(0)


class FakeThreat extends Node:
	var packs: Array = []

	func probe(target: Vector2, count: int) -> Array:
		packs.append([target, count])
		return []


class FakeRoadEvents extends Node:
	var calls: Array = []

	func force_ambush(near_p: Vector2, count := 3) -> void:
		calls.append([near_p, count])


func test_the_hub_says_the_crossing_and_sends_wolves_and_bandits_at_night() -> void:
	var hub: Node = auto_free(WildsHub.new())
	var fake := FakeThreat.new()
	add_child(fake)
	auto_free(fake)
	hub.set("threat", fake)
	add_child(hub)
	var re := FakeRoadEvents.new()
	re.name = "RoadEvents"
	add_child(re)
	auto_free(re)
	var chance: Variant = Wilds.data()["safety"]["ambush"]["chance"]
	Wilds.data()["safety"]["ambush"]["chance"] = 1.0
	WorldSim.time_of_day = 12.0
	assert_str(hub.call("status", _road_spot())).is_equal("road")
	assert_str(hub.call("status", _wild_spot())).is_equal("wilds")
	assert_float(float(hub.get("danger"))).is_greater(0.5)
	# by day off-road: nothing comes
	hub.set("_wolf_cd", 0.0)
	hub.set("_ambush_cd", 0.0)
	var day_out: Dictionary = hub.call("encounters", _wild_spot(), 12.0)
	assert_int(int(day_out["wolves"])).is_equal(0)
	assert_int(int(day_out["ambush"])).is_equal(0)
	# on the road at night: still nothing
	var road_out: Dictionary = hub.call("encounters", _road_spot(), 3.0)
	assert_int(int(road_out["wolves"])).is_equal(0)
	# off-road at night: a pack and an ambush
	var out: Dictionary = hub.call("encounters", _wild_spot(), 3.0)
	assert_int(int(out["wolves"])).is_greater_equal(2)
	assert_int(int(out["ambush"])).is_greater_equal(2)
	assert_int(fake.packs.size()).is_equal(1)
	assert_int(re.calls.size()).is_equal(1)
	# the cooldown holds the next one back
	var again: Dictionary = hub.call("encounters", _wild_spot(), 3.0)
	assert_int(int(again["wolves"])).is_equal(0)
	Wilds.data()["safety"]["ambush"]["chance"] = chance


# --- 2. the bandit camp -------------------------------------------------------------------------------------

func test_bandit_camp_spawns_its_roster_and_the_chest_is_bandit_owned() -> void:
	var camp: Node3D = auto_free(BanditCamp.create(self, Wilds.data()["bandit_camp"]))
	camp.build()
	assert_bool(camp.built).is_true()
	var soldiers: Array = camp.spawn_roster()
	assert_int(soldiers.size()).is_between(4, 6)
	assert_int(camp.bandits().size()).is_equal(soldiers.size())
	var lookouts := 0
	for s: Variant in soldiers:
		assert_int(int((s as Node).get("team"))).is_equal(1)
		var f: Variant = (s as Node).get("_fighter")
		assert_object(f).is_not_null()
		assert_str(String(f.archetype)).is_equal("bandit")        # NpcFighter
		if (s as Node).has_meta("lookout"):
			lookouts += 1
	assert_int(lookouts).is_equal(1)
	# the camp: fire, lookout platform, tents, a chest
	assert_object(camp.find_child("LookoutPlatform", true, false)).is_not_null()
	assert_int(camp.get_tree().get_nodes_in_group("bandit_campfire").size()).is_greater(0)
	assert_object(camp.fire_light).is_not_null()
	var chest: Node3D = camp.chest
	assert_object(chest).is_not_null()
	var owner_key := Ownership.owner_of(chest)
	assert_str(owner_key).is_equal("bandit:thornfield_bandit_camp")
	assert_int(Ownership.kind_of(owner_key)).is_equal(Ownership.Kind.BANDIT)
	assert_bool(Ownership.is_theft(owner_key)).is_false()
	assert_bool(Ownership.is_theft("shop:0:inn")).is_true()          # the rule still bites for everyone else
	for o: Array in chest.call("_menu")["options"]:
		assert_bool(String(o[0]).begins_with("Steal ")).is_false()
	# off the road: well away from the safe stretch
	assert_float(WorldGen.road_distance(camp.center.x, camp.center.y)).is_greater(40.0)
	# killing them all leaves the camp empty for a while
	for s: Variant in soldiers:
		(s as Node).queue_free()
	camp.despawn_roster()
	assert_int(camp.bandits().size()).is_equal(0)


# --- 3. hidden places and gather nodes -----------------------------------------------------------------------

func test_the_hidden_places_are_present_and_interactable() -> void:
	var hp: Node3D = auto_free(HiddenPlaces.new())
	add_child(hp)
	hp.build_all()
	var kinds := {}
	var seen: Array[Vector2] = []
	assert_int(HiddenPlaces.ids().size()).is_between(3, 6)
	for id: String in HiddenPlaces.ids():
		var n: Node3D = hp.places.get(id)
		assert_object(n).override_failure_message(id).is_not_null()
		kinds[String(n.get_meta("kind"))] = true
		var p := HiddenPlaces.pos_of(id)
		assert_bool(WorldGen.near_water(p.x, p.y, 4.0)).override_failure_message(id + " is wet").is_false()
		assert_float(WorldGen.road_distance(p.x, p.y)).override_failure_message(id).is_greater(25.0)
		for q: Vector2 in seen:
			assert_float(p.distance_to(q)).is_greater(30.0)
		seen.append(p)
		var hot: Node = hp.interactable_of(id)
		assert_object(hot).override_failure_message(id + " has nothing to use").is_not_null()
		assert_bool(hot is InteriorDoor or hot is Station or hot.has_meta(Interactable.META)).override_failure_message(id).is_true()
	for k: String in ["cache", "shrine", "cave", "glade", "hermit"]:
		assert_bool(kinds.has(k)).override_failure_message(k).is_true()
	# the cache pays once and stays taken
	var first: String = hp.use("hunters_cache")
	assert_str(first).is_not_empty()
	assert_bool(HiddenPlaces.is_done("hunters_cache")).is_true()
	assert_str(hp.use("hunters_cache")).is_empty()
	# the shrine carries a lore fact; the hermit talks and gives
	var shrine := Wilds.hidden_def("ruined_shrine")
	assert_str(String(shrine["fact"])).is_not_empty()
	var menu: Dictionary = hp.hermit_menu("hermit_hut")
	assert_int((menu["options"] as Array).size()).is_greater(1)
	assert_str(String(menu["body"])).is_not_empty()
	# the cave nook is a real generated mine with ore in it
	var door := hp.interactable_of("cave_nook") as InteriorDoor
	assert_object(door).is_not_null()
	var layout: Dictionary = door.call("layout")
	assert_str(String(layout["theme"])).is_equal("mine")
	assert_int((layout["rooms"] as Array).size()).is_equal(2)
	var ore := 0
	for n2: Dictionary in layout["content"]["nodes"]:
		if String(n2["kind"]) in ["iron_ore", "copper_ore", "coal", "silver_ore"]:
			ore += 1
	assert_int(ore).is_greater(0)
	# the fallen-tree bridge spans the way to the glade
	var glade: Node3D = hp.places["herb_glade"]
	assert_object(glade.find_child("*", true, false)).is_not_null()
	assert_bool(glade.has_meta("bridge_from") and glade.has_meta("bridge_to")).is_true()
	assert_float((glade.get_meta("bridge_from") as Vector2).distance_to(glade.get_meta("bridge_to") as Vector2)).is_between(5.0, 20.0)


func test_gather_nodes_forage_ore_and_deadwood_pay_out_and_regrow() -> void:
	var g: Node3D = auto_free(GatherNodes.new())
	add_child(g)
	var kinds := {}
	for s: Dictionary in g.specs:
		kinds[String(s["kind"])] = true
		var p: Vector2 = s["pos"]
		assert_bool(WorldGen.near_water(p.x, p.y, 3.0)).is_false()
	assert_int(g.specs.size()).is_greater_equal(8)
	for k: String in ["herb", "mushroom", "firewood", "iron", "copper"]:
		assert_bool(kinds.has(k)).override_failure_message(k).is_true()
	g.build_all()
	assert_int(g.live_count()).is_equal(g.specs.size())
	var herb := "n_herb_1"
	var before: int = Life.count("healing_herb")
	var got: int = g.gather(herb, "herb")
	assert_int(got).is_greater(0)
	assert_int(Life.count("healing_herb")).is_equal(before + got)
	assert_int(g.gather(herb, "herb")).is_equal(0)                # bare until it regrows
	var day := WorldSim.day
	WorldSim.day = day + 3
	assert_bool(GatherNodes.ready_now(herb, "herb")).is_true()
	WorldSim.day = day
	assert_int(g.gather("n_wood_1", "firewood")).is_greater(0)
	assert_int(g.gather("n_iron_1", "iron")).is_greater(0)


# --- 4. the Rift -------------------------------------------------------------------------------------------

func test_the_rift_layout_connects_entrance_camp_three_encounters_boss_and_exit() -> void:
	var g := RiftLayout.generate()
	assert_bool(bool(g.get("hand_tuned", false))).is_true()
	assert_int((g["rooms"] as Array).size()).is_equal(5)
	# the exit back to the surface, in the camp
	var ex: Dictionary = g["content"]["exit"]
	assert_bool(ex.has("pos") and ex.has("yaw")).is_true()
	assert_int(RiftLayout.room_at(g, (ex["pos"] as Vector3) + Vector3(sin(float(ex["yaw"])), 0, cos(float(ex["yaw"]))) * 1.9)).is_equal(0)
	# entrance -> camp -> encounter, encounter, encounter -> boss, in that order
	assert_array(RiftLayout.room_path(g, 0, 4)).is_equal([0, 1, 2, 3, 4])
	assert_int(int(g["boss_room"])).is_equal(4)
	# the camp is safe: no hostile in it, but a fire, a quartermaster spot and a bed
	var by_room := {}
	for c: Dictionary in g["content"]["creatures"]:
		by_room[int(c["room"])] = int(by_room.get(int(c["room"]), 0)) + 1
		assert_str(String(c["element"])).is_equal("rift")           # Rift-touched
	assert_bool(by_room.has(0)).is_false()
	for r in [1, 2, 3]:
		assert_int(int(by_room.get(r, 0))).override_failure_message("room %d" % r).is_greater_equal(2)
	assert_int(int(by_room.get(4, 0))).is_equal(1)
	var camp_fire := false
	for l: Dictionary in g["content"]["lights"]:
		if String(l["kind"]) == "campfire" and int(l["room"]) == 0:
			camp_fire = true
	assert_bool(camp_fire).is_true()
	assert_int(RiftLayout.room_at(g, g["content"]["camp"]["quartermaster"])).is_equal(0)
	assert_int(RiftLayout.room_at(g, g["content"]["camp"]["bed"])).is_equal(0)
	assert_int((g["content"]["safe_rooms"] as Array).size()).is_equal(1)
	# flood fill over the open cells: with the gate open every room is reachable from the entrance
	var open_all := Gen.reachable(g, true)
	for r: Dictionary in g["rooms"]:
		assert_bool(open_all.has(r["center"])).override_failure_message("room %d unreachable" % int(r["id"])).is_true()
	# the lever gate: boss sealed while it is shut, everything before it open, and the lever is on the entrance side
	assert_int((g["gates"] as Array).size()).is_equal(1)
	var shut := Gen.reachable(g, false)
	for r in [0, 1, 2, 3]:
		assert_bool(shut.has((g["rooms"][r] as Dictionary)["center"])).is_true()
	assert_bool(shut.has((g["rooms"][4] as Dictionary)["center"])).is_false()
	var lever: Dictionary = g["content"]["levers"][0]
	assert_bool(shut.has(Gen.cell_at(g, lever["pos"]))).is_true()
	assert_int(int(lever["gate"])).is_equal(0)
	# loot chests: three in the encounter rooms, each on the open side of the gate
	assert_int((g["content"]["chests"] as Array).size()).is_equal(3)
	for k: Dictionary in g["content"]["chests"]:
		assert_bool(shut.has(Gen.cell_at(g, k["pos"]))).override_failure_message(String(k["id"])).is_true()
		assert_int((k["loot"] as Array).size()).is_greater(1)
	# the hazard: two vents in the weeping hall
	assert_int((g["content"]["hazards"] as Array).size()).is_equal(2)
	for h: Dictionary in g["content"]["hazards"]:
		assert_int(RiftLayout.room_at(g, h["pos"])).is_equal(2)
	# the mini-boss: a Rift-touched orc, health scaled down from the x5 default
	var boss: Dictionary = {}
	for c2: Dictionary in g["content"]["creatures"]:
		if bool(c2["boss"]):
			boss = c2
	assert_str(String(boss["kind"])).is_equal("orc")
	assert_float(float(boss["hp_mul"])).is_between(1.0, 5.0)
	assert_int(RiftLayout.room_at(g, boss["pos"])).is_equal(4)


func test_the_rift_door_is_a_dungeon_door_with_a_fixed_layout() -> void:
	var door: Node3D = auto_free(RiftDoor.new())
	add_child(door)
	door.call("configure_rift")
	assert_bool(door is InteriorDoor).is_true()
	assert_str(String(door.get("dungeon_id"))).is_equal("thornfield_rift")
	assert_bool(bool(door.call("layout").get("hand_tuned", false))).is_true()
	assert_bool(bool(door.call("_can_enter"))).is_true()
	assert_str(String(door.get("prompt_text"))).contains("Enter")
	var st1: Dictionary = RiftDoor.state_for("thornfield_rift")
	assert_bool(st1 == RiftDoor.state_for("thornfield_rift")).is_true()
	# the mouth in the world sits well off the road, south of Thornfield
	var ent: Node3D = auto_free(RiftEntrance.new())
	add_child(ent)
	ent.build()
	assert_bool(ent.built).is_true()
	assert_object(ent.door).is_not_null()
	assert_float(WorldGen.road_distance(ent.center.x, ent.center.y)).is_greater(60.0)
	assert_bool(WorldGen.near_water(ent.center.x, ent.center.y, 6.0)).is_false()


func _built_rift(creatures: bool, state: Dictionary) -> Node3D:
	var g := RiftLayout.layout()
	var root: Node3D = Build.build(g, state, {"creatures": creatures, "exit_label": "Leave the Cleft"})
	add_child(root)
	return root


func test_the_rift_camp_has_a_quartermaster_shop_a_bed_that_saves_and_working_vents() -> void:
	var root := _built_rift(false, {})
	var ex: Dictionary = RiftExtras.attach(root, RiftLayout.layout())
	var qm: Node3D = ex["quartermaster"]
	var shop: Dictionary = qm.call("open")
	assert_int((shop["options"] as Array).size()).is_greater_equal(4)
	var buys := 0
	for o: Array in shop["options"]:
		if String(o[0]).begins_with("Buy "):
			buys += 1
	assert_int(buys).is_greater_equal(4)
	var gold: int = Game.gold
	Game.gold = 100
	var bought: String = RiftExtras.buy("bandage", 6)
	assert_str(bought).contains("Bought")
	assert_int(Game.gold).is_equal(94)
	Game.gold = 2
	assert_str(RiftExtras.buy("healing_salve", 18)).contains("Not enough")
	Game.gold = gold
	var bed: Node3D = ex["bed"]
	var labels: Array = []
	for o2: Array in (bed.call("open") as Dictionary)["options"]:
		labels.append(String(o2[0]))
	assert_bool(labels.has("Save game")).is_true()
	assert_bool(labels.has("Rest until morning")).is_true()
	# the vents: warn, burst, hurt a player standing on one, quiet again
	var vents: Array = ex["vents"]
	assert_int(vents.size()).is_equal(2)
	var v: Node3D = vents[0]
	var p := _player_at(Vector2.ZERO)
	p.global_position = v.global_position
	v.set("phase", "idle")
	v.set("_t", 0.0)
	var period := float(v.get("period"))
	var warned := false
	var fired := false
	var t := 0.0
	while t < period + 1.0 and not fired:
		fired = bool(v.call("step", 0.1))
		warned = warned or String(v.get("phase")) == "warn"
		t += 0.1
	assert_bool(warned).is_true()
	assert_bool(fired).is_true()
	assert_int(int(p.get("hits"))).is_equal(int(v.get("damage")))
	root.free()


func test_the_boss_arena_uses_the_shared_telegraph_rings_for_its_slam() -> void:
	var root := _built_rift(true, {})
	var boss: Node = null
	for c: Variant in root.creatures:
		if is_instance_valid(c) and String((c as Node).get("cid")) == "boss":
			boss = c
	assert_object(boss).is_not_null()
	assert_str(String(boss.get("element"))).is_equal("rift")
	assert_int(int(boss.get("max_health"))).is_less(int((float(boss.KINDS["orc"]["hp"]) + 12 * 4.5) * 5.0))
	boss.set("_move", "slam")
	boss.set("_winding", 1.35)
	boss.call("_show_telegraph", true)
	var rings: Node = root.get_node_or_null("TelegraphRings")
	assert_object(rings).is_not_null()
	assert_int(int(rings.call("active_count"))).is_equal(1)
	boss.call("_show_telegraph", false)
	root.free()


func test_the_rift_looted_and_boss_state_persists_through_dungeon_persistence() -> void:
	var state := {}
	var root := _built_rift(false, state)
	assert_bool(root.things.has("k1")).is_true()
	root.mark_looted("k1")
	root.open_gate(0, "lever")
	root.free()
	var root2 := _built_rift(false, state)
	assert_bool(root2.things.has("k1")).is_false()           # still looted
	assert_bool(root2.things.has("k2")).is_true()
	assert_bool(root2.gates.has(0)).is_false()               # the Shardglass Door stays open
	root2.free()
	# the boss: kill it, leave, come back
	var state2 := {}
	var root3 := _built_rift(true, state2)
	var boss: Node = null
	for c: Variant in root3.creatures:
		if is_instance_valid(c) and String((c as Node).get("cid")) == "boss":
			boss = c
	assert_object(boss).is_not_null()
	boss.call("take_damage", 999999)
	assert_bool(bool(state2["boss_dead"])).is_true()
	assert_bool((state2["killed"] as Dictionary).has("boss")).is_true()
	root3.free()
	var root4 := _built_rift(true, state2)
	for c2: Variant in root4.creatures:
		assert_str(String((c2 as Node).get("cid"))).is_not_equal("boss")
	root4.free()
	# and through the realm save (the exploration module owns this dictionary when the game runs)
	var ex: Variant = Life.realm.mod("exploration")
	var live: Dictionary = ex.state("thornfield_rift")
	live["looted"]["k3"] = true
	live["boss_dead"] = true
	var saved: Dictionary = ex.serialize()
	ex.deserialize(saved)
	assert_bool(bool(ex.state("thornfield_rift")["boss_dead"])).is_true()
	assert_bool((ex.state("thornfield_rift")["looted"] as Dictionary).has("k3")).is_true()
	(ex.state("thornfield_rift") as Dictionary)["looted"].erase("k3")
	(ex.state("thornfield_rift") as Dictionary)["boss_dead"] = false


func test_the_rift_stays_inside_the_low_draw_budget() -> void:
	var root := _built_rift(false, {})
	RiftExtras.attach(root, RiftLayout.layout())
	var d := Props.draws(root)
	var chunks := int(root.get_meta("chunks"))
	print("RIFT draws=%d chunks=%d tris=%d" % [d, chunks, int(root.get_meta("tris"))])
	assert_int(d).override_failure_message("rift draws %d" % d).is_less_equal(150)
	root.free()


# --- 5. the outpost ---------------------------------------------------------------------------------------

func test_the_outpost_stands_at_the_soldier_careers_position() -> void:
	var data: Dictionary = Career.data()
	var o: Dictionary = (data["posts"]["outposts"] as Array)[0]
	var expect := Wilds.anchor() + Vector2(float((o["offset"] as Array)[0]), float((o["offset"] as Array)[1]))
	var post := Career.resolve_post(WorldGen.settlements)
	assert_str(String(post["kind"])).is_equal("outpost")
	assert_bool((post["pos"] as Vector2).is_equal_approx(expect)).is_true()
	var fort: Node3D = auto_free(Outpost.new())
	add_child(fort)
	assert_bool(fort.matches_career()).is_true()
	assert_bool(fort.center.is_equal_approx(post["pos"])).is_true()
	fort.build()
	assert_bool(fort.built).is_true()
	# the fort fits inside the career's radius for the post
	for run: Array in fort.wall_runs():
		for e: Vector2 in run:
			assert_float(fort.local(e.x, e.y).distance_to(post["pos"])).is_less(float(post["radius"]))
	# palisade (one multimesh), two gates, two towers
	assert_object(fort.palisade).is_not_null()
	assert_int(int(fort.palisade.get_meta("sections"))).is_greater_equal(20)
	assert_int(int(fort.find_child("Gates", true, false).get_meta("gate_count"))).is_equal(2)
	assert_int(fort.find_children("Watchtower*", "MeshInstance3D", true, false).size()).is_equal(2)
	# barracks with an interior door onto an existing interior
	var door: InteriorDoor = fort.barracks_door as InteriorDoor
	assert_object(door).is_not_null()
	assert_bool(ResourceLoader.exists(door.interior_scene)).is_true()
	assert_str(door.prompt_text).contains("Barracks")
	# the captain station, with a menu
	var cap: Node3D = fort.captain
	assert_bool(cap.is_in_group("outpost_captain")).is_true()
	assert_str(String(cap.get_meta("post_id"))).is_equal(String(post["id"]))
	assert_str(String(cap.call("open")["title"])).contains("Captain")
	# the muster yard and its training dummies
	assert_object(fort.muster).is_not_null()
	assert_int(fort.dummies.size()).is_greater_equal(3)
	assert_float(fort.muster_pos().distance_to(post["pos"])).is_less(float(post["radius"]))
	# the garrison: 4-6 guard soldiers (NpcFighter "guard") that patrol
	var sol: Array = fort.spawn_garrison()
	assert_int(sol.size()).is_between(4, 6)
	for s: Variant in sol:
		assert_int(int((s as Node).get("team"))).is_equal(0)
		assert_str(String(((s as Node).get("_fighter") as RefCounted).archetype)).is_equal("guard")
	assert_int(int(fort.patrol_squad.get("order"))).is_equal(Squad.Order.HOLD)
	fort.patrol_tick(5.0)
	assert_int(int(fort.patrol_squad.get("order"))).is_equal(Squad.Order.MOVE)
	fort.despawn_garrison()


func test_the_career_menu_provider_replaces_the_captains_notice() -> void:
	var fort: Node3D = auto_free(Outpost.new())
	add_child(fort)
	fort.build()
	var before_provider := Outpost.menu_provider
	Outpost.menu_provider = func() -> Dictionary: return {"title": "Enlist", "body": "x", "options": []}
	assert_str(String(fort.captain_menu()["title"])).is_equal("Enlist")
	Outpost.menu_provider = before_provider
	assert_str(String(fort.captain_menu()["title"])).contains("Captain")


# ---------------------------------------------------------------- playtest gap: the bedroll says "until morning"
func test_the_bedroll_rests_until_the_next_six_in_the_morning() -> void:
	var day0 := WorldSim.day
	for start: float in [12.0, 20.5, 3.0, 5.9, 6.0]:
		WorldSim.time_of_day = start
		var d := WorldSim.day
		var line := RiftExtras.rest(auto_free(Node.new()))
		assert_float(WorldSim.time_of_day).is_equal_approx(6.0, 0.001)
		var expect_next_day := start >= 6.0 - 0.25 and start < 24.0           # from 05:45 on, "the next 06:00" is tomorrow's
		assert_int(WorldSim.day - d).is_equal(1 if expect_next_day else 0)
		assert_str(line).contains("06:00")
	WorldSim.day = day0


func test_a_noon_nap_on_the_bedroll_is_long_not_two_hours() -> void:
	WorldSim.time_of_day = 12.0
	var before := WorldSim.day * 24.0 + WorldSim.time_of_day
	RiftExtras.rest(auto_free(Node.new()))
	var slept := WorldSim.day * 24.0 + WorldSim.time_of_day - before
	assert_float(slept).is_equal_approx(18.0, 0.01)
	assert_str(String(RiftExtras.bed_menu(auto_free(Node.new()))["options"][0][0])).is_equal("Rest until morning")
