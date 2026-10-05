extends RefCounted
## Shared glue for world nodes that run a GatherSession through the mobile panel (forage_nodes, build_resources,
## fishing_spot, ore_vein style). Static helpers only; the nodes keep their own spawn and visuals.

const GatherSession := preload("res://scripts/sim/gather_session.gd")
const GatherPanel := preload("res://scripts/ui/gather_panel.gd")
const Crafting := preload("res://scripts/sim/crafting.gd")


## Opens the panel under `host`. on_done(result: Dictionary) runs once (take result, or an empty result when
## cancelled). Returns the panel, or null when the session could not start (empty node).
static func open(host: Node, node: Dictionary, title: String, tool_tier: int, seed_value: int, on_done: Callable) -> Control:
	var s := GatherSession.new()
	if not s.start(node, skill_level(String(GatherSession.KINDS.get(String(node.get("kind", "")), {}).get("skill", ""))), tool_tier, seed_value):
		return null
	var layer := CanvasLayer.new()
	layer.layer = 18
	# The world lives in a SubViewport behind the HUD: a panel parented there never gets clicks (the HUD's full-screen
	# look area swallows them). Parent it to the game scene's own viewport so it sits above the HUD (layer 10).
	var tree := host.get_tree()
	(tree.current_scene if tree != null and tree.current_scene != null else host).add_child(layer)
	var panel: Control = GatherPanel.new()
	layer.add_child(panel)
	panel.call("setup", s, title)
	panel.connect("finished", func(res: Dictionary) -> void:
		if is_instance_valid(layer):
			layer.queue_free()
		on_done.call(res))
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
