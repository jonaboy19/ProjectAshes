extends Node
## Region 1 integration hub (packages C-H, C3, C4, C5, C6, C6b, C7, C8, C12). One node, created by
## main.gd after the world exists, that connects the pure Region 1 sims (scripts/region1/*) to the
## running game with as few edits to shared files as possible:
##
##   Wardlines (N1)   binds the frontier's runestone network, takes over its coverage (hook H3), puts a
##                    "read / carve / mend / link / relight" menu on every stone and the carve canvas;
##   Scar Tide (N2)   variants for the ecology (H4), the violet terrain mask (H5), burn / harvest / ward
##                    actions at the front, scar goods prices, outbreaks the story asks for;
##   Ember Legacy (N3) the three-card ember choice after a life, ancestor stones that power and greet;
##   Ashsight (N4)    flags the sites, lets the player kneel at the ashes of a raid (replay);
##   Story (C7)       r1_story_director.gd: the main quest as NPCs, dialogue, tracker and journal;
##   Tutorial (C8)    the contextual prompt bridge;
##   Audio (C12)      rune hum, ward and carve sounds, the story music cues.
##
## Everything here is optional at runtime: a module that is not registered (disabled in
## data/region1/modules.json) simply leaves its part of the game as it was.

const Places := preload("res://scripts/region1/region1_places.gd")
const SeasonsRef := preload("res://scripts/sim/seasons.gd")
const Director := preload("res://scripts/region1/r1_story_director.gd")
const CarveView := preload("res://scripts/region1/r1_carve_view.gd")
const FollowStation := preload("res://scripts/region1/r1_follow_station.gd")
const MapLayer := preload("res://scripts/region1/r1_map_layer.gd")
const HUM_PATH := "res://assets/audio/region1/ambience/sfx_r1_rune_hum_loop.ogg"
const ELDER_IDS := ["elder_glade", "elder_greyseam", "elder_highwatch", "elder_crownstead", "elder_elden"]
const ELDER_PREFIX := "Elder Stone ("
const STONE_REACH := 3.0
const FESTIVAL_MAP := {"planting": "planting", "midsummer": "midsummer_fair", "harvest": "harvest",
	"solstice": "winter_solstice", "kindling_night": "kindling_night"}
## Burning the Scar back needs one Sunstone Oil, or this much firewood.
const FIREWOOD_FOR_FIRE := 4
const BURN_RADIUS := 36.0
const HARVEST_RADIUS := 44.0

signal ember_offered(ember_id: int)

var main: Node
var hud: Node
var player: Node3D
var world: Node3D

var wl: Wardlines
var scar: Region1Sim
var el: EmberLegacy
var mem: AshMemory
var story: Node                  ## r1_story_director.gd
var tutorial: Region1TutorialBridge
var ash: AshsightController
var carve_view: Control
var rec := RuneGesture.new()
var map_layer: Control
var stone_station: Station
var scar_station: Station
var ash_station: Station
var parley_station: Station
var _parley_target := ""

var _net: RARunestoneNetwork
var _timer: Timer
var _scar_tex: ImageTexture
var _hum: Array[AudioStreamPlayer3D] = []
var _hum_stream: AudioStream
var _ember_done: Dictionary = {}     ## ember id -> true once offered
var _succession_noted: Dictionary = {}
var _tick_n := 0
var _carve_target := -1
var _staged: Dictionary = {}          ## story site -> true once a memory was staged there
var _pressed_rumour_day := -1


func setup(p_main: Node) -> void:
	main = p_main
	hud = main.get("hud")
	player = main.get("player")
	world = main.get("world")
	Places.clear()
	rec.register_state()
	wl = Region1State.sim(&"wardlines") as Wardlines
	scar = Region1State.sim(&"scar_tide")
	el = Region1State.sim(&"ember_legacy") as EmberLegacy
	mem = Region1State.sim(&"ash_memory") as AshMemory
	_bind_wardlines()
	_bind_scar()
	_bind_ember()
	_bind_ash()
	_build_ui()
	_build_story()
	_build_tutorial()
	_bind_audio()
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_timer.start()
	Frontier.day_advanced.connect(_on_day)
	if WorldSim.seasons != null:
		WorldSim.seasons.festival_started.connect(_on_festival)
	player.died.connect(_on_player_died)


func _exit_tree() -> void:
	if Frontier.runestones != null and Frontier.runestones.coverage_override.get_object() == wl:
		Frontier.runestones.coverage_override = Callable()
	if Frontier.ecology != null:
		Frontier.ecology.variant_override = Callable()


# =====================================================================================
# Wardlines (N1): hook H3 wiring
# =====================================================================================

## The five Elder Stones become real network stones next to their places (until the world layout adds
## dedicated sites); their names start with ELDER_PREFIX, which is how they are found again after a save.
func _ensure_elder_stones(net: RARunestoneNetwork) -> void:
	for id: String in ELDER_IDS:
		var r := Places.resolve(id)
		if r.is_empty():
			continue
		var nm2 := ELDER_PREFIX + _elder_label(id) + ")"
		var have := false
		for s: Dictionary in net.stones:
			if String(s["name"]) == nm2:
				have = true
				break
		if not have:
			var s := net.add_stone(r["pos"], 240.0, -1, nm2)
			s["elder"] = true


## Road and anchor stones the story names (the Miller's Stone, the Silverford test stone, the edge anchor) become
## real network stones next to their places when the world has none within 70 m. They are found again after a
## save by name, exactly like the Elder Stones, so the stone list is the same on every load.
func _ensure_story_stones(net: RARunestoneNetwork) -> void:
	for spec: Dictionary in Places.story_stone_specs():
		var have := false
		for s: Dictionary in net.stones:
			if String(s["name"]) == String(spec["name"]) or (not bool(spec["force"]) and not String(s["name"]).begins_with(ELDER_PREFIX) and (s["pos"] as Vector2).distance_to(spec["pos"]) < 70.0):
				have = true
				break
		if not have:
			net.add_stone(spec["pos"], 130.0, -1, String(spec["name"]))


