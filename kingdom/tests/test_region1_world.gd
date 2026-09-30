extends GdUnitTestSuite
## Region 1 world packages C0 C1 C2 C10 C11 (docs/regions/REGION_1_PLAN.md): canon data, poster places as sites, one identity
## per settlement, border teases, creature placement.

const World := preload("res://scripts/world/region1_world.gd")
const Identity := preload("res://scripts/world/region1_identity.gd")
const Creatures := preload("res://scripts/world/region1_creatures.gd")
const CANON := ["highwatch_keep", "elder_highwatch", "elder_greyseam", "elder_elden", "crownstead_estate", "dawn_chapel",
	"eastern_gate", "grimfen_pass", "scar_arena", "solkar_camp"]


func before() -> void:
	WorldGen.setup(1066)


func _asset_exists(a: String) -> bool:
	var key := a.split("@")[0]
	var base := ""
	if key.begins_with("free:"):
		return ResourceLoader.exists("res://assets/incoming/meshy_free/%s_lod0.glb" % key.substr(5))
	if key.begins_with("r1:"):
		base = "res://assets/incoming/region1/" + key.substr(3)
		return ResourceLoader.exists(base + "_lod0.glb") or ResourceLoader.exists(base + ".glb")
	if key.begins_with("gen:"):
		return ResourceLoader.exists("res://assets/generated/%s.glb" % key.substr(4))
	if key.begins_with("nature:"):
		return ResourceLoader.exists("res://assets/generated/region/nature/%s.glb" % key.substr(7))
	if key.begins_with("props/"):
		return ResourceLoader.exists("res://assets/generated/%s.glb" % key)
	return ResourceLoader.exists("res://assets/generated/region/%s.glb" % key)


# --- C0 canon data ------------------------------------------------------------------

func test_canon_names_keep_ids() -> void:
	var lore := RAWorldLore.new()
	assert_dict(lore.errors).is_empty()
	var cal := lore.nation("caldrenn")
	assert_str(str(cal["name"])).is_equal("Kingdom of Valencious")
	assert_str(str(cal["dynasty"])).is_equal("House Caldrenn")
	assert_str(str(lore.nation("solmarch")["name"])).contains("Aurelis Patriarchate")
	assert_str(str(lore.nation("ongur_khanate")["region_name"])).is_equal("Zephyr Steppe")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/nations.json"))
	var ids := []
	for n: Dictionary in raw["teaser_realms"]:
		ids.append(n["id"])
	for want in ["varska_marches", "serathi_lowlands", "solkar_dominion", "frostcrown_holds", "umbrafen_marsh"]:
		assert_array(ids).contains([want])
	# Teasers are not wars or factions: they stay out of `nations`.
	assert_dict(lore.nation("solkar_dominion")).is_empty()


func test_regions_json_has_locked_exits_with_hints() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/regions.json"))
	var exits: Array = d["exits"]
	assert_int(exits.size()).is_greater_equal(4)
	for e: Dictionary in exits:
		assert_bool(bool(e["locked"])).is_true()
		assert_str(str(e["hint"])).is_not_empty()
	for r: Dictionary in d["regions"]:
		if r["status"] == "unexplored":
			assert_str(str(r["hint"])).is_not_equal("The %s reaches" % str(r["id"]).get_slice("_", 0))


func test_first_region_lists_the_poster_places() -> void:
	var lore := RAWorldLore.new()
	for id in ["silverford", "greenhollow", "highwatch_keep", "crownstead", "elden_road", "elder_glade", "elder_greyseam", "elder_highwatch",
			"elder_crownstead", "elder_elden", "eastern_gate", "grimfen_pass", "miller_stone", "old_mill_staff_yard", "silverford_guild_hall"]:
		assert_dict(lore.place(id)).override_failure_message("first_region.json lacks " + id).is_not_empty()
	# A lore place that stands for a planned site sits on it.
	for id in ["highwatch_keep", "eastern_gate", "grimfen_pass", "elder_greyseam", "elder_elden", "elder_highwatch"]:
		var site := World.site(id)
		var pl := lore.place(id)
		assert_bool((pl["pos"] as Vector2).distance_to(site["pos"]) < 3.0).override_failure_message("%s lore pos %s vs site %s" % [id, pl["pos"], site["pos"]]).is_true()


