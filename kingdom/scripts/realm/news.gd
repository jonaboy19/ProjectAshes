extends "res://scripts/realm/realm_module.gd"
## Information (docs/design/CIVILIZATION.md CIV-B): rumours with incomplete facts that sharpen as they spread along
## roads, regional news for taverns, notice boards and travellers with delay, fame travelling at road speed per
## settlement, social titles (a nickname emerges from deeds, spreads, becomes established, then formal through
## sim/titles.gd), and political marriages / delegations / embassies as data events (presentation comes later).
##
## Extends realm/society.gd instead of duplicating it: road adjacency, `learn`, player deed rumours and
## `fame_at` come from society. News items store only the facts; what a listener hears is computed from
## (road distance, days since the event), so propagation is closed form: nothing is stored per hop, catch_up
## has nothing to replay, and saves stay small.
##
## Sources: other modules' `news_events()` (governance, notables, and -- when present -- civilization,
## migration, ecology) are consumed with a cursor on each event's "seq". Anything can also call post().

const Soc := preload("res://scripts/realm/society.gd")
const Titles := preload("res://scripts/sim/titles.gd")
const SAVE_VERSION := 1
const ROAD_SPEED := 500.0        # world units per day for rumours carried by travellers
const COURIER_SPEED := 1000.0    # official notices
const SHARPEN_UNITS := 1200.0    # extra road distance that adds one level of detail
const SHARPEN_DAYS := 5.0
const ITEM_CAP := 70
const ITEM_LIFE := 120
const FAME_CAP := 100
const FAME_SCALE := 1800.0
const NICK_AT := 4.5
const SUBJECT_CAP := 40
const DIP_CAP := 32

const SOURCES := ["governance", "notables", "civilization", "migration", "ecology"]
const VAGUE := {
	"expedition_lost": "Folk whisper that an expedition has vanished somewhere %s.",
	"expedition_missing": "Word is that a party is overdue somewhere %s.",
	"expedition_out": "A party went out %s of here, they say.",
	"expedition_return": "Somebody came back from the wilds %s with crates of salvage.",
	"expedition_rescued": "A party everyone feared lost was found %s.",
	"crisis": "Something is wrong %s. Travellers will not say what.",
	"crisis_failed": "Something terrible happened %s.",
	"crisis_resolved": "Trouble %s has been put down, by somebody.",
	"succession": "Somebody new sits in a chair %s.",
	"revolt": "There has been shouting, and worse, %s.",
	"strike": "There is a stoppage %s, they say.",
	"petition": "Folk %s are muttering over their laws.",
	"law": "They have changed a law %s.",
	"founded_org": "Somebody has founded something new %s.",
	"research_done": "Scholars %s found something useful.",
	"relic_lead": "Odd gear has been seen %s.",
	"caravan_lost": "Something destroyed a caravan %s.",
	"delegation": "Fine carriages were seen on the road %s.",
	"marriage": "They say two great houses are to be joined, somewhere %s.",
	"embassy": "Foreigners are settling in %s.",
}
const NOUN := {
	"expedition_lost": "a vanished expedition", "expedition_missing": "an overdue expedition", "expedition_out": "an expedition setting out",
	"expedition_return": "an expedition's return", "expedition_rescued": "a rescue", "crisis": "trouble", "crisis_failed": "a disaster",
	"crisis_resolved": "a problem solved", "succession": "a new ruler", "revolt": "a revolt", "strike": "a strike", "petition": "a petition",
	"law": "a new law", "founded_org": "a new foundation", "research_done": "a discovery", "relic_lead": "strange relics",
	"delegation": "a foreign delegation", "marriage": "a wedding of houses", "embassy": "an embassy",
}
const DEED_NICK := {
	"beast_slain": ["Wolfbane", "the Beast-Slayer", "Fangbreaker", "Hornless", "the Hunter-Saint"],
	"bandits_broken": ["Roadwarden", "the Bandit's Bane", "Gallows-Dodger", "Toll-Breaker"],
	"healed": ["the Gentle Hand", "Fever-Breaker", "Lantern-Nurse", "the Mender"],
	"defended": ["Wallkeeper", "the Shield", "Gate-Holder", "the Bulwark"],
	"rift_sealed": ["Riftwalker", "the Seal-Bearer", "Gap-Mender", "Ashwarden"],
	"expedition": ["Deepwalker", "the Returner", "Lamp-Bearer", "Cairn-Builder", "the Far-Goer"],
	"rescued": ["the Finder", "Lamplighter", "the Lifeline", "Hearthbringer"],
	"discovery": ["the Lamp-Keeper", "Stonewright", "the Clear-Eyed", "Rune-Reader"],
	"founded": ["the Founder", "Firstbuilder", "the Landtaker"], "charity": ["the Open Hand", "Alms-Giver", "the Giving"],
	"duelist": ["Bladesong", "the Duellist", "Steel-Tongue"], "tower": ["Towerbreaker", "Skyclimber", "Stair-Eater"],
	"crime": ["Shadowhand", "the Ill-Omened", "Nightfinger"], "generic": ["the Remembered"],
}
const SOC_DEED := {"monster_kill": "beast_slain", "rescue": "rescued", "donation": "charity", "duel_won": "duelist",
	"crime": "crime", "tower_clear": "tower"}