func _elder_label(id: String) -> String:
	match id:
		"elder_glade": return "Stagborn Glade"
		"elder_greyseam": return "Greyseam"
		"elder_highwatch": return "Highwatch"
		"elder_crownstead": return "Crownstead"
		_: return "Elden Road"


func elder_network_ids(net: RARunestoneNetwork) -> PackedInt32Array:
	var out := PackedInt32Array()
	for s: Dictionary in net.stones:
		if String(s["name"]).begins_with(ELDER_PREFIX):
			out.append(int(s["id"]))
	return out


func _bind_wardlines() -> void:
	if wl == null:
		return
	_net = Frontier.runestones
	_ensure_elder_stones(_net)
	_ensure_story_stones(_net)
	var elders := elder_network_ids(_net)
	if not (wl.layout_source == "network" and wl.n == _net.stones.size()):
		wl.bind_network(_net, elders)    # a save loaded later replaces this with its own layout
	_net.coverage_override = wl.coverage_callable()
	if not wl.event.is_connected(_on_ward_event):
		wl.event.connect(_on_ward_event)


## Network id -> the story's stone ids (registry "stones"): "miller_stone", "greenhollow_road", "elder_glade", ...
func story_stone_ids(net_id: int) -> Array[String]:
	var out: Array[String] = []
	if Frontier.runestones == null or net_id < 0 or net_id >= Frontier.runestones.stones.size():
		return out
	var s: Dictionary = Frontier.runestones.stones[net_id]
	var sp: Vector2 = s["pos"]
	var reg: Dictionary = Places.registry().get("stones", {})
	for sid: String in reg:
		if sid.begins_with("_"):
			continue
		var info: Dictionary = reg[sid]
		var r := Places.resolve(String(info.get("place", "")))
		if r.is_empty():
			continue
		var kind := String(info.get("kind", "road"))
		var is_elder_stone := String(s["name"]).begins_with(ELDER_PREFIX)
		if kind == "elder":
			if is_elder_stone and _nearest_named(r["pos"], true) == net_id:
				out.append(sid)
		elif is_elder_stone:
			continue
		elif bool(info.get("group", false)):
			var root := String(info["place"]).trim_suffix("_road")
			var names: Array = Places.NAMES.get(root, [root.capitalize()])
			if String(s.get("road_to", "")) in names or sp.distance_to(r["pos"]) < 260.0:
				out.append(sid)
		else:
			if _nearest_named(r["pos"], false) == net_id and sp.distance_to(r["pos"]) < 420.0:
				out.append(sid)
	return out


## Nearest network stone (elder stones only, or everything but elders) to `pos`.
func _nearest_named(pos: Vector2, elder: bool) -> int:
	var best := -1
	var best_d := INF
	for s: Dictionary in Frontier.runestones.stones:
		if String(s["name"]).begins_with(ELDER_PREFIX) != elder:
			continue
		var d: float = (s["pos"] as Vector2).distance_to(pos)
		if d < best_d:
			best_d = d
			best = int(s["id"])
	return best


## Wardlines events -> sound, rumours, the ashes.
func _on_ward_event(kind: StringName, data: Dictionary) -> void:
	var pos := Vector3.INF
	if data.has("id") and int(data["id"]) < Frontier.runestones.stones.size():
		var sp: Vector2 = Frontier.runestones.stones[int(data["id"])]["pos"]
		pos = Vector3(sp.x, WorldGen.height(sp.x, sp.y), sp.y)
	match String(kind):
		"stone_lit":
			_sfx_near("r1_ward_activate", pos, 70.0)
		"stone_dark", "stone_failed":
			_sfx_near("r1_ward_break", pos, 70.0)
		"stone_damaged":
			if pos != Vector3.INF:
				AshMemory.report(&"sabotage", Vector2(pos.x, pos.z), AshMemory.clock())
		"road_rumour", "elder_strained", "alarm":
			if is_instance_valid(player) and String(data.get("rumour", "")) != "":
				var near := true
				if kind == &"alarm" and pos != Vector3.INF:
					near = player.global_position.distance_to(pos) < 420.0
				if near:
					Game.say(String(data["rumour"]))


func _on_day(_day: int) -> void:
	_push_to_network()


## Wardlines owns wear; write its numbers back once a day so the old network (map colours, rumours, the
## stone glow in FrontierPresence, economy road risk) agrees. Only changed condition bands signal.
func _push_to_network() -> void:
	if wl == null or _net == null:
		return
	for i in mini(wl.n, _net.stones.size()):
		var s: Dictionary = _net.stones[i]
		var old_band := _net.condition_name(s)
		s["power"] = wl.charge[i]
		s["condition"] = wl.condition[i]
		if _net.condition_name(s) != old_band:
			_net.stone_changed.emit(s)
	if el != null:
		el.apply_to_network(_net)


# --- the stone under the player's hand --------------------------------------------------

func _stone_finder(pp: Vector2) -> Dictionary:
	if wl == null or _net == null:
		return {}
	var best := -1
	var best_d := STONE_REACH
	for s: Dictionary in _net.stones:
		var d: float = pp.distance_to(s["pos"])
		if d < best_d:
			best_d = d
			best = int(s["id"])
	if best < 0:
		return {}
	var st: Dictionary = _net.stones[best]
	var ancestor := el != null and el.is_ancestor_stone(best)
	var elder := String(st["name"]).begins_with(ELDER_PREFIX)
	var verb := "Speak to the stone" if ancestor else ("Read the Elder Stone" if elder else "Read the stone")
	return {"pos": st["pos"], "verb": verb, "title": String(st["name"]), "menu": Callable(self, "stone_menu").bind(best)}


