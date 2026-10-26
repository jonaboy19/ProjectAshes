extends Node
## Headless door check (READY_V1 C16): walks to the Ashford door of every service lot (inn, smith, trader, guild, healer,
## manor), asserts the door is what E would do, presses E through Interaction.activate (the interact controller's route),
## asserts the interior loaded, then leaves.
##   godot --headless --path kingdom scenes/main.tscn -- --quality=low --adult --qa=res://tools_qa/v1/door_check.gd
## Exits 0 when every door enters, 1 otherwise. Teleports are [HOOK]s (no walking).

const ASSETS := ["inn", "blacksmith", "mhouse_trader", "adventurer_guild", "healer_house", "mhouse_manor"]

var main: Node
var fails := 0


func run(m: Node) -> void:
	main = m
	await get_tree().create_timer(1.0).timeout
	var ac: Vector2 = WorldGen.settlements[0]["pos"]
	var doors: Array = []
	for n in main.find_children("*", "Area3D", true, false):
		if n is InteriorDoor and not (n as InteriorDoor).is_exit:
			doors.append(n)
	print("[door_check] %d entrance doors loaded" % doors.size())
	for asset: String in ASSETS:
		var door: InteriorDoor = null
		var bd := 1e9
		for d: InteriorDoor in doors:
			if String(d.get_meta("asset", "")) != asset:
				continue
			var dist := Vector2(d.global_position.x, d.global_position.z).distance_to(ac)
			if dist < bd and dist < 160.0:
				bd = dist
				door = d
		if not _check("%s: a door stands in Ashford" % asset, door != null):
			continue
		var dp := Vector2(door.global_position.x, door.global_position.z)
		var stand := dp + Vector2(sin(door.rotation.y), cos(door.rotation.y)) * 1.2
		main.call("_teleport", stand, door.rotation.y + PI)
		for i in 4:
			main.settlements.update_now()
		await get_tree().create_timer(0.8).timeout
		await get_tree().physics_frame
		var pl: Node3D = main.player
		var near: Node3D = Interaction.best_node(pl)
		_check("%s: E would use the door (nearest %s)" % [asset, near.name if near != null else "-"], near == door)
		_check("%s: E enters" % asset, Interaction.activate(pl))
		var t := 0.0
		while InteriorDoor.active == null and t < 30.0:
			await get_tree().create_timer(0.25).timeout
			t += 0.25
		_check("%s: interior loaded" % asset, InteriorDoor.active != null and InteriorDoor.active.interior != null)
		if InteriorDoor.active != null:
			InteriorDoor.active.call("leave")
			await get_tree().create_timer(0.8).timeout
		_check("%s: back outside" % asset, InteriorDoor.active == null)
	print("[door_check] %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _check(what: String, ok: bool) -> bool:
	print("[door_check] CHECK %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1
	return ok
