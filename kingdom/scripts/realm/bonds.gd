extends "res://scripts/realm/realm_module.gd"
## NPC-to-NPC relationships (NI-5, docs/design/NPC_INTELLIGENCE_MAP.md section 5). THIN ADAPTER: the ties themselves live in
## sim/npc_social_graph.gd (packed, top-K per character, eight signed-byte axes: trust, affection, respect, fear, resentment, rivalry,
## attraction, obligation; each decaying on its own half-life at read time). This module only decides what happens between people and
## turns it into deltas through data/npc/bonds.json.
##
## ASYMMETRIC: every event moves A's view of B and B's view of A by different amounts, and by the holder's own person record
## (persona.gd): a betrayal costs an honest person more trust, a pitiless one keeps the resentment longer, a bold one fears less.
## WHAT MOVES TIES: the town round (a slice of the towns every day; each town looks at a few pairs: chat, work together, kin, courting,
## apprenticeship, a soldier protecting a neighbour, the odd spat) and the events ring (weddings, feuds, crimes seen).
## WHAT TIES DO: minds.gd reads them as small bounded terms (who to marry, which organisation to join with friends, whom to avoid or take
## revenge on), rumours.gd spreads a story first along trusted ties with more belief, and four life stories are produced by the mechanisms:
##   APPRENTICE SURPASSES MASTER   a younger colleague is taught (persona skill bytes grow toward a ceiling set by the master's skill and
##                                 the talent gap); when the apprentice passes the master the master's view turns to rivalry and respect.
##   SOLDIER WEDS FARMER           soldiers protect neighbours (respect, obligation), courting forms attraction, minds weighs the match.
##   VILLAGE ELDER                 a town's most esteemed adult (respect and trust other people hold) is named its informal leader.
##   REVENGE / RECONCILIATION      a long grudge in a hot-tempered person opens a house feud (dynasties.gd); a merciful one reconciles.
## COST: nothing per tick for decay (closed form at read). Day tick is chunked: a seventh of the towns a day, CHUNK_TOWNS towns a job, at
## most ROUND_PAIRS pairs a town. catch_up is one bounded round per town plus closed-form apprenticeship. Determinism: every roll is
## hash([WorldSim.SEED, tag, day, id]).

const Graph := preload("res://scripts/sim/npc_social_graph.gd")
const Persona := preload("res://scripts/realm/persona.gd")
const Events := preload("res://scripts/realm/events.gd")
const PD := preload("res://scripts/realm/politics_data.gd")

const DATA_FILE := "res://data/npc/bonds.json"
const YEAR := 360
const ROUND_PAIRS := 6
const CHUNK_TOWNS := 1
const EVENTS_PER_JOB := 10          # world events turned into ties by one job (a backlog drains over the next days)
const MENTOR_MAX := 120
const STORY_MAX := 30
const VET_MAX := 160
const ESTEEM_MIN := 24.0
const ELDER_AGE := 24
## persona skill byte (0 craft, 1 trade, 2 arms, 3 lore) a profession is learned in.
const PROF_SKILL := {"farmer": 0, "carpenter": 0, "smith": 0, "laborer": 0, "merchant": 1, "hunter": 2, "mercenary": 2, "scout": 3}
const SOLDIER_PROFS := ["mercenary"]

static var _data: Dictionary = {}

var social_graph: Variant = null          # set by the hub's owner (Life); a private graph is made when nobody gave one
var _own: Variant = null
var _mentor: Dictionary = {}              # apprentice -> [master, day taught first]
var _leader: Dictionary = {}              # sid -> [ch, day]
var _vet: Dictionary = {}                 # ch -> day first seen under arms (a veteran stays one)
var _story: Array = []                    # [day, kind, a, b, text]
var _last_ev := 0
var _day := 0
var _pe: Variant = null
var _tmp := PackedFloat32Array()
var stats := {"events": 0, "rounds": 0, "pairs": 0, "taught": 0, "surpassed": 0, "soldier_weds_farmer": 0, "soldier_farmer_leader": 0, "elders": 0, "feuds_opened": 0,
	"reconciled": 0, "revenge": 0}
var by_kind: Dictionary = {}


