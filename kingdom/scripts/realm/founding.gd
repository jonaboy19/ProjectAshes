extends "res://scripts/realm/realm_module.gd"
## Settlement founding as one loop (Living World §6, LW-5.1 to LW-5.3, docs/design/LIVING_WORLD_SANDBOX.md Stage 5).
## Player and NPC founders use the same calls. The module owns no population, no buildings and no gold of its own: it reads and drives
## camps.gd / civilization.gd / migration.gd / recruitment.gd / farming.gd / businesses.gd / build_kit.gd and adds what they lack.
##
##   1. evaluate_site(pos)          ten scores in plain words (water, food, resources, defence, trade, legality, political risk,
##                                  safety, climate, room) with the legal status of the ground
##   2. LandLaw (land_law.gd)       private, leased, granted, town, royal domain, religious, disputed, wilderness, frontier, enemy,
##                                  protected. Own, build and govern are three separate flags on the founding (`rights`).
##   3. escalation                  an illegal build gathers heat from its visibility (traffic, size, roads, rumours):
##                                  discovered, investigated, warned, political intervention (legalise for dues / fine / submit),
##                                  enforcement, military response. Weak or warring realms delay; corrupt governors take bribes.
##   4. stages                      scouting, occupation, survival, production, recruitment, infrastructure, government,
##                                  recognition (a Stage 6 petition stub). Each stage opens on real facts, never on a timer alone.
##      scale classes               camp, hamlet, village, town, city, regional stronghold from population + services + infrastructure.
##   5. residents                   pull and push come from civilization.gd; jobless residents leave, savings open businesses.
##   6. problems                    stress per domain (food, treasury, crime, corruption, epidemic, desertion, raids, succession).
##   7. hidden valley               deliveries raise exposure; a public trade post takes the traffic; at 60 the Crown knows.
##   8. NPC founders                begin(pos, name, "npc") runs the identical flow; tick_week starts them now and then.
## Cap: the player founds at most BuildKit.MAX_GRIDS (3) settlements. Cost: tick_day runs in chunks of CHUNK foundings, every step is
## closed form in `n` days (catch_up passes n = days), tick_week is O(foundings). Saves ~1 KB per founding, at most MAX_FOUNDINGS.

const LandLaw := preload("res://scripts/realm/land_law.gd")
const LandClaim := preload("res://scripts/realm/land_claim.gd")
const BuildKit := preload("res://scripts/realm/build_kit.gd")
const Events := preload("res://scripts/realm/events.gd")
const Hv := preload("res://scripts/world/hidden_valley.gd")

const STAGES := ["scouting", "occupation", "survival", "production", "recruitment", "infrastructure", "government", "recognition"]
const STAGE_WORDS := ["Scouting the ground", "Occupying the site", "Surviving: shelter, water, storage", "Producing food", "Recruiting settlers",
	"Building permanent works", "Setting up local government", "Seeking recognition"]
const ESC := ["unseen", "discovered", "investigated", "warned", "intervention", "enforcement", "military"]
const ESC_WORDS := ["Nobody has noticed your works.", "Surveyors have noticed new buildings.", "An official is asking who allowed this.",
	"You have been warned in writing to stop or regularise.", "The authorities demand a settlement.", "Enforcement: your works are being torn down.",
	"A military force has been sent against you."]
const ESC_AT := [0.0, 3.0, 10.0, 20.0, 32.0, 48.0, 70.0]
const PEND_DAYS := 12
const MIL_REPEAT := 60
const ROLES := ["reeve", "captain", "steward"]
const SCALES := ["camp", "hamlet", "village", "town", "city"]
const SCALE_POP := [0, 9, 35, 110, 380]
const SCALE_SERVICES := [0, 3, 5, 7, 9]
const SCALE_INFRA := [0, 0, 2, 4, 7]
const STRONGHOLD := {"pop": 150, "walls": 1, "patrol": 0.15}
const SERVICES := ["shelter", "water", "storage", "food", "trade", "defence", "learning", "roads", "government", "crafts"]
const PROBLEMS := ["food_shortage", "treasury_crisis", "crime", "corruption", "epidemic", "desertion", "raid", "succession"]
const PROBLEM_WORDS := {
	"food_shortage": "Food shortage: there is not enough grain for everyone.",
	"treasury_crisis": "Treasury crisis: the coffers cannot cover wages and upkeep.",
	"crime": "A crime wave: thefts and brawls and no one to keep order.",
	"corruption": "Corruption: an official is skimming the treasury.",
	"epidemic": "Epidemic: sickness spreads through crowded huts.",
	"desertion": "Desertion: settlers are slipping away in the night.",
	"raid": "Raiders have struck the settlement.",
	"succession": "Succession: an office is empty and rivals circle it.",
}
const SCOUT_DAYS := 3
const AUTO_APPOINT_DAYS := 21
const MIN_POP_RECRUITED := 20
const KNOWN := 60.0                      # hidden valley exposure at which the realm learns of it
const DELIVERY_FEEDS := 8                # people one delivery of grain feeds for a week
const MAX_FOUNDINGS := 24
const NPC_MAX := 3
const NPC_P := 0.05
const NPC_FROM := 60
const NPC_GAP := 45
const CHUNK := 2
const HIST_MAX := 14
const TITLE_COST := {"lease": 40.0, "purchase": 150.0, "grant": 90.0}
const BIZ_PER_FOUNDING := 4
const BIZ_DEMAND := [["shop", "", 40, "merchant"], ["workshop", "bakery", 70, "baker"], ["inn", "", 100, "innkeeper"], ["caravan", "", 160, "trader"]]

var _f: Dictionary = {}               # int id -> founding record
var _next := 1
var _zones: Array = []                # [x, z, r, status, holder]
var _corrupt: Dictionary = {}         # str(sid) -> 0..1 override of how corrupt the governor there is
var _day := 0
var _war := false
var _npc_day := -999
var _npc_left := 0                    # weeks of site search still to do (transient)
var _npc_best := Vector2.ZERO
var _npc_bs := -1.0
var _waves_week := 0                  # recruitment waves sent in this weekly tick (transient)
var stats := {"begun": 0, "ended": 0, "promoted": 0, "problems": 0, "escalations": 0, "bribes": 0, "legalised": 0, "razed": 0, "npc_begun": 0}
var prof_on := false
var prof: Dictionary = {}


# ------------------------------------------------------------------ plumbing

func _rng(tag: String, d: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, d, str(id)])
	return r


func _mod(n: String) -> RefCounted:
	return hub.mod(n) if hub != null else null


func _civ() -> RefCounted:
	return _mod("civilization")


func _call(m: String, fn: String, args: Array = [], dflt: Variant = null) -> Variant:
	var o := _mod(m)
	if o == null or not o.has_method(fn):
		return dflt
	return o.callv(fn, args)


func _ev(kind: String, f: Dictionary, cause: String, outcome: String, weight := 2) -> void:
	Events.log_to(hub, kind, String(f["pid"]), [], cause, outcome, weight)


func _say(f: Dictionary, text: String, msgs: Array) -> void:
	if String(f["who"]) == "player":
		msgs.append(text)


func _hist(f: Dictionary, text: String) -> void:
	var h: Array = f["hist"]
	h.append("d%d %s" % [_day, text])
	if h.size() > HIST_MAX:
		h.remove_at(0)


func _pos(f: Dictionary) -> Vector2:
	return Vector2(float(f["pos"][0]), float(f["pos"][1]))


func _place(f: Dictionary) -> Dictionary:
	var civ := _civ()
	if civ == null or String(f["node"]) == "":
		return {}
	return civ.call("place", String(f["node"]))


func _pop(f: Dictionary) -> int:
	var civ := _civ()
	return int(civ.call("population", String(f["node"]))) if civ != null and String(f["node"]) != "" else 0


func _static_place(f: Dictionary) -> Dictionary:
	var civ := _civ()
	var sid := int(f["land"].get("sid", -1))
	return civ.call("place", "s%d" % sid) if civ != null and sid >= 0 else {}


func _pf(key: String, t0: int) -> int:
	if prof_on:
		var t1 := Time.get_ticks_usec()
		var a: Array = prof.get(key, [0, 0])
		a[0] = int(a[0]) + 1
		a[1] = int(a[1]) + (t1 - t0)
		prof[key] = a
		return t1
	return 0


# ------------------------------------------------------------------ queries

func ids(active_only := false) -> Array:
	var out: Array = []
	var k := _f.keys()
	k.sort()
	for i in k:
		if not active_only or int((_f[i] as Dictionary)["end"]) < 0:
			out.append(i)
	return out


func get_founding(fid: int) -> Dictionary:
	return _f.get(fid, {})


func active_count(who := "") -> int:
	var n := 0
	for f: Dictionary in _f.values():
		if int(f["end"]) < 0 and (who == "" or String(f["who"]) == who):
			n += 1
	return n


func stage_name(fid: int) -> String:
	var f: Dictionary = _f.get(fid, {})
	return "" if f.is_empty() else String(STAGES[int(f["st"])])


func land_status_at(pos: Vector2) -> Dictionary:
	var s := LandLaw.status_at(pos, _zones, _mod("land"))
	s["rights"] = LandLaw.rights_of(String(s["status"]))
	return s


func corruption_at(sid: int) -> float:
	var k := str(sid)
	if _corrupt.has(k):
		return float(_corrupt[k])
	var base := float(absi(hash([WorldSim.SEED, "corrupt", sid])) % 100) / 100.0
	var q := 0.5
	var gv := _mod("governance")
	if gv != null and gv.has_method("leader_quality"):
		q = float(gv.call("leader_quality", sid))
	return clampf(0.6 * base + 0.4 * (1.0 - q), 0.0, 1.0)


func force_corruption(sid: int, v: float) -> void:
	_corrupt[str(sid)] = clampf(v, 0.0, 1.0)


# ------------------------------------------------------------------ 1. site evaluation

static func _band(v: float, words: Array) -> String:
	return String(words[clampi(int(v * float(words.size())), 0, words.size() - 1)])


