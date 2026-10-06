extends Node
## A kit town as a place (F8): the node main.gd adds, one per town file (`TownHub.attach_all(world)`), after the world exists. It
## wires the F7 quest library to the real game for the town's quest files and builds the physical parts the quests need:
##
##   quests      the town file's quest definitions are loaded into the quest runner
##   clues       Investigate props (`clues`)                                                    (town_clues.gd)
##   stashes     goods a Collect stage lets the player take (`stashes`)                         (town_clues.gd)
##   pens        rail-fence pens for the livestock (the animals come from AmbientLife)          (town_livestock.gd)
##   threat      the den near the town and its night probes of `probe_place`                    (town_threat.gd)
##   special     the town's one-off code: Thornfield's barn figure, grain cart, wilds           (town_special.gd)
## and feeds the quest bus from the real systems: `enter_area` for the town's places, `inventory` from Life's pack,
## `kill`/`died` from Life.region1_kill, `died` from WorldSim.kill_person (town_roster.gd), `deliver` from the talk menu
## (town_talk.gd), `arrive`/`actor_pos`/`died` from a special's actors, `observe` from QuestPump.
##
## Everything is cheap when idle: one 0.5 s poll, no per-frame work. A town with a `hub` script in its file gets that
## script instead (a facade that extends this one, for tools that call town-specific methods).

const TownData := preload("res://scripts/world/town_kit/town_data.gd")
const TownRoster := preload("res://scripts/world/town_kit/town_roster.gd")
const TownPlaces := preload("res://scripts/world/town_kit/town_places.gd")
const TownLivestock := preload("res://scripts/world/town_kit/town_livestock.gd")
const TownClues := preload("res://scripts/world/town_kit/town_clues.gd")
const TownThreat := preload("res://scripts/world/town_kit/town_threat.gd")
const TownSpecial := preload("res://scripts/world/town_kit/town_special.gd")
const TICK := 0.5
const REENTER := 2.0
const PLACES_REFRESH := 20            # polls between two resolutions of the place list (10 s)

var tid := ""
var doc: Dictionary = {}
var pump: Node
var threat: Node
var special: TownSpecial
var pens: Node3D
var clues: Array = []
var stashes: Array = []

var _acc := 0.0
var _inside: Dictionary = {}        # place id -> seconds until the next enter_area
var _places_cache: Dictionary = {}
var _places_age := 1000

static var _lead: Node = null       # the hub that reports the town-independent `died {species}` once per kill


## Attaches one hub per town file. Returns the hubs.
static func attach_all(parent: Node) -> Array:
	var out: Array = []
	for id: String in TownData.ids():
		out.append(attach(parent, id))
	return out


static func attach(parent: Node, town_id: String) -> Node:
	var path := String(TownData.town(town_id).get("hub", ""))
	var script: GDScript = load(path) if path != "" else load("res://scripts/world/town_kit/town_hub.gd")
	var h: Node = script.new()
	h.set("tid", town_id)
	parent.add_child(h)
	return h


func _ready() -> void:
	doc = TownData.town(tid)
	name = String(doc.get("hub_name", "TownHub_" + tid))
	if _lead == null or not is_instance_valid(_lead):
		_lead = self
	TownRoster.bind(tid)
	pump = load("res://scripts/quests/quest_pump.gd").attach(self)
	_register_quests(QuestHub.runner())
	var sp := String(doc.get("special", ""))
	special = (load(sp) as GDScript).new() if sp != "" else TownSpecial.new()
	clues = TownClues.build_clues(tid, self)
	stashes = TownClues.build_stashes(tid, self)
	pens = TownLivestock.build_pens(tid, self)
	special.build(self)
	if not (doc.get("threat", {}) as Dictionary).is_empty():
		threat = TownThreat.new()
		threat.configure(tid)
		add_child(threat)
	special.after_threat(self)
	if Life != null:
		TownRoster.seed_social_graph(Life.get("npc_social_graph"), WorldSim.SEED, tid)
		Life.region1_kill.connect(_on_kill)
		Life.inventory_changed.connect(_emit_inventory)


func _exit_tree() -> void:
	if _lead == self:
		_lead = null


## The quest files named by the town file are made sure to be in the runner (QuestHub already loads data/quests/*/).
func _register_quests(r: QuestRunner) -> void:
	for path: String in doc.get("quests", []):
		var d := QuestDef.load_json(path)
		if d != null and r.def(d.id) == null:
			r.add_def(d)


## The special's values for `get()` (a Thornfield hub answers get("cart"), get("figure"), ...).
func _get(property: StringName) -> Variant:
	return special.prop(String(property)) if special != null else null


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
		if threat != null:
			threat.call("tick", pp)
	special.poll(self, dt)
	_emit_inventory()


func places() -> Dictionary:
	_places_age += 1
	if _places_age >= PLACES_REFRESH or _places_cache.is_empty():
		_places_cache = TownPlaces.places(tid)
		_places_age = 0
	return _places_cache


func _places(pp: Vector2, dt: float) -> void:
	var bus := QuestBus.shared()
	var list := places()
	for id: String in list:
		var p: Dictionary = list[id]
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


## A creature fell: `died {actor: species}` (once, from the lead hub) and, near this town's places, `kill {target, place}` for each.
func _on_kill(species: String, where: Vector3) -> void:
	var bus := QuestBus.shared()
	if _lead == null or not is_instance_valid(_lead) or not _lead.is_inside_tree():
		_lead = self
	if _lead == self:
		bus.emit_event(&"died", {"actor": species})
	var p := Vector2(where.x, where.z)
	var list := TownPlaces.places(tid)
	for id: String in list:
		var pl: Dictionary = list[id]
		if id != tid and p.distance_to(pl["pos"]) <= float(pl["radius"]) + 25.0:
			bus.emit_event(&"kill", {"target": species, "place": id, "amount": 1})
