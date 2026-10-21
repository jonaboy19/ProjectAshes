extends "res://scripts/realm/realm_module.gd"
## AR-6/7/8/11 (docs/design/AURA_RELEASE.md sections 5, 8, 10): what the world remembers after an aura is released or a big deed done.
##  * dread and awe axes per (subject, town), half-lives from data/aura/aura_ladder.json. They are kept HERE because politics_data
##    AXES is frozen at nine axes; every change is mirrored onto the existing reputation axes (cruelty / strength / trust) so
##    witnesses, rumours and roads carry it (reputation.record), and onto a news item so far towns hear a vaguer, later story.
##  * recognition roll (disguise respected), the infamy cascade (shutters, empty market, curfew), bounded price/refusal, the bill.
##  * the escalation ladder 0..5 (watch, patrol, officer parley, captain and mages, knights/inquisitors, royal response) and the
##    player options (suppress, talk, intimidate, bribe, surrender, flee, fight, appeal) with deterministic outcomes.
##  * legends (cap 20).
## Nothing here moves an NPC. World/animation hooks are read-only views: fear_state(sid), cascade_level(). Rolls hash [SEED, "aura", day, id].

const Data := preload("res://scripts/sim/aura_data.gd")
const PD := preload("res://scripts/realm/politics_data.gd")
const SP := preload("res://scripts/realm/social_perception.gd")
const DV := preload("res://scripts/realm/district_values.gd")
const Faith := preload("res://scripts/realm/faith.gd")

const SUBJECT := "i:player"
const LEGEND_CAP := 20
const KEY_CAP := 40
const WITNESS_CAP := 12          # psyche memories written per incident
const WITNESS_DAY_CAP := 36      # ... and per day
const FLEE_FRAC := 0.08          # share of a town's people that flee after a severe event
const FLEE_MAX := 40
const FLEE_CALM_DAYS := 14       # dread under 20 for this long and the families come home
const FLEE_GIVE_UP := 180        # ... or they settle where they fled to
const OPTIONS := ["suppress", "talk", "intimidate", "bribe", "surrender", "flee", "fight", "fight_lethal", "appeal"]

var _ax: Dictionary = {}        # "subject#sid" -> [dread, awe, day, kingdom_scale 0/1, days_high]
var _lad: Dictionary = {}       # "subject#sid" -> {step, arrive, clock, s4, held, fav}
var _inc: Array = []            # ring of [day, sid, peak*100, harm*100, witnesses, step]
var _legends: Array = []        # [{id, subject, deed, day, sid}]
var _deeds: Dictionary = {}     # "subject|deed" -> count
var _bills: Dictionary = {}     # "subject#sid" -> gold due
var _gold := 0
var _day := 0
var _away: Dictionary = {}      # sid -> [n, dest_node, day_left, calm_days]: households that fled after a severe event
var _psy_day := -1
var _psy_n := 0
var _scout_day: Dictionary = {} # sid -> day of the last power report
var stats := {"incidents": 0, "deeds": 0, "options": 0, "bills_paid": 0, "witnessed": 0, "fled": 0, "returned": 0, "scouted": 0}


# ------------------------------------------------------------------ helpers

static func key(subject: String, sid: int) -> String:
	return "%s#%d" % [subject, sid]


func _now() -> int:
	return maxi(_day, PD.today())


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


static func ladder_data() -> Dictionary:
	return Data.table("aura_ladder")


func _roll(tag: String, id: Variant) -> float:
	return float(absi(hash([WorldSim.SEED, "aura", _now(), tag, id])) % 10000) / 10000.0


static func culture_row(kingdom: String) -> Dictionary:
	var cs: Dictionary = Data.table("aura_culture").get("cultures", {})
	var c := "other"
	if kingdom in Faith.CHURCH_KINGDOMS:
		c = "church"
	elif kingdom == SP.HOME or kingdom == "":
		c = "valencios"
	elif cs.has(kingdom):
		c = kingdom
	return (cs.get(c, cs.get("other", {})) as Dictionary).duplicate()


func _kingdom(sid: int, opts: Dictionary = {}) -> String:
	return String(opts.get("kingdom", PD.kingdom_of(sid)))


func _row(subject: String, sid: int) -> Array:
	var k := key(subject, sid)
	if not _ax.has(k):
		if _ax.size() >= KEY_CAP * 4:
			_evict()
		_ax[k] = [0.0, 0.0, _now(), 0, 0]
	return _ax[k]


