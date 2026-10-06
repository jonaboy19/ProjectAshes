extends RefCounted
## Travel rules for the 12 x 12 km world (docs/design/REALM_PLAN.md "Travel and world size"): crossing the map is a
## journey. Pure data and static helpers, nothing here needs an autoload (tests/test_travel_rules.gd runs it directly).
##
##   * Stamina: a long run drains stamina (after RUN_FREE_S seconds of running outside towns). At zero you are winded:
##     walk until WINDED_RECOVER. Walking costs nothing. A horse canters for free and gallops GALLOP_FREE_S seconds
##     before it needs GALLOP_REST_S seconds at a canter or less (player.gd drives both, mount_controller.gallop_allowed).
##   * Night camping: a Bedroll or Travel Tent (data/items/tools.json, rest_bonus) used outdoors from dusk sleeps rough.
##     A tinderbox lights a fire. The night is risky: camp_risk() from the ecology's danger, nearby bandit camps and the
##     road; the outcomes are an ambush (bandits or beasts), a thief, a travelling visitor, or a quiet night.
##   * Fast travel: only between DISCOVERED waystations (coach inns and roadhouses), only starting from one, and it
##     costs gold (fare()) and in-game hours (coach_hours()).
##   * Road events (realm_encounters.gd) read road_weights() for what the road shows the player.

const RUN_FREE_S := 10.0          ## seconds of continuous running before stamina starts to drain (a dash is free)
const RUN_DRAIN := 9.0            ## stamina per second while running past RUN_FREE_S (a full bar lasts ~11 s of that)
const WINDED_RECOVER := 0.7       ## fraction of your stamina cap needed before you may run again after being winded
const WINDED_REGEN := 0.18        ## stamina regeneration while winded, x the usual: about 14 s of walking to get your wind back
const GALLOP_FREE_S := 30.0       ## a horse gallops this long ...
const GALLOP_REST_S := 10.0       ## ... then needs this long at a canter or slower

## Coach speed: faster than a courier on the realm's roads (campaign.COURIER_SPEED is 540 m/h, camps travel 1050 m/h).
const COACH_M_PER_HOUR := 1575.0
const COACH_BOARDING_H := 0.5
const FARE_BASE := 4
const FARE_PER_200M := 1
const BOARD_KINDS := ["waystation", "ferry"]   ## site kinds a ride may start from (a ferry landing is a coach stop over water)
const WAYSTATION_REACH := 90.0    ## metres from a waystation site's centre that count as "at" it (its yard is ~22 m wide)

const CAMP_FROM_HOUR := 17        ## camping opens at dusk ...
const CAMP_UNTIL_HOUR := 5        ## ... until just before dawn
const CAMP_SETTLEMENT_MARGIN := 1.4   ## x settlement radius: closer than this, go to an inn
const KIT_BONUS := {"tent_kit": 0.6, "bedroll": 0.25}   ## data/items/tools.json rest_bonus
const GROUND_QUALITY := 0.5       ## Needs.sleep quality on bare ground

const ROAD_MAX_DIST := 45.0       ## metres from the road centre: "on the road"
const ROAD_COOLDOWN_H := 6        ## game hours between two road events (3 real minutes)
const ROAD_MIN_DIST := 1400.0     ## metres travelled since the last one: about six meetings on a 10 km road, not a stream
const ROAD_TICK_CHANCE := 0.012   ## per 2 s tick of valid road, scaled by road_weights() total


# --- stamina ---------------------------------------------------------------------------------------------

## Stamina per second drained by running for `run_time` seconds (0 inside the free window).
static func run_drain(run_time: float) -> float:
	return RUN_DRAIN if run_time > RUN_FREE_S else 0.0


## True while the player is winded: out of stamina, until it climbs back to WINDED_RECOVER x `cap` (the current stamina
## cap, lower when tired). Sustained running therefore averages about 4.2 m/s instead of 6.5: a canter (5.8) is better.
static func is_winded(stamina: float, was_winded: bool, cap := 100.0) -> bool:
	if stamina <= 0.0:
		return true
	return was_winded and stamina < WINDED_RECOVER * cap