# --- C2 settlement identity -----------------------------------------------------------

func test_every_settlement_has_its_own_identity() -> void:
	var list := Identity.all()
	assert_int(list.size()).is_equal(WorldGen.settlements.size())
	var trades := {}
	var npcs := {}
	var landmarks := {}
	for s in WorldGen.settlements:
		var st := Identity.of(String(s["name"]))
		assert_dict(st).override_failure_message("no identity for " + String(s["name"])).is_not_empty()
		assert_str(str(st["trade"])).is_not_empty()
		assert_int((st["rumours"] as Array).size()).is_greater_equal(4)
		var lm: Dictionary = st["landmark"]
		assert_int((lm["parts"] as Array).size()).is_greater_equal(10)
		var npc: Dictionary = st["npc"]
		assert_str(str(npc["name"])).is_not_empty()
		assert_bool(Assets.MH_LOOKS.has(str(npc["look"])) or Assets.LOOKS.has(str(npc["look"]))).override_failure_message("look " + str(npc["look"])).is_true()
		assert_int((npc["lines"] as Array).size()).is_greater_equal(3)
		for r: String in st["rumours"]:
			assert_int(r.length()).is_less_equal(140)
		assert_bool(trades.has(st["trade"]) or npcs.has(npc["name"]) or landmarks.has(lm["name"])).is_false()
		trades[st["trade"]] = true
		npcs[npc["name"]] = true
		landmarks[lm["name"]] = true
		# ... and a body in the world, beside the town.
		var site := World.site("landmark_" + String(s["name"]).to_lower())
		assert_dict(site).override_failure_message("no landmark site for " + String(s["name"])).is_not_empty()
		assert_float((site["pos"] as Vector2).distance_to(s["pos"])).is_less(float(s["radius"]) * 1.15 + 140.0)
		assert_str(str(site["town"])).is_equal(String(s["name"]))
		assert_bool(site.has("x")).is_true()


func test_poster_aliases() -> void:
	assert_str(Identity.display_name("Oakvale")).is_equal("Greenhollow")
	assert_str(Identity.display_name("Ironmarch")).is_equal("Silverford")
	assert_str(Identity.display_name("Ashford")).is_equal("Ashford")
	var d = preload("res://scripts/sim/discovery.gd").new()
	d.build_from_world([])
	var names := []
	for pl: Dictionary in d.places:
		names.append(pl["name"])
	for n in ["Silverford", "Greenhollow", "Highwatch Keep", "The Eastern Gate", "Grimfen Pass", "Greyseam Elder Stone", "Scar Mouth Arena",
			"Chapel of the Dawn Throne", "Crownstead Steward's Hall", "Stagborn Glade"]:
		assert_array(names).override_failure_message("map lacks " + n).contains([n])
	assert_bool(names.has("Oakvale")).is_false()
	# Closed exits carry their hint for the map card.
	for pl: Dictionary in d.places:
		if pl["name"] in ["The Eastern Gate", "Grimfen Pass"]:
			assert_bool(bool(pl["locked"])).is_true()
			assert_str(str(pl["hint"])).is_not_empty()


func test_rumour_near_is_local() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for s in WorldGen.settlements:
		var r := Identity.rumour_near(s["pos"], rng)
		assert_str(r).is_not_empty()
		assert_array(Identity.of(String(s["name"]))["rumours"]).contains([r])
	assert_str(Identity.rumour_near(Vector2(-3900, -3900), rng)).is_empty()


# --- C1 layout ---------------------------------------------------------------------------