func _evict() -> void:
	var worst := ""
	var wv := 1.0e9
	for k: String in _ax:
		var r: Array = _ax[k]
		var v := float(r[0]) + float(r[1])
		if v < wv:
			wv = v
			worst = k
	if worst != "":
		_ax.erase(worst)
		_lad.erase(worst)


func _decayed(v: float, from_day: int, half_life: float) -> float:
	return v * pow(0.5, float(maxi(_now() - from_day, 0)) / maxf(half_life, 1.0))


func _is_legend(subject: String) -> bool:
	for l: Dictionary in _legends:
		if String(l["subject"]) == subject:
			return true
	return false


# ------------------------------------------------------------------ axes

## Local dread/awe 0..100 with the documented half-lives (dread 90 days, 240 once a legend; awe 150).
func dread(subject: String, sid: int) -> float:
	var r: Array = _ax.get(key(subject, sid), [])
	if r.is_empty():
		return 0.0
	var ld := ladder_data()
	var hl := float(ld.get("dread_half_life_legend_days", 240)) if _is_legend(subject) else float(ld.get("dread_half_life_days", 90))
	return clampf(_decayed(float(r[0]), int(r[2]), hl), 0.0, 100.0)


func awe(subject: String, sid: int) -> float:
	var r: Array = _ax.get(key(subject, sid), [])
	if r.is_empty():
		return 0.0
	return clampf(_decayed(float(r[1]), int(r[2]), float(ladder_data().get("awe_half_life_days", 150))), 0.0, 100.0)


## Dread as the town believes it: local plus what the road told them of other towns, capped (30 points, 60 for a kingdom-scale deed).
func dread_felt(subject: String, sid: int) -> float:
	var local := dread(subject, sid)
	var other := 0.0
	var scale := false
	for k: String in _ax:
		if k.begins_with(subject + "#") and k != key(subject, sid):
			var o_sid := int(k.get_slice("#", 1))
			other = maxf(other, dread(subject, o_sid))
			scale = scale or int((_ax[k] as Array)[3]) == 1
	var cap := 60.0 if scale else float(ladder_data().get("spread_cap", 0.3)) * 100.0
	return clampf(local + minf(other * 0.5, cap), 0.0, 100.0)


## Applies a change, scaled by the culture of the kingdom (monster towns shrug, church kingdoms feel more of both).
func add(subject: String, sid: int, d_dread: float, d_awe: float, opts: Dictionary = {}) -> void:
	var cul := culture_row(_kingdom(sid, opts))
	var r := _row(subject, sid)
	var nd := dread(subject, sid) + d_dread * (float(cul.get("dread_mult", 1.0)) if d_dread > 0.0 else 1.0)
	var na := awe(subject, sid) + d_awe * (float(cul.get("awe_mult", 1.0)) if d_awe > 0.0 else 1.0)
	r[0] = clampf(nd, 0.0, 100.0)
	r[1] = clampf(na, 0.0, 100.0)
	r[2] = _now()
	if bool(opts.get("kingdom_scale", false)):
		r[3] = 1
	_mirror(subject, sid, d_dread, d_awe)


## Mirror onto the frozen reputation axes so rumours/witnesses/roads carry the change.
func _mirror(subject: String, sid: int, d_dread: float, d_awe: float) -> void:
	var rep: Variant = _mod("reputation")
	if rep == null:
		return
	if absf(d_dread) >= 1.0:
		rep.record(subject, "cruelty", d_dread * 0.25, sid, "witness")
	if absf(d_awe) >= 1.0:
		rep.record(subject, "strength", d_awe * 0.2, sid, "witness")


## A deed from the table in aura_ladder.json (deeds). magnitude scales it. Returns the dread delta applied.
func on_deed(subject: String, deed: String, sid: int, magnitude := 1.0, opts: Dictionary = {}) -> float:
	var def: Dictionary = (ladder_data().get("deeds", {}) as Dictionary).get(deed, {})
	if def.is_empty():
		return 0.0
	stats["deeds"] = int(stats["deeds"]) + 1
	var dd := float(def.get("dread", 0.0)) * magnitude
	var da := float(def.get("awe", 0.0)) * magnitude
	var big := absf(dd) >= 30.0 or absf(da) >= 30.0
	add(subject, sid, dd, da, {"kingdom": opts.get("kingdom", _kingdom(sid)), "kingdom_scale": big and (deed in ["siege_broken", "noble_assassinated", "breakthrough_seen"])})
	var nm: Variant = _mod("news")
	if nm != null and (absf(dd) + absf(da)) >= 10.0:
		nm.post("aura_incident", sid, "%s: %s" % [deed.replace("_", " "), "the one they fear" if dd > da else "the one they speak of"], clampf((absf(dd) + absf(da)) / 20.0, 0.5, 4.0))
	_note_deed(subject, deed, sid)
	if big:
		_followers_react(subject, sid, bool(opts.get("protect", false)))
		_scout_news(subject, sid, _kingdom(sid, opts))
	var dm: Variant = _mod("districts")
	if dm != null and dd > 0.0:
		for q: String in dm.quarters_of(sid):
			dm.on_crime(sid, q, clampf(dd / 40.0, 0.0, 1.0))
	return dd


