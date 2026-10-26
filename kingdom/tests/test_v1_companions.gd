extends GdUnitTestSuite
## Ready v1 C6: companions in combat. The Down timer, hold-E revive, death or 3-day injury by difficulty, the Call
## (summon delay), the player's target becoming everyone's target, and a headless fight (follower + player vs 3 wolves).

const Hub := preload("res://scripts/realm/realm_hub.gd")
const Rec := preload("res://scripts/realm/recruitment.gd")
const Fol := preload("res://scripts/realm/followers.gd")
const Brain := preload("res://scripts/actors/follower_brain.gd")
const Body := preload("res://scripts/actors/follower_body.gd")
const Manager := preload("res://scripts/actors/follower_manager.gd")

const PLAYER_STUB := """
extends CharacterBody3D
var dead := false
var health := 100
var target: Node3D = null
var hits_taken := 0
func take_damage(amount: int, _from: Node = null, _kb := Vector3.ZERO) -> void:
	health -= amount
	hits_taken += 1
func locked_target() -> Node3D:
	return target if is_instance_valid(target) else null
"""


func after_test() -> void:
	Manager.difficulty_override = null


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


func _hire(hub: RefCounted, skip: int, duty := "guard") -> String:
	var rc: RefCounted = hub.mod("recruitment")
	var res: Dictionary = rc.engage(_row(skip), Rec.make_terms(60, duty, 0, true), "personal", "", {"trust": 40.0, "reputation": 80.0})
	assert_bool(res["ok"]).is_true()
	return res["fid"]


func _player(at: Vector2) -> CharacterBody3D:
	var scr := GDScript.new()
	scr.source_code = PLAYER_STUB
	scr.reload()
	var p := CharacterBody3D.new()
	p.set_script(scr)
	p.add_to_group("player")
	add_child(p)
	p.global_position = Vector3(at.x, WorldGen.height(at.x, at.y), at.y)
	return p


func _body(fid: String, row: int, ctx: Dictionary, f: Dictionary) -> Node3D:
	var b: Node3D = Body.new()
	b.call("setup", fid, row, ctx, f, "guard")
	add_child(b)
	b.call("place_at", ctx["pos"] + Vector2(2, 2))
	return b


# --- pure rules --------------------------------------------------------------------------------------------
func test_difficulty_decides_death_or_injury() -> void:
	assert_str(Brain.down_outcome(0)).is_equal("injured")          # SettingsStore index 0 = Story
	assert_str(Brain.down_outcome("story")).is_equal("injured")
	assert_str(Brain.down_outcome("Story")).is_equal("injured")
	for d in [1, 2, 3, "normal", "hard", "brutal"]:
		assert_str(Brain.down_outcome(d)).is_equal("dead")
	assert_float(Brain.DOWN_SECONDS).is_equal(30.0)
	assert_int(Brain.INJURY_DAYS).is_equal(3)
	assert_int(Brain.revive_hp(50)).is_equal(20)
	assert_int(Brain.revive_hp(1)).is_equal(1)


func test_the_players_target_is_everyones_target() -> void:
	var foes := [{"id": 1, "d": 3.0}, {"id": 2, "d": 9.0}, {"id": 3, "d": 40.0}]
	assert_int(Brain.pick_foe(foes, -1)).is_equal(1)           # nobody locked: the nearest
	assert_int(Brain.pick_foe(foes, 2)).is_equal(2)            # the player's lock wins over a nearer foe
	assert_int(Brain.pick_foe(foes, 3)).is_equal(1)            # ...unless it is far out of range
	assert_int(Brain.pick_foe([], 7)).is_equal(-1)


# --- followers.gd: Down, revive, death, injury -----------------------------------------------------------------
func test_revive_clears_down() -> void:
	var hub := _hub()
	var fol: RefCounted = hub.mod("followers")
	var fid := _hire(hub, 0)
	assert_bool(fol.mark_down(fid, Brain.DOWN_SECONDS)).is_true()
	assert_bool(fol.is_down(fid)).is_true()
	assert_float(fol.down_left(fid)).is_equal(30.0)
	assert_bool(fol.revive(fid)).is_true()
	assert_bool(fol.is_down(fid)).is_false()
	assert_bool(fol.revive(fid)).is_false()
	assert_str(fol.get_follower(fid)["status"]).is_equal("present")


