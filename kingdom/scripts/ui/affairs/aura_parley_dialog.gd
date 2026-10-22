extends "res://scripts/ui/affairs/affairs_modal.gd"
## AURA ESCALATION: an officer has come to parley after a release or a deed (scripts/realm/aura_fallout.gd ladder / resolve).
## Seven answers: suppress, talk, intimidate, bribe, surrender, flee, fight. Deterministic outcomes come from the module; gold moves
## through the module's pending-gold queue (Life drains it), never from here. The dialog cannot be waved away: you must answer.
##   AuraParleyDialog.open(parent_node, subject = "player", sid = -1, hub_override = null, ctx = {}) -> dialog or null (no ladder).
## `chosen(option, result)` is emitted so the world can act on flee / fight.

signal chosen(option: String, result: Dictionary)

const Base := preload("res://scripts/ui/affairs/affairs_base.gd")
const OPTIONS := {
	"suppress": ["Rein it in", "Pull the aura back and stand down."],
	"talk": ["Talk", "Explain yourself. Rank and manner count."],
	"intimidate": ["Intimidate", "Let him feel your weight. Only a strong presence works."],
	"bribe": ["Bribe", "A purse for a blind eye. An honest officer will record it."],
	"surrender": ["Surrender", "Go to the magistrate. A hearing, and a fine."],
	"flee": ["Flee", "Run for it. The faster you are, the better the chance."],
	"fight": ["Fight (not to kill)", "Put him down without killing. It will be remembered."],
}
const STEP_WORDS := ["a watch patrol", "a patrol", "an officer", "a captain and mages", "knights and inquisitors", "the royal response"]
const OUTCOME := {
	"calmed": "The officer relaxes a little. \"Keep it that way.\"",
	"unmoved": "The officer is not impressed; he has seen it.",
	"dismissed": "\"Move along, then.\" The matter is dropped.",
	"fined": "He lets you go with a fine.",
	"escorted_out_or_worse": "He does not buy it. The patrol closes in.",
	"officer_backs_off": "The officer takes a step back and says nothing more.",
	"defied": "He will not be cowed. More men are sent for.",
	"refused_and_recorded": "\"Are you offering me a bribe?\" He writes your name down.",
	"too_poor": "You do not have enough to make it worth his while.",
	"taken": "The purse disappears. The officer finds he saw nothing.",
	"hearing": "You are taken to the magistrate for a hearing.",
	"detained": "You are taken in. There is no hearing to be had.",
	"escaped": "You are gone before they can close the street.",
	"caught": "They catch you. It is worse now.",
	"restrained_nonlethal": "You put them down. The whole town saw it.",
	"major_crime": "Blood in the street. There is no going back from this.",
	"patron_intervenes": "A patron's name carries weight; the officer withdraws.",
	"no_patron": "No one speaks for you.",
	"refused": "He will not parley at this stage.",
}

var subject := "player"
var sid := -1
var ctx: Dictionary = {}
var last: Dictionary = {}
var _n := 0


static func open(parent: Node, subj := "player", at_sid := -1, hub_override: RefCounted = null, context := {}, pause := true) -> Control:
	var d: Control = (load("res://scripts/ui/affairs/aura_parley_dialog.gd") as GDScript).new()
	d.set("realm_override", hub_override)
	d.set("subject", subj)
	d.set("sid", at_sid)
	d.set("ctx", context)
	d.set("pause_game", pause)
	d.set("can_dismiss", false)
	var af: Variant = d.call("mod", "aura_fallout")
	if af == null or int((af.call("ladder", subj, at_sid) as Dictionary)["step"]) < 0:
		d.free()
		return null
	parent.add_child(d)
	return d


func _compose() -> void:
	var af: Variant = mod("aura_fallout")
	var lad: Dictionary = af.call("ladder", subject, sid) if af != null else {"step": -1}
	var step := int(lad["step"])
	if af == null or step < 0:
		title_text = "The street is quiet"
		body_text = "No one is coming for you."
		done = true
		return
	title_text = "%s has come for you" % String(STEP_WORDS[clampi(step, 0, 5)]).capitalize()
	var dread: float = af.call("dread_felt", subject, sid)
	var mood := Base.fuzzy(dread / 100.0, ["a nervous street", "a frightened street", "a street in fear", "a street in terror", "a street emptied by fear"])
	body_text = "%s. %s." % [mood.capitalize(), "The officer is here and waits for your answer" if bool(lad["arrived"]) else "They are still on their way, but there is no hiding"]


func _build_options(box: VBoxContainer) -> void:
	for o: String in OPTIONS:
		var info: Array = OPTIONS[o]
		option(box, "%s  -  %s" % [String(info[0]), String(info[1])], pick.bind(o))


func pick(opt: String) -> void:
	var af: Variant = mod("aura_fallout")
	if af == null:
		return
	var c := {"persuasion": 0.3, "rank": int(Game.rank), "power": 0.3, "gold": int(Game.gold), "honest": 0.5, "n": _n}
	c.merge(ctx, true)
	_n += 1
	last = af.call("resolve", subject, sid, opt, c)
	if not bool(last.get("ok", false)):
		result_text = "Nothing comes of it."
		return
	chosen.emit(opt, last)
	var text := String(OUTCOME.get(String(last["outcome"]), "It is done."))
	if int(last.get("gold", 0)) < 0:
		text += " (%d gold)" % -int(last["gold"])
	var after := int(last["after"])
	var ended := after <= 0 or String(last["outcome"]) in ["hearing", "dismissed", "detained", "escaped", "major_crime", "restrained_nonlethal"]
	if ended:
		finish(text)
	else:
		result_text = text