const PACT := ["open trade talks", "sign a border pact", "swear a mutual-aid oath", "exchange hostages of honour"]

var _items: Array = []          # {id, kind, sid, day, mag, text, detail, official}
var _cursor: Dictionary = {}    # source -> last seq consumed
var _fame: Array = []           # {s, n, sid, amt, day}
var _deeds: Dictionary = {}     # subject -> {n, w:{deed: weight}, sid}
var _nicks: Dictionary = {}     # subject -> {nick, deed, state, day, sid, w}
var _formal: Array = []         # {subject, n, nick, day, id}
var _dip: Array = []            # delegations / marriages / embassies
var _emb: Array = []            # lasting embassies {a, b, sid, day}
var _dip_total: Dictionary = {} # kind -> how many ever happened (the list below keeps only the latest)
var _seen_text: Array = []
var _soc_seen: Array = []
var _marr_max := 0               # highest marriage id already reported (factions ids only grow)
var _next_item := 1
var _next_dip := 1
var _day := 0
var _built := false
var _sig := -1
var _dist: Dictionary = {}      # sid -> PackedFloat32Array road distances (not saved)
var _life: Object = null
var _titles_npc := Titles.new(false)


# ------------------------------------------------------------------ helpers

func _rng(tag: String, day: int, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, day, id])
	return r


func _sname(sid: int) -> String:
	if sid >= 0 and sid < WorldGen.settlements.size():
		return String(WorldGen.settlements[sid]["name"])
	return "the road"


func _mod(n: String) -> Variant:
	return hub.mod(n) if hub != null else null


func _sync(ctx: Dictionary) -> void:
	var l: Variant = ctx.get("life")
	if l is Object:
		_life = l


func _ensure() -> void:
	var sig := hash([WorldGen.roads.size(), WorldGen.settlements.size()])
	if _built and sig == _sig:
		return
	var soc: Variant = _mod("society")
	var nb: Dictionary = soc.call("_road_nbrs") if soc != null and soc.has_method("_road_nbrs") else {}
	_built = true
	_sig = sig
	_dist.clear()
	var n := WorldGen.settlements.size()
	for s in n:
		var d := PackedFloat32Array()
		d.resize(n)
		d.fill(1.0e9)
		d[s] = 0.0
		var open: Array = [s]
		var done := {}
		while not open.is_empty():
			var bi := 0
			for i in open.size():
				if d[int(open[i])] < d[int(open[bi])]:
					bi = i
			var cur := int(open[bi])
			open.remove_at(bi)
			if done.has(cur):
				continue
			done[cur] = true
			for e: Array in nb.get(cur, []):
				var to := int(e[0])
				var nd := d[cur] + float(e[1])
				if nd < d[to]:
					d[to] = nd
					open.append(to)
		_dist[s] = d


