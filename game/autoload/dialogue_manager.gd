extends Node
## Loads conversations from res://data/dialogue/*.json and plays them line by line.
## The UI listens to the signals; gameplay code only calls start()/start_for_npc().
##
## Entry format:
##   "id": {"speaker": "Name", "lines": ["..."],
##          "on_finish": {"set_flag": "x", "advance_quest": ["quest", "step"], "start_quest": "q"}}
## NPC routing: "npcs": {"npc_id": [{"id": "entry", "requires": ["flag"], "forbids": ["flag"]}]}
## The first route whose conditions pass is played.

signal dialogue_started(entry_id: String)
signal line_shown(speaker: String, text: String)
signal dialogue_ended(entry_id: String)

var entries: Dictionary = {}
var npc_routes: Dictionary = {}
var active_id: String = ""
var _line_index := 0


func _ready() -> void:
	var dir := DirAccess.open("res://data/dialogue")
	if dir == null:
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var data := GameState.load_json("res://data/dialogue/" + file_name)
		entries.merge(data.get("entries", {}), true)
		npc_routes.merge(data.get("npcs", {}), true)


func is_active() -> bool:
	return active_id != ""


func start_for_npc(npc_id: String) -> void:
	for route: Dictionary in npc_routes.get(npc_id, []):
		if _conditions_pass(route):
			start(route["id"])
			return


func start(entry_id: String) -> void:
	if is_active() or not entries.has(entry_id):
		return
	active_id = entry_id
	_line_index = 0
	dialogue_started.emit(entry_id)
	_show_line()


func advance() -> void:
	if not is_active():
		return
	_line_index += 1
	if _line_index < entries[active_id]["lines"].size():
		_show_line()
		return
	var finished := active_id
	active_id = ""
	_apply_effects(entries[finished].get("on_finish", {}))
	dialogue_ended.emit(finished)


func _show_line() -> void:
	var entry: Dictionary = entries[active_id]
	line_shown.emit(entry.get("speaker", ""), entry["lines"][_line_index])


func _conditions_pass(route: Dictionary) -> bool:
	for flag: String in route.get("requires", []):
		if not GameState.get_flag(flag):
			return false
	for flag: String in route.get("forbids", []):
		if GameState.get_flag(flag):
			return false
	for step: Array in route.get("on_step", []):
		if not Quests.is_on_step(step[0], step[1]):
			return false
	return true


func _apply_effects(effects: Dictionary) -> void:
	if effects.has("set_flag"):
		GameState.set_flag(effects["set_flag"])
	if effects.has("start_quest"):
		Quests.start(effects["start_quest"])
	if effects.has("advance_quest"):
		Quests.advance(effects["advance_quest"][0], effects["advance_quest"][1])
