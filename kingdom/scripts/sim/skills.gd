extends RefCounted
## Skills, techniques and cultivation: the player's martial arts, elemental
## magic, ninja and samurai arts, command and life skills. Everything is data in
## data/skills/*.json (one file per tree, listed in index.json, plus
## realms.json and manuals.json); add a technique or a tree without code.
##
## Pure data and rules (no nodes), deterministic (own seeded RNG, serialized).
##   - trees:      id -> {id, name, category, element, color, desc, sects, techniques: [ids]}
##   - techniques: id -> normalised definition (see _normalise for every field)
##   - learning:   technique points (earned by level, sect membership, earned
##                 titles, realm breakthroughs and manuals), prerequisites
##                 (`requires`) and gates (`needs`: level, realm, sect, title,
##                 flag, manual). Hidden techniques stay invisible until their
##                 gates are met (hidden triggers set "ability:<id>" flags).
##   - loadout:    ACTIVE_SLOTS active techniques plus passive_slots() passives.
##   - casting:    cost (stamina, qi or magicules), cooldown, damage scaled by
##                 rank, realm and equipped passives. Qi is pooled here; the
##                 caller pays stamina and magicules.
##   - cultivation: donghua realms (Mortal Body -> Qi Condensation ->
##                 Foundation Establishment -> Core Formation -> ...), each with
##                 minor stages; the peak stage is a bottleneck that needs a
##                 breakthrough (can fail: qi deviation).
##
## Wiring (Life owns one; see the hook lines in the skills report):
##   var skills := preload("res://scripts/sim/skills.gd").new()
##   skills.sync_progress(skills.ctx_from_life(Life))   # hourly: credit new points
##   Life.snapshot()["skills"] = skills.serialize()
##
## GodotGAS (addons/GodotGAS) was considered: its abilities are Node/Resource
## components built in the editor, which does not suit JSON-defined trees or a
## headless RefCounted model, so this is plain GDScript.

signal learned(tech: Dictionary, rank: int)
signal loadout_changed
signal points_changed(points: int)
signal stage_advanced(realm: int, stage: int)
## {success, realm, name, text, damage, magicule_growth}
signal breakthrough(result: Dictionary)

const DATA_DIR := "res://data/skills/"
const ACTIVE_SLOTS := 4
const BASE_PASSIVE_SLOTS := 2
const MAX_PASSIVE_SLOTS := 6
const RESOURCES := ["stamina", "qi", "magicules"]
## Hand seals (Naruto-style) for high-tier techniques: a technique's "seals"
## array is the sequence tapped on the seal pad before it fires.
const SEALS := ["rat", "tiger", "dragon", "snake", "bird", "boar"]
## Damage bonus when the seal sequence is completed.
const SEAL_BONUS := 0.15
const SHAPES := ["melee", "projectile", "aoe", "target_aoe", "cone", "chain", "dash", "blink", "buff", "utility"]
## Per rank above 1: damage +25 %, cooldown -10 %.
const RANK_DAMAGE := 0.25
const RANK_COOLDOWN := 0.1
## Points credited once per source.
const SECT_POINTS := 2
const TITLE_POINTS := 1
const BREAKTHROUGH_POINTS := 2
## Every level after the first gives a point; every fifth level one more.
const BONUS_EVERY := 5
## Failed breakthroughs keep this share of the stage's cultivation.
const DEVIATION_KEEP := 0.6
## Qi regeneration multiplier while meditating.
const MEDITATE_REGEN := 4.0
## Used when data/skills/realms.json is missing.
const FALLBACK_REALMS := [
	{"id": "mortal", "name": "Mortal Body", "stages": 1, "qi": 20, "regen": 0.4, "xp": 40, "power": 1.0, "chance": 1.0, "level": 1, "magicules": 0},
	{"id": "qi_condensation", "name": "Qi Condensation", "stages": 9, "qi": 60, "regen": 1.0, "xp": 60, "power": 1.15, "chance": 0.85, "level": 3, "magicules": 10},
]