## Road distance between two settlements (1e9 when no road joins them).
func road_distance(a: int, b: int) -> float:
	_ensure()
	if a < 0 or b < 0 or not _dist.has(a) or b >= WorldGen.settlements.size():
		return 1.0e9
	return float((_dist[a] as PackedFloat32Array)[b])


func _dir(from_sid: int, to_sid: int) -> String:
	if from_sid < 0 or to_sid < 0 or from_sid == to_sid:
		return "near here"
	var d: Vector2 = (WorldGen.settlements[to_sid]["pos"] as Vector2) - (WorldGen.settlements[from_sid]["pos"] as Vector2)
	var ns := "north" if d.y < 0 else "south"
	var ew := "west" if d.x < 0 else "east"
	var where := ew if absf(d.x) > absf(d.y) * 2.0 else (ns if absf(d.y) > absf(d.x) * 2.0 else "%s-%s" % [ns, ew])
	return "%s of here" % where


# ------------------------------------------------------------------ items

## Posts a piece of news. `official` items (notices) start clear and travel by courier; rumours start vague.
func post(kind: String, sid: int, text: String, mag := 1.0, detail := "", official := false, day := -1) -> int:
	var id := _next_item
	_next_item += 1
	_items.append({"id": id, "kind": kind, "sid": sid, "day": _day if day < 0 else day, "mag": snappedf(mag, 0.1), "text": text, "detail": detail,
		"official": official})
	if _items.size() > ITEM_CAP:
		_items.pop_front()
	return id


func _arrival(it: Dictionary, sid: int) -> float:
	var o := int(it["sid"])
	if o < 0:
		return float(it["day"]) + 2.0
	var dist := road_distance(o, sid)
	if dist >= 1.0e8:
		return 1.0e9
	return float(it["day"]) + dist / (COURIER_SPEED if bool(it["official"]) else ROAD_SPEED)


## Detail level 0..3 a listener at `sid` has on `day`.
func _level(it: Dictionary, sid: int, day: int) -> int:
	var arr := _arrival(it, sid)
	if arr > float(day):
		return -1
	var o := int(it["sid"])
	var far := 0.0 if o < 0 else maxf(0.0, road_distance(o, sid))
	var lv := (2 if bool(it["official"]) else 0) + int(far / SHARPEN_UNITS) + int((float(day) - arr) / SHARPEN_DAYS)
	return clampi(lv, 0, 3)


func _text_at(it: Dictionary, sid: int, lv: int) -> String:
	var kind := String(it["kind"])
	match lv:
		0:
			var tpl: String = String(VAGUE.get(kind, "Something happened %s, they say."))
			return tpl % (_dir(sid, int(it["sid"])) if int(it["sid"]) >= 0 else "across the realm")
		1:
			return "They are talking about %s near %s." % [String(NOUN.get(kind, "some trouble")), _sname(int(it["sid"]))]
		2:
			return String(it["text"])
	var d := String(it["detail"])
	return String(it["text"]) + ((" " + d) if d != "" else "")


## Everything a listener at `sid` has heard by `day` (-1 = today), newest first: [{id, kind, text, lvl, age, official, mag}].
func items_at(sid: int, day := -1) -> Array:
	_ensure()
	var dd := _day if day < 0 else day
	var out: Array = []
	for i in range(_items.size() - 1, -1, -1):
		var it: Dictionary = _items[i]
		var lv := _level(it, sid, dd)
		if lv < 0 or dd - int(it["day"]) > ITEM_LIFE:
			continue
		out.append({"id": int(it["id"]), "kind": it["kind"], "text": _text_at(it, sid, lv), "lvl": lv, "age": dd - int(it["day"]),
			"official": bool(it["official"]), "mag": float(it["mag"]), "sid": int(it["sid"])})
	return out


## Channels: "tavern" (everything, gossip flavoured), "board" (official notices only), "traveller" (far news that just arrived).
func news_for(sid: int, channel := "tavern", limit := 4) -> Array:
	var out: Array = []
	for e: Dictionary in items_at(sid):
		match channel:
			"board":
				if not bool(e["official"]):
					continue
			"traveller":
				if int(e["sid"]) == sid or road_distance(int(e["sid"]), sid) < SHARPEN_UNITS or float(e["age"]) - road_distance(int(e["sid"]), sid) / ROAD_SPEED > 4.0:
					continue
		out.append(e)
		if out.size() >= limit:
			break
	return out


