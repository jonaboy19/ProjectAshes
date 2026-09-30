extends "res://scripts/realm/realm_module.gd"
## City life (docs/design/LIVING_WORLD.md L§4 inns, L§5 renting, L§7-11 jobs,
## L§12 quest boards, L§13/14 hidden work, L§15-17 guilds, L§35 districts at
## night, L§49 schedules create opportunities).
##
## Pure data, deterministic (seed = hash([WorldSim.SEED, tag, day, id])) and
## JSON-safe. Settlements are built lazily from WorldGen.settlements the first
## time something asks about them, so untouched towns cost nothing.
##
## Money rule: this module never touches the real purse. Everything that
## costs or pays (inn nights, rent, wages, guild dues) is added to a signed
## ledger; the game calls take_pending_gold() and applies the net amount.
## Results also carry "cost" for the UI, but callers must NOT deduct it again.
##
## No glowing markers: quest boards, hidden leads and opportunities are text
## only (no positions). Hidden careers never appear in jobs() or board().
##
## Optional cross-module hooks (all guarded with has_method): society
## (perceived_class, bounty, add_rep, rumours, learn, knows, log_failure) and
## hidden-career clues from crime (society calls note_activity).

const DISTRICTS := ["market", "craft", "noble", "temple", "docks", "slums"]
const RANKS := ["Applicant", "Member", "Journeyman", "Master", "Officer", "Leader"]
const JOB_HIRE_SCORE := 60.0
const JOB_MAX_PER_SETTLEMENT := 14
const BOARD_CAP := 3
const FIRE_ABSENCES := 3
const RENT_GRACE_DAYS := 7
const RUMOUR_LINES_MAX := 3

const INN_TIERS := {
	"cheap": {"price": [3, 6], "quality": [0.25, 0.5], "security": [0.1, 0.35], "class_min": 0, "rooms": [6, 12],
		"clientele": "dockhands, drovers and people who owe someone", "services": ["shared room", "stew", "gossip"],
		"refuses": []},
	"merchant": {"price": [14, 26], "quality": [0.6, 0.8], "security": [0.6, 0.85], "class_min": 2, "rooms": [4, 9],
		"clientele": "traders, factors and wealthy travellers", "services": ["private room", "safe storage", "stabling", "trade news"],
		"refuses": ["criminal_record"]},
	"noble": {"price": [60, 110], "quality": [0.9, 1.0], "security": [0.85, 1.0], "class_min": 3, "rooms": [3, 6],
		"clientele": "lords, envoys and their retinues", "services": ["suite", "safe storage", "bath", "court gossip"],
		"refuses": ["criminal_record", "rags"]},
}
const INN_NAMES_A := ["Gilded", "Rusty", "Sleeping", "Crooked", "Silver", "Weeping", "Broken", "Wayward", "Salted", "Pale"]
const INN_NAMES_B := ["Stag", "Anchor", "Lantern", "Kettle", "Crown", "Ferret", "Plough", "Bell", "Heron", "Barrel"]
const KIND_INNS := {
	"village": ["cheap"], "frontier_town": ["cheap", "merchant"],
	"town": ["cheap", "merchant", "cheap"], "castle": ["cheap", "merchant", "noble"],
}
const KIND_DISTRICTS := {
	"village": ["market", "craft"],
	"frontier_town": ["market", "craft", "slums"],
	"town": ["market", "craft", "temple", "slums"],
	"castle": ["market", "craft", "noble", "temple", "docks", "slums"],
}
const HOME_KINDS := {
	"room": {"rent": [9, 16], "class_min": 0},
	"apartment": {"rent": [24, 40], "class_min": 1},
	"house": {"rent": [55, 90], "class_min": 2},
	"farmhouse": {"rent": [35, 60], "class_min": 1},
	"workshop_home": {"rent": [45, 75], "class_min": 1},
	"estate": {"rent": [220, 380], "class_min": 3},
}
const KIND_HOMES := {
	"village": ["room", "farmhouse", "farmhouse", "house"],
	"frontier_town": ["room", "apartment", "house"],
	"town": ["room", "room", "apartment", "apartment", "house", "workshop_home"],
	"castle": ["room", "room", "apartment", "apartment", "house", "house", "workshop_home", "estate"],
}
const HOME_DISTRICT := {"room": "slums", "apartment": "craft", "house": "market", "farmhouse": "market",
	"workshop_home": "craft", "estate": "noble"}

## Job templates. req keys are player stat names (see DEFAULT_PLAYER).
const JOB_TPL := {
	"stall_hand": {"title": "Stall Hand", "district": "market", "roles": ["stallholder", "grocer"], "req": {}, "wage": 4, "style": "warm", "ladder": ["Stall Hand", "Salesman", "Stall Owner"], "shift": [8, 16], "via": "board"},
	"clerk": {"title": "Merchant's Clerk", "district": "market", "roles": ["merchant", "factor"], "req": {"literacy": 30}, "literate": true, "refs": 1, "wage": 9, "style": "shrewd", "ladder": ["Clerk", "Senior Clerk", "Factor"], "shift": [8, 17], "via": "word_of_mouth"},
	"caravan_guard": {"title": "Caravan Guard", "district": "market", "roles": ["caravan master"], "req": {"combat": 25}, "min_age": 17, "wage": 10, "style": "stern", "ladder": ["Guard", "Outrider", "Caravan Captain"], "shift": [7, 17], "via": "board", "war": true},
	"smith_apprentice": {"title": "Smith's Apprentice", "district": "craft", "roles": ["smith"], "req": {}, "wage": 3, "style": "stern", "ladder": ["Apprentice", "Journeyman", "Smith", "Master Smith"], "shift": [7, 15], "via": "board"},
	"smith": {"title": "Smith", "district": "craft", "roles": ["smith"], "req": {"craft": 30}, "apprentice": "smith_apprentice", "wage": 10, "style": "stern", "ladder": ["Journeyman", "Smith", "Master Smith"], "shift": [7, 15], "via": "shop"},
	"weaver": {"title": "Weaver", "district": "craft", "roles": ["weaver"], "req": {"craft": 15}, "apprentice": "stall_hand", "wage": 6, "style": "warm", "ladder": ["Spinner", "Weaver", "Master Weaver"], "shift": [8, 16], "via": "shop"},
	"dockhand": {"title": "Dockhand", "district": "docks", "roles": ["dock foreman"], "req": {"strength": 10}, "wage": 5, "style": "stern", "ladder": ["Dockhand", "Stevedore", "Foreman"], "shift": [6, 15], "via": "board"},
	"acolyte": {"title": "Temple Acolyte", "district": "temple", "roles": ["priest", "abbess"], "req": {"faith": 15, "literacy": 15}, "wage": 4, "style": "warm", "ladder": ["Acolyte", "Brother", "Priest"], "shift": [5, 13], "via": "guild"},
	"scribe": {"title": "Household Scribe", "district": "noble", "roles": ["steward", "lady"], "req": {"literacy": 40}, "literate": true, "class_min": 2, "refs": 1, "wage": 12, "style": "shrewd", "ladder": ["Copyist", "Scribe", "Secretary"], "shift": [9, 17], "via": "word_of_mouth"},
	"servant": {"title": "Household Servant", "district": "noble", "roles": ["steward"], "req": {"charm": 15}, "clean": true, "wage": 6, "style": "stern", "ladder": ["Servant", "Footman", "Steward"], "shift": [7, 19], "via": "shop"},
	"city_guard": {"title": "Guard Recruit", "district": "market", "roles": ["guard captain"], "req": {"combat": 30}, "min_age": 18, "clean": true, "citizen": true, "wage": 8, "style": "stern", "ladder": ["Guard Recruit", "Guard", "Veteran", "Sergeant", "Lieutenant", "Captain", "Commander"], "shift": [8, 16], "via": "board", "war": true},
	"day_labour": {"title": "Day Labourer", "district": "slums", "roles": ["gang boss", "widow"], "req": {}, "wage": 3, "style": "shrewd", "ladder": ["Labourer", "Ganghand"], "shift": [7, 15], "via": "word_of_mouth"},
	"harvest_hand": {"title": "Harvest Hand", "district": "market", "roles": ["farmer"], "req": {"strength": 8}, "wage": 5, "style": "warm", "ladder": ["Hand", "Reaper", "Reeve"], "shift": [6, 15], "via": "board", "season": ["summer", "autumn"]},
}
const STAT_REASON := {
	"craft": "You have never worked a forge or loom.", "combat": "You are not trained to fight.",
	"literacy": "You cannot read and write well enough.", "charm": "You lack the manner the post needs.",
	"faith": "You show little devotion.", "strength": "You are not strong enough for the work.",
	"magic": "You have no magical affinity.",
}
const DEFAULT_PLAYER := {"gold": 0, "class": 1, "age": 20, "combat": 0, "craft": 0, "literacy": 0, "charm": 10,
	"stealth": 0, "magic": 0, "faith": 0, "strength": 10, "refs": 0, "record": false, "citizen": true, "rep": 0}

const BOARD_KINDS := {
	"gate": ["escort", "missing traveller", "monster sighting"],
	"market": ["delivery", "trade job", "workers wanted"],
	"craft": ["commission", "apprentice wanted", "material run"],
	"noble": ["courier", "witness needed", "tutor wanted"],
	"temple": ["pilgrim escort", "relic search", "herb gathering"],
	"docks": ["cargo haul", "pier watch", "missing sailor"],
	"slums": ["unofficial job", "debt collection", "no questions asked"],
	"guild": ["special contract", "guild bounty"],
}
const LANDMARKS := ["old well", "tannery", "chandler's row", "dry fountain", "bell tower", "salt gate", "bakery with the green door",
	"dyers' steps", "cooper's yard", "split oak", "lamplit arch", "fishmonger's stair", "shuttered granary", "leaning shrine"]
const POSTER_ROLES := ["widow", "caravan master", "priest", "innkeeper", "smith", "steward", "captain", "herbalist", "merchant", "ferryman"]
const FIRST := ["Aldric", "Brenna", "Corin", "Dessa", "Edmar", "Fenna", "Gorm", "Hilda", "Ivo", "Jorun", "Kessa", "Lorn", "Mira", "Nils", "Orla", "Pell", "Quin", "Rhea", "Sten", "Tova"]
const LAST := ["Ashby", "Brook", "Crane", "Dunn", "Ember", "Fallow", "Gray", "Hale", "Ironside", "Marsh", "Nettle", "Oakes", "Pike", "Reed", "Stone", "Thorne"]

