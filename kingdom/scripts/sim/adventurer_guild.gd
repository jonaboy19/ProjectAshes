class_name RAAdventurerGuild
extends RefCounted
## The Adventurer Guild. One branch per settlement, each with a commissions
## board rebuilt daily from the real state of the world: wolf dens and their
## threat, caravans that need an escort, things the market is short of,
## deliveries, rumours worth investigating, and the real open seats of the
## settlement's organisations (RACareers), so jobs can be found through the
## guild as well as at the door.
##
## Ranks F..S are earned with points from completed commissions. Rewards are
## balanced against village wages (5..30 gold/day, a Guard earns 9): an F job
## pays about one or two days of wages, a C job about a week.
##
## Pure data (serializable); nothing here touches nodes or autoloads.
##
## INTEGRATION (for Life / Frontier; not wired yet):
## - Life owns `var guild := RAAdventurerGuild.new()`, calls
##   `guild.add_branch(0, "Ashford Guild Hall")` for each settlement with a hall,
##   and sets `guild.context = _guild_context` where
##   `_guild_context(settlement: int, day: int) -> Dictionary` returns
##     {"dens": [{id, species, population, threat, distance}],   # from Frontier.ecology.dens,
##                                                               #   threat = Frontier.ecology.pressure_at(den.pos) total
##      "caravans": [{id, from, to, danger, days}],              # merchants moving goods (future)
##      "gathering": [{item, amount}],                           # market goods below target stock
##      "deliveries": [{item, to, days}],
##      "rumours": [{id, label, threat}],                        # Frontier.threat modifiers
##      "vacancies": RAAdventurerGuild.vacancies_from(careers, settlement)}
## - At hour 5 (with careers.tick_day) call `guild.tick_day(WorldSim.day)`; show
##   the returned events with Game.say and charge nothing (fines become debt).
## - Joining: `var r := guild.join(RAAdventurerGuild.PLAYER, 0, Game.gold, day)`;
##   on r.ok do Game.add_gold(-r.fee).
## - Life.on_wolf_killed -> `guild.on_kill(PLAYER, "wolf", den_id)`.
##   Selling/handing in herbs -> `guild.on_gathered(PLAYER, item, n)`.
##   careers.apply success -> `guild.on_hired(PLAYER, org_id, title, day)`.
## - `guild.complete(PLAYER, cid, day)` returns gold (after debt) and points;
##   Game.add_gold(r.gold). A rank-up to D is a scout scenario
##   (RAScouts.on_scenario(profile, "guild_rank_d", day)).
## - Save: snapshot["guild"] = guild.serialize(); restore after add_branch calls.

signal commission_posted(branch: Dictionary, commission: Dictionary)
signal rank_changed(member: int, rank: int)

const PLAYER := -1
const RANKS := ["F", "E", "D", "C", "B", "A", "S"]
## Lifetime points needed for each rank.
const RANK_POINTS := [0, 60, 180, 450, 1000, 2200, 5000]
## Reward gold band per rank [min, max]. Guard wage 9/day, Captain 30/day:
## F = 1..2 days, E = 2..3.5 days, D = 3..6 days, C = about a week (6..10 days).
const RANK_GOLD := [[9, 18], [16, 32], [28, 55], [55, 90], [100, 170], [180, 320], [350, 650]]
## Base points per rank (scaled 0.8..1.2 by difficulty inside the rank).
const RANK_REWARD_POINTS := [10, 18, 30, 50, 80, 130, 220]
const MEMBERSHIP_FEE := 10
## A member may take commissions up to this many ranks above their own.
const ACCEPT_ABOVE := 1
const MAX_ACTIVE := 3
const BOARD_SIZE := 12
## Failing (or abandoning) a commission: a fine of this share of the reward and
## the loss of this share of its points.
const FAIL_GOLD_SHARE := 0.25
const FAIL_POINT_SHARE := 0.5
## Chance per day that an eligible source becomes a posting (vacancies always post).
const POST_CHANCE := 0.75
const VACANCY_POINTS := 5
const DEADLINE_DAYS := {"cull": 5, "escort": 2, "gather": 4, "deliver": 3, "investigate": 6, "vacancy": 7}