## One line of tavern talk for a villager standing near `pos` (village_services._pick_rumour), or "".
func tavern_line_at(pos: Vector2, salt := 0) -> String:
	_ensure()
	var best := -1
	var bd := INF
	for s: Dictionary in WorldGen.settlements:
		var d := (s["pos"] as Vector2).distance_squared_to(pos)
		if d < bd:
			bd = d
			best = int(s["id"])
	if best < 0:
		return ""
	var list := items_at(best)
	if list.is_empty():
		return ""
	var weights: Array = []
	var total := 0.0
	for e: Dictionary in list:
		var w := (0.4 + float(e["mag"])) / (1.0 + float(e["age"]) * 0.08)
		weights.append(w)
		total += w
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, "tavern", salt])
	var pick := r.randf() * total
	for i in list.size():
		pick -= float(weights[i])
		if pick <= 0.0:
			return String((list[i] as Dictionary)["text"])
	return String((list[0] as Dictionary)["text"])


# ------------------------------------------------------------------ fame

func _fame_event(subject: String, nm: String, sid: int, amt: float, day: int) -> void:
	_fame.append({"s": subject, "n": nm, "sid": sid, "amt": snappedf(amt, 0.1), "day": day})
	if _fame.size() > FAME_CAP:
		_fame.pop_front()


## Fame of `subject` ("player" or "n:<notable id>") as known at a settlement: arrives at road speed, fades, dilutes with distance.
func fame_at(sid: int, subject := "player", day := -1) -> float:
	if subject == "player":
		var soc: Variant = _mod("society")
		return float(soc.fame_at(sid)) if soc != null else 0.0
	_ensure()
	var dd := _day if day < 0 else day
	var f := 0.0
	for e: Dictionary in _fame:
		if String(e["s"]) != subject:
			continue
		var dist := road_distance(int(e["sid"]), sid)
		if dist >= 1.0e8 or float(e["day"]) + dist / ROAD_SPEED > float(dd):
			continue
		f += float(e["amt"]) * exp(-dist / FAME_SCALE) * exp(-float(dd - int(e["day"])) / 400.0)
	return snappedf(f, 0.001)


func fame_reach(subject: String, threshold := 0.25) -> int:
	var n := 0
	for s in WorldGen.settlements.size():
		if fame_at(s, subject) >= threshold:
			n += 1
	return n


# ------------------------------------------------------------------ deeds and nicknames

## A deed done by `subject` ("player" or "n:<nid>"). Builds fame at road speed; enough weight of one kind births a nickname.
func record_deed(subject: String, nm: String, deed: String, sid: int, mag: float, day := -1) -> void:
	var dd := _day if day < 0 else day
	if not _deeds.has(subject):
		if _deeds.size() >= SUBJECT_CAP:
			_drop_weakest()
		_deeds[subject] = {"n": nm, "w": {}, "sid": sid}
	var d: Dictionary = _deeds[subject]
	d["n"] = nm
	d["sid"] = sid
	var w: Dictionary = d["w"]
	w[deed] = snappedf(float(w.get(deed, 0.0)) + mag, 0.1)
	if subject != "player":
		_fame_event(subject, nm, sid, mag * 4.0, dd)
	if not _nicks.has(subject) and float(w[deed]) >= NICK_AT:
		var list: Array = DEED_NICK.get(deed, DEED_NICK["generic"])
		var nick: String = list[absi(int(hash([subject, deed]))) % list.size()]
		for k in list.size():   # each nickname belongs to one person; a second bearer is told apart by place
			var cand: String = list[(absi(int(hash([subject, deed]))) + k) % list.size()]
			if not _nick_taken(cand):
				nick = cand
				break
			nick = "%s of %s" % [cand, _sname(sid)]
		_nicks[subject] = {"nick": nick, "deed": deed, "state": "whisper", "day": dd, "sid": sid, "w": float(w[deed])}
	elif _nicks.has(subject) and String((_nicks[subject] as Dictionary)["deed"]) == deed:
		(_nicks[subject] as Dictionary)["w"] = float(w[deed])


