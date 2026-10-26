extends Node3D
## A well (or spring / water trough): "Drink" quenches thirst; once you are quenched the verb becomes "Fill flask",
## which gives a Flask of Clean Water (data/items/food.json clean_water, drinkable later from the pack) up to MAX_FLASKS.

const MAX_FLASKS := 3
const DRINK := 60.0

var source_name := "Well"


static func spawn(parent: Node, pos: Vector3, title := "Well") -> Node3D:
	var w: Node3D = load("res://scripts/interaction/kinds/well.gd").new()
	w.set("source_name", title)
	w.name = "WaterSource"
	parent.add_child(w)
	w.position = pos   # parent-local (settlement roots sit at the origin)
	return w


func _ready() -> void:
	Interactable.attach(self, {"id_fn": func() -> String: return "water/%d_%d" % [roundi(global_position.x), roundi(global_position.z)],
		"verb": "Drink", "range": 2.8,
		"do": func(_p: Node) -> void: use(),
		"label": func() -> Dictionary: return {"verb": verb(), "target": source_name}})


## Pure: which action the source offers for a thirst value and flask count.
static func action_for(water: float, flasks: int) -> String:
	if water < 90.0:
		return "drink"
	return "fill" if flasks < MAX_FLASKS else "drink"


func verb() -> String:
	return "Fill flask" if action_for(Life.needs.water, Life.count("clean_water")) == "fill" else "Drink"


func use() -> String:
	var msg := ""
	if action_for(Life.needs.water, Life.count("clean_water")) == "fill":
		Life.give("clean_water")
		msg = "You fill a flask with clean water."
	else:
		Life.needs.drink(DRINK)
		msg = "You drink deeply. You feel %s." % Life.needs.thirst_label().to_lower()
	if Engine.get_main_loop() != null:
		var a := (Engine.get_main_loop() as SceneTree).root.get_node_or_null(^"Audio")
		if a != null and a.has_method("play_sfx"):
			a.call("play_sfx", "step_water", global_position, -6.0)
	var scene := get_tree().current_scene
	var hud: Variant = scene.get("hud") if scene else null
	if hud is Object and (hud as Object).has_method("notify"):
		(hud as Object).call("notify", "info", source_name, msg)
	return msg
