extends Node
## Realm events that happen IN THE WORLD (ACADEMY_PLAN "Guidance instead of cutscenes"): no
## cutscene, no map marker. When the realm has something to tell the player (a call-up from an
## employer or neighbour, the scouts' visit at nine, a graduation offer, trouble on a family
## trip), a person walks up, dialogue_ui opens with their offer and the choices go straight to
## the module API. A short event banner opens it and a notify hint says what to do next.
##
## Child of realm_presence.gd (its setup() adds this node). Cost model, nothing per frame:
##   * WorldSim.hour_changed  -> pick_next(): the next deliverable event (pure logic, testable);
##   * a 2 s Timer            -> deliver it when the player is free, walk the messenger (a Tween
##                               on one body), watch the dialogue, refresh the drill yard;
##   * hints                  -> region-1 tutorial_prompt_view (text-only "plain" prompts),
##                               shown once per hint id, dismissible with its x.
## Priority: family trouble, scout test, scout news, graduation offer, call-up (levy first),
## call-up report. A key is remembered in `delivered` so nothing is ever delivered twice;
## the state is saved through Region1State ("realm_encounters").

const PromptView := preload("res://scripts/region1/tutorial_prompt_view.gd")
const DrillYard := preload("res://scripts/world/drill_yard.gd")
const TravelRules := preload("res://scripts/world/travel_rules.gd")
const Crafting := preload("res://scripts/sim/crafting.gd")

const SCOUT_AGE := 9            ## education.gd SCOUT_AGE
const TICK := 2.0
const WALK_SPEED := 2.3
const RUN_SPEED := 4.4
const SPAWN_DIST := 15.0
const TALK_DIST := 2.4
const NEAR_BODY := 6.0          ## a villager this close can speak for a neighbour's message
const GIVE_UP_S := 45.0
const COOLDOWN_H := 1           ## game hours between two deliveries
const KEEP_DAYS := 40           ## delivered keys older than this are forgotten
const SQUARE_R := 70.0          ## "the village square" for the scouts' noon test
const NOON := [12, 17]
const HINT_SECONDS := 7.0
## Road events (docs/design/REALM_PLAN.md "Travel and world size"): a caravan, a traveller with news, a roadside camp or
## an ambush meets the player on the road. Paced by travel_rules.gd (ROAD_COOLDOWN_H game hours AND ROAD_MIN_DIST metres
## between two events, a small chance per tick scaled by the road's danger), so a long walk has a few meetings, not a stream.
const CARAVAN_STOCK := ["bread", "cheese", "jerky", "bandage", "waterskin", "tinderbox", "bedroll"]
const CARAVAN_MARKUP := 1.35
const MEAL_PRICE := 4
const CAMP_REST_H := 1.0

## One line each, short enough for a pill. The first time the event happens only.
const HINTS := {
	"first_callup": "Someone has work for you. Hear them out.",
	"first_training": "Anyone can train at the drill yard.",
	"scout_season": "Scouts gather at the village square at noon.",
	"first_job": "You have a job. Keep your shifts to be paid.",
}

const LOOK_BY_TEMPLATE := {"stolen_ore": "Blacksmith", "forge_rush": "Blacksmith", "missing_caravan": "Trader", "bandit_patrol": "Guard",
	"militia_levy": "Guard", "smugglers": "Trader", "relic_theft": "Monk", "escort_message": "Noble"}
const ROLE_BY_FROM := {"employer": "Employer", "neighbour": "Neighbour", "guild": "Guild", "authority": "Officer"}
const ENC_LOOK := {"bandits": "Bandit", "rebels": "Mercenary", "war": "Guard", "monsters": "Hunter", "road_closure": "Guard",
	"criminal_group": "Bandit", "corrupt_official": "Noble"}
const ENC_ROLE := {"bandits": "Highwayman", "rebels": "Rebel leader", "war": "Press-gang sergeant", "monsters": "Frightened carter",
	"road_closure": "Road warden", "criminal_group": "Gang boss", "corrupt_official": "Toll-keeper"}
const ENC_CHOICE := {"fight": "Fight", "flee": "Flee", "bargain": "Bargain", "hide": "Hide", "surrender": "Surrender", "wait": "Wait it out"}
const ENC_OUTCOME := {"safe": "You get through with your skin.", "paid": "The way is opened.", "delayed": "The road is clear again.",
	"robbed": "They strip what they can carry and are gone.", "injured": "Blood is spilled before it is over.",
	"separated": "It goes as badly as it can.", "killed": "Someone does not walk away from it."}
const ORG_LOOK := {"army": "Guard", "guild": "Trader", "noble_house": "Noble", "research": "Herbalist", "rift_expedition": "Hunter",
	"school": "Elder_Man", "government": "Noble", "sect": "Monk", "church": "Monk"}
const ORG_ROLE := {"army": "Army recruiting officer", "guild": "Guild representative", "noble_house": "Steward of a noble house",
	"research": "Research fellow", "rift_expedition": "Expedition master", "school": "Headmaster", "government": "Clerk of the Crown",
	"sect": "Sect elder", "church": "Almoner"}

var hud: Node
var hub_override: RefCounted = null      ## tests: a RealmHub instead of Life.realm
var delivered: Dictionary = {}           ## key -> day it was delivered
var hints_seen: Dictionary = {}          ## hint id -> true
var yard: Node3D

var _timer: Timer
var _pending: Dictionary = {}
var _s: Dictionary = {}                  ## the live session (empty = nothing happening)
var _next_ok := 0                        ## abs game hour before which nothing new is delivered
var _tween: Tween
var _view: Control
var _hint_queue: Array[String] = []
var _hint_until := 0.0
var _hint_shown := ""
var _spawn_fail := 0
var _road_ok := 0                        ## abs game hour before which no road event happens
var _road_last := Vector2.INF            ## where the last road event happened


func setup(p_hud: Node) -> void:
	hud = p_hud


func _ready() -> void:
	name = "RealmEncounters"
	add_to_group("realm_encounters")      # Life.camp_here finds it to give a night ambush a body
	WorldSim.hour_changed.connect(_on_hour)
	_timer = Timer.new()
	_timer.wait_time = TICK
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_timer.start()
	Region1State.register(&"realm_encounters", snapshot, restore, 1)
	if Life.has_signal("employment_changed"):
		Life.employment_changed.connect(_on_employment)
	yard = DrillYard.new()
	add_child(yard)
	yard.setup(hud, self, 0)


