extends Node3D
## One running micro event: builds its cast and props from a catalogue entry's template and parameters
## (scripts/population/micro_catalog.gd), runs for a while, and tears itself down. The director
## (micro_events.gd) decides WHICH scene and WHEN; this decides WHERE and HOW it looks.
##
## Templates (entry["tpl"]): vehicle, walkers, vignette, chase, eject, kids, procession, shutters, lamp, gate,
## fire, broken_cart, carry. Each lays out sites from the settlement plan (gates, plaza, inn door, temple front,
## well, stalls, drill yard, streets, house doors), routes along the street graph, and queues actions on
## MicroActor bodies. All randomness comes from `rng`, seeded by the director, so a scene is reproducible.
##
## Hooks into the rest of the game: NpcWorld.report (fire, fight, festival, funeral, scream), NpcWorld.report_crime
## (thefts, with the NPC as culprit), LivingEvents (clangs), realm/news.gd (the town crier's real news),
## realm/society.gd (helping a stranded carter earns standing), Game gold.

const MicroActor := preload("res://scripts/population/micro_actor.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const UtilityBrain := preload("res://scripts/population/utility_brain.gd")
const Schedule := preload("res://scripts/population/schedule.gd")
const TownMood := preload("res://scripts/population/town_mood.gd")
const StreetGraph := preload("res://scripts/population/street_graph.gd")

const KIND_OF := {"FIRE": 0, "FIGHT": 1, "CRIME": 2, "FESTIVAL": 3, "SCREAM": 4, "FUNERAL": 5}
## Role -> [Assets.character look, height]; arrays are picked by cast index.
const ROLES := {
	"villager": [["Rogue_Hooded", 1.7], ["Barbarian", 1.74], ["Mage", 1.66], ["Rogue", 1.7]],
	"worker": [["Barbarian", 1.74], ["Rogue", 1.7]],
	"woman": [["Mage", 1.66]],
	"merchant": [["Trader", 1.7]],
	"guard": [["Knight", 1.78]],
	"sergeant": [["Mercenary", 1.82]],
	"noble": [["Noble", 1.74]],
	"monk": [["Monk", 1.7]],
	"child": [["Child_Boy", 1.2], ["Child_Girl", 1.2]],
	"elder": [["Elder_Man", 1.6], ["Elder_Woman", 1.55]],
	"adventurer": [["Mercenary", 1.8], ["Hunter", 1.74], ["Herbalist", 1.66], ["Plate_Knight", 1.84], ["Mage", 1.7]],
	"hunter": [["Hunter", 1.74]],
	"baker": [["Baker", 1.7]],
	"innkeeper": [["Innkeeper", 1.74]],
	"smith": [["Blacksmith", 1.76]],
	"thief": [["Rogue_Hooded", 1.7]],
	"drunk": [["Barbarian", 1.74], ["Rogue_Hooded", 1.7]],
	"bandit": [["Bandit", 1.78]],
	"soldier": [["Knight", 1.78], ["Mercenary", 1.8]],
	"bard": [["Trader", 1.7], ["Rogue", 1.7]],
}

var entry: Dictionary = {}
var p: Dictionary = {}
var sid := -1
var rng := RandomNumberGenerator.new()
var director: Node
var actors: Array = []
var extras: Array = []          # nodes owned by the scene (props, lights) freed with it
var elapsed := 0.0
var duration := 40.0
var finished := false
var anchor := Vector2.INF       # where the player should look
var station: Node3D
var announce := ""              # one line for the debug log / tests

var graph: StreetGraph
var plan: Dictionary = {}
var centre := Vector2.ZERO
var wall_r := 60.0
var plaza_r := 12.0
var player := Vector2.ZERO
var pfwd := Vector2.DOWN
var _sites_cache := {}
var _spawned := 0
var _unfinished := 0


func setup(e: Dictionary, p_sid: int, seed_i: int, player_pos: Vector2, player_forward: Vector2, p_director: Node) -> bool:
	entry = e
	p = e.get("p", {})
	sid = p_sid
	director = p_director
	rng.seed = seed_i
	player = player_pos
	pfwd = player_forward.normalized() if player_forward.length() > 0.1 else Vector2.DOWN
	var s: Dictionary = WorldGen.settlements[sid]
	plan = s.get("plan", {})
	centre = s["pos"]
	wall_r = float(plan.get("wall_radius", float(s["radius"])))
	plaza_r = float(plan.get("plaza_r", 12.0))
	graph = StreetGraph.for_settlement(sid) as StreetGraph
	var dur: Array = e.get("dur", [40, 60])
	duration = rng.randf_range(float(dur[0]), float(dur[1]))
	name = "Micro_" + String(e["id"])
	var ok := false
	match String(e["tpl"]):
		"vehicle": ok = _t_vehicle()
		"walkers": ok = _t_walkers()
		"vignette": ok = _t_vignette()
		"chase": ok = _t_chase()
		"eject": ok = _t_eject()
		"kids": ok = _t_kids()
		"procession": ok = _t_procession()
		"shutters": ok = _t_shutters()
		"lamp": ok = _t_lamp()
		"gate": ok = _t_gate()
		"fire": ok = _t_fire()
		"broken_cart": ok = _t_broken_cart()
		"carry": ok = _t_carry()
	if ok:
		var rep: Dictionary = p.get("report", {})
		if not rep.is_empty() and anchor != Vector2.INF:
			NpcWorld.report(int(KIND_OF.get(String(rep["kind"]), 3)), anchor, float(rep.get("radius", 28.0)), duration + 8.0,
				float(rep.get("strength", 0.8)), sid)
		announce = "%s at %s" % [String(e["id"]), str(anchor.snapped(Vector2.ONE))]
	return ok


func _process(delta: float) -> void:
	if finished:
		return
	elapsed += delta
	var alive := 0
	for a in actors:
		if is_instance_valid(a) and not (a as Node).is_queued_for_deletion():
			alive += 1
	if _spawned > 0 and alive == 0 and elapsed > 2.0:
		finish()
	elif elapsed > duration + 45.0:
		finish()
	elif anchor != Vector2.INF and player.distance_to(anchor) > 140.0 and elapsed > 6.0:
		finish()


## Free everything (actors, props, lights, the help station).
func finish() -> void:
	if finished:
		return
	finished = true
	for a in actors:
		if is_instance_valid(a):
			(a as Node).queue_free()
	for n in extras:
		if is_instance_valid(n):
			(n as Node).queue_free()
	if station != null and is_instance_valid(station):
		station.queue_free()
	if director != null and director.has_method("on_scene_finished"):
		director.call("on_scene_finished", self)
	queue_free()


## Live actors that have a body (the director's budget).
func actor_count() -> int:
	var n := 0
	for a in actors:
		if is_instance_valid(a):
			n += 1
	return n


func on_actor_built(_a: Node) -> void:
	pass


# ================================================================ casting helpers
func _look(role: String, i: int) -> Array:
	var list: Array = ROLES.get(role, ROLES["villager"])
	return list[posmod(i, list.size())]


func _human(role: String, at: Vector2, yaw := 0.0, i := -1, scale := 1.0) -> Node3D:
	var idx := i if i >= 0 else _spawned
	var l: Array = _look(role, idx)
	var a := MicroActor.human(String(l[0]), float(l[1]) * scale, at, yaw)
	return _adopt(a)


func _animal(kind: String, at: Vector2, yaw := 0.0, scale := 1.0) -> Node3D:
	return _adopt(MicroActor.animal(kind, at, yaw, scale))


func _vehicle(body: String, animals: Array, at: Vector2, yaw := 0.0, hitch := 2.4) -> Node3D:
	return _adopt(MicroActor.vehicle(body, animals, at, yaw, hitch))


func _prop(body: Variant, at: Vector2, yaw := 0.0) -> Node3D:
	return _adopt(MicroActor.prop(body, at, yaw))


func _adopt(a: Node3D) -> Node3D:
	a.set("scene", self)
	add_child(a)
	actors.append(a)
	_spawned += 1
	return a


## A node the scene owns that is not an actor (a light, a decal).
func _own(n: Node3D) -> Node3D:
	add_child(n)
	extras.append(n)
	return n


func _say(cat: String, i := 0) -> String:
	if cat == "@news":
		return _news_line(i)
	return NpcWorld.line(cat, i + sid * 31, int(rng.randi() % 1000))


## One line of the town crier: the settlement's real notices (realm/news.gd board items), the tavern gossip or,
## at war, the state of the war; a generic proclamation when the realm has nothing to say.
func _news_line(i: int) -> String:
	var lines: Array = []
	var life: Node = get_node_or_null("/root/Life")
	var realm: RefCounted = life.get("realm") if life != null else null
	if realm != null:
		var news: Variant = realm.call("mod", "news")
		if news != null:
			for e: Dictionary in news.call("news_for", sid, "board", 4):
				lines.append(String(e["text"]))
			if lines.size() < 3:
				var t := String(news.call("tavern_line_at", centre, int(rng.randi() % 50)))
				if t != "":
					lines.append(t)
	var war: Variant = life.get("war") if life != null else null
	if war != null and war.has_method("is_at_war") and bool(war.call("is_at_war")):
		lines.append("The realm is at war with %s. The levy is called." % String(war.call("enemy_id")).capitalize())
	if lines.is_empty():
		return NpcWorld.line("crier", i + sid, int(rng.randi() % 1000))
	return String(lines[posmod(i + int(rng.randi() % 7), lines.size())])


# ================================================================ geometry helpers
func _yaw_of(v: Vector2) -> float:
	return atan2(v.x, v.y)


func _path_len(path: PackedVector2Array) -> float:
	var d := 0.0
	for i in range(1, path.size()):
		d += path[i - 1].distance_to(path[i])
	return d


func _route(a: Vector2, b: Vector2) -> PackedVector2Array:
	if graph != null:
		var r := graph.route(a, b)
		if r.size() >= 2:
			return r
	return PackedVector2Array([a, b])


## Spots where something of `kind` can be placed (cached per scene).
func _sites(kind: String) -> Array:
	if _sites_cache.has(kind):
		return _sites_cache[kind]
	var out: Array = []
	var places := NpcWorld.places_of(sid)
	match kind:
		"gate":
			for g in plan.get("gates", []):
				out.append(centre + Vector2(cos(float(g)), sin(float(g))) * (wall_r - 3.5))
		"plaza":
			for i in 8:
				var a := TAU * i / 8.0 + 0.3
				out.append(centre + Vector2(cos(a), sin(a)) * plaza_r * 0.8)
		"plaza_c":
			out.append(centre)
		"inn":
			if graph != null and graph.inn_door != Vector2.INF:
				out.append(graph.inn_door)
		"temple":
			var pl := UtilityBrain.places(sid, graph)
			if pl["shrine"] != Vector2.INF:
				out.append(pl["shrine"])
			else:
				out.append(centre + Vector2(0.0, plaza_r))
		"well":
			var pl2 := UtilityBrain.places(sid, graph)
			if pl2["well"] != Vector2.INF:
				out.append(pl2["well"])
		"stall":
			var stalls: PackedVector2Array = places.get("stalls", PackedVector2Array())
			var yaws: PackedFloat32Array = places.get("stall_yaw", PackedFloat32Array())
			for i in stalls.size():
				out.append(stalls[i] + Vector2(sin(yaws[i]), cos(yaws[i])) * 2.0)
		"drill":
			out.append(Schedule.spot(WorldGen.settlements[sid], Schedule.Phase.TRAIN, 0, 1))
		"street":
			for st: Dictionary in plan.get("streets", []):
				var a: Vector2 = st["a"]
				var b: Vector2 = st["b"]
				var n := maxi(1, int(a.distance_to(b) / 9.0))
				for k in n + 1:
					var q := a.lerp(b, float(k) / float(n))
					if q.distance_to(centre) > plaza_r * 0.9 and q.distance_to(centre) < wall_r - 6.0:
						out.append(q)
		"door":
			var k := 0
			for lot: Dictionary in plan.get("lots", []):
				k += 1
				if k % 2 == 0:
					continue
				var yaw: float = lot["yaw"]
				var d := (lot["pos"] as Vector2) + Vector2(sin(yaw), cos(yaw)) * 4.2
				out.append(graph.push_out(d, 0.5) if graph != null else d)
		_:
			pass
	_sites_cache[kind] = out
	return out


## A site of `kind` within [dmin, dmax] of the player, preferring ones in front of them; Vector2.INF if none.
## `avoid` lists points to keep at least 12 m from (a second site of a scene).
func _pick_site(kind: String, dmin := 8.0, dmax := 55.0, avoid := PackedVector2Array()) -> Vector2:
	var best := Vector2.INF
	var best_s := -INF
	for q: Vector2 in _sites(kind):
		var d := q.distance_to(player)
		if d < dmin or d > dmax:
			continue
		var skip := false
		for o in avoid:
			if q.distance_to(o) < 12.0:
				skip = true
		if skip:
			continue
		var dir := (q - player) / maxf(d, 0.1)
		var s := pfwd.dot(dir) * 0.8 + rng.randf() * 0.5 - d * 0.004
		if s > best_s:
			best_s = s
			best = q
	return best


## A pair of sites for something passing the player: starts `from_kind` side, ends `to_kind` side, the line
## between them close to the player. Returns [a, b] or [].
func _pass_pair(from_kind: String, to_kind: String, near := 24.0) -> Array:
	var best: Array = []
	var best_s := INF
	var from_sites := _cap_sites(_sites(from_kind), 15.0, 100.0)
	var to_sites := _cap_sites(_sites(to_kind), 0.0, 120.0)
	# A big town's gates are 110 m from its square: when none is near, the scene enters from a street instead.
	if from_sites.is_empty():
		from_sites = _cap_sites(_sites("street"), 38.0, 85.0)
	if to_sites.is_empty():
		to_sites = _cap_sites(_sites("street"), 30.0, 110.0)
	for a: Vector2 in from_sites:
		for b: Vector2 in to_sites:
			if a.distance_to(b) < 30.0:
				continue
			var q := Geometry2D.get_closest_point_to_segment(player, a, b)
			var miss := q.distance_to(player)
			var s := miss + rng.randf() * 8.0 + (0.0 if (a - player).dot(b - player) < 0.0 else 20.0)
			if s < best_s:
				best_s = s
				best = [a, b]
	if best.is_empty() or best_s > near + 40.0:
		return []
	return best


## At most 18 sites within [dmin, dmax] of the player (a deterministic subsample for long street lists).
func _cap_sites(list: Array, dmin: float, dmax: float) -> Array:
	var out: Array = []
	for q: Vector2 in list:
		var d := q.distance_to(player)
		if d >= dmin and d <= dmax:
			out.append(q)
	if out.size() <= 18:
		return out
	var step := float(out.size()) / 18.0
	var sub: Array = []
	for i in 18:
		sub.append(out[int(float(i) * step + rng.randf() * step * 0.99)])
	return sub


## The far exit a passer-by continues to after `b`: the gate (or street end) farthest from `from` that is not behind.
func _exit_from(b: Vector2, away_from: Vector2) -> Vector2:
	var best := b
	var best_d := 0.0
	for q: Vector2 in _sites("gate"):
		var d := q.distance_to(away_from)
		if d > best_d and q.distance_to(b) > 8.0:
			best_d = d
			best = q
	return best


## Positions along `path` for a follower: shifted sideways by `lat` and starting `back` metres behind its start.
func _member_path(path: PackedVector2Array, lat: float, back: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if path.size() < 2:
		return path
	var d0 := (path[1] - path[0]).normalized()
	out.append(path[0] - d0 * back + Vector2(-d0.y, d0.x) * lat)
	for i in path.size():
		var d: Vector2
		if i == 0:
			d = (path[1] - path[0]).normalized()
		elif i == path.size() - 1:
			d = (path[i] - path[i - 1]).normalized()
		else:
			d = ((path[i + 1] - path[i]).normalized() + (path[i] - path[i - 1]).normalized()).normalized()
			if d.length() < 0.1:
				d = (path[i + 1] - path[i]).normalized()
		var q := path[i] + Vector2(-d.y, d.x) * lat
		out.append(graph.push_out(q, 0.35) if graph != null else q)
	return out


func _first_dir(path: PackedVector2Array) -> Vector2:
	return (path[1] - path[0]).normalized() if path.size() > 1 else Vector2.DOWN


func _clip_list(v: Variant) -> Array:
	if v is Array:
		return v
	return [String(v)]


# ================================================================ template: vehicle
## A cart, wagon or carriage passes the player along the streets with its draught animal, driver and escorts;
## optionally it stops (delivery: carriers take crates to the stalls, passengers step out) and goes on.
func _t_vehicle() -> bool:
	var pair := _pass_pair(String(p.get("from", "gate")), String(p.get("to", "gate")))
	if pair.is_empty():
		return false
	var a: Vector2 = pair[0]
	var b: Vector2 = pair[1]
	var path := _route(a, b)
	if path.size() < 2:
		return false
	anchor = player
	var speed := float(p.get("speed", 1.5))
	var d0 := _first_dir(path)
	var body := String(p.get("body", "cart"))
	var v := _vehicle(body, p.get("animals", ["horse_draft"]), a, _yaw_of(d0), float(p.get("hitch", 2.6)))
	var stop := float(p.get("stop", 0.0))
	var exit_pt := _exit_from(b, a)
	var tail := _route(b, exit_pt) if stop > 0.0 and exit_pt.distance_to(b) > 10.0 else PackedVector2Array()
	v.walk(path, speed)
	if stop > 0.0:
		v.wait(stop)
		if tail.size() > 1:
			v.walk(tail, speed)
	v.vanish()
	# Driver walks by the animal's head.
	var driver := _human(String(p.get("driver", "worker")), a, _yaw_of(d0), 0)
	var dpath := _member_path(path, 1.5, -2.2)
	if String(p.get("bark", "")) != "" and stop <= 0.0:
		driver.say(_say(String(p["bark"]), 2), 3.2)
	driver.walk(dpath, speed, "Walking_A")
	if stop > 0.0:
		driver.say(_say(String(p.get("bark", "delivery")), 1), 3.0)
		driver.wait(stop)
		if tail.size() > 1:
			driver.walk(_member_path(tail, 1.5, -2.2), speed)
	driver.vanish()
	var k := 0
	for esc: String in p.get("escorts", []):
		var lat := (-1.4 if k % 2 == 0 else 1.4)
		var back := 3.5 + float(k) * 1.6
		var e := _human(esc, a, _yaw_of(d0), k + 1)
		e.walk(_member_path(path, lat, back), speed, "Life_Walk_March" if esc == "guard" or esc == "soldier" else "Walking_A")
		if stop > 0.0:
			e.wait(stop)
			if tail.size() > 1:
				e.walk(_member_path(tail, lat, back), speed)
		e.vanish()
		k += 1
	# Carriers: walk behind the cart, and at the stop take crates to the nearest stalls.
	var stalls := _sites("stall")
	for ci in int(p.get("carriers", 0)):
		var c := _human("worker", a, _yaw_of(d0), ci + 3)
		var cp := _member_path(path, -0.9 + float(ci) * 1.8, 2.6)
		c.walk(cp, speed)
		if stop > 0.0 and not stalls.is_empty():
			var st: Vector2 = stalls[posmod(ci * 3 + rng.randi(), stalls.size())]
			var drop := _route(b, st)
			c.walk(drop, 1.1, "Walking_A", "Life_Carry_Crate_Upper")
			c.play("Life_Carry_Put_Down", 2.2)
			c.hold([])
			c.walk(_route(st, b), 1.2, "Walking_A")
			c.wait(maxf(stop - 14.0, 1.0))
			if tail.size() > 1:
				c.walk(_member_path(tail, 0.0, 2.0), speed)
		c.vanish()
	# Passengers step out at the destination and walk to the plaza.
	var pax: Array = p.get("passengers", [])
	var pi := 0
	for role: String in pax:
		var pa := _human(role, a, _yaw_of(d0), pi + 5)
		pa.walk(_member_path(path, -1.2 + float(pi) * 2.0, 1.4), speed, "Walking_A")
		var dest: Vector2 = _sites("plaza")[0] if not _sites("plaza").is_empty() else b
		pa.walk(_route(b, dest), 1.1, "Life_Walk_Proud" if role == "noble" else "Walking_A")
		pa.say(_say(String(p.get("pax_bark", "noble")), pi + 7), 3.4)
		pa.play(["Life_Social_Wave_Greet", "Life_Ambient_Look_Around"], 4.0)
		pa.wait(10.0)
		pa.vanish()
		pi += 1
	return true


# ================================================================ template: walkers
## A group walks past: members {role, clip, upper, hold}, same path, staggered behind each other.
func _t_walkers() -> bool:
	var pair := _pass_pair(String(p.get("from", "gate")), String(p.get("to", "plaza")), 30.0)
	if pair.is_empty():
		return false
	var a: Vector2 = pair[0]
	var b: Vector2 = pair[1]
	var path := _route(a, b)
	if path.size() < 2:
		return false
	anchor = player
	var speed := float(p.get("speed", 1.2))
	var d0 := _first_dir(path)
	var exit_pt := _exit_from(b, a)
	var tail := _route(b, exit_pt) if String(p.get("end", "leave")) == "leave" and exit_pt.distance_to(b) > 10.0 else PackedVector2Array()
	var members: Array = p.get("members", [])
	var after: Dictionary = p.get("after", {})
	var k := 0
	for m: Dictionary in members:
		var lat := float(m.get("lat", (-0.9 if k % 2 == 0 else 0.9)))
		var back := float(m.get("back", float(k) * 1.4))
		var h := _human(String(m.get("role", "villager")), a, _yaw_of(d0), k)
		var spd := float(m.get("speed", speed))
		var clip := String(m.get("clip", p.get("clip", "Walking_A")))
		if m.has("hold"):
			h.hold(m["hold"])
		if m.has("say"):
			h.say(_say(String(m["say"]), k + 2), 3.4)
		h.walk(_member_path(path, lat, back), spd, clip, String(m.get("upper", "")))
		if not after.is_empty():
			h.play(_clip_list(after.get("clips", ["Life_Ambient_Look_Around"])), float(after.get("t", 8.0)), b + _first_dir(path) * 4.0)
			if after.has("say") and k == 0:
				h.say(_say(String(after["say"]), 4), 3.4)
		if tail.size() > 1:
			h.walk(_member_path(tail, lat, back), spd, clip, String(m.get("upper", "")))
		if m.has("hold"):
			h.hold([])
		h.vanish()
		k += 1
	# Animals driven along: they trot ahead of and beside the walkers.
	var j := 0
	for an: String in p.get("animals", []):
		var off := (float(j % 3) - 1.0) * 1.3
		var ap := _animal(an, a, _yaw_of(d0))
		ap.walk(_member_path(path, off, -3.0 - float(j) * 1.1 + rng.randf() * 0.6), speed * 0.9)
		if tail.size() > 1:
			ap.walk(_member_path(tail, off, -2.0), speed * 0.9)
		ap.vanish()
		j += 1
	return true


# ================================================================ template: vignette
## People at a site doing things (a performer with a crowd, a sermon, the town crier, laundry, drills ...).
## members: {role, clips, off:[x,z] (m in the site frame, z towards the viewer), face, hold, say:[cat, every s]}.
func _t_vignette() -> bool:
	var site_kind := String(p.get("site", "plaza"))
	var site := _pick_site(site_kind, float(p.get("dmin", 8.0)), float(p.get("dmax", 42.0)))
	if site == Vector2.INF and bool(p.get("ahead_ok", true)):
		site = _ahead(float(p.get("ahead", 16.0)))
	if site == Vector2.INF:
		return false
	anchor = site
	var to_player := (player - site)
	var fwd := to_player.normalized() if to_player.length() > 1.0 else Vector2.DOWN
	match String(p.get("frame", "player")):
		"centre":
			fwd = (centre - site).normalized() if centre.distance_to(site) > 1.0 else fwd
		"inn":
			if graph != null and graph.inn_door != Vector2.INF:
				fwd = graph.inn_facing
	var side := Vector2(-fwd.y, fwd.x)
	var i := 0
	var members: Array = p.get("members", [])
	if p.has("grid"):
		members = _grid_members(p["grid"], p.get("grid_role", "guard"), p.get("grid_clips", ["Sword_Attack"]), p.get("sergeant", true))
	for m: Dictionary in members:
		var off: Array = m.get("off", [0.0, 0.0])
		var at := site + side * float(off[0]) + fwd * float(off[1])
		if graph != null:
			at = graph.push_out(at, 0.45)
		var face := String(m.get("face", "player"))
		var yaw := _yaw_of(fwd)
		match face:
			"away": yaw = _yaw_of(-fwd)
			"centre": yaw = _yaw_of((site - at) if site.distance_to(at) > 0.3 else fwd)
			"m0": yaw = _yaw_of(fwd)
		var h := _human(String(m.get("role", "villager")), at, yaw, i, float(m.get("scale", 1.0)))
		if m.has("hold"):
			h.hold(m["hold"])
		var tgt := player if face == "player" else (site if face == "centre" else at + Vector2.from_angle(PI * 0.5 - yaw) * 3.0)
		h.wait(float(m.get("delay", 0.0)))
		_loop_clips(h, _clip_list(m.get("clips", ["Idle"])), duration, tgt, m.get("say", []), i)
		h.vanish()
		i += 1
	# A ring of dancers / players facing the site.
	var ring: Dictionary = p.get("ring", {})
	if not ring.is_empty():
		var rn := int(ring.get("n", 6))
		for k in rn:
			var th := TAU * float(k) / float(rn)
			var rp := site + Vector2(cos(th), sin(th)) * float(ring.get("r", 2.4))
			if graph != null:
				rp = graph.push_out(rp, 0.4)
			var roles: Array = ring.get("roles", ["villager"])
			var dh := _human(String(roles[posmod(k, roles.size())]), rp, _yaw_of(site - rp), 40 + k)
			dh.wait(float(k) * 0.4)
			_loop_clips(dh, _clip_list(ring.get("clips", ["Dance"])), duration, site, [], 40 + k)
			dh.vanish()
	# Audience: a ring (open towards the player) of onlookers who react.
	var aud: Dictionary = p.get("audience", {})
	var n := int(aud.get("n", 0))
	for k in n:
		var base := atan2(fwd.y, fwd.x)
		var sweep := TAU - 1.5
		var th := base + 0.75 + sweep * (float(k) + 0.5) / float(maxi(n, 1))
		var r := rng.randf_range(float(aud.get("r0", 3.4)), float(aud.get("r1", 5.4)))
		var at2 := site + Vector2(cos(th), sin(th)) * r
		if graph != null:
			at2 = graph.push_out(at2, 0.45)
		var role := String(_clip_list(aud.get("roles", ["villager"]))[posmod(k, _clip_list(aud.get("roles", ["villager"])).size())])
		var aud_h := _human(role, at2, _yaw_of(site - at2), 20 + k)
		aud_h.wait(rng.randf_range(0.5, 6.0) + float(k) * 0.8)
		_loop_clips(aud_h, _clip_list(aud.get("clips", ["Life_Talk_Listen_Nod", "Life_Social_Laugh", "Life_Tavern_Cheer"])), duration, site,
			[String(aud.get("say", "audience")), 11.0] if aud.has("say") else [], 20 + k)
		aud_h.vanish()
	# Static props (a hat on the ground, a washing line, a lectern).
	for pr: Dictionary in p.get("props", []):
		var off2: Array = pr.get("off", [0.0, 0.0])
		var ppos := site + side * float(off2[0]) + fwd * float(off2[1])
		var node := Assets.building_node(String(pr["key"]), false)
		if node != null:
			node.position = Vector3(ppos.x, WorldGen.height(ppos.x, ppos.y), ppos.y)
			node.rotation.y = _yaw_of(fwd) + float(pr.get("yaw", 0.0))
			node.scale = Vector3.ONE * float(pr.get("scale", 1.0))
			_own(node)
	return true


## Queue `clips` (cycling) on `h` for `total` seconds, saying lines now and then.
func _loop_clips(h: Node3D, clips: Array, total: float, face_at: Vector2, say_spec: Array, i: int) -> void:
	var t := 0.0
	var k := i
	var said := 0.0
	var gap := float(say_spec[1]) if say_spec.size() > 1 else 0.0
	while t < total:
		var seg := rng.randf_range(4.0, 8.0)
		h.play(clips[posmod(k, clips.size())], seg, face_at)
		if gap > 0.0 and said <= t:
			h.say(_say(String(say_spec[0]), i + k), 3.4)
			said = t + gap + rng.randf() * 3.0
		t += seg
		k += 1


## Drill formation: `cols x rows` guards (+ a sergeant in front) facing the viewer.
func _grid_members(grid: Array, role: String, clips: Array, sergeant: bool) -> Array:
	var out: Array = []
	var cols := int(grid[0])
	var rows := int(grid[1])
	var sp := float(grid[2])
	for r in rows:
		for c in cols:
			out.append({"role": role, "clips": clips, "face": "player",
				"off": [(float(c) - float(cols - 1) * 0.5) * sp, -float(r) * sp - 1.5],
				"delay": float(c + r * cols) * 0.35, "hold": [{"id": "spear", "hand": "r"}] if rows * cols < 0 else []})
	if sergeant:
		out.append({"role": "sergeant", "clips": ["Life_Guard_Attention", "Life_Social_Point_Directions", "Life_Market_Call_Out"], "face": "centre",
			"off": [0.0, 2.2], "say": ["shift", 8.0]})
	return out


## A spot a few metres in front of the player (snapped out of buildings), or INF.
func _ahead(dist: float) -> Vector2:
	var q := player + pfwd * dist + Vector2(-pfwd.y, pfwd.x) * rng.randf_range(-3.0, 3.0)
	if graph != null:
		q = graph.push_out(q, 0.6)
		if graph.inside(q, 0.6):
			return Vector2.INF
	return q


# ================================================================ template: chase
## Someone runs through the streets, pursued. runner {role, clip, upper, speed, say}, chasers [role], an
## optional victim left behind, crime reported at the start, `scream` (the alarm for monsters), `animals`.
func _t_chase() -> bool:
	var pair := _pass_pair(String(p.get("from", "plaza")), String(p.get("to", "gate")), 28.0)
	if pair.is_empty():
		pair = _pass_pair("street", "gate", 30.0)
	if pair.is_empty():
		return false
	var a: Vector2 = pair[0]
	var b: Vector2 = pair[1]
	var path := _route(a, b)
	if path.size() < 2:
		return false
	anchor = player
	var d0 := _first_dir(path)
	var run: Dictionary = p.get("runner", {})
	var speed := float(run.get("speed", 4.6))
	var role := String(run.get("role", "thief"))
	var runner: Node3D
	if p.has("runner_animal"):
		runner = _animal(String(p["runner_animal"]), a, _yaw_of(d0), 1.0)
		runner.walk(path, speed)
	else:
		runner = _human(role, a, _yaw_of(d0), 0)
		runner.walk(path, speed, String(run.get("clip", "Running_A")))
		if run.has("say"):
			runner._q.push_front({"a": "say", "text": _say(String(run["say"]), 3), "t": 2.6})
	runner.vanish()
	var delay := float(p.get("delay", 2.0))
	var k := 0
	for ch: String in p.get("chasers", []):
		var c := _human(ch, a - d0 * (2.5 + float(k) * 1.8), _yaw_of(d0), k + 1)
		c.wait(delay + float(k) * 0.8)
		if p.has("chaser_say") and k == 0:
			c.say(_say(String(p["chaser_say"]), 5), 3.0)
		var cp := _member_path(path, (-0.7 if k % 2 == 0 else 0.7), 0.0)
		c.walk(cp, speed * float(p.get("chaser_speed", 0.82)), "Running_A")
		c.play(["Life_Ambient_Wipe_Brow", "Life_Ambient_Look_Around"], 4.0, b)
		c.vanish()
		k += 1
	# Chickens (or other animals) scatter ahead of the runner.
	var j := 0
	for an: String in p.get("scatter", []):
		var off := Vector2(-d0.y, d0.x) * (float(j) - 1.0) * 1.2
		var s := _animal(an, a + d0 * (5.0 + float(j) * 2.0) + off, _yaw_of(d0))
		s.walk(_member_path(path, off.x * 0.5, -4.0 - float(j) * 1.5), speed * 0.7)
		s.vanish()
		j += 1
	# The victim: stands at the start gesturing after the runner.
	if p.has("victim"):
		var v := _human(String(p["victim"]), a - Vector2(-d0.y, d0.x) * 1.8, _yaw_of(d0), 9)
		v.say(_say(String(p.get("victim_say", "stop_thief")), 6), 3.2)
		v.play(["Life_Social_Argue_A", "Life_Social_Shake_Head", "Life_Social_Point_Directions"], 6.0, b)
		v.play(["Life_Mocap_Sad", "Life_Ambient_Look_Around"], 6.0)
		v.vanish()
	if p.has("crime"):
		var crime: Dictionary = p["crime"]
		var at := a
		var tree := get_tree()
		var town := sid
		tree.create_timer(float(crime.get("after", 1.0))).timeout.connect(func() -> void:
			NpcWorld.report_crime(tree, String(crime["kind"]), at, town, false))
	if bool(p.get("scream", false)):
		NpcWorld.report(NpcWorld.Kind.SCREAM, a, 38.0, 14.0, 0.8, sid)
	return true


# ================================================================ template: eject (tavern brawl / thrown-out drunk)
func _t_eject() -> bool:
	if graph == null or graph.inn_door == Vector2.INF or graph.inn_door.distance_to(player) > float(p.get("dmax", 60.0)):
		return false
	var door := graph.inn_door
	var out_dir := graph.inn_facing
	anchor = door + out_dir * 3.0
	var side := Vector2(-out_dir.y, out_dir.x)
	var fight := bool(p.get("fight", false))
	var keeper := _human("innkeeper", door - out_dir * 0.4, _yaw_of(out_dir), 0)
	var drunk := _human("drunk", door - out_dir * 0.2, _yaw_of(out_dir), 1)
	var drunk_to := door + out_dir * 4.5 + side * 1.2
	drunk_to = graph.push_out(drunk_to, 0.5)
	if not fight:
		keeper.wait(1.5)
		keeper.play(["Life_Social_Argue_A", "Life_Social_Shake_Head"], 2.6, door + out_dir * 2.0)
		keeper.say(_say("barkeep", 2), 3.0)
		keeper.play(["Life_Social_Shake_Head", "Life_Social_Argue_B"], 3.0, door + out_dir * 3.0)
		keeper.play("Life_Ambient_Wipe_Brow", 2.0)
		keeper.walk(PackedVector2Array([door - out_dir * 1.2]), 1.1)
		keeper.vanish()
		drunk.wait(1.5)
		drunk.walk(PackedVector2Array([drunk_to]), 0.9, "Life_Walk_Drunk")
		drunk.say(_say("drunk", 3), 3.6)
		drunk.play(["Life_Rest_Sit_Ground", "Sitting_Idle_Loop", "Sitting_Idle"], 7.0, door)
		drunk.play(["Life_Mocap_Cry", "Life_Social_Shrug"], 3.0, door)
		var home := _pick_site("street", 40.0, 90.0)
		var leave_to := _route(drunk_to, home) if home != Vector2.INF else PackedVector2Array([drunk_to + side * 20.0])
		drunk.walk(leave_to, 0.7, "Life_Walk_Drunk")
		drunk.vanish()
		NpcWorld.report(NpcWorld.Kind.FIGHT, drunk_to, 16.0, 12.0, 0.45, sid)
	else:
		# Two drunks come to blows in front of the inn; the watch breaks it up.
		var other := _human("drunk", door + side * 1.0, _yaw_of(-out_dir), 2)
		keeper.wait(0.5)
		keeper.walk(PackedVector2Array([door + out_dir * 1.0]), 1.0)
		keeper.say(_say("barkeep", 4), 3.0)
		keeper.play(["Life_Social_Argue_A"], 3.0, drunk_to)
		keeper.vanish()
		var mid := door + out_dir * 3.2
		drunk.walk(PackedVector2Array([mid - side * 0.6]), 0.9, "Life_Walk_Drunk")
		other.walk(PackedVector2Array([mid + side * 0.6]), 0.9, "Life_Walk_Drunk")
		for d: Node3D in [drunk, other]:
			d.say(_say("drunk", 5), 2.6)
			d.play(["Punch_Jab", "Punch_Cross", "Life_Social_Argue_A"], 3.0, mid)
			d.play(["Hit_Chest", "Life_Social_Argue_B"], 1.4, mid)
			d.play(["Punch_Cross", "Punch_Jab"], 3.5, mid)
		NpcWorld.report(NpcWorld.Kind.FIGHT, mid, 34.0, 26.0, 1.0, sid)
		var gp := _sites("gate")
		var gate_from: Vector2 = gp[0] if not gp.is_empty() else centre
		for gi in 2:
			var g := _human("guard", gate_from + Vector2(float(gi) * 1.2, 0.0), 0.0, gi + 3)
			g.wait(2.0)
			g.say(_say("guard_respond", gi), 2.6)
			g.walk(_route(gate_from, mid + out_dir * 3.0), 3.4, "Running_A")
			g.play(["Life_Guard_Attention", "Life_Social_Point_Directions"], 5.0, mid)
			g.walk(_route(mid, centre), 1.0, "Life_Walk_March")
			g.vanish()
		drunk.play(["Life_Rest_Sit_Ground", "Sitting_Idle"], 6.0, mid)
		drunk.walk(_route(mid, centre + Vector2(plaza_r, 0.0)), 0.7, "Life_Walk_Drunk")
		drunk.vanish()
		other.play(["Life_Social_Shrug", "Life_Social_Shake_Head"], 5.0, mid)
		other.walk(PackedVector2Array([door]), 0.8, "Life_Walk_Drunk")
		other.vanish()
	return true


# ================================================================ template: kids
func _t_kids() -> bool:
	var site := _pick_site(String(p.get("site", "plaza")), 6.0, 45.0)
	if site == Vector2.INF:
		site = _ahead(14.0)
	if site == Vector2.INF:
		return false
	anchor = site
	var n := int(p.get("n", 3))
	var r := float(p.get("radius", 7.0))
	for k in n:
		var at := site + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.0, r * 0.6)
		if graph != null:
			at = graph.push_out(at, 0.4)
		var kid := _human("child", at, rng.randf() * TAU, k)
		var t := 0.0
		var cur := at
		while t < duration:
			var nxt := site + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.5, r)
			if graph != null:
				nxt = graph.push_out(nxt, 0.4)
				if not graph.clear_line(cur, nxt, 0.3):
					nxt = site
			var sp := rng.randf_range(2.4, 3.4)
			kid.walk(PackedVector2Array([nxt]), sp, "Running_A")
			if rng.randf() < 0.45:
				kid.play(_clip_list(p.get("clips", ["Life_Kid_Tag_Touch", "Life_Kid_Hopscotch", "Life_Kid_Clap_Jump"])), rng.randf_range(1.6, 3.2), site)
			if k == 0 and rng.randf() < 0.3:
				kid.say(_say("child_play", t as int), 2.4)
			t += cur.distance_to(nxt) / sp + 2.0
			cur = nxt
		kid.vanish()
	return true


