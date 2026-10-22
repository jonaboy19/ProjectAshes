extends RefCounted
## Type registry of the objective library: JSON "type" -> script. `create` builds one from a data dictionary
## (null for an unknown type), `from_save` rebuilds one from `save()` output.

const TYPES := {
	"goto": preload("res://scripts/quests/objectives/goto.gd"),
	"talk_to": preload("res://scripts/quests/objectives/talk_to.gd"),
	"kill": preload("res://scripts/quests/objectives/kill.gd"),
	"collect": preload("res://scripts/quests/objectives/collect.gd"),
	"deliver": preload("res://scripts/quests/objectives/deliver.gd"),
	"escort": preload("res://scripts/quests/objectives/escort.gd"),
	"protect": preload("res://scripts/quests/objectives/protect.gd"),
	"investigate": preload("res://scripts/quests/objectives/investigate.gd"),
	"wait": preload("res://scripts/quests/objectives/wait.gd"),
	"observe": preload("res://scripts/quests/objectives/observe.gd"),
	"choose": preload("res://scripts/quests/objectives/choose.gd"),
}
## Story-event style names accepted as aliases.
const ALIASES := {"talk": "talk_to", "enter_area": "goto", "item": "collect"}


static func type_names() -> PackedStringArray:
	var out := PackedStringArray(TYPES.keys())
	out.sort()
	return out


static func has_type(t: String) -> bool:
	return TYPES.has(ALIASES.get(t, t))


static func create(d: Dictionary) -> RefCounted:
	var t := String(d.get("type", ""))
	t = String(ALIASES.get(t, t))
	if not TYPES.has(t):
		return null
	var o: RefCounted = TYPES[t].new()
	var dd := d.duplicate(true)
	dd["type"] = t
	o.setup(dd)
	return o


static func from_save(s: Dictionary) -> RefCounted:
	var o := create(s.get("data", {"type": s.get("type", "")}) if s.has("data") else {"type": s.get("type", ""), "id": s.get("id", "")})
	if o != null:
		o.load_state(s)
	return o
