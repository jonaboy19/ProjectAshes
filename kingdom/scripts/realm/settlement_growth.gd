extends "res://scripts/realm/realm_module.gd"
## READY_V1 C4: how a camp the player founded grows. One state row per build-kit grid (the C2 settlement id), ticked once a day:
##   labour       followers and settlers are put on the grid's construction sites (loose plans are handed to the crew first)
##   food         a stock; settlers farm, followers forage; everyone eats; a famine empties the stock and the people leave
##   housing      tents + one house per four finished roof pieces + extra beds
##   contentment  0..1 from food, housing, safety (palisade), amenities (well, hall) and jobs, eased toward its target
##   immigration  settlers arrive while there is food, room and goodwill
##   tiers        Camp -> Hamlet (6 people, 2 houses, 5 days of food) -> Village (15 people, a well, a hall, contentment 0.5)
## Everything the ledger screen (ui/settlement_ledger.gd) shows comes from ledger(gid). Tier-ups are announced through `tier_reached`
## (C5, the lordship milestone, listens). Pure data; reads build_kit, construction and followers; never touches the player's gold.

signal tier_reached(gid: int, tier: int, tier_name: String)

const TIERS := ["camp", "hamlet", "village"]
const TIER_WORDS := ["Camp", "Hamlet", "Village"]
const HAMLET_POP := 6
const HAMLET_HOUSES := 2
const HAMLET_FOOD_DAYS := 5.0
const VILLAGE_POP := 15
const VILLAGE_CONTENT := 0.5
const START_POP := 2
const TENT_ROOM := 3                  # a camp sleeps this many before any house stands
const HOUSE_ROOF_PIECES := 4          # one cottage = four roof pieces
const HOUSE_ROOM := 4
const WORKING_SHARE := 0.7            # of the settlers can work
const FARMER_SHARE := 0.6             # of the workers farm; the rest build
const FOOD_PER_FARMER := 2.0
const FOOD_PER_FOLLOWER := 1.0
const EAT_PER_PERSON := 1.0
const STORE_BASE := 60.0
const STORE_PER_CRATE := 30.0
const SPOIL := 0.02                   # of the stock above a week's food, per day
const STARVE_LEAVE_DAYS := 3
const CONTENT_EASE := 0.3
const ARRIVE_BASE := 0.3
const ARRIVE_MIN_CONTENT := 0.4
const ARRIVE_MIN_FOOD_DAYS := 3.0
const CATCH_UP_CAP := 30

var states: Dictionary = {}           # str(gid) -> state
var auto_crew := true                 # hand loose plans to a crew and put people on it (the player can turn it off)
var _msgs: Array = []


func _kit() -> RefCounted:
	return hub.mod("build_kit") if hub != null else null


func _cons() -> RefCounted:
	return hub.mod("construction") if hub != null else null


func _new_state(gid: int, day: int) -> Dictionary:
	return {"gid": gid, "pop": START_POP, "food": 12.0, "content": 0.5, "tier": 0, "since": day, "tier_day": [day, -1, -1],
		"starve": 0, "food_mult": 1.0, "arrived": 0, "left": 0, "crew": [], "last": {}}


func state_of(gid: int) -> Dictionary:
	return states.get(str(gid), {})


## Adds food to the stock (a delivery by the player, a trader, a rescue). Returns what the stores could take.
func add_food(gid: int, n: float) -> float:
	var s: Dictionary = states.get(str(gid), {})
	if s.is_empty():
		return 0.0
	var room := maxf(0.0, store_cap(gid) - float(s["food"]))
	var put := minf(n, room)
	s["food"] = float(s["food"]) + put
	return put


func store_cap(gid: int) -> float:
	return STORE_BASE + STORE_PER_CRATE * float(structures(gid)["crates"])