func test_unrevived_follower_dies_on_normal_and_hard() -> void:
	for diff in ["normal", "hard", 1]:
		var hub := _hub()
		var fol: RefCounted = hub.mod("followers")
		var rc: RefCounted = hub.mod("recruitment")
		var fid := _hire(hub, 0)
		fol.mark_down(fid, 30.0)
		var res: Dictionary = fol.resolve_down(fid, diff)
		assert_str(res["outcome"]).is_equal("dead")
		assert_str(fol.get_follower(fid)["status"]).is_equal("dead")
		assert_array(fol.party()).is_empty()
		assert_int(fol.fallen().size()).is_equal(1)
		assert_int(fol.list().size()).is_equal(0)                 # not on any roster
		rc.report_death(fid)
		assert_bool(rc.active_ids().has(fid)).is_false()
		assert_bool(rc.is_recruited(_row(0))).is_false()           # the row is free (the sim kills the person)
		# the daily agency pass keeps a dead follower dead (it is not turned into "left")
		rc.tick_day(1, {"gold": 100, "season": "summer", "at_war": false, "abs_hours": 0, "player_pos": Vector3.ZERO, "life": null})
		assert_str(fol.get_follower(fid)["status"]).is_equal("dead")


func test_story_difficulty_means_a_three_day_injury() -> void:
	var hub := _hub()
	var fol: RefCounted = hub.mod("followers")
	var fid := _hire(hub, 0)
	fol.tick_day(10, {})
	fol.mark_down(fid, 30.0)
	var res: Dictionary = fol.resolve_down(fid, "story")
	assert_str(res["outcome"]).is_equal("injured")
	assert_int(int(res["until"])).is_equal(13)
	assert_str(fol.get_follower(fid)["status"]).is_equal("present")
	assert_bool(fol.is_injured(fid)).is_true()
	assert_int(fol.injury_days_left(fid)).is_equal(3)
	assert_bool(fol.is_down(fid)).is_false()
	fol.tick_day(12, {})
	assert_bool(fol.is_injured(fid)).is_true()
	fol.tick_day(13, {})
	assert_bool(fol.is_injured(fid)).is_false()
	assert_int(fol.fallen().size()).is_equal(0)


func test_down_and_injury_survive_a_save() -> void:
	var hub := _hub()
	var fol: RefCounted = hub.mod("followers")
	var a := _hire(hub, 0)
	var b := _hire(hub, 1)
	fol.mark_down(a, 12.5)
	fol.resolve_down(b, "story")
	var d: Dictionary = JSON.parse_string(JSON.stringify(fol.serialize()))
	var fol2: RefCounted = Fol.new()
	fol2.deserialize(d)
	assert_bool(fol2.is_down(a)).is_true()
	assert_float(fol2.down_left(a)).is_equal(12.5)
	assert_bool(fol2.is_injured(b)).is_true()
	# a dead follower comes back dead
	var c := _hire(hub, 2)
	fol.resolve_down(c, "hard")
	var fol3: RefCounted = Fol.new()
	fol3.deserialize(JSON.parse_string(JSON.stringify(fol.serialize())))
	assert_str(fol3.get_follower(c)["status"]).is_equal("dead")
	assert_int(fol3.fallen().size()).is_equal(1)


func test_the_call_uses_the_summon_delay() -> void:
	var hub := _hub()
	var fol: RefCounted = hub.mod("followers")
	var near := _hire(hub, 0)
	var far := _hire(hub, 1)
	var down := _hire(hub, 2)
	var hurt := _hire(hub, 3)
	for fid in [near, far, down, hurt]:
		fol.get_follower(fid)["loyalty"] = 90.0
	fol.get_follower(near)["loc"] = "s0"
	fol.get_follower(far)["loc"] = "s3"
	fol.mark_down(down, 30.0)
	fol.resolve_down(hurt, "story")
	var res: Dictionary = fol.call_party("s0")
	assert_array(res["called"]).contains([far])
	assert_bool((res["called"] as Array).has(near)).is_false()    # already there
	assert_bool((res["called"] as Array).has(down)).is_false()
	assert_bool((res["called"] as Array).has(hurt)).is_false()
	assert_float(float(res["eta"])).is_greater(0.0)
	assert_str(fol.get_follower(far)["status"]).is_equal("traveling")
	# the road takes its hours
	for h in int(ceil(float(res["eta"]))) + 1:
		fol.tick_hour(h, {})
	assert_str(fol.get_follower(far)["status"]).is_equal("present")
	assert_str(fol.get_follower(far)["loc"]).is_equal("s0")