## Branch: {settlement, name, board: Array[commission]}
var branches: Array[Dictionary] = []
## member id (int; PLAYER or a WorldSim person) -> {id, branch, rank, points,
## completed, failed, joined_day, debt}
var members: Dictionary = {}
## Callable(settlement: int, day: int) -> Dictionary; see header.
var context: Callable = func(_s: int, _d: int) -> Dictionary: return {}

var _next_id := 1
var _rng := RandomNumberGenerator.new()


func _init(seed_value := 2718) -> void:
	_rng.seed = seed_value


# --- branches ------------------------------------------------------------------

func add_branch(settlement: int, branch_name: String) -> Dictionary:
	var b := {"settlement": settlement, "name": branch_name, "board": []}
	branches.append(b)
	return b


func branch(settlement: int) -> Dictionary:
	for b in branches:
		if int(b["settlement"]) == settlement:
			return b
	return {}


# --- ranks & membership ----------------------------------------------------------

static func rank_name(rank: int) -> String:
	return RANKS[clampi(rank, 0, RANKS.size() - 1)]


static func rank_for_points(points: int) -> int:
	var r := 0
	for i in RANK_POINTS.size():
		if points >= int(RANK_POINTS[i]):
			r = i
	return r


## Rank a threat value (0..100, from RAThreatMap / den pressure) calls for.
static func rank_for_threat(threat: float) -> int:
	return clampi(int(threat / 14.0), 0, RANKS.size() - 1)


## Gold and points for a commission of `rank` at difficulty t (0..1) inside that rank.
static func reward_for(rank: int, t: float) -> Dictionary:
	var band: Array = RANK_GOLD[rank]
	var tt := clampf(t, 0.0, 1.0)
	return {"gold": int(round(lerpf(float(band[0]), float(band[1]), tt))),
		"points": int(round(float(RANK_REWARD_POINTS[rank]) * lerpf(0.8, 1.2, tt)))}


func is_member(who: int) -> bool:
	return members.has(who)


func member(who: int) -> Dictionary:
	return members.get(who, {})


## Join at a branch. Returns {ok, fee, text}. The caller deducts the fee.
func join(who: int, settlement: int, gold: int, day: int) -> Dictionary:
	if is_member(who):
		return {"ok": false, "fee": 0, "text": "You are already a guild member."}
	var b := branch(settlement)
	if b.is_empty():
		return {"ok": false, "fee": 0, "text": "There is no guild hall here."}
	if gold < MEMBERSHIP_FEE:
		return {"ok": false, "fee": 0, "text": "Membership costs %d gold." % MEMBERSHIP_FEE}
	members[who] = {"id": who, "branch": settlement, "rank": 0, "points": 0, "completed": 0,
		"failed": 0, "joined_day": day, "debt": 0}
	return {"ok": true, "fee": MEMBERSHIP_FEE,
		"text": "Registered at %s as an F-rank adventurer." % b["name"]}


## Adds points (may be negative, floored at 0). Rank only ever goes up.
## Returns the new rank if it rose, else -1.
func add_points(who: int, amount: int) -> int:
	var m := member(who)
	if m.is_empty():
		return -1
	m["points"] = maxi(0, int(m["points"]) + amount)
	var r := rank_for_points(int(m["points"]))
	if r > int(m["rank"]):
		m["rank"] = r
		rank_changed.emit(who, r)
		return r
	return -1


## Pays towards a member's fines. Returns the gold actually used.
func settle_debt(who: int, gold: int) -> int:
	var m := member(who)
	if m.is_empty():
		return 0
	var paid := mini(gold, int(m["debt"]))
	m["debt"] = int(m["debt"]) - paid
	return paid


# --- board ---------------------------------------------------------------------

func board(settlement: int) -> Array:
	return branch(settlement).get("board", [])


func commission(cid: int) -> Dictionary:
	for b in branches:
		for c: Dictionary in b["board"]:
			if int(c["id"]) == cid:
				return c
	return {}


## Commissions currently accepted by `who`.
func active_for(who: int) -> Array:
	var out := []
	for b in branches:
		for c: Dictionary in b["board"]:
			if c["state"] == "accepted" and int(c["taker"]) == who:
				out.append(c)
	return out


