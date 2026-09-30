extends RefCounted
## War between Caldrenn and one of its harder neighbours (data/world/nations.json:
## Ongur Khanate "wary", Urrokai Clanlands "hostile" -- the two most plausible
## sources of an actual war, per each nation's relations to Caldrenn).
## docs/RISING_ASHES_LIFE_SIM_DESIGN.md, "Living world simulation": "War
## reaches ordinary people: prices, horses, recruitment, contracts, refugees,
## danger, fortified borders, crime."
##
## Pure data (RefCounted, serialisable). A diplomatic tension meter per
## candidate nation simmers from border incidents, noble feuds (nobility.gd's
## feuds()) and Rift crises. War needs a CASUS BELLI (claim, feud, succession,
## repeated raids, Rift crisis, broken treaty, insult to a house): tension alone
## never declares one, and a truce after every peace blocks a redeclaration.
## A war is fought on a front of 2-3 border regions with abstract battles,
## war weariness on both sides, raids on villages near the front, and ends in a
## peace deal with terms (land, tribute, hostages, marriage) and a truce.
## Wars are rare (about one every 1-3 years) and last weeks to months.
## The player feeds it through scripts/realm/war_influence.gd (add_tension,
## offer_cb, add_support, push_peace ...).
##
## This file never touches Life, lordship, economy, careers or nobility
## directly -- it only reads what it's given in `tick_day`'s ctx and hands
## back messages plus small, explicit hooks (battle_at_front(),
## contract_for_merchant(), crop_requisition_fraction(), raided_today()) for
## the caller to apply to those systems. See the task report for the exact
## lines that wire is_at_war() into life_path.flags["at_war"] (which economy,
## lordship and career_ladders already read) and into main.gd/village_services.gd.
##
## tick_day ctx: {feud_count: int (nobility.feuds().size()), rift_instability:
## float (Frontier.rift_instability), season: String}. Returns Array[String]
## of Game.say-able lines, same shape as lordship.daily_tick()/economy.tick_hour().

signal war_declared(enemy: String, front: Array)
signal war_ended(enemy: String, treaty_text: String)

const NATIONS_PATH := "res://data/world/nations.json"
## The two neighbours realistically hostile enough to fight Caldrenn (see
## nations.json: caldrenn.relations).
const WAR_CANDIDATES := ["ongur_khanate", "urrokai_clanlands"]
const BORDER_WEIGHT := {"hostile": 1.6, "wary": 1.0, "neutral": 0.6}

const TENSION_WAR_THRESHOLD := 85.0
const TENSION_PEACE_CAP := 65.0            # without a casus belli tension simmers below this
const TENSION_PEACE_DECAY := 0.30
const TENSION_BORDER_INCIDENT := Vector2(0.05, 0.40)
const TENSION_PER_FEUD := 0.05
const TENSION_RIFT_MULT := 4.0             # only while the Rift is truly unstable (RIFT_CRISIS)
const RIFT_CRISIS := 0.5
const TENSION_AFTER_WAR := 10.0
const DECLARE_CHANCE := 0.12               # per day once tension and a casus belli are both ready

## Casus belli kinds: weight (tension impulse), ttl days, who usually holds the grievance, war goal.
const CB_KINDS := {
	"claim": {"weight": 34.0, "ttl": 420, "goal": "land", "label": "Territorial claim"},
	"feud": {"weight": 26.0, "ttl": 300, "goal": "tribute", "label": "Noble feud"},
	"succession": {"weight": 32.0, "ttl": 360, "goal": "marriage", "label": "Succession dispute"},
	"raids": {"weight": 30.0, "ttl": 240, "goal": "tribute", "label": "Repeated raids"},
	"rift": {"weight": 38.0, "ttl": 200, "goal": "hostages", "label": "Rift crisis"},
	"broken_treaty": {"weight": 45.0, "ttl": 500, "goal": "land", "label": "Broken treaty"},
	"insult": {"weight": 24.0, "ttl": 240, "goal": "tribute", "label": "Insult to a house"},
	"incident": {"weight": 14.0, "ttl": 120, "goal": "tribute", "label": "Border incident"},
}
## Natural arrival rates of a casus belli per day, times the stance weight (feud also times feud count).
const CB_RATE := {"claim": 0.00055, "feud": 0.00045, "succession": 0.00050, "insult": 0.00040}
const RAID_RATE := 0.035                   # border raids per day (x stance weight)
const RAID_CB_COUNT := 6                   # raids inside RAID_CB_WINDOW days become a casus belli
const RAID_CB_WINDOW := 45
const CB_MAX := 6

const FRONT_REGIONS_MIN := 2
const FRONT_REGIONS_MAX := 3
const RAID_CHANCE := 0.05                  # per front region per day
const BATTLE_CHANCE := 0.30                # per day (winter x0.35)
const WEARINESS_PER_DAY := Vector2(0.008, 0.018)
const WEARINESS_PER_LOSS := 0.0004
const TREATY_EXHAUSTION := 1.0
const PEACE_PRESSURE_NEEDED := 1.0         # peace pressure from brokers/pressure sums with weariness
const MIN_WAR_DAYS := 14
const MAX_WAR_DAYS := 240
const TRUCE_DAYS := Vector2i(150, 420)
const WAR_MERCHANT_GOODS := ["iron_sword", "iron_helm", "leather_jerkin"]
const NEWS_MAX := 30
const CHRONICLE_MAX := 20
const ACT_LOG_MAX := 30
const HOSTAGE_NAMES := ["the Khan's young nephew", "a daughter of the chief's household", "two sons of a border clan", "the heir of a frontier house"]