## Ten scores in 0..1 (higher is better; political_risk is shown as the risk itself) and a plain-words line for each.
func evaluate_site(pos: Vector2) -> Dictionary:
	var cm := _mod("camps")
	var br: Dictionary = {"water": 0.0, "wood": 0.0, "defence": 0.0, "road": 0.0, "flooded": WorldGen.is_water(pos.x, pos.y)}
	if cm != null:
		br = cm.call("site_breakdown", pos)
	var inv := Hv.in_valley(pos)
	var st := land_status_at(pos)
	var rights: Dictionary = st["rights"]
	var ns_dist := float(st.get("dist", 9999.0))
	# water
	var water := maxf(float(br["water"]), 0.9 if inv else 0.0)
	# food: level ground, water to irrigate, cleared land; the vale's soil is black and deep
	var h0: float = WorldGen.height(pos.x, pos.y)
	var dh := 0.0
	for o in [Vector2(40, 0), Vector2(-40, 0), Vector2(0, 40), Vector2(0, -40)]:
		dh = maxf(dh, absf(WorldGen.height(pos.x + o.x, pos.y + o.y) - h0))
	var flat := 1.0 - clampf(dh / 10.0, 0.0, 1.0)
	var food := clampf(0.15 + 0.4 * flat + 0.25 * water + 0.1 * (1.0 - float(br["wood"])) + 2.0 * Hv.site_bonus(pos), 0.0, 1.0)
	# resources: timber on the spot, finds (ore, crystal) within reach
	var finds := 0.0
	var civ := _civ()
	if civ != null:
		for fd: Dictionary in civ.call("finds"):
			var fp: Vector2 = fd["pos"] if fd["pos"] is Vector2 else Vector2(float(fd["pos"][0]), float(fd["pos"][1]))
			if fp.distance_to(pos) < 700.0:
				finds += float(fd.get("rich", 0.5)) * 0.5
	var resources := clampf(0.6 * float(br["wood"]) + 0.4 * minf(1.0, finds) + (0.25 if inv else 0.0), 0.0, 1.0)
	# defence: high ground, ward-stones, the vale's rim
	var cov := 0.0
	if civ != null:
		cov = float(civ.call("_coverage", pos))
	var defence := clampf(float(br["defence"]) + 0.4 * cov + (0.5 if inv else 0.0), 0.0, 1.0)
	# trade: roads and a market town an easy walk away
	var near_t := clampf(1.0 - absf(ns_dist - 600.0) / 1500.0, 0.0, 1.0)
	var trade := clampf(0.6 * float(br["road"]) + 0.4 * near_t, 0.0, 1.0)
	# legality and political risk
	var legality := 0.0
	if bool(rights["build"]):
		legality = 1.0 if String(st["status"]) in ["leased", "granted"] else 0.75
	elif not (rights["titles"] as Array).is_empty():
		legality = 0.3
	var risk := clampf(0.6 * (1.0 - legality) * clampf(float(rights["auth"]), 0.0, 1.5) / 1.0 + 0.4 * clampf(1.0 - ns_dist / 1500.0, 0.0, 1.0), 0.0, 1.0)
	if inv:
		risk = minf(risk, 0.15)
	# safety: monsters, rifts, runestones
	var danger := 0.0
	var eco := _mod("ecology")
	if eco != null and eco.has_method("danger_at"):
		danger = float((eco.call("danger_at", pos) as Dictionary).get("total", 0.0)) / 100.0
	var rift := LandLaw.near_rift(pos)
	var rift_t := 0.0 if rift == INF else clampf(1.0 - rift / 900.0, 0.0, 1.0)
	var safety := clampf(1.0 - 0.6 * minf(1.0, danger * 2.0) - 0.5 * rift_t + 0.3 * cov + (0.2 if inv else 0.0), 0.0, 1.0)
	# climate: height and the far north bite
	var climate := 1.0 - clampf(clampf((h0 - 60.0) / 140.0, 0.0, 1.0) * 0.6 + clampf(absf(pos.y) / 6000.0, 0.0, 1.0) * 0.3, 0.0, 1.0)
	# expansion room: level dry ground in a ring, clear of other settlements
	var ok := 0
	for k in 8:
		var a := TAU * float(k) / 8.0
		var q := pos + Vector2(cos(a), sin(a)) * 90.0
		if WorldGen.is_water(q.x, q.y):
			continue
		if absf(WorldGen.height(q.x, q.y) - h0) > 8.0:
			continue
		ok += 1
	var room := float(ok) / 8.0
	var scores := {"water": water, "food": food, "resources": resources, "defence": defence, "trade": trade, "legality": legality,
		"political_risk": risk, "safety": safety, "climate": climate, "room": room}
	var overall := 0.17 * water + 0.15 * food + 0.08 * resources + 0.12 * defence + 0.10 * trade + 0.12 * legality + 0.08 * (1.0 - risk) \
		+ 0.12 * safety + 0.03 * climate + 0.03 * room
	if bool(br["flooded"]):
		overall = 0.0
	var lines: Array = [
		"Water: " + _band(water, ["no fresh water within reach", "only a distant or seasonal source", "a workable stream or spring nearby", "a good stream close by", "clear water at the doorstep"]),
		"Food: " + _band(food, ["thin, stony ground", "poor soil: farms would struggle", "soil that will feed a small farm", "good tilth and room for fields", "rich black earth"]),
		"Resources: " + _band(resources, ["nothing worth taking nearby", "a little timber", "timber and some stone", "timber and a promising find", "rich timber and ore"]),
		"Defence: " + _band(defence, ["open ground, easy to raid", "few natural defences", "some high ground", "a defensible rise", "a natural fortress"]),
		"Trade: " + _band(trade, ["cut off from every road", "far from the roads", "a short way from the trade roads", "close to a busy road", "on a crossing of trade"]),
		"Legality: " + String(st["words"]),
		"Political risk: " + _band(risk, ["the realm will not notice you", "few eyes on you", "watchful neighbours", "the lords will take an interest", "you stand under the lords' noses"]),
		"Safety: " + _band(safety, ["monsters and rifts make it deadly", "dangerous: beasts roam nearby", "some beasts and strays about", "mostly quiet", "safe, with ward-stones near"]),
		"Climate: " + _band(climate, ["bitter, high and windswept", "harsh winters", "fair seasons", "mild seasons", "gentle and mild"]),
		"Room to grow: " + _band(room, ["hemmed in", "little level ground", "room for a village", "room for a town", "room to grow into a city"]),
	]
	var blocked := LandClaim.block_reason(pos)
	var verdict := _band(overall, ["Nobody should settle here.", "A hard place to live.", "A workable site with trade-offs.", "A good site.", "An excellent site."])
	var camp_score := float(cm.call("score_site", pos)) if cm != null else 0.0
	var out := {"pos": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1)], "camp": snappedf(camp_score, 0.001), "scores": {}, "overall": snappedf(overall, 0.001), "lines": lines, "verdict": verdict,
		"blocked": blocked, "status": String(st["status"]), "holder": String(st["holder"]), "sid": int(st.get("sid", -1)), "near": String(st.get("near", "")),
		"rights": rights, "hidden": inv, "legal_words": String(st["words"])}
	for k: String in scores:
		(out["scores"] as Dictionary)[k] = snappedf(float(scores[k]), 0.001)
	return out


# ------------------------------------------------------------------ begin, occupy, abandon

func _new_record(id: int, pos: Vector2, fname: String, who: String, founder: String, ev: Dictionary) -> Dictionary:
	var reg := _mod("registry")
	var rights: Dictionary = ev["rights"]
	return {"id": id, "pid": reg.call("ref", "hd:f%d" % id) if reg != null else "fd:%d" % id, "who": who, "fn": founder, "name": fname,
		"pos": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1)], "st": 0, "sd": _day, "born": _day, "end": -1, "why": "",
		"node": "", "gid": 0, "cid": -1, "parcel": "", "ev": ev["scores"].duplicate(), "overall": float(ev["overall"]),
		"land": {"status": ev["status"], "holder": ev["holder"], "sid": ev["sid"], "near": ev["near"]},
		"rights": {"own": false, "build": false, "govern": false}, "base": {"own": bool(rights["own"]), "build": bool(rights["build"]), "govern": false},
		"acts": [], "dues": 0.0, "arrears": 0.0, "vassal": "",
		"esc": {"step": 0, "heat": 0.0, "vis": 0.0, "pend": "", "pday": -1, "terms": {}, "bribes": 0, "fines": 0, "delay": 0.0, "outcome": "", "mil": -9999, "rum": 0.0},
		"off": {}, "gone": {}, "hist": [], "stress": {}, "probs": [], "pn": {}, "sc": 0, "sc_up": 0.0, "sc_dn": 0.0, "strong": false,
		"hid": bool(ev["hidden"]), "expo": 0.0, "dw": 0.0, "dt": 0, "post": [], "post_day": -1, "sav": 0.0, "biz": [], "pet": {},
		"zero": 0.0, "wave": -9999, "gov_day": -1, "farm_n": 0}


## Starts a founding at `pos`: scouting begins. who "player" (capped at BuildKit.MAX_GRIDS) or "npc". Returns {ok, fid, reason, site}.
func begin(pos: Vector2, fname := "", who := "player", founder := "") -> Dictionary:
	if who == "player" and active_count("player") >= BuildKit.MAX_GRIDS:
		return {"ok": false, "fid": 0, "reason": "You can found at most %d settlements." % BuildKit.MAX_GRIDS}
	if who != "player" and active_count("npc") >= NPC_MAX:
		return {"ok": false, "fid": 0, "reason": "Too many founders are already on the road."}
	if _f.size() >= MAX_FOUNDINGS:
		var gone: Array = []
		for k: int in ids():
			if int((_f[k] as Dictionary)["end"]) >= 0:
				gone.append(k)
		if gone.is_empty():
			return {"ok": false, "fid": 0, "reason": "The realm has no room for another founding."}
		_f.erase(gone[0])
	for f2: Dictionary in _f.values():
		if int(f2["end"]) < 0 and _pos(f2).distance_to(pos) < 120.0:
			return {"ok": false, "fid": 0, "reason": "Another founding is already here."}
	var ev := evaluate_site(pos)
	if String(ev["blocked"]) != "":
		return {"ok": false, "fid": 0, "reason": String(ev["blocked"]), "site": ev}
	var cmod := _mod("camps")
	if float(ev["overall"]) < 0.2 or (cmod != null and float(ev["camp"]) < float(cmod.get("MIN_CAMP_SCORE"))):
		return {"ok": false, "fid": 0, "reason": "The ground is too poor to settle (little water, timber, high ground or road): " + String(ev["verdict"]), "site": ev}
	var id := _next
	_next += 1
	var nm := fname if fname != "" else _site_name(id, pos)
	var fo := founder if founder != "" else ("You" if who == "player" else "a band of settlers")
	_f[id] = _new_record(id, pos, nm, who, fo, ev)
	stats["begun"] = int(stats["begun"]) + 1
	ScatterExclusion.sync_founded(_f.values())   # terrain_backend=terrain3d: keep the scatter forest off the new site
	if who != "player":
		stats["npc_begun"] = int(stats["npc_begun"]) + 1
	var f: Dictionary = _f[id]
	_hist(f, "scouts set out for %s" % nm)
	_ev("founding", f, "scouting", "%s scouts %s" % [fo, nm], 2)
	return {"ok": true, "fid": id, "reason": "", "site": ev}


