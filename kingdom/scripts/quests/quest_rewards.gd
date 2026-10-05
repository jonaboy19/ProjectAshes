extends RefCounted
## Pays quest rewards through the game's own APIs: gold (Game.add_gold), items (Life.give), faction
## reputation and personal opinion (Life.relationships), life-path flags (Life.life_path.set_flag).
## Autoloads are looked up by path so the library itself stays loadable without a running game.
##
## rewards = {gold: int, items: {item: n}, rep: {faction: n}, flags: [name],
##            relationship: [{npc, value, label, days}]}
## Returns the summary text, e.g. "+15g, Thornfield +4".


static func _autoload(name: String) -> Object:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(name) if tree != null else null


static func apply(rewards: Dictionary) -> String:
	var parts := PackedStringArray()
	if rewards.is_empty():
		return ""
	var game := _autoload("Game")
	var life := _autoload("Life")
	var gold := int(rewards.get("gold", 0))
	if gold != 0 and game != null:
		game.call("add_gold", gold)
		parts.append("%+dg" % gold)
	var items: Dictionary = rewards.get("items", {})
	for item: String in items:
		if life != null:
			life.call("give", item, int(items[item]))
		parts.append("%s x%d" % [item.replace("_", " "), int(items[item])])
	var rel: Object = life.get("relationships") if life != null else null
	if rel != null:
		var reps: Dictionary = rewards.get("rep", {})
		for f: String in reps:
			rel.call("change_rep", f, float(reps[f]))
			parts.append("%s %+d" % [rel.call("faction_name", f), int(reps[f])])
		var now := _now()
		for r: Variant in rewards.get("relationship", []):
			var d: Dictionary = r
			rel.call("add_modifier", String(d.get("npc", "")), String(d.get("id", "quest")), String(d.get("label", "Remembers what you did")),
				float(d.get("value", 0.0)), now, float(d.get("days", 60.0)), int(d.get("stacks", 3)))
	if life != null:
		var lp: Variant = life.get("life_path")
		if lp is Object:
			for f: Variant in rewards.get("flags", []):
				(lp as Object).call("set_flag", String(f))
	return ", ".join(parts)


static func _now() -> float:
	var ws := _autoload("WorldSim")
	return float(ws.get("day")) + float(ws.get("time_of_day")) / 24.0 if ws != null else 0.0
