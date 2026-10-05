class_name QuestRunner
extends RefCounted
## Runs library quests. Listens to a QuestBus; every event goes to the open objectives of every active quest.
##
##   var r := QuestRunner.new(bus)          # QuestBus.shared() by default
##   r.add_def(QuestDef.load_json(path))    # or r.load_dir("res://data/quests/thornfield")
##   r.start("thornfield_spoiled_barley")   # "" or the reason it can't
##   bus.emit_event(&"interact", {"id": "thornfield/clue/sack"})
##
## Stage modes: all (every non-optional objective), any (one is enough), sequence (in order, only the first open
## one listens). An objective failing fails the stage (all/sequence) or, in `any`, once every one has failed; a
## failed stage fails the quest. A Choose objective picks the next stage through the stage's `branches`.
## Rewards go through `reward_fn(rewards) -> String` (QuestRewards.apply by default).
##
## Save: serialize()/deserialize() is JSON-safe; QuestHub registers it with Region1State, the same save path
## Life.snapshot uses for "region1".

const Def := preload("res://scripts/quests/quest_def.gd")
const Objectives := preload("res://scripts/quests/quest_objectives.gd")
const Rewards := preload("res://scripts/quests/quest_rewards.gd")
const SAVE_VERSION := 1

## {type: "started"|"objective_done"|"stage"|"completed"|"failed", quest, stage?, objective?, text}
signal quest_event(e: Dictionary)

var bus: QuestBus = null
var defs: Dictionary = {}                 # quest id -> QuestDef
var runs: Dictionary = {}                 # quest id -> Run (active, done and failed quests)
var pinned: Array = []                    # quest ids the player pinned (the only source of markers)
var reward_fn := Callable()
var clock_fn := Callable()                # () -> float game day, for started/finished stamps
var history_log: Array[Dictionary] = []


class Run extends RefCounted:
	var id := ""
	var state := "active"                 # active | done | failed
	var stage := ""
	var objs: Array = []
	var chosen: Dictionary = {}           # choose objective id -> option id
	var history: Array = []               # stage ids completed, in order
	var started := 0.0
	var finished := -1.0
	var ending := ""                      # id of the last stage reached
	var paid := ""                        # reward summary text of the last payout


func _init(p_bus: QuestBus = null) -> void:
	bind(p_bus if p_bus != null else QuestBus.shared())


func bind(p_bus: QuestBus) -> void:
	if bus != null and bus.fired.is_connected(handle_event):
		bus.fired.disconnect(handle_event)
	bus = p_bus
	bus.fired.connect(handle_event)


func unbind() -> void:
	if bus != null and bus.fired.is_connected(handle_event):
		bus.fired.disconnect(handle_event)


# --- definitions ----------------------------------------------------------------------

func add_def(d: QuestDef) -> void:
	if d != null and d.id != "":
		defs[d.id] = d


func load_dir(dir: String) -> int:
	var n := 0
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			var d := QuestDef.load_json(dir.path_join(f))
			if d != null:
				add_def(d)
				n += 1
	return n


func def(id: String) -> QuestDef:
	return defs.get(id) as QuestDef


# --- starting and stopping ---------------------------------------------------------------

## "" when the quest can be taken now, else the reason.
func can_start(id: String) -> String:
	var d := def(id)
	if d == null:
		return "No such quest."
	var r := run(id)
	if r != null and r.state != "failed":
		return "You already have this one." if r.state == "active" else "That is finished."
	for req: Variant in d.requires():
		if not is_done(String(req)):
			return "Not yet."
	return ""


func start(id: String) -> String:
	var why := can_start(id)
	if why != "":
		return why
	var d := def(id)
	var r := Run.new()
	r.id = id
	r.started = _now()
	runs[id] = r
	_enter_stage(r, d.first_stage())
	_emit({"type": "started", "quest": id, "text": "Quest started: %s" % d.title})
	return ""


func abandon(id: String) -> void:
	var r := run(id)
	if r == null or r.state != "active":
		return
	runs.erase(id)
	pinned.erase(id)


## Definitions this person offers right now.
func offers_for(npc: String) -> Array[QuestDef]:
	var out: Array[QuestDef] = []
	for id: String in defs:
		var d: QuestDef = defs[id]
		if d.giver_npc() != "" and d.giver_npc().to_lower() == npc.to_lower() and can_start(id) == "":
			out.append(d)
	return out


# --- queries --------------------------------------------------------------------------

func run(id: String) -> Run:
	return runs.get(id) as Run


func is_active(id: String) -> bool:
	return run(id) != null and run(id).state == "active"