func _exit_tree() -> void:
	if Region1State.has(&"realm_encounters"):
		Region1State.unregister(&"realm_encounters")


# --- save -------------------------------------------------------------------------------

func snapshot() -> Dictionary:
	return {"delivered": delivered.duplicate(), "hints": hints_seen.duplicate(), "road_ok": _road_ok,
		"road_last": [_road_last.x, _road_last.y] if _road_last != Vector2.INF else []}


func restore(d: Dictionary) -> void:
	delivered = {}
	hints_seen = {}
	var dv: Variant = d.get("delivered", {})
	if dv is Dictionary:
		for k: Variant in dv:
			delivered[String(k)] = int(dv[k])
	var hs: Variant = d.get("hints", {})
	if hs is Dictionary:
		for k: Variant in hs:
			hints_seen[String(k)] = true
	_road_ok = int(d.get("road_ok", 0))
	var rl: Variant = d.get("road_last", [])
	_road_last = Vector2(float((rl as Array)[0]), float((rl as Array)[1])) if rl is Array and (rl as Array).size() == 2 else Vector2.INF
	_pending = {}
	_s = {}


# --- what is there to deliver -----------------------------------------------------------

func _mod(mod_name: String) -> Variant:
	var hub: Variant = hub_override
	if hub == null:
		hub = Life.get("realm")
	return hub.mod(mod_name) if hub != null else null


func _abs_hour() -> int:
	return WorldSim.day * 24 + int(WorldSim.time_of_day)


func is_delivered(key: String) -> bool:
	return delivered.has(key)


## The next event worth a visit, or {}. Pure: nothing is changed. ctx (all optional, for tests):
## day, hour, age, near_square (bool).
func pick_next(ctx: Dictionary = {}) -> Dictionary:
	var day := int(ctx.get("day", WorldSim.day))
	var hour := int(ctx.get("hour", int(WorldSim.time_of_day)))
	var hh: Variant = _mod("household")
	if hh != null:
		var enc: Dictionary = hh.pending_encounter()
		if not enc.is_empty():
			var key := "enc:%d:%d:%s" % [int(enc.get("day", 0)), int(enc.get("hour", 0)), String(enc.get("kind", ""))]
			if not delivered.has(key):
				return {"kind": "encounter", "key": key, "enc": enc}
	var edu: Variant = _mod("education")
	if edu != null:
		var age := int(ctx.get("age", Life.age() if Life.get("life_path") != null else 9))
		if age >= SCOUT_AGE and age <= SCOUT_AGE + 2 and not edu.is_student():
			var scouts: Array = edu.scouts_present(day)
			if not scouts.is_empty():
				var near_sq := bool(ctx.get("near_square", _near_square()))
				if hour >= int(NOON[0]) and hour <= int(NOON[1]) and near_sq:
					var sc: Dictionary = scouts[0]
					var tk := "scouttest:%s:%d" % [sc["id"], day]
					if not delivered.has(tk):
						return {"kind": "scout_test", "key": tk, "scout": sc}
				if hour >= 7:
					var nk := "scoutnews:%d" % int((edu.season as Dictionary).get("start_day", 0))
					if not delivered.has(nk):
						return {"kind": "scout_news", "key": nk, "scouts": scouts}
		for o: Dictionary in edu.graduation_offers():
			var gk := "grad:%s" % o["id"]
			if not delivered.has(gk):
				return {"kind": "grad", "key": gk, "offer": o}
	var cu: Variant = _mod("callups")
	if cu != null:
		var open: Array = []
		for o: Dictionary in cu.offers():
			if not bool(o["delivered"]) and not delivered.has("cu:%s" % o["id"]):
				open.append(o)
		if not open.is_empty():
			open.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var la := String(a["template"]) == "militia_levy"
				var lb := String(b["template"]) == "militia_levy"
				if la != lb:
					return la
				return int(a["deadline"]) < int(b["deadline"]))
			return {"kind": "callup", "key": "cu:%s" % open[0]["id"], "offer": open[0]}
		for o: Dictionary in cu.active():
			var rk := "cur:%s:%d" % [o["id"], day]
			if int(o["accepted_day"]) >= 0 and day > int(o["accepted_day"]) and not delivered.has(rk):
				return {"kind": "callup_report", "key": rk, "offer": o}
	if bool(ctx.get("roads", true)):
		return road_event(ctx)
	return {}


## The nearest bandit camp or hideout (metres), cached: the sites never change after WorldGen.setup.
static var _bandit_sites: Array[Vector2] = []
static var _bandit_sig := -1


static func bandit_distance(p: Vector2) -> float:
	if _bandit_sig != WorldGen.sites.size():
		_bandit_sig = WorldGen.sites.size()
		_bandit_sites.clear()
		for site: Dictionary in WorldGen.sites:
			if String(site.get("kind", "")) in ["bandit_camp", "hideout"]:
				_bandit_sites.append(site["pos"])
	var best := 1.0e9
	for b: Vector2 in _bandit_sites:
		best = minf(best, p.distance_to(b))
	return best