static func data() -> Dictionary:
	if not _data.is_empty():
		return _data
	var f := FileAccess.open(DATA_FILE, FileAccess.READ)
	var doc: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	var d := {"events": {}, "scale": []}
	var axes: Array = Graph.BOND_AXES
	var sc: Array = []
	for i in axes.size():
		sc.append(null)
	if doc is Dictionary:
		var src: Dictionary = (doc as Dictionary).get("scale", {})
		for i in axes.size():
			if src.has(axes[i]):
				var r: Array = src[axes[i]]
				sc[i] = [int(Persona.FIELD.get(String(r[0]), -1)), float(r[1]), int(r[2])]
		for kind: String in (doc as Dictionary).get("events", {}):
			var row: Dictionary = (doc as Dictionary)["events"][kind]
			var pair: Array = []
			for side: String in ["self", "other"]:
				var v := PackedFloat32Array()
				v.resize(axes.size())
				for k: String in (row.get(side, {}) as Dictionary):
					var ix := axes.find(k)
					if ix >= 0:
						v[ix] = float(row[side][k])
				pair.append(v)
			(d["events"] as Dictionary)[kind] = pair
	d["scale"] = sc
	_data = d
	return _data


func _now() -> int:
	return maxi(_day, PD.today())


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


func _h(tag: String, day: int, id: Variant) -> int:
	return absi(hash([WorldSim.SEED, tag, day, id]))


func _roll(tag: String, day: int, id: Variant) -> float:
	return float(_h(tag, day, id) % 100000) / 100000.0


## The graph the ties live in: the game's (Life.npc_social_graph) when the hub was given it, else a private one (tests, tools).
func graph() -> Object:
	var g: Variant = social_graph
	if g == null and hub != null:
		g = hub.get("social_graph")
	if g != null:
		return g
	if _own == null:
		_own = Graph.new()
	return _own


# ------------------------------------------------------------------ reading

## A's view of B as a dictionary axis name -> value, decayed to `day` (today when -1). Empty axes read 0.
func view(a: String, b: String, day := -1) -> Dictionary:
	var v: PackedFloat32Array = graph().bond_get(a, b, _now() if day < 0 else day)
	var out := {}
	for i in Graph.BOND_AXES.size():
		out[Graph.BOND_AXES[i]] = v[i]
	return out


func axis(a: String, b: String, ax: int, day := -1) -> float:
	return graph().bond_get(a, b, _now() if day < 0 else day)[ax]


## One number, -100..100: how warmly A regards B.
func regard(a: String, b: String, day := -1) -> float:
	return _regard(graph().bond_get(a, b, _now() if day < 0 else day))


static func _regard(v: PackedFloat32Array) -> float:
	return clampf(0.35 * v[0] + 0.35 * v[1] + 0.2 * v[2] + 0.15 * v[6] - 0.6 * v[4] - 0.2 * v[3] - 0.15 * v[5], -100.0, 100.0)


## 0..100: friendship (the mean of trust and affection).
static func _close(v: PackedFloat32Array) -> float:
	return clampf((v[0] + v[1]) * 0.5, 0.0, 100.0)


## How well A and B would do as a couple, -100..100: attraction, affection and trust both ways, hatred and rivalry against.
func match_score(a: String, b: String, day := -1) -> float:
	var dd := _now() if day < 0 else day
	var g: Object = graph()
	var ab: PackedFloat32Array = g.bond_get(a, b, dd)
	var s := 0.4 * ab[6] + 0.3 * ab[1] + 0.2 * ab[0] + 0.1 * ab[2] - 0.6 * ab[4] - 0.3 * ab[5]
	var ba: PackedFloat32Array = g.bond_get(b, a, dd)
	s += 0.7 * (0.4 * ba[6] + 0.3 * ba[1] + 0.2 * ba[0] + 0.1 * ba[2] - 0.6 * ba[4] - 0.3 * ba[5])
	return clampf(s, -100.0, 100.0)


## Ties with real attraction (candidates for a marriage the character already has feelings for), strongest first.
func suitors(ch: String, limit := 3) -> Array:
	var out: Array = []
	for t: Array in graph().bond_list(ch, _now()):
		var v: PackedFloat32Array = t[1]
		if v[6] >= 14.0 and v[4] < 30.0:
			out.append(t[0])
	return out.slice(0, limit) if out.size() > limit else out


