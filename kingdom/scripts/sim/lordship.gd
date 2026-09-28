extends RefCounted
## Lordship: becoming a lord opens a settlement-management layer on top of the
## RPG (docs/RISING_ASHES_LIFE_SIM_DESIGN.md, "Property, nobility, lordship":
## "residents, repairs, runestones, wolves, merchants, bandits, taxes,
## refugees, wages and winter").
##
## Pure data (RefCounted, serialisable). Reads WorldGen.settlements (a
## settlement's name/pos/radius), WorldSim (its residents, for population and
## family names), Frontier.runestones (the settlement's ring stones -- the
## same ones seeded in autoload/frontier.gd) and Frontier.ecology (nearby
## monster dens), the way autoload/life.gd already reads them. Never touches
## Game.gold: a village's treasury is its own purse, separate from the
## player's pocket.
##
## A held village: {settlement, reason, granted_day, population, refugees_taken,
##   treasury, tax_rate ("low"/"fair"/"harsh"), loyalty 0..100, food (stores),
##   militia, infra: {well, mill, granary, walls, roads} each 0..1 condition,
##   runestones: [stone id...], liege_opinion, last_season, levied,
##   issues: [{id, kind, day, data}], projects: [{id, kind, days_left, total_days, data}],
##   pending: [{kind, day, data}], next_issue_id, next_project_id}
##
## Daily flow (see daily_tick, called once per in-game day from life.gd's hourly
## tick -- see the file's own docstring for the exact hook line): tax income,
## food production/consumption (season-aware), militia wages, infrastructure
## decay, projects advance, a weighted random issue may appear, loyalty drives
## unrest/revolt or prosperity, and autumn brings the harvest tithe.
##
## Issues are pure data; decisions_for() recomputes a fresh, affordable set of
## choices from the village's *current* state every time (never stored), so
## `issues` only ever needs {id, kind, day, data} to round-trip through JSON.
## decide() applies a chosen decision's effects (gold from the village
## treasury, loyalty, food, a biography reputation sphere, liege opinion,
## population) and may hand back a `quest_spec` for the caller to turn into a
## real radiant quest (see radiant_quests.gd's `add_lord_task`) and a
## `biography` highlight line for the caller to log.

signal issue_raised(settlement: int, issue: Dictionary)
signal village_changed(settlement: int)

const REASONS: Array[String] = ["military_service", "purchase", "marriage", "crown"]
const TAX_RATES := {
	"low": {"mult": 0.65, "loyalty": 0.35},
	"fair": {"mult": 1.0, "loyalty": 0.0},
	"harsh": {"mult": 1.5, "loyalty": -0.6},
}
const BASE_TAX_PER_POP := 0.045
const FOOD_PRODUCED_PER_POP := 0.026
const FOOD_CONSUMED_PER_POP := 0.02
const WINTER_FOOD_MULT := 1.4
const HARVEST_FOOD_MULT := 1.25          # autumn: the granary fills faster
const MILITIA_WAGE := 2
const INFRA_DECAY := {"well": 0.006, "mill": 0.005, "granary": 0.004, "walls": 0.0022, "roads": 0.004}
const MAX_OPEN_ISSUES := 4
const ISSUE_CHANCE := 0.4
const TITHE_RATE := 0.35                  # fraction of a season's tax income owed to the liege
const UNREST_LOYALTY := 25.0
const REVOLT_LOYALTY := 8.0
const PROSPERITY_LOYALTY := 70.0
const REFUGEE_WAVE := Vector2i(6, 30)

## Project kind -> {gold, days, label}.
const PROJECTS := {
	"repair_well": {"gold": 40, "days": 3, "label": "Repair the well"},
	"rebuild_walls": {"gold": 130, "days": 8, "label": "Rebuild the walls"},
	"repair_runestone": {"gold": 60, "days": 4, "label": "Repair the runestone"},
	"watchtower": {"gold": 150, "days": 10, "label": "Build a watchtower"},
	"expand_fields": {"gold": 90, "days": 6, "label": "Expand the fields"},
	"recruit_militia": {"gold": 24, "days": 2, "label": "Recruit militia"},
}
const MILITIA_PER_RECRUIT_PROJECT := 3

## The random-issue pool: kind -> base weight. harvest_tithe isn't in here (it
## fires on the first day of autumn, not by weighted roll).
const ISSUE_POOL := {
	"well_broken": 1.0, "runestone_cracked": 1.0, "wolves": 1.1, "bandits": 0.85,
	"merchant_warehouse": 0.7, "smith_iron": 0.7, "irrigation_dispute": 0.8,
	"refugees": 0.55, "festival_request": 0.6, "plague_scare": 0.4, "fire": 0.4,
}

## settlement id -> village dict.
var villages: Dictionary = {}


# --- granting --------------------------------------------------------------------

func is_lord_of(settlement_idx: int) -> bool:
	return villages.has(settlement_idx)


func held_settlements() -> Array:
	return villages.keys()