## A road event for the player's position, or {}. Pure given ctx (all optional, for tests): pos, abs_hour, hour, day,
## road_ok, last_pos, road_info {dist, tier}, danger {total, sources}, caravans (Array of {name, dest}), bandit_dist,
## near_town, rolls [gate, pick, variant].
func road_event(ctx: Dictionary = {}) -> Dictionary:
	var pos := Vector2.INF
	if ctx.has("pos"):
		pos = ctx["pos"]
	else:
		var pl := _player()
		if pl == null or bool(pl.get("dead")):
			return {}
		pos = Vector2(pl.global_position.x, pl.global_position.z)
	if int(ctx.get("abs_hour", _abs_hour())) < int(ctx.get("road_ok", _road_ok)):
		return {}
	var last: Vector2 = ctx.get("last_pos", _road_last)
	if last != Vector2.INF and pos.distance_to(last) < TravelRules.ROAD_MIN_DIST:
		return {}
	var ri: Dictionary = ctx["road_info"] if ctx.has("road_info") else WorldGen.road_info(pos.x, pos.y)
	if float(ri["dist"]) > TravelRules.ROAD_MAX_DIST:
		return {}
	var near_town := false
	var near: Dictionary = WorldGen.nearest_settlement(pos)
	if not near.is_empty():
		var dn := pos.distance_to(near["pos"])
		if dn < float(near["radius"]) * 1.6:
			return {}                # never inside a settlement
		near_town = dn < 1200.0
	if ctx.has("near_town"):
		near_town = bool(ctx["near_town"])
	var danger: Dictionary = ctx["danger"] if ctx.has("danger") else {}
	if not ctx.has("danger"):
		var eco: Variant = _mod("ecology")
		if eco != null and eco.has_method("danger_at"):
			danger = eco.danger_at(pos)
	var caravans: Array = []
	if ctx.has("caravans"):
		caravans = ctx["caravans"]
	else:
		var ent: Variant = _mod("enterprise")
		if ent != null and ent.has_method("list_caravans"):
			for c: Dictionary in ent.list_caravans():
				if String(c.get("state", "")) == "travel" and (ent.caravan_pos(c) as Vector2).distance_to(pos) < 900.0:
					caravans.append({"name": String(c.get("name", "A caravan")), "dest": _settlement_name(int(c.get("dest", -1)))})
	var day := int(ctx.get("day", WorldSim.day))
	var hour := int(ctx.get("hour", int(WorldSim.time_of_day)))
	var tier := String(ri["tier"])
	var bd := float(ctx["bandit_dist"]) if ctx.has("bandit_dist") else bandit_distance(pos)
	var weights := TravelRules.road_weights({"tier": tier, "danger": float(danger.get("total", 0.0)), "bandit_dist": bd,
		"caravans": caravans.size(), "near_town": near_town, "hour": hour})
	var rolls: Array = ctx.get("rolls", [randf(), randf(), randf()])
	var sub := TravelRules.pick_road_kind(weights, float(rolls[0]), float(rolls[1]))
	if sub == "":
		return {}
	var key := "road:%d:%d:%s" % [day, hour, sub]
	if delivered.has(key):
		return {}
	var sources: Array = danger.get("sources", [])
	var species := String((sources[0] as Dictionary).get("species", "")) if not sources.is_empty() else ""
	var e := {"kind": "road", "sub": sub, "key": key, "pos": pos, "tier": tier, "danger": float(danger.get("total", 0.0)),
		"variant": int(float(rolls[2]) * 1000.0), "near_town": near_town}
	match sub:
		"caravan":
			if not caravans.is_empty():
				e["caravan"] = caravans[int(float(rolls[2]) * caravans.size()) % caravans.size()]
		"ambush":
			var beasts := species != "" and float(danger.get("total", 0.0)) >= 12.0 and bd > 700.0 and not species in ["clan"]
			e["foe"] = "beasts" if beasts else "bandits"
			e["species"] = species if beasts else ""
			e["toll"] = TravelRules.ambush_toll(float(danger.get("total", 0.0)))
	return e


func _settlement_name(sid: int) -> String:
	return String(WorldGen.settlements[sid]["name"]) if sid >= 0 and sid < WorldGen.settlements.size() else "the next town"


func _near_square() -> bool:
	var pl := _player()
	if pl == null or WorldGen.settlements.is_empty():
		return false
	var c: Vector2 = WorldGen.settlements[0]["pos"]
	return Vector2(pl.global_position.x, pl.global_position.z).distance_to(c) <= SQUARE_R


# --- driving ----------------------------------------------------------------------------

func _on_hour(_h: int) -> void:
	var cut := WorldSim.day - KEEP_DAYS
	for k: String in delivered.keys():
		if int(delivered[k]) < cut:
			delivered.erase(k)
	if _s.is_empty():
		_pending = pick_next()


func _on_tick() -> void:
	var pl := _player()
	if pl != null and yard != null:
		yard.refresh(Vector2(pl.global_position.x, pl.global_position.z))
		_near_yard_hint(pl)
	_pump_hints()
	if not _s.is_empty():
		_watch_session()
		return
	if _pending.is_empty():
		_pending = pick_next()
	if _pending.is_empty() or _abs_hour() < _next_ok or not _player_free():
		return
	var entry := _pending
	_pending = {}
	if String(entry["kind"]) == "road":
		if _road_stale(entry):
			return                      # the player has walked on: the road offers something else later
		if String(entry["sub"]) == "ambush" and String(entry.get("foe", "")) == "beasts":
			_road_beasts(entry)
			return
	if not _begin(entry):
		_pending = entry     # no room to arrive yet: try again on the next tick


## A road event is only for where the player was when it rolled.
func _road_stale(entry: Dictionary) -> bool:
	var pl := _player()
	if pl == null:
		return true
	var pp := Vector2(pl.global_position.x, pl.global_position.z)
	return pp.distance_to(entry["pos"]) > 140.0 or float(WorldGen.road_info(pp.x, pp.y)["dist"]) > TravelRules.ROAD_MAX_DIST * 1.5


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null


## True while an NPC is walking up / talking (work_spots hides its job prompt meanwhile).
func in_session() -> bool:
	return not _s.is_empty()


func _player_free() -> bool:
	var pl := _player()
	if pl == null or bool(pl.get("dead")) or get_tree().paused:
		return false
	for n in get_tree().get_nodes_in_group("work_spots"):     # never talk over a job widget
		if n.has_method("is_modal") and bool(n.is_modal()):
			return false
	if hud != null and hud.has_method("is_menu_open") and bool(hud.is_menu_open()):
		return false
	var door := InteriorDoor.active
	if door != null and door.interior != null and is_instance_valid(door.interior):
		return false
	for n in get_tree().get_nodes_in_group("team1"):    # never walk up in the middle of a fight
		var e := n as Node3D
		if e != null and e.is_visible_in_tree() and e.global_position.distance_to(pl.global_position) < 22.0:
			return false
	return true


func _ctx() -> Dictionary:
	var ctx := {"life": Life}
	var pl := _player()
	if pl != null:
		ctx["player_pos"] = Vector2(pl.global_position.x, pl.global_position.z)
	var war: Variant = Life.get("war")
	if war != null and war.has_method("is_at_war"):
		ctx["at_war"] = war.is_at_war()
	return ctx


# --- the messenger ----------------------------------------------------------------------

func _look_of(entry: Dictionary) -> String:
	match String(entry["kind"]):
		"encounter": return String(ENC_LOOK.get(String((entry["enc"] as Dictionary).get("kind", "")), "Bandit"))
		"scout_test": return "Noble" if float((entry["scout"] as Dictionary).get("noble_pressure", 0.0)) > 0.15 else "Guard"
		"scout_news": return "Elder_Man"
		"road": return _road_look(entry)
		"grad": return String(ORG_LOOK.get(String((entry["offer"] as Dictionary)["org"]), "Guard"))
		_: return String(LOOK_BY_TEMPLATE.get(String((entry["offer"] as Dictionary)["template"]), "Rogue_Hooded"))


