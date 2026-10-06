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
##
## Scale (30 hubs, S2): a GATED hub (`attach_all(world, true)`, what main.gd does) follows the cell streamer's "settlement" profile.
## Outside that tier (650 m, plus 200 m of hysteresis) it is asleep: no _process, no poll, its clue and stash props hidden and
## not interactable, its pens hidden, its probe creatures released. The first time the player comes within range it is ACTIVATED
## once (quests registered, props, pens, den and threat node, social-graph ties) and woken; after that it only wakes and sleeps.
## Hubs poll at staggered phases (never all in one frame). A hub without the gate (tests, tools, Thornfield) is always awake.

const TownData := preload("res://scripts/world/town_kit/town_data.gd")
const TownRoster := preload("res://scripts/world/town_kit/town_roster.gd")
const TownPlaces := preload("res://scripts/world/town_kit/town_places.gd")
const TownLivestock := preload("res://scripts/world/town_kit/town_livestock.gd")
const TownClues := preload("res://scripts/world/town_kit/town_clues.gd")
const TownThreat := preload("res://scripts/world/town_kit/town_threat.gd")
const TownSpecial := preload("res://scripts/world/town_kit/town_special.gd")
const CellStreamer := preload("res://scripts/core/cell_streamer.gd")
const TICK := 0.5
const REENTER := 2.0
const PROFILE := "settlement"
const KILL_PAD := 25.0                # a kill within this of a place's radius still counts for it
const PLACES_REFRESH := 20            # polls between two resolutions of the place list (10 s)

var tid := ""
var gated := false                  # follows the cell streamer (see above); set before the hub enters the tree
var doc: Dictionary = {}
var pump: Node
var threat: Node
var special: TownSpecial
var pens: Node3D
var clues: Array = []
var stashes: Array = []

var _acc := 0.0
var _awake := true
var _active := false                # activated: the town's nodes exist
var _centre := Vector2.INF          # settlement centre and the reach of its places (kill gate), resolved on first use
var _reach := 0.0
var _inside: Dictionary = {}        # place id -> seconds until the next enter_area
var _places_cache: Dictionary = {}
var _places_age := 1000

static var prof := false            # QA: count the microseconds hubs spend in _process (tools_qa/perf/town_kit_perf.gd)
static var prof_usec := 0
static var prof_calls := 0
static var _lead: Node = null       # the hub that reports the town-independent `died {species}` once per kill


## Attaches one hub per town file. Returns the hubs. `gated` = the hubs sleep outside the settlement tier of the cell streamer
## (towns with a hand-made `special`, Thornfield, stay awake).
static func attach_all(parent: Node, gated := false) -> Array:
	var out: Array = []
	for id: String in TownData.ids():
		out.append(attach(parent, id, gated))
	return out


static func attach(parent: Node, town_id: String, gated := false) -> Node:
	var d := TownData.town(town_id)
	var path := String(d.get("hub", ""))
	var script: GDScript = load(path) if path != "" else load("res://scripts/world/town_kit/town_hub.gd")
	var h: Node = script.new()
	h.set("tid", town_id)
	h.set("gated", gated and String(d.get("special", "")) == "")
	parent.add_child(h)
	return h


func _ready() -> void:
	doc = TownData.town(tid)
	name = String(doc.get("hub_name", "TownHub_" + tid))
	if _lead == null or not is_instance_valid(_lead):
		_lead = self
	_acc = TICK * float(absi(hash(tid)) % 100) / 100.0          # staggered polls: 30 hubs never all poll in the same frame
	if Life != null:
		Life.region1_kill.connect(_on_kill)
		Life.inventory_changed.connect(_on_inventory_changed)
	if gated:
		_awake = false
		set_process(false)
		var s := TownPlaces.settlement(tid)
		if not s.is_empty():
			CellStreamer.shared().add_site(PROFILE, "town:" + tid, s["pos"], _on_tier)
		else:
			_activate()
			_set_awake(true)
		return
	_activate()


func _exit_tree() -> void:
	if _lead == self:
		_lead = null
	if gated:
		CellStreamer.shared().remove_site(PROFILE, "town:" + tid)


