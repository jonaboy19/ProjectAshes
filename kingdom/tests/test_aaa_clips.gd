extends GdUnitTestSuite
## AAA mocap wiring (docs/anim/aaa_wiring/): the manifest covers every staged clip, wired names are unique, never shadow an
## existing clip and carry no IP-flavoured names, and every NPC combat row has a marker.

const AaaClipsScript := preload("res://scripts/actors/aaa_clips.gd")
const Moves := preload("res://scripts/combat/combat_moves.gd")
const Markers := preload("res://scripts/actors/combat_markers.gd")
const BANNED := ["Knight", "Assassin", "Chantless", "Magic_", "Smoke", "Execution", "Decapitation", "Bending", "Mythic", "Umbrella"]


func _pack_clip_names(pack: String) -> Array:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(pack + ".clips.json"))
	var out: Array = []
	for c: Dictionary in d:
		out.append(String(c["name"]))
	return out


func test_manifest_lists_all_108_clips_exactly() -> void:
	var packs: Dictionary = AaaClipsScript.manifest()["packs"]
	assert_int(packs.size()).is_equal(10)
	var total := 0
	for pack: String in packs:
		var want := _pack_clip_names(pack)
		var have: Array = (packs[pack] as Dictionary).keys()
		want.sort()
		have.sort()
		assert_array(have).is_equal(want)
		total += have.size()
	assert_int(total).is_equal(108)


func test_every_entry_has_a_decision_and_a_reason() -> void:
	var packs: Dictionary = AaaClipsScript.manifest()["packs"]
	for pack: String in packs:
		for clip: String in packs[pack]:
			var e: Dictionary = packs[pack][clip]
			assert_bool(["add", "cmp", "skip"].has(String(e["status"]))).is_true()
			assert_bool(String(e.get("why", "")).length() > 8).is_true()
			if String(e["status"]) != "skip":
				assert_bool(e.has("as")).is_true()


func test_game_names_are_unique_and_clean() -> void:
	var seen := {}
	var packs: Dictionary = AaaClipsScript.manifest()["packs"]
	for pack: String in packs:
		for clip: String in packs[pack]:
			var e: Dictionary = packs[pack][clip]
			if not e.has("as"):
				continue
			var n := String(e["as"])
			assert_bool(seen.has(n)).is_false()
			seen[n] = true
			for bad: String in BANNED:
				assert_bool(n.contains(bad)).is_false()
	assert_int(seen.size()).is_greater(15)


func test_wired_clips_reach_the_shared_library_and_none_shadows_an_existing_clip() -> void:
	var lib: AnimationLibrary = Assets._ual_for(NodePath("Probe/Skeleton3D"))
	var names := AaaClipsScript.wired_names()
	assert_int(names.size()).is_greater(15)
	for n in names:
		assert_bool(lib.has_animation(n)).is_true()
		# merge_into refuses an existing name, so a same-named clip that is not ours would lack this meta
		assert_bool(lib.get_animation(n).has_meta("aaa_source")).is_true()
		assert_float(lib.get_animation(n).length).is_greater(0.3)
	var first := lib.get_animation(names[0])
	for t in first.get_track_count():
		assert_bool(String(first.track_get_path(t)).begins_with("Probe/Skeleton3D")).is_true()


func test_trimmed_duel_clips_have_the_trim_length() -> void:
	var lib: AnimationLibrary = Assets._ual_for(NodePath("Probe/Skeleton3D"))
	assert_float(lib.get_animation("Duel_Lunge").length).is_equal_approx(1.4, 0.05)
	assert_float(lib.get_animation("Duel_Riposte").length).is_equal_approx(1.3, 0.05)
	assert_float(lib.get_animation("Duel_Parry_High").length).is_equal_approx(1.2, 0.05)


func test_vault_run_exists_for_the_player_rig() -> void:
	var lib: AnimationLibrary = Assets._ual_for(NodePath("Probe/Skeleton3D"))
	assert_bool(lib.has_animation("Vault_Run")).is_true()
	assert_bool(lib.has_animation("Vault_Low")).is_true()      # the authored vaults are untouched


func test_every_npc_combat_row_has_a_marker() -> void:
	var anims: Array = []
	for row: Array in Moves.BANDIT_ROWS:
		anims.append(String(row[0]))
	for row: Array in Moves.BRUTE_ROWS:
		anims.append(String(row[0]))
	for k in ["parry", "riposte", "lunge"]:
		anims.append(String(Moves.DUEL[k]))
	for a: String in anims:
		assert_bool(Markers.has_clip(a)).is_true()
		var h := Markers.hits_s(a, 1.0)
		assert_int(h.size()).is_greater(0)
		assert_float(h[0]).is_greater(0.1)
	# the row's contact time is the marker's (seconds at rate 1)
	for row: Array in Moves.BANDIT_ROWS:
		assert_float(float(row[3])).is_equal_approx(Markers.hits_s(String(row[0]), 1.0)[0], 0.02)


func test_npc_swing_table_only_names_wired_clips() -> void:
	var wired := AaaClipsScript.wired_names()
	for table: Dictionary in [Moves.NPC_SWINGS, Moves.NPC_SWINGS_2H]:
		for id: String in table:
			for clip: String in table[id]:
				assert_bool(wired.has(clip)).is_true()
	assert_str(Moves.npc_swing("bandit_cleave", false, 0)).is_equal("Bandit_Heavy_Chop")
	assert_str(Moves.npc_swing("bandit_cleave", true, 1)).is_equal("GS_Spin")
	assert_str(Moves.npc_swing("not_a_move", false, 0)).is_equal("")