func stone_menu(id: int) -> Dictionary:
	var s: Dictionary = _net.stones[id]
	var info := wl.stone_info(id) if id < wl.n else {}
	var elder: bool = bool(info.get("elder", false))
	var opts: Array = []
	var body := ""
	if not info.is_empty():
		body = "%s. %s glyph. Charge %d%%, condition %d%%." % [String(info["band"]).capitalize(), "No" if String(info["glyph"]) == "none" else String(info["glyph"]).capitalize(),
			int(round(float(info["charge"]) * 100.0)), int(round(float(info["condition"]) * 100.0))]
		if elder:
			for e: Dictionary in wl.elder_status():
				if int(e["id"]) == id:
					body = "An Elder Stone. Power %d%%, feeding %d stones (load %d%%)." % [int(round(float(e["power"]) * 100.0)), int(e["stones"]), int(round(float(e["load"]) * 100.0))]
		elif float(info["fed"]) < 0.4:
			body += " Little power reaches it."
	# Ancestor stone: the ember speaks (dialogue page).
	var page_head: Dictionary = {}
	if el != null and el.is_ancestor_stone(id):
		page_head = _ancestor_head(id)
	if not elder:
		opts.append(["Carve a glyph", Callable(self, "_open_carve").bind(id)])
		opts.append(["Mend the stone", Callable(self, "_mend").bind(id)])
		opts.append(["Link to a nearby stone", Callable(self, "_link_menu").bind(id)])
	else:
		if _elder_needs_relight(id):
			opts.append(["Relight the Elder Stone", Callable(self, "_relight").bind(id)])
		opts.append(["Bless the heart-stone (draw a bless glyph)", Callable(self, "_open_carve_bless").bind(id)])
		opts.append(["Link to a nearby stone", Callable(self, "_link_menu").bind(id)])
	if el != null and not el.embers.is_empty() and not el.is_ancestor_stone(id):
		opts.append(["Lay an ember to rest here", Callable(self, "_ember_stone_here").bind(int(el.embers[0]["id"]), id)])
	if page_head.has("speaker"):
		opts.append(["Who were you?", Callable(self, "_ancestor_card").bind(id)])
	opts.append(["Leave", Callable(self, "_close_menu")])
	if page_head.has("speaker"):
		var page: Dictionary = page_head.duplicate()
		page["options"] = opts
		return page
	return {"title": String(s["name"]), "body": body, "options": opts}


func _close_menu() -> String:
	if hud != null:
		hud.close_menu()
	return ""


func _ancestor_head(id: int) -> Dictionary:
	var rec_d := el.stone_record(id)
	var pack := false
	for n in get_tree().get_nodes_in_group("team1"):
		if n is Node3D and String(n.get("species") if n.get("species") != null else "") == "wolf" \
				and (n as Node3D).global_position.distance_to(_stone_world(id)) < 120.0:
			pack = true
			break
	var raid := mem != null and mem.heat_at(_net.stones[id]["pos"]) > 0.25
	var sit := EmberLegacy.situation_for({"pack": pack, "raid": raid}, float(_net.stones[id]["condition"]), wl != null and not wl.rumours().is_empty())
	var near := WorldGen.nearest_settlement(_net.stones[id]["pos"])
	var line := el.bark(id, sit, {"heir": Life.life_path.full_name(), "place": String(near.get("name", "the road"))}, WorldSim.day)
	var ad := String(rec_d.get("first", rec_d.get("ancestor", "Ancestor")))
	return {"title": String(rec_d.get("ancestor", "Ancestor")), "body": line, "speaker": ad, "role": String(rec_d.get("title", "")),
		"line": line, "relationship": "Family", "rel_value": 60.0, "portrait_key": "anc_%d" % id, "look": "Elder_Man"}


func _ancestor_card(id: int) -> String:
	var c := el.card(id)
	if c.is_empty():
		return ""
	Game.say("%s\n%s" % [String(c["title"]), "\n".join(PackedStringArray(c["lines"]))])
	return ""


func _stone_world(id: int) -> Vector3:
	var p: Vector2 = _net.stones[id]["pos"]
	return Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


func _mend(id: int) -> String:
	if wl == null or id >= wl.n:
		return ""
	if wl.day_f - wl.last_repair[id] < 0.4 and wl.condition[id] > 0.6:
		return "It was mended not long ago."
	wl.repair(id)
	Life.record("mended_stone", 1.0)
	_sfx_near("r1_ward_activate", _stone_world(id), 40.0)
	return "You scrape the moss from the runes and re-cut what the weather took."


# --- the carve canvas ------------------------------------------------------------------

func _open_carve(id: int) -> String:
	_carve_target = id
	if hud != null:
		hud.close_menu()
	carve_view.open(rec, String(_net.stones[id]["name"]), ["ward", "lure", "alarm", "bless"])
	return ""


func _open_carve_bless(id: int) -> String:
	_carve_target = id
	if hud != null:
		hud.close_menu()
	carve_view.open(rec, String(_net.stones[id]["name"]), ["bless", "ward"])
	return ""


func _on_carved(glyph: String, result: Dictionary) -> void:
	var id := _carve_target
	_carve_target = -1
	if id == -2:
		# Drawn in the air to calm a great creature (the parley route): a bless glyph is enough.
		if glyph == "bless" and _parley_target != "":
			_parley_done(_parley_target, "You draw the glyph slowly, palm open. The great head turns, considers you, and lowers.")
		else:
			Game.say("It does not calm. Try a bless glyph, slowly.")
		return
	if id < 0 or wl == null:
		return
	var res := wl.carve(id, glyph)
	var sp := _stone_world(id)
	if bool(res.get("ok", false)):
		Game.say("A %s glyph takes on %s." % [glyph, String(_net.stones[id]["name"])])
		_sfx_near("r1_glyph_carve", sp, 40.0)
		Region1TutorialDirector.tell(&"carve")
		for sid in story_stone_ids(id):
			story.notify(&"carve", {"glyph": glyph, "stone": sid, "amount": 1})
		_push_to_network()
		return
	var reason := String(res.get("reason", ""))
	if reason == "elder_stone":
		# An Elder Stone keeps no glyph; a bless glyph feeds its heart instead.
		var e: int = wl.elder_of[id]
		if glyph == "bless" and e >= 0:
			wl.elder_power[e] = minf(1.0, wl.elder_power[e] + 0.35)
			wl.call("_dirty_alloc")
			Game.say("The Elder Stone drinks the blessing. Its light steadies.")
			_sfx_near("r1_ward_activate", sp, 60.0)
			Region1TutorialDirector.tell(&"carve")
			for sid in story_stone_ids(id):
				story.notify(&"carve", {"glyph": glyph, "stone": sid, "amount": 1})
		else:
			Game.say("An Elder Stone keeps no glyph of its own. Try a bless glyph.")
		return
	match reason:
		"too_dim":
			Game.say("The stone is too dim to take a glyph. Mend it first.")
		"unfed", "elder_spent":
			Game.say("No power reaches this stone right now. Give the Elder a few days, or link it to another.")
		_:
			Game.say("The glyph does not take.")


