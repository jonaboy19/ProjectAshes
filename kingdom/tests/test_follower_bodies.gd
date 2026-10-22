extends GdUnitTestSuite
## Stage 3 recruits with bodies: the embodiment cap, the follow threshold, waiting outside interiors, formation,
## orders (follow / wait / home / work), the budgeted manager, the pruning of old left-follower records, and the
## talk-menu entries (followers, hiring board).

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Rec := preload("res://scripts/realm/recruitment.gd")
const Fol := preload("res://scripts/realm/followers.gd")
const RUI := preload("res://scripts/ui/recruitment_ui.gd")
const Brain := preload("res://scripts/actors/follower_brain.gd")
const Manager := preload("res://scripts/actors/follower_manager.gd")
const M := Brain.Mode


func _hub() -> RefCounted:
	WorldGen.setup(2024)
	return Hub.new()


func _row(skip := 0) -> int:
	var rg: Vector2i = WorldSim.ranges[0]
	var seen := 0
	for i in range(rg.x, rg.y):
		if WorldSim.health[i] == 0:
			continue
		if seen >= skip:
			return i
		seen += 1
	return rg.x


func _hire(hub: RefCounted, skip: int, duty := "guard", chain := "personal") -> String:
	var rc: RefCounted = hub.mod("recruitment")
	var res: Dictionary = rc.engage(_row(skip), Rec.make_terms(60, duty, 0, true), chain, "", {"trust": 40.0, "reputation": 80.0})
	assert_bool(res["ok"]).is_true()
	return res["fid"]


# --- budget and selection ----------------------------------------------------------------------------
func test_embodiment_cap() -> void:
	assert_int(Brain.budget(24)).is_equal(Brain.MAX_EMBODIED)
	assert_int(Brain.budget(8)).is_equal(6)
	assert_int(Brain.budget(5)).is_equal(3)
	assert_int(Brain.budget(1)).is_equal(Brain.MIN_EMBODIED)
	var cands: Array = []
	for i in range(1, 11):
		cands.append({"fid": "f%d" % i, "order": "follow", "fighter": i > 7, "d": 0.0})
	var picked: Array = Brain.select(cands, Brain.budget(24))
	assert_int(picked.size()).is_equal(6)
	assert_array(picked.slice(0, 3)).contains_exactly(["f8", "f9", "f10"])    # fighters first, then by id
	assert_array(picked.slice(3)).contains_exactly(["f1", "f2", "f3"])
	assert_int(Brain.select(cands, 3).size()).is_equal(3)


func test_local_workers_need_the_player_nearby() -> void:
	var cands: Array = [
		{"fid": "f1", "order": "work", "fighter": false, "d": 20.0},
		{"fid": "f2", "order": "work", "fighter": false, "d": 80.0},
		{"fid": "f3", "order": "wait", "fighter": false, "d": 10.0},
		{"fid": "f4", "order": "home", "fighter": false, "d": 5.0},
		{"fid": "f5", "order": "follow", "fighter": false, "d": 0.0},
	]
	var picked: Array = Brain.select(cands, 6)
	assert_array(picked).contains_exactly(["f5", "f3", "f1"])    # followers first, then nearest; far and body-less home: none
	assert_array(Brain.select(cands, 6, {"f4": true, "f2": true})).contains(["f4"])    # a home walker keeps its body
	# Followers take the slots first when the cap is tight.
	assert_array(Brain.select(cands, 1)).contains_exactly(["f5"])
	# hysteresis: an embodied worker just past the range stays, a new one does not
	var edge: Array = [{"fid": "f1", "order": "work", "fighter": false, "d": Brain.LOCAL_RANGE + 5.0}]
	assert_int(Brain.select(edge, 6).size()).is_equal(0)
	assert_int(Brain.select(edge, 6, {"f1": true}).size()).is_equal(1)


func test_a_waiter_nearby_keeps_its_body_over_followers() -> void:
	var cands: Array = [{"fid": "f9", "order": "wait", "fighter": false, "d": 6.0}]
	for i in range(1, 7):
		cands.append({"fid": "f%d" % i, "order": "follow", "fighter": false, "d": 0.0})
	assert_bool(Brain.select(cands, 6).has("f9")).is_false()                      # not yet embodied: followers first
	var kept: Array = Brain.select(cands, 6, {"f9": true})
	assert_bool(kept.has("f9")).is_true()
	assert_int(kept.size()).is_equal(6)


