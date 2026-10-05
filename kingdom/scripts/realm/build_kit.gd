extends "res://scripts/realm/realm_module.gd"
## Palworld-style free building with a snapping modular kit (docs/design/RETINUE_SETTLEMENT_ASCENSION.md 4.3, L31).
## Pure data: grids (one per player settlement, at most 3), pieces on a 2 m cell / 3 m storey grid, support
## (Valheim-lite integrity, no physics), plans that the construction crews raise (construction.place_kit_plan),
## removal with refunds, finger roads and a packed 16-byte-per-piece save. Rendering: scripts/build/build_renderer.gd,
## UI: scripts/build/build_mode.gd. Skill: .claude/skills/ashes-build-kit.
##
## Grid-local coordinates (metres, relative to the grid origin on the ground):
##   cell (i, k)  -> centre (2i, *, 2k), spans +-1 m
##   edge ex(i,k) -> along X at (2i, *, 2k+1): between cells (i,k) and (i,k+1)        (rot 0 / 2)
##   edge ez(i,k) -> along Z at (2i+1, *, 2k): between cells (i,k) and (i+1,k)        (rot 1 / 3)
##   storey L     -> floor height 0.5 + 3 L (foundation top = 0.5)

const CATALOG_PATH := "res://data/build_kit/pieces.json"
const CELL := 2.0
const STOREY := 3.0
const FOUNDATION_TOP := 0.5
const MAX_LEVEL := 3                    # 2 storeys + an attic roof
const MAX_GRIDS := 3                    # docs/regions/OWNER_DECISIONS.md: max 3 settlements you found
const GRID_RADIUS := 64.0
const PIECE_CAP := {"low": 1400, "medium": 1800, "high": 2200}
const REFUND_REMOVE := 0.5
const REFUND_COLLAPSE := 0.25
const LOSS_V := {"wood": 0.1, "stone": 0.05, "": 0.1}
const LOSS_H := {"wood": 1.0 / 3.0, "stone": 0.2, "": 1.0 / 3.0}
const MIN_INTEGRITY := 0.001
## Foundations: ground under the cell may sit this far below / above the grid base.
const SINK_MAX := 1.2
const BURY_MAX := 0.45
const FREE_SNAP := 0.5
const FREE_ROT_DEG := 15
const SLOT_ID := {"c": 0, "ex": 1, "ez": 2, "free": 3}
const SLOT_NAME := ["c", "ex", "ez", "free"]

static var _cat: Dictionary = {}

var grids: Dictionary = {}              # gid -> grid
var _next_grid := 1
var cap := 2200
## World ground height (x, z) -> y. The game sets WorldGen.height; tests use flat ground.
var height_fn: Callable = func(_x: float, _z: float) -> float: return 0.0
## Inventory override for tests ({item: n}); otherwise construction's bag / Life inventory.
var bag: Variant = null
var log_lines: Array = []
## Bumped on every change so the renderer knows when to rebuild (runtime only).
var rev := 0
## Runtime only: slot index per grid, rebuilt on load. gid -> {key: pid}
var _index: Dictionary = {}
var _integ: Dictionary = {}             # gid -> {pid: integrity}


# ------------------------------------------------------------------ catalogue

static func catalog() -> Dictionary:
	if _cat.is_empty():
		var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
		var d: Dictionary = JSON.parse_string(f.get_as_text()) if f != null else {}
		var by_id := {}
		var order: Array = []
		for p: Dictionary in d.get("pieces", []):
			p["index"] = order.size()
			by_id[String(p["id"])] = p
			order.append(String(p["id"]))
		d["by_id"] = by_id
		d["order"] = order
		_cat = d
	return _cat


static func def(kind: String) -> Dictionary:
	return catalog()["by_id"].get(kind, {})


static func kinds_in(cat_name: String) -> Array:
	var out: Array = []
	for k: String in catalog()["order"]:
		if String(def(k)["cat"]) == cat_name:
			out.append(k)
	return out


static func mesh_path(kind: String, lod := 0) -> String:
	return "res://assets/incoming/build_kit/%s_lod%d.glb" % [kind, lod]


static func level_y(level: int) -> float:
	return FOUNDATION_TOP + STOREY * level


# ------------------------------------------------------------------ inventory (shared with construction)

func _cons() -> RefCounted:
	return hub.mod("construction") if hub != null else null


func have(item: String) -> int:
	if bag is Dictionary:
		return int((bag as Dictionary).get(item, 0))
	var c := _cons()
	return int(c.call("_have", item)) if c != null else Life.count(item)