## One tick of the gallop clock: climbs while galloping, falls while not. Returns [gallop_time, allowed].
static func gallop_step(gallop_time: float, galloping: bool, delta: float, allowed: bool) -> Array:
	var t := gallop_time
	if galloping:
		t += delta
	else:
		t = maxf(0.0, t - delta * (GALLOP_FREE_S / GALLOP_REST_S))
	if t >= GALLOP_FREE_S:
		allowed = false
	elif t <= 0.0:
		allowed = true
	return [t, allowed]


# --- fast travel -----------------------------------------------------------------------------------------

## Gold for a coach ride of `distance` metres.
static func fare(distance: float) -> int:
	return FARE_BASE + int(ceil(distance / 200.0)) * FARE_PER_200M


## In-game hours the ride takes.
static func coach_hours(distance: float) -> float:
	return COACH_BOARDING_H + distance / COACH_M_PER_HOUR


## The waystation site the player stands at (within WAYSTATION_REACH of its centre), or {}.
static func waystation_at(pos: Vector2, sites: Array) -> Dictionary:
	var best := {}
	var best_d := WAYSTATION_REACH
	for s: Dictionary in sites:
		if not (String(s.get("kind", "")) in BOARD_KINDS):
			continue
		var d := pos.distance_to(s["pos"])
		if d < best_d:
			best_d = d
			best = s
	return best


## "" when a ride may start here and now, else why not. `waystation`: waystation_at(). `gold`: the purse.
static func ride_block_reason(waystation: Dictionary, cost: int, gold: int) -> String:
	if waystation.is_empty():
		return "Coaches run from waystations and coach inns. Walk to one first."
	if gold < cost:
		return "The fare is %d gold. You have %d." % [cost, gold]
	return ""


# --- night camping ---------------------------------------------------------------------------------------

## The best sleeping kit among what is carried: {id, name, bonus, fire}. id "" = nothing to sleep on.
static func camp_kit(carried: Dictionary) -> Dictionary:
	var id := ""
	var bonus := 0.0
	for k: String in KIT_BONUS:
		if int(carried.get(k, 0)) > 0 and float(KIT_BONUS[k]) > bonus:
			id = k
			bonus = float(KIT_BONUS[k])
	return {"id": id, "bonus": bonus, "fire": int(carried.get("tinderbox", 0)) > 0, "tent": id == "tent_kit"}


## Needs.sleep quality of a night in this camp (0.5 bare ground .. 1.0 a good bed).
static func camp_quality(kit: Dictionary) -> float:
	return clampf(GROUND_QUALITY + float(kit.get("bonus", 0.0)) + (0.08 if bool(kit.get("fire", false)) else 0.0), 0.3, 1.0)


## "" when the player may camp: hour (0..23), distance to the nearest settlement as a multiple of its radius,
## inside a building, enemies near, kit.
static func camp_block_reason(hour: int, in_interior: bool, settlement_ratio: float, enemies_near: bool, kit: Dictionary) -> String:
	if in_interior:
		return "Step outside first."
	if String(kit.get("id", "")) == "":
		return "You have nothing to sleep on. A bedroll or a tent kit would do."
	if enemies_near:
		return "Not with enemies this close."
	if settlement_ratio < CAMP_SETTLEMENT_MARGIN:
		return "Too close to town. Take a bed at the inn."
	if hour < CAMP_FROM_HOUR and hour >= CAMP_UNTIL_HOUR:
		return "It is not dark yet. Camp after %d:00." % CAMP_FROM_HOUR
	return ""


## Chance that the night is disturbed. ctx: danger (0..100, ecology danger_at), road_dist (m), bandit_dist (m to the nearest
## bandit camp or hideout), tier ("kingdom"|"rural"|"frontier"|""), fire, tent.
static func camp_risk(ctx: Dictionary) -> float:
	var p := 0.05 + float(ctx.get("danger", 0.0)) * 0.004
	var bd := float(ctx.get("bandit_dist", 1.0e9))
	p += 0.10 if bd < 700.0 else (0.04 if bd < 1400.0 else 0.0)
	if float(ctx.get("road_dist", 1.0e9)) < 60.0:
		p += 0.04
	if bool(ctx.get("fire", false)):
		p *= 0.7
	if bool(ctx.get("tent", false)):
		p *= 0.85
	if String(ctx.get("tier", "")) == "kingdom":
		p *= 0.4
	return clampf(p, 0.02, 0.6)