var trees: Dictionary = {}
var tree_order: Array[String] = []
var techniques: Dictionary = {}
var realms: Array = []
var manual_defs: Dictionary = {}

## Learned techniques: id -> rank (1..max_rank).
var ranks: Dictionary = {}
## Active slots ("" = empty) and equipped passives.
var loadout: Array = []
var passives: Array = []
var points := 0
## Point sources already paid: "level" -> points so far, "sect:<id>", "title:<id>", "realm:<n>", "manual:<id>".
var credited: Dictionary = {}
## Manuals read: id -> day.
var manuals: Dictionary = {}
## Seconds left: id -> float.
var cooldowns: Dictionary = {}
## Timed self buffs from techniques: [{stats: {...}, left: seconds, id}]
var buffs: Array = []
var realm := 0
var stage := 0
var cult_xp := 0.0
var qi := 0.0
## Flat extra max qi (pills, rewards).
var qi_bonus := 0.0
var meditating := false

var _rng := RandomNumberGenerator.new()


func _init(load_data := true, seed_value := 8128) -> void:
	_rng.seed = seed_value
	loadout.resize(ACTIVE_SLOTS)
	loadout.fill("")
	if load_data:
		load_dir(DATA_DIR)
	if realms.is_empty():
		realms = FALLBACK_REALMS.duplicate(true)
	qi = qi_max()


# --- data ----------------------------------------------------------------------

func load_dir(dir: String) -> void:
	var index: Variant = _read_json(dir.path_join("index.json"))
	if not index is Dictionary:
		push_warning("skills: no index.json in " + dir)
		return
	for tid: String in index.get("trees", []):
		var t: Variant = _read_json(dir.path_join(tid + ".json"))
		if t is Dictionary:
			add_tree(t)
	var r: Variant = _read_json(dir.path_join(String(index.get("realms", "realms.json"))))
	if r is Dictionary and r.get("realms", []) is Array and not (r["realms"] as Array).is_empty():
		realms = (r["realms"] as Array).duplicate(true)
	var m: Variant = _read_json(dir.path_join(String(index.get("manuals", "manuals.json"))))
	if m is Dictionary:
		for md: Dictionary in m.get("manuals", []):
			manual_defs[String(md["id"])] = md.duplicate(true)


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Adds (or replaces) a tree and its techniques. The technique list may hold
## full definitions or ids of techniques already added.
func add_tree(def: Dictionary) -> void:
	var tid := String(def["id"])
	var t := def.duplicate(true)
	var ids: Array[String] = []
	for entry: Variant in def.get("techniques", []):
		if entry is Dictionary:
			var d := _normalise(entry, tid, t)
			techniques[d["id"]] = d
			ids.append(d["id"])
		else:
			ids.append(String(entry))
	t["techniques"] = ids
	t["color"] = String(def.get("color", "#f5b841"))
	if not trees.has(tid):
		tree_order.append(tid)
	trees[tid] = t


func _normalise(src: Dictionary, tid: String, t: Dictionary) -> Dictionary:
	var d := src.duplicate(true)
	var kind := String(d.get("kind", "active"))
	var defaults := {
		"kind": kind, "tree": tid, "desc": "", "tier": 1, "col": 0, "points": 1,
		"max_rank": 1, "requires": [], "needs": {}, "hidden": false,
		"resource": "stamina", "cost": 0.0, "cooldown": 1.0, "damage": 0, "shape": "melee",
		"range": 2.8, "radius": 0.0, "angle": 60.0, "speed": 20.0, "knockback": 1.5,
		"hits": 1, "hit_interval": 0.15, "hit_time": 0.25, "count": 1, "spread": 0.0,
		"chains": 0, "chain_range": 6.0, "pierce": false, "effect": {}, "passive": {},
		"anim": "Spell_Simple_Shoot", "anim_mode": "upper", "anim_speed": 1.0,
		"vfx": "", "element": String(t.get("element", "qi")), "seals": [],
	}
	for k: String in defaults:
		if not d.has(k):
			d[k] = defaults[k]
	# "anim" may be one clip or a preference list (newer clips first, a stock UAL
	# clip last); "anims" keeps the list, "anim" the first choice.
	var a: Variant = d["anim"]
	var anims: Array = []
	if a is Array:
		for c: Variant in a:
			anims.append(String(c))
	else:
		anims.append(String(a))
	if anims.is_empty():
		anims.append("Spell_Simple_Shoot")
	d["anims"] = anims
	d["anim"] = anims[0]
	for k: String in ["tier", "col", "points", "max_rank", "damage", "hits", "count", "chains"]:
		d[k] = int(d[k])
	for k: String in ["cost", "cooldown", "range", "radius", "angle", "speed", "knockback", "hit_interval",
			"hit_time", "spread", "chain_range", "anim_speed"]:
		d[k] = float(d[k])
	return d


