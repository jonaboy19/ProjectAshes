extends GdUnitTestSuite
## NPC motion package M2: the tagged clip library (tools/anim/life/tag_clips.py -> data/anim/motion_tags.json)
## and the variety picker (scripts/living_world/clip_picker.gd). Rules C1, C2, C3 of docs/plans/NPC_MOTION_RULES.md.


func after_test() -> void:
	ClipPicker.reset()


## A small synthetic index so exact weights and pool sizes are known.
func _synth(weights: Array, verb := "x") -> void:
	var clips := {}
	for i in weights.size():
		clips["C%d" % i] = {"verb": verb, "posture": "stand", "prop": "none", "mood": "calm", "layer": "full",
			"intensity": 0.5, "vat": true, "phase": "loop", "weight": weights[i], "wired": true, "tags": []}
	ClipPicker.load_index({"clips": clips})


func _index() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ClipPicker.INDEX_PATH))


# --- C1: tagged library -----------------------------------------------------------------------------

func test_every_life_clip_has_a_verb_and_posture() -> void:
	var doc := _index()
	var clips: Dictionary = doc["clips"]
	var verbs: Array = doc["axes"]["verb"]
	var postures: Array = doc["axes"]["posture"]
	var life := LifeLibrary.meta()
	assert_int(life.size()).is_greater(200)
	for name: String in life:
		assert_bool(clips.has(name)).override_failure_message("life clip %s is not tagged" % name).is_true()
		var c: Dictionary = clips[name]
		assert_bool(verbs.has(c.get("verb"))).override_failure_message("%s verb %s" % [name, c.get("verb")]).is_true()
		assert_bool(postures.has(c.get("posture"))).override_failure_message("%s posture %s" % [name, c.get("posture")]).is_true()


func test_no_unknown_names_or_axis_values() -> void:
	var doc := _index()
	var life := LifeLibrary.meta()
	var ax: Dictionary = doc["axes"]
	for name: String in doc["clips"]:
		var c: Dictionary = doc["clips"][name]
		if String(c["library"]).begins_with("UAL_Life_"):
			assert_bool(life.has(name)).override_failure_message("%s is tagged but not in any sidecar" % name).is_true()
		for axis: String in ["verb", "posture", "prop", "mood", "layer", "phase"]:
			assert_bool((ax[axis] as Array).has(c[axis])).override_failure_message("%s: %s=%s" % [name, axis, c[axis]]).is_true()
		assert_float(c["intensity"]).is_between(0.0, 1.0)
		assert_float(c["weight"]).is_greater(0.0)
		assert_bool(typeof(c["vat"]) == TYPE_BOOL).is_true()


func test_vat_flag_matches_the_bake_list() -> void:
	var bake: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/living_world/vat_bake.json"))
	var baked := {}
	for set_name: String in bake["clip_sets"]:
		for item: String in bake["clip_sets"][set_name]:
			for part in item.split("+"):
				baked[part] = true
	var clips: Dictionary = _index()["clips"]
	for name: String in baked:
		if clips.has(name):
			assert_bool(clips[name]["vat"]).override_failure_message("%s is baked but vat=false" % name).is_true()
	assert_bool(clips["Life_Farm_Hoe"]["vat"]).is_true()
	assert_bool(clips["Life_Smith_Hammer"]["vat"]).is_false()


func test_untagged_libraries_get_sane_tags() -> void:
	var clips: Dictionary = _index()["clips"]
	assert_str(clips["Life_Mx5_Talk_Explain"]["verb"]).is_equal("talk")             # Mixamo5
	assert_str(clips["Life_Mx5_Argue_A"]["mood"]).is_equal("angry")
	assert_str(clips["Life_Mz_Chop_Wood"]["verb"]).is_equal("chop")                 # Meshy
	assert_str(clips["Life_Mz_Chop_Wood"]["prop"]).is_equal("axe")
	assert_str(clips["Life_Mz_Sleep_Bed"]["posture"]).is_equal("lie")
	assert_str(clips["Life_Mx2_Plant_Plant"]["posture"]).is_equal("kneel")          # Mixamo_Farm
	assert_str(clips["Life_Mx2_Water"]["verb"]).is_equal("water")
	assert_str(clips["Life_Farm_Milk_Cow"]["posture"]).is_equal("sit")              # Work
	assert_str(clips["Life_Carry_Bucket_Upper"]["layer"]).is_equal("upper")
	assert_str(clips["Life_Carry_Bucket_Upper"]["prop"]).is_equal("bucket")
	assert_str(clips["Life_Rest_Sit_Bench_Enter"]["phase"]).is_equal("enter")
	assert_str(clips["Life_Smith_Hammer_Enter"]["verb"]).is_equal("forge")          # inherits the parent row
	assert_str(clips["Life_Walk_Sad"]["mood"]).is_equal("sad")


