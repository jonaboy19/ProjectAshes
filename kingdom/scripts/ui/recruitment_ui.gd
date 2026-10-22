extends RefCounted
## The talk-menu and notice-board halves of recruitment (scripts/realm/recruitment.gd, Living World §2).
##   add_options(...)  puts "Offer work" in the conversation with anyone; the negotiation is a small menu where
##                     you tune wage / duty / housing / length, make the offer, and hear a plain-words answer
##                     (accept, counter-offer, or refusal with the reason).
##   board_menu(...)   a notice board at an inn / market / guild hall: post a vacancy, read who applied, hire.
## Pure menu data (Callables returning strings); VillageServices owns the HUD. State lives in `_st`.

const Rec := preload("res://scripts/realm/recruitment.gd")
const DUTY_ORDER := ["labor", "guard", "escort", "scout", "steward"]
const LENGTHS := [0, 30, 90]

static var _st: Dictionary = {}


static func rc() -> RefCounted:
	var hub: Variant = Life.get("realm") if Life != null else null
	return hub.mod("recruitment") if hub != null else null


static func _env(trust: float, rep: float) -> Dictionary:
	return {"trust": trust, "reputation": rep}


## "Offer work" for a villager (info.person >= 0) who is not yet in your service.
static func add_options(opts: Array, info: Dictionary, hud: Node, back: Callable, trust := 0.0, rep := 30.0) -> void:
	var m := rc()
	var row := int(info.get("person", -1))
	if m == null or row < 0 or not bool(m.call("_alive", row)):
		return
	if bool(m.call("is_recruited", row)):
		add_follower_options(opts, info, hud, back)
		return
	opts.append(["Offer work", _open.bind(info, hud, back, trust, rep)])


static func _open(info: Dictionary, hud: Node, back: Callable, trust: float, rep: float) -> String:
	var m := rc()
	var row := int(info["person"])
	var p: Dictionary = m.call("profile", row)
	_st = {"row": row, "wage": maxi(1, int(p["ask"]) - 1), "duty": "labor", "house": false, "len": 0, "last": "",
		"counter": {}, "trust": trust, "rep": rep}
	hud.call("show_menu", _neg_menu.bind(info, hud, back))
	return ""


static func _terms() -> Dictionary:
	return Rec.make_terms(int(_st["wage"]), String(_st["duty"]), int(_st["len"]), bool(_st["house"]))


static func _neg_menu(info: Dictionary, hud: Node, back: Callable) -> Dictionary:
	var m := rc()
	var t := _terms()
	var duty_label: String = Rec.DUTIES[_st["duty"]]["label"]
	var opts: Array = [
		["Wage: %dg a day  (+1)" % int(_st["wage"]), _bump.bind(1)],
		["Lower the wage  (-1)", _bump.bind(-1), int(_st["wage"]) > 1],
		["Work: %s  (change)" % duty_label, _cycle_duty],
		["Housing: %s  (toggle)" % ("a bed provided" if _st["house"] else "none"), _toggle_house],
		["Term: %s  (change)" % ("open-ended" if int(_st["len"]) == 0 else "%d days" % int(_st["len"])), _cycle_len],
	]
	var counter: Dictionary = _st["counter"]
	if not counter.is_empty():
		opts.append(["Agree to %dg a day" % int(counter["w"]), _agree.bind(info, hud)])
	opts.append(["Make the offer", _offer.bind(info, hud)])
	opts.append(["Never mind", _leave.bind(hud, back)])
	var body := "You propose %dg a day for %s%s%s." % [int(t["w"]), duty_label,
		", with a bed" if t["h"] == 1 else "", "" if int(t["n"]) == 0 else ", %d days" % int(t["n"])]
	if String(_st["last"]) != "":
		body += "\n\n" + String(_st["last"])
	return {"title": "Offer work to %s" % String(info["name"]), "body": body, "options": opts}


static func _bump(d: int) -> String:
	_st["wage"] = maxi(1, int(_st["wage"]) + d)
	_st["counter"] = {}
	return ""


static func _cycle_duty() -> String:
	_st["duty"] = DUTY_ORDER[(DUTY_ORDER.find(_st["duty"]) + 1) % DUTY_ORDER.size()]
	_st["counter"] = {}
	return ""


static func _toggle_house() -> String:
	_st["house"] = not bool(_st["house"])
	_st["counter"] = {}
	return ""


static func _cycle_len() -> String:
	_st["len"] = LENGTHS[(LENGTHS.find(int(_st["len"])) + 1) % LENGTHS.size()]
	_st["counter"] = {}
	return ""


