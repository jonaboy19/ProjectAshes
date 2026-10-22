extends Node3D
## Gives recruits (scripts/realm/recruitment.gd) a body near the player, inside a budget. A child of PopulationLOD
## (it shares that node's embodiment rules): PopulationLOD never draws a row this manager owns, and the manager
## never builds more than Brain.budget(Quality.npc_full) bodies (at most 6), one per frame.
##
##   follow order    always wanted, fighters first; the 7th and later stay data only and trail the player
##   work / wait     a body only while the player is within LOCAL_RANGE of where they are; otherwise data only
##   home            walks home with a body (if it has one), then the row goes back to the village schedule
## Data only = the WorldSim row, kept in place by owning it (set_external_position_owner), moved with the player
## (follow) or to the post (work). Rows are released when the recruit leaves, is dismissed or is sent home.

const Brain := preload("res://scripts/actors/follower_brain.gd")
const Body := preload("res://scripts/actors/follower_body.gd")

const CHECK := 0.5

## row -> fid for every row this manager owns (PopulationLOD reads it through owns()).
static var owned_rows: Dictionary = {}

## Shared with every body: player node, pos, yaw, speed, inside, jump, owner.
var ctx := {"player": null, "pos": Vector2.ZERO, "yaw": 0.0, "speed": 0.0, "inside": false, "jump": 0.0, "owner": 0}
var _bodies: Dictionary = {}       # fid -> Body
var _queue: Array = []             # [fid, spawn Vector2] waiting to be built (one per frame)
var _acc := 0.0
var _last_pp := Vector3.INF
## Tests and tools can hand in a hub; null means the game's Life.realm.
var hub: RefCounted = null


static func owns(row: int) -> bool:
	return owned_rows.has(row)


func _ready() -> void:
	add_to_group("follower_manager")
	ctx["owner"] = get_instance_id()


func _exit_tree() -> void:
	for row: int in owned_rows.keys():
		_release(row)


func body_of(fid: String) -> Node3D:
	return _bodies.get(fid)


func body_count() -> int:
	return _bodies.size()


func _hub() -> RefCounted:
	if hub != null:
		return hub
	return Life.get("realm") if Life != null else null


func _recruitment() -> RefCounted:
	var h := _hub()
	return h.mod("recruitment") if h != null else null


func _will_of(fid: String) -> String:
	var h := _hub()
	var w: RefCounted = h.mod("will") if h != null else null
	return String(w.will_of(fid)) if w != null else ""


func _followers() -> RefCounted:
	var h := _hub()
	return h.mod("followers") if h != null else null


# --------------------------------------------------------------------------- per frame

func _physics_process(_delta: float) -> void:
	var pl: Node3D = ctx["player"] if ctx["player"] != null and is_instance_valid(ctx["player"]) else null
	if pl == null:
		pl = get_tree().get_first_node_in_group("player") as Node3D
		ctx["player"] = pl
	if pl == null:
		return
	var pp := pl.global_position
	ctx["jump"] = pp.distance_to(_last_pp) if _last_pp != Vector3.INF else 0.0
	_last_pp = pp
	ctx["pos"] = Vector2(pp.x, pp.z)
	ctx["yaw"] = pl.rotation.y
	var v: Variant = pl.get("velocity")
	ctx["speed"] = Vector2((v as Vector3).x, (v as Vector3).z).length() if v is Vector3 else 0.0
	ctx["inside"] = InteriorDoor.active != null
	# A door or a fast travel is also one big step: while inside nobody follows, so the exit does not teleport
	# a waiter that is still next to the door (needs_teleport also needs them to be far).


func _process(delta: float) -> void:
	if not _queue.is_empty():
		var q: Array = _queue.pop_front()
		_build(String(q[0]), q[1] as Vector2)
	_acc += delta
	if _acc < CHECK:
		return
	_acc = 0.0
	refresh()


# --------------------------------------------------------------------------- the check

