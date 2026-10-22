extends "res://scripts/realm/realm_module.gd"
## MN-1..MN-5: the naming bond wired into the realm. Wraps the existing RANaming ledger (cost, risk, roster, Soul Name ritual) and adds
##   the bond record (form/mind/speech/ability tracks 0..4, depth, independence, ambition, byname), the naming rules the design adds
##   (exhaustion tiers, hollowing, refused names, forbidden species), tribe naming (Rite of the Many), recruiting a named or hired
##   monster as a follower row, and a small monster-will (orders refused, leaving). Everything is deterministic: rolls are hashes of
##   (seed_value, tag, day, id). Pure data; no nodes. Owner open questions are DATA FLAGS (data/world/mn_flags.json).
## Life owns the RANaming and RAMagicules instances; pass `naming` (or leave the private one for tests/tools).

const Data := preload("res://scripts/realm/mn_data.gd")
const Status := preload("res://scripts/realm/status.gd")

const BAND_STAGE := {"lesser": 1, "true": 2}
const REFUSE_COOLDOWN_DAYS := 7
const OUTRIGHT_RATIO := 2.5
const HOLLOW_RATIO := 1.5
const HOLLOW_FLOOR := 0.25
const TRIBE_FACTOR := 0.7
const TRIBE_MIN_TOTAL := 1.4
const TRIBE_NO_FEAST_LOYALTY := 55
const BOND_MAX := 16
const PRIDE := {"orc": 0.25, "lizardfolk": 0.2, "ogre": 0.15, "troll": 0.15, "wolf": 0.1, "bear": 0.15, "goblin": 0.1, "kobold": 0.05, "slime": 0.02, "spider": 0.1}
const CLASS_OCC := {"warrior": "mercenary", "scout": "scout", "mage": "priest", "guardian": "knight", "artisan": "smith", "hunter": "hunter", "healer": "healer"}
const ETHOS_TRAITS := {"oath": ["honorable", "loyal"], "clan": ["greedy", "cautious"], "pack": ["loyal", "brave"], "law": ["honorable", "curious"],
	"labour": ["stubborn", "loyal"], "calm": ["merciful", "curious"], "web": ["cautious", "curious"], "stone": ["stubborn", "brave"],
	"solitary": ["stubborn", "brave"], "dead": []}
const BYNAMES := ["Ember-Fang of the %s", "the Quiet Oath of %s", "Ash-Tread of %s", "Hearth-Warden of %s", "the Grey Counsel of %s", "Pass-Keeper of %s"]
const MORAL_ORDERS := ["burn_granary", "slaughter_prisoners", "poison_well", "betray_ally"]

var seed_value := 8128
var naming: RANaming = RANaming.new()
var _shared := false     # true once Life lends its own RANaming (then Life saves it, not this module)
var _bonds: Dictionary = {}          # "b1" -> record
var _next := 1
var _refused_until: Dictionary = {}  # target key -> day
var _debts: Array = []               # name-back obligations [{bond_key, namer, day}]
var hollowed_total := 0.0
var peak_pool := 0.0
var winded_until := -1
var collapse: Dictionary = {}        # {day, hours} of the latest collapse
var vassal_camps: Dictionary = {}    # camp id -> {master, leader, members [ids], day}
var rivals: Array = []               # defector bands [{id, leader_name, members, species, day, camp}]
var _day := 0


## Life calls this once so the bond module and the UI use one ledger.
func share_naming(n: RANaming) -> void:
	naming = n
	_shared = true


func _roll(tag: String, id: Variant, day := -1) -> float:
	return float(absi(hash([seed_value, tag, _day if day < 0 else day, str(id)])) % 10000) / 10000.0


# ------------------------------------------------------------------ rules (pure)

static func species_ceiling(species: String) -> Array:
	var row := Data.species_row(species)
	return (row.get("ceil", [2, 2, 2, 2]) as Array).duplicate()


static func band_cap(tier: int) -> int:
	var cap := 0
	for p: Array in Data.table("species_tracks").get("band_cap_by_tier", [[3, 2], [5, 3], [7, 4]]):
		if tier >= int(p[0]):
			cap = int(p[1])
	return cap