## What happens: roll in [0, 1) twice (a, b). Returns {outcome: safe|visitor|ambush|thief, foe: bandits|beasts,
## species, hours: hours slept before it happens (0 = the whole night)}.
static func camp_outcome(ctx: Dictionary, roll_a: float, roll_b: float) -> Dictionary:
	var p := camp_risk(ctx)
	var out := {"outcome": "safe", "foe": "", "species": "", "hours": 0}
	if roll_a < p:
		var beasts := String(ctx.get("species", "")) != "" and float(ctx.get("danger", 0.0)) >= 12.0 \
				and float(ctx.get("bandit_dist", 1.0e9)) > 700.0
		if roll_b < 0.22 and not beasts:
			out["outcome"] = "thief"
		else:
			out["outcome"] = "ambush"
			out["foe"] = "beasts" if beasts else "bandits"
			out["species"] = String(ctx.get("species", "wolf")) if beasts else ""
		out["hours"] = 2 + int(roll_b * 4.0)
	elif roll_a < p + 0.14:
		out["outcome"] = "visitor"
	return out


## Hours a night's sleep lasts from `hour_f` (fractional hour of the day) to about 06:30, at least 1, at most 12.
static func night_hours(hour_f: float) -> float:
	var until_morning := fposmod(6.5 - hour_f, 24.0)
	return clampf(until_morning, 1.0, 12.0)


# --- road events -----------------------------------------------------------------------------------------

## What the road may show the player, as weights per kind. ctx: tier ("kingdom"|"rural"|"frontier"), danger (0..100),
## bandit_dist (m), caravans (count within ~900 m), near_town (bool: within 1.2 km of a settlement), hour (0..23).
static func road_weights(ctx: Dictionary) -> Dictionary:
	var tier := String(ctx.get("tier", "rural"))
	var danger := float(ctx.get("danger", 0.0))
	var hour := int(ctx.get("hour", 12))
	var night := hour >= 20 or hour < 5
	var w := {"news": 1.0, "camp": 0.55, "caravan": 0.6, "ambush": 0.0}
	if tier == "kingdom":
		w["news"] = 1.4
		w["caravan"] = 1.0
		w["camp"] = 0.2
	elif tier == "frontier":
		w["camp"] = 0.8
		w["caravan"] = 0.35
	if bool(ctx.get("near_town", false)):
		w["camp"] = float(w["camp"]) * 0.4
	w["caravan"] = float(w["caravan"]) + 0.8 * minf(float(ctx.get("caravans", 0)), 3.0)
	if tier != "kingdom":
		var bd := float(ctx.get("bandit_dist", 1.0e9))
		w["ambush"] = danger / 35.0 + (1.2 if bd < 700.0 else (0.5 if bd < 1400.0 else 0.0)) + (0.3 if tier == "frontier" else 0.0)
		if night:
			w["ambush"] = float(w["ambush"]) * 1.6
			w["camp"] = float(w["camp"]) * 1.3
			w["caravan"] = float(w["caravan"]) * 0.4
	return w


## Picks one kind from road_weights() with rolls in [0, 1), or "" when the roll falls in the quiet part: the chance of any
## event on a given check is ROAD_TICK_CHANCE per unit of total weight (so a calm road is mostly quiet).
static func pick_road_kind(weights: Dictionary, roll_gate: float, roll_pick: float) -> String:
	var total := 0.0
	for k: String in weights:
		total += float(weights[k])
	if total <= 0.0 or roll_gate > ROAD_TICK_CHANCE * total:
		return ""
	var at := roll_pick * total
	var acc := 0.0
	var last := ""
	for k: String in weights:
		if float(weights[k]) <= 0.0:
			continue
		last = k
		acc += float(weights[k])
		if at < acc:
			return k
	return last


## The gold a bandit ambush asks for.
static func ambush_toll(danger: float) -> int:
	return int(clampf(15.0 + danger * 1.5, 15.0, 120.0))