# --- the body --------------------------------------------------------------------------------------------------
func _setup_body(hub: RefCounted, skip := 0) -> Array:
	var fid := _hire(hub, skip)
	var f: Dictionary = hub.mod("followers").get_follower(fid)
	var p := _player(WorldSim.pos[int(f["person"])])
	var ctx := {"player": p, "pos": Vector2(p.global_position.x, p.global_position.z), "yaw": 0.0, "speed": 0.0,
		"inside": false, "jump": 0.0, "owner": 1}
	var b := _body(fid, int(f["person"]), ctx, f)
	return [fid, p, b]


func test_down_timer_and_revive_by_hand() -> void:
	var hub := _hub()
	var s := _setup_body(hub)
	var b: Node3D = s[2]
	assert_bool(b.is_in_group("combatant")).is_true()
	b.call("take_damage", 9999)
	assert_bool(b.call("is_down")).is_true()
	assert_float(b.call("down_left")).is_equal(Brain.DOWN_SECONDS)
	assert_bool(b.is_in_group("combatant")).is_false()          # foes stop seeing a Down body
	b.call("take_damage", 5)                                    # no more blows land
	for i in 29 * 60:
		b._physics_process(1.0 / 60.0)
	assert_bool(b.call("is_down")).is_true()
	assert_float(b.call("down_left")).is_between(0.5, 1.5)
	# hold-E: an Interactable with the revive hold time and range
	var c := Interactable.component_of(b)
	assert_object(c).is_not_null()
	assert_float(c.hold_time).is_equal(Brain.REVIVE_HOLD)
	assert_bool(c.can_interact(s[1])).is_true()
	assert_str(c.verb).is_equal("Revive")
	c.interact(s[1])
	assert_bool(b.call("is_down")).is_false()
	assert_int(int(b.get("hp"))).is_equal(Brain.revive_hp(int(b.get("max_hp"))))
	assert_bool(b.is_in_group("combatant")).is_true()
	assert_bool(c.can_interact(s[1])).is_false()


func test_down_timer_expiry_emits_for_the_manager() -> void:
	var hub := _hub()
	var s := _setup_body(hub)
	var b: Node3D = s[2]
	var fired: Array = []
	b.connect("down_expired", func(fid: String) -> void: fired.append(fid))
	b.call("take_damage", 9999)
	for i in 31 * 60:
		b._physics_process(1.0 / 60.0)
	assert_array(fired).contains_exactly([s[0]])
	assert_bool(bool(b.get("fallen"))).is_true()
	# a body with no manager listening just gets up again
	var s2 := _setup_body(hub, 1)
	var loose: Node3D = s2[2]
	loose.call("take_damage", 9999)
	for i in 31 * 60:
		loose._physics_process(1.0 / 60.0)
	assert_bool(loose.call("is_down")).is_false()


# --- the manager: death, injury, the Call ---------------------------------------------------------------------------
func _manager(hub: RefCounted, player: Node3D) -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	var m: Node3D = Manager.new()
	m.hub = hub
	holder.add_child(m)
	m.ctx["player"] = player
	m.ctx["pos"] = Vector2(player.global_position.x, player.global_position.z)
	return m


func _embody(m: Node3D) -> void:
	m.refresh()
	for i in 12:
		m._process(0.0)


func test_manager_kills_or_injures_by_difficulty() -> void:
	for diff in ["normal", "story"]:
		var hub := _hub()
		var fol: RefCounted = hub.mod("followers")
		var rc: RefCounted = hub.mod("recruitment")
		var fid := _hire(hub, 0)
		var row := int(fol.get_follower(fid)["person"])
		var p := _player(WorldSim.pos[row])
		var m := _manager(hub, p)
		Manager.difficulty_override = diff
		_embody(m)
		var b: Node3D = m.body_of(fid)
		assert_object(b).is_not_null()
		b.call("take_damage", 9999)
		assert_bool(fol.is_down(fid)).is_true()                  # the sim knows (and a save would keep it)
		for i in 31 * 60:
			b._physics_process(1.0 / 60.0)
		if diff == "normal":
			assert_str(fol.get_follower(fid)["status"]).is_equal("dead")
			assert_bool(WorldSim.health[row] == 0).is_true()     # the person is dead in the sim too
			assert_bool(rc.is_recruited(row)).is_false()
			assert_bool(Manager.owns(row)).is_false()
		else:
			assert_str(fol.get_follower(fid)["status"]).is_equal("present")
			assert_bool(fol.is_injured(fid)).is_true()
			assert_bool(WorldSim.health[row] != 0).is_true()
			m.refresh()
			assert_object(m.body_of(fid)).is_null()              # recovering: no body for three days
		m.get_parent().queue_free()
		p.queue_free()


