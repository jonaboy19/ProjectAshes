class_name QuestHub
extends RefCounted
## The game's one QuestRunner (library quests) and its save hook. `runner()` builds it on first use: it listens
## to QuestBus.shared(), loads every definition under data/quests/*/ and registers with Region1State, so the
## runner is saved and restored inside Life's "region1" snapshot with no change to Life itself
## (the same path Region1StoryQuest uses).

const REGION1_STATE := "res://scripts/region1/region1_state.gd"
const DATA_ROOT := "res://data/quests"
const MODULE := &"quest_lib"

static var _runner: QuestRunner = null


static func runner() -> QuestRunner:
	if _runner == null:
		_runner = QuestRunner.new(QuestBus.shared())
		for sub: String in DirAccess.get_directories_at(DATA_ROOT):
			_runner.load_dir(DATA_ROOT.path_join(sub))
		_runner.clock_fn = _clock
		var rs: Variant = load(REGION1_STATE)
		if rs != null:
			rs.register(MODULE, _snapshot, _restore, QuestRunner.SAVE_VERSION)
	return _runner


## The runner if the game has built one, else null (the journal must not create it as a side effect).
static func peek() -> QuestRunner:
	return _runner


## Drops the runner (new game in tests, or a fresh process state).
static func reset() -> void:
	if _runner != null:
		_runner.unbind()
	_runner = null
	var rs: Variant = load(REGION1_STATE)
	if rs != null:
		rs.unregister(MODULE)


static func _snapshot() -> Dictionary:
	return _runner.serialize() if _runner != null else {}


static func _restore(d: Dictionary) -> void:
	if _runner != null:
		_runner.deserialize(d)


static func _clock() -> float:
	var tree := Engine.get_main_loop() as SceneTree
	var ws := tree.root.get_node_or_null("WorldSim") if tree != null else null
	return float(ws.get("day")) + float(ws.get("time_of_day")) / 24.0 if ws != null else 0.0