static var _nations: Dictionary = {}

## Diplomatic tension 0..100 per candidate nation id.
var tension: Dictionary = {}
## {} when at peace, else {enemy, started_day, front: [{name, pos, control}], exhaustion, enemy_exhaustion,
## caldrenn_losses, enemy_losses, battles, cb: {..}, goal, aggressor, support, pressure}.
var war: Dictionary = {}
## Short historical record of how wars ended (treaty lines), newest last.
var chronicle: Array[String] = []
## id -> Array of {kind, text, day, expires, weight, by}: live reasons to fight.
var cbs: Dictionary = {}
## id -> day the truce ends (no declaration until then).
var truce_until: Dictionary = {}
## Hostages held after a treaty: [{name, from, until, day}].
var hostages: Array = []
## The latest peace deal: {enemy, day, winner, goal, land, tribute, hostages, marriage, truce_days, text}.
var last_treaty: Dictionary = {}
## Raid days per nation (repeated raids become a casus belli).
var _raid_days: Dictionary = {}
## The player's acts: {id: last day} cooldown map plus a short log [{day, act, text}].
var act_days: Dictionary = {}
var act_log: Array = []
## Villages the player is guarding: name -> until_day.
var guarded: Dictionary = {}
## Tribute still owed: {to, amount, until}
var tribute: Dictionary = {}
## {settlement_name, day}: the villages raided on the most recent tick_day().
var _last_raids: Array[Dictionary] = []
var _news_log: Array[String] = []
var _rng := RandomNumberGenerator.new()
var _day := 0
var _rift_days := 0
var wars_total := 0


func _init(seed_value := 90210) -> void:
	_rng.seed = seed_value
	for id: String in WAR_CANDIDATES:
		tension[id] = 0.0
		cbs[id] = []
		_raid_days[id] = []


static func nations() -> Dictionary:
	if _nations.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(NATIONS_PATH))
		_nations = d if d is Dictionary else {}
	return _nations


static func _nation(id: String) -> Dictionary:
	for n: Dictionary in (nations().get("nations", []) as Array):
		if String(n.get("id", "")) == id:
			return n
	return {}


static func display_name(id: String) -> String:
	var n := _nation(id)
	return String(n.get("short_name", n.get("name", id.capitalize())))


static func _caldrenn_stance(id: String) -> String:
	var caldrenn := _nation("caldrenn")
	return String((caldrenn.get("relations", {}) as Dictionary).get(id, "neutral"))


static func stance_weight(id: String) -> float:
	return float(BORDER_WEIGHT.get(_caldrenn_stance(id), 0.8))


# --- state -----------------------------------------------------------------------

func is_at_war() -> bool:
	return not war.is_empty()


func enemy_id() -> String:
	return String(war.get("enemy", ""))


func front() -> Array:
	return (war.get("front", []) as Array).duplicate(true)


## Caldrenn's war weariness 0..3 (1.0 = the crown wants peace).
func exhaustion() -> float:
	return float(war.get("exhaustion", 0.0))


func enemy_exhaustion() -> float:
	return float(war.get("enemy_exhaustion", 0.0))


func tension_of(id: String) -> float:
	return float(tension.get(id, 0.0))


func casualties() -> Dictionary:
	if war.is_empty():
		return {"caldrenn": 0, "enemy": 0}
	return {"caldrenn": int(war.get("caldrenn_losses", 0)), "enemy": int(war.get("enemy_losses", 0))}


func war_day() -> int:
	return _day - int(war.get("started_day", _day)) if is_at_war() else 0


## The villages raided on the most recently ticked day: [{settlement_name, day}].
## The caller (life.gd's hook) uses this to dock lordship loyalty and mark
## refugees for the nearest safe town.
func raided_today() -> Array[Dictionary]:
	return _last_raids.duplicate(true)


# --- casus belli -------------------------------------------------------------------

## Adds a reason to fight `id`. `by` is who holds the grievance ("caldrenn" or "enemy").
## A second reason of the same kind refreshes the first instead of stacking. Returns the record.
func offer_cb(id: String, kind: String, text: String, day := -1, by := "caldrenn", weight_mult := 1.0) -> Dictionary:
	if not cbs.has(id) or not CB_KINDS.has(kind):
		return {}
	var d := _day if day < 0 else day
	var def: Dictionary = CB_KINDS[kind]
	var list: Array = cbs[id]
	for c: Dictionary in list:
		if String(c["kind"]) == kind:
			c["expires"] = d + int(def["ttl"])
			c["text"] = text
			return c
	var rec := {"kind": kind, "text": text, "day": d, "expires": d + int(def["ttl"]), "weight": float(def["weight"]) * weight_mult, "by": by}
	list.append(rec)
	if list.size() > CB_MAX:
		list.pop_front()
	tension[id] = clampf(float(tension.get(id, 0.0)) + float(rec["weight"]), 0.0, 100.0)
	_news("Grievance with %s: %s" % [display_name(id), text])
	return rec


