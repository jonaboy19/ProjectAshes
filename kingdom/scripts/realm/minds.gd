extends "res://scripts/realm/realm_module.gd"
## Smart NPCs (LW-8, docs/design/LIVING_WORLD_SANDBOX.md section 11): the decision layers for the registry-upgraded Characters
## (registry.gd, at most CHAR_MAX = 1000 of them). The people who matter are real records; everyone else is a count per settlement
## (the AGGREGATE households: wealth and food per town, `agg_*`) that turns into a Character only when something references them
## (`ensure_row`, recruiting, marrying ...) and folds back into the count when idle for 30 days, far from the player and tied to nothing.
##
## FIVE LAYERS, in the order a character thinks:
##   1 needs            money (cash against the household's cost), work, belonging, safety (the town's danger and hunger)
##   2 responsibilities dependants, an employer, a seat in an organization, farms and businesses owned: they raise the cost of leaving
##   3 goals            a life arc by age (young: work, marry, move; settled: land, business, organization; established: lead, hand over;
##                      elder: retire) -- the goal is the highest-scoring action that is open to the character right now
##   4 relationships    kin, a spouse to be, the house's feuds (a feuding house is not married into), opinion from memory and rumour
##   5 known world      only what reached their town: news.gd items by road distance and delay, the town's own reputation, what is felt
##                      locally (famine, fever, tax). A boom three towns away is unknown until its news has arrived.
## The chosen action goes through the same module APIs the player uses: change job (businesses.hire, farming.hire_on, a new trade),
## rent or buy land (farming.take_tenancy / buy_direct), join or found an organization (organizations.apply / start_founding), open a
## business (businesses.npc_try_found), marry (homes.marry), move town (homes.relocate), take a farm contract (farming.accept_contract),
## petition (audiences.file), enlist (armies.enlist).
##
## TIERS (docs/design/LIVING_WORLD_SANDBOX.md Part E): the settlement the player is in is T-near (looked at every day, all five layers);
## every other upgraded character is T-mid/far (every third day, jittered by id, layers 1-3 and a light 5). Nothing is polled: each
## character has a due day in a bucket queue, and a change in its world (`poke`, `poke_town`) moves the day up. The day tick comes in
## chunks of CHUNK characters so no single pump job passes its budget.
##
## Life cycle lives here too: a yearly check on the birthday (death by an age table, raised by fever and famine), marriage, children (as rows
## in homes.gd until they come of age: `spawn_adult`), inheritance on death (dynasties.gd) and the memory of it (rumours.gd).
## Determinism: every roll is hash([WorldSim.SEED, tag, day, id]); no global RNG; no Vector2 in the saved state.

const PD := preload("res://scripts/realm/politics_data.gd")
const Events := preload("res://scripts/realm/events.gd")
const D := preload("res://scripts/realm/organizations_data.gd")
const BZ := preload("res://scripts/realm/businesses.gd")
const Registry := preload("res://scripts/realm/registry.gd")
const Persona := preload("res://scripts/realm/persona.gd")
const Core := preload("res://scripts/sim/utility_core.gd")

const YEAR := 360
const CHUNK := 5
const CHUNK_UNITS := 14              # work units a chunk may spend (a look 1, an attempt 2, a founding 6): deterministic, unlike a clock
const MIND_MAX := 960
const ADULT := 16
const CADENCE_NEAR := 1
const CADENCE_MID := 3
const IDLE_DAYS := 30
const REGION_RADIUS := 1400.0
const GOALS := ["idle", "work", "wed", "land", "business", "org_join", "org_found", "move", "contract", "petition", "enlist", "retire"]
const PROFS := ["farmer", "carpenter", "smith", "hunter", "mercenary", "laborer", "merchant", "scout"]
const JOB_PROF := ["farmer", "smith", "merchant", "mercenary", "laborer", "hunter"]   # WorldSim.JOBS order
const SEX := ["m", "f"]
const BOOM_KINDS := ["mine", "recognition"]
## Days before the same character tries the same kind of thing again: [after success, after failure], by goal index.
const GOAL_WAIT := [[0, 0], [0, 0], [0, 0], [0, 0], [120, 30], [20, 12], [240, 60], [180, 20], [14, 14], [60, 60], [90, 30], [0, 0]]
const GOALS_FILE := "res://data/npc/goals.json"
const TRACE_K := 3                   # decisions kept per near-tier character (NI-3 decision trace)
const BYTE := 1.0 / 255.0
## The input vector a goal's gates and terms read (data/npc/goals.json spells these lowercase). One flat PackedFloat32Array reused by
## every _choose: nothing is allocated per decision.
enum I { MONEY, WORK, WORK0, BELONG, TIED, AMB, AGE, AGE21, NOSPOUSE, FAILS, HAS_EMP, OWNS, SEATED, HOLDS_LAND, CASH, FARMER, AMB_FOUND, OPEN,
	WED_TIER, PUSH, PULL, MOVES_OK, MOVE_GATE, GRIEF, PETITION_SCOPE, ARMS, WORK_OR_POOR, FEAR, NOISE,
	BOLD, WARM, DISC, HON, LOY, PRI, STRESS_D, FEAR_D, ANGER_D, GRIEF_D, CONF_D, SCAR, COUNT }
const TOP_UP_PER_DAY := 6
const SEED_PER_DAY := 40             # a new world's first characters come in batches this big, one batch a day
const MOVES_PER_DAY := 2             # households that set out in one day, realm-wide (roads and the Rift do not empty a town in a night)

var auto_seed := true
var seed_target := 360
var aggregate_far := false
var focus_fixed := false
var _focus := -1
var _m: Dictionary = {}          # ch -> mind record
var _due: Dictionary = {}        # day -> [ch]
var _town: Dictionary = {}       # sid -> [ch] (derived)
var _kids: Dictionary = {}       # parent ch -> [ch] (derived)
var _agg: Dictionary = {}        # sid -> [wealth, food] (only towns that differ from the start)
var _dead := 0
var _day := 0
var _seeded := false
var _hire_idx: Dictionary = {}   # sid -> [bid]   (rebuilt once a day)
var _hire_day := -1
var _info: Dictionary = {}       # sid -> town facts (cached per day)
var _info_day := -1
var _carry: Array = []           # due characters not reached yesterday
var _tick_us := 0
var _tick_max := 0
var _focus_day := -1
var _focus_c := -1
var _land_day := -1
var _land_idx: Dictionary = {}
var _org_day := -1
var _org_idx: Dictionary = {}
var profile := false
var trace_on := true                 # decision traces for near-tier characters (off: nothing recorded)
var _in := PackedFloat32Array()      # the reused input vector (enum I)
var _trace: Dictionary = {}          # near-tier ch -> ring of [day, goal, PackedFloat32Array of (goal, score, top input) triples]
var _pe: Variant = null              # persona module (cached)
var _rm: Variant = null              # rumours module (cached)
var _ps: Variant = null              # psyche module (cached)
var _pl := ""                        # the player's character id
var _pl_day := -1
static var _gdef: Array = []         # compiled goals.json: [goal index, base, gates, terms] per goal, in evaluation order
static var _gthr := 0.22
static var _gfast: Object = null     # goals.json compiled by utility_core.compile (null: interpret with Core.evaluate)
static var _inp_names: PackedStringArray = PackedStringArray()
var _cost := 0
var _phase := 0                      # 1 seeding characters, 2 pairing them into households (not saved: a load resumes with the slow top-up)
var _couple_q: Array = []
var _seed_start := 0
var _moves_today := 0
var _moves_day := -1
var _prof: Dictionary = {}
var stats := {"decisions": 0, "idle": 0, "work": 0, "job_changed": 0, "wed": 0, "land": 0, "business": 0, "org_join": 0, "org_found": 0, "move": 0, "contract": 0,
	"petition": 0, "enlist": 0, "retire": 0, "failed": 0, "deaths": 0, "births_adults": 0, "demoted": 0, "promoted": 0, "pokes": 0}


func _now() -> int:
	return maxi(_day, PD.today())


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


func _om() -> Variant:
	return _mod("organizations")


func _ev(kind: String, sid: int, actors: Array, cause: String, outcome: String, w := 2) -> void:
	Events.log_to(hub, kind, "ss:%d" % sid if sid >= 0 else "", actors, cause, outcome, w)


func _h(tag: String, day: int, id: Variant) -> int:
	return absi(hash([WorldSim.SEED, tag, day, id]))


func _roll(tag: String, day: int, id: Variant) -> float:
	return float(_h(tag, day, id) % 100000) / 100000.0


# ------------------------------------------------------------------ queries

func is_mind(ch: String) -> bool:
	return _m.has(ch)


func is_alive(ch: String) -> bool:
	return _m.has(ch)


func count() -> int:
	return _m.size()


func ids() -> Array:
	var out: Array = _m.keys()
	out.sort()
	return out


func mind(ch: String) -> Dictionary:
	var r: Dictionary = _m.get(ch, {})
	if r.is_empty():
		return {}
	var out := r.duplicate()
	out["age"] = age_of(ch)
	out["goal"] = String(GOALS[int(r["g"])])
	out["sid"] = town_of(ch)
	return out