func village(settlement_idx: int) -> Dictionary:
	return villages.get(settlement_idx, {})


## Grants the player settlement_idx (reasons: "military_service", "purchase",
## "marriage", "crown"). A no-op returning the existing village if already held.
func grant(settlement_idx: int, reason := "crown") -> Dictionary:
	if villages.has(settlement_idx):
		return villages[settlement_idx]
	var v := {
		"settlement": settlement_idx, "reason": reason if reason in REASONS else "crown",
		"granted_day": WorldSim.day, "population": _resident_count(settlement_idx),
		"refugees_taken": 0, "treasury": 60, "tax_rate": "fair", "loyalty": 55.0,
		"food": 40.0, "militia": 4,
		"infra": {"well": 1.0, "mill": 1.0, "granary": 1.0, "walls": 0.8, "roads": 0.85},
		"runestones": _runestones_for(settlement_idx), "liege_opinion": 0.0,
		"last_season": -1, "levied": false,
		"issues": [], "projects": [], "pending": [],
		"next_issue_id": 1, "next_project_id": 1,
		"ledger": {"income": 0, "wages": 0, "food_produced": 0.0, "food_consumed": 0.0},
	}
	villages[settlement_idx] = v
	village_changed.emit(settlement_idx)
	return v


## Grants Ashford (settlement 0) so it's easy to test lordship in a live game.
func debug_grant_home() -> Dictionary:
	return grant(0, "crown")


## A loyalty-flavoured line for a village resident's greeting (a dialogue
## hook -- see the report for exactly where to splice it in), or "" when the
## player isn't that settlement's lord or loyalty is unremarkable.
func loyalty_greeting_line(settlement_idx: int) -> String:
	if not villages.has(settlement_idx):
		return ""
	var loyalty := float(villages[settlement_idx]["loyalty"])
	if loyalty >= 70.0:
		return "Good times, since you took the manor."
	if loyalty <= 25.0:
		return "Times are hard under your rule, my lord."
	return ""


func settlement_name(settlement_idx: int) -> String:
	if settlement_idx < 0 or settlement_idx >= WorldGen.settlements.size():
		return "?"
	return String(WorldGen.settlements[settlement_idx].get("name", "?"))


func _resident_count(settlement_idx: int) -> int:
	if settlement_idx < WorldSim.ranges.size():
		var r: Vector2i = WorldSim.ranges[settlement_idx]
		return maxi(0, r.y - r.x)
	return int(WorldGen.settlements[settlement_idx].get("population", 100)) if settlement_idx < WorldGen.settlements.size() else 100


## This settlement's own ring stones (owner-tagged in Frontier's network, see
## frontier.gd's `_seed_frontier`); falls back to whatever stones are nearby
## for a settlement with no ring of its own.
func _runestones_for(settlement_idx: int) -> Array:
	var out: Array = []
	for s: Dictionary in Frontier.runestones.stones:
		if int(s.get("owner", -1)) == settlement_idx:
			out.append(int(s["id"]))
	if not out.is_empty():
		return out
	var pos: Vector2 = WorldGen.settlements[settlement_idx]["pos"]
	var radius: float = float(WorldGen.settlements[settlement_idx]["radius"]) * 3.0
	for s: Dictionary in Frontier.runestones.stones_near(pos):
		if (s["pos"] as Vector2).distance_to(pos) <= radius:
			out.append(int(s["id"]))
	return out


# --- daily simulation --------------------------------------------------------------