func _nick_taken(nick: String) -> bool:
	for s: String in _nicks:
		if String((_nicks[s] as Dictionary)["nick"]) == nick:
			return true
	return false


func _drop_weakest() -> void:
	var worst := ""
	var wv := 1.0e9
	var dkeys: Array = _deeds.keys()
	dkeys.sort()
	for s: String in dkeys:
		if _nicks.has(s) and String((_nicks[s] as Dictionary)["state"]) == "formal":
			continue
		var tot := 0.0
		for k: String in (_deeds[s]["w"] as Dictionary):
			tot += float(_deeds[s]["w"][k])
		if s != "player" and tot < wv:
			wv = tot
			worst = s
	if worst != "":
		_deeds.erase(worst)
		_nicks.erase(worst)


func nickname(subject := "player") -> Dictionary:
	return (_nicks.get(subject, {}) as Dictionary).duplicate()


func nicknames() -> Dictionary:
	return _nicks.duplicate(true)


func formal_titles() -> Array:
	return _formal.duplicate(true)


## Spread state of a nickname: whisper -> nickname (used in several places) -> established -> formal.
func _nick_step(subject: String, day: int) -> void:
	var nk: Dictionary = _nicks[subject]
	var st := String(nk["state"])
	if st == "formal":
		return
	var age := day - int(nk["day"])
	var reach := _nick_reach(subject, nk, day)
	nk["reach"] = reach
	var w := float(nk["w"])
	var new_st := st
	if st == "whisper" and reach >= 3 and age >= 12:
		new_st = "nickname"
	elif st == "nickname" and reach >= 6 and age >= 60 and w >= 7.0:
		new_st = "established"
	elif st == "established" and reach >= 8 and age >= 150 and w >= 10.0:
		new_st = "formal"
	if new_st == st:
		return
	nk["state"] = new_st
	var nm := String((_deeds.get(subject, {"n": "Someone"}) as Dictionary)["n"])
	match new_st:
		"nickname":
			post("nickname", int(nk["sid"]), "They have started calling %s \"%s\"." % [nm, nk["nick"]], 1.0, "", false, day)
		"established":
			post("nickname", int(nk["sid"]), "\"%s\" is what everyone calls %s now." % [nk["nick"], nm], 1.2, "", false, day)
		"formal":
			_make_formal(subject, nk, nm, day)


func _nick_reach(subject: String, nk: Dictionary, day: int) -> int:
	# Reach: settlements the story has arrived at (road speed), for the player by society's heard rumours when richer.
	var n := 0
	var o := int(nk["sid"])
	var speed := ROAD_SPEED
	for s in WorldGen.settlements.size():
		var dist := road_distance(o, s)
		if dist < 1.0e8 and float(nk["day"]) + dist / speed <= float(day):
			n += 1
	if subject == "player":
		var soc: Variant = _mod("society")
		if soc != null:
			var heard := 0
			for r: Dictionary in soc.rumour_list:
				if String(r["subject"]) == "player":
					heard = maxi(heard, (r["heard"] as Dictionary).size())
			n = mini(n, maxi(heard, 1))
	return n


func _make_formal(subject: String, nk: Dictionary, nm: String, day: int) -> void:
	var tid := "nick_%s_%s" % [subject.replace(":", "_"), String(nk["deed"])]
	var def := {"id": tid, "name": String(nk["nick"]), "desc": "Known across the realm for what %s did." % nm, "effect": {"reputation_gain": 0.02}}
	var reg: Variant = _titles_npc
	if subject == "player" and _life != null and _life.get("titles") != null:
		reg = _life.get("titles")
	reg.add(def)
	reg.grant(tid, day)
	_formal.append({"subject": subject, "n": nm, "nick": String(nk["nick"]), "day": day, "id": tid})
	if _formal.size() > 24:
		_formal.pop_front()
	post("title", int(nk["sid"]), "%s is formally honoured as \"%s\"." % [nm, nk["nick"]], 2.0, "", true, day)
	if subject.begins_with("n:"):
		var nmod: Variant = _mod("notables")
		if nmod != null and nmod.has_method("set_nick"):
			nmod.set_nick(subject.substr(2), String(nk["nick"]))


