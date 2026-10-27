extends RefCounted
## Acceptance scenario A (docs/plans/MASTER_BACKLOG.md §3, WP-01): one continuous movement chain in the real game, played by
## the playtest bot through the player's own entry points.
##   PLAYTEST_STAGES=scen_a  godot scenes/main.tscn -- --qa=res://tools_qa/playtest_bot/playtest_bot.gd
## Steps (each logs CHECK PASS/FAIL "scenario A <n>: ..."): 1 run 60 m along an Ashford street, 2 vault the field fence
## (traversal VAULT entered and left), 3 climb the hayloft ladder and back down, 4 enter a house through its door,
## 5 sit on a chair inside and stand up, 6 draw the sword and fight a bandit (3 exchanges: block, parry window, hit),
## 7 pick up a sack, carry it 10 m, put it down, 8 mount a horse, ride 50 m, dismount.
## Every step also checks the player is not in bind / T-pose (skeleton pose sanity) and saves a shot for the strip.
## The pieces come from data/world/slice_dressing.json (scripts/world/town_kit/slice_dressing.gd).

const Slice := preload("res://scripts/world/town_kit/slice_dressing.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const CarryK := preload("res://scripts/interaction/kinds/carryable.gd")

var b               # the playtest bot (untyped: its helpers are called dynamically)
var player: Node3D
var ok_steps := 0
var _street := Vector2.ZERO


func run(bot: Node) -> void:
	b = bot
	player = b.get("player")
	WorldSim.time_of_day = 11.0
	var town: Dictionary = Slice.settlement(String(Slice.data().get("scenario_a", {}).get("town", "Ashford")))
	if town.is_empty():
		b.check("scenario A: the scenario town exists", false)
		return
	await _step1_run(town)
	await _step2_vault(town)
	await _step3_ladder()
	await _step4_house(town)
	await _step5_sit()
	await _step6_fight()
	await _step7_carry()
	await _step8_mount()
	b.check("scenario A: all 8 steps passed", ok_steps == 8, "%d of 8" % ok_steps)


func _pass(n: int, label: String, ok: bool, detail := "") -> void:
	var sane := _pose_sane()
	if b.check("scenario A %d: %s" % [n, label], ok and sane, detail + ("" if sane else " | BIND/T-POSE frame")):
		ok_steps += 1
	await b.shot("scen_a_%d" % n)


## Pose sanity: the hands hang below the shoulders' line somewhere in a T-pose they sit level with it far out to the sides.
func _pose_sane() -> bool:
	var sk: Skeleton3D = null
	for n in player.find_children("*", "Skeleton3D", true, false):
		sk = n
		break
	if sk == null:
		return true
	var hl := sk.find_bone("hand_l")
	var hr := sk.find_bone("hand_r")
	var ul := sk.find_bone("upperarm_l")
	if hl < 0 or hr < 0 or ul < 0:
		return true
	var span := sk.get_bone_global_pose(hl).origin.distance_to(sk.get_bone_global_pose(hr).origin)
	var arm := sk.get_bone_global_pose(ul).origin.distance_to(sk.get_bone_global_pose(hl).origin)
	var level := absf(sk.get_bone_global_pose(hl).origin.y - sk.get_bone_global_pose(ul).origin.y)
	return not (span > arm * 3.4 and level < arm * 0.12)


func _trav_state() -> int:
	var t: Variant = player.get("_trav")
	return int((t as Object).get("state")) if t is Object and (t as Object).get("state") != null else -1


func _step1_run(town: Dictionary) -> void:
	var start := Vector2(town["pos"]) + Vector2(4, 4)
	_street = start
	await b.teleport(start, 0.0, 1.0)
	var t0 = b.now()
	var target := start + Vector2(0, 60)
	var ok: bool = await b.walk_to(target, 3.0, 40.0, true, 4.0)
	await _pass(1, "run 60 m along the street", ok, "%.1f s" % (b.now() - t0))


func _step2_vault(town: Dictionary) -> void:
	var fe: Dictionary = Slice.data()["scenario_a"]["fence"]
	var fp: Vector2 = Slice.to_world(town, fe["at"])
	var fence = b.get_tree().root.find_child("ScenarioFence", true, false) as Node3D
	var normal := Vector2(1, 0)
	if fence != null:
		var z: Vector3 = fence.global_basis.z
		normal = Vector2(z.x, z.z).normalized()
		fp = Vector2(fence.global_position.x, fence.global_position.z)
	var from := fp - normal * 5.0
	await b.teleport(from, b.yaw_to(from, fp), 1.0)
	b.hold("move_forward", true)
	b.hold("sprint", true)
	var entered := false
	var crossed := false
	var t0 = b.now()
	while b.now() - t0 < 6.0:
		var d := (Vector2(player.global_position.x, player.global_position.z) - fp).dot(normal)
		if d > -1.4 and not entered:
			player.call("jump")
		if _trav_state() > 0:
			entered = true
		if d > 1.0:
			crossed = true
			break
		await b.frames(1)
	b.release_all()
	await b.wait(0.8)
	await _pass(2, "vault the field fence (traversal entered and left)", entered and crossed and _trav_state() <= 0,
			"entered %s crossed %s state %d fence %s" % [str(entered), str(crossed), _trav_state(), str(fence != null)])


func _step3_ladder() -> void:
	var lad = b.get_tree().root.find_child("HayloftLadder", true, false) as Node3D
	if lad == null:
		await _pass(3, "climb the hayloft ladder and back down", false, "no HayloftLadder in the scene")
		return
	var bottom: Vector3 = (lad.get("bottom") as Node3D).global_position
	var top: Vector3 = (lad.get("top") as Node3D).global_position
	var stand := Vector2(bottom.x, bottom.z) + Vector2(0.0, 0.9)
	await b.teleport(stand, b.yaw_to(stand, Vector2(bottom.x, bottom.z)), 0.8)
	lad.call("climb", player, true)
	var up: bool = await b.wait_until(func() -> bool: return player.global_position.y > top.y - 0.4 and _trav_state() <= 0, 12.0)
	await b.shot("scen_a_3_top")
	lad.call("climb", player, false)
	var down: bool = await b.wait_until(func() -> bool: return player.global_position.y < bottom.y + 0.4 and _trav_state() <= 0, 12.0)
	await _pass(3, "climb the hayloft ladder and back down", up and down, "up %s down %s y %.2f" % [str(up), str(down), player.global_position.y])


func _step4_house(town: Dictionary) -> void:
	var tc := Vector2(town["pos"])
	var door: Node3D = null
	var bd := 1e9
	for n in b.get_tree().root.find_children("*", "Area3D", true, false):
		if n.get_class() == "Area3D" and n.get("is_exit") == false and n.get("interior_scene") != null:
			var d := Vector2(n.global_position.x, n.global_position.z).distance_to(tc)
			if d < bd and d < 160.0:
				bd = d
				door = n
	if door == null:
		await _pass(4, "enter a house through its door", false, "no door near the town")
		return
	var dp := Vector2(door.global_position.x, door.global_position.z)
	var stand := dp + (tc - dp).normalized() * 1.2
	await b.teleport(stand, b.yaw_to(stand, dp), 0.6)
	var t0 = b.now()
	await b.key(KEY_E)
	var inside: bool = await b.wait_until(func() -> bool: return InteriorDoor.active != null, 30.0)
	await b.wait(1.0)
	var fell := player.global_position.y < door.global_position.y - 20.0
	await _pass(4, "enter a house through its door", inside and not fell, "%.0f ms, inside %s" % [(b.now() - t0) * 1000.0, str(inside)])


func _step5_sit() -> void:
	var seat: Node3D = null
	var bd := 1e9
	for n in b.get_tree().root.find_children("Seat_*", "Node3D", true, false):
		var d := (n as Node3D).global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			seat = n
	if seat == null or bd > 40.0:
		# no chair in this interior: leave and sit on a bench of the living world (SmartObjects seats via PlayerSeats)
		await _leave_building()
		seat = await _smart_seat()
		if seat == null:
			await _pass(5, "sit on a chair and stand up", false, "no Seat indoors and no SmartObjects seat near the town")
			return
	var sp := Vector2(seat.global_position.x, seat.global_position.z)
	await b.walk_to(sp, 1.6, 12.0, false, 4.0)
	var sat: bool = seat.call("sit", player)
	await b.wait(2.5)
	var seated := player.has_meta("seated_on")
	await b.shot("scen_a_5_seated")
	b.hold("move_forward", true)
	await b.wait(0.4)
	b.release_all()
	await b.wait(1.5)
	await _pass(5, "sit on a chair and stand up", sat and seated and not player.has_meta("seated_on"), "sat %s seated %s" % [str(sat), str(seated)])
	await _leave_building()


func _leave_building() -> void:
	if InteriorDoor.active != null:
		for n in b.get_tree().root.find_children("*", "Area3D", true, false):
			if n.get("is_exit") == true:
				var ep := Vector2(n.global_position.x, n.global_position.z)
				await b.walk_to(ep, 0.4, 15.0, false, 4.0)
				await b.key(KEY_E)
				break
		await b.wait_until(func() -> bool: return InteriorDoor.active == null, 20.0)
		await b.wait(1.0)


func _step6_fight() -> void:
	var c = b.p2() + Vector2(0, 12)
	await b.teleport(c, 0.0, 0.8)
	player.call("set_sheathed", true, true)
	await b.wait(0.3)
	player.call("toggle_sheathe")      # draw (H)
	await b.wait(0.6)
	var drawn: bool = not bool(player.get("sheathed"))
	var fwd := Vector2(-sin(float(player.get("_yaw"))), -cos(float(player.get("_yaw"))))
	var bp = c + fwd * 4.0
	var bandit: Node3D = Soldier.create(1, "Bandit", "Bandit", ["1H_Sword", "Round_Shield"])
	b.get("main").get("world").add_child(bandit)
	bandit.global_position = Vector3(bp.x, WorldGen.height(bp.x, bp.y) + 0.3, bp.y)
	await b.wait(1.0)
	var blocked := [0]
	var on_block := func(_a: Node, _broken: bool) -> void: blocked[0] += 1
	player.connect("blocked", on_block)
	# exchange 1: hold block while the bandit swings
	Input.action_press("block")
	await b.wait(2.5)
	Input.action_release("block")
	var hp0 := int(bandit.get("health"))
	var killed: bool = await b.call("_fight", bandit, "scenario bandit", 30.0)
	player.disconnect("blocked", on_block)
	var hurt: bool = killed or not is_instance_valid(bandit) or int(bandit.get("health")) < hp0
	var survived: bool = not bool(player.get("dead"))
	await _pass(6, "draw the sword and fight a bandit (block, hit)", drawn and hurt and survived, "drawn %s blocks %d killed %s survived %s" % [str(drawn), blocked[0], str(killed), str(survived)])
	if is_instance_valid(bandit) and not bool(bandit.get("dead")):
		bandit.queue_free()
	await b.ensure_alive()
	player.set("health", player.get("max_health"))


func _step7_carry() -> void:
	# on the street of step 1 (known clear), walking the same way
	await b.teleport(_street + Vector2(0, 20), b.yaw_to(_street, _street + Vector2(0, 60)), 1.0)
	var c = b.p2()
	var f := Vector3(-sin(float(player.get("_yaw"))), 0, -cos(float(player.get("_yaw"))))
	var sack: Node3D = CarryK.spawn(b.get("main").get("world"), player.global_position + f * 0.9, "sack")
	await b.wait(0.5)
	var picked: bool = player.call("carry_pick", sack)
	await b.wait(1.6)
	var start = b.p2()
	var ok: bool = await b.walk_to(start + Vector2(f.x, f.z) * 10.0, 1.2, 20.0, false, 4.0)
	var carried = player.call("carrying") == sack
	player.call("carry_drop")
	await b.wait(1.2)
	var on_ground := absf(sack.global_position.y - WorldGen.height(sack.global_position.x, sack.global_position.z)) < 0.25
	await _pass(7, "pick up a sack, carry it 10 m, put it down", picked and ok and carried and on_ground,
			"picked %s walked %s carried %s down %s from %s" % [str(picked), str(ok), str(carried), str(on_ground), str(c)])
	sack.queue_free()


func _step8_mount() -> void:
	var c = b.p2()
	var horse := Critter.new()
	horse.kind = "horse"
	horse.home = c + Vector2(2, 0)
	b.get("main").get("world").add_child(horse)
	horse.global_position = Vector3(c.x + 2.0, WorldGen.height(c.x + 2.0, c.y), c.y)
	await b.wait(1.0)
	player.call("toggle_mount", horse)
	await b.wait(1.0)
	var mounted: bool = player.call("is_mounted")
	var start = b.p2()
	var rode: bool = await b.walk_to(start + Vector2(0, 50), 4.0, 40.0, true, 6.0)
	if bool(player.call("is_mounted")):
		player.call("toggle_mount")
	await b.wait(1.5)
	await _pass(8, "mount a horse, ride 50 m, dismount", mounted and rode and not bool(player.call("is_mounted")),
			"mounted %s rode %s" % [str(mounted), str(rode)])


## The nearest seated SmartObjects slot to the town centre: walk there and let PlayerSeats put a Seat on it.
func _smart_seat() -> Node3D:
	var so: Variant = NpcWorld.smart
	if so == null:
		return null
	var best := -1
	var bd := 1e9
	var me: Vector3 = player.global_position
	var spots: Array = so.get("spots")
	var types: Dictionary = so.get("types")
	for i in spots.size():
		var td: Dictionary = types.get(spots[i]["type"], {})
		if (load("res://scripts/interaction/player_seats.gd") as GDScript).call("seat_slots", td).is_empty():
			continue
		var d: float = (spots[i]["xform"] as Transform3D).origin.distance_to(me)
		if d < bd:
			bd = d
			best = i
	if best < 0:
		return null
	var o: Vector3 = (spots[best]["xform"] as Transform3D).origin
	await b.teleport(Vector2(o.x, o.z) + Vector2(1.5, 1.5), 0.0, 1.0)
	await b.wait(1.5)
	var seat: Node3D = null
	var sd := 1e9
	for n in b.get_tree().root.find_children("Seat_*", "Node3D", true, false):
		var d: float = (n as Node3D).global_position.distance_to(player.global_position)
		if d < sd:
			sd = d
			seat = n
	return seat