## Advances every held village by one in-game day. `ctx`: {season, at_war}
## (as life.gd's hourly tick already tracks). Returns messages for Game.say.
func daily_tick(day: int, ctx: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var season := String(ctx.get("season", "spring"))
	var at_war := bool(ctx.get("at_war", false))
	for settlement_idx in villages.keys().duplicate():
		out.append_array(_tick_village(villages[settlement_idx], day, season, at_war))
	return out


func _tick_village(v: Dictionary, day: int, season: String, at_war: bool) -> Array[String]:
	var out: Array[String] = []
	var name := settlement_name(int(v["settlement"]))
	# --- tax income ---
	var rate: Dictionary = TAX_RATES.get(String(v["tax_rate"]), TAX_RATES["fair"])
	var income := int(round(int(v["population"]) * BASE_TAX_PER_POP * float(rate["mult"])))
	v["treasury"] = int(v["treasury"]) + income
	v["loyalty"] = clampf(float(v["loyalty"]) + float(rate["loyalty"]) * 0.1, 0.0, 100.0)
	# --- food ---
	var well_mult: float = clampf(0.5 + float(v["infra"]["well"]) * 0.5, 0.5, 1.0)
	var produced := int(v["population"]) * FOOD_PRODUCED_PER_POP * well_mult * (0.0 if season == "winter" else (HARVEST_FOOD_MULT if season == "autumn" else 1.0))
	var consumed := int(v["population"]) * FOOD_CONSUMED_PER_POP * (WINTER_FOOD_MULT if season == "winter" else 1.0)
	v["food"] = maxf(0.0, float(v["food"]) + produced - consumed)
	v["ledger"] = {"income": income, "wages": int(v["militia"]) * MILITIA_WAGE, "food_produced": produced, "food_consumed": consumed}
	if float(v["food"]) <= 0.0 and consumed > produced:
		v["loyalty"] = clampf(float(v["loyalty"]) - 3.0, 0.0, 100.0)
		if randf_from(v, day, 991) < 0.25:
			out.append("%s is starving. The granary is empty." % name)
	# --- militia wages ---
	var wages := int(v["militia"]) * MILITIA_WAGE
	if int(v["treasury"]) >= wages:
		v["treasury"] = int(v["treasury"]) - wages
	else:
		v["treasury"] = 0
		v["loyalty"] = clampf(float(v["loyalty"]) - 2.0, 0.0, 100.0)
		v["militia"] = maxi(0, int(v["militia"]) - 1)
	# --- infrastructure decay ---
	var infra: Dictionary = v["infra"]
	for key: String in infra.keys():
		infra[key] = maxf(0.0, float(infra[key]) - float(INFRA_DECAY.get(key, 0.004)))
	# --- projects ---
	out.append_array(_tick_projects(v, day))
	# --- pending followups ---
	out.append_array(_tick_pending(v, day))
	# --- seasonal tithe (harvest) ---
	if int(v["last_season"]) != _season_index(season):
		v["last_season"] = _season_index(season)
		if season == "autumn":
			_raise_issue(v, "harvest_tithe", day, {"amount": maxi(6, income * 4)})
	# --- levy on war ---
	if at_war and not bool(v["levied"]) and int(v["militia"]) > 0:
		v["levied"] = true
		var taken := maxi(1, int(v["militia"]) / 2)
		v["militia"] = int(v["militia"]) - taken
		v["loyalty"] = clampf(float(v["loyalty"]) - 4.0, 0.0, 100.0)
		out.append("%d militia of %s march off to war." % [taken, name])
	elif not at_war:
		v["levied"] = false
	# --- random issue ---
	if v["issues"].size() < MAX_OPEN_ISSUES and randf_from(v, day, 17) < ISSUE_CHANCE:
		var kind := _roll_issue_kind(v, day)
		if kind != "":
			var issue := _raise_issue(v, kind, day, _issue_data(v, kind, day))
			if not issue.is_empty():
				out.append("%s: %s" % [name, String(issue["title"])])
	# --- loyalty -> population ---
	out.append_array(_tick_loyalty(v, day, name))
	village_changed.emit(int(v["settlement"]))
	return out


func _season_index(season: String) -> int:
	return ["spring", "summer", "autumn", "winter"].find(season)


## A small, deterministic per-village-per-day RNG draw (0..1), salted so
## different calls in the same tick don't correlate.
func randf_from(v: Dictionary, day: int, salt: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(v["settlement"]), day, salt])
	return rng.randf()


func randi_range_from(v: Dictionary, day: int, salt: int, lo: int, hi: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(v["settlement"]), day, salt])
	return rng.randi_range(lo, hi)


func _tick_loyalty(v: Dictionary, day: int, name: String) -> Array[String]:
	var out: Array[String] = []
	var loyalty := float(v["loyalty"])
	if loyalty < REVOLT_LOYALTY and randf_from(v, day, 501) < 0.12:
		var lost := maxi(1, int(round(int(v["population"]) * 0.15)))
		v["population"] = maxi(0, int(v["population"]) - lost)
		v["treasury"] = int(v["treasury"]) / 2
		v["loyalty"] = 30.0
		v["issues"].clear()
		out.append("%s has revolted! %d residents flee and the treasury is looted." % [name, lost])
	elif loyalty < UNREST_LOYALTY and randf_from(v, day, 502) < 0.18:
		var left := maxi(1, int(round(int(v["population"]) * 0.03)))
		v["population"] = maxi(0, int(v["population"]) - left)
		out.append("%s: families are leaving. Loyalty is too low (%d)." % [name, int(loyalty)])
	elif loyalty > PROSPERITY_LOYALTY and float(v["food"]) > int(v["population"]) * 1.5 and randf_from(v, day, 503) < 0.1:
		v["population"] = int(v["population"]) + 1
	return out


# --- issues: availability, generation, decisions ------------------------------------

func _has_open_issue(v: Dictionary, kind: String) -> bool:
	for q: Dictionary in v["issues"]:
		if String(q["kind"]) == kind:
			return true
	return false


func _living_den_near(settlement_idx: int) -> Dictionary:
	var pos: Vector2 = WorldGen.settlements[settlement_idx]["pos"]
	var radius: float = float(WorldGen.settlements[settlement_idx]["radius"]) * 6.0
	var best := {}
	var best_d := INF
	for den: Dictionary in Frontier.ecology.dens:
		if not bool(den["alive"]) or int(den["population"]) <= 0:
			continue
		var d: float = (den["pos"] as Vector2).distance_to(pos)
		if d < radius and d < best_d:
			best_d = d
			best = den
	return best