# ------------------------------------------------------------------ diplomacy as data

func diplomacy(kind := "") -> Array:
	var out: Array = []
	for e: Dictionary in _dip:
		if kind == "" or String(e["kind"]) == kind:
			out.append(e.duplicate(true))
	return out


func embassies() -> Array:
	return _emb.duplicate(true)


func _fname(id: String) -> String:
	var fa: Variant = _mod("factions")
	if fa != null:
		var f: Dictionary = fa.faction(id)
		if not f.is_empty():
			return String(f["name"])
	return id


func _dip_add(kind: String, a: String, b: String, sid: int, travel: int, text: String) -> void:
	_dip_total[kind] = int(_dip_total.get(kind, 0)) + 1
	_dip.append({"id": _next_dip, "kind": kind, "a": a, "b": b, "sid": sid, "day": _day, "arrive": _day + travel,
		"status": "travelling" if travel > 0 else "arrived", "text": text})
	_next_dip += 1
	if _dip.size() > DIP_CAP:
		_dip.pop_front()


func _diplomacy_day(day: int) -> void:
	# Arrivals (delegations reach their host; the news follows them).
	for e: Dictionary in _dip:
		if String(e["status"]) == "travelling" and day >= int(e["arrive"]):
			e["status"] = "arrived"
			post("delegation", int(e["sid"]), String(e["text"]), 1.5, "", true, day)
	if day % 7 != 5:
		return
	var fa: Variant = _mod("factions")
	if fa == null or not fa.has_method("factions"):
		return
	var r := _rng("ndip", day, 0)
	# New marriages (the factions module arranges some on its own) become news.
	for m: Dictionary in fa.marriages():
		var mid := int(m.get("id", 0))
		if mid > _marr_max:
			_marr_max = mid
			if int(m.get("day", day)) < day - 60:
				continue   # an old wedding found on first look is history, not news
			var t := "%s and %s are to be joined in marriage." % [_fname(String(m["a"])), _fname(String(m["b"]))]
			_dip_add("marriage", String(m["a"]), String(m["b"]), _court_sid(r), 0, t)
			post("marriage", _court_sid(r), t, 1.5, "", true, day)
	var ids: Array = []
	for f: Dictionary in fa.factions():
		if String(f["kind"]) in ["nation", "house"] and String(f["id"]) != "player":
			ids.append(String(f["id"]))
	if ids.size() < 2:
		return
	# A political marriage proposal between friendly powers.
	if r.randf() < 0.06 and fa.has_method("propose_marriage"):
		var a: String = ids[r.randi() % ids.size()]
		var b: String = ids[r.randi() % ids.size()]
		if a != b and float(fa.relation(a, b).get("trust", 0.0)) >= 55.0:
			fa.propose_marriage(a, b)
	# A delegation travels to a court: friendly powers send them most, which deepens the friendship.
	if r.randf() < 0.15:
		var friendly: Array = []
		for a1: String in ids:
			for b1: String in ids:
				if a1 < b1 and String(fa.faction(a1)["kind"]) == "nation" and String(fa.faction(b1)["kind"]) == "nation" \
						and float(fa.relation(a1, b1).get("trust", 0.0)) >= 45.0:
					friendly.append([a1, b1])
		var a2: String = ids[r.randi() % ids.size()]
		var b2: String = ids[r.randi() % ids.size()]
		if not friendly.is_empty() and r.randf() < 0.75:
			var fp: Array = friendly[r.randi() % friendly.size()]
			a2 = String(fp[0])
			b2 = String(fp[1])
		if a2 != b2:
			var sid := _court_sid(r)
			var purpose: String = PACT[r.randi() % PACT.size()]
			_dip_add("delegation", a2, b2, sid, r.randi_range(4, 12), "A delegation from %s arrives at %s to %s with %s." % [_fname(a2), _sname(sid), purpose, _fname(b2)])
			if fa.has_method("change_relation"):
				fa.change_relation(a2, b2, "trust", 3.0)
	# Lasting trust becomes an embassy compound and a foreign community.
	if _emb.size() < 6:
		var pairs: Array = []
		for a3: String in ids:
			for b3: String in ids:
				if a3 != b3 and String(fa.faction(a3)["kind"]) == "nation" and String(fa.faction(b3)["kind"]) == "nation" \
						and float(fa.relation(a3, b3).get("trust", 0.0)) >= 72.0 and not _has_embassy(a3, b3):
					pairs.append([a3, b3])
		if not pairs.is_empty() and r.randf() < 0.4:
			var pr: Array = pairs[r.randi() % pairs.size()]
			var sid3 := _court_sid(r)
			_emb.append({"a": pr[0], "b": pr[1], "sid": sid3, "day": day})
			var t3 := "%s opens an embassy in %s; a foreign quarter begins to form." % [_fname(String(pr[0])), _sname(sid3)]
			_dip_add("embassy", String(pr[0]), String(pr[1]), sid3, 0, t3)
			post("embassy", sid3, t3, 1.5, "", true, day)


