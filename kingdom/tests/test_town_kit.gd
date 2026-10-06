extends GdUnitTestSuite
## The town kit (scripts/world/town_kit/, scripts/world/town_kit/town_data.gd): every settlement with a data/region1/towns/<id>.json gets the
## living-place treatment, and all 30 Region 1 settlements have one. Thornfield is the hand-made first user (test_thornfield.gd keeps its
## behaviour); the other 29 are generated (tools/towns/gen_town.py) and prove the kit is data-driven. Checked for EVERY town file: it
## loads and validates, the roster binds to distinct WorldSim rows, the required lots exist, names are unique region-wide, the dialogue
## files exist and vary, the roles and the threat fit the identity (all twelve archetypes, the capital's court), the livestock and pens
## are sound, and each generated quest line is played to its end by firing events through the kit (hub, clues, stash, talk menu, kill
## events). Scale: hubs asleep far away cost nothing per frame (cell streamer tiers), wake in range, and bind cheaply.

const TownData := preload("res://scripts/world/town_kit/town_data.gd")
const TownRoster := preload("res://scripts/world/town_kit/town_roster.gd")
const TownLots := preload("res://scripts/world/town_kit/town_lots.gd")
const TownPlaces := preload("res://scripts/world/town_kit/town_places.gd")
const TownHub := preload("res://scripts/world/town_kit/town_hub.gd")
const TownThreat := preload("res://scripts/world/town_kit/town_threat.gd")
const TownLivestock := preload("res://scripts/world/town_kit/town_livestock.gd")
const TownClues := preload("res://scripts/world/town_kit/town_clues.gd")
const TownTalk := preload("res://scripts/world/town_kit/town_talk.gd")
const Talk := preload("res://scripts/quests/quest_talk.gd")
const Perception := preload("res://scripts/population/perception.gd")
const DialogueRunner := preload("res://scripts/sim/dialogue_runner.gd")
const CellStreamer := preload("res://scripts/core/cell_streamer.gd")
## An authority role per archetype (the first resident of a town, the giver of its first quest); "reeve" for the rest.
const AUTHORITY := {"royal": "chamberlain", "mining": "yard-boss", "fortress": "watch-commander", "hunting": "huntmaster", "fishing": "harbourmaster",
	"merchant": "factor", "criminal": "headman", "religious": "chaplain"}
## Any one of these roles shows that the roster follows the identity.
const ARCH_ROLES := {"royal": ["tourney marshal", "household knight", "court scribe", "courtier"], "farming": ["farmer"], "pastoral": ["shepherd"],
	"craft": ["dyer", "weaver", "wheelwright", "cloth merchant"], "mining": ["miner"], "fortress": ["soldier"], "hunting": ["hunter"],
	"religious": ["chaplain", "beekeeper", "herbwife"], "merchant": ["trader", "weigh-master"], "scholarly": ["glasswright", "lamp-maker"],
	"criminal": ["trapper", "tanner", "go-between", "raven keeper"], "fishing": ["fisher", "boatwright"]}

var _time_before := 12.0
var _day_before := 1


func before() -> void:
	WorldGen.setup(WorldSim.SEED)
	WorldSim.reset()          # a clean population, and every roster bound to it


func after() -> void:
	# The Thornfield special prewarms the grain cart's route on a worker thread; let it finish before the process exits.
	var barn := TownPlaces.door_of_site("thornfield", "thornfield_barn")
	var mill := TownPlaces.door_of_site("thornfield", "thornfield_mill")
	if barn != Vector2.INF and mill != Vector2.INF:
		preload("res://scripts/world/thornfield/cart_route.gd").plan(barn, mill)


func before_test() -> void:
	QuestHub.reset()
	QuestBus.reset_shared()
	_time_before = WorldSim.time_of_day
	_day_before = WorldSim.day


func after_test() -> void:
	QuestHub.reset()
	QuestBus.reset_shared()
	WorldSim.time_of_day = _time_before
	WorldSim.day = _day_before
	preload("res://scripts/core/node_pool.gd").clear_all()
	Perception.set_environment(12.0)
	_clear_pack()
	CellStreamer.reset_shared()


func _generated() -> Array[String]:
	var out: Array[String] = []
	for id: String in TownData.ids():
		if id != "thornfield":
			out.append(id)
	return out


func _clear_pack() -> void:
	for it: InventoryItem in Life.inventory.get_items().duplicate():
		Life.inventory.remove_item(it)


func _player_at(p: Vector2) -> Node3D:
	var n := Node3D.new()
	var sc := GDScript.new()                  # a stand-in player: the properties the quest pump and the creatures read
	sc.source_code = "extends Node3D\nvar crouching := false\nvar dead := false\n"
	sc.reload()
	n.set_script(sc)
	n.add_to_group("player")
	add_child(n)
	n.global_position = Vector3(p.x, 0.0, p.y)
	return auto_free(n)


# ---------------------------------------------------------------- the data
func test_every_town_file_loads_and_validates() -> void:
	var ids := TownData.ids()
	assert_int(ids.size()).is_equal(WorldGen.settlements.size())          # S2: every Region 1 settlement has the treatment
	for s in WorldGen.settlements:
		assert_bool(TownData.has_town(String(s["name"]))).override_failure_message(String(s["name"]) + " has no town file").is_true()
	for must: String in ["thornfield", "millbrook", "redwater", "kingsreach", "ashford", "saltwick", "skarholm"]:
		assert_bool(ids.has(must)).override_failure_message(must + " has no town file").is_true()
	for id: String in ids:
		var doc := TownData.town(id)
		assert_str(String(doc["id"])).is_equal(id)
		var errs := TownData.validate(doc)
		assert_array(Array(errs)).override_failure_message("%s: %s" % [id, "; ".join(errs)]).is_empty()
		var n := TownData.residents(id).size()
		assert_int(n).override_failure_message(id + " roster size").is_between(10, 25)