## Open commissions a member could take right now.
func available_for(who: int, settlement: int) -> Array:
	var out := []
	for c: Dictionary in board(settlement):
		if c["state"] == "open" and check_accept(who, int(c["id"])) == "":
			out.append(c)
	return out


## The daily step: overdue commissions expire (open) or fail (accepted), then the
## board is refilled from the world. Returns events [{type, commission, text, ...}].
func tick_day(day: int) -> Array:
	var events := []
	for b in branches:
		var keep := []
		for c: Dictionary in (b["board"] as Array).duplicate():
			var state := String(c["state"])
			if state == "open" and day > int(c["deadline"]):
				c["state"] = "expired"
				events.append({"type": "expired", "commission": c, "text": "Expired: %s." % c["title"]})
				continue
			if state == "accepted" and day > int(c["deadline"]):
				var r := fail(int(c["taker"]), int(c["id"]), day, "deadline passed")
				events.append({"type": "failed", "commission": c, "member": int(c["taker"]),
					"fine": r["fine"], "text": r["text"]})
			if state == "open" or String(c["state"]) == "accepted":
				keep.append(c)
		b["board"] = keep
		for c: Dictionary in _generate(b, day):
			events.append({"type": "posted", "commission": c, "text": "New commission: %s." % c["title"]})
	return events


func _has_source(b: Dictionary, source: String) -> bool:
	for c: Dictionary in b["board"]:
		if c["source"] == source:
			return true
	return false


func _generate(b: Dictionary, day: int) -> Array:
	var ctx: Dictionary = context.call(int(b["settlement"]), day)
	# Real vacancies always post first; the rest are interleaved by type so one
	# busy category (eight dens) can't crowd the board.
	var fresh := []
	for v: Dictionary in ctx.get("vacancies", []):
		var src := "vacancy:%s/%s" % [v["org"], v["seat"]]
		if not _has_source(b, src):
			fresh.append(_make_vacancy(v, src, day))
	var groups := [[], [], [], [], []]
	for d: Dictionary in ctx.get("dens", []):
		var src := "cull:%d" % int(d["id"])
		if int(d.get("population", 0)) > 0 and not _has_source(b, src) and _rng.randf() < POST_CHANCE:
			groups[0].append(_make_cull(d, src, day))
	for cv: Dictionary in ctx.get("caravans", []):
		var src := "escort:%s" % cv["id"]
		if not _has_source(b, src) and _rng.randf() < POST_CHANCE:
			groups[1].append(_make_escort(cv, src, day))
	for g: Dictionary in ctx.get("gathering", []):
		var src := "gather:%s" % g["item"]
		if not _has_source(b, src) and _rng.randf() < POST_CHANCE:
			groups[2].append(_make_gather(g, src, day))
	for dl: Dictionary in ctx.get("deliveries", []):
		var src := "deliver:%s:%s" % [dl["item"], dl["to"]]
		if not _has_source(b, src) and _rng.randf() < POST_CHANCE:
			groups[3].append(_make_deliver(dl, src, day))
	for ru: Dictionary in ctx.get("rumours", []):
		var src := "investigate:%s" % ru["id"]
		if not _has_source(b, src) and _rng.randf() < POST_CHANCE:
			groups[4].append(_make_investigate(ru, src, day))
	var i := 0
	var added := true
	while added:
		added = false
		for grp: Array in groups:
			if i < grp.size():
				fresh.append(grp[i])
				added = true
		i += 1
	var posted := []
	for c: Dictionary in fresh:
		if b["board"].size() >= BOARD_SIZE:
			break
		c["id"] = _next_id
		_next_id += 1
		c["branch"] = int(b["settlement"])
		b["board"].append(c)
		posted.append(c)
		commission_posted.emit(b, c)
	return posted


func _base(type: String, source: String, rank: int, t: float, day: int, days: int) -> Dictionary:
	var rw := reward_for(rank, t)
	var gold: int = rw["gold"]
	var points: int = rw["points"]
	return {"id": 0, "branch": 0, "type": type, "source": source, "title": "", "rank": rank,
		"reward": gold, "points": points, "posted_day": day, "deadline": day + days,
		"penalty": {"gold": int(ceil(gold * FAIL_GOLD_SHARE)), "points": int(ceil(points * FAIL_POINT_SHARE))},
		"target": {}, "required": 1, "progress": 0, "state": "open", "taker": 0}


