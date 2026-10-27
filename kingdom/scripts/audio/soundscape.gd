extends Node
## Positional soundscape on top of the director's 2D beds (AAA gap audit 2026-10-28, audio rows "Ambience layers" and
## "Reverb / occlusion"). Child of the AudioDirector; everything is built-in Godot:
##   - Spot emitters: a small pool of looping AudioStreamPlayer3D voices placed on the NEAREST sound sources around the
##     listener: smart objects (anvil / bellows -> forge, market stalls -> market walla, well, bar counter / tavern
##     tables -> tavern spill, cook pot -> hearth), campfires (groups bandit_campfire / fire_hazard, the slice road
##     camp) and moving carts (group "vehicle"). Inverse-distance attenuation + air-absorption low-pass per voice,
##     culled past each kind's max distance, faded in / out when the nearest set changes. Streams are OGG Vorbis
##     (decoded on the fly, never loaded whole).
##   - Occlusion: one ray per tick (round-robin) from the listener to an emitter; a wall in between moves that voice
##     to the AmbOccluded bus (low-pass 1.1 kHz, -4 dB) with a short dip so the swap never clicks.
##   - Zone reverb: an Area3D that follows the listener with reverb_bus_* set to the wet-only Zone bus; the acoustic
##     space is probed every 0.5 s (interior kind, wall rays for alley / street, forest density) and the reverb
##     character + send amount crossfade to it (audio_buses.gd ZONES).
##   - Life on the emitters: an unattended anvil still rings now and then by day, the well chain / bucket creaks.
## Budget: HIGH 8 emitter voices (+ 1 one-shot voice), LOW 4 and no forest reverb. `active` = false disables it all.

const AudioBuses := preload("res://scripts/audio/audio_buses.gd")
const NpcWorld := preload("res://scripts/population/npc_world.gd")
const Slice := preload("res://scripts/world/town_kit/slice_dressing.gd")

## Physics layer 28: only audio queries (AudioStreamPlayer3D.area_mask) see the zone Area3D.
const ZONE_LAYER := 1 << 27
const SCAN_RADIUS := 70.0
const RESCAN_MOVE := 6.0
const CLUSTER := 14.0
## kind -> {key: loop sound name (director library), unit: unit_size, max: max_distance, db: volume, hours: [from, to]
## (empty = always), night_db: extra dB at night}
const KINDS := {
	"forge": {"key": "amb_forge", "unit": 5.0, "max": 38.0, "db": -3.0, "hours": [6.0, 20.5]},
	"market": {"key": "amb_walla_market", "unit": 10.0, "max": 60.0, "db": 0.0, "hours": [7.0, 19.5]},
	"well": {"key": "amb_well", "unit": 2.0, "max": 16.0, "db": -8.0, "hours": []},
	"tavern": {"key": "amb_walla_tavern", "unit": 6.0, "max": 42.0, "db": -1.0, "hours": [], "night_db": 3.0},
	"hearth": {"key": "amb_fire_small", "unit": 2.5, "max": 16.0, "db": -6.0, "hours": []},
	"campfire": {"key": "amb_campfire", "unit": 4.0, "max": 36.0, "db": -1.0, "hours": []},
	"cart": {"key": "loop_cart", "unit": 4.0, "max": 40.0, "db": -2.0, "hours": []},
}
const SPOT_KIND := {"anvil": "forge", "bellows": "forge", "market_stall": "market", "shop_counter": "market",
	"well": "well", "bar_counter": "tavern", "tavern_table": "tavern", "cook_pot": "hearth"}

var active := true
var director: Node          ## the AudioDirector (pick_fn / play_sfx / listener)
var zone := "open"
var zone_amount := 0.0

var _voices: Array[AudioStreamPlayer3D] = []
var _state: Array[Dictionary] = []      # per voice: {src: source dict or {}, occluded, occ_votes, fading}
var _sources: Array[Dictionary] = []    # {kind, pos, node (moving) or null, id}
var _root: Node3D
var _area: Area3D
var _scan_at := Vector3.INF
var _scan_timer := 0.0
var _zone_timer := 0.0
var _occ_i := 0
var _occ_timer := 0.0
var _life_timer := 3.0
var _zone_tween: Tween
var _low := false
var _zone_pending := ""