func age_of(ch: String) -> int:
	var r: Dictionary = _m.get(ch, {})
	return (_now() - int(r["b"])) / YEAR if not r.is_empty() else -1


func sex_of(ch: String) -> String:
	return String(SEX[int((_m.get(ch, {"x": 0}) as Dictionary)["x"])])


func town_of(ch: String) -> int:
	var om: Variant = _om()
	if om == null:
		return -1
	return int((om.char_rec(ch) as Dictionary).get("sid", -1))


func spouse_of(ch: String) -> String:
	return String((_m.get(ch, {}) as Dictionary).get("sp", ""))


func children_of(ch: String) -> Array:
	return (_kids.get(ch, []) as Array).duplicate()


func house_members(nm: String) -> Array:
	var dn: Variant = _mod("dynasties")
	return dn.members_of(nm) if dn != null else []


func in_town(sid: int) -> Array:
	return (_town.get(sid, []) as Array).duplicate()


func town_count(sid: int) -> int:
	return (_town.get(sid, []) as Array).size()


func goal_of(ch: String) -> String:
	return String(GOALS[int((_m.get(ch, {"g": 0}) as Dictionary)["g"])])


func focus_sid() -> int:
	if focus_fixed:
		return _focus
	if _focus_day == _now():
		return _focus_c
	var cl: Variant = _mod("city_life")
	_focus_c = int(cl.near_settlement()) if cl != null and cl.has_method("near_settlement") else -1
	_focus_day = _now()
	return _focus_c


func set_focus(sid: int) -> void:
	focus_fixed = true
	_focus = sid


func tier_of(ch: String) -> int:
	var f := focus_sid()
	return 1 if f >= 0 and town_of(ch) == f else 2


## Characters of a town chosen by a hash (for witnesses and believers of a story), never more than n.
func witnesses_at(sid: int, n: int, salt: Variant) -> Array:
	return _pick_town(sid, n, "wit", salt)


func believers_at(sid: int, n: int, salt: Variant) -> Array:
	return _pick_town(sid, n, "bel", salt)


func _pick_town(sid: int, n: int, tag: String, salt: Variant) -> Array:
	var out: Array = []
	var lst: Array = _town.get(sid, [])
	if lst.is_empty():
		return out
	var h0 := _h(tag, 0, salt)
	for i in mini(n, lst.size()):
		var ch: String = lst[(h0 + i) % lst.size()]
		if not out.has(ch):
			out.append(ch)
	return out


# ------------------------------------------------------------------ aggregate households

func _agg_row(sid: int) -> Array:
	var r: Array = _agg.get(sid, [])
	if r.is_empty():
		var pop := int(PD.settlement(sid).get("population", 200))
		r = [float(pop) * 14.0, float(pop) * 3.0]
		_agg[sid] = r
	return r


func agg_wealth(sid: int) -> int:
	return int(float(_agg_row(sid)[0]))


func agg_households(sid: int) -> int:
	return maxi(1, int(PD.settlement(sid).get("population", 200)) / 4) - town_count(sid) / 3


## Takes up to `amt` gold from a town's households (tithe, tax in kind). At most 3% of what they hold.
func agg_take(sid: int, amt: int) -> int:
	var r := _agg_row(sid)
	var got := mini(amt, int(float(r[0]) * 0.03))
	r[0] = float(r[0]) - float(got)
	return maxi(0, got)


func agg_add(sid: int, amt: int) -> void:
	var r := _agg_row(sid)
	r[0] = float(r[0]) + float(amt)


func _week_agg(week: int) -> void:
	var em: Variant = _mod("emergence")
	for s: Dictionary in WorldGen.settlements:
		var sid := int(s["id"])
		var pop := float(int(s.get("population", 200)))
		var r := _agg_row(sid)
		var target := pop * 14.0
		var growth := 0.02 * (target - float(r[0])) + pop * 0.15
		var food_m := 1.0
		if em != null:
			food_m = float(em.food_price_mult(sid))
			growth -= (food_m - 1.0) * pop * 0.5
		r[0] = maxf(pop, float(r[0]) + growth)
		r[1] = clampf(float(r[1]) + (pop * 3.0 - float(r[1])) * 0.05 - (food_m - 1.0) * pop * 0.2, 0.0, pop * 6.0)


# ------------------------------------------------------------------ making minds

func _prof_of_row(row: int) -> String:
	return String(JOB_PROF[int(WorldSim.job[row]) % JOB_PROF.size()])


## A WorldSim row becomes a mind (and a registry Character) if there is room. Returns the ch id or "".
func ensure_row(row: int) -> String:
	var reg: Variant = _mod("registry")
	var om: Variant = _om()
	if reg == null or om == null or _m.size() >= MIND_MAX or row < 0 or row >= WorldSim.health.size() or WorldSim.health[row] == 0:
		return ""
	var existing: String = reg.lookup(reg.key_ws(row))
	if existing != "" and _m.has(existing):
		return existing
	var ch: String = reg.upgrade_row(row, _now())
	if ch == "":
		return ""
	if _m.has(ch):
		return ch
	var sid := _sid_of_row(row)
	var h := _h("mind", 0, row)
	var age := 16 + (h % 47)
	if h % 7 == 0:
		age = 16 + (h / 7) % 14
	var amb_found := (h / 11) % 100 < 18
	var cash := int(WorldSim.money[row]) * 3 + 20 + (h / 13) % 90
	if amb_found:
		cash += 350 + (h / 17) % 800
	if om.has_char(ch):
		(om.char_rec(ch) as Dictionary)["sid"] = sid
	else:
		om.ensure_char(ch, {"prof": _prof_of_row(row), "cash": cash, "sid": sid, "npc": false, "amb": "found" if amb_found else "join", "rep": float((h / 19) % 20)})
	var rec := {"b": _now() - age * YEAR - (h / 23) % YEAR, "x": (h / 29) % 2, "g": 0, "n": _now() + 1 + (h % CADENCE_MID), "y": 0, "l": _now(), "f": 0, "r": row,
		"sp": "", "pa": "", "tp": "", "ed": 1 + (h / 31) % 2, "j": 0, "o": 0, "od": -99, "cd": 0, "fo": ""}
	rec["y"] = int(rec["b"]) + (age + 1) * YEAR
	_register(ch, rec, sid)
	var dn: Variant = _mod("dynasties")
	if dn != null:
		var nm := "%s@%d" % [dn.name_for(sid, (h / 37) % 5), sid]
		dn.set_house(ch, nm, sid)
	var fa: Variant = _mod("faith")
	if fa != null:
		fa.seed_belief(ch, sid, reg.traits_of(ch))
	stats["promoted"] = int(stats["promoted"]) + 1
	return ch


## Brings an existing character (a recruited follower, a founder, a test fixture) under the decision layers. The organizations record
## must exist (it holds the purse and the town). Returns false when there is no room.
func adopt(ch: String, age := 30, sex := "m", house := "", parent := "") -> bool:
	var om: Variant = _om()
	if _m.has(ch):
		return true
	if om == null or not om.has_char(ch) or _m.size() >= MIND_MAX:
		return false
	var sid := int((om.char_rec(ch) as Dictionary)["sid"])
	var rg: Variant = _mod("registry")
	if rg != null and Registry.is_pid(ch) and not rg.is_upgraded(ch) and not rg.upgrade(ch, _now()):
		return false                                         # the registry's 1,000 are all taken
	var h := _h("adopt", 0, ch)
	var rec := {"b": _now() - age * YEAR - h % YEAR, "x": 0 if sex == "m" else 1, "g": 0, "n": _now() + 1 + h % CADENCE_MID, "y": 0, "l": _now(), "f": 0, "r": -1, "sp": "",
		"pa": parent, "tp": "", "ed": 1, "j": 0, "o": 0, "od": -99, "cd": 0, "fo": ""}
	rec["y"] = int(rec["b"]) + (age + 1) * YEAR
	_register(ch, rec, sid)
	var dn: Variant = _mod("dynasties")
	if dn != null and house != "":
		dn.set_house(ch, house, sid)
	var fa: Variant = _mod("faith")
	var reg: Variant = _mod("registry")
	if fa != null and reg != null:
		fa.seed_belief(ch, sid, reg.traits_of(ch))
	return true


func _sid_of_row(row: int) -> int:
	for sid in WorldSim.ranges.size():
		var rg: Vector2i = WorldSim.ranges[sid]
		if row >= rg.x and row < rg.y:
			return sid
	return 0


func _register(ch: String, rec: Dictionary, sid: int) -> void:
	_m[ch] = rec
	var pe: Variant = _mod("persona")
	if pe != null:
		pe.ensure(ch, sid, int(rec["ed"]), String(rec["pa"]), int(rec["r"]))
	if not _town.has(sid):
		_town[sid] = []
	(_town[sid] as Array).append(ch)
	var pa := String(rec["pa"])
	if pa != "":
		if not _kids.has(pa):
			_kids[pa] = []
		(_kids[pa] as Array).append(ch)
	_schedule(ch, int(rec["n"]))


func _schedule(ch: String, day: int) -> void:
	if not _due.has(day):
		_due[day] = []
	(_due[day] as Array).append(ch)
	(_m[ch] as Dictionary)["n"] = day