## Who `ch` would tell a story to and who would believe them: [[listener, trust the listener has in ch], ...] by trust, at most `limit`.
## A teller needs to be close to the listener (they chat), the listener needs to trust the teller.
func listeners(ch: String, limit := 3) -> Array:
	var out: Array = []
	var g: Object = graph()
	var dd := _now()
	for t: Array in g.bond_list(ch, dd):
		if _close(t[1]) < 15.0:
			continue
		var back: PackedFloat32Array = g.bond_get(String(t[0]), ch, dd)
		if back[0] >= 12.0 and back[4] < 40.0:
			out.append([t[0], back[0]])
	out.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	return out.slice(0, limit) if out.size() > limit else out


## Friends (closeness at least `min_close`), strongest first.
func friends(ch: String, min_close := 20.0, limit := 4) -> Array:
	var out: Array = []
	for t: Array in graph().bond_list(ch, _now()):
		if _close(t[1]) >= min_close:
			out.append(t[0])
	return out.slice(0, limit) if out.size() > limit else out


## The strongest grudge: {"id", "v"} (resentment, with rivalry counting for half) or {} when there is none worth the name.
func foe(ch: String, min_v := 12.0) -> Dictionary:
	var best := {}
	var bv := min_v
	for t: Array in graph().bond_list(ch, _now()):
		var v: PackedFloat32Array = t[1]
		var x := maxf(v[4], 0.0) + 0.5 * maxf(v[5], 0.0)
		if x > bv:
			bv = x
			best = {"id": t[0], "v": x}
	return best


## 0..1 how much `ch` wants to be elsewhere: fear and resentment of people it knows.
func avoidance(ch: String) -> float:
	var m := 0.0
	for t: Array in graph().bond_list(ch, _now()):
		var v: PackedFloat32Array = t[1]
		m = maxf(m, maxf(v[3] * 0.8, v[4] * 0.7))
	return clampf(m / 100.0, 0.0, 1.0)


## 0..1 the pull of a friend already seated in an organisation: friends the character has that belong to one.
func friend_pull(ch: String, member_of: Callable) -> float:
	var best := 0.0
	for t: Array in graph().bond_list(ch, _now()):
		var c := _close(t[1])
		if c >= 20.0 and bool(member_of.call(t[0])):
			best = maxf(best, c)
	return clampf(best / 80.0, 0.0, 1.0)


## Who people in `sid` look up to: {"id", "esteem"} for the current informal leader or {}.
func leader_of(sid: int) -> Dictionary:
	var l: Variant = _leader.get(sid)
	return {"id": String(l[0]), "since": int(l[1])} if l != null else {}


func story_log() -> Array:
	return _story.duplicate()


func mentor_of(ch: String) -> String:
	var m: Variant = _mentor.get(ch)
	return String(m[0]) if m != null else ""


func is_veteran(ch: String) -> bool:
	return _vet.has(ch)


# ------------------------------------------------------------------ writing

func _persona_of(ch: String) -> Array:
	if _pe == null:
		_pe = _mod("persona")
	if _pe != null:
		var o: int = _pe.off(ch)
		if o >= 0:
			return [_pe.buf(), o]
	return [Persona.neutral(), 0]


## Applies one holder's side of an event: persona-scaled deltas onto holder's view of target.
func _apply(holder: String, target: String, deltas: PackedFloat32Array, day: int, mag: float) -> bool:
	var sc: Array = data()["scale"]
	var pp := _persona_of(holder)
	var pb: PackedByteArray = pp[0]
	var po: int = pp[1]
	if _tmp.size() != deltas.size():
		_tmp.resize(deltas.size())
	var any := false
	for i in deltas.size():
		var dv := deltas[i] * mag
		if dv != 0.0 and sc[i] != null:
			var r: Array = sc[i]
			var sg: int = r[2]
			if int(r[0]) >= 0 and (sg == 0 or (sg > 0 and dv > 0.0) or (sg < 0 and dv < 0.0)):
				dv *= clampf(1.0 + float(r[1]) * (2.0 * float(pb[po + int(r[0])]) / 255.0 - 1.0), 0.4, 1.7)
		_tmp[i] = dv
		any = any or dv != 0.0
	return any and graph().bond_adjust(holder, target, _tmp, day)


