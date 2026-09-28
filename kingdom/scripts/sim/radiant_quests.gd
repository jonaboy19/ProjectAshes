extends RefCounted
## Radiant quests: small jobs generated from the state of the world, offered by
## the people who would need them (the healer wants herbs, the guild wants a den
## thinned, a worried villager has lost a child) and posted on the guild board.
##
## Kinds, each only when the world has what it needs:
##   fetch_herbs  - bring healing herbs to the healer (gather, then return)
##   clear_wolves - thin a living wolf den (Frontier.ecology.dens), then report
##   deliver      - carry goods to Cinderpost Waystation (WorldGen.sites)
##   escort       - meet a trader in the square and walk them to the waystation
##   lost_child   - search near Whisper Hollow and bring the child home
##
## Generation is pure and deterministic: generate(world, seed, day) gives the
## same quests for the same inputs. `world` is a plain Dictionary so tests can
## build one by hand (world_from_game() in VillageServices builds the live one):
##   {home: Vector2, dens: [{id, species, pos: Vector2, population, alive}],
##    sites: [{name, kind, pos: Vector2}], places: {id: {name, kind, pos: Vector2, radius}}}
##
## Progress is polled, so no other system has to call in: update(ctx) with
##   ctx = {pos: Vector2, day: float, count_item: Callable(item) -> int,
##          den_population: Callable(den_id) -> int  (-1 when the den is gone)}
## returns events [{type: "stage"|"ready"|"complete"|"failed", quest, text}].
## "complete" and turn_in() quests carry `reward` {gold, rep: {faction: n}, opinion};
## the caller pays it (keeps this file free of autoloads).
##
## Quest Weaver (addons/quest_weaver) runs quests authored as graphs in the
## editor, so generated quests are tracked here; VillageServices mirrors their
## life cycle onto QuestWeaverGlobal.quest_event_fired for graph quests to hear.

const KINDS := ["fetch_herbs", "clear_wolves", "deliver", "escort", "lost_child"]
const KIND_ROLE := {"fetch_herbs": "healer", "clear_wolves": "guild", "deliver": "villager",
	"escort": "guild", "lost_child": "villager"}
const MAX_ACTIVE := 3
const BOARD_SIZE := 5
const OFFER_DAYS := 4
const CHILD_NAMES := ["Pip", "Tam", "Wren", "Lotte", "Hob", "Merry", "Col", "Bess", "Nell", "Dunny"]
const TRADER_NAMES := ["Odo Farrow", "Gilda Pennick", "Sten Coldbrook", "Maris Hollins", "Bertil Oakes"]
const GOODS := ["salted mutton", "barley sacks", "lamp oil", "horseshoes", "wool bolts", "cider casks"]

var offers: Array[Dictionary] = []
var active: Array[Dictionary] = []
var completed := 0
var failed := 0
## Quest id the compass follows ("" = the first active quest).
var tracked := ""
var last_refill_day := -999


# --- generation -------------------------------------------------------------------

## `count` quests for this world, seed and day. Same inputs, same quests.
static func generate(world: Dictionary, seed_value: int, day: int, count := BOARD_SIZE) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, day, "radiant"])
	var kinds: Array = available_kinds(world)
	var out: Array[Dictionary] = []
	if kinds.is_empty():
		return out
	# Every available kind once in a shuffled order, then random repeats.
	var order: Array = []
	var pool: Array = kinds.duplicate()
	while not pool.is_empty():
		order.append(pool.pop_at(rng.randi() % pool.size()))
	while order.size() < count:
		order.append(kinds[rng.randi() % kinds.size()])
	for i in count:
		var q := _make(String(order[i]), world, rng)
		if q.is_empty():
			continue
		q["id"] = "rq_%d_%d_%d" % [absi(seed_value) % 100000, day, i]
		q["offered_day"] = day
		out.append(q)
	return out


static func available_kinds(world: Dictionary) -> Array:
	var out: Array = ["fetch_herbs"]
	if not _live_wolf_dens(world).is_empty():
		out.append("clear_wolves")
	if not _waystation(world).is_empty():
		out.append("deliver")
		out.append("escort")
	if (world.get("places", {}) as Dictionary).has("whisper_hollow"):
		out.append("lost_child")
	return out


