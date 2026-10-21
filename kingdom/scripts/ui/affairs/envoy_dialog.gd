extends "res://scripts/ui/affairs/affairs_modal.gd"
## AUDIENCE: an envoy waits at your door (scripts/realm/war_intel.gd envoys / respond). Nine answers, each with a plain-words hint;
## what lies under the envoy's words (trade, kin, fear, secret aid) is not shown, so a smiling envoy can still be lying.
##   EnvoyDialog.open(parent_node, hub_override = null) -> the dialog (or null when nobody waits).

const LABELS := {
	"accept": ["Accept", "Grant what is asked."],
	"refuse": ["Refuse", "Send the envoy away with a no."],
	"negotiate": ["Negotiate", "Haggle for better terms."],
	"delay": ["Ask for time", "Keep them waiting; patience wears thin."],
	"ask_intel": ["Ask what he knows", "Trade the answer for word of the other side."],
	"mediate": ["Offer to mediate", "Stand between the two parties."],
	"demand_compensation": ["Demand compensation", "Name a price for your trouble."],
	"secretly_aid": ["Aid them in secret", "Say nothing, help quietly. If found out, it is a breach."],
	"delegate_council": ["Leave it to the council", "Your council decides; they may do better or worse."],
}
const ASK_WORDS := {"neutrality": "that you stay out of their quarrel", "passage": "leave to march across your land",
	"aid": "your help in their war", "alliance": "a pact of alliance", "tribute": "tribute"}
const AGENDA_WORDS := {"sincere": "sincere", "arrogant": "overbearing", "desperate": "desperate", "deceptive": "double-tongued", "rogue": "acting without his master's leave"}

var eid := -1
var last: Dictionary = {}


static func open(parent: Node, hub_override: RefCounted = null, pause := true) -> Control:
	var d: Control = (load("res://scripts/ui/affairs/envoy_dialog.gd") as GDScript).new()
	d.set("realm_override", hub_override)
	d.set("pause_game", pause)
	d.call("_pick")
	if int(d.get("eid")) < 0:
		d.free()
		return null
	parent.add_child(d)
	return d


func _ready() -> void:
	_pick()
	super._ready()


func _pick() -> void:
	var wi: Variant = mod("war_intel")
	var list: Array = wi.call("envoys", "waiting") if wi != null else []
	eid = int((list[0] as Dictionary)["id"]) if not list.is_empty() else -1


func _compose() -> void:
	var wi: Variant = mod("war_intel")
	if wi == null or eid < 0:
		title_text = "Audience"
		body_text = "No one waits to see you."
		done = true
		return
	var e: Dictionary = wi.call("envoy", eid)
	title_text = "An envoy of %s" % nice(String(e["from"]))
	var against := String(e["against"])
	var line := "He asks %s%s." % [String(ASK_WORDS.get(String(e["ask"]), String(e["ask"]))), (", against " + nice(against)) if against != "" else ""]
	var ag := String(e["agenda"])
	if bool(e["informed"]) and ag != "unknown":
		line += " Your advisors say he is %s." % String(AGENDA_WORDS.get(ag, ag))
	else:
		line += " You cannot tell what lies behind his words."
	var wait := int(e["until"]) - int(WorldSim.day)
	line += " He will wait %s." % ("only today" if wait <= 0 else "%d more days" % wait)
	body_text = line


func _build_options(box: VBoxContainer) -> void:
	for r: String in LABELS:
		var info: Array = LABELS[r]
		option(box, String(info[0]) + "  -  " + String(info[1]), answer.bind(r))


static func nice(id: String) -> String:
	var s := id
	for pre: String in ["k:", "f:", "fo:", "i:"]:
		if s.begins_with(pre):
			s = s.substr(pre.length())
	return s.replace("_", " ").capitalize()


func answer(response: String) -> void:
	var wi: Variant = mod("war_intel")
	if wi == null or eid < 0:
		return
	last = wi.call("respond", eid, response, {})
	if not bool(last.get("ok", false)):
		result_text = "The envoy does not understand."
		return
	var text := String(last.get("text", ""))
	finish(text if text != "" else "The envoy bows and takes your answer.")