func _site_name(id: int, pos: Vector2) -> String:
	var a: Array = ["Ash", "Fern", "Stone", "Elder", "Amber", "Gale", "Thorn", "Mist", "Wolf", "Sun"]
	var b: Array = ["stead", "hollow", "rest", "wick", "haven", "field", "mere", "ford"]
	var r := _rng("name", id, int(pos.x * 3.0 + pos.y))
	return "%s%s" % [a[r.randi() % a.size()], b[r.randi() % b.size()]]


## Raises the first camp (scouting must be done). Player claims also open a build-kit grid.
func occupy(fid: int) -> Dictionary:
	var f: Dictionary = _f.get(fid, {})
	if f.is_empty() or int(f["end"]) >= 0:
		return {"ok": false, "reason": "There is no such founding."}
	if String(f["node"]) != "":
		return {"ok": true, "reason": ""}
	if int(f["st"]) < 1:
		return {"ok": false, "reason": "Scouting is not finished: %s" % ", ".join(blockers(fid))}
	var civ := _civ()
	if civ == null:
		return {"ok": false, "reason": "No civilization."}
	var pos := _pos(f)
	var why := LandClaim.block_reason(pos)
	if why != "":
		return {"ok": false, "reason": why}
	var bk := _mod("build_kit")
	var player := String(f["who"]) == "player"
	if player and bk != null and (bk.get("grids") as Dictionary).size() >= BuildKit.MAX_GRIDS:
		return {"ok": false, "reason": "You can found at most %d settlements." % BuildKit.MAX_GRIDS}
	var node: String = civ.call("found_place", pos, String(f["name"]), "%s and their settlers" % String(f["fn"]), _day, 8)
	if node == "":
		return {"ok": false, "reason": "There is no room for a camp here (too many camps, or too close to another)."}
	f["node"] = node
	f["cid"] = int((civ.call("place", node) as Dictionary).get("camp", -1))
	_refresh_rights(f)
	var land: Dictionary = f["land"]
	if bool((f["base"] as Dictionary)["own"]) and String(land["status"]) == "wilderness":
		(f["acts"] as Array).append("occupation")
	_refresh_rights(f)
	if player and bk != null:
		var kind := "squat"
		if bool((f["rights"] as Dictionary)["build"]):
			kind = "occupation" if "occupation" in (f["acts"] as Array) else ((f["acts"] as Array)[0] if not (f["acts"] as Array).is_empty() else "occupation")
		var r: Dictionary = bk.call("claim", Vector3(pos.x, WorldGen.height(pos.x, pos.y), pos.y), String(kind), String(f["name"]))
		if bool(r.get("ok", false)):
			f["gid"] = int(r["gid"])
	var cm := _mod("camps")
	if cm != null:
		for k in ["tent", "well", "warehouse"]:
			cm.call("place_structure", int(f["cid"]), k, pos)
	f["st"] = 2
	f["sd"] = _day
	_hist(f, "camp raised at %s" % String(f["name"]))
	_ev("founding", f, "occupation", "%s raises a camp" % String(f["name"]), 3)
	if not bool((f["rights"] as Dictionary)["build"]):
		_hist(f, "built without right (%s)" % String(land["status"]))
		_ev("crime", f, "illegal build", "camp on %s ground" % String(land["status"]).replace("_", " "), 2)
	return {"ok": true, "reason": ""}


func abandon(fid: int) -> bool:
	var f: Dictionary = _f.get(fid, {})
	if f.is_empty() or int(f["end"]) >= 0:
		return false
	_end(f, "abandoned")
	return true


func _end(f: Dictionary, why: String) -> void:
	f["end"] = _day
	f["why"] = why
	stats["ended"] = int(stats["ended"]) + 1
	_hist(f, "ended: " + why)
	_ev("founding", f, why, "%s: %s" % [String(f["name"]), why], 4)


# ------------------------------------------------------------------ rights and titles

func _refresh_rights(f: Dictionary) -> void:
	var b: Dictionary = f["base"]
	var acts: Array = f["acts"]
	var r: Dictionary = f["rights"]
	r["own"] = bool(b["own"]) or "purchase" in acts or "grant" in acts
	r["build"] = bool(b["build"]) or "lease" in acts or "purchase" in acts or "grant" in acts or "submit" in acts or "legalise" in acts
	r["govern"] = "recognition" in acts


func _add_zone(pos: Vector2, radius: float, status: String, holder: String) -> void:
	_zones.append([snappedf(pos.x, 0.1), snappedf(pos.y, 0.1), radius, status, holder])
	if _zones.size() > LandLaw.ZONE_MAX:
		_zones.remove_at(0)


## Regularises the ground: how in "lease", "purchase" or "grant" (what the status allows). Paid from the settlement's treasury.
func seek_title(fid: int, how: String) -> Dictionary:
	var f: Dictionary = _f.get(fid, {})
	if f.is_empty() or int(f["end"]) >= 0 or String(f["node"]) == "":
		return {"ok": false, "reason": "Found the camp first."}
	var land: Dictionary = f["land"]
	var allowed: Array = LandLaw.rights_of(String(land["status"]))["titles"]
	if not (how in allowed):
		return {"ok": false, "reason": "On %s ground you cannot %s. %s" % [String(land["status"]).replace("_", " "), how, LandLaw.words(String(land["status"]))]}
	if how in (f["acts"] as Array):
		return {"ok": false, "reason": "You already hold that title."}
	var p := _place(f)
	var cost := float(TITLE_COST[how])
	if float(p.get("treasury", 0.0)) < cost:
		return {"ok": false, "reason": "The treasury holds less than the %d gold it costs." % int(cost)}
	p["treasury"] = float(p["treasury"]) - cost
	(f["acts"] as Array).append(how)
	if how == "lease":
		f["dues"] = maxf(float(f["dues"]), 0.08)
	_add_zone(_pos(f), 180.0, "leased" if how == "lease" else "granted", String(f["fn"]))
	land["status"] = "leased" if how == "lease" else "granted"
	_refresh_rights(f)
	_clear_escalation(f, "title")
	_hist(f, "took a %s" % how)
	_ev("contract", f, how, "%s holds a %s" % [String(f["name"]), how], 3)
	return {"ok": true, "reason": "", "cost": int(cost)}


func _clear_escalation(f: Dictionary, outcome: String) -> void:
	var e: Dictionary = f["esc"]
	e["step"] = 0
	e["heat"] = 0.0
	e["pend"] = ""
	e["pday"] = -1
	e["outcome"] = outcome


## Stage 6 stub: files a petition for recognition (the right to govern). Needs the recognition stage.
func file_petition(fid: int) -> Dictionary:
	var f: Dictionary = _f.get(fid, {})
	if f.is_empty() or int(f["end"]) >= 0 or int(f["st"]) < 7:
		return {"ok": false, "reason": "The settlement is not ready: " + ", ".join(blockers(fid))}
	if not (f["pet"] as Dictionary).is_empty():
		return {"ok": false, "reason": "A petition is already filed."}
	var land: Dictionary = f["land"]
	f["pet"] = {"state": "filed", "day": _day, "to": String(land.get("holder", "")) if String(land.get("holder", "")) != "" else String(land.get("near", "the Crown")),
		"scale": SCALES[int(f["sc"])], "pop": _pop(f), "officials": (f["off"] as Dictionary).size(), "stage6": "pending"}
	_hist(f, "petition for recognition filed")
	_ev("founding", f, "petition", "%s petitions for recognition" % String(f["name"]), 4)
	return {"ok": true, "reason": ""}


## Stage 6 hook (stub): the realm answers. A grant gives the right to govern.
func resolve_petition(fid: int, granted: bool) -> bool:
	var f: Dictionary = _f.get(fid, {})
	if f.is_empty() or String((f["pet"] as Dictionary).get("state", "")) != "filed":
		return false
	(f["pet"] as Dictionary)["state"] = "granted" if granted else "refused"
	if granted:
		(f["acts"] as Array).append("recognition")
		_refresh_rights(f)
	_hist(f, "recognition %s" % ("granted" if granted else "refused"))
	return true


# ------------------------------------------------------------------ officials (appointed, 6.11)

func appoint(fid: int, role: String, who: Dictionary) -> bool:
	var f: Dictionary = _f.get(fid, {})
	if f.is_empty() or int(f["end"]) >= 0 or not (role in ROLES) or String(f["node"]) == "":
		return false
	(f["off"] as Dictionary)[role] = {"n": String(who.get("name", "An appointee")), "c": clampf(float(who.get("competence", 0.5)), 0.0, 1.0),
		"h": clampf(float(who.get("honesty", 0.6)), 0.0, 1.0), "age": int(who.get("age", 34)), "since": _day}
	(f["gone"] as Dictionary).erase(role)
	_hist(f, "%s %s appointed" % [role, String(who.get("name", ""))])
	_ev("succession", f, "appointment", "%s becomes %s of %s" % [String(who.get("name", "")), role, String(f["name"])], 2)
	return true


