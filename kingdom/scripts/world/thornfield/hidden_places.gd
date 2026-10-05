extends Node3D
## Five small hidden places in the forest around Thornfield (F9), all from data/region1/world/thornfield_wilds.json "hidden":
##   hunters_cache   a hollow log with a hunter's stores (one-time reward)
##   ruined_shrine   the Shrine of the Ash-Warden: a carving with lore (a Society fact) and herbs left at its foot
##   cave_nook       a tiny hand-made mine with ore inside (data/region1/world/thornfield_nook.json) on the dungeon code: a DungeonDoor subclass
##   herb_glade      a fallen-tree bridge to a glade of herbs (the herbs are gather nodes, gather_nodes.gd)
##   hermit_hut      Orrin the Hermit, a Station with talk and a gift of herbs
## Each is found by walking there (no markers). What was taken is a WorldState delta "wilds/hidden/<id>" so it stays
## taken across saves. Built within BUILD metres of the player and freed beyond FREE.

const Wilds := preload("res://scripts/world/thornfield/wilds.gd")
const Props := preload("res://scripts/world/thornfield/wilds_props.gd")
const RiftDoor := preload("res://scripts/world/thornfield/rift_door.gd")
const Gathering := preload("res://scripts/sim/gathering_items.gd")
const DungeonItems := preload("res://scripts/interiors/dungeon_items.gd")
const WorldState := preload("res://scripts/world/world_state.gd")
const BUILD := 170.0
const FREE := 260.0

var places: Dictionary = {}         # id -> Node3D (the built place root)


func _ready() -> void:
	name = "WildsHiddenPlaces"


static func ids() -> Array:
	var out: Array = []
	for d: Dictionary in Wilds.data()["hidden"]:
		out.append(String(d["id"]))
	return out


static func pos_of(id: String) -> Vector2:
	var d := Wilds.hidden_def(id)
	return Wilds.at(d["offset"]) if not d.is_empty() else Vector2.INF


static func state_id(id: String) -> String:
	return "wilds/hidden/" + id


static func is_done(id: String) -> bool:
	return bool((WorldState.shared().call("get_state", state_id(id), {"done": false}) as Dictionary).get("done", false))


func build_all() -> void:
	for id: String in ids():
		build(id)


func build(id: String) -> Node3D:
	if places.has(id) and is_instance_valid(places[id]):
		return places[id]
	var d := Wilds.hidden_def(id)
	var p := pos_of(id)
	if d.is_empty() or p == Vector2.INF:
		return null
	var n := Node3D.new()
	n.name = "Hidden_" + id
	n.set_meta("place_id", id)
	n.set_meta("kind", String(d["kind"]))
	n.add_to_group("wilds_hidden")
	add_child(n)
	n.global_position = Wilds.ground(p)
	match String(d["kind"]):
		"cache":
			Props.prop(n, "log_branchy", p, 0.6, 1.0)
			Props.prop(n, "woodpile", p + Vector2(2.2, 1.0), 1.2, 0.6)
			_interact(n, id, d)
		"shrine":
			Props.prop(n, "shrine", p, 0.4, 1.0, 3.8)
			Props.prop(n, "boulder", p + Vector2(4.0, 2.0), 0.9, 0.9)
			Props.prop(n, "flowers", p + Vector2(1.2, 2.6), 0.0, 1.4)
			_interact(n, id, d)
		"cave":
			_build_cave(n, d, p)
		"glade":
			_build_glade(n, d, p)
		"hermit":
			_build_hermit(n, d, p)
	places[id] = n
	return n


## The node a player uses at this place (an Interactable host, a Station or the cave's door).
func interactable_of(id: String) -> Node:
	var n: Node3D = places.get(id)
	if n == null or not is_instance_valid(n):
		return null
	var st := n.find_child("Hermit", true, false)
	if st != null:
		return st
	var door := n.find_child("RiftDoor_*", true, false)
	if door != null:
		return door
	return n if n.has_meta(Interactable.META) else null


func _interact(n: Node3D, id: String, d: Dictionary) -> void:
	Interactable.attach(n, {"id": "wilds/hidden/" + id, "verb": String(d.get("verb", "Search")), "target": String(d.get("target", d["name"])), "range": 3.4,
		"do": func(_pl: Node) -> void: use(id)})


## The interaction: reads the text, learns the fact, pays the one-time reward. Returns the reward line ("" when
## there is nothing (more) to take).
func use(id: String) -> String:
	var d := Wilds.hidden_def(id)
	if d.is_empty():
		return ""
	Game.say(String(d["text"]))
	if d.has("fact"):
		_learn(String(d["fact"]), String(d.get("fact_text", d["text"])))
	return claim(id)