func _make_cull(d: Dictionary, source: String, day: int) -> Dictionary:
	var threat := float(d.get("threat", 10.0))
	var rank := rank_for_threat(threat)
	var pop := int(d["population"])
	var kills := clampi(int(ceil(pop * 0.5)), 1, pop)
	var frac := fposmod(threat, 14.0) / 14.0 if rank < RANKS.size() - 1 else 1.0
	var c := _base("cull", source, rank, frac * 0.7 + clampf(kills / 10.0, 0.0, 1.0) * 0.3, day,
		int(DEADLINE_DAYS["cull"]))
	var species := String(d.get("species", "wolf"))
	c["target"] = {"den": int(d["id"]), "species": species}
	c["required"] = kills
	var plural: String = ({"wolf": "wolves"} as Dictionary).get(species, species + "s") if kills != 1 else species
	var where := String(d.get("place", ""))
	if where == "":
		where = "%dm %s" % [int(d.get("distance", 0.0)), String(d.get("compass", "out"))]
	c["title"] = "Cull %d %s (%s)" % [kills, plural, where]
	return c


func _make_escort(cv: Dictionary, source: String, day: int) -> Dictionary:
	var danger := float(cv.get("danger", 15.0))
	var rank := maxi(1, rank_for_threat(danger))
	var days := maxi(1, int(cv.get("days", 1)))
	var c := _base("escort", source, rank, fposmod(danger, 14.0) / 14.0, day, days + int(DEADLINE_DAYS["escort"]))
	c["target"] = {"caravan": String(cv["id"]), "from": String(cv.get("from", "")), "to": String(cv.get("to", ""))}
	c["title"] = "Escort the %s caravan to %s" % [String(cv.get("from", "merchant")), String(cv.get("to", "the next town"))]
	return c


func _make_gather(g: Dictionary, source: String, day: int) -> Dictionary:
	var amount := maxi(1, int(g.get("amount", 5)))
	var rank := 1 if amount > 12 else 0
	var c := _base("gather", source, rank, clampf(amount / 12.0, 0.0, 1.0), day, int(DEADLINE_DAYS["gather"]))
	c["target"] = {"item": String(g["item"])}
	c["required"] = amount
	c["title"] = "Gather %d %s" % [amount, String(g["item"]).replace("_", " ")]
	return c


func _make_deliver(dl: Dictionary, source: String, day: int) -> Dictionary:
	var days := maxi(1, int(dl.get("days", 1)))
	var c := _base("deliver", source, 0, clampf(days / 4.0, 0.0, 1.0), day, days + int(DEADLINE_DAYS["deliver"]))
	c["target"] = {"item": String(dl["item"]), "to": String(dl["to"])}
	c["title"] = "Deliver %s to %s" % [String(dl["item"]).replace("_", " "), String(dl["to"])]
	return c


func _make_investigate(ru: Dictionary, source: String, day: int) -> Dictionary:
	var threat := float(ru.get("threat", 30.0))
	var rank := maxi(2, rank_for_threat(threat))
	var c := _base("investigate", source, rank, fposmod(threat, 14.0) / 14.0, day, int(DEADLINE_DAYS["investigate"]))
	c["target"] = {"rumour": String(ru["id"])}
	c["title"] = "Investigate: %s" % String(ru.get("label", "strange tracks"))
	return c


func _make_vacancy(v: Dictionary, source: String, day: int) -> Dictionary:
	var c := _base("vacancy", source, 0, 0.0, day, int(DEADLINE_DAYS["vacancy"]))
	c["reward"] = 0
	c["points"] = VACANCY_POINTS
	c["penalty"] = {"gold": 0, "points": 0}
	c["target"] = {"org": String(v["org"]), "seat": String(v["seat"]), "wage": int(v.get("wage", 0))}
	c["title"] = "Vacancy: %s at %s (%d gold/day)" % [v["seat"], v.get("org_name", v["org"]), int(v.get("wage", 0))]
	return c