func _settler(f: Dictionary, role: String) -> Dictionary:
	var r := _rng("settler", _day, "%d%s" % [int(f["id"]), role])
	var first: Array = ["Bram", "Orla", "Tavis", "Maren", "Edric", "Sela", "Rook", "Halla", "Joss", "Wren", "Cade", "Ilsa"]
	var last: Array = ["Hale", "Marsh", "Cooper", "Reed", "Thatcher", "Fenn", "Ashby", "Wick"]
	return {"name": "%s %s" % [first[r.randi() % first.size()], last[r.randi() % last.size()]], "competence": snappedf(r.randf_range(0.3, 0.85), 0.01),
		"honesty": snappedf(r.randf_range(0.3, 0.95), 0.01), "age": 24 + r.randi() % 30}


## The settlers pick whoever they trust for each empty office.
func appoint_from_settlers(fid: int) -> int:
	var f: Dictionary = _f.get(fid, {})
	if f.is_empty():
		return 0
	var n := 0
	for role: String in ROLES:
		if not (f["off"] as Dictionary).has(role):
			if appoint(fid, role, _settler(f, role)):
				n += 1
	return n


func _officials_step(f: Dictionary, n: float, msgs: Array) -> void:
	var off: Dictionary = f["off"]
	for role: String in off.keys():
		var o: Dictionary = off[role]
		var age := float(o["age"]) + n / 360.0
		o["age"] = age
		var hz := 0.0 if age < 45.0 else 0.00006 * pow(age - 44.0, 1.5)
		if hz > 0.0 and _rng("odeath", _day, "%d%s" % [int(f["id"]), role]).randf() < 1.0 - pow(1.0 - hz, n):
			off.erase(role)
			(f["gone"] as Dictionary)[role] = _day
			_say(f, "%s, %s of %s, has died." % [String(o["n"]), role, String(f["name"])], msgs)
			_ev("succession", f, "death", "%s of %s dies" % [role, String(f["name"])], 3)
			_stress_to(f, "succession", 1.0)


# ------------------------------------------------------------------ 3. escalation

func _weak(f: Dictionary) -> bool:
	if _war:
		return true
	var sp := _static_place(f)
	if sp.is_empty():
		return false
	return float(sp.get("war", 0.0)) > 0.25 or float(sp.get("unrest", 0.0)) > 0.6 or float(sp.get("treasury", 100.0)) < 40.0


func visibility(f: Dictionary) -> float:
	var e: Dictionary = f["esc"]
	if not e.has("rd"):
		var rd0: float = WorldGen.road_distance(float(f["pos"][0]), float(f["pos"][1]))
		e["rd"] = 99999.0 if rd0 == INF else rd0
	var pop := _pop(f)
	var pieces := 0
	var bk := _mod("build_kit")
	if bk != null and int(f["gid"]) > 0:
		pieces = int(bk.call("piece_count", int(f["gid"])))
	var rd := float(e["rd"])
	var road := 0.0 if bool(f["hid"]) else clampf(1.0 - rd / 500.0, 0.0, 1.0)
	var size := clampf(float(pop) / 200.0 + float(pieces) / 400.0, 0.0, 1.0)
	var traffic := clampf((float(f["dw"]) + _arrivals(f)) / 12.0, 0.0, 1.0)
	var rum := clampf(float((f["esc"] as Dictionary)["rum"]) / 6.0, 0.0, 1.0)
	return clampf(0.3 * road + 0.25 * size + 0.25 * traffic + 0.2 * rum, 0.0, 1.0)


func _arrivals(f: Dictionary) -> float:
	var mg := _mod("migration")
	if mg == null or String(f["node"]) == "":
		return 0.0
	return float((mg.call("waves_to", String(f["node"])) as Array).size()) * 2.0


func _escalate(f: Dictionary, day: int, n: float, msgs: Array) -> void:
	var e: Dictionary = f["esc"]
	e["rum"] = maxf(0.0, float(e["rum"]) - 0.05 * n)
	if bool((f["rights"] as Dictionary)["build"]):
		e["heat"] = maxf(0.0, float(e["heat"]) - 0.5 * n)
		if float(e["heat"]) <= 0.0 and int(e["step"]) > 0 and String(e["pend"]) == "":
			e["step"] = 0
		return
	var vis := float(e["vis"])
	if n > 1.5 or day - int(e.get("vd", -99)) >= 4:
		vis = visibility(f)
		e["vis"] = snappedf(vis, 0.001)
		e["vd"] = day
	if bool(f["hid"]) and float(f["expo"]) < KNOWN:
		return                                  # the realm does not know it is there
	var auth := float(LandLaw.rights_of(String((f["land"] as Dictionary)["status"]))["auth"])
	var rate := vis * auth
	if _weak(f):
		e["delay"] = float(e["delay"]) + rate * n * 0.6
		rate *= 0.4
	if String(e["pend"]) != "":
		if day - int(e["pday"]) > PEND_DAYS:
			_resolve(f, "refuse", msgs)
		return
	e["heat"] = float(e["heat"]) + rate * n
	var step := int(e["step"])
	while step + 1 < ESC.size() and float(e["heat"]) >= float(ESC_AT[step + 1]):
		if step + 1 == 6 and day - int(e["mil"]) < MIL_REPEAT:
			break
		step += 1
		e["step"] = step
		stats["escalations"] = int(stats["escalations"]) + 1
		_on_step(f, step, day, msgs)
		if String(e["pend"]) != "" or int(f["end"]) >= 0 or int(e["step"]) != step:
			break


func _on_step(f: Dictionary, step: int, day: int, msgs: Array) -> void:
	var e: Dictionary = f["esc"]
	var nm := String(f["name"])
	var holder := String((f["land"] as Dictionary).get("holder", "the Crown"))
	_ev("crime", f, "illegal build", "%s: %s" % [nm, ESC[step]], 2 + step / 2)
	match step:
		1:
			_say(f, "Surveyors from %s have noticed the new buildings at %s." % [holder, nm], msgs)
		2:
			_say(f, "An official of %s is asking who gave leave to build at %s." % [holder, nm], msgs)
		3:
			_say(f, "A written warning arrives for %s: stop building, or take a lease." % nm, msgs)
		4:
			_open_intervention(f, day, msgs)
		5:
			_enforce(f, msgs)
		6:
			_military(f, day, msgs)
	if step in [2, 3, 4] and String(f["who"]) == "npc" and String(e["pend"]) == "" and int(f["end"]) < 0:
		_try_bribe(f, msgs)


## The authorities put a demand on the table. `forced` names the branch (legalise, fine, submit); empty lets the situation choose.
func offer(fid: int, forced := "") -> bool:
	var f: Dictionary = _f.get(fid, {})
	if f.is_empty() or int(f["end"]) >= 0 or String(f["node"]) == "" or not (forced in ["", "legalise", "fine", "submit"]):
		return false
	var e: Dictionary = f["esc"]
	e["step"] = 4
	e["heat"] = maxf(float(e["heat"]), float(ESC_AT[4]))
	_open_intervention(f, _day, [], forced)
	return true


func _open_intervention(f: Dictionary, day: int, msgs: Array, forced := "") -> void:
	var e: Dictionary = f["esc"]
	var pop := _pop(f)
	var p := _place(f)
	var r := _rng("branch", day, int(f["id"]))
	var defence := _defence(f)
	var w_leg := clampf(float(pop) / 150.0, 0.1, 1.0) * (1.4 if float(p.get("inc", 0.0)) > 4.0 else 1.0)
	var w_fine := 0.55
	var w_sub := 0.25 + (1.0 - defence) * 0.7
	var tot := w_leg + w_fine + w_sub
	var x := r.randf() * tot
	var branch := "legalise" if x < w_leg else ("fine" if x < w_leg + w_fine else "submit")
	if forced != "":
		branch = forced
	var nfine := int(e["fines"])
	e["pend"] = branch
	e["pday"] = day
	e["terms"] = {"dues": 0.1, "fine": int(round((30.0 + 4.0 * pop) * pow(1.5, nfine))), "vassal": String((f["land"] as Dictionary).get("holder", "the Crown"))}
	var t: Dictionary = e["terms"]
	var line := ""
	match branch:
		"legalise":
			line = "The authorities offer to legalise %s for a share of its income (%d%% dues). Accept or refuse." % [String(f["name"]), int(float(t["dues"]) * 100.0)]
		"fine":
			line = "The authorities fine %s %d gold for building without right. Pay or refuse." % [String(f["name"]), int(t["fine"])]
		_:
			line = "%s demands that %s submit to its rule. Accept or refuse." % [String(t["vassal"]), String(f["name"])]
	_say(f, line, msgs)
	_hist(f, "intervention: " + branch)
	if String(f["who"]) == "npc":
		_resolve(f, "auto", msgs)


func _defence(f: Dictionary) -> float:
	var p := _place(f)
	var cm := _mod("camps")
	var d := 0.0
	if cm != null and int(f["cid"]) >= 0:
		d = float(cm.call("defence_of", int(f["cid"])))
	return clampf(d + float(p.get("patrol", 0.0)) + 0.1 * float(p.get("walls", 0)), 0.0, 1.0)


## The player (or the NPC policy) answers a pending demand: "accept", "refuse" or "bribe".
func respond(fid: int, choice: String) -> Dictionary:
	var f: Dictionary = _f.get(fid, {})
	if f.is_empty() or String((f["esc"] as Dictionary)["pend"]) == "":
		return {"ok": false, "reason": "Nothing awaits your answer."}
	var msgs: Array = []
	if choice == "bribe":
		return bribe(fid)
	_resolve(f, choice, msgs)
	return {"ok": true, "reason": "", "msgs": msgs, "outcome": String((f["esc"] as Dictionary)["outcome"])}


