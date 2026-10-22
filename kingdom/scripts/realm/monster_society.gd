extends "res://scripts/realm/realm_module.gd"
## MN-6..MN-11: the social side of monster companions. Pure data, deterministic, closed-form catch_up.
##   fame / infamy   how known (and for what) a namer is, per settlement and per culture (news of a name travels with a delay)
##   gates           permits, a bribe log, and the glue from Status + EntryLaw to the player's party (entry verdict, options, effects)
##   prejudice       (settlement, culture, species) -> 0..1, softened slowly by contact, raised by incidents and atrocities
##   reactions       weekly household comfort -> complaint, petition, protest, leaving (reason "monsters"), arrivals of friendly folk
## The migration module is another team's: departures are queued here (`take_departures`) and posted as news; it reads them.

const Data := preload("res://scripts/realm/mn_data.gd")
const Status := preload("res://scripts/realm/status.gd")
const EntryLaw := preload("res://scripts/realm/entry_law.gd")
const Barks := preload("res://scripts/realm/monster_barks.gd")

const PERMIT_MAX := 64
const BRIBE_MAX := 64
const PREJ_MAX := 800
const POSITIVE_CONTACT_PER_YEAR := 0.01
const ATROCITY := 0.2
const CHILD_OFFSET := 0.15
const COMFORT_THRESHOLD := 0.5
const NEWS_DELAY := 4
const STAGES := ["content", "complain", "petition", "protest", "leave"]

var seed_value := 1
var barks := Barks.new()
var _fame: Dictionary = {}          # "subject|scope" -> [fame, infamy]; scope "t:<sid>" or "c:<culture>"
var _pending: Array = []            # delayed culture-scope news [[due_day, subject, culture, fame, infamy]]
var _permits: Array = []            # [{id, subject, kind, issuer, species, heads, expires, forged}]
var _next_permit := 1
var _bribes: Array = []             # [{subject, sid, price, day, evidence}]
var _prej: Dictionary = {}          # "sid|culture|species" -> float (touched pairs only)
var _contact: Dictionary = {}       # key -> contact today (0/1), cleared each day
var _stage: Dictionary = {}         # household id -> stage index
var _gone: Dictionary = {}          # household id -> day it left
var _tension: Dictionary = {}       # sid -> 0..1
var _departures: Array = []         # [{sid, hid, day, reason, n}]
var _arrivals: Array = []           # [{sid, day, kind, n}]
var _petitions: Array = []          # [{sid, hid, day, demands}]
var _day := 0


func _roll(tag: String, id: Variant, day: int) -> float:
	return float(absi(hash([seed_value, tag, day, str(id)])) % 10000) / 10000.0


func _faith() -> Variant:
	return hub.mod("faith") if hub != null else null


func culture_of_sid(sid: int) -> String:
	var f: Variant = _faith()
	if f != null and sid >= 0:
		return Data.culture_of(f.culture_tags(sid))
	return "caldric"


# ------------------------------------------------------------------ fame and infamy

func fame_of(subject: String, sid: int) -> float:
	return _fi(subject, sid)[0]


func infamy_of(subject: String, sid: int) -> float:
	return _fi(subject, sid)[1]


func _fi(subject: String, sid: int) -> Array:
	var a: Array = _fame.get("%s|t:%d" % [subject, sid], [0.0, 0.0])
	var b: Array = _fame.get("%s|c:%s" % [subject, culture_of_sid(sid)], [0.0, 0.0])
	return [clampf(float(a[0]) + float(b[0]), 0.0, 100.0), clampf(float(a[1]) + float(b[1]), 0.0, 100.0)]


func _bump(subject: String, scope: String, fame: float, infamy: float) -> void:
	var k := "%s|%s" % [subject, scope]
	var v: Array = _fame.get(k, [0.0, 0.0])
	_fame[k] = [clampf(float(v[0]) + fame, 0.0, 100.0), clampf(float(v[1]) + infamy, 0.0, 100.0)]


## A name was given: known at once where it happened; other cultures hear NEWS_DELAY days later and read it their own way.
func on_name_story(namer: String, sid: int, b: Dictionary, day: int) -> void:
	var weight := 1.0 + float(b.get("form", 0)) * 0.3 + (1.0 if String(b.get("grade", "")) == "true" else 0.0)
	if sid >= 0:
		var cult := culture_of_sid(sid)
		_bump(namer, "t:%d" % sid, 4.0 * weight, 2.0 * weight if cult == "solenne" else 0.0)
	for cult: String in Data.table("culture_attitudes").get("cultures", {}):
		var att := Status.attitude(cult, {"species": b.get("species", ""), "kind": b.get("kind", "monster")})
		_pending.append([day + NEWS_DELAY, namer, cult, 3.0 * weight if att >= 0 else 1.0 * weight, 4.0 * weight if att <= -2 else 0.0])
	if _pending.size() > 200:
		_pending = _pending.slice(_pending.size() - 200)