## Open seats of a settlement's organisations as guild vacancy sources.
static func vacancies_from(careers: RACareers, settlement: int) -> Array:
	var out := []
	for o in careers.orgs:
		if int(o["settlement"]) != settlement:
			continue
		for v: Dictionary in careers.vacancies(o["id"]):
			var s: Dictionary = v["seat"]
			if int(s["merit"]) >= 9999:
				continue   # owner seats are never advertised
			out.append({"org": o["id"], "org_name": o["name"], "seat": s["title"], "wage": int(s["wage"]),
				"open": int(v["open"])})
	return out


# --- commission flow -------------------------------------------------------------

## Why `who` cannot accept commission `cid`, or "".
func check_accept(who: int, cid: int) -> String:
	var m := member(who)
	if m.is_empty():
		return "Only guild members can take commissions."
	var c := commission(cid)
	if c.is_empty():
		return "That commission is gone."
	if c["state"] != "open":
		return "That commission is already taken."
	if int(m["debt"]) > 0:
		return "Settle your fine of %d gold first." % int(m["debt"])
	if int(c["rank"]) > int(m["rank"]) + ACCEPT_ABOVE:
		return "This needs rank %s; you are %s." % [rank_name(int(c["rank"])), rank_name(int(m["rank"]))]
	if c["type"] != "vacancy" and _active_count(who) >= MAX_ACTIVE:
		return "You already carry %d commissions." % MAX_ACTIVE
	return ""


func _active_count(who: int) -> int:
	var n := 0
	for c: Dictionary in active_for(who):
		if c["type"] != "vacancy":
			n += 1
	return n


## Returns "" or the refusal.
func accept(who: int, cid: int, day: int) -> String:
	var why := check_accept(who, cid)
	if why != "":
		return why
	var c := commission(cid)
	c["state"] = "accepted"
	c["taker"] = who
	c["accepted_day"] = day
	return ""


## Adds progress to an accepted commission. Returns true when it is ready to hand in.
func progress(who: int, cid: int, amount := 1) -> bool:
	var c := commission(cid)
	if c.is_empty() or c["state"] != "accepted" or int(c["taker"]) != who:
		return false
	c["progress"] = mini(int(c["required"]), int(c["progress"]) + amount)
	return is_ready(cid)


func is_ready(cid: int) -> bool:
	var c := commission(cid)
	return not c.is_empty() and int(c["progress"]) >= int(c["required"])


## A kill by `who`. Counts towards their cull commissions for that den (or any den
## of the species when den_id < 0). Returns the ids of commissions now ready.
func on_kill(who: int, species: String, den_id := -1) -> Array:
	var ready := []
	for c: Dictionary in active_for(who):
		if c["type"] != "cull":
			continue
		var t: Dictionary = c["target"]
		if t["species"] == species and (den_id < 0 or int(t["den"]) == den_id):
			if progress(who, int(c["id"])):
				ready.append(int(c["id"]))
	return ready


func on_gathered(who: int, item: String, amount := 1) -> Array:
	var ready := []
	for c: Dictionary in active_for(who):
		if c["type"] == "gather" and c["target"]["item"] == item:
			if progress(who, int(c["id"]), amount):
				ready.append(int(c["id"]))
	return ready


## `who` took a seat through careers; completes the matching vacancy posting.
## Returns the completion result or {}.
func on_hired(who: int, org_id: String, title: String, day: int) -> Dictionary:
	for b in branches:
		for c: Dictionary in b["board"]:
			if c["type"] != "vacancy" or c["target"]["org"] != org_id or c["target"]["seat"] != title:
				continue
			if c["state"] == "open" and is_member(who):
				c["state"] = "accepted"
				c["taker"] = who
			if c["state"] == "accepted" and int(c["taker"]) == who:
				c["progress"] = 1
				return complete(who, int(c["id"]), day)
	return {}