func is_done(id: String) -> bool:
	return run(id) != null and run(id).state == "done"


func is_failed(id: String) -> bool:
	return run(id) != null and run(id).state == "failed"


func active_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in runs:
		if (runs[id] as Run).state == "active":
			out.append(id)
	out.sort()
	return out


func stage_of(id: String) -> String:
	return run(id).stage if run(id) != null else ""


func objectives_of(id: String) -> Array:
	return run(id).objs if run(id) != null else []


## Open choose objectives of a quest's current stage: [{objective, options: [{id, text}], npc}].
func pending_choices(id: String) -> Array:
	var out: Array = []
	var r := run(id)
	if r == null or r.state != "active":
		return out
	for o: RefCounted in r.objs:
		if o.type == "choose" and not o.is_done():
			out.append({"objective": o.id, "options": o.data.get("options", []), "npc": String(o.data.get("npc", ""))})
	return out


## Open talk objectives of active quests aimed at `npc`: quest ids waiting to hear from them.
func quests_awaiting_talk(npc: String) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in active_ids():
		for o: RefCounted in (run(id) as Run).objs:
			if o.type == "talk_to" and not o.is_done() and not o.is_failed() and _listening(run(id), o) \
					and String(o.data.get("npc", "")).to_lower() == npc.to_lower():
				out.append(id)
				break
	return out


# --- events ---------------------------------------------------------------------------

## Convenience: fire an event on the bus this runner listens to.
func notify(type: StringName, ev: Dictionary = {}) -> void:
	bus.emit_event(type, ev)


func handle_event(type: StringName, ev: Dictionary) -> void:
	for id: String in active_ids():
		var r := run(id)
		var touched := false
		for o: RefCounted in r.objs:
			if not _listening(r, o):
				continue
			var was_done: bool = o.is_done()
			if o.on_event(type, ev):
				touched = true
				if o.type == "choose" and o.chosen != "":
					r.chosen[o.id] = o.chosen
				if o.is_done() and not was_done:
					_emit({"type": "objective_done", "quest": id, "stage": r.stage, "objective": o.id, "text": o.describe()})
		if touched:
			_evaluate(r)


## Whether an objective currently hears events: all of them, except later ones in a `sequence` stage.
func _listening(r: Run, o: RefCounted) -> bool:
	if o.is_done() or o.is_failed():
		return false
	var d := def(r.id)
	var s := d.stage(r.stage) if d != null else {}
	if String(s.get("mode", "all")) != "sequence":
		return true
	for p: RefCounted in r.objs:
		if p == o:
			return true
		if not p.is_done() and not p.optional:
			return false
	return true


func _evaluate(r: Run) -> void:
	var guard := 0
	while r.state == "active" and guard < 16:
		guard += 1
		var d := def(r.id)
		var s := d.stage(r.stage)
		var mode := String(s.get("mode", "all"))
		var open := r.objs.filter(func(o: RefCounted) -> bool: return not o.optional)
		if open.is_empty():
			open = r.objs
		var n_done := open.filter(func(o: RefCounted) -> bool: return o.is_done()).size()
		var n_failed := open.filter(func(o: RefCounted) -> bool: return o.is_failed()).size()
		var stage_done := (n_done >= 1) if mode == "any" else (n_done == open.size())
		var stage_failed := (n_failed == open.size()) if mode == "any" else (n_failed >= 1)
		if stage_failed and not stage_done:
			_fail(r)
			return
		if not stage_done:
			return
		r.history.append(r.stage)
		var pay := _pay(s.get("rewards", {}))
		r.paid = pay
		_emit({"type": "stage", "quest": r.id, "stage": r.stage, "text": "%s%s" % [String(s.get("title", r.stage)), (" (%s)" % pay) if pay != "" else ""]})
		var nxt := d.next_stage(r.stage, r.chosen)
		if nxt == "":
			_complete(r)
			return
		_enter_stage(r, nxt)


func _enter_stage(r: Run, sid: String) -> void:
	var d := def(r.id)
	r.stage = sid
	r.ending = sid
	r.objs = []
	for od: Dictionary in d.stage(sid).get("objectives", []):
		var o := Objectives.create(od)
		if o != null:
			r.objs.append(o)


func _complete(r: Run) -> void:
	var d := def(r.id)
	r.state = "done"
	r.finished = _now()
	var pay := _pay(d.rewards())
	if pay != "":
		r.paid = pay
	_emit({"type": "completed", "quest": r.id, "text": "Quest complete: %s%s" % [d.title, (" (%s)" % pay) if pay != "" else ""]})


