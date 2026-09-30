extends Node3D
## Runs the exploration layer: the Hidden Vale's look (light shafts, deer, presenter), the discovery cutscene the first time
## the player walks out of the gorge into the vale, and the 26 exploration POIs (finding them, their interactions and
## rewards). Added once by RegionDressing._ready (one "Hidden valley hook" line), like Region1Look.
##
## State lives in Life.discovery (saved already): found secrets are ids, harvests are "res:<id>" -> day, map reveals from
## the half-burnt map are "reveal:x:z:r". Nothing here is on the map until found (Discovery keeps {"secret": true} sites
## out of its place list).
## Per-frame cost: a 0.15 s poll over ~30 POIs; interactables exist only for spots within 70 m.

const HV := preload("res://scripts/world/hidden_valley.gd")
const POIS := preload("res://scripts/world/region_pois.gd")
const Vista := preload("res://scripts/cinematic/discovery_vista.gd")
const ValeLook := preload("res://scripts/world/vale_look.gd")
const AmbientFxScript := preload("res://scripts/world/ambient_fx.gd")
const MUSIC := "res://assets/audio/region1/music/mus_r1_forest_glade.ogg"
const SPOT_NEAR := 70.0
const SPOT_FAR := 95.0
const POLL := 0.15

var focus := Vector3.ZERO
var look: Node3D
var playing := false              # a discovery sequence is on
var vista: Node                   # the running discovery_vista node

var _timer := 0.0
var _shafts: MultiMeshInstance3D
var _shaft_mat: ShaderMaterial
var _spots: Dictionary = {}       # key -> Spot
var _stations: Dictionary = {}
var _wildlife_done := false
var _menu_was_open := false
var _pois: Array[Dictionary] = []


## One interactable: prompt()/use() are all Player.nearest_interactable() and the HUD need.
class Spot extends Node3D:
	var director: Node
	var key := ""
	var text := "Use"
	var _last := -1000

	func prompt() -> String:
		return text

	func use() -> void:
		var f := Engine.get_process_frames()
		if f - _last < 10:
			return
		_last = f
		director.call("use_spot", self)


func _ready() -> void:
	name = "ExplorationDirector"
	POIS.register_items(Life)
	look = ValeLook.new()
	add_child(look)
	for s: Dictionary in WorldGen.sites:
		if String(s.get("poi", "")) != "":
			_pois.append(s)
	_build_shafts()


func _process(delta: float) -> void:
	var p := get_parent()
	if p and "focus" in p:
		focus = p.focus
	look.set("focus", focus)
	_update_shafts()
	_update_rifts()
	_poll_interact()
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = POLL
	var pl := _player()
	if pl == null:
		return
	var at := Vector2(pl.global_position.x, pl.global_position.z)
	if _disc().places.is_empty():      # the HUD builds the place list lazily; do the same so secrets exist before they are found
		_disc().build_from_world(Life.lore.places_in_region())
	if not _wildlife_done:
		_seed_wildlife()
	if not playing:
		_check_vale(pl, at)
		_check_pois(at)
	_refresh_spots(at)


# --- helpers -----------------------------------------------------------------------------------------------------

func _player() -> Node3D:
	var pl: Variant = Life.player
	return pl if pl is Node3D and is_instance_valid(pl) else null


## A node of the world (AmbientLife, AmbientFx...) that has `method`, found among RegionDressing's siblings.
func _sibling_with(method: String) -> Node:
	var world := get_parent().get_parent() if get_parent() else null
	if world == null:
		return null
	for c in world.get_children():
		if c != get_parent() and c.has_method(method):
			return c
	return null


func _hud() -> Node:
	var scene := get_tree().current_scene
	var h: Variant = scene.get("hud") if scene else null
	return h if h is Node and is_instance_valid(h) else null


func _disc() -> RefCounted:
	return Life.discovery


func _day() -> int:
	return int(WorldSim.day)


func _hour() -> float:
	return float(WorldSim.time_of_day)


func _is_night() -> bool:
	var h := _hour()
	return h >= 20.0 or h < 5.0


func _say(text: String) -> void:
	Game.say(text)


func _site_id(s: Dictionary) -> String:
	var p: Vector2 = s["pos"]
	return "site:%s:%d:%d" % [s["name"], roundi(p.x), roundi(p.y)]