## Data problems as readable strings (empty when the data is sound).
func validate() -> Array[String]:
	var errs: Array[String] = []
	for id: String in techniques:
		var d: Dictionary = techniques[id]
		for r: String in d["requires"]:
			if not techniques.has(r):
				errs.append("%s requires unknown %s" % [id, r])
		if d["kind"] == "active":
			if not d["resource"] in RESOURCES:
				errs.append("%s has unknown resource %s" % [id, d["resource"]])
			if not d["shape"] in SHAPES:
				errs.append("%s has unknown shape %s" % [id, d["shape"]])
			if float(d["cooldown"]) <= 0.0:
				errs.append("%s has no cooldown" % id)
			for seal: Variant in d["seals"]:
				if not String(seal) in SEALS:
					errs.append("%s uses unknown seal %s" % [id, seal])
		var n: Dictionary = d["needs"]
		if n.has("manual") and not manual_defs.has(String(n["manual"])):
			errs.append("%s needs unknown manual %s" % [id, n["manual"]])
		if int(n.get("realm", 0)) >= realms.size():
			errs.append("%s needs a realm that does not exist" % id)
	for mid: String in manual_defs:
		for tid: String in manual_defs[mid].get("teaches", []):
			if not techniques.has(tid):
				errs.append("manual %s teaches unknown %s" % [mid, tid])
	return errs


func get_def(id: String) -> Dictionary:
	return techniques.get(id, {})


func tree_of(id: String) -> Dictionary:
	return trees.get(String(get_def(id).get("tree", "")), {})


func color_of(id: String) -> Color:
	return Color.from_string(String(tree_of(id).get("color", "#f5b841")), Color("f5b841"))


# --- context -------------------------------------------------------------------

## The unlock context from the Life autoload (duck-typed, safe on nulls):
## {level, titles: {id: day}, flags: {flag: value}, sects: [org ids]}.
## Sect membership reads "sect:<id>", "member:<id>" and scouts' "recruited:<id>" flags.
static func ctx_from_life(life: Object) -> Dictionary:
	var ctx := {"level": 1, "titles": {}, "flags": {}, "sects": []}
	if life == null:
		return ctx
	if life.has_method("player_level"):
		ctx["level"] = int(life.call("player_level"))
	var t: Variant = life.get("titles")
	if t is Object and (t as Object).get("earned_ids") is Dictionary:
		ctx["titles"] = (t as Object).get("earned_ids")
	var lp: Variant = life.get("life_path")
	if lp is Object and (lp as Object).get("flags") is Dictionary:
		ctx["flags"] = (lp as Object).get("flags")
	ctx["sects"] = sects_from_flags(ctx["flags"])
	return ctx


static func sects_from_flags(flags: Dictionary) -> Array:
	var out := []
	for f: String in flags:
		if not _has(flags, f):
			continue
		for prefix: String in ["sect:", "member:", "recruited:"]:
			if f.begins_with(prefix):
				out.append(f.trim_prefix(prefix))
	return out


static func _has(set_like: Variant, key: String) -> bool:
	if set_like is Dictionary:
		var d: Dictionary = set_like
		if not d.has(key):
			return false
		var v: Variant = d[key]
		return v != null and not (v is bool and not v)     # titles map id -> day (0 counts)
	if set_like is Array:
		return (set_like as Array).has(key)
	return false