static func _offer(info: Dictionary, hud: Node) -> String:
	var m := rc()
	var env := _env(float(_st["trust"]), float(_st["rep"]))
	var ev: Dictionary = m.call("evaluate", int(_st["row"]), _terms(), env)
	var why: Array = m.call("reason_lines", ev)
	var tail := "\n" + "\n".join(PackedStringArray(why)) if not why.is_empty() else ""
	if ev["verdict"] == "accept":
		var res: Dictionary = m.call("engage", int(_st["row"]), _terms(), "personal", "", env)
		if bool(res["ok"]):
			hud.call("close_menu")
			return "%s %s" % [ev["line"], res["line"]]
	_st["counter"] = ev["counter"] if ev["verdict"] == "counter" else {}
	_st["last"] = "%s%s" % [ev["line"], tail]
	return ""


static func _agree(info: Dictionary, hud: Node) -> String:
	var counter: Dictionary = _st["counter"]
	if counter.is_empty():
		return ""
	_st["wage"] = int(counter["w"])
	_st["counter"] = {}
	return _offer(info, hud)


static func _leave(hud: Node, back: Callable) -> String:
	if back.is_valid():
		return String(back.call())
	hud.call("close_menu")
	return ""


# --- your followers: orders, raise, contract, dismiss ------------------------------

const ORDER_LABEL := {"follow": "following you", "wait": "waiting", "home": "at home", "work": "working"}


## The talk-menu entries for someone who is already in your service (info.person is their row).
static func add_follower_options(opts: Array, info: Dictionary, hud: Node, back: Callable) -> void:
	var m := rc()
	if m == null:
		return
	var fid := String(m.call("fid_of", int(info.get("person", -1))))
	if fid == "" or m.call("get_entry", fid).is_empty():
		return
	opts.append(["Give an order", _show.bind(_orders_menu.bind(fid, info, hud, back), hud)])
	opts.append(["Pay a raise", _show.bind(_raise_menu.bind(fid, info, hud, back), hud)])
	opts.append(["View contract", _show.bind(_contract_menu.bind(fid, info, hud, back), hud)])
	opts.append(["Dismiss", _show.bind(_dismiss_menu.bind(fid, info, hud, back), hud)])


static func _show(menu: Callable, hud: Node) -> String:
	hud.call("show_menu", menu)
	return ""


static func _fol() -> RefCounted:
	var hub: Variant = Life.get("realm") if Life != null else null
	return hub.mod("followers") if hub != null else null


static func _name(fid: String) -> String:
	var f: Dictionary = _fol().get_follower(fid)
	return String(f.get("name", "They"))


## The orders a follower can be given right now: [label, order, arg]. Work lists every group you run.
static func order_choices(fid: String) -> Array:
	var m := rc()
	var out: Array = [["Follow me", "follow", ""], ["Wait here", "wait", ""], ["Go home", "home", ""]]
	if m != null:
		var n := 0
		for g: Dictionary in m.call("groups"):
			out.append(["Work at %s" % String(g["name"]), "work", String(g["id"])])
			n += 1
			if n >= 5:
				break
	return out


static func _orders_menu(fid: String, info: Dictionary, hud: Node, back: Callable) -> Dictionary:
	var m := rc()
	var opts: Array = []
	var cur: Dictionary = m.call("effective_order", fid)
	for ch: Array in order_choices(fid):
		var is_cur: bool = ch[1] == cur["order"] and (ch[1] != "work" or ch[2] == cur["arg"])
		opts.append([("%s  (now)" % ch[0]) if is_cur else ch[0], _order.bind(fid, ch[1], ch[2])])
	opts.append(["Back", _leave.bind(hud, back)])
	var o := String(cur["order"])
	var what := String(ORDER_LABEL.get(o, o))
	if o == "work":
		what = "working at %s" % String((m.call("group", cur["arg"]) as Dictionary).get("name", "their post"))
	return {"title": "Orders for %s" % _name(fid), "body": "%s is %s." % [_name(fid), what], "options": opts}


static func _order(fid: String, order: String, arg: String) -> String:
	var res: Dictionary = rc().call("set_order", fid, order, arg)
	return String(res.get("line", ""))


static func raise_target(fid: String) -> int:
	var m := rc()
	var e: Dictionary = m.call("get_entry", fid)
	var c: Dictionary = m.call("contract_of", fid)
	if e.is_empty() or c.is_empty():
		return 0
	return int(e["dm"]) if int(e["dm"]) > 0 else int(c["t"]["w"]) + 1


static func _raise_menu(fid: String, info: Dictionary, hud: Node, back: Callable) -> Dictionary:
	var m := rc()
	var c: Dictionary = m.call("contract_of", fid)
	var e: Dictionary = m.call("get_entry", fid)
	var asked := int(e.get("dm", 0)) > 0
	var opts: Array = [
		["Raise to %dg a day%s" % [raise_target(fid), "  (what they asked)" if asked else ""], _raise.bind(fid)],
		["Back", _leave.bind(hud, back)],
	]
	var body := "%s is paid %dg a day." % [_name(fid), int(c["t"]["w"])]
	if asked:
		body += " They have asked for %dg." % int(e["dm"])
	return {"title": "Pay a raise", "body": body, "options": opts}