func _elder_needs_relight(id: int) -> bool:
	if wl == null or id >= wl.n or wl.elder_of[id] < 0:
		return false
	if wl.elder_power[wl.elder_of[id]] < 0.95:
		return true
	# The story may ask for a relight even when the stone is well.
	for sid in story_stone_ids(id):
		for t: String in story.story.active_steps():
			var o: Dictionary = story.story.current_objective(t)
			if String(o.get("type", "")) == "relight_elder" and String(o.get("stone", "")) == sid:
				return true
	return false


func _relight(id: int) -> String:
	var e: int = wl.elder_of[id]
	if e < 0:
		return ""
	wl.elder_power[e] = 1.0
	wl.call("_dirty_alloc")
	wl.emit_event(&"elder_calm", {"elder": e, "name": wl.st_name[id], "rumour": "%s is lit again." % wl.st_name[id]})
	_sfx_near("r1_ward_activate", _stone_world(id), 80.0)
	story.show_staging("elder_relight")
	for sid in story_stone_ids(id):
		story.notify(&"relight_elder", {"stone": sid})
	_push_to_network()
	return "Blue light runs out along the ward-lines, stone to stone."


func _link_menu(id: int) -> Dictionary:
	# A second-level menu: the three nearest stones this one is not linked to yet.
	var cand: Array = []
	for i in wl.n:
		if i == id or wl._find_link(id, i) >= 0:
			continue
		var d: float = wl.st_pos[id].distance_to(wl.st_pos[i])
		if d <= float(wl._cf("links", "max_len")):
			cand.append([d, i])
	cand.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var opts: Array = []
	for k in mini(4, cand.size()):
		var j: int = int(cand[k][1])
		opts.append(["%s (%d m)" % [wl.st_name[j], int(cand[k][0])], Callable(self, "_make_link").bind(id, j)])
	if opts.is_empty():
		opts.append(["No stone in reach to link", Callable(self, "_close_menu"), false])
	opts.append(["Back", Callable(self, "_back_to_stone").bind(id)])
	return {"title": "Link %s" % wl.st_name[id], "body": "A wardline carries power from stone to stone. Longer lines leak more.", "options": opts}


func _back_to_stone(id: int) -> String:
	if hud != null:
		hud.show_menu(Callable(self, "stone_menu").bind(id))
	return ""


func _make_link(a: int, b: int) -> String:
	var res: Dictionary = wl.add_link(a, b)
	if not bool(res.get("ok", false)):
		return "The link will not hold (%s)." % String(res.get("reason", "too far"))
	var tos: Array[String] = [""]
	for pid in Places.registry().get("places", {}):
		var r := Places.resolve(String(pid))
		if not r.is_empty() and (wl.st_pos[b] as Vector2).distance_to(r["pos"]) <= maxf(float(r["radius"]) * 3.0, 260.0):
			tos.append(String(pid))
	tos.append_array(story_stone_ids(b))
	var froms: Array[String] = [""]
	froms.append_array(story_stone_ids(a))
	for f in froms:
		for t in tos:
			story.notify(&"wardline_link", {"from": f, "to": t, "amount": 1})
	_push_to_network()
	return "The wardline hums into place."


# --- parley: the non-combat route past the story's great creatures ----------------------

const PARLEY_NAMES := {"antlered_warden": "The Antlered Warden", "scarbound_troll": "The Scarbound Troll"}


func _parley_finder(pp: Vector2) -> Dictionary:
	if story == null or story.story == null:
		return {}
	for t: Dictionary in story.parley_targets():
		var r := Places.resolve(String(t["place"]))
		if not r.is_empty() and pp.distance_to(r["pos"]) <= maxf(float(r["radius"]) * 1.4, 70.0):
			return {"pos": pp, "at_player_height": true, "verb": "Parley", "title": "", "menu": Callable(self, "parley_menu").bind(String(t["target"]))}
	return {}


func parley_menu(target: String) -> Dictionary:
	var has_gift: bool = Life.count("venison_roast") >= 1 or Life.count("bread") >= 3
	var opts: Array = [
		["Offer a gift of food (a venison roast or three loaves)", Callable(self, "_parley_gift").bind(target), has_gift],
		["Draw a bless glyph in the air to calm it", Callable(self, "_parley_glyph").bind(target)],
		["Step back (you may also fight it)", Callable(self, "_close_menu")]]
	return {"title": String(PARLEY_NAMES.get(target, target.capitalize())), "body": "You do not have to fight it. Something this old can be appeased, or out-waited, if you are careful and do not hurry.", "options": opts}


func _parley_gift(target: String) -> String:
	if not Life.take("venison_roast", 1) and not Life.take("bread", 3):
		return "You have nothing to offer."
	_parley_done(target, "You set the gift on the ground and back away. After a long while it eats, and lets you pass.")
	return ""


func _parley_glyph(target: String) -> String:
	_parley_target = target
	_carve_target = -2
	if hud != null:
		hud.close_menu()
	carve_view.open(rec, "the air between you", ["bless", "ward"])
	return ""


func _parley_done(target: String, text: String) -> void:
	_parley_target = ""
	Game.say(text)
	story.parley(target)


# =====================================================================================
# Scar Tide (N2): hooks H4 and H5, economy, actions
# =====================================================================================

