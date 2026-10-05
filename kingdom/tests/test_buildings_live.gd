extends GdUnitTestSuite
## F6 buildings come alive: deterministic layout choice from the building id, the layout kit (every layout has a bed,
## a seat, an owned container and an exit; shops have a counter station), interior light by hour, the household roster
## against the schedule hours, the exit door reaching the spawn point, door passes and the guard lantern cap.

const Layouts := preload("res://scripts/interiors/interior_layouts.gd")
const Light := preload("res://scripts/interiors/interior_light.gd")
const Household := preload("res://scripts/interiors/household.gd")
const Schedule := preload("res://scripts/population/schedule.gd")
const Ownership := preload("res://scripts/sim/ownership.gd")
const BuildingProfiles := preload("res://scripts/world/building_profiles.gd")
const GuardLantern := preload("res://scripts/population/guard_lantern.gd")
const DoorPass := preload("res://scripts/world/door_pass.gd")
const BedProp := preload("res://scripts/interiors/bed_prop.gd")

var _clock := 8.0


func before_test() -> void:
	_clock = WorldSim.time_of_day


func after_test() -> void:
	WorldSim.time_of_day = _clock


## A layout scene built and furnished without a door (no NPC bodies, fixed owner).
func _room(id: String, owner := "household:0:0") -> Node3D:
	var packed := load(Layouts.scene_path(id)) as PackedScene
	var room := packed.instantiate() as Node3D
	room.set("spawn_npcs", false)
	room.set("live_roster", false)
	add_child(room)
	room.call("build_furniture", "test_%s" % id, owner)
	return auto_free(room)


# ---- layout choice -------------------------------------------------------------------------------------

func test_pick_is_deterministic_per_building_id() -> void:
	for cat: String in Layouts.VARIANTS:
		var seen := {}
		for i in 300:
			var id := "b%d_%d" % [i * 7, i * 13 - 90]
			var a := Layouts.pick(cat, id)
			assert_str(Layouts.pick(cat, id)).is_equal(a)
			assert_bool((Layouts.VARIANTS[cat] as Array).has(a)).is_true()
			seen[a] = true
		assert_int(seen.size()).is_equal((Layouts.VARIANTS[cat] as Array).size())    # every variant is used
	# the same lot position always gives the same id, hence the same interior scene
	var lot := Vector2(120.4, -33.6)
	assert_str(BuildingProfiles.building_id(lot)).is_equal(BuildingProfiles.building_id(lot))
	var s1 := BuildingProfiles.interior_scene("mhouse_family", BuildingProfiles.building_id(lot))
	assert_str(BuildingProfiles.interior_scene("mhouse_family", BuildingProfiles.building_id(lot))).is_equal(s1)


func test_profiles_route_buildings_to_layout_kinds() -> void:
	var id := BuildingProfiles.building_id(Vector2(10, 20))
	assert_bool((Layouts.SHOP as Array).has(BuildingProfiles.layout_for("mhouse_trader", id))).is_true()
	assert_bool((Layouts.HOUSE as Array).has(BuildingProfiles.layout_for("mhouse_peasant_a", id))).is_true()
	assert_bool((Layouts.HOUSE as Array).has(BuildingProfiles.layout_for("house_3", id))).is_true()
	assert_bool((Layouts.TAVERN as Array).has(BuildingProfiles.layout_for("inn", id))).is_true()
	assert_str(BuildingProfiles.layout_for("blacksmith", id)).is_empty()     # the smithy keeps its hand-made interior
	assert_str(BuildingProfiles.interior_scene("mhouse_trader", id)).contains("/modular/")
	assert_str(BuildingProfiles.interior_scene("blacksmith", id)).is_equal(BuildingProfiles.INTERIORS["blacksmith"])
	assert_str(BuildingProfiles.interior_scene("mhouse_family")).is_equal(BuildingProfiles.HOUSE_INTERIOR)    # no id: old behaviour
	for lid: String in Layouts.all_ids():
		assert_bool(ResourceLoader.exists(Layouts.scene_path(lid))).is_true()


func test_nine_layouts_exist_in_the_requested_counts() -> void:
	assert_int(Layouts.HOUSE.size()).is_equal(4)
	assert_int(Layouts.SHOP.size()).is_equal(3)
	assert_int(Layouts.TAVERN.size()).is_equal(2)
	for lid: String in Layouts.all_ids():
		assert_bool(Layouts.layout(lid).is_empty()).is_false()
		assert_array(Layouts.problems(Layouts.layout(lid))).is_empty()    # nothing overlaps, leaves the room or blocks the door


# ---- furniture ------------------------------------------------------------------------------------------