static func power_of(species: String) -> float:
	return float(Data.species_row(species).get("power", RANaming.species_info(species).get("power", 1.0)))


static func is_forbidden(species: String) -> bool:
	var row := Data.species_row(species)
	return species == "undead" or (bool(row.get("forbidden", false)) and bool(Data.flag("undead_naming_forbidden")))


## load / capacity: 1.0 means the namer is exactly able; above 1.0 the creature outweighs the namer.
static func ratio(species: String, level: int, caster_level: int, tier: int, level_penalty := 0) -> float:
	var cap := maxf(1.0, float(caster_level - level_penalty) * (1.0 + 0.15 * float(maxi(0, tier - 2))))
	return power_of(species) * float(maxi(1, level)) / cap


static func hollow_fraction(r: float) -> float:
	return clampf((r - HOLLOW_RATIO) * 0.6, 0.0, 0.6) if r > HOLLOW_RATIO else 0.0


## Exhaustion tier by the fraction of the reserve a rite spends: none | winded | fatigue | overdrawn.
static func exhaustion_tier(spent: float, reserve_max: float, current: float) -> String:
	if spent > current:
		return "overdrawn"
	var f := spent / maxf(1.0, reserve_max)
	if f < 0.4:
		return "none"
	if f < 0.7:
		return "winded"
	return "fatigue"


func preview(caster: RAMagicules, caster_level: int, tier: int, species: String, level: int, injuries: RAInjuries = null, opts := {}) -> Dictionary:
	var n := int(opts.get("group", 1))
	var base := naming.preview(caster, caster_level, species, level, injuries)
	var r := ratio(species, level, caster_level, tier, naming.level_penalty(int(opts.get("day", _day))))
	var c := int(base["cost"])
	if n > 1:
		c = int(ceil(maxf(float(base["cost"]) * TRIBE_FACTOR * float(n), float(base["cost"]) * TRIBE_MIN_TOTAL)))
	var out := base.duplicate()
	out["cost"] = c
	out["possible"] = float(c) <= caster.spendable() and not is_forbidden(species) and r <= OUTRIGHT_RATIO
	out["ratio"] = r
	out["forbidden"] = is_forbidden(species)
	out["refuse_outright"] = r > OUTRIGHT_RATIO
	out["hollow"] = hollow_fraction(r)
	out["exhaustion"] = exhaustion_tier(float(c), caster.effective_max(), caster.current)
	out["note"] = "It would be like naming a storm." if r > OUTRIGHT_RATIO else ("The name may take more than you have." if r > HOLLOW_RATIO else "")
	return out


# ------------------------------------------------------------------ bonds

func bond(id: String) -> Dictionary:
	return _bonds.get(id, {})


func bond_ids() -> Array:
	var ids := _bonds.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a.substr(1)) < int(b.substr(1)))
	return ids


func count() -> int:
	return _bonds.size()


func _start_stage(grade: String, species: String, tier: int) -> Array:
	var ceil_a := species_ceiling(species)
	var s0: int = int(BAND_STAGE.get(grade, 1))
	if grade == "true":
		s0 = clampi(band_cap(tier), 2, 4) if band_cap(tier) >= 2 else 2
		s0 = mini(s0, 2)       # a True Name starts at 2 and grows with depth to the species ceiling
	var out: Array = []
	for i in 4:
		out.append(mini(s0, int(ceil_a[i])))
	return out


func _new_bond(grade: String, species: String, name: String, namer: String, tier: int, day: int, extra: Dictionary) -> Dictionary:
	var id := "b%d" % _next
	_next += 1
	var tr := _start_stage(grade, species, tier)
	var row := Data.species_row(species)
	var b := {"id": id, "namer": namer, "grade": grade, "species": species, "name": name, "day": day,
		"form": tr[0], "mind": tr[1], "speech": tr[2], "ability": tr[3], "start": tr.duplicate(), "depth": 0.0,
		"loyalty": 75, "ref": 0, "ref_kind": "", "independence": snappedf(0.15 + 0.08 * float(tr[1]), 0.01), "ambition": "",
		"deeds": 0, "byname": "", "dormant_until": -1, "station": -1, "follower": "", "camp": "", "level": 1, "class": "", "keep": true,
		"harmed": 0, "tribe_of": "", "kind": String(row.get("kind", "monster")), "forbidden": false}
	for k: String in extra:
		b[k] = extra[k]
	b["ambition"] = _roll_ambition(species, id)
	_bonds[id] = b
	return b


