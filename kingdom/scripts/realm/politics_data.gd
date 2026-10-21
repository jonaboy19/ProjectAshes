extends RefCounted
## Shared static data for the Stage 6 politics modules (stewardship, audiences, reputation, territory, diplomacy, courts, succession).
## docs/design/LIVING_WORLD_SANDBOX.md section 7, 8 and 13. Pure data, no state.

const Factions := preload("res://scripts/realm/factions.gd")

## The thirteen kingdoms: the eight of data/world/nations.json plus the five teaser realms (FOUNDATION_PLAN froze these; Stage 6 unfreezes them).
const TEASERS := ["varska_marches", "serathi_lowlands", "solkar_dominion", "frostcrown_holds", "umbrafen_marsh"]
const HOME := "caldrenn"
const AXES := ["competence", "reliability", "generosity", "cruelty", "legitimacy", "wealth", "strength", "influence", "trust"]
const SCOPES := ["i", "h", "t", "f", "r", "a", "k"]   # individual, household, town, faction, religion, army, kingdom
const LEVELS := ["village", "district", "governor", "crown"]

## Offices per authority level. gate: what the clerk/steward/chamberlain wants before you are let in.
## fame, rank (OR sponsors of at least sponsor_rank), plus must_rank for the crown. limits cap what the office may grant.
const OFFICES := {
	0: {"role": "headman", "gatekeeper": "village clerk", "fame": 0.0, "rank": 0, "sponsors": 0, "sponsor_rank": 0, "must_rank": 0,
		"jurisdiction": "the village and its fields", "limits": {"tax": 0.10, "levy": 2, "build": 12, "years": 1}},
	1: {"role": "district magistrate", "gatekeeper": "court clerk", "fame": 6.0, "rank": 1, "sponsors": 1, "sponsor_rank": 1, "must_rank": 0,
		"jurisdiction": "the villages of the district", "limits": {"tax": 0.15, "levy": 6, "build": 40, "years": 3}},
	2: {"role": "governor", "gatekeeper": "steward", "fame": 25.0, "rank": 2, "sponsors": 1, "sponsor_rank": 3, "must_rank": 0,
		"jurisdiction": "the county or estate and all its districts", "limits": {"tax": 0.22, "levy": 20, "build": 160, "years": 10}},
	3: {"role": "crown", "gatekeeper": "chamberlain", "fame": 70.0, "rank": 4, "sponsors": 1, "sponsor_rank": 3, "must_rank": 4,
		"jurisdiction": "the whole kingdom", "limits": {"tax": 0.35, "levy": 200, "build": 1000, "years": 99}},
}

## Petition types: min authority level, document, base wait (days), fee, evidence needed (all of), evidence that helps.
const PETITIONS := {
	"settlement_recognition": {"level": 1, "doc": "charter", "wait": 10, "fee": 40, "need": ["survey", "witness"], "help": ["recommendation"], "words": "recognition of a settlement"},
	"org_recognition": {"level": 1, "doc": "charter", "wait": 4, "fee": 20, "need": ["charter", "witness"], "help": ["recommendation"], "words": "recognition of an organisation"},
	"land": {"level": 2, "doc": "grant", "wait": 8, "fee": 50, "need": ["deed"], "help": ["witness", "survey", "service_record"], "words": "a grant of land"},
	"title": {"level": 2, "doc": "grant", "wait": 16, "fee": 120, "need": ["service_record", "recommendation"], "help": ["witness"], "words": "a title of rank"},
	"mining_rights": {"level": 2, "doc": "licence", "wait": 7, "fee": 60, "need": ["survey"], "help": ["recommendation", "payment"], "words": "mining rights"},
	"trade_rights": {"level": 1, "doc": "licence", "wait": 4, "fee": 25, "need": ["witness"], "help": ["charter", "recommendation"], "words": "trade rights"},
	"military_aid": {"level": 2, "doc": "grant", "wait": 6, "fee": 0, "need": ["witness", "survey"], "help": ["recommendation"], "words": "military aid"},
	"tax_relief": {"level": 1, "doc": "grant", "wait": 4, "fee": 0, "need": ["witness"], "help": ["survey", "recommendation"], "words": "relief from tax"},
	"dispute": {"level": 1, "doc": "grant", "wait": 5, "fee": 15, "need": ["witness"], "help": ["deed", "charter", "recommendation"], "words": "a ruling in a dispute"},
	"amnesty": {"level": 2, "doc": "grant", "wait": 9, "fee": 30, "need": ["recommendation"], "help": ["service_record", "payment"], "words": "an amnesty"},
	"office": {"level": 2, "doc": "commission", "wait": 8, "fee": 40, "need": ["recommendation", "service_record"], "help": ["witness"], "words": "an office"},
}
const EVIDENCE_KINDS := ["deed", "witness", "recommendation", "survey", "charter", "payment", "service_record"]
const DOC_KINDS := ["charter", "licence", "grant", "commission"]