# ================================================================ template: procession
## Funeral (bier, bearers, priest, mourners to the temple, who then kneel) or wedding (couple, musicians, children).
func _t_procession() -> bool:
	var wedding := String(p.get("kind", "funeral")) == "wedding"
	var temple := _sites("temple")
	if temple.is_empty():
		return false
	var dest: Vector2 = temple[0]
	var from := _pick_site("door", 25.0, 80.0)
	if from == Vector2.INF or from.distance_to(dest) < 20.0:
		var g := _sites("gate")
		if g.is_empty():
			return false
		from = g[0]
	var path := _route(from, dest)
	if path.size() < 2:
		return false
	var mid := path[path.size() / 2]
	anchor = dest if player.distance_to(dest) < player.distance_to(mid) else mid
	var d0 := _first_dir(path)
	var speed := 0.72 if not wedding else 0.95
	var k := 0
	var dest_face := (dest - path[path.size() - 2]).normalized()
	if not wedding:
		# Bier carried by four, priest ahead, mourners behind.
		var bier := _prop(func() -> Node3D: return _bier_node(), from, _yaw_of(d0))
		bier.walk(path, speed)
		bier.vanish()
		for bi in 4:
			var lat := -0.62 if bi % 2 == 0 else 0.62
			var back := -0.9 if bi < 2 else 0.95
			var bearer := _human("worker", from, _yaw_of(d0), bi)
			bearer.walk(_member_path(path, lat, back), speed, "Life_Walk_Sad")
			bearer.play(["Life_Social_Mourn_Stand", "Life_Mocap_Sad"], 14.0, dest + dest_face * 3.0)
			bearer.vanish()
		var priest := _human("monk", from, _yaw_of(d0), 5)
		priest.walk(_member_path(path, 0.0, -3.0), speed, "Life_Walk_Proud")
		priest.say(_say("funeral", 1), 4.0)
		priest.play(["Life_Pray_Stand", "Life_Talk_Emphatic"], 16.0, dest - dest_face * 3.0)
		priest.vanish()
		for mi in int(p.get("mourners", 5)):
			var lat2 := (-1.0 if mi % 2 == 0 else 1.0) * (0.8 + float(mi / 2) * 0.1)
			var m := _human("elder" if mi % 3 == 0 else ("woman" if mi % 2 == 0 else "villager"), from, _yaw_of(d0), mi + 6)
			m.walk(_member_path(path, lat2, 3.0 + float(mi) * 1.1), speed, "Life_Walk_Sad")
			m.play(["Life_Social_Mourn_Kneel", "Life_Social_Mourn_Stand", "Life_Mocap_Cry"], 18.0, dest + dest_face * 3.0)
			m.vanish()
		NpcWorld.report(NpcWorld.Kind.FUNERAL, dest, 30.0, duration + 40.0, 1.0, sid)
	else:
		for wi in 2:
			var couple := _human("villager" if wi == 0 else "woman", from, _yaw_of(d0), 30 + wi)
			couple.walk(_member_path(path, -0.45 + float(wi) * 0.9, -1.0), speed, "Life_Walk_Happy")
			couple.play(["Life_Social_Hug_A", "Life_Mocap_Happy", "Life_Tavern_Cheer"], 12.0, dest)
			couple.vanish()
		for mi in 3:
			var mus := _human("bard", from, _yaw_of(d0), mi + 34)
			mus.walk(_member_path(path, (float(mi) - 1.0) * 1.1, -3.0 - float(mi) * 0.4), speed, "Life_Walk_Happy")
			mus.hold([{"id": "lute" if mi != 1 else "flute", "hand": "l" if mi != 1 else "r"}])
			mus.play(["Life_Music_Lute" if mi != 1 else "Life_Music_Flute"], 20.0, dest)
			mus.vanish()
		for ki in 4:
			var kid := _human("child", from, _yaw_of(d0), ki)
			kid.walk(_member_path(path, rng.randf_range(-2.0, 2.0), 2.0 + float(ki) * 0.8), 1.5, "Life_Walk_Happy")
			kid.play(["Life_Kid_Clap_Jump", "Life_Kid_Skip", "Life_Kid_Tag_Touch"], 18.0, dest)
			kid.vanish()
		NpcWorld.report(NpcWorld.Kind.FESTIVAL, dest, 40.0, duration + 40.0, 0.9, sid)
	return true


