extends "res://scripts/realm/realm_module.gd"
## CIV-A (docs/design/CIVILIZATION.md): people on the move.
##   waves       push (war, monsters, famine, unrest, a cut-off town, decline) and pull (safety, jobs, boom, a place with room) move
##               groups along the road graph; they take days to arrive (pooled to MAX_WAVES active) and land as settlers or refugees
##   refugees    what a place cannot house waits in a refugee camp at its edge and is taken in slowly as housing allows
##   specialists named master smiths, scholars, healers, architects, trainers and commanders (cap MAX_SPECIALISTS in the region) come
##               to places famous in their field, stay for years, and leave when the place falls
##   districts   every place keeps culture shares per district; sustained inflow of one people names a quarter there
##   exchange    long contact adds foods, clothes and festivals of a culture to a place
## Reads realm/civilization.gd (push/pull, housing) and applies people through civilization.add_people, so settlements.gd stays the
## one owner of population. catch_up is a few aggregate steps, never a loop over days.

const MAX_WAVES := 16
const MAX_SPECIALISTS := 30
const MAX_NEWS := 40
const QUARTER_MIN := 36.0               # foreign inflow (people, fading) a place needs before newcomers form a quarter of their own
const QUARTER_WEEKS := 6.0              # ... held for this many weeks
const PULL_DELTA := 0.15                # attraction gain over its reference that draws settlers from neighbours
const PULL_P := 0.08                    # weekly chance a place that qualifies actually draws a group
const PULL_MIN := 14                    # smallest settler group worth a wave (no daily trickles)
const GOV_PUSH := 0.8                   # weight of governance.emigration_pressure in a place's push
const NEWS_MAG := {"wave": 0.3, "arrival": 0.2, "refugees": 1.5, "quarter": 2.0, "tradition": 1.5, "master": 0.6, "master_arrived": 1.0, "master_left": 1.0}
const FIELDS := ["smith", "scholar", "healer", "architect", "trainer", "commander"]
const TITLES := {"smith": "Master Smith", "scholar": "Scholar", "healer": "Healer", "architect": "Master Builder", "trainer": "Weapon-Master", "commander": "Captain"}
const FIRST := ["Orin", "Maela", "Tobin", "Isra", "Bram", "Yssa", "Corvin", "Hale", "Nessa", "Dorran", "Petra", "Alric", "Sable", "Wick", "Eda", "Kellan"]
const LAST := ["Vell", "Ashdown", "Hartle", "Quill", "Stormer", "Greaves", "Thorne", "Marrow", "Fenwick", "Dray", "Lockhart", "Penhale"]
const CULTURES := ["native", "sunreach", "frostmark", "beastfolk", "refugee"]
const CULTURE_NAMES := {"native": "Kingdom", "sunreach": "Sunreach", "frostmark": "Frostmark", "beastfolk": "Beastfolk", "refugee": "Refugee"}
const QUARTER_SUFFIX := ["Quarter", "Row", "Yard", "Hollow"]
## culture -> traditions it can lend a place, in the order they are adopted: food, clothes, festival, food, clothes
const TRADITIONS := {
	"sunreach": [["food", "saffron_rice"], ["clothes", "silk_sashes"], ["festival", "Lantern Night"], ["food", "spiced_lamb"], ["clothes", "dyed_robes"]],
	"frostmark": [["food", "smoked_fish"], ["clothes", "fur_cloaks"], ["festival", "Midwinter Fire"], ["food", "honey_mead"], ["clothes", "rune_belts"]],
	"beastfolk": [["food", "nut_bread"], ["clothes", "feather_trim"], ["festival", "Moonrun"], ["food", "river_stew"], ["clothes", "woven_charms"]],
	"refugee": [["food", "hearth_porridge"], ["clothes", "patched_cloaks"], ["festival", "Remembrance Night"]],
}
const EXPOSURE_STEP := 45.0          # share-days of contact per tradition adopted
const WAVE_KINDS := {"settlers": "", "workers": "miner", "merchants": "merchant", "mercenaries": "soldier", "researchers": "scholar", "criminals": "thief", "refugees": ""}

## Waves in flight: {id, from, to, n, kind, cause, culture, depart, arrive, origin}
var _waves: Array = []
var _next_wave := 1
## node -> {districts:[{name,n,mix,quarter}], infl:{culture:people}, sustain:{culture:weeks}, exp:{culture:share-days}, ado:[{kind,id,from,day}],
##          fame:{field:0..1}, ref:{n,since}, seen_ref:bool}
var _cult: Dictionary = {}
var _spec: Array = []
var _next_spec := 1
var _news: Array = []
var _next_news := 1
var _seq := 0                           # news.gd cursor counter (= last event id)
var _digest: Array = []
var _route_cache: Dictionary = {}       # transient: "a|b" -> {h, day}
var _mc: Dictionary = {}                # transient: node -> settled masters
var _mc_n := -1
var _mc_dirty := true
var _day := 0
var _inited := false
var _stat := {"waves": 0, "moved": 0, "refugees": 0}