func _has_embassy(a: String, b: String) -> bool:
	for e: Dictionary in _emb:
		if String(e["a"]) == a and String(e["b"]) == b:
			return true
	return false


func _court_sid(r: RandomNumberGenerator) -> int:
	var c: Array = []
	for s: Dictionary in WorldGen.settlements:
		if String(s["kind"]) in ["castle", "town"]:
			c.append(int(s["id"]))
	return int(c[r.randi() % c.size()]) if not c.is_empty() else 0


# ------------------------------------------------------------------ ingest

func _ingest() -> void:
	for src: String in SOURCES:
		var m: Variant = _mod(src)
		if m == null or not m.has_method("news_events"):
			continue
		var last := int(_cursor.get(src, 0))
		var sq: Variant = m.get("_seq")
		if sq != null and int(sq) < last:
			last = 0   # the module's counter was reset (new game / replaced save)
		var mx := last
		var evs: Array = m.news_events(last) if m.get_method_argument_count("news_events") > 0 else m.news_events()
		for e: Dictionary in evs:
			mx = maxi(mx, int(e.get("seq", 0)))
			if int(e.get("seq", 0)) > last:
				post(String(e.get("kind", "news")), int(e.get("sid", -1)), String(e.get("text", "")), float(e.get("mag", 1.0)),
					String(e.get("detail", "")), bool(e.get("official", false)), int(e.get("day", _day)))
		_cursor[src] = mx
	var fa: Variant = _mod("factions")
	if fa != null and fa.has_method("news"):
		for line: Variant in fa.news(4):
			var h := String(line)
			if h != "" and not _seen_text.has(h):
				_seen_text.append(h)
				if _seen_text.size() > 40:
					_seen_text.pop_front()
				post("realm", -1, h, 1.0, "", true)
	var soc: Variant = _mod("society")
	if soc != null:
		for r: Dictionary in soc.rumour_list:
			var id := String(r["id"])
			if String(r["subject"]) == "player" and not _soc_seen.has(id):
				_soc_seen.append(id)
				if _soc_seen.size() > 60:
					_soc_seen.pop_front()
				record_deed("player", "You", String(SOC_DEED.get(String(r["deed"]), "generic")), int(r["origin"]), float(r["mag"]) * float(r["tone"]) if float(r["tone"]) > 0.0 else 0.0, _day)
				if float(r["tone"]) < 0.0:
					record_deed("player", "You", "crime", int(r["origin"]), float(r["mag"]) * 0.5, _day)


# ------------------------------------------------------------------ ticks

func tick_hour(_hour: int, ctx: Dictionary) -> Array:
	_sync(ctx)
	return []


func tick_day(day: int, ctx: Dictionary) -> Array:
	return _run_chunks(day, ctx)