func _roll_ambition(species: String, id: String) -> String:
	var amb: Dictionary = Data.species_row(species).get("ambitions", {"none": 100})
	var total := 0
	for k: String in amb:
		total += int(amb[k])
	var r := _roll("ambition", id, 0) * float(maxi(total, 1))
	var acc := 0.0
	for k: String in amb:
		acc += float(amb[k])
		if r < acc:
			return k
	return "none"


func _refusal_chance(species: String, target: Dictionary, r: float, caster_level: int) -> float:
	var ch := float(PRIDE.get(species, 0.1)) + float(target.get("pride", 0.0)) + 0.3 * float(target.get("grudge", 0.0))
	if bool(target.get("bound_elsewhere", false)):
		ch += 0.15
	if int(target.get("level", 1)) >= caster_level:
		ch += 0.1
	if r > 1.0 and r <= HOLLOW_RATIO:
		ch += 0.25
	if bool(target.get("starving", false)):
		ch -= 0.1
	return clampf(ch, 0.0, 0.9)


## Name a creature. target: {species, level, name, key, pride, grudge, bound_elsewhere, starving}. opts: {grade "lesser"|"true", klass,
## at_shrine, day, namer, tier, station, sid (settlement where it is told)}. Returns {ok, outcome, text, bond, cost, ratio, exhaustion,
## collapse_hours, hollowed, injuries}. Outcomes: named | forbidden | refused_outright | cooldown | refused | backlash | named_back.
func name_creature(caster: RAMagicules, injuries: RAInjuries, caster_level: int, target: Dictionary, given: String, opts := {}) -> Dictionary:
	var species := String(target.get("species", "wolf"))
	var level := int(target.get("level", 1))
	var grade := String(opts.get("grade", "lesser"))
	var tier := int(opts.get("tier", 3))
	var day := int(opts.get("day", _day))
	var out := {"ok": false, "outcome": "", "text": "", "bond": {}, "cost": 0, "ratio": 0.0, "exhaustion": "none", "collapse_hours": 0, "hollowed": 0.0, "injuries": []}
	if peak_pool <= 0.0:
		peak_pool = caster.max_pool
	if is_forbidden(species):
		out["outcome"] = "forbidden"
		out["text"] = "The dead are not named. Some doors stay shut."
		return out
	if _bonds.size() >= BOND_MAX:
		out["outcome"] = "full"
		out["text"] = "You cannot keep more bonds than you can feed."
		return out
	var key := String(target.get("key", "%s:%s" % [species, String(target.get("name", given))]))
	if int(_refused_until.get(key, -1)) > day:
		out["outcome"] = "cooldown"
		out["text"] = "It still turns its face from you."
		return out
	var pen := naming.level_penalty(day)
	var r := ratio(species, level, caster_level, tier, pen)
	out["ratio"] = r
	if r > OUTRIGHT_RATIO:
		out["outcome"] = "refused_outright"
		out["text"] = "It would be like naming a storm."
		return out
	var cost := RANaming.cost(species, level)
	out["cost"] = cost
	if float(cost) > caster.spendable() and grade != "true":
		out["outcome"] = "unaffordable"
		out["text"] = "The name will not hold: it needs %d embers and you can give at most %d." % [cost, int(floor(caster.spendable()))]
		return out
	# Refusal.
	var chance := _refusal_chance(species, target, r, caster_level - pen)
	if _roll("refuse", key, day) < chance:
		_refused_until[key] = day + REFUSE_COOLDOWN_DAYS
		var second := _roll("refuse2", key, day)
		if second < 0.15:
			out["outcome"] = "named_back"
			_debts.append({"key": key, "namer": String(opts.get("namer", "player")), "day": day, "species": species})
			out["text"] = "It says its own name instead, and you owe it an answer."
		elif second < 0.55:
			out["outcome"] = "backlash"
			var half := caster.spend(float(cost) * 0.5)
			if injuries != null and injuries.find("soul_fatigue").is_empty():
				injuries.add("soul_fatigue", day, 2)
			out["text"] = "The name breaks on its teeth. Half the cost is lost and Soul Fatigue follows."
			out["damage"] = half.get("damage", 0)
		else:
			out["outcome"] = "refused"
			out["text"] = "It turns away. Nothing happens."
		return out
	var pre_cur := caster.current
	var pre_max := caster.effective_max()
	var tgt := {"kind": "monster", "species": species, "level": level, "name": String(target.get("name", given))}
	var res: Dictionary
	var klass := String(opts.get("klass", RANaming.class_options(species)[0]))
	if grade == "true":
		res = naming.soul_name_ritual(caster, tier, tgt, given, day, {"at_shrine": bool(opts.get("at_shrine", false))})
		if not bool(res["ok"]):
			out["outcome"] = "failed"
			out["text"] = String(res["text"])
			return out
	else:
		res = naming.name_monster(caster, injuries, caster_level - pen, species, level, given, klass, day)
		if not bool(res["ok"]):
			out["outcome"] = "failed"
			out["text"] = String(res["text"])
			return out
	out["text"] = String(res["text"])
	out["damage"] = int(res.get("damage", 0))
	var spent := float(cost) if grade != "true" else float(res.get("shared", 0.0))
	out["exhaustion"] = exhaustion_tier(spent, pre_max, pre_cur) if grade != "true" else "none"
	if out["exhaustion"] == "winded":
		winded_until = day + 1
	if out["exhaustion"] == "overdrawn":
		var hrs := 6 + int(_roll("collapse", key, day) * 18.0)
		collapse = {"day": day, "hours": hrs}
		out["collapse_hours"] = hrs
	var extra := {"ref_kind": "soul" if grade == "true" else "roster", "level": level, "class": klass, "cost": cost,
		"ref": int(res["bond"]["id"]) if grade == "true" else int(res["subordinate"]["id"]),
		"loyalty": int(res["bond"]["loyalty"]) if grade == "true" else int(res["subordinate"]["loyalty"]), "station": int(opts.get("station", -1))}
	var b := _new_bond(grade, species, String(given).strip_edges(), String(opts.get("namer", "player")), tier, day, extra)
	if r > HOLLOW_RATIO:
		var frac := hollow_fraction(r)
		var loss := caster.max_pool * frac
		var floor_v := peak_pool * HOLLOW_FLOOR
		var new_max := maxf(caster.max_pool - loss, minf(floor_v, caster.max_pool))
		out["hollowed"] = caster.max_pool - new_max
		hollowed_total += float(out["hollowed"])
		caster.max_pool = new_max
		caster.current = minf(caster.current, caster.effective_max())
		b["independence"] = 0.8
		out["text"] += " The name takes more than you had: your reserve is hollowed."
	if int(res.get("soul_fatigue_days", 0)) > 0 and injuries != null and injuries.find("soul_fatigue").is_empty():
		injuries.add("soul_fatigue", day, int(res["soul_fatigue_days"]))
	out["ok"] = true
	out["outcome"] = "named"
	out["bond"] = b
	_story(b, int(opts.get("sid", -1)), day)
	return out


