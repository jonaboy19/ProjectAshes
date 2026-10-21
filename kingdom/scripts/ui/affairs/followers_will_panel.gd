extends "res://scripts/ui/affairs/affairs_base.gd"
## FOLLOWERS (will): what a follower WANTS (scripts/realm/follower_will.gd). Motives are read as words, never numbers; a hidden agenda
## stays hidden until an investigation finds it. Pending requests have answer buttons; orders carry a hint of how they will be taken
## (a resentful follower who would hide it reads as willing); and the lord's actions: reward, promote, dismiss, forgive, imprison,
## investigate, audit.

const WORDS := {
	"aff": ["cold toward you", "distant", "cordial", "warm", "devoted to you"],
	"res": ["contemptuous", "doubtful of you", "regards you fairly", "respects you", "reveres you"],
	"fear": ["unafraid", "wary", "uneasy", "afraid of you", "terrified of you"],
	"ide": ["a pragmatist", "flexible", "principled", "devout", "uncompromising"],
	"gre": ["content", "modest in wants", "wants more", "covetous", "avaricious"],
	"pro": ["detached", "caring", "protective", "very protective", "would die for their kin"],
}
const LABEL := {"aff": "Affection", "res": "Respect", "fear": "Fear", "ide": "Ideals", "gre": "Greed", "pro": "Protectiveness"}
const AGENDA_WORDS := {"profit": "is lining their pockets", "power": "wants your seat", "enemy_agent": "serves your enemy",
	"revenge": "is nursing a revenge", "": "has no hidden aim"}
const REQUEST_WORDS := {"assignment": "asks for work that suits them better", "leave": "asks leave to go",
	"better_conditions": "asks for better food, rest or pay", "partnership": "asks to be made a partner in your cause",
	"reward": "asks to be rewarded for their service"}
const HINTS := {"comply": "Will likely obey.", "stay_behind": "May ask to stay with their kin.",
	"refuse_moral": "May refuse on conscience.", "consider_leaving": "May start to think of leaving."}
## Order presets: {kind, label, moral, danger, tie}.
const ORDERS := [
	{"kind": "patrol", "label": "Walk the patrol", "moral": 0.0, "danger": 0.15, "tie": 0.0},
	{"kind": "hold_line", "label": "Hold the line against the raiders", "moral": 0.1, "danger": 0.75, "tie": 0.0},
	{"kind": "attack_neighbour", "label": "March on the neighbour's town", "moral": 0.6, "danger": 0.7, "tie": 0.5},
	{"kind": "burn_village", "label": "Burn the rebel village", "moral": 0.95, "danger": 0.4, "tie": 0.3},
]
const REWARDS := [25, 100]
const PD := preload("res://scripts/realm/politics_data.gd")

var selected := ""
var last_order_line := ""


func _fill(b: VBoxContainer) -> void:
	var fo: Variant = mod("followers")
	var w: Variant = mod("will")
	if fo == null or w == null:
		_dim(b, EMPTY)
		return
	var list: Array = fo.call("list")
	if list.is_empty():
		_dim(b, "You have no followers yet. Hire someone to see what they want.")
		return
	if selected == "" or fo.call("get_follower", selected).is_empty():
		selected = String((list[0] as Dictionary)["id"])
	var top := _flow(b)
	for f: Dictionary in list:
		var fid := String(f["id"])
		var mark := " (!)" if String(w.call("pending_request", fid)) != "" else ""
		_chip(top, String(f["name"]) + mark, fid == selected, func() -> void:
			selected = fid
			last_order_line = "")
	_follower_detail(b, selected, fo, w)


func _follower_detail(b: VBoxContainer, fid: String, fo: Variant, w: Variant) -> void:
	var f: Dictionary = fo.call("get_follower", fid)
	var st: Dictionary = w.call("state_of", fid)
	var m: Dictionary = st["m"]
	var head := _card(b)
	_txt(head, String(f.get("name", fid)), AF.TEXT, 21, "title_bold")
	_txt(head, "%s. Role: %s, rank %d. %s." % [String(f.get("occupation", "")).capitalize(), String(w.call("role_of", fid)).capitalize(),
		int(w.call("rank_of", fid)), mood_word(st)], AF.TEXT_DIM)
	if bool(w.call("is_held", fid)):
		_txt(head, "Held in a cell.", Kit.BAD)
	var will: String = w.call("will_of", fid)
	if will != "":
		_txt(head, "Lately: %s." % will.replace("_", " "), AF.GOLD)
	_sec("What drives them")
	var mc := _card(b)
	for k: String in ["aff", "res", "fear", "ide", "gre", "pro"]:
		var row := HBoxContainer.new()
		row.add_child(Kit.lbl(String(LABEL[k]), 16, AF.TEXT_DIM))
		row.add_child(Kit.hspacer())
		row.add_child(Kit.lbl(fuzzy(float(m[k]), WORDS[k]), 16, AF.TEXT))
		mc.add_child(row)
	if bool(st["known"]):
		_txt(mc, "You know that they %s." % String(AGENDA_WORDS.get(String(st["agenda"]), "hide something")), Kit.BAD)
	else:
		_dim(mc, "You have found nothing to hide. That is not proof there is nothing.")
	if float(st["g"]) > 0.35:
		_txt(mc, "They carry a grudge%s." % (" they barely hide" if float(st["g"]) > 0.7 else ""), Kit.BAD)
	_sec("Requests")
	var req: String = w.call("pending_request", fid)
	if req == "":
		_dim(b, "They ask nothing of you now.")
	else:
		var rc := _card(b)
		_txt(rc, "%s %s." % [String(f.get("name", fid)), REQUEST_WORDS.get(req, "has a request")], AF.TEXT, 17)
		var rf := _flow(rc)
		_btn(rf, "Grant", func() -> String: return answer(fid, "grant"), true)
		_btn(rf, "Promise", func() -> String: return answer(fid, "promise"))
		_btn(rf, "Refuse", func() -> String: return answer(fid, "deny"))
	_sec("Give an order")
	for o: Dictionary in ORDERS:
		var oc := _card(b)
		var hint := order_hint(fid, o)
		var orow := HBoxContainer.new()
		oc.add_child(orow)
		orow.add_child(Kit.lbl(String(o["label"]), 16, AF.TEXT, true))
		var ob := Kit.button("Order", false, 40, 14)
		ob.pressed.connect(func() -> void:
			give_order(fid, o)
			_redraw())
		orow.add_child(ob)
		_dim(oc, hint)
	if last_order_line != "":
		_txt(b, last_order_line, AF.GOLD_BRIGHT, 16, "italic")
	_sec("Your hand")
	var act := _flow(b)
	for g: int in REWARDS:
		_btn(act, "Reward %dg" % g, func() -> String: return reward(fid, g), false, int(Game.gold) < g)
	_btn(act, "Promote", func() -> String: return promote(fid))
	_btn(act, "Forgive", func() -> String: return forgive(fid))
	_btn(act, "Investigate", func() -> String: return investigate(fid))
	_btn(act, "Audit books", func() -> String: return audit(fid))
	var grim := _flow(b)
	_danger(grim, "imprison:" + fid, "Imprison", func() -> String: return imprison(fid))
	_danger(grim, "dismiss:" + fid, "Dismiss", func() -> String: return dismiss(fid))