# --- technique points --------------------------------------------------------------

static func points_for_level(level: int) -> int:
	var l := maxi(level, 1)
	@warning_ignore("integer_division")
	return (l - 1) + l / BONUS_EVERY


## Credits points not yet paid for level, sect memberships and earned titles.
## Idempotent; call whenever any of those may have changed. Returns messages.
func sync_progress(ctx: Dictionary) -> Array[String]:
	var msgs: Array[String] = []
	var due := points_for_level(int(ctx.get("level", 1)))
	var paid := int(credited.get("level", 0))
	if due > paid:
		_add_points(due - paid)
		credited["level"] = due
		msgs.append("+%d technique point%s (level)." % [due - paid, "" if due - paid == 1 else "s"])
	for s: String in ctx.get("sects", []):
		if not credited.has("sect:" + s):
			credited["sect:" + s] = SECT_POINTS
			_add_points(SECT_POINTS)
			msgs.append("+%d technique points: your sect's teachings." % SECT_POINTS)
	var titles: Variant = ctx.get("titles", {})
	var tlist: Array = []
	if titles is Dictionary:
		tlist = (titles as Dictionary).keys()
	elif titles is Array:
		tlist = titles
	for tid: Variant in tlist:
		var key := "title:" + String(tid)
		if not credited.has(key):
			credited[key] = TITLE_POINTS
			_add_points(TITLE_POINTS)
			msgs.append("+%d technique point: a title's insight." % TITLE_POINTS)
	return msgs


func _add_points(n: int) -> void:
	points += n
	points_changed.emit(points)


## Extra points from quests or rewards (key makes it one-shot; "" = always).
func award_points(n: int, key := "") -> bool:
	if key != "":
		if credited.has(key):
			return false
		credited[key] = n
	_add_points(n)
	return true


# --- learning ----------------------------------------------------------------------

func rank_of(id: String) -> int:
	return int(ranks.get(id, 0))


func is_learned(id: String) -> bool:
	return rank_of(id) > 0


## Why a technique can or cannot be learned (or ranked up) now.
## -> {ok, reasons: [String], visible, maxed, cost}
func check(id: String, ctx: Dictionary) -> Dictionary:
	var d := get_def(id)
	if d.is_empty():
		return {"ok": false, "reasons": ["Unknown technique."], "visible": false, "maxed": false, "cost": 0}
	var reasons: Array[String] = []
	var gates_ok := true
	var r := rank_of(id)
	var maxed := r >= int(d["max_rank"])
	if maxed:
		reasons.append("Mastered.")
	for req: String in d["requires"]:
		if not is_learned(req):
			reasons.append("Learn %s first." % String(get_def(req).get("name", req)))
	var n: Dictionary = d["needs"]
	if n.has("level") and int(ctx.get("level", 1)) < int(n["level"]):
		reasons.append("Needs level %d." % int(n["level"]))
		gates_ok = false
	if n.has("realm") and realm < int(n["realm"]):
		reasons.append("Needs the %s realm." % realm_name(int(n["realm"])))
		gates_ok = false
	if n.has("sect"):
		var ok := false
		var sects: Array = ctx.get("sects", [])
		for s: String in n["sect"]:
			if sects.has(s):
				ok = true
		if not ok:
			reasons.append("Taught only by: %s." % ", ".join(PackedStringArray((n["sect"] as Array).map(_sect_name))))
			gates_ok = false
	if n.has("title") and not _has(ctx.get("titles", {}), String(n["title"])):
		reasons.append("Requires a title: %s." % String(n["title"]).capitalize())
		gates_ok = false
	if n.has("flag") and not _has(ctx.get("flags", {}), String(n["flag"])):
		reasons.append("Something must awaken in you first.")
		gates_ok = false
	if n.has("manual") and not manuals.has(String(n["manual"])):
		reasons.append("Find the manual: %s." % String(manual_defs.get(String(n["manual"]), {}).get("name", n["manual"])))
		gates_ok = false
	var cost := int(d["points"])
	if not maxed and points < cost:
		reasons.append("Needs %d technique point%s." % [cost, "" if cost == 1 else "s"])
	var visible := not bool(d["hidden"]) or gates_ok or r > 0
	return {"ok": reasons.is_empty(), "reasons": reasons, "visible": visible, "maxed": maxed, "cost": cost}