## Hidden careers: clue kinds -> points; stage thresholds; leads are hints only.
const HIDDEN := {
	"thief": {"clues": {"crime_theft": 2.0, "crime_pickpocket": 2.0, "night_slums": 1.0, "inn_gossip": 0.5, "crime_burglary": 2.0},
		"leads": ["Coins keep going missing near the cheap taverns, and nobody is angry about it.",
			"A boy in the slums says a woman pays well for fast fingers, if you know the whistle.",
			"A man in a grey hood asks whether you would care for more dangerous work than picking pockets."],
		"trial": {"stat": "stealth", "target": 35, "text": "Lift a sealed purse from a merchant's belt without being seen."},
		"ranks": ["Cutpurse", "Burglar", "Fence-runner", "Shadow"]},
	"smuggler": {"clues": {"explore_sewer": 2.0, "crime_smuggling": 3.0, "night_docks": 1.0, "inn_gossip": 0.5, "crime_black_market": 2.0},
		"leads": ["People disappear beneath the Old Quarter and come back with new boots.",
			"A drainage tunnel behind the tannery smells of pitch, not sewage, and has fresh boot marks.",
			"Someone in the tunnel asks whether you can keep quiet, carry a crate and not look inside."],
		"trial": {"stat": "charm", "target": 30, "text": "Carry a sealed crate past the gate watch without a flicker of nerves."},
		"ranks": ["Runner", "Boatman", "Fixer", "Harbour King"]},
	"assassin": {"clues": {"crime_murder": 2.0, "crime_violence": 1.0, "explore_sewer": 0.5, "underworld_rep": 1.0},
		"gate": {"smuggler": 2}, "min_stage_wait": 2,
		"leads": ["A guild clerk was found in the canal, and the constable stopped asking after two days.",
			"The smugglers go quiet whenever a certain quiet woman buys drinks.",
			"Over cold tea, someone asks what you would do for enough coin, and whether you can forget a name."],
		"trial": {"stat": "combat", "target": 50, "text": "Deal with a debtor before the bell rings, and leave no trail."},
		"ranks": ["Blade", "Knife", "Quiet Hand", "Nameless"]},
	"informant": {"clues": {"inn_gossip": 1.0, "overheard": 2.0, "learned_fact": 0.5, "night_slums": 0.5},
		"leads": ["The innkeeper always knows who owes what, and someone pays her for it.",
			"A tinker sells nothing and yet has been at every corner where something happened.",
			"A tinker offers a coin for every name and a secret you can prove."],
		"trial": {"stat": "literacy", "target": 20, "text": "Bring back one true secret, and prove you were nowhere near it."},
		"ranks": ["Ear", "Whisperer", "Broker", "Spymaster"]},
}
const HIDDEN_STAGES := [2.0, 5.0, 9.0]

const GUILD_KINDS := {
	"merchant": {"name": "Merchants' Guild", "entry": "payment", "fee": 60, "rep_min": 0, "refs": 1, "stat": "", "dues": 8},
	"hunters": {"name": "Hunters' Lodge", "entry": "demonstration", "fee": 10, "rep_min": 0, "refs": 0, "stat": "combat", "target": 20, "dues": 3},
	"adventurers": {"name": "Adventurers' Guild", "entry": "exam", "fee": 10, "rep_min": 0, "refs": 0, "stat": "combat", "target": 15, "dues": 2},
	"smiths": {"name": "Smiths' Guild", "entry": "apprenticeship", "fee": 20, "rep_min": 0, "refs": 0, "stat": "craft", "target": 5, "dues": 4},
	"healers": {"name": "Healers' Circle", "entry": "sponsorship", "fee": 25, "rep_min": 5, "refs": 1, "stat": "literacy", "target": 20, "dues": 4},
	"mages": {"name": "Mage Society", "entry": "exam", "fee": 120, "rep_min": 15, "refs": 1, "stat": "magic", "target": 30, "dues": 12},
}
const KIND_GUILDS := {
	"frontier_town": ["hunters", "adventurers"],
	"town": ["merchant", "hunters", "smiths", "healers"],
	"castle": ["merchant", "adventurers", "smiths", "healers", "mages"],
}
const GUILD_FACTIONS := [["old_guard", "Old Guard", "keep the ancient rules"], ["reformers", "Reformers", "open the guild to newcomers"],
	["purse", "Purse Faction", "raise dues and buy influence"]]

const SCHED_ROLES := {
	"corrupt_noble": {"actions": ["rob", "assassinate", "protect", "follow", "blackmail", "warn"], "text": "%s travels home alone along the %s every %s evening."},
	"gate_guard": {"actions": ["sneak past", "steal", "follow"], "text": "%s leaves the gate unwatched around %s to relieve himself, most nights."},
	"merchant": {"actions": ["rob", "protect", "follow", "trade"], "text": "%s carries the day's takings to the counting-house by the %s after dark."},
	"courier": {"actions": ["intercept", "protect", "follow", "warn"], "text": "%s rides a sealed pouch through the %s every %s morning."},
}
const DOW := ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

var player: Dictionary = DEFAULT_PLAYER.duplicate()
var pending_gold: int = 0
var _cities: Dictionary = {}       # str(sid) -> settlement life record
var _leases: Dictionary = {}       # home_id -> lease
var _stay: Dictionary = {}         # {} or active inn stay
var _job: Dictionary = {}          # current employment ({} if none)
var _history: Array = []           # employment history (also references)
var _blacklist: Dictionary = {}    # employer -> reason
var _emp_rep: float = 50.0
var _hidden: Dictionary = {}       # career -> {pts, stage, member, rank, done, trial_day, sid}
var _hidden_contracts: Array = []
var _guilds: Dictionary = {}       # gid -> guild
var _guilds_built: bool = false
var _seen: Dictionary = {}         # schedule id -> observations
var _last_day: int = 0
var _hour: int = 8
var _now: float = 0.0
var _at_war: bool = false
var _season: String = "spring"
var _near_sid: int = -1
var _log: Array = []               # recent news for UI (strings)
var _cache_sids: Array = []


func _init() -> void:
	pass


# ---------------------------------------------------------------- helpers

func _rng(tag: String, day: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, id])
	return r


func _sett(sid: int) -> Dictionary:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return WorldGen.settlements[sid]
	return {}


func _kind(sid: int) -> String:
	return String(_sett(sid).get("kind", "village"))


func _sname(sid: int) -> String:
	return String(_sett(sid).get("name", "the road"))


func _soc() -> RefCounted:
	if hub != null:
		var m: RefCounted = hub.mod("society")
		if m != null:
			return m
	return null


func _soc_call(method: String, args: Array, fallback: Variant = null) -> Variant:
	var s := _soc()
	if s != null and s.has_method(method):
		return s.callv(method, args)
	return fallback


func _pick(r: RandomNumberGenerator, arr: Array) -> Variant:
	return arr[r.randi() % arr.size()]


func _range(r: RandomNumberGenerator, pair: Array) -> float:
	return lerpf(float(pair[0]), float(pair[1]), r.randf())


func _npc_name(r: RandomNumberGenerator) -> String:
	return "%s %s" % [_pick(r, FIRST), _pick(r, LAST)]


func _gold() -> int:
	return int(player.get("gold", 0)) + pending_gold


func set_player(d: Dictionary) -> void:
	for k: String in d:
		player[k] = d[k]


func player_stats() -> Dictionary:
	return player.duplicate()


func _class() -> int:
	var c: Variant = _soc_call("perceived_class", [], null)
	if c != null:
		return int(c)
	return int(player.get("class", 1))


func _bounty(sid: int) -> int:
	var b: Variant = _soc_call("bounty", [sid], null)
	if b != null:
		return int(b)
	return int(player.get("bounty", 0))


func _has_record() -> bool:
	return bool(player.get("record", false)) or _bounty(-1) > 0


func take_pending_gold() -> int:
	var g := pending_gold
	pending_gold = 0
	return g


func news() -> Array:
	return _log.duplicate()


func _say(msgs: Array, text: String) -> void:
	msgs.append(text)
	_log.append(text)
	if _log.size() > 20:
		_log.pop_front()


func _sync(ctx: Dictionary) -> void:
	_now = float(ctx.get("abs_hours", _now))
	_at_war = bool(ctx.get("at_war", false))
	_season = String(ctx.get("season", _season))
	if ctx.has("gold"):
		player["gold"] = int(ctx["gold"])
	if ctx.get("stats") is Dictionary:
		for k: String in ctx["stats"]:
			player[k] = ctx["stats"][k]
	var pp: Variant = ctx.get("player_pos")
	if pp is Vector2 or pp is Vector3:
		var p2: Vector2 = Vector2(pp.x, pp.z) if pp is Vector3 else pp
		_near_sid = _nearest(p2)


func _nearest(p: Vector2) -> int:
	var best := -1
	var bd := INF
	for s: Dictionary in WorldGen.settlements:
		var d: float = (s["pos"] as Vector2).distance_squared_to(p)
		if d < bd:
			bd = d
			best = int(s["id"])
	if best >= 0 and bd > pow(float(_sett(best).get("radius", 100.0)) * 2.5, 2.0):
		return -1
	return best


func near_settlement() -> int:
	return _near_sid


# --------------------------------------------------------- settlement build

func districts(sid: int) -> Array:
	var d: Array = (KIND_DISTRICTS.get(_kind(sid), ["market"]) as Array).duplicate()
	return d


