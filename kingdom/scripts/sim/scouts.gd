class_name RAScouts
extends RefCounted
## Talent scouts: recruiters from the army, a royal academy, a martial sect or
## a merchant house. Being scouted must feel rare and earned. On an ordinary
## day the chance is tiny (BASE_DAILY, capped under 1% even for a titled,
## famous youth in the right age window). Real scenarios (a tournament bout, a
## wolf pack broken in view of a patrol, reaching D rank at the guild, saving a
## caravan) roll their own, larger but still uncommon chance, and only
## organisations that would plausibly be there can appear.
##
## Scouts can recruit anyone: pass the player's profile or NPC profiles.
## Every event is a dictionary {id, day, candidate, scout, org, scenario, offer}.
##
## Soulbeasts: extremely rare. An offer may carry `soulbeast_path = true` and
## `travel_permit = "Xiava's Lake"` ONLY from an academy or sect with Xiava
## access, and only on a small extra roll. That flag is all this sim models; the
## lake is a later region.
##
## Candidate profile: {id: int, name: String, age: int, titles: Array, feats: Array,
##                     reputation: float 0..100, guild_rank: int (optional)}
##
## INTEGRATION (for Life; not wired yet):
## - Life owns `var scouts := RAScouts.new()` and builds the player profile from
##   Game (age from WorldSim birth day, titles/feats from the title system, merit
##   or fame as reputation).
## - At hour 5: `var e := scouts.daily_roll(profile, WorldSim.day)`; if not empty,
##   stage it (a stranger waits at the inn / gate) and show the offer dialogue.
##   NPCs: `scouts.roll_population(npc_profiles, day)` occasionally takes talent
##   away from the village (careers.remove_person on acceptance).
## - Scenario hooks: tournament win -> `on_scenario(profile, "tournament", day)`;
##   Life.on_wolf_killed when a pack is wiped within a patrol's sight ->
##   "wolf_pack_patrol"; guild rank_changed to D (2) -> "guild_rank_d";
##   escort commission complete -> "caravan_saved".
## - `scouts.accept(event_id, day)` / `decline(event_id)`; on accept Life resigns
##   the careers seat and moves the player into the org (future military/academy sims).
##   `scouts.tick_day(day)` expires unanswered offers.
## - Save: snapshot["scouts"] = scouts.serialize().

## Daily ambient chance before boosts.
const BASE_DAILY := 0.0015
## Ambient daily chance never exceeds this, whatever the boosts.
const MAX_DAILY := 0.009
## Scenario chances are multiplied by the boost but capped here.
const MAX_SCENARIO := 0.35
const AGE_WINDOW := Vector2i(12, 24)
const AGE_WINDOW_BOOST := 1.6
const TITLE_BOOST := 0.3
const FEAT_BOOST := 0.2
const MAX_COUNTED := 5
## Days after any scouting (accepted or not) before the next can happen.
const COOLDOWN_DAYS := 180
const OFFER_DAYS := 7
## Share of academy/sect offers (with Xiava access) that open the soulbeast path.
const SOULBEAST_CHANCE := 0.04

const ORGS := {
	"army": {"kind": "military", "name": "the Royal Army", "scout": "Recruiting Officer", "xiava_access": false,
		"offer": {"role": "Recruit, Third Squad", "wage": 12, "signing_bonus": 20}},
	"academy": {"kind": "academy", "name": "Emberhold Royal Academy", "scout": "Academy Examiner", "xiava_access": true,
		"offer": {"role": "Scholarship Student", "wage": 4, "signing_bonus": 0, "tuition_waived": true}},
	"sect": {"kind": "sect", "name": "the Azure Peak Sect", "scout": "Wandering Elder", "xiava_access": true,
		"offer": {"role": "Outer Disciple", "wage": 3, "signing_bonus": 0, "lodging": true}},
	"merchant": {"kind": "merchant", "name": "House Calder Trading Company", "scout": "Factor", "xiava_access": false,
		"offer": {"role": "Caravan Guard-Apprentice", "wage": 14, "signing_bonus": 15}},
}