func _sect_name(s: Variant) -> String:
	return String(s).replace("_", " ").capitalize()


func can_learn(id: String, ctx: Dictionary) -> bool:
	return bool(check(id, ctx)["ok"])


func is_visible(id: String, ctx: Dictionary) -> bool:
	return bool(check(id, ctx)["visible"])


## Learn (or rank up) with points. -> {ok, text, rank}
func learn(id: String, ctx: Dictionary) -> Dictionary:
	var c := check(id, ctx)
	if not c["ok"]:
		return {"ok": false, "text": " ".join(PackedStringArray(c["reasons"])), "rank": rank_of(id)}
	points -= int(c["cost"])
	points_changed.emit(points)
	return _set_rank(id, rank_of(id) + 1)


## Learn for free, ignoring requirements (quest rewards, hidden triggers, manuals).
func grant(id: String) -> Dictionary:
	if not techniques.has(id):
		return {"ok": false, "text": "Unknown technique.", "rank": 0}
	if is_learned(id):
		return {"ok": false, "text": "Already known.", "rank": rank_of(id)}
	return _set_rank(id, 1)


func _set_rank(id: String, r: int) -> Dictionary:
	var d := get_def(id)
	ranks[id] = r
	learned.emit(d, r)
	if r == 1 and d["kind"] == "active" and loadout.has(""):
		equip(loadout.find(""), id)     # fill an empty slot automatically
	elif r == 1 and d["kind"] == "passive" and passives.size() < passive_slots():
		equip_passive(id)
	var text := "Learned %s." % d["name"] if r == 1 else "%s rank %d." % [d["name"], r]
	return {"ok": true, "text": text, "rank": r}


## A manual found in the world. -> {ok, text, unlocked: [technique names]}
func read_manual(manual_id: String, day := -1) -> Dictionary:
	var m: Dictionary = manual_defs.get(manual_id, {})
	if m.is_empty():
		return {"ok": false, "text": "The pages mean nothing to you.", "unlocked": []}
	if manuals.has(manual_id):
		return {"ok": false, "text": "You already know this manual by heart.", "unlocked": []}
	manuals[manual_id] = day
	var got: Array[String] = []
	var pts := int(m.get("points", 0))
	if pts > 0:
		award_points(pts, "manual:" + manual_id)
	for tid: String in m.get("teaches", []):
		if bool(m.get("grant", false)) and not is_learned(tid):
			grant(tid)
		got.append(String(get_def(tid).get("name", tid)))
	return {"ok": true, "text": "You study %s. (%s)" % [m.get("name", manual_id), ", ".join(PackedStringArray(got))],
		"unlocked": got}


# --- loadout -------------------------------------------------------------------

func passive_slots() -> int:
	@warning_ignore("integer_division")
	return mini(MAX_PASSIVE_SLOTS, BASE_PASSIVE_SLOTS + realm / 2)


## Put a learned active technique in a slot (swaps if it sits in another). "" clears.
func equip(slot: int, id: String) -> bool:
	if slot < 0 or slot >= ACTIVE_SLOTS:
		return false
	if id != "":
		if not is_learned(id) or get_def(id).get("kind", "") != "active":
			return false
		var old := loadout.find(id)
		if old >= 0:
			loadout[old] = loadout[slot]
	loadout[slot] = id
	loadout_changed.emit()
	return true


func unequip(slot: int) -> void:
	equip(slot, "")


func slot_of(id: String) -> int:
	return loadout.find(id)


func equip_passive(id: String) -> bool:
	if passives.has(id) or not is_learned(id) or get_def(id).get("kind", "") != "passive":
		return false
	if passives.size() >= passive_slots():
		return false
	passives.append(id)
	loadout_changed.emit()
	return true


