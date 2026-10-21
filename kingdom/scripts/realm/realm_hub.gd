extends RefCounted
## Realm simulation hub: owns every realm module and runs the time-tier
## schedule from docs/design/SIM_HIERARCHY.md so nothing spikes a frame.
##
## Life (autoload/life.gd) owns one hub as `Life.realm` and calls:
##   on_hour(hour, ctx)  -> queues each module's tick_hour (and tick_day at 06:00,
##                          tick_week on day % 7 == 0)
##   pump()              -> every frame; runs queued jobs until PUMP_BUDGET_USEC
##   catch_up(days, ctx) -> after long sleeps / loads
## Messages from ticks are returned by pump() for Life to Game.say().

const MODULES := {
	"registry": preload("res://scripts/realm/registry.gd"),   # LW-1.1: persistent ids + legacy alias map
	"events": preload("res://scripts/realm/events.gd"),       # LW-1.2: EventRecord ring with summarised archive
	"followers": preload("res://scripts/realm/followers.gd"),
	"recruitment": preload("res://scripts/realm/recruitment.gd"),   # Living World §2: contracts, notices, chains, managers
	"camps": preload("res://scripts/realm/camps.gd"),
	"civilization": preload("res://scripts/realm/civilization.gd"),
	"migration": preload("res://scripts/realm/migration.gd"),
	"settlements": preload("res://scripts/realm/settlements.gd"),
	"land": preload("res://scripts/realm/land.gd"),
	"factions": preload("res://scripts/realm/factions.gd"),
	"strongholds": preload("res://scripts/realm/strongholds.gd"),
	"campaign": preload("res://scripts/realm/campaign.gd"),
	"city_life": preload("res://scripts/realm/city_life.gd"),
	"society": preload("res://scripts/realm/society.gd"),
	"governance": preload("res://scripts/realm/governance.gd"),
	"notables": preload("res://scripts/realm/notables.gd"),
	"news": preload("res://scripts/realm/news.gd"),
	"exploration": preload("res://scripts/realm/exploration.gd"),
	"power_paths": preload("res://scripts/realm/power_paths.gd"),
	"education": preload("res://scripts/realm/education.gd"),
	"cultivation": preload("res://scripts/realm/cultivation.gd"),
	"household": preload("res://scripts/realm/household.gd"),
	"callups": preload("res://scripts/realm/callups.gd"),
	"work": preload("res://scripts/realm/work.gd"),
	"scribe": preload("res://scripts/realm/scribe.gd"),
	"soldier": preload("res://scripts/realm/soldier.gd"),
	"trades": preload("res://scripts/realm/career_trades.gd"),
	"enterprise": preload("res://scripts/realm/enterprise.gd"),
	"construction": preload("res://scripts/realm/construction.gd"),
	"towers": preload("res://scripts/realm/towers.gd"),
	"ecology": preload("res://scripts/realm/ecology.gd"),
	"farming": preload("res://scripts/realm/farming.gd"),     # LW Stage 3: land ladder, fields, livestock, farm economy, NPC farmers
	"organizations": preload("res://scripts/realm/organizations.gd"),   # LW Stage 4: one generic organization record (ranks, rights, succession, branches)
	"businesses": preload("res://scripts/realm/businesses.gd"),         # LW Stage 4: shops, workshops, inns, caravans with accounts and remote reports
	"build_kit": preload("res://scripts/realm/build_kit.gd"),   # Build-kit hook: modular piece building (docs/regions/HOOKS_FOR_CLOUD.md)
	"stewardship": preload("res://scripts/realm/stewardship.gd"),   # LW Stage 6: authority chain per location, running a territory
	"reputation": preload("res://scripts/realm/reputation.gd"),     # LW Stage 6: multi-axis reputation with travel delay
	"audiences": preload("res://scripts/realm/audiences.gd"),       # LW Stage 6: petitions in 8 steps, documents, disputes, reviews
	"territory": preload("res://scripts/realm/territory.gd"),       # LW Stage 6: ten territory layers; capture is not lordship
	"diplomacy": preload("res://scripts/realm/diplomacy.gd"),       # LW Stage 6: pacts, breaches, reactions to independent factions
	"courts": preload("res://scripts/realm/courts.gd"),             # LW Stage 6: laws per kingdom, cases, trials, appeals
	"succession": preload("res://scripts/realm/succession.gd"),     # LW Stage 6: claims, regents, local succession rules
	"armies": preload("res://scripts/realm/armies.gd"),         # LW Stage 7: Army entity (ar:n), force types and legal limits, officers, couriers, fog of war, logistics, settlement defence
	"ledger": preload("res://scripts/realm/ledger.gd"),               # MW-19/20/21: scheduled wages, taxes, rent, upkeep, loans, contracts; shortage ladder; delegation and audit
	"will": preload("res://scripts/realm/follower_will.gd"),   # MW-12/13/14: follower motives, roles, order responses, requests, delegation quality, player actions
	"persona": preload("res://scripts/realm/persona.gd"),       # NI-2: packed person record (origin, culture, values, intelligence), the source of truth for traits
	"emergence": preload("res://scripts/realm/emergence.gd"),   # LW Stage 8: emergent event chains with knock-on effects, delivered as news
	"faith": preload("res://scripts/realm/faith.gd"),           # LW Stage 8: churches as organizations, belief, festivals, culture tags
	"dynasties": preload("res://scripts/realm/dynasties.gd"),   # LW Stage 8: houses, family reputation, specialties, feuds, estates
	"homes": preload("res://scripts/realm/homes.gd"),           # LW Stage 8: homes, households, education ages, relocation, travel parties
	"minds": preload("res://scripts/realm/minds.gd"),           # LW Stage 8: five-layer decisions for upgraded Characters, aggregate households
	"rumours": preload("res://scripts/realm/rumours.gd"),       # LW Stage 8: memory and rumour, wrong stories, investigation
	"founding": preload("res://scripts/realm/founding.gd"),     # LW Stage 5: site evaluation, legal land, illegal-build escalation, founding stages, scale classes, hidden valley, NPC founders
}
## Order matters within a tier: land before factions before campaign.
const ORDER := ["registry", "events", "settlements", "land", "camps", "civilization", "migration", "followers", "recruitment", "will", "factions", "strongholds", "campaign", "city_life", "society", "governance", "notables", "news", "exploration", "power_paths", "education", "cultivation", "household", "callups", "work", "scribe", "soldier", "trades", "enterprise", "construction", "towers", "ecology", "farming", "organizations", "businesses", "ledger", "build_kit", "founding", "stewardship", "reputation", "audiences", "territory", "diplomacy", "courts", "succession", "armies", "emergence", "faith", "dynasties", "homes", "persona", "minds", "rumours"]
## Max microseconds of realm work per frame (mobile: ~0.6 ms of a 16.6 ms frame).
const PUMP_BUDGET_USEC := 600