## Ambient scenarios can happen any eligible day; the rest are triggered by events.
const SCENARIOS := {
	"training_yard": {"ambient": true, "orgs": ["army", "sect"], "chance": 0.0,
		"text": "A stranger watched you train at dawn and did not leave until you finished."},
	"market_haggle": {"ambient": true, "orgs": ["merchant"], "chance": 0.0,
		"text": "A travelling factor saw how you handled the market and asked your name."},
	"elder_word": {"ambient": true, "orgs": ["academy"], "chance": 0.0,
		"text": "The village elder spoke your name to a visiting examiner."},
	"tournament": {"ambient": false, "orgs": ["army", "academy", "sect"], "chance": 0.12,
		"text": "Someone in the crowd at the tournament asked to speak with you after your bout."},
	"wolf_pack_patrol": {"ambient": false, "orgs": ["army"], "chance": 0.06,
		"text": "A patrol saw you break the wolf pack. Their officer wants a word."},
	"guild_rank_d": {"ambient": false, "orgs": ["merchant", "army", "academy"], "chance": 0.08,
		"text": "Your D-rank plate drew attention at the guild hall."},
	"caravan_saved": {"ambient": false, "orgs": ["merchant"], "chance": 0.07,
		"text": "The caravan master has written to his house about you."},
}

const SCOUT_NAMES := ["Aldric Venn", "Mei Lan", "Oswin Harrow", "Sera Quill", "Tobias Rook", "Lin Yue",
	"Hadrin Cole", "Yara Sol", "Kest Marrow", "Rui Feng"]

## Open offers: [event]
var offers: Array[Dictionary] = []
## candidate id -> last day they were scouted.
var last_scouted: Dictionary = {}
## candidate id -> org id they joined through a scout.
var recruited: Dictionary = {}
## candidate id -> true while they hold an open offer (index over `offers`).
var _pending: Dictionary = {}
var _next_id := 1
var _rng := RandomNumberGenerator.new()


func _init(seed_value := 5051) -> void:
	_rng.seed = seed_value


## Multiplier from age, titles, feats and reputation (1.0 = unremarkable adult).
static func boost(c: Dictionary) -> float:
	var f := 1.0
	var age := int(c.get("age", 18))
	if age >= AGE_WINDOW.x and age <= AGE_WINDOW.y:
		f *= AGE_WINDOW_BOOST
	elif age < 10:
		f *= 0.2
	elif age > 35:
		f *= 0.4
	f *= 1.0 + TITLE_BOOST * mini((c.get("titles", []) as Array).size(), MAX_COUNTED)
	f *= 1.0 + FEAT_BOOST * mini((c.get("feats", []) as Array).size(), MAX_COUNTED)
	f *= 1.0 + clampf(float(c.get("reputation", 0.0)), 0.0, 100.0) / 50.0
	return f


## Ambient daily chance for a candidate (0 while on cooldown or already recruited).
func daily_chance(c: Dictionary, day: int) -> float:
	if not eligible(c, day):
		return 0.0
	return minf(BASE_DAILY * boost(c), MAX_DAILY)


func scenario_chance(c: Dictionary, scenario: String, day: int) -> float:
	if not eligible(c, day) or not SCENARIOS.has(scenario):
		return 0.0
	return minf(float(SCENARIOS[scenario]["chance"]) * boost(c), MAX_SCENARIO)


func eligible(c: Dictionary, day: int) -> bool:
	var id := int(c.get("id", 0))
	if recruited.has(id) or _pending.has(id):
		return false
	if last_scouted.has(id) and day - int(last_scouted[id]) < COOLDOWN_DAYS:
		return false
	return int(c.get("age", 18)) >= 8


## One ordinary day. Returns an event or {}.
func daily_roll(c: Dictionary, day: int) -> Dictionary:
	if _rng.randf() >= daily_chance(c, day):
		return {}
	var ambient := []
	for sid: String in SCENARIOS:
		if SCENARIOS[sid]["ambient"]:
			ambient.append(sid)
	var pick: String = ambient[_rng.randi() % ambient.size()]
	return _make_event(c, pick, day)


## Something notable happened in front of witnesses. Returns an event or {}.
func on_scenario(c: Dictionary, scenario: String, day: int) -> Dictionary:
	if _rng.randf() >= scenario_chance(c, scenario, day):
		return {}
	return _make_event(c, scenario, day)


