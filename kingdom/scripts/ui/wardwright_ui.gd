extends RefCounted
## The Runeward Legion's recruiter (Region 1, the Wardwright career, data/careers/wardwright.json): the talk-menu half of the
## Silverford (Ironmarch) Runecarvers' Guild. Same pattern as the Soldier captain (scripts/ui/soldier_ui.gd): the person's menu offers
## enlistment through the career module (realm module "trades"), refuses with a reason, and shows the terms once you are on the roll.
## The roster entry is generated (tools/towns/gen_town.py RECRUITERS); the career screen still joins the career too.
##   WardwrightUI.add_options(opts, info)      called from VillageServices._talk_page for every talk menu

const ROLE := "wardwright recruiter"
const CAREER := "wardwright"
const MIN_AGE := 12            ## the Blessing: nobody carves a stone before it

static var day_override := -1
static var age_override := -1
static var trades_override: RefCounted = null


static func _age() -> int:
	return age_override if age_override >= 0 else (Life.age() if Life != null else 0)


static func _day() -> int:
	return day_override if day_override >= 0 else int(WorldSim.day)


static func trades() -> RefCounted:
	if trades_override != null:
		return trades_override
	var hub: Variant = Life.get("realm") if Life != null else null
	return hub.mod("trades") if hub != null else null


static func is_recruiter(info: Dictionary) -> bool:
	return String(info.get("role", "")) == ROLE


## Why this person cannot be enlisted now, or "".
static func enlist_refusal(m: RefCounted, age: int) -> String:
	if m == null:
		return "The roll is closed."
	if bool(m.call("is_member", CAREER)):
		return "You are already on the roll."
	if age < MIN_AGE:
		return "\"The Legion takes no one before their Blessing. Come back at %d, with a steady hand.\"" % MIN_AGE
	return ""


## One line of terms from data/careers/wardwright.json (the stipend of the first rank, the fee for a glyph).
static func terms_text() -> String:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/careers/wardwright.json")) if FileAccess.file_exists("res://data/careers/wardwright.json") else null
	if not (d is Dictionary):
		return "A stipend by rank and a fee for every stone mended or glyph carved."
	var week: Array = (d as Dictionary).get("stipend_week", [])
	var carve: Dictionary = (d as Dictionary).get("carve", {})
	return "%dg a week at the first rank, rising to %dg, and %dg for each glyph you carve (the first %d a day)." % [
		int(week[0]) if not week.is_empty() else 0, int(week[week.size() - 1]) if not week.is_empty() else 0, int(carve.get("base", 0)), int(carve.get("max_paid_carves", 0))]


static func add_options(opts: Array, info: Dictionary) -> void:
	if not is_recruiter(info):
		return
	var m := trades()
	var why := enlist_refusal(m, _age())
	if m != null and bool(m.call("is_member", CAREER)):
		opts.append(["Ask about the terms", _terms.bind(m)])
		return
	opts.append(["Join the Runeward Legion" if why == "" else "Join the Runeward Legion (refused)", _enlist.bind(m), why == ""])
	opts.append(["Ask about the terms", _terms.bind(m)])


static func _enlist(m: RefCounted) -> String:
	var why := enlist_refusal(m, _age())
	if why != "":
		return why
	var r: Dictionary = m.call("join", CAREER, _day())
	if not bool(r.get("ok", false)):
		return String(r.get("reason", ""))
	return "\"Your name is on the roll, %s. Walk the road, mend what is dim, carve what has gone dark. %s\"" % [String(m.call("rank_title", CAREER)), terms_text()]


static func _terms(m: RefCounted) -> String:
	var t := terms_text()
	if m != null and bool(m.call("is_member", CAREER)):
		return "\"You are %s on the roll. %s\"" % [String(m.call("rank_title", CAREER)), t]
	return "\"%s\"" % t