func _bier_node() -> Node3D:
	var root := Node3D.new()
	var frame := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.75, 0.14, 2.0)
	frame.mesh = bm
	frame.position = Vector3(0.0, 0.95, 0.0)
	frame.material_override = Assets.flat_material(Color(0.28, 0.2, 0.13))
	root.add_child(frame)
	var cloth := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.6, 0.16, 1.7)
	cloth.mesh = cm
	cloth.position = Vector3(0.0, 1.07, 0.0)
	cloth.material_override = Assets.flat_material(Color(0.82, 0.78, 0.7))
	root.add_child(cloth)
	for i in 2:
		var pole := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.06, 0.06, 2.3)
		pole.mesh = pm
		pole.position = Vector3(-0.42 + float(i) * 0.84, 0.92, 0.0)
		pole.material_override = frame.material_override
		root.add_child(pole)
	return root


# ================================================================ template: carry (errands)
## Workers carry things between two sites and back: water, bread, crates, messages.
func _t_carry() -> bool:
	var from_kind := String(p.get("from", "well"))
	var to_kind := String(p.get("to", "door"))
	var a := _pick_site(from_kind, 6.0, 60.0)
	if a == Vector2.INF:
		return false
	var b := _pick_site(to_kind, 10.0, 70.0, PackedVector2Array([a]))
	if b == Vector2.INF:
		return false
	var path := _route(a, b)
	if path.size() < 2:
		return false
	anchor = a.lerp(b, 0.5)
	var upper := String(p.get("upper", "Life_Carry_Two_Buckets_Upper"))
	var role := String(p.get("role", "woman"))
	var back_path := _route(b, a)
	for k in int(p.get("n", 2)):
		var h := _human(role, a, _yaw_of(_first_dir(path)), k)
		h.wait(float(k) * 1.8)
		if p.has("fill"):
			h.play(_clip_list(p["fill"]), float(p.get("fill_t", 5.0)), a + _first_dir(path) * 2.0)
		for cyc in int(p.get("cycles", 2)):
			h.walk(_member_path(path, float(k) * 0.5, 0.0), float(p.get("speed", 1.0)), "Walking_A", upper)
			h.play(_clip_list(p.get("drop", ["Life_Carry_Put_Down"])), 2.4, b)
			if cyc == 0 and p.has("say"):
				h.say(_say(String(p["say"]), k), 3.2)
			h.walk(_member_path(back_path, float(k) * 0.5, 0.0), float(p.get("back_speed", 1.2)), "Walking_A")
		h.hold([])
		h.vanish()
	return true