## "Devoted and steady" / "Restless" ...: a mood in words from affection, respect, fear and grudge.
func mood_word(st: Dictionary) -> String:
	var m: Dictionary = st["m"]
	var g := float(st["g"])
	if g > 0.6:
		return "Bitter"
	if g > 0.35:
		return "Resentful"
	var warm := (float(m["aff"]) + float(m["res"])) * 0.5
	if warm > 0.75:
		return "Devoted"
	if warm > 0.5:
		return "Steady"
	if warm > 0.3:
		return "Restless"
	return "Cold"


## How an order will probably be taken, from respond(apply=false). Secret answers (a leak, a plot) read as "hard to read".
func order_hint(fid: String, order: Dictionary) -> String:
	var w: Variant = mod("will")
	if w == null:
		return ""
	var r: Dictionary = w.call("respond", fid, order, {"day": today()}, false)
	return String(HINTS.get(String(r["outward"]), "Hard to read; they give nothing away."))


# ------------------------------------------------------------------ actions

func answer(fid: String, how: String) -> String:
	var w: Variant = mod("will")
	if w == null:
		return ""
	var r: Dictionary = w.call("answer", fid, how)
	return {"grant": "Granted.", "promise": "You promise to see to it.", "deny": "Refused."}.get(how, "") if bool(r.get("ok", false)) else ""


func give_order(fid: String, order: Dictionary) -> String:
	var w: Variant = mod("will")
	if w == null:
		return ""
	var r: Dictionary = w.call("respond", fid, order, {"day": today()}, true)
	var hidden: bool = String(r["action"]) != String(r["outward"])
	var who := follower_name(fid)
	last_order_line = ("%s salutes. \"It will be done.\"" % who) if hidden or String(r["outward"]) == "comply" else String(r["line"])
	return ""


func reward(fid: String, gold: int) -> String:
	var w: Variant = mod("will")
	if w == null or int(Game.gold) < gold:
		return "You cannot afford that."
	var r: Dictionary = w.call("reward", fid, gold)
	Game.add_gold(-int(r["cost"]))
	return "%s takes the %d gold gladly." % [follower_name(fid), int(r["cost"])]


func promote(fid: String) -> String:
	var w: Variant = mod("will")
	return String((w.call("promote", fid) as Dictionary)["line"]) if w != null else ""


func forgive(fid: String) -> String:
	var w: Variant = mod("will")
	return String((w.call("forgive", fid) as Dictionary)["line"]) if w != null else ""


func dismiss(fid: String) -> String:
	var w: Variant = mod("will")
	if w == null:
		return ""
	var r: Dictionary = w.call("dismiss", fid, 0)
	if not bool(r.get("ok", false)):
		return "%s is not on your payroll, so there is nothing to end." % follower_name(fid)
	return String(r.get("line", "")) if String(r.get("line", "")) != "" else "Dismissed."


func imprison(fid: String) -> String:
	var w: Variant = mod("will")
	if w == null:
		return ""
	var sid := here_sid()
	var kingdom := String(PD.kingdom_of(sid))
	return String((w.call("imprison", fid, kingdom, "", sid, 0.0, today()) as Dictionary)["line"])


func investigate(fid: String) -> String:
	var w: Variant = mod("will")
	if w == null:
		return ""
	var r: Dictionary = w.call("investigate", fid, 0.5, today())
	if bool(r["found"]):
		var ag := String(r["agenda"])
		return "You find that %s %s." % [follower_name(fid), AGENDA_WORDS.get(ag, "hides something")]
	return "You find nothing, and %s knows you looked." % follower_name(fid)


func audit(fid: String) -> String:
	var w: Variant = mod("will")
	return String((w.call("audit", fid) as Dictionary)["line"]) if w != null else ""