## Re-decides who has a body. Public so tests and tools can run it without waiting.
func refresh() -> void:
	var rc := _recruitment()
	var fol := _followers()
	var pl: Node3D = ctx["player"]
	if rc == null or fol == null or pl == null:
		_drop_all()
		return
	var pp: Vector2 = ctx["pos"]
	var cands: Array = []
	var info := {}
	for fid: String in rc.active_ids():
		var f: Dictionary = fol.get_follower(fid)
		var row := int(f.get("person", -1))
		if f.is_empty() or row < 0 or row >= WorldSim.population() or String(f["status"]) != "present":
			continue
		var eo: Dictionary = rc.effective_order(fid)
		var ord := String(eo["order"])
		var duty := String((rc.contract_of(fid).get("t", {}) as Dictionary).get("d", "labor"))
		var anchor := _anchor(rc, fid, f, row, ord, String(eo["arg"]), pp)
		var body: Node3D = _bodies.get(fid)
		var d := 0.0
		if ord == "wait":
			var at: Vector2 = body.call("sim_position") if body != null else Vector2(WorldSim.pos[row])
			d = at.distance_to(pp)
		elif ord != "follow":
			d = anchor.distance_to(pp)
		if ord == "home" and body == null:
			continue
		cands.append({"fid": fid, "order": ord, "fighter": Brain.is_fighter(duty, String(f["occupation"])), "d": d})
		var wl := _will_of(fid)
		info[fid] = {"row": row, "will": wl, "order": ord, "arg": String(eo["arg"]), "anchor": anchor, "f": f, "duty": duty}
	var cap := Brain.budget(int(Quality.npc_full))
	var want: Array = Brain.select(cands, cap, _bodies)
	var want_set := {}
	for i in want.size():
		want_set[want[i]] = i
	# bodies that are no longer wanted (or whose recruit is gone) go back to data only
	for fid: String in _bodies.keys():
		var b: Node3D = _bodies[fid]
		if not want_set.has(fid) or not info.has(fid) or bool(b.get("finished")):
			_remove_body(fid)
	var slot_i := 0
	for fid: String in want:
		var inf: Dictionary = info[fid]
		var b2: Node3D = _bodies.get(fid)
		if b2 != null:
			b2.set("anchor", inf["anchor"])
			b2.set("will", inf["will"])
			b2.call("set_order", inf["order"], inf["arg"])
			if inf["order"] == "follow":
				b2.set("slot", slot_i)
		elif not _queued(fid):
			_queue.append([fid, _spawn_point(inf, slot_i)])
		if inf["order"] == "follow":
			slot_i += 1
	# data only: keep every managed row still, trailing the player or at its post; release the rest
	var keep := {}
	for fid: String in info:
		var inf2: Dictionary = info[fid]
		var row2: int = inf2["row"]
		if inf2["order"] == "home" and not _bodies.has(fid):
			continue
		keep[row2] = fid
		if _bodies.has(fid):
			_hold(row2, Vector2.INF)
			continue
		match String(inf2["order"]):
			"follow":
				# a recruit that refused / asked to stay behind (follower_will) holds position instead of trailing the player
				_hold(row2, Vector2.INF if String(inf2["will"]) in Brain.WILL_HOLD else pp)
			"work":
				_hold(row2, inf2["anchor"] if (inf2["anchor"] as Vector2).distance_to(pp) > Brain.LOCAL_RANGE * 1.5 else Vector2.INF)
			_:
				_hold(row2, Vector2.INF)
	for row3: int in owned_rows.keys():
		if not keep.has(row3):
			_release(row3)
	_queue = _queue.filter(func(q: Array) -> bool: return want_set.has(q[0]))


func _queued(fid: String) -> bool:
	for q: Array in _queue:
		if q[0] == fid:
			return true
	return false


func _drop_all() -> void:
	for fid: String in _bodies.keys():
		_remove_body(fid)
	_queue.clear()
	for row: int in owned_rows.keys():
		_release(row)


# --------------------------------------------------------------------------- rows and bodies

## Take (or keep) ownership of a row; `at` moves it when not INF.
func _hold(row: int, at: Vector2) -> void:
	if not owned_rows.has(row):
		var lod := get_parent()
		if lod != null and lod.has_method("evict_person"):
			lod.call("evict_person", row)
		owned_rows[row] = true
	WorldSim.set_external_position_owner(row, int(ctx["owner"]), true, at)


func _release(row: int) -> void:
	owned_rows.erase(row)
	WorldSim.set_external_position_owner(row, int(ctx["owner"]), false, Vector2.INF)