# ================================================================ template: shutters (market closing / opening)
func _t_shutters() -> bool:
	if director == null:
		return false
	var closing := bool(p.get("close", true))
	var places := NpcWorld.places_of(sid)
	var stalls: PackedVector2Array = places.get("stalls", PackedVector2Array())
	var yaws: PackedFloat32Array = places.get("stall_yaw", PackedFloat32Array())
	if stalls.is_empty():
		return false
	var idx: Array = []
	for i in stalls.size():
		if stalls[i].distance_to(player) < 60.0:
			idx.append(i)
	if idx.is_empty():
		return false
	idx.sort_custom(func(x: int, y: int) -> bool: return stalls[x].distance_to(player) < stalls[y].distance_to(player))
	anchor = stalls[idx[0]]
	var shut: Dictionary = director.call("shutter_nodes", sid)
	var count := 0
	for i: int in idx:
		if count >= int(p.get("max", 6)):
			break
		count += 1
		var sp := stalls[i]
		var yaw := yaws[i]
		var front := Vector2(sin(yaw), cos(yaw))
		if closing:
			var node: Node3D = shut.get(i)
			if node == null:
				node = _make_shutter(sp, yaw)
				shut[i] = node
				director.call("add_shutter", sid, i, node)
			var keeper := _human("merchant", sp + front * 1.7, _yaw_of(-front), count)
			keeper.wait(float(count) * 2.5)
			keeper.say(_say("market_close", count), 2.8)
			keeper.play(["Life_Market_Arrange", "Life_Shop_Wipe", "Life_Market_Hand_Over"], 3.5, sp)
			keeper.call_later(func() -> void: _lower_shutter(node))
			keeper.play(["Life_Shop_Tally", "Life_Ambient_Wipe_Brow"], 3.0, sp)
			var home := _pick_site("door", 20.0, 90.0)
			keeper.walk(_route(sp + front * 1.7, home if home != Vector2.INF else centre), 1.1, "Walking_A")
			keeper.vanish()
		else:
			var node2: Node3D = shut.get(i)
			if node2 != null:
				var keeper2 := _human("merchant", sp + front * 5.0, _yaw_of(-front), count)
				keeper2.walk(PackedVector2Array([sp + front * 1.7]), 1.1)
				keeper2.say(_say("gate_open", count), 2.6)
				keeper2.call_later(func() -> void: _raise_shutter(node2, sp, yaw))
				keeper2.play(["Life_Market_Arrange", "Life_Shop_Wipe"], 3.5, sp)
				keeper2.vanish()
	return count > 0