func test_a_broken_town_file_is_reported() -> void:
	var doc: Dictionary = TownData.town("millbrook").duplicate(true)
	(doc["residents"] as Array)[1]["name"] = (doc["residents"] as Array)[0]["name"]       # a duplicate name
	(doc["residents"] as Array)[2]["home"] = "millbrook_nowhere"
	(doc["lots"]["required"] as Array)[0]["btype"] = "castle"
	doc["threat"]["probe_place"] = "nowhere"
	var errs := TownData.validate(doc, false)
	var text := "; ".join(errs)
	assert_str(text).contains("duplicated").contains("not a lot or a door").contains("unknown lot type").contains("probe_place")


func test_the_town_files_match_the_live_world() -> void:
	var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/region1/world/settlement_facts.json"))
	var by_name := {}
	for f: Dictionary in facts["settlements"]:
		by_name[String(f["name"])] = f
	for id: String in TownData.ids():
		var doc := TownData.town(id)
		var s := TownPlaces.settlement(id)
		assert_bool(s.is_empty()).override_failure_message(id + " is not a settlement").is_false()
		assert_str(String(s["kind"])).is_equal(String(doc["kind"]))
		assert_int(int(s["population"])).is_equal(int(doc["population"]))
	# The facts file (what the generator reads) agrees with WorldGen for every settlement.
	for s in WorldGen.settlements:
		var f: Dictionary = by_name[String(s["name"])]
		assert_str(String(f["kind"])).is_equal(String(s["kind"]))
		assert_int(int(f["population"])).is_equal(int(s["population"]))
		assert_int(int(f["id"])).is_equal(int(s["id"]))


func test_names_are_unique_across_all_town_files() -> void:
	var seen := {}
	var ids_seen := {}
	for id: String in TownData.ids():
		for e: Dictionary in TownData.residents(id):
			var nm := String(e["name"])
			assert_bool(seen.has(nm)).override_failure_message("%s: '%s' also lives in %s" % [id, nm, seen.get(nm, "")]).is_false()
			seen[nm] = id
			var rid := String(e["id"])
			assert_bool(ids_seen.has(rid)).override_failure_message("roster id %s repeated" % rid).is_false()
			ids_seen[rid] = id
	# Nor do they borrow the names of the settlement identities' named NPCs or the main cast.
	var st: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/region1/world/settlements.json"))
	for s: Dictionary in st["settlements"]:
		if String(s["npc"]["name"]) != "Hesta Thorne":     # Thornfield's own identity NPC is its roster's brewmistress
			assert_bool(seen.has(String(s["npc"]["name"]))).override_failure_message(String(s["npc"]["name"])).is_false()
	for cast: String in ["Maren Coldbrook", "Bram Hollis", "Idra Vell", "Odrin Thale", "Rowan Ashby", "Tamsin Reeve", "Wren Coldbrook"]:
		assert_bool(seen.has(cast)).override_failure_message(cast).is_false()


func test_generated_residents_have_roles_traits_ties_and_several_lines() -> void:
	for id: String in _generated():
		var doc := TownData.town(id)
		var arch := String((doc["identity"] as Dictionary)["arch"])
		var jobs := {}
		for e: Dictionary in TownData.residents(id):
			var rid := String(e["id"])
			assert_int((e["traits"] as Array).size()).override_failure_message(rid).is_between(2, 3)
			assert_bool((e["relationships"] as Dictionary).is_empty()).override_failure_message(rid + " has no ties").is_false()
			var d: Dictionary = e["dialogue"]
			var lines := (d["greeting"] as Array).size() + (d["rumour"] as Array).size() + (d["opinions"] as Dictionary).size()
			assert_int(lines).override_failure_message("%s has %d lines" % [rid, lines]).is_between(4, 9)
			jobs[String(e["role"])] = true
		assert_bool(jobs.has("elder")).override_failure_message(id + " lacks an elder").is_true()
		if int(doc["population"]) >= 150:
			assert_bool(jobs.has("child")).override_failure_message(id + " lacks a child").is_true()
		# The first resident is the town's authority, and gives the first quest.
		var first: Dictionary = TownData.residents(id)[0]
		assert_str(String(first["role"])).override_failure_message(id).is_equal(String(AUTHORITY.get(arch, "reeve")))
		var q1 := QuestDef.load_json(String((doc["quests"] as Array)[0]))
		assert_str(q1.giver_npc()).is_equal(String(first["id"]))
		var fits := false
		for r: String in ARCH_ROLES[arch]:
			fits = fits or jobs.has(r)
		assert_bool(fits).override_failure_message("%s (%s) has no role of its identity: %s" % [id, arch, str(jobs.keys())]).is_true()
	# The identity shows in the roles: Redwater's dyers and weavers, Millbrook's farmers and miller, Stonehollow's masons, Saltwick's salters.
	for pair: Array in [["redwater", ["dyer", "weaver"]], ["millbrook", ["farmer", "miller", "baker"]], ["stonehollow", ["quarryman", "mason"]],
			["saltwick", ["fisher", "net mender", "salter"]], ["skarholm", ["miner", "smelter", "collier"]], ["westfen", ["herbwife", "reed-cutter"]],
			["amberley", ["beekeeper", "chandler"]], ["emberfall", ["glasswright", "lamp-maker"]], ["ravenscar", ["raven keeper", "go-between"]]]:
		var roles := {}
		for e: Dictionary in TownData.residents(String(pair[0])):
			roles[String(e["role"])] = true
		for r: String in pair[1]:
			assert_bool(roles.has(r)).override_failure_message("%s has no %s" % [pair[0], r]).is_true()


func test_every_archetype_is_present_and_the_roles_are_not_a_copy_of_each_other() -> void:
	var archs := {}
	var role_sets := {}
	for id: String in TownData.ids():
		archs[String((TownData.town(id)["identity"] as Dictionary)["arch"])] = true
		var roles: Array = []
		for e: Dictionary in TownData.residents(id):
			if not roles.has(String(e["role"])):
				roles.append(String(e["role"]))
		roles.sort()
		role_sets[",".join(roles)] = id
	assert_int(archs.size()).is_equal(12)
	assert_int(role_sets.size()).override_failure_message("two towns share an identical set of roles").is_greater_equal(26)


