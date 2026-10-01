extends GdUnitTestSuite
## The Hidden Vale and the exploration POIs: deterministic terrain, one way in (the gorge), found once, saved, and a
## top-tier settlement site; the 56 POIs (26 + 30 for the 12 km world) are placed, spread out, secret until found and listed without spoilers.

const HV := preload("res://scripts/world/hidden_valley.gd")
const POIS := preload("res://scripts/world/region_pois.gd")
const Discovery := preload("res://scripts/sim/discovery.gd")
const Director := preload("res://scripts/world/exploration_director.gd")
const Hub := preload("res://scripts/realm/realm_hub.gd")


func before() -> void:
	WorldGen.setup(1066)


func _disc() -> RefCounted:
	var d := Discovery.new()
	d.build(WorldGen.settlements, WorldGen.sites, [], WorldGen.camp_grounds)
	return d


func _poi_site(id: String) -> Dictionary:
	for s: Dictionary in WorldGen.sites:
		if String(s.get("poi", "")) == id:
			return s
	return {}


func _sid(s: Dictionary) -> String:
	var p: Vector2 = s["pos"]
	return "site:%s:%d:%d" % [s["name"], roundi(p.x), roundi(p.y)]


# --- terrain -------------------------------------------------------------------------------------------------

func test_valley_terrain_is_deterministic() -> void:
	var probes: Array[Vector2] = []
	for u in [-200.0, -60.0, 0.0, 90.0, 210.0, 330.0, 470.0]:
		for v in [-120.0, 0.0, 80.0]:
			probes.append(HV.w(u, v))
	var first: Array[float] = []
	for p in probes:
		first.append(WorldGen.height(p.x, p.y))
	var center := HV.CENTER
	WorldGen.setup(1066)
	assert_vector(HV.CENTER).is_equal(center)
	for i in probes.size():
		assert_float(WorldGen.height(probes[i].x, probes[i].y)).is_equal(first[i])


func test_valley_has_room_in_both_test_seeds() -> void:
	for seed_value in [1066, 2024]:
		WorldGen.setup(seed_value)
		var room := INF
		for st in WorldGen.settlements:
			room = minf(room, HV.CENTER.distance_to(st["pos"]) - float(st["radius"]))
		for r in WorldGen.roads:
			var a: Vector2 = WorldGen.settlements[r.x]["pos"]
			var b: Vector2 = WorldGen.settlements[r.y]["pos"]
			room = minf(room, HV.CENTER.distance_to(Geometry2D.get_closest_point_to_segment(HV.CENTER, a, b)))
		assert_float(room).override_failure_message("seed %d: only %.0f m to the nearest road or town" % [seed_value, room]).is_greater(600.0)
	WorldGen.setup(1066)


func test_bowl_is_ringed_by_cliffs_with_a_meadow_floor() -> void:
	var fl := WorldGen.height(HV.CENTER.x, HV.CENTER.y)
	var rim_min := INF
	for k in 24:
		var a := TAU * k / 24.0
		var dir := Vector2(cos(a), sin(a))
		var top := 0.0
		for r in range(200, 420, 6):
			var q := HV.CENTER + dir * r
			if absf(HV.to_local(q).y - HV.gorge_offset(HV.to_local(q).x)) < 60.0 and HV.to_local(q).x > 100.0:
				top = -1.0
				break
			top = maxf(top, WorldGen.height(q.x, q.y))
		if top >= 0.0:
			rim_min = minf(rim_min, top - fl)
	assert_float(rim_min).override_failure_message("lowest rim only %.0f m above the floor" % rim_min).is_greater(40.0)