func _make_shutter(sp: Vector2, yaw: float) -> Node3D:
	var n := Node3D.new()
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.4, 1.55, 0.07)
	board.mesh = bm
	board.material_override = Assets.flat_material(Color(0.34, 0.23, 0.14))
	board.position = Vector3(0.0, 0.0, 0.0)
	n.add_child(board)
	for i in 3:
		var strap := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.08, 1.6, 0.09)
		strap.mesh = sm
		strap.position = Vector3(-1.3 + float(i) * 1.3, 0.0, 0.0)
		strap.material_override = Assets.flat_material(Color(0.12, 0.1, 0.09))
		n.add_child(strap)
	var front := Vector2(sin(yaw), cos(yaw))
	var at := sp + front * 1.15
	n.position = Vector3(at.x, WorldGen.height(sp.x, sp.y) + 2.7, at.y)       # raised: above the stall front
	n.rotation.y = yaw
	n.set_meta("stall_pos", sp)
	n.set_meta("down", false)
	return n


func _lower_shutter(n: Node3D) -> void:
	if n == null or not is_instance_valid(n) or bool(n.get_meta("down", false)):
		return
	n.set_meta("down", true)
	var sp: Vector2 = n.get_meta("stall_pos")
	var tw := n.create_tween()
	tw.tween_property(n, "position:y", WorldGen.height(sp.x, sp.y) + 1.15, 1.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	LivingEvents.emit("clang", n.global_position, 14.0, 1.5)


func _raise_shutter(n: Node3D, sp: Vector2, _yaw: float) -> void:
	if n == null or not is_instance_valid(n):
		return
	n.set_meta("down", false)
	var tw := n.create_tween()
	tw.tween_property(n, "position:y", WorldGen.height(sp.x, sp.y) + 2.7, 1.6)


# ================================================================ template: lamp (the lamplighter)
func _t_lamp() -> bool:
	var pts := PackedVector2Array()
	var cands := _sites("street")
	cands.append_array(_sites("plaza"))
	cands = cands.filter(func(q: Vector2) -> bool: return q.distance_to(player) < 55.0)
	if cands.size() < 3:
		return false
	cands.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.distance_to(player) < y.distance_to(player))
	# Walk a rough chain of lamps: start at a far one, then each time the nearest unvisited within 14 m.
	var cur: Vector2 = cands[cands.size() - 1]
	var left := cands.duplicate()
	left.erase(cur)
	pts.append(cur)
	while pts.size() < 5 and not left.is_empty():
		var best := -1
		var bd := 1e9
		for i in left.size():
			var d := (left[i] as Vector2).distance_to(cur)
			if d > 7.0 and d < bd:
				bd = d
				best = i
		if best < 0 or bd > 22.0:
			break
		cur = left[best]
		pts.append(cur)
		left.remove_at(best)
	if pts.size() < 2:
		return false
	anchor = pts[0].lerp(pts[pts.size() - 1], 0.5)
	var h := _human("worker", pts[0], _yaw_of(pts[1] - pts[0]), 0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.omni_range = 6.5
	light.light_energy = 1.1
	light.shadow_enabled = false
	light.position = Vector3(0.35, 1.45, 0.25)
	h.call_later(func() -> void:
		if is_instance_valid(h):
			h.add_child(light))
	h.hold([{"id": "cane", "hand": "r"}])
	for i in pts.size():
		if i > 0:
			h.walk(_route(pts[i - 1], pts[i]), 1.15)
		h.play(["Life_Ambient_Check_Sky", "Life_Market_Arrange"], 2.4, pts[i] + Vector2(1.0, 0.0))
		var at := pts[i]
		h.call_later(func() -> void: _light_lamp(at))
	h.say(_say("lamp", 1), 3.0)
	h.hold([])
	var out := _pick_site("gate", 0.0, 140.0)
	if out != Vector2.INF:
		h.walk(_route(pts[pts.size() - 1], out), 1.15)
	h.call_later(func() -> void:
		if is_instance_valid(light):
			light.queue_free())
	h.vanish()
	return true


## A lit lamp: a warm glow post (no real light: the budget has one torch light).
func _light_lamp(at: Vector2) -> void:
	var post := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	post.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.78, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.3)
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	post.material_override = mat
	post.position = Vector3(at.x, WorldGen.height(at.x, at.y) + 3.1, at.y)
	if director != null and director.has_method("add_lamp"):
		director.call("add_lamp", sid, post)
	else:
		_own(post)


