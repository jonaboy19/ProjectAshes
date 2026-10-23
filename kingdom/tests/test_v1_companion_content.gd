extends GdUnitTestSuite
## Ready v1, C7: three named companions (Brannoc Tallow, Sister Oriel Vane, Hesk Ironbrow) as data. Each has a bio,
## recruit dialogue and a 3-step personal quest (data/quests/companions, dialogue/companions). The quests finish
## through QuestRunner on every branch, the dialogue is sound for the runner, and courtship is offered to
## male-female pairs only (OWNER_DECISIONS 2026-09-29).

const Talk := preload("res://scripts/quests/quest_talk.gd")
const Runner := preload("res://scripts/sim/dialogue_runner.gd")
const DIR := "res://data/quests/companions"
const REGISTRY := "res://data/region1/quests/r1_registry.json"

## id -> {sex, quest, branches: {option: [final-stage events]}}
const COMPANIONS := {
	"brannoc_tallow": {"sex": "male", "quest": "companion_ashes_of_the_hand"},
	"oriel_vane": {"sex": "female", "quest": "companion_a_relic_unburned"},
	"hesk_ironbrow": {"sex": "male", "quest": "companion_the_unfinished_arch"},
}

var paid: Array = []


func before_test() -> void:
	paid.clear()
	Runner.clear_cache()


func _runner() -> QuestRunner:
	var r := QuestRunner.new(QuestBus.new())
	r.awards_xp = false
	r.reward_fn = func(rw: Dictionary) -> String:
		paid.append(rw)
		return "paid"
	assert_int(r.load_dir(DIR)).is_equal(3)
	return r


func _flags_paid() -> Array:
	var out: Array = []
	for rw: Dictionary in paid:
		out.append_array(rw.get("flags", []))
	return out


func _choose(r: QuestRunner, npc: String, option_text: String) -> void:
	for o: Array in Talk.options_for(r, npc):
		if String(o[0]) == option_text:
			(o[1] as Callable).call()
			return
	fail("no option '%s' offered by %s" % [option_text, npc])


# --- the quests -------------------------------------------------------------------------

func test_each_companion_has_one_sound_three_step_quest() -> void:
	var r := _runner()
	for cid: String in COMPANIONS:
		var d: QuestDef = r.def(COMPANIONS[cid]["quest"])
		assert_object(d).override_failure_message(cid).is_not_null()
		assert_array(d.validate()).override_failure_message(cid).is_empty()
		assert_str(d.giver_npc()).is_equal(cid)
		assert_array(d.rewards().get("flags", [])).contains(["companion.%s.done" % cid])
		# 3 steps on every path: step 1, step 2 (the decision), then one of the two endings.
		assert_int(d.stages.size()).is_equal(4)
		var ends := d.stages.filter(func(s: Dictionary) -> bool: return bool(s.get("end", false)))
		assert_int(ends.size()).is_equal(2)
		assert_int(d.objective_types().size()).is_greater_equal(3)


func test_quests_are_loaded_by_the_game_hub_and_offered_by_their_companion() -> void:
	QuestHub.reset()
	var r := QuestHub.runner()
	for cid: String in COMPANIONS:
		assert_bool(r.defs.has(COMPANIONS[cid]["quest"])).is_true()
		var offers := r.offers_for(cid)
		assert_int(offers.size()).is_equal(1)
		assert_str(Talk.options_for(r, cid)[0][0]).contains(offers[0].title)
	QuestHub.reset()


func test_every_place_named_exists_in_the_region_1_registry() -> void:
	var reg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY))
	var places: Dictionary = reg["places"]
	var r := _runner()
	for cid: String in COMPANIONS:
		var d: QuestDef = r.def(COMPANIONS[cid]["quest"])
		var named: Array = [String(d.data["giver"].get("place", ""))]
		for s: Dictionary in d.stages:
			for o: Dictionary in s["objectives"]:
				if o.has("place"):
					named.append(String(o["place"]))
		for p: Variant in named:
			assert_bool(places.has(String(p))).override_failure_message("%s: unknown place %s" % [cid, p]).is_true()


func test_brannoc_ashes_of_the_hand_finishes_on_both_branches() -> void:
	for branch: String in ["law", "quiet"]:
		paid.clear()
		var r := _runner()
		var q := "companion_ashes_of_the_hand"
		assert_str(r.start(q)).is_empty()
		r.notify(&"enter_area", {"place": "duskbriar_bandit_camp"})
		assert_str(r.stage_of(q)).is_equal("ash")
		for c: String in ["cold_hearth", "ledger_page", "dropped_boot"]:
			r.notify(&"interact", {"id": "duskbriar/ash/" + c})
		_choose(r, "brannoc_tallow", "Hand Mab to Captain Hollis's Guard" if branch == "law" else "Burn the ledger and let Mab run")
		assert_str(r.stage_of(q)).is_equal(branch)
		r.notify(&"talk", {"npc": "bram_hollis" if branch == "law" else "mab_larkin"})
		assert_bool(r.is_done(q)).is_true()
		assert_int(r.run(q).history.size()).is_equal(3)
		var flags := _flags_paid()
		assert_array(flags).contains(["companion.brannoc_tallow.done", "companion.brannoc_tallow.spy_role",
			"companion.brannoc_tallow.path_" + branch])