func _take(item: String, n: int) -> bool:
	if n <= 0:
		return true
	if bag is Dictionary:
		var d := bag as Dictionary
		if int(d.get(item, 0)) < n:
			return false
		d[item] = int(d[item]) - n
		return true
	var c := _cons()
	return bool(c.call("_take", item, n)) if c != null else Life.take(item, n)


func _give(item: String, n: int) -> void:
	if n <= 0:
		return
	if bag is Dictionary:
		(bag as Dictionary)[item] = int((bag as Dictionary).get(item, 0)) + n
		return
	var c := _cons()
	if c != null:
		c.call("_give", item, n)
	else:
		Life.give(item, n)


func missing_for(cost: Dictionary) -> Dictionary:
	var out := {}
	for item: String in cost:
		var short := int(cost[item]) - have(item)
		if short > 0:
			out[item] = short
	return out


func knows(fact: String) -> bool:
	if fact == "":
		return true
	var c := _cons()
	return c == null or bool(c.call("knows", fact))


# ------------------------------------------------------------------ grids (settlements)

func grid_at(world: Vector3) -> int:
	for gid: int in grids:
		var o := _origin(gid)
		if Vector2(world.x - o.x, world.z - o.z).length() <= GRID_RADIUS:
			return gid
	return 0


## The grid of the settlement here, founding a new one if there is none and fewer than MAX_GRIDS exist.
func ensure_grid(world: Vector3, name := "") -> Dictionary:
	var gid := grid_at(world)
	if gid > 0:
		return {"ok": true, "gid": gid, "reason": ""}
	if grids.size() >= MAX_GRIDS:
		return {"ok": false, "gid": 0, "reason": "You can found at most %d settlements." % MAX_GRIDS}
	gid = _next_grid
	_next_grid += 1
	var ox := snappedf(world.x, CELL)
	var oz := snappedf(world.z, CELL)
	var oy := float(height_fn.call(ox, oz))
	grids[gid] = {"id": gid, "name": name if name != "" else "Settlement %d" % gid, "origin": [ox, oy, oz],
		"pieces": {}, "next": 1, "roads": [], "plans": {}}
	_index[gid] = {}
	_integ[gid] = {}
	return {"ok": true, "gid": gid, "reason": ""}


func _origin(gid: int) -> Vector3:
	var o: Array = grids[gid]["origin"]
	return Vector3(float(o[0]), float(o[1]), float(o[2]))


func to_local(gid: int, world: Vector3) -> Vector3:
	return world - _origin(gid)


func to_world(gid: int, local: Vector3) -> Vector3:
	return local + _origin(gid)


func piece_count(gid := 0) -> int:
	if gid > 0:
		return (grids[gid]["pieces"] as Dictionary).size()
	var n := 0
	for g: int in grids:
		n += (grids[g]["pieces"] as Dictionary).size()
	return n


# ------------------------------------------------------------------ snapping

static func _fp(kind: String, rot: int) -> Vector2i:
	var fp: Array = def(kind).get("fp", [1, 1])
	var w := int(fp[0])
	var d := int(fp[1])
	return Vector2i(d, w) if (rot % 2) == 1 else Vector2i(w, d)


## Snaps a grid-local point to the piece's slot. Returns {slot, i, k, L, rot, p (local Vector3), yaw (radians)}.
func snap_local(gid: int, kind: String, local: Vector3, rot: int, level: int) -> Dictionary:
	var d := def(kind)
	var snap := String(d.get("snap", "free"))
	var lv := clampi(level, 0, MAX_LEVEL)
	if bool(d.get("ground_only", false)):
		lv = 0
	lv = maxi(lv, int(d.get("min_level", 0)))
	var out := {"kind": kind, "L": lv}
	if snap == "cell":
		var r := posmod(rot, 4)
		var fp := _fp(kind, r)
		var i := roundi((local.x - (fp.x - 1)) / CELL)
		var k := roundi((local.z - (fp.y - 1)) / CELL)
		out.merge({"slot": "c", "i": i, "k": k, "rot": r})
		out["p"] = Vector3(i * CELL + (fp.x - 1), 0.0, k * CELL + (fp.y - 1))
	elif snap == "edge":
		var r2 := posmod(rot, 4)
		var n := int((d.get("fp", [1, 1]) as Array)[0])
		if r2 % 2 == 0:
			var i2 := roundi((local.x - (n - 1)) / CELL)
			var k2 := roundi((local.z - 1.0) / CELL)
			out.merge({"slot": "ex", "i": i2, "k": k2, "rot": r2})
			out["p"] = Vector3(i2 * CELL + (n - 1), 0.0, k2 * CELL + 1.0)
		else:
			var i3 := roundi((local.x - 1.0) / CELL)
			var k3 := roundi((local.z - (n - 1)) / CELL)
			out.merge({"slot": "ez", "i": i3, "k": k3, "rot": r2})
			out["p"] = Vector3(i3 * CELL + 1.0, 0.0, k3 * CELL + (n - 1))
	else:
		var deg := posmod(rot * FREE_ROT_DEG, 360) if absi(rot) < 24 else posmod(rot, 360)
		var px := snappedf(local.x, FREE_SNAP)
		var pz := snappedf(local.z, FREE_SNAP)
		out.merge({"slot": "free", "i": floori((px + 1.0) / CELL), "k": floori((pz + 1.0) / CELL), "rot": deg})
		out["p"] = Vector3(px, 0.0, pz)
	out["p"] = Vector3(out["p"].x, _y_for(gid, out), out["p"].z)
	out["yaw"] = deg_to_rad(float(out["rot"]) * (90.0 if out["slot"] != "free" else 1.0))
	return out