## Tribe rite: names `leader` (grade as opts) and then up to 3 + tier*2 kin. members: [{name, species, level}]. feast: loyalty 75 else 55.
func tribe_name(caster: RAMagicules, injuries: RAInjuries, caster_level: int, leader: Dictionary, given: String, members: Array, opts := {}) -> Dictionary:
	var tier := int(opts.get("tier", 3))
	var day := int(opts.get("day", _day))
	var out := {"ok": false, "text": "", "leader": {}, "members": [], "cost": 0, "defectors": [], "camp": ""}
	var cap := 3 + tier * 2
	if members.size() > cap:
		out["text"] = "A rite can bind at most %d kin at this tier." % cap
		return out
	var sp := String(leader.get("species", "goblin"))
	var single := RANaming.cost(sp, int(leader.get("level", 1)))
	var kin_cost := 0.0
	for m: Dictionary in members:
		kin_cost += float(RANaming.cost(String(m.get("species", sp)), int(m.get("level", 1)))) * TRIBE_FACTOR
	var total := maxf(float(single) + kin_cost, float(single) * TRIBE_MIN_TOTAL)
	out["cost"] = int(ceil(total))
	if kin_cost > caster.spendable():
		out["text"] = "The kin cost more than you can give."
		return out
	var lr := name_creature(caster, injuries, caster_level, leader, given, opts)
	if not bool(lr["ok"]):
		out["text"] = String(lr["text"])
		out["leader_result"] = lr
		return out
	out["leader"] = lr["bond"]
	var spent := caster.spend(kin_cost)
	var camp := String(opts.get("camp", "camp%d" % _next))
	var feast := bool(opts.get("feast", false))
	var ids: Array = [lr["bond"]["id"]]
	var lieutenant_refuses := _roll("lieutenant", camp, day) < 0.2 and members.size() >= 3
	var defect: Array = []
	var idx := 0
	for m: Dictionary in members:
		idx += 1
		if lieutenant_refuses and idx <= mini(4, members.size()) and idx >= 1 and defect.size() < 4 and (idx == 1 or _roll("follow", "%s:%d" % [camp, idx], day) < 0.6):
			defect.append(m)
			continue
		var mb := _new_bond("lesser", String(m.get("species", sp)), "%s kin %d" % [given, idx], String(opts.get("namer", "player")), tier, day,
			{"ref_kind": "kin", "level": int(m.get("level", 1)), "tribe_of": lr["bond"]["id"], "camp": camp, "loyalty": 75 if feast else TRIBE_NO_FEAST_LOYALTY,
			"station": int(opts.get("station", -1))})
		for t in ["form", "mind", "speech"]:
			mb[t] = mini(1, int(species_ceiling(String(mb["species"]))[["form", "mind", "speech"].find(t)]))
		mb["ability"] = 0
		ids.append(mb["id"])
		out["members"].append(mb)
	lr["bond"]["camp"] = camp
	vassal_camps[camp] = {"master": String(opts.get("namer", "player")), "leader": lr["bond"]["id"], "members": ids, "day": day}
	if not defect.is_empty():
		var rv := {"id": "rv%d" % (rivals.size() + 1), "leader_name": String(defect[0].get("name", "a lieutenant")), "members": defect.size(), "species": String(defect[0].get("species", sp)), "day": day, "camp": camp}
		rivals.append(rv)
		out["defectors"] = defect
		out["rival"] = rv
	out["ok"] = true
	out["camp"] = camp
	out["overdraw"] = spent.get("overdraw", 0.0)
	out["text"] = "The rite is done: %d named, %d refused." % [ids.size(), defect.size()]
	return out