func unequip_passive(id: String) -> void:
	if passives.has(id):
		passives.erase(id)
		loadout_changed.emit()


## Summed stats of equipped passives (times rank) and active buffs:
## {"sword_damage": 0.12, "max_qi": 0.1, "cooldown": -0.05, ...}
func effects() -> Dictionary:
	var out := {}
	for id: String in passives:
		var p: Dictionary = get_def(id).get("passive", {})
		for k: String in p:
			out[k] = float(out.get(k, 0.0)) + float(p[k]) * rank_of(id)
	for b: Dictionary in buffs:
		var s: Dictionary = b["stats"]
		for k: String in s:
			out[k] = float(out.get(k, 0.0)) + float(s[k])
	return out


func add_buff(stats: Dictionary, seconds: float, id := "") -> void:
	for b: Dictionary in buffs:
		if id != "" and b["id"] == id:
			b["left"] = seconds
			b["stats"] = stats.duplicate()
			return
	buffs.append({"stats": stats.duplicate(), "left": seconds, "id": id})


# --- casting -------------------------------------------------------------------

func cost_of(id: String) -> float:
	var d := get_def(id)
	var fx := effects()
	var k := 1.0 + float(fx.get(String(d.get("resource", "")) + "_cost", 0.0))
	return maxf(0.0, float(d.get("cost", 0.0)) * clampf(k, 0.3, 2.0))


func cooldown_of(id: String) -> float:
	var d := get_def(id)
	var r := maxi(rank_of(id), 1)
	var k := (1.0 - RANK_COOLDOWN * (r - 1)) * (1.0 + float(effects().get("cooldown", 0.0)))
	return maxf(0.2, float(d.get("cooldown", 1.0)) * clampf(k, 0.3, 2.0))


func damage_of(id: String) -> int:
	var d := get_def(id)
	var base := float(d.get("damage", 0))
	if base <= 0.0:
		return 0
	var r := maxi(rank_of(id), 1)
	var fx := effects()
	var bonus := float(fx.get(String(d.get("element", "")) + "_damage", 0.0))
	match String(d.get("tree", "")):
		"swordsmanship", "iaido":
			bonus += float(fx.get("sword_damage", 0.0))
		"fist_palm":
			bonus += float(fx.get("fist_damage", 0.0))
	var realm_k := 1.0
	if d["resource"] != "stamina" or d["tree"] in ["qi", "fist_palm", "swordsmanship", "iaido"]:
		realm_k = float(realm_info().get("power", 1.0))
	return maxi(1, int(round(base * (1.0 + RANK_DAMAGE * (r - 1)) * (1.0 + bonus) * realm_k)))


func cooldown_left(id: String) -> float:
	return float(cooldowns.get(id, 0.0))


## 0 = ready, 1 = just used.
func cooldown_fraction(id: String) -> float:
	var left := cooldown_left(id)
	return 0.0 if left <= 0.0 else clampf(left / cooldown_of(id), 0.0, 1.0)


## `pools`: what the caller can pay, {"stamina": float, "magicules": float}
## (qi is read from this object). -> {ok, reason}
func can_cast(id: String, pools := {}) -> Dictionary:
	var d := get_def(id)
	if d.is_empty() or not is_learned(id):
		return {"ok": false, "reason": "Not learned."}
	if d["kind"] != "active":
		return {"ok": false, "reason": "Passive."}
	if cooldown_left(id) > 0.0:
		return {"ok": false, "reason": "%.1fs" % cooldown_left(id)}
	var res := String(d["resource"])
	var have := qi if res == "qi" else float(pools.get(res, 0.0))
	var cost := cost_of(id)
	if have + 0.001 < cost:
		return {"ok": false, "reason": "Not enough %s." % res}
	return {"ok": true, "reason": ""}