func add_infamy(subject: String, sid: int, amt: float) -> void:
	_bump(subject, "t:%d" % sid, 0.0, amt)


# ------------------------------------------------------------------ permits and bribes

func issue_permit(subject: String, kind: String, issuer: String, species: Array, heads: int, days: int, forged := false, day := -1) -> Dictionary:
	var d := _day if day < 0 else day
	var p := {"id": "pm%d" % _next_permit, "subject": subject, "kind": kind, "issuer": issuer, "species": species.duplicate(), "heads": heads,
		"expires": d + days, "forged": forged}
	_next_permit += 1
	_permits.append(p)
	if _permits.size() > PERMIT_MAX:
		_permits.pop_front()
	return p


func permits_of(subject: String, day: int) -> Array:
	return _permits.filter(func(p: Dictionary) -> bool: return p["subject"] == subject and int(p["expires"]) >= day)


func log_bribe(subject: String, sid: int, price: int, day: int, evidence: bool) -> void:
	_bribes.append({"subject": subject, "sid": sid, "price": price, "day": day, "evidence": evidence})
	if _bribes.size() > BRIBE_MAX:
		_bribes.pop_front()
	var recent := 0
	for b: Dictionary in _bribes:
		if b["subject"] == subject and day - int(b["day"]) <= 30:
			recent += 1
	add_infamy(subject, sid, 1.0 + (2.0 if recent >= 3 else 0.0))


func bribes_of(subject: String) -> Array:
	return _bribes.filter(func(b: Dictionary) -> bool: return b["subject"] == subject)


# ------------------------------------------------------------------ status and gates

func status_of(subject: String, sid: int, culture := "", extra := {}) -> Dictionary:
	var subj := Status.gather(hub, subject, sid, extra)
	if not subj.has("fame"):
		subj["fame"] = fame_of(subject, sid)
		subj["infamy"] = infamy_of(subject, sid)
	var obs := {"culture": culture if culture != "" else culture_of_sid(sid), "sid": sid, "kingdom": String(extra.get("kingdom", ""))}
	return Status.of(subj, obs, {"hub": hub})


func gate(subject: String, party: Array, town: Dictionary, hour: int, day: int, extra := {}) -> Dictionary:
	var sid := int(town.get("sid", 0))
	var st := status_of(subject, sid, String(town.get("culture", "")), extra)
	var ctx := {"hour": hour, "day": day, "seed": seed_value, "permits": permits_of(subject, day), "seal": bool(extra.get("church_seal", false)),
		"sponsor_status": float(extra.get("sponsor_status", 0.0))}
	var r := EntryLaw.check(party, town, float(st["value"]), ctx)
	r["status_band"] = st["band"]
	if r["verdict"] in ["turn_back", "bar"]:
		_news("gate_turned_back", sid, "A traveller with a strange company was turned away at the gate.", day)
	return r


func take_option(subject: String, party: Array, town: Dictionary, opt: String, hour: int, day: int, extra := {}) -> Dictionary:
	var sid := int(town.get("sid", 0))
	var st := status_of(subject, sid, String(town.get("culture", "")), extra)
	var ctx := {"hour": hour, "day": day, "seed": seed_value, "permits": permits_of(subject, day), "sponsor_status": float(extra.get("sponsor_status", 0.0)),
		"quality": float(extra.get("quality", 0.5)), "guard": extra.get("guard", {"perception": 0.4})}
	var r := EntryLaw.apply_option(party, town, opt, float(st["value"]), ctx)
	if float(r["infamy_delta"]) > 0.0:
		add_infamy(subject, sid, float(r["infamy_delta"]))
	if opt == "bribe" and bool(r["ok"]):
		log_bribe(subject, sid, -int(r["gold"]), day, bool(r["evidence"]))
		if bool(r["evidence"]):
			_news("bribe_found", sid, "They say a guard took coin to let a beast through.", day)
	if bool(r["arrest"]):
		_news("disguise_caught", sid, "Guards caught a smuggled beast at the gate.", day)
	return r


func _news(kind: String, sid: int, text: String, day: int) -> void:
	if hub == null:
		return
	var nw: Variant = hub.mod("news")
	if nw != null and sid >= 0:
		nw.post(kind, sid, text, 0.6, "", false, day)


# ------------------------------------------------------------------ prejudice

static func baseline(culture: String, species: String) -> float:
	var kind: String = String(Data.species_row(species).get("kind", "monster"))
	var a := Status.attitude(culture, {"species": species, "kind": kind})
	return clampf(0.5 - 0.15 * float(a), 0.05, 0.95)


func _pk(sid: int, culture: String, species: String) -> String:
	return "%d|%s|%s" % [sid, culture, species]