func test_kingsreach_keeps_the_castle_the_court_and_the_steward_to_itself() -> void:
	var roles := {}
	for e: Dictionary in TownData.residents("kingsreach"):
		roles[String(e["role"])] = true
		for banned: String in ["steward", "lord", "lady", "king", "queen", "prince", "herald"]:
			assert_bool(String(e["role"]).contains(banned) or String(e["name"]).contains("Corwin")).override_failure_message("%s clashes with the keep: %s" % [e["name"], e["role"]]).is_false()
	for court: String in ["chamberlain", "tourney marshal", "household knight", "court scribe", "falconer", "master of horse", "courtier", "royal cook", "treasury clerk"]:
		assert_bool(roles.has(court)).override_failure_message("the court lacks a " + court).is_true()
	var s := TownPlaces.settlement("kingsreach")
	var keep := Vector2.INF
	for lm: Dictionary in s["plan"]["landmarks"]:
		if String(lm["asset"]) == "castle":
			keep = lm["pos"]
	assert_vector(keep).is_not_equal(Vector2.INF)
	# The court works at the keep gate: a door next to the castle that the planner drew, not a lot the kit converted.
	var gate := TownLots.door_pos("kingsreach_keep")
	assert_vector(gate).is_not_equal(Vector2.INF)
	assert_float(gate.distance_to(keep)).is_between(12.0, 19.0)
	for lot: Dictionary in s["plan"]["lots"]:
		if String(lot.get("role", "")) == "courthouse":
			assert_str(String(lot.get("btype", ""))).override_failure_message("the courthouse lot was taken by the kit").is_empty()
	for e: Dictionary in TownData.residents("kingsreach"):
		if ["chamberlain", "court scribe", "courtier", "royal cook", "treasury clerk", "household knight"].has(String(e["role"])):
			assert_str(String(e["work"])).is_equal("kingsreach_keep")


func test_dialogue_is_varied_inside_each_town() -> void:
	for id: String in _generated():
		var greetings: Array = []
		var rumours: Array = []
		var times := 0
		for e: Dictionary in TownData.residents(id):
			greetings.append_array(e["dialogue"]["greeting"])
			rumours.append_array(e["dialogue"]["rumour"])
			times += (e["dialogue"].get("time", {}) as Dictionary).size()
		assert_float(float(_unique(greetings)) / float(greetings.size())).override_failure_message(id + " greetings repeat").is_greater_equal(0.9)
		assert_float(float(_unique(rumours)) / float(rumours.size())).override_failure_message(id + " rumours repeat").is_greater_equal(0.8)
		assert_int(times).override_failure_message(id + " has no time of day remarks").is_greater(3)
	# Towns differ: an innkeeper of a mining town and of a fishing town do not say the same things.
	var a := String(_resident_of("stonehollow", "innkeeper")["dialogue"]["rumour"][0])
	var b := String(_resident_of("saltwick", "innkeeper")["dialogue"]["rumour"][0])
	assert_str(a).is_not_equal(b)
	# A line about this very town: its landmark is named.
	var named := 0
	for e: Dictionary in TownData.residents("saltwick"):
		for r: String in (e["dialogue"]["greeting"] as Array) + (e["dialogue"]["rumour"] as Array):
			if r.contains("Saltwick Salt Works"):
				named += 1
	assert_int(named).is_greater(0)


func _unique(a: Array) -> int:
	var seen := {}
	for x: Variant in a:
		seen[x] = true
	return seen.size()


func _resident_of(id: String, role: String) -> Dictionary:
	for e: Dictionary in TownData.residents(id):
		if String(e["role"]) == role:
			return e
	return {}


func test_threats_fit_the_places() -> void:
	var seen := {}
	for id: String in TownData.ids():
		var doc := TownData.town(id)
		var ident: Dictionary = doc["identity"]
		var sp := String((doc["threat"] as Dictionary)["species"])
		seen[sp] = true
		var hint: Array = ident.get("hint", [])
		var terrain: Array = ident.get("terrain", [])
		var kits: Array = ident.get("kits", [])
		var arch := String(ident["arch"])
		var wet := hint.has("mere") or hint.has("marsh") or hint.has("coast")
		match sp:
			"bog_toad":
				assert_bool(arch == "fishing" or wet).override_failure_message(id + ": toads away from water").is_true()
			"giant_wasp":
				assert_bool(kits.has("bees") or kits.has("candles") or terrain.has("crater") or (arch == "craft" and hint.has("river"))).override_failure_message(id + ": wasps with no hives or warmth").is_true()
			"ghoul":
				assert_bool(arch == "mining" and (terrain.has("moor") or terrain.has("hill"))).override_failure_message(id + ": ghouls above ground").is_true()
			"wolf":
				assert_bool(arch != "fishing" and not (wet and arch != "hunting" and arch != "fortress")).override_failure_message(id + ": wolves in the marsh").is_true()
		# Frontier towns see more night probes than a walled capital.
		var th: Dictionary = doc["threat"]
		if String(doc["kind"]) == "frontier_town":
			assert_int(int(th["probe_chance"])).is_greater_equal(60)
		if arch == "royal":
			assert_int(int(th["probe_chance"])).is_less_equal(30)
	for need: String in ["wolf", "bog_toad", "ghoul", "giant_wasp"]:
		assert_bool(seen.has(need)).override_failure_message("no town has a " + need + " threat").is_true()


func test_every_bindable_resident_has_a_dialogue_file_in_the_runner_format() -> void:
	for id: String in TownData.ids():
		var dir := String(TownData.town(id).get("dialogue_dir", id))
		for e: Dictionary in TownData.residents(id):
			if not bool(e.get("bind", true)) and not bool(e.get("station", false)):
				continue
			var d := DialogueRunner.load_file(dir + "/" + String(e["id"]))
			assert_bool(d.is_empty()).override_failure_message(String(e["id"])).is_false()
			var start := DialogueRunner.start_node(d)
			assert_bool(DialogueRunner.node_exists(d, start) and DialogueRunner.node_exists(d, "rumour")).is_true()
			var ctx := {"tier": "stranger", "time": "morning", "child": false, "first": "X", "name": "X"}
			var line := DialogueRunner.pick_line(d, start, ctx, RandomNumberGenerator.new())
			assert_str(String(line.get("text", ""))).override_failure_message(String(e["id"])).is_not_empty()
			assert_bool(DialogueRunner.choices(d, start, ctx).size() >= 2).is_true()