func _bind_scar() -> void:
	if scar == null:
		return
	if wl != null:
		scar.coverage = wl.coverage_callable()
	scar.blocked = func(p: Vector2) -> bool: return WorldGen.is_water(p.x, p.y)
	scar.season_cb = func() -> int: return SeasonsRef.season_of(WorldSim.seasons.current_day()) if WorldSim.seasons != null else 0
	Frontier.ecology.variant_override = Callable(scar, "variant_for")    # hook H4
	if not scar.event.is_connected(_on_scar_event):
		scar.event.connect(_on_scar_event)
	_upload_mask()


func _upload_mask() -> void:
	if scar == null or not scar.mask_dirty():
		return
	var img: Image = scar.mask_image()
	if _scar_tex == null:
		_scar_tex = ImageTexture.create_from_image(img)
	else:
		_scar_tex.update(img)
	RenderingServer.global_shader_parameter_set("scar_mask", _scar_tex)   # hook H5 reads it in terrain.gdshader


func _on_scar_event(kind: StringName, data: Dictionary) -> void:
	match String(kind):
		"ward_pressure":
			if wl != null:
				for p: Array in data.get("points", []):
					wl.pressure(Vector2(float(p[0]), float(p[1])), 60.0, 0.02)
		"outbreak":
			Game.say(String(data.get("rumour", "")))


func _places_near(pos: Vector2, pad: float) -> Array[String]:
	var out: Array[String] = []
	for id in Places.registry().get("places", {}):
		var r := Places.resolve(String(id))
		if not r.is_empty() and pos.distance_to(r["pos"]) <= float(r["radius"]) + pad:
			out.append(String(id))
	return out


func _scar_finder(pp: Vector2) -> Dictionary:
	if scar == null:
		return {}
	var f: Vector2 = scar.nearest_front(pp, 16.0)
	if f == Vector2.INF:
		return {}
	return {"pos": pp, "at_player_height": true, "verb": "Face the Scar", "title": "", "menu": Callable(self, "scar_menu").bind(f)}


func scar_menu(front: Vector2) -> Dictionary:
	var here := Vector2(player.global_position.x, player.global_position.z)
	var cells: int = scar.count_near(here, 70.0)
	var has_oil: bool = Life.count("sunstone_oil") > 0
	var has_wood: bool = Life.count("firewood") >= FIREWOOD_FOR_FIRE
	var cost := "1 Sunstone Oil" if has_oil else ("%d firewood" % FIREWOOD_FOR_FIRE)
	var opts: Array = [
		["Burn it back (%s)" % cost, Callable(self, "_scar_burn").bind(front), has_oil or has_wood],
		["Cut crystals and scarbloom", Callable(self, "_scar_harvest").bind(front)],
		["Ward the front (carve a stone)", Callable(self, "_scar_ward").bind(front)],
		["Leave it", Callable(self, "_close_menu")]]
	return {"title": "The Scar's edge", "body": "Violet ground, warm to the touch, humming. About %d cells of it lie within seventy paces. Fire burns it back for a while; a bright ward stops it; its crystals sell dear." % cells, "options": opts}


func _scar_burn(front: Vector2) -> String:
	if Life.count("sunstone_oil") > 0:
		Life.take("sunstone_oil", 1)
	elif not Life.take("firewood", FIREWOOD_FOR_FIRE):
		return "You have nothing to burn it with."
	var cleared: int = scar.burn(front, BURN_RADIUS, 1.0)
	_flash_fire(front)
	AshMemory.report(&"fire", front, AshMemory.clock())
	Life.record("scar_burned", 1.0)
	if cleared > 0:
		for pid in _places_near(front, 60.0):
			story.notify(&"scar_contain", {"place": pid, "amount": cleared})
		Game.say("The fire drives the Scar back: %d cells scorched clean." % cleared)
	else:
		Game.say("The fire takes, but the Scar only pulls back a little. Burn again.")
	return ""


func _flash_fire(at: Vector2) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 4.0
	l.omni_range = 18.0
	world.add_child(l)
	l.global_position = Vector3(at.x, WorldGen.height(at.x, at.y) + 1.5, at.y)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 1.6)
	tw.tween_callback(l.queue_free)


func _scar_harvest(front: Vector2) -> String:
	var res: Dictionary = scar.harvest(front, HARVEST_RADIUS)
	var c := int(res.get("crystals", 0))
	var b := int(res.get("bloom", 0))
	if c + b == 0:
		return "Nothing ripe here. The crystals grow deeper in."
	if c > 0:
		Life.give("scar_crystal", c)
	if b > 0:
		Life.give("scarbloom", b)
	if c > 0:
		for pid in _places_near(front, 60.0):
			story.notify(&"scar_harvest", {"place": pid, "amount": c})
	Life.record("scar_harvested", float(c + b))
	return "You cut %d scar crystal%s and %d scarbloom." % [c, "" if c == 1 else "s", b]


func _scar_ward(front: Vector2) -> String:
	var best := -1
	var best_d := 220.0
	for s: Dictionary in _net.stones:
		if String(s["name"]).begins_with(ELDER_PREFIX):
			continue
		var d: float = front.distance_to(s["pos"])
		if d < best_d:
			best_d = d
			best = int(s["id"])
	if best < 0:
		return "No runestone stands near enough to hold a ward against it."
	Game.say("The nearest stone is %d paces away: %s." % [int(best_d), String(_net.stones[best]["name"])])
	_open_carve(best)
	return ""


## When the story's Scar step starts and there is no Scar near its place yet, it breaks out there
## (so the answer "burn it or reap it" is always available and never blocked by the season).
func _seed_outbreaks_for_step(step_id: String) -> void:
	if scar == null:
		return
	var s: Dictionary = story.story.step(step_id)
	for o: Dictionary in s.get("objectives", []):
		var t := String(o.get("type", ""))
		var subs: Array = o.get("of", []) if t == "any" else [o]
		for sub: Dictionary in subs:
			var st := String(sub.get("type", ""))
			if st != "scar_contain" and st != "scar_harvest":
				continue
			var pid := String(sub.get("place", ""))
			var r := Places.resolve(pid)
			if r.is_empty():
				continue
			var need := maxi(int(sub.get("cells", 0)), int(sub.get("crystals", 0)) * 2)
			if scar.count_near(r["pos"], 140.0) < need * 2:
				scar.seed_at(r["pos"], clampf(sqrt(float(need) * 2.0 / PI) + 1.0, 2.0, 5.0), pid)