## Ambient rolls for many NPCs. Returns the events.
func roll_population(candidates: Array, day: int) -> Array:
	var out := []
	for c: Dictionary in candidates:
		var e := daily_roll(c, day)
		if not e.is_empty():
			out.append(e)
	return out


func _make_event(c: Dictionary, scenario: String, day: int) -> Dictionary:
	var sc: Dictionary = SCENARIOS[scenario]
	var org_ids: Array = sc["orgs"]
	var org_id: String = org_ids[_rng.randi() % org_ids.size()]
	var org: Dictionary = ORGS[org_id]
	var terms: Dictionary = (org["offer"] as Dictionary).duplicate()
	terms["expires_day"] = day + OFFER_DAYS
	terms["soulbeast_path"] = false
	terms["travel_permit"] = ""
	# Roll always happens (keeps the RNG sequence stable); only counts for Xiava orgs.
	var sb_roll := _rng.randf()
	if org["xiava_access"] and sb_roll < SOULBEAST_CHANCE:
		terms["soulbeast_path"] = true
		terms["travel_permit"] = "Xiava's Lake"
	var id := int(c.get("id", 0))
	var e := {"id": _next_id, "day": day, "candidate": id, "candidate_name": String(c.get("name", "")),
		"scout": {"name": SCOUT_NAMES[_rng.randi() % SCOUT_NAMES.size()], "title": org["scout"]},
		"org": {"id": org_id, "name": org["name"], "kind": org["kind"]},
		"scenario": {"id": scenario, "text": sc["text"]},
		"offer": terms}
	_next_id += 1
	last_scouted[id] = day
	offers.append(e)
	_pending[id] = true
	return e


func offer(event_id: int) -> Dictionary:
	for o in offers:
		if int(o["id"]) == event_id:
			return o
	return {}


## Accept an open offer. Returns the event (now closed) or {} if gone/expired.
func accept(event_id: int, day: int) -> Dictionary:
	var e := offer(event_id)
	if e.is_empty() or day > int(e["offer"]["expires_day"]):
		return {}
	offers.erase(e)
	_pending.erase(int(e["candidate"]))
	recruited[int(e["candidate"])] = String(e["org"]["id"])
	return e


func decline(event_id: int) -> void:
	var e := offer(event_id)
	if not e.is_empty():
		offers.erase(e)
		_pending.erase(int(e["candidate"]))


## Unanswered offers lapse. Returns the expired events.
func tick_day(day: int) -> Array:
	var gone := []
	var keep: Array[Dictionary] = []
	for o in offers:
		if day > int(o["offer"]["expires_day"]):
			gone.append(o)
			_pending.erase(int(o["candidate"]))
		else:
			keep.append(o)
	offers = keep
	return gone


func serialize() -> Dictionary:
	var os := []
	for o in offers:
		os.append(o.duplicate(true))
	var ls := {}
	for k: int in last_scouted:
		ls[str(k)] = last_scouted[k]
	var rs := {}
	for k: int in recruited:
		rs[str(k)] = recruited[k]
	return {"offers": os, "last_scouted": ls, "recruited": rs, "next_id": _next_id, "rng": str(_rng.state)}


func deserialize(d: Dictionary) -> void:
	offers.clear()
	_pending.clear()
	for o: Dictionary in d.get("offers", []):
		var e := o.duplicate(true)
		e["id"] = int(e["id"])
		e["day"] = int(e["day"])
		e["candidate"] = int(e["candidate"])
		var of: Dictionary = e["offer"]
		for k in ["wage", "signing_bonus", "expires_day"]:
			if of.has(k):
				of[k] = int(of[k])
		offers.append(e)
		_pending[int(e["candidate"])] = true
	last_scouted.clear()
	var ls: Dictionary = d.get("last_scouted", {})
	for k: String in ls:
		last_scouted[int(k)] = int(ls[k])
	recruited.clear()
	var rs: Dictionary = d.get("recruited", {})
	for k: String in rs:
		recruited[int(k)] = String(rs[k])
	_next_id = int(d.get("next_id", _next_id))
	if d.has("rng"):
		_rng.state = String(d["rng"]).to_int()