func _ensure(sid: int) -> Dictionary:
	var key := str(sid)
	if _cities.has(key):
		return _cities[key]
	var c := {"sid": sid, "districts": districts(sid), "inns": [], "homes": [], "jobs": [], "next_job": 0,
		"boards": {}, "next_post": 0, "sched": [], "landmarks": [], "last_refresh": -1}
	var r := _rng("city", 0, sid)
	var lm: Array = LANDMARKS.duplicate()
	for i in lm.size():
		var j := r.randi() % lm.size()
		var t: Variant = lm[i]
		lm[i] = lm[j]
		lm[j] = t
	c["landmarks"] = lm.slice(0, 5)
	var kind := _kind(sid)
	var tiers: Array = KIND_INNS.get(kind, ["cheap"])
	for i in tiers.size():
		var tier: String = tiers[i]
		var tt: Dictionary = INN_TIERS[tier]
		var ir := _rng("inn", 0, [sid, i])
		var dist := "market"
		if tier == "cheap":
			dist = "slums" if (c["districts"] as Array).has("slums") else "market"
		elif tier == "noble":
			dist = "noble"
		c["inns"].append({"id": "inn:%d:%d" % [sid, i], "name": "The %s %s" % [_pick(ir, INN_NAMES_A), _pick(ir, INN_NAMES_B)],
			"tier": tier, "district": dist, "price": int(round(_range(ir, tt["price"]))), "quality": snappedf(_range(ir, tt["quality"]), 0.01),
			"security": snappedf(_range(ir, tt["security"]), 0.01), "class_min": int(tt["class_min"]),
			"rooms": int(round(_range(ir, tt["rooms"]))), "clientele": tt["clientele"], "services": (tt["services"] as Array).duplicate(),
			"refuses": (tt["refuses"] as Array).duplicate()})
	var homes: Array = KIND_HOMES.get(kind, ["room"])
	for i in homes.size():
		var hk: String = homes[i]
		var hr := _rng("home", 0, [sid, i])
		var ht: Dictionary = HOME_KINDS[hk]
		var hd: String = HOME_DISTRICT[hk]
		if not (c["districts"] as Array).has(hd):
			hd = (c["districts"] as Array)[0]
		var rent := int(round(_range(hr, ht["rent"])))
		c["homes"].append({"id": "home:%d:%d" % [sid, i], "sid": sid, "kind": hk, "district": hd, "rent": rent,
			"deposit": rent, "class_min": int(ht["class_min"])})
	for d: String in c["districts"]:
		c["boards"][d] = []
	c["boards"]["gate"] = []
	if KIND_GUILDS.has(kind):
		c["boards"]["guild"] = []
	_build_sched(c, sid)
	_cities[key] = c
	_refresh_city(c, _last_day)
	return c


func _build_sched(c: Dictionary, sid: int) -> void:
	var r := _rng("sched", 0, sid)
	var roles: Array = ["corrupt_noble", "gate_guard", "merchant", "courier"]
	var n := 3 if _kind(sid) == "village" else 4
	for i in n:
		var role: String = roles[i % roles.size()]
		var lm: Array = c["landmarks"]
		var e := {"id": "sch:%d:%d" % [sid, i], "role": role, "npc": _npc_name(r), "dow": -1, "from": 0, "to": 0,
			"place": String(lm[r.randi() % lm.size()])}
		match role:
			"corrupt_noble":
				e["dow"] = r.randi() % 7
				e["from"] = 19
				e["to"] = 22
				e["district"] = "noble" if (c["districts"] as Array).has("noble") else "market"
			"gate_guard":
				e["from"] = 1 + r.randi() % 3
				e["to"] = e["from"] + 1
				e["district"] = "market"
			"merchant":
				e["from"] = 20
				e["to"] = 23
				e["district"] = "market"
			"courier":
				e["dow"] = r.randi() % 7
				e["from"] = 6
				e["to"] = 8
				e["district"] = "market"
		c["sched"].append(e)


# --------------------------------------------------------------- L§4 inns

func inns(sid: int) -> Array:
	var c := _ensure(sid)
	var out: Array = []
	for inn: Dictionary in c["inns"]:
		var o: Dictionary = inn.duplicate(true)
		var r := _rng("occ", _last_day, inn["id"])
		o["taken"] = int(float(inn["rooms"]) * (0.2 + 0.7 * r.randf()))
		o["free"] = maxi(0, int(inn["rooms"]) - int(o["taken"]))
		o["price_now"] = price_now(inn)
		o["refusal"] = stay_refusal(inn)
		out.append(o)
	return out


func price_now(inn: Dictionary) -> int:
	var p := float(inn["price"])
	if _at_war:
		p *= 1.15
	return maxi(1, int(round(p)))


func stay_refusal(inn: Dictionary) -> String:
	var cl := _class()
	if cl < int(inn["class_min"]) and String(inn["tier"]) != "cheap":
		return "The keeper looks you over and says there are no rooms for the likes of you."
	if (inn["refuses"] as Array).has("criminal_record") and _has_record():
		return "The keeper has heard your name, and it is not welcome here."
	if (inn["refuses"] as Array).has("rags") and cl < 2:
		return "You are not dressed for this house."
	return ""


func rent_room(sid: int, nights: int, inn_id: String = "") -> Dictionary:
	if nights < 1:
		return {"ok": false, "reason": "How many nights?", "cost": 0}
	var c := _ensure(sid)
	var chosen: Dictionary = {}
	for inn: Dictionary in c["inns"]:
		if inn_id != "" and String(inn["id"]) != inn_id:
			continue
		if stay_refusal(inn) != "":
			if inn_id != "":
				return {"ok": false, "reason": stay_refusal(inn), "cost": 0}
			continue
		if chosen.is_empty() or int(inn["price"]) < int(chosen["price"]):
			chosen = inn
	if chosen.is_empty():
		return {"ok": false, "reason": "No inn here will take you.", "cost": 0}
	var occ := inns(sid)
	for o: Dictionary in occ:
		if o["id"] == chosen["id"] and int(o["free"]) <= 0:
			return {"ok": false, "reason": "The inn is full tonight.", "cost": 0}
	var cost := price_now(chosen) * nights
	if nights >= 7:
		cost = int(round(cost * 0.9))
	if _gold() < cost:
		return {"ok": false, "reason": "You cannot afford %d gold." % cost, "cost": cost}
	pending_gold -= cost
	_stay = {"inn": chosen["id"], "sid": sid, "from": _now, "until": _now + nights * 24.0,
		"quality": float(chosen["quality"]), "security": float(chosen["security"]), "tier": chosen["tier"], "nights": nights}
	return {"ok": true, "reason": "", "cost": cost, "inn": chosen["id"], "until_hour": _stay["until"]}


func stay() -> Dictionary:
	return _stay.duplicate(true)


func rest_quality() -> float:
	if _stay.is_empty():
		return 0.15
	return float(_stay["quality"])


func inn_rumours(sid: int, count: int = RUMOUR_LINES_MAX) -> Array:
	var c := _ensure(sid)
	var out: Array = []
	var heard: Variant = _soc_call("rumours", [sid], [])
	if heard is Array:
		for t: Variant in heard:
			if out.size() < count:
				out.append(String(t))
	var r := _rng("gossip", _last_day, sid)
	var flavour := ["Prices at the %s have gone up again.", "Someone was seen slipping into the alley by the %s at night.",
		"The watch changes guard early near the %s now.", "A stranger has been asking about the %s."]
	while out.size() < count:
		out.append(String(_pick(r, flavour)) % String(_pick(r, c["landmarks"])))
	# Cheap inns leak underworld gossip: a slow trickle toward hidden leads.
	for inn: Dictionary in c["inns"]:
		if inn["tier"] == "cheap" and _rng("gleak", _last_day, sid).randf() < 0.35:
			note_activity("inn_gossip", sid, 1.0)
			break
	return out


# ----------------------------------------------------------- L§5 renting

func homes(sid: int) -> Array:
	var c := _ensure(sid)
	var out: Array = []
	for h: Dictionary in c["homes"]:
		var o: Dictionary = h.duplicate()
		o["leased"] = _leases.has(h["id"]) and String(_leases[h["id"]]["status"]) != "evicted"
		o["refusal"] = _home_refusal(h)
		out.append(o)
	return out


func _find_home(home_id: String) -> Dictionary:
	var parts := home_id.split(":")
	if parts.size() != 3:
		return {}
	var c := _ensure(int(parts[1]))
	for h: Dictionary in c["homes"]:
		if h["id"] == home_id:
			return h
	return {}


func _home_refusal(h: Dictionary) -> String:
	if _class() < int(h["class_min"]):
		return "The landlord wants a tenant of better standing."
	if _has_record() and int(h["class_min"]) >= 2:
		return "The landlord asks about your record and shuts the door."
	if _blacklist.has("landlord:" + str(h["sid"])):
		return "You were thrown out of this district's leases before."
	return ""


func lease(home_id: String, weeks: int = 1) -> Dictionary:
	var h := _find_home(home_id)
	if h.is_empty():
		return {"ok": false, "reason": "No such home.", "cost": 0}
	if _leases.has(home_id) and String(_leases[home_id]["status"]) != "evicted":
		return {"ok": false, "reason": "You already hold this lease.", "cost": 0}
	var why := _home_refusal(h)
	if why != "":
		return {"ok": false, "reason": why, "cost": 0}
	var cost := int(h["deposit"]) + int(h["rent"]) * maxi(1, weeks)
	if _gold() < cost:
		return {"ok": false, "reason": "You need %d gold (deposit plus rent)." % cost, "cost": cost}
	pending_gold -= cost
	_leases[home_id] = {"home": home_id, "sid": int(h["sid"]), "kind": h["kind"], "district": h["district"], "rent": int(h["rent"]),
		"paid_until": _last_day + 7 * maxi(1, weeks), "arrears": 0.0, "status": "active", "residents": [], "belongings_kept": true,
		"start_day": _last_day, "auto_pay": true}
	return {"ok": true, "reason": "", "cost": cost, "paid_until_day": _leases[home_id]["paid_until"]}


func pay_rent(home_id: String, weeks: int = 1) -> Dictionary:
	if not _leases.has(home_id):
		return {"ok": false, "reason": "No lease.", "cost": 0}
	var l: Dictionary = _leases[home_id]
	var cost := int(l["rent"]) * maxi(1, weeks) + int(ceil(float(l["arrears"])))
	if _gold() < cost:
		return {"ok": false, "reason": "You cannot cover %d gold." % cost, "cost": cost}
	pending_gold -= cost
	l["paid_until"] = maxi(int(l["paid_until"]), _last_day) + 7 * maxi(1, weeks)
	l["arrears"] = 0.0
	if String(l["status"]) == "overdue":
		l["status"] = "active"
	return {"ok": true, "reason": "", "cost": cost, "paid_until_day": l["paid_until"]}


func end_lease(home_id: String) -> bool:
	if not _leases.has(home_id):
		return false
	_leases.erase(home_id)
	return true


func add_resident(home_id: String, who: String) -> bool:
	if not _leases.has(home_id) or String(_leases[home_id]["status"]) == "evicted":
		return false
	var res: Array = _leases[home_id]["residents"]
	if not res.has(who):
		res.append(who)
	return true