func casus_belli(id: String) -> Array:
	var out: Array = []
	for c: Dictionary in (cbs.get(id, []) as Array):
		if int(c["expires"]) > _day:
			out.append((c as Dictionary).duplicate())
	return out


func has_casus_belli(id: String) -> bool:
	return not casus_belli(id).is_empty()


func _strongest_cb(id: String) -> Dictionary:
	var best := {}
	for c: Dictionary in casus_belli(id):
		if best.is_empty() or float(c["weight"]) > float(best["weight"]):
			best = c
	return best


func remove_cb(id: String, kind: String) -> bool:
	var list: Array = cbs.get(id, [])
	for i in list.size():
		if String(list[i]["kind"]) == kind:
			list.remove_at(i)
			return true
	return false


# --- truces and diplomacy ---------------------------------------------------------------

func truce_days_left(id: String, day := -1) -> int:
	var d := _day if day < 0 else day
	return maxi(0, int(truce_until.get(id, 0)) - d)


func under_truce(id: String, day := -1) -> bool:
	return truce_days_left(id, day) > 0


## Tearing up a truce: the honour cost is the caller's (factions war_rep "break_treaty"); here the other
## side gets a casus belli and tension jumps. No-op without a truce.
func break_truce(id: String, by := "caldrenn", day := -1) -> bool:
	var d := _day if day < 0 else day
	if not under_truce(id, d):
		return false
	truce_until[id] = d
	var who := display_name(id) if by != "caldrenn" else "Caldrenn"
	offer_cb(id, "broken_treaty", "%s broke the truce sworn in the last peace." % who, d, "enemy" if by == "caldrenn" else "caldrenn")
	return true


## Per-nation diplomacy card for UI and news: stance, tension, truce, reasons to fight, hostages.
func diplomacy(id: String) -> Dictionary:
	var lines: Array[String] = []
	for c: Dictionary in casus_belli(id):
		lines.append(String(c["text"]))
	var held: Array[String] = []
	for h: Dictionary in hostages:
		if String(h["from"]) == id:
			held.append(String(h["name"]))
	var st := "peace"
	if is_at_war() and enemy_id() == id:
		st = "war"
	elif under_truce(id):
		st = "truce"
	return {"id": id, "name": display_name(id), "state": st, "stance": _caldrenn_stance(id), "tension": snappedf(tension_of(id), 0.1),
		"truce_days": truce_days_left(id), "reasons": lines, "hostages": held, "at_war": st == "war"}


func all_diplomacy() -> Array:
	var out: Array = []
	for id: String in WAR_CANDIDATES:
		out.append(diplomacy(id))
	return out


# --- daily tick --------------------------------------------------------------------

## Advances the war (or the peacetime tension leading to one) by one day.
## Returns lines for Game.say, same convention as lordship.daily_tick().
## ctx: feud_count, rift_instability, season; optional succession_crisis: String (nation id).
func tick_day(day: int, ctx: Dictionary) -> Array[String]:
	_last_raids.clear()
	_day = day
	_expire(day)
	var out: Array[String] = []
	out.append_array(_tribute_day(day))
	if is_at_war():
		out.append_array(_tick_war(day, ctx))
		return out
	out.append_array(_tick_tension(day, ctx))
	var candidate := _ready_for_war(day)
	if candidate != "":
		out.append(_declare_war(candidate, day))
	return out


func _expire(day: int) -> void:
	for id: String in cbs:
		var keep: Array = []
		for c: Dictionary in (cbs[id] as Array):
			if int(c["expires"]) > day:
				keep.append(c)
		cbs[id] = keep
	var g := {}
	for k: String in guarded:
		if int(guarded[k]) > day:
			g[k] = guarded[k]
	guarded = g
	var hk: Array = []
	for h: Dictionary in hostages:
		if int(h["until"]) > day:
			hk.append(h)
		else:
			_news("%s is released from %s's custody." % [String(h["name"]), "Caldrenn" if String(h["from"]) != "caldrenn" else display_name(String(h.get("to", "")))])
	hostages = hk