func test_canon_sites_exist_and_are_appended() -> void:
	var academy_id := -1
	for s in WorldGen.sites:
		if String(s["kind"]) == "academy":
			academy_id = int(s["id"])
	for id in CANON:
		var s := World.site(id)
		assert_dict(s).override_failure_message("missing site " + id).is_not_empty()
		assert_int(int(s["id"])).override_failure_message("%s must come after the academy" % id).is_greater(academy_id)
		var p: Vector2 = s["pos"]
		assert_bool(WorldGen.is_water(p.x, p.y)).override_failure_message(id + " wet").is_false()
		assert_int((s["parts"] as Array).size()).override_failure_message("%s has %d parts (draw-call budget 45)" % [id, (s["parts"] as Array).size()]).is_less_equal(45)
		for part: Array in s["parts"]:
			assert_bool(_asset_exists(String(part[0]))).override_failure_message("%s: missing asset %s" % [id, part[0]]).is_true()
	for s in WorldGen.sites:
		if String(s.get("r1id", "")).begins_with("landmark_"):
			for part: Array in s["parts"]:
				assert_bool(_asset_exists(String(part[0]))).override_failure_message("%s: missing asset %s" % [s["name"], part[0]]).is_true()
	assert_int((World.site("highwatch_keep")["parts"] as Array).size()).is_less_equal(40)


func test_canon_geography() -> void:
	var by_name := {}
	for s in WorldGen.settlements:
		by_name[String(s["name"])] = s
	var keep := World.site("highwatch_keep")["pos"] as Vector2
	assert_bool(keep.y < (by_name["Highcliff"]["pos"] as Vector2).y).is_true()          # the keep is on the ridge north of Highcliff
	assert_float(keep.distance_to(by_name["Highcliff"]["pos"])).is_less(520.0)
	var gate := World.site("eastern_gate")["pos"] as Vector2
	assert_float(gate.x).is_greater(3300.0)                                              # east
	var pass_pos := World.site("grimfen_pass")["pos"] as Vector2
	assert_float(pass_pos.y).is_less(-3000.0)                                            # north
	assert_bool(World.site("eastern_gate")["locked"]).is_true()
	assert_bool(World.site("grimfen_pass")["locked"]).is_true()
	assert_str(str(World.site("solkar_camp")["season"])).is_equal("summer")
	# Elden road stones run from the shrine to the Elden Elder Stone.
	var n := 0
	for s in WorldGen.sites:
		if String(s.get("r1id", "")).begins_with("elden_waymark"):
			n += 1
	assert_int(n).is_greater_equal(3)


func test_world_sites_are_deterministic() -> void:
	var first := []
	for id in CANON:
		first.append(World.site(id)["pos"])
	WorldGen.setup(1066)
	for i in CANON.size():
		assert_vector(World.site(CANON[i])["pos"]).is_equal(first[i])


func test_settlement_sites_do_not_overlap() -> void:
	var list: Array = []
	for s in WorldGen.sites:
		if String(s.get("r1id", "")) != "":
			list.append(s)
	for i in list.size():
		for j in range(i + 1, list.size()):
			var a: Dictionary = list[i]
			var b: Dictionary = list[j]
			if String(a["kind"]) == "waystone" or String(b["kind"]) == "waystone" or String(a["r1id"]) == "elder_highwatch" or String(b["r1id"]) == "elder_highwatch":
				continue
			assert_float((a["pos"] as Vector2).distance_to(b["pos"])).override_failure_message("%s overlaps %s" % [a["name"], b["name"]]).is_greater(float(a["clear"]) * 0.6 + float(b["clear"]) * 0.6)


func test_dressing_builds_world_sites_with_people_and_signs() -> void:
	var d := RegionDressing.new()
	add_child(d)
	d.build_all_now()
	var boards := 0
	var stations := 0
	for n in d.find_children("NameBoard", "Node3D", true, false):
		boards += 1
	for n in d.find_children("*", "Station", true, false):
		stations += 1
	assert_int(boards).is_greater_equal(20)
	assert_int(stations).is_greater_equal(20)
	d.free()


# --- C11 creatures --------------------------------------------------------------------------