func leases() -> Array:
	var out: Array = []
	for k: String in _leases:
		out.append((_leases[k] as Dictionary).duplicate(true))
	return out


func _tick_leases(day: int, msgs: Array) -> void:
	for k: String in _leases:
		var l: Dictionary = _leases[k]
		if String(l["status"]) == "evicted":
			continue
		var due: int = int(l["paid_until"])
		if day < due:
			if day == due - 1:
				_say(msgs, "Rent is due tomorrow on your %s in %s." % [String(l["kind"]).replace("_", " "), _sname(int(l["sid"]))])
			continue
		if bool(l.get("auto_pay", false)) and _gold() >= int(l["rent"]):
			pending_gold -= int(l["rent"])
			l["paid_until"] = day + 7
			_say(msgs, "Rent of %d gold paid on your %s in %s." % [int(l["rent"]), String(l["kind"]).replace("_", " "), _sname(int(l["sid"]))])
			continue
		l["status"] = "overdue"
		l["arrears"] = float(l["arrears"]) + float(l["rent"]) / 7.0
		if day - due >= RENT_GRACE_DAYS:
			_evict(l, msgs)


func _evict(l: Dictionary, msgs: Array) -> void:
	l["status"] = "evicted"
	l["belongings_kept"] = false
	_blacklist["landlord:" + str(l["sid"])] = "evicted"
	_emp_rep = maxf(0.0, _emp_rep - 5.0)
	_say(msgs, "The landlord in %s has changed the locks. Your belongings are in the yard." % _sname(int(l["sid"])))
	_soc_call("add_rep", ["city:%d" % int(l["sid"]), -3.0, "eviction"])
	_soc_call("log_failure", ["evicted", "Evicted from a %s in %s. Cheaper rooms lie in the slums, among people who ask few questions." % [String(l["kind"]).replace("_", " "), _sname(int(l["sid"]))], int(l["sid"])])


# ------------------------------------------------------------- L§7-11 jobs

func _refresh_city(c: Dictionary, day: int) -> void:
	var sid: int = int(c["sid"])
	# Expire and fill openings; boards likewise.
	var jobs: Array = c["jobs"]
	for i in range(jobs.size() - 1, -1, -1):
		if int(jobs[i]["expires"]) <= day:
			jobs.remove_at(i)
	var cap: int = int({"village": 4, "frontier_town": 6, "town": 9, "castle": 14}.get(_kind(sid), 4))
	cap = mini(cap, JOB_MAX_PER_SETTLEMENT)
	var r := _rng("jobs", day, sid)
	var tpl_ids: Array = JOB_TPL.keys()
	var guard := 0
	while jobs.size() < cap and guard < 12:
		guard += 1
		var tid: String = tpl_ids[r.randi() % tpl_ids.size()]
		var t: Dictionary = JOB_TPL[tid]
		if not (c["districts"] as Array).has(t["district"]):
			continue
		if t.has("season") and not (t["season"] as Array).has(_season):
			continue
		if t.get("war", false) and not _at_war and r.randf() < 0.5:
			continue
		var employer := _npc_name(r)
		var via := String(t.get("via", "board"))
		var id := "job:%d:%d" % [sid, int(c["next_job"])]
		c["next_job"] = int(c["next_job"]) + 1
		jobs.append({"id": id, "sid": sid, "district": t["district"], "tpl": tid, "title": t["title"], "employer": employer,
			"role": _pick(r, t["roles"]), "wage": int(round(float(t["wage"]) * (1.15 if _at_war and t.get("war", false) else 1.0))),
			"via": via, "posted": day, "expires": day + 6 + r.randi() % 10})
	# Boards.
	var boards: Dictionary = c["boards"]
	for bd: String in boards:
		var arr: Array = boards[bd]
		for i in range(arr.size() - 1, -1, -1):
			if int(arr[i]["expires"]) <= day or arr[i]["taken"]:
				arr.remove_at(i)
		var want := BOARD_CAP if bd == "gate" else 2
		if _kind(sid) == "village":
			want = 2 if bd == "gate" else 1
		var br := _rng("board", day, [sid, bd])
		var tries := 0
		while arr.size() < want and tries < 6:
			tries += 1
			arr.append(_make_post(c, sid, bd, br))
	c["last_refresh"] = day


func _make_post(c: Dictionary, sid: int, bd: String, r: RandomNumberGenerator) -> Dictionary:
	var kinds: Array = BOARD_KINDS[bd]
	var kind: String = kinds[r.randi() % kinds.size()]
	var lm: Array = c["landmarks"]
	var a: String = lm[r.randi() % lm.size()]
	var b: String = lm[r.randi() % lm.size()]
	var poster := {"name": _npc_name(r), "role": _pick(r, POSTER_ROLES)}
	var danger := r.randi() % 4
	var reward := int(round((6.0 + danger * 9.0 + r.randf() * 8.0) * (1.2 if _at_war else 1.0)))
	var text := "%s wants a %s. Ask for %s at the house past the %s, on the street behind the %s." % [
		String(poster["role"]).capitalize(), kind, poster["name"], a, b]
	if bd == "slums":
		text = "No questions. %s pays for a %s. Look for the door behind the %s, knock twice." % [poster["name"], kind, a]
	if bd == "guild":
		text = "Guild seal: %s. Speak to %s at the hall." % [kind, poster["name"]]
	var pid := int(c["next_post"])
	c["next_post"] = pid + 1
	return {"id": "post:%d:%d" % [sid, pid], "sid": sid, "district": bd, "kind": kind, "poster": poster, "text": text,
		"reward": reward, "danger": danger, "posted": _last_day, "expires": _last_day + 4 + r.randi() % 8, "taken": false,
		"min_rank": 1 if bd == "guild" else 0, "teaches": "place:%d:%s" % [sid, a]}


func jobs(sid: int) -> Array:
	var c := _ensure(sid)
	var out: Array = []
	for j: Dictionary in c["jobs"]:
		var o: Dictionary = j.duplicate(true)
		var t: Dictionary = JOB_TPL[j["tpl"]]
		o["req"] = (t["req"] as Dictionary).duplicate()
		o["refs"] = int(t.get("refs", 0))
		o["class_min"] = int(t.get("class_min", 0))
		o["min_age"] = int(t.get("min_age", 0))
		o["clean"] = bool(t.get("clean", false))
		o["shift"] = (t["shift"] as Array).duplicate()
		o["visible"] = String(j["via"]) != "word_of_mouth" or _refs() > 0 or bool(_soc_call("knows", ["contact:%d" % sid], false))
		o["blacklisted"] = _blacklist.has(j["employer"])
		out.append(o)
	return out


func _find_job(job_id: String) -> Dictionary:
	var parts := job_id.split(":")
	if parts.size() != 3:
		return {}
	var c := _ensure(int(parts[1]))
	for j: Dictionary in c["jobs"]:
		if j["id"] == job_id:
			return j
	return {}


func _refs() -> int:
	var n := int(player.get("refs", 0))
	for h: Dictionary in _history:
		if h.get("reference", false):
			n += 1
	return n


func _qual(t: Dictionary) -> Dictionary:
	## Returns {score 0..50, missing: [stat], hard: [reason]}.
	var missing: Array = []
	var hard: Array = []
	var ratio_sum := 0.0
	var req: Dictionary = t["req"]
	for k: String in req:
		var have := float(player.get(k, 0))
		var need := float(req[k])
		ratio_sum += minf(1.0, have / need)
		if have < need * 0.5:
			missing.append(k)
	var score := 50.0 if req.is_empty() else 50.0 * ratio_sum / float(req.size())
	if int(player.get("age", 20)) < int(t.get("min_age", 0)):
		hard.append("You are too young for the post.")
	if bool(t.get("clean", false)) and _has_record():
		hard.append("They want a clean record and yours is not.")
	if bool(t.get("citizen", false)) and not bool(player.get("citizen", true)):
		hard.append("Only citizens may serve.")
	if _class() < int(t.get("class_min", 0)):
		hard.append("They want someone of better standing.")
	if int(t.get("refs", 0)) > _refs():
		hard.append("They ask who will vouch for you, and nobody will.")
	if bool(t.get("literate", false)) and float(player.get("literacy", 0)) < 15.0:
		hard.append("You cannot read well enough.")
	return {"score": score, "missing": missing, "hard": hard}


func interview_questions(job_id: String) -> Array:
	var j := _find_job(job_id)
	if j.is_empty():
		return []
	var t: Dictionary = JOB_TPL[j["tpl"]]
	var trade := String(t["title"]).to_lower()
	return [
		{"id": "experience", "text": "Have you done %s work before?" % trade, "options": [
			"Yes, for years.", "A little, but I learn fast.", "No, but I will work hard."]},
		{"id": "attitude", "text": "What do I get if I hire you?", "options": [
			"I turn up early, every day.", "Honest work, if the pay is fair.", "I do what I am told."]},
		{"id": "reason", "text": "Why this job?", "options": [
			"For the coin.", "I want to learn the trade.", "%s sent me." % _pick(_rng("ref", 0, job_id), FIRST)]},
	]


func _answer_score(qid: String, opt: int, style: String, q: Dictionary, notes: Array) -> float:
	match qid:
		"experience":
			var truth := not (q["missing"] as Array).has("craft") and (q["score"] as float) >= 35.0
			if opt == 0:
				if truth:
					return 10.0
				notes.append("You claimed experience the master could see you lacked.")
				return -15.0
			if opt == 1:
				return 5.0 if style != "stern" else 3.0
			return 4.0 if style == "warm" else 1.0
		"attitude":
			if opt == 0:
				if _emp_rep >= 50.0:
					return 9.0
				notes.append("Word of your habits has reached this street.")
				return -6.0
			if opt == 1:
				return 5.0 if style == "shrewd" else (1.0 if style == "stern" else 3.0)
			return 7.0 if style == "stern" else 2.0
		"reason":
			if opt == 0:
				return 5.0 if style == "shrewd" else 0.0
			if opt == 1:
				return 8.0 if style == "warm" else 5.0
			if _refs() > 0:
				return 9.0
			notes.append("The name you gave meant nothing to them.")
			return -12.0
	return 0.0


