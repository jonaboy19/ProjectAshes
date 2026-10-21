extends "res://scripts/realm/realm_module.gd"
## Secrets (NI-8, docs/design/NPC_INTELLIGENCE_MAP.md): what a character hides - an affair, a debt, a crime, a shame, a hidden agenda - kept as one
## packed int each (kind, severity, state, day, a tag for the other party). Most of them are never stored: a character's starting secrets are a pure
## function of (world seed, id), so only a secret that CHANGED (leaked, learned, exposed, spent) or was BORN from play (a crime committed) is saved.
## Who-knows-what lives in courts.gd's ledger (one store; the blackmail there reads it). Worst case about 80 B a character with an override, a few KB at 1,000 characters. A hidden plan (plans.json "hidden") shows up as an agenda.
##
## Discovery: `investigate(by, subject, skill, gold)` (a rumoured secret is easier to confirm), and a weekly sample of characters whose hidden secrets
## leak into the town as a rumour (rumours.gd). Leverage: `secrets_of(id)` is the hook the courts read, `knows(by, subject)` says who holds what,
## `leverage(by, subject)` the best usable one and `use(by, subject, slot, "blackmail" | "expose")` spends it. Gold is never moved here: a blackmail
## answers with the demand and the caller (courts, a quest) settles it through the ledger.
##
## Cost: one scan of the new event tail a day, six characters sampled a week. Everything else is on demand.

const Events := preload("res://scripts/realm/events.gd")

const KINDS := ["affair", "debt", "crime", "agenda", "shame"]
const STATES := ["hidden", "rumoured", "exposed", "leveraged"]
const S_HIDDEN := 0
const S_RUMOURED := 1
const S_EXPOSED := 2
const S_LEVERAGED := 3
const AGENDA_SLOT := 7              # the virtual slot of a hidden plan
const SECRET_MAX := 3
const OVERRIDE_MAX := 320
const BLACKMAIL_COOLDOWN := 30
const SAMPLE_PER_WEEK := 6
const LEAKS_PER_WEEK := 3
const NEW_PER_DAY := 4
const START_CHANCE := 0.3

var _o: Dictionary = {}            # ch -> PackedInt32Array (every secret of a character whose list changed)
var _local: Array = []             # the same rows as courts' ledger, kept only when there is no courts module (tools); otherwise courts.gd is the one store
var _last_ev := 0
var stats := {"born": 0, "leaked": 0, "found": 0, "blackmail": 0, "exposed": 0}


func _now() -> int:
	return maxi(WorldSim.day if WorldSim != null else 0, 0)


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


static func pack(kind: int, sev: int, state: int, day: int, tag: int) -> int:
	return (kind & 7) | ((clampi(sev, 1, 15) & 15) << 3) | ((state & 3) << 7) | ((day & 65535) << 9) | ((tag & 63) << 25)


static func kind_of(v: int) -> int:
	return v & 7


static func severity_of(v: int) -> int:
	return (v >> 3) & 15


static func state_of(v: int) -> int:
	return (v >> 7) & 3


static func day_of(v: int) -> int:
	return (v >> 9) & 65535


static func tag_of(v: int) -> int:
	return (v >> 25) & 63


static func _with_state(v: int, st: int) -> int:
	return (v & ~(3 << 7)) | ((st & 3) << 7)


