extends "res://scripts/ui/affairs/affairs_modal.gd"
## TOWN GATE: the verdict of the town's entry law for your party (scripts/realm/monster_society.gd gate / take_option over
## entry_law.gd). Admitted (maybe with terms), turned back, or barred; when blocked you choose a way in: show a permit, bribe the guard,
## find a sponsor, dress them as servants, argue, undergo a rite, or leave the monster outside. Coin is taken here (the gate module only
## reports it); a failed bribe or disguise can mean arrest, which `resolved` reports to the world.
##   GatePrompt.open(parent, party, town, hour, day, extra = {}, hub_override = null) -> dialog or null (nothing blocks you).
##   party: [{species, kind, speech, civility, power, named, bond_id}]   town: {sid, name, culture, kingdom, corruption}

signal resolved(result: Dictionary)

const Base := preload("res://scripts/ui/affairs/affairs_base.gd")
const TITLE := {"admit": "The gate stands open", "admit_with_terms": "Admitted, on terms", "turn_back": "Turned back at the gate", "bar": "Barred from the town"}
const OPT_LABEL := {
	"permit": "Show a permit", "bribe": "Slip the guard a bribe", "sponsor": "Call on a sponsor", "disguise": "Dress them as servants",
	"talk": "Let it argue its own case", "cleansing": "Undergo the cleansing rite", "leave_outside": "Leave the monster outside",
}
const TERM_WORDS := {"register": "register the beast", "collar_tag": "wear a collar tag", "handler": "keep a handler at its side",
	"seal_inspected": "have the church seal inspected", "monster_quarter_only": "keep to the monster quarter", "pen": "be penned at the gate",
	"muzzle": "be muzzled"}

var party: Array = []
var town: Dictionary = {}
var hour := 12
var day := 0
var extra: Dictionary = {}
var subject := "player"
var verdict: Dictionary = {}
var outcome: Dictionary = {}


static func open(parent: Node, p: Array, t: Dictionary, h: int, d: int, ex := {}, hub_override: RefCounted = null, pause := true) -> Control:
	var g: Control = (load("res://scripts/ui/affairs/gate_prompt.gd") as GDScript).new()
	g.set("realm_override", hub_override)
	g.set("party", p)
	g.set("town", t)
	g.set("hour", h)
	g.set("day", d)
	g.set("extra", ex)
	g.set("pause_game", pause)
	g.set("can_dismiss", false)
	if not bool(g.call("check")):
		g.free()
		return null
	parent.add_child(g)
	return g


## Asks the gate. True when something blocks the party and the prompt is needed.
func check() -> bool:
	var ms: Variant = mod("monster_society")
	if ms == null:
		return false
	verdict = ms.call("gate", subject, party, town, hour, day, extra)
	return String(verdict["verdict"]) in ["turn_back", "bar"] or not (verdict["terms"] as Array).is_empty()


func _compose() -> void:
	if verdict.is_empty():
		check()
	var v := String(verdict.get("verdict", "admit"))
	title_text = "%s: %s" % [String(town.get("name", "The town")), String(TITLE.get(v, v))]
	var lines: Array = verdict.get("lines", [])
	var text := "\n".join(PackedStringArray(lines))
	var terms: Array = verdict.get("terms", [])
	if not terms.is_empty():
		var words: Array = terms.map(func(t: String) -> String: return String(TERM_WORDS.get(t, t)))
		text += "\nThey must " + ", ".join(PackedStringArray(words)) + "."
		if int(verdict.get("fee", 0)) > 0:
			text += " The fee is %d gold." % int(verdict["fee"])
	if v in ["turn_back", "bar"]:
		text += "\nYour standing here: %s." % String(verdict.get("status_band", "unknown")).capitalize()
	body_text = text


func _build_options(box: VBoxContainer) -> void:
	var v := String(verdict.get("verdict", "admit"))
	if v in ["admit", "admit_with_terms"]:
		option(box, "Go in" if v == "admit" else "Accept the terms and go in", accept_terms)
		return
	var ms: Variant = mod("monster_society")
	var held: int = (ms.call("permits_of", subject, day) as Array).size() if ms != null else 0
	for o: Dictionary in verdict.get("options", []):
		var id := String(o["id"])
		var label := String(OPT_LABEL.get(id, id))
		var cost := 0
		match id:
			"bribe":
				cost = int(o.get("price", 0))
				label += " (%d gold)" % cost
			"cleansing":
				cost = int(o.get("gold", 0))
				label += " (%d gold, %d days)" % [cost, int(o.get("days", 0))]
			"permit":
				label += " (%d held)" % held
			"talk":
				label += " (%s)" % Base.fuzzy(float(o.get("chance", 0.0)), ["hopeless", "unlikely", "possible", "likely", "very likely"])
		option(box, label, take.bind(id, cost), cost > int(Game.gold) or (id == "permit" and held == 0))


func accept_terms() -> void:
	outcome = {"ok": true, "result": "admitted", "verdict": verdict.get("verdict", "admit"), "gold": -int(verdict.get("fee", 0))}
	if int(outcome["gold"]) < 0 and int(Game.gold) >= -int(outcome["gold"]):
		Game.add_gold(int(outcome["gold"]))
	resolved.emit(outcome)
	finish("You pass through.")


func take(opt: String, cost: int) -> void:
	var ms: Variant = mod("monster_society")
	if ms == null:
		return
	outcome = ms.call("take_option", subject, party, town, opt, hour, day, extra)
	var gold := int(outcome.get("gold", 0))
	if gold < 0 and int(Game.gold) >= -gold:
		Game.add_gold(gold)
	var lines: Array = outcome.get("lines", [])
	var text := " ".join(PackedStringArray(lines))
	resolved.emit(outcome)
	if bool(outcome.get("arrest", false)):
		finish((text + " " if text != "" else "") + "You are seized by the guard.")
	elif bool(outcome.get("ok", false)):
		finish(text if text != "" else "You pass through.")
	else:
		result_text = text if text != "" else _fail_words(String(outcome.get("result", "")))


func _fail_words(r: String) -> String:
	match r:
		"sponsor_too_low", "sponsor_refused":
			return "No one of standing will vouch for you here."
		"no_permit":
			return "The permit is not enough."
		"talk_failed":
			return "The guard is not listening."
		"not_offered":
			return "No such rite is offered here."
	return "The guard shakes his head."