func _borrowable(entry: Dictionary) -> Node3D:
	if not String(entry["kind"]) in ["callup", "callup_report", "scout_news"]:
		return null
	var pl := _player()
	for n in get_tree().get_nodes_in_group("villager"):
		var v := n as Node3D
		if v != null and v.is_visible_in_tree() and v.global_position.distance_to(pl.global_position) <= NEAR_BODY:
			return v
	return null


static func _model_of(n: Node) -> Node3D:
	for c in n.get_children():
		if c is Node3D and not (c is CollisionShape3D) and not c.find_children("*", "Skeleton3D", true, false).is_empty():
			return c as Node3D
	return null


## The session's NPC body, or null when it is gone (a freed object cannot be cast with `as`).
func _body() -> Node3D:
	var b: Variant = _s.get("body")
	return b as Node3D if is_instance_valid(b) else null


## Starts one delivery. Returns false when no ground to arrive from was found (retry later).
func _begin(entry: Dictionary) -> bool:
	var pl := _player()
	if pl == null:
		return false
	var borrowed := _borrowable(entry)
	var look := _look_of(entry)
	_s = {"entry": entry, "state": "walking", "look": look, "line": "", "opts": [], "next": "", "borrowed": borrowed != null, "body": null, "t": 0.0}
	if borrowed != null:
		_s["body"] = _model_of(borrowed)
		_arrive()
		return true
	var pp := Vector2(pl.global_position.x, pl.global_position.z)
	var hurried := String(entry["kind"]) == "encounter" or (String(entry["kind"]) == "road" and String(entry.get("sub", "")) == "ambush")
	var at := _find_spawn(pl, pp, 12.0 if hurried else SPAWN_DIST)
	if at == Vector2.INF:
		_spawn_fail += 1
		if _spawn_fail < 4:
			_s = {}
			return false
		at = pp + Vector2(0, SPAWN_DIST * 0.6)       # nowhere clear after a few tries: appear close
	_spawn_fail = 0
	var body := Assets.character(look, 1.75, [])
	if body == null:
		_s = {}
		return false
	add_child(body)
	body.global_position = Vector3(at.x, WorldGen.height(at.x, at.y), at.y)
	_play(body, ["Walk", "Walking_A"])
	_s["body"] = body
	_s["speed"] = RUN_SPEED if hurried else WALK_SPEED
	_s["last"] = 0.0
	_tween = create_tween()
	_tween.tween_method(_step, 0.0, GIVE_UP_S, GIVE_UP_S)
	return true


## A dry spot `dist` metres out with a clear line to the player, preferring the way the camera looks.
func _find_spawn(pl: Node3D, pp: Vector2, dist: float) -> Vector2:
	var fwd := Vector2(0, -1)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var f := -cam.global_transform.basis.z
		fwd = Vector2(f.x, f.z).normalized() if Vector2(f.x, f.z).length() > 0.01 else fwd
	var space := pl.get_world_3d().direct_space_state
	var base := atan2(fwd.y, fwd.x)
	for i in 12:
		var a := base + (float(i + 1) / 2 if i % 2 == 0 else -float(i + 1) / 2) * 0.5236
		var q := pp + Vector2(cos(a), sin(a)) * dist
		if WorldGen.is_water(q.x, q.y) or WorldGen.near_water(q.x, q.y, 2.0):
			continue
		var from := Vector3(q.x, WorldGen.height(q.x, q.y) + 1.4, q.y)
		var query := PhysicsRayQueryParameters3D.create(from, pl.global_position + Vector3.UP * 1.4, 1)
		if space.intersect_ray(query).is_empty():
			return q
	return Vector2.INF


func _play(body: Node3D, names: Array) -> void:
	var ap := Assets.animation_player(body)
	if ap == null:
		return
	for n: String in names:
		if ap.has_animation(n):
			var anim := ap.get_animation(n)
			if anim != null and anim.loop_mode == Animation.LOOP_NONE:
				anim.loop_mode = Animation.LOOP_LINEAR
			ap.play(n)
			return
	var all := ap.get_animation_list()
	if not all.is_empty():
		ap.play(all[0])


## Tween step: walk toward wherever the player is now (they may keep moving).
func _step(t: float) -> void:
	var body := _body()
	var pl := _player()
	if _s.is_empty() or _s["state"] != "walking" or body == null or not is_instance_valid(body) or pl == null:
		return
	var dt := t - float(_s["last"])
	_s["last"] = t
	var to := Vector2(pl.global_position.x - body.global_position.x, pl.global_position.z - body.global_position.z)
	if to.length() <= TALK_DIST:
		_tween.kill()
		_arrive()
		return
	if t >= GIVE_UP_S - 0.05:
		_abort()
		return
	var d := to.normalized()
	var p := Vector2(body.global_position.x, body.global_position.z) + d * float(_s["speed"]) * dt
	body.global_position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)
	body.rotation.y = atan2(d.x, d.y)


func _abort() -> void:
	var body := _body()
	if body != null and is_instance_valid(body) and not bool(_s.get("borrowed", false)):
		body.queue_free()
	_s = {}
	_pending = {}


func _arrive() -> void:
	var body := _body()
	var pl := _player()
	if body != null and is_instance_valid(body) and pl != null and not bool(_s["borrowed"]):
		var to := pl.global_position - body.global_position
		body.rotation.y = atan2(to.x, to.z)
		_play(body, ["Idle_Talking", "Idle"])
	_s["state"] = "talking"
	_s["t_open"] = Time.get_ticks_msec() / 1000.0
	var entry: Dictionary = _s["entry"]
	delivered[String(entry["key"])] = WorldSim.day
	if String(entry["kind"]) == "road":
		_road_done(entry)
	_open(entry)
	if hud != null and hud.has_method("show_menu") and not _s.is_empty():
		hud.show_menu(_page)