func _note_deed(subject: String, deed: String, sid: int) -> void:
	var k := "%s|%s" % [subject, deed]
	_deeds[k] = int(_deeds.get(k, 0)) + 1
	var def: Dictionary = (ladder_data().get("deeds", {}) as Dictionary).get(deed, {})
	var weight := absf(float(def.get("dread", 0.0))) + absf(float(def.get("awe", 0.0)))
	if int(_deeds[k]) >= 3 or weight >= 45.0:
		_make_legend(subject, deed, sid)


func _make_legend(subject: String, deed: String, sid: int) -> void:
	for l: Dictionary in _legends:
		if String(l["subject"]) == subject and String(l["deed"]) == deed:
			return
	_legends.append({"id": "lg%d" % (_legends.size() + stats["deeds"]), "subject": subject, "deed": deed, "day": _now(), "sid": sid})
	while _legends.size() > LEGEND_CAP:
		_legends.pop_front()


func legends(subject := "") -> Array:
	var out: Array = []
	for l: Dictionary in _legends:
		if subject == "" or String(l["subject"]) == subject:
			out.append(l)
	return out


# ------------------------------------------------------------------ recognition and economy

## P(recognise) = clamp(axis/100*0.6 + gear*0.2 + face*0.2 + hearsay, 0, 1). A disguise nobody pierces mostly defeats it.
func recognise(observer: Dictionary, subject: Dictionary, sid: int, ctx: Dictionary = {}) -> float:
	var sub := String(subject.get("id", SUBJECT))
	var axis := maxf(dread_felt(sub, sid), awe(sub, sid))
	var p := clampf(axis / 100.0 * 0.6 + clampf(float(subject.get("gear_signature", 0.0)), 0.0, 1.0) * 0.2 + (0.2 if bool(observer.get("face_seen", false)) else 0.0) + clampf(float(ctx.get("hearsay", 0.0)), 0.0, 0.2), 0.0, 1.0)
	if not (subject.get("disguise", {}) as Dictionary).is_empty():
		var idn: Dictionary = SP.new().identity(observer, subject, {"day": _now()})
		if not bool(idn["exposed"]):
			p *= 0.1
	return p


## 0 calm .. 4 curfew (cascade thresholds 30/50/70/85). 5 = awe flipped the cascade: people come out.
func cascade_level(subject: String, sid: int) -> int:
	var dr := dread_felt(subject, sid)
	if awe(subject, sid) >= dr + 20.0 and dr > 0.0:
		return -1
	var lv := 0
	for t in ladder_data().get("cascade", [30, 50, 70, 85]):
		if dr >= float(t):
			lv += 1
	return lv


## What the world side (Codex) reads to flip shutters / empty stalls. No entity is touched.
func fear_state(sid: int, subject := SUBJECT) -> Dictionary:
	var lv := cascade_level(subject, sid)
	return {"level": lv, "shutters": lv >= 2, "market_empty": lv >= 3, "curfew": lv >= 4, "people_out": lv < 0, "dread": dread_felt(subject, sid), "awe": awe(subject, sid),
		"vendors_refuse": lv >= 3}


## Bounded risk premium for merchants who stay (max +40 percent, none below dread 30).
func price_mult(sid: int, subject := SUBJECT) -> float:
	var dr := dread_felt(subject, sid)
	if dr < 30.0:
		return 1.0
	return 1.0 + clampf((dr - 30.0) / 70.0, 0.0, 1.0) * float(ladder_data().get("price_max", 0.4))


## Non-devotee vendors refuse at dread >= 70. A fallback (fence, monastery) always exists, so the player is never locked out.
func vendor_refuses(sid: int, vendor: Dictionary = {}, subject := SUBJECT) -> bool:
	if bool(vendor.get("devotee", false)) or bool(vendor.get("fence", false)):
		return false
	return dread_felt(subject, sid) >= 70.0


func fallback_shop(_sid: int) -> bool:
	return true