func _cracked_stone(v: Dictionary) -> Dictionary:
	for id in v["runestones"]:
		if int(id) >= Frontier.runestones.stones.size():
			continue
		var s: Dictionary = Frontier.runestones.stones[int(id)]
		if Frontier.runestones.condition_name(s) in ["cracked", "dark"]:
			return s
	return {}


func _available_issue_kinds(v: Dictionary) -> Array:
	var out: Array = []
	var sid := int(v["settlement"])
	for kind: String in ISSUE_POOL:
		if _has_open_issue(v, kind):
			continue
		match kind:
			"well_broken":
				if float(v["infra"]["well"]) > 0.3:
					out.append(kind)
			"runestone_cracked":
				if not _cracked_stone(v).is_empty():
					out.append(kind)
			"wolves":
				if not _living_den_near(sid).is_empty():
					out.append(kind)
			"irrigation_dispute":
				if int(v["population"]) >= 2:
					out.append(kind)
			_:
				out.append(kind)
	return out


func _roll_issue_kind(v: Dictionary, day: int) -> String:
	var kinds := _available_issue_kinds(v)
	if kinds.is_empty():
		return ""
	var total := 0.0
	for k: String in kinds:
		total += float(ISSUE_POOL[k])
	var roll := randf_from(v, day, 23) * total
	for k: String in kinds:
		roll -= float(ISSUE_POOL[k])
		if roll <= 0.0:
			return k
	return String(kinds.back())


func _issue_data(v: Dictionary, kind: String, day: int) -> Dictionary:
	match kind:
		"runestone_cracked":
			return {"stone_id": int(_cracked_stone(v)["id"])}
		"wolves":
			return {"den_id": int(_living_den_near(int(v["settlement"])).get("id", -1))}
		"irrigation_dispute":
			var sid := int(v["settlement"])
			var r: Vector2i = WorldSim.ranges[sid] if sid < WorldSim.ranges.size() else Vector2i(0, 0)
			var span := maxi(1, r.y - r.x)
			var a := r.x + randi_range_from(v, day, 71, 0, span - 1)
			var b := r.x + randi_range_from(v, day, 73, 0, span - 1)
			return {"family_a": WorldSim.person_name(a), "family_b": WorldSim.person_name(b)}
		"refugees":
			return {"count": randi_range_from(v, day, 61, REFUGEE_WAVE.x, REFUGEE_WAVE.y)}
		_:
			return {}


## Adds a new open issue of `kind` (dedup against an existing one of the same
## kind); returns the issue dict, or {} if one is already open.
func _raise_issue(v: Dictionary, kind: String, day: int, data: Dictionary) -> Dictionary:
	if _has_open_issue(v, kind):
		return {}
	var issue := {"id": int(v["next_issue_id"]), "kind": kind, "day": day, "data": data}
	v["next_issue_id"] = int(v["next_issue_id"]) + 1
	v["issues"].append(issue)
	issue_raised.emit(int(v["settlement"]), issue)
	issue["title"] = issue_title(v, issue)
	return issue


func issue_title(v: Dictionary, issue: Dictionary) -> String:
	var name := settlement_name(int(v["settlement"]))
	var data: Dictionary = issue.get("data", {})
	match String(issue["kind"]):
		"well_broken":
			return "The well in %s needs repairing." % name
		"runestone_cracked":
			var sid := int(data.get("stone_id", -1))
			var sname := String(Frontier.runestones.stones[sid]["name"]) if sid >= 0 and sid < Frontier.runestones.stones.size() else "a runestone"
			return "The %s has cracked." % sname
		"wolves":
			return "Wolves are taking livestock near %s." % name
		"bandits":
			return "Bandits are working the southern road out of %s." % name
		"merchant_warehouse":
			return "A merchant wants to build a warehouse in %s." % name
		"smith_iron":
			return "The smith of %s wants better iron." % name
		"irrigation_dispute":
			return "%s and %s are feuding over irrigation rights." % [String(data.get("family_a", "One family")), String(data.get("family_b", "another"))]
		"refugees":
			return "%d refugees have arrived at %s's gates." % [int(data.get("count", 10)), name]
		"festival_request":
			return "The folk of %s want a festival." % name
		"harvest_tithe":
			return "The harvest tithe of %d gold is owed to your liege." % int(data.get("amount", 20))
		"plague_scare":
			return "A plague scare grips %s." % name
		"fire":
			return "Fire has broken out in %s." % name
	return "Something needs your attention in %s." % name