func _rng(tag: String, day: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, str(id)])
	return r


func _mod(n: String) -> RefCounted:
	return hub.mod(n) if hub != null else null


func _civ() -> RefCounted:
	return _mod("civilization")


func _ensure() -> void:
	if _inited:
		return
	_inited = true
	var civ := _civ()
	if civ != null:
		civ.call("_ensure")
		for node in civ.call("place_ids"):
			_ensure_place(String(node))


func _hid(node: String) -> int:
	return int(node.substr(1))


# --------------------------------------------------------------- public getters

func active_waves() -> Array:
	return _waves


func waves_to(node: String) -> Array:
	return _waves.filter(func(w: Dictionary) -> bool: return String(w["to"]) == node)


func wave_progress(w: Dictionary, day: int) -> float:
	return clampf(float(day - int(w["depart"])) / maxf(1.0, float(int(w["arrive"]) - int(w["depart"]))), 0.0, 1.0)


func districts(node: String) -> Array:
	_ensure_place(node)
	return (_cult.get(node, {}).get("districts", []) as Array).duplicate(true)


func culture_shares(node: String) -> Dictionary:
	_ensure_place(node)
	var out := {}
	var total := 0.0
	for d: Dictionary in _cult.get(node, {}).get("districts", []):
		for c: String in d["mix"]:
			out[c] = float(out.get(c, 0.0)) + float(d["mix"][c]) * float(d["n"])
		total += float(d["n"])
	for c: String in out.keys():
		out[c] = snappedf(float(out[c]) / maxf(total, 1.0), 0.001)
	return out


func quarters(node: String) -> Array:
	return districts(node).filter(func(d: Dictionary) -> bool: return String(d["quarter"]) != "")


func is_mixed(node: String) -> bool:
	var n := 0
	for c: String in culture_shares(node):
		if float(culture_shares(node)[c]) >= 0.15:
			n += 1
	return n >= 2


func traditions(node: String) -> Array:
	return (_cult.get(node, {}).get("ado", []) as Array).duplicate(true)


func refugees_at(node: String) -> int:
	return int(_cult.get(node, {}).get("ref", {}).get("n", 0))