func test_every_layout_has_bed_seat_container_and_exit() -> void:
	for lid: String in Layouts.all_ids():
		var l := Layouts.layout(lid)
		var wp: Dictionary = l["waypoints"]
		assert_int((wp["bed"] as Array).size()).is_greater(0)
		assert_int((wp["seat"] as Array).size()).is_greater(0)
		assert_int((wp["hearth"] as Array).size()).is_greater(0)
		var room := _room(lid)
		var c: Dictionary = room.call("furniture_counts")
		assert_int(int(c["beds"])).is_greater(0)
		assert_int(int(c["seats"])).is_greater(0)
		assert_int(int(c["containers"])).is_greater(0)
		var exit: InteriorDoor = room.get("exit_door")
		assert_object(exit).is_not_null()
		assert_bool(exit.is_exit).is_true()
		assert_object(room.find_child("PlayerSpawn", true, false)).is_not_null()
		if String(l["category"]) == "shop":
			assert_int(int(c["stations"])).is_equal(1)
			assert_bool(room.find_child("Service_Merchant", true, false) is Station).is_true()
			assert_int((wp["counter"] as Array).size()).is_greater(0)
		if not (l["loft"] as Dictionary).is_empty():
			assert_int(int(c["ladders"])).is_equal(1)


func test_containers_and_beds_carry_the_household_owner() -> void:
	for lid: String in Layouts.all_ids():
		var owner := "household:2:5"
		var room := _room(lid, owner)
		for cn: Node in room.get("furniture")["containers"]:
			assert_str(Ownership.owner_of(cn)).is_equal(owner)
			assert_bool(cn.has_meta("owner")).is_true()
			assert_bool(Ownership.is_theft(Ownership.owner_of(cn), {"lots": []})).is_true()    # F5 theft rules apply
		for b: Node in room.get("furniture")["beds"]:
			assert_str(Ownership.owner_of(b)).is_equal(owner)
	# a shop owner on a shop layout
	var shop := _room("general_store", "shop:0:general_store")
	for cn: Node in shop.get("furniture")["containers"]:
		assert_str(Ownership.owner_of(cn)).is_equal("shop:0:general_store")


func test_bed_terms_follow_ownership() -> void:
	assert_bool(BedProp.terms("player")["ok"]).is_true()
	assert_int(BedProp.terms("player")["price"]).is_equal(0)
	var rent := BedProp.terms("shop:0:inn")
	assert_bool(rent["ok"]).is_true()
	assert_int(rent["price"]).is_equal(BedProp.BED_PRICE)
	assert_bool(BedProp.terms("household:0:3", {"lots": []})["ok"]).is_false()
	assert_bool(BedProp.terms("household:0:3", {"lots": ["s0:l3"]})["ok"]).is_true()    # your own rented house


func test_draw_budget_per_interior() -> void:
	for lid: String in Layouts.all_ids():
		var room := _room(lid)
		var est: Dictionary = room.call("draw_estimate")
		assert_int(int(est["shell"])).is_less_equal(60)
		assert_int(int(est["lights"])).is_less_equal(2)
		prints("draws", lid, est)


# ---- light by hour --------------------------------------------------------------------------------------

func test_interior_light_changes_with_the_hour() -> void:
	var night := Light.brightness(2.0, "house")
	var dawn := Light.brightness(6.5, "house")
	var noon := Light.brightness(12.0, "house")
	var dusk := Light.brightness(18.5, "house")
	assert_float(noon).is_greater(dawn)
	assert_float(dawn).is_greater(night)
	assert_float(noon).is_greater(dusk)
	assert_float(dusk).is_greater(night)
	assert_float(Light.daylight(3.0)).is_equal(0.0)
	assert_float(Light.daylight(12.0)).is_equal(1.0)
	# windows go cool at night, warm at dawn and dusk, white by day
	var wn := Light.window_color(2.0)
	var wd := Light.window_color(12.0)
	assert_float(wn.b).is_greater(wn.r)
	assert_float(wd.r).is_greater(wn.r)
	var dusk_c := Light.window_color(18.8)
	assert_float(dusk_c.r - dusk_c.b).is_greater(wd.r - wd.b)
	# lit hearths and lamps at night, banked fire by day, a tavern fire never goes out
	assert_bool(Light.lamp_on(22.0)).is_true()
	assert_bool(Light.lamp_on(12.0)).is_false()
	assert_bool(Light.hearth_lit(22.0)).is_true()
	assert_bool(Light.hearth_lit(12.0)).is_false()
	assert_bool(Light.hearth_lit(12.0, true)).is_true()
	assert_bool(bool(Light.state(12.0, "tavern")["hearth_lit"])).is_true()