func issue_desc(v: Dictionary, issue: Dictionary) -> String:
	match String(issue["kind"]):
		"well_broken":
			return "The village well is cracked and fouled. Left alone, sickness follows."
		"runestone_cracked":
			return "Its light is guttering. Left dark, the wards around the village weaken."
		"wolves":
			return "A den nearby has grown bold; shepherds are losing livestock."
		"bandits":
			return "Travellers are being robbed on the road south. Something must be done."
		"merchant_warehouse":
			return "A merchant offers to build a warehouse, if you'll help fund it."
		"smith_iron":
			return "The forge is running low on decent ore; the smith wants it sourced properly."
		"irrigation_dispute":
			return "Both families swear the water rights are theirs. They want you to rule."
		"refugees":
			return "They ask for shelter and work. Food and loyalty hang in the balance."
		"festival_request":
			return "A festival would lift spirits, at the cost of stores and coin."
		"harvest_tithe":
			return "Your liege expects the season's due. Delay it at your peril."
		"plague_scare":
			return "A fever is spreading. Quick, decisive care could stop it here."
		"fire":
			return "Flames threaten the granary and nearby homes."
	return ""


## Fresh, affordable-labelled decisions for an open issue, recomputed from the
## village's current state (never stored). Each: {label, gold, loyalty, food,
## sphere ("military"/"trade"), reputation, liege_opinion, population,
## infra: {key: value}, project, quest_spec, affordable}.
func decisions_for(v: Dictionary, issue: Dictionary) -> Array[Dictionary]:
	var t := int(v["treasury"])
	var out: Array[Dictionary] = []
	var data: Dictionary = issue.get("data", {})
	match String(issue["kind"]):
		"well_broken":
			out.append(_d("Pay for repairs now (40g)", {"gold": -40, "loyalty": 6.0, "infra": {"well": 1.0},
				"highlight": "Repaired the well of %s" % settlement_name(int(v["settlement"]))}, t))
			out.append(_d("Start a slower repair project (15g, 3 days)", {"gold": -15, "project": "repair_well"}, t))
			out.append(_d("Ignore it", {"loyalty": -8.0, "sphere": "trade", "reputation": -2.0}, t))
		"runestone_cracked":
			var sid := int(data.get("stone_id", -1))
			var sname := String(Frontier.runestones.stones[sid]["name"]) if sid >= 0 and sid < Frontier.runestones.stones.size() else "the runestone"
			out.append(_d("Pay for repairs now (60g)", {"gold": -60, "loyalty": 5.0, "runestone_repair": sid,
				"highlight": "Repaired %s" % sname}, t))
			out.append(_d("Send someone to see to it (20g)", {"gold": -20, "project": "repair_runestone",
				"quest_spec": _quest_repair_runestone(v, sid)}, t))
			out.append(_d("Ignore it", {"loyalty": -6.0, "sphere": "military", "reputation": -3.0}, t))
		"wolves":
			var den_id := int(data.get("den_id", -1))
			out.append(_d("Hire hunters to thin the den (30g)", {"gold": -30, "loyalty": 4.0, "cull_den": den_id}, t))
			out.append(_d("Deal with it yourself", {"quest_spec": _quest_clear_wolves(v, den_id)}, t))
			out.append(_d("Ignore it", {"loyalty": -5.0, "food": -6.0, "sphere": "trade", "reputation": -2.0,
				"followup_kind": "wolves", "followup_days": 5, "followup_data": {"den_id": den_id}}, t))
		"bandits":
			out.append(_d("Send a militia patrol (25g)", {"gold": -25, "loyalty": 5.0, "sphere": "military", "reputation": 2.0}, t))
			out.append(_d("Deal with it yourself", {"quest_spec": _quest_bandits(v)}, t))
			out.append(_d("Pay them off", {"gold": -20, "loyalty": -6.0, "sphere": "trade", "reputation": -4.0,
				"followup_kind": "bandits", "followup_days": 6}, t))
		"merchant_warehouse":
			out.append(_d("Fund the warehouse (50g)", {"gold": -50, "loyalty": 4.0, "sphere": "trade", "reputation": 4.0}, t))
			out.append(_d("Approve, on the merchant's coin", {"loyalty": 2.0, "sphere": "trade", "reputation": 1.0}, t))
			out.append(_d("Refuse", {"loyalty": -1.0, "sphere": "trade", "reputation": -2.0}, t))
		"smith_iron":
			out.append(_d("Buy iron from the regional market (35g)", {"gold": -35, "loyalty": 3.0, "sphere": "trade", "reputation": 2.0}, t))
			out.append(_d("Send someone to fetch it", {"quest_spec": _quest_fetch_iron(v)}, t))
			out.append(_d("Tell him to make do", {"loyalty": -2.0}, t))
		"irrigation_dispute":
			var a := String(data.get("family_a", "One family"))
			var b := String(data.get("family_b", "the other"))
			out.append(_d("Rule for %s" % a, {"loyalty": -1.0, "sphere": "trade", "reputation": 1.0}, t))
			out.append(_d("Rule for %s" % b, {"loyalty": -1.0, "sphere": "trade", "reputation": 1.0}, t))
			out.append(_d("Order a shared canal (25g)", {"gold": -25, "loyalty": 5.0, "sphere": "trade", "reputation": 2.0}, t))
		"refugees":
			var n := int(data.get("count", 10))
			out.append(_d("Take them all in", {"loyalty": 6.0, "population": n, "food": -float(n) * 1.5, "sphere": "trade", "reputation": 3.0,
				"highlight": "Took in %d refugees at %s" % [n, settlement_name(int(v["settlement"]))]}, t))
			out.append(_d("Take in half", {"loyalty": 2.0, "population": n / 2, "food": -float(n) * 0.75, "sphere": "trade", "reputation": 1.0}, t))
			out.append(_d("Turn them away", {"loyalty": -4.0, "sphere": "trade", "reputation": -3.0}, t))
		"festival_request":
			out.append(_d("Fund a proper festival (30g)", {"gold": -30, "loyalty": 10.0, "food": -8.0}, t))
			out.append(_d("A modest celebration (10g)", {"gold": -10, "loyalty": 4.0, "food": -3.0}, t))
			out.append(_d("Decline", {"loyalty": -3.0}, t))
		"harvest_tithe":
			var owed := int(data.get("amount", 20))
			out.append(_d("Pay it in full (%dg)" % owed, {"gold": -owed, "liege_opinion": 8.0, "sphere": "trade"}, t))
			out.append(_d("Pay half (%dg)" % (owed / 2), {"gold": -owed / 2, "liege_opinion": -3.0, "sphere": "trade"}, t))
			out.append(_d("Refuse", {"liege_opinion": -15.0, "loyalty": -2.0, "sphere": "military", "reputation": -3.0}, t))
		"plague_scare":
			out.append(_d("Quarantine and treat (35g)", {"gold": -35, "loyalty": -2.0, "population": 0, "sphere": "trade", "reputation": 3.0}, t))
			out.append(_d("Start a healer's project (20g, 3 days)", {"gold": -20, "project": "repair_well"}, t))
			out.append(_d("Pray and hope", {"loyalty": -6.0, "population": -maxi(1, int(v["population"]) / 20), "sphere": "trade", "reputation": -3.0}, t))
		"fire":
			out.append(_d("Organise a bucket brigade", {"loyalty": 3.0, "infra": {"granary": maxf(0.4, float(v["infra"]["granary"]))}}, t))
			out.append(_d("Pay for firefighters (25g)", {"gold": -25, "loyalty": 5.0, "infra": {"granary": 1.0}}, t))
			out.append(_d("Let it burn", {"loyalty": -7.0, "infra": {"granary": maxf(0.0, float(v["infra"]["granary"]) - 0.4)}}, t))
	return out