func snap_world(gid: int, kind: String, world: Vector3, rot: int, level: int) -> Dictionary:
	var s := snap_local(gid, kind, to_local(gid, world), rot, level)
	s["world"] = to_world(gid, s["p"])
	return s


func _ground_local(gid: int, x: float, z: float) -> float:
	var o := _origin(gid)
	return float(height_fn.call(x + o.x, z + o.z)) - o.y


func _y_for(gid: int, s: Dictionary) -> float:
	var d := def(String(s["kind"]))
	var layer := String(d.get("layer", "prop"))
	var lv := int(s["L"])
	var p: Vector3 = s["p"]
	if layer == "foundation" or layer == "ground" or bool(d.get("ground_only", false)):
		if layer == "foundation":
			return 0.0
		return _ground_local(gid, p.x, p.z)
	if lv > 0:
		return level_y(lv)
	# level 0: on a foundation if there is one under it, else on the ground
	if _find(gid, "c", int(s["i"]), int(s["k"]), 0, "foundation") > 0 or s["slot"] in ["ex", "ez"]:
		return FOUNDATION_TOP
	return _ground_local(gid, p.x, p.z) if s["slot"] == "free" else FOUNDATION_TOP


# ------------------------------------------------------------------ occupancy index

static func _key(slot: String, i: int, k: int, lv: int, layer: String) -> String:
	return "%s:%d:%d:%d:%s" % [slot, i, k, lv, layer]


## Slot keys a piece occupies (cells for cell pieces, edges for edge pieces; none for free props).
static func keys_of(s: Dictionary) -> Array:
	var kind := String(s["kind"])
	var d := def(kind)
	var layer := String(d.get("layer", "prop"))
	var out: Array = []
	var slot := String(s["slot"])
	var i := int(s["i"])
	var k := int(s["k"])
	var lv := int(s["L"])
	if slot == "c":
		var fp := _fp(kind, int(s["rot"]))
		for a in fp.x:
			for b in fp.y:
				out.append(_key("c", i + a, k + b, lv, layer))
	elif slot == "ex" or slot == "ez":
		var n := int((d.get("fp", [1, 1]) as Array)[0])
		for a in n:
			out.append(_key(slot, i + (a if slot == "ex" else 0), k + (a if slot == "ez" else 0), lv, layer))
	return out


func _find(gid: int, slot: String, i: int, k: int, lv: int, layer: String) -> int:
	return int((_index.get(gid, {}) as Dictionary).get(_key(slot, i, k, lv, layer), 0))


func _reindex(gid: int) -> void:
	var idx := {}
	for pid: int in grids[gid]["pieces"]:
		for key: String in keys_of(grids[gid]["pieces"][pid]):
			idx[key] = pid
	_index[gid] = idx
	_recompute_integrity(gid)


# ------------------------------------------------------------------ support (Valheim-lite)