static func _raise(fid: String) -> String:
	return String(rc().call("offer_raise", fid, 1).get("line", ""))


static func contract_text(fid: String) -> String:
	var m := rc()
	var c: Dictionary = m.call("contract_of", fid)
	var e: Dictionary = m.call("get_entry", fid)
	if c.is_empty():
		return "No contract."
	var f: Dictionary = _fol().get_follower(fid)
	var t: Dictionary = c["t"]
	var lines := PackedStringArray()
	lines.append("%s, %s" % [f.get("name", ""), String(f.get("occupation", ""))])
	lines.append("Work: %s. Wage: %dg a day%s." % [Rec.DUTIES[t["d"]]["label"], int(t["w"]), ", a bed provided" if int(t["h"]) == 1 else ""])
	lines.append("Term: %s." % ("open-ended" if int(t["n"]) == 0 else "%d days" % int(t["n"])))
	lines.append("Owed: %dg. Morale %d%%, trust %d." % [int(f.get("owed", 0)), int(round(float(e.get("m", 0.0)) * 100.0)), int(e.get("tr", 0.0))])
	var o: Dictionary = m.call("effective_order", fid)
	lines.append("Now: %s." % String(ORDER_LABEL.get(o["order"], o["order"])))
	var hist: Array = c.get("h", [])
	if not hist.is_empty():
		var bits := PackedStringArray()
		for h: Array in hist:
			bits.append("day %d %s" % [int(h[0]), String(h[1])])
		lines.append("Record: " + ", ".join(bits) + ".")
	return "\n".join(lines)


static func _contract_menu(fid: String, info: Dictionary, hud: Node, back: Callable) -> Dictionary:
	return {"title": "Contract", "body": contract_text(fid), "options": [["Back", _leave.bind(hud, back)]]}


static func _dismiss_menu(fid: String, info: Dictionary, hud: Node, back: Callable) -> Dictionary:
	var f: Dictionary = _fol().get_follower(fid)
	var owed := int(f.get("owed", 0))
	return {"title": "Dismiss %s?" % _name(fid),
		"body": "They will leave your service.%s" % ((" Back pay owed: %dg (settled now if you can)." % owed) if owed > 0 else ""),
		"options": [["Yes, dismiss", _dismiss.bind(fid, hud)], ["No", _leave.bind(hud, back)]]}


static func _dismiss(fid: String, hud: Node) -> String:
	var res: Dictionary = rc().call("dismiss", fid, int(Game.gold))
	hud.call("close_menu")
	return String(res.get("line", ""))


# --- notice board -----------------------------------------------------------------

## Menu for a board at settlement `sid` (kind: inn / market / guild).
static func board_menu(sid: int, kind: String, hud: Node, trust := 0.0, rep := 30.0) -> Dictionary:
	var m := rc()
	var lines := PackedStringArray()
	var opts: Array = []
	if m == null:
		return {"title": "Notices", "body": "", "options": opts}
	for nid: Dictionary in m.call("notices"):
		if int(nid["sid"]) != sid:
			continue
		var apps: Array = m.call("applicants", nid["id"])
		lines.append("Your notice (%s, %dg/day): %d applicant%s" % [Rec.DUTIES[nid["t"]["d"]]["label"], int(nid["t"]["w"]), apps.size(), "" if apps.size() == 1 else "s"])
		for a: Dictionary in apps:
			opts.append(["Hire %s (%s, asks about %dg)" % [a["name"], a["occ"], int(a["ask"])], _hire.bind(nid["id"], int(a["row"]), trust, rep)])
	for duty: String in ["labor", "guard", "escort"]:
		var wage := 4 if duty == "labor" else 6
		opts.append(["Post a vacancy: %s, %dg/day  (%dg for the notice)" % [Rec.DUTIES[duty]["label"], wage, Rec.NOTICE_FEE],
			_post.bind(sid, kind, duty, wage, rep), Game.gold >= Rec.NOTICE_FEE])
	if lines.is_empty():
		lines.append("No vacancy of yours is posted here. Applicants arrive over the following days.")
	return {"title": "Hiring", "body": "\n".join(lines), "options": opts}


static func _post(sid: int, kind: String, duty: String, wage: int, rep: float) -> String:
	var m := rc()
	return String(m.call("post_notice", sid, kind, Rec.make_terms(wage, duty, 0, false), "", 10, "", rep)["line"])


static func _hire(nid: String, row: int, trust: float, rep: float) -> String:
	var m := rc()
	var res: Dictionary = m.call("hire_applicant", nid, row, {}, _env(trust, rep))
	if bool(res["ok"]):
		return String(res["line"])
	var ev: Dictionary = res.get("eval", {})
	return String(ev.get("line", res["line"]))