# =====================================================================================
# Ember Legacy (N3)
# =====================================================================================

func _bind_ember() -> void:
	if el == null:
		return
	el.apply_to_network(_net)
	_apply_ancestors_to_wardlines()
	if not el.life_ended.is_connected(_on_life_ended):
		el.life_ended.connect(_on_life_ended)


## Ancestor stones grow their Wardlines bubble and charge once (recorded in the ember save so a load
## never applies it twice).
func _apply_ancestors_to_wardlines() -> void:
	if el == null or wl == null:
		return
	var rps := float(el.data().get("power", {}).get("radius_per_power", 0.6))
	for key: String in el.ancestor_stones:
		var rec_d: Dictionary = el.ancestor_stones[key]
		if bool(rec_d.get("wl_applied", false)):
			continue
		var id := int(key)
		if id < 0 or id >= wl.n:
			continue
		var b := float(rec_d["power_bonus"])
		wl.st_radius[id] = wl.st_radius[id] * (1.0 + b * rps)
		wl.charge[id] = minf(1.0, wl.charge[id] + b)
		wl.repair(id, b * 0.5, true)
		rec_d["wl_applied"] = true
		wl.call("_refresh_all")
		wl.call("_dirty_alloc")


func _on_life_ended(_summary: Dictionary) -> void:
	# The choice is offered by the tick once the heir has taken over and no menu is open.
	pass


func _offer_ember(ember_id: int, who := "") -> void:
	_ember_done[ember_id] = true
	if who == "" and not _succession_noted.has(ember_id):
		_succession_noted[ember_id] = true
		el.on_succession()        # the heir has taken over: heirlooms level up
	hud.show_menu(Callable(self, "ember_menu").bind(ember_id, who))
	ember_offered.emit(ember_id)


func ember_menu(ember_id: int, who := "") -> Dictionary:
	var cards := el.choices_for(ember_id)
	var e := el.ember(ember_id)
	if e.is_empty():
		return {"title": "The ember", "body": "It has already found its rest.", "options": [["Close", Callable(self, "_close_menu")]]}
	var p: Dictionary = e["profile"]
	var opts: Array = []
	for c: Dictionary in cards:
		opts.append(["%s: %s" % [String(c["title"]), String(c["text"])], Callable(self, "_ember_choose").bind(ember_id, String(c["choice"]), who)])
	opts.append(["Decide later", Callable(self, "_close_menu")])
	return {"title": "%s, %s" % [String(p["name"]), String(p["title"])], "body": "An ember remains, warm in your hand. Where should it rest? It stays with you until you choose.", "options": opts}


func _ember_choose(ember_id: int, choice: String, who: String) -> String:
	match choice:
		"runestone":
			hud.show_menu(Callable(self, "ember_stone_menu").bind(ember_id, who))
			return ""
		"heirloom":
			var r := el.choose_heirloom(ember_id)
			if bool(r.get("ok", false)):
				var it := el.heirloom_item(int(r["heirloom"]["id"]))
				if not it.is_empty():
					Life.give(String(it["id"]), 1)
				Game.say(String(r["text"]))
				_ember_story(who, "heirloom")
			hud.close_menu()
			return ""
		"heir":
			var b := el.choose_heir(ember_id)
			if bool(b.get("ok", false)):
				el.apply_blessing(b, Life.echoes, WorldSim.day, Life.mastery)
				Game.say(String(b["text"]))
				_ember_story(who, "heir")
			hud.close_menu()
			return ""
	return ""


func ember_stone_menu(ember_id: int, who: String) -> Dictionary:
	var here := Vector2(player.global_position.x, player.global_position.z)
	var cand: Array = []
	for s: Dictionary in _net.stones:
		if el.is_ancestor_stone(s["id"]) or String(s["name"]).begins_with(ELDER_PREFIX):
			continue
		cand.append([here.distance_to(s["pos"]), int(s["id"])])
	cand.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var opts: Array = []
	for k in mini(5, cand.size()):
		var id := int(cand[k][1])
		opts.append(["%s (%d m)" % [String(_net.stones[id]["name"]), int(cand[k][0])], Callable(self, "_ember_stone_pick").bind(ember_id, id, who)])
	opts.append(["Back", Callable(self, "_ember_back").bind(ember_id, who)])
	return {"title": "Rest in a runestone", "body": "Choose the stone that will carry the ember. It grows stronger and speaks to your family.", "options": opts}


func _ember_back(ember_id: int, who: String) -> String:
	hud.show_menu(Callable(self, "ember_menu").bind(ember_id, who))
	return ""


func _ember_stone_here(ember_id: int, id: int) -> String:
	return _ember_stone_pick(ember_id, id, "")


func _ember_stone_pick(ember_id: int, id: int, who: String) -> String:
	var r := el.choose_runestone(ember_id, id, String(_net.stones[id]["name"]), WorldSim.day)
	if bool(r.get("ok", false)):
		var rec_d: Dictionary = r["stone"]
		story.note_ancestor(String(rec_d["ancestor"]), String(rec_d["stone_name"]))
		el.apply_to_network(_net)
		_apply_ancestors_to_wardlines()
		_push_to_network()
		_sfx_near("r1_ward_activate", _stone_world(id), 90.0)
		Game.say(String(r["text"]))
		_ember_story(who, "stone")
	else:
		Game.say(String(r.get("text", "It will not settle.")))
	hud.close_menu()
	return ""


func _ember_story(who: String, choice: String) -> void:
	if who != "":
		story.notify(&"ember_choice", {"who": who, "choice": choice})