func _process(delta: float) -> void:
	var lis: Node3D = director.listener if director and director.call("_listener_ok") else null
	if not active or lis == null or not is_instance_valid(lis) or not lis.is_inside_tree():
		_silence()
		return
	if _root == null or not is_instance_valid(_root) or _root.get_viewport() != lis.get_viewport():
		_build(lis.get_viewport())
	var lp := lis.global_position
	_area.global_position = lp
	_scan_timer -= delta
	if _scan_timer <= 0.0 or _scan_at.distance_to(lp) > RESCAN_MOVE:
		_scan_timer = 1.0
		_scan_at = lp
		_collect(lp)
		_assign(lp)
	_follow_moving()
	_occ_timer -= delta
	if _occ_timer <= 0.0:
		_occ_timer = 0.12
		_occlusion_tick(lis)
	_zone_timer -= delta
	if _zone_timer <= 0.0:
		_zone_timer = 0.5
		_update_zone(lis)
	_life_timer -= delta
	if _life_timer <= 0.0:
		_life_timer = randf_range(3.5, 8.0)
		_life(lp)


## Voices playing right now (budget log).
func playing() -> int:
	var n := 0
	for v in _voices:
		n += 1 if is_instance_valid(v) and v.playing else 0
	return n


func describe() -> String:
	var kinds := []
	for i in _voices.size():
		if _voices[i].playing and not (_state[i]["src"] as Dictionary).is_empty():
			kinds.append("%s%s" % [_state[i]["src"]["kind"], "*" if _state[i]["occluded"] else ""])
	return "zone %s (%.2f), emitters %s" % [zone, zone_amount, kinds]


# ------------------------------------------------------------------ build
func _build(vp: Viewport) -> void:
	if _root and is_instance_valid(_root):
		_root.queue_free()
	_voices.clear()
	_state.clear()
	_low = Quality.tier <= Quality.LOW
	_root = Node3D.new()
	_root.name = "Soundscape"
	vp.add_child(_root)
	for i in (4 if _low else 8):
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.attenuation_filter_cutoff_hz = 6500.0
		p.attenuation_filter_db = -18.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		p.area_mask = 1 | ZONE_LAYER
		p.bus = AudioBuses.AMBIENCE
		p.volume_db = -80.0
		_root.add_child(p)
		_voices.append(p)
		_state.append({"src": {}, "occluded": false, "votes": 0, "fade": null})
	_area = Area3D.new()
	_area.name = "ZoneReverb"
	_area.collision_layer = ZONE_LAYER
	_area.collision_mask = 0
	_area.monitoring = false
	_area.monitorable = true
	_area.reverb_bus_enabled = true
	_area.reverb_bus_name = AudioBuses.ZONE
	_area.reverb_bus_amount = 0.0
	_area.reverb_bus_uniformity = 0.35
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 45.0
	cs.shape = sh
	_area.add_child(cs)
	_root.add_child(_area)
	zone = "open"
	zone_amount = 0.0


func _silence() -> void:
	for v in _voices:
		if is_instance_valid(v) and v.playing:
			v.stop()


# ------------------------------------------------------------------ sources
func _collect(lp: Vector3) -> void:
	_sources.clear()
	var r2 := SCAN_RADIUS * SCAN_RADIUS
	var so: SmartObjects = NpcWorld.smart
	if so != null:
		var clusters: Array[Dictionary] = []
		for sp: Dictionary in so.spots:
			var kind := String(SPOT_KIND.get(String(sp["type"]), ""))
			if kind == "":
				continue
			var o: Vector3 = (sp["xform"] as Transform3D).origin
			if o.distance_squared_to(lp) > r2:
				continue
			var merged := false
			for c in clusters:
				if c["kind"] == kind and (c["pos"] as Vector3).distance_to(o) < CLUSTER:
					c["sum"] += o
					c["n"] += 1
					c["pos"] = c["sum"] / float(c["n"])
					if String(sp["type"]) == "anvil":
						c["anvil"] = sp
					merged = true
					break
			if not merged:
				clusters.append({"kind": kind, "pos": o, "sum": o, "n": 1, "node": null,
					"anvil": sp if String(sp["type"]) == "anvil" else {}})
		for c in clusters:
			c["pos"] += Vector3.UP * (1.6 if c["kind"] in ["market", "tavern"] else 0.9)
			c["id"] = "%s_%d_%d" % [c["kind"], roundi(c["pos"].x / 4.0), roundi(c["pos"].z / 4.0)]
			_sources.append(c)
	var tree := get_tree()
	var fires := 0
	for g in ["bandit_campfire", "fire_hazard"]:
		for n in tree.get_nodes_in_group(g):
			var f := n as Node3D
			if f != null and f.is_inside_tree() and f.global_position.distance_squared_to(lp) < r2:
				_sources.append({"kind": "campfire", "pos": f.global_position + Vector3.UP * 0.4, "node": null, "id": "fire_%d" % f.get_instance_id()})
				fires += 1
	if fires == 0:
		var rc := Slice.road_camp_pos()
		if rc != Vector2.INF and Vector2(lp.x, lp.z).distance_to(rc) < SCAN_RADIUS:
			_sources.append({"kind": "campfire", "pos": Vector3(rc.x, WorldGen.height(rc.x, rc.y) + 0.4, rc.y), "node": null, "id": "roadcamp"})
	for n in tree.get_nodes_in_group("vehicle"):
		var v := n as Node3D
		if v != null and v.is_inside_tree() and v.is_visible_in_tree() and v.global_position.distance_squared_to(lp) < r2:
			_sources.append({"kind": "cart", "pos": v.global_position + Vector3.UP * 0.8, "node": v, "id": "cart_%d" % v.get_instance_id()})