## `gen_town.py --all --check` exits 0 when every file on disk (town, quests, dialogue) is exactly what the generator makes now (and
## nothing stale is left behind). Skipped quietly when python3 is not installed.
func test_the_generator_reproduces_every_generated_file() -> void:
	var out: Array = []
	var code := OS.execute("python3", [ProjectSettings.globalize_path("res://tools/towns/gen_town.py"), "--all", "--check"], out, true)
	if code == -1:
		push_warning("python3 not available: generator check skipped")
		return
	assert_int(code).override_failure_message("gen_town.py --all --check: " + "\n".join(out)).is_equal(0)
	# the dry run builds every settlement, Thornfield included, and the sanity pass of the generator agrees with the engine's validator
	var dry: Array = []
	assert_int(OS.execute("python3", [ProjectSettings.globalize_path("res://tools/towns/gen_town.py"), "--all", "--dry-run"], dry, true)).is_equal(0)
	assert_int(String("\n".join(dry)).count("\n")).is_greater_equal(29)


# ---------------------------------------------------------------- the rosters bind
func test_every_roster_binds_to_distinct_worldsim_people_in_its_town() -> void:
	TownRoster.bind_all(true)
	var seen := {}
	for id: String in TownData.ids():
		var rows := TownRoster.rows_of(id)
		var sid := TownRoster.settlement_id(id)
		var r: Vector2i = WorldSim.ranges[sid]
		var want := 0
		for e: Dictionary in TownData.residents(id):
			if not bool(e.get("bind", true)):
				continue
			want += 1
			var rid := String(e["id"])
			assert_bool(rows.has(rid)).override_failure_message("%s/%s did not bind" % [id, rid]).is_true()
			var row := int(rows[rid])
			assert_bool(row >= r.x and row < r.y).override_failure_message("%s row %d outside %s" % [rid, row, r]).is_true()
			assert_bool(seen.has(row)).override_failure_message("row shared: " + rid).is_false()
			seen[row] = true
			assert_str(WorldSim.person_name(row)).is_equal(String(e["name"]))
			assert_int(int(WorldSim.job[row])).is_equal(int(e["job"]))
			assert_str(TownRoster.id_of(row)).is_equal(rid)
			assert_str(TownRoster.town_of(rid)).is_equal(id)
			assert_float(TownRoster.embody_weight(row)).is_less(1.0)
			if bool(e.get("child", false)):
				assert_bool(preload("res://scripts/population/npc_world.gd").is_child(row)).override_failure_message(rid).is_true()
		assert_int(rows.size()).override_failure_message(id + " bound count").is_equal(want)
	# Everyone else is still an ordinary generated name.
	var plain := WorldSim.ranges[TownRoster.settlement_id("millbrook")].x
	for i in range(plain, plain + 60):
		if not TownRoster.is_named(i):
			assert_str(TownRoster.name_of(i)).is_empty()
			assert_float(TownRoster.embody_weight(i)).is_equal(1.0)


func test_named_people_walk_to_their_own_doors_and_keep_their_schedules() -> void:
	TownRoster.bind_all(true)
	for id: String in _generated():
		for e: Dictionary in TownData.residents(id):
			var row := TownRoster.row_of(String(e["id"]))
			assert_int(row).is_greater_equal(0)
			for which in [0, 1]:
				var bid := String(e["home" if which == 0 else "work"])
				var door := TownLots.door_pos(bid)
				assert_bool(door != Vector2.INF).override_failure_message("%s: %s has no door in the world" % [e["id"], bid]).is_true()
				# a lot's door is a doorstep; a work site's door or the keep gate is a yard shared by ten people
				var limit := 1.2 if not TownLots.building(bid).is_empty() else 3.6
				assert_float(TownRoster.spot(row, which).distance_to(door)).override_failure_message("%s %s" % [e["id"], bid]).is_less(limit)
			assert_vector(TownRoster.spot(row, 2)).is_equal(Vector2.INF)
			# A schedule override applies in its window and the baseline outside every window.
			var s0: Dictionary = (e["schedule"] as Array)[0]
			var inside := (float(s0["from"]) + float(s0["to"])) * 0.5 if float(s0["from"]) <= float(s0["to"]) else float(s0["from"]) + 0.25
			var want: int = preload("res://scripts/population/schedule.gd").NAMES.find(String(s0["phase"]))
			assert_int(TownRoster.override_phase(row, inside, 99)).is_equal(want)


func test_people_who_work_at_a_yard_or_the_keep_gate_are_not_hidden_indoors() -> void:
	TownRoster.bind_all(true)
	var checked := 0
	var indoors_shop := 0
	for id: String in ["kingsreach", "stonehollow", "harrowgate"]:
		for e: Dictionary in TownData.residents(id):
			var row := TownRoster.row_of(String(e["id"]))
			if not [1, 2].has(int(e["job"])):
				continue
			var yard := TownLots.building(String(e["work"])).is_empty()
			WorldSim.job[row] = int(e["job"])
			WorldSim.phase[row] = 1
			WorldSim.pos[row] = WorldSim.target[row]
			# WorldSim keeps 3 in 4 craftsmen inside a building they work in (by row); a yard has no inside
			if yard:
				assert_bool(TownRoster.outdoor_work(row)).override_failure_message(String(e["id"])).is_true()
				assert_bool(WorldSim.is_indoors(row)).override_failure_message("%s works at %s but is hidden indoors" % [e["id"], e["work"]]).is_false()
				checked += 1
			elif row % 4 != 0:
				assert_bool(WorldSim.is_indoors(row)).override_failure_message(String(e["id"])).is_true()
				indoors_shop += 1
	assert_int(checked).is_greater(5)
	assert_int(indoors_shop).is_greater(0)
	WorldSim.reset()


