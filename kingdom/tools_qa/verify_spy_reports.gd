extends SceneTree
## Full production scripts and Campaign serializer, with project autoloads.
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	for path: String in ["res://scripts/actors/player.gd", "res://scripts/realm/enterprise.gd"]:
		var script: Script = load(path)
		if script == null or not script.can_instantiate():
			push_error("Cannot instantiate production script: " + path)
			quit(1)
			return
	var script: Script = load("res://scripts/realm/campaign.gd")
	if script == null or not script.can_instantiate():
		quit(1)
		return
	var campaign = script.new()
	campaign.set("_hours", 16)
	assert(campaign.queue_observation(7, "north", "scout:42", Vector2(120, -80), 10, 80, 140, 4))
	assert(campaign.enemy_pieces().is_empty())
	var saved: Dictionary = JSON.parse_string(JSON.stringify(campaign.serialize()))
	var restored = script.new()
	restored.deserialize(saved)
	assert(restored.now_hours() == 16)
	var messages: Array = []
	restored.set("_hours", 19)
	restored._deliver_spy_reports(messages)
	assert(restored.enemy_pieces().is_empty() and messages.is_empty())
	restored.set("_hours", 20)
	restored._deliver_spy_reports(messages)
	var pieces: Array = restored.enemy_pieces()
	assert(pieces.size() == 1 and pieces[0].age_hours == 10)
	assert(pieces[0].pos == Vector2(120, -80) and messages.size() == 1)
	var delivered = script.new()
	delivered.deserialize(JSON.parse_string(JSON.stringify(restored.serialize())))
	assert(delivered.enemy_pieces()[0].age_hours == 10)
	assert(delivered.enemy_pieces()[0].pos == Vector2(120, -80))
	print("PRODUCTION_SPY_SAVE_PASS Player/Enterprise/Campaign load; pending and delivered full Campaign JSON round trips")
	quit()
