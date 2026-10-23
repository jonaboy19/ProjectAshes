extends GdUnitTestSuite
## Phase W4 (PA_plans/WORLD_BRIEF.md): landmark and POI bodies (data/region1/world/w4_sites.json, scripts/world/region1_w4.gd), the Scar Mouth
## Arena at its canon point, and the landmark terrain stamps (Rift trench, Ashen Scar crater field, mine portals) on both macro modes.

const W4 := preload("res://scripts/world/region1_w4.gd")
const World := preload("res://scripts/world/region1_world.gd")
const Landmarks := preload("res://scripts/region1/region1_landmarks.gd")

## The inventory ids (PA_plans/W4_LANDMARK_INVENTORY.md) with no or partial body before W4: each must be covered by a W4 site or be an alias.
const NO_OR_PARTIAL := ["parchment:", "ashford_ring", "greenhollow_south_fields", "proposed:silverford", "rift_mouth",
	"edge:the_western_reaches", "edge:to_the_aurelis_patriarchate", "edge:to_the_frostcrown_holds", "edge:to_the_solkar_dominion",
	"lore:duskbriar_wood", "lore:duskfen_wood", "site:Emberglass East Landing:-322:300", "lore:greywood", "exit:harrow_arch", "lore:hollowfang_wood",
	"lore:mistwood", "silverford_market", "site:Solkar Caravan Camp:1991:-1831", "lore:ashrun_river", "lore:elden_road", "greenhollow_road",
	"kings_ember_road", "miller_stone", "lore:silverrun_river", "greyseam_seam", "lore:thornwold", "exit:westfen_fen"]
## Covered outside w4_sites.json: the Emberglass landing (landmarks.json parts via Region1Look), the Arena record (sites.json).
const ELSEWHERE := ["site:Emberglass East Landing:-322:300"]


func after() -> void:
	WorldMacro.override = ""
	Region1Terrain.enabled = true
	WorldGen.setup(1066)


func _asset_exists(a: String) -> bool:
	var key := a.split("@")[0]
	if key.begins_with("free:"):
		return ResourceLoader.exists("res://assets/incoming/meshy_free/%s_lod0.glb" % key.substr(5))
	if key.begins_with("dl3:"):
		return ResourceLoader.exists("res://assets/incoming/meshy_dl3/%s_lod0.glb" % key.substr(4))
	if key.begins_with("r1:"):
		var base := "res://assets/incoming/region1/" + key.substr(3)
		return ResourceLoader.exists(base + "_lod0.glb") or ResourceLoader.exists(base + ".glb")
	if key.begins_with("meshy:"):
		return ResourceLoader.exists("res://assets/incoming/ai3d/meshy/%s_lod0.glb" % key.substr(6))
	if key.begins_with("gen:"):
		return ResourceLoader.exists("res://assets/generated/%s.glb" % key.substr(4))
	if key.begins_with("nature:"):
		return ResourceLoader.exists("res://assets/generated/region/nature/%s.glb" % key.substr(7))
	if key.begins_with("props/"):
		return ResourceLoader.exists("res://assets/generated/%s.glb" % key)
	return ResourceLoader.exists("res://assets/generated/region/%s.glb" % key)


func _w4_sites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in WorldGen.sites:
		if String(s.get("r1id", "")).begins_with("w4_"):
			out.append(s)
	return out


# --- data ----------------------------------------------------------------------------------

func test_every_w4_part_is_an_existing_asset() -> void:
	var d := W4.data()
	assert_array(d["sites"]).is_not_empty()
	for spec: Dictionary in d["sites"]:
		assert_array(spec["parts"]).override_failure_message(spec["id"] + " has no parts").is_not_empty()
		for p: Array in spec["parts"]:
			assert_bool(_asset_exists(String(p[0]))).override_failure_message("%s: missing asset %s" % [spec["id"], p[0]]).is_true()


