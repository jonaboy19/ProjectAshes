extends RefCounted
## Kit-placed quest props of a town: Investigate clues and Collect stashes, from the town file's `clues` and `stashes`.
##
## A clue is a Clue interactable (scripts/interaction/kinds/clue.gd): no marker, no glow, a small low-contrast prop; Examine fires
## `interact {id}` on the quest bus, which Investigate objectives count. A stash is a pile of goods ("Take") that exists for a
## Collect stage: it is available while its quest is on its stage and pays out once per run of that quest, then the Collect
## objective counts them through the hub's inventory poll.
##
##   clue  {id, anchor | building, at, h, target, note, prop}      prop: sack | ledger | lock | tracks | crate | stone | scorch | bones | rag
##   stash {id, item, count, anchor | building, at, quest, stage, target, say, prop}
##
## `build_clues(tid, parent)` / `build_stashes(tid, parent)` return the nodes; tests call `take(node)` / `Clue.examine()`.
## Preload, no class_name; every function is static.

const TownData := preload("res://scripts/world/town_kit/town_data.gd")
const TownPlaces := preload("res://scripts/world/town_kit/town_places.gd")
const Ground := preload("res://scripts/world/town_kit/town_ground.gd")


static func clue_ids(tid: String) -> Array:
	var out: Array = []
	for c: Dictionary in TownData.town(tid).get("clues", []):
		out.append(String(c["id"]))
	return out


## World XZ of a clue / stash definition, moved to the nearest dry, level-enough ground when the authored offset lands in water or on a
## slope (Vector2.INF only when the anchor is missing; a quest prop is never dropped).
static func spot(tid: String, def: Dictionary) -> Vector2:
	var w := TownPlaces.resolve(tid, def)
	if w == Vector2.INF:
		return w
	return Ground.settle_prop(tid, w)


static func build_clues(tid: String, parent: Node) -> Array:
	var out: Array = []
	for c: Dictionary in TownData.town(tid).get("clues", []):
		var w := spot(tid, c)
		if w == Vector2.INF:
			continue
		var y := WorldGen.height(w.x, w.y) + float(c.get("h", 0.0))
		var node: Node3D = Clue.spawn(parent, Vector3(w.x, y, w.y), String(c["id"]), String(c.get("note", "")), String(c.get("target", "Something odd")))
		_dress(node, String(c.get("prop", "crate")))
		out.append(node)
	return out


# --- stashes -------------------------------------------------------------------------------------

static func build_stashes(tid: String, parent: Node) -> Array:
	var out: Array = []
	for s: Dictionary in TownData.town(tid).get("stashes", []):
		var w := spot(tid, s)
		if w == Vector2.INF:
			continue
		var n := Node3D.new()
		n.name = "Stash_" + String(s["id"]).replace("/", "_")
		parent.add_child(n)
		n.global_position = Vector3(w.x, WorldGen.height(w.x, w.y), w.y)
		n.set_meta("stash", s)
		_dress(n, String(s.get("prop", "sack")))
		Interactable.attach(n, {"id": String(s["id"]), "verb": "Take", "target": String(s.get("target", "Supplies")), "range": 2.6,
			"can": func(_p: Node) -> bool: return available(n),
			"do": func(_p: Node) -> void: take(n)})
		out.append(n)
	return out


## Is this stash on offer: its quest is active, on the stage the stash is for, and this run has not taken it yet.
static func available(stash: Node) -> bool:
	var s: Dictionary = stash.get_meta("stash", {})
	var r := QuestHub.peek()
	if s.is_empty() or r == null:
		return false
	var qid := String(s.get("quest", ""))
	return r.is_active(qid) and r.stage_of(qid) == String(s.get("stage", "")) and float(stash.get_meta("given_for", -1.0)) != r.run(qid).started


## Gives the goods (once per quest run). Returns "ok", or "" when nothing was on offer.
static func take(stash: Node) -> String:
	if not available(stash):
		return ""
	var s: Dictionary = stash.get_meta("stash", {})
	var r := QuestHub.peek()
	stash.set_meta("given_for", r.run(String(s["quest"])).started)
	Life.give(String(s["item"]), int(s.get("count", 1)))
	Game.say(String(s.get("say", "You take the %s." % String(s["item"]).replace("_", " "))))
	return "ok"


# --- props ---------------------------------------------------------------------------------------

## The small prop that makes a clue or stash findable by eye: simple shapes, low contrast, no light.
static func _dress(node: Node3D, prop: String) -> void:
	match prop:
		"sack":
			var mesh: ArrayMesh = Assets.building_mesh("sack_pile")
			if mesh != null:
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.scale = Vector3.ONE * 0.55
				mi.position.y = -0.04
				node.add_child(mi)
			node.add_child(_stain(Color(0.16, 0.13, 0.07, 0.5), 0.9))
		"ledger":
			node.add_child(_box(Vector3(0.34, 0.035, 0.24), Color(0.25, 0.14, 0.09), Vector3.ZERO))
			node.add_child(_box(Vector3(0.30, 0.02, 0.21), Color(0.86, 0.80, 0.66), Vector3(0, 0.026, 0)))
		"lock":
			node.add_child(_box(Vector3(0.22, 0.05, 0.12), Color(0.18, 0.16, 0.15), Vector3.ZERO))
			node.add_child(_box(Vector3(0.09, 0.12, 0.05), Color(0.30, 0.26, 0.20), Vector3(0.08, -0.14, 0.03), 0.5))
		"tracks":
			node.add_child(_stain(Color(0.10, 0.07, 0.04, 0.55), 0.8))
		"stone":
			node.add_child(_box(Vector3(0.5, 0.3, 0.4), Color(0.42, 0.42, 0.40), Vector3(0, 0.15, 0), 0.0, 0.5))
		"scorch":
			node.add_child(_stain(Color(0.05, 0.045, 0.04, 0.7), 0.9))
			node.add_child(_box(Vector3(0.22, 0.08, 0.16), Color(0.09, 0.08, 0.07), Vector3(0.1, 0.05, 0.0), 0.0, 0.7))
		"bones":
			node.add_child(_box(Vector3(0.32, 0.05, 0.06), Color(0.80, 0.77, 0.68), Vector3(0, 0.04, 0), 0.0, 0.4))
			node.add_child(_box(Vector3(0.22, 0.05, 0.06), Color(0.78, 0.75, 0.66), Vector3(0.12, 0.04, 0.1), 0.0, -0.9))
			node.add_child(_stain(Color(0.14, 0.09, 0.06, 0.45), 0.7))
		"rag":
			node.add_child(_box(Vector3(0.42, 0.015, 0.2), Color(0.30, 0.22, 0.34), Vector3(0, 0.02, 0), 0.0, 0.3))
			node.add_child(_box(Vector3(0.12, 0.03, 0.12), Color(0.34, 0.26, 0.38), Vector3(0.1, 0.035, 0.06), 0.0, 1.0))
		_:
			node.add_child(_box(Vector3(0.5, 0.4, 0.4), Color(0.36, 0.26, 0.16), Vector3(0, 0.2, 0), 0.0, 0.3))


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _box(size: Vector3, c: Color, at: Vector3, roll := 0.0, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = at
	mi.rotation = Vector3(0.0, yaw, roll)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _stain(c: Color, r: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(r * 2.0, r * 2.0)
	mi.mesh = q
	mi.material_override = _mat(c)
	mi.position.y = 0.02
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