func _d(label: String, effects: Dictionary, treasury: int) -> Dictionary:
	var e := effects.duplicate(true)
	e["label"] = label
	e["affordable"] = treasury + int(e.get("gold", 0)) >= 0
	return e


func _quest_clear_wolves(v: Dictionary, den_id: int) -> Dictionary:
	var pos := Vector2.ZERO
	for den: Dictionary in Frontier.ecology.dens:
		if int(den["id"]) == den_id:
			pos = den["pos"]
	return {"title": "Clear the wolves near %s" % settlement_name(int(v["settlement"])),
		"desc": "The den has been taking livestock. Thin it.",
		"kind": "kill_den", "pos": pos, "den_id": den_id, "kills": 3, "radius": 40.0,
		"reward": {"gold": 20, "sphere": "military", "reputation": 4.0}, "days": 8}


func _quest_bandits(v: Dictionary) -> Dictionary:
	var pos: Vector2 = WorldGen.settlements[int(v["settlement"])]["pos"] + Vector2(0.0, float(WorldGen.settlements[int(v["settlement"])]["radius"]) * 3.0)
	return {"title": "Clear the bandits south of %s" % settlement_name(int(v["settlement"])),
		"desc": "Riders have been robbing the southern road.",
		"kind": "reach", "pos": pos, "radius": 40.0,
		"reward": {"gold": 25, "sphere": "military", "reputation": 4.0}, "days": 6}


func _quest_repair_runestone(v: Dictionary, stone_id: int) -> Dictionary:
	var pos := Vector2.ZERO
	var sname := "the runestone"
	if stone_id >= 0 and stone_id < Frontier.runestones.stones.size():
		var s: Dictionary = Frontier.runestones.stones[stone_id]
		pos = s["pos"]
		sname = String(s["name"])
	return {"title": "Repair %s" % sname, "desc": "The stone needs a steady hand and time to mend.",
		"kind": "reach", "pos": pos, "radius": 12.0, "stone_id": stone_id,
		"reward": {"gold": 15, "sphere": "trade", "reputation": 2.0}, "days": 6}


func _quest_fetch_iron(v: Dictionary) -> Dictionary:
	return {"title": "Fetch iron for the smith of %s" % settlement_name(int(v["settlement"])),
		"desc": "The forge needs better ore than the village can dig on its own.",
		"kind": "gather", "item": "iron_ore", "amount": 6, "pos": WorldGen.settlements[int(v["settlement"])]["pos"], "radius": 6.0,
		"reward": {"gold": 18, "sphere": "trade", "reputation": 2.0}, "days": 6}