func apply(job_id: String, answers: Array = []) -> Dictionary:
	var j := _find_job(job_id)
	if j.is_empty():
		return {"ok": false, "hired": false, "score": 0.0, "reason": "The post has been filled.", "missing": []}
	if not _job.is_empty():
		return {"ok": false, "hired": false, "score": 0.0, "reason": "You already have a job; resign first.", "missing": []}
	if _blacklist.has(j["employer"]):
		return {"ok": true, "hired": false, "score": 0.0, "reason": "%s remembers how you left last time." % j["employer"], "missing": []}
	var t: Dictionary = JOB_TPL[j["tpl"]]
	var q := _qual(t)
	var res := {"ok": true, "hired": false, "score": 0.0, "reason": "", "missing": q["missing"], "alternative": "", "notes": []}
	if not (q["hard"] as Array).is_empty():
		res["reason"] = String((q["hard"] as Array)[0])
		return res
	if not (q["missing"] as Array).is_empty():
		var what := String(STAT_REASON.get((q["missing"] as Array)[0], "You lack the skills."))
		res["reason"] = what
		if t.has("apprentice"):
			res["alternative"] = t["apprentice"]
			res["reason"] = what + " They would take you on as an apprentice instead."
		return res
	var notes: Array = res["notes"]
	var score: float = q["score"]
	var questions := interview_questions(job_id)
	for i in questions.size():
		if i < answers.size():
			score += _answer_score(String(questions[i]["id"]), int(answers[i]), String(t["style"]), q, notes)
	score += float(player.get("charm", 10)) * 0.2 + (_emp_rep - 50.0) * 0.15 + float(player.get("rep", 0)) * 0.05
	score += _rng("interview", _last_day, job_id).randf_range(-4.0, 4.0)
	res["score"] = snappedf(score, 0.1)
	if score >= JOB_HIRE_SCORE:
		res["hired"] = true
		res["reason"] = "%s shakes your hand. You start at the next shift." % j["employer"]
		_hire(j, t)
	else:
		var why := "They found someone steadier." if notes.is_empty() else String(notes[0])
		if answers.is_empty():
			why = "You said nothing to persuade them."
		res["reason"] = why
	return res


func _hire(j: Dictionary, t: Dictionary) -> void:
	var c := _ensure(int(j["sid"]))
	(c["jobs"] as Array).erase(j)
	_job = {"job": j["id"], "tpl": j["tpl"], "sid": int(j["sid"]), "title": (t["ladder"] as Array)[0], "employer": j["employer"],
		"wage": int(j["wage"]), "rank": 0, "ladder": (t["ladder"] as Array).duplicate(), "hired": _last_day, "since_rank": _last_day,
		"shift": (t["shift"] as Array).duplicate(), "performance": 60.0, "merit": 0.0, "missed": 0, "recent_missed_day": _last_day,
		"worked_today": false, "days_worked": 0, "owed": 0, "leave_until": -1}


func job() -> Dictionary:
	return _job.duplicate(true)


func is_employed() -> bool:
	return not _job.is_empty()


func employment_reputation() -> float:
	return _emp_rep


func work_shift(quality: float = 1.0) -> Dictionary:
	if _job.is_empty():
		return {"ok": false, "reason": "You have no job."}
	if int(_job["leave_until"]) > _last_day:
		return {"ok": false, "reason": "You are on sick leave."}
	var s: Array = _job["shift"]
	if _hour < int(s[0]) or _hour >= int(s[1]):
		return {"ok": false, "reason": "Your shift is %d:00 to %d:00." % [int(s[0]), int(s[1])]}
	if bool(_job["worked_today"]):
		return {"ok": true, "reason": "Already clocked in today."}
	_job["worked_today"] = true
	_job["days_worked"] = int(_job["days_worked"]) + 1
	_job["performance"] = minf(100.0, float(_job["performance"]) + 3.0 * clampf(quality, 0.0, 1.5) - (2.0 if quality < 0.4 else 0.0))
	if _hour > int(s[0]) + 1:
		_job["performance"] = float(_job["performance"]) - 1.5   # late
	_job["owed"] = int(_job["owed"]) + int(round(float(_job["wage"]) * clampf(quality, 0.3, 1.2)))
	return {"ok": true, "reason": ""}


func accomplish(kind: String, amount: float = 1.0) -> void:
	if _job.is_empty():
		return
	_job["merit"] = float(_job["merit"]) + amount
	_job["performance"] = minf(100.0, float(_job["performance"]) + amount * 1.5)


func injure(days: int) -> void:
	if not _job.is_empty():
		_job["leave_until"] = _last_day + days
		_job["long_leave"] = days > 14


func caught_stealing() -> Array:
	var m: Array = []
	if not _job.is_empty():
		_fire("stealing", m)
	return m


func insubordinate() -> Array:
	var m: Array = []
	if not _job.is_empty():
		_job["performance"] = float(_job["performance"]) - 30.0
		_say(m, "%s bristles at your tone. One more time and you are out." % _job["employer"])
		if float(_job["performance"]) < 20.0:
			_fire("insubordination", m)
	return m


func resign() -> Array:
	var m: Array = []
	if _job.is_empty():
		return m
	var good := float(_job["performance"]) >= 60.0
	_history.append({"employer": _job["employer"], "sid": _job["sid"], "title": _job["title"], "ended": _last_day, "reason": "resigned",
		"reference": good})
	_emp_rep = clampf(_emp_rep + (3.0 if good else -4.0), 0.0, 100.0)
	_say(m, "You leave your post as %s. %s" % [_job["title"], "They promise a good word." if good else "Nobody says goodbye."])
	_job = {}
	return m


func _fire(reason: String, msgs: Array) -> void:
	var sid: int = int(_job["sid"])
	var text: String = {"absence": "You were dismissed for missing too many shifts.", "poor_work": "You were dismissed for poor work.",
		"stealing": "You were caught stealing and thrown out.", "insubordination": "You were dismissed for insubordination.",
		"injury": "You were let go while injured; the post had to be filled."}.get(reason, "You were dismissed.")
	_say(msgs, String(text))
	var cost: float = {"stealing": 40.0, "insubordination": 15.0, "absence": 15.0, "poor_work": 12.0, "injury": 2.0}.get(reason, 10.0)
	_emp_rep = clampf(_emp_rep - cost, 0.0, 100.0)
	if reason != "injury":
		_blacklist[_job["employer"]] = reason
	_history.append({"employer": _job["employer"], "sid": sid, "title": _job["title"], "ended": _last_day, "reason": reason, "reference": false})
	var rep_hit := -10.0 if reason == "stealing" else (-1.0 if reason == "injury" else -3.0)
	_soc_call("add_rep", ["city:%d" % sid, rep_hit, "fired:" + reason])
	if reason == "stealing":
		_soc_call("add_crim_rep", ["city:%d" % sid, 2.0, "theft"])
	_soc_call("log_failure", ["fired", "Fired from your post in %s (%s). With no pay the rent will be hard; cheaper streets and crueller company wait." % [_sname(sid), reason], sid])
	_job = {}


func job_history() -> Array:
	return _history.duplicate(true)


func _tick_job_day(day: int, msgs: Array) -> void:
	if _job.is_empty():
		return
	var j := _job
	if int(j["leave_until"]) > day:
		if bool(j.get("long_leave", false)):
			_fire("injury", msgs)
		j["worked_today"] = false
		return
	var off_day := day % 7 == 0
	if bool(j["worked_today"]):
		pending_gold += int(j["owed"])
		j["owed"] = 0
		j["merit"] = float(j["merit"]) + 0.5
	elif not off_day:
		j["missed"] = int(j["missed"]) + 1
		j["performance"] = float(j["performance"]) - 6.0
		_say(msgs, "%s noted your absence today." % j["employer"])
	if day - int(j["recent_missed_day"]) >= 7:
		j["recent_missed_day"] = day
		j["missed"] = maxi(0, int(j["missed"]) - 1)
	j["worked_today"] = false
	if int(j["missed"]) >= FIRE_ABSENCES:
		_fire("absence", msgs)
		return
	if float(j["performance"]) < 20.0:
		_fire("poor_work", msgs)
		return
	_maybe_promote(day, msgs)


func _maybe_promote(day: int, msgs: Array) -> void:
	var rank: int = int(_job["rank"])
	var ladder: Array = _job["ladder"]
	if rank + 1 >= ladder.size():
		return
	if float(_job["merit"]) >= 6.0 * float(rank + 1) and float(_job["performance"]) >= 65.0 and day - int(_job["since_rank"]) >= 10:
		_job["rank"] = rank + 1
		_job["title"] = ladder[rank + 1]
		_job["since_rank"] = day
		_job["wage"] = int(round(float(_job["wage"]) * 1.3))
		_emp_rep = clampf(_emp_rep + 5.0, 0.0, 100.0)
		_say(msgs, "%s promotes you to %s for your work, not your years." % [_job["employer"], _job["title"]])


# ---------------------------------------------------------- L§12 boards

func board_districts(sid: int) -> Array:
	return (_ensure(sid)["boards"] as Dictionary).keys()


func board(sid: int, district: String) -> Array:
	var c := _ensure(sid)
	var out: Array = []
	if not (c["boards"] as Dictionary).has(district):
		return out
	for p: Dictionary in c["boards"][district]:
		if not p["taken"]:
			out.append(p.duplicate(true))
	return out


func take_posting(post_id: String) -> Dictionary:
	var parts := post_id.split(":")
	if parts.size() != 3:
		return {"ok": false, "reason": "Unknown posting."}
	var c := _ensure(int(parts[1]))
	for bd: String in c["boards"]:
		for p: Dictionary in c["boards"][bd]:
			if p["id"] == post_id and not p["taken"]:
				if int(p["min_rank"]) > 0 and not _in_any_guild():
					return {"ok": false, "reason": "The clerk asks for your guild seal."}
				p["taken"] = true
				_soc_call("learn", [String(p["teaches"])])
				return {"ok": true, "reason": "", "text": p["text"], "reward": p["reward"], "danger": p["danger"]}
	return {"ok": false, "reason": "Someone else took it."}


func _in_any_guild() -> bool:
	for gid: String in _guilds:
		if int(_guilds[gid]["player"]["rank"]) >= 0:
			return true
	return false


# ------------------------------------------------- L§13/14 hidden careers

