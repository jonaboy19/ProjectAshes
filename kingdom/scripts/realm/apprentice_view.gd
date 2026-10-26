extends RefCounted
## Apprenticeships and pupils (realm/society.gd L§40/41) as rows for the Realm > Masters tab.
## The society sim already runs terms (money / respect / service / talent / recommendation), 40 lesson days, missed-lesson
## dismissal and teaching pupils; this file only turns it into player-facing data. Pure, testable headless.

## Society occupation -> the craft (skill id) a master of it teaches. Occupations missing here take no apprentices.
const CRAFT := {"smith": "smithing", "weaver": "tailoring", "baker": "cooking", "hunter": "hunting", "scribe": "scribing",
	"physician": "alchemy", "master craftsman": "carpentry", "guard": "combat", "captain": "combat", "knight": "combat",
	"merchant": "trade", "priest": "faith", "fisher": "fishing", "farmhand": "farming", "peddler": "trade", "guildmaster": "trade"}


static func craft_for(job: String) -> String:
	return String(CRAFT.get(job, ""))


## Masters near the player: [{id, name, job, craft, tier, term}] (tier >= 3, alive, teaches something), best first.
static func masters(society: Object, limit := 12) -> Array:
	var out: Array = []
	if society == null:
		return out
	var sid := int((society.get("player") as Dictionary).get("sid", 0))
	var npcs: Dictionary = society.get("npcs")
	for id: String in society.call("npcs_in", sid):
		var n: Dictionary = npcs.get(id, {})
		var craft := craft_for(String(n.get("job", "")))
		if craft == "" or int(n.get("tier", 0)) < 3 or not bool(n.get("alive", true)):
			continue
		out.append({"id": id, "name": String(n["name"]), "job": String(n["job"]), "craft": craft, "tier": int(n["tier"]),
			"term": String(society.call("master_terms", id))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["tier"]) > int(b["tier"]))
	return out.slice(0, limit)


## The current apprenticeship as {master, craft, days, need, missed, progress} or {}.
static func current(society: Object) -> Dictionary:
	if society == null:
		return {}
	var a: Dictionary = society.get("apprenticeship")
	if a.is_empty():
		return {}
	var npcs: Dictionary = society.get("npcs")
	var n: Dictionary = npcs.get(String(a["master"]), {})
	return {"master": String(n.get("name", "your master")), "craft": String(a["craft"]), "days": int(a["days"]),
		"need": int(a["need"]), "missed": int(a["missed"]), "progress": clampf(float(a["days"]) / maxf(float(a["need"]), 1.0), 0.0, 1.0)}


const TERM_WORDS := {"money": "asks a fee up front", "respect": "wants your respect first", "service": "wants a season of errands",
	"talent": "wants to see talent (skill 10)", "recommendation": "wants someone to vouch for you"}