## Compensation bill for damage (cracked glass, wrecked carts). Paid once.
func bill(subject: String, sid: int, damage_gold: int) -> int:
	if damage_gold <= 0:
		return 0
	var k := key(subject, sid)
	_bills[k] = int(_bills.get(k, 0)) + damage_gold
	return int(_bills[k])


func bill_due(subject: String, sid: int) -> int:
	return int(_bills.get(key(subject, sid), 0))


func pay_bill(subject: String, sid: int) -> Dictionary:
	var k := key(subject, sid)
	var due := int(_bills.get(k, 0))
	if due <= 0:
		return {"ok": false}
	_bills.erase(k)
	_gold -= due
	add(subject, sid, -15.0, 5.0, {"kingdom": _kingdom(sid)})
	stats["bills_paid"] = int(stats["bills_paid"]) + 1
	return {"ok": true, "paid": due}


## Signed gold for life.gd (negative = the player owes). Never touches the purse.
func take_pending_gold() -> int:
	var g := _gold
	_gold = 0
	return g


# ------------------------------------------------------------------ incident and ladder

## Which step the response reaches. m: {t1, t2, t3, t4 counts, sustained_s, damage, death, noble_killed, demonic_church}. dread 0..100.
static func step_for(m: Dictionary, dread_v: float, repeat4 := 0) -> int:
	var step := -1
	var t1 := int(m.get("t1", 0))
	var t2 := int(m.get("t2", 0))
	var t3 := int(m.get("t3", 0))
	var t4 := int(m.get("t4", 0))
	if t1 + t2 + t3 + t4 >= 1:
		step = 0
	if t2 + t3 + t4 >= 3 or t3 + t4 >= 1:
		step = 1
	if float(m.get("sustained_s", 0.0)) >= 10.0 or t4 >= 1 or dread_v >= 50.0:
		if t1 + t2 + t3 + t4 >= 1 or dread_v >= 50.0:
			step = 2
	if bool(m.get("damage", false)) or t4 >= 5:
		step = maxi(step, 3)
	if dread_v >= 70.0 or bool(m.get("death", false)) or bool(m.get("demonic_church", false)):
		step = maxi(step, 4)
	if dread_v >= 85.0 or bool(m.get("noble_killed", false)) or repeat4 >= 2:
		step = maxi(step, 5)
	return maxi(step, 0) if step >= 0 else -1


## Severity 0..1, monotonic in the fear peak and the number of T3+ observers.
static func severity(peak: float, t3plus: int, harm: float) -> float:
	return clampf(clampf(peak, 0.0, 1.0) * (0.5 + 0.1 * minf(float(t3plus), 5.0)) + clampf(harm, 0.0, 1.0) * 0.3, 0.0, 1.0)


func ladder(subject: String, sid: int) -> Dictionary:
	var l: Dictionary = _lad.get(key(subject, sid), {})
	if l.is_empty():
		return {"step": -1, "arrived": false, "eta_s": 0.0, "id": "none"}
	var steps: Array = ladder_data().get("steps", [])
	var st := int(l["step"])
	return {"step": st, "arrived": float(l["clock"]) >= float(l["arrive"]), "eta_s": maxf(float(l["arrive"]) - float(l["clock"]), 0.0),
		"id": String((steps[st] as Dictionary).get("id", "")) if st >= 0 and st < steps.size() else "none", "repeat4": int(l.get("s4", 0)),
		"who": String((steps[st] as Dictionary).get("who", "")) if st >= 0 and st < steps.size() else ""}


func _set_step(subject: String, sid: int, step: int, why: String) -> void:
	var k := key(subject, sid)
	var l: Dictionary = _lad.get(k, {"step": -1, "arrive": 0.0, "clock": 0.0, "s4": 0, "fav": 0})
	if step < 0:
		_lad.erase(k)
		return
	step = clampi(step, 0, 5)
	var steps: Array = ladder_data().get("steps", [])
	var dl: Array = (steps[step] as Dictionary).get("delay_s", [0, 15])
	var changed := step != int(l["step"])
	l["step"] = step
	if changed:
		l["clock"] = 0.0
		l["arrive"] = float(dl[0]) + _roll("arrive", k + str(step)) * (float(dl[1]) - float(dl[0]))
	if step == 4 and changed:
		l["s4"] = int(l.get("s4", 0)) + 1
	l["why"] = why
	_lad[k] = l
	_on_step(subject, sid, step)