# --- the Hidden Vale -----------------------------------------------------------------------------------------------

## The first time the player steps out of the gorge into the vale: the discovery sequence.
func _check_vale(pl: Node3D, at: Vector2) -> void:
	if not HV.enabled() or at.distance_squared_to(HV.CENTER) > 420.0 * 420.0:
		return
	if _disc().is_discovered(HV.place_id()) or InteriorDoor.active != null:
		return
	var l := HV.to_local(at)
	var in_mouth: bool = l.x > 140.0 and l.x < 215.0 and absf(l.y - HV.gorge_offset(l.x)) < 16.0
	if not in_mouth and HV.rn_at(at) > 0.92:
		return
	start_vale_sequence(pl)


## Plays the fly-out. `on_done` (optional) runs when it ends (tests, QA tools).
func start_vale_sequence(pl: Node3D, on_done := Callable()) -> Node:
	playing = true
	_disc().discover(HV.place_id(), _day())          # first, so the HUD's own banner never races the sequence
	var shots := vale_shots(Vector2(pl.global_position.x, pl.global_position.z))
	var birds := [[2.6, Callable(self, "_birds_take_off").bind(pl.global_position)],
		[4.2, Callable(self, "_birds_take_off").bind(pl.global_position + Vector3(0, 0, 0))]]
	var hud := _hud()
	var def := {"shots": shots, "kicker": "A place apart", "title": "The Hidden Vale",
		"line": "Untouched. No one has walked here in an age...", "title_at": 5.0, "music": MUSIC, "music_db": -3.0,
		"freeze": [pl], "hide": [hud] if hud else [], "events": birds}
	vista = Vista.new()
	add_child(vista)
	vista.finished.connect(func(skipped: bool) -> void:
		playing = false
		vista = null
		_vale_rewards(skipped)
		if on_done.is_valid():
			on_done.call(skipped))
	vista.play(def)
	return vista


## The camera path: out of the slot, up over the vale, a slow look across meadow, pond and falls. ~12.5 s.
static func vale_shots(_player_at: Vector2) -> Array:
	var g0 := HV.gorge_world(205.0)
	var g1 := HV.gorge_world(150.0)
	var over := HV.w(62.0, 6.0)
	var high := HV.w(-8.0, -95.0)
	var far_look := HV.w(-150.0, 10.0)
	var pond := HV.w(26.0, -56.0)
	var stones := HV.stones_world()
	var gh := func(p: Vector2, up: float) -> Vector3: return Vector3(p.x, WorldGen.height(p.x, p.y) + up, p.y)
	var a: Dictionary = Vista.shot(gh.call(g0, 1.7), gh.call(g1, 2.4), gh.call(HV.w(100.0, 8.0), 4.0), gh.call(HV.w(60.0, 6.0), 8.0), 3.6, 50.0, 56.0,
		{"fade_in": 1.2, "ease": "in_out"})
	var b: Dictionary = Vista.shot(gh.call(g1, 2.4), gh.call(over, 30.0), gh.call(HV.w(60.0, 6.0), 8.0), gh.call(far_look, 30.0), 5.0, 56.0, 62.0)
	var c: Dictionary = Vista.shot(gh.call(over, 30.0), gh.call(high, 40.0), gh.call(far_look, 30.0), gh.call(stones, 6.0), 4.0, 62.0, 58.0, {"fade_out": 1.0})
	return [a, b, c]


## Kept fresh by the director: birds burst from the canopy (AmbientFx's landed flocks if any, plus a small flock of our own).
func _birds_take_off(at: Vector3) -> void:
	var fx: Variant = _sibling_with("scatter")
	if fx is Node and is_instance_valid(fx):
		fx.call("scatter", at)
	var bmesh: Mesh = AmbientFxScript._make_bird_mesh()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.1, 0.1)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var flock := Node3D.new()
	add_child(flock)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(at.x * 7.0 + at.z)
	var center := HV.w(10.0, 40.0)
	for i in 14:
		var mi := MeshInstance3D.new()
		mi.mesh = bmesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = Vector3.ONE * 2.2
		flock.add_child(mi)
		var start := Vector3(center.x + rng.randf_range(-30, 30), WorldGen.height(center.x, center.y) + 4.0, center.y + rng.randf_range(-30, 30))
		mi.global_position = start
		var dir := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
		var end := start + dir * rng.randf_range(60, 110) + Vector3(0, rng.randf_range(35, 60), 0)
		mi.look_at(end)
		var tw := mi.create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "global_position", end, rng.randf_range(5.5, 8.0)).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		var flap := mi.create_tween().set_loops(24)
		flap.tween_property(mi, "scale:y", 0.6, 0.13)
		flap.tween_property(mi, "scale:y", 2.2, 0.13)
	get_tree().create_timer(9.0).timeout.connect(flock.queue_free)