## Flood fill over the ground (slope <= 1, the player's 45 degrees): with the gorge walled off nothing escapes the vale.
func _flood(block_gorge: bool) -> Vector2i:
	var cell := 2.0
	var half := 600.0
	var n := int(half * 2.0 / cell)
	var c := HV.CENTER
	var hh := PackedFloat32Array()
	hh.resize(n * n)
	for j in n:
		for i in n:
			hh[j * n + i] = WorldGen.height(c.x - half + i * cell, c.y - half + j * cell)
	var seen := PackedByteArray()
	seen.resize(n * n)
	var q: Array[Vector2i] = [Vector2i(n / 2, n / 2)]
	seen[(n / 2) * n + n / 2] = 1
	var qi := 0
	var outside := 0
	while qi < q.size():
		var cur: Vector2i = q[qi]
		qi += 1
		var wp := Vector2(c.x - half + cur.x * cell, c.y - half + cur.y * cell)
		if wp.distance_to(c) > 540.0:
			outside += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: Vector2i = cur + d
			if nx.x < 1 or nx.y < 1 or nx.x >= n - 1 or nx.y >= n - 1 or seen[nx.y * n + nx.x] == 1:
				continue
			var hc := hh[nx.y * n + nx.x]
			var gx := minf(absf(hh[nx.y * n + nx.x + 1] - hc), absf(hc - hh[nx.y * n + nx.x - 1])) / cell
			var gz := minf(absf(hh[(nx.y + 1) * n + nx.x] - hc), absf(hc - hh[(nx.y - 1) * n + nx.x])) / cell
			if Vector2(gx, gz).length() > 1.0:
				continue
			if block_gorge:
				var np := Vector2(c.x - half + nx.x * cell, c.y - half + nx.y * cell)
				var l := HV.to_local(np)
				if l.x > 150.0 and l.x < 560.0 and absf(l.y - HV.gorge_offset(l.x)) < 60.0:
					continue
			seen[nx.y * n + nx.x] = 1
			q.append(nx)
	return Vector2i(q.size(), outside)


func test_entrance_only_via_the_pass() -> void:
	var open := _flood(false)
	var walled := _flood(true)
	assert_int(open.y).override_failure_message("the gorge must lead out of the vale").is_greater(1000)
	assert_int(walled.y).override_failure_message("%d cells beyond the rim are reachable without the gorge" % walled.y).is_equal(0)
	assert_int(walled.x).is_greater(20000)      # the vale itself is a real walkable place


func test_gorge_is_narrow_and_walkable() -> void:
	for u in range(170, 470, 20):
		var g := HV.gorge_world(float(u))
		var h := WorldGen.height(g.x, g.y)
		assert_float(h).is_between(HV.mouth_h - 4.0, HV.floor_h + 2.0)
		var side := HV.PERP * (HV.gorge_half_width(float(u)) + 14.0)
		assert_float(WorldGen.height(g.x + side.x, g.y + side.y) - h).is_greater(-0.5)
	var mid := HV.gorge_world(300.0)
	var wall := HV.PERP * 22.0
	assert_float(WorldGen.height(mid.x + wall.x, mid.y + wall.y) - WorldGen.height(mid.x, mid.y)).is_greater(25.0)


func test_stream_and_pond_hold_water_and_stay_off_the_map() -> void:
	var pond := HV.w(28.0, -56.0)
	assert_bool(WorldGen.is_water(pond.x, pond.y)).is_true()
	assert_float(WorldGen.water_depth(pond.x, pond.y)).is_greater(1.0)
	var spring := HV.w(-80.0, -8.0)
	assert_bool(WorldGen.near_water(spring.x, spring.y, 12.0)).is_true()
	assert_int(WorldGen.rivers.size()).is_equal(3)     # the vale's water is not a map river
	var kn := HV.knoll_world()
	assert_bool(WorldGen.is_water(kn.x, kn.y)).is_false()


# --- settlement site -----------------------------------------------------------------------------------------

func test_the_knoll_is_a_top_tier_settlement_site() -> void:
	var camps: RefCounted = Hub.new().mod("camps")
	var score: float = camps.score_site(HV.knoll_world())
	assert_float(score).is_greater(0.8)
	var better := 0
	var n := 0
	for x in range(-3200, 3201, 200):
		for z in range(-3200, 3201, 200):
			n += 1
			if float(camps.score_site(Vector2(x, z))) >= score:
				better += 1
	assert_float(float(better) / n).override_failure_message("%d of %d land samples score as well as the knoll" % [better, n]).is_less(0.01)
	assert_float(camps.score_site(Vector2(0, 0))).is_less(score)
	# And it really can be founded there.
	assert_int(camps.found_camp(HV.knoll_world(), "Vale Camp", 1)).is_greater(0)


