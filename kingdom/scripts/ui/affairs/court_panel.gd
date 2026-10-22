extends "res://scripts/ui/affairs/affairs_base.gd"
## COURT: open cases, their evidence (with how far the court will trust it), witnesses, filing a case, appeal, and the four influence
## verbs (persuade / intimidate / blackmail / patronage) on the officer or judge. Public API: courts.cases, case_of, file_case,
## bring_to_court, appeal, close_case, witness_reliability, influence. Chances are shown as words.

const Soc := preload("res://scripts/realm/society.gd")
const Courts := preload("res://scripts/realm/courts.gd")
const STRENGTH := ["thin", "weak", "fair", "strong", "damning"]
const TRUST := ["unreliable", "shaky", "fair", "steady", "trusted"]
const CHANCE := ["a slim chance", "a poor chance", "an even chance", "a good chance", "a very good chance"]
const VERB_LABEL := {"persuade": "Persuade", "intimidate": "Intimidate", "blackmail": "Blackmail", "patronage": "Offer patronage"}
const VERB_HINT := {"persuade": "Reason with them; your name and manner count.", "intimidate": "Threaten; fear may turn on you.",
	"blackmail": "Needs a secret you hold over them.", "patronage": "A gift or a post; they will owe you."}
const PATRON_GOLD := 50
const CASE_SHOWN := 12

var selected := ""
var crime := "robbery"
var accused := ""                    # "" = unknown party, else "f:<follower id>"
var verb := "persuade"
var influence_text := ""


func _fill(b: VBoxContainer) -> void:
	var cs: Variant = mod("courts")
	if cs == null:
		_dim(b, EMPTY)
		return
	_sec("Open cases")
	var open: Array = (cs.call("cases") as Array).filter(func(c: Dictionary) -> bool: return String(c["state"]) != "closed")
	if open.is_empty():
		_dim(b, "No case is before the courts.")
	else:
		var shown: Array = open.slice(maxi(0, open.size() - CASE_SHOWN))
		if selected == "" or not shown.any(func(c: Dictionary) -> bool: return String(c["id"]) == selected):
			selected = String((shown[shown.size() - 1] as Dictionary)["id"])
		var fl := _flow(b)
		for c: Dictionary in shown:
			var cid := String(c["id"])
			_chip(fl, "%s: %s" % [nice(String(c["crime"])), state_word(c)], cid == selected, func() -> void:
				selected = cid
				influence_text = "")
		_case_detail(b, cs, selected)
	_sec("File a case")
	_file_block(b, cs)


func state_word(c: Dictionary) -> String:
	match String(c["state"]):
		"open":
			return "under inquiry"
		"charged":
			return "awaiting trial"
		"tried":
			return "guilty" if String(c["verdict"]) == "guilty" else "cleared"
		"appeal":
			return "on appeal"
		"cold":
			return "gone cold"
	return String(c["state"])


func _case_detail(b: VBoxContainer, cs: Variant, cid: String) -> void:
	var c: Dictionary = cs.call("case_of", cid)
	if c.is_empty():
		return
	var card := _card(b)
	_txt(card, "%s in %s" % [nice(String(c["crime"])), nice(String(c["kingdom"]))], AF.TEXT, 19, "title")
	var acc: Dictionary = c["accused"]
	_txt(card, "Accused: %s.  Complainant: %s.  Officer: %s." % [nice(String(acc.get("name", "unknown"))) if not acc.is_empty() else "not yet known",
		nice(String((c["complainant"] as Dictionary)["name"])), String((c["officer"] as Dictionary)["name"])], AF.TEXT_DIM)
	_txt(card, "The case is %s, before the court of level %d." % [state_word(c), int(c["level"])], AF.TEXT)
	if String(c["verdict"]) != "":
		var sen: Dictionary = c["sentence"]
		_txt(card, "Verdict: %s.%s" % [String(c["verdict"]), "" if sen.is_empty() else " Sentence: %s." % sentence_word(sen)], AF.GOLD)
	_sec("Evidence")
	var ev: Array = c["evidence"]
	if ev.is_empty():
		_dim(b, "Nothing has been found yet.")
	for e: Dictionary in ev:
		var kind := String(Soc.EVIDENCE_KIND.get(String(e["type"]), "other"))
		_txt(b, "%s (%s): %s" % [nice(String(e["type"])), kind, fuzzy(float(e["s"]), STRENGTH)], AF.TEXT)
	var wit: Array = c["witnesses"]
	if not wit.is_empty():
		_sec("Witnesses")
		for w: Dictionary in wit:
			var rel := float(cs.call("witness_reliability", String(w["id"])))
			_txt(b, "%s: %s, %s" % [String(w["name"]), "saw it" if bool(w["saw"]) else "saw nothing", fuzzy(rel, TRUST)], AF.TEXT)
	_sec("Your move")
	var act := _flow(b)
	var state := String(c["state"])
	_btn(act, "Press for trial", func() -> String: return press(cid), true, acc.is_empty() or state in ["charged", "tried", "appeal", "closed"])
	_btn(act, "Appeal the verdict", func() -> String: return appeal(cid), false, not (state == "tried" and String(c["verdict"]) == "guilty"))
	_danger(act, "close:" + cid, "Drop the case", func() -> String: return drop(cid))
	_influence_block(b, c)


