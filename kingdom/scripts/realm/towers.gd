extends "res://scripts/realm/realm_module.gd"
## Dungeon towers (docs/design/DUNGEON_TOWERS.md): who has cleared which floor, stairway/teleport-gate unlocks, first
## clears (once, ever), NPC adventurer parties racing the player up the tower, boss knowledge learned over attempts and
## scouting, relics from first clears, and the cost of dying inside.
##
## Pure data, deterministic (seed = hash([WorldSim.SEED, tag, day, id])), JSON-safe. Never touches the purse or the
## inventory itself: callers (tower_site.gd) apply gold/items from the dictionaries returned here.
## Cross-module (guarded): society.add_rumour / add_rep / learn / knows, followers (hire at camp).

const TowerData := preload("res://scripts/world/towers/tower_data.gd")

const PARTY_COUNT := 4
const PARTY_NAMES := ["Dawnbreakers", "The Ashen Vanguard", "Lantern Company", "Ironwake Raiders", "Kingsreach Wardens", "Free Blades"]
const MEMBER_FIRST := ["Alda", "Bertram", "Cael", "Dagna", "Eirik", "Fenna", "Garrick", "Hilde", "Ivor", "Jessa", "Korrin", "Lyra",
	"Merrin", "Nessa", "Orrin", "Pell"]
const MEMBER_LAST := ["Ashdown", "Brack", "Coldwater", "Dunmere", "Fell", "Greyle", "Hale", "Ironside", "Marsh", "Oakley", "Thorne"]
const MEMBER_JOBS := ["knight", "mercenary", "hunter", "healer", "scout", "smith"]
const ANNOUNCE_MAX := 30
## Fraction of this run's loot and of the purse lost on death.
const DEATH_LOOT_LOSS := 0.3
const DEATH_GOLD_LOSS := 0.1
const FAME_FIRST_CLEAR := 12
const PARTY_PROGRESS_RATE := 0.36        # floor progress per day at power == level

## tower -> [floors the player has beaten]
var cleared: Dictionary = {}
## tower -> highest floor whose boss anyone has killed (opens the stairs for everyone)
var world_cleared: Dictionary = {}
## tower -> {floor(str): {"by", "day", "player"}}
var first_clears: Dictionary = {}
## tower -> [floors whose gate the player activated]
var activated: Dictionary = {}
## tower -> {floor(str): n}  shared attempts on each boss (player + parties): every failure teaches everyone
var attempts: Dictionary = {}
## tower -> {floor(str): [pattern ids the player knows]}
var known: Dictionary = {}
var relics: Array = []
var parties: Array = []
var announcements: Array = []
var stats := {"deaths": 0, "clears": 0, "rematches": 0}
## Loot gathered since the player last left the tower by a safe route: what a death can take.
var run := {"tower": "", "items": {}, "gold": 0}
var _day := 0
var _built := false


# ------------------------------------------------------------------ helpers