# --- discovery -----------------------------------------------------------------------------------------------

func test_vale_is_secret_then_found_exactly_once() -> void:
	var d := _disc()
	var id := HV.place_id()
	assert_bool(d.place(id).is_empty()).is_true()            # not on the map or the compass
	assert_bool(d.secret_place(id).is_empty()).is_false()
	var total: int = d.places.size()
	assert_bool(d.discover(id, 5)).is_true()
	assert_bool(d.discover(id, 6)).is_false()
	assert_int(d.places.size()).is_equal(total + 1)
	assert_str(d.place(id)["name"]).is_equal("The Hidden Vale")
	# Walking about never finds it by accident: the HUD's own update() cannot see secret sites.
	var d2 := _disc()
	var hits: Array = d2.update(HV.stones_world(), 1)
	assert_int(hits.size()).is_equal(0)


func test_save_round_trip_keeps_secrets_and_notes() -> void:
	var d := _disc()
	var poi := _poi_site("kestrel")
	d.discover(HV.place_id(), 3)
	d.discover(_sid(poi), 4)
	d.note("res:moon_a", 9)
	var blob: Variant = JSON.parse_string(JSON.stringify(d.serialize()))
	var d2 := _disc()
	d2.deserialize(blob)
	assert_bool(d2.is_discovered(HV.place_id())).is_true()
	assert_bool(d2.is_discovered(_sid(poi))).is_true()
	assert_int(d2.note_day("res:moon_a")).is_equal(9)
	assert_bool(d2.place(HV.place_id()).is_empty()).is_false()     # found secrets rejoin the place list
	assert_bool(d2.discover(HV.place_id(), 9)).is_false()            # and do not fire again
	# A rebuild after the load (HUD builds lazily) still lists them.
	d2.build(WorldGen.settlements, WorldGen.sites, [], WorldGen.camp_grounds)
	assert_bool(d2.place(HV.place_id()).is_empty()).is_false()


func test_discovery_sequence_is_8_to_15_seconds_and_skippable() -> void:
	var shots := Director.vale_shots(HV.gorge_world(185.0))
	var total := CutscenePlayer.total_duration(shots)
	assert_float(total).is_between(8.0, 15.0)
	var cp := CutscenePlayer.new()
	add_child(cp)
	cp.play(shots)
	assert_bool(cp.skippable).is_true()
	cp.advance(1.0)
	cp.skip()
	assert_bool(cp.playing).is_false()
	cp.free()


# --- POIs ------------------------------------------------------------------------------------------------------

func test_all_pois_are_placed_apart_and_secret() -> void:
	var sites: Array[Dictionary] = []
	for s: Dictionary in WorldGen.sites:
		if String(s.get("poi", "")) != "" and String(s["poi"]) != "hidden_vale":
			sites.append(s)
	assert_int(sites.size()).is_equal(POIS.DEFS.size())          # 26 + 30 for the 12 km world: every one finds ground
	var names := {}
	for i in sites.size():
		var s: Dictionary = sites[i]
		assert_bool(bool(s["secret"])).is_true()
		assert_bool(names.has(s["name"])).is_false()
		names[s["name"]] = true
		assert_bool(WorldGen.is_water(s["pos"].x, s["pos"].y)).is_false()
		assert_bool(HV.protected_ground(s["pos"])).is_false()
		for j in range(i + 1, sites.size()):
			assert_float((s["pos"] as Vector2).distance_to(sites[j]["pos"])).is_greater(200.0)
	var kinds := {}
	for s: Dictionary in sites:
		kinds[s["kind"]] = int(kinds.get(s["kind"], 0)) + 1
	for k in ["poi_vista", "poi_shrine", "poi_lore", "poi_camp", "poi_herbs", "poi_cache", "poi_battlefield", "poi_fishing", "poi_hermit", "poi_rift", "poi_hunter"]:
		assert_bool(kinds.has(k)).override_failure_message("no %s placed (%s)" % [k, kinds]).is_true()