func test_room_nodes_follow_the_hour() -> void:
	var room := _room("cottage")
	room.call("apply_hour", 12.0)
	var day: Dictionary = room.call("light_report")
	room.call("apply_hour", 23.0)
	var night: Dictionary = room.call("light_report")
	assert_float(float(day["window_energy"])).is_greater(float(night["window_energy"]))
	assert_float(float(day["ambient_energy"])).is_greater(float(night["ambient_energy"]))
	assert_float(float(night["hearth_energy"])).is_greater(float(day["hearth_energy"]))    # lit at night, banked at noon
	assert_float(float(night["room_energy"])).is_greater(0.0)                              # the lamp
	assert_bool((night["window_color"] as Color).is_equal_approx(day["window_color"])).is_false()


# ---- household roster -----------------------------------------------------------------------------------

func test_home_lot_formula_matches_worldsim() -> void:
	var lots: Array = []
	for i in 9:
		lots.append({"pos": Vector2(i * 20.0, i * 5.0), "yaw": 0.0, "asset": "house_1"})
	var s := {"id": 0, "radius": 60.0, "pos": Vector2.ZERO, "plan": {"lots": lots}}
	for person in 40:
		var spot: Vector2 = WorldSim._spot(s, 0, person)
		var lot: Vector2 = lots[Household.home_lot(person, lots.size())]["pos"]
		assert_vector(spot).is_equal_approx(lot + Vector2(0, 4.6), Vector2(0.001, 0.001))


func test_household_roster_matches_schedule_hours() -> void:
	var jobs := [0, 3, 2, 4, 0, 5]          # farmer, guard, merchant, laborer, farmer, woodcutter
	var job_of := func(i: int) -> int: return int(jobs[i % jobs.size()])
	var people: Array = [0, 1, 2, 3, 4, 5]
	# deep night: everybody who is not on the watch is home and asleep
	var night := Household.roster(people, [], [], 2.0, 3, 0, job_of, "house")
	assert_int(night.size()).is_equal(6)
	for e: Dictionary in night:
		assert_str(e["act"]).is_equal("sleep")
	# mid-day on a working day: farmers and woodcutters are out; whoever is in matches the schedule phase
	for hour in [7.0, 9.0, 12.5, 15.0, 18.5, 20.5, 23.0]:
		var r := Household.roster(people, [], [], hour, 3, 0, job_of, "house")
		var expect: Array = []
		for p: int in people:
			if Schedule.phase(int(job_of.call(p)), hour, 0, p, 3) == Schedule.Phase.HOME:
				expect.append(p)
		var got: Array = []
		for e: Dictionary in r:
			got.append(int(e["person"]))
		assert_array(got).is_equal(expect)
	var noon := Household.roster(people, [], [], 10.0, 3, 0, job_of, "house")
	assert_int(noon.size()).is_less(6)
	# meals and fire
	assert_str(Household.home_act(12.5, 1)).is_equal("eat")
	assert_str(Household.home_act(20.0, 1)).is_equal("hearth")
	assert_str(Household.home_act(23.0, 1)).is_equal("sleep")
	assert_str(Household.home_act(5.0, 1)).is_equal("sleep")
	# the merchant works the counter during the day in a shop, and is not there in the middle of the night
	var shop_day := Household.roster([], [2], [], 11.0, 3, 0, job_of, "shop")
	assert_int(shop_day.size()).is_equal(1)
	assert_str(shop_day[0]["act"]).is_equal("counter")
	assert_int(Household.roster([], [2], [], 2.0, 3, 0, job_of, "shop").size()).is_equal(0)


func test_roster_places_everyone_on_their_own_waypoint() -> void:
	var l := Layouts.layout("family_loft")
	var entries: Array = []
	for i in 6:
		entries.append({"person": i, "act": "sleep", "role": "resident"})
	var placed := Household.place(entries, l["waypoints"])
	assert_int(placed.size()).is_equal((l["waypoints"]["bed"] as Array).size())
	var seen := {}
	for e: Dictionary in placed:
		var key := "%s" % [e["wp"]["p"]]
		assert_bool(seen.has(key)).is_false()
		seen[key] = true
	# the loft beds are real waypoints above the ground floor
	var high := false
	for e: Dictionary in placed:
		high = high or float(e["wp"]["p"].y) > 2.0
	assert_bool(high).is_true()


# ---- exit door ------------------------------------------------------------------------------------------

