extends "res://scripts/realm/realm_module.gd"
## Survival-style construction (docs/design/REALM_WAR_SETTLEMENT.md §3-6). You gather logs, stone, clay and
## thatch, process them at a sawhorse or mason's bench, lay a blueprint anywhere valid, stock it with
## materials and put workers on it. Progress is labour-hours: each worker's building skill and tools set
## the speed, master builders speed the crew (and unlock the tall tiers), missing materials stall the site,
## and everything keeps going while you are away (catch_up replays the same working hours in a loop
## that ends as soon as a site is done or stuck). Finished buildings join a holding (camp -> hamlet ->
## village -> town), feed settlements.gd identity, lay footpaths that wear into roads (camps.build_road),
## and register as obstacles for the walkers in construction_nav.gd. Enterprise fief projects use
## crew_output() so both crews share one labour model. Pure data, JSON-safe save.

const D := preload("res://scripts/realm/construction_data.gd")
const Nav := preload("res://scripts/realm/construction_nav.gd")
const SettlementsScript := preload("res://scripts/realm/settlements.gd")

var sites: Dictionary = {}          # int -> site
var workers: Dictionary = {}        # "w<n>" -> worker
var holdings: Dictionary = {}       # int -> holding
var known: Dictionary = {}          # fact -> true (learned from masters and finished buildings)
var trails: Dictionary = {}         # "a|b" -> {a, b, uses}
var gathered: Dictionary = {}       # "cx,cz" -> {hp, day, t}
var external: Dictionary = {}       # kind -> count finished through fief projects
var pending_gold := 0
var _street_queue_on := false       # catch_up queues street-graph registrations and flushes them once
var _street_queue := {}             # settlement id -> [[pos, yaw, half, door], ...]
var log_lines: Array = []

## Tests inject these; in the game they stay null and the player's Inventory/purse/mastery are used.
var bag: Variant = null             # Dictionary item -> count
var gold_ref: Variant = null        # Dictionary {"gold": n}
var mastery_ref: RefCounted = null

var _next_site := 1
var _next_worker := 1
var _next_holding := 1
var _day := 0
var _upkeep_acc := 0.0
var _trail_cache: Array = []
var _trail_dirty := true


# ------------------------------------------------------------------ plumbing

func _rng(tag: String, id: Variant) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([WorldSim.SEED, tag, _day, str(id)])
	return r


func _mod(n: String) -> RefCounted:
	return hub.mod(n) if hub != null else null


func _have(item: String) -> int:
	if bag is Dictionary:
		return int((bag as Dictionary).get(item, 0))
	return Life.count(item)


func _take(item: String, n: int) -> bool:
	if n <= 0:
		return true
	if bag is Dictionary:
		var d := bag as Dictionary
		if int(d.get(item, 0)) < n:
			return false
		d[item] = int(d[item]) - n
		return true
	return Life.take(item, n)


func _give(item: String, n: int) -> void:
	if n <= 0:
		return
	if bag is Dictionary:
		var d := bag as Dictionary
		d[item] = int(d.get(item, 0)) + n
	else:
		Life.give(item, n)


func gold_available() -> int:
	var g := 0
	if gold_ref is Dictionary:
		g = int((gold_ref as Dictionary).get("gold", 0))
	else:
		g = Game.gold
	return g + pending_gold


func _spend(n: int) -> bool:
	if gold_available() < n:
		return false
	pending_gold -= n
	return true


func take_pending_gold() -> int:
	var g := pending_gold
	pending_gold = 0
	return g


func _mastery() -> RefCounted:
	return mastery_ref if mastery_ref != null else Life.mastery