func test_the_authority_holds_audience_in_the_market_at_midday() -> void:
	for id: String in _generated():
		var first: Dictionary = TownData.residents(id)[0]
		var at_noon := ""
		for sp: Dictionary in first["schedule"]:
			if 12.0 >= float(sp["from"]) and 12.0 < float(sp["to"]):
				at_noon = String(sp["phase"])
		assert_str(at_noon).override_failure_message(id + ": the giver of the first quest is indoors at noon").is_equal("market")


func test_the_roster_seeds_warm_ties_into_the_social_graph() -> void:
	TownRoster.bind_all(true)
	for id: String in _generated():
		var graph := preload("res://scripts/sim/npc_social_graph.gd").new()
		var n := TownRoster.seed_social_graph(graph, WorldSim.SEED, id)
		assert_int(n).override_failure_message(id).is_greater(2)
		assert_int(TownRoster.seed_social_graph(graph, WorldSim.SEED, id)).is_equal(0)       # idempotent


func test_a_killed_resident_is_announced_on_the_quest_bus() -> void:
	TownRoster.bind_all(true)
	var events: Array = []
	var cb := func(t: StringName, d: Dictionary) -> void: events.append([String(t), d])
	QuestBus.shared().fired.connect(cb)
	var rid := String(TownData.residents("redwater")[3]["id"])
	WorldSim.kill_person(TownRoster.row_of(rid))
	QuestBus.shared().fired.disconnect(cb)
	assert_bool(events.any(func(e: Array) -> bool: return e[0] == "died" and String(e[1].get("actor", "")) == rid)).is_true()
	WorldSim.reset()


func test_the_talk_system_knows_them_by_their_roster_ids() -> void:
	TownRoster.bind_all(true)
	var sv := VillageServices.new()
	auto_free(sv)
	for id: String in _generated():
		var e: Dictionary = TownData.residents(id)[2]
		var row := TownRoster.row_of(String(e["id"]))
		var info: Dictionary = sv._npc_info({"id": "p%d" % row, "person": row})
		assert_str(String(info["id"])).is_equal(String(e["id"]))
		assert_str(String(info["name"])).is_equal(String(e["name"]))
		assert_str(String(info["file"])).is_equal("%s/%s" % [id, e["id"]])
		assert_str(String(info["role"])).is_equal(String(e["role"]))
	# The giver offers the first quest of the line through the ordinary talk options, in every town.
	for id: String in _generated():
		var giver: Dictionary = TownData.residents(id)[0]
		var opts: Array = []
		Talk.add_options(opts, {"id": String(giver["id"]), "name": String(giver["name"])})
		assert_int(opts.size()).override_failure_message(id + ": " + String(giver["name"])).is_equal(1)
		assert_str(String(opts[0][0])).contains("Ask about work")


# ---------------------------------------------------------------- the lots
func test_every_town_has_the_lots_its_file_requires() -> void:
	for id: String in TownData.ids():
		var s := TownPlaces.settlement(id)
		assert_bool((s["plan"] as Dictionary).has("slice")).override_failure_message(id + " has no forced lots").is_true()
		var kind := String(TownData.town(id)["kind"])
		var types := TownLots.required_types(id)
		for t: String in ["tavern", "smithy", "general_shop"]:
			assert_bool(types.has(t)).override_failure_message("%s lacks a %s in its file" % [id, t]).is_true()
		if kind != "village":
			for t: String in ["bakery", "healer", "guard_post"]:
				assert_bool(types.has(t)).override_failure_message("%s (%s) lacks a %s in its file" % [id, kind, t]).is_true()
		for t: String in types:
			assert_array(TownLots.lots_of_type(id, t)).override_failure_message("%s: no %s lot" % [id, t]).is_not_empty()
		var reg: Dictionary = s["plan"]["slice"]["buildings"]
		for bid: String in reg:
			var b: Dictionary = reg[bid]
			var lot: Dictionary = s["plan"]["lots"][int(b["lot"])]
			assert_str(String(lot["bid"])).is_equal(bid)
			assert_str(String(lot["btype"])).is_equal(String(b["type"]))
			assert_vector(Vector2(b["door"])).is_not_equal(Vector2.INF)
			assert_str(TownLots.tid_of_bid(bid)).is_equal(id)
		assert_str(String(reg[id + "_smithy"]["asset"])).is_equal("blacksmith")
		assert_str(String(reg[id + "_inn"]["asset"])).is_equal("inn")
		assert_int(TownLots.lots_of_type(id, "house").size()).is_greater_equal(1)
		# Every home and workplace the roster names exists as a lot or a door.
		for e: Dictionary in TownData.residents(id):
			for key: String in ["home", "work"]:
				if (TownData.town(id).get("default_spots", []) as Array).has(String(e[key])):
					continue          # a deliberate "use the settlement's shared spot" (Thornfield's temple)
				assert_bool(TownLots.door_pos(String(e[key])) != Vector2.INF).override_failure_message("%s %s %s" % [e["id"], key, e[key]]).is_true()


func test_the_lots_are_forced_for_any_seed() -> void:
	for id: String in ["millbrook", "redwater", "kingsreach", "saltwick", "skarholm", "emberfall"]:
		var s := TownPlaces.settlement(id)
		for seed_value: int in [1, 77]:
			var plan := CityPlanner.plan(s, WorldGen.gate_angles(s), seed_value)
			for t: String in TownLots.required_types(id):
				var found := false
				for lot: Dictionary in plan["lots"]:
					if String(lot.get("btype", "")) == t:
						found = true
				assert_bool(found).override_failure_message("%s seed %d has no %s" % [id, seed_value, t]).is_true()


func test_a_settlement_without_a_town_file_is_left_alone() -> void:
	# Every real settlement has a file now: a made-up one must come out of the planner untouched.
	var fake: Dictionary = (TownPlaces.settlement("millbrook") as Dictionary).duplicate()
	fake["name"] = "Nowhere-on-Sea"
	assert_bool(TownLots.is_kit_town(fake)).is_false()
	var plan := CityPlanner.plan(fake, WorldGen.gate_angles(fake), 1)
	assert_bool((plan as Dictionary).has("slice")).is_false()
	for lot: Dictionary in plan["lots"]:
		assert_bool(lot.has("bid")).is_false()