func _vale_rewards(skipped: bool) -> void:
	var soc := _mod("society")
	if soc:
		soc.call("learn", HV.FACT_LORE, HV.LORE_TEXT)
		soc.call("learn", HV.FACT_LEAD, HV.LEAD_TEXT)
	Life.biography.add_highlight("Found the Hidden Vale, a green bowl in the western ridges that no road reaches.", _day())
	Life.record("explored_forest", 2.0)
	_xp(60, "discovered the Hidden Vale")
	var h := _hud()
	if h and h.has_method("notify"):
		h.call("notify", "location", "Location Discovered", "The Hidden Vale")
	if skipped:
		_say("The Hidden Vale. Untouched. No one has walked here in an age.")
	_seed_wildlife()


func _xp(amount: int, reason: String) -> void:
	if Life.has_method("add_xp"):
		Life.call("add_xp", amount, reason)
	elif Life.has_method("add_merit"):
		Life.add_merit(maxi(1, amount / 10), reason)


func _mod(name_: String) -> RefCounted:
	var realm: Variant = Life.get("realm")
	if realm is RefCounted and (realm as RefCounted).has_method("mod"):
		return (realm as RefCounted).call("mod", name_)
	return null


# --- Wildlife and light ---------------------------------------------------------------------------------------------

## Deer and stagborn graze the meadow, rabbits in the fringe (AmbientLife spawns them near the player only).
func _seed_wildlife() -> void:
	var amb: Variant = _sibling_with("_group")
	if not (amb is Node) or not is_instance_valid(amb):
		return
	_wildlife_done = true
	var spots := [Vector2(40, 40), Vector2(-60, 70), Vector2(70, -20), Vector2(-100, -40)]
	for i in spots.size():
		var q := HV.w(spots[i].x, spots[i].y)
		(amb as Node).call("_group", q, [["deer", 3], ["stag", 1]] if i % 2 == 0 else [["deer", 2], ["rabbit", 2]], 16.0)
	(amb as Node).call("_group", HV.w(-20.0, -10.0), [["stag", 2], ["deer", 2]], 18.0)