func test_aaa_unwired_clips_are_never_picked() -> void:
	var clips: Dictionary = _index()["clips"]
	assert_bool(clips["Run_Natural"]["wired"]).is_false()
	assert_bool(ClipPicker.is_known("Run_Natural")).is_false()
	assert_bool(ClipPicker.is_known("GS_Slash")).is_true()
	assert_bool(ClipPicker.is_known("Life_Farm_Hoe")).is_true()


# --- C2: variety pick -------------------------------------------------------------------------------

func test_no_immediate_repeat_over_1000_picks() -> void:
	for verb: String in ["talk", "sit", "look", "walk", "carry", "play_music"]:
		var pool := ClipPicker.candidates({"verb": verb})
		assert_int(pool.size()).is_greater(3)
		var hist := PackedStringArray()
		var prev := ""
		for cycle in 1000:
			var c := ClipPicker.pick({"verb": verb, "day": 2, "cycle": cycle}, {"id": 7}, hist)
			assert_str(c).is_not_empty()
			assert_bool(c != prev).override_failure_message("%s repeated %s at cycle %d" % [verb, c, cycle]).is_true()
			assert_bool(hist.has(c)).override_failure_message("%s in the last 3 at cycle %d" % [c, cycle]).is_false()
			prev = c
			hist.append(c)
			if hist.size() > ClipPicker.HISTORY_WINDOW:
				hist.remove_at(0)


func test_small_pool_never_dead_ends() -> void:
	_synth([1.0, 1.0])
	var hist := PackedStringArray()
	var prev := ""
	for cycle in 200:
		var c := ClipPicker.pick({"verb": "x", "cycle": cycle}, {"id": 1}, hist)
		assert_str(c).is_not_empty()
		assert_bool(c != prev).is_true()      # with two clips the newest history entry is still excluded
		prev = c
		hist.append(c)
	_synth([1.0])
	assert_str(ClipPicker.pick({"verb": "x"}, {"id": 1}, PackedStringArray(["C0", "C0", "C0"]))).is_equal("C0")


func test_weight_distribution_within_ten_percent() -> void:
	var ws := [1.0, 2.0, 3.0, 4.0]
	_synth(ws)
	var counts := {}
	var n := 20000
	for cycle in n:
		var c := ClipPicker.pick({"verb": "x", "day": cycle / 100, "cycle": cycle}, {"id": cycle % 37}, PackedStringArray())
		counts[c] = int(counts.get(c, 0)) + 1
	for i in ws.size():
		var expect: float = ws[i] / 10.0
		var got: float = float(counts.get("C%d" % i, 0)) / n
		assert_float(got / expect).override_failure_message("C%d got %f want %f" % [i, got, expect]).is_between(0.9, 1.1)


func test_real_verb_distribution_follows_weights() -> void:
	var query := {"verb": "talk"}
	var persona := {"id": 5, "gesture": 1.15, "mood": 0.8}
	var w := ClipPicker.weights(query, persona)
	var sum := 0.0
	for k: String in w:
		sum += w[k]
	assert_int(w.size()).is_greater(4)
	var counts := {}
	var n := 30000
	for cycle in n:
		var q := {"verb": "talk", "day": cycle / 200, "cycle": cycle}
		var c := ClipPicker.pick(q, {"id": 5, "gesture": 1.15, "mood": 0.8}, PackedStringArray())
		counts[c] = int(counts.get(c, 0)) + 1
	for k: String in w:
		var expect: float = w[k] / sum
		if expect < 0.04:
			continue  # tiny buckets are noise at this sample size
		assert_float(float(counts.get(k, 0)) / n / expect).override_failure_message("%s" % k).is_between(0.9, 1.1)