## Starts the cooldown and pays qi. The caller pays stamina / magicules with
## the returned cost. -> {ok, reason, resource, cost, cooldown, damage, def}
func begin_cast(id: String, pools := {}, sealed := false) -> Dictionary:
	var c := can_cast(id, pools)
	if not c["ok"]:
		return c
	var d := get_def(id)
	var cost := cost_of(id)
	if d["resource"] == "qi":
		qi = maxf(0.0, qi - cost)
	var cd := cooldown_of(id)
	cooldowns[id] = cd
	var fx: Dictionary = d.get("effect", {})
	if fx.has("cultivate"):
		cultivate(float(fx["cultivate"]))
	if fx.has("qi"):
		restore_qi(float(fx["qi"]))
	var dmg := damage_of(id)
	if sealed and not (d["seals"] as Array).is_empty():
		dmg = int(round(dmg * (1.0 + SEAL_BONUS)))
	return {"ok": true, "reason": "", "resource": d["resource"], "cost": cost, "cooldown": cd,
		"damage": dmg, "def": d}


func needs_seals(id: String) -> bool:
	return not (get_def(id).get("seals", []) as Array).is_empty()


## A botched seal sequence: nothing is paid, but the technique rests briefly.
func fizzle(id: String, seconds := 2.0) -> void:
	cooldowns[id] = maxf(cooldown_left(id), seconds)


## Advance cooldowns, buffs and qi regeneration by `seconds` of game time.
func tick(seconds: float) -> void:
	if seconds <= 0.0:
		return
	for id: String in cooldowns.keys():
		var left := float(cooldowns[id]) - seconds
		if left <= 0.0:
			cooldowns.erase(id)
		else:
			cooldowns[id] = left
	for b: Dictionary in buffs.duplicate():
		b["left"] = float(b["left"]) - seconds
		if b["left"] <= 0.0:
			buffs.erase(b)
	qi = minf(qi_max(), qi + qi_regen() * seconds)


func restore_qi(amount: float) -> void:
	qi = clampf(qi + amount, 0.0, qi_max())


# --- cultivation -------------------------------------------------------------------

func realm_info(i := -1) -> Dictionary:
	var k := realm if i < 0 else i
	return realms[clampi(k, 0, realms.size() - 1)]


func realm_name(i := -1) -> String:
	return String(realm_info(i).get("name", "?"))


func stage_count(i := -1) -> int:
	return maxi(1, int(realm_info(i).get("stages", 1)))


## "Qi Condensation, layer 3" / "Foundation Establishment, late stage".
func realm_label() -> String:
	var n := stage_count()
	if n <= 1:
		return realm_name()
	if n == 9:
		return "%s, layer %d" % [realm_name(), stage + 1]
	var names := ["early", "middle", "late", "peak"]
	return "%s, %s stage" % [realm_name(), names[clampi(stage, 0, names.size() - 1)]]


func qi_max() -> float:
	var base := float(realm_info().get("qi", 20.0)) * (1.0 + 0.12 * stage) + qi_bonus
	return maxf(1.0, base * (1.0 + float(effects().get("max_qi", 0.0))))


func qi_regen() -> float:
	var r := float(realm_info().get("regen", 0.5)) * (1.0 + float(effects().get("qi_regen", 0.0)))
	return r * (MEDITATE_REGEN if meditating else 1.0)


func stage_xp_needed() -> float:
	return float(realm_info().get("xp", 50.0)) * (1.0 + 0.25 * stage)


func is_final_realm() -> bool:
	return realm >= realms.size() - 1


## The peak stage is full: only a breakthrough moves you on.
func at_bottleneck() -> bool:
	return stage >= stage_count() - 1 and cult_xp >= stage_xp_needed() and not is_final_realm()


## Gain cultivation (meditation, combat, pills). Minor stages advance on their
## own; progress stops at the bottleneck. Returns the number of stages gained.
func cultivate(amount: float) -> int:
	if amount <= 0.0:
		return 0
	cult_xp += amount
	var gained := 0
	while cult_xp >= stage_xp_needed() and stage < stage_count() - 1:
		cult_xp -= stage_xp_needed()
		stage += 1
		gained += 1
		stage_advanced.emit(realm, stage)
	if stage >= stage_count() - 1:
		cult_xp = minf(cult_xp, stage_xp_needed())
	return gained