func prejudice(sid: int, culture: String, species: String) -> float:
	return float(_prej.get(_pk(sid, culture, species), baseline(culture, species)))


func _set_prej(sid: int, culture: String, species: String, v: float) -> void:
	if _prej.size() >= PREJ_MAX and not _prej.has(_pk(sid, culture, species)):
		return
	_prej[_pk(sid, culture, species)] = clampf(v, 0.0, 1.0)


## Positive contact (trade, shared work, a rescue) that happened today. Softens at POSITIVE_CONTACT_PER_YEAR per year of daily contact.
func contact(sid: int, culture: String, species: String) -> void:
	_contact[_pk(sid, culture, species)] = true


func incident(sid: int, culture: String, species: String, severity := 0.05) -> void:
	_set_prej(sid, culture, species, prejudice(sid, culture, species) + severity)
	_tension[sid] = clampf(float(_tension.get(sid, 0.0)) + severity * 2.0, 0.0, 1.0)


func atrocity(sid: int, culture: String, species: String) -> void:
	incident(sid, culture, species, ATROCITY)


## Doctrine change (a council ruling): the slow lever for church kingdoms.
func doctrine_shift(sid: int, culture: String, species: String, delta: float) -> void:
	_set_prej(sid, culture, species, prejudice(sid, culture, species) + delta)


static func child_prejudice(parent: float) -> float:
	return maxf(0.0, parent - CHILD_OFFSET)


func _drift_day() -> void:
	for k: String in _contact:
		var parts: PackedStringArray = k.split("|")
		_set_prej(int(parts[0]), parts[1], parts[2], float(_prej.get(k, baseline(parts[1], parts[2]))) - POSITIVE_CONTACT_PER_YEAR / 360.0)
	_contact.clear()
	for sid: Variant in _tension.keys():
		_tension[sid] = maxf(0.0, float(_tension[sid]) - 0.01)
		if float(_tension[sid]) <= 0.0:
			_tension.erase(sid)


func tension(sid: int) -> float:
	return float(_tension.get(sid, 0.0))


# ------------------------------------------------------------------ settlement reactions

static func comfort(prej: float, exposure: float) -> float:
	return clampf(1.0 - prej * clampf(exposure, 0.0, 1.0), 0.0, 1.0)


## households: [{id, culture}]; monsters: [{species, harmed bool}]. One week of reactions for settlement `sid`.
## Returns events [{type: "complain"|"petition"|"protest"|"leave"|"riot"|"arrive", sid, hid, ...}].
func weekly_reaction(sid: int, households: Array, monsters: Array, day: int, incident_today := false) -> Array:
	var ev: Array = []
	if monsters.is_empty():
		for h: Dictionary in households:
			if int(_stage.get(h["id"], 0)) > 0:
				_stage[h["id"]] = int(_stage[h["id"]]) - 1
		return ev
	var harmed := false
	for m: Dictionary in monsters:
		harmed = harmed or bool(m.get("harmed", false))
	var exposure := minf(1.0, float(monsters.size()) / 3.0 + (0.2 if harmed else 0.0))
	var friendly := 0
	for h: Dictionary in households:
		var hid := String(h["id"])
		if _gone.has(hid):
			continue
		var worst := 0.0
		for m: Dictionary in monsters:
			worst = maxf(worst, prejudice(sid, String(h.get("culture", "caldric")), String(m["species"])))
		var c := comfort(worst, exposure)
		var st := int(_stage.get(hid, 0))
		if c < COMFORT_THRESHOLD:
			if _roll("react", hid, day) < 0.55 + (0.2 if harmed else 0.0):
				st = mini(st + 1, STAGES.size() - 1)
		else:
			friendly += 1
			if st > 0 and _roll("calm", hid, day) < 0.5:
				st -= 1
		_stage[hid] = st
		var t := String(STAGES[st])
		if st > 0 and int(_stage.get("_seen" + hid, -1)) != st:
			_stage["_seen" + hid] = st
			match t:
				"complain":
					ev.append({"type": "complain", "sid": sid, "hid": hid})
				"petition":
					var dm: String = ["move_them", "muzzle_them", "register_them"][absi(hash([hid, day])) % 3]
					_petitions.append({"sid": sid, "hid": hid, "day": day, "demands": dm})
					ev.append({"type": "petition", "sid": sid, "hid": hid, "demand": dm})
				"protest":
					_tension[sid] = clampf(float(_tension.get(sid, 0.0)) + 0.1, 0.0, 1.0)
					ev.append({"type": "protest", "sid": sid, "hid": hid})
				"leave":
					_gone[hid] = day
					_departures.append({"sid": sid, "hid": hid, "day": day, "reason": "monsters", "n": 1})
					_tension[sid] = clampf(float(_tension.get(sid, 0.0)) + 0.05, 0.0, 1.0)
					ev.append({"type": "leave", "sid": sid, "hid": hid, "reason": "monsters"})
	if incident_today and float(_tension.get(sid, 0.0)) > 0.8:
		ev.append({"type": "riot", "sid": sid})
	if friendly > 0 and _roll("arrive", sid, day) < 0.3:
		_arrivals.append({"sid": sid, "day": day, "kind": "monster_friendly", "n": 1})
		ev.append({"type": "arrive", "sid": sid, "kind": "monster_friendly"})
	for e: Dictionary in ev:
		match String(e["type"]):
			"petition":
				_news("petition", sid, "Folk are muttering over the beasts in their streets.", day)
			"leave":
				_news("exodus", sid, "Families are leaving, they say, over the monsters.", day)
	return ev