## [[pid, horizontal], ...] of the pieces that could hold this one up. Empty + grounded() == true for ground pieces.
func _supporters(gid: int, s: Dictionary) -> Array:
	var d := def(String(s["kind"]))
	var layer := String(d.get("layer", "prop"))
	var slot := String(s["slot"])
	var i := int(s["i"])
	var k := int(s["k"])
	var lv := int(s["L"])
	var out: Array = []
	var add := func(pid: int, horizontal: bool) -> void:
		if pid > 0 and pid != int(s.get("id", -1)):
			out.append([pid, horizontal])
	if slot == "ex" or slot == "ez":
		var cells: Array = [Vector2i(i, k), Vector2i(i, k + 1)] if slot == "ex" else [Vector2i(i, k), Vector2i(i + 1, k)]
		match layer:
			"wall", "fence":
				if lv == 0:
					for c: Vector2i in cells:
						add.call(_find(gid, "c", c.x, c.y, 0, "foundation"), false)
				else:
					add.call(_find(gid, slot, i, k, lv - 1, "wall"), false)
					for c: Vector2i in cells:
						add.call(_find(gid, "c", c.x, c.y, lv, "floor"), false)
			"gable":
				add.call(_find(gid, slot, i, k, lv - 1, "wall"), false)
				for c: Vector2i in cells:
					add.call(_find(gid, "c", c.x, c.y, lv, "roof"), false)
			"ridge":
				for c: Vector2i in cells:
					add.call(_find(gid, "c", c.x, c.y, lv, "roof"), false)
			"door":
				add.call(_find(gid, slot, i, k, lv, "wall"), false)
	elif slot == "c":
		var fp := _fp(String(s["kind"]), int(s["rot"]))
		for a in fp.x:
			for b in fp.y:
				var ci := i + a
				var ck := k + b
				match layer:
					"floor", "roof":
						for e: Array in [["ex", ci, ck], ["ex", ci, ck - 1], ["ez", ci, ck], ["ez", ci - 1, ck]]:
							add.call(_find(gid, e[0], e[1], e[2], lv - 1, "wall"), false)
							if layer == "roof":
								add.call(_find(gid, e[0], e[1], e[2], lv, "gable"), false)
						add.call(_find(gid, "c", ci, ck, lv - 1, "pillar"), false)
						for n: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
							add.call(_find(gid, "c", ci + n.x, ck + n.y, lv, layer), true)
					"pillar":
						add.call(_find(gid, "c", ci, ck, lv, "floor"), false)
						add.call(_find(gid, "c", ci, ck, lv - 1, "pillar"), false)
					"stairs":
						add.call(_find(gid, "c", ci, ck, lv, "floor"), false)
						add.call(_find(gid, "c", ci, ck, 0, "foundation"), false)
	else:
		add.call(_find(gid, "c", i, k, lv, "floor"), false)
		add.call(_find(gid, "c", i, k, 0, "foundation"), false)
	return out


func _grounded(s: Dictionary) -> bool:
	var d := def(String(s["kind"]))
	var layer := String(d.get("layer", "prop"))
	if layer in ["foundation", "ground"] or bool(d.get("ground_only", false)):
		return true
	var lv := int(s["L"])
	if lv == 0 and layer in ["pillar", "stairs", "prop"]:
		return true
	return false


## Integrity (0..1) the piece would have given the current integrity of its supporters.
func integrity_of(gid: int, s: Dictionary) -> float:
	if _grounded(s):
		return 1.0
	var mat := String(def(String(s["kind"])).get("mat", ""))
	var best := 0.0
	var ig: Dictionary = _integ.get(gid, {})
	for sp: Array in _supporters(gid, s):
		var v := float(ig.get(int(sp[0]), 0.0)) - (float(LOSS_H[mat]) if bool(sp[1]) else float(LOSS_V[mat]))
		best = maxf(best, v)
	return best


func _recompute_integrity(gid: int) -> void:
	var ig := {}
	_integ[gid] = ig
	var pieces: Dictionary = grids[gid]["pieces"]
	for pid: int in pieces:
		ig[pid] = 1.0 if _grounded(pieces[pid]) else 0.0
	var changed := true
	var guard := 0
	while changed and guard < 64:
		changed = false
		guard += 1
		for pid: int in pieces:
			if _grounded(pieces[pid]):
				continue
			var v := integrity_of(gid, pieces[pid])
			if v > float(ig[pid]) + 0.0001:
				ig[pid] = v
				changed = true


func integrity(gid: int, pid: int) -> float:
	return float((_integ.get(gid, {}) as Dictionary).get(pid, 0.0))


# ------------------------------------------------------------------ checks and placement

