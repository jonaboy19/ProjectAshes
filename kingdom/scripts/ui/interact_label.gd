extends RefCounted
## Turns whatever the player can use into a "Verb — Target" label for the HUD's primary action
## button ("Talk — Roland Ward", "Enter — Golden Stag Inn", "Inspect — Notice Board", "Work — Blacksmith").
##
## An Interactable component (scripts/interaction/interactable.gd) supplies verb and target directly; the rest
## below is the legacy convention for group members that only have prompt()/use().
## CONVENTION: an interactable may define `interact_label()` returning either a Dictionary
## {verb, target} or a String ("Talk — Roland Ward"), or carry the same as meta "interact_label".
## Without it the label is derived, in order, from: a Station's `verb` + `title` (NPCs, work spots, boards);
## a door's building name (meta "building_name", else its prompt text); the node's prompt() text
## ("Enter the smithy" -> Enter — Smithy); finally a node `title` / `display_name` / meta "display_name".
## Always returns {verb, target, text, icon, danger}; never an empty verb.

const SEP := " — "
const ARTICLES := ["the ", "a ", "an "]
const ALIASES := {"Read": "Inspect", "Use": "Use", "Name": "Name"}
const ICONS := {"talk": "conversation", "inspect": "magnifying-glass", "read": "magnifying-glass", "enter": "walk",
	"leave": "walk", "exit": "walk", "ride": "walk", "dismount": "walk"}
const GENERIC_NAMES := ["TalkTarget", "Villager", ""]
## Verbs that are crimes: the HUD pill draws them in red (package F5).
const DANGER_VERBS := ["Steal", "Pickpocket", "Rob"]


static func resolve(n: Object) -> Dictionary:
	if n == null or not is_instance_valid(n):
		return _pack("Use", "")
	# An attached Interactable component is the source of truth: verb and target come from it.
	var comp: Interactable = Interactable.component_of(n) if n is Node else null
	if comp != null:
		return comp.label()
	return legacy(n)


## The pre-Interactable derivation (interact_label(), meta, Station verb + title, door building name, prompt()).
## Interactable.label() ends here for wrapped legacy nodes and for components whose label_fn is unset on a door.
static func legacy(n: Object) -> Dictionary:
	if n == null or not is_instance_valid(n):
		return _pack("Use", "")
	var raw: Variant = null
	if n.has_method("interact_label"):
		raw = n.call("interact_label")
	elif n is Node and (n as Node).has_meta("interact_label"):
		raw = (n as Node).get_meta("interact_label")
	if raw is Dictionary and String((raw as Dictionary).get("verb", "")) != "":
		return _pack(String(raw["verb"]), String(raw.get("target", "")))
	if raw is String and raw != "":
		return from_text(raw)
	var prompt := ""
	if n.has_method("prompt"):
		prompt = String(n.call("prompt"))
	# Doors: the building's name.
	if n.get("prompt_text") != null and n.get("is_exit") != null:
		var d := from_prompt(prompt)
		var bname := ""
		if n is Node and (n as Node).has_meta("building_name"):
			bname = String((n as Node).get_meta("building_name"))
		return _pack(String(d["verb"]), bname if bname != "" else String(d["target"]))
	# Stations (NPC talk targets, work spots, boards, counters): verb + title.
	var title: Variant = n.get("title")
	if title is String and title != "" and not GENERIC_NAMES.has(title):
		var verb: Variant = n.get("verb")
		var v: String = String(verb) if verb is String and verb != "" else String(from_prompt(prompt)["verb"])
		return _pack(v, String(title))
	var d2 := from_prompt(prompt)
	if String(d2["target"]) == "":
		for key in ["display_name", "npc_name", "label_text"]:
			var v2: Variant = n.get(key)
			if v2 is String and v2 != "":
				d2["target"] = v2
				break
		if String(d2["target"]) == "" and n is Node and (n as Node).has_meta("display_name"):
			d2["target"] = String((n as Node).get_meta("display_name"))
	return _pack(String(d2["verb"]), String(d2["target"]))


## "Talk — Roland Ward" / "Talk - Roland" / "Enter the inn" -> {verb, target}.
static func from_text(t: String) -> Dictionary:
	for sep in [SEP, " - ", ": "]:
		var i := t.find(sep)
		if i > 0:
			return _pack(t.left(i), t.substr(i + sep.length()))
	return from_prompt(t)


## A bare prompt ("Enter the smithy", "Work the fields (hold)", "Talk") split into verb and target.
static func from_prompt(p: String) -> Dictionary:
	var t := p.strip_edges()
	if t == "":
		return {"verb": "Use", "target": ""}
	var sp := t.find(" ")
	if sp < 0:
		return {"verb": t, "target": ""}
	var rest := t.substr(sp + 1).strip_edges()
	for a: String in ARTICLES:
		if rest.to_lower().begins_with(a):
			rest = rest.substr(a.length())
			break
	return {"verb": t.left(sp), "target": rest}


## {verb, target, text, icon} from a verb and a target (what Interactable.label() ends in).
static func pack(verb: String, target: String) -> Dictionary:
	return _pack(verb, target)


static func _pack(verb: String, target: String) -> Dictionary:
	verb = verb.strip_edges()
	target = _title_case(target.strip_edges())
	verb = String(ALIASES.get(verb, verb))
	if verb == "":
		verb = "Use"
	verb = verb.left(1).to_upper() + verb.substr(1)
	var key := verb.to_lower().split(" ")[0]
	return {"verb": verb, "target": target, "text": verb + (SEP + target if target != "" else ""),
		"icon": String(ICONS.get(key, "hand")), "danger": DANGER_VERBS.has(verb)}


## Capitalises words that start lower-case ("fields (hold)" -> "Fields (hold)"); keeps given names as they are.
static func _title_case(s: String) -> String:
	if s == "":
		return s
	var out := PackedStringArray()
	for w in s.split(" "):
		if w.length() > 3 and w[0] == w[0].to_lower() and w[0] != "(" and w[0] != "-":
			w = w.left(1).to_upper() + w.substr(1)
		elif w.length() > 0 and w.length() <= 3 and w[0] == w[0].to_lower() and out.is_empty():
			w = w.left(1).to_upper() + w.substr(1)
		out.append(w)
	return " ".join(out)