## What the finished pieces of grid `gid` give: houses, beds, capacity, well, hall, defence, jobs.
func structures(gid: int) -> Dictionary:
	var kit := _kit()
	var out := {"roofs": 0, "houses": 0, "beds": 0, "capacity": TENT_ROOM, "well": false, "hall": false, "defence": 0, "stations": 0,
		"stalls": 0, "crates": 0, "pieces": 0, "banner": false, "table": false}
	if kit == null or not kit.grids.has(gid):
		return out
	for pid: int in kit.grids[gid]["pieces"]:
		var rec: Dictionary = kit.grids[gid]["pieces"][pid]
		if String(rec["state"]) != "done":
			continue
		out["pieces"] = int(out["pieces"]) + 1
		var kind := String(rec["kind"])
		var d: Dictionary = kit.def(kind)
		if kind.begins_with("roof_") and not kind.begins_with("roof_ridge"):
			out["roofs"] = int(out["roofs"]) + 1
		out["beds"] = int(out["beds"]) + int(d.get("beds", 0))
		if kind.contains("well"):
			out["well"] = true
		if String(d.get("role", "")) == "banner":
			out["banner"] = true
		if kind.begins_with("table") or kind.contains("_table_"):
			out["table"] = true
		if String(d.get("role", "")) == "stall":
			out["stalls"] = int(out["stalls"]) + 1
		if String(d.get("station", "")) != "" and kit.CRAFT_BENCH.has(String(d["station"])):
			out["stations"] = int(out["stations"]) + 1
		if kind == "storage_crates" or int(d.get("store", 0)) > 0:
			out["crates"] = int(out["crates"]) + 1
		if String(d.get("cat", "")) == "defence" and String(d.get("layer", "")) in ["wall", "fence"]:
			out["defence"] = int(out["defence"]) + 1
	out["houses"] = int(out["roofs"]) / HOUSE_ROOF_PIECES
	out["hall"] = bool(out["banner"]) and bool(out["table"]) and int(out["roofs"]) >= HOUSE_ROOF_PIECES * 2
	out["capacity"] = TENT_ROOM + int(out["houses"]) * HOUSE_ROOM + int(out["beds"])
	return out


# ------------------------------------------------------------------ the day

func tick_day(day: int, _ctx: Dictionary) -> Array:
	_msgs = []
	var kit := _kit()
	if kit == null:
		return []
	for k: String in states.keys():
		if not kit.grids.has(int(k)):
			states.erase(k)            # abandoned
	var gids: Array = kit.grids.keys()
	gids.sort()
	for gid: int in gids:
		if not states.has(str(gid)):
			states[str(gid)] = _new_state(gid, day)
	var party := _free_followers()
	for i in gids.size():
		var gid: int = gids[i]
		var mine: Array = []
		for j in party.size():
			if j % gids.size() == i:
				mine.append(party[j])
		_day(gid, day, mine)
	return _msgs


func tick_day_chunks(_day: int, _ctx: Dictionary) -> Array:
	return []


func _free_followers() -> Array:
	var fm: RefCounted = hub.mod("followers") if hub != null else null
	var out: Array = []
	if fm == null:
		return out
	for f: Dictionary in fm.call("list", "present"):
		var fid := String(f["id"])
		if bool(fm.call("is_down", fid)) or bool(fm.call("is_injured", fid)):
			continue
		out.append(fid)
	return out


func _day(gid: int, day: int, followers: Array) -> void:
	var s: Dictionary = states[str(gid)]
	var st := structures(gid)
	var pop := int(s["pop"])
	var work := int(floor(float(pop) * WORKING_SHARE))
	var farmers := int(ceil(float(work) * FARMER_SHARE))
	var builders := work - farmers
	if auto_crew:
		_crew(gid, s, followers, builders)
	# food
	var made := (float(farmers) * FOOD_PER_FARMER + float(followers.size()) * FOOD_PER_FOLLOWER) * float(s["food_mult"])
	var eat := float(pop) * EAT_PER_PERSON
	var stock := float(s["food"]) + made
	var starving := false
	if stock >= eat:
		stock -= eat
		s["starve"] = 0
	else:
		stock = 0.0
		starving = true
		s["starve"] = int(s["starve"]) + 1
	var week := eat * 7.0
	if stock > week:
		stock -= (stock - week) * SPOIL
	s["food"] = minf(stock, store_cap(gid))
	var food_days := float(s["food"]) / maxf(eat, 1.0)
	# jobs: farm plots + stations + stalls + palisade gangs
	var slots := 2 + int(st["stations"]) * 2 + int(st["stalls"]) * 2 + int(st["defence"]) / 4 + int(st["houses"])
	var employed := mini(work, slots + builders)
	# contentment
	var parts := contentment_parts(pop, food_days, starving, st, work, slots, builders)
	var target := clampf(0.35 + _sum(parts), 0.0, 1.0)
	s["content"] = clampf(float(s["content"]) + (target - float(s["content"])) * CONTENT_EASE, 0.0, 1.0)
	# starvation drives people away
	if starving and int(s["starve"]) >= STARVE_LEAVE_DAYS and pop > 1:
		s["pop"] = pop - 1
		s["left"] = int(s["left"]) + 1
		_msgs.append("%s: hunger drives a settler away." % settlement_name(gid))
	# immigration
	elif float(s["content"]) >= ARRIVE_MIN_CONTENT and food_days >= ARRIVE_MIN_FOOD_DAYS and pop < int(st["capacity"]):
		var r := RandomNumberGenerator.new()
		r.seed = hash([WorldSim.SEED, "growth_arrive", day, gid])
		var p := ARRIVE_BASE + 0.4 * (float(s["content"]) - ARRIVE_MIN_CONTENT) + (0.1 if bool(st["hall"]) else 0.0)
		if r.randf() < p:
			var n := mini(2 if r.randf() < 0.2 else 1, int(st["capacity"]) - pop)
			s["pop"] = pop + n
			s["arrived"] = int(s["arrived"]) + n
			_msgs.append("%s: %s settle%s at %s." % ["A family" if n > 1 else "A settler", "", "" if n > 1 else "s", settlement_name(gid)])
	s["last"] = {"made": made, "eat": eat, "food_days": food_days, "starving": starving, "slots": slots, "employed": employed,
		"work": work, "farmers": farmers, "builders": builders, "followers": followers.size(), "parts": parts, "target": target, "day": day}
	_tiers(gid, s, st, food_days, day)