func test_every_no_or_partial_place_has_a_body_or_an_alias() -> void:
	var d := W4.data()
	var covered := {}
	for spec: Dictionary in d["sites"]:
		for c: String in spec.get("covers", []):
			covered[c] = true
	for k: String in (d["aliases"] as Dictionary).keys():
		covered[k] = true
	for k: String in ELSEWHERE:
		covered[k] = true
	for id: String in NO_OR_PARTIAL:
		assert_bool(covered.has(id)).override_failure_message("no W4 site, alias or other body for " + id).is_true()
	# Every alias gives its reason.
	for k: String in (d["aliases"] as Dictionary).keys():
		assert_str(String(d["aliases"][k])).is_not_empty()


func test_emberglass_east_landing_has_a_dock_and_a_boat() -> void:
	var lm: Dictionary = {}
	for l: Dictionary in Landmarks.data().get("landmarks", []):
		if l["id"] == "emberglass_ferry":
			lm = l
	assert_dict(lm).is_not_empty()
	var near := 0
	var dock := false
	var boat := false
	for part: Dictionary in lm["parts"]:
		if not part.has("w"):
			continue
		var w := Vector2(float(part["w"][0]), float(part["w"][1]))
		if w.distance_to(Vector2(-322, 300)) < 40.0:
			near += 1
			dock = dock or String(part["a"]).contains("dock")
			boat = boat or String(part["a"]).contains("boat")
			assert_bool(_asset_exists(String(part["a"]).trim_prefix("res://assets/generated/").trim_suffix(".glb"))).is_true()
	assert_int(near).is_greater_equal(3)
	assert_bool(dock and boat).is_true()


# --- planned world -------------------------------------------------------------------------

func test_w4_sites_are_planned_last_and_on_dry_ground() -> void:
	WorldGen.setup(1066)
	var sites := _w4_sites()
	var d := W4.data()
	var want := 0
	for spec: Dictionary in d["sites"]:
		if not spec.has("milestones"):
			want += 1
	assert_int(sites.size()).override_failure_message("planned %d W4 sites, data has %d single sites + milestones" % [sites.size(), want]).is_greater_equal(want)
	# They are the tail of WorldGen.sites: no earlier id moved.
	var first := WorldGen.sites.size() - sites.size()
	for i in sites.size():
		assert_bool(String(WorldGen.sites[first + i].get("r1id", "")).begins_with("w4_")).is_true()
	for s in sites:
		var p: Vector2 = s["pos"]
		assert_bool(WorldGen.is_water(p.x, p.y)).override_failure_message("%s stands in water" % s["name"]).is_false()
		assert_float(WorldGen.road_distance(p.x, p.y)).override_failure_message("%s on a road" % s["name"]).is_greater(2.5)
	for id in ["w4_ashford_ring", "w4_rift_mouth", "w4_elden_marker", "w4_millers_stone", "w4_silverford_market", "w4_greenhollow_fields",
			"w4_grove_duskbriar", "w4_grove_duskfen", "w4_grove_greywood", "w4_grove_hollowfang", "w4_grove_mistwood", "w4_grove_thornwold",
			"w4_edge_west", "w4_edge_east", "w4_edge_north", "w4_edge_south", "w4_ashrun_marker", "w4_silverrun_marker", "w4_greyseam_seam"]:
		assert_dict(W4.site(id)).override_failure_message("W4 site not planned: " + id).is_not_empty()
	var ember := 0
	var green := 0
	for s in sites:
		ember += 1 if String(s["r1id"]).begins_with("w4_milestones_ember") else 0
		green += 1 if String(s["r1id"]).begins_with("w4_milestones_greenhollow") else 0
	assert_int(ember).override_failure_message("Ember Road milestones").is_greater_equal(3)
	assert_int(green).override_failure_message("Greenhollow Road milestones").is_greater_equal(3)