func _fail(r: Run) -> void:
	var d := def(r.id)
	r.state = "failed"
	r.finished = _now()
	pinned.erase(r.id)
	_pay(d.data.get("on_fail", {}))
	_emit({"type": "failed", "quest": r.id, "text": "Quest failed: %s" % d.title})


func _pay(rewards: Dictionary) -> String:
	if rewards.is_empty():
		return ""
	return String(reward_fn.call(rewards)) if reward_fn.is_valid() else Rewards.apply(rewards)


func _now() -> float:
	return float(clock_fn.call()) if clock_fn.is_valid() else 0.0


func _emit(e: Dictionary) -> void:
	history_log.append(e)
	if history_log.size() > 128:
		history_log.pop_front()
	quest_event.emit(e)


# --- journal and pins ---------------------------------------------------------------------

## Entries for the journal screen: active quests first, then finished and failed ones.
## [{id, title, state, summary, giver, stage, lines: [{text, done, failed}], pinned, ending}]
func journal() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pass_state: String in ["active", "done", "failed"]:
		var ids := PackedStringArray()
		for id: String in runs:
			if (runs[id] as Run).state == pass_state:
				ids.append(id)
		ids.sort()
		for id: String in ids:
			var r := run(id)
			var d := def(id)
			if d == null:
				continue
			var lines: Array = []
			if r.state == "active":
				for o: RefCounted in r.objs:
					lines.append({"text": o.describe(), "done": o.is_done(), "failed": o.is_failed()})
			out.append({"id": id, "title": d.title, "state": r.state, "summary": d.summary(), "giver": d.giver_name(),
				"stage": String(d.stage(r.stage).get("title", "")), "lines": lines, "pinned": pinned.has(id),
				"ending": r.ending, "paid": r.paid})
	return out


## One block of plain text per quest, for menus that only show strings.
func journal_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for e: Dictionary in journal():
		var head := "%s%s" % ["▸ " if bool(e["pinned"]) else "", e["title"]]
		match String(e["state"]):
			"done":
				out.append("%s - done" % head)
			"failed":
				out.append("%s - failed" % head)
			_:
				var parts := PackedStringArray()
				for l: Dictionary in e["lines"]:
					parts.append(("[x] " if bool(l["done"]) else "[ ] ") + String(l["text"]))
				out.append("%s - %s" % [head, "; ".join(parts)])
	return out


func pin(id: String) -> void:
	if is_active(id) and not pinned.has(id):
		pinned.append(id)


func unpin(id: String) -> void:
	pinned.erase(id)


func is_pinned(id: String) -> bool:
	return pinned.has(id)


## Map/compass markers: only for quests the player pinned, only for open objectives that have a position.
func pinned_markers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in pinned:
		var r := run(id)
		if r == null or r.state != "active":
			continue
		for o: RefCounted in r.objs:
			var p: Variant = o.marker_pos()
			if p is Vector2 and not o.is_done():
				out.append({"quest": id, "objective": o.id, "pos": p, "text": o.describe()})
				break
	return out


# --- save -------------------------------------------------------------------------------

func serialize() -> Dictionary:
	var rs := {}
	for id: String in runs:
		var r: Run = runs[id]
		var objs: Array = []
		for o: RefCounted in r.objs:
			objs.append(o.save())
		rs[id] = {"state": r.state, "stage": r.stage, "objs": objs, "chosen": r.chosen.duplicate(), "history": r.history.duplicate(),
			"started": r.started, "finished": r.finished, "ending": r.ending, "paid": r.paid}
	return {"version": SAVE_VERSION, "runs": rs, "pinned": pinned.duplicate()}


func deserialize(d: Dictionary) -> void:
	runs.clear()
	pinned.clear()
	var rs: Dictionary = d.get("runs", {})
	for id: String in rs:
		var s: Dictionary = rs[id]
		var r := Run.new()
		r.id = id
		r.state = String(s.get("state", "active"))
		r.stage = String(s.get("stage", ""))
		r.chosen = (s.get("chosen", {}) as Dictionary).duplicate()
		r.history = (s.get("history", []) as Array).duplicate()
		r.started = float(s.get("started", 0.0))
		r.finished = float(s.get("finished", -1.0))
		r.ending = String(s.get("ending", ""))
		r.paid = String(s.get("paid", ""))
		for os: Variant in s.get("objs", []):
			var o := Objectives.from_save(os)
			if o != null:
				r.objs.append(o)
		runs[id] = r
	for p: Variant in d.get("pinned", []):
		pinned.append(String(p))