## Hand in a finished commission. Returns {ok, gold, points, fine_paid, rank_up, rank, text}.
## `gold` is already net of any outstanding fine.
func complete(who: int, cid: int, day: int) -> Dictionary:
	var c := commission(cid)
	if c.is_empty() or c["state"] != "accepted" or int(c["taker"]) != who:
		return {"ok": false, "gold": 0, "points": 0, "text": "You hold no such commission."}
	if int(c["progress"]) < int(c["required"]):
		return {"ok": false, "gold": 0, "points": 0,
			"text": "Not done yet: %d of %d." % [int(c["progress"]), int(c["required"])]}
	if day > int(c["deadline"]):
		var f := fail(who, cid, day, "too late")
		return {"ok": false, "gold": 0, "points": 0, "text": f["text"]}
	c["state"] = "completed"
	_remove(cid)
	var m := member(who)
	var fine := settle_debt(who, int(c["reward"]))
	m["completed"] = int(m["completed"]) + 1
	var up := add_points(who, int(c["points"]))
	var text := "Commission complete: %s. +%d gold, +%d points." % [c["title"], int(c["reward"]) - fine, int(c["points"])]
	if up >= 0:
		text += " You are now %s rank!" % rank_name(up)
	return {"ok": true, "gold": int(c["reward"]) - fine, "points": int(c["points"]), "fine_paid": fine,
		"rank_up": up >= 0, "rank": int(m["rank"]), "commission": c, "text": text}


## Failure or abandonment: the fine becomes guild debt, points are lost.
## Returns {ok, fine, points_lost, text}.
func fail(who: int, cid: int, _day: int, reason := "abandoned") -> Dictionary:
	var c := commission(cid)
	if c.is_empty() or c["state"] != "accepted" or int(c["taker"]) != who:
		return {"ok": false, "fine": 0, "points_lost": 0, "text": "You hold no such commission."}
	c["state"] = "failed"
	_remove(cid)
	var m := member(who)
	var pen: Dictionary = c["penalty"]
	var fine := int(pen["gold"])
	var lost := int(pen["points"])
	if not m.is_empty():
		m["failed"] = int(m["failed"]) + 1
		m["debt"] = int(m["debt"]) + fine
		add_points(who, -lost)
	return {"ok": true, "fine": fine, "points_lost": lost, "commission": c,
		"text": "Commission failed (%s): %s. Fine %d gold, -%d points." % [reason, c["title"], fine, lost]}


func _remove(cid: int) -> void:
	for b in branches:
		var brd: Array = b["board"]
		for i in brd.size():
			if int(brd[i]["id"]) == cid:
				brd.remove_at(i)
				return


# --- save / load -----------------------------------------------------------------

func serialize() -> Dictionary:
	var bs := []
	for b in branches:
		bs.append({"settlement": b["settlement"], "name": b["name"], "board": (b["board"] as Array).duplicate(true)})
	var ms := {}
	for who: int in members:
		ms[str(who)] = (members[who] as Dictionary).duplicate()
	return {"branches": bs, "members": ms, "next_id": _next_id, "rng": str(_rng.state)}


func deserialize(data: Dictionary) -> void:
	for bd: Dictionary in data.get("branches", []):
		var b := branch(int(bd["settlement"]))
		if b.is_empty():
			b = add_branch(int(bd["settlement"]), String(bd["name"]))
		var brd := []
		for c: Dictionary in bd.get("board", []):
			brd.append(_norm_commission(c))
		b["board"] = brd
	members.clear()
	var ms: Dictionary = data.get("members", {})
	for key: String in ms:
		var m: Dictionary = ms[key]
		var who := int(key)
		members[who] = {"id": who, "branch": int(m["branch"]), "rank": int(m["rank"]), "points": int(m["points"]),
			"completed": int(m["completed"]), "failed": int(m["failed"]), "joined_day": int(m["joined_day"]),
			"debt": int(m["debt"])}
	_next_id = int(data.get("next_id", _next_id))
	if data.has("rng"):
		_rng.state = String(data["rng"]).to_int()


static func _norm_commission(c: Dictionary) -> Dictionary:
	var out := c.duplicate(true)
	for k in ["id", "branch", "rank", "reward", "points", "posted_day", "deadline", "required", "progress", "taker", "accepted_day"]:
		if out.has(k):
			out[k] = int(out[k])
	var pen: Dictionary = out["penalty"]
	out["penalty"] = {"gold": int(pen["gold"]), "points": int(pen["points"])}
	var t: Dictionary = out["target"]
	for k in ["den", "wage"]:
		if t.has(k):
			t[k] = int(t[k])
	return out