func camp_attacks(camp: String, who: String) -> bool:
	var c: Dictionary = vassal_camps.get(camp, {})
	return c.is_empty() or String(c["master"]) != who


# ------------------------------------------------------------------ growth

func add_depth(id: String, amount: float) -> Array:
	var b := bond(id)
	var events: Array = []
	if b.is_empty():
		return events
	b["depth"] = clampf(float(b["depth"]) + amount, 0.0, 100.0)
	events.append_array(_grow(b))
	return events


func _stage_cap(b: Dictionary, i: int) -> int:
	var ceil_v := int(species_ceiling(String(b["species"]))[i])
	if String(b["grade"]) == "lesser" or String(b["grade"]) == "hired":
		return mini(ceil_v, int(Data.table("species_tracks").get("lesser_cap", 2)))
	return ceil_v


func _grow(b: Dictionary) -> Array:
	var ev: Array = []
	var th: Array = Data.table("species_tracks").get("depth_thresholds", [30, 55, 80])
	var steps := 0
	for t in th:
		if float(b["depth"]) >= float(t):
			steps += 1
	var names := ["form", "mind", "speech", "ability"]
	var jumped := false
	for i in 4:
		var want: int = mini(int((b["start"] as Array)[i]) + steps, _stage_cap(b, i))
		if want > int(b[names[i]]):
			b[names[i]] = want
			jumped = true
			ev.append({"type": "grew", "bond": b["id"], "track": names[i], "stage": want})
	if jumped:
		b["dormant_until"] = _day + int(Data.table("species_tracks").get("dormancy_days", 3))
		b["independence"] = clampf(float(b["independence"]) + 0.05, 0.0, 1.0)
	return ev


