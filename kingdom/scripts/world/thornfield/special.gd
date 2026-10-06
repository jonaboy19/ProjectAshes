extends "res://scripts/world/town_kit/town_special.gd"
## Thornfield's one-off quest set pieces, the part of the town the generic kit (scripts/world/town_kit/) does not know:
##
##   clues       thornfield/clue/{sack,prints,lock,ledger} around the brewery granary and Hesta's table   (clues.gd)
##   barn figure Wilm Garrow's night body at the barn, watched through QuestPump.watch("barn_figure", ...)  (barn_figure.gd)
##   grain cart  an actor with health that rolls from the barn to the mill; wolves hunt it                   (grain_cart.gd)
##   barley      the tithe barn's sound barley, which the player may load for the cart
##   Hesta       the giver of all three quests, a roster resident that stands at the brewery as a Station
##   wilds       the wilds, the Rift, the bandit camp, the outpost (F9)                                      (wilds_hub.gd)
## The town file (data/region1/towns/thornfield.json) names this script as its `special`; the kit's TownHub calls the hooks of
## town_special.gd. The generic parts (roster, lots, keepers, places, threat, pens, quest wiring) are the kit's.

const Sites := preload("res://scripts/world/thornfield/sites.gd")
const TownRoster := preload("res://scripts/world/town_kit/town_roster.gd")
const Clues := preload("res://scripts/world/thornfield/clues.gd")
const BarnFigure := preload("res://scripts/world/thornfield/barn_figure.gd")
const GrainCart := preload("res://scripts/world/thornfield/grain_cart.gd")
const CartRoute := preload("res://scripts/world/thornfield/cart_route.gd")
const HestaBody := preload("res://scripts/world/thornfield/hesta_body.gd")
const WildsHub := preload("res://scripts/world/thornfield/wilds_hub.gd")   # F9: the wilds, the Rift, the bandit camp, the outpost
const CARTS := "thornfield_grain_carts"
const CULPRIT := "thornfield_the_culprit"
const BARLEY_STORE := "thornfield/barley_store"
const SACKS := 4

var wilds: Node
var figure: Node3D
var cart: Node3D
var store: Node3D
var hesta: Node3D

var _hub: Node
var _cart_stage := ""
var _cart_started := false
var _barley_given_for := -1.0       # the quest start stamp the store already paid out for


func build(hub: Node) -> void:
	_hub = hub
	_localize_markers(QuestHub.runner())
	hub.clues.append_array(Clues.build(hub))
	store = _build_barley_store(hub)
	hesta = _build_hesta(hub)
	figure = _build_figure(hub)
	var barn_door := Sites.door_of_site("thornfield_barn")
	var mill_door := Sites.door_of_site("thornfield_mill")
	if barn_door != Vector2.INF and mill_door != Vector2.INF:
		CartRoute.prewarm(barn_door, mill_door)      # the cart's way is planned on a worker thread (cart_route.gd)


func after_threat(hub: Node) -> void:
	wilds = WildsHub.attach(hub, hub.threat)


func poll(hub: Node, _dt: float) -> void:
	_cart_tick(hub)


func prop(name: String) -> Variant:
	match name:
		"wilds": return wilds
		"figure": return figure
		"cart": return cart
		"store": return store
		"hesta": return hesta
	return null


## Dialogue keys the generated resident files use (Wilm's confession / bribe nodes).
func ctx_extra(info: Dictionary) -> Dictionary:
	var r := QuestHub.peek()
	if r == null or String(info.get("id", "")) != "wilm_garrow":
		return {}
	return {"thornfield_confront": r.is_active(CULPRIT) and r.stage_of(CULPRIT) == "confront",
		"thornfield_bribe_paid": r.is_active(CULPRIT) and r.stage_of(CULPRIT) == "bribed"}


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

func _build_figure(hub: Node) -> Node3D:
	var row := TownRoster.row_of("wilm_garrow")
	var f := BarnFigure.spawn(hub, row)
	hub.pump.call("watch", "barn_figure", Callable(f, "watch_pos"), Callable(f, "watch_facing"))
	return f


## A pile of the tithe barley by the granary door: "Take sound barley" while the cart quest is on its first stage.
func _build_barley_store(hub: Node) -> Node3D:
	var b := Sites.brewery()
	var n := Node3D.new()
	n.name = "BarleyStore"
	hub.add_child(n)
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
func _build_hesta(hub: Node) -> Node3D:
	var b := Sites.brewery()
	var e := TownRoster.entry("hesta_thorne")
	if b.is_empty() or e.is_empty():
		return null
	var w := Sites.to_world(b, Sites.HESTA_AT)
	var st := Station.new(String(e["name"]), "Talk", Callable())
	st.name = "Hesta"
	st.subtitle = String(e.get("role", "Brewmistress")).capitalize()    # one plate: the name, the title as a smaller second line
	st.set_meta("npc_id", "hesta_thorne")
	st.menu = func() -> Dictionary:
		var sv := Interaction.services(hub)
		if sv == null:
			return {"title": String(e["name"]), "body": "...", "options": []}
		return sv.call("talk_menu", {"id": "hesta_thorne", "name": String(e["name"])})
	hub.add_child(st)
	st.global_position = Vector3(w.x, WorldGen.height(w.x, w.y), w.y)
	var toward := Sites.front(b)            # faces the street, not the table (a sign post and lanterns stand in between)
	st.rotation.y = atan2(toward.x, toward.y)
	var body: Node3D = HestaBody.new()
	st.add_child(body)
	st.set_meta("talk_body", body)
	return st


# --- the grain cart ------------------------------------------------------------------------------

## Cart route: barn yard -> mill. There is no road between them, so CartRoute plans a few waypoints across the farmland that keep
## clear of every tree, rock, bush, site and building (and wide enough for the player to walk beside the cart).
func cart_route() -> PackedVector2Array:
	var a := Sites.door_of_site("thornfield_barn")
	var m := Sites.door_of_site("thornfield_mill")
	if a == Vector2.INF or m == Vector2.INF:
		return PackedVector2Array()
	return CartRoute.plan(a, m)


func _cart_tick(hub: Node) -> void:
	var r := QuestHub.peek()
	if r == null:
		return
	var threat: Node = hub.threat
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
		hub.add_child(cart)
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