func test_exit_door_trigger_reaches_the_spawn_point() -> void:
	for lid: String in Layouts.all_ids():
		var l := Layouts.layout(lid)
		var box := Layouts.exit_box(l)
		assert_bool(box.grow(-0.3).has_point(Layouts.spawn_point(l) + Vector3(0, 1.0, 0))).is_true()
		var room := _room(lid)
		var exit: InteriorDoor = room.get("exit_door")
		var spawn := room.find_child("PlayerSpawn", true, false) as Node3D
		var cs := exit.get_child(0) as CollisionShape3D
		var local := exit.to_local(spawn.global_position)
		var half := (cs.shape as BoxShape3D).size * 0.5
		assert_float(absf(local.x - cs.position.x)).is_less(half.x)
		assert_float(absf(local.z - cs.position.z)).is_less(half.z)
		assert_float(exit.global_position.distance_to(spawn.global_position)).is_less(1.5)    # inside Interactable range


func test_cover_point_grows_a_short_exit_box() -> void:
	# the hand-made box: 1.6 x 2.2 x 1 at the door, the spawn 1.1 m in front of it
	var r := InteriorDoor.reach_box(Vector3(1.6, 2.2, 1.0), Vector3(0, 1.1, 0), Vector3(0, 0, 1.1), 0.35)
	assert_bool(r.is_empty()).is_false()
	var size: Vector3 = r["size"]
	var c: Vector3 = r["centre"]
	assert_float(c.z + size.z * 0.5).is_greater_equal(1.1 + 0.35 - 0.001)
	assert_float(c.z - size.z * 0.5).is_less_equal(-0.5 + 0.001)       # still covers the door itself
	assert_float(size.x).is_equal_approx(1.6, 0.001)
	# already inside: unchanged
	assert_bool(InteriorDoor.reach_box(Vector3(2, 2, 4), Vector3.ZERO, Vector3(0, 0, 0.5)).is_empty()).is_true()
	# a live area gets its shape replaced
	var door := InteriorDoor.new()
	door.is_exit = true
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.6, 2.2, 1.0)
	cs.shape = bs
	door.add_child(cs)
	add_child(door)
	auto_free(door)
	door.cover_point(door.to_global(Vector3(0, 0, 1.1)))
	assert_float((cs.shape as BoxShape3D).size.z).is_greater(1.4)
	assert_float(bs.size.z).is_equal_approx(1.0, 0.001)       # the shared sub-resource was copied, not edited


# ---- guards and doors -----------------------------------------------------------------------------------

func test_guard_lantern_cap_is_four_nearest() -> void:
	var guards: Array = []
	for i in 9:
		var g := Node3D.new()
		add_child(g)
		g.global_position = Vector3(float(i) * 6.0, 0, 0)
		GuardLantern.attach(g)
		guards.append(auto_free(g))
	var on := GuardLantern.update(get_tree(), Vector3.ZERO, 23.0)
	assert_int(on).is_equal(GuardLantern.MAX_LIT)
	var lit: Array = []
	for i in 9:
		var light := (guards[i] as Node3D).get_node("GuardLantern/Light") as OmniLight3D
		assert_bool((guards[i] as Node3D).get_node("GuardLantern").visible).is_true()    # every lantern glows
		if light.visible:
			lit.append(i)
	assert_array(lit).is_equal([0, 1, 2, 3])
	# the focus moves: the nearest four change
	assert_int(GuardLantern.update(get_tree(), Vector3(48, 0, 0), 23.0)).is_equal(4)
	assert_bool(((guards[8] as Node3D).get_node("GuardLantern/Light") as OmniLight3D).visible).is_true()
	assert_bool(((guards[0] as Node3D).get_node("GuardLantern/Light") as OmniLight3D).visible).is_false()
	# daytime: dark and hidden
	assert_int(GuardLantern.update(get_tree(), Vector3.ZERO, 12.0)).is_equal(0)
	assert_bool((guards[0] as Node3D).get_node("GuardLantern").visible).is_false()
	assert_array(GuardLantern.nearest([{"id": "a", "dist": 5.0}, {"id": "b", "dist": 1.0}, {"id": "c", "dist": 3.0}], 2)).is_equal(["b", "c"])
	assert_bool(GuardLantern.night(22.0)).is_true()
	assert_bool(GuardLantern.night(3.0)).is_true()
	assert_bool(GuardLantern.night(12.0)).is_false()


func test_door_pass_only_where_it_can_be_seen() -> void:
	assert_bool(DoorPass.worth_animating(10.0, 3.0)).is_true()
	assert_bool(DoorPass.worth_animating(90.0, 3.0)).is_false()      # the player is far away: no animation, no cost
	assert_bool(DoorPass.worth_animating(10.0, 20.0)).is_false()
	var door := InteriorDoor.new()
	add_child(door)
	auto_free(door)
	assert_bool(door.is_in_group("entrance_door")).is_true()
	door.npc_pass()
	assert_object(door.get_node_or_null("NpcLeaf")).is_not_null()    # the leaf swings, then frees itself
	assert_object(DoorPass.nearest_door(get_tree(), door.global_position + Vector3(2, 0, 0))).is_same(door)