## One event between `a` and `b` (see data/npc/bonds.json for the kinds). `mag` scales it. False when the kind is unknown or neither
## person can hold a tie.
func event(kind: String, a: String, b: String, day := -1, mag := 1.0) -> bool:
	var row: Variant = (data()["events"] as Dictionary).get(kind)
	if row == null or a == b or Graph.person_number(a) == 0 or Graph.person_number(b) == 0:
		return false
	var dd := _now() if day < 0 else day
	var ok1 := _apply(a, b, (row as Array)[0], dd, mag)
	var ok2 := _apply(b, a, (row as Array)[1], dd, mag)
	stats["events"] = int(stats["events"]) + 1
	by_kind[kind] = int(by_kind.get(kind, 0)) + 1
	return ok1 or ok2


func forget(ch: String) -> void:
	graph().bond_forget(ch)
	_mentor.erase(ch)
	for k: Variant in _mentor.keys():
		if String((_mentor[k] as Array)[0]) == ch:
			_mentor.erase(k)
	_vet.erase(ch)
	for sid: Variant in _leader.keys():
		if String((_leader[sid] as Array)[0]) == ch:
			_leader.erase(sid)


func _tell(day: int, kind: String, a: String, b: String, text: String) -> void:
	_story.append([day, kind, a, b, text.substr(0, 90)])
	if _story.size() > STORY_MAX:
		_story.pop_front()
	var reg: Variant = _mod("registry")
	if reg != null:
		reg.remember(a, "d%d %s" % [day, text])
		if b != "":
			reg.remember(b, "d%d %s" % [day, text])


# ------------------------------------------------------------------ the world's events

func _scan_events(day: int) -> void:
	var ev: Variant = _mod("events")
	if ev == null:
		return
	var mn: Variant = _mod("minds")
	var rows: Array = ev.after(_last_ev)
	var seen := 0
	for r: Dictionary in rows:
		if seen >= EVENTS_PER_JOB:
			break
		_last_ev = maxi(_last_ev, int(r["n"]))
		var acts: Array = r["actors"]
		seen += 1 if String(r["kind"]) in ["marriage", "emergency", "crime"] else 0
		match String(r["kind"]):
			"marriage":
				if acts.size() >= 2:
					_on_wedding(String(acts[0]), String(acts[1]), day)
			"emergency":
				if String(r["cause"]) == "feud" and acts.size() >= 2:
					event("feud", String(acts[0]), String(acts[1]), day)
			"crime":
				if acts.size() >= 1 and mn != null and String(r["cause"]) != "feud_violence":
					_on_crime(String(acts[0]), String(r["where"]), int(r["n"]), day, mn)


func _on_wedding(a: String, b: String, day: int) -> void:
	event("marriage", a, b, day)
	var dn: Variant = _mod("dynasties")
	if dn != null:                                  # the families meet: a few in-law ties each way
		for pair: Array in [[a, b], [b, a]]:
			var fam: Array = dn.members_of(dn.house_of(String(pair[1]))) if dn.house_of(String(pair[1])) != "" else []
			var done := 0
			for m: Variant in fam:
				if String(m) != String(pair[0]) and String(m) != String(pair[1]) and done < 2:
					event("inlaw", String(pair[0]), String(m), day)
					done += 1
	var om: Variant = _mod("organizations")
	var pa := _prof(a, om)
	var pb := _prof(b, om)
	var sa: bool = pa in SOLDIER_PROFS or _vet.has(a)
	var sb: bool = pb in SOLDIER_PROFS or _vet.has(b)
	if (sa and pb == "farmer" and not sb) or (sb and pa == "farmer" and not sa):
		var sol := a if sa else b
		var far := b if sa else a
		stats["soldier_weds_farmer"] = int(stats["soldier_weds_farmer"]) + 1
		_vet[sol] = _vet.get(sol, day)
		_tell(day, "soldier_weds_farmer", sol, far, "a soldier weds a farmer")