func _on_step(subject: String, sid: int, step: int) -> void:
	var nm: Variant = _mod("news")
	if step >= 2 and nm != null:
		nm.post("aura_ladder", sid, "the watch moves against the one who frightens the town", float(step))
	if step == 5:
		var wi: Variant = _mod("war_intel")
		if wi != null and wi.has_method("envoy_arrive"):
			wi.envoy_arrive("k:" + _kingdom(sid), subject, "neutrality", "", {"sid": sid, "agenda": "terms"})


## A visible release or deed ends here. Returns the ladder step reached (-1 none). opts: {kingdom, quarter, duration_s, damage_gold, death,
## noble_killed, demonic, t1..t4}. Writes the ring, dread, the bill, the district shock, a court case and the news item.
func on_incident(subject: String, sid: int, quarter: String, peak: float, harm: float, witnesses: int, opts: Dictionary = {}) -> int:
	stats["incidents"] = int(stats["incidents"]) + 1
	var kingdom := _kingdom(sid, opts)
	var cul := culture_row(kingdom)
	var t3p := int(opts.get("t3", 0)) + int(opts.get("t4", 0))
	var sev := severity(peak, t3p, harm)
	_inc.append([_now(), sid, int(round(peak * 100.0)), int(round(harm * 100.0)), witnesses, 0])
	while _inc.size() > int(ladder_data().get("incident_ring", 64)):
		_inc.pop_front()
	if bool(cul.get("release_expected", false)):
		add(subject, sid, 0.0, sev * 6.0, {"kingdom": kingdom})   # a greeting, not a crime
		return -1
	add(subject, sid, 12.0 * sev, 0.0, {"kingdom": kingdom})
	if opts.has("witness_ids"):
		witness_memories(opts["witness_ids"], peak, "aura_fear")
	if opts.has("awe_ids"):
		witness_memories(opts["awe_ids"], peak * 0.6, "aura_awe")
	if sev >= 0.3:
		_followers_react(subject, sid, bool(opts.get("protect", false)))
	var dm: Variant = _mod("districts")
	if dm != null and quarter != "" and dm.has_quarter(sid, quarter):
		dm.on_crime(sid, quarter, sev)
	if int(opts.get("damage_gold", 0)) > 0:
		bill(subject, sid, int(opts["damage_gold"]))
	var k := key(subject, sid)
	var prev: Dictionary = _lad.get(k, {})
	var m := {"t1": int(opts.get("t1", 0)), "t2": int(opts.get("t2", 0)), "t3": int(opts.get("t3", 0)), "t4": int(opts.get("t4", 0)),
		"sustained_s": float(opts.get("duration_s", 0.0)), "damage": int(opts.get("damage_gold", 0)) > 0, "death": bool(opts.get("death", false)),
		"noble_killed": bool(opts.get("noble_killed", false)),
		"demonic_church": bool(opts.get("demonic", false)) and bool(cul.get("inquisitors", false))}
	var step := step_for(m, dread_felt(subject, sid), int(prev.get("s4", 0)))
	if step >= 3:
		_scout_news(subject, sid, kingdom)
	if step >= 4 or (sev >= 0.8 and step >= 3):
		_flee(subject, sid)
	if step >= 0:
		if prev.is_empty() or step > int(prev["step"]):
			_set_step(subject, sid, step, "incident")
		(_inc.back() as Array)[5] = step
		var cm: Variant = _mod("courts")
		if step >= 2 and cm != null and not bool(opts.get("no_case", false)):
			var cid: String = cm.file_case("public_terror", sid, {"id": "t:%d" % sid, "name": "the town"}, {"id": subject, "name": "the stranger"},
				{"culprit": subject, "kingdom": kingdom, "witnesses": []})
			if cid != "":
				_lad[k]["case"] = cid
	return step


func advance(subject: String, sid: int, seconds: float) -> void:
	var l: Dictionary = _lad.get(key(subject, sid), {})
	if not l.is_empty():
		l["clock"] = float(l["clock"]) + seconds