func _say(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 20:
		log_lines.pop_front()


func _p2(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	if v is Vector3:
		return Vector2((v as Vector3).x, (v as Vector3).z)
	return Vector2.INF


func site_pos(s: Dictionary) -> Vector2:
	var p: Array = s["pos"]
	return Vector2(p[0], p[1])


# ------------------------------------------------------------------ knowledge and unlocking

func knows(fact: String) -> bool:
	if known.has(fact):
		return true
	var soc := _mod("society")
	return soc != null and soc.has_method("knows") and bool(soc.call("knows", fact))


func count_built(kind: String) -> int:
	var n := int(external.get(kind, 0))
	for id: int in sites:
		var s: Dictionary = sites[id]
		if String(s["kind"]) == kind and String(s["state"]) == "done" and not bool(s.get("npc", false)):
			n += 1
	return n


func tier_built(t: int) -> int:
	var n := 0
	for id: int in sites:
		var s: Dictionary = sites[id]
		if String(s["state"]) == "done" and int(D.CATALOG[String(s["kind"])]["tier"]) == t and not bool(s.get("npc", false)):
			n += 1
	return n


## What still stands between you and placing `kind` (prerequisites only, not materials or ground):
## [] when it is unlocked. Each entry is a line for the UI.
func missing_needs(kind: String) -> Array:
	var d := D.def(kind)
	var out: Array = []
	if d.is_empty():
		return ["No such building."]
	var t := int(d["tier"])
	if t > 0 and tier_built(t - 1) + int(external.get("_any", 0)) < 1:
		out.append("Finish a %s building first" % String(D.TIER_NAMES[t - 1]).to_lower())
	for k: String in d.get("needs", []):
		if count_built(k) < 1:
			out.append("Build a %s" % String(D.CATALOG[k]["name"]).to_lower())
	for f: String in d.get("know", []):
		if not knows(f):
			out.append("Learn %s" % String(D.KNOW_NAMES.get(f, f)).to_lower())
	return out


func missing_needs_for_upgrade(kind: String) -> Array:
	var out := missing_needs(kind)
	var from := String(D.def(kind).get("upgrades_from", ""))
	if from == "":
		return out
	# the old building stands: that satisfies its own prerequisite lines
	return out.filter(func(line: String) -> bool: return line != "Build a %s" % String(D.CATALOG[from]["name"]).to_lower())


func costs_for(kind: String, upgrade := false) -> Dictionary:
	var out := {}
	var cost: Dictionary = D.def(kind).get("cost", {})
	for item: String in cost:
		var n := int(cost[item])
		out[item] = maxi(1, int(ceil(n * D.UPGRADE_COST))) if upgrade else n
	return out


func hours_for(kind: String, upgrade := false) -> float:
	var h := float(D.def(kind).get("hours", 1.0))
	return h * D.UPGRADE_HOURS if upgrade else h


# ------------------------------------------------------------------ holdings

## Nearest holding within reach of a spot, or 0.
func holding_at(pos: Vector2) -> int:
	var best := 0
	var bd := D.HOLDING_RADIUS
	for id: int in holdings:
		var d := pos.distance_to(_hpos(holdings[id]))
		if d < bd:
			bd = d
			best = id
	return best


func _hpos(h: Dictionary) -> Vector2:
	var p: Array = h["pos"]
	return Vector2(p[0], p[1])


func _new_holding(pos: Vector2) -> int:
	var id := _next_holding
	_next_holding += 1
	var camp_id := -1
	var cm := _mod("camps")
	var nm := "Camp %d" % id
	if cm != null:
		camp_id = int(cm.call("found_camp", pos, "", _day))
		if camp_id > 0:
			var cd: Dictionary = cm.call("camp", camp_id)
			cd["src"] = "construction"
			nm = String(cd.get("name", nm))
	holdings[id] = {"id": id, "name": nm, "pos": [pos.x, pos.y], "camp": camp_id, "pop": 0.0, "level": "camp",
		"store": {}, "founded_day": _day, "road_done": false}
	return id


func rename_holding(hid: int, nm: String) -> void:
	if holdings.has(hid) and nm.strip_edges() != "":
		holdings[hid]["name"] = nm.strip_edges().left(24)


func store_cap(hid: int) -> int:
	var cap := 40
	for id: int in sites:
		var s: Dictionary = sites[id]
		if int(s["holding"]) == hid and String(s["state"]) == "done":
			cap += int(D.CATALOG[String(s["kind"])].get("store", 0))
	return cap


func store_used(hid: int) -> int:
	var n := 0
	var st: Dictionary = holdings.get(hid, {}).get("store", {})
	for k: String in st:
		n += int(st[k])
	return n


func store_count(hid: int, item: String) -> int:
	return int(holdings.get(hid, {}).get("store", {}).get(item, 0))


func deposit(hid: int, item: String, n: int) -> int:
	if not holdings.has(hid) or n <= 0:
		return 0
	var room := store_cap(hid) - store_used(hid)
	var k := mini(mini(n, _have(item)), room)
	if k <= 0 or not _take(item, k):
		return 0
	var st: Dictionary = holdings[hid]["store"]
	st[item] = int(st.get(item, 0)) + k
	return k


func withdraw(hid: int, item: String, n: int) -> int:
	var k := mini(n, store_count(hid, item))
	if k <= 0:
		return 0
	var st: Dictionary = holdings[hid]["store"]
	st[item] = int(st[item]) - k
	_give(item, k)
	return k


func deposit_all(hid: int) -> int:
	var total := 0
	for item: String in D.MATERIAL_ORDER:
		total += deposit(hid, item, _have(item))
	return total


## The spot haulers carry from: the holding's finished storage building, else its centre.
func hub_site(hid: int) -> Dictionary:
	var best: Dictionary = {}
	for id: int in sites:
		var s: Dictionary = sites[id]
		if int(s["holding"]) == hid and String(s["state"]) == "done" and String(D.CATALOG[String(s["kind"])].get("role", "")) == "storage":
			if best.is_empty() or int(s["id"]) < int(best["id"]):
				best = s
	return best


func hub_pos(hid: int) -> Vector2:
	var h := hub_site(hid)
	if not h.is_empty():
		return Nav.door_of(h)
	return _hpos(holdings.get(hid, {"pos": [0, 0]}))


# ------------------------------------------------------------------ placement

func snap(p: Vector2, grid := 2.0) -> Vector2:
	return Vector2(snappedf(p.x, grid), snappedf(p.y, grid))


func _corners(kind: String, pos: Vector2, yaw: float) -> Array:
	var h := D.half_size(kind)
	var ax := Vector2(cos(yaw), -sin(yaw))
	var az := Vector2(sin(yaw), cos(yaw))
	var out: Array = [pos]
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			out.append(pos + ax * h.x * sx + az * h.y * sz)
	return out


## Ground shape under a footprint: {ok, reason, base (average height), low, high}.
func ground(kind: String, pos: Vector2, yaw: float) -> Dictionary:
	var lo := INF
	var hi := -INF
	var sum := 0.0
	var pts := _corners(kind, pos, yaw)
	for p: Vector2 in pts:
		if WorldGen.is_water(p.x, p.y):
			return {"ok": false, "reason": "Too wet to build on.", "base": 0.0, "low": 0.0, "high": 0.0}
		var h := WorldGen.height(p.x, p.y)
		lo = minf(lo, h)
		hi = maxf(hi, h)
		sum += h
	var sz: Vector2 = D.def(kind).get("size", Vector2(3, 3))
	var allowed := D.MAX_SLOPE + 0.1 * maxf(sz.x, sz.y)
	if hi - lo > allowed:
		return {"ok": false, "reason": "Too steep.", "base": sum / pts.size(), "low": lo, "high": hi}
	return {"ok": true, "reason": "", "base": sum / pts.size(), "low": lo, "high": hi}


static func boxes_overlap(a: Array, b: Array, margin := 0.0) -> bool:
	var axes: Array[Vector2] = []
	for bx: Array in [a, b]:
		var ax: Vector2 = bx[1]
		axes.append(ax)
		axes.append(Vector2(-ax.y, ax.x))
	for axis: Vector2 in axes:
		var ra := _radius_on(a, axis)
		var rb := _radius_on(b, axis)
		var dist := absf(((b[0] as Vector2) - (a[0] as Vector2)).dot(axis))
		if dist > ra + rb + margin:
			return false
	return true


static func _radius_on(bx: Array, axis: Vector2) -> float:
	var ax: Vector2 = bx[1]
	var az := Vector2(-ax.y, ax.x)
	var h: Vector2 = bx[2]
	return absf(axis.dot(ax)) * h.x + absf(axis.dot(az)) * h.y


## Terrain, overlap and world checks that are cheap enough to run every frame of a dragged ghost.
func can_place_here(kind: String, pos: Vector2, yaw: float, upgrade_of := 0) -> String:
	var d := D.def(kind)
	if d.is_empty():
		return "No such building."
	var g := ground(kind, pos, yaw)
	if not bool(g["ok"]):
		return String(g["reason"])
	var box: Array = [pos, Vector2(cos(yaw), -sin(yaw)), D.half_size(kind)]
	for id: int in sites:
		if id == upgrade_of:
			continue
		var s: Dictionary = sites[id]
		var other := Nav.box_of(s)
		if (other[0] as Vector2).distance_to(pos) < 40.0 and boxes_overlap(box, other, 0.5):
			return "Something already stands here."
	for st: Dictionary in WorldGen.settlements:
		var sp: Vector2 = st["pos"]
		if sp.distance_to(pos) < float(st["radius"]) * 1.1:
			return "Too close to %s." % String(st["name"])
	for ws: Dictionary in WorldGen.sites:
		var wp: Vector2 = ws["pos"]
		if wp.distance_to(pos) < float(ws.get("clear", 6.0)) + D.half_size(kind).length():
			return "That ground is taken."
	if WorldGen.road_distance(pos.x, pos.y) < 2.5 + D.half_size(kind).y and kind not in ["gate", "campfire"]:
		return "That would block the road."
	if WorldGen.forest_density(pos.x, pos.y) > 0.55 and kind not in ["fence", "palisade", "stone_wall", "campfire"]:
		return "Too thick with trees. Clear them first."
	if has_homestead_block(pos):
		return "That is homestead land."
	return ""


func has_homestead_block(pos: Vector2) -> bool:
	if bag is Dictionary:
		return false
	var hs: Variant = Life.get("homestead")
	if hs == null:
		return false
	for pl: Dictionary in (hs as Object).call("plots"):
		if (pl["pos"] as Vector2).distance_to(pos) < 18.0:
			return true
	return false


## Stock you could lay on a site there: inventory plus the local holding's store.
func available(item: String, pos: Vector2) -> int:
	var hid := holding_at(pos)
	return _have(item) + (store_count(hid, item) if hid > 0 else 0)


## Prerequisites, ground and the starting share of materials. "" means you may lay the blueprint.
func can_place(kind: String, pos: Vector2, yaw: float, upgrade_of := 0) -> String:
	var needs := missing_needs_for_upgrade(kind) if upgrade_of > 0 else missing_needs(kind)
	if not needs.is_empty():
		return String(needs[0]) + "."
	if upgrade_of > 0:
		var old: Dictionary = sites.get(upgrade_of, {})
		if old.is_empty() or String(old["state"]) != "done" or String(D.def(kind).get("upgrades_from", "")) != String(old["kind"]):
			return "That cannot be upgraded to a %s." % String(D.def(kind).get("name", kind)).to_lower()
		for id: int in sites:
			if int(sites[id].get("upgrade_of", 0)) == upgrade_of:
				return "Already being upgraded."
	var why := can_place_here(kind, pos, yaw, upgrade_of)
	if why != "":
		return why
	var cost := costs_for(kind, upgrade_of > 0)
	for item: String in cost:
		var need := int(ceil(int(cost[item]) * D.START_SHARE))
		if available(item, pos) < need:
			return "Bring at least %d %s to start." % [need, _item_name(item)]
	return ""


func _item_name(item: String) -> String:
	return String(D.MATERIALS.get(item, item.capitalize()))


## Lays a blueprint and puts what you carry onto the site. Checks that builders can walk there.
## `from` is where you are standing (the route is checked from there and from the holding's hub).
func place(kind: String, pos: Vector2, yaw: float, upgrade_of := 0, from := Vector2.INF) -> Dictionary:
	var why := can_place(kind, pos, yaw, upgrade_of)
	if why != "":
		return {"ok": false, "reason": why, "id": 0}
	var hid := holding_at(pos)
	var probe := {"kind": kind, "pos": [pos.x, pos.y], "yaw": yaw}
	var door := Nav.door_of(probe)
	var anchors: Array[Vector2] = []
	if hid > 0:
		anchors.append(hub_pos(hid))
	if from != Vector2.INF:
		anchors.append(from)
	var okay := anchors.is_empty()
	for a: Vector2 in anchors:
		if a.distance_to(door) < 260.0 and Nav.reachable(self, a, door, upgrade_of):
			okay = true
			break
	if not okay:
		return {"ok": false, "reason": "Nobody could walk there: water or cliffs in the way.", "id": 0}
	if hid == 0:
		hid = _new_holding(pos)
	var id := _next_site
	_next_site += 1
	var cost := costs_for(kind, upgrade_of > 0)
	var s := {"id": id, "kind": kind, "pos": [pos.x, pos.y], "yaw": yaw, "holding": hid, "state": "site",
		"progress": 0.0, "total": hours_for(kind, upgrade_of > 0), "need": cost, "have": {}, "workers": [],
		"upgrade_of": upgrade_of, "started_day": _day, "done_day": -1, "carry": 0.0}
	sites[id] = s
	_trail_dirty = true
	# stock the site from the local store first, then your pack
	for item: String in cost:
		var n := int(cost[item])
		var from_store := mini(store_count(hid, item), n)
		if from_store > 0:
			(holdings[hid]["store"] as Dictionary)[item] = store_count(hid, item) - from_store
		var from_pack := 0
		if n - from_store > 0:
			from_pack = mini(_have(item), n - from_store)
			if from_pack > 0:
				_take(item, from_pack)
		if from_store + from_pack > 0:
			(s["have"] as Dictionary)[item] = from_store + from_pack
	return {"ok": true, "reason": "", "id": id}



## Build-kit hook (scripts/realm/build_kit.gd; docs/regions/HOOKS_FOR_CLOUD.md): a blueprint of kit pieces becomes one ordinary
## site of kind "kit_plan" with its own material bill and labour-hours, so the existing crews, hauling, stages and stalls raise it.
## The kit grid already checked the ground and support; this only stocks the site like place() does.
func place_kit_plan(pos: Vector2, yaw: float, cost: Dictionary, hours: float, label := "") -> Dictionary:
	var hid := holding_at(pos)
	if hid == 0:
		hid = _new_holding(pos)
	var id := _next_site
	_next_site += 1
	var need := {}
	for item: String in cost:
		if int(cost[item]) > 0:
			need[item] = int(cost[item])
	var s := {"id": id, "kind": "kit_plan", "pos": [pos.x, pos.y], "yaw": yaw, "holding": hid, "state": "site",
		"progress": 0.0, "total": maxf(hours, 1.0), "need": need, "have": {}, "workers": [],
		"upgrade_of": 0, "started_day": _day, "done_day": -1, "carry": 0.0, "label": label}
	sites[id] = s
	_trail_dirty = true
	for item: String in need:
		var n := int(need[item])
		var from_store := mini(store_count(hid, item), n)
		if from_store > 0:
			(holdings[hid]["store"] as Dictionary)[item] = store_count(hid, item) - from_store
		var from_pack := mini(_have(item), n - from_store)
		if from_pack > 0:
			_take(item, from_pack)
		if from_store + from_pack > 0:
			(s["have"] as Dictionary)[item] = from_store + from_pack
	return {"ok": true, "reason": "", "id": id}

# ------------------------------------------------------------------ NPC development sites (realm/civilization.gd)
## A settlement's own project (houses, walls, a market...) shown as a normal staged site (foundation -> frame -> walls ->
## roof -> done) with no holding, no crew and no materials to haul: civilization.gd sets its progress from the calendar, so the
## stage the player sees is a pure function of the day. NPC sites never count for the player's unlocks, upkeep or levels.

func npc_place(kind: String, pos: Vector2, yaw: float, total_hours: float, label: String, node: String) -> int:
	if not D.CATALOG.has(kind):
		return 0
	var id := _next_site
	_next_site += 1
	sites[id] = {"id": id, "kind": kind, "pos": [pos.x, pos.y], "yaw": yaw, "holding": 0, "state": "site",
		"progress": 0.0, "total": maxf(total_hours, 1.0), "need": {}, "have": {}, "workers": [],
		"upgrade_of": 0, "started_day": _day, "done_day": -1, "carry": 0.0, "npc": true, "label": label, "node": node}
	_trail_dirty = true
	return id


## Progress 0..1 (never moves backwards). Returns the stage name the site is now at.
func npc_set_progress(id: int, frac: float) -> String:
	var s: Dictionary = sites.get(id, {})
	if s.is_empty() or not bool(s.get("npc", false)) or String(s["state"]) == "done":
		return ""
	s["progress"] = maxf(float(s["progress"]), clampf(frac, 0.0, 0.999) * float(s["total"]))
	return D.stage_name(float(s["progress"]) / float(s["total"]))


func npc_finish(id: int) -> void:
	var s: Dictionary = sites.get(id, {})
	if s.is_empty() or not bool(s.get("npc", false)):
		return
	s["state"] = "done"
	s["progress"] = float(s["total"])
	s["done_day"] = _day


func npc_remove(id: int) -> void:
	if bool(sites.get(id, {}).get("npc", false)):
		sites.erase(id)
		_trail_dirty = true


## Keeps the save small: only the newest `keep` finished NPC buildings stay as sites (the rest are simply part of the town).
func npc_prune(keep: int) -> int:
	var done: Array = []
	for id: int in sites:
		var s: Dictionary = sites[id]
		if bool(s.get("npc", false)) and String(s["state"]) == "done":
			done.append(id)
	done.sort()
	var n := 0
	while done.size() > keep:
		sites.erase(done.pop_front())
		n += 1
	if n > 0:
		_trail_dirty = true
	return n


func npc_sites(node := "") -> Array:
	var out: Array = []
	var ids := sites.keys()
	ids.sort()
	for id: int in ids:
		var s: Dictionary = sites[id]
		if bool(s.get("npc", false)) and (node == "" or String(s.get("node", "")) == node):
			out.append(s)
	return out


func upgrade_options(site_id: int) -> Array:
	var out: Array = []
	var s: Dictionary = sites.get(site_id, {})
	if s.is_empty() or String(s["state"]) != "done":
		return out
	for k: String in D.KIND_ORDER:
		if String(D.CATALOG[k].get("upgrades_from", "")) == String(s["kind"]):
			out.append(k)
	return out


func upgrade(site_id: int, to_kind: String, from := Vector2.INF) -> Dictionary:
	var s: Dictionary = sites.get(site_id, {})
	if s.is_empty():
		return {"ok": false, "reason": "No such building.", "id": 0}
	return place(to_kind, site_pos(s), float(s["yaw"]), site_id, from)


## Stops work and puts the delivered materials back into the holding's store.
func cancel_site(site_id: int) -> bool:
	var s: Dictionary = sites.get(site_id, {})
	if s.is_empty() or String(s["state"]) == "done":
		return false
	var hid := int(s["holding"])
	if holdings.has(hid):
		var st: Dictionary = holdings[hid]["store"]
		for item: String in s["have"]:
			st[item] = int(st.get(item, 0)) + int(s["have"][item])
	for wid: String in (s["workers"] as Array).duplicate():
		unassign(wid)
	sites.erase(site_id)
	_trail_dirty = true
	return true


## Hand over materials from your pack to a site. Returns how many went in.
func deliver(site_id: int, item: String, n: int) -> int:
	var s: Dictionary = sites.get(site_id, {})
	if s.is_empty() or String(s["state"]) == "done":
		return 0
	var room := int(s["need"].get(item, 0)) - int(s["have"].get(item, 0))
	var k := mini(mini(n, room), _have(item))
	if k <= 0 or not _take(item, k):
		return 0
	(s["have"] as Dictionary)[item] = int(s["have"].get(item, 0)) + k
	return k


func deliver_all(site_id: int) -> int:
	var s: Dictionary = sites.get(site_id, {})
	var t := 0
	for item: String in s.get("need", {}):
		t += deliver(site_id, item, 9999)
	return t


# ------------------------------------------------------------------ workers

func _worker_name(r: RandomNumberGenerator) -> String:
	return String(D.NAMES[r.randi() % D.NAMES.size()])


func _new_worker(src: String, nm: String, skill: float, wage: int, role: String) -> Dictionary:
	var id := "w%d" % _next_worker
	_next_worker += 1
	var r := _rng("worker", id)
	var w := {"id": id, "name": nm, "src": src, "fid": "", "skill": skill, "wage": wage, "role": role, "site": 0,
		"strength": snappedf(r.randf_range(0.85, 1.2), 0.01), "unpaid": 0, "master": skill >= D.MASTER_SKILL}
	workers[id] = w
	return w


func worker_count(site_id: int, role := "") -> int:
	var n := 0
	for wid: String in sites.get(site_id, {}).get("workers", []):
		if role == "" or String(workers[wid]["role"]) == role:
			n += 1
	return n


func _attach(w: Dictionary, site_id: int) -> void:
	var old := int(w["site"])
	if old > 0 and sites.has(old):
		(sites[old]["workers"] as Array).erase(String(w["id"]))
	w["site"] = site_id
	(sites[site_id]["workers"] as Array).append(String(w["id"]))


func unassign(wid: String) -> void:
	var w: Dictionary = workers.get(wid, {})
	if w.is_empty():
		return
	var sid := int(w["site"])
	if sites.has(sid):
		(sites[sid]["workers"] as Array).erase(wid)
	w["site"] = 0
	if String(w["src"]) != "player" and String(w["src"]) != "follower":
		workers.erase(wid)
	elif String(w["src"]) == "follower":
		var fm := _mod("followers")
		if fm != null:
			fm.call("assign_post", String(w["fid"]), "")
		workers.erase(wid)


func player_worker() -> Dictionary:
	for wid: String in workers:
		if String(workers[wid]["src"]) == "player":
			return workers[wid]
	return {}


## You pick up a hammer on a site (role "build" or "haul"). One site at a time.
func assign_player(site_id: int, role := "build") -> Dictionary:
	if not sites.has(site_id) or String(sites[site_id]["state"]) == "done":
		return {}
	var w := player_worker()
	if w.is_empty():
		w = _new_worker("player", "You", 0.0, 0, role)
	w["role"] = role
	_attach(w, site_id)
	return w


func assign_follower(site_id: int, fid: String, role := "build") -> Dictionary:
	if not sites.has(site_id) or String(sites[site_id]["state"]) == "done":
		return {}
	var fm := _mod("followers")
	if fm == null:
		return {}
	var f: Dictionary = fm.call("get_follower", fid)
	if f.is_empty() or String(f["status"]) != "present":
		return {}
	for wid: String in workers:
		if String(workers[wid]["fid"]) == fid:
			unassign(wid)
			break
	var w := _new_worker("follower", String(f["name"]), 0.0, 0, role)
	w["fid"] = fid
	_attach(w, site_id)
	fm.call("assign_post", fid, "build:%d" % site_id)
	return w


## Nearest settlement that can supply labour within a day's walk, or -1.
func labour_source(pos: Vector2) -> int:
	var best := -1
	var bd := 1800.0
	for st: Dictionary in WorldGen.settlements:
		var d := pos.distance_to(st["pos"])
		if d < bd:
			bd = d
			best = int(st["id"])
	return best


func hired_from(sid: int) -> int:
	var n := 0
	for wid: String in workers:
		var w: Dictionary = workers[wid]
		if String(w["src"]) == "hired" and int(w.get("home", -1)) == sid:
			n += 1
	return n


## Labourers a settlement can spare for you (shares the fief crew pool with enterprise works).
func labour_free(sid: int) -> int:
	var e := _mod("enterprise")
	var free := 6
	if e != null and e.has_method("labour_free"):
		free = int(e.call("labour_free", sid))
	return maxi(0, free)


func hire_builder(site_id: int, master := false, role := "build") -> Dictionary:
	var s: Dictionary = sites.get(site_id, {})
	if s.is_empty() or String(s["state"]) == "done":
		return {"ok": false, "reason": "Nothing to build there.", "id": ""}
	if (s["workers"] as Array).size() >= D.MAX_WORKERS:
		return {"ok": false, "reason": "The site is crowded enough.", "id": ""}
	var pos := site_pos(s)
	var sid := labour_source(pos)
	if sid < 0:
		return {"ok": false, "reason": "No village near enough to hire from.", "id": ""}
	var st: Dictionary = WorldGen.settlements[sid]
	if master and String(st["kind"]) not in ["town", "castle", "frontier_town"]:
		return {"ok": false, "reason": "No master builder lives that close. Try a town.", "id": ""}
	if labour_free(sid) - hired_from(sid) < 1:
		return {"ok": false, "reason": "%s has no spare hands." % String(st["name"]), "id": ""}
	var wage := D.MASTER_WAGE if master else (D.HIRE_WAGE if role == "build" else D.HIRE_WAGE - 1)
	if gold_available() < wage:
		return {"ok": false, "reason": "A day's wage is %d gold." % wage, "id": ""}
	var r := _rng("hire", "%d:%d" % [site_id, _next_worker])
	var skill := r.randf_range(0.7, 0.88) if master else r.randf_range(0.18, 0.5)
	var w := _new_worker("hired", ("Master " if master else "") + _worker_name(r), skill, wage, role)
	w["home"] = sid
	w["master"] = master
	_attach(w, site_id)
	return {"ok": true, "reason": "", "id": String(w["id"])}


func dismiss(wid: String) -> void:
	unassign(wid)


## Skill 0..1 of a worker for a discipline ("carpentry" or "masonry").
func worker_skill(w: Dictionary, disc: String) -> float:
	match String(w["src"]):
		"player":
			return clampf(float(_mastery().call("level", disc)) / 100.0, 0.02, 1.0)
		"follower":
			var fm := _mod("followers")
			var f: Dictionary = fm.call("get_follower", String(w["fid"])) if fm != null else {}
			if f.is_empty():
				return 0.0
			var sk: Dictionary = f["skills"]
			return clampf(float(sk.get("building", float(sk.get("repair", 0.25)) * 0.6)), 0.05, 1.0)
	return float(w["skill"])


func _active(w: Dictionary, site: Dictionary, ctx: Dictionary) -> bool:
	match String(w["src"]):
		"player":
			if not ctx.has("player_pos"):
				return true
			var pp := _p2(ctx["player_pos"])
			return pp != Vector2.INF and pp.distance_to(site_pos(site)) <= D.PLAYER_NEAR
		"follower":
			var fm := _mod("followers")
			var f: Dictionary = fm.call("get_follower", String(w["fid"])) if fm != null else {}
			if f.is_empty() or String(f["status"]) != "present":
				return false
			return true
	return int(w.get("unpaid", 0)) < 1


func discipline_of(kind: String) -> String:
	var cost: Dictionary = D.def(kind).get("cost", {})
	return "masonry" if cost.has("cut_stone") else "carpentry"


func tools_on(site: Dictionary) -> bool:
	if store_count(int(site["holding"]), "tools") > 0:
		return true
	return _have("hammer") > 0 or _have("tools") > 0 or _have("wood_axe") > 0


func crew_cap(kind: String) -> int:
	var sz: Vector2 = D.def(kind).get("size", Vector2(3, 3))
	return clampi(2 + int(sz.x * sz.y / 14.0), 2, D.MAX_WORKERS)


## Labour-hours one crew adds per working hour. Shared by the fief projects (enterprise) and player sites.
## rates: each builder's 0..1 skill; masters are those at or above MASTER_SKILL.
static func crew_labour(skills: Array, tools: bool, cap: int) -> Dictionary:
	var rates: Array = []
	var masters := 0
	var best := 0.0
	for sk: float in skills:
		var r := 0.45 + 0.9 * sk
		if tools:
			r *= D.TOOL_BONUS
		rates.append(r)
		best = maxf(best, sk)
		if sk >= D.MASTER_SKILL:
			masters += 1
	rates.sort()
	rates.reverse()
	var total := 0.0
	for i in rates.size():
		total += float(rates[i]) * (1.0 if i < cap else D.CROWD_FACTOR)
	total *= 1.0 + minf(D.MASTER_BONUS_CAP, D.MASTER_BONUS * masters)
	return {"rate": total, "masters": masters, "best": best, "builders": skills.size()}


## Fief crews: man-days of progress per day for `crew` labourers of average skill, scaled so the default
## crew (skill 0.4, no tools) matches the old flat rate of one man-day each.
func crew_output(crew: int, avg_skill := 0.4, tools := false, masters := 0) -> float:
	var sk: Array = []
	for i in crew:
		sk.append(D.MASTER_SKILL + 0.05 if i < masters else avg_skill)
	var base := (0.45 + 0.9 * 0.4)
	return float(crew_labour(sk, tools, D.MAX_WORKERS + 4)["rate"]) / base


func labour_taken(sid: int) -> int:
	return hired_from(sid)


## A finished fief project counts as a building for unlocking and identity.
func on_fief_complete(_sid: int, project: String) -> void:
	var k := String(D.FIEF_TO_KIND.get(project, ""))
	if k != "":
		external[k] = int(external.get(k, 0)) + 1
	external["_any"] = maxi(int(external.get("_any", 0)), 0)


func site_rate(site: Dictionary, ctx: Dictionary) -> Dictionary:
	var kind := String(site["kind"])
	var disc := discipline_of(kind)
	var skills: Array = []
	var haulers := 0
	for wid: String in site["workers"]:
		var w: Dictionary = workers[wid]
		if not _active(w, site, ctx):
			continue
		match String(w["role"]):
			"build":
				skills.append(worker_skill(w, disc))
			"haul":
				haulers += 1
	var tools := tools_on(site)
	var r := crew_labour(skills, tools, crew_cap(kind))
	r["haulers"] = haulers
	r["tools"] = tools
	return r


func allowed_progress(site: Dictionary) -> float:
	var frac := 1.0
	for item: String in site["need"]:
		var need := int(site["need"][item])
		if need > 0:
			frac = minf(frac, float(int(site["have"].get(item, 0))) / need)
	return float(site["total"]) * frac


func missing_materials(site: Dictionary) -> Dictionary:
	var out := {}
	for item: String in site["need"]:
		var m := int(site["need"][item]) - int(site["have"].get(item, 0))
		if m > 0:
			out[item] = m
	return out


func pack_bonus() -> float:
	var fm := _mod("followers")
	if fm == null or not fm.has_method("tamed"):
		return 0.0
	var b := 0.0
	for c: Dictionary in fm.call("tamed"):
		var sp: Dictionary = fm.get("SPECIES").get(String(c["species"]), {})
		b += float(sp.get("roles", {}).get("hauling", 0.0)) * 0.6
	return minf(b, 1.5)


## Units per working hour the site's haulers bring from the holding's store.
func haul_rate(site: Dictionary, ctx: Dictionary) -> float:
	var hid := int(site["holding"])
	if not holdings.has(hid):
		return 0.0
	var hp := hub_pos(hid)
	var door := Nav.door_of(site)
	var speed := 1.0
	var hs := hub_site(hid)
	if not hs.is_empty():
		speed = path_speed(int(hs["id"]), int(site["id"]))
	var dist := hp.distance_to(door) * 1.15
	var trip := 2.0 * dist / (D.HAUL_M_PER_HOUR * speed) + D.LOAD_HOURS
	var total := 0.0
	var pack := 1.0 + pack_bonus()
	for wid: String in site["workers"]:
		var w: Dictionary = workers[wid]
		if String(w["role"]) != "haul" or not _active(w, site, ctx):
			continue
		var str_mult := float(w.get("strength", 1.0))
		if String(w["src"]) == "player":
			str_mult = 1.1
		total += D.CARRY_BASE * str_mult * pack / trip
	return total


func stall_reason(site: Dictionary, ctx := {}) -> String:
	if String(site["state"]) == "done":
		return ""
	var r := site_rate(site, ctx)
	var d := D.def(String(site["kind"]))
	if int(r["builders"]) == 0:
		return "No builders on site."
	if float(r["best"]) < float(d.get("min_skill", 0.0)) - 1e-6:
		var need := float(d.get("min_skill", 0.0))
		return "Needs a %s (skill %d)." % ["master builder" if need >= D.MASTER_SKILL else "skilled builder", int(round(need * 100.0))]
	if float(site["progress"]) >= allowed_progress(site) - 1e-6:
		var miss := missing_materials(site)
		var parts := PackedStringArray()
		for item: String in D.MATERIAL_ORDER:
			if miss.has(item):
				parts.append("%d %s" % [int(miss[item]), _item_name(item).to_lower()])
		return "Waiting for " + ", ".join(parts) + "."
	return ""


func eta_working_hours(site: Dictionary, ctx := {}) -> float:
	if String(site["state"]) == "done":
		return 0.0
	if stall_reason(site, ctx) != "":
		return -1.0
	var rate := float(site_rate(site, ctx)["rate"])
	if rate <= 0.0:
		return -1.0
	return (float(site["total"]) - float(site["progress"])) / rate


## Wall-clock game hours to go (nights are not worked).
func eta_hours(site: Dictionary, ctx := {}) -> float:
	var wh := eta_working_hours(site, ctx)
	if wh < 0.0:
		return -1.0
	return wh + floorf(wh / float(D.WORK_HOURS_PER_DAY)) * float(24 - D.WORK_HOURS_PER_DAY)


func site_info(site_id: int, ctx := {}) -> Dictionary:
	var s: Dictionary = sites.get(site_id, {})
	if s.is_empty():
		return {}
	var d := D.def(String(s["kind"]))
	var r := site_rate(s, ctx)
	var pct := clampf(float(s["progress"]) / maxf(float(s["total"]), 0.001), 0.0, 1.0) if String(s["state"]) != "done" else 1.0
	return {"id": site_id, "kind": String(s["kind"]), "name": String(d["name"]), "pct": pct, "stage": D.stage_name(pct),
		"stage_i": D.stage_index(pct), "builders": int(r["builders"]), "haulers": int(r["haulers"]), "masters": int(r["masters"]),
		"best": float(r["best"]), "rate": float(r["rate"]), "tools": bool(r["tools"]), "stall": stall_reason(s, ctx),
		"eta": eta_hours(s, ctx), "missing": missing_materials(s), "need": s["need"], "have": s["have"],
		"workers": (s["workers"] as Array).size(), "min_skill": float(d.get("min_skill", 0.0)), "state": String(s["state"]),
		"upgrade": int(s.get("upgrade_of", 0)) > 0}


# ------------------------------------------------------------------ the work itself

## One working hour on one site. Returns true if anything changed (so callers can stop early).
func _site_hour(site: Dictionary, ctx: Dictionary, info: Dictionary) -> bool:
	var changed := false
	var hid := int(site["holding"])
	var hr := float(info["haul"])
	if hr > 0.0 and holdings.has(hid):
		site["carry"] = float(site["carry"]) + hr
		var moved := 0
		var st: Dictionary = holdings[hid]["store"]
		while float(site["carry"]) >= 1.0:
			var picked := ""
			for item: String in D.MATERIAL_ORDER:
				if int(site["need"].get(item, 0)) > int(site["have"].get(item, 0)) and int(st.get(item, 0)) > 0:
					picked = item
					break
			if picked == "":
				site["carry"] = minf(float(site["carry"]), 1.0)
				break
			st[picked] = int(st[picked]) - 1
			(site["have"] as Dictionary)[picked] = int(site["have"].get(picked, 0)) + 1
			site["carry"] = float(site["carry"]) - 1.0
			moved += 1
		if moved > 0:
			changed = true
			var hs := hub_site(hid)
			if not hs.is_empty():
				note_trip(int(hs["id"]), int(site["id"]), float(moved) / maxf(D.CARRY_BASE, 1.0))
	var d := D.def(String(site["kind"]))
	if float(info["best"]) >= float(d.get("min_skill", 0.0)) - 1e-6 and int(info["builders"]) > 0:
		var room := minf(allowed_progress(site), float(site["total"])) - float(site["progress"])
		var gain := minf(float(info["rate"]), maxf(room, 0.0))
		if gain > 1e-9:
			site["progress"] = float(site["progress"]) + gain
			changed = true
			_train(site, gain, info)
	return changed


func _train(site: Dictionary, gain: float, _info: Dictionary) -> void:
	var disc := discipline_of(String(site["kind"]))
	for wid: String in site["workers"]:
		var w: Dictionary = workers[wid]
		if String(w["role"]) != "build":
			continue
		if String(w["src"]) == "player":
			_mastery().call("gain", disc, 0.05 * minf(gain, 2.0), _day)
		elif String(w["src"]) == "follower":
			var fm := _mod("followers")
			var f: Dictionary = fm.call("get_follower", String(w["fid"])) if fm != null else {}
			if not f.is_empty():
				f["skills"]["building"] = minf(0.95, float(f["skills"].get("building", 0.25)) + 0.0006)


func _site_info(site: Dictionary, ctx: Dictionary) -> Dictionary:
	var r := site_rate(site, ctx)
	return {"rate": float(r["rate"]), "best": float(r["best"]), "builders": int(r["builders"]), "haul": haul_rate(site, ctx)}


## Advance every building site by `hours` working hours. Sites that finish or cannot move are dropped
## from the loop, so a long absence costs next to nothing.
func advance(hours: int, ctx: Dictionary) -> Array:
	var out: Array = []
	var ids := sites.keys()
	ids.sort()
	for id: int in ids:
		var s: Dictionary = sites[id]
		if String(s["state"]) != "site" or bool(s.get("npc", false)):
			continue   # NPC development sites are staged by realm/civilization.gd (npc_set_progress)
		var info := _site_info(s, ctx)
		for _h in hours:
			if not _site_hour(s, ctx, info):
				break
			if float(s["progress"]) >= float(s["total"]) - 1e-6:
				out.append_array(_complete(s))
				break
	out.append_array(_stations(hours))
	return out


func _stations(hours: int) -> Array:
	var out: Array = []
	for id: int in sites:
		var s: Dictionary = sites[id]
		if String(s["state"]) != "done" or not D.STATIONS.has(String(s["kind"])):
			continue
		var stn: Dictionary = D.STATIONS[String(s["kind"])]
		var hid := int(s["holding"])
		if not holdings.has(hid):
			continue
		for wid: String in s["workers"]:
			var w: Dictionary = workers[wid]
			if String(w["role"]) != "craft" or (String(w["src"]) == "hired" and int(w.get("unpaid", 0)) >= 1):
				continue
			var st: Dictionary = holdings[hid]["store"]
			var sk := worker_skill(w, "carpentry")
			var want := float(int(stn["per_hour"]) * hours) * (0.6 + 0.8 * sk)
			var batches := mini(int(want / int(stn["n_in"])), int(st.get(String(stn["in"]), 0)) / int(stn["n_in"]))
			if batches > 0:
				st[String(stn["in"])] = int(st[String(stn["in"])]) - batches * int(stn["n_in"])
				st[String(stn["out"])] = int(st.get(String(stn["out"]), 0)) + batches * int(stn["n_out"])
	return out


func _complete(s: Dictionary) -> Array:
	var out: Array = []
	var kind := String(s["kind"])
	var d := D.def(kind)
	s["state"] = "done"
	s["progress"] = float(s["total"])
	s["done_day"] = _day
	for wid: String in (s["workers"] as Array).duplicate():
		unassign(wid)
	s["workers"] = []
	var old_id := int(s.get("upgrade_of", 0))
	if old_id > 0 and sites.has(old_id):
		var old: Dictionary = sites[old_id]
		var old_kind := String(old["kind"])
		s["from_kind"] = old_kind
		sites.erase(old_id)
		for k: String in trails.keys():
			var t: Dictionary = trails[k]
			if int(t["a"]) == old_id or int(t["b"]) == old_id:
				var tt: Dictionary = trails[k]
				trails.erase(k)
				var na := int(s["id"]) if int(tt["a"]) == old_id else int(tt["a"])
				var nb := int(s["id"]) if int(tt["b"]) == old_id else int(tt["b"])
				if na != nb:
					trails[_tkey(na, nb)] = {"a": mini(na, nb), "b": maxi(na, nb), "uses": float(tt["uses"])}
		out.append("%s: the %s has been upgraded to a %s." % [_hname(int(s["holding"])), old_kind.replace("_", " "), String(d["name"]).to_lower()])
	else:
		out.append("%s: the %s is finished." % [_hname(int(s["holding"])), String(d["name"]).to_lower()])
	for f: String in d.get("grants", []):
		if not known.has(f):
			known[f] = true
			out.append("You have learned %s." % String(D.KNOW_NAMES.get(f, f)).to_lower())
	_trail_dirty = true
	_register_world(s)
	out.append_array(_update_level(int(s["holding"])))
	return out


func _hname(hid: int) -> String:
	return String(holdings.get(hid, {}).get("name", "Camp"))


## Hooks a finished building into the wider realm: camp supply chains, settlement identity, the street graph.
func _register_world(s: Dictionary) -> void:
	var kind := String(s["kind"])
	var d := D.def(kind)
	var hid := int(s["holding"])
	var pos := site_pos(s)
	var cm := _mod("camps")
	var h: Dictionary = holdings.get(hid, {})
	if cm != null and not h.is_empty() and int(h["camp"]) > 0 and D.CAMP_KIND.has(kind):
		var st: Dictionary = cm.call("place_structure", int(h["camp"]), String(D.CAMP_KIND[kind]), pos)
		if not st.is_empty():
			st["hours_left"] = 0
			st["active"] = true
			st["src"] = "construction"
	var stl := _mod("settlements")
	if stl != null and d.has("ident"):
		var near := WorldGen.nearest_settlement(pos)
		if not near.is_empty() and pos.distance_to(near["pos"]) < float(near["radius"]) * 3.0:
			stl.call("add_structure", int(near["id"]), String(d["ident"]))
			s["fed"] = int(near["id"])
	var stl_near := WorldGen.nearest_settlement(pos)
	if not stl_near.is_empty() and pos.distance_to(stl_near["pos"]) < float(stl_near["radius"]) * 3.0:
		var sid := int(stl_near["id"])
		var entry := [pos, float(s["yaw"]), D.half_size(kind), Nav.door_of(s)]
		if _street_queue_on:
			# catch_up: queue, flush once per town (see _flush_street_queue)
			if not _street_queue.has(sid):
				_street_queue[sid] = []
			(_street_queue[sid] as Array).append(entry)
		else:
			var sg: RefCounted = load("res://scripts/population/street_graph.gd").for_settlement(sid)
			if sg != null and sg.has_method("register_building"):
				sg.call("register_building", entry[0], entry[1], entry[2], entry[3])


## Registers the buildings queued during catch_up with their towns' street graphs, in finish order.
func _flush_street_queue() -> void:
	_street_queue_on = false
	var queue := _street_queue
	_street_queue = {}
	for sid: int in queue:
		var sg: RefCounted = load("res://scripts/population/street_graph.gd").for_settlement(sid)
		if sg != null and sg.has_method("register_buildings"):
			sg.call("register_buildings", queue[sid])


# ------------------------------------------------------------------ settlement levels

func _holding_sites(hid: int, done_only := true) -> Array:
	var out: Array = []
	for id: int in sites:
		var s: Dictionary = sites[id]
		if int(s["holding"]) == hid and (not done_only or String(s["state"]) == "done"):
			out.append(s)
	return out


func beds_of(hid: int) -> int:
	var n := 0
	for s: Dictionary in _holding_sites(hid):
		n += int(D.CATALOG[String(s["kind"])].get("beds", 0))
	return n


func roles_of(hid: int) -> Dictionary:
	var out := {}
	for s: Dictionary in _holding_sites(hid):
		var role := String(D.CATALOG[String(s["kind"])].get("role", ""))
		out[role] = int(out.get(role, 0)) + 1
	return out


func _level_index(hid: int) -> int:
	var h: Dictionary = holdings.get(hid, {})
	if h.is_empty():
		return 0
	var done := _holding_sites(hid)
	var roles := roles_of(hid)
	var max_tier := 0
	for s: Dictionary in done:
		max_tier = maxi(max_tier, int(D.CATALOG[String(s["kind"])]["tier"]))
	var best := 0
	for i in D.LEVELS.size():
		var L: Dictionary = D.LEVELS[i]
		if done.size() < int(L["buildings"]) or float(h["pop"]) < float(L["pop"]) or max_tier < int(L["tiers"]):
			break
		var ok := true
		for role: String in L["roles"]:
			if int(roles.get(role, 0)) < int(L["roles"][role]):
				ok = false
		if not ok:
			break
		best = i
	return best


## What a holding still needs for its next level: [] at the top.
func next_level_needs(hid: int) -> Array:
	var i := _level_index(hid)
	if i >= D.LEVELS.size() - 1:
		return []
	var L: Dictionary = D.LEVELS[i + 1]
	var h: Dictionary = holdings[hid]
	var done := _holding_sites(hid)
	var out: Array = []
	if done.size() < int(L["buildings"]):
		out.append("%d more buildings" % (int(L["buildings"]) - done.size()))
	if float(h["pop"]) < float(L["pop"]):
		out.append("%d people (have %d)" % [int(L["pop"]), int(h["pop"])])
	var max_tier := 0
	for s: Dictionary in done:
		max_tier = maxi(max_tier, int(D.CATALOG[String(s["kind"])]["tier"]))
	if max_tier < int(L["tiers"]):
		out.append("a tier %d building" % int(L["tiers"]))
	var roles := roles_of(hid)
	for role: String in L["roles"]:
		if int(roles.get(role, 0)) < int(L["roles"][role]):
			out.append("%d %s buildings" % [int(L["roles"][role]), role])
	return out


func _update_level(hid: int) -> Array:
	var h: Dictionary = holdings.get(hid, {})
	if h.is_empty():
		return []
	var i := _level_index(hid)
	var id := String(D.LEVELS[i]["id"])
	if id == String(h["level"]):
		return []
	var up := i > _level_by_id(String(h["level"]))
	h["level"] = id
	if up:
		return ["%s has grown into a %s." % [h["name"], String(D.LEVELS[i]["name"]).to_lower()]]
	return ["%s has shrunk to a %s." % [h["name"], String(D.LEVELS[i]["name"]).to_lower()]]


func _level_by_id(id: String) -> int:
	for i in D.LEVELS.size():
		if String(D.LEVELS[i]["id"]) == id:
			return i
	return 0


func level_name(hid: int) -> String:
	for L: Dictionary in D.LEVELS:
		if String(L["id"]) == String(holdings.get(hid, {}).get("level", "camp")):
			return String(L["name"])
	return "Camp"


## Identity weights of a holding from what stands in it, in settlements.gd's vocabulary.
func holding_identity(hid: int) -> Dictionary:
	var raw := {}
	for i: String in SettlementsScript.IDENTITIES:
		raw[i] = 0.0
	for s: Dictionary in _holding_sites(hid):
		var ik := String(D.CATALOG[String(s["kind"])].get("ident", ""))
		var w: Dictionary = SettlementsScript.STRUCT_WEIGHT.get(ik, {})
		for i: String in w:
			raw[i] += float(w[i])
	var h: Dictionary = holdings.get(hid, {})
	if not h.is_empty():
		raw["farming"] += float(roles_of(hid).get("food", 0)) * 0.6 + float(roles_of(hid).get("shelter", 0)) * 0.3
		raw["mining"] += float(roles_of(hid).get("craft", 0)) * 0.3
	var total := 0.0
	for i: String in raw:
		total += float(raw[i])
	var top := ""
	var tv := 0.0
	var out := {}
	for i: String in raw:
		out[i] = float(raw[i]) / total if total > 0.0 else 0.0
		if float(out[i]) > tv:
			tv = float(out[i])
			top = i
	return {"weights": out, "top": top}


func holding_info(hid: int) -> Dictionary:
	var h: Dictionary = holdings.get(hid, {})
	if h.is_empty():
		return {}
	var idn := holding_identity(hid)
	return {"id": hid, "name": String(h["name"]), "level": String(h["level"]), "level_name": level_name(hid),
		"buildings": _holding_sites(hid).size(), "beds": beds_of(hid), "pop": int(h["pop"]), "roles": roles_of(hid),
		"next": next_level_needs(hid), "identity": String(idn["top"]), "store_used": store_used(hid), "store_cap": store_cap(hid)}


# ------------------------------------------------------------------ trails

static func _tkey(a: int, b: int) -> String:
	return "%d|%d" % [mini(a, b), maxi(a, b)]


func note_trip(a: int, b: int, n := 1.0) -> void:
	if a == b or not sites.has(a) or not sites.has(b):
		return
	var k := _tkey(a, b)
	if not trails.has(k):
		trails[k] = {"a": mini(a, b), "b": maxi(a, b), "uses": 0.0}
	var old := trail_level(float(trails[k]["uses"]))
	trails[k]["uses"] = float(trails[k]["uses"]) + n
	if trail_level(float(trails[k]["uses"])) != old:
		_trail_dirty = true


static func trail_level(uses: float) -> String:
	if uses >= D.ROAD_USES:
		return "road"
	if uses >= D.FOOTPATH_USES:
		return "footpath"
	return ""


func path_speed(a: int, b: int) -> float:
	var t: Dictionary = trails.get(_tkey(a, b), {})
	if t.is_empty():
		return 1.0
	return float(D.PATH_SPEED[trail_level(float(t["uses"]))])


## Worn trails as [from, to, speed multiplier] for routing.
func trail_segments() -> Array:
	if not _trail_dirty:
		return _trail_cache
	_trail_cache = []
	for k: String in trails:
		var t: Dictionary = trails[k]
		var lv := trail_level(float(t["uses"]))
		if lv == "" or not sites.has(int(t["a"])) or not sites.has(int(t["b"])):
			continue
		_trail_cache.append([Nav.door_of(sites[int(t["a"])]), Nav.door_of(sites[int(t["b"])]), float(D.PATH_SPEED[lv])])
	_trail_dirty = false
	return _trail_cache


## For drawing: every trail with any wear, [{a, b, level, uses}].
func trail_list() -> Array:
	var out: Array = []
	for k: String in trails:
		var t: Dictionary = trails[k]
		if not sites.has(int(t["a"])) or not sites.has(int(t["b"])) or float(t["uses"]) < 3.0:
			continue
		out.append({"a": Nav.door_of(sites[int(t["a"])]), "b": Nav.door_of(sites[int(t["b"])]),
			"level": trail_level(float(t["uses"])), "uses": float(t["uses"])})
	return out


func _daily_trails() -> void:
	for hid: int in holdings:
		var homes: Array = []
		var users: Array = []
		for s: Dictionary in _holding_sites(hid):
			var role := String(D.CATALOG[String(s["kind"])].get("role", ""))
			if role == "shelter" and int(D.CATALOG[String(s["kind"])].get("beds", 0)) > 0:
				homes.append(s)
			elif role in ["food", "craft", "water", "trade", "storage", "faith", "command"]:
				users.append(s)
		if homes.is_empty() or float(holdings[hid]["pop"]) < 1.0:
			continue
		for u: Dictionary in users:
			var near: Dictionary = homes[0]
			var bd := INF
			for hm: Dictionary in homes:
				var d := site_pos(hm).distance_to(site_pos(u))
				if d < bd:
					bd = d
					near = hm
			note_trip(int(near["id"]), int(u["id"]), 1.0)
		# the hub sees every road of the holding: it becomes a real road when well worn
		var hs := hub_site(hid)
		if not hs.is_empty():
			var worn := 0.0
			for k: String in trails:
				var t: Dictionary = trails[k]
				if int(t["a"]) == int(hs["id"]) or int(t["b"]) == int(hs["id"]):
					worn += float(t["uses"])
			if worn >= D.ROAD_USES and not bool(holdings[hid]["road_done"]):
				_road_to_realm(hid)


func _road_to_realm(hid: int) -> void:
	var h: Dictionary = holdings[hid]
	h["road_done"] = true
	var cm := _mod("camps")
	if cm == null or int(h["camp"]) <= 0:
		return
	var me := "c%d" % int(h["camp"])
	for e: Dictionary in cm.call("edges"):
		if String(e["a"]) == me or String(e["b"]) == me:
			cm.call("build_road", e["a"], e["b"], "road")
	_say("Traffic has worn a real road out of %s." % String(h["name"]))


# ------------------------------------------------------------------ gathering in the wild

static func node_key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]


## Rolls what a world grid cell holds: {ok, kind, pos, yaw, scale} (deterministic per cell).
static func node_cell(c: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(c.x, c.y, 9191))
	var q := (Vector2(c) + Vector2(rng.randf_range(0.15, 0.85), rng.randf_range(0.15, 0.85))) * D.NODE_CELL
	var roll := rng.randf()
	var yaw := rng.randf() * TAU
	var scl := rng.randf_range(0.85, 1.2)
	var out := {"ok": false}
	if WorldGen.is_water(q.x, q.y) or WorldGen.road_distance(q.x, q.y) < 5.0:
		return out
	var near := WorldGen.nearest_settlement(q)
	if not near.is_empty() and q.distance_to(near["pos"]) < float(near["radius"]) * 1.15:
		return out
	var sd := WorldGen.shore_distance(q.x, q.y)
	var kind := ""
	if sd > 1.5 and sd < 18.0:
		kind = "clay" if roll < 0.4 else ("reeds" if roll < 0.85 else "")
	else:
		var forest := WorldGen.forest_density(q.x, q.y)
		var slope := absf(WorldGen.height(q.x + 3.0, q.y) - WorldGen.height(q.x - 3.0, q.y)) + absf(WorldGen.height(q.x, q.y + 3.0) - WorldGen.height(q.x, q.y - 3.0))
		if slope > 3.2 and roll < 0.55:
			kind = "rock"
		elif forest >= 0.35 and roll < 0.6:
			kind = "tree"
		elif forest < 0.35 and roll < 0.1:
			kind = "rock"
		elif forest >= 0.2 and roll < 0.07:
			kind = "reeds"
	if kind == "":
		return out
	return {"ok": true, "kind": kind, "pos": Vector3(q.x, WorldGen.height(q.x, q.y), q.y), "yaw": yaw, "scale": scl}


func node_ready(key: String, kind: String, day: int) -> bool:
	var g: Dictionary = gathered.get(key, {})
	if g.is_empty():
		return true
	var regrow := int(D.NODES[kind]["regrow"])
	if int(g["hp"]) <= 0:
		if day - int(g["day"]) >= regrow:
			gathered.erase(key)
			return true
		return false
	if day - int(g["t"]) >= 2:
		gathered.erase(key)
	return true


func node_hp(key: String, kind: String) -> int:
	return int(gathered.get(key, {}).get("hp", int(D.NODES[kind]["hp"])))


## One strike at a node. {item, n, felled}. `level` is the gatherer's skill (1..100), `roll` a 0..1 random.
func strike_node(key: String, kind: String, day: int, has_tool: bool, level: int, roll: float) -> Dictionary:
	var nd: Dictionary = D.NODES.get(kind, {})
	if nd.is_empty() or not node_ready(key, kind, day):
		return {"item": "", "n": 0, "felled": false}
	var hp := node_hp(key, kind) - 1
	var n := int(nd["per"])
	if has_tool:
		n += int(nd["bonus"])
	if roll < 0.04 * float(level - 1):
		n += 1
	var felled := hp <= 0
	if felled:
		n += int(nd["finish"])
	gathered[key] = {"hp": maxi(hp, 0), "day": day, "t": day}
	return {"item": String(nd["item"]), "n": n, "felled": felled}


# ------------------------------------------------------------------ processing

## A finished station of `kind` within `reach` of `pos`, or {}.
func station_near(kind: String, pos: Vector2, reach := 22.0) -> Dictionary:
	for id: int in sites:
		var s: Dictionary = sites[id]
		if String(s["kind"]) == kind and String(s["state"]) == "done" and site_pos(s).distance_to(pos) <= reach:
			return s
	return {}


## Turns raw material into building material at a station near you. Returns {ok, reason, made, hours}.
func process(kind: String, batches: int, pos: Vector2, reach := 22.0) -> Dictionary:
	var stn: Dictionary = D.STATIONS.get(kind, {})
	if stn.is_empty():
		return {"ok": false, "reason": "Nothing to process there.", "made": 0, "hours": 0.0}
	if station_near(kind, pos, reach).is_empty():
		return {"ok": false, "reason": "Stand by a %s." % String(D.CATALOG[kind]["name"]).to_lower(), "made": 0, "hours": 0.0}
	var k := mini(batches, _have(String(stn["in"])) / int(stn["n_in"]))
	if k <= 0:
		return {"ok": false, "reason": "You need %d %s." % [int(stn["n_in"]), _item_name(String(stn["in"])).to_lower()], "made": 0, "hours": 0.0}
	_take(String(stn["in"]), k * int(stn["n_in"]))
	_give(String(stn["out"]), k * int(stn["n_out"]))
	return {"ok": true, "reason": "", "made": k * int(stn["n_out"]), "hours": float(k * int(stn["n_in"])) / float(stn["per_hour"])}


## A master builder on your crew teaches a skill for gold.
func learn_lesson(fact: String) -> Dictionary:
	var ls: Dictionary = D.LESSONS.get(fact, {})
	if ls.is_empty():
		return {"ok": false, "reason": "Nobody teaches that."}
	if knows(fact):
		return {"ok": false, "reason": "You already know it."}
	var master := false
	for wid: String in workers:
		if bool(workers[wid].get("master", false)) and int(workers[wid]["site"]) > 0:
			master = true
	if not master:
		return {"ok": false, "reason": "Put a master builder to work on one of your sites first."}
	if fact == "build:architecture" and not knows("build:masonry"):
		return {"ok": false, "reason": "Learn masonry first."}
	if not _spend(int(ls["gold"])):
		return {"ok": false, "reason": "The lesson costs %d gold." % int(ls["gold"])}
	known[fact] = true
	return {"ok": true, "reason": ""}


# ------------------------------------------------------------------ ticks

func _working(hour: int) -> bool:
	return hour >= D.WORK_FROM and hour < D.WORK_TO


func tick_hour(hour: int, ctx: Dictionary) -> Array:
	if sites.is_empty() or not _working(hour):
		return []
	return advance(1, ctx)


func tick_day(day: int, ctx: Dictionary) -> Array:
	_day = day
	return _day_upkeep(ctx)


func _day_upkeep(_ctx: Dictionary) -> Array:
	var out: Array = []
	# wages: the hired walk off when you cannot pay them
	var wages := 0
	for wid: String in workers:
		if String(workers[wid]["src"]) == "hired":
			wages += int(workers[wid]["wage"])
	if wages > 0:
		if gold_available() >= wages:
			pending_gold -= wages
		else:
			for wid: String in workers.keys():
				if String(workers[wid]["src"]) == "hired":
					out.append("%s walks off the site: unpaid." % String(workers[wid]["name"]))
					unassign(wid)
	var up := 0.0
	for id: int in sites:
		var s: Dictionary = sites[id]
		if String(s["state"]) == "done" and not bool(s.get("npc", false)):
			up += float(D.CATALOG[String(s["kind"])].get("upkeep", 0.0))
	_upkeep_acc += up
	if _upkeep_acc >= 1.0:
		var pay := int(_upkeep_acc)
		_upkeep_acc -= pay
		pending_gold -= mini(pay, maxi(gold_available(), 0))
	for hid: int in holdings:
		var h: Dictionary = holdings[hid]
		var beds := beds_of(hid)
		var roles := roles_of(hid)
		var target := float(beds) * (0.9 if int(roles.get("water", 0)) > 0 else 0.6) * (1.0 if int(roles.get("food", 0)) + int(roles.get("storage", 0)) > 0 else 0.6)
		if float(h["pop"]) < target:
			h["pop"] = minf(target, float(h["pop"]) + 0.5)
		elif float(h["pop"]) > target:
			h["pop"] = maxf(target, float(h["pop"]) - 1.0)
		out.append_array(_update_level(hid))
	_daily_trails()
	return out


## `days` passed unobserved: replay each day's working hours (early exit per site) and the daily upkeep.
func catch_up(days: int, ctx: Dictionary) -> Array:
	var out: Array = []
	_street_queue_on = true
	for _d in mini(days, D.CATCH_UP_CAP_DAYS):
		out.append_array(advance(D.WORK_HOURS_PER_DAY, ctx))
		_day += 1
		out.append_array(_day_upkeep(ctx))
	_flush_street_queue()
	return out


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	var ss := {}
	for id: int in sites:
		ss[str(id)] = (sites[id] as Dictionary).duplicate(true)
	var hh := {}
	for id: int in holdings:
		hh[str(id)] = (holdings[id] as Dictionary).duplicate(true)
	return {"sites": ss, "workers": workers.duplicate(true), "holdings": hh, "known": known.duplicate(), "trails": trails.duplicate(true),
		"gathered": gathered.duplicate(true), "external": external.duplicate(), "pending_gold": pending_gold,
		"next_site": _next_site, "next_worker": _next_worker, "next_holding": _next_holding, "day": _day, "upkeep_acc": _upkeep_acc,
		"log": log_lines.duplicate()}


func deserialize(d: Dictionary) -> void:
	sites = {}
	for k: String in d.get("sites", {}):
		var s: Dictionary = (d["sites"][k] as Dictionary).duplicate(true)
		s["id"] = int(s["id"])
		s["holding"] = int(s["holding"])
		s["upgrade_of"] = int(s.get("upgrade_of", 0))
		for item: String in s.get("need", {}):
			s["need"][item] = int(s["need"][item])
		for item: String in s.get("have", {}):
			s["have"][item] = int(s["have"][item])
		sites[int(k)] = s
	workers = (d.get("workers", {}) as Dictionary).duplicate(true)
	for wid: String in workers:
		workers[wid]["site"] = int(workers[wid]["site"])
	holdings = {}
	for k: String in d.get("holdings", {}):
		var h: Dictionary = (d["holdings"][k] as Dictionary).duplicate(true)
		h["id"] = int(h["id"])
		h["camp"] = int(h["camp"])
		for item: String in h.get("store", {}):
			h["store"][item] = int(h["store"][item])
		holdings[int(k)] = h
	known = (d.get("known", {}) as Dictionary).duplicate()
	trails = (d.get("trails", {}) as Dictionary).duplicate(true)
	for k: String in trails:
		trails[k]["a"] = int(trails[k]["a"])
		trails[k]["b"] = int(trails[k]["b"])
	gathered = (d.get("gathered", {}) as Dictionary).duplicate(true)
	for k: String in gathered:
		gathered[k]["hp"] = int(gathered[k]["hp"])
		gathered[k]["day"] = int(gathered[k]["day"])
		gathered[k]["t"] = int(gathered[k].get("t", gathered[k]["day"]))
	external = (d.get("external", {}) as Dictionary).duplicate()
	pending_gold = int(d.get("pending_gold", 0))
	_next_site = int(d.get("next_site", 1))
	_next_worker = int(d.get("next_worker", 1))
	_next_holding = int(d.get("next_holding", 1))
	_day = int(d.get("day", 0))
	_upkeep_acc = float(d.get("upkeep_acc", 0.0))
	log_lines = (d.get("log", []) as Array).duplicate()
	_trail_dirty = true