func take_departures() -> Array:
	var d := _departures
	_departures = []
	return d


func take_arrivals() -> Array:
	var a := _arrivals
	_arrivals = []
	return a


func petitions() -> Array:
	return _petitions.duplicate(true)


func stage_of(hid: String) -> String:
	return String(STAGES[int(_stage.get(hid, 0))])


func has_left(hid: String) -> bool:
	return _gone.has(hid)


## Deterministic households for a settlement when the caller has none (culture tags from faith, else caldric).
func default_households(sid: int, n := 8) -> Array:
	var tags: Array = ["caldric"]
	var f: Variant = _faith()
	if f != null:
		tags = f.culture_tags(sid)
	var out: Array = []
	for i in n:
		out.append({"id": "h%d_%d" % [sid, i], "culture": Data.culture_of([tags[i % tags.size()]])})
	return out


# ------------------------------------------------------------------ gossip

func gossip(npc: String, subject_status: float, situation: String, culture: String, species: String, day: int, hour: int) -> Dictionary:
	barks.seed_value = seed_value
	return barks.pick(npc, Status.band_of(subject_status), situation, culture, species, day * 24 + hour)


# ------------------------------------------------------------------ ticks and save

func tick_day(day: int, _ctx: Dictionary) -> Array:
	_day = day
	var keep: Array = []
	for p: Array in _pending:
		if int(p[0]) <= day:
			_bump(String(p[1]), "c:" + String(p[2]), float(p[3]), float(p[4]))
		else:
			keep.append(p)
	_pending = keep
	_drift_day()
	return []


func tick_week(_week: int, _ctx: Dictionary) -> Array:
	if hub == null:
		return []
	var mb: Variant = hub.mod("monster_bonds")
	if mb == null:
		return []
	var sids := {}
	for id in mb.bond_ids():
		var s := int(mb.bond(id)["station"])
		if s >= 0:
			sids[s] = true
	var msgs: Array = []
	for sid: int in sids:
		var mons: Array = []
		for b: Dictionary in mb.stationed(sid):
			mons.append({"species": b["species"], "harmed": int(b["harmed"]) > 0})
		weekly_reaction(sid, default_households(sid), mons, _day)
	return msgs


func catch_up(days: int, _ctx: Dictionary) -> Array:
	# Closed form: positive contact is not remembered across a gap, tensions simply cool.
	_day += days
	for sid: Variant in _tension.keys():
		_tension[sid] = maxf(0.0, float(_tension[sid]) - 0.01 * float(days))
		if float(_tension[sid]) <= 0.0:
			_tension.erase(sid)
	return []


func serialize() -> Dictionary:
	return {"fame": _fame.duplicate(true), "pending": _pending.duplicate(true), "permits": _permits.duplicate(true), "np": _next_permit,
		"bribes": _bribes.duplicate(true), "prej": _prej.duplicate(), "stage": _stage.duplicate(), "gone": _gone.duplicate(),
		"tension": _tension.duplicate(), "dep": _departures.duplicate(true), "arr": _arrivals.duplicate(true), "pet": _petitions.duplicate(true), "day": _day}


func deserialize(d: Dictionary) -> void:
	_fame = (d.get("fame", {}) as Dictionary).duplicate(true)
	_pending = (d.get("pending", []) as Array).duplicate(true)
	_permits = (d.get("permits", []) as Array).duplicate(true)
	_next_permit = int(d.get("np", 1))
	_bribes = (d.get("bribes", []) as Array).duplicate(true)
	_prej = (d.get("prej", {}) as Dictionary).duplicate()
	_stage = (d.get("stage", {}) as Dictionary).duplicate()
	_gone = (d.get("gone", {}) as Dictionary).duplicate()
	_tension = {}
	for k: Variant in (d.get("tension", {}) as Dictionary):
		_tension[int(k)] = float(d["tension"][k])
	_departures = (d.get("dep", []) as Array).duplicate(true)
	_arrivals = (d.get("arr", []) as Array).duplicate(true)
	_petitions = (d.get("pet", []) as Array).duplicate(true)
	_day = int(d.get("day", 0))