static func _sum(parts: Array) -> float:
	var t := 0.0
	for p: Array in parts:
		t += float(p[1])
	return t


## The contentment breakdown as [[label, delta]] added to the 0.35 baseline.
func contentment_parts(pop: int, food_days: float, starving: bool, st: Dictionary, work: int, slots: int, builders: int) -> Array:
	var parts: Array = []
	if starving:
		parts.append(["Hunger", -0.35])
	elif food_days >= HAMLET_FOOD_DAYS:
		parts.append(["Full stores", 0.15])
	elif food_days >= 2.0:
		parts.append(["Enough to eat", 0.05])
	else:
		parts.append(["Thin larder", -0.1])
	var cap := int(st["capacity"])
	if pop > cap:
		parts.append(["Crowding", -0.25 * clampf(float(pop - cap) / maxf(float(cap), 1.0), 0.0, 1.0)])
	elif int(st["houses"]) > 0:
		parts.append(["Roofs overhead", 0.12])
	else:
		parts.append(["Sleeping in tents", 0.0])
	parts.append(["Safety", 0.1 if int(st["defence"]) >= 4 else 0.0])
	parts.append(["A well", 0.08 if bool(st["well"]) else 0.0])
	parts.append(["A hall", 0.08 if bool(st["hall"]) else 0.0])
	var idle := maxi(0, work - builders - slots)
	parts.append(["Work", -0.1 * clampf(float(idle) / maxf(float(work), 1.0), 0.0, 1.0)])
	return parts


func _tiers(gid: int, s: Dictionary, st: Dictionary, food_days: float, day: int) -> void:
	var tier := int(s["tier"])
	if tier == 0 and int(s["pop"]) >= HAMLET_POP and int(st["houses"]) >= HAMLET_HOUSES and food_days >= HAMLET_FOOD_DAYS:
		tier = 1
	if tier == 1 and int(s["pop"]) >= VILLAGE_POP and bool(st["well"]) and bool(st["hall"]) and float(s["content"]) >= VILLAGE_CONTENT:
		tier = 2
	if tier > int(s["tier"]):
		s["tier"] = tier
		(s["tier_day"] as Array)[tier] = day
		_msgs.append("%s has grown into a %s." % [settlement_name(gid), TIERS[tier]])
		tier_reached.emit(gid, tier, TIERS[tier])