# ================================================================ template: gate (close / open / shift / question)
func _t_gate() -> bool:
	var gates := _sites("gate")
	if gates.is_empty():
		return false
	var gi := -1
	var bd := 1e9
	for i in gates.size():
		var d := (gates[i] as Vector2).distance_to(player)
		if d < bd:
			bd = d
			gi = i
	if bd > float(p.get("dmax", 80.0)):
		return false
	var gp: Vector2 = gates[gi]
	var ang := float(plan["gates"][gi])
	var dir := Vector2(cos(ang), sin(ang))
	var side := Vector2(-dir.y, dir.x)
	anchor = gp
	var mode := String(p.get("mode", "shift"))
	var inside := gp - dir * 3.0
	match mode:
		"close", "open":
			if director != null:
				director.call("set_gate", sid, gi, mode == "close", centre + dir * wall_r, ang)
			for k in 2:
				var g := _human("guard", inside + side * (float(k) * 2.4 - 1.2) - dir * 5.0, _yaw_of(dir), k)
				g.walk(PackedVector2Array([inside + side * (float(k) * 3.0 - 1.5)]), 1.2, "Life_Walk_March")
				g.say(_say("gate_close" if mode == "close" else "gate_open", k), 3.2)
				g.play(["Life_Guard_Attention", "Life_Guard_Look_Out", "Life_Guard_Lean_Spear"], 10.0 + float(k) * 3.0, gp + dir * 6.0)
				if mode == "close":
					g.hold([{"id": "spear", "hand": "r"}])
				g.vanish()
			if mode == "close" and bool(p.get("latecomer", true)):
				var late := _human("villager", gp + dir * 14.0, _yaw_of(-dir), 4)
				late.walk(PackedVector2Array([inside - dir * 1.0]), 4.2, "Running_A")
				late.say("Wait for me!", 2.4)
				late.play(["Life_Ambient_Wipe_Brow", "Life_Social_Wave_Greet"], 3.0, gp)
				var late_home := _pick_site("door", 20.0, 90.0)
				late.walk(_route(inside, late_home if late_home != Vector2.INF else centre), 1.2)
				late.vanish()
			LivingEvents.emit("clang", Vector3(gp.x, WorldGen.height(gp.x, gp.y), gp.y), 30.0, 3.0)
		"shift":
			var barracks := centre + dir * (wall_r - 24.0)
			var relief := PackedVector2Array()
			for k in 2:
				var nw := _human("guard", barracks + side * (float(k) * 1.4 - 0.7), _yaw_of(dir), k)
				nw.walk(_route(barracks, inside + side * (float(k) * 2.0 - 1.0)), 1.1, "Life_Walk_March")
				nw.say(_say("shift", k), 3.0)
				nw.play(["Life_Social_Nod", "Life_Guard_Attention"], 3.0, gp)
				nw.hold([{"id": "spear", "hand": "r"}])
				nw.play(["Life_Guard_Lean_Spear", "Life_Guard_Look_Out", "Life_Guard_Attention"], duration, gp + dir * 6.0)
				nw.vanish()
				var old := _human("guard", inside + side * (float(k) * 2.0 - 1.0) + dir * 0.5, _yaw_of(dir), k + 2)
				old.hold([{"id": "spear", "hand": "r"}])
				old.play(["Life_Guard_Lean_Spear", "Life_Guard_Look_Out"], 6.0, gp + dir * 6.0)
				old.say(_say("shift", k + 4), 3.0)
				old.play(["Life_Social_Nod", "Life_Guard_Attention"], 3.0, inside + side * (float(k) * 2.0 - 1.0) - dir * 3.0)
				old.hold([])
				old.walk(_route(inside, barracks), 1.1, "Life_Walk_March")
				old.vanish()
				relief.append(barracks)
		"question":
			var guard := _human("guard", inside + side * 0.6, _yaw_of(dir), 0)
			guard.hold([{"id": "spear", "hand": "r"}])
			var trav := _human(String(p.get("traveller", "adventurer")), gp + dir * 9.0, _yaw_of(-dir), 1)
			trav.walk(PackedVector2Array([gp + dir * 1.2 - side * 0.5]), 1.2, "Walking_A")
			trav.hold([{"id": "book", "hand": "r"}])
			trav.say(_say("traveller", 1), 3.2)
			trav.play(["Life_Read_Stand", "Life_Talk_Explain", "Life_Talk_Casual"], 8.0, gp)
			trav.play(["Life_Talk_Casual", "Life_Social_Shrug", "Life_Talk_Explain"], 8.0, gp)
			trav.hold([])
			var trav_to := _pick_site("plaza", 0.0, 140.0)
			trav.walk(_route(gp, trav_to if trav_to != Vector2.INF else centre), 1.15, "Walking_A")
			trav.vanish()
			guard.wait(4.0)
			guard.say(_say("guard_ask", 2), 3.2)
			guard.play(["Life_Guard_Attention", "Life_Talk_Emphatic", "Life_Talk_Casual"], 9.0, gp + dir * 2.0)
			guard.play(["Life_Social_Nod", "Life_Social_Point_Directions"], 5.0, centre)
			guard.play(["Life_Guard_Lean_Spear", "Life_Guard_Look_Out"], 6.0, gp + dir * 6.0)
			guard.hold([])
			guard.vanish()
	return true


