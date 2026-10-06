extends Node
## The live end of package F5: one small node that turns the pure rules into play.
##   - pickpocket: a "Pickpocket" hold interaction (scripts/sim/pickpocket.gd) offered through an Interaction provider
##     when the player is crouched right behind a villager who has not noticed anything. A proxy Interactable follows
##     that villager, so the player's InteractionController runs the hold like any other.
##   - trespass: inside a home that is not yours at night or when locked, or a shop out of hours, the occupant
##     notices you, warns you once, and files a crime if you linger (scripts/population/trespass.gd).
##   - arrest: a guard within reach of a player with a bounty offers pay / jail / resist (scripts/sim/arrest.gd).
## Installed once by VillageServices (`CrimeWatch.install(host)`); ticks at 4 Hz, does nothing in a bare scene.

const Locks := preload("res://scripts/world/locks.gd")
const Ownership := preload("res://scripts/sim/ownership.gd")
const Theft := preload("res://scripts/sim/theft.gd")
const Pickpocket := preload("res://scripts/sim/pickpocket.gd")
const Arrest := preload("res://scripts/sim/arrest.gd")
const Trespass := preload("res://scripts/population/trespass.gd")
const Takedown := preload("res://scripts/combat/takedown.gd")
const Perception := preload("res://scripts/population/perception.gd")
const AlertNet := preload("res://scripts/population/alert_net.gd")
const Search := preload("res://scripts/population/search.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const NODE_NAME := "CrimeWatch"
const TICK := 0.25

var _acc := 0.0
var _proxy: Node3D
var _comp: Interactable
var _target: Node3D = null
var _tres := Trespass.new_state()


static func install(host: Node) -> Node:
	var ex := host.get_node_or_null(NODE_NAME)
	if ex != null:
		return ex
	var n := (load("res://scripts/population/crime_watch.gd") as GDScript).new() as Node
	n.name = NODE_NAME
	host.add_child(n)
	return n


func _ready() -> void:
	_proxy = Node3D.new()
	_proxy.name = "PickpocketProxy"
	add_child(_proxy)
	_comp = Interactable.attach(_proxy, {"id": "pickpocket/target", "verb": "Pickpocket", "priority": 2, "range": Pickpocket.REACH + 0.6,
		"hold_time": Pickpocket.HOLD_TIME, "enabled": false,
		"can": func(_p: Node) -> bool: return _target != null and is_instance_valid(_target),
		"do": func(p: Node) -> void: _pickpocket(p),
		"label": func() -> Dictionary: return {"verb": "Pickpocket", "target": _target_name()}})
	Interaction.add_provider(_provide)


func _exit_tree() -> void:
	Interaction.remove_provider(_provide)


func _process(delta: float) -> void:
	_acc += delta
	if _acc < TICK:
		return
	var dt := _acc
	_acc = 0.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or bool(player.get("dead")):
		return
	_tick_trespass(player, dt)
	_tick_arrest(player)


# ================================================================ pickpocket
func _target_name() -> String:
	if _target != null and is_instance_valid(_target):
		var n: Variant = _target.get("npc_name")
		if n is String and n != "":
			return n
	return "Villager"


## Interaction provider: the pickpocket candidate while crouched behind someone, else nothing.
func _provide(player_pos: Vector3, _facing: Vector3) -> Array:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	_target = _victim_for(player, Vector2(player_pos.x, player_pos.z))
	if _target == null:
		_comp.enabled = false
		return []
	_proxy.global_position = _target.global_position + Vector3(0, 1.0, 0)
	_comp.enabled = true
	return [_comp.candidate()]


func _victim_for(player: Node3D, here: Vector2) -> Node3D:
	if player == null or not bool(player.get("crouching")):
		return null
	var day := int(WorldSim.day)
	for n in get_tree().get_nodes_in_group("villager"):
		var v := n as Node3D
		if v == null or not v.has_method("perception_facing"):
			continue
		var vp := Vector2(v.global_position.x, v.global_position.z)
		if vp.distance_to(here) > Pickpocket.REACH:
			continue
		var person := int(v.get("person"))
		if person < 0 or Takedown.is_down(person) or Pickpocket.already_robbed(person, day):
			continue
		var guard := person < WorldSim.job.size() and WorldSim.job[person] == 3
		if guard:
			continue
		if Takedown.can_takedown(here, vp, v.call("perception_facing"), int(v.call("alert_class")), false):
			return v
	return null


func _pickpocket(_p: Node) -> void:
	var v := _target
	if v == null or not is_instance_valid(v):
		return
	var here := Vector2(v.global_position.x, v.global_position.z)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var pp := Vector2(player.global_position.x, player.global_position.z)
	var person := int(v.get("person"))
	var behind := Takedown.can_takedown(pp, here, v.call("perception_facing"), 0, false)
	var skill := float(Locks.player_holder().get("skill", 0.0))     # nimble fingers: the same 0..10 skill as lockpicking
	var p := Pickpocket.chance(skill, float(v.call("perception_acuity")), Perception.light_at(pp), behind, int(v.call("alert_class")), true, Pickpocket.heat_today(int(WorldSim.day)))
	var res := Pickpocket.resolve(Pickpocket.attempt(p, randf())["ok"], person, int(WorldSim.day),
		func(g: int) -> void: Game.add_gold(g))
	Game.say(String(res["text"]))
	var sid := _sid_at(here)
	match String(res["crime"]):
		"pickpocket":
			Theft.report(get_tree(), "pickpocket", here, sid)
		"robbery":
			if v.has_method("witness"):
				v.call("witness", here, "robbery", true, true)      # the victim certainly saw
			Theft.report(get_tree(), "robbery", here, sid)


# ================================================================ trespass
func _tick_trespass(player: Node3D, dt: float) -> void:
	var door: InteriorDoor = InteriorDoor.active
	if door == null or not is_instance_valid(door) or door.interior == null or not is_instance_valid(door.interior):
		Trespass.step(_tres, dt, false, 0.0)
		return
	var owner := Ownership.owner_of(door.interior)
	var locked := false
	if door.model != null:
		var lid := String(door.model.get("lock_id"))
		locked = lid != "" and Locks.is_locked(lid)
	var back := bool(door.interior.get_meta("back_room", false))
	var trespassing := Trespass.evaluate(owner, locked, float(WorldSim.time_of_day), null, back)
	var stance := NpcWorld.player_stance()
	var ev := Trespass.step(_tres, dt, trespassing, Trespass.rate_for(stance <= 0.55, stance >= 1.2), true)
	match ev:
		"warn":
			Game.say(Trespass.WARNING)
		"crime":
			var sid := Ownership.sid_of(owner)
			if sid < 0:
				sid = _sid_at(Vector2(door.global_position.x, door.global_position.z))
			Trespass.commit(_society(), sid)
			AlertNet.raise(sid, Time.get_ticks_msec(), 1)
			Game.say("\"Thief! Get out of my house!\"")


# ================================================================ arrest
func _tick_arrest(player: Node3D) -> void:
	var soc := _society()
	if soc == null or InteriorDoor.active != null:
		return
	var here := Vector2(player.global_position.x, player.global_position.z)
	var sid := _sid_at(here)
	if sid < 0:
		return
	var bounty := int(soc.call("bounty", sid))
	var now := Time.get_ticks_msec()
	if not Arrest.can_offer(bounty, now):
		return
	var hud := Interaction.hud(player)
	if hud == null or hud.call("is_menu_open"):
		return
	if not _guard_in_reach(here):
		return
	Arrest.note_offer(now)
	var ctx := {"soc": soc, "sid": sid, "gold": Game.gold,
		"advance": func(h: float) -> void: WorldSim.advance_hours(h),
		"take_gold": func(n: int) -> void: Game.add_gold(-n),
		"alarm": func(levels: int) -> void: _raise_alarm(sid, here, levels),
		"on_done": func(choice: String) -> void: _after_choice(choice, sid, player)}
	hud.call("show_menu", func() -> Dictionary:
		ctx["gold"] = Game.gold
		return Arrest.menu(ctx))


func _guard_in_reach(here: Vector2) -> bool:
	for n in get_tree().get_nodes_in_group("villager"):
		var v := n as Node3D
		if v == null or not v.has_method("alert_class"):
			continue
		var person := int(v.get("person"))
		if person < 0 or person >= WorldSim.job.size() or WorldSim.job[person] != 3 or Takedown.is_down(person):
			continue
		if Vector2(v.global_position.x, v.global_position.z).distance_to(here) <= Arrest.CATCH_RADIUS \
				and int(v.call("alert_class")) >= Perception.Cls.NOTICE:
			return true
	return false


func _raise_alarm(sid: int, at: Vector2, levels: int) -> void:
	var now := Time.get_ticks_msec()
	AlertNet.raise(sid, now, levels)
	Search.begin(at, sid, now)


## After jail the player is let out at the plaza; after resisting the arrest offer comes again soon.
func _after_choice(choice: String, sid: int, player: Node3D) -> void:
	if choice == "jail" and sid >= 0 and sid < WorldGen.settlements.size():
		var c: Vector2 = WorldGen.settlements[sid]["pos"]
		player.global_position = Vector3(c.x, WorldGen.height(c.x, c.y) + 1.0, c.y)
	if choice == "resist":
		Arrest.reset()


# ================================================================ helpers
func _society() -> Object:
	return Life.realm.call("mod", "society") if Life.realm != null else null


func _sid_at(p: Vector2) -> int:
	return int(NpcWorld._sid_at(p))