func test_deterministic() -> void:
	var hist := PackedStringArray(["Life_Talk_Explain"])
	var a := PackedStringArray()
	for cycle in 100:
		a.append(ClipPicker.pick({"verb": "talk", "day": 4, "cycle": cycle}, {"id": 11, "gesture": 1.1}, hist))
	ClipPicker.reset()   # reload the index from disk: same answers
	for cycle in 100:
		assert_str(ClipPicker.pick({"verb": "talk", "day": 4, "cycle": cycle}, {"id": 11, "gesture": 1.1}, hist)).is_equal(a[cycle])
	# a different person or day gives a different sequence
	var other := 0
	for cycle in 100:
		if ClipPicker.pick({"verb": "talk", "day": 4, "cycle": cycle}, {"id": 12, "gesture": 1.1}, hist) != a[cycle]:
			other += 1
	assert_int(other).is_greater(30)


func test_neighbour_desync_rule() -> void:
	_synth([1.0, 1.0, 1.0, 1.0, 1.0])
	var neigh := PackedStringArray(["C0", "C1", "C2"])  # oldest first: only the last 2 count
	var seen := {}
	for cycle in 400:
		var c := ClipPicker.pick({"verb": "x", "cycle": cycle}, {"id": 3}, PackedStringArray(), neigh)
		assert_bool(c != "C1" and c != "C2").override_failure_message("copied a neighbour: %s" % c).is_true()
		seen[c] = true
	assert_bool(seen.has("C0")).is_true()   # the third-newest neighbour entry is not excluded
	assert_bool(seen.has("C3") and seen.has("C4")).is_true()
	# history wins over neighbours when the pool is tight: 5 clips, 3 in history, 2 on neighbours -> nothing left,
	# so the neighbour exclusion is dropped and the history exclusion holds
	var hist := PackedStringArray(["C0", "C1", "C2"])
	for cycle in 100:
		var c := ClipPicker.pick({"verb": "x", "cycle": cycle}, {"id": 3}, hist, PackedStringArray(["C3", "C4"]))
		assert_bool(c == "C3" or c == "C4").is_true()


func test_two_bodies_side_by_side_do_not_sync() -> void:
	# a stand-in for the npc_street_flow gate: bodies decide in turn, each seeing the last two clips of the others
	var bodies := 6
	var playing := PackedStringArray()
	playing.resize(bodies)
	var hists: Array[PackedStringArray] = []
	for b in bodies:
		hists.append(PackedStringArray())
	var clashes := 0
	for cycle in 300:
		for b in bodies:
			var neigh := PackedStringArray()
			for o in bodies:
				if o != b and playing[o] != "":
					neigh.append(playing[o])
			var c := ClipPicker.pick({"verb": "look", "cycle": cycle}, {"id": 100 + b}, hists[b], neigh)
			if neigh.size() >= 2 and (c == neigh[neigh.size() - 1] or c == neigh[neigh.size() - 2]):
				clashes += 1
			playing[b] = c
			hists[b].append(c)
			if hists[b].size() > 3:
				hists[b].remove_at(0)
	assert_int(clashes).is_equal(0)


func test_filters_and_relaxation() -> void:
	var sits := ClipPicker.candidates({"verb": "sit"})
	assert_int(sits.size()).is_greater(5)
	assert_bool(sits.has("Life_Rest_Sit_Bench_Enter")).is_false()                      # transitions need phase=enter
	assert_bool(ClipPicker.candidates({"verb": "sit", "phase": "enter"}).has("Life_Rest_Sit_Bench_Enter")).is_true()
	for c in ClipPicker.candidates({"verb": "carry", "layer": "upper"}):
		assert_str(_index()["clips"][c]["layer"]).is_equal("upper")
	for c in ClipPicker.candidates({"verb": "walk", "vat": true}):
		assert_bool(_index()["clips"][c]["vat"]).is_true()
	# an impossible prop relaxes to the verb's clips; an unknown verb returns ""
	assert_int(ClipPicker.candidates({"verb": "talk", "prop": "bucket"}).size()).is_greater(0)
	assert_str(ClipPicker.pick({"verb": "no_such_verb"}, {}, PackedStringArray())).is_empty()
	# prop filter picks the prop clip when one exists
	var tools := ClipPicker.candidates({"verb": "forge", "prop": "tongs"})
	assert_int(tools.size()).is_greater(0)
	assert_str(_index()["clips"][tools[0]]["prop"]).is_equal("tongs")