## Seed `n` characters spread over the towns by population (deterministic).
func seed_minds(n: int) -> int:
	_seeded = true
	var total := 0
	for rg: Vector2i in WorldSim.ranges:
		total += rg.y - rg.x
	if total <= 0:
		return 0
	var made := 0
	for sid in WorldSim.ranges.size():
		var rg: Vector2i = WorldSim.ranges[sid]
		var cnt := rg.y - rg.x
		var want := maxi(1, n * cnt / total)
		var k := 0
		var tries := 0
		while k < want and tries < want * 4 and _m.size() < MIND_MAX and made < n:
			var row := rg.x + _h("seedrow", sid, tries) % maxi(1, cnt)
			tries += 1
			if ensure_row(row) != "":
				k += 1
				made += 1
	_seed_couples()
	return made


## A realistic start: about half of the grown people are already married, with children of every age (rows in homes.gd).
func _seed_couples(only: Array = []) -> void:
	var hm: Variant = _mod("homes")
	if hm == null:
		return
	var now := _now()
	for sid: Variant in (only if not only.is_empty() else _town.keys()):
		var men: Array = []
		var women: Array = []
		for ch: String in _town[sid]:
			var r: Dictionary = _m[ch]
			var age := (now - int(r["b"])) / YEAR
			if String(r["sp"]) != "" or age < 20 or age > 55:
				continue
			(men if int(r["x"]) == 0 else women).append(ch)
		for m: String in men:
			if _h("sc", 0, m) % 100 >= 58 or women.is_empty():
				continue
			var ma := (now - int((_m[m] as Dictionary)["b"])) / YEAR
			for i in women.size():
				var w: String = women[i]
				var wa := (now - int((_m[w] as Dictionary)["b"])) / YEAR
				if absi(wa - ma) <= 9:
					women.remove_at(i)
					var res: Dictionary = hm.marry(m, w, {"sid": int(sid)})
					if bool(res.get("ok", false)):
						var hid := String(res["hh"])
						var n := _h("kids", 0, m) % 4 if wa >= 24 else _h("kids", 0, m) % 2
						for k in n:
							var span := maxi(1, wa - 19)
							hm.add_child(hid, now - ((_h("kb", k, m) % span) * YEAR + _h("kb2", k, m) % YEAR))
					break


func spawn_adult(hid: String, kid: Array) -> String:
	var reg: Variant = _mod("registry")
	var om: Variant = _om()
	var hm: Variant = _mod("homes")
	if reg == null or om == null or hm == null or _m.size() >= MIND_MAX or reg.upgraded_count() >= reg.CHAR_MAX - 4:
		return ""
	var hh: Dictionary = hm.household(hid)
	if hh.is_empty():
		return ""
	var ch: String = reg.mint("ch")
	if ch == "" or not reg.upgrade(ch, _now()):
		return ""
	var sid := int(hh["sid"])
	var parent := String(hh["head"])
	var h := _h("adult", int(kid[0]), ch)
	var dn: Variant = _mod("dynasties")
	var house: String = dn.house_of(parent) if dn != null else ""
	var prof: String = PROFS[h % PROFS.size()]
	if dn != null and house != "":
		prof = dn.steer_trade(house, ch, prof)
	var ed := int(kid[2])
	om.ensure_char(ch, {"prof": prof, "cash": 30 + ed * 20, "sid": sid, "npc": false, "amb": "found" if (h / 3) % 100 < 14 + ed * 4 else "join"})
	var rec := {"b": int(kid[0]), "x": 0 if String(kid[1]) == "m" else 1, "g": 0, "n": _now() + 1, "y": 0, "l": _now(), "f": 0, "r": -1, "sp": "", "pa": parent, "tp": "", "ed": ed, "j": 1, "o": 0, "od": -99, "cd": 0, "fo": ""}
	rec["y"] = int(rec["b"]) + (age_from(int(kid[0])) + 1) * YEAR
	_register(ch, rec, sid)
	if dn != null and house != "":
		dn.set_house(ch, house, sid)
	var fa: Variant = _mod("faith")
	if fa != null:
		fa.seed_belief(ch, sid, [])
		if fa.belief_of(parent) > 0.0 and absi(hash([WorldSim.SEED, "inh", ch])) % 100 < 70:
			fa.set_belief(ch, fa.faith_of(parent), fa.belief_of(parent) * 0.8)
	stats["births_adults"] = int(stats["births_adults"]) + 1
	return ch


func age_from(born: int) -> int:
	return (_now() - born) / YEAR


func set_travelling(ch: String, tp: String) -> void:
	if _m.has(ch):
		(_m[ch] as Dictionary)["tp"] = tp


func set_town(ch: String, sid: int) -> void:
	var om: Variant = _om()
	if om == null or not _m.has(ch):
		return
	var old := town_of(ch)
	if old == sid:
		return
	if _town.has(old):
		(_town[old] as Array).erase(ch)
	(om.char_rec(ch) as Dictionary)["sid"] = sid
	if not _town.has(sid):
		_town[sid] = []
	(_town[sid] as Array).append(ch)
	om.ensure_char(ch, {"sid": sid})                      # (also tells organizations that the town index of its NPCs changed)


func on_married(a: String, b: String, _hid: String) -> void:
	for w: String in [a, b]:
		if _m.has(w):
			(_m[w] as Dictionary)["sp"] = b if w == a else a
			(_m[w] as Dictionary)["l"] = _now()
	var dn: Variant = _mod("dynasties")
	if dn != null:
		var ha: String = dn.house_of(a)
		var hb: String = dn.house_of(b)
		if ha != "" and hb != "" and ha != hb:
			dn.end_feud(ha, hb, "marriage") if dn.feud_heat(ha, hb) > 0.0 else null
			# The wife takes the husband's house.
			var wife := a if sex_of(a) == "f" else b
			var husband := b if wife == a else a
			if dn.house_of(husband) != "":
				dn.leave_house(wife)
				dn.set_house(wife, dn.house_of(husband))


func poke(ch: String) -> void:
	if not _m.has(ch):
		return
	var r: Dictionary = _m[ch]
	if int(r["n"]) > _now() + 1:
		_schedule(ch, _now() + 1)
		stats["pokes"] = int(stats["pokes"]) + 1


func poke_town(sid: int, n: int) -> int:
	var k := 0
	for ch: String in _town.get(sid, []):
		poke(ch)
		k += 1
		if k >= n:
			break
	return k


# ------------------------------------------------------------------ death

func die(ch: String, cause := "age") -> bool:
	if not _m.has(ch):
		return false
	var rec: Dictionary = _m[ch]
	var om: Variant = _om()
	var sid := town_of(ch)
	var nm_age := age_of(ch)
	stats["deaths"] = int(stats["deaths"]) + 1
	_dead += 1
	var dn: Variant = _mod("dynasties")
	if om != null:
		for oid: String in om.memberships(ch).duplicate():
			om.leave(oid, ch)
		var emp: Dictionary = om.employment(ch)
		if String(emp.get("by", "")).begins_with("bz:") and _mod("businesses") != null:
			_mod("businesses").fire(String(emp["by"]), ch)
		om.unemploy(ch)
	var est: Dictionary = dn.on_death(ch, cause) if dn != null else {}
	_ev("death", sid, [ch], cause, "A %d-year-old dies (%s)" % [nm_age, cause], 4 if not est.is_empty() and (not (est["businesses"] as Array).is_empty() or not (est["parcels"] as Array).is_empty()) else 2)
	var sp := String(rec["sp"])
	var hm: Variant = _mod("homes")
	if hm != null:
		hm.widow(ch)
	if sp != "" and _m.has(sp):
		(_m[sp] as Dictionary)["sp"] = ""
		poke(sp)
	var pa := String(rec["pa"])
	if pa != "" and _kids.has(pa):
		(_kids[pa] as Array).erase(ch)
	for k: Variant in _kids.get(ch, []):
		if _m.has(String(k)):
			(_m[String(k)] as Dictionary)["pa"] = ""
			poke(String(k))
	_kids.erase(ch)
	var rm: Variant = _mod("rumours")
	if rm != null:
		rm.drop_character(ch)
	var fa: Variant = _mod("faith")
	if fa != null:
		fa.drop_character(ch)
	if _town.has(sid):
		(_town[sid] as Array).erase(ch)
	_m.erase(ch)
	_trace.erase(ch)
	var pe: Variant = _mod("persona")
	if pe != null:
		pe.drop(ch)
	var reg: Variant = _mod("registry")
	if reg != null:
		reg.retire(ch, "d%d died aged %d (%s)" % [_now(), nm_age, cause])
	return true


static func annual_death_risk(age: int) -> float:
	if age < 16:
		return 0.01
	if age < 40:
		return 0.004
	if age < 55:
		return 0.012
	if age < 65:
		return 0.035
	if age < 75:
		return 0.08
	return 0.18