func test_oriel_a_relic_unburned_finishes_on_both_branches() -> void:
	for branch: String in ["return", "hide"]:
		paid.clear()
		var r := _runner()
		var q := "companion_a_relic_unburned"
		assert_str(r.start(q)).is_empty()
		r.notify(&"talk", {"npc": "lucan"})                  # too early: the road comes first
		assert_str(r.stage_of(q)).is_equal("milestone")
		r.notify(&"enter_area", {"place": "kings_ember_road"})
		r.notify(&"talk", {"npc": "lucan"})
		assert_str(r.stage_of(q)).is_equal("choice")
		_choose(r, "oriel_vane", "Carry the lamp to the Dawn Throne" if branch == "return" else "Set the lamp in an Ashford stone")
		r.notify(&"enter_area", {"place": "kingsreach" if branch == "return" else "ashford_ring"})
		assert_bool(r.is_done(q)).is_true()
		assert_int(r.run(q).history.size()).is_equal(3)
		assert_array(_flags_paid()).contains(["companion.oriel_vane.done", "companion.oriel_vane.healer_role",
			"companion.oriel_vane.path_" + branch])


func test_hesk_the_unfinished_arch_finishes_on_both_branches() -> void:
	for branch: String in ["charter", "durrow"]:
		paid.clear()
		var r := _runner()
		var q := "companion_the_unfinished_arch"
		assert_str(r.start(q)).is_empty()
		r.notify(&"item", {"item": "cut_stone", "amount": 12})   # ignored until he reaches the quarry
		assert_str(r.stage_of(q)).is_equal("quarry")
		r.notify(&"enter_area", {"place": "hollin_cut_stone"})
		r.notify(&"item", {"item": "cut_stone", "amount": 12})
		assert_str(r.stage_of(q)).is_equal("form")
		_choose(r, "hesk_ironbrow", "Set it pointed, in Charter form" if branch == "charter" else "Set it round, the Durrow way")
		r.notify(&"enter_area", {"place": "silverford_guild_hall"})
		assert_bool(r.is_done(q)).is_true()
		assert_int(r.run(q).history.size()).is_equal(3)
		assert_array(_flags_paid()).contains(["companion.hesk_ironbrow.done", "companion.hesk_ironbrow.stone_tier",
			"companion.hesk_ironbrow.path_" + branch])


func test_a_companion_quest_saves_and_restores_mid_way() -> void:
	var r := _runner()
	var q := "companion_the_unfinished_arch"
	r.start(q)
	r.notify(&"enter_area", {"place": "hollin_cut_stone"})
	r.notify(&"item", {"item": "cut_stone", "amount": 5})
	var snap: Dictionary = JSON.parse_string(JSON.stringify(r.serialize()))
	var r2 := _runner()
	r2.deserialize(snap)
	assert_bool(r2.is_active(q)).is_true()
	r2.notify(&"item", {"item": "cut_stone", "amount": 7})
	assert_str(r2.stage_of(q)).is_equal("form")


# --- the dialogue -----------------------------------------------------------------------

func _dialogue(cid: String) -> Dictionary:
	return Runner.load_file(cid, "res://dialogue/companions")


func test_dialogue_is_valid_reachable_and_short() -> void:
	for cid: String in COMPANIONS:
		var d := _dialogue(cid)
		assert_bool(d.is_empty()).override_failure_message(cid).is_false()
		assert_array(Array(Runner.validate(d))).override_failure_message(cid).is_empty()
		var nodes: Dictionary = d["nodes"]
		var seen := {}
		var todo: Array = [Runner.start_node(d)]
		while not todo.is_empty():
			var n: String = todo.pop_back()
			if seen.has(n) or not nodes.has(n):
				continue
			seen[n] = true
			for c: Dictionary in nodes[n].get("choices", []):
				todo.append(String(c.get("goto", "")))
		assert_int(seen.size()).override_failure_message("%s: unreachable nodes" % cid).is_equal(nodes.size())
		for n: String in nodes:
			assert_str(String(nodes[n].get("speaker", ""))).override_failure_message("%s/%s speaker" % [cid, n]).is_equal(cid)
			for l: Dictionary in nodes[n]["lines"]:
				assert_int(String(l["text"]).length()).override_failure_message("%s/%s line" % [cid, n]).is_less_equal(120)
			for c: Dictionary in nodes[n].get("choices", []):
				assert_int(String(c["text"]).length()).override_failure_message("%s/%s choice" % [cid, n]).is_less_equal(40)