func _resolve(f: Dictionary, choice: String, msgs: Array) -> void:
	var e: Dictionary = f["esc"]
	var branch := String(e["pend"])
	var t: Dictionary = e["terms"]
	var p := _place(f)
	if choice == "auto":
		var def := _defence(f)
		choice = "accept"
		if branch == "submit" and def >= 0.45:
			choice = "refuse"
		if branch == "fine" and float(p.get("treasury", 0.0)) < float(t["fine"]):
			choice = "refuse"
	e["pend"] = ""
	e["pday"] = -1
	if choice != "accept":
		e["step"] = 5
		e["heat"] = maxf(float(e["heat"]), float(ESC_AT[5]))
		e["outcome"] = "refused"
		_say(f, "You refuse. The authorities will enforce the law.", msgs)
		_enforce(f, msgs)
		return
	match branch:
		"legalise":
			(f["acts"] as Array).append("legalise")
			f["dues"] = maxf(float(f["dues"]), float(t["dues"]))
			_add_zone(_pos(f), 180.0, "leased", String(t["vassal"]))
			(f["land"] as Dictionary)["status"] = "leased"
			stats["legalised"] = int(stats["legalised"]) + 1
			_say(f, "%s is legalised. You owe dues from now on." % String(f["name"]), msgs)
			_clear_escalation(f, "legalised")
		"fine":
			var fine := float(t["fine"])
			var paid := minf(fine, float(p.get("treasury", 0.0)))
			p["treasury"] = float(p.get("treasury", 0.0)) - paid
			f["arrears"] = float(f["arrears"]) + (fine - paid)
			e["fines"] = int(e["fines"]) + 1
			e["step"] = 3
			e["heat"] = float(ESC_AT[3])
			e["outcome"] = "fined"
			_say(f, "You pay %d gold. The building is still unlawful: the matter is not closed." % int(fine), msgs)
		_:
			(f["acts"] as Array).append("submit")
			f["vassal"] = String(t["vassal"])
			f["dues"] = maxf(float(f["dues"]), 0.18)
			_add_zone(_pos(f), 180.0, "leased", String(t["vassal"]))
			(f["land"] as Dictionary)["status"] = "leased"
			_say(f, "%s submits to %s." % [String(f["name"]), String(t["vassal"])], msgs)
			_clear_escalation(f, "submitted")
	_refresh_rights(f)
	_hist(f, "%s: %s" % [branch, String(e["outcome"])])


## Pay the local governor to look away. Works on a corrupt governor, backfires on an honest one.
func bribe(fid: int) -> Dictionary:
	var f: Dictionary = _f.get(fid, {})
	if f.is_empty():
		return {"ok": false, "reason": "No such founding."}
	var e: Dictionary = f["esc"]
	var step := int(e["step"])
	if step < 1 or step > 4:
		return {"ok": false, "reason": "There is nothing to buy off."}
	var p := _place(f)
	var cost := 25.0 * float(step)
	if float(p.get("treasury", 0.0)) < cost:
		return {"ok": false, "reason": "The treasury holds less than the %d gold the governor wants." % int(cost)}
	var sid := int((f["land"] as Dictionary).get("sid", -1))
	var corrupt := corruption_at(sid)
	p["treasury"] = float(p["treasury"]) - cost
	var ok := _rng("bribe", _day, "%d%d" % [int(f["id"]), int(e["bribes"])]).randf() < corrupt
	if ok:
		e["bribes"] = int(e["bribes"]) + 1
		e["step"] = maxi(0, step - 2)
		e["heat"] = float(ESC_AT[int(e["step"])])
		e["pend"] = ""
		e["pday"] = -1
		e["outcome"] = "bribed"
		e["rum"] = float(e["rum"]) + 1.0                 # bought silence leaks
		stats["bribes"] = int(stats["bribes"]) + 1
		_hist(f, "bribed the governor")
		_ev("crime", f, "bribe", "%s bribes the governor" % String(f["name"]), 3)
		return {"ok": true, "reason": "", "accepted": true}
	e["heat"] = float(e["heat"]) + 6.0
	e["outcome"] = "bribe refused"
	_hist(f, "bribe refused")
	_ev("crime", f, "bribe", "an honest governor refuses %s" % String(f["name"]), 3)
	return {"ok": true, "reason": "", "accepted": false}


func _try_bribe(f: Dictionary, _msgs: Array) -> void:
	var sid := int((f["land"] as Dictionary).get("sid", -1))
	if corruption_at(sid) >= 0.5:
		bribe(int(f["id"]))


func _enforce(f: Dictionary, msgs: Array) -> void:
	var civ := _civ()
	var p := _place(f)
	if civ == null or p.is_empty():
		return
	var pop := _pop(f)
	var loss := maxi(1, int(round(0.12 * pop)))
	civ.call("add_people", String(f["node"]), -loss, "", _day)
	p["housing"] = maxf(10.0, float(p["housing"]) * 0.85)
	var bk := _mod("build_kit")
	var torn := 0
	if bk != null and int(f["gid"]) > 0 and (bk.get("grids") as Dictionary).has(int(f["gid"])):
		var pcs: Dictionary = (bk.get("grids") as Dictionary)[int(f["gid"])]["pieces"]
		var keys: Array = pcs.keys()
		keys.sort()
		var want := maxi(1, int(0.15 * keys.size())) if keys.size() > 0 else 0
		while torn < want and not keys.is_empty():
			var pid: int = keys.pop_back()
			if (bk.call("remove", int(f["gid"]), pid, 0.0) as Dictionary).get("ok", true):
				torn += 1
	(f["esc"] as Dictionary)["outcome"] = "enforced"
	_say(f, "Enforcers tear down part of %s: %d people leave%s." % [String(f["name"]), loss, (", %d pieces torn down" % torn) if torn > 0 else ""], msgs)
	_hist(f, "enforcement: %d people, %d pieces lost" % [loss, torn])
	_ev("crime", f, "enforcement", "%s is torn down in part" % String(f["name"]), 4)


func _military(f: Dictionary, day: int, msgs: Array) -> void:
	var civ := _civ()
	var e: Dictionary = f["esc"]
	e["mil"] = day
	if civ == null:
		return
	var pop := _pop(f)
	var force := 0.45 + 0.35 * float(e["vis"])
	var def := _defence(f)
	if def >= force:
		civ.call("add_people", String(f["node"]), -maxi(1, int(0.05 * pop)), "", day)
		_add_zone(_pos(f), 220.0, "disputed", "the Crown and %s" % String(f["fn"]))
		(f["land"] as Dictionary)["status"] = "disputed"
		e["outcome"] = "repelled"
		_say(f, "A royal force is thrown back from %s. The ground is now disputed." % String(f["name"]), msgs)
		_hist(f, "military response repelled")
	else:
		var gone := maxi(1, int(0.45 * pop))
		civ.call("add_people", String(f["node"]), -gone, "", day)
		civ.call("add_pressure", String(f["node"]), "war", 0.5)
		var p := _place(f)
		p["treasury"] = 0.0
		e["outcome"] = "razed"
		stats["razed"] = int(stats["razed"]) + 1
		_say(f, "Soldiers burn %s. %d people are dead or gone." % [String(f["name"]), gone], msgs)
		_hist(f, "razed by soldiers")
		if pop - gone < 6:
			_end(f, "razed")
	_ev("battle", f, "military response", "%s: %s" % [String(f["name"]), String(e["outcome"])], 5)


# ------------------------------------------------------------------ 4. stages, services, scale

func _farms_built(f: Dictionary) -> int:
	var cm := _mod("camps")
	var n := 0
	if cm != null and int(f["cid"]) >= 0:
		for s: Dictionary in cm.call("structures", int(f["cid"]), "food"):
			if String(s["kind"]) == "farm_plot" and int(s["hours_left"]) <= 0:
				n += 1
	return n


func services(f: Dictionary) -> Array:
	var out: Array = []
	var p := _place(f)
	var cm := _mod("camps")
	if p.is_empty() or cm == null:
		return out
	var cid := int(f["cid"])
	var built: Dictionary = p["built"]
	if bool(cm.call("has_role", cid, "shelter")):
		out.append("shelter")
	if bool(cm.call("has_role", cid, "water")) or float((f["ev"] as Dictionary).get("water", 0.0)) >= 0.7 or int(built.get("well", 0)) > 0:
		out.append("water")
	if bool(cm.call("has_role", cid, "storage")):
		out.append("storage")
	if int(p["farms"]) > 0 or bool(cm.call("has_role", cid, "food")):
		out.append("food")
	if int(built.get("market", 0)) > 0 or bool(cm.call("has_role", cid, "trade")):
		out.append("trade")
	if int(built.get("wall", 0)) > 0 or float(p["patrol"]) >= 0.2 or bool(cm.call("has_role", cid, "defence")):
		out.append("defence")
	if int(built.get("school", 0)) > 0:
		out.append("learning")
	if int(built.get("road", 0)) > 0 or int(built.get("bridge", 0)) > 0 or float(p["road_x"]) > 0.0:
		out.append("roads")
	if (f["off"] as Dictionary).size() >= 2:
		out.append("government")
	if not (f["biz"] as Array).is_empty() or bool(cm.call("has_role", cid, "craft")):
		out.append("crafts")
	return out


func infrastructure(f: Dictionary) -> int:
	var p := _place(f)
	if p.is_empty():
		return 0
	var n := 0
	for k: String in p["built"]:
		n += int(p["built"][k])
	var cm := _mod("camps")
	if cm != null and int(f["cid"]) >= 0:
		for s: Dictionary in cm.call("structures", int(f["cid"])):
			if int(s["hours_left"]) <= 0 and String(s["role"]) in ["water", "storage", "defence", "trade"]:
				n += 1
	return n


func scale_facts(f: Dictionary) -> Dictionary:
	var p := _place(f)
	return {"pop": _pop(f), "services": services(f).size(), "infra": infrastructure(f), "walls": int(p.get("walls", 0)), "patrol": float(p.get("patrol", 0.0))}


func scale_name(f: Dictionary) -> String:
	return "regional stronghold" if bool(f["strong"]) else String(SCALES[int(f["sc"])])


func _scale_target(facts: Dictionary) -> int:
	var t := 0
	for i in SCALES.size():
		if int(facts["pop"]) >= int(SCALE_POP[i]) and int(facts["services"]) >= int(SCALE_SERVICES[i]) and int(facts["infra"]) >= int(SCALE_INFRA[i]):
			t = i
	return t