func _on_crime(who: String, where: String, n: int, day: int, mn: Object) -> void:
	if Graph.person_number(who) == 0 or not where.begins_with("ss:"):
		return
	for w: Variant in mn.witnesses_at(int(where.substr(3)), 2, n):
		if String(w) != who:
			event("crime_witnessed", String(w), who, day)


func _prof(ch: String, om: Variant) -> String:
	return String((om.char_rec(ch) as Dictionary).get("prof", "")) if om != null else ""


# ------------------------------------------------------------------ the town round

func _adult(mn: Object, ch: String) -> bool:
	return mn.age_of(ch) >= 16


## One town's round: up to ROUND_PAIRS pairs meet. `scale` > 1 is a catch-up (several weeks in one pass, bounded).
func _town_round(sid: int, day: int, scale := 1) -> void:
	var mn: Variant = _mod("minds")
	var om: Variant = _mod("organizations")
	if mn == null or om == null:
		return
	var lst: Array = mn.in_town(sid)
	var n := lst.size()
	if n < 2:
		return
	stats["rounds"] = int(stats["rounds"]) + 1
	var pairs := mini(ROUND_PAIRS * scale, maxi(1, n / 2) * scale)
	pairs = mini(pairs, 24)
	var danger := float((mn.town_facts(sid, day) as Dictionary).get("danger", 0.0))
	var g: Object = graph()
	for k in pairs:
		var i := _h("bpi", day, sid * 64 + k) % n
		var a: String = lst[i]
		var b := ""
		if _roll("bpk", day, sid * 64 + k) < 0.4:          # an old acquaintance is more likely to be met again
			var kn: Array = g.bond_list(a, day, 3)
			if not kn.is_empty():
				var cand := String((kn[_h("bpj", day, sid * 64 + k) % kn.size()] as Array)[0])
				if mn.is_mind(cand) and int(mn.town_of(cand)) == sid:
					b = cand
		if b == "":
			b = lst[(i + 1 + _h("bpn", day, sid * 64 + k) % (n - 1)) % n]
		if a == b or not _adult(mn, a) or not _adult(mn, b):
			continue
		stats["pairs"] = int(stats["pairs"]) + 1
		_meet(a, b, sid, day, mn, om, danger, k)
	_grudges(sid, day, lst, mn)


func _meet(a: String, b: String, sid: int, day: int, mn: Object, om: Object, danger: float, k: int) -> void:
	var va: PackedFloat32Array = graph().bond_get(a, b, day)
	# people who fear or hate each other keep apart: the tie is not renewed
	if va[4] >= 50.0 or va[3] >= 50.0:
		return
	var vb: PackedFloat32Array = graph().bond_get(b, a, day)
	if vb[4] >= 50.0 or vb[3] >= 50.0:
		return
	var pa := _prof(a, om)
	var pb := _prof(b, om)
	var sa: bool = pa in SOLDIER_PROFS
	var sb: bool = pb in SOLDIER_PROFS
	if sa:
		_vet[a] = _vet.get(a, day)
	if sb:
		_vet[b] = _vet.get(b, day)
	if _vet.size() > VET_MAX:
		_vet.erase(_vet.keys()[0])
	var dn: Variant = _mod("dynasties")
	var ha: String = dn.house_of(a) if dn != null else ""
	var hb: String = dn.house_of(b) if dn != null else ""
	var ag_a: int = mn.age_of(a)
	var ag_b: int = mn.age_of(b)
	var r := _roll("bpm", day, a + b + str(k))
	if ha != "" and ha == hb:
		event("family", a, b, day)
	elif dn != null and ha != "" and hb != "" and dn.feud_heat(ha, hb) >= 30.0 and r < 0.5:
		event("spat", a, b, day)
	elif (sa != sb) and r < 0.45 + 0.4 * danger:
		# a soldier on the town's watch stands between a neighbour and trouble
		event("protect", a if sa else b, b if sa else a, day)
	elif pa == pb and pa != "" and absi(ag_a - ag_b) >= 10 and _teach(a, b, ag_a, ag_b, pa, day):
		pass
	elif pa == pb and pa != "" and r > 0.92:
		event("spat", a, b, day)                          # rivals in one trade
	elif pa == pb and pa != "":
		event("work_together", a, b, day)
	elif mn.spouse_of(a) == "" and mn.spouse_of(b) == "" and mn.sex_of(a) != mn.sex_of(b) and ag_a >= 17 and ag_b >= 17 \
			and absi(ag_a - ag_b) <= 9 and ag_a <= 45 and ag_b <= 45 and r < 0.6:
		event("court", a, b, day)
	elif r > 0.93 and va[0] > 10.0:
		event("help", a, b, day)
	else:
		event("chat", a, b, day)