func _tick_tension(day: int, ctx: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var feud_count := int(ctx.get("feud_count", 0))
	var rift := float(ctx.get("rift_instability", 0.0))
	var succession := String(ctx.get("succession_crisis", ""))
	if rift >= RIFT_CRISIS:
		_rift_days += 1
	else:
		_rift_days = maxi(0, _rift_days - 1)
	for id: String in WAR_CANDIDATES:
		var w := stance_weight(id)
		var t := float(tension[id])
		var delta := _rng.randf_range(TENSION_BORDER_INCIDENT.x, TENSION_BORDER_INCIDENT.y) * w
		delta += feud_count * TENSION_PER_FEUD
		if rift >= RIFT_CRISIS:
			delta += rift * TENSION_RIFT_MULT
		# natural casus belli: each needs a real reason, none is tension alone
		if _rng.randf() < RAID_RATE * w:
			(_raid_days[id] as Array).append(day)
		var rd: Array = (_raid_days[id] as Array).filter(func(x: int) -> bool: return day - x <= RAID_CB_WINDOW)
		_raid_days[id] = rd
		if rd.size() >= RAID_CB_COUNT:
			offer_cb(id, "raids", "%s raiders have hit our border villages %d times this season." % [display_name(id), rd.size()], day, "caldrenn")
			_raid_days[id] = []
		if _rift_days >= 4 and not has_cb_kind(id, "rift"):
			offer_cb(id, "rift", "The Rift is tearing the marches; each side blames the other's wards.", day, "caldrenn" if _rng.randf() < 0.5 else "enemy")
		if feud_count > 0 and _rng.randf() < CB_RATE["feud"] * feud_count * w:
			offer_cb(id, "feud", "A feud between noble houses has dragged %s emissaries in." % display_name(id), day, "caldrenn" if _rng.randf() < 0.6 else "enemy")
		if (succession == id or _rng.randf() < CB_RATE["succession"] * w):
			offer_cb(id, "succession", "The succession at the %s court is disputed, and a claimant seeks Caldrenn's backing." % display_name(id), day, "enemy" if _rng.randf() < 0.5 else "caldrenn")
		if _rng.randf() < CB_RATE["claim"] * w:
			offer_cb(id, "claim", _claim_text(id), day, "caldrenn" if _rng.randf() < 0.5 else "enemy")
		if _rng.randf() < CB_RATE["insult"] * w:
			offer_cb(id, "insult", "A %s envoy insulted a great house of Caldrenn at court." % display_name(id), day, "caldrenn")
		var cap := 100.0 if has_casus_belli(id) else TENSION_PEACE_CAP
		t = clampf(t + delta - TENSION_PEACE_DECAY, 0.0, cap)
		if t > TENSION_PEACE_CAP and not has_casus_belli(id):
			t = TENSION_PEACE_CAP
		tension[id] = t
	return out


func has_cb_kind(id: String, kind: String) -> bool:
	for c: Dictionary in casus_belli(id):
		if String(c["kind"]) == kind:
			return true
	return false


func _claim_text(id: String) -> String:
	var pool: Array[String] = []
	for s: Dictionary in WorldGen.settlements:
		if String(s.get("kind", "")) == "frontier_town":
			pool.append(String(s["name"]))
	if pool.is_empty():
		return "%s revives an old claim to the border march." % display_name(id)
	pool.sort()
	return "%s claims the lands around %s by an old charter." % [display_name(id), pool[_rng.randi() % pool.size()]]


func _ready_for_war(day: int) -> String:
	var best_id := ""
	var best_t := -1.0
	for id: String in WAR_CANDIDATES:
		if under_truce(id, day):
			continue
		if not has_casus_belli(id):
			continue
		var t: float = float(tension[id])
		if t >= TENSION_WAR_THRESHOLD and t > best_t:
			best_t = t
			best_id = id
	if best_id != "" and _rng.randf() > DECLARE_CHANCE:
		return ""
	return best_id


func _declare_war(id: String, day: int) -> String:
	var front_regions := _build_front()
	var cb := _strongest_cb(id)
	var goal := String(CB_KINDS.get(String(cb.get("kind", "incident")), {}).get("goal", "tribute"))
	var aggressor := String(cb.get("by", "caldrenn"))
	war = {"enemy": id, "started_day": day, "front": front_regions, "exhaustion": 0.0, "enemy_exhaustion": 0.0,
		"caldrenn_losses": 0, "enemy_losses": 0, "battles": 0, "cb": cb.duplicate(), "goal": goal,
		"aggressor": "caldrenn" if aggressor == "caldrenn" else id, "support": _rng.randf_range(-0.1, 0.1), "pressure": 0.0,
		"pace": _rng.randf_range(0.5, 1.6)}
	wars_total += 1
	tension[id] = 40.0
	var who := "Caldrenn" if aggressor == "caldrenn" else display_name(id)
	var line := "War: %s takes up arms against %s. Cause: %s" % [who, display_name(id) if aggressor == "caldrenn" else "Caldrenn", String(cb.get("text", "border troubles"))]
	_news(line)
	war_declared.emit(id, front_regions)
	return line


## 2-3 border regions to fight over: the furthest frontier towns and forts
## from home (WorldGen.settlements kind "frontier_town", WorldGen.sites kind
## "fort"). Falls back to a fixed border march so a front always exists even
## on a seed with neither.
func _build_front() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for s: Dictionary in WorldGen.settlements:
		if String(s.get("kind", "")) == "frontier_town":
			candidates.append({"name": String(s["name"]), "pos": s["pos"]})
	for s: Dictionary in WorldGen.sites:
		if String(s.get("kind", "")) == "fort":
			candidates.append({"name": String(s["name"]), "pos": s["pos"]})
	if candidates.is_empty():
		var home: Vector2 = WorldGen.settlements[0]["pos"] if not WorldGen.settlements.is_empty() else Vector2.ZERO
		candidates.append({"name": "the border march", "pos": home + Vector2(900.0, 0.0)})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["name"]) < String(b["name"]))     # stable before the rng picks
	var picks: Array[Dictionary] = []
	var pool := candidates.duplicate()
	var want: int = mini(pool.size(), FRONT_REGIONS_MIN + (_rng.randi() % (FRONT_REGIONS_MAX - FRONT_REGIONS_MIN + 1)))
	want = maxi(want, 1)
	for i in want:
		if pool.is_empty():
			break
		var c: Dictionary = pool.pop_at(_rng.randi() % pool.size())
		picks.append({"name": c["name"], "pos": c["pos"], "control": 0.5})
	return picks