func test_fixed_sites_sit_on_their_canon_points() -> void:
	WorldGen.setup(1066)
	assert_bool((W4.site("w4_ashford_ring")["pos"] as Vector2).distance_to(Vector2(0, 12)) < 0.1).is_true()
	assert_bool((W4.site("w4_rift_mouth")["pos"] as Vector2).distance_to(Vector2(2699.9, 2513.4)) < 0.1).is_true()
	# Groves stay inside their forest's zone.
	var lore := RAWorldLore.new()
	for pair in [["w4_grove_duskbriar", "duskbriar_wood"], ["w4_grove_greywood", "greywood"], ["w4_grove_mistwood", "mistwood"],
			["w4_grove_thornwold", "thornwold"], ["w4_grove_hollowfang", "hollowfang_wood"], ["w4_grove_duskfen", "duskfen_wood"]]:
		var pl := lore.place(pair[1])
		assert_dict(pl).is_not_empty()
		assert_float((W4.site(pair[0])["pos"] as Vector2).distance_to(pl["pos"])).override_failure_message(pair[0] + " strayed from its forest").is_less(160.0)


func test_scar_mouth_arena_is_one_record_at_the_canon_point() -> void:
	WorldGen.setup(1066)
	var arenas := 0
	for s in WorldGen.sites:
		if String(s["kind"]) == "scar_arena":
			arenas += 1
	assert_int(arenas).is_equal(1)
	var site := World.site("scar_arena")
	assert_bool((site["pos"] as Vector2).distance_to(Vector2(2864.1, 2586.4)) < 0.5).override_failure_message("arena at %s" % site["pos"]).is_true()
	var lore := RAWorldLore.new()
	assert_bool((site["pos"] as Vector2).distance_to(lore.place("scar_arena")["pos"]) < 1.0).is_true()
	assert_bool(WorldGen.is_water(site["pos"].x, site["pos"].y)).is_false()


# --- stamps --------------------------------------------------------------------------------

func _site_pos(name: String) -> Vector2:
	for s in WorldGen.sites:
		if String(s["name"]) == name:
			return s["pos"]
	return Vector2.INF


## Metres added by the W4 stamps alone (the older stamps - Hollin's Reach, Crownstead, the Wyrm's Ridge - have their own tests).
func _w4(x: float, z: float) -> float:
	var d := 0.0
	for e: Dictionary in Region1Terrain._stamps:
		var id := String(e.get("id", ""))
		if not (id.ends_with("_noise") or id.ends_with("_valencious")):
			continue
		if x <= e["x0"] or z <= e["z0"] or x >= e["x1"] or z >= e["z1"]:
			continue
		d += Region1Terrain._sample(e, x, z, 0)
	return d


