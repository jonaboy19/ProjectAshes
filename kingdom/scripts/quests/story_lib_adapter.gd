extends RefCounted
## Lets Region 1 story steps use library objectives. A step objective of type "lib" wraps one library objective:
##
##   {"id": "watch", "type": "lib", "objective": {"type": "observe", "target": "barn_figure", "seconds": 20}}
##
## Region1StoryQuest.notify feeds every story event (enter_area, kill, talk, ...) to the wrapped objective, and the
## step's objective completes when the library objective is done. Story progress is saved per objective id as whole units plus
## the objective's own state, so a loaded game resumes exactly where it was. Library objective ids must be
## unique within the story quest. Event names and parameters are the story's own, so nothing new is needed on the
## director's side; extra library events (interact, hours, observe, ...) can be passed to `StoryQuest.notify` too.

const Objectives := preload("res://scripts/quests/quest_objectives.gd")


## The live library objective for story objective `o`, restored from the saved units in `p` when first used.
static func objective(cache: Dictionary, o: Dictionary, p: Dictionary) -> RefCounted:
	var oid := String(o.get("id", ""))
	if not cache.has(oid):
		var d: Dictionary = (o.get("objective", {}) as Dictionary).duplicate(true)
		d["id"] = oid
		var obj := Objectives.create(d)
		if obj == null:
			return null
		var saved: Variant = JSON.parse_string(String(p.get("_lib_" + oid, "")))
		if saved is Dictionary:
			obj.load_state(saved)
		else:
			obj.load_state({"have": float(p.get(oid, 0)), "done": bool(p.get("_done_" + oid, false))})
		cache[oid] = obj
	return cache[oid]


## Feed one event; saves the objective's units into the step progress `p` (whole units, plus the full objective state as a JSON string). True when anything changed.
static func feed(cache: Dictionary, o: Dictionary, t: String, params: Dictionary, p: Dictionary) -> bool:
	var obj := objective(cache, o, p)
	if obj == null:
		return false
	var changed: bool = obj.on_event(StringName(t), params)
	if changed:
		p[String(o.get("id", ""))] = int(obj.have)
		p["_lib_" + String(o.get("id", ""))] = JSON.stringify(obj.save())   # full state (found clues, watch seconds)
	return changed


static func is_done(cache: Dictionary, o: Dictionary, p: Dictionary) -> bool:
	var obj := objective(cache, o, p)
	return obj != null and obj.is_done()