## Resolves a player option against the standing ladder step. ctx: {persuasion 0..1, rank 0..5, power 0..1, gold, honest 0..1 (officer),
## kingdom, quarter}. Deterministic. Returns {ok, option, before, after, outcome, gold, text}.
func resolve(subject: String, sid: int, option: String, ctx: Dictionary = {}) -> Dictionary:
	if not (option in OPTIONS):
		return {"ok": false, "reason": "unknown_option"}
	var k := key(subject, sid)
	var l: Dictionary = _lad.get(k, {})
	if l.is_empty():
		return {"ok": false, "reason": "no_ladder"}
	stats["options"] = int(stats["options"]) + 1
	var before := int(l["step"])
	var kingdom := _kingdom(sid, ctx)
	var cul := culture_row(kingdom)
	var power := clampf(float(ctx.get("power", 0.3)), 0.0, 1.0)
	var honest := clampf(float(ctx.get("honest", 0.5)), 0.0, 1.0)
	var dr := dread_felt(subject, sid)
	var aw := awe(subject, sid)
	var r := _roll(option, k + str(before) + str(int(ctx.get("n", 0))))
	var out := "none"
	var after := before
	var gold := 0
	match option:
		"suppress":
			after = maxi(before - 1, 0) if before <= 2 else before
			out = "calmed" if after < before else "unmoved"
			add(subject, sid, -2.0, 1.0, {"kingdom": kingdom})
		"talk":
			var score := clampf(float(ctx.get("persuasion", 0.3)) * 0.5 + aw / 200.0 + float(ctx.get("rank", 0)) / 10.0 - dr / 200.0, 0.0, 1.0) + (0.05 if bool(cul.get("licence", false)) else 0.0)
			if before >= 4:
				out = "refused"
			elif score + r * 0.2 >= 0.5:
				after = 0
				out = "dismissed"
			elif score + r * 0.2 >= 0.3:
				after = maxi(before - 1, 0)
				out = "fined"
				gold = -int(25 + 10 * before)
			else:
				after = before + 1
				out = "escorted_out_or_worse"
		"intimidate":
			if power >= 0.3 and before <= 2:
				after = maxi(before - 1, 0)
				out = "officer_backs_off"
				add(subject, sid, 8.0, -2.0, {"kingdom": kingdom})
				l["superior"] = true
			else:
				after = before + 1
				out = "defied"
				add(subject, sid, 5.0, -3.0, {"kingdom": kingdom})
		"bribe":
			var cost := int((40.0 + dr * 3.0) * float(before + 1))
			if honest > 0.7:
				after = before + 1
				out = "refused_and_recorded"
				var rep: Variant = _mod("reputation")
				if rep != null:
					rep.on_deed(subject, "bribed", sid, 1.0)
			elif int(ctx.get("gold", cost)) < cost:
				out = "too_poor"
			else:
				after = maxi(before - 2, 0) if before <= 3 else before
				out = "taken"
				gold = -cost
				var dm: Variant = _mod("districts")
				if dm != null:
					dm.on_corruption(sid, String(ctx.get("quarter", "other")), 0.03)
			l["cost"] = cost
		"surrender":
			if before <= 3:
				var cm: Variant = _mod("courts")
				var cid := String(l.get("case", ""))
				if cm != null and cid == "":
					cid = cm.file_case("public_terror", sid, {"id": "t:%d" % sid, "name": "the town"}, {"id": subject, "name": "the stranger"}, {"culprit": subject, "kingdom": kingdom})
				if cm != null and cid != "":
					cm.bring_to_court(cid)
					l["case"] = cid
				after = 0
				out = "hearing"
				gold = -int(30 + 15 * before)
				add(subject, sid, -4.0, 3.0, {"kingdom": kingdom})
			else:
				out = "detained"
		"flee":
			var chance := clampf(0.35 + power * 0.4 + float(ctx.get("speed", 0.0)) * 0.2 - float(before) * 0.08, 0.05, 0.95)
			if r < chance:
				out = "escaped"
				after = maxi(before, 2)
				add(subject, sid, 2.0, 0.0, {"kingdom": kingdom})
			else:
				out = "caught"
				after = before + 1
		"fight":
			out = "restrained_nonlethal"
			after = before if before >= 3 else 3
			add(subject, sid, 5.0, -2.0, {"kingdom": kingdom})
		"fight_lethal":
			out = "major_crime"
			after = maxi(before, 4)
			add(subject, sid, 30.0, -10.0, {"kingdom": kingdom})
		"appeal":
			if aw >= 40.0 and before >= 1:
				after = before - 1
				out = "patron_intervenes"
				l["fav"] = int(l.get("fav", 0)) + 1
			else:
				out = "no_patron"
	if gold != 0:
		_gold += gold
	l["opt"] = option
	if after != before:
		_lad[k] = l
		_set_step(subject, sid, after, option)
	return {"ok": true, "option": option, "before": before, "after": clampi(after, 0, 5), "outcome": out, "gold": gold, "culture": culture_row(kingdom).get("reads", "")}


func favours(subject: String, sid: int) -> int:
	return int((_lad.get(key(subject, sid), {}) as Dictionary).get("fav", 0))


# ------------------------------------------------------------------ knock-on hooks (AR-9, AR-10)