# ================================================================ template: fire (a small blaze and the bucket line)
func _t_fire() -> bool:
	var wells := _sites("well")
	var well: Vector2 = wells[0] if not wells.is_empty() else centre
	var doors := _sites("door")
	if doors.is_empty():
		return false
	var site := Vector2.INF
	var best := 1e9
	for q: Vector2 in doors:
		var d := q.distance_to(player)
		if d > 14.0 and d < 55.0 and q.distance_to(well) > 14.0 and d < best:
			best = d
			site = q
	if site == Vector2.INF:
		return false
	anchor = site
	var fire := Node3D.new()
	fire.name = "MicroFire"
	fire.set_meta("fire_strength", 0.7)
	fire.add_to_group("fire_hazard")
	fire.position = Vector3(site.x, WorldGen.height(site.x, site.y), site.y)
	_own(fire)
	var vfx: GDScript = load("res://scripts/vfx/vfx.gd")
	var host := get_parent()
	var burn_t := get_tree().create_timer(0.1)
	burn_t.timeout.connect(func() -> void:
		if is_instance_valid(fire) and host != null:
			vfx.call("fire_pillar", host, fire.global_position, 1.0, 5.0))
	var ticker := Timer.new()
	ticker.wait_time = 4.5
	ticker.timeout.connect(func() -> void:
		if is_instance_valid(fire) and fire.is_in_group("fire_hazard") and host != null:
			vfx.call("fire_pillar", host, fire.global_position, 1.0, 5.0))
	fire.add_child(ticker)
	ticker.start()
	# Dies out as the brigade works (the scene's own clock): remove from the hazard group at the end.
	get_tree().create_timer(maxf(duration - 8.0, 10.0)).timeout.connect(func() -> void:
		if is_instance_valid(fire):
			fire.remove_from_group("fire_hazard")
			ticker.stop())
	var line := _route(well, site)
	var n := int(p.get("n", 5))
	for k in n:
		var t := float(k) / float(maxi(n - 1, 1))
		var spot := well.lerp(site, 0.12 + 0.8 * t)
		if graph != null:
			spot = graph.push_out(spot, 0.4)
		var h := _human("woman" if k % 2 == 0 else "villager", well + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0)), 0.0, k)
		h.say(_say("fire_bucket", k), 2.6)
		h.walk(PackedVector2Array([spot]), 2.4, "Running_A")
		var loops := int((duration - 8.0) / 5.0)
		for r in maxi(loops, 1):
			h.play(["Life_Carry_Pick_Up", "Life_Chore_Well_Lift_Bucket"], 2.4, site if k > n / 2 else well)
			h.play(["Life_Carry_Put_Down", "Life_Carry_Pick_Up"], 2.4, site if k > n / 2 else well)
		h.play(["Life_Ambient_Wipe_Brow", "Life_Mocap_Happy"], 3.0, site)
		h.vanish()
	line.clear()
	return true


