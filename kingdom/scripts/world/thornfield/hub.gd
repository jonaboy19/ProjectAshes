extends Node
## Thornfield as a place (F8): the one node main.gd adds after the world exists. It wires the F7 quest library to the
## real game for the three Thornfield quests and builds the physical parts the quests need:
##
##   clues       thornfield/clue/{sack,prints,lock,ledger} around the brewery granary and Hesta's table   (clues.gd)
##   barn figure Wilm Garrow's night body at the barn, watched through QuestPump.watch("barn_figure", ...)  (barn_figure.gd)
##   grain cart  an actor with health that rolls from the barn to the mill; wolves hunt it                   (grain_cart.gd)
##   wolves      the den near the town, night probes of the farms, the cart ambush                           (wolf_threat.gd)
##   livestock   pens for the farm's sheep and pigs (the animals come from AmbientLife via livestock.gd)
##   barley      the tithe barn's sound barley, which the player may load for the cart
## and feeds the quest bus from the real systems: `enter_area` for the four places, `inventory` from Life's pack,
## `kill`/`died` from Life.region1_kill, `died` from WorldSim.kill_person (roster.gd), `deliver` from the talk menu
## (thornfield_talk.gd), `arrive`/`actor_pos`/`died` from the cart, `observe` from QuestPump.
##
## Everything is cheap when idle: one 0.5 s poll, no per-frame work.

const Sites := preload("res://scripts/world/thornfield/sites.gd")
const Roster := preload("res://scripts/world/thornfield/roster.gd")
const Clues := preload("res://scripts/world/thornfield/clues.gd")
const Livestock := preload("res://scripts/world/thornfield/livestock.gd")
const BarnFigure := preload("res://scripts/world/thornfield/barn_figure.gd")
const GrainCart := preload("res://scripts/world/thornfield/grain_cart.gd")
const WolfThreat := preload("res://scripts/world/thornfield/wolf_threat.gd")
const WildsHub := preload("res://scripts/world/thornfield/wilds_hub.gd")   # F9: the wilds, the Rift, the bandit camp, the outpost
const TICK := 0.5
const REENTER := 2.0
const CARTS := "thornfield_grain_carts"
const BARLEY_STORE := "thornfield/barley_store"
const SACKS := 4

var pump: Node
var threat: Node
var wilds: Node
var figure: Node3D
var cart: Node3D
var clues: Array = []
var pens: Node3D
var store: Node3D
var hesta: Node3D

var _acc := 0.0
var _inside: Dictionary = {}        # place id -> seconds until the next enter_area
var _cart_stage := ""
var _cart_started := false
var _barley_given_for := -1.0       # the quest start stamp the store already paid out for


static func attach(parent: Node) -> Node:
	var h: Node = load("res://scripts/world/thornfield/hub.gd").new()
	parent.add_child(h)
	return h


func _ready() -> void:
	name = "ThornfieldHub"
	Roster.bind()
	pump = load("res://scripts/quests/quest_pump.gd").attach(self)
	_localize_markers(QuestHub.runner())
	clues = Clues.build(self)
	pens = Livestock.build_pens(self)
	store = _build_barley_store()
	hesta = _build_hesta()
	figure = _build_figure()
	threat = WolfThreat.new()
	add_child(threat)
	wilds = WildsHub.attach(self, threat)
	if Life != null:
		Roster.seed_social_graph(Life.get("npc_social_graph"), WorldSim.SEED)
		Life.region1_kill.connect(_on_kill)
		Life.inventory_changed.connect(_emit_inventory)


## The quest data's `pos` hints are placeholders (site-local guesses); in the game they are the barn figure's spot and the
## mill. They only show when the player pins the quest.
func _localize_markers(r: QuestRunner) -> void:
	var fig := Sites.figure_spot()
	var mill := Sites.door_of_site("thornfield_mill")
	for pair: Array in [["thornfield_spoiled_barley", "watch", fig], ["thornfield_grain_carts", "escort", mill]]:
		var d := r.def(String(pair[0]))
		if d == null or pair[2] == Vector2.INF:
			continue
		for st: Dictionary in d.stages:
			for o: Dictionary in st.get("objectives", []):
				if String(o.get("id", "")) == String(pair[1]):
					var p: Vector2 = pair[2]
					o["pos"] = [p.x, p.y]


# --- the parts ---------------------------------------------------------------------------------

func _build_figure() -> Node3D:
	var row := Roster.row_of("wilm_garrow")
	var f := BarnFigure.spawn(self, row)
	pump.call("watch", "barn_figure", Callable(f, "watch_pos"), Callable(f, "watch_facing"))
	return f


## A pile of the tithe barley by the granary door: "Take sound barley" while the cart quest is on its first stage.
func _build_barley_store() -> Node3D:
	var b := Sites.brewery()
	var n := Node3D.new()
	n.name = "BarleyStore"
	add_child(n)
	if b.is_empty():
		return n
	var w := Sites.to_world(b, Sites.BARN_DOOR + Vector2(2.4, 0.8))
	n.global_position = Vector3(w.x, WorldGen.height(w.x, w.y), w.y)
	var mesh: ArrayMesh = Assets.building_mesh("sack_pile")
	if mesh != null:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.scale = Vector3.ONE * 0.8
		n.add_child(mi)
	Interactable.attach(n, {"id": BARLEY_STORE, "verb": "Take", "target": "Sound barley", "range": 2.6,
		"can": func(_p: Node) -> bool: return store_available(),
		"do": func(_p: Node) -> void: take_barley()})
	return n