func test_the_keepers_run_their_buildings() -> void:
	TownRoster.bind_all(true)
	for id: String in _generated():
		for t: String in TownLots.required_types(id):
			if t == "guard_post":
				continue
			var bid: String = TownLots.lots_of_type(id, t)[0]
			var keeper := TownRoster.keeper_of(bid)
			assert_bool(keeper.is_empty()).override_failure_message("%s has no keeper" % bid).is_false()
			assert_str(String(keeper["work"])).is_equal(bid)
			assert_str(TownRoster.look_of(keeper)).is_not_empty()
			if t != "tavern" and t != "healer":
				assert_str(TownRoster.building_name(bid)).contains(String(keeper["name"]).get_slice(" ", 1))


func test_places_resolve_in_the_world() -> void:
	for id: String in TownData.ids():
		var doc := TownData.town(id)
		var places := TownPlaces.places(id)
		for p: Dictionary in doc["places"]:
			assert_bool(places.has(String(p["id"]))).override_failure_message("%s place %s" % [id, p["id"]]).is_true()
		for k: String in (doc.get("doors", {}) as Dictionary):
			assert_bool(TownPlaces.door_of_site(id, k) != Vector2.INF).override_failure_message(k).is_true()
		assert_vector(places[id]["pos"]).is_equal(TownPlaces.settlement(id)["pos"])
	# A dry-nudged place is on dry ground.
	for id: String in _generated():
		var p := TownPlaces.place_pos(id, id + "_outskirts")
		assert_bool(WorldGen.near_water(p.x, p.y, 4.0)).override_failure_message(id + " outskirts are wet").is_false()


# ---------------------------------------------------------------- threat and livestock
func test_each_town_has_a_den_near_it_and_its_threat_creatures_can_spawn() -> void:
	for id: String in TownData.ids():
		var cfg: Dictionary = TownData.town(id)["threat"]
		assert_bool(TownThreat.SPECIES.has(String(cfg["species"]))).override_failure_message(id).is_true()
		var th := TownThreat.new()
		th.configure(id)
		add_child(auto_free(th))
		var den_id: int = th.ensure_den()
		assert_int(den_id).override_failure_message(id + " has no den").is_greater_equal(0)
		var den: Dictionary = Frontier.ecology.dens[den_id]
		assert_str(String(den["species"])).is_equal(String(cfg["species"]))
		assert_float((den["pos"] as Vector2).distance_to(TownPlaces.settlement(id)["pos"])).is_less_equal(float(cfg["den_ring"][1]) + 0.01)
		var target := TownPlaces.place_pos(id, String(cfg["probe_place"]))
		assert_vector(target).is_not_equal(Vector2.INF)
		var pack: Array = th.probe(target, 1)
		assert_int(pack.size()).is_equal(1)
		assert_str(String((pack[0] as Node).get("species"))).is_equal(String(cfg["species"]))
		assert_bool((pack[0] as Node).is_in_group(String(cfg["group"]))).is_true()


func test_generated_towns_stock_their_farms_with_real_animals() -> void:
	var kinds_found := 0
	for id: String in TownData.ids():
		for g: Dictionary in TownLivestock.groups(id):
			for k: Array in g["kinds"]:
				kinds_found += 1
				assert_bool(preload("res://scripts/actors/critter.gd").KINDS.has(String(k[0]))).override_failure_message(String(k[0])).is_true()
	assert_int(kinds_found).is_greater(30)


func test_farming_and_village_archetypes_have_settlement_relative_pens() -> void:
	var with_pens := 0
	var built := 0
	for id: String in _generated():
		var doc := TownData.town(id)
		var arch := String((doc["identity"] as Dictionary)["arch"])
		var lv: Dictionary = doc.get("livestock", {})
		var pens: Array = lv.get("pens", [])
		if ["farming", "pastoral", "religious"].has(arch):
			assert_array(pens).override_failure_message(id + " (" + arch + ") has no pens").is_not_empty()
		for p: Dictionary in pens:
			assert_str(String((doc["anchors"] as Dictionary)[String(p["anchor"])]["kind"])).is_equal("settlement")      # no site anchor needed
			# the pen stands around one of the town's livestock groups
			var near := false
			for g: Dictionary in lv["groups"]:
				if (g["at"] as Array) == (p["at"] as Array):
					near = true
			assert_bool(near).override_failure_message(id + ": a pen with no animals in it").is_true()
		if not pens.is_empty():
			with_pens += 1
			var root: Node3D = TownLivestock.build_pens(id, self)
			auto_free(root)
			if root.get_child_count() > 0:
				built += 1
				var mm: MultiMesh = (root.get_child(0) as MultiMeshInstance3D).multimesh
				assert_int(mm.instance_count).override_failure_message(id).is_greater(8)
			else:
				# a pen is only skipped on wet ground
				for p: Dictionary in pens:
					var w := TownPlaces.resolve(id, p)
					assert_bool(WorldGen.near_water(w.x, w.y, 3.0)).override_failure_message(id + ": pens missing on dry ground").is_true()
	assert_int(with_pens).is_greater(12)
	assert_int(built).is_greater(8)
	# The rails stand around the animals, wherever the pen faces: every piece within the pen's half-diagonal of its centre (+ a rail).
	for id: String in _generated():
		var pens2: Array = (TownData.town(id).get("livestock", {}) as Dictionary).get("pens", [])
		if pens2.is_empty():
			continue
		var pieces := TownLivestock.pen_transforms(id)
		for piece: Transform3D in pieces:
			var near := false
			for p: Dictionary in pens2:
				var c := TownPlaces.resolve(id, p)
				var half := Vector2(float(p["size"][0]), float(p["size"][1])).length() * 0.5 + 2.0
				if Vector2(piece.origin.x, piece.origin.z).distance_to(c) <= half:
					near = true
			assert_bool(near).override_failure_message("%s: a pen rail stands %s, away from every pen" % [id, str(piece.origin)]).is_true()
	# Millbrook, a farming village: three pens (cows, hens, pigs) on the settlement frame, rails all round.
	var mill: Node3D = TownLivestock.build_pens("millbrook", self)
	auto_free(mill)
	assert_int(mill.get_child_count()).is_equal(1)