## One-time reward (items + gold) of a place; "" when already taken or the place pays nothing.
static func claim(id: String) -> String:
	var d := Wilds.hidden_def(id)
	if d.is_empty() or not d.has("reward") or is_done(id):
		return ""
	var r: Dictionary = d["reward"]
	Gathering.register(Life)
	DungeonItems.register(Life)
	var parts := PackedStringArray()
	for e: Array in r.get("items", []):
		Life.give(String(e[0]), int(e[1]))
		parts.append("%d %s" % [int(e[1]), Life.item_name(String(e[0]))])
	var gold := int(r.get("gold", 0))
	if gold > 0:
		Game.add_gold(gold)
		parts.append("%d gold" % gold)
	WorldState.shared().call("set_state", state_id(id), {"done": true}, {"done": false})
	var line := "You find: %s." % ", ".join(parts)
	Game.say(line)
	return line


static func _learn(fact: String, text: String) -> void:
	if Life == null or Life.get("realm") == null:
		return
	var soc: Variant = Life.realm.mod("society")
	if soc != null:
		soc.learn(fact, text)


# --- the cave nook: the existing generated-dungeon code ---------------------------------------------

func _build_cave(n: Node3D, d: Dictionary, p: Vector2) -> void:
	# a crack in the hillside: two leaning boulders and a dark gap between them
	Props.prop(n, "boulder", p + Vector2(-2.3, 0.0), 0.3, 1.5)
	Props.prop(n, "boulder", p + Vector2(2.3, 0.4), 2.4, 1.6)
	var gap := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.0, 2.6, 0.2)
	gap.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.03)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gap.material_override = mat
	gap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(gap)
	gap.global_position = Wilds.ground(p) + Vector3(0, 1.3, -0.6)
	var door := RiftDoor.new()
	n.add_child(door)
	door.configure_hand(String(d["layout"]))
	door.global_position = Wilds.ground(p) + Vector3(0, 0.0, 1.4)
	door.global_position.y = WorldGen.height(door.global_position.x, door.global_position.z)
	n.set_meta("dungeon_id", door.dungeon_id)


# --- the glade and its fallen-tree bridge -----------------------------------------------------------------

func _build_glade(n: Node3D, d: Dictionary, p: Vector2) -> void:
	var br: Dictionary = d["bridge"]
	var a := Wilds.at(br["from"])
	var b := Wilds.at(br["to"])
	var mid := (a + b) * 0.5
	var dir := b - a
	var length := dir.length()
	var log := Props.mesh("log")
	var mi := Props.prop(n, "log", mid, atan2(-dir.y, dir.x), maxf(length / 4.24, 0.5) if log != null else 1.0)
	mi.set_meta("bridge", true)
	n.set_meta("bridge_from", a)
	n.set_meta("bridge_to", b)
	for k in 5:
		var q := p + Vector2(cos(k * 1.9) * 4.0, sin(k * 1.9) * 4.0)
		Props.prop(n, "flowers", q, float(k), 1.5)
	Props.prop(n, "hazel", p + Vector2(-5.0, 3.0), 0.7, 0.9)
	_interact(n, "herb_glade", {"verb": "Rest", "target": "the glade", "name": d["name"], "text": d["text"]})


# --- Orrin ----------------------------------------------------------------------------------------

func _build_hermit(n: Node3D, d: Dictionary, p: Vector2) -> void:
	Props.prop(n, "lean_to", p + Vector2(0, -4.0), PI, 1.3)
	Props.prop(n, "woodpile", p + Vector2(4.0, -2.0), 0.5, 0.7)
	Props.prop(n, "campfire", p + Vector2(0.0, 2.6), 0.0, 0.8, 0.0, false)
	Props.fire_light(n, Wilds.ground(p + Vector2(0.0, 2.6), 1.2), 1.1, 9.0)
	var st := Station.new(String(d["npc"]), "Talk", Callable())
	st.name = "Hermit"
	st.menu = func() -> Dictionary: return hermit_menu(String(d["id"]))
	n.add_child(st)
	st.global_position = Wilds.ground(p + Vector2(-1.6, 1.4))
	var body := Assets.character("Herbalist", 1.7, [])
	if body != null:
		st.add_child(body)
		var ap := Assets.animation_player(body)
		if ap:
			ap.play("Idle" if ap.has_animation("Idle") else ap.get_animation_list()[0])
	st.rotation.y = atan2(1.6, -1.4)


func hermit_menu(id: String) -> Dictionary:
	var d := Wilds.hidden_def(id)
	var lines: Array = d["lines"]
	var line := String(lines[int(WorldSim.day) % lines.size()])
	var opts: Array = [["Ask about the Rift", func() -> String: return String(d["rumour"])]]
	if not is_done(id):
		opts.append(["Accept the herbs he offers", func() -> String: return claim(id)])
	return {"title": String(d["npc"]), "body": line, "options": opts}


# --- by distance ---------------------------------------------------------------------------------------

func refresh(pp: Vector2) -> void:
	for id: String in ids():
		var p := pos_of(id)
		if p == Vector2.INF:
			continue
		var dist := pp.distance_to(p)
		if dist < BUILD and not places.has(id):
			build(id)
		elif dist > FREE and places.has(id):
			if is_instance_valid(places[id]):
				(places[id] as Node).queue_free()
			places.erase(id)