func refugee_camps() -> Array:
	var out: Array = []
	var civ := _civ()
	for node: String in _cult:
		var n := refugees_at(node)
		if n >= 12 and civ != null:
			out.append({"node": node, "n": n, "pos": civ.call("pos_of", node), "since": int(_cult[node]["ref"].get("since", 0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["node"]) < String(b["node"]))
	return out


func specialists(node := "") -> Array:
	return _spec.filter(func(m: Dictionary) -> bool: return node == "" or String(m["at"]) == node)


func master_count(node: String) -> int:
	if _mc_n != _spec.size() or _mc_dirty:
		_mc = {}
		for m: Dictionary in _spec:
			if String(m["state"]) == "settled":
				_mc[String(m["at"])] = int(_mc.get(String(m["at"]), 0)) + 1
		_mc_n = _spec.size()
		_mc_dirty = false
	return int(_mc.get(node, 0))


func master_bonus(node: String, field: String) -> float:
	var b := 0.0
	for m: Dictionary in _spec:
		if String(m["at"]) == node and String(m["state"]) == "settled" and String(m["field"]) == field:
			b += 0.12
	return minf(b, 0.4)


func fame_of(node: String, field: String) -> float:
	return float(_cult.get(node, {}).get("fame", {}).get(field, 0.0))


func stats() -> Dictionary:
	return _stat.duplicate()


func news_events(since := 0) -> Array:
	return _news if since <= 0 else _news.filter(func(e: Dictionary) -> bool: return int(e["seq"]) > since)


func news_since(last_id: int) -> Array:
	return _news.filter(func(e: Dictionary) -> bool: return int(e["id"]) > last_id)


func digest() -> Array:
	return _digest


## Test/sim and story hook: send a wave now. `cause` is free text ("war", "monsters", ...); returns the wave or {}.
func send_wave(from: String, to: String, n: int, kind := "settlers", cause := "", culture := "native", day := -1) -> Dictionary:
	_ensure()
	var d := _day if day < 0 else day
	if _waves.size() >= MAX_WAVES or n <= 0:
		return {}
	var civ := _civ()
	if civ == null or not bool(civ.call("has_place", to)):
		return {}
	var hours := _hours(from, to, d)
	if hours < 0.0:
		return {}
	if from != "" and bool(civ.call("has_place", from)):
		n = -int(civ.call("add_people", from, -n, "", d))
		if n <= 0:
			return {}
	var w := {"id": _next_wave, "from": from, "to": to, "n": n, "kind": kind, "cause": cause, "culture": culture, "depart": d,
		"arrive": d + maxi(2, int(ceil(hours * 0.8))), "origin": culture}
	_next_wave += 1
	_waves.append(w)
	_stat["waves"] = int(_stat["waves"]) + 1
	var fname := String(civ.call("name_of", from)) if from != "" and bool(civ.call("has_place", from)) else "the roads"
	var line := "A group of %d %s left %s for %s%s." % [n, kind, fname, civ.call("name_of", to), " (%s)" % cause if cause != "" else ""]
	_news_add("wave", to, line, d)
	return w


# --------------------------------------------------------------- places: districts and culture

func _ensure_place(node: String) -> void:
	if _cult.has(node):
		return
	var civ := _civ()
	if civ == null or not bool(civ.call("has_place", node)):
		return
	var p: Dictionary = civ.call("place", node)
	var pop := maxi(1, int(civ.call("population", node)))
	var r := _rng("cult", 0, node)
	var names: Array = ["Camp"]
	if not bool(p["dyn"]):
		var kind := String(WorldGen.settlements[int(p["sid"])]["kind"])
		names = {"castle": ["Keep Ward", "Market Ward", "Low Town"], "town": ["Old Town", "Market Row", "Riverside"],
			"frontier_town": ["Garrison Yard", "Old Town"], "village": ["Village Green"]}.get(kind, ["Village Green"])
	var ds: Array = []
	var share := 1.0 / float(names.size())
	for i in names.size():
		var mix := {"native": 1.0}
		# trading towns and the capital always had a few foreign families
		if not bool(p["dyn"]) and names.size() >= 2 and i == names.size() - 1:
			var c: String = ["sunreach", "frostmark", "beastfolk"][r.randi() % 3]
			mix = {"native": 0.9, c: 0.1}
		ds.append({"name": names[i], "n": int(pop * share), "mix": mix, "quarter": ""})
	_cult[node] = {"districts": ds, "infl": {}, "sustain": {}, "exp": {}, "ado": [], "fame": {}, "ref": {"n": 0, "since": 0}, "seen_ref": false}


func _normalize(node: String, pop: int) -> void:
	var ds: Array = _cult[node]["districts"]
	var total := 0.0
	for d: Dictionary in ds:
		total += float(d["n"])
	if total <= 0.0:
		return
	var k := float(pop) / total
	for d: Dictionary in ds:
		d["n"] = int(round(float(d["n"]) * k))


## Newcomers settle in a quarter of their own people if there is one, else in the outermost district.
func _absorb(node: String, culture: String, m: int) -> void:
	_ensure_place(node)
	if not _cult.has(node) or m <= 0:
		return
	var cd: Dictionary = _cult[node]
	var ds: Array = cd["districts"]
	var target: Dictionary = ds[ds.size() - 1]
	for d: Dictionary in ds:
		if String(d["quarter"]) == culture:
			target = d
			break
	if String(target["quarter"]) != "" and String(target["quarter"]) != culture:
		for d: Dictionary in ds:
			if String(d["quarter"]) == "":
				target = d
	var n0 := float(target["n"])
	var mix: Dictionary = target["mix"]
	for c: String in mix.keys():
		mix[c] = float(mix[c]) * n0 / (n0 + m)
	mix[culture] = float(mix.get(culture, 0.0)) + float(m) / (n0 + m)
	target["n"] = int(n0) + m
	var infl: Dictionary = cd["infl"]
	infl[culture] = float(infl.get(culture, 0.0)) + m


func _quarter_name(node: String, culture: String) -> String:
	var r := _rng("quarter", _day, node + culture)
	return "%s %s" % [CULTURE_NAMES[culture], QUARTER_SUFFIX[r.randi() % QUARTER_SUFFIX.size()]]


# --------------------------------------------------------------- waves

func _hours(from: String, to: String, day: int) -> float:
	var cm := _mod("camps")
	var civ := _civ()
	if civ != null and (bool(civ.call("is_isolated", to)) or (from != "" and bool(civ.call("is_isolated", from)))):
		return -1.0
	if cm == null:
		return 6.0
	var src := from
	if src == "":
		src = _outside_entry(to)
		if src == "":
			return 6.0
	var key := "%s|%s" % [src, to]
	var c: Dictionary = _route_cache.get(key, {})
	if not c.is_empty() and day - int(c["day"]) < 30:
		return float(c["h"])
	var path: Array = cm.call("route", src, to)
	var h := -1.0
	if not path.is_empty():
		h = float(cm.call("travel_hours", src, to))
	_route_cache[key] = {"h": h, "day": day}
	return h


## A big settlement on the road network nearest the place: where "the outside world" walks in from.
func _outside_entry(to: String) -> String:
	var civ := _civ()
	if civ == null:
		return ""
	var best := ""
	var bd := INF
	var at: Vector2 = civ.call("pos_of", to)
	for node in civ.call("place_ids"):
		var p: Dictionary = civ.call("place", String(node))
		if String(node) == to or bool(p["ruin"]) or bool(p["dyn"]) or int(p["tier"]) < 3:
			continue
		var d := at.distance_squared_to(civ.call("pos_of", String(node)))
		if d < bd:
			bd = d
			best = String(node)
	return best


## Civilization's push plus governance's emigration pressure (harsh laws, angry blocs, strikes) for a static place (null-guarded).
func _push_total(node: String, p: Dictionary) -> float:
	var push := float(p["push"])
	var gov: RefCounted = hub.mod("governance") if hub != null else null
	if gov != null and gov.has_method("emigration_pressure") and not bool(p["dyn"]):
		push = clampf(push + GOV_PUSH * maxf(0.0, float(gov.call("emigration_pressure", int(p["sid"]))) - 0.25), 0.0, 1.0)
	return push


func _cause_of(p: Dictionary) -> String:
	var opts := {"war": 0.6 * float(p["war"]), "monsters": 0.5 * float(p["monster"]), "famine": 0.3 if float(p["famine"]) > 10.0 else 0.0,
		"hard times": 0.9 * float(p["unrest"]), "isolation": 0.3 * minf(1.0, float(p["cut"]) / 120.0), "harsh rule": float(p.get("gov_push", 0.0)), "decline": 0.25 * maxf(0.0, float(p["ref"]) - float(p["attr"])) * 2.0}
	var best := "hard times"
	var bv := -1.0
	for k: String in ["war", "monsters", "famine", "hard times", "isolation", "harsh rule", "decline"]:
		if float(opts[k]) > bv:
			bv = float(opts[k])
			best = k
	return best


func _pick_dest(civ: RefCounted, from: String, r: RandomNumberGenerator) -> String:
	var src_pull := float(civ.call("pull_of", from))
	var at: Vector2 = civ.call("pos_of", from)
	var best := ""
	var bs := -INF
	for node in civ.call("place_ids"):
		var p: Dictionary = civ.call("place", String(node))
		if String(node) == from or bool(p["ruin"]):
			continue
		var pull := float(p["pull"])
		var dist: float = at.distance_to(civ.call("pos_of", String(node)))
		var sc := pull - 0.00007 * dist + 0.03 * r.randf() - (0.25 if float(p["H"]) > 1.15 else 0.0)
		if pull > src_pull + 0.04 and sc > bs:
			bs = sc
			best = String(node)
	return best


func _composition(r: RandomNumberGenerator, p: Dictionary) -> String:
	var x := r.randf()
	var rich := false
	for d: Dictionary in p["res"]:
		if String(d["kind"]) in ["rift_crystal", "silver"]:
			rich = true
	if x < 0.45:
		return "workers"
	if x < 0.65:
		return "merchants"
	if x < 0.80:
		return "mercenaries"
	if x < 0.90:
		return "researchers" if rich or r.randf() < 0.5 else "settlers"
	return "criminals"


func _eval_place(node: String, day: int, weeks: float) -> Array:
	var out: Array = []
	var civ := _civ()
	if civ == null or not bool(civ.call("has_place", node)):
		return out
	_ensure_place(node)
	var p: Dictionary = civ.call("place", node)
	var cd: Dictionary = _cult[node]
	var pop := int(civ.call("population", node))
	if bool(p["ruin"]):
		cd["ref"] = {"n": 0, "since": 0}
		return out
	var r := _rng("eval", day, node)
	var pname := String(p["name"])
	_normalize(node, pop)
	# 1. push: people leave a place in trouble
	var push := _push_total(node, p)
	p["gov_push"] = 0.5 * (push - float(p["push"]))
	if push > 0.35 and pop >= 30:
		cd["emi"] = float(cd.get("emi", 0.0)) + float(pop) * (push - 0.25) * 0.035 * weeks
	else:
		cd["emi"] = float(cd.get("emi", 0.0)) * pow(0.9, weeks)
	if float(cd["emi"]) >= maxf(8.0, 0.04 * float(pop)) and _waves.size() < MAX_WAVES:
		var n := int(cd["emi"])
		var to := _pick_dest(civ, node, r)
		if to != "":
			var cause := _cause_of(p)
			var kind := "refugees" if cause in ["war", "monsters", "famine"] else "settlers"
			var w := send_wave(node, to, n, kind, cause, "refugee" if kind == "refugees" else _dominant_culture(node), day)
			if not w.is_empty():
				cd["emi"] = float(cd["emi"]) - float(w["n"])
				out.append("%d people are leaving %s%s." % [int(w["n"]), pname, " (%s)" % cause])
	# 2. boom: merchants, workers, mercenaries, researchers and criminals walk in from the wider kingdom
	var boom := float(civ.call("boom_of", node, day).get("power", 0.0))
	if boom > 0.15 and float(p["H"]) < 1.12 and refugees_at(node) < pop / 2 + 10 and _waves.size() < MAX_WAVES and r.randf() < 1.0 - pow(0.8, weeks):
		var kind2 := _composition(r, p)
		var n2 := maxi(8, int((4.0 + 18.0 * boom) * weeks * (0.7 + 0.6 * r.randf())))
		var cul := _roll_culture(r)
		var w2 := send_wave("", node, n2, kind2, "boom", cul, day)
		if not w2.is_empty():
			out.append("A group of %d %s is heading for %s." % [n2, kind2, pname])
	# 3. pull: a place that has grown more attractive than its neighbours draws settlers from them
	var delta := float(p["attr"]) - float(p["ref"])
	if delta > PULL_DELTA and float(p["H"]) < 1.05 and _waves.size() < MAX_WAVES and r.randf() < 1.0 - pow(1.0 - PULL_P, weeks):
		var src := _pick_source(civ, node, r)
		if src != "":
			var spop := int(civ.call("population", src))
			var n3 := int(minf(float(spop) * 0.03, 4.0 + 60.0 * delta) * weeks)
			if n3 >= PULL_MIN:
				send_wave(src, node, n3, "settlers", "better prospects", _dominant_culture(src), day)
	# 4. refugees in the camp are taken in as housing allows
	out.append_array(_refugees_week(civ, node, p, pop, weeks, day, r))
	# 5. quarters, exchange, specialists
	out.append_array(_culture_week(civ, node, p, pop, weeks, day))
	out.append_array(_specialists_week(node, p, weeks, day, r))
	return out


func _pick_source(civ: RefCounted, to: String, r: RandomNumberGenerator) -> String:
	var at: Vector2 = civ.call("pos_of", to)
	var best := ""
	var bs := -INF
	for node in civ.call("place_ids"):
		var q: Dictionary = civ.call("place", String(node))
		if String(node) == to or bool(q["ruin"]) or int(civ.call("population", String(node))) < 60:
			continue
		var dist: float = at.distance_to(civ.call("pos_of", String(node)))
		if dist > 2600.0:
			continue
		var sc := (float(q["ref"]) - float(q["attr"])) * 2.0 + float(q["push"]) - 0.0003 * dist + 0.05 * r.randf() + 0.0002 * float(civ.call("population", String(node)))
		if sc > bs:
			bs = sc
			best = String(node)
	return best


func _dominant_culture(node: String) -> String:
	var best := "native"
	var bv := -1.0
	var sh := culture_shares(node)
	for c: String in CULTURES:
		if float(sh.get(c, 0.0)) > bv:
			bv = float(sh.get(c, 0.0))
			best = c
	return best


func _roll_culture(r: RandomNumberGenerator) -> String:
	var x := r.randf()
	if x < 0.5:
		return "native"
	if x < 0.72:
		return "sunreach"
	if x < 0.9:
		return "frostmark"
	return "beastfolk"


# --------------------------------------------------------------- arrival

func _arrivals(day: int) -> Array:
	var out: Array = []
	var civ := _civ()
	if civ == null:
		return out
	var i := _waves.size() - 1
	var landed: Array = []
	while i >= 0:
		var w: Dictionary = _waves[i]
		if int(w["arrive"]) <= day:
			landed.append(w)
			_waves.remove_at(i)
		i -= 1
	landed.reverse()
	for w: Dictionary in landed:
		out.append_array(_land(civ, w, day))
	return out


func _land(civ: RefCounted, w: Dictionary, day: int) -> Array:
	var out: Array = []
	var to := String(w["to"])
	var n := int(w["n"])
	if not bool(civ.call("has_place", to)) or bool(civ.call("is_ruin", to)):
		return out
	_ensure_place(to)
	var p: Dictionary = civ.call("place", to)
	var pname := String(p["name"])
	var occ: String = WAVE_KINDS.get(String(w["kind"]), "")
	var pop := int(civ.call("population", to))
	var room := int(float(p["housing"]) * 1.08) - pop
	var take := n
	if String(w["kind"]) == "refugees" or room < n:
		take = clampi(room, 0, n)
		if String(w["kind"]) == "refugees":
			take = clampi(room, 0, int(n * 0.5))
	var rest := n - take
	var got := int(civ.call("add_people", to, take, occ, day)) if take > 0 else 0
	if got > 0:
		_absorb(to, String(w["culture"]), got)
		_stat["moved"] = int(_stat["moved"]) + got
	if rest > 0:
		var cd: Dictionary = _cult[to]
		var ref: Dictionary = cd["ref"]
		if int(ref["n"]) == 0:
			ref["since"] = day
		ref["n"] = int(ref["n"]) + rest
		ref["cul"] = String(w["culture"]) if String(w["kind"]) != "refugees" else "refugee"
		_stat["refugees"] = int(_stat["refugees"]) + rest
		p["refugees"] = int(ref["n"])
	var txt := "%d %s have reached %s" % [n, String(w["kind"]), pname]
	if rest > 0:
		txt += "; %d wait outside the walls for housing" % rest
	txt += "."
	if String(w["kind"]) == "criminals":
		txt = "%d newcomers of doubtful trade have come to %s." % [n, pname]
	_news_add("arrival", to, txt, day)
	if n >= 20 or rest > 0:
		out.append(txt)
	return out


func _refugees_week(civ: RefCounted, node: String, p: Dictionary, pop: int, weeks: float, day: int, _r: RandomNumberGenerator) -> Array:
	var out: Array = []
	var ref: Dictionary = _cult[node]["ref"]
	var n := int(ref["n"])
	if n <= 0:
		p["refugees"] = 0
		return out
	var room := maxi(0, int(float(p["housing"]) * 0.97) - pop)
	var take := mini(n, int(ceil(float(mini(room, n)) * (1.0 - pow(0.6, weeks)))))
	if take > 0:
		var got := int(civ.call("add_people", node, take, "", day))
		if got > 0:
			_absorb(node, String(ref.get("cul", "refugee")), got)
			n -= got
	var attr := int(ceil(float(n) * (1.0 - pow(0.94, weeks))))
	n = maxi(0, n - attr)
	ref["n"] = n
	p["refugees"] = n
	if n >= 12 and not bool(_cult[node]["seen_ref"]):
		_cult[node]["seen_ref"] = true
		var line := "A refugee camp has formed outside %s." % String(p["name"])
		_news_add("refugees", node, line, day)
		out.append(line)
	elif n < 6:
		_cult[node]["seen_ref"] = false
	if n > 0:
		civ.call("add_pressure", node, "law", minf(0.02, 0.0004 * float(n) * weeks))
	return out


func _culture_week(_civ_ref: RefCounted, node: String, p: Dictionary, pop: int, weeks: float, day: int) -> Array:
	var out: Array = []
	var cd: Dictionary = _cult[node]
	var infl: Dictionary = cd["infl"]
	var sustain: Dictionary = cd["sustain"]
	var ds: Array = cd["districts"]
	# inflow memory fades, quarters form from sustained inflow
	for c: String in infl.keys():
		infl[c] = float(infl[c]) * pow(0.96, weeks)
		if c == "native":
			continue
		var has_q := false
		for d: Dictionary in ds:
			if String(d["quarter"]) == c:
				has_q = true
		var thr := maxf(QUARTER_MIN, 0.10 * float(pop))
		if float(infl[c]) >= thr and not has_q and ds.size() < 5:
			sustain[c] = float(sustain.get(c, 0.0)) + weeks
			if float(sustain[c]) >= QUARTER_WEEKS:
				var take := int(minf(float(infl[c]), float(pop) * 0.3))
				var src: Dictionary = ds[ds.size() - 1]
				src["n"] = maxi(0, int(src["n"]) - take)
				var qn := _quarter_name(node, c)
				ds.append({"name": qn, "n": take, "mix": {c: 0.85, "native": 0.15}, "quarter": c})
				sustain.erase(c)
				var line := "Newcomers from %s have settled together in %s; people call it the %s." % [CULTURE_NAMES[c], String(p["name"]), qn]
				_news_add("quarter", node, line, day)
				out.append(line)
		else:
			sustain[c] = maxf(0.0, float(sustain.get(c, 0.0)) - weeks)
	# districts grow with the place
	var tier := int(p["tier"])
	var named := 0
	for d: Dictionary in ds:
		if String(d["quarter"]) == "":
			named += 1
	var want := 1 + (1 if tier >= 2 else 0) + (1 if tier >= 3 else 0)
	if named < want and bool(p["dyn"]):
		var nm: String = ["Market Row", "Low Town", "Hill Ward"][named - 1 if named >= 1 else 0]
		ds.insert(maxi(0, ds.size() - 1), {"name": nm, "n": int(pop * 0.25), "mix": {"native": 1.0}, "quarter": ""})
	# cultural exchange: contact time becomes foods, clothes and festivals
	var ex: Dictionary = cd["exp"]
	var shares := culture_shares(node)
	for c: String in shares.keys():
		if c == "native" or float(shares[c]) < 0.04:
			continue
		ex[c] = float(ex.get(c, 0.0)) + float(shares[c]) * weeks * 7.0
		var have := 0
		for a: Dictionary in cd["ado"]:
			if String(a["from"]) == c:
				have += 1
		var pool: Array = TRADITIONS.get(c, [])
		if have < pool.size() and float(ex[c]) >= EXPOSURE_STEP * float(have + 1):
			var item: Array = pool[have]
			(cd["ado"] as Array).append({"kind": item[0], "id": item[1], "from": c, "day": day})
			var line2 := "%s now keeps %s, a festival of the %s." % [String(p["name"]), item[1], CULTURE_NAMES[c]]
			if item[0] == "food":
				line2 = "%s has taken to %s, a dish of the %s." % [String(p["name"]), String(item[1]).replace("_", " "), CULTURE_NAMES[c]]
			elif item[0] == "clothes":
				line2 = "In %s they wear %s now, in the %s style." % [String(p["name"]), String(item[1]).replace("_", " "), CULTURE_NAMES[c]]
			_news_add("tradition", node, line2, day)
			if tier >= 2:
				out.append(line2)
	return out


# --------------------------------------------------------------- specialists

func _fame_target(p: Dictionary, field: String) -> float:
	var stl := _mod("settlements")
	var idt := {}
	if stl != null and not bool(p["dyn"]):
		idt = stl.call("identity", int(p["sid"]))
	var built: Dictionary = p["built"]
	var tier := float(p["tier"])
	var iron := 0.0
	for d: Dictionary in p["res"]:
		if bool(d["dev"]) and String(d["kind"]) in ["iron", "silver"]:
			iron = 1.0
	var t := 0.0
	match field:
		"smith":
			t = 0.6 * float(idt.get("mining", 0.0)) + 0.35 * iron + 0.06 * tier
		"scholar":
			t = 0.8 * float(idt.get("scholarly", 0.0)) + 0.35 * float(built.get("school", 0)) + 0.03 * tier
		"healer":
			t = 0.7 * float(idt.get("religious", 0.0)) + 0.1 * float(built.get("well", 0)) + 0.04 * tier
		"architect":
			t = 0.05 * tier + 0.04 * float(mini(8, int(built.get("house", 0)) + int(built.get("wall", 0)) * 2))
		"trainer":
			t = 0.6 * float(idt.get("fortress", 0.0)) + 0.09 * float(p["walls"]) + 0.3 * minf(1.0, float(p["patrol"]))
		"commander":
			t = 0.6 * float(idt.get("fortress", 0.0)) + 0.4 * float(p["war"]) + 0.03 * tier
	return clampf(t + (0.12 if master_fields_has(String(p["node"]), field) else 0.0), 0.0, 1.0)


func master_fields_has(node: String, field: String) -> bool:
	for m: Dictionary in _spec:
		if String(m["at"]) == node and String(m["field"]) == field:
			return true
	return false


func _specialists_week(node: String, p: Dictionary, weeks: float, day: int, r: RandomNumberGenerator) -> Array:
	var out: Array = []
	var cd: Dictionary = _cult[node]
	var fame: Dictionary = cd["fame"]
	var k := 1.0 - exp(-0.012 * 7.0 * weeks)
	var best_field := ""
	var bf := 0.0
	for f: String in FIELDS:
		var tgt := _fame_target(p, f)
		fame[f] = float(fame.get(f, 0.0)) + (tgt - float(fame.get(f, 0.0))) * k
		if float(fame[f]) >= 0.42 and not master_fields_has(node, f) and float(fame[f]) > bf:
			bf = float(fame[f])
			best_field = f
	if best_field == "" or _spec.size() >= MAX_SPECIALISTS or int(p["tier"]) < 1:
		return out
	if r.randf() >= 1.0 - pow(0.88, weeks):
		return out
	var from_node := _outside_entry(node)
	var hours := _hours("", node, day)
	var arrive_in := maxi(6, int(ceil(maxf(hours, 4.0) * 1.5)))
	var nm := "%s %s %s" % [TITLES[best_field], FIRST[r.randi() % FIRST.size()], LAST[r.randi() % LAST.size()]]
	var life := 365 * r.randi_range(6, 22)
	var m := {"id": _next_spec, "name": nm, "field": best_field, "at": node, "from": from_node, "state": "travelling", "arrive": day + arrive_in,
		"left_day": day + arrive_in + life, "age0": r.randi_range(32, 58)}
	_next_spec += 1
	_spec.append(m)
	var line := "%s is on the road to %s, drawn by its name for %s." % [nm, String(p["name"]), _field_words(best_field)]
	_news_add("master", node, line, day)
	out.append(line)
	return out


static func _field_words(f: String) -> String:
	return {"smith": "good iron", "scholar": "learning", "healer": "healing", "architect": "building", "trainer": "arms training", "commander": "soldiering"}.get(f, f)


func _specialists_day(day: int) -> Array:
	var out: Array = []
	var civ := _civ()
	var i := _spec.size() - 1
	while i >= 0:
		var m: Dictionary = _spec[i]
		var node := String(m["at"])
		var gone := civ == null or not bool(civ.call("has_place", node)) or bool(civ.call("is_ruin", node))
		if String(m["state"]) == "travelling":
			if gone:
				_spec.remove_at(i)
			elif int(m["arrive"]) <= day:
				m["state"] = "settled"
				_mc_dirty = true
				var line := "%s has settled in %s." % [m["name"], civ.call("name_of", node)]
				_news_add("master_arrived", node, line, day)
				out.append(line)
		else:
			var fell := civ != null and not gone and int(civ.call("tier", node)) < 1 and fame_of(node, String(m["field"])) < 0.2
			if gone or fell or int(m["left_day"]) <= day:
				var why := "has died" if int(m["left_day"]) <= day and not gone else "has left %s" % (civ.call("name_of", node) if civ != null else node)
				var line2 := "%s %s." % [m["name"], why]
				_news_add("master_left", node, line2, day)
				out.append(line2)
				_spec.remove_at(i)
		i -= 1
	return out


# --------------------------------------------------------------- news

func _news_add(kind: String, node: String, text: String, day: int) -> void:
	var civ := _civ()
	var sid := int(civ.call("news_sid", node)) if civ != null else -1
	_news.append({"id": _next_news, "seq": _next_news, "day": day, "kind": kind, "node": node, "name": String(civ.call("name_of", node)) if civ != null else node,
		"text": text, "sid": sid, "mag": float(NEWS_MAG.get(kind, 1.0)), "detail": "", "official": false})
	_seq = _next_news
	_next_news += 1
	if _news.size() > MAX_NEWS:
		_news.pop_front()


# --------------------------------------------------------------- ticks

func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


func tick_day_chunks(day: int, _ctx: Dictionary) -> Array:
	_ensure()
	var chunks: Array = []
	chunks.append(func() -> Array: return _day_core(day))
	var civ := _civ()
	if civ != null:
		for node in civ.call("place_ids"):
			var nd := String(node)
			if (day + _hid(nd) * 5) % 7 == 0:
				chunks.append(func() -> Array: return _eval_place(nd, day, 1.0))
	return chunks


func _day_core(day: int) -> Array:
	_day = maxi(_day, day)
	var out := _arrivals(day)
	out.append_array(_specialists_day(day))
	return out


var _news0 := 0
var _driven := -1                       # window length civilization.catch_up already drove through catch_begin/step/end


## civilization.catch_up steps this module inside each of its windows (waves then meet the housing the place has at that time);
## a standalone catch_up (no civilization) runs the same three calls itself.
func catch_begin(days: int) -> void:
	_ensure()
	_digest = []
	_news0 = _next_news
	_driven = days


func catch_step(to_day: int, span: int) -> void:
	var civ := _civ()
	if civ == null:
		return
	_day = to_day
	_arrivals(to_day)
	for node in civ.call("place_ids"):
		_eval_place(String(node), to_day, float(span) / 7.0)
	_specialists_day(to_day)


func catch_end(end_day: int) -> void:
	_arrivals(end_day)   # waves sent during the window that were already due by its end
	var rank := {"refugees": 0, "quarter": 1, "master_arrived": 2, "wave": 3, "tradition": 4, "arrival": 5, "master": 6, "master_left": 7}
	var evs := _news.filter(func(e: Dictionary) -> bool: return int(e["id"]) >= _news0 and String(e["kind"]) != "wave")
	evs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(rank.get(a["kind"], 9)) < int(rank.get(b["kind"], 9)))
	for e: Dictionary in evs:
		if _digest.size() >= 8:
			break
		_digest.append(String(e["text"]))


func catch_up(days: int, _ctx: Dictionary) -> Array:
	_ensure()
	if _driven == days:
		_driven = -1
		return _digest.duplicate()
	_driven = -1
	if days < 1 or _civ() == null:
		_digest = []
		return _digest
	catch_begin(days)
	_driven = -1
	var steps := clampi(int(ceil(float(days) / 14.0)), 1, 8)
	var start := _day
	for k in steps:
		var to_day := start + int(round(float(k + 1) * float(days) / float(steps)))
		catch_step(to_day, to_day - (start + int(round(float(k) * float(days) / float(steps)))))
	catch_end(start + days)
	return _digest.duplicate()


# --------------------------------------------------------------- save

func serialize() -> Dictionary:
	var cu := {}
	for node: String in _cult:
		cu[node] = (_cult[node] as Dictionary).duplicate(true)
	return {"waves": _waves.duplicate(true), "next_wave": _next_wave, "cult": cu, "spec": _spec.duplicate(true), "next_spec": _next_spec,
		"news": _news.duplicate(true), "next_news": _next_news, "digest": _digest.duplicate(), "day": _day, "inited": _inited, "stat": _stat.duplicate()}


func deserialize(d: Dictionary) -> void:
	_waves = (d.get("waves", []) as Array).duplicate(true)
	for w: Dictionary in _waves:
		for k in ["id", "n", "depart", "arrive"]:
			w[k] = int(w[k])
	_next_wave = int(d.get("next_wave", 1))
	_cult = (d.get("cult", {}) as Dictionary).duplicate(true)
	for node: String in _cult:
		for dd: Dictionary in _cult[node]["districts"]:
			dd["n"] = int(dd["n"])
		_cult[node]["ref"]["n"] = int(_cult[node]["ref"]["n"])
		_cult[node]["ref"]["since"] = int(_cult[node]["ref"]["since"])
	_spec = (d.get("spec", []) as Array).duplicate(true)
	for m: Dictionary in _spec:
		for k in ["id", "arrive", "left_day", "age0"]:
			m[k] = int(m[k])
	_next_spec = int(d.get("next_spec", 1))
	_news = (d.get("news", []) as Array).duplicate(true)
	_next_news = int(d.get("next_news", 1))
	_seq = _next_news - 1
	for e: Dictionary in _news:   # saves from before news.gd wiring
		if not e.has("seq"):
			e["seq"] = int(e["id"])
			e["sid"] = -1
			e["mag"] = float(NEWS_MAG.get(String(e["kind"]), 1.0))
	_digest = (d.get("digest", []) as Array).duplicate()
	_day = int(d.get("day", 0))
	_inited = bool(d.get("inited", false))
	_stat = (d.get("stat", {"waves": 0, "moved": 0, "refugees": 0}) as Dictionary).duplicate()
	_route_cache = {}
	_mc_dirty = true