func _audible(kind: String) -> bool:
	var hours: Array = KINDS[kind]["hours"]
	if hours.is_empty():
		return true
	var h := float(WorldSim.time_of_day)
	return h >= float(hours[0]) and h < float(hours[1])


## Nearest audible sources win the voices; a voice keeps its source while it stays in the set (no restart).
func _assign(lp: Vector3) -> void:
	var cands: Array[Dictionary] = []
	for s in _sources:
		var k: Dictionary = KINDS[s["kind"]]
		var d := (s["pos"] as Vector3).distance_to(lp)
		if d < float(k["max"]) and _audible(s["kind"]) and director.has_sound(String(k["key"])):
			s["d"] = d
			cands.append(s)
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	cands = cands.slice(0, _voices.size())
	var wanted := {}
	for c in cands:
		wanted[c["id"]] = c
	# keep voices whose source is still wanted, release the rest
	var free: Array[int] = []
	for i in _voices.size():
		var cur: Dictionary = _state[i]["src"]
		if not cur.is_empty() and wanted.has(cur["id"]):
			var c: Dictionary = wanted[cur["id"]]
			_state[i]["src"] = c
			wanted.erase(cur["id"])
			if c["node"] == null:
				_voices[i].global_position = c["pos"]
		else:
			if not cur.is_empty():
				_fade(i, -80.0, 1.2, true)
				_state[i]["src"] = {}
			free.append(i)
	for id: String in wanted:
		if free.is_empty():
			break
		var i: int = free.pop_front()
		_start(i, wanted[id], lp)


func _start(i: int, src: Dictionary, lp: Vector3) -> void:
	var k: Dictionary = KINDS[src["kind"]]
	var stream: AudioStream = director.call("pick_loop", String(k["key"]))
	if stream == null:
		return
	var p := _voices[i]
	_state[i]["src"] = src
	_state[i]["occluded"] = false
	_state[i]["votes"] = 0
	p.stream = stream
	p.unit_size = float(k["unit"])
	p.max_distance = float(k["max"]) + 6.0
	p.bus = AudioBuses.AMBIENCE
	p.global_position = src["pos"]
	p.pitch_scale = randf_range(0.97, 1.03)
	p.volume_db = -60.0
	p.play(randf() * maxf(0.0, stream.get_length() - 2.0))
	_fade(i, _target_db(src), 1.6)


func _target_db(src: Dictionary) -> float:
	var k: Dictionary = KINDS[src["kind"]]
	var db := float(k["db"])
	var h := float(WorldSim.time_of_day)
	if h < 6.0 or h >= 20.5:
		db += float(k.get("night_db", 0.0))
	if src["kind"] == "market":
		db += clampf(log(float(src.get("n", 1))) * 2.5, 0.0, 4.0)     # more stalls, more voices
	return db


func _fade(i: int, db: float, time: float, stop_after := false) -> void:
	var old: Variant = _state[i]["fade"]
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
	var p := _voices[i]
	var t := create_tween()
	t.tween_property(p, "volume_db", db, time)
	if stop_after:
		t.tween_callback(p.stop)
	_state[i]["fade"] = t


func _follow_moving() -> void:
	for i in _voices.size():
		var src: Dictionary = _state[i]["src"]
		if src.is_empty() or src["node"] == null:
			continue
		var n: Variant = src["node"]
		if is_instance_valid(n) and (n as Node3D).is_inside_tree():
			_voices[i].global_position = (n as Node3D).global_position + Vector3.UP * 0.8
		else:
			_fade(i, -80.0, 0.8, true)
			_state[i]["src"] = {}