# --- follow threshold, teleport, interiors ---------------------------------------------------------------
func test_follow_threshold_and_catch_up() -> void:
	assert_bool(Brain.should_move(1.0, false)).is_false()                 # near the slot: stands
	assert_bool(Brain.should_move(Brain.FOLLOW_START + 0.1, false)).is_true()
	assert_bool(Brain.should_move(1.5, true)).is_true()                   # already walking: carries on to the stop radius
	assert_bool(Brain.should_move(Brain.FOLLOW_STOP - 0.1, true)).is_false()
	assert_float(Brain.follow_speed(0.5, 3.0, 3.0)).is_equal(0.0)
	assert_float(Brain.follow_speed(6.0, 3.0, 8.0)).is_less_equal(Brain.RUN_SPEED)
	assert_float(Brain.follow_speed(20.0, 6.5, Brain.CATCHUP_DIST + 5.0)).is_greater(Brain.RUN_SPEED)    # catching up beats a run
	assert_int(Brain.decide("follow", {"dist": 4.0})).is_equal(M.FOLLOW)
	assert_int(Brain.decide("follow", {"dist": Brain.CATCHUP_DIST - 0.1})).is_equal(M.FOLLOW)
	assert_int(Brain.decide("follow", {"dist": Brain.CATCHUP_DIST + 0.1})).is_equal(M.CATCHUP)
	assert_int(Brain.decide("follow", {"dist": Brain.TELEPORT_DIST + 1.0})).is_equal(M.TELEPORT)


func test_teleports_on_fast_travel_and_far_behind() -> void:
	assert_bool(Brain.needs_teleport(Brain.TELEPORT_DIST + 1.0, 0.0)).is_true()
	assert_bool(Brain.needs_teleport(20.0, Brain.TELEPORT_JUMP)).is_true()       # the player jumped: fast travel
	assert_bool(Brain.needs_teleport(5.0, Brain.TELEPORT_JUMP + 10.0)).is_false()  # but someone still beside them does not blink
	assert_bool(Brain.needs_teleport(20.0, 3.0)).is_false()
	assert_int(Brain.decide("follow", {"dist": 20.0, "jump": 60.0})).is_equal(M.TELEPORT)


func test_waits_outside_interiors() -> void:
	assert_int(Brain.decide("follow", {"dist": 3.0, "player_inside": true})).is_equal(M.WAIT_OUTSIDE)
	# even far away or after the jump into the interior space: nobody follows indoors, nobody blinks in
	assert_int(Brain.decide("follow", {"dist": 500.0, "jump": 500.0, "player_inside": true, "fighter": true, "foe": true})).is_equal(M.WAIT_OUTSIDE)
	assert_int(Brain.decide("follow", {"dist": 3.0, "player_inside": false})).is_equal(M.FOLLOW)


func test_fighters_fight_beside_the_player() -> void:
	assert_bool(Brain.is_fighter("guard", "builder")).is_true()
	assert_bool(Brain.is_fighter("labor", "mercenary")).is_true()
	assert_bool(Brain.is_fighter("labor", "builder")).is_false()
	assert_int(Brain.decide("follow", {"dist": 4.0, "fighter": true, "foe": true})).is_equal(M.FIGHT)
	assert_int(Brain.decide("follow", {"dist": 4.0, "fighter": false, "foe": true})).is_equal(M.FOLLOW)
	assert_int(Brain.decide("follow", {"dist": Brain.LEASH + 2.0, "fighter": true, "foe": true})).is_not_equal(M.FIGHT)    # leashed
	assert_int(Brain.fighter_rank(0.9)).is_greater(Brain.fighter_rank(0.2))


func test_formation_slots_differ_and_face_the_player() -> void:
	var pp := Vector2(100, 100)
	var seen := {}
	for i in 6:
		var p := Brain.follow_point(pp, 0.0, true, i)
		seen[Vector2(snappedf(p.x, 0.01), snappedf(p.y, 0.01))] = true
		assert_float(p.y).is_less(pp.y)           # behind a player facing +Z
	assert_int(seen.size()).is_equal(6)
	assert_float(Brain.follow_point(pp, 0.0, false, 0).x).is_not_equal(Brain.follow_point(pp, 0.0, false, 1).x)
	# turning the player turns the formation
	var a := Brain.follow_point(pp, 0.0, true, 0)
	var b := Brain.follow_point(pp, PI, true, 0)
	assert_float(a.distance_to(pp)).is_equal_approx(b.distance_to(pp), 0.001)
	assert_float(b.y).is_greater(pp.y)