## Extra menu rows for a story character (the director asks): Rowan's ember in Act IV.
func npc_extra_options(npc_id: String) -> Array:
	var out: Array = []
	if npc_id == "rowan_ashby" and el != null:
		for t: String in story.story.active_steps():
			var o: Dictionary = story.story.current_objective(t)
			if String(o.get("type", "")) == "ember_choice" and String(o.get("who", "")) == "rowan":
				out.append(["Lay Rowan's ember to rest", Callable(self, "_offer_rowan")])
	return out


func _offer_rowan() -> String:
	var summary := {"name": "Sir Rowan Ashby", "family": "Ashby", "age": 71, "day": WorldSim.day, "cause": "old age",
		"place": "Highwatch Keep", "reputation": {"military": 40.0}, "chapters": [{"role": "knight", "org": "Order of the Highwatch", "place": "Highwatch Keep", "start_day": 0, "end_day": -1}],
		"highlights": [{"text": "Held the Highwatch gate through forty winters", "day": 0}], "echoes": [], "mastery": {}, "tendencies": {}}
	var id := el.on_life_ended(summary)
	_offer_ember(id, "rowan")
	return ""


# =====================================================================================
# Ashsight (N4): hooks C6 / C6b
# =====================================================================================

func _bind_ash() -> void:
	if mem == null:
		return
	var cam: Variant = player.get("camera")
	if cam is Camera3D:
		ash = AshsightController.new()
		ash.name = "Ashsight"
		world.add_child(ash)
		ash.setup(cam as Camera3D, main.get("env"), func(p: Vector2) -> float: return WorldGen.height(p.x, p.y))
		ash.ended.connect(func() -> void: Region1TutorialDirector.tell(&"ashsight"))
		ash.warm()
	_flag_sites()


func _flag_sites() -> void:
	if mem == null:
		return
	for s: Dictionary in _net.stones:
		AshMemory.flag_site_static(String(s["name"]), s["pos"])
	# Story places the quest reads the ashes of.
	for pid: String in ["miller_stone", "ashford_ring", "greenhollow_farm", "crownstead"]:
		var r := Places.resolve(pid)
		if not r.is_empty():
			AshMemory.flag_site_static(Places.place_name(pid), r["pos"])


func _ash_finder(pp: Vector2) -> Dictionary:
	if mem == null or ash == null:
		return {}
	var ids: Array[int] = mem.incidents_near(pp, 40.0)
	if not ids.is_empty():
		return {"pos": pp, "at_player_height": true, "verb": "Kneel at the ashes", "title": "", "menu": Callable(self, "_ash_menu").bind(ids[0])}
	# A story site that wants its memory: kneeling stages one there (first Ashsight, Act II).
	var need := _story_ash_site(pp)
	if need != "":
		return {"pos": pp, "at_player_height": true, "verb": "Kneel at the ashes", "title": "", "menu": Callable(self, "_ash_menu_stage").bind(need)}
	return {}


## The registry place the current Ashsight objective names, when the player stands in it.
func _story_ash_site(pp: Vector2) -> String:
	if story == null or story.story == null:
		return ""
	for t: String in story.story.active_steps():
		var o: Dictionary = story.story.current_objective(t)
		if String(o.get("type", "")) == "ashsight":
			var r := Places.resolve(String(o.get("site", "")))
			if not r.is_empty() and pp.distance_to(r["pos"]) <= maxf(float(r["radius"]), 50.0):
				return String(o["site"])
	return ""


func _ash_menu(id: int) -> Dictionary:
	return {"title": "The ashes remember", "body": "Warm still. Kneel and let them show you what happened here.",
		"options": [["Kneel and read the ashes", Callable(self, "_kneel").bind(id)], ["Leave", Callable(self, "_close_menu")]]}


func _ash_menu_stage(site: String) -> Dictionary:
	return {"title": "The ashes remember", "body": "Something happened here. The ash is faint but it is not cold.",
		"options": [["Kneel and read the ashes", Callable(self, "_kneel_stage").bind(site)], ["Leave", Callable(self, "_close_menu")]]}


func _kneel_stage(site: String) -> String:
	var r := Places.resolve(site)
	var id := stage_memory(r["pos"], site)
	return _kneel(id)


func _kneel(id: int) -> String:
	if hud != null:
		hud.close_menu()
	if id < 0 or ash == null or not ash.show_incident(mem, id):
		return "The ashes are cold."
	var c: Vector2 = mem.replay_info(id).get("center", Vector2.ZERO)
	for pid in _places_near(c, 70.0):
		story.notify(&"ashsight", {"site": pid})
	return ""


## Records a scripted raid memory at `pos` the way the game emitters would (AshFakeRaid's beats, moved
## to the site): used when the story sends the player to read the ashes of a place where nothing has
## happened in the simulation yet.
func stage_memory(pos: Vector2, site_name: String) -> int:
	if mem == null:
		return -1
	mem.flag_site(Places.place_name(site_name), pos)
	var t0 := AshMemory.clock()
	var id := mem.begin_incident(&"raid", pos, t0, {}, true)
	if id < 0:
		return -1
	var t := 0.0
	var dur := float(AshFakeRaid.DURATION)
	while t <= dur + 0.0001:
		var actors: Array = []
		for a: Dictionary in AshFakeRaid.truth(t):
			actors.append({"id": a["id"], "role": a["role"], "pos": (a["pos"] as Vector2) + pos})
		mem.sample(t0 + t, actors)
		t += 1.0
	for m: Array in AshFakeRaid.MARKS:
		mem.mark(id, t0 + float(m[0]), String(m[1]))
	for a2: Array in AshFakeRaid.ACTS:
		mem.act(id, t0 + float(a2[0]), String(a2[1]), StringName(a2[2]))
	mem.end_incident(id, t0 + dur)
	_staged[site_name] = true
	return id


func _on_player_died() -> void:
	var p := player.global_position
	AshMemory.report(&"death", Vector2(p.x, p.z), AshMemory.clock(), [{"id": "player", "role": "villager", "pos": Vector2(p.x, p.z)}])


# =====================================================================================
# UI, story, tutorial
# =====================================================================================

