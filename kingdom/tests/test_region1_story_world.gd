extends GdUnitTestSuite
## The story keyed to the real 12 km world: every place the quest names resolves to a world site (by r1id / name /
## settlement, not the registry's guess), is on dry land, and the runestones the steps carve, link and relight exist
## and are fed by an Elder Stone in the wardlines built the way the glue builds them.

const Places := preload("res://scripts/region1/region1_places.gd")
const Ward := preload("res://scripts/region1/wardlines.gd")
const ELDER_PREFIX := "Elder Stone ("
const ELDERS := ["elder_glade", "elder_greyseam", "elder_highwatch", "elder_crownstead", "elder_elden"]
## Places that are spots inside a settlement; the registry's metres-from-Ashford guess is right for them.
const FALLBACK_OK := ["ashford_ring", "miller_stone", "duskbriar_wood", "kings_ember_road", "shrine_of_the_sleeping_flame",
	"tuskridge_hold", "mossfang_warren"]

var net: RARunestoneNetwork
var wl


func before() -> void:
	WorldGen.setup(1066)


func before_test() -> void:
	Places.clear()


func after_test() -> void:
	Places.clear()


func _story_places() -> Array[String]:
	var out: Array[String] = []
	var q: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/region1/quests/r1_main.json"))
	for s: Dictionary in q["steps"]:
		out.append(String(s["place"]))
		for o: Dictionary in s["objectives"]:
			for sub: Dictionary in ((o["of"] as Array) if String(o["type"]) == "any" else [o]):
				for k in ["place", "site", "to", "from"]:
					if sub.has(k) and (Places.registry()["places"] as Dictionary).has(String(sub[k])):
						out.append(String(sub[k]))
	return out


func test_every_story_place_is_a_real_site_on_dry_land() -> void:
	var bad: Array[String] = []
	var seen := {}
	for id in _story_places() + ELDERS + ["scar_watch"]:
		if seen.has(id):
			continue
		seen[id] = true
		var r := Places.resolve(id)
		if r.is_empty():
			bad.append("%s unresolved" % id)
			continue
		if String(r["source"]) == "registry" and not FALLBACK_OK.has(id):
			bad.append("%s only has the registry guess" % id)
		var p: Vector2 = r["pos"]
		if WorldGen.is_water(p.x, p.y):
			bad.append("%s is in water at %s" % [id, p])
	assert_array(bad).override_failure_message("place problems: %s" % [bad]).is_empty()


func test_places_are_where_the_world_says() -> void:
	# Spot checks against the sites the world planners placed.
	var hw: Dictionary = {}
	for s in WorldGen.sites:
		if String(s.get("r1id", "")) == "highwatch_keep":
			hw = s
	assert_bool(hw.is_empty()).is_false()
	assert_float((Places.position_of("highwatch_keep") as Vector2).distance_to(hw["pos"])).is_less(1.0)
	assert_float((Places.position_of("rift_mouth") as Vector2).distance_to(_site_pos("Scar Mouth Arena"))).is_less(1.0)
	assert_float((Places.position_of("ashen_scar") as Vector2).distance_to(_site_pos("The Ashen Scar"))).is_less(1.0)
	assert_float((Places.position_of("greenhollow_farm") as Vector2).distance_to(_site_pos("Pennick Farm, Greenhollow"))).is_less(1.0)
	assert_float((Places.position_of("stagborn_glade") as Vector2).distance_to(_site_pos("Stagborn Glade"))).is_less(1.0)
	# The elder stone sites the world built are the story's elder stones.
	assert_float((Places.position_of("elder_elden") as Vector2).distance_to(_site_pos("Elden Elder Stone"))).is_less(1.0)
	assert_float((Places.position_of("elder_greyseam") as Vector2).distance_to(_site_pos("Greyseam Elder Stone"))).is_less(1.0)
	assert_float((Places.position_of("elder_highwatch") as Vector2).distance_to(_site_pos("Highwatch Elder Stone"))).is_less(1.0)
	# Order along the story's road is plausible: the finale is the farthest place from Ashford.
	var far := (Places.position_of("rift_mouth") as Vector2).length()
	for id in ["greenhollow", "silverford", "highwatch_keep", "crownstead", "elden_road", "greyseam_mine", "stagborn_glade"]:
		assert_float((Places.position_of(id) as Vector2).length()).is_less(far)


func _site_pos(site_name: String) -> Vector2:
	for s in WorldGen.sites:
		if String(s["name"]) == site_name:
			return s["pos"]
	return Vector2.INF