static func _live_wolf_dens(world: Dictionary) -> Array:
	var out: Array = []
	for d: Dictionary in world.get("dens", []):
		if bool(d.get("alive", true)) and String(d.get("species", "")) == "wolf" and int(d.get("population", 0)) > 0:
			out.append(d)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return out


static func _waystation(world: Dictionary) -> Dictionary:
	for s: Dictionary in world.get("sites", []):
		if String(s.get("kind", "")) == "waystation":
			return {"name": String(s.get("name", "Cinderpost Waystation")), "pos": s["pos"]}
	var pl: Dictionary = world.get("places", {}).get("cinderpost_waystation", {})
	if not pl.is_empty():
		return {"name": String(pl.get("name", "Cinderpost Waystation")), "pos": pl["pos"]}
	return {}


static func _compass(v: Vector2) -> String:
	var dirs := ["east", "southeast", "south", "southwest", "west", "northwest", "north", "northeast"]
	return dirs[int(round(fposmod(atan2(v.y, v.x), TAU) / (TAU / 8.0))) % 8]


static func _stage(type: String, text: String, pos: Vector2, radius: float, extra := {}) -> Dictionary:
	var s := {"type": type, "text": text, "pos": pos, "radius": radius}
	s.merge(extra)
	return s


static func _make(kind: String, world: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var home: Vector2 = world.get("home", Vector2.ZERO)
	var q := {"kind": kind, "giver_role": KIND_ROLE[kind], "giver": "", "giver_name": "", "giver_pos": home,
		"stage": 0, "state": "offered", "progress": 0, "baseline": -1, "deadline": -1, "data": {}}
	match kind:
		"fetch_herbs":
			var n := rng.randi_range(3, 6)
			var ang := rng.randf() * TAU
			var spot := home + Vector2(cos(ang), sin(ang)) * rng.randf_range(90.0, 220.0)
			q["title"] = "Herbs for the healer"
			q["desc"] = "The herbalist is low on healing herbs. Bring %d; they grow in meadows and on forest floors, thickest %s of the village." % [n, _compass(spot - home)]
			q["stages"] = [_stage("gather", "Gather %d healing herbs" % n, spot, 60.0, {"item": "healing_herb", "amount": n}),
				_stage("return", "Bring the herbs to the herbalist", home, 6.0)]
			q["reward"] = {"gold": 4 + n * 3, "rep": {"ashford": 3}, "opinion": 10}
			q["days"] = 6
		"clear_wolves":
			var dens := _live_wolf_dens(world)
			var den: Dictionary = dens[rng.randi() % dens.size()]
			var p: Vector2 = den["pos"]
			var kills := clampi(rng.randi_range(2, 4), 1, int(den["population"]))
			var far := int(p.distance_to(home))
			q["title"] = "Wolves %s of the village" % _compass(p - home)
			q["desc"] = "A wolf den %d m %s has grown bold. Kill %d of the pack and report back." % [far, _compass(p - home), kills]
			q["stages"] = [_stage("kill_den", "Kill %d wolves near the den" % kills, p, 40.0, {"den_id": int(den["id"]), "kills": kills}),
				_stage("return", "Report to whoever sent you", home, 6.0)]
			q["reward"] = {"gold": 10 + kills * 5 + far / 60, "rep": {"ashford": 4, "adventurer_guild": 6}, "opinion": 8}
			q["days"] = 8
		"deliver":
			var w := _waystation(world)
			var goods: String = GOODS[rng.randi() % GOODS.size()]
			var p2: Vector2 = w["pos"]
			q["title"] = "Delivery to %s" % w["name"]
			q["desc"] = "A crate of %s is owed at %s, %d m %s along the King's Ember Road." % [goods, w["name"], int(p2.distance_to(home)), _compass(p2 - home)]
			q["stages"] = [_stage("reach", "Deliver the %s to %s" % [goods, w["name"]], p2, 16.0)]
			q["reward"] = {"gold": 8 + int(p2.distance_to(home)) / 40, "rep": {"ashford": 2, "crown_caldrenn": 3}, "opinion": 8}
			q["data"] = {"goods": goods}
			q["days"] = 5
		"escort":
			var w2 := _waystation(world)
			var trader: String = TRADER_NAMES[rng.randi() % TRADER_NAMES.size()]
			var meet := home + Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0))
			var p3: Vector2 = w2["pos"]
			q["title"] = "Escort %s" % trader
			q["desc"] = "The trader %s needs a sword beside the cart on the road to %s. Meet them in the square." % [trader, w2["name"]]
			q["stages"] = [_stage("reach", "Meet %s in Ashford's square" % trader, meet, 8.0),
				_stage("reach", "Escort %s to %s" % [trader, w2["name"]], p3, 18.0)]
			q["reward"] = {"gold": 14 + int(p3.distance_to(home)) / 30, "rep": {"crown_caldrenn": 5, "adventurer_guild": 3}, "opinion": 6}
			q["data"] = {"trader": trader}
			q["days"] = 4
		"lost_child":
			var hollow: Dictionary = world["places"]["whisper_hollow"]
			var hp: Vector2 = hollow["pos"]
			var child: String = CHILD_NAMES[rng.randi() % CHILD_NAMES.size()]
			var ang2 := rng.randf() * TAU
			var search := hp + Vector2(cos(ang2), sin(ang2)) * rng.randf_range(4.0, 22.0)
			q["title"] = "Little %s is missing" % child
			q["desc"] = "%s wandered off chasing lights toward %s and hasn't come home." % [child, hollow.get("name", "Whisper Hollow")]
			q["stages"] = [_stage("reach", "Search near %s for %s" % [hollow.get("name", "Whisper Hollow"), child], search, 9.0),
				_stage("reach", "Bring %s home to Ashford" % child, home, 30.0)]
			q["reward"] = {"gold": 12, "rep": {"ashford": 8}, "opinion": 15}
			q["data"] = {"child": child}
			q["days"] = 3
		_:
			return {}
	return q