# ---------------------------------------------------------------- the hubs
func test_attach_all_makes_one_hub_per_town_file_and_polls_places() -> void:
	var holder := Node3D.new()
	add_child(auto_free(holder))
	var hubs := TownHub.attach_all(holder)
	assert_int(hubs.size()).is_equal(TownData.ids().size())
	var names := []
	for h: Node in hubs:
		names.append(String(h.name))
	assert_bool(names.has("ThornfieldHub")).is_true()
	assert_bool(names.has("TownHub_millbrook") and names.has("TownHub_redwater")).is_true()
	var events: Array = []
	var cb := func(t: StringName, d: Dictionary) -> void: events.append([String(t), d])
	QuestBus.shared().fired.connect(cb)
	var p := TownPlaces.place_pos("millbrook", "millbrook_works")
	_player_at(p)
	for h: Node in hubs:
		h.call("poll", 0.5)
	QuestBus.shared().fired.disconnect(cb)
	var entered := events.filter(func(e: Array) -> bool: return e[0] == "enter_area" and String(e[1]["place"]) == "millbrook_works")
	assert_int(entered.size()).is_equal(1)         # one hub reports it, not three


func test_a_kill_is_reported_once_as_died_and_per_town_as_kill() -> void:
	var holder := Node3D.new()
	add_child(auto_free(holder))
	TownHub.attach_all(holder)
	var events: Array = []
	var cb := func(t: StringName, d: Dictionary) -> void: events.append([String(t), d])
	QuestBus.shared().fired.connect(cb)
	var at := TownPlaces.place_pos("millbrook", "millbrook_outskirts")
	Life.region1_kill.emit("wolf", Vector3(at.x, 0.0, at.y))
	QuestBus.shared().fired.disconnect(cb)
	assert_int(events.filter(func(e: Array) -> bool: return e[0] == "died" and String(e[1].get("actor", "")) == "wolf").size()).is_equal(1)
	var kills := events.filter(func(e: Array) -> bool: return e[0] == "kill" and String(e[1]["place"]) == "millbrook_outskirts")
	assert_int(kills.size()).is_equal(1)           # one `kill` per place the kill happened near, whichever hub is asked
	assert_str(String(kills[0][1]["target"])).is_equal("wolf")
	assert_int(events.filter(func(e: Array) -> bool: return e[0] == "kill" and String(e[1]["place"]).begins_with("thornfield")).size()).is_equal(0)


# ---------------------------------------------------------------- the quest lines
func test_each_generated_quest_line_is_valid_and_chained() -> void:
	var objective_types := {}
	var titles := {}
	var total := 0
	var split_givers := 0
	var signatures := {}
	for id: String in _generated():
		var r := QuestHub.runner()
		var paths: Array = TownData.town(id)["quests"]
		assert_int(paths.size()).is_equal(3)
		var prev := ""
		var givers := {}
		for path: String in paths:
			var d := QuestDef.load_json(path)
			assert_bool(d != null).override_failure_message(path).is_true()
			assert_array(Array(d.validate())).override_failure_message("%s: %s" % [path, "; ".join(d.validate())]).is_empty()
			assert_bool(r.def(d.id) != null).override_failure_message(d.id + " not loaded by QuestHub").is_true()
			if prev != "":
				assert_array(d.requires()).contains([prev])
			prev = d.id
			assert_str(d.giver_npc()).is_not_empty()
			assert_bool(not TownRoster.entry(d.giver_npc()).is_empty()).is_true()
			givers[d.giver_npc()] = true
			titles[d.title] = true
			total += 1
			var sig: Array = []
			for st: Dictionary in d.stages:
				var types: Array = []
				for o: Dictionary in st["objectives"]:
					types.append(String(o["type"]))
				sig.append("+".join(types))
			signatures["|".join(sig)] = true
			for t: String in d.objective_types():
				objective_types[t] = true
		if givers.size() > 1:
			split_givers += 1
	for t: String in ["talk_to", "goto", "kill", "collect", "deliver", "investigate", "choose"]:
		assert_bool(objective_types.has(t)).override_failure_message("no quest uses " + t).is_true()
	# Not copies of each other with the names swapped: many titles, many shapes, more than one giver per town.
	assert_float(float(titles.size()) / float(total)).override_failure_message("quest titles repeat: %d of %d" % [titles.size(), total]).is_greater_equal(0.8)
	assert_int(signatures.size()).override_failure_message("quest shapes: %d" % signatures.size()).is_greater_equal(15)
	assert_int(split_givers).is_greater(17)


func test_quest_templates_vary_by_archetype_and_between_towns_of_one_archetype() -> void:
	var by_arch := {}
	var all := {}
	for id: String in _generated():
		var ident: Dictionary = TownData.town(id)["identity"]
		var key := ",".join(ident["quest_templates"])
		all[key] = true
		var arch := String(ident["arch"])
		if not by_arch.has(arch):
			by_arch[arch] = {}
		assert_bool((by_arch[arch] as Dictionary).has(key)).override_failure_message("%s repeats the quest line of a %s town: %s" % [id, arch, key]).is_false()
		by_arch[arch][key] = id
	assert_int(all.size()).is_greater_equal(_generated().size() - 4)
	var used := {}
	for key: String in all:
		for t: String in key.split(","):
			used[t] = true
	for t: String in ["haul", "order", "two", "carry", "table", "theft", "witness", "sabotage", "contraband", "taint", "edge", "tracks", "intel", "waves", "bait"]:
		assert_bool(used.has(t)).override_failure_message("no town uses the " + t + " template").is_true()


## Every town's three-quest line is played to its end through the hub: alternate towns take the other branch of the mystery.
func test_every_generated_quest_line_completes_through_the_kit() -> void:
	var k := 0
	for id: String in _generated():
		QuestHub.reset()
		QuestBus.reset_shared()
		_clear_pack()
		var hub: Node = TownHub.attach(self, id)
		var endings := _play_line(hub, id, k % 2)
		hub.get_parent().remove_child(hub)
		hub.free()
		for e: Array in endings:
			assert_str(String(QuestHub.peek().run(String(e[0])).ending)).override_failure_message("%s: %s ended '%s'" % [id, e[0], QuestHub.peek().run(String(e[0])).ending]).is_equal(String(e[1]))
		k += 1
	assert_int(k).is_equal(29)


