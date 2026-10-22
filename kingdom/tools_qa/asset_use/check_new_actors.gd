extends SceneTree
## Headless smoke check for the actors and rooms added by docs/qa/ASSET_AUDIT.md work: new Critter kinds (clip aliases), dungeon creature
## kinds (KayKit skeletons with gear, Ultimate Monsters), and the two lord's halls. Prints one line each; exit 1 on a missing model.
##   Godot --headless --path kingdom -s res://tools_qa/asset_use/check_new_actors.gd


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	await process_frame
	var bad := 0
	var host := Node3D.new()
	root.add_child(host)
	var critter: GDScript = load("res://scripts/actors/critter.gd")
	for k in ["cow_brown_a", "cow_brown_b", "cow_spotted", "hen_meshy", "rooster_meshy", "horse_white", "husky"]:
		var c: Node3D = critter.new()
		c.set("kind", k)
		host.add_child(c)
		await process_frame
		var ap: AnimationPlayer = Assets.animation_player(c)
		var ok := ap != null and ap.has_animation("Idle") and ap.has_animation("Walk") and ap.has_animation("Eat")
		print("critter %-14s anim %s Idle %s Walk %s Run %s Eat %s" % [k, ap != null, ap != null and ap.has_animation("Idle"), ap != null and ap.has_animation("Walk"), ap != null and ap.has_animation("Run"), ap != null and ap.has_animation("Eat")])
		if not ok:
			bad += 1
	var dc: GDScript = load("res://scripts/interiors/dungeon_creature.gd")
	for k in ["skeleton_minion", "skeleton_warrior", "skeleton_rogue", "skeleton_mage", "mushroom_king", "ghost_skull"]:
		var d: Node3D = dc.new()
		d.set("kind", k)
		host.add_child(d)
		await process_frame
		var m: Node3D = d.get("_model")
		var ap2: AnimationPlayer = Assets.animation_player(m) if m != null else null
		var clips: Dictionary = d.get("_clips")
		var missing: Array = []
		if ap2 != null:
			for key in clips:
				if not ap2.has_animation(String(clips[key])):
					missing.append("%s=%s" % [key, clips[key]])
		var gear := 0
		if m != null:
			gear = m.find_children("*", "BoneAttachment3D", true, false).size()
		print("dungeon %-16s model %s anim %s gear %d missing clips %s" % [k, m != null, ap2 != null, gear, missing])
		if m == null or ap2 == null or not missing.is_empty():
			bad += 1
	for sc in ["steward_hall", "keep_hall"]:
		var ps := load("res://scenes/interiors/%s_interior.tscn" % sc) as PackedScene
		var room := ps.instantiate() as Node3D
		host.add_child(room)
		await process_frame
		var items := room.get_node("Furniture").get_child_count()
		print("hall %-12s furniture %d spawn %s exit %s npcs %d" % [sc, items, room.get_node_or_null("PlayerSpawn") != null, room.get_node_or_null("ExitDoor") != null, room.get_node("NPCs").get_child_count()])
		if items < 15:
			bad += 1
	print("check_new_actors: %d problems" % bad)
	quit(1 if bad > 0 else 0)