func breakthrough_chance(bonus := 0.0) -> float:
	var next := realm_info(realm + 1)
	var c := float(next.get("chance", 0.5)) + bonus + float(effects().get("breakthrough", 0.0))
	return clampf(c, 0.05, 1.0)


## Try to break into the next realm. `level` (optional) must reach the next
## realm's "level"; `roll` in [0,1) overrides the RNG (tests, scripted events).
## -> {ok, success, realm, name, text, damage, magicule_growth}
func attempt_breakthrough(bonus := 0.0, level := -1, roll := -1.0) -> Dictionary:
	var res := {"ok": false, "success": false, "realm": realm, "name": realm_name(), "text": "", "damage": 0,
		"magicule_growth": 0.0}
	if not at_bottleneck():
		res["text"] = "Your cultivation is not yet at its peak." if not is_final_realm() else "There is nowhere higher to climb."
		return res
	var next := realm_info(realm + 1)
	if level >= 0 and level < int(next.get("level", 0)):
		res["text"] = "Your body cannot hold %s yet (level %d)." % [next.get("name", "?"), int(next.get("level", 0))]
		return res
	res["ok"] = true
	var r := roll if roll >= 0.0 else _rng.randf()
	if r < breakthrough_chance(bonus):
		realm += 1
		stage = 0
		cult_xp = 0.0
		qi = qi_max()
		award_points(BREAKTHROUGH_POINTS, "realm:%d" % realm)
		res["success"] = true
		res["realm"] = realm
		res["name"] = realm_name()
		res["magicule_growth"] = float(next.get("magicules", 0.0))
		res["text"] = "Breakthrough! You step into %s." % realm_name()
	else:
		cult_xp *= DEVIATION_KEEP
		qi = 0.0
		res["damage"] = 10 + 6 * realm
		res["text"] = "Qi deviation! Your meridians burn and the breakthrough fails."
	breakthrough.emit(res)
	return res


# --- save --------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {"version": 1, "ranks": ranks.duplicate(), "loadout": loadout.duplicate(), "passives": passives.duplicate(),
		"points": points, "credited": credited.duplicate(), "manuals": manuals.duplicate(),
		"cooldowns": cooldowns.duplicate(), "buffs": buffs.duplicate(true), "realm": realm, "stage": stage,
		"xp": cult_xp, "qi": qi, "qi_bonus": qi_bonus, "rng": str(_rng.state)}


func deserialize(d: Dictionary) -> void:
	ranks = {}
	for id: String in d.get("ranks", {}):
		if techniques.has(id) or techniques.is_empty():
			ranks[id] = int(d["ranks"][id])
	loadout.fill("")
	var lo: Array = d.get("loadout", [])
	for i in mini(lo.size(), ACTIVE_SLOTS):
		var id := String(lo[i]) if lo[i] != null else ""
		loadout[i] = id if id == "" or ranks.has(id) else ""
	passives = []
	for id: Variant in d.get("passives", []):
		if ranks.has(String(id)):
			passives.append(String(id))
	points = int(d.get("points", 0))
	credited = {}
	for k: String in d.get("credited", {}):
		credited[k] = int(d["credited"][k])
	manuals = {}
	for k: String in d.get("manuals", {}):
		manuals[k] = int(d["manuals"][k])
	cooldowns = {}
	for id: String in d.get("cooldowns", {}):
		cooldowns[id] = float(d["cooldowns"][id])
	buffs = (d.get("buffs", []) as Array).duplicate(true)
	realm = clampi(int(d.get("realm", 0)), 0, realms.size() - 1)
	stage = int(d.get("stage", 0))
	cult_xp = float(d.get("xp", 0.0))
	qi_bonus = float(d.get("qi_bonus", 0.0))
	qi = clampf(float(d.get("qi", qi_max())), 0.0, qi_max())
	if d.has("rng"):
		_rng.state = String(d["rng"]).to_int()
	loadout_changed.emit()
	points_changed.emit(points)