var mods := {}
var _queue: Array = []   # [module_name, method, arg, ctx]  or  ["", Callable, null, null] (a day-tick chunk)


func _init() -> void:
	for k: String in ORDER:
		var m: RefCounted = MODULES[k].new()
		m.hub = self
		mods[k] = m


## Builds every module's lazy data (rosters, schedules, guilds) up front so the
## first in-game hour/day never pays for it. Call behind a loading screen.
func warm_up() -> void:
	for k: String in ORDER:
		var m: RefCounted = mods[k]
		for f: String in ["_ensure", "_ensure_npcs", "_ensure_guilds"]:
			if m.has_method(f) and m.get_method_argument_count(f) == 0:
				m.call(f)
	var cl: RefCounted = mods["city_life"]
	if cl.has_method("_ensure"):
		for st in WorldGen.settlements:
			cl.call("_ensure", int(st["id"]))


func mod(name: String) -> RefCounted:
	return mods.get(name)


func on_hour(hour: int, day: int, ctx: Dictionary) -> void:
	for k: String in ORDER:
		_queue.append([k, "tick_hour", hour, ctx])
	if hour == 6:
		for k: String in ORDER:
			_queue.append([k, "tick_day", day, ctx])
		if day % 7 == 0:
			for k: String in ORDER:
				_queue.append([k, "tick_week", day / 7, ctx])


## Adds spread-out jobs of another system (Callables returning an Array of lines to say), run by pump() in order after
## what is already queued. Life uses it for the economy's hourly tick (RAEconomy.queue_hour_jobs).
func queue_jobs(jobs: Array) -> void:
	for cb: Callable in jobs:
		_queue.append(["", cb, null, null])


## Runs queued jobs within the frame budget; at least one job per call so the
## queue always drains. Returns messages to show.
func pump() -> Array:
	var out: Array = []
	if _queue.is_empty():
		return out
	var t0 := Time.get_ticks_usec()
	while not _queue.is_empty():
		out.append_array(_run_job(_queue.pop_front()))
		if Time.get_ticks_usec() - t0 > PUMP_BUDGET_USEC:
			break
	return out


## Runs one queued job. A module's tick_day that offers chunks is expanded in place into one job per
## chunk (same order, same results) so the pump can spread it over frames.
func _run_job(j: Array) -> Array:
	if j[1] is Callable:
		return (j[1] as Callable).call()
	var m: RefCounted = mods[j[0]]
	if j[1] == "tick_day":
		var chunks: Array = m.tick_day_chunks(j[2], j[3])
		if not chunks.is_empty():
			for i in range(chunks.size() - 1, -1, -1):
				_queue.push_front(["", chunks[i], null, null])
			return []
	return m.call(j[1], j[2], j[3])


## Flush everything now (tests, save, sleep).
func drain() -> Array:
	var out: Array = []
	while not _queue.is_empty():
		out.append_array(_run_job(_queue.pop_front()))
	return out


func catch_up(days: int, ctx: Dictionary) -> Array:
	var out := drain()
	for k: String in ORDER:
		out.append_array(mods[k].catch_up(days, ctx))
	return out


func serialize() -> Dictionary:
	var d := {}
	for k: String in ORDER:
		d[k] = mods[k].serialize()
	return d


func deserialize(d: Dictionary) -> void:
	_queue.clear()
	for k: String in ORDER:
		if d.get(k) is Dictionary:
			mods[k].deserialize(d[k])