# --- orders -------------------------------------------------------------------------------------------
func test_orders_and_defaults() -> void:
	var hub := _hub()
	var rc: RefCounted = hub.mod("recruitment")
	var guard := _hire(hub, 0, "guard")
	var hand := _hire(hub, 1, "labor")
	assert_str(rc.effective_order(guard)["order"]).is_equal("follow")      # a guard follows by default
	assert_str(rc.effective_order(hand)["order"]).is_equal("home")         # a labourer with no post is at home
	assert_bool(rc.set_order(hand, "work")["ok"]).is_false()               # work where?
	var gid: String = rc.create_group("property", "mill", "Mill")
	var res: Dictionary = rc.set_order(hand, "work", gid)
	assert_bool(res["ok"]).is_true()
	assert_str(rc.effective_order(hand)["order"]).is_equal("work")
	assert_str(rc.effective_order(hand)["arg"]).is_equal(gid)
	assert_bool(rc.set_order(guard, "wait")["ok"]).is_true()
	assert_str(rc.effective_order(guard)["order"]).is_equal("wait")
	assert_bool(rc.set_order(guard, "follow")["ok"]).is_true()
	assert_bool(rc.set_order(guard, "dance")["ok"]).is_false()
	assert_bool(rc.set_order(guard, "home")["ok"]).is_true()
	# an estate employee does not march on the road
	var emp := _hire(hub, 2, "labor", "property")
	assert_bool(rc.set_order(emp, "follow")["ok"]).is_false()
	# a property employee assigned to a group works there by default
	rc.assign_to_group(emp, gid)
	assert_str(rc.effective_order(emp)["order"]).is_equal("work")
	# orders survive a save
	var fol: RefCounted = hub.mod("followers")
	var d2: Dictionary = JSON.parse_string(JSON.stringify(fol.serialize()))
	var fol2: RefCounted = Fol.new()
	fol2.deserialize(d2)
	assert_str(fol2.get_follower(guard)["order"]).is_equal("home")
	assert_str(fol2.get_follower(hand)["order_arg"]).is_equal(gid)


func test_dismiss_and_raise() -> void:
	var hub := _hub()
	var rc: RefCounted = hub.mod("recruitment")
	var fid := _hire(hub, 0, "guard")
	var before: int = rc.contract_of(fid)["t"]["w"]
	var r: Dictionary = rc.offer_raise(fid, 2)
	assert_bool(r["ok"]).is_true()
	assert_int(rc.contract_of(fid)["t"]["w"]).is_equal(before + 2)
	var fol: RefCounted = hub.mod("followers")
	fol.get_follower(fid)["owed"] = 20
	var d: Dictionary = rc.dismiss(fid, 12)
	assert_bool(d["ok"]).is_true()
	assert_int(d["paid"]).is_equal(12)
	assert_bool(rc._active(fid)).is_false()
	assert_str(fol.get_follower(fid)["status"]).is_equal("left")
	assert_bool(rc.dismiss(fid, 0)["ok"]).is_false()


# --- pruning ------------------------------------------------------------------------------------------
func test_old_left_records_are_pruned_to_a_summary() -> void:
	var hub := _hub()
	var fol: RefCounted = hub.mod("followers")
	var rc: RefCounted = hub.mod("recruitment")
	var ids: Array = []
	for i in 14:
		var fid: String = fol.hire("mercenary", "s0", true, "p%d" % i)
		fol.get_follower(fid)["joined_day"] = i
		ids.append(fid)
	var contract_fid := _hire(hub, 0, "guard")
	for fid in ids:
		fol.get_follower(fid)["status"] = "left"
	rc.dismiss(contract_fid, 0)
	var gone: Array = fol.prune_left()
	assert_int(gone.size()).is_equal(15 - Fol.LEFT_KEEP)
	assert_int(fol.list("left").size()).is_equal(Fol.LEFT_KEEP)
	assert_int(fol.left_pruned()).is_equal(gone.size())
	var lines: Array = fol.left_summary()
	assert_int(lines.size()).is_equal(gone.size())
	assert_str(lines[0]).contains("served from day")
	assert_array(gone).contains(["f1"])                                    # the oldest went first
	assert_bool(fol.get_follower(contract_fid).is_empty()).is_false()     # the newest stayed
	# the log is bounded
	for i in 40:
		var f2: String = fol.hire("scout", "s0", true, "q%d" % i)
		fol.get_follower(f2)["status"] = "left"
		fol.prune_left()
	assert_int(fol.left_summary().size()).is_equal(Fol.LOG_MAX)
	assert_int(fol.left_pruned()).is_greater(Fol.LOG_MAX)
	# the summary survives a save and the save does not grow with pruned people
	var d: Dictionary = JSON.parse_string(JSON.stringify(fol.serialize()))
	var fol2: RefCounted = Fol.new()
	fol2.deserialize(d)
	assert_int(fol2.left_pruned()).is_equal(fol.left_pruned())
	assert_array(fol2.left_summary()).is_equal(fol.left_summary())
	assert_int(fol2.list("left").size()).is_equal(Fol.LEFT_KEEP)