## The secrets a character starts with: a pure function of the world seed and its id.
func _derive(ch: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var h := absi(hash([WorldSim.SEED, "sec", ch]))
	if float(h % 1000) / 1000.0 >= START_CHANCE:
		return out
	var n := 1 + (1 if (h / 1000) % 5 == 0 else 0)
	for i in n:
		var hi := absi(hash([WorldSim.SEED, "sec", ch, i]))
		out.append(pack(hi % 5 if hi % 5 != 3 else 4, 3 + (hi / 7) % 10, S_HIDDEN, 0, (hi / 131) % 64))
	return out


func _list(ch: String) -> PackedInt32Array:
	if _o.has(ch):
		return _o[ch]
	return _derive(ch)


func _store(ch: String, lst: PackedInt32Array) -> void:
	if not _o.has(ch) and _o.size() >= OVERRIDE_MAX:
		var k: Variant = _o.keys()[0]                       # the oldest override gives way (insertion order)
		_o.erase(k)
	_o[ch] = lst


## Everything `id` hides, as rows {slot, kind, severity, state, tag, known (anyone else holds it), value (what it is worth as leverage, gold)}.
## The hook for the courts' blackmail. A hidden plan adds an agenda row (slot 7). Unknown ids have none.
func secrets_of(id: String) -> Array:
	var out: Array = []
	if id == "":
		return out
	var lst := _list(id)
	for i in lst.size():
		out.append(_row(id, i, lst[i]))
	var mn: Variant = _mod("minds")
	if mn != null and mn.has_method("plan_of"):
		var pl: Dictionary = mn.plan_of(id)
		if not pl.is_empty() and bool(pl.get("hidden", false)):
			out.append(_row(id, AGENDA_SLOT, pack(3, 5 + mini(5, int(pl["commit"]) / 50), S_HIDDEN, int(pl["born"]), 0)))
	return out


func _row(id: String, slot: int, v: int) -> Dictionary:
	var sev := severity_of(v)
	return {"slot": slot, "kind": KINDS[mini(kind_of(v), KINDS.size() - 1)], "severity": sev, "state": STATES[state_of(v)], "tag": tag_of(v),
		"known": not known_by(id).is_empty(), "value": sev * 25}


func count_of(id: String) -> int:
	return secrets_of(id).size()


func _value(id: String, slot: int) -> int:
	if slot == AGENDA_SLOT:
		for r: Dictionary in secrets_of(id):
			if int(r["slot"]) == AGENDA_SLOT:
				return pack(3, int(r["severity"]), S_HIDDEN, 0, 0)
		return 0
	var lst := _list(id)
	return lst[slot] if slot >= 0 and slot < lst.size() else 0


## A character takes on a new secret (a crime it got away with, a debt it hides). Returns its slot or -1 when it already carries the most.
func add(ch: String, kind: String, severity: int, day := -1, tag := 0) -> int:
	var ki := KINDS.find(kind)
	var lst := _list(ch).duplicate()
	if ki < 0 or lst.size() >= SECRET_MAX:
		return -1
	lst.append(pack(ki, severity, S_HIDDEN, _now() if day < 0 else day, tag))
	_store(ch, lst)
	stats["born"] = int(stats["born"]) + 1
	return lst.size() - 1


## The knowledge ledger: courts.gd's `_secrets` rows {holder, about, text, sev, day, used, src, until}; a row found here has src "slot:N".
func _ledger() -> Array:
	var ct: Variant = _mod("courts")
	return ct.secrets_ledger() if ct != null else _local


static func _slot_of(row: Dictionary) -> int:
	var src := String(row.get("src", ""))
	return int(src.substr(5)) if src.begins_with("slot:") else -2


func known_by(subject: String) -> Array:
	var out: Array = []
	for k: Dictionary in _ledger():
		if String(k["about"]) == subject and not out.has(String(k["holder"])):
			out.append(String(k["holder"]))
	return out


## Does `by` hold a secret of `subject` (`slot` -1: any, including what a court case taught it)?
func knows(by: String, subject: String, slot := -1) -> bool:
	for k: Dictionary in _ledger():
		if String(k["holder"]) == by and String(k["about"]) == subject and (slot < 0 or _slot_of(k) == slot):
			return true
	return false


## `by` looks into `subject`'s affairs. The best hidden or rumoured secret `by` does not yet hold is the one at stake; the chance grows with skill, gold
## spent and with the story having already leaked. Same day, same answer. Returns {ok, found, slot, kind, severity, reason}.
func investigate(by: String, subject: String, skill := 0.5, gold := 0) -> Dictionary:
	var best := -1
	var bv := 0
	var sl: Array = secrets_of(subject)
	for r: Dictionary in sl:
		var sl_i := int(r["slot"])
		if String(r["state"]) == "exposed" or knows(by, subject, sl_i):
			continue
		var score := int(r["severity"]) + (6 if String(r["state"]) == "rumoured" else 0)
		if score > bv:
			bv = score
			best = sl_i
	if best < 0:
		return {"ok": true, "found": false, "slot": -1, "kind": "", "severity": 0, "reason": "Nothing to find."}
	var om: Variant = _mod("organizations")
	if gold > 0 and om != null and not om.pay(by, gold):
		return {"ok": false, "found": false, "slot": -1, "kind": "", "severity": 0, "reason": "Digging costs gold."}
	var v := _value(subject, best)
	var chance := clampf(0.15 + 0.5 * skill + float(gold) / 400.0 + (0.25 if state_of(v) == S_RUMOURED else 0.0), 0.05, 0.95)
	var roll := float(absi(hash([WorldSim.SEED, "sinv", subject, by, _now(), best])) % 1000) / 1000.0
	if roll > chance:
		return {"ok": true, "found": false, "slot": best, "kind": "", "severity": 0, "reason": "Nothing certain comes of it."}
	var ct: Variant = _mod("courts")
	if ct != null:
		ct.learn_secret(by, subject, KINDS[mini(kind_of(v), KINDS.size() - 1)], float(severity_of(v)) / 15.0, "slot:%d" % best)
	else:
		_local.append({"holder": by, "about": subject, "text": "", "sev": float(severity_of(v)) / 15.0, "day": _now(), "used": 0, "src": "slot:%d" % best})
	stats["found"] = int(stats["found"]) + 1
	return {"ok": true, "found": true, "slot": best, "kind": KINDS[mini(kind_of(v), KINDS.size() - 1)], "severity": severity_of(v), "reason": ""}


## The best secret of `subject` that `by` holds and may still use: {ok, slot, kind, severity, demand (gold), power 0..1 (how hard it presses)}.
func leverage(by: String, subject: String) -> Dictionary:
	var best := {}
	for k: Dictionary in _ledger():
		if String(k["holder"]) != by or String(k["about"]) != subject or _slot_of(k) < 0 or int(k.get("until", 0)) > _now():
			continue
		var v := _value(subject, _slot_of(k))
		if v == 0 or state_of(v) == S_EXPOSED:
			continue
		var sev := severity_of(v)
		if best.is_empty() or sev > int(best["severity"]):
			best = {"ok": true, "slot": _slot_of(k), "kind": KINDS[mini(kind_of(v), KINDS.size() - 1)], "severity": sev, "demand": sev * 25, "power": snappedf(float(sev) / 15.0, 0.01)}
	return best if not best.is_empty() else {"ok": false, "slot": -1, "kind": "", "severity": 0, "demand": 0, "power": 0.0}


func _set_state(subject: String, slot: int, st: int) -> void:
	if slot == AGENDA_SLOT:
		return
	var lst := _list(subject).duplicate()
	if slot >= 0 and slot < lst.size():
		lst[slot] = _with_state(lst[slot], st)
		_store(subject, lst)


## Spends a held secret. "blackmail": the subject is frightened (mood and a threat in bonds), the answer carries the demand and the secret may not be
## pressed again for BLACKMAIL_COOLDOWN days. "expose": the secret becomes a story in the subject's town (rumours.gd), a crime-like event is logged and
## the subject takes the blow. Returns {ok, gold (demand), reason}.
func use(by: String, subject: String, slot: int, how: String) -> Dictionary:
	var row := {}
	for k: Dictionary in _ledger():
		if String(k["holder"]) == by and String(k["about"]) == subject and _slot_of(k) == slot:
			row = k
			break
	if row.is_empty():
		return {"ok": false, "gold": 0, "reason": "Nothing is known of that."}
	var v := _value(subject, slot)
	if v == 0 or state_of(v) == S_EXPOSED:
		return {"ok": false, "gold": 0, "reason": "It is no longer a secret."}
	var sev := severity_of(v)
	var mn: Variant = _mod("minds")
	var sid: int = int(mn.town_of(subject)) if mn != null and mn.is_mind(subject) else -1
	var ps: Variant = _mod("psyche")
	if how == "blackmail":
		if int(row.get("until", 0)) > _now():
			return {"ok": false, "gold": 0, "reason": "Too soon to press again."}
		row["until"] = _now() + BLACKMAIL_COOLDOWN
		row["used"] = int(row["used"]) + 1
		_set_state(subject, slot, S_LEVERAGED)
		if ps != null:
			ps.experience(subject, "crime", float(sev) / 15.0 * 0.6, 1.0, 1)
		var bo: Variant = _mod("bonds")
		if bo != null:
			bo.event("threat", by, subject, _now(), float(sev) / 8.0)
		stats["blackmail"] = int(stats["blackmail"]) + 1
		return {"ok": true, "gold": sev * 25, "reason": ""}
	if how == "expose":
		_set_state(subject, slot, S_EXPOSED)
		var rm: Variant = _mod("rumours")
		if rm != null and sid >= 0:
			rm.say("crime", subject, sid, -float(sev) * 5.0, {"origin": "witness", "by": by})
		Events.log_to(hub, "crime", "ss:%d" % sid if sid >= 0 else "", [subject, by], "secret_exposed", "A secret comes out", clampi(sev / 2, 2, 7))
		if ps != null:
			ps.experience(subject, "crime", float(sev) / 15.0, 1.0, 6)
		stats["exposed"] = int(stats["exposed"]) + 1
		return {"ok": true, "gold": 0, "reason": ""}
	return {"ok": false, "gold": 0, "reason": "Unknown use."}


# ------------------------------------------------------------------ ticks

func tick_day(day: int, _ctx: Dictionary) -> Array:
	var ev: Variant = _mod("events")
	var mn: Variant = _mod("minds")
	if ev == null or mn == null:
		return []
	var made := 0
	for r: Dictionary in ev.after(_last_ev):
		_last_ev = maxi(_last_ev, int(r["n"]))
		if String(r["kind"]) != "crime" or int(r["weight"]) < 2 or made >= NEW_PER_DAY:
			continue
		var acts: Array = r["actors"]
		if not acts.is_empty() and mn.is_mind(String(acts[0])):
			var ch := String(acts[0])
			var has := false
			for s: Dictionary in secrets_of(ch):
				has = has or String(s["kind"]) == "crime"
			if not has and add(ch, "crime", 3 + int(r["weight"]), day) >= 0:
				made += 1
	return []


func tick_week(week: int, _ctx: Dictionary) -> Array:
	var mn: Variant = _mod("minds")
	var rm: Variant = _mod("rumours")
	if mn == null or rm == null:
		return []
	var ids: Array = mn.ids()
	if ids.is_empty():
		return []
	var leaks := 0
	for i in SAMPLE_PER_WEEK:
		var ch: String = ids[absi(hash([WorldSim.SEED, "sleak", week, i])) % ids.size()]
		for s: Dictionary in secrets_of(ch):
			if String(s["state"]) != "hidden" or int(s["slot"]) == AGENDA_SLOT or leaks >= LEAKS_PER_WEEK:
				continue
			if float(absi(hash([WorldSim.SEED, "sleak2", week, ch, s["slot"]])) % 1000) / 1000.0 < 0.04 * float(s["severity"]) / 5.0:
				_set_state(ch, int(s["slot"]), S_RUMOURED)
				rm.say("crime", ch, int(mn.town_of(ch)), -float(s["severity"]) * 3.0, {"origin": "gossip"})
				stats["leaked"] = int(stats["leaked"]) + 1
				leaks += 1
	return []


func drop_character(ch: String) -> void:
	_o.erase(ch)
	_local = _local.filter(func(k: Dictionary) -> bool: return String(k["holder"]) != ch and String(k["about"]) != ch)


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	var o: Dictionary = {}
	for ch: Variant in _o:
		o[ch] = Array(_o[ch])
	return {"o": o, "k": _local.duplicate(true), "le": _last_ev, "st": stats.duplicate()}


func deserialize(d: Dictionary) -> void:
	_o = {}
	_local = []
	var o: Dictionary = d.get("o", {})
	for ch: Variant in o:
		var p := PackedInt32Array()
		for v: Variant in o[ch]:
			p.append(int(v))
		_o[String(ch)] = p
	for k: Variant in d.get("k", []):
		if k is Dictionary:
			_local.append((k as Dictionary).duplicate())
	_last_ev = int(d.get("le", 0))
	var st: Dictionary = d.get("st", {})
	for k: String in stats:
		stats[k] = int(st.get(k, stats[k]))