# ------------------------------------------------------------------ occlusion
func _occlusion_tick(lis: Node3D) -> void:
	if _voices.is_empty():
		return
	_occ_i = (_occ_i + 1) % _voices.size()
	var i := _occ_i
	var p := _voices[i]
	var src: Dictionary = _state[i]["src"]
	if src.is_empty() or not p.playing:
		return
	var space := lis.get_world_3d().direct_space_state
	var from := lis.global_position
	var to := p.global_position
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.collide_with_areas = false
	var player := get_tree().get_first_node_in_group("player")
	if player is CollisionObject3D:
		q.exclude = [(player as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	var blocked := not hit.is_empty() and (hit["position"] as Vector3).distance_to(to) > 1.2
	# two agreeing rays before switching, so a post or a passer-by doesn't flutter the filter
	var votes := int(_state[i]["votes"])
	votes = clampi(votes + (1 if blocked else -1), -2, 2)
	_state[i]["votes"] = votes
	var occ: bool = _state[i]["occluded"]
	if (votes >= 2 and not occ) or (votes <= -2 and occ):
		_state[i]["occluded"] = not occ
		var want_bus := AudioBuses.AMB_OCCLUDED if not occ else AudioBuses.AMBIENCE
		var target := _target_db(src)
		var t := create_tween()
		t.tween_property(p, "volume_db", target - 9.0, 0.1)
		t.tween_callback(func() -> void: p.bus = want_bus)
		t.tween_property(p, "volume_db", target, 0.25)
		_state[i]["fade"] = t


# ------------------------------------------------------------------ zone reverb
func _update_zone(lis: Node3D) -> void:
	var kind := _probe_zone(lis)
	if kind == zone:
		_zone_pending = ""
		return
	# two agreeing probes (1 s) before the space changes: a doorway or a gap between houses doesn't flutter the reverb
	if kind != _zone_pending:
		_zone_pending = kind
		return
	_zone_pending = ""
	zone = kind
	var amount := 0.0
	if kind != "open":
		amount = AudioBuses.ZONES[kind]["amount"]
	if _zone_tween and _zone_tween.is_valid():
		_zone_tween.kill()
	# duck the send, swap the reverb character, bring the new send up (no zipper in the tail)
	_zone_tween = create_tween()
	_zone_tween.tween_property(_area, "reverb_bus_amount", 0.0, 0.25)
	_zone_tween.tween_callback(func() -> void: AudioBuses.set_zone(kind))
	_zone_tween.tween_property(_area, "reverb_bus_amount", amount, 0.6)
	zone_amount = amount
	if director and director.get("_log"):
		print("[audio] zone -> %s (send %.2f)" % [kind, amount])


func _probe_zone(lis: Node3D) -> String:
	var interior: String = director.get("_interior") if director else ""
	if interior != "":
		match interior:
			"tavern", "guild":
				return "tavern"
			"church":
				return "church"
			_:
				return "room"
	var p := lis.global_position
	# walls: 8 horizontal rays at ear height from the PLAYER (the camera can sit inside a wall's margin)
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	var o := (pl.global_position if pl != null else p) + Vector3.UP * 1.6
	var space := lis.get_world_3d().direct_space_state
	var dists: Array[float] = []
	for k in 8:
		var a := TAU * float(k) / 8.0
		var q := PhysicsRayQueryParameters3D.create(o, o + Vector3(cos(a), 0.0, sin(a)) * 14.0, 1)
		if pl is CollisionObject3D:
			q.exclude = [(pl as CollisionObject3D).get_rid()]
		var h := space.intersect_ray(q)
		dists.append(o.distance_to(h["position"]) if not h.is_empty() else 99.0)
	# opposite pairs (0-4, 1-5, 2-6, 3-7): a narrow gap both ways = alley, a wall line on at least one side = street
	var narrow := 0
	var walls := 0
	for k in 4:
		var a2 := dists[k]
		var b2 := dists[k + 4]
		if a2 + b2 < 9.0:
			narrow += 1
		walls += int(a2 < 10.0) + int(b2 < 10.0)
	if narrow >= 1 and walls >= 4:
		return "alley"
	if walls >= 3:
		return "street"
	if not _low and not WorldGen.settlements.is_empty() and WorldGen.forest_density(p.x, p.z) > 0.35:
		return "forest"
	return "open"


# ------------------------------------------------------------------ life on emitters
func _life(lp: Vector3) -> void:
	for i in _voices.size():
		var src: Dictionary = _state[i]["src"]
		if src.is_empty() or not _voices[i].playing:
			continue
		match String(src["kind"]):
			"forge":
				var anvil: Dictionary = src.get("anvil", {})
				var worked := false
				for h: int in anvil.get("holders", []):
					worked = worked or h >= 0
				if not worked and not anvil.is_empty() and _audible("forge") and randf() < 0.6:
					_hammer_run((anvil["xform"] as Transform3D).origin + Vector3.UP * 0.9)
			"well":
				if randf() < 0.25:
					director.play_sfx("well_bucket", src["pos"], -10.0, 0.06)


## A smith's run: 3-6 strikes with the occasional lighter tap, the rhythm of real work.
func _hammer_run(at: Vector3) -> void:
	var n := randi_range(3, 6)
	var t := 0.0
	for k in n:
		var light := randf() < 0.3
		get_tree().create_timer(t).timeout.connect(func() -> void:
			if is_instance_valid(director):
				director.play_sfx("anvil_strike" if director.has_sound("anvil_strike") else "anvil", at, -9.0 if light else -4.0, 0.03))
		t += randf_range(0.42, 0.62)
