extends Node3D
## Gathering nodes along the Thornfield wilds trail (F9): forage (herbs, mushrooms), deadwood and ore outcrops, each
## at a fixed data offset (data/region1/world/thornfield_wilds.json "nodes", plus the glade's herbs). A node pays out
## through Life.give with the same items, yields and regrowth the forage and ore systems use (Gathering.FORAGE for
## herb / mushroom / firewood, OreVein.ORES for iron / copper / coal); a gathered node stays bare until its regrowth day,
## remembered as a WorldState delta "wilds/node/<id>" so it survives saves. Each live node has an Interactable.
## Built within BUILD metres of the player, freed beyond FREE (the hub calls refresh()).

const Wilds := preload("res://scripts/world/thornfield/wilds.gd")
const Props := preload("res://scripts/world/thornfield/wilds_props.gd")
const Gathering := preload("res://scripts/sim/gathering_items.gd")
const OreVein := preload("res://scripts/world/ore_vein.gd")
const WorldState := preload("res://scripts/world/world_state.gd")
const BUILD := 150.0
const FREE := 230.0
const ORE_REGROW_DAYS := 5
const SOURCES := ["herb", "mushroom", "firewood", "iron", "copper", "coal"]

## [{id, kind, pos: Vector2}] every node of the trail (data nodes + glade herbs).
var specs: Array = []
var _live: Dictionary = {}          # id -> Node3D


func _ready() -> void:
	name = "WildsGatherNodes"
	specs = plan()


## The plan from data (pure given the world: positions follow Thornfield).
static func plan() -> Array:
	var out: Array = []
	for n: Dictionary in Wilds.data()["nodes"]:
		out.append({"id": String(n["id"]), "kind": String(n["kind"]), "pos": Wilds.at(n["offset"])})
	for h: Dictionary in Wilds.data()["hidden"]:
		if h.has("herbs"):
			var i := 0
			for o: Array in h["herbs"]:
				out.append({"id": "%s_herb_%d" % [String(h["id"]), i], "kind": "herb", "pos": Wilds.at(o)})
				i += 1
	return out


## {item, min, max, regrow_days, verb} of a kind.
static func yield_of(kind: String) -> Dictionary:
	if Gathering.FORAGE.has(kind):
		var f: Dictionary = Gathering.FORAGE[kind]
		return {"item": String(f["item"]), "min": int(f["min"]), "max": int(f["max"]), "regrow_days": int(f["respawn_days"]), "verb": String(f["verb"])}
	var o: Dictionary = OreVein.ORES.get(kind, {})
	if o.is_empty():
		return {}
	return {"item": String(o["item"]), "min": int(o["min"]), "max": int(o["max"]), "regrow_days": ORE_REGROW_DAYS, "verb": String(o["verb"])}


static func state_id(id: String) -> String:
	return "wilds/node/" + id


## Is the node ready (never gathered, or its regrowth day has come)?
static func ready_now(id: String, kind: String) -> bool:
	var st: Dictionary = WorldState.shared().call("get_state", state_id(id), {"day": -999})
	return int(WorldSim.day) - int(st.get("day", -999)) >= int(yield_of(kind).get("regrow_days", 3))


func build_all() -> void:
	for s: Dictionary in specs:
		_build(s)


func live_count() -> int:
	return _live.size()


func node_of(id: String) -> Node3D:
	return _live.get(id)


func _build(s: Dictionary) -> Node3D:
	var id := String(s["id"])
	if _live.has(id) and is_instance_valid(_live[id]):
		return _live[id]
	var kind := String(s["kind"])
	var p: Vector2 = s["pos"]
	if p == Vector2.INF:
		return null
	var n := Node3D.new()
	n.name = "Gather_" + id
	n.set_meta("node_id", id)
	n.set_meta("kind", kind)
	add_child(n)
	n.global_position = Wilds.ground(p)
	var key := "hazel"
	var sc := 0.45
	match kind:
		"herb":
			key = "flowers"
			sc = 1.2
		"mushroom":
			key = "fern"
			sc = 0.7
		"firewood":
			key = "log_branchy"
			sc = 0.8
		_:
			key = "boulder"
			sc = 0.7
	var mi := Props.prop(n, key, p, float(id.hash() % 628) / 100.0, sc, 0.0, false)
	if kind in ["iron", "copper", "coal"]:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = (OreVein.ORES[kind]["color"] as Color).lerp(Color(0.45, 0.43, 0.4), 0.35)
		mat.roughness = 0.9
		mi.material_override = mat
	var y := yield_of(kind)
	Interactable.attach(n, {"id": "wilds/gather/" + id, "verb": String(y.get("verb", "Gather")), "target": "", "range": 3.0,
		"can": func(_pl: Node) -> bool: return ready_now(id, kind),
		"do": func(_pl: Node) -> void: gather(id, kind)})
	_live[id] = n
	n.set_meta("interactable_ok", true)
	return n


## Gathers a node: Life.give, WorldState regrowth stamp, the node goes bare. Returns the item count (0 = not ready).
func gather(id: String, kind: String) -> int:
	if not ready_now(id, kind):
		return 0
	var y := yield_of(kind)
	if y.is_empty():
		return 0
	Gathering.register(Life)
	var n := randi_range(int(y["min"]), int(y["max"]))
	if kind in ["iron", "copper", "coal"] and Life.count("pickaxe") > 0:
		n += 1
	Life.give(String(y["item"]), n)
	WorldState.shared().call("set_state", state_id(id), {"day": int(WorldSim.day)}, {"day": -999})
	Game.say("You gather %d %s." % [n, Life.item_name(String(y["item"]))])
	var node: Node3D = _live.get(id)
	if node != null and is_instance_valid(node):
		node.visible = false
	return n


## Restores visibility of regrown nodes (called with the hub timer).
func refresh(pp: Vector2) -> void:
	for s: Dictionary in specs:
		var id := String(s["id"])
		var p: Vector2 = s["pos"]
		if p == Vector2.INF:
			continue
		var d := pp.distance_to(p)
		if d < BUILD and not _live.has(id):
			_build(s)
		elif d > FREE and _live.has(id):
			if is_instance_valid(_live[id]):
				(_live[id] as Node).queue_free()
			_live.erase(id)
		if _live.has(id) and is_instance_valid(_live[id]):
			(_live[id] as Node3D).visible = ready_now(id, String(s["kind"]))