func _watch_session() -> void:
	if String(_s.get("state", "")) != "talking" or hud == null:
		return
	var open: bool = hud.has_method("is_menu_open") and bool(hud.is_menu_open())
	# Another menu (a workplace, a shop) can replace the conversation: then we are done, and we
	# must not close what is on screen now.
	var src: Variant = hud.get("_menu_source")
	var hijacked: bool = src is Callable and (src as Callable).is_valid() and src != Callable(self, "_page")
	var stale := Time.get_ticks_msec() / 1000.0 - float(_s.get("t_open", 0.0)) > 300.0
	if not open or hijacked or stale:
		_finish(open and not hijacked)     # the player walked out: the offer stays open


func _finish(close_menu := true) -> void:
	if close_menu and hud != null and hud.has_method("is_menu_open") and bool(hud.is_menu_open()):
		hud.close_menu()
	var nxt := String(_s.get("next", ""))
	if nxt != "" and hud != null and hud.has_method("notify"):
		hud.notify("quest", "What next", nxt)
	var body := _body()
	var borrowed := bool(_s.get("borrowed", false))
	var hint_id := String(_s.get("hint", ""))
	_s = {}
	_next_ok = _abs_hour() + COOLDOWN_H
	if body != null and is_instance_valid(body) and not borrowed:
		_walk_off(body)
	if hint_id != "":
		hint(hint_id)


## The messenger turns and walks away, then is freed: no lingering bodies.
func _walk_off(body: Node3D) -> void:
	var pl := _player()
	if pl == null:
		body.queue_free()
		return
	var away := Vector2(body.global_position.x - pl.global_position.x, body.global_position.z - pl.global_position.z)
	away = away.normalized() if away.length() > 0.01 else Vector2(0, 1)
	_play(body, ["Walk", "Walking_A"])
	body.rotation.y = atan2(away.x, away.y)
	var from := Vector2(body.global_position.x, body.global_position.z)
	var tw := body.create_tween()
	tw.tween_method(_walk_off_step.bind(body, from, away), 0.0, 1.0, 9.0)
	tw.tween_callback(body.queue_free)


func _walk_off_step(k: float, body: Node3D, from: Vector2, away: Vector2) -> void:
	if is_instance_valid(body):
		var p := from + away * k * 16.0
		body.global_position = Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


# --- dialogue ---------------------------------------------------------------------------

func _page() -> Dictionary:
	if _s.is_empty():
		return {"title": "", "body": "", "options": []}
	var body := _body()
	return {"title": String(_s["speaker"]), "body": String(_s["line"]), "options": _s["opts"],
		"speaker": String(_s["speaker"]), "role": String(_s["role"]), "line": String(_s["line"]),
		"relationship": "", "rel_value": 0.0, "portrait_key": "rx_%s" % String((_s["entry"] as Dictionary)["key"]),
		"model": body if body != null and is_instance_valid(body) else null, "look": String(_s["look"])}


func _say(line: String, opts: Array) -> void:
	_s["line"] = line
	_s["opts"] = opts


func _end(msg := "") -> String:
	_finish()
	return msg


func _banner(kind: String, title: String, sub: String, kicker := "") -> void:
	if hud != null and hud.has_method("show_event"):
		hud.show_event(kind, title, sub, kicker)


## Opens the page for an entry: speaker, first line, choices, banner.
func _open(entry: Dictionary) -> void:
	match String(entry["kind"]):
		"callup": _open_callup(entry["offer"], false)
		"callup_report": _open_callup(entry["offer"], true)
		"scout_news": _open_scout_news(entry)
		"scout_test": _open_scout_test(entry["scout"])
		"grad": _open_grad(entry["offer"])
		"encounter": _open_encounter(entry["enc"])
		"road": _open_road(entry)


# call-ups ----

static func _strip_speaker(text: String) -> String:
	var i := text.find(": \"")
	var t := text.substr(i + 2) if i > 0 and i < 40 else text
	return t.trim_prefix("\"").trim_suffix("\"")


func _open_callup(o: Dictionary, report: bool) -> void:
	var cu: Variant = _mod("callups")
	_s["speaker"] = String(o["npc_name"])
	_s["role"] = String(ROLE_BY_FROM.get(String(o["from"]), "Neighbour"))
	if report:
		_say("\"Well? Have you dealt with it? %s\"" % ("I am still waiting on word." if int(o["deadline"]) <= WorldSim.day else "There is still time."),
			[["Set out now (3 hours)", _cu_go.bind(String(o["id"]))], ["Not yet", _end]])
		return
	cu.mark_delivered(String(o["id"]))
	var levy := String(o["template"]) == "militia_levy"
	_banner("quest", "The Muster" if levy else "A Request", String(o["place"]), "%s asks for you" % String(o["npc_name"]))
	_say(_strip_speaker(String(o["text"])), _cu_opts(o))
	_s["hint"] = "first_callup"


func _cu_opts(o: Dictionary) -> Array:
	var id := String(o["id"])
	return [["Accept", _cu_accept.bind(id)], ["Decline", _cu_decline.bind(id)], ["Ask more", _cu_more.bind(id)], ["Not now", _end]]


func _cu_more(id: String) -> String:
	var o: Dictionary = _mod("callups").offer(id)
	var d := int(o.get("deadline", 0)) - WorldSim.day
	var danger := "It should be safe enough." if float(o["danger"]) < 0.2 else ("There is some risk." if float(o["danger"]) < 0.4 else "It will be dangerous.")
	var who := "I need someone who can fight." if String(o["role"]) == "combat" else "I only need an extra pair of hands."
	var pay := int((o["reward"] as Dictionary)["gold"])
	_say("\"%s I can pay %d gold and you will have my thanks. %s It cannot wait past %s.\"" % [who, pay, danger,
		"today" if d <= 0 else ("tomorrow" if d == 1 else "%d days" % d)], _cu_opts(o))
	return ""


func _cu_accept(id: String) -> String:
	var res: Dictionary = _mod("callups").accept(id)
	if not bool(res.get("ok", false)):
		_say("\"%s\"" % String(res.get("reason", "Too late, I am afraid.")), [["Farewell", _end]])
		return ""
	var o: Dictionary = res["offer"]
	_say("\"Good. I knew I could ask you. Give it a day, then come and tell me how it went.\"", [["Farewell", _end]])
	_s["next"] = "Do what %s asked in %s. They will look for you tomorrow." % [o["npc_name"], o["place"]]
	_banner("quest", "Request Accepted", String(o["place"]), String(o["npc_name"]))
	return ""


func _cu_decline(id: String) -> String:
	_mod("callups").decline(id)
	_say("\"I understand. I will ask someone else.\"", [["Farewell", _end]])
	return ""


