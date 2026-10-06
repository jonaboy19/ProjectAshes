extends RefCounted
## Shared glue for world nodes that run a GatherSession through the mobile panel (forage_nodes, build_resources,
## fishing_spot, ore_vein style). Static helpers only; the nodes keep their own spawn and visuals.

const GatherSession := preload("res://scripts/sim/gather_session.gd")
const GatherPanel := preload("res://scripts/ui/gather_panel.gd")
const Crafting := preload("res://scripts/sim/crafting.gd")
static var _active_panel: WeakRef


## Opens the panel under `host`. on_done(result: Dictionary) runs once (take result, or an empty result when
## cancelled). Returns the panel, or null when the session could not start (empty node).
static func open(host: Node, node: Dictionary, title: String, tool_tier: int, seed_value: int, on_done: Callable) -> Control:
	var actor: Variant = Life.player
	if not (actor is Node3D) or not is_instance_valid(actor):
		return null
	var start_pos: Vector3 = actor.global_position
	var s := GatherSession.new()
	if not s.start(node, skill_level(String(GatherSession.KINDS.get(String(node.get("kind", "")), {}).get("skill", ""))), tool_tier, seed_value):
		return null
	var previous: Variant = _active_panel.get_ref() if _active_panel != null else null
	if is_instance_valid(previous):
		previous.call("cancel")
	var layer := CanvasLayer.new()
	layer.layer = 18
	# The world lives in a SubViewport behind the HUD: a panel parented there never gets clicks (the HUD's full-screen
	# look area swallows them). Parent it to the game scene's own viewport so it sits above the HUD (layer 10).
	var tree := host.get_tree()
	(tree.current_scene if tree != null and tree.current_scene != null else host).add_child(layer)
	var panel: Control = GatherPanel.new()
	layer.add_child(panel)
	panel.call("setup", s, title)
	_active_panel = weakref(panel)
	panel.connect("finished", func(res: Dictionary) -> void:
		if _active_panel != null and _active_panel.get_ref() == panel:
			_active_panel = null
		if is_instance_valid(layer):
			layer.queue_free()
		if on_done.is_valid():
			on_done.call(res))
	var guard := Timer.new()
	guard.wait_time = 0.2
	panel.add_child(guard)
	guard.timeout.connect(func() -> void:
		if not is_instance_valid(actor) or actor != Life.player:
			panel.call("cancel")
		elif bool(actor.get("dead")) or actor.global_position.distance_squared_to(start_pos) > 16.0:
			panel.call("cancel")
		elif actor.has_method("_menu_open") and bool(actor.call("_menu_open")):
			panel.call("cancel"))
	guard.start()
	return panel


static func skill_level(skill: String) -> int:
	var c: Variant = Life.get("crafting")
	return int((c as Object).call("level", skill)) if c is Object and skill != "" else 1


## Grants the session's XP to its skill; returns the new level (or 0 with no crafting).
static func grant_xp(res: Dictionary, mult := 1.0) -> int:
	var c: Variant = Life.get("crafting")
	if not c is Object or String(res.get("skill", "")) == "":
		return 0
	return int((c as Object).call("add_xp", String(res["skill"]), int(round(float(res.get("xp", 3)) * mult))))


static func has_tool(tool: String) -> bool:
	if tool == "":
		return false
	if Life.count(tool) > 0:
		return true
	var eq: Variant = Life.get("equipment")
	return eq is Object and String((eq as Object).call("item_in", "main_hand")) == tool


## Gives the gathered items with their quality tier and applies hazard damage to the player. Returns a
## " Hurt: N." style suffix for the toast ("" without damage).
static func deliver(res: Dictionary, n: int) -> String:
	if n > 0:
		Crafting.give_item(Life, String(res["item"]), n, int(res.get("tier", 1)))
	var dmg := int(res.get("damage", 0))
	if dmg > 0 and Life.player != null and is_instance_valid(Life.player):
		(Life.player as Object).call("take_damage", dmg)
		return "  It costs you %d health." % dmg
	return ""
