class_name RAEcologyBounty
extends RefCounted
## WP-17 ecology chain: deer scarcity -> hungry wolves press on the farms -> livestock lost -> the settlement
## posts a wolf bounty on the radiant board -> if nobody claims it in time the settlement pays a hunter NPC to
## thin the den itself. Pure data: callers pass the world in and apply the returned events.
##
## Wiring (all optional Callables, so tests and the hub can bind what they have):
##   bind(eco, prey_index: Callable(sid) -> float, den_settlement: Callable(den) -> {sid, pos, name})
##   tick_day(day, rq, pay: Callable(sid, gold) -> bool)
## `prey_index` is realm/ecology.gd prey_index(sid) (deer + elk stock against carrying capacity, ~1 = full).

const RQ := preload("res://scripts/sim/radiant_quests.gd")

signal bounty_posted(b: Dictionary)
signal hunter_hired(b: Dictionary)

const SCARCE_BELOW := 0.45            # prey index under this starts to bite
const LOSSES_TO_POST := 2             # livestock events in LOSS_WINDOW days
const LOSS_WINDOW := 14
const HIRE_AFTER_DAYS := 6            # bounty ignored this long -> the settlement hires a hunter
const BASE_REWARD := 30
const HUNTER_FEE := 20
const HUNTER_NAMES := ["Garrick Thorne", "Ysolde Marsh", "Brannoc Reeve", "Tilda Fenn", "Osric Vale"]

## {sid, den_id, quest_id, posted_day, reward, state: "posted"|"claimed"|"hunter"|"resolved"|"failed", hunter}
var bounties: Array[Dictionary] = []
var hunters: Array[Dictionary] = []     # {id, name, sid, hired_day, den_id}
var _eco: RAMonsterEcology = null
var _prey_index: Callable = Callable()
var _den_home: Callable = Callable()
var _losses: Dictionary = {}            # sid -> Array of days
var _seen_day := 0
var _seq := 0


func bind(eco: RAMonsterEcology, prey_index: Callable, den_home: Callable) -> void:
	_eco = eco
	_prey_index = prey_index
	_den_home = den_home
	_seen_day = eco.current_day()
	# Link 1: scarcity feeds the wolves (hungrier -> bolder -> livestock events).
	eco.prey_scarcity = func(p: Vector2) -> float: return scarcity_at(p)


## 0..1 deer scarcity around p (0 = plenty, 1 = none), from the nearest settlement's zone.
func scarcity_at(p: Vector2) -> float:
	if not _prey_index.is_valid() or not _den_home.is_valid():
		return 0.0
	var home: Dictionary = _den_home.call({"pos": p})
	if home.is_empty():
		return 0.0
	return clampf((SCARCE_BELOW - float(_prey_index.call(int(home["sid"])))) / SCARCE_BELOW, 0.0, 1.0)


func bounty_for_den(den_id: int) -> Dictionary:
	for b in bounties:
		if int(b["den_id"]) == den_id and String(b["state"]) in ["posted", "claimed", "hunter"]:
			return b
	return {}


## Daily step after the ecology ran. Returns event dicts {type, ...} for the news/event log.
func tick_day(day: int, rq: RefCounted, pay: Callable = Callable()) -> Array:
	var out: Array = []
	if _eco == null:
		return out
	# Link 2: livestock losses near a settlement are counted per settlement.
	for e: Dictionary in _eco.events_since(_seen_day):
		if String(e.get("type", "")) != "livestock_taken":
			continue
		var sid := int(e.get("settlement", -1))
		if sid < 0:
			continue
		var days: Array = _losses.get(sid, [])
		days.append(day)
		_losses[sid] = days
	_seen_day = _eco.current_day() + 1
	# Link 3: enough losses post a bounty on the raiding den.
	for sid: int in _losses.keys():
		var days: Array = (_losses[sid] as Array).filter(func(d: int) -> bool: return day - d <= LOSS_WINDOW)
		_losses[sid] = days
		if days.size() < LOSSES_TO_POST:
			continue
		var den := _raider_for(sid)
		if den.is_empty() or not bounty_for_den(int(den["id"])).is_empty():
			continue
		out.append(_post(day, sid, den, rq))
	# Link 4: bounties are claimed, ignored (hunter hired) or resolved.
	for b in bounties:
		var den: Dictionary = _eco.dens[int(b["den_id"])]
		var live := bool(den["alive"]) and int(den["population"]) > 0
		match String(b["state"]):
			"posted", "claimed":
				var q: Dictionary = rq.find(String(b["quest_id"]))
				if not live:
					b["state"] = "resolved"
					_drop_offer(rq, String(b["quest_id"]))
					out.append({"type": "bounty_resolved", "sid": b["sid"], "by": "player", "day": day})
				elif q.is_empty():
					b["state"] = "failed"     # the claimant failed or abandoned: a fresh bounty can be posted
				elif String(q["state"]) == "active":
					b["state"] = "claimed"
				elif day - int(b["posted_day"]) >= HIRE_AFTER_DAYS:
					out.append_array(_hire(day, b, den, rq, pay))
			"hunter":
				if not live:
					b["state"] = "resolved"
					out.append({"type": "bounty_resolved", "sid": b["sid"], "by": "hunter", "day": day})
	return out