func store_available() -> bool:
	var r := QuestHub.peek()
	return r != null and r.is_active(CARTS) and r.stage_of(CARTS) == "load" and _barley_given_for != r.run(CARTS).started


func take_barley() -> String:
	var r := QuestHub.peek()
	if not store_available():
		return ""
	_barley_given_for = r.run(CARTS).started
	Life.give("barley", SACKS)
	Game.say("You take %d sacks of sound barley from the tithe barn." % SACKS)
	return "ok"


## Hesta Thorne, the giver of all three quests: a roster resident that is not a WorldSim row, so she stands at her stool by the
## brewery table as a Station whose menu is the ordinary conversation (dialogue/thornfield/hesta_thorne.json + the quest options).
func _build_hesta() -> Node3D:
	var b := Sites.brewery()
	var e := Roster.entry("hesta_thorne")
	if b.is_empty() or e.is_empty():
		return null
	var w := Sites.to_world(b, Sites.HESTA_AT)
	var st := Station.new(String(e["name"]), "Talk", Callable())
	st.name = "Hesta"
	st.set_meta("npc_id", "hesta_thorne")
	st.menu = func() -> Dictionary:
		var sv := Interaction.services(self)
		if sv == null:
			return {"title": String(e["name"]), "body": "...", "options": []}
		return sv.call("talk_menu", {"id": "hesta_thorne", "name": String(e["name"])})
	add_child(st)
	st.global_position = Vector3(w.x, WorldGen.height(w.x, w.y), w.y)
	var toward := Sites.to_world(b, Sites.TABLE_AT) - w
	st.rotation.y = atan2(toward.x, toward.y)
	var body: Node3D = Assets.character("Trader", 1.7, [])
	if body != null:
		st.add_child(body)
		var ap := Assets.animation_player(body)
		if ap:
			ap.play("Idle" if ap.has_animation("Idle") else ap.get_animation_list()[0])
	return st


# --- the poll ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_acc += delta
	if _acc < TICK:
		return
	var dt := _acc
	_acc = 0.0
	poll(dt)


## One poll step (tests call it directly with a stand-in player in group "player").
func poll(dt: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null:
		var pp := Vector2(player.global_position.x, player.global_position.z)
		_places(pp, dt)
		threat.call("tick", pp)
	_cart_tick()
	_emit_inventory()


func _places(pp: Vector2, dt: float) -> void:
	var bus := QuestBus.shared()
	var places := Sites.places()
	for id: String in places:
		var p: Dictionary = places[id]
		var d := pp.distance_to(p["pos"])
		if d <= float(p["radius"]):
			var left: float = float(_inside.get(id, 0.0)) - dt
			if left <= 0.0:
				bus.emit_event(&"enter_area", {"place": id})
				left = REENTER
			_inside[id] = left
		elif _inside.has(id) and d > float(p["radius"]) * 1.25:
			_inside.erase(id)


## Life's pack counts for every item an active quest collects (Collect reads `inventory {counts}`); sent whenever an
## open Collect objective disagrees with the pack, so a stage that starts while the player already carries the goods
## counts them at once.
func _emit_inventory() -> void:
	var r := QuestHub.peek()
	if r == null:
		return
	var counts := {}
	var stale := false
	for qid: String in r.active_ids():
		for o: RefCounted in r.objectives_of(qid):
			if String(o.type) == "collect" and not o.is_done():
				var item := String(o.data.get("item", ""))
				var n: int = Life.count(item)
				counts[item] = n
				if int(o.have) != n:
					stale = true
	if stale:
		QuestBus.shared().emit_event(&"inventory", {"counts": counts})


## A monster fell: `died {actor: species}` and, near Thornfield's places, `kill {target, place}` for each.
func _on_kill(species: String, where: Vector3) -> void:
	var bus := QuestBus.shared()
	bus.emit_event(&"died", {"actor": species})
	var p := Vector2(where.x, where.z)
	var places := Sites.places()
	for id: String in places:
		var pl: Dictionary = places[id]
		if id != "thornfield" and p.distance_to(pl["pos"]) <= float(pl["radius"]) + 25.0:
			bus.emit_event(&"kill", {"target": species, "place": id, "amount": 1})


# --- the grain cart ------------------------------------------------------------------------------

## Cart route: barn yard -> mill (straight, the farm lane).
func cart_route() -> PackedVector2Array:
	var a := Sites.door_of_site("thornfield_barn")
	var m := Sites.door_of_site("thornfield_mill")
	return PackedVector2Array([a, m]) if a != Vector2.INF and m != Vector2.INF else PackedVector2Array()


func _cart_tick() -> void:
	var r := QuestHub.peek()
	if r == null:
		return
	var active := r.is_active(CARTS)
	var done := r.is_done(CARTS)
	if not active and not done:
		if cart != null and is_instance_valid(cart):
			cart.queue_free()
			cart = null
		_cart_stage = ""
		_cart_started = false
		threat.call("clear_ambush")
		return
	if cart == null or not is_instance_valid(cart):
		cart = GrainCart.new()
		add_child(cart)
		var route := cart_route()
		if not route.is_empty():
			cart.call("place_at", route[route.size() - 1] if done else route[0])
		if done:
			cart.set("finished", true)
		_cart_stage = ""
	var stage := r.stage_of(CARTS)
	if stage == _cart_stage:
		return
	_cart_stage = stage
	match stage:
		"guard":
			threat.call("ambush", cart, 3)
			Game.say("Wolves at the hedge. Hold them off the cart.")
		"road":
			cart.call("start_route", cart_route())