## An older colleague takes a younger one in hand (once; the pair stays a master and an apprentice until the apprentice passes the master).
func _teach(a: String, b: String, ag_a: int, ag_b: int, prof: String, day: int) -> bool:
	var master := a if ag_a > ag_b else b
	var app := b if master == a else a
	if _mentor.has(app) or _mentor.size() >= MENTOR_MAX or not PROF_SKILL.has(prof):
		return false
	_pe = _mod("persona")
	if _pe == null:
		return false
	var idx: int = PROF_SKILL[prof]
	var sm: int = _pe.skill_of(master, idx)
	var sa: int = _pe.skill_of(app, idx)
	if sm < 0 or sa < 0 or sm < sa + 10:
		return false
	_mentor[app] = [master, day]
	stats["taught"] = int(stats["taught"]) + 1
	event("teach", master, app, day)
	return true


## The apprentices (those whose number falls on today's slice) learn; closed form for `weeks` weeks at once.
func _mentors_step(day: int, weeks: int, only_slice := true) -> void:
	_pe = _mod("persona")
	var mn: Variant = _mod("minds")
	var om: Variant = _mod("organizations")
	if _pe == null or mn == null or om == null:
		return
	var apps: Array = _mentor.keys()
	apps.sort()
	for app: Variant in apps:
		var ap := String(app)
		if only_slice and Graph.person_number(ap) % 7 != day % 7:
			continue
		var rec: Array = _mentor[ap]
		var master := String(rec[0])
		if not mn.is_mind(ap) or not mn.is_mind(master):
			_mentor.erase(ap)
			continue
		var prof := _prof(ap, om)
		if not PROF_SKILL.has(prof):
			continue
		var idx: int = PROF_SKILL[prof]
		var sm: int = _pe.skill_of(master, idx)
		var sa: int = _pe.skill_of(ap, idx)
		if sm < 0 or sa < 0:
			_mentor.erase(ap)
			continue
		var tal: float = float(_pe.intelligence(ap)) - float(_pe.intelligence(master))
		# the most the apprentice can reach is the master's own skill, plus 36 points for each tenth of intelligence they have beyond
		# the master's and a fifth: only a clearly gifted one can pass
		var ceiling := float(sm) + 36.0 * (tal - 0.12)
		var rate := (1.0 + 4.0 * float(_pe.intelligence(ap))) * float(weeks)
		var room := ceiling - float(sa)
		var gain := int(minf(rate, maxf(room, 0.0)))
		if gain > 0:
			_pe.skill_gain(ap, idx, gain)
			sa += gain
		if mn.town_of(ap) == mn.town_of(master) and weeks >= 1:
			event("teach", master, ap, day, 0.5)
		if sa > sm + 2:
			_surpassed(ap, master, day)
			_mentor.erase(ap)


func _surpassed(app: String, master: String, day: int) -> void:
	stats["surpassed"] = int(stats["surpassed"]) + 1
	event("outshine", master, app, day)
	_tell(day, "apprentice_surpasses_master", app, master, "an apprentice surpasses the master")
	var dn: Variant = _mod("dynasties")
	var mn: Variant = _mod("minds")
	if dn != null and mn != null:
		dn.deed(app, "built", int(mn.town_of(app)), 1.0)
	Events.log_to(hub, "founding", "ss:%d" % int(mn.town_of(app)) if mn != null else "", [app, master], "apprentice_surpasses_master", "An apprentice has passed their master", 3)


# ------------------------------------------------------------------ elders