func test_recruitment_forgets_pruned_people() -> void:
	var hub := _hub()
	var fol: RefCounted = hub.mod("followers")
	var rc: RefCounted = hub.mod("recruitment")
	var first := _hire(hub, 0, "labor")
	rc.dismiss(first, 0)
	for i in 10:
		fol.get_follower(fol.hire("scout", "s0", true, "z%d" % i))["status"] = "left"
	assert_bool(rc.get_entry(first).is_empty()).is_false()
	hub.mod("followers").tick_day(1, {})
	hub.mod("recruitment").tick_day(1, {"gold": 100, "season": "summer", "at_war": false, "abs_hours": 0, "player_pos": Vector3.ZERO, "life": null})
	assert_bool(fol.get_follower(first).is_empty()).is_true()
	assert_bool(rc.get_entry(first).is_empty()).is_true()
	assert_bool(rc.contract_of(first).is_empty()).is_true()
	# a fresh hire of the same person still works
	assert_bool(rc.engage(_row(0), Rec.make_terms(60, "guard", 0, true), "personal", "", {"trust": 40.0, "reputation": 80.0})["ok"]).is_true()


# --- the manager (a body smoke test) ---------------------------------------------------------------------
func test_manager_embodies_within_the_cap() -> void:
	var hub := _hub()
	var rc: RefCounted = hub.mod("recruitment")
	var fids: Array = []
	for i in 8:
		fids.append(_hire(hub, i, "guard"))
	var player := Node3D.new()
	player.add_to_group("player")
	add_child(player)
	var pos := WorldSim.pos[_row(0)]
	player.global_position = Vector3(pos.x, WorldGen.height(pos.x, pos.y), pos.y)
	var holder := Node3D.new()
	add_child(holder)
	var m: Node3D = Manager.new()
	m.hub = hub
	holder.add_child(m)
	m.ctx["player"] = player
	m.ctx["pos"] = Vector2(player.global_position.x, player.global_position.z)
	m.refresh()
	for i in 12:
		m._process(0.0)
	var cap := Brain.budget(int(Quality.npc_full))
	assert_int(m.body_count()).is_between(1, cap)
	assert_int(m.body_count()).is_less_equal(Brain.MAX_EMBODIED)
	# every embodied row is owned by the manager (PopulationLOD will not draw it), and so are the data-only ones
	for fid in fids:
		assert_bool(Manager.owns(int(hub.mod("followers").get_follower(fid)["person"]))).is_true()
	# orders: wait keeps the body where it is, home sends it away and (arrived) frees the row
	var first: String = fids[0]
	var b: Node3D = m.body_of(first)
	assert_object(b).is_not_null()
	rc.set_order(first, "wait")
	m.refresh()
	assert_str(String(b.get("order"))).is_equal("wait")
	# an interior opens: followers wait outside
	m.ctx["inside"] = true
	b.call("_decide", b.call("sim_position"), 3.0)
	assert_int(int(b.get("mode"))).is_equal(M.WAIT) # still a wait order
	rc.set_order(first, "follow")
	m.refresh()
	b.call("_decide", b.call("sim_position"), 3.0)
	assert_int(int(b.get("mode"))).is_equal(M.WAIT_OUTSIDE)
	m.ctx["inside"] = false
	# leaving the service frees the row
	var row := int(hub.mod("followers").get_follower(first)["person"])
	rc.dismiss(first, 0)
	m.refresh()
	assert_bool(Manager.owns(row)).is_false()
	assert_object(m.body_of(first)).is_null()
	m.free()
	assert_int(Manager.owned_rows.size()).is_equal(0)
	player.queue_free()


# --- the menus -----------------------------------------------------------------------------------------
func test_order_choices_list_groups() -> void:
	var hub := _hub()
	var rc: RefCounted = hub.mod("recruitment")
	rc.create_group("property", "mill", "Mill")
	rc.create_group("property", "farm", "Farm")
	assert_array(rc.groups().map(func(g: Dictionary) -> String: return g["name"])).contains_exactly(["Mill", "Farm"])