## The town's nodes, built once (immediately for an ungated hub, on the first wake for a gated one).
func _activate() -> void:
	if _active:
		return
	_active = true
	TownRoster.bind(tid)
	pump = load("res://scripts/quests/quest_pump.gd").attach(self)
	_register_quests(QuestHub.runner())
	var sp := String(doc.get("special", ""))
	special = (load(sp) as GDScript).new() if sp != "" else TownSpecial.new()
	clues = TownClues.build_clues(tid, self)
	stashes = TownClues.build_stashes(tid, self)
	pens = TownLivestock.build_pens(tid, self)
	special.build(self)
	if Life != null:
		TownRoster.seed_social_graph(Life.get("npc_social_graph"), WorldSim.SEED, tid)
	if gated:
		_build_threat.call_deferred()          # the den search (a few ms of terrain samples) takes the next frame, not this one
	else:
		_build_threat()


## The threat node: it places (or finds) the town's den, which scans the country around the town once.
func _build_threat() -> void:
	if threat != null or not is_inside_tree():
		return
	if not (doc.get("threat", {}) as Dictionary).is_empty():
		threat = TownThreat.new()
		threat.configure(tid)
		add_child(threat)
	special.after_threat(self)


func is_awake() -> bool:
	return _awake


func is_active() -> bool:
	return _active


## CellStreamer site callback: the settlement tier of this town changed.
func _on_tier(_id: Variant, tier: int, _old: int) -> void:
	_set_awake(tier != CellStreamer.Tier.UNLOADED)


func _set_awake(on: bool) -> void:
	if on == _awake and (not on or _active):
		return
	_awake = on
	if on:
		_activate()
		set_process(true)
		_places_age = PLACES_REFRESH
		_props_on(true)
	else:
		set_process(false)
		_inside.clear()
		_props_on(false)
		if threat != null:
			threat.call("sleep")


## Clue and stash props and the pens: shown and usable while awake, hidden and out of the interaction scan while asleep.
func _props_on(on: bool) -> void:
	for n: Variant in clues + stashes:
		if is_instance_valid(n):
			(n as Node3D).visible = on
			Interactable.set_active(n as Node, on)
	if pens != null:
		pens.visible = on


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
	var t0 := Time.get_ticks_usec() if prof else 0
	_acc += delta
	if _acc >= TICK:
		var dt := _acc
		_acc = 0.0
		poll(dt)
	if prof:
		prof_usec += Time.get_ticks_usec() - t0
		prof_calls += 1


## One poll step (tests call it directly with a stand-in player in group "player").
func poll(dt: float) -> void:
	if not _active:
		return
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


func _is_lead() -> bool:
	if _lead == null or not is_instance_valid(_lead) or not _lead.is_inside_tree():
		_lead = self
	return _lead == self


## Life's pack changed: the lead hub (one of them, not thirty) checks the open Collect objectives.
func _on_inventory_changed() -> void:
	if _is_lead():
		_emit_inventory()


## A creature fell: `died {actor: species}` (once, from the lead hub) and, near this town's places, `kill {target, place}` for each.
## The places are only resolved when the kill was within the reach of this town.
func _on_kill(species: String, where: Vector3) -> void:
	var bus := QuestBus.shared()
	if _is_lead():
		bus.emit_event(&"died", {"actor": species})
	var p := Vector2(where.x, where.z)
	if _centre == Vector2.INF:
		_resolve_reach()
	if _centre == Vector2.INF or p.distance_to(_centre) > _reach:
		return
	var list := TownPlaces.places(tid)
	for id: String in list:
		var pl: Dictionary = list[id]
		if id != tid and p.distance_to(pl["pos"]) <= float(pl["radius"]) + KILL_PAD:
			bus.emit_event(&"kill", {"target": species, "place": id, "amount": 1})


## The settlement centre and how far from it any place (plus the kill padding) reaches.
func _resolve_reach() -> void:
	var s := TownPlaces.settlement(tid)
	if s.is_empty():
		return
	_centre = s["pos"]
	_reach = 0.0
	var list := TownPlaces.places(tid)
	for id: String in list:
		var pl: Dictionary = list[id]
		_reach = maxf(_reach, _centre.distance_to(pl["pos"]) + float(pl["radius"]) + KILL_PAD)