func _birthday(ch: String, rec: Dictionary, day: int) -> bool:
	rec["y"] = int(rec["y"]) + YEAR
	var age := (day - int(rec["b"])) / YEAR
	var sid := town_of(ch)
	var em: Variant = _mod("emergence")
	var p := annual_death_risk(age) * (float(em.mortality_mult(sid)) if em != null else 1.0)
	var fa: Variant = _mod("faith")
	if fa != null and fa.shelter_capacity(sid) > 0:
		p *= 0.95
	var hunger := clampf((float(em.food_price_mult(sid)) - 1.0) / 0.6, 0.0, 1.0) if em != null else 0.0
	if _roll("layoff", day, ch) < 0.05 + 0.25 * hunger:
		rec["j"] = int(rec["j"]) | 1
	if _roll("die", day, ch) < p:
		die(ch, "age" if age >= 60 else ("fever" if em != null and em.mortality_mult(sid) > 1.4 else "illness"))
		return true
	return false


# ------------------------------------------------------------------ the five layers

## Layer 5, local part: what the town feels today (cached once per day per town).
func _town_facts(sid: int, day: int) -> Dictionary:
	if _info_day != day:
		_info = {}
		_info_day = day
		var rg: Variant = _mod("registry")
		_pl = String(rg.lookup("pl:player")) if rg != null else ""
	var f: Dictionary = _info.get(sid, {})
	if not f.is_empty():
		return f
	var em: Variant = _mod("emergence")
	var nw: Variant = _mod("news")
	f = {"hunger": 0.0, "danger": 0.0, "unrest": 0.0, "fever": 0.0, "jobs": 0, "boom_sid": -1, "boom": 0.0, "arms": 0, "view": 0.0}
	var rmod: Variant = _mod("rumours")
	if rmod != null and _pl != "":
		f["view"] = float(rmod.town_view(sid, _pl))      # what the town says of the player (-100..100): the opinion layer of every decision here
	if em != null:
		f["hunger"] = clampf((float(em.food_price_mult(sid)) - 1.0) / 0.6, 0.0, 1.0)
		f["danger"] = clampf(float(em.danger_at(sid)), 0.0, 1.0)
		f["unrest"] = clampf(float(em.unrest_at(sid)) * 3.0, 0.0, 1.0)
		f["fever"] = clampf((float(em.mortality_mult(sid)) - 1.0) / 0.9, 0.0, 1.0)
	var ar: Variant = _mod("armies")
	if ar != null and float(ar.defence_rating(sid)) > 0.0:
		f["arms"] = 1
	f["jobs"] = (_hire_idx.get(sid, []) as Array).size()
	# What has reached this town about other towns: a boom is a place to go to, only if the news has arrived.
	if nw != null:
		var best := 0.0
		for it: Array in nw.heard_kinds(sid, BOOM_KINDS, day, 6):
			var o := int(it[0])
			if o == sid or o < 0 or int(it[2]) < 1 or int(it[3]) > 60:
				continue
			var v := float(it[1]) * (1.0 + 0.2 * float(it[2]))
			if v > best:
				best = v
				f["boom_sid"] = o
		f["boom"] = best
	_info[sid] = f
	return f


func _refresh_hiring(day: int) -> void:
	if _hire_day == day:
		return
	_hire_day = day
	_hire_idx = {}
	var bz: Variant = _mod("businesses")
	if bz == null:
		return
	for bid: String in bz.ids():
		var b: Dictionary = bz.biz(bid)
		if String(b["st"]) != "active":
			continue
		if (b["staff"] as Array).size() < int((BZ.KINDS[b["kind"]] as Dictionary)["max"]):
			var sid := int(b["sid"])
			if not _hire_idx.has(sid):
				_hire_idx[sid] = []
			(_hire_idx[sid] as Array).append(bid)


## Layers 1-3 in one pass: returns the index of the goal with the highest score (0 = nothing worth doing).
## Ties that make leaving costly, refreshed every ten days or when an action changes them: bit 1 a business, 2 land, 4 a seat in an organization.
func _ties(ch: String, rec: Dictionary, c: Dictionary, day: int) -> int:
	if day - int(rec["od"]) < 10:
		return int(rec["o"])
	var om: Variant = _om()
	var bz: Variant = _mod("businesses")
	var t := 0
	if not (c["own"] as Array).is_empty() or (bz != null and not bz.owned_by(ch).is_empty()):
		t |= 1
	if _holds_land(ch):
		t |= 2
	if not om.memberships(ch).is_empty():
		t |= 4
	rec["o"] = t
	rec["od"] = day
	return t


## Hub warm-up hook: reads and compiles the goal table behind the loading screen, not in the first pump job of the first day.
func _ensure() -> void:
	_load_goals()


## Compiles data/npc/goals.json once: gates and terms become flat float arrays over the input vector (enum I) for utility_core.
static func _load_goals() -> void:
	if not _gdef.is_empty():
		return
	_inp_names = PackedStringArray()
	for k: String in I.keys():
		_inp_names.append(k.to_lower())
	var f := FileAccess.open(GOALS_FILE, FileAccess.READ)
	var doc: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	if not (doc is Dictionary):
		push_error("minds: %s is missing or invalid" % GOALS_FILE)
		return
	_gthr = float((doc as Dictionary).get("threshold", 0.22))
	for g: Dictionary in (doc as Dictionary).get("goals", []):
		var gates: Array = []
		var terms: Array = []
		var ok := GOALS.has(String(g["id"]))
		for r: Array in g.get("gates", []):
			ok = ok and _inp_names.has(String(r[0]))
			gates.append([_inp_names.find(String(r[0])), int(Core.OPS.get(String(r[1]), 0)), float(r[2])])
		for r: Array in g.get("terms", []):
			ok = ok and _inp_names.has(String(r[0]))
			terms.append([_inp_names.find(String(r[0])), int(Core.RESP_NAMES.get(String(r[1]), Core.Resp.LINEAR)), float(r[2]), float(r[3]), float(r[4])])
		if not ok:
			push_error("minds: goal %s in %s names an unknown goal or input; skipped" % [str(g.get("id")), GOALS_FILE])
			continue
		_gdef.append([GOALS.find(String(g["id"])), float(g.get("base", 0.0)), Core.pack(gates), Core.pack(terms)])
	_gfast = Core.compile(_gdef, _gthr)