## The network as the game builds it plus the glue's additions (Elder Stones, story stones), bound to Wardlines.
func _build_wardlines() -> void:
	Frontier.reset()
	net = Frontier.runestones
	for id in ELDERS:
		var r := Places.resolve(id)
		var s := net.add_stone(r["pos"], 240.0, -1, ELDER_PREFIX + id + ")")
		s["elder"] = true
	for spec: Dictionary in Places.story_stone_specs():
		var have := false
		for s: Dictionary in net.stones:
			if String(s["name"]) == String(spec["name"]) or (not bool(spec["force"]) and not String(s["name"]).begins_with(ELDER_PREFIX) and (s["pos"] as Vector2).distance_to(spec["pos"]) < 70.0):
				have = true
				break
		if not have:
			net.add_stone(spec["pos"], 130.0, -1, String(spec["name"]))
	var elders := PackedInt32Array()
	for s: Dictionary in net.stones:
		if String(s["name"]).begins_with(ELDER_PREFIX):
			elders.append(int(s["id"]))
	wl = Ward.new().setup(1066)
	wl.bind_network(net, elders)


func _nearest(pos: Vector2, elder: bool) -> int:
	var best := -1
	var bd := INF
	for s: Dictionary in net.stones:
		if String(s["name"]).begins_with(ELDER_PREFIX) != elder:
			continue
		var d: float = (s["pos"] as Vector2).distance_to(pos)
		if d < bd:
			bd = d
			best = int(s["id"])
	return best


func test_every_stone_the_story_carves_is_fed_by_an_elder() -> void:
	_build_wardlines()
	var reg: Dictionary = Places.registry()["stones"]
	var checked := 0
	for sid: String in reg:
		if sid.begins_with("_") or String(reg[sid]["kind"]) == "elder" or bool(reg[sid].get("group", false)):
			continue
		var pos: Vector2 = Places.position_of(String(reg[sid]["place"]))
		var id := _nearest(pos, false)
		assert_int(id).override_failure_message("no stone for %s" % sid).is_greater(-1)
		assert_float((net.stones[id]["pos"] as Vector2).distance_to(pos)).override_failure_message("%s: nearest stone is %.0f m away" % [sid, (net.stones[id]["pos"] as Vector2).distance_to(pos)]).is_less(120.0)
		assert_int(wl.supplier[id]).override_failure_message("%s (%s) has no Elder feeding it" % [sid, net.stones[id]["name"]]).is_greater(-1)
		assert_float(wl.charge[id]).override_failure_message("%s is too dim to carve (%.2f)" % [sid, wl.charge[id]]).is_greater_equal(0.25)
		checked += 1
	assert_int(checked).is_greater(4)


func test_greenhollow_road_has_stones_and_rifts_edge_has_three() -> void:
	_build_wardlines()
	var road := Places.position_of("greenhollow_road") as Vector2
	var n := 0
	for s: Dictionary in net.stones:
		if String(s.get("road_to", "")) in ["Oakvale", "Greenhollow"] and (s["pos"] as Vector2).distance_to(road) < 260.0:
			n += 1
	assert_int(n).override_failure_message("stones on the Greenhollow road near its place: %d" % n).is_greater_equal(2)
	# ...and they are fed, so the two ward carves the step asks for can be made.
	for s: Dictionary in net.stones:
		if String(s.get("road_to", "")) == "Oakvale" and (s["pos"] as Vector2).distance_to(road) < 260.0:
			assert_int(wl.supplier[int(s["id"])]).override_failure_message("%s has no Elder feeding it" % s["name"]).is_greater(-1)
			assert_float(wl.charge[int(s["id"])]).override_failure_message("%s too dim (%.2f)" % [s["name"], wl.charge[int(s["id"])]]).is_greater_equal(0.25)
	var camp := Places.position_of("rifts_edge_camp") as Vector2
	var m := 0
	for s: Dictionary in net.stones:
		if (s["pos"] as Vector2).distance_to(camp) < 260.0 and not String(s["name"]).begins_with(ELDER_PREFIX):
			m += 1
	assert_int(m).is_greater_equal(3)
	# Kingsreach has a stone for Crownstead's line, within link range of the Crownstead Elder Stone.
	var kr := Places.position_of("kingsreach") as Vector2
	var best := INF
	for s: Dictionary in net.stones:
		if not String(s["name"]).begins_with(ELDER_PREFIX):
			best = minf(best, (s["pos"] as Vector2).distance_to(kr))
	assert_float(best).is_less(260.0)
	var el := _nearest(Places.position_of("elder_crownstead"), true)
	assert_bool(el >= 0 and String(net.stones[el]["name"]).contains("elder_crownstead")).is_true()