## Every fourth week the town's most esteemed adult becomes its informal leader (or stays).
func _elder(sid: int, day: int, mn: Object) -> void:
	if (day / 7) % 4 != sid % 4:
		return
	var lst: Array = mn.in_town(sid)
	if lst.size() < 4:
		return
	var esteem := {}
	var g: Object = graph()
	for h: Variant in lst:
		for t: Array in g.bond_list(String(h), day, Graph.BOND_K, false):
			var v: PackedFloat32Array = t[1]
			var e := 0.5 * v[2] + 0.3 * v[0] + 0.2 * v[1] + 0.25 * v[7]
			if e > 0.0:
				esteem[t[0]] = float(esteem.get(t[0], 0.0)) + e
	var best := ""
	var bv := 0.0
	var keys: Array = esteem.keys()
	keys.sort()
	for c: Variant in keys:
		var cs := String(c)
		if not mn.is_mind(cs) or int(mn.town_of(cs)) != sid or mn.age_of(cs) < ELDER_AGE or mn.age_of(cs) > 70:
			continue
		var e2 := float(esteem[c]) + (6.0 if _vet.has(cs) else 0.0)
		if e2 > bv:
			bv = e2
			best = cs
	if best == "" or bv < ESTEEM_MIN:
		return
	var cur: Variant = _leader.get(sid)
	if cur != null and mn.is_mind(String(cur[0])):
		if String(cur[0]) == best:
			return
		var ce := float(esteem.get(String(cur[0]), 0.0))
		if bv < ce * 1.3 + 4.0:
			return
	_leader[sid] = [best, day]
	stats["elders"] = int(stats["elders"]) + 1
	var tag := "veteran" if _vet.has(best) else "elder"
	_tell(day, "village_leader", best, "", "%s rises to lead %s" % [tag, PD.sname(sid)])
	var spouse: String = mn.spouse_of(best)
	if _vet.has(best) and spouse != "" and _prof(spouse, _mod("organizations")) == "farmer":
		stats["soldier_farmer_leader"] = int(stats["soldier_farmer_leader"]) + 1
		_tell(day, "soldier_farmer_leader", best, spouse, "a soldier who wed a farmer now leads the village")
	Events.log_to(hub, "succession", "ss:%d" % sid, [best], "village_elder", "The village looks to a new elder", 3)
	var dn: Variant = _mod("dynasties")
	if dn != null:
		dn.deed(best, "kept_order", sid, 1.0)
	for h2: Variant in lst:                               # the esteem is made official: those who rated them gain a little more respect
		if String(h2) != best and g.bond_get(String(h2), best, day)[2] > 8.0:
			event("help", best, String(h2), day, 0.3)


# ------------------------------------------------------------------ grudges

## A hot-tempered person with a long grudge in their own town acts on it; a merciful one lets it go.
func _grudges(sid: int, day: int, lst: Array, mn: Object) -> void:
	var h: String = lst[_h("grj", day, sid) % lst.size()]
	var f: Dictionary = foe(h, 24.0)
	if f.is_empty():
		return
	var tgt := String(f["id"])
	if not mn.is_mind(tgt) or int(mn.town_of(tgt)) != sid:
		return
	var pp := _persona_of(h)
	var pb: PackedByteArray = pp[0]
	var po: int = pp[1]
	var vol := float(pb[po + Persona.O_VOL]) / 255.0
	var pride := float(pb[po + Persona.O_PRI]) / 255.0
	var mercy := float(pb[po + Persona.O_MER]) / 255.0
	var bold := float(pb[po + Persona.O_BOLD]) / 255.0
	var p_act := clampf(0.05 + 0.25 * vol + 0.12 * pride + 0.1 * bold - 0.25 * mercy, 0.01, 0.5)
	var p_rec := clampf(0.04 + 0.35 * mercy - 0.1 * pride, 0.0, 0.5)
	var r := _roll("grr", day, h + tgt)
	if r < p_act:
		var dn: Variant = _mod("dynasties")
		var ha: String = dn.house_of(h) if dn != null else ""
		var hb: String = dn.house_of(tgt) if dn != null else ""
		stats["revenge"] = int(stats["revenge"]) + 1
		if dn != null and ha != "" and hb != "" and ha != hb and dn.feud_heat(ha, hb) <= 0.0:
			if dn.open_feud(ha, hb, "grudge", 32.0):
				stats["feuds_opened"] = int(stats["feuds_opened"]) + 1
				_tell(day, "revenge", h, tgt, "a grudge becomes a feud between houses")
		else:
			event("threat", h, tgt, day)
	elif r > 1.0 - p_rec:
		event("reconcile", h, tgt, day)
		stats["reconciled"] = int(stats["reconciled"]) + 1