## Applies a decision on an open issue. Returns {ok, text, quest_spec (optional),
## biography (optional highlight line)}.
func decide(settlement_idx: int, issue_id: int, choice: int) -> Dictionary:
	if not villages.has(settlement_idx):
		return {"ok": false, "text": "You hold no such village."}
	var v: Dictionary = villages[settlement_idx]
	var issue := {}
	for q: Dictionary in v["issues"]:
		if int(q["id"]) == issue_id:
			issue = q
	if issue.is_empty():
		return {"ok": false, "text": "That matter has already been settled."}
	var decisions := decisions_for(v, issue)
	if choice < 0 or choice >= decisions.size():
		return {"ok": false, "text": "No such choice."}
	var d: Dictionary = decisions[choice]
	var cost := -mini(0, int(d.get("gold", 0)))
	if cost > int(v["treasury"]):
		return {"ok": false, "text": "Not enough in the treasury (need %d, have %d)." % [cost, int(v["treasury"])]}
	v["treasury"] = int(v["treasury"]) + int(d.get("gold", 0))
	v["loyalty"] = clampf(float(v["loyalty"]) + float(d.get("loyalty", 0.0)), 0.0, 100.0)
	v["food"] = maxf(0.0, float(v["food"]) + float(d.get("food", 0.0)))
	v["population"] = maxi(0, int(v["population"]) + int(d.get("population", 0)))
	v["liege_opinion"] = clampf(float(v["liege_opinion"]) + float(d.get("liege_opinion", 0.0)), -100.0, 100.0)
	var infra_set: Dictionary = d.get("infra", {})
	for key: String in infra_set:
		v["infra"][key] = clampf(float(infra_set[key]), 0.0, 1.0)
	if d.has("runestone_repair"):
		Frontier.runestones.maintain(int(d["runestone_repair"]), WorldSim.day, 1.0)
	if d.has("cull_den"):
		Frontier.ecology.cull(int(d["cull_den"]), 3)
	if d.has("project"):
		_start_project_internal(v, String(d["project"]), WorldSim.day)
	if d.has("followup_kind"):
		v["pending"].append({"kind": String(d["followup_kind"]), "day": WorldSim.day + int(d.get("followup_days", 4)),
			"data": d.get("followup_data", {})})
	v["issues"].erase(issue)
	var result := {"ok": true, "text": String(d["label"]), "sphere": String(d.get("sphere", "")),
		"reputation": float(d.get("reputation", 0.0))}
	if d.has("quest_spec"):
		result["quest_spec"] = d["quest_spec"]
	if d.has("highlight"):
		result["biography"] = String(d["highlight"])
	village_changed.emit(settlement_idx)
	return result


func _tick_pending(v: Dictionary, day: int) -> Array[String]:
	var out: Array[String] = []
	for p: Dictionary in v["pending"].duplicate():
		if day >= int(p["day"]):
			v["pending"].erase(p)
			var issue := _raise_issue(v, String(p["kind"]), day, p.get("data", {}))
			if not issue.is_empty():
				out.append("%s: %s" % [settlement_name(int(v["settlement"])), String(issue["title"])])
	return out


# --- projects -----------------------------------------------------------------------

## Starts a project (charging the village treasury). "" on success, else why not.
func start_project(settlement_idx: int, kind: String) -> String:
	if not villages.has(settlement_idx):
		return "You hold no such village."
	if not PROJECTS.has(kind):
		return "No such project."
	var v: Dictionary = villages[settlement_idx]
	var cost := int(PROJECTS[kind]["gold"])
	if int(v["treasury"]) < cost:
		return "Not enough in the treasury (need %d, have %d)." % [cost, int(v["treasury"])]
	v["treasury"] = int(v["treasury"]) - cost
	_start_project_internal(v, kind, WorldSim.day)
	return ""


func _start_project_internal(v: Dictionary, kind: String, day: int) -> void:
	var info: Dictionary = PROJECTS[kind]
	var data := {}
	if kind == "repair_runestone":
		var stone := _cracked_stone(v)
		data["stone_id"] = int(stone.get("id", -1)) if not stone.is_empty() else -1
	v["projects"].append({"id": int(v["next_project_id"]), "kind": kind, "days_left": int(info["days"]),
		"total_days": int(info["days"]), "data": data})
	v["next_project_id"] = int(v["next_project_id"]) + 1


func _tick_projects(v: Dictionary, day: int) -> Array[String]:
	var out: Array[String] = []
	var name := settlement_name(int(v["settlement"]))
	for p: Dictionary in v["projects"].duplicate():
		p["days_left"] = int(p["days_left"]) - 1
		if int(p["days_left"]) > 0:
			continue
		v["projects"].erase(p)
		out.append(_complete_project(v, p, day, name))
	return out