## Can this snapped piece go here? {ok, reason, plan (materials missing: may still be laid as a plan), integrity, missing}.
func check(gid: int, s: Dictionary, as_plan := false) -> Dictionary:
	var kind := String(s["kind"])
	var d := def(kind)
	var res := {"ok": false, "reason": "", "plan": false, "integrity": 0.0, "missing": {}}
	if d.is_empty():
		res["reason"] = "Unknown piece."
		return res
	if not grids.has(gid):
		res["reason"] = "Found a settlement first."
		return res
	if piece_count(gid) >= cap:
		res["reason"] = "This settlement has reached its %d-piece limit." % cap
		return res
	if not knows(String(d.get("know", ""))):
		res["reason"] = "Learn %s first." % String(d["know"]).trim_prefix("build:")
		return res
	var p: Vector3 = s["p"]
	if Vector2(p.x, p.z).length() > GRID_RADIUS:
		res["reason"] = "Outside the settlement."
		return res
	for key: String in keys_of(s):
		if (_index[gid] as Dictionary).has(key):
			res["reason"] = "Something is already there."
			return res
	if String(s["slot"]) == "free":
		for pid: int in grids[gid]["pieces"]:
			var o: Dictionary = grids[gid]["pieces"][pid]
			if String(o["slot"]) == "free" and int(o["L"]) == int(s["L"]) and _pv(o).distance_to(p) < 0.45:
				res["reason"] = "Something is already there."
				return res
	var layer := String(d.get("layer", ""))
	if layer == "foundation":
		var fp := _fp(kind, int(s["rot"]))
		for a in fp.x:
			for b in fp.y:
				var g := _ground_local(gid, (int(s["i"]) + a) * CELL, (int(s["k"]) + b) * CELL)
				if g < -SINK_MAX:
					res["reason"] = "Too steep: the ground falls away."
					return res
				if g > BURY_MAX:
					res["reason"] = "Too steep: the slope buries it."
					return res
	if bool(d.get("needs_doorway", false)):
		var w := _find(gid, String(s["slot"]), int(s["i"]), int(s["k"]), int(s["L"]), "wall")
		if w == 0 or not bool(def(String(grids[gid]["pieces"][w]["kind"])).get("doorway", false)):
			res["reason"] = "Doors go in a doorway wall."
			return res
	var ig := integrity_of(gid, s)
	res["integrity"] = ig
	if ig < MIN_INTEGRITY:
		res["reason"] = "Nothing holds it up."
		return res
	var miss := missing_for(d.get("cost", {}))
	res["missing"] = miss
	if not miss.is_empty():
		res["plan"] = true
		if not as_plan:
			res["reason"] = "Missing materials: lay it as a plan for workers."
			res["ok"] = false
			return res
	res["ok"] = true
	return res


static func _pv(s: Dictionary) -> Vector3:
	var a: Array = s["p"]
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## Places a snapped piece. `plan`: lay it without materials; workers raise it later (hand_to_workers).
func place(gid: int, s: Dictionary, plan := false) -> Dictionary:
	var chk := check(gid, s, plan)
	if not bool(chk["ok"]):
		return {"ok": false, "reason": chk["reason"], "id": 0}
	var d := def(String(s["kind"]))
	var as_plan := plan or bool(chk["plan"])
	if not as_plan:
		for item: String in d.get("cost", {}):
			_take(item, int(d["cost"][item]))
	var g: Dictionary = grids[gid]
	var pid := int(g["next"])
	g["next"] = pid + 1
	var p: Vector3 = s["p"]
	var rec := {"id": pid, "kind": String(s["kind"]), "slot": String(s["slot"]), "i": int(s["i"]), "k": int(s["k"]), "L": int(s["L"]),
		"rot": int(s["rot"]), "p": [p.x, p.y, p.z], "state": "plan" if as_plan else "done", "hp": 1.0, "site": 0}
	g["pieces"][pid] = rec
	for key: String in keys_of(rec):
		_index[gid][key] = pid
	_integ[gid][pid] = integrity_of(gid, rec)
	rev += 1
	return {"ok": true, "reason": "", "id": pid, "plan": as_plan}


## Removes a piece (50% refund of a finished one) and drops anything that loses its support (25% refund each).
func remove(gid: int, pid: int, share := REFUND_REMOVE) -> Dictionary:
	var g: Dictionary = grids.get(gid, {})
	if g.is_empty() or not (g["pieces"] as Dictionary).has(pid):
		return {"ok": false, "refund": {}, "collapsed": []}
	var refund := {}
	_drop(gid, pid, share, refund)
	_recompute_integrity(gid)
	var collapsed: Array = []
	var again := true
	while again:
		again = false
		for other: int in (g["pieces"] as Dictionary).keys():
			if integrity(gid, other) < MIN_INTEGRITY:
				collapsed.append(other)
				_drop(gid, other, REFUND_COLLAPSE, refund)
				again = true
		if again:
			_recompute_integrity(gid)
	rev += 1
	for item: String in refund:
		_give(item, int(refund[item]))
	return {"ok": true, "refund": refund, "collapsed": collapsed}