func _choose(ch: String, rec: Dictionary, c: Dictionary, age: int, day: int, tier: int, facts: Dictionary) -> int:
	_load_goals()
	if _in.size() != I.COUNT:
		_in.resize(I.COUNT)
	var hm: Variant = _mod("homes")
	var cash := int(c["cash"])
	var deps: int = hm.dependents(ch) if hm != null else 0
	var has_emp := not (c["emp"] as Dictionary).is_empty()
	var ties := _ties(ch, rec, c, day)
	var owns: bool = (ties & 1) != 0
	var seated: bool = (ties & 4) != 0
	var spouse := String(rec["sp"])
	var found: bool = String(c["amb"]) == "found"
	# the person: persona.gd is the one source of temperament and values (made on first use for characters from an old save)
	if _pe == null:
		_pe = _mod("persona")
	var pb: PackedByteArray = Persona.neutral()
	var po := 0
	if _pe != null:
		po = _pe.off(ch)
		if po < 0:
			po = _pe.ensure(ch, int(c["sid"]), int(rec["ed"]), String(rec["pa"]), int(rec["r"]))
		if po >= 0:
			pb = _pe.buf()
		else:
			po = 0
	var bold := float(pb[po + Persona.O_BOLD]) * BYTE
	var honest := float(pb[po + Persona.O_HON]) * BYTE
	# 1. needs
	var need_money := clampf(1.0 - float(cash) / float(50 + 30 * deps), 0.0, 1.0)
	# Most people have an ordinary job the simulation does not track; work is a need only after losing one (flag bit 0).
	var fl := int(rec["j"])
	if (fl & 2) != 0 and not has_emp and not owns:
		fl |= 1                                             # a post the character held explicitly is gone
	fl = (fl | 2) if has_emp else (fl & ~2)
	rec["j"] = fl
	var need_work := 1.0 if ((fl & 1) == 1 and not owns and not seated and not has_emp) else 0.0
	var need_belong := 0.0 if (seated or spouse != "") else 0.5
	# 4./5. what the character remembers and what the town says: the player's standing and bad news held in memory make it afraid
	var fear := 0.0
	if _rm == null:
		_rm = _mod("rumours")
	if _rm != null and _pl != "":
		var felt: Vector3 = _rm.felt(ch, _pl)
		var op: float = felt.x * 0.7 + float(facts["view"]) * 0.3 if felt.y > 0.0 else float(facts["view"]) * 0.5
		fear = minf(1.0, maxf(clampf(-op / 70.0, 0.0, 1.0), felt.z * 0.8) * (1.25 - 0.5 * bold))
	# 6. mood (NI-4): deviations from the person's own baseline, so someone with no history scores exactly as before; bounded additions
	if _ps == null:
		_ps = _mod("psyche")
	var mv := PackedFloat32Array()
	if _ps != null:
		mv = _ps.devs(ch, day)
		fear = minf(1.0, fear + 0.6 * maxf(mv[1], 0.0) + 0.3 * mv[5])
	var need_safe := maxf(maxf(float(facts["danger"]), float(facts["fever"])), fear * 0.8)
	# 2. responsibilities raise the price of leaving
	var tied := (0.15 if deps > 0 else 0.0) + (0.3 if owns else 0.0) + (0.1 if has_emp else 0.0) + (0.1 if seated else 0.0)
	var ambition := float(pb[po + Persona.O_AMB]) * BYTE * (1.3 if found else 0.7)
	var vol := float(pb[po + Persona.O_VOL]) * BYTE
	var noise := (_roll("gn", day, ch) - 0.5) * 0.2 * (0.6 + 0.8 * vol)
	var open: bool = day >= int(rec["cd"])                 # a recent attempt at something big (a move, a founding, a petition) is not repeated at once
	var hunger := float(facts["hunger"])
	var unrest := float(facts["unrest"])
	# 5. the known world decides about leaving: bad conditions at home against a boom whose news has arrived
	var push := maxf(maxf(hunger, need_safe), float(int(rec["f"])) / 4.0 if need_work > 0.0 else 0.0)
	var pull := clampf(float(facts["boom"]) / 3.0, 0.0, 1.0) if int(facts["boom_sid"]) >= 0 else 0.0
	# A far boom only tempts the unsettled: the jobless, the poor, the young and ambitious. Settled people leave only when pushed.
	var restless: bool = need_work > 0.0 or need_money > 0.5 or (ambition > 0.7 and age < 35)
	if not restless:
		pull *= 0.3
	var grief := maxf(maxf(hunger, unrest), fear * (0.5 + 0.5 * honest))
	if mv.size() == 6:
		grief = maxf(grief, 0.8 * maxf(mv[3], 0.0))
	_in[I.MONEY] = need_money
	_in[I.WORK] = need_work
	_in[I.WORK0] = 1.0 if need_work == 0.0 else 0.0
	_in[I.BELONG] = need_belong
	_in[I.TIED] = tied
	_in[I.AMB] = ambition
	_in[I.AGE] = float(age)
	_in[I.AGE21] = 1.0 if age >= 21 else 0.0
	_in[I.NOSPOUSE] = 1.0 if spouse == "" else 0.0
	_in[I.FAILS] = float(int(rec["f"]))
	_in[I.HAS_EMP] = 1.0 if has_emp else 0.0
	_in[I.OWNS] = 1.0 if owns else 0.0
	_in[I.SEATED] = 1.0 if seated else 0.0
	_in[I.HOLDS_LAND] = 1.0 if (ties & 2) != 0 else 0.0
	_in[I.CASH] = float(cash)
	_in[I.FARMER] = 1.0 if String(c["prof"]) == "farmer" else 0.0
	_in[I.AMB_FOUND] = 1.0 if found else 0.0
	_in[I.OPEN] = 1.0 if open else 0.0
	_in[I.WED_TIER] = 1.0 if (tier == 1 or age >= 20) else 0.0
	_in[I.PUSH] = push
	_in[I.PULL] = pull
	_in[I.MOVES_OK] = 1.0 if _moves_today < MOVES_PER_DAY else 0.0
	_in[I.MOVE_GATE] = 1.0 if (push > 0.35 or pull > 0.4) else 0.0
	_in[I.GRIEF] = grief
	_in[I.PETITION_SCOPE] = 1.0 if (tier == 1 or grief > 0.55) else 0.0
	_in[I.ARMS] = float(int(facts["arms"]))
	_in[I.WORK_OR_POOR] = 1.0 if (need_work > 0.0 or need_money > 0.7) else 0.0
	_in[I.FEAR] = fear
	_in[I.NOISE] = noise
	_in[I.BOLD] = bold
	_in[I.WARM] = float(pb[po + Persona.O_WARM]) * BYTE
	_in[I.DISC] = float(pb[po + Persona.O_DISC]) * BYTE
	_in[I.HON] = honest
	_in[I.LOY] = float(pb[po + Persona.O_LOY]) * BYTE
	_in[I.PRI] = float(pb[po + Persona.O_PRI]) * BYTE
	for k in 6:
		_in[I.STRESS_D + k] = mv[k] if mv.size() == 6 else 0.0
	# 3. goals by age and need: the highest score above the threshold, file order breaking ties
	var best := 0
	if _gfast != null:
		best = _gfast.pick(_in)
	else:
		best = _pick_slow(_in)
	if tier == 1 and trace_on:
		# The decision trace keeps the input vector (one small array) and explains it on demand in trace(): nothing is scored twice here.
		var ring: Array = _trace.get(ch, [])
		if ring.is_empty():
			_trace[ch] = ring
		ring.append([day, best, _in.duplicate()])
		if ring.size() > TRACE_K:
			ring.pop_front()
	return best


## The interpreted goal choice (utility_core.evaluate over the tables): the fallback when the compiled one is unavailable, and what
## trace() uses to show every candidate. Highest score above the threshold, file order breaking ties.
func _pick_slow(inp: PackedFloat32Array) -> int:
	var best := 0
	var bs := _gthr
	for gd: Array in _gdef:
		var u: float = Core.evaluate(gd[1], gd[2], gd[3], inp)
		if u > bs and u > Core.GATE_FAIL:
			bs = u
			best = gd[0]
	return best


## The last decisions of a near-tier character, newest first: [{day, goal, scores: [{goal, score, why}]}], best candidate first. `scores`
## lists every goal whose gates held; `why` is the input that moved that score most (a need, a persona term or fear). Far characters keep
## no trace (goal_of gives their last choice).
func trace(ch: String) -> Array:
	_load_goals()
	var out: Array = []
	var ring: Array = _trace.get(ch, [])
	for i in range(ring.size() - 1, -1, -1):
		var e: Array = ring[i]
		var inp: PackedFloat32Array = e[2]
		var rows: Array = []
		for gd: Array in _gdef:
			var u: float = Core.evaluate(gd[1], gd[2], gd[3], inp)
			if u <= Core.GATE_FAIL:
				continue
			var tt: int = Core.top_term(gd[3], inp)
			rows.append({"goal": GOALS[int(gd[0])], "score": snappedf(u, 0.001), "why": _inp_names[int((gd[3] as PackedFloat32Array)[tt])] if tt >= 0 else "base"})
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
		out.append({"day": int(e[0]), "goal": GOALS[int(e[1])], "scores": rows, "threshold": _gthr})
	return out


func _holds_land(ch: String) -> bool:
	var fm: Variant = _mod("farming")
	if fm == null:
		return false
	return not (fm.parcels_of(ch) as Array).is_empty() or not (fm.rented_by(ch) as Array).is_empty()


# ------------------------------------------------------------------ actions

func _act(ch: String, rec: Dictionary, c: Dictionary, goal: int, age: int, day: int, facts: Dictionary) -> bool:
	match goal:
		1: return _a_work(ch, c, day)
		2: return _a_wed(ch, rec, c, age, day)
		3: return _a_land(ch, c, day)
		4: return _a_business(ch, c, day)
		5: return _a_join(ch, c, day)
		6: return _a_found(ch, c, day)
		7: return _a_move(ch, rec, c, day, facts)
		8: return _a_contract(ch, day)
		9: return _a_petition(ch, c, day, facts)
		10: return _a_enlist(ch, rec, c, day)
		11: return _a_retire(ch, c)
	return false


func _a_work(ch: String, c: Dictionary, day: int) -> bool:
	var rec: Dictionary = _m[ch]
	var sid := int(c["sid"])
	var bz: Variant = _mod("businesses")
	_refresh_hiring(day)
	var lst: Array = _hire_idx.get(sid, [])
	if bz != null and not lst.is_empty():
		var bid: String = lst[_h("hire", day, ch) % lst.size()]
		if bool(bz.hire(bid, ch).get("ok", false)):
			rec["j"] = (int(rec["j"]) & ~1) | 2
			stats["work"] = int(stats["work"]) + 1
			return true
	var fm: Variant = _mod("farming")
	if fm != null and String(c["prof"]) in ["farmer", "laborer"]:
		var jobs: Array = fm.jobs(sid)
		if not jobs.is_empty():
			var pid: String = jobs[_h("fjob", day, ch) % jobs.size()]
			if fm.hire_on(pid, ch) == "":
				_om().employ(ch, pid, 6)
				rec["j"] = (int(rec["j"]) & ~1) | 2
				stats["work"] = int(stats["work"]) + 1
				return true
	# Casual work, where the town has any (the rest of the economy is not tracked per person).
	if _roll("casual", day, ch) < 0.5 + 0.1 * float(mini(3, (_hire_idx.get(sid, []) as Array).size())) - 0.4 * float(_town_facts(sid, day)["hunger"]):
		rec["j"] = int(rec["j"]) & ~1
		stats["work"] = int(stats["work"]) + 1
		return true
	if int(rec["f"]) < 2:
		return false
	# No post to be had: learn another trade (steered by the house's specialty, else by what the town lacks).
	var dn: Variant = _mod("dynasties")
	var pick: String = PROFS[_h("trade", day, ch) % PROFS.size()]
	if dn != null:
		pick = dn.steer_trade(dn.house_of(ch), ch, pick)
	if pick != String(c["prof"]):
		_om().set_profession(ch, pick)
		rec["j"] = int(rec["j"]) & ~1
		stats["job_changed"] = int(stats["job_changed"]) + 1
		return true
	return false