func sentence_word(s: Dictionary) -> String:
	var parts: Array = []
	for k: String in s:
		parts.append("%s %s" % [String(k).replace("_", " "), str(s[k])])
	return ", ".join(PackedStringArray(parts))


func _influence_block(b: VBoxContainer, c: Dictionary) -> void:
	_sec("Bend the law")
	var targets: Array = []
	var off: Dictionary = c["officer"]
	if String(off["id"]) != "":
		targets.append({"id": String(off["id"]), "name": "the officer, " + String(off["name"])})
	var jd: Dictionary = c["judge"]
	if not jd.is_empty() and String(jd.get("id", "")) != "":
		targets.append({"id": String(jd["id"]), "name": "the judge, " + String(jd["name"])})
	if targets.is_empty():
		_dim(b, "There is nobody here you could work on.")
		return
	var fl := _flow(b)
	for v: String in Courts.VERBS:
		_chip(fl, String(VERB_LABEL[v]), v == verb, func() -> void: verb = v)
	_dim(b, String(VERB_HINT[verb]))
	var tf := _flow(b)
	for t: Dictionary in targets:
		var tid := String(t["id"])
		_btn(tf, "%s: %s" % [String(VERB_LABEL[verb]), String(t["name"])], func() -> String: return influence(c, tid),
			false, verb == "patronage" and int(Game.gold) < PATRON_GOLD)
	if verb == "patronage":
		_dim(b, "A gift of %d gold." % PATRON_GOLD)
	if influence_text != "":
		_txt(b, influence_text, AF.GOLD_BRIGHT, 16, "italic")


func _file_block(b: VBoxContainer, cs: Variant) -> void:
	var card := _card(b)
	_dim(card, "What was done?")
	var fl := _flow(card)
	var keys: Array = Soc.CRIMES.keys()
	keys.sort()
	for k: String in keys:
		_chip(fl, nice(k), k == crime, func() -> void: crime = k)
	_dim(card, "Against whom?")
	var af := _flow(card)
	_chip(af, "Unknown party", accused == "", func() -> void: accused = "")
	var fo: Variant = mod("followers")
	if fo != null:
		for f: Dictionary in fo.call("list"):
			var fid := "f:" + String(f["id"])
			_chip(af, String(f["name"]), accused == fid, func() -> void: accused = fid)
	_btn(card, "File the case", func() -> String: return file(), true)


# ------------------------------------------------------------------ actions

func file() -> String:
	var cs: Variant = mod("courts")
	if cs == null:
		return ""
	var acc: Dictionary = {}
	if accused != "":
		acc = {"id": accused, "name": follower_name(accused.substr(2))}
	var cid: String = cs.call("file_case", crime, here_sid(), {"id": "player", "name": "You"}, acc, {})
	if cid == "":
		return "The clerk will not take the case."
	selected = cid
	return "Case filed: %s." % nice(crime)


func press(cid: String) -> String:
	var cs: Variant = mod("courts")
	if cs != null and bool(cs.call("bring_to_court", cid)):
		return "The accused will be brought before the bench."
	return "There is no one to charge yet."


func drop(cid: String) -> String:
	var cs: Variant = mod("courts")
	if cs != null and bool(cs.call("close_case", cid)):
		return "The case is dropped."
	return ""


func appeal(cid: String) -> String:
	var cs: Variant = mod("courts")
	if cs == null:
		return ""
	var c: Dictionary = cs.call("case_of", cid)
	var fee := Courts.APPEAL_FEE * (int(c.get("level", 1)) + 1)
	if int(Game.gold) < fee:
		return "An appeal costs %d gold and you do not have it." % fee
	var r: Dictionary = cs.call("appeal", cid, {"id": "player", "name": "You", "fame": int(Game.renown)}, {})
	if not bool(r["ok"]):
		return String(r.get("reason", "The appeal is refused."))
	Game.add_gold(-int(r.get("fee", fee)))
	return "The verdict is overturned on appeal." if bool(r["overturned"]) else "The higher court upholds the verdict."


func influence(c: Dictionary, target: String) -> String:
	var cs: Variant = mod("courts")
	if cs == null:
		return ""
	var gold := PATRON_GOLD if verb == "patronage" else 0
	var r: Dictionary = cs.call("influence", verb, "player", target, {"sid": int(c["sid"]), "ask": 0.4, "gold": gold})
	if not bool(r.get("ok", false)):
		influence_text = String(r.get("reason", "Not a thing you can do."))
		return ""
	if int(r.get("cost", 0)) > 0:
		Game.add_gold(-int(r["cost"]))
	influence_text = "%s (%s). %s" % ["It works" if bool(r["success"]) else "They are not moved", fuzzy(float(r["p"]), CHANCE),
		"They owe you now." if String(r.get("obligation", "")) != "" else ""]
	return ""