func _drop(gid: int, pid: int, share: float, refund: Dictionary) -> void:
	var g: Dictionary = grids[gid]
	var rec: Dictionary = g["pieces"][pid]
	if String(rec["state"]) == "done":
		var cost: Dictionary = def(String(rec["kind"])).get("cost", {})
		for item: String in cost:
			var n := int(floor(int(cost[item]) * share))
			if n > 0:
				refund[item] = int(refund.get(item, 0)) + n
	for key: String in keys_of(rec):
		if int(_index[gid].get(key, 0)) == pid:
			_index[gid].erase(key)
	g["pieces"].erase(pid)
	_integ[gid].erase(pid)


## Lays a built-in blueprint (data/build_kit/pieces.json "blueprints") as plans at cell (ci, ck), turned by quarter turns.
## Returns {ok, placed, failed, reasons}.
func place_blueprint(gid: int, bp_id: String, ci: int, ck: int, quarter := 0) -> Dictionary:
	var bp: Dictionary = catalog().get("blueprints", {}).get(bp_id, {})
	if bp.is_empty():
		return {"ok": false, "placed": 0, "failed": 0, "reasons": ["No such blueprint."]}
	var placed := 0
	var failed := 0
	var reasons: Array = []
	# lower levels and structure first, so supports exist when the next row is checked
	var rows: Array = (bp["pieces"] as Array).duplicate()
	for row: Array in rows:
		var kind := String(row[0])
		var slot := String(row[5]) if row.size() > 5 else "c"
		var local := _bp_local(kind, slot, int(row[1]), int(row[2]), int(row[4]), quarter) + Vector3(ci * CELL, 0, ck * CELL)
		var rot := int(row[4]) + quarter
		if slot == "free":
			rot = posmod((int(row[4]) + quarter) * 6, 24)       # free props turn in 15 degree steps: a quarter is 6
		var s := snap_local(gid, kind, local, rot, int(row[3]))
		var r := place(gid, s, true)
		if bool(r["ok"]):
			placed += 1
		else:
			failed += 1
			reasons.append("%s: %s" % [kind, r["reason"]])
	return {"ok": failed == 0, "placed": placed, "failed": failed, "reasons": reasons}


## Grid-local centre of a blueprint row (before turning), turned by `quarter` quarter turns about the origin cell.
func _bp_local(kind: String, slot: String, i: int, k: int, rot: int, quarter: int) -> Vector3:
	var p := Vector3.ZERO
	var n := int((def(kind).get("fp", [1, 1]) as Array)[0])
	match slot:
		"ex":
			p = Vector3(i * CELL + (n - 1), 0, k * CELL + 1.0)
		"ez":
			p = Vector3(i * CELL + 1.0, 0, k * CELL + (n - 1))
		"free":
			p = Vector3(i * CELL, 0, k * CELL)
		_:
			var fp := _fp(kind, rot)
			p = Vector3(i * CELL + (fp.x - 1), 0, k * CELL + (fp.y - 1))
	return Basis(Vector3.UP, quarter * PI * 0.5) * p


# ------------------------------------------------------------------ plans raised by the construction crews

## Bundles every loose plan piece of a grid into ONE construction site (kind "kit_plan") with the summed bill and labour,
## so the existing crews, hauling, stages and stalls raise it. Returns {ok, site, pieces, reason}.
func hand_to_workers(gid: int, label := "") -> Dictionary:
	var c := _cons()
	if c == null:
		return {"ok": false, "site": 0, "pieces": 0, "reason": "No construction crews here."}
	var cost := {}
	var hours := 0.0
	var ids: Array = []
	var centre := Vector3.ZERO
	for pid: int in grids[gid]["pieces"]:
		var rec: Dictionary = grids[gid]["pieces"][pid]
		if String(rec["state"]) == "plan" and int(rec["site"]) == 0:
			var d := def(String(rec["kind"]))
			for item: String in d.get("cost", {}):
				cost[item] = int(cost.get(item, 0)) + int(d["cost"][item])
			hours += float(d.get("hours", 1.0))
			ids.append(pid)
			centre += _pv(rec)
	if ids.is_empty():
		return {"ok": false, "site": 0, "pieces": 0, "reason": "Lay some plans first."}
	centre = to_world(gid, centre / ids.size())
	var r: Dictionary = c.call("place_kit_plan", Vector2(centre.x, centre.z), 0.0, cost, hours,
		label if label != "" else "%s (%d pieces)" % [String(grids[gid]["name"]), ids.size()])
	if not bool(r.get("ok", false)):
		return {"ok": false, "site": 0, "pieces": 0, "reason": String(r.get("reason", ""))}
	var sid := int(r["id"])
	for pid: int in ids:
		grids[gid]["pieces"][pid]["site"] = sid
	grids[gid]["plans"][str(sid)] = ids
	rev += 1
	return {"ok": true, "site": sid, "pieces": ids.size(), "reason": ""}