func _check_stamps(mode: String) -> void:
	WorldMacro.override = mode
	Region1Terrain.enabled = true
	WorldGen.setup(1066)
	var tag := "[" + mode + "] "
	# Only this mode's variants are loaded.
	var ids: Array = []
	for e: Dictionary in Region1Terrain._stamps:
		ids.append(String(e.get("id", "")))
	for id in ["rift_trench", "ashen_scar", "mine_greyseam", "mine_deepvein", "mine_coldseam", "mine_ironroot", "grimfen_pass_cut"]:
		assert_array(ids).override_failure_message(tag + "stamp not loaded: " + id + " in " + str(ids)).contains([id + "_" + mode])
		var other := "valencious" if mode == "noise" else "noise"
		assert_array(ids).override_failure_message(tag + "wrong-mode stamp loaded: " + id).not_contains([id + "_" + other])
	# The Rift: a trench, and the pad of the Rift Edge Camp and every other site is untouched.
	var rift := _site_pos("The Rift")
	# The noise variant runs its trench through the Rift; the valencious variant follows the macro's own trench axis, which is 20 m off it.
	var rc := Vector2.ZERO if mode == "noise" else 19.9 * Vector2(-sin(deg_to_rad(25.0)), cos(deg_to_rad(25.0)))
	var rd := _w4(rift.x + rc.x, rift.y + rc.y)
	assert_float(rd).override_failure_message(tag + "Rift floor delta %.2f" % rd).is_less(-4.0 if mode == "valencious" else -10.0)
	# The Ashen Scar: the Rift Mouth sits at the bottom of the crater.
	var mouth := W4.site("w4_rift_mouth")["pos"] as Vector2
	var cd := _w4(mouth.x, mouth.y)
	assert_float(cd).override_failure_message(tag + "crater floor delta %.2f" % cd).is_less(-5.0)
	assert_float(_w4(mouth.x + 150.0, mouth.y)).override_failure_message(tag + "crater rim").is_greater(-4.0)
	# Mine portals: a raised brow behind the entrance.
	for mn in ["Greyseam Mine", "Deepvein Mine", "Coldseam Mine", "Ironroot Mine"]:
		var site: Dictionary = {}
		for s in WorldGen.sites:
			if String(s["name"]) == mn:
				site = s
		assert_dict(site).is_not_empty()
		var f := Vector2(sin(float(site["yaw"])), cos(float(site["yaw"])))
		var behind: Vector2 = site["pos"] - f * 9.0
		var brow := _w4(behind.x, behind.y)
		assert_float(brow).override_failure_message("%s%s brow %.2f" % [tag, mn, brow]).is_greater(1.5)
		# The portal itself keeps its ground (the entrance stands where it did).
		var at: Vector2 = site["pos"]
		assert_float(absf(_w4(at.x, at.y))).override_failure_message("%s%s portal moved %.2f" % [tag, mn, _w4(at.x, at.y)]).is_less(0.6)
	# No planned site pad (other than the stamps' own) is touched, nor any settlement centre, nor a road bed.
	var moved: Array[String] = []
	for s in WorldGen.sites:
		var p: Vector2 = s["pos"]
		if float(s["clear"]) <= 0.0 or not bool(s["flatten"]) or String(s["name"]) in ["The Rift", "The Rift Mouth", "Grimfen Pass"]:
			continue
		var d := _w4(p.x, p.y)
		if absf(d) > 0.05:
			moved.append("%s %.2f" % [s["name"], d])
	assert_array(moved).override_failure_message(tag + "stamps move site pads: " + str(moved)).is_empty()
	for st in WorldGen.settlements:
		assert_float(absf(_w4(st["pos"].x, st["pos"].y))).is_less(0.01)
	# Far from every stamp the ground is untouched.
	assert_float(_w4(0.0, 0.0)).is_equal(0.0)


func test_stamps_on_the_noise_terrain() -> void:
	_check_stamps("noise")


func test_stamps_on_the_valencious_macro() -> void:
	_check_stamps("valencious")


## Positions measured before W4 (sites_base dump, seed 1066): the late stamps start after planning, so none of these moves.
func test_planned_sites_did_not_move() -> void:
	var want := {"Greyseam Mine": Vector2(-150.0, -470.0), "The Rift": Vector2(1130.2, 1004.4), "Rift's Edge Camp": Vector2(1069.2, 991.1),
		"Deepvein Mine": Vector2(-738.5, -2563.7), "Ironroot Mine": Vector2(-4047.9, 1304.6), "Coldseam Mine": Vector2(2782.7, -5622.3),
		"The Ashen Scar": Vector2(2509.3, 2468.2), "Scar Watch": Vector2(2469.9, 2419.7), "Highwatch Elder Stone": Vector2(105.5, -1650.1),
		"Greyseam Elder Stone": Vector2(-188.1, -499.2), "Elden Elder Stone": Vector2(-1199.6, -91.3), "The Eastern Gate": Vector2(3771.9, 480.8),
		"Grimfen Pass": Vector2(559.5, -3597.8), "Emberglass East Landing": Vector2(-322.0, 300.0)}
	for mode in ["noise", "valencious"]:
		WorldMacro.override = mode
		WorldGen.setup(1066)
		for n: String in want:
			assert_bool(_site_pos(n).distance_to(want[n]) < 0.15).override_failure_message("[%s] %s moved: %s vs %s" % [mode, n, _site_pos(n), want[n]]).is_true()
