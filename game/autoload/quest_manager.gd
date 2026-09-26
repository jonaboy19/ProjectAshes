extends Node
## Data-driven linear quests (res://data/quests.json).
## A quest only advances when the step you name is the current step, so world
## triggers can fire freely without skipping story beats.

signal quest_updated(quest_id: String, title: String, step_text: String)
signal step_started(quest_id: String, step_id: String)
signal quest_completed(quest_id: String, title: String)

var quests: Dictionary = {}
## quest_id -> current step index (== steps.size() when complete)
var progress: Dictionary = {}
var tracked: String = ""


func _ready() -> void:
	quests = GameState.load_json("res://data/quests.json")


func start(quest_id: String) -> void:
	if not quests.has(quest_id) or progress.has(quest_id):
		return
	progress[quest_id] = 0
	tracked = quest_id
	_announce(quest_id)


func current_step(quest_id: String) -> String:
	if not progress.has(quest_id):
		return ""
	var steps: Array = quests[quest_id]["steps"]
	var index: int = progress[quest_id]
	return steps[index]["id"] if index < steps.size() else ""


func is_on_step(quest_id: String, step_id: String) -> bool:
	return current_step(quest_id) == step_id


## Completes `step_id` if it is the current step. Returns true on success.
func advance(quest_id: String, step_id: String) -> bool:
	if not is_on_step(quest_id, step_id):
		return false
	progress[quest_id] += 1
	var steps: Array = quests[quest_id]["steps"]
	if progress[quest_id] >= steps.size():
		quest_completed.emit(quest_id, quests[quest_id]["title"])
		quest_updated.emit(quest_id, quests[quest_id]["title"], "Complete")
	else:
		_announce(quest_id)
	GameState.save_game()
	return true


func serialize() -> Dictionary:
	return {"progress": progress, "tracked": tracked}


func deserialize(data: Dictionary) -> void:
	progress = data.get("progress", {})
	tracked = data.get("tracked", "")
	if tracked != "":
		_announce(tracked)


func _announce(quest_id: String) -> void:
	var quest: Dictionary = quests[quest_id]
	var step: Dictionary = quest["steps"][progress[quest_id]]
	quest_updated.emit(quest_id, quest["title"], step["text"])
	step_started.emit(quest_id, step["id"])