func _rng(tag: String, day: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	var seed_base: int = WorldSim.SEED
	r.seed = hash([seed_base, tag, day, str(id)])
	return r


func _mod(n: String) -> RefCounted:
	return hub.mod(n) if hub != null else null


func _list(d: Dictionary, tid: String) -> Array:
	if not d.has(tid):
		d[tid] = []
	return d[tid]


func _sub(d: Dictionary, tid: String) -> Dictionary:
	if not d.has(tid):
		d[tid] = {}
	return d[tid]


func _nearest_sid(tid: String) -> int:
	var at := tower_pos(tid)
	if at == Vector2.INF:
		return 0
	var st: Dictionary = WorldGen.nearest_settlement(at)
	return int(st.get("id", 0)) if not st.is_empty() else 0


# ------------------------------------------------------------------ floors and gates

func tower_pos(tid: String) -> Vector2:
	for s: Dictionary in WorldGen.sites:
		if String(s.get("kind", "")) == "dungeon_tower" and String(s.get("tower", "")) == tid:
			return s["pos"]
	return Vector2.INF


func highest_cleared(tid: String) -> int:
	var best := 0
	for f in (cleared.get(tid, []) as Array):
		best = maxi(best, int(f))
	return best


func world_highest(tid: String) -> int:
	return int(world_cleared.get(tid, 0))


func player_cleared(tid: String, f: int) -> bool:
	return (cleared.get(tid, []) as Array).has(f)


func boss_dead(tid: String, f: int) -> bool:
	return f <= world_highest(tid) or player_cleared(tid, f)


## The floor's entrance stairs are open: floor 1 always, floor f once floor f-1's boss is dead (by anyone).
func is_floor_open(tid: String, f: int) -> bool:
	if f < 1 or f > TowerData.floor_count(tid):
		return false
	return f == 1 or boss_dead(tid, f - 1)


func gate_floors(tid: String) -> Array:
	var out: Array = (activated.get(tid, []) as Array).duplicate()
	out.sort()
	return out


func activate_gate(tid: String, f: int) -> bool:
	if not is_floor_open(tid, f):
		return false
	var a := _list(activated, tid)
	if a.has(f):
		return false
	a.append(f)
	return true


## Gate rule: only floors whose gate is activated (and still open) can be teleported to.
func can_teleport_to(tid: String, f: int) -> bool:
	return (activated.get(tid, []) as Array).has(f) and is_floor_open(tid, f)


## [{floor, name, theme, level, cleared, world_cleared}] for the teleport menu.
func teleport_menu(tid: String) -> Array:
	var out: Array = []
	for f in gate_floors(tid):
		var info := TowerData.floor_info(tid, int(f))
		out.append({"floor": int(f), "name": info["name"], "theme": info["theme"], "level": info["level"],
			"cleared": player_cleared(tid, int(f)), "boss_dead": boss_dead(tid, int(f))})
	return out


## Floor the stairs lead to from `f`, or 0 when the boss still lives.
func stairs_up_target(tid: String, f: int) -> int:
	return f + 1 if boss_dead(tid, f) and f < TowerData.floor_count(tid) else 0


# ------------------------------------------------------------------ boss knowledge

func attempts_on(tid: String, f: int) -> int:
	return int((attempts.get(tid, {}) as Dictionary).get(str(f), 0))


func known_patterns(tid: String, f: int) -> Array:
	return ((known.get(tid, {}) as Dictionary).get(str(f), []) as Array).duplicate()


func knows_pattern(tid: String, f: int, pat: String) -> bool:
	return (((known.get(tid, {}) as Dictionary).get(str(f), []) as Array)).has(pat)


func _learn_pattern(tid: String, f: int, pat: String) -> bool:
	var k := _sub(known, tid)
	if not k.has(str(f)):
		k[str(f)] = []
	if (k[str(f)] as Array).has(pat):
		return false
	(k[str(f)] as Array).append(pat)
	var soc := _mod("society")
	if soc != null:
		soc.learn("tower:%s:%d:%s" % [tid, f, pat], "%s: %s" % [TowerData.PATTERNS[pat]["name"], TowerData.PATTERNS[pat]["hint"]])
	return true


## Every attempt on a boss reveals its next unseen pattern (the fight itself teaches). Returns the pattern learned or "".
func record_attempt(tid: String, f: int, player_attempt := true) -> String:
	var a := _sub(attempts, tid)
	a[str(f)] = int(a.get(str(f), 0)) + 1
	if not player_attempt:
		return ""
	for pat: String in TowerData.floor_info(tid, f)["boss"]["patterns"]:
		if _learn_pattern(tid, f, pat):
			return pat
	return ""


func scout_cost(tid: String, f: int) -> int:
	return 30 + 20 * f


## A scout's report: all patterns, the boss's level and health. Returns {ok, text, learned}.
func scout_report(tid: String, f: int) -> Dictionary:
	if f < 1 or f > TowerData.floor_count(tid):
		return {"ok": false, "text": "", "learned": []}
	var info := TowerData.floor_info(tid, f)
	var learned: Array = []
	for pat: String in info["boss"]["patterns"]:
		if _learn_pattern(tid, f, pat):
			learned.append(pat)
	var soc := _mod("society")
	if soc != null:
		soc.learn("tower:%s:%d:boss" % [tid, f], "%s, level %d, about %d health." % [info["boss"]["name"], info["level"], info["boss"]["hp"]])
	var names: Array = []
	for pat: String in info["boss"]["patterns"]:
		names.append(String(TowerData.PATTERNS[pat]["name"]))
	return {"ok": true, "learned": learned,
		"text": "%s (%s), level %d, about %d health. Moves: %s." % [info["boss"]["name"], info["boss"]["title"], info["level"],
			info["boss"]["hp"], ", ".join(names)]}


func has_scouted(tid: String, f: int) -> bool:
	var soc := _mod("society")
	return soc != null and soc.knows("tower:%s:%d:boss" % [tid, f])


# ------------------------------------------------------------------ clears

func _announce(text: String) -> void:
	announcements.append({"day": _day, "text": text})
	if announcements.size() > ANNOUNCE_MAX:
		announcements.pop_front()


## A boss has died. `who` is "player" or a party name. Returns {first_clear, player_first, relic, fame, text, rumour}.
## The first kill of a floor is recorded once; only the player's own first clear yields its relic.
func boss_defeated(tid: String, f: int, who := "player", rematch := false) -> Dictionary:
	var info := TowerData.floor_info(tid, f)
	var fc := _sub(first_clears, tid)
	var first := not fc.has(str(f))
	var is_player := who == "player"
	var res := {"first_clear": first, "player_first": false, "relic": {}, "fame": 0, "text": "", "rumour": "", "floor": f,
		"boss": info["boss"]["name"]}
	if is_player and rematch:
		stats["rematches"] = int(stats["rematches"]) + 1
	if first:
		fc[str(f)] = {"by": who, "day": _day, "player": is_player}
		world_cleared[tid] = maxi(world_highest(tid), f)
		res["player_first"] = is_player
		var tname: String = TowerData.tower(tid).get("name", tid)
		var line := ""
		if is_player:
			line = "%s falls on floor %d of %s. The stairway to floor %d opens." % [info["boss"]["name"], f, tname, f + 1]
			res["fame"] = FAME_FIRST_CLEAR + f * 2
			var rel := TowerData.relic(tid, f)
			relics.append(rel)
			res["relic"] = rel
		else:
			line = "%s have felled %s on floor %d of %s. The stairway opens." % [who, info["boss"]["name"], f, tname]
		res["text"] = line
		_announce(line)
		res["rumour"] = _rumour(tid, f, who, info)
	if is_player:
		if not player_cleared(tid, f):
			_list(cleared, tid).append(f)
			stats["clears"] = int(stats["clears"]) + 1
		for pat: String in info["boss"]["patterns"]:
			_learn_pattern(tid, f, pat)
		# the far stairs wake: the next floor's gate may now be activated by walking in
	return res


func _rumour(tid: String, f: int, who: String, info: Dictionary) -> String:
	var soc := _mod("society")
	if soc == null:
		return ""
	var sid := _nearest_sid(tid)
	var mag := 2.0 + float(f) * 0.5
	var detail := "floor %d: %s" % [f, info["boss"]["name"]]
	var rid: String = soc.add_rumour("tower_clear", sid, mag, "player" if who == "player" else who, 1.0, detail)
	if who == "player":
		soc.add_rep("city:%d" % sid, 3.0 + 0.5 * f, "tower floor %d cleared" % f)
	return rid


## Reads better than society's generic rumour line (until society grows DEED_TEXT["tower_clear"]).
func rumour_line(tid: String, f: int, who: String) -> String:
	var info := TowerData.floor_info(tid, f)
	if who == "player":
		return "Someone has slain %s on floor %d of %s!" % [info["boss"]["name"], f, TowerData.tower(tid).get("name", tid)]
	return "%s cleared floor %d of %s." % [who, f, TowerData.tower(tid).get("name", tid)]


func relic_bonus() -> Dictionary:
	var out := {"max_health": 0.0, "damage": 0.0, "armour": 0.0, "stamina_regen": 0.0}
	for r: Dictionary in relics:
		out[String(r["stat"])] = float(out.get(String(r["stat"]), 0.0)) + float(r["value"])
	return out


# ------------------------------------------------------------------ death cost

func begin_run(tid: String) -> void:
	if String(run["tower"]) != tid:
		run = {"tower": tid, "items": {}, "gold": 0}


func add_run_loot(item: String, n := 1, gold := 0) -> void:
	if item != "":
		var it: Dictionary = run["items"]
		it[item] = int(it.get(item, 0)) + n
	run["gold"] = int(run["gold"]) + gold


## Leaving by stairs/gate/safe zone banks everything.
func bank_run() -> void:
	run = {"tower": "", "items": {}, "gold": 0}


## What a death takes: ~10% of the purse and ~30% of the loot gathered this run (rounded up per stack), plus a minor
## injury. Returns {gold, items:{id:n}, injury}. The run log is emptied. Deterministic per (day, deaths).
func death_losses(purse: int) -> Dictionary:
	var r := _rng("tower_death", _day, int(stats["deaths"]))
	stats["deaths"] = int(stats["deaths"]) + 1
	var lost_items := {}
	var keys: Array = (run["items"] as Dictionary).keys()
	keys.sort()
	for k: String in keys:
		var have := int(run["items"][k])
		var lose := int(floor(float(have) * DEATH_LOOT_LOSS))
		if float(have) * DEATH_LOOT_LOSS - float(lose) > 0.0 and r.randf() < (float(have) * DEATH_LOOT_LOSS - float(lose)):
			lose += 1
		if lose > 0:
			lost_items[k] = lose
	var gold := clampi(int(round(float(purse) * DEATH_GOLD_LOSS)), 0, purse)
	var inj: String = ["bruised_ribs", "deep_cut"][r.randi() % 2]
	bank_run()
	return {"gold": gold, "items": lost_items, "injury": inj}


# ------------------------------------------------------------------ NPC parties

func _ensure() -> void:
	if _built:
		return
	_built = true
	if not parties.is_empty():
		return
	var r := _rng("tower_parties", 0, 0)
	var names := PARTY_NAMES.duplicate()
	for i in PARTY_COUNT:
		var nm: String = names.pop_at(r.randi() % names.size())
		var size := 4 if i > 0 else 6
		var members: Array = []
		for j in size:
			members.append({"name": "%s %s" % [MEMBER_FIRST[r.randi() % MEMBER_FIRST.size()], MEMBER_LAST[r.randi() % MEMBER_LAST.size()]],
				"job": MEMBER_JOBS[r.randi() % MEMBER_JOBS.size()], "hurt_days": 0})
		parties.append({"id": "p%d" % i, "name": nm, "tower": TowerData.DEFAULT_TOWER, "raid": i == 0, "members": members,
			"power": snappedf(4.5 + r.randf() * 3.0 + (1.5 if i == 0 else 0.0), 0.01), "floor": 1, "progress": snappedf(r.randf() * 0.4, 0.01),
			"state": "climbing", "rest": 0, "casualties": 0, "clears": 0, "best": 0})


func party(pid: String) -> Dictionary:
	_ensure()
	for p: Dictionary in parties:
		if p["id"] == pid:
			return p
	return {}


## Parties resting in the base camp (recruitable there), as {party, name, job, party_name}.
func camp_adventurers(tid: String) -> Array:
	_ensure()
	var out: Array = []
	for p: Dictionary in parties:
		if String(p["tower"]) == tid and p["state"] == "camp":
			for m: Dictionary in p["members"]:
				out.append({"party": p["id"], "party_name": p["name"], "name": m["name"], "job": m["job"], "hurt": int(m["hurt_days"])})
	return out


func party_status(p: Dictionary) -> String:
	match String(p["state"]):
		"camp":
			return "%s rest at the base camp (best floor %d)." % [p["name"], int(p["best"])]
		_:
			return "%s are on floor %d." % [p["name"], int(p["floor"])]


func tick_day(day: int, _ctx: Dictionary) -> Array:
	_ensure()
	_day = day
	var out: Array = []
	for p: Dictionary in parties:
		out.append_array(_party_day(p, day))
	return out


func _party_day(p: Dictionary, day: int) -> Array:
	var out: Array = []
	var tid: String = p["tower"]
	var n_floors := TowerData.floor_count(tid)
	var r := _rng("tower_party_day", day, p["id"])
	p["power"] = snappedf(float(p["power"]) + 0.04, 0.01)             # they train
	for m: Dictionary in p["members"]:
		m["hurt_days"] = maxi(0, int(m["hurt_days"]) - 1)
	if p["state"] == "camp":
		p["rest"] = int(p["rest"]) - 1
		if int(p["rest"]) <= 0:
			p["state"] = "climbing"
			# the stairs may have been opened by someone else while they rested
			if int(p["floor"]) <= world_highest(tid) and int(p["floor"]) < n_floors:
				p["floor"] = int(p["floor"]) + 1
				p["progress"] = 0.0
		return out
	var f := int(p["floor"])
	if f > n_floors:
		return out
	var level := float(TowerData.floor_level(tid, f))
	var healthy := 0
	for m: Dictionary in p["members"]:
		if int(m["hurt_days"]) == 0:
			healthy += 1
	var strength := float(p["power"]) * (0.6 + 0.4 * float(healthy) / maxf(1.0, float(p["members"].size())))
	p["progress"] = snappedf(float(p["progress"]) + PARTY_PROGRESS_RATE * clampf(strength / level, 0.25, 2.0) * (0.7 + 0.6 * r.randf()), 0.001)
	if float(p["progress"]) < 1.0:
		return out
	# the boss room
	p["progress"] = 1.0
	if f <= world_highest(tid) and f < n_floors:
		# someone already felled it; the stairs are open, climb on
		p["floor"] = f + 1
		p["progress"] = 0.0
		return out
	var known_bonus := 0.06 * float(mini(attempts_on(tid, f), 6))
	var p_win := clampf(0.52 + 0.11 * (strength - level) + known_bonus, 0.04, 0.96)
	if r.randf() < p_win:
		if f > world_highest(tid):
			var res := boss_defeated(tid, f, String(p["name"]))
			out.append(String(res["text"]))
		p["clears"] = int(p["clears"]) + 1
		p["best"] = maxi(int(p["best"]), f)
		p["power"] = snappedf(float(p["power"]) + 0.9, 0.01)
		if f < n_floors:
			p["floor"] = f + 1
			p["progress"] = 0.0
		else:
			p["state"] = "camp"
			p["rest"] = 6
	else:
		record_attempt(tid, f, false)
		p["progress"] = 0.55                    # they retreat through the floor and try again
		p["state"] = "camp"
		p["rest"] = 2 + r.randi() % 3
		var margin := level - strength
		if margin > 0.0:
			for m: Dictionary in p["members"]:
				if r.randf() < clampf(0.25 + margin * 0.05, 0.0, 0.6):
					m["hurt_days"] = 2 + r.randi() % 4
		if margin > 4.0 and r.randf() < clampf((margin - 4.0) * 0.12, 0.0, 0.5):
			# a death: someone is replaced by a fresh recruit
			var idx := r.randi() % (p["members"] as Array).size()
			var gone: Dictionary = p["members"][idx]
			p["members"][idx] = {"name": "%s %s" % [MEMBER_FIRST[r.randi() % MEMBER_FIRST.size()], MEMBER_LAST[r.randi() % MEMBER_LAST.size()]],
				"job": gone["job"], "hurt_days": 0}
			p["casualties"] = int(p["casualties"]) + 1
			p["power"] = snappedf(maxf(3.0, float(p["power"]) - 0.4), 0.01)
			out.append("%s lost %s on floor %d of %s." % [p["name"], gone["name"], f, TowerData.tower(tid).get("name", tid)])
	return out


## Sleeping / travelling: resolve the party race statistically (capped so it stays cheap).
func catch_up(days: int, _ctx: Dictionary) -> Array:
	_ensure()
	var out: Array = []
	var d0 := _day
	for i in mini(days, 90):
		out.append_array(tick_day(d0 + i + 1, {}))
	_day = d0 + days
	return out


## Player-visible race summary: [{name, floor, best, state}] plus who leads.
func race() -> Array:
	_ensure()
	var out: Array = []
	for p: Dictionary in parties:
		out.append({"name": p["name"], "floor": int(p["floor"]), "best": int(p["best"]), "state": p["state"], "raid": bool(p["raid"])})
	return out


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	return {"cleared": cleared.duplicate(true), "world": world_cleared.duplicate(true), "first": first_clears.duplicate(true),
		"act": activated.duplicate(true), "att": attempts.duplicate(true), "known": known.duplicate(true), "relics": relics.duplicate(true),
		"parties": parties.duplicate(true), "ann": announcements.duplicate(true), "stats": stats.duplicate(), "run": run.duplicate(true),
		"day": _day}


func deserialize(d: Dictionary) -> void:
	cleared = _fix_int_lists(d.get("cleared", {}))
	world_cleared = {}
	for k: String in (d.get("world", {}) as Dictionary):
		world_cleared[k] = int(d["world"][k])
	first_clears = (d.get("first", {}) as Dictionary).duplicate(true)
	activated = _fix_int_lists(d.get("act", {}))
	attempts = (d.get("att", {}) as Dictionary).duplicate(true)
	known = (d.get("known", {}) as Dictionary).duplicate(true)
	relics = (d.get("relics", []) as Array).duplicate(true)
	parties = (d.get("parties", []) as Array).duplicate(true)
	announcements = (d.get("ann", []) as Array).duplicate(true)
	stats = {"deaths": 0, "clears": 0, "rematches": 0}
	for k: String in (d.get("stats", {}) as Dictionary):
		stats[k] = int(d["stats"][k])
	run = (d.get("run", {"tower": "", "items": {}, "gold": 0}) as Dictionary).duplicate(true)
	_day = int(d.get("day", 0))
	_built = not parties.is_empty()


## JSON turns ints into floats: floor lists must come back as ints.
func _fix_int_lists(src: Variant) -> Dictionary:
	var out := {}
	if src is Dictionary:
		for k: String in src:
			var a: Array = []
			for v: Variant in src[k]:
				a.append(int(v))
			out[k] = a
	return out