func _a_wed(ch: String, rec: Dictionary, c: Dictionary, age: int, day: int) -> bool:
	var hm: Variant = _mod("homes")
	var dn: Variant = _mod("dynasties")
	var rm: Variant = _mod("rumours")
	if hm == null:
		return false
	var sid := int(c["sid"])
	var lst: Array = _town.get(sid, [])
	if lst.size() < 2:
		return false
	var best := ""
	var bscore := -1.0e9
	var my_house: String = dn.house_of(ch) if dn != null else ""
	var start := _h("wed", day, ch)
	for i in mini(8, lst.size()):
		var o: String = lst[(start + i) % lst.size()]
		if o == ch or not _m.has(o):
			continue
		var orec: Dictionary = _m[o]
		var oage := (day - int(orec["b"])) / YEAR
		if String(orec["sp"]) != "" or oage < 18 or oage > 45 or int(orec["x"]) == int(rec["x"]) or absi(oage - age) > 9 or String(orec["tp"]) != "":
			continue
		var oh: String = dn.house_of(o) if dn != null else ""
		if my_house != "" and my_house == oh:
			continue                                           # no marrying into one's own house
		var heat: float = dn.feud_heat(my_house, oh) if dn != null and my_house != "" and oh != "" else 0.0
		if heat >= 45.0:
			continue                                           # feuding houses do not make matches
		var op: float = rm.opinion(o, ch, sid) if rm != null else 0.0
		var oc: Dictionary = _om().char_rec(o)
		var sc := -absf(float(oage - age)) * 0.4 + op * 0.05 + float(mini(int(oc["cash"]), 400)) / 200.0 + _roll("wedc", day, o) * 2.0
		if sc > bscore:
			bscore = sc
			best = o
	if best == "":
		return false
	if _roll("wedp", day, ch) > 0.55:
		return false
	var husband := ch if int(rec["x"]) == 0 else best
	var res: Dictionary = hm.marry(husband, ch if husband == best else best, {"sid": sid, "well": false})
	if not bool(res.get("ok", false)):
		return false
	stats["wed"] = int(stats["wed"]) + 1
	if rm != null:
		rm.witness(ch, "marriage", ch, 25.0, sid, {"ev": 0})
	return true


func _a_land(ch: String, c: Dictionary, day: int) -> bool:
	var fm: Variant = _mod("farming")
	if fm == null:
		return false
	var sid := int(c["sid"])
	if _land_day != day:
		_land_day = day
		_land_idx = {}
		for pid0: String in fm.for_rent():
			var ps := int(fm.parcel(pid0)["sid"])
			if not _land_idx.has(ps):
				_land_idx[ps] = []
			(_land_idx[ps] as Array).append(pid0)
	var cands: Array = _land_idx.get(sid, [])
	if cands.is_empty():
		return false
	var pid2: String = cands[_h("land", day, ch) % cands.size()]
	if not fm.farmers().has(ch):
		var put := int(float(c["cash"]) * 0.6)
		if put < 60 or not _om().pay(ch, put):
			return false
		fm.add_farmer(ch, sid, put, 0.6, int((_m[ch] as Dictionary).get("r", -1)), "Farmer %s" % ch)
	var f: Dictionary = fm.farmer(ch)
	# Buy the Crown's vacant land outright if the purse allows, else rent it.
	if fm.is_vacant(pid2) and int(f["cash"]) >= fm.value(pid2):
		if fm.buy_direct(pid2, ch) == "":
			stats["land"] = int(stats["land"]) + 1
			(_m[ch] as Dictionary)["od"] = -99
			return true
	if fm.take_tenancy(pid2, "rent", ch) == "":
		stats["land"] = int(stats["land"]) + 1
		(_m[ch] as Dictionary)["od"] = -99
		return true
	return false


func _a_business(ch: String, c: Dictionary, day: int) -> bool:
	var bz: Variant = _mod("businesses")
	if bz == null:
		return false
	if bz.npc_try_found(ch, day):
		stats["business"] = int(stats["business"]) + 1
		(_m[ch] as Dictionary)["od"] = -99
		return true
	return false


func _a_join(ch: String, c: Dictionary, _day2: int) -> bool:
	var om: Variant = _om()
	var sid := int(c["sid"])
	var best := ""
	var bs := -1.0e9
	var prof := String(c["prof"])
	if _org_day != _now():
		_org_day = _now()
		_org_idx = {}
	if not _org_idx.has(sid):
		_org_idx[sid] = om.orgs_in(sid, "")
	for oid: String in _org_idx[sid]:
		if not (prof in (D.TYPES[String(om.org(oid)["type"])]["prof"] as Array)):
			continue
		var sc := float(om.offer_score(oid, ch))
		if sc > bs and om.join_conflict(oid, ch) == "":
			bs = sc
			best = oid
	if best == "":
		return false
	if bool(om.apply(best, ch, "").get("ok", false)):
		stats["org_join"] = int(stats["org_join"]) + 1
		(_m[ch] as Dictionary)["od"] = -99
		return true
	return false


func _a_found(ch: String, c: Dictionary, day: int) -> bool:
	var om: Variant = _om()
	var sid := int(c["sid"])
	var types: Array = []
	for t: String in D.TYPE_IDS:
		if String(c["prof"]) in (D.TYPES[t]["prof"] as Array):
			types.append(t)
	if types.is_empty():
		return false
	var t2: String = types[_h("ftype", day, ch) % types.size()]
	var td: Dictionary = D.type_def(t2)
	if int(c["cash"]) < int(td.get("found", 0)) + 30 or om.orgs_in(sid, t2).size() >= 2:
		return false
	var nm := "%s of %s (%s)" % [String(D.TYPES[t2]["label"]), PD.sname(sid), ch]
	var res: Dictionary = om.start_founding(ch, t2, nm, sid, "autonomous")
	if bool(res.get("ok", false)):
		(_m[ch] as Dictionary)["fo"] = String(res["org"])
		stats["org_found"] = int(stats["org_found"]) + 1
		(_m[ch] as Dictionary)["od"] = -99
		return true
	return false


## The next step of a founding that characters lead, using the player's own calls (organizations.gd runs the same steps for the NPC actors it seeds
## itself; characters of this module are not in its NPC list, so their founders are walked through here). `deputy_ok` lets a church find a second
## founder when nobody fitting is free. Returns the step taken ("" when nothing was due).
func advance_founding(oid: String, day: int, deputy_ok := false) -> String:
	var om: Variant = _om()
	if om == null or not om.exists(oid):
		return ""
	var o: Dictionary = om.org(oid)
	var lead := String(o["leader"])
	if String(o["st"]) != "active" or lead == "" or int(o["stage"]) >= 3 or lead == String(_mod("registry").lookup("pl:player")):
		return ""
	var td: Dictionary = om.type_of(oid)
	var sid := int(o["sid"])
	if om.member_count(oid) < int(td.get("min_founders", 2)):
		var lst: Array = _town.get(sid, [])
		for k in mini(8, lst.size()):
			var ch2: String = lst[(_h("ffr", day, oid) + k) % lst.size()]
			if ch2 == lead or not om.memberships(ch2).is_empty():
				continue
			var c2: Dictionary = om.char_rec(ch2)
			if not (String(c2["prof"]) in (td.get("prof", []) as Array)) or _roll("ffa", day, ch2) > 0.5:
				continue
			if bool(om.add_founder(oid, lead, ch2).get("ok", false)):
				return "founder"
		if deputy_ok:
			var reg: Variant = _mod("registry")
			var dep: String = reg.mint("ch") if reg != null else ""
			if dep != "":
				om.ensure_char(dep, {"prof": String((td.get("prof", ["priest"]) as Array)[0]), "cash": 60, "sid": sid, "amb": "join"})
				if bool(om.add_founder(oid, lead, dep).get("ok", false)):
					return "founder"
		return ""
	if (o["charter"] as Dictionary).is_empty():
		om.draft_charter(oid, lead, "We, the founders of %s, bind ourselves." % o["name"])
		return "charter"
	if String(o["legal"]) == "none":
		om.petition_recognition(oid, lead)
		return "petition"
	if (o["hq"] as Dictionary).is_empty() and String(o["legal"]) in ["recognised", "outlaw"]:
		om.rent_hq(oid, lead, sid)
		return "hq"
	return ""