func _remove_body(fid: String) -> void:
	var b: Node3D = _bodies.get(fid)
	_bodies.erase(fid)
	if b == null:
		return
	var row := int(b.get("row"))
	if is_instance_valid(b):
		WorldSim.set_external_position_owner(row, int(ctx["owner"]), true, b.call("sim_position"))
		b.queue_free()


func _spawn_point(inf: Dictionary, slot_i: int) -> Vector2:
	var row: int = inf["row"]
	var pp: Vector2 = ctx["pos"]
	var at: Vector2 = WorldSim.pos[row]
	match String(inf["order"]):
		"follow":
			var yaw := float(ctx["yaw"])
			return Brain.follow_point(pp, yaw, false, slot_i) - Vector2(sin(yaw), cos(yaw)) * 1.2
		"work", "home":
			if at.distance_to(pp) > Brain.LOCAL_RANGE and inf["anchor"] != Vector2.INF:
				return inf["anchor"]
	return at


func _build(fid: String, at: Vector2) -> void:
	if _bodies.has(fid) or _bodies.size() >= Brain.budget(int(Quality.npc_full)):
		return
	var rc := _recruitment()
	var fol := _followers()
	if rc == null or fol == null:
		return
	var f: Dictionary = fol.get_follower(fid)
	if f.is_empty() or not f.has("person"):
		return
	var eo: Dictionary = rc.effective_order(fid)
	var duty := String((rc.contract_of(fid).get("t", {}) as Dictionary).get("d", "labor"))
	var b: Node3D = Body.new()
	b.call("setup", fid, int(f["person"]), ctx, f, duty)
	b.set("order", String(eo["order"]))
	b.set("order_arg", String(eo["arg"]))
	b.set("will", _will_of(fid))
	b.set("anchor", _anchor(rc, fid, f, int(f["person"]), String(eo["order"]), String(eo["arg"]), ctx["pos"]))
	add_child(b)
	b.call("place_at", at)
	b.set("slot", _slot_for(fid))
	_hold(int(f["person"]), Vector2.INF)
	WorldSim.set_external_position_owner(int(f["person"]), int(ctx["owner"]), true, b.call("sim_position"))
	_bodies[fid] = b


func _slot_for(fid: String) -> int:
	var i := 0
	for other: String in _bodies:
		if String(_bodies[other].get("order")) == "follow":
			i += 1
	return i


# --------------------------------------------------------------------------- places

## Where a recruit's post is: the work group's property (or its settlement), their home, or the player.
func _anchor(rc: RefCounted, _fid: String, f: Dictionary, row: int, ord: String, arg: String, pp: Vector2) -> Vector2:
	match ord:
		"follow":
			return pp
		"wait":
			return Vector2(WorldSim.pos[row])
		"home":
			return _settlement_spot(int(WorldSim.home[row]), row)
		"work":
			var g: Dictionary = rc.group(arg)
			var ref := String(g.get("ref", ""))
			var prop: Variant = Life.get("property")
			if prop != null and ref != "":
				var pi: Dictionary = prop.info(ref)
				if not pi.is_empty() and pi.has("pos"):
					return pi["pos"] as Vector2
			var loc := String(f.get("loc", ""))
			var sid := int(loc.substr(1)) if loc.begins_with("s") and loc.substr(1).is_valid_int() else int(WorldSim.home[row])
			return _settlement_spot(sid, row)
	return Vector2(WorldSim.pos[row])


func _settlement_spot(sid: int, row: int) -> Vector2:
	if sid < 0 or sid >= WorldGen.settlements.size():
		return Vector2(WorldSim.pos[row])
	var c: Vector2 = WorldGen.settlements[sid]["pos"]
	var a := float(absi(hash(row)) % 628) / 100.0
	return c + Vector2(cos(a), sin(a)) * 6.0


## Build the manager under `parent` (PopulationLOD does this in setup()).
static func attach(parent: Node) -> Node:
	var existing := parent.get_node_or_null("FollowerManager")
	if existing != null:
		return existing
	var m: Node = (load("res://scripts/actors/follower_manager.gd") as GDScript).new()
	m.name = "FollowerManager"
	parent.add_child(m)
	return m