func _complete_project(v: Dictionary, p: Dictionary, day: int, name: String) -> String:
	var kind := String(p["kind"])
	match kind:
		"repair_well":
			v["infra"]["well"] = 1.0
			v["loyalty"] = clampf(float(v["loyalty"]) + 5.0, 0.0, 100.0)
			return "%s: the well has been repaired." % name
		"rebuild_walls":
			v["infra"]["walls"] = 1.0
			v["loyalty"] = clampf(float(v["loyalty"]) + 6.0, 0.0, 100.0)
			return "%s: the walls have been rebuilt." % name
		"repair_runestone":
			var stone_id := int(p["data"].get("stone_id", -1))
			var sname := "the runestone"
			if stone_id >= 0 and stone_id < Frontier.runestones.stones.size():
				Frontier.runestones.maintain(stone_id, day, 1.0)
				sname = String(Frontier.runestones.stones[stone_id]["name"])
			v["loyalty"] = clampf(float(v["loyalty"]) + 4.0, 0.0, 100.0)
			return "%s: %s has been repaired." % [name, sname]
		"watchtower":
			v["infra"]["walls"] = minf(1.0, float(v["infra"]["walls"]) + 0.2)
			v["militia"] = int(v["militia"]) + 2
			return "%s: a watchtower now stands guard." % name
		"expand_fields":
			v["food"] = float(v["food"]) + 20.0
			return "%s: the fields have been expanded." % name
		"recruit_militia":
			v["militia"] = int(v["militia"]) + MILITIA_PER_RECRUIT_PROJECT
			return "%s: %d new militia have finished training." % [name, MILITIA_PER_RECRUIT_PROJECT]
	return "%s: a project has finished." % name


# --- tax rate & levy ------------------------------------------------------------------

func set_tax_rate(settlement_idx: int, rate: String) -> String:
	if not villages.has(settlement_idx):
		return "You hold no such village."
	if not TAX_RATES.has(rate):
		return "No such tax rate."
	villages[settlement_idx]["tax_rate"] = rate
	return ""


## Called when war begins, in case the daily tick hasn't run yet this day
## (see the life.gd hook in the header docstring for when this fires).
func levy_troops(settlement_idx: int) -> String:
	if not villages.has(settlement_idx):
		return ""
	var v: Dictionary = villages[settlement_idx]
	if bool(v["levied"]) or int(v["militia"]) <= 0:
		return ""
	v["levied"] = true
	var taken := maxi(1, int(v["militia"]) / 2)
	v["militia"] = int(v["militia"]) - taken
	v["loyalty"] = clampf(float(v["loyalty"]) - 4.0, 0.0, 100.0)
	return "%d militia of %s march off to war." % [taken, settlement_name(settlement_idx)]


# --- save / load ------------------------------------------------------------------------

func serialize() -> Dictionary:
	var out := {}
	for id in villages:
		out[str(id)] = (villages[id] as Dictionary).duplicate(true)
	return {"villages": out}


func deserialize(d: Dictionary) -> void:
	villages.clear()
	var vs: Dictionary = d.get("villages", {})
	for key: String in vs:
		var v: Dictionary = (vs[key] as Dictionary).duplicate(true)
		v["settlement"] = int(v.get("settlement", int(key)))
		v["population"] = int(v.get("population", 0))
		v["refugees_taken"] = int(v.get("refugees_taken", 0))
		v["treasury"] = int(v.get("treasury", 0))
		v["militia"] = int(v.get("militia", 0))
		v["next_issue_id"] = int(v.get("next_issue_id", 1))
		v["next_project_id"] = int(v.get("next_project_id", 1))
		v["last_season"] = int(v.get("last_season", -1))
		v["levied"] = bool(v.get("levied", false))
		v["loyalty"] = float(v.get("loyalty", 50.0))
		v["food"] = float(v.get("food", 0.0))
		v["liege_opinion"] = float(v.get("liege_opinion", 0.0))
		var infra: Dictionary = v.get("infra", {})
		for k: String in infra:
			infra[k] = float(infra[k])
		var stones: Array = []
		for s in v.get("runestones", []):
			stones.append(int(s))
		v["runestones"] = stones
		var issues: Array = []
		for q: Variant in v.get("issues", []):
			var qq: Dictionary = q
			qq["id"] = int(qq["id"])
			qq["day"] = int(qq["day"])
			issues.append(qq)
		v["issues"] = issues
		var projects: Array = []
		for p: Variant in v.get("projects", []):
			var pp: Dictionary = p
			pp["id"] = int(pp["id"])
			pp["days_left"] = int(pp["days_left"])
			pp["total_days"] = int(pp["total_days"])
			projects.append(pp)
		v["projects"] = projects
		var pending: Array = []
		for p: Variant in v.get("pending", []):
			var pp2: Dictionary = p
			pp2["day"] = int(pp2["day"])
			pending.append(pp2)
		v["pending"] = pending
		villages[int(key)] = v