func _a_move(ch: String, rec: Dictionary, c: Dictionary, day: int, facts: Dictionary) -> bool:
	var hm: Variant = _mod("homes")
	if hm == null:
		return false
	var from := int(c["sid"])
	var to := int(facts["boom_sid"])
	if to < 0 or to == from:
		# No news of anywhere better: the nearest town the family has heard of by trade (its neighbours).
		var nw: Variant = _mod("news")
		var bd := 1.0e9
		for s: Dictionary in WorldGen.settlements:
			var t := int(s["id"])
			if t == from:
				continue
			var d := float(nw.road_distance(from, t)) if nw != null else 500.0
			if d < bd and d < 900.0 and _town_facts(t, day)["hunger"] < 0.3:
				bd = d
				to = t
	if to < 0 or to == from:
		return false
	if (_mod("businesses") != null and not _mod("businesses").owned_by(ch).is_empty()) or _holds_land(ch):
		return false
	var people: int = 1 + hm.dependents(ch)
	var need: int = hm.provisions_needed(from, to, people, true) + people
	var travel: bool = hm.active_parties().size() < 30 and _om().purse(ch) >= need * 2 + 10
	var res: Dictionary = hm.relocate(ch, to, {"travel": travel, "buy_provisions": need})
	if bool(res.get("ok", false)):
		_moves_today += 1
		rec["f"] = 0
		rec["j"] = 0                                       # a new town, a fresh start: casual work is found on arrival
		stats["move"] = int(stats["move"]) + 1
		return true
	return false


func _a_contract(ch: String, day: int) -> bool:
	var fm: Variant = _mod("farming")
	if fm == null:
		return false
	var mine: Array = fm.parcels_of(ch)
	if mine.is_empty():
		mine = fm.rented_by(ch)
	if mine.is_empty():
		return false
	for ct: Dictionary in fm.contracts():
		if String(ct["taker"]) == "" and not bool(ct.get("done", false)) and int(ct["due"]) > day:
			if fm.accept_contract(int(ct["id"]), String(mine[0]), ch) == "":
				stats["contract"] = int(stats["contract"]) + 1
				return true
	return false


func _a_petition(ch: String, c: Dictionary, day: int, facts: Dictionary) -> bool:
	var au: Variant = _mod("audiences")
	if au == null:
		return false
	var sid := int(c["sid"])
	var rm: Variant = _mod("rumours")
	var by := {"id": ch, "name": ch, "kind": "npc", "fame": float(c["rep"]) / 5.0, "rank": 1 if float(c["rep"]) > 15.0 else 0, "sponsors": []}
	var ptype := "tax_relief" if float(facts["hunger"]) > 0.3 or float(facts["unrest"]) > 0.3 else "trade_rights"
	var res: Dictionary = au.file(ptype, sid, by, {}, {"npc": true, "proxy": true})
	if bool(res.get("ok", false)):
		au.add_evidence(String(res["pid"]), "witness", 0.7, ch)
		stats["petition"] = int(stats["petition"]) + 1
		if rm != null:
			rm.witness(ch, "trade", ch, 5.0, sid, {"quiet": true})
		return true
	return false


func _a_enlist(ch: String, rec: Dictionary, c: Dictionary, day: int) -> bool:
	var ar: Variant = _mod("armies")
	var row := int(rec["r"])
	if ar == null or row < 0 or row >= WorldSim.health.size() or WorldSim.health[row] == 0:
		return false
	var sid := int(c["sid"])
	for aid: Variant in ar.ids():
		var a: Dictionary = ar.army(String(aid))
		if int(a.get("sid", -1)) != sid or not bool(a.get("npc", false)):
			continue
		var r: Dictionary = ar.enlist(String(aid), "spear", row, {"w": 4})
		if bool(r.get("ok", false)):
			stats["enlist"] = int(stats["enlist"]) + 1
			return true
		return false
	return false


func _a_retire(ch: String, c: Dictionary) -> bool:
	var om: Variant = _om()
	var emp: Dictionary = c["emp"]
	if emp.is_empty():
		return false
	if String(emp.get("by", "")).begins_with("bz:") and _mod("businesses") != null:
		_mod("businesses").fire(String(emp["by"]), ch)
	om.unemploy(ch)
	stats["retire"] = int(stats["retire"]) + 1
	return true


# ------------------------------------------------------------------ the decision

## The goal `ch` would choose now, without acting (for the UI's "what is on their mind" and for tests).
func intent(ch: String, day := -1) -> String:
	var rec: Dictionary = _m.get(ch, {})
	var om: Variant = _om()
	if rec.is_empty() or om == null or not om.has_char(ch):
		return ""
	var d := _now() if day < 0 else day
	var c: Dictionary = om.char_rec(ch)
	var age := (d - int(rec["b"])) / YEAR
	return String(GOALS[_choose(ch, rec, c, age, d, tier_of(ch), _town_facts(int(c["sid"]), d))])


## Runs one named goal now through the module APIs (what a decision does once it has chosen). True when it worked.
func perform(ch: String, goal: String, day := -1) -> bool:
	var rec: Dictionary = _m.get(ch, {})
	var om: Variant = _om()
	var gi := GOALS.find(goal)
	if rec.is_empty() or om == null or gi <= 0:
		return false
	var d := _now() if day < 0 else day
	var c: Dictionary = om.char_rec(ch)
	var age := (d - int(rec["b"])) / YEAR
	_refresh_hiring(d)
	var ok := _act(ch, rec, c, gi, age, d, _town_facts(int(c["sid"]), d))
	if ok:
		rec["l"] = d
		rec["od"] = -99
	return ok


func town_facts(sid: int, day := -1) -> Dictionary:
	return _town_facts(sid, _now() if day < 0 else day).duplicate()


func decide(ch: String, day: int) -> bool:
	if profile:
		var t0 := Time.get_ticks_usec()
		var r := _decide(ch, day)
		_prof["decide"] = int(_prof.get("decide", 0)) + Time.get_ticks_usec() - t0
		_prof["decide_n"] = int(_prof.get("decide_n", 0)) + 1
		return r
	return _decide(ch, day)


func _decide(ch: String, day: int) -> bool:
	var rec: Dictionary = _m.get(ch, {})
	if rec.is_empty():
		return false
	var om: Variant = _om()
	var c: Dictionary = om.char_rec(ch) if om != null else {}
	if c.is_empty():
		_schedule(ch, day + CADENCE_MID)
		return false
	stats["decisions"] = int(stats["decisions"]) + 1
	_cost += 1
	if day >= int(rec["y"]) and _birthday(ch, rec, day):
		return true
	var age := (day - int(rec["b"])) / YEAR
	var tier := tier_of(ch)
	if String(rec["tp"]) != "":
		_schedule(ch, day + 2)
		return false
	var sid := int(c["sid"])
	if String(rec["fo"]) != "":
		var fo := String(rec["fo"])
		if advance_founding(fo, day) == "" and (not om.exists(fo) or int(om.org(fo)["stage"]) >= 3 or String(om.org(fo)["leader"]) != ch):
			rec["fo"] = ""
	var facts := _town_facts(sid, day)
	var tp0 := Time.get_ticks_usec()
	var goal := _choose(ch, rec, c, age, day, tier, facts)
	if profile:
		_prof["choose_max"] = maxi(int(_prof.get("choose_max", 0)), Time.get_ticks_usec() - tp0)
		_prof["choose"] = int(_prof.get("choose", 0)) + Time.get_ticks_usec() - tp0
		_prof["n"] = int(_prof.get("n", 0)) + 1
	var done := false
	if goal == 0:
		stats["idle"] = int(stats["idle"]) + 1
	else:
		var ta0 := Time.get_ticks_usec()
		_cost += 6 if goal in [4, 5, 6, 7] else 2
		done = _act(ch, rec, c, goal, age, day, facts)
		if profile:
			var gk := "act_%s" % GOALS[goal]
			_prof[gk] = int(_prof.get(gk, 0)) + Time.get_ticks_usec() - ta0
			_prof[gk + "_n"] = int(_prof.get(gk + "_n", 0)) + 1
			_prof[gk + "_ok"] = int(_prof.get(gk + "_ok", 0)) + (1 if done else 0)
			_prof[gk + "_max"] = maxi(int(_prof.get(gk + "_max", 0)), Time.get_ticks_usec() - ta0)

		if _pe != null:
			_pe.experience(ch, GOALS[goal], done, day)         # what trying (and failing) teaches drifts the person, within a yearly cap
		var wait: int = int(GOAL_WAIT[goal][0 if done else 1])
		if wait > 0:
			rec["cd"] = day + wait
		if done:
			rec["l"] = day
			rec["f"] = 0
		else:
			rec["f"] = mini(8, int(rec["f"]) + 1)
			stats["failed"] = int(stats["failed"]) + 1
	rec["g"] = goal
	# Far from the player, tied to nothing, idle for a month: fold back into the aggregate households.
	if aggregate_far and not done and day - int(rec["l"]) >= IDLE_DAYS and _is_far(sid) and _untied(ch, rec, c):
		if _demote(ch, rec, c):
			return true
	var cad := CADENCE_NEAR if tier == 1 else CADENCE_MID
	_schedule(ch, day + cad * (1 + (mini(5, int(rec["f"])) if goal != 0 and not done else 0)) + (_h("jit", day, ch) % 2 if tier == 2 else 0))
	return done


func _is_far(sid: int) -> bool:
	var f := focus_sid()
	if f < 0:
		return false
	var a: Vector2 = PD.settlement(sid).get("pos", Vector2.ZERO)
	var b: Vector2 = PD.settlement(f).get("pos", Vector2.ZERO)
	return a.distance_to(b) > REGION_RADIUS