func test_poi_plan_is_deterministic_and_leaves_the_world_layout_alone() -> void:
	var before_sites := WorldGen.sites.size()
	var first := {}
	for s: Dictionary in WorldGen.sites:
		if String(s.get("poi", "")) != "":
			first[s["poi"]] = s["pos"]
	WorldGen.setup(1066)
	assert_int(WorldGen.sites.size()).is_equal(before_sites)
	for s: Dictionary in WorldGen.sites:
		if String(s.get("poi", "")) != "":
			assert_vector(s["pos"]).is_equal(first[s["poi"]])
	# Every POI reward refers to known things.
	for d: Dictionary in POIS.DEFS:
		for pair: Array in d.get("items", []):
			var known: bool = POIS.ITEMS.has(pair[0]) or FileAccess.get_file_as_string("res://data/items.json").contains("\"%s\"" % pair[0]) \
				or ["mushroom", "healing_herb"].has(pair[0])
			assert_bool(known).override_failure_message("unknown item %s in %s" % [pair[0], d["id"]]).is_true()


func test_journal_lists_found_ones_and_only_counts_the_rest() -> void:
	var d := _disc()
	var j0: Dictionary = POIS.journal(d)
	assert_int(int(j0["total"])).is_equal(POIS.DEFS.size() + 1)        # 56 POIs (26 + 30 for the 12 km world) + the vale
	assert_int((j0["found"] as Array).size()).is_equal(0)
	assert_int(int(j0["unfound"])).is_equal(POIS.DEFS.size() + 1)
	d.discover(_sid(_poi_site("hermit")), 7)
	d.discover(HV.place_id(), 8)
	var j1: Dictionary = POIS.journal(d)
	assert_int((j1["found"] as Array).size()).is_equal(2)
	assert_int(int(j1["unfound"])).is_equal(POIS.DEFS.size() - 1)
	assert_bool(bool(j1["vale"])).is_true()
	# No unfound name or text leaks through the page data.
	var blob := JSON.stringify(j1)
	assert_bool(blob.contains("Kestrel")).is_false()
	assert_bool(blob.contains("Brother Anselm")).is_true()


func test_map_reveal_follows_found_pois_only() -> void:
	var d := _disc()
	assert_int(POIS.reveal_sources(d).size()).is_equal(0)
	d.discover(_sid(_poi_site("kestrel")), 2)
	var src: Array = POIS.reveal_sources(d)
	assert_int(src.size()).is_equal(1)
	assert_float(float(src[0][1])).is_greater(300.0)


func test_rumours_and_hints_are_text_only_and_stop_once_found() -> void:
	var r := HV.rumour()
	assert_str(r).is_not_empty()
	assert_bool(r.contains("(") or r.contains("0")).is_false()      # no coordinates
	for line: String in HV.HUNTER_LINES:
		assert_bool(line.contains(", -")).is_false()


func test_map_fragment_lifts_fog_off_the_vale_and_teaches_a_lead_once() -> void:
	Life.discovery.found.erase("fragment:read")
	assert_bool(HV.read_fragment()).is_true()
	assert_bool(HV.read_fragment()).is_false()
	var src: Array = POIS.reveal_sources(Life.discovery)
	assert_int(src.size()).is_greater(0)
	var hit := false
	for e: Array in src:
		var c: Vector2 = e[0]
		assert_float(c.distance_to(HV.CENTER)).is_greater(float(e[1]))      # the fog over the vale itself stays
		hit = true
	assert_bool(hit).is_true()
	for k: String in Life.discovery.found.keys():
		if k.begins_with("reveal:") or k == "fragment:read":
			Life.discovery.found.erase(k)