## Fear / awe memories for witnesses (psyche kinds aura_fear, aura_awe). Bounded: WITNESS_CAP per call, WITNESS_DAY_CAP per day. Severity scales with
## the peak felt (0..1). Returns the number written.
func witness_memories(ids: Array, peak: float, kind := "aura_fear") -> int:
	var ps: Variant = _mod("psyche")
	if ps == null or ids.is_empty():
		return 0
	if _psy_day != _now():
		_psy_day = _now()
		_psy_n = 0
	var n := 0
	for ch: Variant in ids:
		if n >= WITNESS_CAP or _psy_n >= WITNESS_DAY_CAP:
			break
		if ps.experience(String(ch), kind, clampf(peak, 0.0, 1.0), 1.0, ids.size(), _now()):
			n += 1
			_psy_n += 1
	stats["witnessed"] = int(stats["witnessed"]) + n
	return n


## Followers react by motive (awe, fear, pride, leaving). Never moves a follower or breaks a bond on its own (follower_will rules).
func _followers_react(subject: String, sid: int, protect := false) -> void:
	var fw: Variant = _mod("will")
	if fw != null and fw.has_method("on_aura_all"):
		fw.on_aura_all(awe(subject, sid), dread_felt(subject, sid), protect)


## A scout of the town's kingdom carries word of the power (once per 10 days per town).
func _scout_news(subject: String, sid: int, kingdom: String) -> void:
	var wi: Variant = _mod("war_intel")
	if wi == null or not wi.has_method("scout_power"):
		return
	if _now() - int(_scout_day.get(sid, -99)) < 10:
		return
	_scout_day[sid] = _now()
	var r: Dictionary = wi.scout_power("k:" + kingdom, "scout:%d" % sid, sid, subject)
	if bool(r.get("ok", false)):
		stats["scouted"] = int(stats["scouted"]) + 1


func _node_of(sid: int) -> String:
	return "s%d" % sid


func away(sid: int) -> int:
	return int((_away.get(sid, [0]) as Array)[0])


## Households flee a town after a severe event: a bounded share (FLEE_MAX) goes by road to the nearest other living place. One flight per town at a time.
func _flee(subject: String, sid: int) -> bool:
	if _away.has(sid) or dread_felt(subject, sid) < 60.0:
		return false
	var mig: Variant = _mod("migration")
	var civ: Variant = _mod("civilization")
	if mig == null or civ == null:
		return false
	var node := _node_of(sid)
	if not civ.has_place(node):
		return false
	var n := clampi(int(float(civ.population(node)) * FLEE_FRAC), 0, FLEE_MAX)
	if n < 3:
		return false
	var here: Vector2 = civ.pos_of(node)
	var dest := ""
	var bd := INF
	for other: String in civ.place_ids():
		if other == node or bool((civ.place(other) as Dictionary).get("ruin", false)):
			continue
		var d := here.distance_to(civ.pos_of(other))
		if d < bd:
			bd = d
			dest = other
	if dest == "":
		return false
	var w: Dictionary = mig.send_wave(node, dest, n, "refugees", "terror", "refugee", _now())
	if w.is_empty():
		return false
	_away[sid] = [int(w["n"]), dest, _now(), 0]
	stats["fled"] = int(stats["fled"]) + int(w["n"])
	return true


## Day tick: households come home once the town has been calm for FLEE_CALM_DAYS; after FLEE_GIVE_UP days they stay where they are.
func _chunk_return(subject: String) -> void:
	var mig: Variant = _mod("migration")
	for sid: int in _away.keys():
		var a: Array = _away[sid]
		if dread(subject, sid) < 20.0:
			a[3] = int(a[3]) + 1
		else:
			a[3] = 0
		if _now() - int(a[2]) >= FLEE_GIVE_UP:
			_away.erase(sid)
		elif int(a[3]) >= FLEE_CALM_DAYS:
			if mig != null:
				var w: Dictionary = mig.send_wave(String(a[1]), _node_of(sid), int(a[0]), "settlers", "coming home", "native", _now())
				if not w.is_empty():
					stats["returned"] = int(stats["returned"]) + int(w["n"])
			_away.erase(sid)


# ------------------------------------------------------------------ ticks (chunked)

func tick_day_chunks(day: int, ctx: Dictionary) -> Array:
	return [func() -> Array: return _chunk_decay(day), func() -> Array: return _chunk_shock(day, ctx)]


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