func _untied(ch: String, rec: Dictionary, c: Dictionary) -> bool:
	var om: Variant = _om()
	var hm: Variant = _mod("homes")
	if not (c["own"] as Array).is_empty() or not om.memberships(ch).is_empty() or not (c["emp"] as Dictionary).is_empty():
		return false
	if String(rec["sp"]) != "" or not (_kids.get(ch, []) as Array).is_empty():
		return false
	if _holds_land(ch) or (_mod("businesses") != null and not _mod("businesses").owned_by(ch).is_empty()):
		return false
	if hm != null and (hm.dependents(ch) > 0 or not hm.homes_of(ch).is_empty()):
		return false
	return true


func _demote(ch: String, _rec: Dictionary, c: Dictionary) -> bool:
	var sid := int(c["sid"])
	var om: Variant = _om()
	agg_add(sid, int(c["cash"]))
	var reg: Variant = _mod("registry")
	var dn: Variant = _mod("dynasties")
	if dn != null:
		dn.leave_house(ch)
	var fa: Variant = _mod("faith")
	if fa != null:
		fa.drop_character(ch)
	var rm: Variant = _mod("rumours")
	if rm != null:
		rm.drop_character(ch)
	if _town.has(sid):
		(_town[sid] as Array).erase(ch)
	om.unemploy(ch)
	_m.erase(ch)
	_trace.erase(ch)
	var pe: Variant = _mod("persona")
	if pe != null:
		pe.drop(ch)
	if reg != null:
		reg.retire(ch, "d%d folded into %s" % [_now(), PD.sname(sid)])
	stats["demoted"] = int(stats["demoted"]) + 1
	return true


# ------------------------------------------------------------------ ticks

func _run_chunk(chs: Array, day: int) -> Array:
	var t0 := Time.get_ticks_usec()
	var i := 0
	_cost = 0
	for ch: String in chs:
		i += 1
		if _m.has(ch) and int((_m[ch] as Dictionary)["n"]) <= day:
			decide(ch, day)
		# A chunk that has spent its work units leaves the rest for tomorrow (the pump budget is 0.6 ms a job).
		if _cost >= CHUNK_UNITS:
			for rest: String in chs.slice(i):
				if _m.has(rest) and int((_m[rest] as Dictionary)["n"]) <= day:
					_schedule(rest, day + 1)
			break
	var dt := Time.get_ticks_usec() - t0
	_tick_us += dt
	_tick_max = maxi(_tick_max, dt)
	if profile and dt > int(_prof.get("slow_us", 0)):
		var who: Array = []
		for c: String in chs:
			who.append("%s:%s" % [c, goal_of(c) if _m.has(c) else "gone"])
		_prof["slow_us"] = dt
		_prof["slow_who"] = who
		_prof["slow_day"] = day
	return []


func _due_list(day: int) -> Array:
	var list: Array = []
	for d: Variant in _due.keys():
		if int(d) <= day:
			for ch: String in _due[d]:
				if _m.has(ch) and int((_m[ch] as Dictionary)["n"]) <= day:
					list.append(ch)
			_due.erase(d)
	return list


func tick_day_chunks(day: int, _ctx: Dictionary) -> Array:
	_day = day
	_tick_us = 0
	_tick_max = 0
	_moves_today = 0
	var jobs: Array = []
	jobs.append(func() -> Array: return _job_seed(day))
	jobs.append(func() -> Array: return _job_hiring(day))
	jobs.append(func() -> Array: return _job_owners(day))
	jobs.append(func() -> Array: return _job_parcels(day))
	var list := _due_list(day)
	var i := 0
	while i < list.size():
		var part: Array = list.slice(i, i + CHUNK)
		jobs.append(func() -> Array: return _run_chunk(part, day))
		i += CHUNK
	return jobs


## The day's housekeeping, in jobs of their own so none is a spike: seeding (in small batches over the first days), the hiring index, and the
## owners' and land indexes of other modules, which rebuild lazily on first use after a change (pay for that here, not inside a decision).
func _job_seed(day: int) -> Array:
	if auto_seed and not _seeded and _om() != null and bool(_om().auto_seed):
		_seeded = true
		_phase = 1
		_seed_start = day
	if _phase == 1:
		_top_up(day, SEED_PER_DAY)
		if _m.size() >= mini(seed_target, MIND_MAX) or day - _seed_start > 40:
			_phase = 2
			_couple_q = _town.keys()
			_couple_q.sort()
	elif _phase == 2:
		var part: Array = _couple_q.slice(0, 5)
		_couple_q = _couple_q.slice(5)
		_seed_couples(part)
		if _couple_q.is_empty():
			_phase = 0
	elif _seeded and _m.size() < seed_target and _m.size() < MIND_MAX:
		_top_up(day, TOP_UP_PER_DAY)
	return []


func _job_hiring(day: int) -> Array:
	_refresh_hiring(day)
	return []


func _job_owners(_day2: int) -> Array:
	var bz: Variant = _mod("businesses")
	if bz != null:
		bz.owned_by("")
	return []


func _job_parcels(_day2: int) -> Array:
	var fm: Variant = _mod("farming")
	if fm != null:
		fm.parcels_of("")
	return []


func _top_up(day: int, per: int) -> void:
	var made := 0
	var tries := 0
	while made < per and tries < per * 3 and _m.size() < seed_target and _m.size() < MIND_MAX:
		tries += 1
		var sid := _h("tu", day, tries) % maxi(1, WorldSim.ranges.size())
		var rg: Vector2i = WorldSim.ranges[sid]
		var row := rg.x + _h("turow", day, tries) % maxi(1, rg.y - rg.x)
		if ensure_row(row) != "":
			made += 1


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


func tick_week(week: int, _ctx: Dictionary) -> Array:
	_day = maxi(_day, PD.today())
	_week_agg(week)
	return []


func catch_up(days: int, _ctx: Dictionary) -> Array:
	# Closed form: age and die statistically; everything else is the usual weekly world moving on.
	_day += days
	for ch: String in ids():
		var rec: Dictionary = _m[ch]
		while int(rec["y"]) <= _day and _m.has(ch):
			var yd := int(rec["y"])
			if _birthday(ch, rec, yd):
				break
		if _m.has(ch):
			_schedule(ch, _day + 1 + _h("cu", _day, ch) % CADENCE_MID)
	return []


func perf() -> Dictionary:
	return {"us": _tick_us, "max_chunk_us": _tick_max, "minds": _m.size(), "prof": _prof.duplicate()}


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	var rows: Dictionary = {}
	for ch: Variant in _m:
		var r: Dictionary = _m[ch]
		rows[ch] = [int(r["b"]), int(r["x"]), int(r["g"]), int(r["n"]), int(r["y"]) - int(r["b"]), int(r["l"]), int(r["f"]), int(r["r"]), String(r["sp"]), String(r["pa"]),
			String(r["tp"]), int(r["ed"]), int(r["j"]), int(r["cd"]), String(r["fo"])]
	var agg: Dictionary = {}
	for sid: Variant in _agg:
		agg[str(sid)] = [int(float((_agg[sid] as Array)[0])), int(float((_agg[sid] as Array)[1]))]
	return {"m": rows, "agg": agg, "dead": _dead, "day": _day, "seeded": _seeded, "focus": _focus, "ff": focus_fixed, "st": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_m = {}
	_due = {}
	_town = {}
	_kids = {}
	_agg = {}
	_hire_idx = {}
	_hire_day = -1
	_info = {}
	_info_day = -1
	var om: Variant = _om()
	var rows: Dictionary = d.get("m", {})
	var chs: Array = rows.keys()
	chs.sort()
	for ch: Variant in chs:
		var a: Array = rows[ch]
		var rec := {"b": int(a[0]), "x": int(a[1]), "g": int(a[2]), "n": int(a[3]), "y": int(a[0]) + int(a[4]), "l": int(a[5]), "f": int(a[6]), "r": int(a[7]), "sp": String(a[8]),
			"pa": String(a[9]), "tp": String(a[10]), "ed": int(a[11]), "j": int(a[12]), "o": 0, "od": -99, "cd": int(a[13]), "fo": String(a[14])}
		var sid := -1
		if om != null and om.has_char(String(ch)):
			sid = int((om.char_rec(String(ch)) as Dictionary)["sid"])
		_m[String(ch)] = rec
		if not _town.has(sid):
			_town[sid] = []
		(_town[sid] as Array).append(String(ch))
		if String(rec["pa"]) != "":
			if not _kids.has(String(rec["pa"])):
				_kids[String(rec["pa"])] = []
			(_kids[String(rec["pa"])] as Array).append(String(ch))
		var n := int(rec["n"])
		if not _due.has(n):
			_due[n] = []
		(_due[n] as Array).append(String(ch))
	var agg: Dictionary = d.get("agg", {})
	for k: Variant in agg:
		_agg[int(k)] = [float((agg[k] as Array)[0]), float((agg[k] as Array)[1])]
	_dead = int(d.get("dead", 0))
	_day = int(d.get("day", 0))
	_seeded = bool(d.get("seeded", false))
	_focus = int(d.get("focus", -1))
	focus_fixed = bool(d.get("ff", false))
	var st: Dictionary = d.get("st", {})
	for k: String in stats:
		stats[k] = int(st.get(k, stats[k]))