## Puts loose plans in the crew's hands and the people on the sites. Settlers and followers are re-assigned every morning.
func _crew(gid: int, s: Dictionary, followers: Array, builders: int) -> void:
	var kit := _kit()
	var cons := _cons()
	if kit == null or cons == null:
		return
	for wid: String in s["crew"]:
		cons.call("unassign", wid)
	s["crew"] = []
	kit.hand_to_workers(gid)          # fails quietly when there is nothing to build
	var sites: Array = []
	for sk: String in (kit.grids[gid]["plans"] as Dictionary).keys():
		var sid := int(sk)
		if (cons.get("sites") as Dictionary).has(sid) and String(cons.sites[sid]["state"]) == "site":
			sites.append(sid)
	sites.sort()
	if sites.is_empty():
		return
	var i := 0
	for fid: String in followers:
		var w: Dictionary = cons.call("assign_follower", sites[i % sites.size()], fid)
		if not w.is_empty():
			(s["crew"] as Array).append(String(w["id"]))
		i += 1
	var per: Array = []
	per.resize(sites.size())
	per.fill(0)
	for b in builders:
		per[b % sites.size()] += 1
	for k in sites.size():
		if int(per[k]) > 0:
			(s["crew"] as Array).append_array(cons.call("assign_settlers", sites[k], int(per[k])))


func settlement_name(gid: int) -> String:
	var kit := _kit()
	return String(kit.grids[gid]["name"]) if kit != null and kit.grids.has(gid) else "the camp"


func tier_name(gid: int) -> String:
	return TIER_WORDS[int(state_of(gid).get("tier", 0))]


# ------------------------------------------------------------------ the ledger: every number the screen shows

func ledger(gid: int) -> Dictionary:
	var s := state_of(gid)
	if s.is_empty():
		return {}
	var st := structures(gid)
	var last: Dictionary = s["last"]
	var tier := int(s["tier"])
	var pop := int(s["pop"])
	var eat := float(pop) * EAT_PER_PERSON
	var food_days := float(s["food"]) / maxf(eat, 1.0)
	var check: Array = []
	if tier == 0:
		check = [_chk("People", pop, HAMLET_POP), _chk("Houses", int(st["houses"]), HAMLET_HOUSES), _chk("Days of food", snappedf(food_days, 0.1), HAMLET_FOOD_DAYS)]
	elif tier == 1:
		check = [_chk("People", pop, VILLAGE_POP), _chk("A well", 1 if bool(st["well"]) else 0, 1), _chk("A hall", 1 if bool(st["hall"]) else 0, 1),
			_chk("Contentment", snappedf(float(s["content"]), 0.01), VILLAGE_CONTENT)]
	return {"gid": gid, "name": settlement_name(gid), "tier": tier, "tier_name": TIER_WORDS[tier],
		"next_tier": TIER_WORDS[tier + 1] if tier < 2 else "", "checklist": check,
		"pop": pop, "capacity": int(st["capacity"]), "houses": int(st["houses"]), "beds": int(st["beds"]),
		"food": float(s["food"]), "food_days": food_days, "food_made": float(last.get("made", 0.0)), "food_eaten": float(last.get("eat", eat)),
		"starving": bool(last.get("starving", false)), "store_cap": store_cap(gid),
		"content": float(s["content"]), "content_target": float(last.get("target", s["content"])), "content_parts": last.get("parts", []),
		"jobs": {"slots": int(last.get("slots", 0)), "employed": int(last.get("employed", 0)), "workers": int(last.get("work", 0)),
			"farmers": int(last.get("farmers", 0)), "builders": int(last.get("builders", 0)), "followers": int(last.get("followers", 0))},
		"arrived": int(s["arrived"]), "left": int(s["left"]), "structures": st, "since": int(s["since"])}


static func _chk(label: String, have: Variant, need: Variant) -> Dictionary:
	return {"label": label, "have": have, "need": need, "ok": float(have) >= float(need)}


func catch_up(days: int, _ctx: Dictionary) -> Array:
	var out: Array = []
	for _i in mini(days, CATCH_UP_CAP):
		out.append_array(tick_day(WorldSim.day, {}))
	return out


func serialize() -> Dictionary:
	return {"states": states.duplicate(true), "auto_crew": auto_crew}


func deserialize(d: Dictionary) -> void:
	states = {}
	var src: Dictionary = d.get("states", {})
	for k: String in src:
		var s: Dictionary = (src[k] as Dictionary).duplicate(true)
		s["gid"] = int(s["gid"])
		s["pop"] = int(s["pop"])
		s["tier"] = int(s["tier"])
		s["starve"] = int(s["starve"])
		s["arrived"] = int(s["arrived"])
		s["left"] = int(s["left"])
		var td: Array = []
		for v: Variant in s["tier_day"]:
			td.append(int(v))
		s["tier_day"] = td
		s["crew"] = []
		states[k] = s
	auto_crew = bool(d.get("auto_crew", true))