func _build_shafts() -> void:
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 tint : source_color = vec3(1.0, 0.92, 0.68);
uniform float strength = 0.0;
void fragment() {
	float edge = 1.0 - abs(UV.x * 2.0 - 1.0);
	float fall = smoothstep(0.0, 0.25, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	float soft = pow(edge, 1.6) * fall;
	ALBEDO = tint * soft * strength;
	ALPHA = 1.0;
}
"""
	_shaft_mat = ShaderMaterial.new()
	_shaft_mat.shader = sh
	var quad := QuadMesh.new()
	quad.size = Vector2(9.0, 42.0)
	quad.center_offset = Vector3(0, 21.0, 0)
	quad.material = _shaft_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var list: Array[Transform3D] = []
	for i in 16:
		var q := HV.w(rng.randf_range(-120.0, 110.0), rng.randf_range(-130.0, 130.0))
		if WorldGen.near_water(q.x, q.y, 2.0):
			continue
		var lean := Basis(Vector3.RIGHT, deg_to_rad(-22.0)) * Basis(Vector3.FORWARD, deg_to_rad(10.0))
		var b := Basis(Vector3.UP, deg_to_rad(-35.0) + rng.randf_range(-0.2, 0.2)) * lean
		b = b.scaled(Vector3(rng.randf_range(0.7, 1.3), rng.randf_range(0.8, 1.2), 1.0))
		list.append(Transform3D(b, Vector3(q.x, WorldGen.height(q.x, q.y) - 2.0, q.y)))
	mm.instance_count = list.size()
	for i in list.size():
		mm.set_instance_transform(i, list[i])
	_shafts = MultiMeshInstance3D.new()
	_shafts.name = "LightShafts"
	_shafts.multimesh = mm
	_shafts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shafts.visible = false
	add_child(_shafts)


## Soft god-rays inside the vale by day (fade with the hour, off in rain or away from the vale).
func _update_shafts() -> void:
	if _shafts == null or _shaft_mat == null:
		return
	var near := HV.enabled() and Vector2(focus.x, focus.z).distance_squared_to(HV.CENTER) < 330.0 * 330.0
	var h := _hour()
	var day := clampf(sin((h - 6.0) / 12.0 * PI) * 1.3, 0.0, 1.0)
	var low_sun := 1.0 - 0.5 * absf(h - 12.0) / 6.0          # brighter mornings and evenings than noon
	var amount := day * clampf(low_sun + 0.35, 0.0, 1.0)
	_shafts.visible = near and amount > 0.02
	if _shafts.visible:
		_shaft_mat.set_shader_parameter("strength", 0.16 * amount)


# --- POIs ---------------------------------------------------------------------------------------------------------------

func _check_pois(at: Vector2) -> void:
	for s: Dictionary in _pois:
		var r := float(s.get("radius", 20.0))
		if at.distance_squared_to(s["pos"]) > r * r:
			continue
		var id := _site_id(s)
		if _disc().is_discovered(id):
			continue
		var kind := String(s["kind"])
		if kind == "poi_rift" and not _is_night():
			continue          # the shimmer is only there after dark
		_found_poi(s, id)


func _found_poi(s: Dictionary, id: String) -> void:
	var d := POIS.def(String(s["poi"]))
	_disc().discover(id, _day())
	var h := _hud()
	var banner: Variant = h.get("banner") if h else null
	var kind := String(s["kind"])
	if banner is Object and (banner as Object).has_method("show_place"):
		(banner as Object).call("show_place", String(s["name"]), "Discovery", "Discovered")
	var lore := String(d.get("lore", ""))
	if lore != "":
		_say(lore)
	var soc := _mod("society")
	if soc:
		soc.call("learn", "lore:poi_%s" % String(s["poi"]), lore)
		var lead: Array = d.get("lead", [])
		if lead.size() == 2:
			soc.call("learn", String(lead[0]), String(lead[1]))
	_xp(int(d.get("xp", 10)), "discovered %s" % String(s["name"]))
	Life.record("explored_forest", 1.0)
	if kind == "poi_camp" or kind == "poi_battlefield" or kind == "poi_lore":
		Life.biography.add_highlight("Found %s." % String(s["name"]), _day())
	_grant_bundle(d, false)
	# Stock interactions (once-only rewards) are claimed at the spot; vistas and talkers have nothing more to hand out here.
	if kind == "poi_hermit" or kind == "poi_hunter":
		pass


## Gold / know-how / map reveal at once; items only when `with_items` (they come from the interaction).
func _grant_bundle(d: Dictionary, with_items: bool) -> void:
	if with_items:
		for pair: Array in d.get("items", []):
			Life.give(String(pair[0]), int(pair[1]))
			if String(pair[0]) == "burnt_map_fragment":
				HV.read_fragment()
			_say("Found %d %s." % [int(pair[1]), Life.item_name(String(pair[0]))])
		var g := int(d.get("gold", 0))
		if g > 0:
			Game.add_gold(g)
			_say("Found %d gold." % g)
	for f: String in d.get("know", []):
		_learn_know(f)


func _learn_know(fact: String) -> void:
	var c := _mod("construction")
	if c == null:
		return
	var known: Variant = c.get("known")
	if known is Dictionary and not (known as Dictionary).has(fact):
		(known as Dictionary)[fact] = true
		var names := {"build:fire": "fire-making", "build:carpentry": "carpentry", "build:masonry": "masonry", "build:architecture": "architecture"}
		_say("You have learned %s." % String(names.get(fact, fact)))


# --- interactables -------------------------------------------------------------------------------------------------------

func _refresh_spots(at: Vector2) -> void:
	var want: Dictionary = {}
	for s: Dictionary in _pois:
		var kind := String(s["kind"])
		if POIS.repeat_days(kind) == -1 and kind != "poi_vista":
			_ensure_station(s, at)
			continue
		if at.distance_to(s["pos"]) < SPOT_NEAR and _disc().is_discovered(_site_id(s)):
			want["p:" + String(s["poi"])] = {"pos": _spot_pos(s), "text": POIS.prompt_of(kind), "poi": s}
	if HV.enabled() and at.distance_squared_to(HV.CENTER) < 300.0 * 300.0:
		for n: Dictionary in HV.nodes():
			if at.distance_to(n["pos"]) < SPOT_NEAR:
				want["v:" + String(n["id"])] = {"pos": n["pos"], "text": String(n["prompt"]), "node": n}
	for key: String in _spots.keys():
		var old: Variant = _spots[key]
		if not want.has(key) or not _available(want[key]) or not is_instance_valid(old):
			if is_instance_valid(old):
				(old as Node).queue_free()
			_spots.erase(key)
	for key: String in want:
		if _spots.has(key) or not _available(want[key]):
			continue
		var w: Dictionary = want[key]
		var sp := Spot.new()
		sp.director = self
		sp.key = key
		sp.text = String(w["text"])
		sp.name = "Spot_" + key.replace(":", "_")
		sp.set_meta("spot", w)
		add_child(sp)
		var pp: Vector2 = w["pos"]
		sp.global_position = Vector3(pp.x, WorldGen.height(pp.x, pp.y) + 0.3, pp.y)
		sp.add_to_group("interactable")
		_spots[key] = sp


func _spot_pos(s: Dictionary) -> Vector2:
	var pl: Dictionary = POIS.placed.get(String(s["poi"]), {})
	var yaw := float(pl.get("yaw", 0.0))
	var p: Vector2 = s["pos"]
	if String(s["kind"]) == "poi_cache":
		return p + Vector2(sin(yaw), cos(yaw)) * 2.4
	return p


## A spot is on offer unless it was taken and has not grown back yet (or it is day and the Rift shimmer is night only).
func _available(w: Dictionary) -> bool:
	if w.has("poi"):
		var s: Dictionary = w["poi"]
		var kind := String(s["kind"])
		if kind == "poi_rift" and not _is_night():
			return false
		return _harvest_ready("poi:" + String(s["poi"]), POIS.repeat_days(kind))
	var n: Dictionary = w["node"]
	return _harvest_ready("res:" + String(n["id"]), int(n.get("days", 0)))


func _harvest_ready(key: String, days: int) -> bool:
	var k := "res:" + key if not key.begins_with("res:") else key
	if not _disc().noted(k):
		return true
	if days <= 0:
		return false
	return _day() - _disc().note_day(k) >= days


func use_spot(sp: Spot) -> void:
	var w: Dictionary = sp.get_meta("spot")
	if w.has("poi"):
		var s: Dictionary = w["poi"]
		var kind := String(s["kind"])
		var d := POIS.def(String(s["poi"]))
		if kind == "poi_vista":
			play_vista_pan(s)
			return
		_disc().note("res:poi:" + String(s["poi"]), _day())
		if kind == "poi_fishing":
			var roll := RandomNumberGenerator.new()
			roll.seed = hash([String(s["poi"]), _day()])
			if roll.randf() < 0.7:
				Life.give("silverfin", 1)
				_say("A silverfin! It fights like it has somewhere to be.")
			else:
				_say("The pool is silent. Nothing bites today.")
			return
		_grant_bundle(d, true)
		if kind == "poi_camp" and String(s["poi"]) == "cartographer":
			_say("Half a map, scorched at the edges. A ridge like a horseshoe, open to the south. You study it until you know it by heart.")
		else:
			_say(_flavour(kind))
		sp.queue_free()
		_spots.erase(sp.key)
		return
	var n: Dictionary = w["node"]
	_disc().note("res:" + String(n["id"]), _day())
	if n.has("know"):
		for f: String in n["know"]:
			_learn_know(f)
		_say("The carvings show how the old builders laid a beam and set a stone. You understand them.")
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([String(n["id"]), _day()])
		var amount := rng.randi_range(int(n["min"]), int(n["max"]))
		Life.give(String(n["item"]), amount)
		_say("Gathered %d %s." % [amount, Life.item_name(String(n["item"]))])
		Life.record("gathered_herbs", 0.5)
	sp.queue_free()
	_spots.erase(sp.key)


func _flavour(kind: String) -> String:
	match kind:
		"poi_shrine": return "You leave a small offering. The air feels lighter, and something cool is left in your palm."
		"poi_lore": return "You trace the carvings with your fingers until they make sense."
		"poi_cache": return "Your spade strikes something hard. A box, sealed with wax."
		"poi_battlefield": return "You turn over shields and buckles, and pocket what is worth carrying."
		"poi_rift": return "The air folds around your hand. A shard of violet glass drops into your palm, warm."
		"poi_herbs": return "You gather the pale petals carefully."
		_: return "You search the place carefully."


## A short optional pan from a vista (not a discovery: repeatable, skippable).
func play_vista_pan(s: Dictionary) -> void:
	if playing:
		return
	var pl := _player()
	if pl == null:
		return
	playing = true
	var yaw := float(POIS.placed.get(String(s["poi"]), {}).get("yaw", 0.0))
	var p: Vector2 = s["pos"]
	var eye := Vector3(p.x, WorldGen.height(p.x, p.y) + 2.0, p.y)
	var a := yaw - 0.9
	var b := yaw + 0.9
	var la := Vector3(p.x + sin(a) * 120.0, eye.y + 6.0, p.y + cos(a) * 120.0)
	var lb := Vector3(p.x + sin(b) * 120.0, eye.y + 6.0, p.y + cos(b) * 120.0)
	var hud := _hud()
	vista = Vista.new()
	add_child(vista)
	vista.finished.connect(func(_skipped: bool) -> void:
		playing = false
		vista = null)
	vista.play({"shots": Vista.pan(eye, la, lb, 5.5), "kicker": "A view worth the climb", "title": String(s["name"]), "small": true,
		"title_at": 0.8, "freeze": [pl], "hide": [hud] if hud else []})


# --- Interaction dispatch (same pattern as ForageNodes: main.gd only drives Stations and doors) ---------------------------

func _poll_interact() -> void:
	var pl := _player()
	var menu_open := false
	var h := _hud()
	if h and h.has_method("is_menu_open"):
		menu_open = bool(h.call("is_menu_open"))
	var was := _menu_was_open
	_menu_was_open = menu_open
	if pl == null or menu_open or was or playing or _spots.is_empty():
		return
	if not Input.is_action_just_pressed("interact") or not pl.has_method("nearest_interactable"):
		return
	var target: Variant = pl.call("nearest_interactable")
	if target is Spot and (target as Spot).director == self:
		(target as Spot).use()


# --- The hermit and the old hunter (Stations: main.gd opens their menu) ------------------------------------------------------

func _ensure_station(s: Dictionary, at: Vector2) -> void:
	var key := String(s["poi"])
	var near: bool = at.distance_to(s["pos"]) < 140.0
	if near and not _stations.has(key):
		var st := Station.new(("Brother Anselm" if key == "hermit" else "Old Corwen"), "Talk", _menu_for.bind(key))
		add_child(st)
		var p: Vector2 = s["pos"]
		var yaw := float(POIS.placed.get(key, {}).get("yaw", 0.0))
		var spot := p + Vector2(sin(yaw + 0.6), cos(yaw + 0.6)) * 3.6
		st.global_position = Vector3(spot.x, WorldGen.height(spot.x, spot.y), spot.y)
		var body := Assets.character("Elder_Man" if key == "hermit" else "Rogue_Hooded", 1.72, [])
		if body:
			st.add_child(body)
			body.rotation.y = yaw + PI
			var ap := Assets.animation_player(body)
			if ap:
				for a in ["Idle", "Sitting_Idle"]:
					if ap.has_animation(a):
						ap.play(a)
						break
		_stations[key] = st
	elif not near and _stations.has(key) and at.distance_to(s["pos"]) > 220.0:
		var old: Node = _stations[key]
		_stations.erase(key)
		if is_instance_valid(old):
			old.queue_free()


func _menu_for(key: String) -> Dictionary:
	var soc := _mod("society")
	if key == "hermit":
		return {"title": "Brother Anselm", "body": "\"Sit. The pot is never empty, and I have been listening to this valley for forty winters. It has told me a good deal, if you care to hear it.\"",
			"options": [
				["Ask what he has heard", func() -> String:
					if soc:
						soc.call("learn", "lead:hermit_west", "Anselm says the stagborn winter somewhere west of Cindermoor, past where the land folds under the ridge, and that he has never once found their tracks leaving it.")
					return "\"The stagborn go west in the dry months and do not come back thin. Past Cindermoor the land folds under a ridge, and they walk into it. I never saw them walk out.\""],
				["Ask for a remedy", func() -> String:
					if _disc().noted("res:anselm_dew"):
						return "\"I have given you what I can spare. Come back when the moon has turned.\""
					_disc().note("res:anselm_dew", _day())
					Life.give("spirit_dew", 1)
					Life.give("healing_herb", 3)
					return "He presses a flask and a bundle of herbs into your hands. \"Spirit dew. Do not ask where.\""],
				["Ask him to teach you", func() -> String:
					_learn_know("build:fire")
					return "\"A fire is a patience you can learn. Lay the stones so, and feed it slowly.\""],
			]}
	return {"title": "Old Corwen", "body": "\"Well now. You don't look like a poacher. Sit, sit. Ever tracked a stag through ferns? No? Then you'll want to hear this.\"",
		"options": [
			["Ask about stag tracks", func() -> String:
				var line: String = HV.HUNTER_LINES[_day() % HV.HUNTER_LINES.size()]
				if soc:
					soc.call("learn", "lead:hidden_vale_tracks", line)
				return "\"" + line + "\""],
			["Ask about these parts", func() -> String:
				return "\"Wolves in the north wood, boars in the birches, and something in the west I have no name for. The ridges fold in on themselves out there.\""],
		]}


# --- Rift anomalies (night only) -------------------------------------------------------------------------------------

var _rifts: Dictionary = {}      # poi id -> {root, mat}
var _rift_shader: Shader


## A pulsing violet shimmer over each Rift POI, only near the player and only after dark.
func _update_rifts() -> void:
	var h := _hour()
	var night := clampf((h - 19.0) / 1.5, 0.0, 1.0) if h >= 19.0 else clampf((6.0 - h) / 1.5, 0.0, 1.0)
	var pp := Vector2(focus.x, focus.z)
	for s: Dictionary in _pois:
		if String(s["kind"]) != "poi_rift":
			continue
		var id := String(s["poi"])
		var near: bool = pp.distance_squared_to(s["pos"]) < 150.0 * 150.0 and night > 0.01
		if near and not _rifts.has(id):
			_rifts[id] = _make_rift(s)
		elif _rifts.has(id) and not near:
			var old: Dictionary = _rifts[id]
			(old["root"] as Node).queue_free()
			_rifts.erase(id)
		if _rifts.has(id):
			(_rifts[id]["mat"] as ShaderMaterial).set_shader_parameter("strength", night)


func _make_rift(s: Dictionary) -> Dictionary:
	if _rift_shader == null:
		_rift_shader = Shader.new()
		_rift_shader.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 tint : source_color = vec3(0.62, 0.34, 1.0);
uniform float strength = 0.0;
void fragment() {
	float fres = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	float pulse = 0.6 + 0.4 * sin(TIME * 1.7 + UV.y * 7.0);
	ALBEDO = tint * (0.18 + fres) * pulse * strength;
	ALPHA = 1.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _rift_shader
	var root := Node3D.new()
	root.name = "RiftShimmer_" + String(s["poi"])
	add_child(root)
	var p: Vector2 = s["pos"]
	root.global_position = Vector3(p.x, WorldGen.height(p.x, p.y) + 1.7, p.y)
	var sph := SphereMesh.new()
	sph.radius = 1.6
	sph.height = 3.6
	sph.radial_segments = 24
	sph.rings = 12
	var mi := MeshInstance3D.new()
	mi.mesh = sph
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var ring := TorusMesh.new()
	ring.inner_radius = 2.4
	ring.outer_radius = 2.7
	ring.rings = 24
	ring.ring_segments = 8
	var rm := MeshInstance3D.new()
	rm.mesh = ring
	rm.material_override = mat
	rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rm.rotation = Vector3(0.6, 0.0, 0.3)
	root.add_child(rm)
	var tw := rm.create_tween().set_loops()
	tw.tween_property(rm, "rotation:y", TAU, 9.0).from(0.0)
	return {"root": root, "mat": mat}
