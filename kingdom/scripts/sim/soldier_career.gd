extends RefCounted
## Soldier career rules as pure static functions over data/careers/soldier_career.json (F11). No state, no scene
## access: ranks and promotion lines, weekly wages, the post (an outpost near Thornfield or the town watch),
## named people, and duty generation into library quests (scripts/quests, QuestDef JSON). State and the daily
## clock live in scripts/realm/soldier.gd; the squad in scripts/sim/soldier_squad.gd.

const PATH := "res://data/careers/soldier_career.json"
const DUTY_KINDS := ["patrol", "guard_gate", "escort", "clear", "deliver_orders", "investigate"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = d if d is Dictionary else {}
	return _data


# ---------------------------------------------------------------- ranks

static func ranks() -> Array:
	return data().get("ranks", [])


static func rank_count() -> int:
	return ranks().size()


static func rank_def(i: int) -> Dictionary:
	var r := ranks()
	return r[clampi(i, 0, r.size() - 1)]


static func rank_id(i: int) -> String:
	return String(rank_def(i)["id"])


static func rank_title(i: int) -> String:
	return String(rank_def(i)["title"])


static func rank_index(id: String) -> int:
	var r := ranks()
	for i in r.size():
		if String(r[i]["id"]) == id:
			return i
	return -1


## The soldier-ladder id (ladders.json, military.gd) that this rank stands for.
static func ladder_id(i: int) -> String:
	return String(rank_def(i)["ladder_id"])


static func weekly_wage(i: int) -> int:
	return int(rank_def(i)["wage"])


## Squad members a rank leads (0 below corporal).
static func squad_size(i: int) -> int:
	return int(rank_def(i)["squad"])


## Company size cap from the shared ladder table (the old recruit-hiring cap in main.gd).
static func troops_for_rank(i: int) -> int:
	return preload("res://scripts/sim/career_ladders.gd").troops_for_rank(ladder_id(i))


## Kit the rank is issued: slot -> item id, cumulative up to that rank (later ranks replace earlier slots).
static func kit_for(i: int) -> Dictionary:
	var kit := {}
	for k in range(0, clampi(i, 0, rank_count() - 1) + 1):
		for slot: String in rank_def(k).get("kit", {}):
			kit[slot] = String(rank_def(k)["kit"][slot])
	return kit


## Promotion check from merit points plus the minimum service time in the current rank.
## {eligible, next: {id, title} or {}, lines: [{text, met}], missing: PackedStringArray}
static func promotion(rank: int, merit: float, days_in_rank: int) -> Dictionary:
	if rank >= rank_count() - 1:
		return {"eligible": false, "next": {}, "lines": [], "missing": PackedStringArray()}
	var nxt := rank_def(rank + 1)
	var lines: Array = [
		{"text": "%d merit (have %d)" % [int(nxt["merit"]), int(merit)], "met": merit >= float(nxt["merit"])},
		{"text": "%d days of service in rank (have %d)" % [int(nxt["min_days"]), maxi(0, days_in_rank)], "met": days_in_rank >= int(nxt["min_days"])},
	]
	var missing := PackedStringArray()
	for l: Dictionary in lines:
		if not bool(l["met"]):
			missing.append(String(l["text"]))
	return {"eligible": missing.is_empty(), "next": {"id": nxt["id"], "title": nxt["title"]}, "lines": lines, "missing": missing}


## Weekly pay after docking: `missed` missed musters this week, `leave_days` days on leave. Deserters get nothing.
static func pay_for_week(rank: int, missed: int, on_leave: bool, deserter: bool) -> int:
	var pay: Dictionary = data()["pay"]
	if deserter:
		return int(pay["desertion_pays"])
	var w := float(weekly_wage(rank))
	if on_leave:
		w *= float(pay["leave_fraction"])
	var dock := clampf(float(missed) * float(pay["dock_per_missed_muster"]), 0.0, 1.0)
	return int(round(w * (1.0 - dock)))


# ---------------------------------------------------------------- muster

static func muster() -> Dictionary:
	return data()["muster"]


## Is `hour` (0..24, fractional) inside the muster window?
static func in_muster(hour: float) -> bool:
	var m := muster()
	return hour >= float(m["hour"]) and hour < float(m["hour"]) + float(m["window"])


# ---------------------------------------------------------------- post

## The post: a military outpost near Thornfield when the world has it, else the town watch.
## `settlements` is WorldGen.settlements (Array of {name, pos: Vector2, radius}). Returns
## {id, name, kind: "outpost"|"watch", pos: Vector2, radius, sid, places: {...}}.
static func resolve_post(settlements: Array) -> Dictionary:
	var posts: Dictionary = data()["posts"]
	for o: Dictionary in posts["outposts"]:
		for i in settlements.size():
			if String(settlements[i]["name"]) == String(o["settlement"]):
				var off: Array = o["offset"]
				var p: Vector2 = (settlements[i]["pos"] as Vector2) + Vector2(float(off[0]), float(off[1]))
				return {"id": o["id"], "name": o["name"], "kind": "outpost", "pos": p, "radius": float(o["radius"]), "sid": i, "places": (o["places"] as Dictionary).duplicate(true)}
	var f: Dictionary = posts["fallback"]
	var sid := clampi(int(f["settlement_index"]), 0, maxi(0, settlements.size() - 1))
	var pos := Vector2.ZERO
	var rad := 30.0
	if not settlements.is_empty():
		pos = settlements[sid]["pos"]
		rad = float(settlements[sid]["radius"])
	var off2: Array = f["offset"]
	return {"id": f["id"], "name": f["name"], "kind": "watch", "pos": pos + Vector2(float(off2[0]), float(off2[1])), "radius": rad + float(f["radius_extra"]),
		"sid": sid, "places": (f["places"] as Dictionary).duplicate(true)}


# ---------------------------------------------------------------- people

static func officer_name(r: RandomNumberGenerator) -> String:
	var o: Dictionary = data()["officers"]
	return "%s %s" % [String((o["first"] as Array)[r.randi() % (o["first"] as Array).size()]), String((o["last"] as Array)[r.randi() % (o["last"] as Array).size()])]


static func make_officer(seed_value: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var o: Dictionary = data()["officers"]
	var title := String((o["titles"] as Array)[r.randi() % (o["titles"] as Array).size()])
	return {"id": "cmd_%d" % absi(seed_value % 100000), "name": officer_name(r), "title": title}


# ---------------------------------------------------------------- duties

static func duty_def(kind: String) -> Dictionary:
	return (data()["duties"] as Dictionary).get(kind, {})


## Duty kinds open to a rank, in data order.
static func kinds_for(rank: int) -> Array:
	var out: Array = []
	for k: String in DUTY_KINDS:
		if int(duty_def(k)["min_rank"]) <= rank:
			out.append(k)
	return out


## Weighted pick among the kinds open to `rank` (or the one named by `force`).
static func pick_kind(r: RandomNumberGenerator, rank: int) -> String:
	var kinds := kinds_for(rank)
	var total := 0.0
	for k: String in kinds:
		total += float(duty_def(k)["weight"])
	var roll := r.randf() * total
	for k: String in kinds:
		roll -= float(duty_def(k)["weight"])
		if roll <= 0.0:
			return k
	return String(kinds[0])


static func _pick(r: RandomNumberGenerator, a: Array) -> Variant:
	return a[r.randi() % a.size()]


## Builds today's duty as a library quest definition. Returns
## {kind, id, def: QuestDef JSON, merit, gold, hours, text}. Deterministic in `r`.
static func gen_duty(kind: String, day: int, post: Dictionary, r: RandomNumberGenerator) -> Dictionary:
	var d := duty_def(kind)
	var qid := "soldier_duty_%d_%s" % [day, kind]
	var places: Dictionary = post.get("places", {})
	var base: Vector2 = post.get("pos", Vector2.ZERO)
	var title := String(d["title"])
	var stage: Dictionary = {"id": "duty", "title": "", "mode": "all", "objectives": []}
	var objs: Array = []
	match kind:
		"patrol":
			stage["mode"] = "sequence"
			var route: Array = d["route"]
			var start := r.randi() % route.size()
			for i in int(d["waypoints"]):
				var w: Array = route[(start + i) % route.size()]
				objs.append({"id": "wp%d" % (i + 1), "type": "goto", "pos": [base.x + float(w[0]), base.y + float(w[1])],
					"radius": float(d["radius"]), "text": "Reach waypoint %d of %d" % [i + 1, int(d["waypoints"])]})
			title = title % String(post.get("name", "post")).trim_prefix("the ")
		"guard_gate":
			objs.append({"id": "night", "type": "wait", "hours": float(d["hours"]), "window": d["window"]})
			objs.append({"id": "gate", "type": "protect", "actor": "gate_%s" % String(post.get("id", "post")), "name": "the gate", "hours": float(d["hours"])})
		"escort":
			var dest := String(_pick(r, places.get("escort_to", ["market_gate"])))
			objs.append({"id": "cart", "type": "escort", "actor": "supply_cart", "name": "the supply cart", "place": dest, "radius": float(d["radius"])})
		"clear":
			var t: Dictionary = _pick(r, d["targets"])
			var at := String(_pick(r, places.get("clear_at", ["outer_fields"])))
			objs.append({"id": "clear", "type": "kill", "target": t["target"], "place": at, "count": int(t["count"])})
			title = title % String(t["noun"])
		"deliver_orders":
			var to := String(_pick(r, places.get("orders_to", ["town_hall"])))
			objs.append({"id": "orders", "type": "deliver", "item": d["item"], "to": to, "count": 1})
		"investigate":
			var pool: Array = (d["clues"] as Array).duplicate()
			var picks: Array = []
			while picks.size() < int(d["count"]) and not pool.is_empty():
				var c: Variant = pool.pop_at(r.randi() % pool.size())
				picks.append(c)
			objs.append({"id": "clues", "type": "investigate", "clues": picks, "count": picks.size()})
		_:
			return {}
	stage["title"] = title
	stage["objectives"] = objs
	var def := {"id": qid, "title": title, "summary": String(d["summary"]), "stages": [stage], "rewards": {"merit": int(d["merit"]), "gold": int(d["gold"])},
		"on_fail": {"merit": int(data()["merit"]["duty_failed"])}}
	return {"kind": kind, "id": qid, "def": def, "merit": int(d["merit"]), "gold": int(d["gold"]), "hours": float(d["hours"]), "text": title, "day": day}