## The errand itself: three hours pass and how it went depends on what you can do.
func _cu_go(id: String) -> String:
	var cu: Variant = _mod("callups")
	var edu: Variant = _mod("education")
	var o: Dictionary = cu.offer(id)
	if o.is_empty() or String(o["status"]) != "accepted":
		_say("\"It is settled already.\"", [["Farewell", _end]])
		return ""
	var ability := float(edu.fighting_ability()) if edu != null else 0.0
	var need := 25.0 * float(o["danger"]) * 2.0 if String(o["role"]) == "combat" else 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([WorldSim.SEED, id, WorldSim.day])
	var p := clampf(0.7 + (ability - need) / 100.0 - float(o["danger"]) * 0.35, 0.15, 0.97)
	WorldSim.advance_hours(3.0)
	if rng.randf() < p:
		var res: Dictionary = cu.complete(id, 0.85 + 0.3 * rng.randf())
		var gold := int(res.get("gold", 0))
		_say("\"You did it. Here, %d gold, and my thanks.\"" % gold, [["Farewell", _end]])
		if hud != null:
			hud.notify("quest", "Request Done", "%d gold, %s trusts you more" % [gold, o["npc_name"]])
	else:
		cu.fail(id)
		_say("\"It went badly, then. I will not forget who tried, but I will not forget the loss either.\"", [["Farewell", _end]])
		if hud != null:
			hud.notify("quest", "Request Failed", String(o["npc_name"]))
	return ""


# scouts ----

func _open_scout_news(entry: Dictionary) -> void:
	var edu: Variant = _mod("education")
	var names := PackedStringArray()
	for sc: Dictionary in entry["scouts"]:
		var inst: Dictionary = edu.institution(String(sc["inst"]))
		names.append(String(inst.get("name", "an academy")))
	_s["speaker"] = "Old Bram"
	_s["role"] = "Village elder"
	_banner("location", "Scout Season", String(WorldGen.settlements[0]["name"]), "Recruiters have come")
	_say("\"Have you heard, child? Recruiters from %s are in the village. At noon they gather everyone your age in the square. Stand up straight and show them what you have.\"" % ", ".join(names),
		[["I will be there", _end], ["Not interested", _end]])
	_s["next"] = "Scouts gather at the village square at noon."
	_s["hint"] = "scout_season"


func _open_scout_test(sc: Dictionary) -> void:
	var edu: Variant = _mod("education")
	var inst: Dictionary = edu.institution(String(sc["inst"]))
	_s["speaker"] = String(sc["name"])
	_s["role"] = "%s, %s" % [sc["title"], inst.get("name", "")]
	_banner("location", "The Scouts' Test", String(inst.get("name", "")), String(sc["name"]))
	_say("\"You there. I am testing the children of the village today. A few questions, a few tasks; nothing you cannot do. Will you sit the test?\"",
		[["Take the test", _sc_test.bind(String(sc["id"]))], ["Ask more", _sc_more.bind(String(sc["id"]))], ["Not today", _end]])


func _sc_more(sid: String) -> String:
	_say("\"I look for nerve and quick wits as much as strength. Family name matters less than some would have you believe. Well?\"",
		[["Take the test", _sc_test.bind(sid)], ["Not today", _end]])
	return ""


func _sc_test(sid: String) -> String:
	var edu: Variant = _mod("education")
	var res: Dictionary = edu.attend(sid)
	if not bool(res.get("ok", false)):
		_say("\"%s\"" % String(res.get("reason", "Not now.")), [["Farewell", _end]])
		return ""
	var r: Dictionary = res["result"]
	var inst_id := String(r["inst"])
	match String(r["verdict"]):
		"selected":
			_say("\"Well done. You did better than most. There is a place for you at my school, if you want it.\"",
				[["Accept the place", _sc_take.bind(inst_id)], ["Think it over", _end]])
			_s["next"] = "The place stays open while the scout is in the village."
		"waitlist":
			_say("\"Close, very close. I cannot promise a place, but I will remember your name.\"", [["Farewell", _end]])
		_:
			_say("\"Not this year, I am afraid. It is no shame; there are other roads to a good school.\"", [["Farewell", _end]])
			_s["next"] = "Other doors open later: private teachers, sponsors, smaller schools."
	return ""


func _sc_take(inst_id: String) -> String:
	var edu: Variant = _mod("education")
	var res: Dictionary = edu.apply(inst_id, "scout", _ctx())
	if bool(res.get("ok", false)):
		var inst: Dictionary = edu.institution(inst_id)
		_say("\"Then it is settled. Pack your things; you will be sent for.\"", [["Farewell", _end]])
		_s["next"] = "Your place at %s is settled. Say your goodbyes." % String(inst.get("name", "the school"))
		_banner("quest", "A Place Won", String(inst.get("name", "")), "Admitted")
	else:
		_say("\"%s\"" % String(res.get("reason", "Something is wrong with the papers.")), [["Farewell", _end]])
	return ""


# graduation ----

func _open_grad(o: Dictionary) -> void:
	_s["speaker"] = String(ORG_ROLE.get(String(o["org"]), "Recruiter"))
	_s["role"] = "Recruiter"
	_banner("quest", "An Offer", String(o["role"]), "You are wanted")
	_say("\"Your name is known. We would have you as our %s, at %d gold a week. You are free to refuse; others will ask.\"" % [o["role"], int(o["wage"])], _grad_opts(o))


func _grad_opts(o: Dictionary) -> Array:
	var id := String(o["id"])
	return [["Accept", _grad_accept.bind(id)], ["Decline", _grad_refuse.bind(id)], ["Ask more", _grad_more.bind(id)], ["Not now", _end]]


func _grad_more(id: String) -> String:
	for o: Dictionary in _mod("education").graduation_offers():
		if String(o["id"]) == id:
			_say("\"The post is yours for %d days. No one will think less of you for a farm or a forge instead; it is your choice.\"" % maxi(0, int(o["expires"]) - WorldSim.day), _grad_opts(o))
	return ""


func _grad_accept(id: String) -> String:
	var res: Dictionary = _mod("education").accept_graduation_offer(id)
	_say("\"%s\"" % ("Welcome. Report when you are ready." if bool(res.get("ok", false)) else String(res.get("reason", "Too late."))), [["Farewell", _end]])
	if bool(res.get("ok", false)):
		_s["next"] = String(res.get("reason", ""))
	return ""


