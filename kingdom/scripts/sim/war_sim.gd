extends RefCounted
## War between Caldrenn and one of its harder neighbours (data/world/nations.json:
## Ongur Khanate "wary", Urrokai Clanlands "hostile" -- the two most plausible
## sources of an actual war, per each nation's relations to Caldrenn).
## docs/RISING_ASHES_LIFE_SIM_DESIGN.md, "Living world simulation": "War
## reaches ordinary people: prices, horses, recruitment, contracts, refugees,
## danger, fortified borders, crime."
##
## Pure data (RefCounted, serialisable). A diplomatic tension meter per
## candidate nation rises from border incidents, noble feuds
## (nobility.gd's feuds()) and Rift crises, and decays in peacetime. Crossing
## a threshold declares war: a front line of 2-3 border regions (frontier
## towns and forts, WorldGen.settlements/sites), daily abstract battles with
## casualties, villages near the front raided, and a treaty once both sides
## are exhausted.
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

const TENSION_WAR_THRESHOLD := 80.0
const TENSION_PEACE_DECAY := 0.6
const TENSION_BORDER_INCIDENT := Vector2(0.2, 1.2)
const TENSION_PER_FEUD := 0.35
const TENSION_RIFT_MULT := 4.0
const TENSION_AFTER_WAR := 15.0

const FRONT_REGIONS_MIN := 2
const FRONT_REGIONS_MAX := 3
const RAID_CHANCE := 0.22
const EXHAUSTION_PER_BATTLE := Vector2(0.05, 0.12)
const TREATY_EXHAUSTION := 1.0
const MIN_WAR_DAYS := 8
const WAR_MERCHANT_GOODS := ["iron_sword", "iron_helm", "leather_jerkin"]
const NEWS_MAX := 30
const CHRONICLE_MAX := 20

static var _nations: Dictionary = {}

## Diplomatic tension 0..100 per candidate nation id.
var tension: Dictionary = {}
## {} when at peace, else {enemy, started_day, front: [{name, pos, control}],
## exhaustion, caldrenn_losses, enemy_losses, battles}.
var war: Dictionary = {}
## Short historical record of how wars ended (treaty lines), newest last.
var chronicle: Array[String] = []
## {settlement_name, day}: the villages raided on the most recent tick_day().
var _last_raids: Array[Dictionary] = []
var _news_log: Array[String] = []
var _rng := RandomNumberGenerator.new()


func _init(seed_value := 90210) -> void:
	_rng.seed = seed_value
	for id: String in WAR_CANDIDATES:
		tension[id] = 0.0


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


# --- state -----------------------------------------------------------------------

func is_at_war() -> bool:
	return not war.is_empty()


func enemy_id() -> String:
	return String(war.get("enemy", ""))


func front() -> Array:
	return (war.get("front", []) as Array).duplicate(true)


func exhaustion() -> float:
	return float(war.get("exhaustion", 0.0))


func tension_of(id: String) -> float:
	return float(tension.get(id, 0.0))


func casualties() -> Dictionary:
	if war.is_empty():
		return {"caldrenn": 0, "enemy": 0}
	return {"caldrenn": int(war.get("caldrenn_losses", 0)), "enemy": int(war.get("enemy_losses", 0))}


## The villages raided on the most recently ticked day: [{settlement_name, day}].
## The caller (life.gd's hook) uses this to dock lordship loyalty and mark
## refugees for the nearest safe town.
func raided_today() -> Array[Dictionary]:
	return _last_raids.duplicate(true)


# --- daily tick --------------------------------------------------------------------

## Advances the war (or the peacetime tension leading to one) by one day.
## Returns lines for Game.say, same convention as lordship.daily_tick().
func tick_day(day: int, ctx: Dictionary) -> Array[String]:
	_last_raids.clear()
	if is_at_war():
		return _tick_war(day, ctx)
	_tick_tension(day, ctx)
	var candidate := _ready_for_war()
	if candidate != "":
		return [_declare_war(candidate, day)]
	return []


func _tick_tension(day: int, ctx: Dictionary) -> void:
	var feud_count := int(ctx.get("feud_count", 0))
	var rift := float(ctx.get("rift_instability", 0.0))
	for id: String in WAR_CANDIDATES:
		var weight: float = float(BORDER_WEIGHT.get(_caldrenn_stance(id), 0.8))
		var delta := _rng.randf_range(TENSION_BORDER_INCIDENT.x, TENSION_BORDER_INCIDENT.y) * weight
		delta += feud_count * TENSION_PER_FEUD
		delta += rift * TENSION_RIFT_MULT
		tension[id] = clampf(float(tension[id]) + delta - TENSION_PEACE_DECAY, 0.0, 100.0)


func _ready_for_war() -> String:
	var best_id := ""
	var best_t := -1.0
	for id: String in WAR_CANDIDATES:
		var t: float = float(tension[id])
		if t >= TENSION_WAR_THRESHOLD and t > best_t:
			best_t = t
			best_id = id
	return best_id


