extends PanelContainer
## Debug inspector for one registry character (WP-08): needs, goal, plan, last decision inputs and memories.
## `snapshot(hub, ch)` is pure data (tests and logs use it); the panel just prints `format(snapshot)`.

const MEM_SHOWN := 6

var hub: RefCounted = null
var ch := ""
var _label: RichTextLabel = null


static func snapshot(hub_ref: Variant, ch_id: String) -> Dictionary:
	var out := {"ch": ch_id, "ok": false}
	if hub_ref == null:
		return out
	var minds: Variant = hub_ref.mod("minds")
	var rum: Variant = hub_ref.mod("rumours")
	var psy: Variant = hub_ref.mod("psyche")
	if minds == null:
		return out
	var sid: int = int(minds.town_of(ch_id))
	out["ok"] = true
	out["sid"] = sid
	out["goal"] = String(minds.goal_of(ch_id))
	out["plan"] = minds.plan_of(ch_id)
	out["needs"] = (minds.town_facts(sid) as Dictionary) if sid >= 0 else {}
	out["inputs"] = minds.trace_inputs(ch_id)
	var decisions: Array = minds.trace(ch_id)
	out["last_decision"] = decisions[0] if not decisions.is_empty() else {}
	out["memories"] = (rum.memories(ch_id) as Array).slice(0, MEM_SHOWN) if rum != null else []
	out["moods"] = (psy.memories(ch_id) as Array).slice(0, MEM_SHOWN) if psy != null else []
	return out


static func format(s: Dictionary) -> String:
	if not bool(s.get("ok", false)):
		return "%s: no data" % String(s.get("ch", "?"))
	var lines: Array[String] = ["%s  town %d  goal %s" % [s["ch"], int(s["sid"]), s["goal"]]]
	var plan: Dictionary = s["plan"]
	lines.append("plan: " + ("none" if plan.is_empty() else "%s commit %d steps %s" % [plan["id"], int(plan["commit"]), ", ".join(PackedStringArray(plan["steps"]))]))
	lines.append("needs (town): " + JSON.stringify(s["needs"]))
	lines.append("inputs: " + JSON.stringify(s["inputs"]))
	for m: Dictionary in s["memories"]:
		lines.append("memory d%d %s about %s (mag %.1f, conf %d)" % [int(m["day"]), m["kind"], m["subject"], float(m["mag"]), int(m["conf"])])
	return "\n".join(PackedStringArray(lines))


func show_character(hub_ref: RefCounted, ch_id: String) -> void:
	hub = hub_ref
	ch = ch_id
	refresh()


func refresh() -> void:
	if _label == null:
		_label = RichTextLabel.new()
		_label.fit_content = true
		_label.custom_minimum_size = Vector2(420, 0)
		add_child(_label)
	_label.text = format(snapshot(hub, ch))