func test_the_millbrook_and_redwater_lines_complete_with_either_branch() -> void:
	for pair: Array in [["millbrook", 0], ["redwater", 1], ["kingsreach", 1], ["saltwick", 0]]:
		QuestHub.reset()
		QuestBus.reset_shared()
		_clear_pack()
		var hub: Node = TownHub.attach(self, String(pair[0]))
		_play_line(hub, String(pair[0]), int(pair[1]))
		hub.get_parent().remove_child(hub)
		hub.free()


func test_a_stash_only_pays_out_once_and_only_on_its_stage() -> void:
	var hub: Node = auto_free(TownHub.attach(self, "ashford"))
	var r := QuestHub.runner()
	var stash: Node = hub.get("stashes")[0]
	var sd: Dictionary = stash.get_meta("stash")
	var qid := String(sd["quest"])
	assert_bool(TownClues.available(stash)).is_false()
	assert_str(TownClues.take(stash)).is_empty()
	assert_str(r.start(qid)).is_empty()
	assert_bool(TownClues.available(stash)).is_true()
	assert_str(TownClues.take(stash)).is_equal("ok")
	assert_bool(TownClues.available(stash)).is_false()
	assert_int(Life.count(String(sd["item"]))).is_equal(int(sd["count"]))


## Starts every quest of the town's line in order and plays each to its end the way the game would: places by the stand-in
## player and the hub poll, goods from the kit's stash, hand-overs and choices through the talk helpers, clues by Examine, kills by
## Life.region1_kill. `pick` is the index of the Choose option to take in the mystery (0 the honest one). Returns [[quest id, the end
## stage that option leads to]] for the quests that have a Choose.
func _play_line(hub: Node, id: String, pick: int) -> Array:
	var player := _player_at(TownPlaces.settlement(id)["pos"])
	var r := QuestHub.runner()
	var endings: Array = []
	for path: String in TownData.town(id)["quests"]:
		var d := QuestDef.load_json(path)
		assert_str(r.start(d.id)).override_failure_message(d.id).is_empty()
		var guard := 0
		while r.is_active(d.id) and guard < 40:
			guard += 1
			var open: Array = r.objectives_of(d.id).filter(func(o: RefCounted) -> bool: return not o.is_done())
			assert_bool(open.is_empty()).is_false()
			_do(hub, player, id, d.id, open[0], pick)
		assert_bool(r.is_done(d.id)).override_failure_message("%s did not complete (stage %s)" % [d.id, r.stage_of(d.id)]).is_true()
		assert_str(r.run(d.id).paid).override_failure_message(d.id + " paid nothing").is_not_empty()
		for st: Dictionary in d.stages:
			for o: Dictionary in st["objectives"]:
				if String(o["type"]) == "choose":
					var oid := String((o["options"] as Array)[pick]["id"])
					endings.append([d.id, String((st["branches"] as Dictionary)[oid])])
	# Every quest of the line is finished.
	for path: String in TownData.town(id)["quests"]:
		assert_bool(r.is_done(String(QuestDef.load_json(path).id))).is_true()
	player.get_parent().remove_child(player)
	player.free()
	return endings


func _do(hub: Node, player: Node3D, id: String, qid: String, o: RefCounted, pick: int) -> void:
	var r := QuestHub.runner()
	var data: Dictionary = o.data
	match String(o.type):
		"goto":
			var pos := TownPlaces.place_pos(id, String(data["place"]))
			assert_vector(pos).override_failure_message(String(data["place"])).is_not_equal(Vector2.INF)
			player.global_position = Vector3(pos.x, 0.0, pos.y)
			hub.call("poll", 2.5)
		"collect":
			var done := false
			for stash: Node in hub.get("stashes"):
				var sd: Dictionary = stash.get_meta("stash")
				if String(sd["item"]) == String(data["item"]) and String(sd["quest"]) == qid and TownClues.available(stash):
					assert_str(TownClues.take(stash)).is_equal("ok")
					done = true
					break
			assert_bool(done).override_failure_message("no stash for " + String(data["item"])).is_true()
			hub.call("poll", 0.5)
		"deliver":
			var info := TownRoster.info_for_id(String(data["to"]))
			assert_bool(info.is_empty()).is_false()
			var opts: Array = []
			TownTalk.add_options(opts, info)
			assert_int(opts.size()).is_equal(1)                              # "Hand over N item": the talk menu offers it
			assert_str(TownTalk.hand_over(info, String(data["item"]), int(o.need()))).contains("hand over")
		"investigate":
			var wanted: Array = data["clues"]
			var examined := 0
			for clue: Node in hub.get("clues"):
				if wanted.has(String(clue.get("clue_id"))) and examined < int(o.need()):
					clue.call("examine")
					examined += 1
			assert_int(examined).is_equal(int(o.need()))
		"talk_to":
			var info2 := TownRoster.info_for_id(String(data["npc"]))
			TownTalk.on_node(info2, "greet")                                 # the talk menu entering a node
		"choose":
			var opts2 := Talk.options_for(r, String(data["npc"]))
			var picked := false
			var want_label := String((data["options"] as Array)[pick]["text"])
			for op: Array in opts2:
				if String(op[0]) == want_label:
					(op[1] as Callable).call()
					picked = true
					break
			assert_bool(picked).override_failure_message("no '%s' option offered (%s)" % [want_label, str(opts2.map(func(x: Array) -> String: return String(x[0])))]).is_true()
		"kill":
			var pos2 := TownPlaces.place_pos(id, String(data["place"]))
			for k in int(o.need()):
				Life.region1_kill.emit(String(data["target"]), Vector3(pos2.x, 0.0, pos2.y))
		_:
			assert_bool(false).override_failure_message("objective type %s is not wired by the kit" % o.type).is_true()