func _grad_refuse(id: String) -> String:
	_mod("education").refuse_graduation_offer(id)
	_say("\"A pity. The door stays open if you change your mind.\"", [["Farewell", _end]])
	return ""


# family trouble ----

func _open_encounter(enc: Dictionary) -> void:
	var kind := String(enc.get("kind", "bandits"))
	_s["speaker"] = String(ENC_ROLE.get(kind, "Stranger"))
	_s["role"] = "On the road"
	_banner("quest", "Trouble on the Road", "", "The cart stops")
	var opts: Array = []
	for c: Variant in enc.get("choices", ["wait"]):
		opts.append([String(ENC_CHOICE.get(String(c), String(c).capitalize())), _enc_pick.bind(String(c))])
	_say(String(enc.get("text", "Something bars the way.")), opts)


func _enc_pick(choice: String) -> String:
	var hh: Variant = _mod("household")
	var res: Dictionary = hh.resolve_encounter(choice, _ctx())
	var lines: Array = res.get("messages", [])
	var out := String(ENC_OUTCOME.get(String(res.get("outcome", "safe")), ""))
	_say(" ".join(PackedStringArray([out] + lines.map(func(m: Variant) -> String: return String(m)))), [["Go on", _end]])
	return ""


# road events ----

## Pacing bookkeeping once a road event has fired (a session opened or beasts spawned).
func _road_done(entry: Dictionary) -> void:
	_road_ok = _abs_hour() + TravelRules.ROAD_COOLDOWN_H
	_road_last = entry["pos"]


func _road_look(entry: Dictionary) -> String:
	var v := int(entry.get("variant", 0))
	match String(entry.get("sub", "")):
		"caravan": return "Trader"
		"ambush": return "Bandit"
		"camp": return ["Hunter", "Innkeeper", "Barbarian"][v % 3]
		_: return ["Rogue_Hooded", "Hunter", "Elder_Man", "Herbalist"][v % 4]


func _news_line(pos: Vector2, salt: int) -> String:
	var nw: Variant = _mod("news")
	var line := ""
	if nw != null and nw.has_method("tavern_line_at"):
		line = String(nw.tavern_line_at(pos, salt))
	return line if line != "" else "Nothing much stirs on the roads this season, and that is news enough these days."


func _open_road(entry: Dictionary) -> void:
	var pos: Vector2 = entry["pos"]
	var v := int(entry.get("variant", 0))
	match String(entry["sub"]):
		"caravan":
			var c: Dictionary = entry.get("caravan", {})
			_s["speaker"] = String(c.get("name", ["Caravan master", "Wagon-boss", "Carter"][v % 3]))
			_s["role"] = "Merchant caravan"
			_banner("location", "Caravan on the Road", String(c.get("dest", "")), "Wagons halt")
			var bound := "bound for %s" % String(c["dest"]) if c.has("dest") else "heading down the road"
			_say("\"Well met, traveller. We are %s, and the road is long. We have a little to spare if you have coin, and we would hear how the road ahead looks.\"" % bound,
				[["Buy supplies", _rd_shop], ["Ask about the road", _rd_news.bind(v)], ["Safe travels", _end]])
		"news":
			_s["speaker"] = ["A weary traveller", "A packman", "A pilgrim", "A drover"][v % 4]
			_s["role"] = "On the road"
			_banner("location", "A Traveller", "Word from the road", "You are not alone")
			_say("\"Well met. You are the first soul I have seen since morning. %s\"" % _news_line(pos, v),
				[["Share a bite", _rd_share.bind(v)], ["Ask for more", _rd_news.bind(v + 1)], ["Farewell", _end]])
		"camp":
			_s["speaker"] = ["A camp-keeper", "A tinker", "A drover"][v % 3]
			_s["role"] = "Roadside camp"
			_banner("location", "A Roadside Camp", "Smoke between the trees", "A fire to rest by")
			_say("\"Fire is free to anyone who brings no trouble. Sit down. There is stew if you have a few coins.\"",
				[["Rest by the fire (1 hour)", _rd_rest], ["Hot meal (%d gold)" % MEAL_PRICE, _rd_meal], ["Hear the news", _rd_news.bind(v)], ["Move on", _end]])
		"ambush":
			var toll := int(entry.get("toll", 20))
			_s["speaker"] = "Highwayman"
			_s["role"] = "On the road"
			_banner("quest", "Ambush!", "Stand and deliver", "The road is not safe")
			_say("\"That is far enough. Your purse, or your blood on the road. %d gold will do.\"" % toll,
				[["Pay %d gold" % toll, _rd_pay.bind(toll)], ["Fight", _rd_fight.bind(3, 38.0)], ["Run", _rd_fight.bind(2, 62.0)]])


func _rd_news(salt: int) -> String:
	var pos: Vector2 = (_s["entry"] as Dictionary)["pos"]
	var sub := String((_s["entry"] as Dictionary)["sub"])
	_say("\"%s\"" % _news_line(pos, salt + 7), [["Thank you", _end]] if sub != "camp" else [["Thank you", _end], ["Rest by the fire (1 hour)", _rd_rest]])
	return ""


func _rd_share(_salt: int) -> String:
	if Life.count("bread") > 0 or Life.count("cheese") > 0:
		Life.take("bread" if Life.count("bread") > 0 else "cheese", 1)
		_say("\"Kind of you. Here, a tip for the road: keep to the stones after dark, and do not camp near a den.\"", [["Farewell", _end]])
	else:
		_say("\"You have little to share, and so do I. Walk well.\"", [["Farewell", _end]])
	return ""


func _rd_shop() -> String:
	var opts: Array = []
	for id: String in CARAVAN_STOCK:
		var price := _stock_price(id)
		if price > 0:
			opts.append(["%s  ·  %d gold" % [Crafting.item_name(id), price], _rd_buy.bind(id, price)])
	opts.append(["Never mind", _end])
	_say("\"Take your pick. I will not cheat you, much.\"  (You have %d gold.)" % Game.gold, opts)
	return ""


func _stock_price(id: String) -> int:
	var info := Crafting.item_info(id)
	if info.is_empty():
		return 0
	return maxi(2, int(ceil(float(info.get("price", 5)) * CARAVAN_MARKUP)))


func _rd_buy(id: String, price: int) -> String:
	if Game.gold < price:
		_say("\"Come back when you can afford it.\"", [["Look again", _rd_shop], ["Farewell", _end]])
		return ""
	Game.add_gold(-price)
	Life.give(id, 1)
	_say("\"Pleasure. Anything else?\"  (%d gold left.)" % Game.gold, [["Look again", _rd_shop], ["Farewell", _end]])
	return ""