func is_dormant(id: String, day := -1) -> bool:
	return int(bond(id).get("dormant_until", -1)) > (_day if day < 0 else day)


func can_command(id: String) -> bool:
	return not bond(id).is_empty() and not is_dormant(id)


func record_deed(id: String, n := 1) -> void:
	var b := bond(id)
	if b.is_empty():
		return
	b["deeds"] = int(b["deeds"]) + n
	if b["byname"] == "" and int(b["deeds"]) >= 3:
		var place := String(b.get("place", "the Eastern Pass"))
		b["byname"] = String(BYNAMES[absi(hash([seed_value, b["id"]])) % BYNAMES.size()]) % place
	add_depth(id, 2.0 * n)


func _adjust_loyalty(b: Dictionary, d: int) -> void:
	var kind := String(b["ref_kind"])
	if kind == "roster":
		naming.adjust_loyalty(int(b["ref"]), d)
		b["loyalty"] = int(naming.subordinate(int(b["ref"])).get("loyalty", int(b["loyalty"]) + d))
	elif kind == "soul":
		naming.adjust_bond_loyalty(int(b["ref"]), d)
		b["loyalty"] = int(naming.soul_bond(int(b["ref"])).get("loyalty", int(b["loyalty"]) + d))
	else:
		b["loyalty"] = clampi(int(b["loyalty"]) + d, 0, 100)


func adjust_loyalty(id: String, d: int) -> int:
	var b := bond(id)
	if b.is_empty():
		return -1
	_adjust_loyalty(b, d)
	return int(b["loyalty"])


func set_keep(id: String, fed: bool, slept: bool, spoken_to: bool) -> void:
	var b := bond(id)
	if not b.is_empty():
		b["keep"] = fed and slept
		if spoken_to:
			add_depth(id, 0.5)


func release(id: String) -> void:
	var b := bond(id)
	if b.is_empty():
		return
	if String(b["ref_kind"]) == "roster":
		naming.dismiss(int(b["ref"]))
	elif String(b["ref_kind"]) == "soul":
		naming.dismiss_bond(int(b["ref"]))
	_bonds.erase(id)


func tick_day(day: int, _ctx: Dictionary) -> Array:
	_day = day
	var msgs: Array = []
	for id in bond_ids():
		var b: Dictionary = _bonds[id]
		if not bool(b["keep"]):
			_adjust_loyalty(b, -(1 + int(_roll("keepdrop", id, day) * 3.0)))
		else:
			add_depth(id, 0.5)
		# Independence follows the mind track; falls with respect and fear (loyalty as proxy).
		var tgt := 0.15 + 0.12 * float(b["mind"]) + 0.08 * float(b["speech"]) - 0.002 * float(b["loyalty"])
		b["independence"] = snappedf(clampf(float(b["independence"]) + (tgt - float(b["independence"])) * 0.05, 0.0, 1.0), 0.001)
		if int(b["follower"] != "" and 1 or 0) == 1:
			pass
		if String(b["ref_kind"]) == "roster" and naming.subordinate(int(b["ref"])).is_empty():
			msgs.append("%s has left you." % b["name"])
			_bonds.erase(id)
	return msgs


func catch_up(days: int, ctx: Dictionary) -> Array:
	# Closed form: depth and loyalty drift linearly; bonds that are kept just gain depth.
	var msgs: Array = []
	for id in bond_ids():
		var b: Dictionary = _bonds[id]
		if bool(b["keep"]):
			add_depth(id, 0.5 * float(days))
		else:
			_adjust_loyalty(b, -2 * days)
	_day += days
	return msgs


# ------------------------------------------------------------------ will (MN-4, compact)