func test_creature_species_are_wired() -> void:
	var cfg := Creatures.data()
	var species := {}
	for spec: Dictionary in cfg["dens"]:
		species[spec["species"]] = true
	for sp: String in species:
		assert_bool(RAMonsterEcology.SPECIES.has(sp)).override_failure_message("ecology lacks " + sp).is_true()
		assert_bool(Wolf.SPECIES.has(sp)).override_failure_message("Wolf.SPECIES lacks " + sp).is_true()
		assert_bool(preload("res://scripts/actors/creature_models.gd").MODELS.has(sp)).override_failure_message("models lack " + sp).is_true()
		assert_bool(preload("res://scripts/actors/creature_models.gd").has(sp)).override_failure_message("model file missing for " + sp).is_true()
	for sp in ["stagborn_elk", "stagborn_warden", "ghoul", "giant_wasp", "bog_toad", "rift_slime", "rift_wraith"]:
		assert_bool(species.has(sp)).is_true()


func test_seed_ecology_once_per_species() -> void:
	var eco := RAMonsterEcology.new(11)
	var added := Creatures.seed_ecology(eco)
	assert_int(added).is_greater_equal(15)
	assert_int(Creatures.seed_ecology(eco)).is_equal(0)
	var herds := 0
	var near_water_toads := 0
	for d: Dictionary in eco.dens:
		var p: Vector2 = d["pos"]
		assert_bool(WorldGen.is_water(p.x, p.y)).override_failure_message("%s den in water" % d["species"]).is_false()
		if d["species"] == "stagborn_elk":
			herds += 1
		if d["species"] == "bog_toad" and WorldGen.near_water(p.x, p.y, 40.0):
			near_water_toads += 1
	assert_int(herds).is_equal(2)
	assert_int(near_water_toads).is_greater_equal(2)
	# Stagborn are harmless in the threat map; the Warden is an optional guardian, not an apex that pushes wolves out.
	assert_float(float(RAMonsterEcology.SPECIES["stagborn_elk"]["threat"])).is_equal(0.0)
	assert_bool(bool(RAMonsterEcology.SPECIES["stagborn_warden"].get("apex", false))).is_false()
	# Same seed, same world.
	var eco2 := RAMonsterEcology.new(99)
	Creatures.seed_ecology(eco2)
	assert_int(eco2.dens.size()).is_equal(eco.dens.size())
	for i in eco.dens.size():
		assert_vector(eco.dens[i]["pos"]).is_equal(eco2.dens[i]["pos"])


func test_stagborn_migrate_with_the_seasons() -> void:
	var eco := RAMonsterEcology.new(5)
	Creatures.seed_ecology(eco)
	var herd: Dictionary = {}
	for d: Dictionary in eco.dens:
		if d["species"] == "stagborn_elk":
			herd = d
			break
	var home: Vector2 = herd["pos"]
	for day in 30:
		Creatures.herd_step(eco, "spring", day)
	var north: Vector2 = herd["pos"]
	assert_float(north.distance_to(home)).is_greater(500.0)
	assert_bool(north.y < home.y).is_true()                       # they go north
	var logged := false
	for ev: Dictionary in eco.events_since(0):
		logged = logged or ev["type"] == "herd_migration"
	assert_bool(logged).is_true()
	for day in 60:
		Creatures.herd_step(eco, "autumn", 30 + day)
	assert_float((herd["pos"] as Vector2).distance_to(home)).is_less(north.distance_to(home))


func test_bandit_rosters_cover_every_camp() -> void:
	var camps: Dictionary = Creatures.data()["camps"]
	var n := 0
	for s in WorldGen.sites:
		if String(s["kind"]) == "bandit_camp":
			n += 1
			var r: Dictionary = camps.get(String(s["name"]), Creatures.data()["camp_default"])
			assert_int(int(r["n"])).is_between(3, 8)
	assert_int(n).is_greater_equal(4)
	assert_bool(camps.has("Bandit Camp")).is_true()