func _rd_rest() -> String:
	WorldSim.advance_hours(CAMP_REST_H)
	Life.needs.rest = minf(100.0, Life.needs.rest + 8.0)
	Life.needs.changed.emit()
	var pl := _player()
	if pl != null and pl.get("stamina") != null:
		pl.set("stamina", 100.0)
	_say("\"There. Better. A hot fire does more than people think.\"", [["Thank them", _end]])
	return ""


func _rd_meal() -> String:
	if Game.gold < MEAL_PRICE:
		_say("\"Stew is four gold. You have less. Sit anyway.\"", [["Rest by the fire (1 hour)", _rd_rest], ["Move on", _end]])
		return ""
	Game.add_gold(-MEAL_PRICE)
	Life.needs.eat(38.0)
	_say("\"Eat. It is mostly beans and mostly hot.\"", [["Rest by the fire (1 hour)", _rd_rest], ["Move on", _end]])
	return ""


func _rd_pay(toll: int) -> String:
	if Game.gold < toll:
		_say("\"You have not got it? Then we take what you have, and the rest from your hide.\"",
			[["Fight", _rd_fight.bind(3, 30.0)], ["Run", _rd_fight.bind(2, 62.0)]])
		return ""
	Game.add_gold(-toll)
	_say("\"Wise. Off you go. We never saw you.\"", [["Go on", _end]])
	return ""


func _rd_fight(count: int, dist: float) -> String:
	var entry: Dictionary = _s["entry"]
	_spawn_bandits(entry["pos"], count, dist)
	_end()
	return ""


## Raiders of the existing RoadEvents node (the same squad as the camp ambush) appear just off the road.
func _spawn_bandits(pos: Vector2, count: int, _dist: float) -> void:
	var re: Node = get_tree().root.find_child("RoadEvents", true, false) if is_inside_tree() else null
	if re != null and re.has_method("force_ambush"):
		re.force_ambush(pos, count)


## A beast ambush from an ecology territory has no talking: the animals come out of the verge.
func _road_beasts(entry: Dictionary) -> void:
	_road_done(entry)
	delivered[String(entry["key"])] = WorldSim.day
	_banner("quest", "Something in the Trees", String(entry.get("species", "wolf")).replace("_", " ").capitalize(), "The road is not safe")
	_spawn_beasts(String(entry.get("species", "wolf")), entry["pos"], 2 + int(entry.get("danger", 0.0) / 40.0))


func _spawn_beasts(species: String, pos: Vector2, count: int) -> void:
	var look := {"troll": "bear", "wyvern": "bear", "bear": "bear", "corrupted_wolf": "wolf"}.get(species, species) as String
	if look not in ["wolf", "bear", "boar"]:
		look = "wolf"
	for i in count:
		var w := Wolf.new()
		w.species = look
		if species == "corrupted_wolf":
			w.scale = Vector3.ONE * 1.2
		w.home = pos
		w.territory = 90.0
		add_child(w)
		var a := randf() * TAU
		var q := pos + Vector2.from_angle(a) * randf_range(26.0, 40.0)
		w.global_position = Vector3(q.x, WorldGen.height(q.x, q.y), q.y)
		w.died.connect(func(dead_wolf: Wolf) -> void: Life.on_wolf_killed(dead_wolf.global_position, -1, ""))


## Life.camp_here: the night's ambush (bandits or beasts) arrives at the camp.
func on_camp(foe: String, species: String, _ctx: Dictionary) -> void:
	var pl := _player()
	if pl == null:
		return
	var pp := Vector2(pl.global_position.x, pl.global_position.z)
	_banner("quest", "Attack at Night!", "Raiders" if foe == "bandits" else species.replace("_", " ").capitalize(), "Your camp is found")
	if foe == "beasts":
		_spawn_beasts(species if species != "" else "wolf", pp, 3)
	else:
		_spawn_bandits(pp, 3, 35.0)
	_road_ok = _abs_hour() + TravelRules.ROAD_COOLDOWN_H
	_road_last = pp


## Life.camp_here: a traveller shared the fire (the news line goes to the notification pill).
func camp_visitor() -> void:
	var pl := _player()
	if pl == null or hud == null or not hud.has_method("notify"):
		return
	hud.notify("quest", "A traveller at the fire", _news_line(Vector2(pl.global_position.x, pl.global_position.z), WorldSim.day))


# --- hints (tutorial prompt view) -------------------------------------------------------

## Queue a one-time hint. Ignored if it was shown before or the player turned tips off.
func hint(id: String) -> void:
	if hints_seen.has(id) or not HINTS.has(id):
		return
	var dir: Variant = Region1TutorialDirector.main
	if dir != null and not bool(dir.enabled):
		return
	hints_seen[id] = true
	_hint_queue.append(id)


func _pump_hints() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _hint_shown != "":
		if now >= _hint_until:
			_hide_hint()
		return
	if _hint_queue.is_empty() or hud == null:
		return
	if hud.has_method("is_menu_open") and bool(hud.is_menu_open()):
		return                                   # never on top of a conversation
	var dir: Variant = Region1TutorialDirector.main
	if dir != null and dir.current != &"":
		return                                   # the region-1 tutorial has the floor
	if _view == null or not is_instance_valid(_view):
		_view = PromptView.new()
		_view.name = "RealmHints"
		hud.add_child(_view)
		_view.skip_pressed.connect(_hide_hint)
	var id: String = _hint_queue.pop_front()
	_hint_shown = id
	_hint_until = now + HINT_SECONDS
	_view.show_prompt(StringName(id), {"text_key": "", "text_en": String(HINTS[id]), "plain": true, "anchor": "center", "touch": ""})


func _hide_hint() -> void:
	if _view != null and is_instance_valid(_view):
		_view.hide_prompt(StringName(_hint_shown), &"done")
	_hint_shown = ""


func _near_yard_hint(pl: Node3D) -> void:
	if hints_seen.has("first_training") or yard.spot == Vector2.INF:
		return
	if Vector2(pl.global_position.x, pl.global_position.z).distance_to(yard.spot) < 14.0:
		hint("first_training")


func _on_employment() -> void:
	var careers: Variant = Life.get("careers")
	if careers != null and careers.is_employed():
		hint("first_job")
