extends "res://scripts/realm/realm_module.gd"
## Identity layer (LW-1.1, docs/design/LIVING_WORLD_SANDBOX.md Part C).
## Persistent ids "<prefix>:<n>" (n counts up per prefix and is never reused) plus a two-way alias registry that
## bridges every legacy id (WorldSim row, life_courses id, notable string, follower fid, settlement sid, recruitment
## contract, construction site, ...) to the persistent one. Nothing legacy is rewritten.
##
##   var reg = hub.mod("registry")
##   var ch = reg.ref("ws:1234")            # "ch:1" -- created on first reference, same answer afterwards
##   reg.lookup("ws:1234")                  # "ch:1" or "" (never creates)
##   reg.legacy_of("ch:1")                  # "ws:1234"
##   reg.upgrade_row(1234)                  # full Character record (traits, skills, loyalty, memory[12]), capped at 1000
##
## Legacy keys are "<kind>:<value>": ws (WorldSim row), lc (life_courses id), nt (notable), fo (follower fid),
## ss (settlement sid), cp (camp), rc (recruitment contract), cn (construction site), bg (build_kit grid),
## sn (society npc), pl (the player, "pl:player"), hd (construction holding), ho (household), og (organization), bz (business), tp, ar, tr. The kind picks the persistent prefix.
## Cost: every call is one or two dictionary operations. Save: one dict of counters, one of aliases, the upgraded
## characters (about 60 B each) and a 1-line history of retired ones.

## Persistent prefixes (Part C): character, household, organization, contract, property, building, business, settlement,
## territory, army, faction-relationship, event, travel party.
const PREFIXES := ["ch", "hh", "org", "ct", "pr", "bl", "bz", "st", "tr", "ar", "fr", "ev", "tp"]
## Legacy key kind -> persistent prefix.
const KIND_PREFIX := {
	"ws": "ch", "lc": "ch", "nt": "ch", "fo": "ch", "sn": "ch", "pl": "ch",
	"ss": "st", "cp": "st", "hd": "st",
	"rc": "ct", "cn": "bl", "bg": "pr",
	"ho": "hh", "og": "org", "bz": "bz", "tp": "tp", "ar": "ar", "tr": "tr",
}
const ALIAS_MAX := 6000
const CHAR_MAX := 1000
const HISTORY_MAX := 200
const MEMORY_MAX := 12
const TRAITS := ["brave", "careful", "greedy", "generous", "devout", "curious", "proud", "loyal", "sly", "stubborn",
	"patient", "hot-headed", "kind", "ambitious", "lazy", "honest"]

var _ids: Dictionary = {}        # prefix -> last number issued
var _fwd: Dictionary = {}        # legacy key -> persistent id
var _rev: Dictionary = {}        # persistent id -> first legacy key (derived, rebuilt on load)
var _chars: Dictionary = {}      # persistent id -> upgraded character record
var _hist: Array = []            # retired characters, one line each
var _day := 0


# ------------------------------------------------------------------ ids

## "ch:12" -> {"p": "ch", "n": 12}; {} when it is not a persistent id.
static func parse(pid: Variant) -> Dictionary:
	if not pid is String:
		return {}
	var s: String = pid
	var i := s.find(":")
	if i < 1 or i == s.length() - 1:
		return {}
	var p := s.substr(0, i)
	var rest := s.substr(i + 1)
	if not (p in PREFIXES) or not rest.is_valid_int():
		return {}
	return {"p": p, "n": int(rest)}


static func is_pid(x: Variant) -> bool:
	return not parse(x).is_empty()


static func prefix_of(pid: String) -> String:
	return String(parse(pid).get("p", ""))


## The next number for `prefix` (monotonic, never reused, even after a save and load). 0 for an unknown prefix.
func mint_n(prefix: String) -> int:
	if not (prefix in PREFIXES):
		return 0
	var n := int(_ids.get(prefix, 0)) + 1
	_ids[prefix] = n
	return n


func mint(prefix: String) -> String:
	var n := mint_n(prefix)
	return "%s:%d" % [prefix, n] if n > 0 else ""


func issued(prefix: String) -> int:
	return int(_ids.get(prefix, 0))


# ------------------------------------------------------------------ legacy keys

static func key_ws(row: int) -> String:
	return "ws:%d" % row


static func key_lc(pid: int) -> String:
	return "lc:%d" % pid


static func key_nt(nid: String) -> String:
	return "nt:" + nid


static func key_fo(fid: String) -> String:
	return "fo:" + fid


static func key_ss(sid: int) -> String:
	return "ss:%d" % sid


## Persistent prefix a legacy key maps to ("" when its kind is unknown).
static func legacy_prefix(legacy: String) -> String:
	var i := legacy.find(":")
	return String(KIND_PREFIX.get(legacy.substr(0, i), "")) if i > 0 else ""


## The persistent id of a legacy key, creating it on first reference. "" when the key is malformed, its kind is
## unknown, or the alias table is full (callers then keep the legacy key).
func ref(legacy: String) -> String:
	var got: String = _fwd.get(legacy, "")
	if got != "":
		return got
	var p := legacy_prefix(legacy)
	if p == "" or _fwd.size() >= ALIAS_MAX:
		return ""
	var pid := mint(p)
	_fwd[legacy] = pid
	if not _rev.has(pid):
		_rev[pid] = legacy
	return pid


## The persistent id of a legacy key, "" when it was never referenced. Never creates.
func lookup(legacy: String) -> String:
	return _fwd.get(legacy, "")