func _declare_war(id: String, day: int) -> String:
	var front_regions := _build_front()
	war = {"enemy": id, "started_day": day, "front": front_regions, "exhaustion": 0.0,
		"caldrenn_losses": 0, "enemy_losses": 0, "battles": 0}
	tension[id] = 40.0
	var line := "War: Caldrenn takes up arms against %s." % display_name(id)
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
	war["battles"] = int(war["battles"]) + 1
	out.append(_resolve_battle())
	out.append_array(_raid_front_villages(day))
	war["exhaustion"] = clampf(float(war["exhaustion"]) + _rng.randf_range(EXHAUSTION_PER_BATTLE.x, EXHAUSTION_PER_BATTLE.y), 0.0, 3.0)
	if day - int(war["started_day"]) >= MIN_WAR_DAYS and float(war["exhaustion"]) >= TREATY_EXHAUSTION:
		out.append(_make_treaty(day))
	return out


func _resolve_battle() -> String:
	var front_list: Array = war["front"]
	var idx := _rng.randi() % front_list.size()
	var f: Dictionary = front_list[idx]
	var caldrenn_losses := _rng.randi_range(3, 16)
	var enemy_losses := _rng.randi_range(3, 16)
	war["caldrenn_losses"] = int(war["caldrenn_losses"]) + caldrenn_losses
	war["enemy_losses"] = int(war["enemy_losses"]) + enemy_losses
	f["control"] = clampf(float(f["control"]) + float(enemy_losses - caldrenn_losses) * 0.01, 0.0, 1.0)
	front_list[idx] = f
	var text := "Battle at %s: %d Caldrenn dead, %d of %s fall." % [String(f["name"]), caldrenn_losses, enemy_losses, display_name(enemy_id())]
	_news(text)
	return text


## Villages near the front lose loyalty and send refugees (see raided_today()).
func _raid_front_villages(day: int) -> Array[String]:
	var out: Array[String] = []
	for f: Dictionary in (war["front"] as Array):
		if _rng.randf() > RAID_CHANCE:
			continue
		var near := WorldGen.nearest_settlement(f["pos"])
		if near.is_empty():
			continue
		var name := String(near["name"])
		_last_raids.append({"settlement_name": name, "day": day})
		var line := "Raiders strike near %s; refugees flee toward the safer towns." % name
		out.append(line)
		_news(line)
	return out


func _make_treaty(day: int) -> String:
	var id := enemy_id()
	var caldrenn_won := int(war["enemy_losses"]) >= int(war["caldrenn_losses"])
	var line: String
	if caldrenn_won:
		line = "Treaty of %s: %s cedes its border forts and pays tribute to the crown." % [display_name(id), display_name(id)]
	else:
		line = "Treaty of %s: Caldrenn pays tribute to buy the peace." % display_name(id)
	chronicle.append(line)
	if chronicle.size() > CHRONICLE_MAX:
		chronicle = chronicle.slice(chronicle.size() - CHRONICLE_MAX)
	tension[id] = TENSION_AFTER_WAR
	_news(line)
	war_ended.emit(id, line)
	war = {}
	return line


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
		out.append("War rages against %s." % display_name(id))
		for f: Dictionary in (war.get("front", []) as Array):
			out.append("The front near %s is shifting." % String(f["name"]))
	else:
		for id: String in WAR_CANDIDATES:
			if float(tension[id]) > 50.0:
				out.append("Tempers rise at the border with %s." % display_name(id))
	for line: String in chronicle:
		out.append(line)
	return out


# --- serialisation ---------------------------------------------------------------

func serialize() -> Dictionary:
	return {"tension": tension.duplicate(true), "war": _enc_war(war), "chronicle": chronicle.duplicate(true),
		"news": _news_log.duplicate(true)}


func deserialize(d: Dictionary) -> void:
	tension.clear()
	for id: String in WAR_CANDIDATES:
		tension[id] = 0.0
	for id: String in (d.get("tension", {}) as Dictionary):
		tension[id] = float(d["tension"][id])
	war = _dec_war(d.get("war", {}))
	chronicle.assign(d.get("chronicle", []))
	_news_log.assign(d.get("news", []))


static func _enc_war(w: Dictionary) -> Dictionary:
	if w.is_empty():
		return {}
	var front_out := []
	for f: Dictionary in (w["front"] as Array):
		var p: Vector2 = f["pos"]
		front_out.append({"name": f["name"], "x": p.x, "y": p.y, "control": f["control"]})
	return {"enemy": w["enemy"], "started_day": w["started_day"], "front": front_out,
		"exhaustion": w["exhaustion"], "caldrenn_losses": w["caldrenn_losses"],
		"enemy_losses": w["enemy_losses"], "battles": w["battles"]}


static func _dec_war(w: Variant) -> Dictionary:
	if not (w is Dictionary) or (w as Dictionary).is_empty():
		return {}
	var wd: Dictionary = w
	var front_out: Array[Dictionary] = []
	for f: Dictionary in (wd.get("front", []) as Array):
		front_out.append({"name": String(f["name"]), "pos": Vector2(float(f["x"]), float(f["y"])), "control": float(f["control"])})
	return {"enemy": String(wd["enemy"]), "started_day": int(wd["started_day"]), "front": front_out,
		"exhaustion": float(wd["exhaustion"]), "caldrenn_losses": int(wd["caldrenn_losses"]),
		"enemy_losses": int(wd["enemy_losses"]), "battles": int(wd["battles"])}