func _scale_step(f: Dictionary, n: float, msgs: Array) -> void:
	if String(f["node"]) == "":
		return
	var facts := scale_facts(f)
	var cur := int(f["sc"])
	var tgt := _scale_target(facts)
	if tgt > cur:
		f["sc_up"] = float(f["sc_up"]) + n
		f["sc_dn"] = 0.0
		if float(f["sc_up"]) >= 5.0:
			f["sc"] = cur + 1
			f["sc_up"] = 0.0
			stats["promoted"] = int(stats["promoted"]) + 1
			_hist(f, "grew into a %s" % SCALES[cur + 1])
			_say(f, "%s has grown into a %s." % [String(f["name"]), SCALES[cur + 1]], msgs)
			_ev("founding", f, "promotion", "%s becomes a %s" % [String(f["name"]), SCALES[cur + 1]], 4)
	elif cur > 0 and int(facts["pop"]) < int(0.75 * float(SCALE_POP[cur])):
		f["sc_dn"] = float(f["sc_dn"]) + n
		f["sc_up"] = 0.0
		if float(f["sc_dn"]) >= 20.0:
			f["sc"] = cur - 1
			f["sc_dn"] = 0.0
			_hist(f, "shrank to a %s" % SCALES[cur - 1])
	else:
		f["sc_up"] = 0.0
		f["sc_dn"] = 0.0
	var strong: bool = int(facts["pop"]) >= int(STRONGHOLD["pop"]) and int(facts["walls"]) >= int(STRONGHOLD["walls"]) and float(facts["patrol"]) >= float(STRONGHOLD["patrol"]) \
		and int(f["sc"]) >= 2
	if strong != bool(f["strong"]):
		f["strong"] = strong
		_hist(f, "a regional stronghold" if strong else "no longer a stronghold")


## What the next stage still lacks, in plain words (empty when it can open).
func blockers(fid: int) -> Array:
	var f: Dictionary = _f.get(fid, {})
	var out: Array = []
	if f.is_empty():
		return out
	var st := int(f["st"])
	var p := _place(f)
	match st:
		0:
			if _day - int(f["sd"]) < SCOUT_DAYS:
				out.append("the scouts need %d more days" % (SCOUT_DAYS - (_day - int(f["sd"]))))
			if float(f["overall"]) < 0.22:
				out.append("the site is too poor")
		1:
			if String(f["node"]) == "":
				out.append("raise the first camp")
		2:
			var sv := services(f)
			for k in ["shelter", "water", "storage"]:
				if not (k in sv):
					out.append("no finished %s yet" % k)
		3:
			if int(p.get("farms", 0)) < 1:
				out.append("no working farm yet")
			if float(p.get("F", 1.0)) < 0.75:
				out.append("food is short for the people here")
		4:
			if _pop(f) < MIN_POP_RECRUITED:
				out.append("only %d settlers, need %d" % [_pop(f), MIN_POP_RECRUITED])
		5:
			if infrastructure(f) < 3:
				out.append("fewer than 3 permanent works (%d)" % infrastructure(f))
			if services(f).size() < 6:
				out.append("only %d of 6 services" % services(f).size())
		6:
			for r: String in ROLES:
				if not (f["off"] as Dictionary).has(r):
					out.append("no %s appointed" % r)
		7:
			if (f["pet"] as Dictionary).is_empty():
				out.append("file a petition for recognition")
	return out


func _advance(f: Dictionary, day: int, msgs: Array) -> void:
	var st := int(f["st"])
	if st >= 7:
		return
	if st == 0:
		if day - int(f["sd"]) >= SCOUT_DAYS and float(f["overall"]) >= 0.22:
			f["st"] = 1
			f["sd"] = day
			_hist(f, "scouting done")
			_say(f, "The scouts return: %s" % String(f["name"]), msgs)
			if String(f["who"]) == "npc":
				occupy(int(f["id"]))
		return
	if String(f["node"]) == "":
		return
	if st == 1:
		return
	if not blockers(int(f["id"])).is_empty():
		if st == 6 and (String(f["who"]) == "npc" or day - int(f["sd"]) >= AUTO_APPOINT_DAYS):
			appoint_from_settlers(int(f["id"]))
		return
	f["st"] = st + 1
	f["sd"] = day
	_enter(f, st + 1, day, msgs)
	_hist(f, "stage: " + String(STAGES[st + 1]))
	_say(f, "%s: %s." % [String(f["name"]), String(STAGE_WORDS[st + 1])], msgs)
	_ev("founding", f, String(STAGES[st + 1]), "%s reaches %s" % [String(f["name"]), String(STAGES[st + 1])], 3)


func _enter(f: Dictionary, st: int, day: int, msgs: Array) -> void:
	var cm := _mod("camps")
	var pos := _pos(f)
	match st:
		3:
			if cm != null:
				cm.call("place_structure", int(f["cid"]), "farm_plot", pos)
			_found_parcel(f)
		4:
			_recruit(f, day, msgs)
		5:
			if cm != null:
				cm.call("place_structure", int(f["cid"]), "watchtower", pos)
				cm.call("place_structure", int(f["cid"]), "market_stall", pos)
		6:
			if String(f["who"]) == "npc":
				appoint_from_settlers(int(f["id"]))


func _found_parcel(f: Dictionary) -> void:
	var fm := _mod("farming")
	if fm == null or not fm.has_method("found_parcel") or String(f["parcel"]) != "":
		return
	var sid := int((f["land"] as Dictionary).get("sid", 0))
	var owner := "player" if String(f["who"]) == "player" else "npc:f%d" % int(f["id"])
	f["parcel"] = String(fm.call("found_parcel", maxi(0, sid), _pos(f), 2, owner, "%s Farm" % String(f["name"])))


## Posts a notice at the nearest settlement (recruitment.gd) and sends a wave of settlers (migration.gd). One wave per founding every 14
## days and one per weekly tick for the whole module (a wave plans a route, which is the costly part), so the week job stays small.
func _recruit(f: Dictionary, day: int, msgs: Array) -> void:
	var sid := int((f["land"] as Dictionary).get("sid", -1))
	if sid < 0 or day - int(f["wave"]) < 14 or _waves_week >= 1:
		return
	var mg := _mod("migration")
	var civ := _civ()
	if mg == null or civ == null:
		return
	var from := "s%d" % sid
	if not bool(civ.call("has_place", from)):
		return
	var avail := int(civ.call("population", from))
	var n := clampi(int(0.04 * avail), 4, 16)
	var w: Dictionary = mg.call("send_wave", from, String(f["node"]), n, "settlers", "recruited", "native", day)
	if w.is_empty():
		return
	f["wave"] = day
	_waves_week += 1
	if String(f["who"]) == "player":
		var rc := _mod("recruitment")
		if rc != null and rc.has_method("post_notice"):
			rc.call("post_notice", sid, "market", {"wage": 6, "duty": "labor", "housing": true}, "", 12)
	(f["esc"] as Dictionary)["rum"] = float((f["esc"] as Dictionary)["rum"]) + 0.5
	_say(f, "%d settlers set out from %s for %s." % [int(w["n"]), civ.call("name_of", from), String(f["name"])], msgs)


# ------------------------------------------------------------------ 6. emergent problems

func _stress_to(f: Dictionary, kind: String, v: float) -> void:
	(f["stress"] as Dictionary)[kind] = maxf(float((f["stress"] as Dictionary).get(kind, 0.0)), v)


func has_problem(fid: int, kind: String) -> bool:
	var f: Dictionary = _f.get(fid, {})
	if f.is_empty():
		return false
	for pr: Array in f["probs"]:
		if String(pr[0]) == kind and int(pr[2]) < 0:
			return true
	return false


func problems(fid: int, active_only := true) -> Array:
	var f: Dictionary = _f.get(fid, {})
	var out: Array = []
	if f.is_empty():
		return out
	for pr: Array in f["probs"]:
		if not active_only or int(pr[2]) < 0:
			out.append({"kind": String(pr[0]), "day": int(pr[1]), "solved": int(pr[2]), "severity": int(pr[3]), "words": String(PROBLEM_WORDS[String(pr[0])])})
	return out


func _problems_step(f: Dictionary, day: int, n: float, msgs: Array) -> void:
	var p := _place(f)
	if p.is_empty():
		return
	var s: Dictionary = f["stress"]
	var pop := float(_pop(f))
	var F := float(p.get("F", 1.0))
	var off: Dictionary = f["off"]
	var captain := off.has("captain")
	var honesty := 1.0
	if not off.is_empty():
		honesty = 0.0
		for r: String in off:
			honesty += float((off[r] as Dictionary)["h"])
		honesty /= float(off.size())
	var tr := float(p.get("treasury", 0.0))
	var def := _defence(f)
	_bump(s, "food_shortage", n * clampf((0.9 - F) * 0.12, 0.0, 0.2) if F < 0.9 else -n * 0.05)
	_bump(s, "treasury_crisis", n * 0.08 if (tr < 12.0 + pop * 0.3 and int(f["st"]) >= 3) else -n * 0.05)
	var crime := float(p.get("crime", 0.0))
	_bump(s, "crime", n * (crime - 0.3) * 0.4 * (0.4 if captain else 1.0) if crime > 0.3 else -n * 0.03)
	_bump(s, "corruption", n * 0.02 * (1.0 - honesty) * minf(1.0, tr / 80.0) if not off.is_empty() else 0.0)
	_bump(s, "epidemic", n * 0.004 * maxf(0.0, float(p.get("H", 0.9)) - 0.8) * (pop / 80.0) if pop >= 12.0 else -n * 0.01)
	var unrest := float(p.get("unrest", 0.0))
	_bump(s, "desertion", n * ((unrest - 0.45) * 0.5 + (0.02 if float(f["arrears"]) > 0.0 else 0.0)) if (unrest > 0.45 or float(f["arrears"]) > 0.0) else -n * 0.03)
	var monster := float(p.get("monster", 0.0))
	_bump(s, "raid", n * monster * 0.3 * (1.0 - def) if monster > 0.12 else -n * 0.02)
	for k: String in PROBLEMS:
		var v := float(s.get(k, 0.0))
		if v >= 1.0 and not has_problem(int(f["id"]), k):
			_fire(f, k, day, msgs)
			s[k] = 0.35
	_resolve_problems(f, day, p)
	# ongoing effects of what is unresolved
	if has_problem(int(f["id"]), "food_shortage"):
		(_civ()).call("add_pressure", String(f["node"]), "famine", 0.01 * n)