# ------------------------------------------------------------------ the day

func tick_day_chunks(day: int, _ctx: Dictionary) -> Array:
	_day = day
	var jobs: Array = []
	jobs.append(func() -> Array:
		_scan_events(day)
		return [])
	var mn: Variant = _mod("minds")
	if mn != null:
		var sids: Array = []
		for sid: Variant in mn.towns():
			if int(sid) % 7 == day % 7:
				sids.append(int(sid))
		var i := 0
		while i < sids.size():
			var part: Array = sids.slice(i, i + CHUNK_TOWNS)
			jobs.append(func() -> Array:
				for s: Variant in part:
					_town_round(int(s), day)
				return [])
			if (day / 7) % 4 == int(part[0]) % 4:             # that town's monthly look at who the village looks up to
				jobs.append(func() -> Array:
					for s2: Variant in part:
						_elder(int(s2), day, mn)
					return [])
			i += CHUNK_TOWNS
	jobs.append(func() -> Array:
		_mentors_step(day, 1)
		return [])
	return jobs


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


## Elapsed days in one bounded pass: events once, one scaled round per town, apprenticeship in closed form. Decay needs nothing.
func catch_up(days: int, _ctx: Dictionary) -> Array:
	_day += days
	if days < 7:
		return []
	var weeks := mini(days / 7, 12)
	_scan_events(_now())
	var mn: Variant = _mod("minds")
	if mn != null:
		for sid: Variant in mn.towns():
			_town_round(int(sid), _now(), weeks)
			_elder(int(sid), (_now() / 28) * 28 + int(sid) % 4 * 7, mn)
	_mentors_step(_now(), mini(days / 7, 52), false)
	return []


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	var ment: Array = []
	var keys: Array = _mentor.keys()
	keys.sort()
	for k: Variant in keys:
		ment.append([k, (_mentor[k] as Array)[0], (_mentor[k] as Array)[1]])
	var lead: Array = []
	var ls: Array = _leader.keys()
	ls.sort()
	for s: Variant in ls:
		lead.append([s, (_leader[s] as Array)[0], (_leader[s] as Array)[1]])
	var vet: Array = _vet.keys()
	vet.sort()
	var out := {"v": 1, "last": _last_ev, "mentor": ment, "leader": lead, "vet": vet, "story": _story.duplicate(true), "stats": stats.duplicate(),
		"kinds": by_kind.duplicate()}
	# Ties normally save with the game's graph (npc_social_graph); a private graph (no game) saves here.
	if _own != null and social_graph == null and (hub == null or hub.get("social_graph") == null):
		var gs: Dictionary = (_own as Object).bond_serialize()
		if not gs.is_empty():
			out["ties"] = gs
	return out


func deserialize(d: Dictionary) -> void:
	_mentor = {}
	_leader = {}
	_vet = {}
	_story = []
	_last_ev = int(d.get("last", 0))
	for r: Variant in d.get("mentor", []):
		if r is Array and (r as Array).size() == 3:
			_mentor[String(r[0])] = [String(r[1]), int(r[2])]
	for r: Variant in d.get("leader", []):
		if r is Array and (r as Array).size() == 3:
			_leader[int(r[0])] = [String(r[1]), int(r[2])]
	for v: Variant in d.get("vet", []):
		_vet[String(v)] = 0
	for s: Variant in d.get("story", []):
		if s is Array:
			_story.append(s)
	for k: Variant in (d.get("stats", {}) as Dictionary):
		stats[k] = int(d["stats"][k])
	by_kind = (d.get("kinds", {}) as Dictionary).duplicate()
	if d.has("ties"):
		if _own == null:
			_own = Graph.new()
		(_own as Object).bond_deserialize(d["ties"])