## An order meets the monster's character. Returns {action "obey"|"refuse"|"negotiate"|"leave", line}.
func respond(id: String, order: String, situation := {}) -> Dictionary:
	var b := bond(id)
	if b.is_empty():
		return {"action": "refuse", "line": ""}
	if is_dormant(id):
		return {"action": "refuse", "line": "It cannot hear you; it is changing."}
	var ethos := String(Data.species_row(String(b["species"])).get("ethos", ""))
	var indep := float(b["independence"])
	if order in MORAL_ORDERS:
		if ethos in ["oath", "law", "calm"] or indep > 0.7:
			return {"action": "refuse", "line": "I gave my word. Not this."}
		if int(b["loyalty"]) < 40:
			return {"action": "leave", "line": "Find another hand for that."}
	if indep > 0.7 and order == "work" and not bool(situation.get("paid", true)):
		return {"action": "negotiate", "line": "Wages first."}
	if int(b["loyalty"]) < 25:
		return {"action": "leave", "line": ""}
	return {"action": "obey", "line": ""}


## Ambition check when denied (land, a seat, wages): returns {leaves, founds_tribe}.
func consider_leaving(id: String, denied: String) -> Dictionary:
	var b := bond(id)
	if b.is_empty():
		return {"leaves": false, "founds_tribe": false}
	var amb := String(b["ambition"])
	var match_ := (denied == "land" and amb in ["greed", "territory", "found_tribe", "power"]) or (denied == "seat" and amb == "council_seat")
	var leaves: bool = match_ and float(b["independence"]) > 0.5
	if leaves:
		b["status"] = "gone"
	return {"leaves": leaves, "founds_tribe": leaves and amb in ["found_tribe", "territory", "power"]}


# ------------------------------------------------------------------ party view

func civility(b: Dictionary) -> float:
	return clampf(0.3 + 0.1 * float(b["form"]) + 0.05 * float(b["mind"]) + (0.1 if String(b["byname"]) != "" else 0.0) - 0.2 * minf(1.0, float(b["harmed"])), 0.0, 1.0)


## Active companions as party rows for Status and the gate. namer "" = all.
func companions_of(namer: String) -> Array:
	var out: Array = []
	for id in bond_ids():
		var b: Dictionary = _bonds[id]
		if namer != "" and String(b["namer"]) != namer:
			continue
		if int(b["station"]) >= 0 or String(b.get("status", "")) == "gone":
			continue
		out.append(party_row(b))
	return out


func party_row(b: Dictionary) -> Dictionary:
	return {"bond_id": int(String(b["id"]).substr(1)), "species": b["species"], "kind": b["kind"], "speech": b["speech"], "form": b["form"],
		"civility": civility(b), "named": true, "power": maxi(1, int(round(power_of(String(b["species"])) * float(b["level"]) / 3.0)))}


func stationed(sid: int) -> Array:
	var out: Array = []
	for id in bond_ids():
		if int(_bonds[id]["station"]) == sid:
			out.append(_bonds[id])
	return out


func station(id: String, sid: int) -> void:
	var b := bond(id)
	if not b.is_empty():
		b["station"] = sid


# ------------------------------------------------------------------ followers (recruiting)

func _fol() -> RefCounted:
	return hub.mod("followers") if hub != null else null


## Makes bond `id` a follower row (named monsters join as followers). Returns the follower id ("" when no followers module).
func recruit_follower(id: String, loc := "s0") -> String:
	var b := bond(id)
	var fol := _fol()
	if b.is_empty() or fol == null:
		return ""
	if String(b["follower"]) != "":
		return String(b["follower"])
	var occ: String = String(CLASS_OCC.get(String(b["class"]), "mercenary"))
	var fid: String = fol.hire(occ, loc, true, "mn_" + String(id))
	var f: Dictionary = fol.get_follower(fid)
	f["name"] = b["name"]
	var ethos := String(Data.species_row(String(b["species"])).get("ethos", ""))
	var traits: Array = (ETHOS_TRAITS.get(ethos, ["loyal"]) as Array).duplicate()
	while traits.size() < 3:
		var extra: String = ["brave", "cautious", "curious"][traits.size() % 3]
		if extra not in traits:
			traits.append(extra)
		else:
			break
	f["traits"] = traits
	f["origin"] = "the wild (%s)" % b["species"]
	f["loyalty"] = float(b["loyalty"])
	f["salary"] = 0 if String(b["grade"]) != "hired" else int(b.get("wage", 0))
	f["flags"] = {"monster": b["species"], "bond": id}
	f.erase("values")
	fol._expand(f)
	b["follower"] = fid
	return fid