func tick_day_chunks(day: int, ctx: Dictionary) -> Array:
	return [
		func() -> Array:
			_sync(ctx)
			_day = day
			_ensure()
			_ingest()
			return [],
		func() -> Array:
			var keys: Array = _nicks.keys()
			keys.sort()
			for s: String in keys:
				_nick_step(s, day)
			var msgs: Array = []
			while _items.size() > 0 and day - int((_items[0] as Dictionary)["day"]) > ITEM_LIFE + 30:
				_items.pop_front()
			while _fame.size() > 0 and day - int((_fame[0] as Dictionary)["day"]) > 900:
				_fame.pop_front()
			return msgs,
		func() -> Array:
			_diplomacy_day(day)
			return [],
	]


func tick_week(_week: int, _ctx: Dictionary) -> Array:
	return []


func catch_up(days: int, ctx: Dictionary) -> Array:
	if days <= 0:
		return []
	_sync(ctx)
	_day += days
	_ensure()
	_ingest()
	var keys: Array = _nicks.keys()
	keys.sort()
	for s: String in keys:
		# A nickname can move several stages across a long absence: step until it settles.
		for k in 4:
			var before := String((_nicks[s] as Dictionary)["state"])
			_nick_step(s, _day)
			if String((_nicks[s] as Dictionary)["state"]) == before:
				break
	for e: Dictionary in _dip:
		if String(e["status"]) == "travelling" and _day >= int(e["arrive"]):
			e["status"] = "arrived"
	var r := _rng("ncatch", _day, days)
	var fa: Variant = _mod("factions")
	if fa != null and days >= 14 and r.randf() < minf(0.8, float(days) / 7.0 * 0.15):
		_diplomacy_day(_day - _day % 7 + 5)
	return []


# ------------------------------------------------------------------ persistence

func stats() -> Dictionary:
	return {"items": _items.size(), "fame": _fame.size(), "nicks": _nicks.size(), "formal": _formal.size(), "dip": _dip.size(), "embassies": _emb.size(), "dip_total": _dip_total.duplicate()}


func serialize() -> Dictionary:
	return {"v": SAVE_VERSION, "items": _items.duplicate(true), "cursor": _cursor.duplicate(), "fame": _fame.duplicate(true), "deeds": _deeds.duplicate(true),
		"nicks": _nicks.duplicate(true), "formal": _formal.duplicate(true), "dip": _dip.duplicate(true), "emb": _emb.duplicate(true), "dip_total": _dip_total.duplicate(),
		"seen_text": _seen_text.duplicate(), "soc_seen": _soc_seen.duplicate(), "marr_max": _marr_max, "next": [_next_item, _next_dip],
		"day": _day, "npc_titles": _titles_npc.serialize()}


func deserialize(d: Dictionary) -> void:
	_items = (d.get("items", []) as Array).duplicate(true)
	_cursor = (d.get("cursor", {}) as Dictionary).duplicate()
	_fame = (d.get("fame", []) as Array).duplicate(true)
	_deeds = (d.get("deeds", {}) as Dictionary).duplicate(true)
	_nicks = (d.get("nicks", {}) as Dictionary).duplicate(true)
	_formal = (d.get("formal", []) as Array).duplicate(true)
	_dip = (d.get("dip", []) as Array).duplicate(true)
	_emb = (d.get("emb", []) as Array).duplicate(true)
	_dip_total = (d.get("dip_total", {}) as Dictionary).duplicate()
	_seen_text = (d.get("seen_text", []) as Array).duplicate()
	_soc_seen = (d.get("soc_seen", []) as Array).duplicate()
	_marr_max = int(d.get("marr_max", 0))
	var nx: Array = d.get("next", [1, 1])
	_next_item = int(nx[0])
	_next_dip = int(nx[1])
	_day = int(d.get("day", 0))
	_titles_npc = Titles.new(false)
	for f: Dictionary in _formal:
		if not String(f["subject"]).begins_with("n:"):
			continue
		_titles_npc.add({"id": String(f["id"]), "name": String(f["nick"]), "desc": "", "effect": {}})
		_titles_npc.grant(String(f["id"]), int(f["day"]))
	_sig = -1