func _hid(career: String) -> Dictionary:
	if not _hidden.has(career):
		_hidden[career] = {"pts": 0.0, "stage": 0, "member": false, "rank": 0, "done": 0, "trial_day": -100, "sid": -1}
	return _hidden[career]


func note_activity(kind: String, sid: int, amount: float = 1.0) -> void:
	## Exploration, crime and reputation feed hidden careers. Never offered.
	for career: String in HIDDEN:
		var def: Dictionary = HIDDEN[career]
		var w: float = float((def["clues"] as Dictionary).get(kind, 0.0))
		if w <= 0.0:
			continue
		var h := _hid(career)
		h["pts"] = float(h["pts"]) + w * amount
		if int(h["sid"]) < 0:
			h["sid"] = sid
	for career: String in _hidden:
		_update_stage(career, _hidden[career])


func _update_stage(career: String, h: Dictionary) -> void:
	var def: Dictionary = HIDDEN[career]
	var st := 0
	for i in HIDDEN_STAGES.size():
		if float(h["pts"]) >= float(HIDDEN_STAGES[i]):
			st = i + 1
	if def.has("gate"):
		for need: String in def["gate"]:
			if int(_hid(need)["stage"]) < int(def["gate"][need]):
				st = mini(st, 1)
	if st > int(h["stage"]):
		h["stage"] = st


func on_fact(fact: String) -> void:
	note_activity("learned_fact", -1, 1.0)
	if fact.begins_with("place:") and "sewer" in fact:
		note_activity("explore_sewer", -1, 1.0)


func hidden_leads() -> Array:
	## Text hints only; the career itself is never named until you are in.
	var out: Array = []
	for career: String in HIDDEN:
		if not _hidden.has(career):
			continue
		var h: Dictionary = _hidden[career]
		var st := int(h["stage"])
		if st <= 0:
			continue
		var leads: Array = HIDDEN[career]["leads"]
		out.append({"id": career, "stage": st, "sid": int(h["sid"]), "text": leads[st - 1],
			"member": bool(h["member"]), "trial_ready": st >= 3 and not bool(h["member"])})
	return out


func hidden_trial(career: String) -> Dictionary:
	if not HIDDEN.has(career):
		return {"ok": false, "reason": "Nothing like that."}
	var h := _hid(career)
	if bool(h["member"]):
		return {"ok": false, "reason": "You are already one of them."}
	if int(h["stage"]) < 3:
		return {"ok": false, "reason": "Nobody has asked you anything yet."}
	if _last_day - int(h["trial_day"]) < 7:
		return {"ok": false, "reason": "They told you to come back in a week."}
	var def: Dictionary = HIDDEN[career]
	var tr: Dictionary = def["trial"]
	var have := float(player.get(tr["stat"], 0))
	var roll := _rng("trial", _last_day, career).randf() * 30.0
	h["trial_day"] = _last_day
	if have + roll >= float(tr["target"]) + 15.0:
		h["member"] = true
		h["rank"] = 0
		_hidden_contracts = _hidden_contracts.filter(func(c: Dictionary) -> bool: return c["career"] != career)
		return {"ok": true, "passed": true, "reason": "They nod. You are in.", "task": tr["text"], "rank": (def["ranks"] as Array)[0]}
	h["pts"] = maxf(float(HIDDEN_STAGES[1]) + 0.5, float(h["pts"]) - 2.0)
	_soc_call("log_failure", ["hidden_trial", "You failed a test in the dark. A door closed, and someone in the trade now knows your face.", int(h["sid"])])
	return {"ok": true, "passed": false, "reason": "You fumbled it. Come back in a week.", "task": tr["text"]}


func hidden_member(career: String) -> bool:
	return _hidden.has(career) and bool(_hidden[career]["member"])


func hidden_rank(career: String) -> String:
	if not hidden_member(career):
		return ""
	var ranks: Array = HIDDEN[career]["ranks"]
	return String(ranks[mini(int(_hidden[career]["rank"]), ranks.size() - 1)])


func hidden_contracts(career: String) -> Array:
	var out: Array = []
	if not hidden_member(career):
		return out
	for c: Dictionary in _hidden_contracts:
		if c["career"] == career:
			out.append(c.duplicate(true))
	return out


func complete_hidden_contract(cid: String, success: bool) -> Dictionary:
	for i in _hidden_contracts.size():
		var c: Dictionary = _hidden_contracts[i]
		if c["id"] == cid:
			_hidden_contracts.remove_at(i)
			var h := _hid(String(c["career"]))
			if success:
				h["done"] = int(h["done"]) + 1
				pending_gold += int(c["pay"])
				var ranks: Array = HIDDEN[c["career"]]["ranks"]
				if int(h["done"]) % 3 == 0 and int(h["rank"]) + 1 < ranks.size():
					h["rank"] = int(h["rank"]) + 1
				_soc_call("add_crim_rep", ["underworld", 3.0, String(c["career"])])
				return {"ok": true, "pay": c["pay"]}
			_soc_call("add_crim_rep", ["underworld", -2.0, "botched"])
			return {"ok": true, "pay": 0}
	return {"ok": false, "pay": 0}


func _gen_hidden_contracts(day: int) -> void:
	for career: String in _hidden:
		var h: Dictionary = _hidden[career]
		if not bool(h["member"]):
			continue
		var have := 0
		for c: Dictionary in _hidden_contracts:
			if c["career"] == career:
				have += 1
		if have >= 2:
			continue
		var r := _rng("hcon", day, career)
		_hidden_contracts.append({"id": "hc:%s:%d" % [career, day], "career": career, "pay": 20 + int(h["rank"]) * 25 + r.randi() % 20,
			"text": "A message under a stone by the %s: a job, no names." % String(_pick(r, LANDMARKS)), "expires": day + 8})
	_hidden_contracts = _hidden_contracts.filter(func(c: Dictionary) -> bool: return int(c["expires"]) > day)


# ------------------------------------------------------------ L§15-17 guilds

func _ensure_guilds() -> void:
	if _guilds_built:
		return
	_guilds_built = true
	for s: Dictionary in WorldGen.settlements:
		var sid: int = int(s["id"])
		var kinds: Array = KIND_GUILDS.get(String(s["kind"]), [])
		for gk: String in kinds:
			var gid := "g:%s:%d" % [gk, sid]
			var r := _rng("guild", 0, gid)
			var def: Dictionary = GUILD_KINDS[gk]
			var factions: Array = []
			for f: Array in GUILD_FACTIONS:
				factions.append({"id": f[0], "name": f[1], "agenda": f[2], "power": 20.0 + r.randf() * 30.0})
			var officers: Array = []
			for i in 3:
				officers.append({"name": _npc_name(r), "faction": factions[i % factions.size()]["id"], "loyalty": 0.3 + r.randf() * 0.6,
					"corrupt": r.randf() < 0.25, "age": 35 + r.randi() % 30})
			var leader: Dictionary = {"name": _npc_name(r), "age": 50 + r.randi() % 20, "faction": factions[r.randi() % 3]["id"]}
			var rivals: Array = []
			for other: String in kinds:
				if other != gk and rivals.size() < 1:
					rivals.append("g:%s:%d" % [other, sid])
			_guilds[gid] = {"id": gid, "kind": gk, "sid": sid, "name": "%s of %s" % [def["name"], _sname(sid)],
				"entry": String(def["entry"]), "fee": int(def["fee"]), "rep_min": int(def["rep_min"]) + (10 if String(s["kind"]) == "castle" else 0),
				"refs": int(def["refs"]), "stat": String(def.get("stat", "")), "target": int(def.get("target", 0)), "dues": int(def["dues"]),
				"leader": leader, "officers": officers, "factions": factions, "treasury": 200 + r.randi() % 400, "rivals": rivals,
				"player": {"rank": -1, "merit": 0.0, "probation_until": -1, "missed": 0, "trial_day": -100, "support": {}},
				"history": []}


func guilds() -> Array:
	_ensure_guilds()
	var out: Array = []
	var ids: Array = _guilds.keys()
	ids.sort()
	for gid: String in ids:
		out.append((_guilds[gid] as Dictionary).duplicate(true))
	return out


func guild(gid: String) -> Dictionary:
	_ensure_guilds()
	return (_guilds.get(gid, {}) as Dictionary).duplicate(true)


func guild_requirements(gid: String) -> Dictionary:
	_ensure_guilds()
	if not _guilds.has(gid):
		return {}
	var g: Dictionary = _guilds[gid]
	return {"entry": g["entry"], "fee": g["fee"], "rep_min": g["rep_min"], "refs": g["refs"], "stat": g["stat"], "target": g["target"]}


func join_guild(gid: String) -> Dictionary:
	_ensure_guilds()
	if not _guilds.has(gid):
		return {"ok": false, "reason": "No such guild."}
	var g: Dictionary = _guilds[gid]
	var p: Dictionary = g["player"]
	if int(p["rank"]) >= 0:
		return {"ok": false, "reason": "You are already in."}
	if _last_day - int(p["trial_day"]) < 10:
		return {"ok": false, "reason": "They asked you to come back later."}
	var rep := float(_soc_call("rep", ["city:%d" % int(g["sid"])], float(player.get("rep", 0))))
	if rep < float(g["rep_min"]):
		return {"ok": false, "reason": "A famous guild does not take unknowns. Build a name in %s first." % _sname(int(g["sid"]))}
	if int(g["refs"]) > _refs():
		return {"ok": false, "reason": "You need a recommendation or sponsor."}
	if _gold() < int(g["fee"]):
		return {"ok": false, "reason": "The entry fee is %d gold." % int(g["fee"])}
	var stat := String(g["stat"])
	p["trial_day"] = _last_day
	if stat != "":
		var roll := _rng("gjoin", _last_day, gid).randf() * 20.0
		if float(player.get(stat, 0)) + roll < float(g["target"]):
			return {"ok": true, "joined": false, "reason": "Your %s (%s) did not impress the examiners." % [g["entry"], stat]}
	pending_gold -= int(g["fee"])
	g["treasury"] = int(g["treasury"]) + int(g["fee"])
	p["rank"] = 0
	p["probation_until"] = _last_day + 7
	return {"ok": true, "joined": true, "reason": "You are an applicant on probation for a week.", "entry": g["entry"]}


func guild_contribute(gid: String, merit: float) -> void:
	if _guilds.has(gid) and int(_guilds[gid]["player"]["rank"]) >= 0:
		_guilds[gid]["player"]["merit"] = float(_guilds[gid]["player"]["merit"]) + merit