func _chunk_decay(day: int) -> Array:
	_day = maxi(_day, day)
	for k: String in _ax.keys():
		var r: Array = _ax[k]
		var sub := k.get_slice("#", 0)
		var sid := int(k.get_slice("#", 1))
		var dr := dread(sub, sid)
		var aw := awe(sub, sid)
		if dr < 0.5 and aw < 0.5:
			_ax.erase(k)
			_lad.erase(k)
			continue
		r[0] = dr
		r[1] = aw
		r[2] = _day
		r[4] = int(r[4]) + 1 if dr >= 60.0 else 0
	_chunk_return(SUBJECT)
	# old ladders cool down: a step that has arrived and is not refreshed drops one step per day without new dread
	for k: String in _lad.keys():
		var l: Dictionary = _lad[k]
		var sub := k.get_slice("#", 0)
		var sid := int(k.get_slice("#", 1))
		if dread(sub, sid) < 30.0 and int(l["step"]) <= 3:
			_lad.erase(k)
	return []


## Daily district shock for towns with active dread (cap 16): prosperity down, unemployment and tension up; migration after 14 days.
func _chunk_shock(_day_n: int, _ctx: Dictionary) -> Array:
	var dm: Variant = _mod("districts")
	if dm == null:
		return []
	var n := 0
	for k: String in _ax:
		var sub := k.get_slice("#", 0)
		var sid := int(k.get_slice("#", 1))
		var dr := dread(sub, sid)
		if dr < 30.0:
			continue
		if n >= int(ladder_data().get("town_cap", 16)):
			break
		n += 1
		var f := clampf(dr / 100.0, 0.0, 1.0)
		for q: String in dm.quarters_of(sid):
			dm._nudge(sid, q, DV.F_PROS, -0.004 * f)
			dm._nudge(sid, q, DV.F_UNEMP, 0.003 * f)
			dm._nudge(sid, q, DV.F_TENS, 0.004 * f)
			if int((_ax[k] as Array)[4]) == 14:
				dm.migrants(sid, q, -10)
	return []


func catch_up(days: int, _ctx: Dictionary) -> Array:
	if days <= 0:
		return []
	_day = maxi(_day, PD.today())
	return _chunk_decay(_day)


# ------------------------------------------------------------------ save (compact)

func serialize() -> Dictionary:
	var ax := {}
	for k: String in _ax:
		var r: Array = _ax[k]
		ax[k] = [int(round(float(r[0]) * 10.0)), int(round(float(r[1]) * 10.0)), int(r[2]), int(r[3]), int(r[4])]
	var lad := {}
	for k: String in _lad:
		var l: Dictionary = _lad[k]
		lad[k] = [int(l["step"]), int(round(float(l["arrive"]))), int(round(float(l["clock"]))), int(l.get("s4", 0)), int(l.get("fav", 0)), String(l.get("case", ""))]
	return {"ax": ax, "lad": lad, "inc": _inc.duplicate(true), "lg": _legends.duplicate(true), "dd": _deeds.duplicate(), "bl": _bills.duplicate(), "g": _gold, "d": _day, "aw": _away.duplicate(true), "sd": _scout_day.duplicate()}


func deserialize(d: Dictionary) -> void:
	_ax = {}
	for k: String in d.get("ax", {}):
		var r: Array = d["ax"][k]
		_ax[k] = [float(r[0]) / 10.0, float(r[1]) / 10.0, int(r[2]), int(r[3]), int(r[4])]
	_lad = {}
	for k: String in d.get("lad", {}):
		var r: Array = d["lad"][k]
		var e := {"step": int(r[0]), "arrive": float(r[1]), "clock": float(r[2]), "s4": int(r[3]), "fav": int(r[4])}
		if String(r[5]) != "":
			e["case"] = String(r[5])
		_lad[k] = e
	_inc = []
	for row in d.get("inc", []):
		_inc.append([int(row[0]), int(row[1]), int(row[2]), int(row[3]), int(row[4]), int(row[5])])
	_legends = []
	for l in d.get("lg", []):
		_legends.append({"id": String(l["id"]), "subject": String(l["subject"]), "deed": String(l["deed"]), "day": int(l["day"]), "sid": int(l["sid"])})
	_deeds = {}
	for k: String in d.get("dd", {}):
		_deeds[k] = int(d["dd"][k])
	_bills = {}
	for k: String in d.get("bl", {}):
		_bills[k] = int(d["bl"][k])
	_gold = int(d.get("g", 0))
	_day = int(d.get("d", 0))
	_away = {}
	for k in d.get("aw", {}):
		var a: Array = d["aw"][k]
		_away[int(k)] = [int(a[0]), String(a[1]), int(a[2]), int(a[3])]
	_scout_day = {}
	for k in d.get("sd", {}):
		_scout_day[int(k)] = int(d["sd"][k])
