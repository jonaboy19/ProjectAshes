extends RefCounted
## Soldier career UI pieces (F11), kept out of career_screen.gd / career_tasks.gd / village_services.gd so those
## stay small: the Captain's menu (HUD show_menu shape), the career screen summary section, and the work and
## ladder tabs of the career task screen. All text comes from the module's status_view().

const Career := preload("res://scripts/sim/soldier_career.gd")
const AF := preload("res://scripts/ui/ashes_frame.gd")
const OK_COL := Color("7be0a0")
const BAD_COL := Color("ff7a6e")
const DIM_COL := Color("9aa0a8")

static var day_override := -1


static func _day() -> int:
	return day_override if day_override >= 0 else int(WorldSim.day)


static var module_override: RefCounted = null


static func module() -> RefCounted:
	if module_override != null:
		return module_override
	var hub: Variant = Life.get("realm") if Life != null else null
	return hub.mod("soldier") if hub != null else null


## One-line pay text: "56g a week (docked 15% per missed muster)".
static func pay_text(v: Dictionary) -> String:
	if not bool(v["active"]):
		return "No wage."
	var t := "%dg a week" % int(v["wage"])
	if int(v["missed_week"]) > 0:
		t += ", %dg this week after %d missed muster%s" % [int(v["wage_this_week"]), int(v["missed_week"]), "" if int(v["missed_week"]) == 1 else "s"]
	if bool(v["on_leave"]):
		t += " (half pay on leave)"
	return t