## Hire path (no name): an intelligent monster (speech >= 2) bargains. terms {w, h (a den or room)}. Returns {ok, line, bond, fid}.
func hire_monster(species: String, name: String, speech: int, terms: Dictionary, opts := {}) -> Dictionary:
	var day := int(opts.get("day", _day))
	if is_forbidden(species):
		return {"ok": false, "line": "Some things are not hired."}
	if speech < 2:
		return {"ok": false, "line": "It does not understand an offer."}
	var ask := 3 + int(round(power_of(species) * 2.0))
	if int(terms.get("h", 0)) != 1:
		return {"ok": false, "line": "I need a den or a room, not the street."}
	if int(terms.get("w", 0)) < ask:
		return {"ok": false, "line": "Not for that wage. I need %d." % ask, "ask": ask}
	var b := _new_bond("hired", species, name, String(opts.get("namer", "player")), 3, day,
		{"ref_kind": "kin", "level": int(opts.get("level", 3)), "class": String(opts.get("klass", "warrior")), "wage": int(terms["w"]), "loyalty": 60, "speech": speech})
	b["start"][2] = speech
	var fid := recruit_follower(String(b["id"]), String(opts.get("loc", "s0")))
	return {"ok": true, "line": "%s joins you." % name, "bond": b, "fid": fid}


# ------------------------------------------------------------------ legends

func _story(b: Dictionary, sid: int, day: int) -> void:
	if hub == null:
		return
	var ms: Variant = hub.mod("monster_society")
	if ms != null:
		ms.on_name_story(String(b["namer"]), sid, b, day)
	var nw: Variant = hub.mod("news")
	if nw != null and sid >= 0:
		nw.post("name_given", sid, "Somebody spoke a name over a %s %s." % ["wild" if b["kind"] == "beast" else "feared", b["species"]], 1.0, "", false, day)


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	return {"b": _bonds.duplicate(true), "n": _next, "ru": _refused_until.duplicate(), "debts": _debts.duplicate(true), "hollow": hollowed_total,
		"peak": peak_pool, "winded": winded_until, "collapse": collapse.duplicate(), "vassal": vassal_camps.duplicate(true), "rivals": rivals.duplicate(true),
		"day": _day, "naming": {} if _shared else naming.serialize()}


func deserialize(d: Dictionary) -> void:
	_bonds = (d.get("b", {}) as Dictionary).duplicate(true)
	for id: String in _bonds:
		var b: Dictionary = _bonds[id]
		for k: String in ["form", "mind", "speech", "ability", "ref", "station", "deeds", "level", "harmed", "dormant_until"]:
			b[k] = int(b.get(k, 0 if k != "station" and k != "dormant_until" else -1))
		b["start"] = (b.get("start", [1, 1, 1, 1]) as Array).map(func(x: Variant) -> int: return int(x))
		b["depth"] = float(b.get("depth", 0.0))
		b["independence"] = float(b.get("independence", 0.2))
	_next = int(d.get("n", 1))
	_refused_until = (d.get("ru", {}) as Dictionary).duplicate()
	_debts = (d.get("debts", []) as Array).duplicate(true)
	hollowed_total = float(d.get("hollow", 0.0))
	peak_pool = float(d.get("peak", 0.0))
	winded_until = int(d.get("winded", -1))
	collapse = (d.get("collapse", {}) as Dictionary).duplicate()
	vassal_camps = (d.get("vassal", {}) as Dictionary).duplicate(true)
	rivals = (d.get("rivals", []) as Array).duplicate(true)
	_day = int(d.get("day", 0))
	if not _shared and not (d.get("naming", {}) as Dictionary).is_empty():
		naming.deserialize(d["naming"])