## 0..1 progress of the crew site raising this plan piece (1 for finished pieces).
func plan_progress(gid: int, pid: int) -> float:
	var rec: Dictionary = grids[gid]["pieces"].get(pid, {})
	if rec.is_empty() or String(rec["state"]) == "done":
		return 1.0
	var sid := int(rec["site"])
	var c := _cons()
	if sid == 0 or c == null:
		return 0.0
	var site: Dictionary = c.get("sites").get(sid, {})
	if site.is_empty():
		return 0.0
	return clampf(float(site["progress"]) / maxf(float(site["total"]), 0.001), 0.0, 1.0)


## Pieces of a crew site are revealed bottom-up as it progresses: is this one standing yet?
func plan_piece_built(gid: int, pid: int) -> bool:
	var rec: Dictionary = grids[gid]["pieces"].get(pid, {})
	if rec.is_empty():
		return false
	if String(rec["state"]) == "done":
		return true
	var ids: Array = grids[gid]["plans"].get(str(int(rec["site"])), [])
	if ids.is_empty():
		return false
	var order := ids.duplicate()
	var pieces: Dictionary = grids[gid]["pieces"]
	order.sort_custom(func(a: int, b: int) -> bool:
		return (_pv(pieces[a]).y if pieces.has(a) else 0.0) < (_pv(pieces[b]).y if pieces.has(b) else 0.0))
	return order.find(pid) < int(floor(plan_progress(gid, pid) * order.size()))


## Finished crew sites turn their plan pieces into real pieces.
func _settle_plans() -> Array:
	var out: Array = []
	var c := _cons()
	if c == null:
		return out
	var sites: Dictionary = c.get("sites")
	for gid: int in grids:
		var plans: Dictionary = grids[gid]["plans"]
		for sk: String in plans.keys():
			var site: Dictionary = sites.get(int(sk), {})
			var gone := site.is_empty()
			if not gone and String(site["state"]) != "done":
				continue
			var n := 0
			for pid: int in plans[sk]:
				var rec: Dictionary = grids[gid]["pieces"].get(int(pid), {})
				if rec.is_empty():
					continue
				if gone:
					rec["site"] = 0          # the site was cancelled: the pieces go back to loose plans
				else:
					rec["state"] = "done"
					n += 1
			plans.erase(sk)
			rev += 1
			if n > 0:
				out.append("%s: the crew finished %d pieces." % [String(grids[gid]["name"]), n])
	return out


func tick_hour(_hour: int, _ctx: Dictionary) -> Array:
	return _settle_plans()


func catch_up(_days: int, _ctx: Dictionary) -> Array:
	return _settle_plans()


# ------------------------------------------------------------------ roads (finger strokes, scripts/build/road_tool.gd)

static func road_def(tier: String) -> Dictionary:
	return catalog().get("roads", {}).get(tier, {})


static func polyline_length(pts: Array) -> float:
	var l := 0.0
	for i in range(1, pts.size()):
		l += (pts[i] as Vector3).distance_to(pts[i - 1])
	return l


func road_cost(tier: String, pts: Array) -> Dictionary:
	var rd := road_def(tier)
	var tens := polyline_length(pts) / 10.0
	var cost := {}
	for item: String in rd.get("cost_per_10m", {}):
		cost[item] = int(ceil(float(rd["cost_per_10m"][item]) * tens))
	return {"cost": cost, "hours": float(rd.get("hours_per_10m", 1.0)) * tens}


## Adds a road from a stroke already smoothed by RoadTool (world points). Takes the materials. {ok, reason, index}.
func add_road(gid: int, tier: String, world_pts: Array) -> Dictionary:
	if road_def(tier).is_empty() or world_pts.size() < 2:
		return {"ok": false, "reason": "Draw a longer road.", "index": -1}
	var rc := road_cost(tier, world_pts)
	var miss := missing_for(rc["cost"])
	if not miss.is_empty():
		return {"ok": false, "reason": "Missing materials for this road.", "index": -1}
	for item: String in rc["cost"]:
		_take(item, int(rc["cost"][item]))
	var local: Array = []
	for p: Vector3 in world_pts:
		var l := to_local(gid, p)
		local.append([snappedf(l.x, 0.01), snappedf(l.y, 0.01), snappedf(l.z, 0.01)])
	(grids[gid]["roads"] as Array).append({"tier": tier, "pts": local})
	rev += 1
	return {"ok": true, "reason": "", "index": (grids[gid]["roads"] as Array).size() - 1}