func guild_support(gid: String, faction_id: String, gold: int) -> bool:
	if not _guilds.has(gid) or gold <= 0 or _gold() < gold:
		return false
	for f: Dictionary in _guilds[gid]["factions"]:
		if f["id"] == faction_id:
			pending_gold -= gold
			f["power"] = float(f["power"]) + gold * 0.1
			var s: Dictionary = _guilds[gid]["player"]["support"]
			s[faction_id] = float(s.get(faction_id, 0.0)) + gold
			return true
	return false


func found_guild(name: String, kind: String, sid: int) -> Dictionary:
	_ensure_guilds()
	if not GUILD_KINDS.has(kind):
		return {"ok": false, "reason": "Unknown trade."}
	if _gold() < 500:
		return {"ok": false, "reason": "A charter costs 500 gold."}
	var gid := "g:%s:%d:own" % [kind, sid]
	if _guilds.has(gid):
		return {"ok": false, "reason": "You already have one."}
	pending_gold -= 500
	var def: Dictionary = GUILD_KINDS[kind]
	_guilds[gid] = {"id": gid, "kind": kind, "sid": sid, "name": name, "entry": "recommendation", "fee": 0, "rep_min": 0, "refs": 0, "stat": "",
		"target": 0, "dues": int(def["dues"]), "leader": {"name": "You", "age": int(player.get("age", 20)), "faction": ""}, "officers": [],
		"factions": [{"id": "founders", "name": "Founders", "agenda": "grow the guild", "power": 30.0}], "treasury": 0, "rivals": [],
		"player": {"rank": 5, "merit": 20.0, "probation_until": -1, "missed": 0, "trial_day": -100, "support": {}}, "history": ["Chartered by you."]}
	return {"ok": true, "reason": "", "id": gid}


func _tick_guild_day(day: int, msgs: Array) -> void:
	var ids: Array = _guilds.keys()
	for gid: String in ids:
		var g: Dictionary = _guilds[gid]
		var p: Dictionary = g["player"]
		var mine := int(p["rank"]) >= 0
		if int(p["rank"]) == 0 and int(p["probation_until"]) >= 0 and day >= int(p["probation_until"]) and float(p["merit"]) >= 0.0:
			p["rank"] = 1
			p["probation_until"] = -1
			_say(msgs, "%s accepts you as a full member." % g["name"])
		if mine and int(p["rank"]) in [1, 2, 3] and float(p["merit"]) >= 12.0 * float(p["rank"]):
			p["rank"] = int(p["rank"]) + 1
			_say(msgs, "%s raises you to %s." % [g["name"], RANKS[int(p["rank"])]])
		var r := _rng("gpol", day, gid)
		# Random walk of factions.
		for f: Dictionary in g["factions"]:
			f["power"] = clampf(float(f["power"]) + r.randf_range(-1.5, 1.6), 5.0, 100.0)
		# Leader death by age.
		var lead: Dictionary = g["leader"]
		if String(lead["name"]) != "You" and r.randf() < maxf(0.0, (float(lead["age"]) - 55.0) * 0.0004):
			_succession(g, day, msgs, mine, "dies")
			continue
		# Corrupt officers embezzle.
		for o: Dictionary in g["officers"]:
			if bool(o["corrupt"]) and r.randf() < 0.05 and int(g["treasury"]) > 30:
				var take := 5 + r.randi() % 15
				g["treasury"] = int(g["treasury"]) - take
				o["skimmed"] = int(o.get("skimmed", 0)) + take
				if r.randf() < 0.15 + (0.2 if int(p["rank"]) >= 3 else 0.0):
					if mine:
						_say(msgs, "Rumour in %s: %s has been skimming the treasury." % [g["name"], o["name"]])
					g["history"].append("Day %d: %s exposed for embezzlement." % [day, o["name"]])
					o["corrupt"] = false
					o["loyalty"] = float(o["loyalty"]) - 0.3
					if r.randf() < 0.5:
						_succession(g, day, msgs, mine, "is ousted after an embezzling scandal", o["name"])
						break
		# Rival sabotage.
		if not (g["rivals"] as Array).is_empty() and r.randf() < 0.02:
			g["treasury"] = maxi(0, int(g["treasury"]) - 25)
			g["history"].append("Day %d: rivals sabotaged the stores." % day)
			if mine:
				_say(msgs, "%s: rival guildsmen sabotaged the stores." % g["name"])
		g["treasury"] = int(g["treasury"]) + 3
		while (g["history"] as Array).size() > 12:
			g["history"].pop_front()


func _succession(g: Dictionary, day: int, msgs: Array, mine: bool, why: String, exclude: String = "") -> void:
	var best_score := -1.0
	var winner: Dictionary = {}
	var r := _rng("gvote", day, g["id"])
	for o: Dictionary in g["officers"]:
		if o["name"] == exclude:
			continue
		var power := 0.0
		for f: Dictionary in g["factions"]:
			if f["id"] == o["faction"]:
				power = float(f["power"])
		var sc: float = power + float(o["loyalty"]) * 20.0 + r.randf() * 15.0 - (25.0 if bool(o["corrupt"]) else 0.0)
		if sc > best_score:
			best_score = sc
			winner = o
	var p: Dictionary = g["player"]
	var pscore := -1.0
	if int(p["rank"]) >= 4:
		var sup := 0.0
		for k: String in p["support"]:
			sup += float(p["support"][k])
		pscore = float(p["merit"]) * 1.5 + sup * 0.05 + r.randf() * 15.0
	var old := String(g["leader"]["name"])
	if pscore > best_score:
		g["leader"] = {"name": "You", "age": int(player.get("age", 20)), "faction": ""}
		p["rank"] = 5
		_say(msgs, "The members of %s vote. You are their new leader." % g["name"])
	elif not winner.is_empty():
		if int(p["rank"]) == 5:
			p["rank"] = 4
		g["leader"] = {"name": winner["name"], "age": int(winner["age"]), "faction": winner["faction"]}
		(g["officers"] as Array).erase(winner)
		(g["officers"] as Array).append({"name": _npc_name(r), "faction": winner["faction"], "loyalty": 0.5, "corrupt": r.randf() < 0.25, "age": 30 + r.randi() % 20})
	else:
		g["leader"] = {"name": _npc_name(r), "age": 45, "faction": "old_guard"}
	g["history"].append("Day %d: %s %s; %s leads." % [day, old, why, g["leader"]["name"]])
	if mine or _near_sid == int(g["sid"]):
		_say(msgs, "%s: %s %s. %s takes the chair." % [g["name"], old, why, g["leader"]["name"]])


func _tick_guild_week(msgs: Array) -> void:
	for gid: String in _guilds:
		var g: Dictionary = _guilds[gid]
		var p: Dictionary = g["player"]
		if int(p["rank"]) < 0 or String(g["leader"]["name"]) == "You":
			continue
		if _gold() >= int(g["dues"]):
			pending_gold -= int(g["dues"])
			g["treasury"] = int(g["treasury"]) + int(g["dues"])
			p["missed"] = 0
		else:
			p["missed"] = int(p["missed"]) + 1
			_say(msgs, "You could not pay your dues to %s." % g["name"])
			if int(p["missed"]) >= 3:
				p["rank"] = -1
				p["missed"] = 0
				_say(msgs, "%s strikes you from the roll." % g["name"])
				_soc_call("log_failure", ["guild_expelled", "Struck from %s for unpaid dues; the hall's doors are closed, but taverns still hire." % g["name"], int(g["sid"])])


# ------------------------------------------------- L§35 districts at night

static func is_night(hour: int) -> bool:
	return hour >= 21 or hour < 5


func district_state(sid: int, district: String, hour: int) -> Dictionary:
	var c := _ensure(sid)
	var night := is_night(hour)
	var kind := _kind(sid)
	var base := {"market": [7, 19, 0.15, 2], "craft": [7, 18, 0.12, 1], "noble": [8, 20, 0.05, 4],
		"temple": [5, 21, 0.05, 1], "docks": [5, 22, 0.3, 1], "slums": [0, 24, 0.45, 0]}
	var b: Array = base.get(district, [7, 19, 0.15, 1])
	var shops_open := hour >= int(b[0]) and hour < int(b[1])
	if district == "slums":
		shops_open = false
	var size_mult: float = {"village": 0.5, "frontier_town": 0.8, "town": 1.0, "castle": 1.4}.get(kind, 1.0)
	var patrol := int(round(float(b[3]) * float(size_mult)))
	if _at_war:
		patrol += 1
	if night and district != "noble":
		patrol = maxi(0, patrol - 1) if district in ["slums", "docks"] else patrol
	var crime := float(b[2]) * (1.6 if night else 1.0) + (0.05 if _at_war else 0.0)
	crime = clampf(crime - 0.06 * float(patrol), 0.02, 0.95)
	var taverns_open := (hour >= 11 or hour < 3) and district in ["market", "docks", "slums", "craft"]
	var night_npcs: Array = []
	var opps: Array = []
	var r := _rng("night", _last_day, [sid, district])
	if night:
		match district:
			"slums":
				night_npcs = ["fence", "street tough", "beggar with sharp eyes"]
			"docks":
				night_npcs = ["smuggler crew", "night watchman"]
				if hour >= 1 and hour < 4 and r.randf() < 0.6:
					opps.append("A boat with no lantern is unloading at the far pier.")
			"noble":
				night_npcs = ["torch-bearing footman", "patrolling household guard"]
			"temple":
				night_npcs = ["vigil keeper"]
			"market":
				night_npcs = ["lamplighter", "night alchemist" if r.randf() < 0.3 else "drunk merchant"]
		if district == "slums" and r.randf() < 0.5:
			opps.append("A door opens on a back stair; the low music behind it is not for guests.")
	var gate_class := 0
	if district == "noble":
		gate_class = 3 if night else 2
	elif district == "slums":
		gate_class = 0
	elif night and district == "temple":
		gate_class = 1
	var entry_ok := _class() >= gate_class
	return {"district": district, "sid": sid, "night": night, "shops_open": shops_open, "taverns_open": taverns_open,
		"patrol": patrol, "crime_risk": snappedf(crime, 0.01), "lit": 0.3 if night and district == "slums" else (0.6 if night else 1.0),
		"gate_class": gate_class, "entry_ok": entry_ok, "night_npcs": night_npcs, "opportunities": opps,
		"curfew": _at_war and night and district != "slums", "known": (c["districts"] as Array).has(district)}