# --- board ------------------------------------------------------------------------

## Daily upkeep: stale offers go, overdue quests fail, the board refills.
## Returns failure events.
func tick_day(day: int, world: Dictionary, seed_value: int) -> Array:
	var events: Array = []
	offers.assign(offers.filter(func(q: Dictionary) -> bool: return day - int(q["offered_day"]) < OFFER_DAYS))
	for q: Dictionary in active.duplicate():
		if int(q["deadline"]) >= 0 and day > int(q["deadline"]):
			active.erase(q)
			q["state"] = "failed"
			failed += 1
			events.append({"type": "failed", "quest": q, "text": "Quest failed: %s (out of time)." % q["title"]})
	if day != last_refill_day:
		last_refill_day = day
		var want := BOARD_SIZE - offers.size()
		if want > 0:
			for q: Dictionary in generate(world, seed_value, day, want):
				if find(String(q["id"])).is_empty():
					offers.append(q)
	return events


func find(id: String) -> Dictionary:
	for q: Dictionary in offers:
		if q["id"] == id:
			return q
	for q: Dictionary in active:
		if q["id"] == id:
			return q
	return {}


## Offers a giver of this role would make. Villagers only ask people they know
## (tier_rank: 0 enemy .. 5 close friend, see Relationships.tier_rank); the
## guild and the healer offer to anyone.
func offers_for(role: String, tier_rank := 3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if role == "villager" and tier_rank < 3:
		return out
	if tier_rank <= 1:
		return out       # rivals and enemies won't trust you with anything
	for q: Dictionary in offers:
		if q["giver_role"] == role:
			out.append(q)
	return out


func can_accept(id: String) -> String:
	var q := find(id)
	if q.is_empty() or q["state"] != "offered":
		return "That job has been taken."
	if active.size() >= MAX_ACTIVE:
		return "You already carry %d jobs." % MAX_ACTIVE
	return ""


## Takes an offer. `giver`/`giver_name`/`giver_pos` say who to report back to;
## `bonus_opinion` lets friends reward friends. `ctx` as for update() (the den's
## population at acceptance is the baseline for kills).
func accept(id: String, day: int, giver := "", giver_name := "", giver_pos: Variant = null, ctx := {}, bonus_opinion := 0) -> String:
	var why := can_accept(id)
	if why != "":
		return why
	var q := find(id)
	offers.erase(q)
	q["state"] = "active"
	q["giver"] = giver
	q["giver_name"] = giver_name
	if giver_pos is Vector2:
		q["giver_pos"] = giver_pos
		for s: Dictionary in q["stages"]:
			if s["type"] == "return":
				s["pos"] = giver_pos
	q["deadline"] = day + int(q.get("days", 5))
	q["reward"]["opinion"] = int(q["reward"]["opinion"]) + bonus_opinion
	var st := current_stage(q)
	if st.get("type", "") == "kill_den" and ctx.has("den_population"):
		q["baseline"] = int((ctx["den_population"] as Callable).call(int(st["den_id"])))
	active.append(q)
	if tracked == "":
		tracked = id
	return ""


func abandon(id: String) -> void:
	var q := find(id)
	if q.is_empty() or q["state"] == "offered":
		return
	active.erase(q)
	failed += 1
	if tracked == id:
		tracked = ""


static func current_stage(q: Dictionary) -> Dictionary:
	var stages: Array = q.get("stages", [])
	var i := int(q.get("stage", 0))
	return stages[i] if i >= 0 and i < stages.size() else {}


## Polls progress. See the header for ctx and the events returned.
func update(ctx: Dictionary) -> Array:
	var events: Array = []
	var pos: Vector2 = ctx.get("pos", Vector2.INF)
	for q: Dictionary in active.duplicate():
		if q["state"] != "active":
			continue
		var guard := 0
		while guard < 8:
			guard += 1
			var s := current_stage(q)
			if s.is_empty() or not _stage_done(q, s, pos, ctx):
				break
			if s["type"] == "return":
				break
			q["stage"] = int(q["stage"]) + 1
			q["progress"] = 0
			var nxt := current_stage(q)
			if nxt.is_empty():
				active.erase(q)
				q["state"] = "done"
				completed += 1
				if tracked == q["id"]:
					tracked = ""
				events.append({"type": "complete", "quest": q, "reward": q["reward"],
					"text": "Quest complete: %s" % q["title"]})
				break
			if nxt["type"] == "kill_den" and ctx.has("den_population"):
				q["baseline"] = int((ctx["den_population"] as Callable).call(int(nxt["den_id"])))
			events.append({"type": "ready" if nxt["type"] == "return" else "stage", "quest": q, "text": nxt["text"]})
	return events


func _stage_done(q: Dictionary, s: Dictionary, pos: Vector2, ctx: Dictionary) -> bool:
	match String(s["type"]):
		"reach":
			return pos.distance_to(s["pos"]) <= float(s["radius"])
		"gather":
			if not ctx.has("count_item"):
				return false
			var have := int((ctx["count_item"] as Callable).call(String(s["item"])))
			q["progress"] = mini(have, int(s["amount"]))
			return have >= int(s["amount"])
		"kill_den":
			if not ctx.has("den_population"):
				return false
			var popn := int((ctx["den_population"] as Callable).call(int(s["den_id"])))
			if popn < 0:
				q["progress"] = int(s["kills"])
				return true
			if int(q["baseline"]) < 0:
				q["baseline"] = popn
			q["progress"] = maxi(int(q["progress"]), int(q["baseline"]) - popn)
			return int(q["progress"]) >= int(s["kills"])
		"return":
			return true
	return false


## Kills reported directly (optional; polling the den covers it too).
func on_kill(den_id: int) -> void:
	for q: Dictionary in active:
		var s := current_stage(q)
		if s.get("type", "") == "kill_den" and int(s["den_id"]) == den_id:
			q["progress"] = int(q["progress"]) + 1
			q["baseline"] = int(q["baseline"]) + 1   # keeps the polled count from double-counting


## Active quests waiting on a report to this giver id (or role when giver is "").
func ready_for(giver: String, role := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q: Dictionary in active:
		if current_stage(q).get("type", "") != "return":
			continue
		if (giver != "" and q["giver"] == giver) or (role != "" and q["giver_role"] == role):
			out.append(q)
	return out


## Reports a finished quest. {ok, text, quest, reward, take: {item: amount}}; the
## caller removes `take` from the inventory and pays `reward`.
func turn_in(id: String, count_item := Callable()) -> Dictionary:
	var q := find(id)
	if q.is_empty() or current_stage(q).get("type", "") != "return":
		return {"ok": false, "text": "There's nothing to report yet."}
	var take := {}
	for s: Dictionary in q["stages"]:
		if s["type"] == "gather":
			var have := int(count_item.call(String(s["item"]))) if count_item.is_valid() else 0
			if have < int(s["amount"]):
				return {"ok": false, "text": "You need %d %s (you have %d)." % [int(s["amount"]), String(s["item"]).replace("_", " "), have]}
			take[s["item"]] = int(s["amount"])
	active.erase(q)
	q["state"] = "done"
	completed += 1
	if tracked == id:
		tracked = ""
	return {"ok": true, "text": "Quest complete: %s" % q["title"], "quest": q, "reward": q["reward"], "take": take}


func tracked_quest() -> Dictionary:
	if tracked != "":
		var q := find(tracked)
		if not q.is_empty() and q["state"] == "active":
			return q
	return active[0] if not active.is_empty() else {}


## Where the compass should point: the tracked quest's current objective, or null.
func active_objective_position() -> Variant:
	var q := tracked_quest()
	if q.is_empty():
		return null
	var s := current_stage(q)
	return s.get("pos", null)


## One line per active quest for journals: "Herbs for the healer — Gather 4 healing herbs (2/4)".
func journal_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for q: Dictionary in active:
		var s := current_stage(q)
		var extra := ""
		match String(s.get("type", "")):
			"gather":
				extra = " (%d/%d)" % [int(q["progress"]), int(s["amount"])]
			"kill_den":
				extra = " (%d/%d)" % [int(q["progress"]), int(s["kills"])]
		out.append("%s%s — %s%s · due day %d" % ["▸ " if q == tracked_quest() else "", q["title"], s.get("text", ""), extra, int(q["deadline"])])
	return out


# --- save -------------------------------------------------------------------------

static func _enc(v: Variant) -> Variant:
	if v is Vector2:
		return {"__v2": [v.x, v.y]}
	if v is Dictionary:
		var d := {}
		for k: Variant in v:
			d[k] = _enc(v[k])
		return d
	if v is Array:
		var a: Array = []
		for x: Variant in v:
			a.append(_enc(x))
		return a
	return v


static func _dec(v: Variant) -> Variant:
	if v is Dictionary:
		if v.has("__v2"):
			return Vector2(float(v["__v2"][0]), float(v["__v2"][1]))
		var d := {}
		for k: Variant in v:
			d[k] = _dec(v[k])
		return d
	if v is Array:
		var a: Array = []
		for x: Variant in v:
			a.append(_dec(x))
		return a
	return v


## Numbers come back from JSON as floats; restore the int fields.
static func _fix_ints(q: Dictionary) -> Dictionary:
	for k: String in ["stage", "progress", "baseline", "deadline", "offered_day", "days"]:
		if q.has(k):
			q[k] = int(q[k])
	var r: Dictionary = q.get("reward", {})
	for k: String in ["gold", "opinion"]:
		if r.has(k):
			r[k] = int(r[k])
	var reps: Dictionary = r.get("rep", {})
	for f: Variant in reps:
		reps[f] = int(reps[f])
	for s: Dictionary in q.get("stages", []):
		for k: String in ["amount", "kills", "den_id"]:
			if s.has(k):
				s[k] = int(s[k])
	return q


func serialize() -> Dictionary:
	return {"offers": _enc(offers), "active": _enc(active), "completed": completed, "failed": failed,
		"tracked": tracked, "last_refill_day": last_refill_day}


func deserialize(d: Dictionary) -> void:
	offers.clear()
	active.clear()
	for q: Variant in _dec(d.get("offers", [])):
		offers.append(_fix_ints(q))
	for q: Variant in _dec(d.get("active", [])):
		active.append(_fix_ints(q))
	completed = int(d.get("completed", 0))
	failed = int(d.get("failed", 0))
	tracked = String(d.get("tracked", ""))
	last_refill_day = int(d.get("last_refill_day", -999))