func test_each_companion_has_bio_recruit_and_courtship_nodes() -> void:
	for cid: String in COMPANIONS:
		var d := _dialogue(cid)
		for n: String in ["greet", "bio", "bio_2", "bio_3", "recruit", "recruit_yes", "recruit_no", "favour_open", "courtship"]:
			assert_bool(Runner.node_exists(d, n)).override_failure_message("%s lacks %s" % [cid, n]).is_true()
		# Accepting sets the flag the recruitment hook reads.
		var yes: Dictionary = d["nodes"]["recruit_yes"]["choices"][0]
		assert_array(yes["do"]).contains([["flag", "companion.%s.recruit_yes" % cid]])


func test_courtship_is_offered_to_male_female_pairs_only() -> void:
	for cid: String in COMPANIONS:
		var d := _dialogue(cid)
		var mate := "hero.female" if COMPANIONS[cid]["sex"] == "male" else "hero.male"
		var other := "hero.male" if mate == "hero.female" else "hero.female"
		var base := {"companion.%s.done" % cid: true}
		var ctx_ok := {"flags": base.merged({mate: true})}
		var ctx_same := {"flags": base.merged({other: true})}
		var ctx_early := {"flags": {mate: true}}                       # quest not finished
		var ctx_asked := {"flags": base.merged({mate: true, "companion.%s.courting" % cid: true})}
		assert_bool(_offers_courtship(d, ctx_ok)).override_failure_message(cid + " pair").is_true()
		assert_bool(_offers_courtship(d, ctx_same)).override_failure_message(cid + " same sex").is_false()
		assert_bool(_offers_courtship(d, {"flags": base})).override_failure_message(cid + " no hero sex").is_false()
		assert_bool(_offers_courtship(d, ctx_early)).override_failure_message(cid + " before the quest").is_false()
		assert_bool(_offers_courtship(d, ctx_asked)).override_failure_message(cid + " already decided").is_false()
		# The decision itself sets exactly one of two flags.
		var yes: Dictionary = d["nodes"]["court_yes"]["choices"][0]
		var no: Dictionary = d["nodes"]["court_friends"]["choices"][0]
		assert_array(yes["do"]).is_equal([["flag", "companion.%s.courting" % cid]])
		assert_array(no["do"]).is_equal([["flag", "companion.%s.friends_only" % cid]])


func _offers_courtship(d: Dictionary, ctx: Dictionary) -> bool:
	for c: Dictionary in Runner.choices(d, "greet", ctx):
		if String(c["goto"]) == "courtship":
			return true
	return false


func test_recruit_and_quest_choices_follow_the_recruit_flag() -> void:
	for cid: String in COMPANIONS:
		var d := _dialogue(cid)
		var before := Runner.choices(d, "greet", {"flags": {}})
		var after := Runner.choices(d, "greet", {"flags": {"companion.%s.recruit_yes" % cid: true}})
		assert_bool(before.any(func(c: Dictionary) -> bool: return c["goto"] == "recruit")).is_true()
		assert_bool(before.any(func(c: Dictionary) -> bool: return c["goto"] == "favour_open")).is_false()
		assert_bool(after.any(func(c: Dictionary) -> bool: return c["goto"] == "recruit")).is_false()
		assert_bool(after.any(func(c: Dictionary) -> bool: return c["goto"] == "favour_open")).is_true()
		# Every state has a line to show.
		var rng := RandomNumberGenerator.new()
		for flags: Dictionary in [{}, {"companion.%s.recruit_yes" % cid: true}, {"companion.%s.done" % cid: true}]:
			assert_str(String(Runner.pick_line(d, "greet", {"flags": flags, "tier": "stranger"}, rng).get("text", ""))).is_not_empty()


func test_the_text_uses_the_canon_names_and_a_gentle_courtship() -> void:
	var files: Array[String] = []
	for f: String in DirAccess.get_files_at(DIR):
		files.append(DIR + "/" + f)
	for f: String in DirAccess.get_files_at("res://dialogue/companions"):
		files.append("res://dialogue/companions/" + f)
	assert_int(files.size()).is_equal(6)
	for p: String in files:
		var t := FileAccess.get_file_as_string(p)
		for banned: String in ["Ironmarch", "Oakvale"]:
			assert_bool(t.contains(banned)).override_failure_message("%s prints %s" % [p, banned]).is_false()