# ================================================================ template: broken cart (the player can help)
func _t_broken_cart() -> bool:
	var pair := _pass_pair("gate", "plaza", 36.0)
	if pair.is_empty():
		pair = _pass_pair("street", "plaza", 36.0)
	if pair.is_empty():
		return false
	var a: Vector2 = pair[0]
	var b: Vector2 = pair[1]
	var path := _route(a, b)
	if path.size() < 2:
		return false
	# Stops where the street passes about 10 m from the player (the first such point along the way).
	var stop_at := path[0]
	var best := 1e9
	for i in path.size():
		var d := path[i].distance_to(player)
		if d < best and d > 7.0:
			best = d
			stop_at = path[i]
	var cut := PackedVector2Array()
	for q in path:
		cut.append(q)
		if q == stop_at:
			break
	if cut.size() < 2:
		return false
	anchor = stop_at
	var d0 := _first_dir(cut)
	var v := _vehicle("cart", ["donkey"], a, _yaw_of(d0), 2.4)
	v.walk(cut, 1.5)
	var owner := _human("worker", a, _yaw_of(d0), 0)
	owner.walk(_member_path(cut, 1.5, -2.2), 1.5)
	owner.say(_say("broken_cart", 0), 4.0)
	owner.play(["Life_Social_Shake_Head", "Life_Mocap_Sad", "Life_Ambient_Wipe_Brow"], 6.0, stop_at)
	var wheel := Node3D.new()
	var wm := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.5
	cy.bottom_radius = 0.5
	cy.height = 0.09
	wm.mesh = cy
	wm.material_override = Assets.flat_material(Color(0.3, 0.2, 0.12))
	wm.rotation.x = deg_to_rad(80.0)
	wheel.add_child(wm)
	wheel.position = Vector3(stop_at.x + 1.8, WorldGen.height(stop_at.x, stop_at.y) + 0.45, stop_at.y - 1.2)
	_own(wheel)
	var fixed := {"v": false}
	var exit_pt := _exit_from(b, a)
	var tail := _route(stop_at, exit_pt) if exit_pt.distance_to(stop_at) > 10.0 else PackedVector2Array([stop_at + d0 * 30.0])
	var go := func() -> void:
		if fixed["v"]:
			return
		fixed["v"] = true
		if is_instance_valid(wheel):
			wheel.queue_free()
		if station != null and is_instance_valid(station):
			station.queue_free()
		v.clear_queue()
		v.walk(tail, 1.5)
		v.vanish()
		owner.clear_queue()
		owner.play(["Life_Social_Bow", "Life_Social_Wave_Greet"], 2.5, player)
		owner.say(_say("thanks", 1), 3.0)
		owner.walk(_member_path(tail, 1.5, -2.2), 1.5)
		owner.vanish()
	# The stranded carter asks for help; helping earns a few coins and some standing in the town.
	var st := Station.new("Stranded carter", "Help repair", func() -> Dictionary:
		return {"title": "Stranded carter", "body": "A cart wheel has come off and the carter cannot lift the axle alone.",
			"options": [["Lend a hand", func() -> String:
				if fixed["v"]:
					return "The cart is already mended."
				var coins := 4 + int(rng.randi() % 6)
				Game.add_gold(coins)
				var soc: Variant = (Life.realm as RefCounted).call("mod", "society") if Life.realm != null else null
				if soc != null:
					soc.call("add_rep", "city:%d" % sid, 1.5, "helped a carter")
				go.call()
				return "You heave the axle while he wedges the wheel back. He presses %d coins into your hand." % coins]]}
	)
	st.position = Vector3(stop_at.x + 0.9, WorldGen.height(stop_at.x, stop_at.y), stop_at.y + 0.9)
	add_child(st)
	station = st
	# Nobody comes? After a while two passers-by mend it.
	# A child Timer (not a SceneTreeTimer): it dies with this scene, so `go` (which uses self) never fires on a freed scene.
	var mend := Timer.new()
	mend.one_shot = true
	mend.wait_time = maxf(duration - 5.0, 20.0)
	add_child(mend)
	mend.timeout.connect(func() -> void: go.call())
	mend.start()
	return true