func _tick_war(day: int, ctx: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var winter := String(ctx.get("season", "")) == "winter"
	if _rng.randf() < BATTLE_CHANCE * (0.35 if winter else 1.0):
		war["battles"] = int(war["battles"]) + 1
		out.append(_resolve_battle())
	out.append_array(_raid_front_villages(day))
	var sup := float(war.get("support", 0.0))
	var pace := float(war.get("pace", 1.0))
	war["exhaustion"] = clampf(float(war["exhaustion"]) + _rng.randf_range(WEARINESS_PER_DAY.x, WEARINESS_PER_DAY.y) * pace * (1.0 - clampf(sup, -0.5, 0.5) * 0.5), 0.0, 3.0)
	war["enemy_exhaustion"] = clampf(float(war["enemy_exhaustion"]) + _rng.randf_range(WEARINESS_PER_DAY.x, WEARINESS_PER_DAY.y) * pace * (1.0 + clampf(sup, -0.5, 0.5) * 0.5), 0.0, 3.0)
	var days := day - int(war["started_day"])
	if days >= MIN_WAR_DAYS:
		var worn := maxf(float(war["exhaustion"]), float(war["enemy_exhaustion"])) + float(war.get("pressure", 0.0))
		var decisive := _decisive()
		if worn >= TREATY_EXHAUSTION or decisive != "" or days >= MAX_WAR_DAYS:
			out.append(_make_treaty(day))
	return out


## "caldrenn"/"enemy" when one side holds nearly the whole front (the loser sues for peace), else "".
func _decisive() -> String:
	var total := 0.0
	var n := 0
	for f: Dictionary in (war["front"] as Array):
		total += float(f["control"])
		n += 1
	if n == 0:
		return ""
	var avg := total / float(n)
	if avg >= 0.85:
		return "caldrenn"
	if avg <= 0.15:
		return "enemy"
	return ""


func avg_control() -> float:
	if not is_at_war():
		return 0.5
	var total := 0.0
	var n := 0
	for f: Dictionary in (war["front"] as Array):
		total += float(f["control"])
		n += 1
	return total / maxf(1.0, float(n))


func _resolve_battle() -> String:
	var front_list: Array = war["front"]
	var idx := _rng.randi() % front_list.size()
	var f: Dictionary = front_list[idx]
	var sup := float(war.get("support", 0.0))
	var caldrenn_losses := maxi(1, _rng.randi_range(3, 16) - int(round(sup * 6.0)))
	var enemy_losses := maxi(1, _rng.randi_range(3, 16) + int(round(sup * 6.0)))
	war["caldrenn_losses"] = int(war["caldrenn_losses"]) + caldrenn_losses
	war["enemy_losses"] = int(war["enemy_losses"]) + enemy_losses
	war["exhaustion"] = float(war["exhaustion"]) + caldrenn_losses * WEARINESS_PER_LOSS
	war["enemy_exhaustion"] = float(war["enemy_exhaustion"]) + enemy_losses * WEARINESS_PER_LOSS
	f["control"] = clampf(float(f["control"]) + float(enemy_losses - caldrenn_losses) * 0.02, 0.0, 1.0)
	front_list[idx] = f
	var text := "Battle at %s: %d Caldrenn dead, %d of %s fall." % [String(f["name"]), caldrenn_losses, enemy_losses, display_name(enemy_id())]
	_news(text)
	return text


## Villages near the front lose loyalty and send refugees (see raided_today()). A guarded village
## (see guard_settlement) turns the raiders back.
func _raid_front_villages(day: int) -> Array[String]:
	var out: Array[String] = []
	for f: Dictionary in (war["front"] as Array):
		if _rng.randf() > RAID_CHANCE:
			continue
		var near := WorldGen.nearest_settlement(f["pos"])
		if near.is_empty():
			continue
		var name := String(near["name"])
		if int(guarded.get(name, 0)) > day:
			var held := "Raiders probed %s and were turned back by its defenders." % name
			out.append(held)
			_news(held)
			continue
		_last_raids.append({"settlement_name": name, "day": day})
		var line := "Raiders strike near %s; refugees flee toward the safer towns." % name
		out.append(line)
		_news(line)
	return out


func _tribute_day(day: int) -> Array[String]:
	var out: Array[String] = []
	if tribute.is_empty():
		return out
	if int(tribute.get("until", 0)) <= day:
		tribute = {}
	return out


# --- peace -------------------------------------------------------------------------------

## Who is winning right now: "caldrenn", "enemy" or "draw".
func leader() -> String:
	if not is_at_war():
		return "draw"
	var score := (avg_control() - 0.5) * 2.0 + (enemy_exhaustion() - exhaustion()) * 0.4 + float(war.get("support", 0.0))
	if score > 0.2:
		return "caldrenn"
	if score < -0.2:
		return "enemy"
	return "draw"


## The deal the current balance of the war would produce: {winner, goal, land, tribute, hostages, marriage, truce_days, text}.
func propose_terms() -> Dictionary:
	if not is_at_war():
		return {}
	var id := enemy_id()
	var winner := leader()
	var goal := String(war.get("goal", "tribute"))
	var t := {"enemy": id, "winner": winner, "goal": goal, "land": "", "tribute": 0, "hostages": [], "marriage": {}, "truce_days": 0}
	var contested: Dictionary = {}
	var best := -1.0
	for f: Dictionary in (war["front"] as Array):
		var c := float(f["control"]) if winner != "enemy" else 1.0 - float(f["control"])
		if c > best:
			best = c
			contested = f
	var scale := 1.0 + float(int(war.get("caldrenn_losses", 0)) + int(war.get("enemy_losses", 0))) / 600.0
	if winner == "draw":
		t["truce_days"] = int(TRUCE_DAYS.x + 60)
		if goal == "tribute":
			t["tribute"] = int(40.0 * scale)
		t["text"] = "a white peace: prisoners are freed, the borders stay as they were"
	else:
		match goal:
			"land":
				t["land"] = String(contested.get("name", "the border march"))
			"tribute":
				t["tribute"] = int(180.0 * scale)
			"hostages":
				t["hostages"] = [HOSTAGE_NAMES[_rng.randi() % HOSTAGE_NAMES.size()]]
			"marriage":
				t["marriage"] = {"kind": "royal_match", "with": id}
		# a second clause when the win was clear
		if absf(avg_control() - 0.5) > 0.25:
			if t["tribute"] == 0:
				t["tribute"] = int(90.0 * scale)
			elif (t["hostages"] as Array).is_empty():
				t["hostages"] = [HOSTAGE_NAMES[_rng.randi() % HOSTAGE_NAMES.size()]]
		t["truce_days"] = int(_rng.randi_range(TRUCE_DAYS.x + 60, TRUCE_DAYS.y))
		var who := display_name(id) if winner == "caldrenn" else "Caldrenn"
		var to := "Caldrenn" if winner == "caldrenn" else display_name(id)
		var parts: Array[String] = []
		if String(t["land"]) != "":
			parts.append("cedes %s" % String(t["land"]))
		if int(t["tribute"]) > 0:
			parts.append("pays %d crowns in tribute" % int(t["tribute"]))
		if not (t["hostages"] as Array).is_empty():
			parts.append("gives %s as hostage" % String((t["hostages"] as Array)[0]))
		if not (t["marriage"] as Dictionary).is_empty():
			parts.append("seals the peace with a marriage")
		t["text"] = "%s %s to %s" % [who, ", ".join(parts), to]
	return t


func _make_treaty(day: int) -> String:
	return _conclude(day, propose_terms())


## Ends the war with `terms` (from propose_terms(), possibly edited by a broker). Starts the truce.
func _conclude(day: int, terms: Dictionary) -> String:
	var id := enemy_id()
	var dur := day - int(war["started_day"])
	var winner := String(terms.get("winner", "draw"))
	terms["day"] = day
	var line := "Treaty of %s after %d days: %s." % [display_name(id), dur, String(terms.get("text", "peace"))]
	chronicle.append(line)
	if chronicle.size() > CHRONICLE_MAX:
		chronicle = chronicle.slice(chronicle.size() - CHRONICLE_MAX)
	tension[id] = TENSION_AFTER_WAR
	truce_until[id] = day + int(terms.get("truce_days", int(TRUCE_DAYS.x)))
	cbs[id] = []
	(_raid_days[id] as Array).clear()
	for h in (terms.get("hostages", []) as Array):
		var from := id if winner == "caldrenn" else "caldrenn"
		hostages.append({"name": String(h), "from": from, "to": "caldrenn" if winner == "caldrenn" else id, "day": day, "until": day + int(terms.get("truce_days", 180)) / 2})
	var tr := int(terms.get("tribute", 0))
	if tr > 0 and winner != "draw":
		tribute = {"to": "caldrenn" if winner == "caldrenn" else id, "amount": tr, "until": day + 180}
	terms["enemy"] = id
	terms["duration"] = dur
	last_treaty = terms.duplicate(true)
	_news(line)
	war_ended.emit(id, line)
	war = {}
	return line


## Sues for peace now on the current terms (a broker, council or the player's push). Needs MIN_WAR_DAYS.
func conclude_peace(day: int, terms := {}) -> String:
	if not is_at_war():
		return ""
	return _conclude(day, terms if not terms.is_empty() else propose_terms())


# --- player hooks (fed by scripts/realm/war_influence.gd) ------------------------------------------

func add_tension(id: String, delta: float, reason := "") -> float:
	if not tension.has(id):
		return 0.0
	tension[id] = clampf(float(tension[id]) + delta, 0.0, 100.0)
	if reason != "":
		_news(reason)
	return float(tension[id])


## Shifts the odds of the war toward Caldrenn (+) or the enemy (-), -0.5..0.5.
func add_support(delta: float) -> float:
	if not is_at_war():
		return 0.0
	war["support"] = clampf(float(war.get("support", 0.0)) + delta, -0.5, 0.5)
	return float(war["support"])


## Peace pressure (brokers, petitions) adds to weariness when judging whether to end the war.
func push_peace(delta: float) -> float:
	if not is_at_war():
		return 0.0
	war["pressure"] = clampf(float(war.get("pressure", 0.0)) + delta, -1.0, 2.0)
	return float(war["pressure"])


func ease_weariness(delta: float) -> void:
	if is_at_war():
		war["exhaustion"] = clampf(float(war["exhaustion"]) + delta, 0.0, 3.0)


func set_goal(kind: String) -> bool:
	if not is_at_war() or not (kind in ["land", "tribute", "hostages", "marriage"]):
		return false
	war["goal"] = kind
	return true


## A campaign engagement involving the player ended: its losses and the side that won feed the abstract war.
func note_engagement(player_won: bool, lost: int, killed: int, pos := Vector2.INF) -> void:
	if not is_at_war():
		return
	war["caldrenn_losses"] = int(war["caldrenn_losses"]) + lost
	war["enemy_losses"] = int(war["enemy_losses"]) + killed
	war["exhaustion"] = float(war["exhaustion"]) + float(lost) * WEARINESS_PER_LOSS * 2.0
	war["enemy_exhaustion"] = float(war["enemy_exhaustion"]) + float(killed) * WEARINESS_PER_LOSS * 2.0
	add_support(0.03 if player_won else -0.03)
	if pos != Vector2.INF:
		var best := -1
		var bd := 1e18
		var fl: Array = war["front"]
		for i in fl.size():
			var d := (fl[i]["pos"] as Vector2).distance_squared_to(pos)
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			fl[best]["control"] = clampf(float(fl[best]["control"]) + (0.08 if player_won else -0.08), 0.0, 1.0)


func guard_settlement(name: String, until_day: int) -> void:
	guarded[name] = until_day


func act_ready(act: String, day: int, cooldown: int) -> bool:
	return day - int(act_days.get(act, -9999)) >= cooldown


func note_act(act: String, day: int, text: String) -> void:
	act_days[act] = day
	act_log.append({"day": day, "act": act, "text": text})
	if act_log.size() > ACT_LOG_MAX:
		act_log = act_log.slice(act_log.size() - ACT_LOG_MAX)


# --- player involvement hooks --------------------------------------------------------

## A spot and size for main.gd to spawn a joinable battle near the player,
## using the existing raider/army squad setup (see main.gd's _spawn_raiders).
## {} when there's no war.
func battle_at_front() -> Dictionary:
	if not is_at_war():
		return {}
	var front_list: Array = war["front"]
	# The most contested region (control nearest 0.5) is where the fighting is.
	var best: Dictionary = front_list[0]
	var best_d := 1.0
	for f: Dictionary in front_list:
		var d := absf(float(f["control"]) - 0.5)
		if d < best_d:
			best_d = d
			best = f
	return {"pos": best["pos"], "name": String(best["name"]), "size": clampi(6 + int(war["battles"]) / 2, 6, 40)}


## A merchant's army-contract offer, or {} when there's no war. `day` only
## picks which good is wanted, so it's deterministic for a save/replay.
func contract_for_merchant(day: int) -> Dictionary:
	if not is_at_war():
		return {}
	var good: String = WAR_MERCHANT_GOODS[absi(hash([day, "war_contract"])) % WAR_MERCHANT_GOODS.size()]
	return {"good": good, "quantity": 6 + int(war["battles"]) % 10, "pay_mult": 1.5,
		"note": "Army quartermasters are buying up %s at %s." % [good.replace("_", " "), display_name(enemy_id())]}


## Fraction of a farm's stored crops requisitioned for the war effort this
## day (0.0 at peace). homestead.gd's daily tick can subtract
## stored_food * crop_requisition_fraction().
func crop_requisition_fraction() -> float:
	return 0.12 if is_at_war() else 0.0


# --- news & rumours ------------------------------------------------------------------

func _news(line: String) -> void:
	_news_log.append(line)
	if _news_log.size() > NEWS_MAX:
		_news_log = _news_log.slice(_news_log.size() - NEWS_MAX)


func news(limit := 6) -> Array[String]:
	var n: Array[String] = []
	var start: int = maxi(0, _news_log.size() - limit)
	for i in range(start, _news_log.size()):
		n.append(_news_log[i])
	return n


func rumours() -> Array[String]:
	var out: Array[String] = []
	if is_at_war():
		var id := enemy_id()
		out.append("War rages against %s over %s." % [display_name(id), String((war.get("cb", {}) as Dictionary).get("label", String(CB_KINDS.get(String((war.get("cb", {}) as Dictionary).get("kind", "incident")), {}).get("label", "old grievances"))).to_lower())])
		for f: Dictionary in (war.get("front", []) as Array):
			out.append("The front near %s is shifting." % String(f["name"]))
		if exhaustion() > 0.7:
			out.append("The crown's levies are war-weary; talk of peace grows louder.")
	else:
		for id: String in WAR_CANDIDATES:
			if under_truce(id):
				out.append("The truce with %s holds for another %d days." % [display_name(id), truce_days_left(id)])
			for c: Dictionary in casus_belli(id):
				out.append(String(c["text"]))
			if float(tension[id]) > 50.0:
				out.append("Tempers rise at the border with %s." % display_name(id))
	for line: String in chronicle:
		out.append(line)
	return out


# --- serialisation ---------------------------------------------------------------

func serialize() -> Dictionary:
	return {"tension": tension.duplicate(true), "war": _enc_war(war), "chronicle": chronicle.duplicate(true),
		"news": _news_log.duplicate(true), "cbs": cbs.duplicate(true), "truce": truce_until.duplicate(true),
		"hostages": hostages.duplicate(true), "treaty": last_treaty.duplicate(true), "raid_days": _raid_days.duplicate(true),
		"acts": act_days.duplicate(true), "act_log": act_log.duplicate(true), "guarded": guarded.duplicate(true),
		"tribute": tribute.duplicate(true), "rift_days": _rift_days, "wars_total": wars_total, "day": _day}


func deserialize(d: Dictionary) -> void:
	tension.clear()
	cbs.clear()
	_raid_days.clear()
	for id: String in WAR_CANDIDATES:
		tension[id] = 0.0
		cbs[id] = []
		_raid_days[id] = []
	for id: String in (d.get("tension", {}) as Dictionary):
		tension[id] = float(d["tension"][id])
	for id: String in (d.get("cbs", {}) as Dictionary):
		cbs[id] = (d["cbs"][id] as Array).duplicate(true)
		for c: Dictionary in (cbs[id] as Array):
			_ints(c, ["day", "expires"])
	for id: String in (d.get("raid_days", {}) as Dictionary):
		_raid_days[id] = (d["raid_days"][id] as Array).map(func(x: Variant) -> int: return int(x))
	truce_until = {}
	for id: String in (d.get("truce", {}) as Dictionary):
		truce_until[id] = int(d["truce"][id])
	hostages = (d.get("hostages", []) as Array).duplicate(true)
	for h: Dictionary in hostages:
		_ints(h, ["day", "until"])
	last_treaty = (d.get("treaty", {}) as Dictionary).duplicate(true)
	_ints(last_treaty, ["day", "duration", "tribute", "truce_days"])
	act_days = {}
	for k: String in (d.get("acts", {}) as Dictionary):
		act_days[k] = int(d["acts"][k])
	act_log = (d.get("act_log", []) as Array).duplicate(true)
	for a: Dictionary in act_log:
		_ints(a, ["day"])
	guarded = {}
	for k: String in (d.get("guarded", {}) as Dictionary):
		guarded[k] = int(d["guarded"][k])
	tribute = (d.get("tribute", {}) as Dictionary).duplicate(true)
	_ints(tribute, ["amount", "until"])
	_rift_days = int(d.get("rift_days", 0))
	wars_total = int(d.get("wars_total", 0))
	_day = int(d.get("day", 0))
	war = _dec_war(d.get("war", {}))
	chronicle.assign(d.get("chronicle", []))
	_news_log.assign(d.get("news", []))


static func _ints(d: Dictionary, keys: Array) -> void:
	for k: String in keys:
		if d.has(k):
			d[k] = int(d[k])


static func _enc_war(w: Dictionary) -> Dictionary:
	if w.is_empty():
		return {}
	var front_out := []
	for f: Dictionary in (w["front"] as Array):
		var p: Vector2 = f["pos"]
		front_out.append({"name": f["name"], "x": p.x, "y": p.y, "control": f["control"]})
	var o := (w as Dictionary).duplicate(true)
	o["front"] = front_out
	return o


static func _dec_war(w: Variant) -> Dictionary:
	if not (w is Dictionary) or (w as Dictionary).is_empty():
		return {}
	var wd: Dictionary = w
	var front_out: Array[Dictionary] = []
	for f: Dictionary in (wd.get("front", []) as Array):
		front_out.append({"name": String(f["name"]), "pos": Vector2(float(f["x"]), float(f["y"])), "control": float(f["control"])})
	var o := wd.duplicate(true)
	o["front"] = front_out
	for k: String in ["started_day", "caldrenn_losses", "enemy_losses", "battles"]:
		o[k] = int(wd.get(k, 0))
	for k: String in ["exhaustion", "enemy_exhaustion", "support", "pressure"]:
		o[k] = float(wd.get(k, 0.0))
	o["pace"] = float(wd.get("pace", 1.0))
	o["enemy"] = String(wd["enemy"])
	o["goal"] = String(wd.get("goal", "tribute"))
	o["aggressor"] = String(wd.get("aggressor", "caldrenn"))
	o["cb"] = (wd.get("cb", {}) as Dictionary).duplicate(true)
	_ints(o["cb"], ["day", "expires"])
	return o