func _bump(s: Dictionary, k: String, d: float) -> void:
	s[k] = clampf(float(s.get(k, 0.0)) + d, 0.0, 1.5)


func _fire(f: Dictionary, kind: String, day: int, msgs: Array) -> void:
	var probs: Array = f["probs"]
	var active := 0
	for pr: Array in probs:
		if int(pr[2]) < 0:
			active += 1
	if active >= 6:
		return
	var civ := _civ()
	var p := _place(f)
	var pop := _pop(f)
	var sev := 1 + int(float((f["stress"] as Dictionary).get(kind, 1.0)) - 1.0)
	probs.append([kind, day, -1, clampi(sev, 1, 3)])
	if probs.size() > 16:
		for i in probs.size():
			if int((probs[i] as Array)[2]) >= 0:
				probs.remove_at(i)
				break
	(f["pn"] as Dictionary)[kind] = int((f["pn"] as Dictionary).get(kind, 0)) + 1
	stats["problems"] = int(stats["problems"]) + 1
	match kind:
		"food_shortage":
			civ.call("add_pressure", String(f["node"]), "law", 0.08)
		"treasury_crisis":
			_bump(f["stress"], "desertion", 0.3)
		"crime":
			p["treasury"] = maxf(0.0, float(p["treasury"]) * 0.95)
		"corruption":
			var skim := maxf(5.0, 0.06 * float(p["treasury"]))
			p["treasury"] = maxf(0.0, float(p["treasury"]) - skim)
			for r: String in f["off"]:
				var o: Dictionary = f["off"][r]
				o["h"] = maxf(0.0, float(o["h"]) - 0.1)
		"epidemic":
			civ.call("add_people", String(f["node"]), -maxi(1, int(0.04 * pop)), "", day)
		"desertion":
			civ.call("add_people", String(f["node"]), -maxi(1, int(0.05 * pop)), "", day)
			(f["esc"] as Dictionary)["rum"] = float((f["esc"] as Dictionary)["rum"]) + 1.0
		"raid":
			civ.call("add_people", String(f["node"]), -maxi(1, int(0.03 * pop * (1.0 - _defence(f)))), "", day)
			p["treasury"] = maxf(0.0, float(p["treasury"]) * 0.9)
		"succession":
			civ.call("add_pressure", String(f["node"]), "law", 0.05)
	_say(f, "%s: %s" % [String(f["name"]), PROBLEM_WORDS[kind]], msgs)
	_hist(f, "problem: " + kind)
	_ev("emergency", f, kind, "%s: %s" % [String(f["name"]), kind.replace("_", " ")], 3)


func _resolve_problems(f: Dictionary, day: int, p: Dictionary) -> void:
	for pr: Array in f["probs"]:
		if int(pr[2]) >= 0:
			continue
		var k := String(pr[0])
		var age := day - int(pr[1])
		var done := false
		match k:
			"food_shortage": done = float(p.get("F", 1.0)) >= 1.0
			"treasury_crisis": done = float(p.get("treasury", 0.0)) >= 40.0 + 0.5 * float(_pop(f))
			"crime": done = float(p.get("crime", 0.0)) < 0.25 or (age >= 14 and (f["off"] as Dictionary).has("captain"))
			"corruption": done = age >= 20 and not (f["off"] as Dictionary).is_empty()
			"epidemic": done = age >= 21
			"desertion": done = float(p.get("unrest", 0.0)) < 0.35
			"raid": done = age >= 10
			"succession": done = (f["off"] as Dictionary).has("reeve")
		if done or age >= 60:
			pr[2] = day
			_hist(f, "solved: " + k)


# ------------------------------------------------------------------ 5/7. residents, deliveries, hidden valley

func exposure_words(f: Dictionary) -> String:
	var x := float(f["expo"])
	if not bool(f["hid"]):
		return ""
	if x < 25.0:
		return "Secret: nobody outside knows."
	if x < KNOWN:
		return "Rumoured: travellers whisper of a hidden settlement."
	return "Known: the realm knows the Hidden Vale is settled."


## Counts a delivery of goods to the settlement (a cart in through the gorge). In the hidden vale it raises exposure unless the trade
## post takes the traffic.
func record_delivery(fid: int, count := 1) -> void:
	var f: Dictionary = _f.get(fid, {})
	if f.is_empty() or int(f["end"]) >= 0:
		return
	f["dw"] = float(f["dw"]) + float(count)
	f["dt"] = int(f["dt"]) + count


## A public-facing trade post at the mouth of the gorge: honest merchants go there, the carts stop at the post, and the vale's
## doorstep is lawful, known ground.
func build_trade_post(fid: int) -> Dictionary:
	var f: Dictionary = _f.get(fid, {})
	if f.is_empty() or int(f["end"]) >= 0 or not bool(f["hid"]):
		return {"ok": false, "reason": "A trade post is only needed in the hidden vale."}
	if not (f["post"] as Array).is_empty():
		return {"ok": false, "reason": "The post already stands."}
	var p := _place(f)
	if p.is_empty() or int(f["st"]) < 2:
		return {"ok": false, "reason": "Found the camp first."}
	if float(p.get("treasury", 0.0)) < 60.0:
		return {"ok": false, "reason": "The post costs 60 gold."}
	p["treasury"] = float(p["treasury"]) - 60.0
	var at: Vector2 = Hv.gorge_world(Hv.GORGE_MOUTH + 30.0)
	f["post"] = [snappedf(at.x, 0.1), snappedf(at.y, 0.1)]
	f["post_day"] = _day
	_add_zone(at, 140.0, "leased", "the Crown")
	var cm := _mod("camps")
	if cm != null and int(f["cid"]) >= 0:
		var st: Dictionary = cm.call("place_structure", int(f["cid"]), "market_stall", at)
		if not st.is_empty():
			st["hours_left"] = 0
			st["active"] = true
	p["trade_x"] = float(p["trade_x"]) + 0.15
	_hist(f, "trade post opened at the gorge mouth")
	_ev("trade", f, "trade post", "%s opens a trade post" % String(f["name"]), 3)
	return {"ok": true, "reason": ""}


func _hidden_week(f: Dictionary, weeks: float, msgs: Array) -> void:
	var p := _place(f)
	if p.is_empty():
		return
	var pop := float(_pop(f))
	var has_post := not (f["post"] as Array).is_empty()
	var local_cap := 18.0 + float(civ_feeds()) * float(p.get("farms", 0)) * (1.0 + float(p.get("food_x", 0.0)))
	var need := ceili(maxf(0.0, pop - local_cap) / float(DELIVERY_FEEDS))
	var done := 0
	for _i in need:
		if float(p["treasury"]) < 6.0:
			break
		p["treasury"] = float(p["treasury"]) - 6.0
		done += 1
	if done > 0:
		f["dw"] = float(f["dw"]) + float(done)
		f["dt"] = int(f["dt"]) + done
	p["fimp"] = float(done * DELIVERY_FEEDS)
	var deliveries := float(f["dw"])
	var gain := deliveries * (1.4 if has_post else 4.0) + (0.02 * maxf(0.0, pop - 20.0))
	gain += float((f["esc"] as Dictionary)["rum"]) * 0.8
	if has_post:
		gain += 1.0                                # a known post is a known road
	var was := float(f["expo"])
	var e := was + gain * weeks - (2.5 * weeks if deliveries <= 0.0 else 0.0)
	f["expo"] = clampf(e, 0.0, 100.0)
	f["dw"] = 0.0
	if was < KNOWN and float(f["expo"]) >= KNOWN:
		var land: Dictionary = f["land"]
		var st := "leased" if has_post else "frontier"
		land["status"] = st
		land["holder"] = "the Crown"
		_add_zone(_pos(f), 320.0, st, "the Crown")
		var b: Dictionary = f["base"]
		b["build"] = has_post
		b["own"] = false
		_refresh_rights(f)
		if has_post:
			(f["acts"] as Array).append("lease")
			f["dues"] = maxf(float(f["dues"]), 0.06)
			_refresh_rights(f)
		_say(f, "Word is out: the realm knows the Hidden Vale is settled.", msgs)
		_hist(f, "the hidden vale is discovered")
		_ev("founding", f, "discovered", "the Hidden Vale is known", 6)


static func civ_feeds() -> int:
	return 40


func _residents_week(f: Dictionary, weeks: float, day: int) -> void:
	var civ := _civ()
	var p := _place(f)
	if civ == null or p.is_empty():
		return
	var pop := _pop(f)
	# wages: a share of what the place earns reaches households as savings
	var wage := minf(0.22 * float(p.get("inc", 0.0)) * 7.0 * weeks, 0.5 * float(p.get("treasury", 0.0)))
	if wage > 0.0:
		p["treasury"] = float(p["treasury"]) - wage
		f["sav"] = float(f["sav"]) + wage
	# dues owed to whoever lets the land
	if float(f["dues"]) > 0.0:
		var due := float(f["dues"]) * float(p.get("inc", 0.0)) * 7.0 * weeks
		var pay := minf(due, float(p.get("treasury", 0.0)))
		p["treasury"] = float(p["treasury"]) - pay
		f["arrears"] = maxf(0.0, float(f["arrears"]) + (due - pay) - 0.0)
		if due <= pay and float(f["arrears"]) > 0.0:
			var clear := minf(float(f["arrears"]), float(p["treasury"]))
			p["treasury"] = float(p["treasury"]) - clear
			f["arrears"] = float(f["arrears"]) - clear
	# push: jobless, hungry or hunted residents walk away to the nearest town
	var sid := int((f["land"] as Dictionary).get("sid", -1))
	var mg := _mod("migration")
	if mg != null and sid >= 0 and pop > 20 and float(p.get("push", 0.0)) > 0.55 and float(p.get("J", 1.0)) < 0.7:
		var n := maxi(1, int(0.04 * pop))
		mg.call("send_wave", String(f["node"]), "s%d" % sid, n, "emigrants", "no work", "native", day)
	# residents open businesses when the demand is there and their savings can pay
	_open_businesses(f, pop)