func _build_ui() -> void:
	carve_view = CarveView.new()
	carve_view.name = "CarveView"
	hud.add_child(carve_view)
	carve_view.carved.connect(_on_carved)
	map_layer = MapLayer.new()
	map_layer.name = "Region1MapLayer"
	if hud.get("world_map") != null:
		hud.world_map.add_layer(map_layer)
	stone_station = _follower("R1StoneStation", Callable(self, "_stone_finder"))
	scar_station = _follower("R1ScarStation", Callable(self, "_scar_finder"))
	ash_station = _follower("R1AshStation", Callable(self, "_ash_finder"))
	parley_station = _follower("R1ParleyStation", Callable(self, "_parley_finder"))


func _follower(nm: String, finder: Callable) -> Station:
	var f: Station = FollowStation.new(nm)
	f.set("finder", finder)
	f.set("hud", hud)
	world.add_child(f)
	return f


func _build_story() -> void:
	story = Director.new()
	story.name = "StoryDirector"
	add_child(story)
	story.setup(self, hud, player, world)
	story.staging_cue.connect(_on_story_cue)
	story.step_started.connect(_on_step_started)
	story.quest_completed.connect(func() -> void: _on_story_cue("r1_finale", ""))


func _on_step_started(id: String) -> void:
	_seed_outbreaks_for_step(id)


func _on_story_cue(cue: String, _step: String) -> void:
	if Audio.has_method("set_story_cue"):
		Audio.call("set_story_cue", cue)


func _on_festival(f: Dictionary) -> void:
	var id := String(f.get("id", ""))
	if FESTIVAL_MAP.has(id) and story != null:
		story.notify(&"festival", {"festival": FESTIVAL_MAP[id]})


func _build_tutorial() -> void:
	tutorial = Region1TutorialBridge.new()
	tutorial.name = "Region1Tutorial"
	main.add_child(tutorial)
	tutorial.setup(player, hud)
	tutorial.providers["near_dim_stone"] = func(p: Vector3) -> bool:
		if wl == null:
			return false
		var id := wl.nearest_stone(Vector2(p.x, p.z), 6.0)
		return id >= 0 and wl.stone_band(id) < Wardlines.BAND_GLOWING
	tutorial.providers["knows_glyph"] = func(_p: Vector3) -> bool:
		return story != null and story.story != null and story.story.has_flag("r1.a1.taught")
	tutorial.providers["near_ash_site"] = func(p: Vector3) -> bool:
		return mem != null and not mem.incidents_near(Vector2(p.x, p.z), 14.0).is_empty()
	tutorial.providers["new_marker"] = func(_p: Vector3) -> bool: return false   # no world markers: leads are text


# =====================================================================================
# Audio (C12)
# =====================================================================================

func _bind_audio() -> void:
	if ResourceLoader.exists(HUM_PATH):
		_hum_stream = load(HUM_PATH) as AudioStream
		if _hum_stream is AudioStreamOggVorbis:
			(_hum_stream as AudioStreamOggVorbis).loop = true
	for i in 2:
		var p := AudioStreamPlayer3D.new()
		p.stream = _hum_stream
		p.max_distance = 14.0
		p.unit_size = 3.0
		p.bus = "Ambience" if AudioServer.get_bus_index("Ambience") >= 0 else "Master"
		p.volume_db = -80.0
		world.add_child(p)
		_hum.append(p)


func _sfx_near(sound: String, pos: Vector3, max_dist: float) -> void:
	if pos == Vector3.INF or not is_instance_valid(player):
		return
	if player.global_position.distance_to(pos) > max_dist:
		return
	if Audio.has_sound(sound):
		Audio.play_sfx(sound, pos, -2.0, 0.04)


## Two hum voices follow the nearest lit stones within earshot; quieter for weaker stones.
func _update_hum() -> void:
	if _hum.is_empty() or _hum_stream == null or wl == null:
		return
	var pp := player.global_position
	var near: Array = []
	for i in wl.n:
		var d: float = pp.distance_to(Vector3(wl.st_pos[i].x, pp.y, wl.st_pos[i].y))
		if d < 14.0 and wl.stone_strength(i) > 0.2:
			near.append([d, i])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for k in _hum.size():
		var p := _hum[k]
		if k < near.size():
			var i: int = int(near[k][1])
			p.global_position = _stone_world(i) + Vector3.UP * 1.5
			p.volume_db = lerpf(-24.0, -6.0, clampf(wl.stone_strength(i), 0.0, 1.0))
			if not p.playing:
				p.play(randf() * 5.0)
		else:
			p.volume_db = -80.0
			if p.playing:
				p.stop()


# =====================================================================================
# The 1 Hz tick
# =====================================================================================

func _on_tick() -> void:
	_tick_n += 1
	if not is_instance_valid(player):
		return
	if Frontier.runestones != _net:
		_rebind_network()
	_upload_mask()
	_update_hum()
	if tutorial != null and tutorial.director != null:
		var tips := bool(preload("res://scripts/ui/frontend/settings_store.gd").get_value("tutorial_tips"))
		if tips != tutorial.director.enabled:
			tutorial.director.set_enabled(tips)   # the settings toggle (and the prompt's own x) switch tips off
	if _tick_n % 5 == 0:
		_economy()
		_alarms()
	if el != null and not el.embers.is_empty() and story != null:
		var e: Dictionary = el.embers[0]
		var eid := int(e["id"])
		if not _ember_done.has(eid) and not bool(player.get("dead")) and not hud.is_menu_open() and not get_tree().paused:
			_offer_ember(eid)


func _rebind_network() -> void:
	# New game / reset: Frontier made a fresh network. Bind everything again.
	_bind_wardlines()
	_bind_scar()
	_bind_ember()
	_flag_sites()


func _economy() -> void:
	if scar != null and Life.economy != null:
		Life.economy.scar_price_mult = float(scar.price_mult())


func _alarms() -> void:
	if wl == null:
		return
	var n := 0
	for e in get_tree().get_nodes_in_group("team1"):
		if n >= 4:
			break
		if e is Node3D and (e as Node3D).is_visible_in_tree():
			n += 1
			wl.notify_threat(Vector2((e as Node3D).global_position.x, (e as Node3D).global_position.z))