## Makes `legacy` another name of an existing persistent id (the same person known to two systems). False when the
## id is unknown or the legacy key already belongs to a different id.
func alias_to(legacy: String, pid: String) -> bool:
	if not is_pid(pid) or int(parse(pid)["n"]) > issued(prefix_of(pid)):
		return false
	var cur: String = _fwd.get(legacy, "")
	if cur != "":
		return cur == pid
	if _fwd.size() >= ALIAS_MAX:
		return false
	_fwd[legacy] = pid
	if not _rev.has(pid):
		_rev[pid] = legacy
	return true


## The first legacy key registered for a persistent id ("" when none).
func legacy_of(pid: String) -> String:
	return _rev.get(pid, "")


## A persistent id or a legacy key -> a persistent id; the input itself when nothing can be minted (alias table full,
## unknown kind), so event actors never get lost.
func resolve(x: Variant) -> String:
	var s := String(x)
	if is_pid(s):
		return s
	var r := ref(s)
	return r if r != "" else s


func alias_count() -> int:
	return _fwd.size()


# ------------------------------------------------------------------ characters

## A deterministic trait pair for a WorldSim row (no global RNG).
static func traits_for(row: int) -> Array:
	var h := absi(hash([WorldSim.SEED, "ch", row]))
	var a := h % TRAITS.size()
	var b := (h / TRAITS.size()) % TRAITS.size()
	if b == a:
		b = (b + 1) % TRAITS.size()
	return [TRAITS[a], TRAITS[b]]


## The full Character record of a persistent id ({} when it is only an alias).
func character(pid: String) -> Dictionary:
	return _chars.get(pid, {})


## The two hidden trait words of a character: the persona record's when it has one (it is the source of truth), else the stored pair.
func traits_of(pid: String) -> Array:
	var pe: Variant = hub.mod("persona") if hub != null else null
	if pe != null and pe.has(pid):
		return pe.traits(pid)
	return (_chars.get(pid, {}) as Dictionary).get("t", [])


func is_upgraded(pid: String) -> bool:
	return _chars.has(pid)


func upgraded_count() -> int:
	return _chars.size()


## Lazy upgrade of a WorldSim row to a full Character ("ch:n") when something references it (recruit, marry, accuse,
## hire, found). Idempotent and deterministic. Returns the id, or "" when the row is invalid or the cap is reached.
func upgrade_row(row: int, day := -1) -> String:
	if row < 0:
		return ""
	var pid := ref(key_ws(row))
	if pid == "":
		return ""
	return pid if _upgrade(pid, row, day) else ""


## Upgrades an existing id (a notable, a follower) that has no WorldSim row: traits start empty.
func upgrade(pid: String, day := -1) -> bool:
	if not is_pid(pid) or prefix_of(pid) != "ch":
		return false
	return _upgrade(pid, -1, day)


func _upgrade(pid: String, row: int, day: int) -> bool:
	if _chars.has(pid):
		return true
	if _chars.size() >= CHAR_MAX:
		return false
	_chars[pid] = {"r": row, "d": day if day >= 0 else _day, "t": traits_for(row) if row >= 0 else [], "s": {}, "l": {}, "m": []}
	return true


## Remembers something about an upgraded character (bounded to MEMORY_MAX, oldest dropped).
func remember(pid: String, line: String) -> bool:
	if not _chars.has(pid):
		return false
	var m: Array = _chars[pid]["m"]
	m.append(line.substr(0, 60))
	if m.size() > MEMORY_MAX:
		m.pop_front()
	return true


## A dead or idle character falls back to a one-line history; its id and aliases stay valid.
func retire(pid: String, line: String) -> bool:
	if not _chars.has(pid):
		return false
	_chars.erase(pid)
	_hist.append("%s %s" % [pid, line.substr(0, 80)])
	if _hist.size() > HISTORY_MAX:
		_hist = _hist.slice(_hist.size() - HISTORY_MAX)
	return true


func history() -> Array:
	return _hist.duplicate()


# ------------------------------------------------------------------ module hooks

func tick_day(day: int, _ctx: Dictionary) -> Array:
	_day = day
	return []


func serialize() -> Dictionary:
	return {"ids": _ids.duplicate(), "alias": _fwd.duplicate(), "chars": _chars.duplicate(true), "hist": _hist.duplicate(), "day": _day}


func deserialize(d: Dictionary) -> void:
	_ids = {}
	_fwd = {}
	_rev = {}
	_chars = {}
	_hist = []
	var ids: Variant = d.get("ids", {})
	if ids is Dictionary:
		for k: Variant in ids:
			if String(k) in PREFIXES:
				_ids[String(k)] = int(ids[k])
	var al: Variant = d.get("alias", {})
	if al is Dictionary:
		for k: Variant in al:
			var pid := String(al[k])
			if is_pid(pid):
				_fwd[String(k)] = pid
				if not _rev.has(pid):
					_rev[pid] = String(k)
				# A counter can never lag behind an id that exists (damaged or hand-edited saves).
				var pr: Dictionary = parse(pid)
				if int(pr["n"]) > int(_ids.get(pr["p"], 0)):
					_ids[pr["p"]] = int(pr["n"])
	var ch: Variant = d.get("chars", {})
	if ch is Dictionary:
		for k: Variant in ch:
			var c: Variant = ch[k]
			if c is Dictionary and is_pid(String(k)):
				var cd: Dictionary = c
				_chars[String(k)] = {"r": int(cd.get("r", -1)), "d": int(cd.get("d", 0)), "t": cd.get("t", []), "s": cd.get("s", {}),
					"l": cd.get("l", {}), "m": cd.get("m", [])}
	var h: Variant = d.get("hist", [])
	if h is Array:
		for s: Variant in h:
			_hist.append(String(s))
	_day = int(d.get("day", 0))