# ------------------------------------------------------------------ save (16 bytes per piece)

## u16 kind index, i16 x*4, i16 z*4, i16 y*10, u8 rot, u8 state, u8 hp*255, u8 slot|level<<2, u32 site.
func pack_pieces(gid: int) -> PackedByteArray:
	var pieces: Dictionary = grids[gid]["pieces"]
	var b := PackedByteArray()
	b.resize(pieces.size() * 16)
	var o := 0
	for pid: int in pieces:
		var r: Dictionary = pieces[pid]
		var p := _pv(r)
		b.encode_u16(o, int(def(String(r["kind"]))["index"]))
		b.encode_s16(o + 2, roundi(p.x * 4.0))
		b.encode_s16(o + 4, roundi(p.z * 4.0))
		b.encode_s16(o + 6, roundi(p.y * 10.0))
		var slot := String(r["slot"])
		b.encode_u8(o + 8, roundi(float(r["rot"]) / 360.0 * 256.0) % 256 if slot == "free" else int(r["rot"]))
		b.encode_u8(o + 9, 1 if String(r["state"]) == "plan" else 0)
		b.encode_u8(o + 10, clampi(roundi(float(r["hp"]) * 255.0), 0, 255))
		b.encode_u8(o + 11, int(SLOT_ID[slot]) | (int(r["L"]) << 2))
		b.encode_u32(o + 12, int(r["site"]))
		o += 16
	return b


func unpack_pieces(gid: int, b: PackedByteArray) -> void:
	var g: Dictionary = grids[gid]
	g["pieces"] = {}
	var order: Array = catalog()["order"]
	var pid := 1
	for o in range(0, b.size(), 16):
		var kind := String(order[b.decode_u16(o)])
		var x := b.decode_s16(o + 2) / 4.0
		var z := b.decode_s16(o + 4) / 4.0
		var y := b.decode_s16(o + 6) / 10.0
		var sl := b.decode_u8(o + 11)
		var slot := String(SLOT_NAME[sl & 3])
		var lv := sl >> 2
		var rot := b.decode_u8(o + 8)
		if slot == "free":
			rot = roundi(rot / 256.0 * 360.0)
		var s := snap_local(gid, kind, Vector3(x, y, z), rot if slot != "free" else rot, lv) if slot != "free" else {}
		var i := int(s.get("i", floori((x + 1.0) / CELL)))
		var k := int(s.get("k", floori((z + 1.0) / CELL)))
		var rec := {"id": pid, "kind": kind, "slot": slot, "i": i, "k": k, "L": lv, "rot": rot, "p": [x, y, z],
			"state": "plan" if b.decode_u8(o + 9) == 1 else "done", "hp": b.decode_u8(o + 10) / 255.0, "site": int(b.decode_u32(o + 12))}
		g["pieces"][pid] = rec
		pid += 1
	g["next"] = pid
	# plan groups are rebuilt from the pieces' site ids
	var plans := {}
	for p2: int in g["pieces"]:
		var sid := int(g["pieces"][p2]["site"])
		if sid > 0 and String(g["pieces"][p2]["state"]) == "plan":
			if not plans.has(str(sid)):
				plans[str(sid)] = []
			(plans[str(sid)] as Array).append(p2)
	g["plans"] = plans


func serialize() -> Dictionary:
	var gg := {}
	for gid: int in grids:
		var g: Dictionary = grids[gid]
		gg[str(gid)] = {"id": gid, "name": g["name"], "origin": g["origin"], "roads": (g["roads"] as Array).duplicate(true),
			"packed": Marshalls.raw_to_base64(pack_pieces(gid))}
	return {"grids": gg, "next_grid": _next_grid, "log": log_lines.duplicate()}


func deserialize(d: Dictionary) -> void:
	grids = {}
	_index = {}
	_integ = {}
	for key: String in d.get("grids", {}):
		var src: Dictionary = d["grids"][key]
		var gid := int(src["id"])
		grids[gid] = {"id": gid, "name": String(src["name"]), "origin": src["origin"], "pieces": {}, "next": 1,
			"roads": (src.get("roads", []) as Array).duplicate(true), "plans": {}}
		_index[gid] = {}
		_integ[gid] = {}
		unpack_pieces(gid, Marshalls.base64_to_raw(String(src.get("packed", ""))))
		_reindex(gid)
	_next_grid = int(d.get("next_grid", grids.size() + 1))
	log_lines = (d.get("log", []) as Array).duplicate()
	rev += 1