## Plain lines for a squad: "Tam Barley - ready (60/60)".
static func squad_lines(v: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for m: Dictionary in v["squad"]:
		out.append("%s: %s (%d/%d HP, %d kills)" % [String(m["name"]), String(m["state"]), int(m["hp"]), int(m["max_hp"]), int(m["kills"])])
	return out


## Every line the career screen and the work tab show, as [heading, [lines]] pairs (UI-agnostic, testable).
static func summary(v: Dictionary) -> Array:
	var out: Array = []
	if not bool(v["active"]):
		var why := "Not enlisted."
		if bool(v["deserter"]) or String(v["struck_off"]) != "":
			why = "Struck off the rolls (%s). Banned until day %d." % [String(v["struck_off"]), int(v["banned_until"])]
		out.append(["Service", [why]])
		return out
	var service: Array = ["%s, %d merit." % [String(v["rank"]), int(v["merit"])], "Posted to %s under %s." % [String(v["post"]), String(v["officer"])]]
	if bool(v["on_leave"]):
		service.append("On leave until day %d." % int(v["leave_until"]))
	out.append(["Service", service])
	var nxt: Dictionary = v["next"]
	var promo: Array = []
	if nxt.is_empty():
		promo.append("You hold the highest rank this post offers.")
	else:
		promo.append("Next: %s." % String(nxt["title"]))
		for l: Dictionary in v["next_lines"]:
			promo.append(("[ok] " if bool(l["met"]) else "[  ] ") + String(l["text"]))
	out.append(["Promotion", promo])
	var pay: Array = [pay_text(v), "Muster at %02d:00. %s" % [int(Career.muster()["hour"]), "Answered today." if bool(v["attended_today"]) else "Not yet answered today."]]
	if int(v["missed_run"]) > 0:
		pay.append("Missed musters in a row: %d of %d. At %d you are a deserter." % [int(v["missed_run"]), int(v["desert_after"]), int(v["desert_after"])])
	out.append(["Pay and muster", pay])
	var d: Dictionary = v["duty"]
	var duty: Array = []
	if d.is_empty():
		duty.append("No duty posted.")
	else:
		duty.append("%s (%s). Reward %d merit, %dg." % [String(d["text"]), String(d["state"]), int(d["merit"]), int(d["gold"])])
		for l2: Dictionary in d["lines"]:
			duty.append(("[ok] " if bool(l2["done"]) else "[  ] ") + String(l2["text"]))
	out.append(["Today's duty", duty])
	var sq: Array = []
	if int(v["squad_size"]) == 0:
		sq.append("Corporals and above lead a squad.")
	else:
		sq.append_array(Array(squad_lines(v)))
	out.append(["Squad", sq])
	return out


# ---------------------------------------------------------------- career screen

## Adds the soldier section to the career screen's content box (headings and body labels in its style).
static func add_career_section(content: VBoxContainer, heading: Callable, body: Callable) -> void:
	var m := module()
	if m == null or not (bool(m.get("active")) or String(m.get("struck_off")) != ""):
		return
	content.add_child(heading.call("Soldier"))
	for pair: Array in summary(m.call("status_view", _day())):
		content.add_child(body.call("%s" % String(pair[0]).to_upper()))
		for line: String in pair[1]:
			content.add_child(body.call(line))


# ---------------------------------------------------------------- career task screen (work and ladder tabs)

static func fill_work(tasks: Control, m: RefCounted) -> void:
	var day := int(tasks.call("_day"))
	if m == null:
		tasks.call("_text", "The garrison is closed.")
		return
	m.call("todays_duty", day)
	var v: Dictionary = m.call("status_view", day)
	if not bool(v["active"]):
		var why: String = m.call("enlist_refusal", day)
		tasks.call("_card", "Enlist", "Take the Captain's coin. You are issued a kit, a post and an officer; muster is at %02d:00 each morning." % int(Career.muster()["hour"]))
		tasks.call("_btn", "Enlist at the guard post" if why == "" else why, func() -> void:
			var r: Dictionary = m.call("enlist", day, "guard_post")
			tasks.call("_refresh")
			tasks.call("_say", String(r.get("text", r.get("reason", "")))), why == "")
		if String(v["struck_off"]) != "":
			tasks.call("_text", "Struck off for %s." % String(v["struck_off"]), 16, BAD_COL)
		return
	for pair: Array in summary(v):
		var card: VBoxContainer = tasks.call("_card", String(pair[0]), "")
		for line: String in pair[1]:
			card.add_child(AF.label(line, 16, OK_COL if line.begins_with("[ok]") else (BAD_COL if line.begins_with("[  ]") else Color("e8e2d4"))))
	var d: Dictionary = v["duty"]
	if not d.is_empty() and String(d["state"]) == "offered":
		tasks.call("_btn", "Take today's duty", func() -> void:
			var r2: Dictionary = m.call("accept_duty", day)
			tasks.call("_refresh")
			tasks.call("_say", "Duty accepted." if bool(r2["ok"]) else String(r2["reason"])), true)
	elif not d.is_empty() and String(d["state"]) == "active":
		tasks.call("_btn", "Give up the duty", func() -> void:
			m.call("abandon_duty", day)
			tasks.call("_refresh"), true)
	tasks.call("_btn", "Request leave (3 days)", func() -> void:
		var r3: Dictionary = m.call("request_leave", day, 3)
		tasks.call("_refresh")
		tasks.call("_say", "Leave granted." if bool(r3["ok"]) else String(r3["reason"])), not bool(v["on_leave"]))


static func fill_ladder(tasks: Control, m: RefCounted) -> void:
	var day := int(tasks.call("_day"))
	if m == null:
		return
	var v: Dictionary = m.call("status_view", day)
	var cur := int(v["rank_idx"]) if bool(v["active"]) else -1
	for i in Career.rank_count():
		var mark := "[x] " if i < cur else ("[>] " if i == cur else "[ ] ")
		var d := Career.rank_def(i)
		var extra := "  (squad of %d)" % int(d["squad"]) if int(d["squad"]) > 0 else ""
		tasks.call("_text", "%s%s  merit %d, %d days, %dg a week%s" % [mark, String(d["title"]), int(d["merit"]), int(d["min_days"]), int(d["wage"]), extra], 18,
			OK_COL if i < cur else (Color("f0c060") if i == cur else DIM_COL))
	if cur >= 0:
		tasks.call("_btn", "Ask the officer for promotion", func() -> void:
			var r: Dictionary = m.call("petition", day)
			tasks.call("_refresh")
			tasks.call("_say", String(r["text"])), true)


# ---------------------------------------------------------------- Captain's menu

static func _enlist(m: RefCounted, day: int, source: String) -> String:
	var r: Dictionary = m.call("enlist", day, source)
	return String(r.get("text", r.get("reason", "")))


static func _muster(m: RefCounted, day: int) -> String:
	var pos := Vector2.ZERO
	var tree := Engine.get_main_loop() as SceneTree
	var pn: Node3D = tree.get_first_node_in_group("player") as Node3D if tree != null else null
	if pn != null:
		pos = Vector2(pn.global_position.x, pn.global_position.z)
	if bool(m.call("muster_attend", day, float(WorldSim.time_of_day), pos)):
		return "\"Present. Noted.\""
	return "\"Muster is at %02d:00, at the post. You are early, late, or already counted.\"" % int(Career.muster()["hour"])


static func _take_duty(m: RefCounted, day: int) -> String:
	var r: Dictionary = m.call("accept_duty", day)
	return "\"Good. Report back when it is done.\"" if bool(r["ok"]) else String(r["reason"])


static func _petition(m: RefCounted, day: int) -> String:
	return String(m.call("petition", day)["text"])


static func _leave(m: RefCounted, day: int) -> String:
	var r: Dictionary = m.call("request_leave", day, 3)
	return "\"Three days. Be back for muster.\"" if bool(r["ok"]) else String(r["reason"])


static func _resign(m: RefCounted, day: int) -> String:
	return String(m.call("resign", day))


static func _company(sv: Object, hud: Object) -> String:
	hud.call("show_menu", Callable(sv, "captain_menu"))
	return ""


## HUD menu source (hud.show_menu(Callable)). `sv` is the village services (for the company-hiring menu), may be null.
static func captain_menu(sv: Object) -> Dictionary:
	var m := module()
	var day := _day()
	var opts: Array = []
	var body := ""
	if m == null:
		return {"title": "Captain of the Guard", "body": "The captain is away.", "options": opts}
	m.call("todays_duty", day)
	var v: Dictionary = m.call("status_view", day)
	if not bool(v["active"]):
		var why: String = m.call("enlist_refusal", day)
		body = "\"%s\"" % ("Looking for honest work with a spear? Pay by the week, a kit on your back, a bed at the post." if why == "" else why)
		opts.append(["Enlist" if why == "" else "Enlist (refused)", _enlist.bind(m, day, "captain"), why == ""])
	else:
		body = "%s, %d merit. %s\n%s" % [String(v["rank"]), int(v["merit"]), pay_text(v), "\n".join(squad_lines(v))]
		opts.append(["Report for muster", _muster.bind(m, day)])
		var d: Dictionary = v["duty"]
		if not d.is_empty() and String(d["state"]) == "offered":
			opts.append(["Take duty: %s" % String(d["text"]), _take_duty.bind(m, day)])
		if bool(v["ready"]):
			opts.append(["Petition for %s" % String((v["next"] as Dictionary)["title"]), _petition.bind(m, day)])
		opts.append(["Request leave (3 days)", _leave.bind(m, day), not bool(v["on_leave"])])
		if sv != null and sv.has_method("captain_menu") and sv.get("hud") is Object:
			opts.append(["Company business (hire levies)", _company.bind(sv, sv.get("hud") as Object)])
		opts.append(["Resign your commission", _resign.bind(m, day)])
	return {"title": "Captain of the Guard", "body": body, "options": opts}