func test_mood_query_prefers_matching_clips() -> void:
	var w := ClipPicker.weights({"verb": "walk", "mood": "sad"}, {})
	assert_float(w["Life_Walk_Sad"]).is_greater(w["Life_Walk_Happy"] * 10.0)
	var calm := ClipPicker.weights({"verb": "walk"}, {})
	assert_float(calm["Life_Walk_Sad"]).is_equal(calm["Life_Walk_Brisk"])             # no query mood, neutral persona


# --- C3: personality offsets ------------------------------------------------------------------------

func test_persona_bias_and_ranges() -> void:
	var calm := ClipPicker.weights({"verb": "talk"}, {"gesture": 0.8})
	var lively := ClipPicker.weights({"verb": "talk"}, {"gesture": 1.2})
	assert_float(lively["Life_Talk_Emphatic"]).is_greater(calm["Life_Talk_Emphatic"])
	assert_float(lively["Life_Talk_Casual"]).is_less(calm["Life_Talk_Casual"])
	var offsets := {}
	for person in 200:
		assert_float(ClipPicker.loop_rate(person)).is_between(0.93, 1.07)
		assert_float(ClipPicker.walk_speed_scale(person)).is_between(0.88, 1.12)
		assert_float(ClipPicker.idle_pitch_deg(person)).is_between(-3.0, 4.0)
		assert_float(ClipPicker.idle_start_offset(person, 0, 4.0)).is_between(0.0, 4.0)
		# stable per id
		assert_float(ClipPicker.loop_rate(person)).is_equal(ClipPicker.loop_rate(person))
		offsets[snappedf(ClipPicker.idle_start_offset(person, 0, 4.0), 0.05)] = true
	assert_int(offsets.size()).is_greater(30)   # the start phases are spread out, nobody is in sync
	assert_float(ClipPicker.talk_rate(0.8)).is_equal(1.0)
	assert_float(ClipPicker.talk_rate(1.2)).is_equal_approx(1.15, 0.0001)
	assert_float(ClipPicker.talk_rate(1.0)).is_between(1.0, 1.15)


func test_walk_speed_matches_life_ambience() -> void:
	for person in [1, 2, 33, 4096]:
		var amb := LifeAmbience.new(person)
		assert_float(ClipPicker.walk_speed_scale(person)).is_equal_approx(amb.walk_speed, 0.0001)
		assert_float(ClipPicker.loop_rate(person)).is_equal_approx(amb.anim_rate, 0.0001)


# --- cost -------------------------------------------------------------------------------------------

func test_cost_24_bodies_1000_picks() -> void:
	ClipPicker.ensure_loaded()
	var hist := PackedStringArray(["Life_Talk_Casual", "Life_Social_Shrug"])
	var neigh := PackedStringArray(["Life_Talk_Explain", "Life_Mx5_Talk_Funny"])
	var t0 := Time.get_ticks_usec()
	for cycle in 1000:
		for b in 24:
			ClipPicker.pick({"verb": "talk", "posture": "stand", "mood": "happy", "cycle": cycle}, {"id": b, "gesture": 1.1, "mood": 0.6}, hist, neigh)
	var us := float(Time.get_ticks_usec() - t0) / 24000.0
	print("clip_picker.pick: %.1f us per call (24 bodies x 1000 picks)" % us)
	assert_float(us).is_less(250.0)   # loose: a pick runs once per clip change, not per frame; budget is 0.02 ms/body/frame