const REJECT_WORDS := {
	"turned_away": "The clerk turns you away: you are not known or sponsored enough for this office.",
	"no_evidence": "You have shown nothing to prove it.",
	"low_standing": "You are not trusted here.",
	"law_forbids": "The law here forbids it.",
	"rival_claim": "Another claim stands before yours.",
	"bribe_refused": "The offer of coin was taken as an insult.",
	"unreliable": "Your word has not been kept before.",
	"score": "The ruling is no; your case was not strong enough.",
	"lapsed": "You did not come to the hearing.",
	"talks_failed": "The talks collapsed over the terms.",
	"wrong_office": "This is not a matter for this office.",
	"outlaw": "You are an outlaw here; no office will hear you.",
}

const GOVERNMENT := {
	"caldrenn": "feudal monarchy", "seirune_isles": "island league", "ongur_khanate": "khanate", "solmarch": "march league",
	"urrokai_clanlands": "clan moot", "shenlu_peaks": "sect court", "veylwood": "wood council", "hollowdeep": "deep thrones",
	"varska_marches": "march lords", "serathi_lowlands": "merchant republic", "solkar_dominion": "empire", "frostcrown_holds": "hold jarls",
	"umbrafen_marsh": "marsh covens",
}
## Local succession rule per kingdom (succession.gd).
const SUCCESSION_RULE := {
	"caldrenn": "primogeniture", "seirune_isles": "elective", "ongur_khanate": "tanistry", "solmarch": "elective",
	"urrokai_clanlands": "tanistry", "shenlu_peaks": "designation", "veylwood": "elective", "hollowdeep": "ultimogeniture",
	"varska_marches": "primogeniture", "serathi_lowlands": "elective", "solkar_dominion": "designation", "frostcrown_holds": "tanistry",
	"umbrafen_marsh": "designation",
}


static func kingdoms() -> Array:
	var out: Array = []
	for n: Dictionary in Factions.nations_data():
		out.append(String(n["id"]))
	for t: String in TEASERS:
		out.append(t)
	return out


static func is_kingdom(id: String) -> bool:
	return id in kingdoms()


static func kingdom_name(id: String) -> String:
	for n: Dictionary in Factions.nations_data():
		if String(n["id"]) == id:
			return String(n.get("short_name", n.get("name", id)))
	return id.replace("_", " ").capitalize()


static func kingdom_of(_sid: int) -> String:
	## Every settlement WorldGen builds lies in the first region (the Kingdom of Valencious).
	return HOME


## A cheap deterministic generator: hash([SEED, tag, day, id]).
static func rng(tag: String, day: int, id: Variant = 0) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, id])
	return r


static func today() -> int:
	return WorldSim.day


static func settlement(sid: int) -> Dictionary:
	for s: Dictionary in WorldGen.settlements:
		if int(s["id"]) == sid:
			return s
	return {}


static func sname(sid: int) -> String:
	return String(settlement(sid).get("name", "settlement %d" % sid))


static func kind_of(sid: int) -> String:
	return String(settlement(sid).get("kind", "village"))


static func is_seat(kind: String) -> bool:
	return kind in ["castle", "capital"]


static func nearest_of(sid: int, kinds: Array, exclude := -1) -> int:
	var here: Vector2 = settlement(sid).get("pos", Vector2.ZERO)
	var best := -1
	var bd := INF
	for s: Dictionary in WorldGen.settlements:
		var id := int(s["id"])
		if id == exclude or not (String(s.get("kind", "village")) in kinds):
			continue
		var d := here.distance_to(s["pos"])
		if d < bd or (d == bd and id < best):
			bd = d
			best = id
	return best


static func capital_sid() -> int:
	var best := -1
	var bp := -1
	for s: Dictionary in WorldGen.settlements:
		var k := String(s.get("kind", "village"))
		var rank := 2 if k == "capital" else (1 if k == "castle" else 0)
		var pop := int(s.get("population", 0))
		var score := rank * 100000 + pop
		if score > bp:
			bp = score
			best = int(s["id"])
	return best


static func key_ok(d: Dictionary, keys: Array) -> bool:
	for k: String in keys:
		if not d.has(k):
			return false
	return true


static func fix_ints(d: Dictionary, keys: Array) -> void:
	for k: String in keys:
		if d.has(k):
			d[k] = int(d[k])


static func rows_to_ints(rows: Array, keys: Array) -> Array:
	for r: Dictionary in rows:
		fix_ints(r, keys)
	return rows