func _drop_offer(rq: RefCounted, id: String) -> void:
	var q := rq.find(id)
	if not q.is_empty() and String(q["state"]) == "offered":
		rq.offers.erase(q)


## The living wolf den closest to the settlement that is inside livestock range.
func _raider_for(sid: int) -> Dictionary:
	var best := {}
	var best_d := INF
	for den in _eco.dens:
		if not den["alive"] or int(den["population"]) <= 0 or String(den["species"]) != "wolf":
			continue
		var home: Dictionary = _den_home.call(den) if _den_home.is_valid() else {}
		if home.is_empty() or int(home["sid"]) != sid:
			continue
		var d: float = (den["pos"] as Vector2).distance_to(home["pos"])
		if d < best_d:
			best_d = d
			best = den
	return best


func _post(day: int, sid: int, den: Dictionary, rq: RefCounted) -> Dictionary:
	var home: Dictionary = _den_home.call(den)
	var reward := BASE_REWARD + int(den["population"]) * 5
	_seq += 1
	var qid := "bounty_%d_%d_%d" % [sid, day, _seq]
	var q := RQ.make_bounty(qid, den, home["pos"], sid, reward, day)
	rq.offers.append(q)
	var b := {"sid": sid, "den_id": int(den["id"]), "quest_id": qid, "posted_day": day, "reward": reward,
		"state": "posted", "hunter": ""}
	bounties.append(b)
	bounty_posted.emit(b)
	return {"type": "bounty_posted", "sid": sid, "den_id": int(den["id"]), "reward": reward, "day": day,
		"text": "%s posts a %d gold bounty: wolves are taking livestock." % [String(home.get("name", "The village")), reward]}


func _hire(day: int, b: Dictionary, den: Dictionary, rq: RefCounted, pay: Callable) -> Array:
	var out: Array = []
	var fee := HUNTER_FEE + int(b["reward"]) / 2
	if pay.is_valid() and not bool(pay.call(int(b["sid"]), fee)):
		return out                      # too poor to hire anyone: the bounty stays posted
	var hname: String = HUNTER_NAMES[(hunters.size() + int(b["sid"])) % HUNTER_NAMES.size()]
	var hunter := {"id": "hunter_%d_%d" % [int(b["sid"]), hunters.size()], "name": hname, "sid": int(b["sid"]),
		"hired_day": day, "den_id": int(b["den_id"])}
	hunters.append(hunter)
	b["state"] = "hunter"
	b["hunter"] = hunter["id"]
	_drop_offer(rq, String(b["quest_id"]))
	# The hunter thins the pack (about half, at least one) on the day they are hired.
	_eco.cull(int(den["id"]), maxi(1, int(ceil(float(den["population"]) * 0.5))))
	hunter_hired.emit(b)
	out.append({"type": "hunter_hired", "sid": b["sid"], "hunter": hunter, "fee": fee, "day": day,
		"text": "%s hires %s to deal with the wolves nobody would hunt." % ["The village", hname]})
	return out


func serialize() -> Dictionary:
	return {"bounties": bounties.duplicate(true), "hunters": hunters.duplicate(true), "losses": _losses.duplicate(true),
		"seen_day": _seen_day, "seq": _seq}


func deserialize(d: Dictionary) -> void:
	bounties.assign(d.get("bounties", []))
	hunters.assign(d.get("hunters", []))
	_losses = (d.get("losses", {}) as Dictionary).duplicate(true)
	_seen_day = int(d.get("seen_day", 0))
	_seq = int(d.get("seq", 0))