func test_manager_revive_updates_the_sim() -> void:
	var hub := _hub()
	var fol: RefCounted = hub.mod("followers")
	var fid := _hire(hub, 0)
	var p := _player(WorldSim.pos[int(fol.get_follower(fid)["person"])])
	var m := _manager(hub, p)
	_embody(m)
	var b: Node3D = m.body_of(fid)
	b.call("take_damage", 9999)
	for i in 10 * 60:
		b._physics_process(1.0 / 60.0)
	m.refresh()
	assert_float(fol.down_left(fid)).is_between(18.0, 21.0)    # the sim keeps counting down
	b.call("revive")
	assert_bool(fol.is_down(fid)).is_false()
	m.get_parent().queue_free()
	p.queue_free()


func test_the_call_sends_for_everyone_and_resets_orders() -> void:
	var hub := _hub()
	var fol: RefCounted = hub.mod("followers")
	var rc: RefCounted = hub.mod("recruitment")
	var a := _hire(hub, 0)
	var b := _hire(hub, 1)
	var p := _player(WorldSim.pos[int(fol.get_follower(a)["person"])])
	var m := _manager(hub, p)
	rc.set_order(b, "wait")
	_embody(m)
	var res: Dictionary = m.call_followers()
	assert_array(res["called_orders"]).contains([b])
	assert_str(rc.effective_order(b)["order"]).is_equal("follow")
	# a second Call right away is ignored (cooldown), then works again
	assert_array(m.call_followers()["called_orders"]).is_empty()
	m._call_cd = 0.0
	rc.set_order(a, "wait")
	assert_array(m.call_followers()["called_orders"]).contains([a])
	m.get_parent().queue_free()
	p.queue_free()


# --- headless fight: follower + player vs three wolves ------------------------------------------------------------
func test_fight_sim_follower_hurts_three_wolves() -> void:
	var hub := _hub()
	var fol: RefCounted = hub.mod("followers")
	var rc: RefCounted = hub.mod("recruitment")
	var fid := _hire(hub, 0, "guard")
	fol.get_follower(fid)["skills"]["combat"] = 0.8
	var p := _player(WorldSim.pos[int(fol.get_follower(fid)["person"])])
	var m := _manager(hub, p)
	_embody(m)
	var b: Node3D = m.body_of(fid)
	assert_object(b).is_not_null()
	var wolves: Array = []
	for i in 3:
		var w := Wolf.new()
		w.species = "wolf"
		w.home = Vector2(p.global_position.x + 8.0 + i, p.global_position.z + i * 2.0)
		w.territory = 200.0
		add_child(w)
		w.global_position = Vector3(w.home.x, WorldGen.height(w.home.x, w.home.y) + 0.3, w.home.y)
		w._provoked = 8.0
		wolves.append(w)
	p.target = wolves[0]
	var hp0 := 0
	for w: Node in wolves:
		hp0 += int(w.health)
	var steps := 60 * 40
	for i in steps:
		m.ctx["pos"] = Vector2(p.global_position.x, p.global_position.z)
		for w: Node in wolves:
			if is_instance_valid(w) and not bool(w.dead):
				w._physics_process(1.0 / 60.0)
		b._physics_process(1.0 / 60.0)
		if i % 30 == 0:
			p.target = null
			for w: Node in wolves:
				if is_instance_valid(w) and not bool(w.dead):
					p.target = w
					break
	var hp1 := 0
	for w: Node in wolves:
		hp1 += maxi(int(w.health), 0)
	assert_int(hp1).is_less(hp0)                                   # the follower did damage
	for w: Node in wolves:
		if is_instance_valid(w):
			w.queue_free()
	m.get_parent().queue_free()
	p.queue_free()
	rc.dismiss(fid, 0)