# ------------------------------------------------ L§49 schedules

func opportunities(sid: int, hour: int, day: int = -1) -> Array:
	var c := _ensure(sid)
	var d := _last_day if day < 0 else day
	var out: Array = []
	for e: Dictionary in c["sched"]:
		if int(e["dow"]) >= 0 and int(e["dow"]) != d % 7:
			continue
		if hour < int(e["from"]) or hour >= int(e["to"]):
			continue
		var known := int(_seen.get(e["id"], 0)) >= 2 or bool(_soc_call("knows", ["schedule:" + String(e["id"])], false))
		var o := {"id": e["id"], "district": e.get("district", "market"), "known": known, "npc": e["npc"] if known else "someone", "actions": [], "text": "You notice someone coming and going here."}
		if known:
			var role: Dictionary = SCHED_ROLES[e["role"]]
			o["actions"] = (role["actions"] as Array).duplicate()
			var t: String = role["text"]
			match e["role"]:
				"corrupt_noble":
					o["text"] = t % [e["npc"], e["place"], DOW[int(e["dow"])]]
				"gate_guard":
					o["text"] = t % [e["npc"], "%d:00" % int(e["from"])]
				"merchant":
					o["text"] = t % [e["npc"], e["place"]]
				"courier":
					o["text"] = t % [e["npc"], e["place"], DOW[int(e["dow"])]]
			if e["role"] == "gate_guard":
				o["unwatched"] = "the gate"
		out.append(o)
	return out


func observe(sid: int, sched_id: String) -> int:
	## Watching someone's routine once per game day builds knowledge.
	var c := _ensure(sid)
	for e: Dictionary in c["sched"]:
		if e["id"] == sched_id:
			var key := "%s@%d" % [sched_id, _last_day]
			if not _seen.has(key):
				_seen[key] = 1
				_seen[sched_id] = int(_seen.get(sched_id, 0)) + 1
				if int(_seen[sched_id]) >= 2:
					_soc_call("learn", ["schedule:" + sched_id])
			return int(_seen[sched_id])
	return 0


# ------------------------------------------------------------------ ticks

func tick_hour(hour: int, ctx: Dictionary) -> Array:
	var msgs: Array = []
	_sync(ctx)
	_hour = hour
	# Inn stay expiry and cheap-inn theft at 03:00.
	if not _stay.is_empty():
		if hour == 3 and float(_stay["security"]) < 0.4:
			var r := _rng("innthief", int(_now / 24.0), _stay["inn"])
			if r.randf() < (0.4 - float(_stay["security"])) * 0.25 and _gold() > 5:
				var lost := mini(_gold(), 3 + r.randi() % 8)
				pending_gold -= lost
				_say(msgs, "You wake to find your purse lighter by %d gold. The lock was a courtesy." % lost)
				_soc_call("log_failure", ["inn_theft", "Robbed asleep in a cheap inn. Somebody in the taproom knows who did it.", int(_stay["sid"])])
		if _now >= float(_stay["until"]):
			_say(msgs, "Your paid nights at the inn are over.")
			_stay = {}
	# Job shift bookkeeping: end-of-shift with no clock-in counts as a skipped shift.
	if not _job.is_empty():
		var s: Array = _job["shift"]
		if hour == int(s[0]) and not bool(_job["worked_today"]) and _last_day % 7 != 0:
			_say(msgs, "Your shift at %s begins." % _job["employer"])
	# Night overhearing in the slums: the seed of informant / thief leads.
	if _near_sid >= 0 and is_night(hour) and (_cities.has(str(_near_sid)) and (_cities[str(_near_sid)]["districts"] as Array).has("slums")):
		if _rng("overhear", int(_now), _near_sid).randf() < 0.08:
			note_activity("night_slums", _near_sid, 1.0)
	return msgs


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


## The cheap prologue runs now; then one chunk per city refresh, then one per epilogue step.
func tick_day_chunks(day: int, ctx: Dictionary) -> Array:
	_sync(ctx)
	_last_day = day
	_ensure_guilds()
	if _near_sid >= 0:
		_ensure(_near_sid)
	var chunks: Array = []
	for k: String in _cities.keys():
		chunks.append(func() -> Array:
			var c: Dictionary = _cities.get(k, {})
			if not c.is_empty() and int(c["last_refresh"]) != day:
				_refresh_city(c, day)
			return [])
	chunks.append(func() -> Array:
		var msgs: Array = []
		_tick_leases(day, msgs)
		return msgs)
	chunks.append(func() -> Array:
		var msgs: Array = []
		_tick_job_day(day, msgs)
		return msgs)
	chunks.append(func() -> Array:
		var msgs: Array = []
		_tick_guild_day(day, msgs)
		return msgs)
	chunks.append(func() -> Array:
		_gen_hidden_contracts(day)
		return [])
	return chunks


func tick_week(week: int, ctx: Dictionary) -> Array:
	var msgs: Array = []
	_sync(ctx)
	_tick_guild_week(msgs)
	# Rents drift with the market (L "rent changes").
	for k: String in _cities:
		var r := _rng("rent", week, k)
		for h: Dictionary in _cities[k]["homes"]:
			var lo: float = float(HOME_KINDS[h["kind"]]["rent"][0]) * 0.7
			var hi: float = float(HOME_KINDS[h["kind"]]["rent"][1]) * 1.4
			h["rent"] = int(clampf(round(float(h["rent"]) * r.randf_range(0.97, 1.04)), lo, hi))
	return msgs


func catch_up(days: int, ctx: Dictionary) -> Array:
	var msgs: Array = []
	if days <= 0:
		return msgs
	_sync(ctx)
	var day := _last_day + days
	# Employment: an absent player skipped ~6/7 of the days.
	if not _job.is_empty():
		var missed := int(days * 6 / 7)
		if int(_job["leave_until"]) > _last_day:
			missed = maxi(0, missed - (int(_job["leave_until"]) - _last_day))
		_job["missed"] = int(_job["missed"]) + missed
		_job["performance"] = float(_job["performance"]) - 6.0 * float(missed)
		if int(_job["missed"]) >= FIRE_ABSENCES or float(_job["performance"]) < 20.0:
			_last_day = day
			_fire("absence", msgs)
	# Leases: arrears accrue in closed form, then eviction.
	for k: String in _leases:
		var l: Dictionary = _leases[k]
		if String(l["status"]) == "evicted":
			continue
		var due: int = int(l["paid_until"])
		if day >= due:
			var overdue: int = day - due
			var weeks_due := int(ceil(float(overdue + 1) / 7.0))
			var can_pay := bool(l.get("auto_pay", false)) and _gold() >= int(l["rent"]) * weeks_due
			if can_pay:
				pending_gold -= int(l["rent"]) * weeks_due
				l["paid_until"] = due + 7 * weeks_due
			else:
				l["arrears"] = float(l["arrears"]) + float(l["rent"]) / 7.0 * float(overdue)
				l["status"] = "overdue"
				if overdue >= RENT_GRACE_DAYS:
					_evict(l, msgs)
	_last_day = day
	if not _stay.is_empty() and _now >= float(_stay["until"]):
		_stay = {}
	# Cities refresh once; guilds get expected politics (at most one shake-up each).
	for k: String in _cities:
		_refresh_city(_cities[k], day)
	_ensure_guilds()
	for gid: String in _guilds:
		var g: Dictionary = _guilds[gid]
		var lead: Dictionary = g["leader"]
		if String(lead["name"]) != "You":
			var p_die := 1.0 - pow(1.0 - maxf(0.0, (float(lead["age"]) - 55.0) * 0.0004), float(days))
			if _rng("gcatch", day, gid).randf() < p_die:
				_succession(g, day, msgs, int(g["player"]["rank"]) >= 0, "died while you were away")
		g["treasury"] = int(g["treasury"]) + 3 * days
		lead["age"] = int(lead["age"]) + days / 365
		if int(g["player"]["rank"]) == 0 and int(g["player"]["probation_until"]) >= 0 and day >= int(g["player"]["probation_until"]):
			g["player"]["rank"] = 1
	for career: String in _hidden:
		if bool(_hidden[career]["member"]):
			_gen_hidden_contracts(day)
			break
	if days >= 3 and not msgs.is_empty():
		msgs.push_front("While you were away, life in the cities went on.")
	return msgs


# ---------------------------------------------------------------- save/load

func serialize() -> Dictionary:
	return {"player": player.duplicate(true), "pending": pending_gold, "cities": _cities.duplicate(true), "leases": _leases.duplicate(true),
		"stay": _stay.duplicate(true), "job": _job.duplicate(true), "history": _history.duplicate(true), "blacklist": _blacklist.duplicate(true),
		"emp_rep": _emp_rep, "hidden": _hidden.duplicate(true), "hcon": _hidden_contracts.duplicate(true), "guilds": _guilds.duplicate(true),
		"guilds_built": _guilds_built, "seen": _seen.duplicate(true), "day": _last_day, "hour": _hour, "now": _now, "log": _log.duplicate()}


static func _intify(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k: Variant in v:
			out[k] = _intify(v[k])
		return out
	if v is Array:
		var a: Array = []
		for x: Variant in v:
			a.append(_intify(x))
		return a
	if v is float and is_equal_approx(v, round(v)) and absf(v) < 1.0e12:
		return int(v)
	return v


func deserialize(d: Dictionary) -> void:
	var n: Dictionary = _intify(d)
	player = DEFAULT_PLAYER.duplicate()
	for k: String in n.get("player", {}):
		player[k] = n["player"][k]
	pending_gold = int(n.get("pending", 0))
	_cities = n.get("cities", {})
	_leases = n.get("leases", {})
	_stay = n.get("stay", {})
	_job = n.get("job", {})
	_history = n.get("history", [])
	_blacklist = n.get("blacklist", {})
	_emp_rep = float(n.get("emp_rep", 50.0))
	_hidden = n.get("hidden", {})
	_hidden_contracts = n.get("hcon", [])
	_guilds = n.get("guilds", {})
	_guilds_built = bool(n.get("guilds_built", false))
	_seen = n.get("seen", {})
	_last_day = int(n.get("day", 0))
	_hour = int(n.get("hour", 8))
	_now = float(n.get("now", 0.0))
	_log = n.get("log", [])