func _open_businesses(f: Dictionary, pop: int) -> void:
	var bm := _mod("businesses")
	var om := _mod("organizations")
	var sid := int((f["land"] as Dictionary).get("sid", -1))
	if bm == null or om == null or sid < 0 or (f["biz"] as Array).size() >= BIZ_PER_FOUNDING or not om.has_method("spawn_actor") or not bm.has_method("found"):
		return
	var p := _place(f)
	for row: Array in BIZ_DEMAND:
		var kind := String(row[0])
		if pop < int(row[2]) or ("k:" + kind) in (f["pn"] as Dictionary):
			continue
		if kind == "workshop" and int(p.get("farms", 0)) < 1:
			continue
		var cost := int((bm.get("KINDS") as Dictionary)[kind]["cost"]) if bm.get("KINDS") is Dictionary else 300
		if float(f["sav"]) < float(cost + 40):
			continue
		var ch: String = om.call("spawn_actor", sid, String(row[3]), cost + 40)
		if ch == "":
			continue
		var res: Dictionary = bm.call("found", ch, kind, sid, "%s %s" % [String(f["name"]), kind.capitalize()], String(row[1]), cost, "autonomous")
		if bool(res.get("ok", false)):
			f["sav"] = float(f["sav"]) - float(cost + 40)
			(f["biz"] as Array).append(String(res["bz"]))
			(f["pn"] as Dictionary)["k:" + kind] = 1
			_ev("founding", f, "business", "a resident opens a %s at %s" % [kind, String(f["name"])], 2)
		return


func households(fid: int) -> Dictionary:
	var f: Dictionary = _f.get(fid, {})
	var p := _place(f)
	if f.is_empty() or p.is_empty():
		return {}
	var pop := _pop(f)
	var J := clampf(float(p.get("J", 1.0)), 0.0, 1.5)
	return {"people": pop, "households": maxi(1, int(round(float(pop) / 3.8))), "housing": int(p.get("housing", 0)), "workers": int(0.62 * pop),
		"employed": int(0.62 * pop * minf(1.0, J)), "jobless": int(0.62 * pop * maxf(0.0, 1.0 - J)), "savings": int(f["sav"]), "businesses": (f["biz"] as Array).size(),
		"pull": snappedf(float(p.get("pull", 0.0)), 0.01), "push": snappedf(float(p.get("push", 0.0)), 0.01)}


# ------------------------------------------------------------------ NPC founders

## A founder party looks for ground over six weeks (two candidate sites a week, so no week pays for twelve evaluations), then sets out.
func _npc_found(day: int) -> void:
	if _npc_left <= 0:
		var r0 := _rng("npcfound", day, 0)
		if day < NPC_FROM or day - _npc_day < NPC_GAP or active_count("npc") >= NPC_MAX or r0.randf() > NPC_P or WorldGen.settlements.is_empty():
			return
		_npc_left = 6
		_npc_best = Vector2.ZERO
		_npc_bs = -1.0
	var r := _rng("npcsite", day, _npc_left)
	var home: Dictionary = WorldGen.settlements[_rng("npchome", day / 21, 0).randi() % WorldGen.settlements.size()]
	for _i in 2:
		var ang := r.randf() * TAU
		var pos: Vector2 = (home["pos"] as Vector2) + Vector2(cos(ang), sin(ang)) * r.randf_range(450.0, 1300.0)
		if LandClaim.block_reason(pos) != "":
			continue
		var ev := evaluate_site(pos)
		if float(ev["overall"]) > _npc_bs and float(ev["camp"]) >= float(_mod("camps").get("MIN_CAMP_SCORE")) + 0.03:
			_npc_bs = float(ev["overall"])
			_npc_best = pos
	_npc_left -= 1
	if _npc_left > 0:
		return
	if _npc_bs >= 0.3 and active_count("npc") < NPC_MAX:
		var res := begin(_npc_best, "", "npc", "a company of settlers")
		if bool(res["ok"]):
			_npc_day = day


# ------------------------------------------------------------------ info for the UI

func info(fid: int) -> Dictionary:
	var f: Dictionary = _f.get(fid, {})
	if f.is_empty():
		return {}
	var e: Dictionary = f["esc"]
	return {"id": fid, "name": String(f["name"]), "stage": String(STAGES[int(f["st"])]), "stage_words": String(STAGE_WORDS[int(f["st"])]),
		"next": blockers(fid), "scale": scale_name(f), "facts": scale_facts(f) if String(f["node"]) != "" else {}, "services": services(f),
		"land": f["land"].duplicate(), "land_words": LandLaw.words(String(f["land"]["status"])), "rights": f["rights"].duplicate(),
		"escalation": String(ESC[int(e["step"])]), "escalation_words": String(ESC_WORDS[int(e["step"])]), "heat": snappedf(float(e["heat"]), 0.1),
		"visibility": float(e["vis"]), "pending": String(e["pend"]), "dues": float(f["dues"]), "arrears": snappedf(float(f["arrears"]), 0.1),
		"officials": f["off"].duplicate(true), "problems": problems(fid), "households": households(fid), "exposure": snappedf(float(f["expo"]), 0.1),
		"exposure_words": exposure_words(f), "petition": f["pet"].duplicate(), "history": f["hist"].duplicate(), "ended": int(f["end"]) >= 0, "why": String(f["why"])}


# ------------------------------------------------------------------ tick

func _step(f: Dictionary, day: int, n: float) -> Array:
	var msgs: Array = []
	if int(f["end"]) >= 0:
		return msgs
	var t0 := Time.get_ticks_usec() if prof_on else 0
	if String(f["node"]) != "":
		var p := _place(f)
		var pop := _pop(f)
		if p.is_empty() or bool(p.get("ruin", false)):
			_end(f, "ruin")
			return msgs
		if pop <= 0:
			f["zero"] = float(f["zero"]) + n
			if float(f["zero"]) >= 30.0:
				_end(f, "emptied")
				return msgs
		else:
			f["zero"] = 0.0
		var id := int(f["id"])
		var slow := n > 1.5 or (day + id) % 3 == 0          # slow tier: every third day, jittered by id, three days at once
		var n3 := n if n > 1.5 else 3.0
		if slow:
			var fb := _farms_built(f)
			if fb > int(f["farm_n"]):
				f["farm_n"] = fb
				if int(p["farms"]) < fb:
					p["farms"] = fb
		t0 = _pf("1 sync", t0)
		_escalate(f, day, n, msgs)
		t0 = _pf("2 escalate", t0)
		if int(f["end"]) >= 0:
			return msgs
		if n > 1.5 or (day + id) % 2 == 0:
			_problems_step(f, day, n if n > 1.5 else 2.0, msgs)
		t0 = _pf("3 problems", t0)
		if slow:
			_officials_step(f, n3, msgs)
			_scale_step(f, n3, msgs)
		t0 = _pf("4 scale", t0)
	_advance(f, day, msgs)
	_pf("5 advance", t0)
	return msgs


func _week_f(f: Dictionary, weeks: float, day: int, msgs: Array) -> void:
	if int(f["end"]) >= 0 or String(f["node"]) == "":
		return
	var t0 := Time.get_ticks_usec() if prof_on else 0
	if int(f["st"]) == 4:
		_recruit(f, day, msgs)
	t0 = _pf("w1 recruit", t0)
	_residents_week(f, weeks, day)
	t0 = _pf("w2 residents", t0)
	if bool(f["hid"]):
		_hidden_week(f, weeks, msgs)
	else:
		f["dw"] = maxf(0.0, float(f["dw"]) - 4.0 * weeks)
	_pf("w3 hidden", t0)


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


func tick_day_chunks(day: int, ctx: Dictionary) -> Array:
	_day = day
	_war = bool(ctx.get("at_war", false))
	ScatterExclusion.sync_founded(_f.values())   # abandoned/ended foundings free their ground again
	var act := ids(true)
	var out: Array = []
	var i := 0
	while i < act.size():
		var part: Array = act.slice(i, i + CHUNK)
		out.append(_chunk.bind(part, day))
		i += CHUNK
	return out


func _chunk(part: Array, day: int) -> Array:
	var msgs: Array = []
	for fid: int in part:
		var f: Dictionary = _f.get(fid, {})
		if not f.is_empty():
			msgs.append_array(_step(f, day, 1.0))
	return msgs


func tick_week(week: int, _ctx: Dictionary) -> Array:
	var msgs: Array = []
	var day := _day
	_waves_week = 0
	var order := ids(true)
	if not order.is_empty():
		var rot := week % order.size()           # who gets the one wave this week rotates
		order = order.slice(rot) + order.slice(0, rot)
	for fid: int in order:
		_week_f(_f[fid], 1.0, day, msgs)
	_npc_found(maxi(day, week * 7))
	return msgs


func catch_up(days: int, ctx: Dictionary) -> Array:
	_war = bool(ctx.get("at_war", false))
	_day += days
	var msgs: Array = []
	var weeks := float(days) / 7.0
	for fid: int in ids(true):
		var f: Dictionary = _f[fid]
		msgs.append_array(_step(f, _day, float(days)))
		if weeks >= 0.5:
			_week_f(f, weeks, _day, msgs)
	return msgs


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	var rows: Array = []
	for i in ids():
		rows.append(_f[i])
	return {"f": rows, "next": _next, "zones": _zones, "corrupt": _corrupt, "day": _day, "npc_day": _npc_day, "stats": stats}


func deserialize(d: Dictionary) -> void:
	_f = {}
	for r: Dictionary in d.get("f", []):
		var rec: Dictionary = r.duplicate(true)
		rec["id"] = int(rec["id"])
		_f[int(rec["id"])] = rec
	_next = int(d.get("next", 1))
	_zones = (d.get("zones", []) as Array).duplicate(true)
	ScatterExclusion.sync_founded(_f.values())
	_corrupt = (d.get("corrupt", {}) as Dictionary).duplicate(true)
	_day = int(d.get("day", 0))
	_npc_day = int(d.get("npc_day", -999))
	var s: Dictionary = d.get("stats", {})
	for k: String in stats:
		stats[k] = int(s.get(k, stats[k]))
