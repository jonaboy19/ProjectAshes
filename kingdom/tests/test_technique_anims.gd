extends GdUnitTestSuite
## CMU bending clips wired into technique casts (scripts/actors/bending_library.gd, data/powers/bending_clips.json):
## every clip the data maps exists in the "bending" library, the clip fixes hold (no root travel, no floor sink, the
## crouched tail eases out), techniques list a stock clip last, and the cast path retimes and routes the clip.

const BendingLibrary := preload("res://scripts/actors/bending_library.gd")
const AbilityLib := preload("res://scripts/abilities/ability_lib.gd")
const PREFIXES := ["Water_", "Air_", "Earth_", "Fire_", "Lightning_", "Guard_Ready", "Cultivate_"]
const POWER_FILES := ["bending", "sect", "knight"]
const SKILL_FILES := ["fire", "water", "wind", "earth", "lightning", "qi", "fist_palm"]

var _clip_cache := {}


class StubAnimator extends RefCounted:
	var player := AnimationPlayer.new()
	var calls: Array = []

	func play_upper(clip: String, speed := 1.0) -> void:
		calls.append(["upper", clip, speed])

	func play_full(clip: String, speed := 1.0) -> void:
		calls.append(["full", clip, speed])


## [[source, id, anims, mode]] of every power / legacy technique row.
func _rows() -> Array:
	var out: Array = []
	for f: String in POWER_FILES:
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/powers/%s.json" % f))
		for t: Dictionary in d["techniques"]:
			var a: Dictionary = t.get("ability", {})
			out.append([f, String(t["id"]), _as_list(a.get("anim", [])), String(a.get("anim_mode", "upper"))])
	for f: String in SKILL_FILES:
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/skills/%s.json" % f))
		for t: Dictionary in d["techniques"]:
			out.append([f, String(t["id"]), _as_list(t.get("anim", [])), String(t.get("anim_mode", "upper"))])
	return out


func _as_list(v: Variant) -> Array:
	return (v as Array).duplicate() if v is Array else ([String(v)] if String(v) != "" else [])


func _is_bending_name(n: String) -> bool:
	for p: String in PREFIXES:
		if n.begins_with(p):
			return true
	return false


func _glb_clips() -> PackedStringArray:
	var inst: Node = (load(BendingLibrary.GLB) as PackedScene).instantiate()
	var ap := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var out := PackedStringArray()
	for n in ap.get_animation_list():
		if String(n) != "RESET":
			out.append(String(n))
	inst.free()
	out.sort()
	return out


func _rig_player() -> Dictionary:
	var model := Assets.character("Player", 1.8, [])
	add_child(model)
	return {"model": model, "ap": Assets.animation_player(model)}


func test_sidecar_describes_every_clip_of_the_glb() -> void:
	var glb := _glb_clips()
	assert_int(glb.size()).is_equal(36)
	assert_array(Array(BendingLibrary.clip_names())).is_equal(Array(glb))
	for n: String in glb:
		var row := BendingLibrary.info(n)
		assert_bool(row.has("hit")).override_failure_message(n + " has no hit").is_true()
		assert_float(float(row["hit"])).is_greater_equal(0.0)


func test_every_mapped_clip_exists_in_the_bending_library() -> void:
	var rig := _rig_player()
	var ap: AnimationPlayer = rig["ap"]
	assert_int(BendingLibrary.install(ap)).is_equal(36)
	assert_bool(ap.has_animation_library("bending")).is_true()
	assert_int(BendingLibrary.install(ap)).is_equal(0)         # idempotent
	var mapped := 0
	var elements := {}
	for r: Array in _rows():
		for c: String in r[2]:
			if not _is_bending_name(c):
				continue
			mapped += 1
			assert_bool(BendingLibrary.has_clip(c)).override_failure_message("%s: unknown bending clip %s" % [r[1], c]).is_true()
			assert_bool(ap.has_animation("bending/" + c)).override_failure_message("%s: %s not in the library" % [r[1], c]).is_true()
			assert_str(BendingLibrary.resolve(ap, c)).is_equal("bending/" + c)
			elements[c.split("_")[0]] = true
	assert_int(mapped).is_greater_equal(45)
	for e: String in ["Water", "Air", "Earth", "Fire", "Lightning", "Guard", "Cultivate"]:
		assert_bool(elements.has(e)).override_failure_message("no technique uses a %s clip" % e).is_true()
	(rig["model"] as Node).queue_free()


func test_named_techniques_use_their_mapped_clip() -> void:
	var want := {"bn_water_whip": "Water_SpinReach_L", "bn_gust": "Air_Jump_Twist", "bn_air_step": "Air_Evade_L",
		"bn_stone_fist": "Earth_Lunge_R", "bn_quake": "Earth_PunchSeq_Deep", "bn_flame_jab": "Fire_Box_Jab_Hook_B",
		"bn_dragon_breath": "Fire_Punch_Kick", "bn_storm": "Lightning_Point_Snap", "st_circ": "Cultivate_Yoga_Floor_Flow",
		"st_breath_gather": "Cultivate_Yoga_Floor_Flow", "kn_guard": "Guard_Ready_Defensive",
		"kn_charge": "Fire_Stride_Strike_F", "fire_flame_wave": "Fire_Box_Combo_A", "water_whip": "Water_SpinReach_L",
		"qi_gathering": "Cultivate_Yoga_Floor_Flow"}
	var seen := {}
	for r: Array in _rows():
		if want.has(r[1]):
			seen[r[1]] = true
			assert_str(String(r[2][0])).override_failure_message(String(r[1])).is_equal(want[r[1]])
	assert_int(seen.size()).is_equal(want.size())


func test_techniques_keep_a_stock_clip_as_the_last_choice() -> void:
	for r: Array in _rows():
		var anims: Array = r[2]
		if anims.is_empty() or not _is_bending_name(String(anims[0])):
			continue
		assert_bool(anims.size() >= 2 and not _is_bending_name(String(anims[anims.size() - 1]))) \
			.override_failure_message("%s needs a stock clip last: %s" % [r[1], str(anims)]).is_true()


func test_clips_play_in_place_without_floor_sink_and_the_crouch_eases_out() -> void:
	var inst: Node = (load(BendingLibrary.GLB) as PackedScene).instantiate()
	var src := inst.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for n: String in BendingLibrary.clip_names():
		var a := BendingLibrary.prepare(src.get_animation(n), "Armature/Skeleton3D", BendingLibrary.info(n))
		assert_float(a.length).override_failure_message(n).is_greater(0.5)
		assert_int(a.find_track(NodePath("Armature/Skeleton3D:root"), Animation.TYPE_POSITION_3D)).override_failure_message(n + " keeps root travel").is_equal(-1)
		assert_bool(a.loop_mode == Animation.LOOP_NONE).is_true()
	# Air_Evade_L/R travelled 4 m on the root track: gone, the pelvis stays within a lean's reach of the start.
	for n: String in ["Air_Evade_L", "Air_Evade_R"]:
		var a := BendingLibrary.prepare(src.get_animation(n), "Armature/Skeleton3D", BendingLibrary.info(n))
		var idx := a.find_track(NodePath("Armature/Skeleton3D:pelvis"), Animation.TYPE_POSITION_3D)
		var p0: Vector3 = a.track_get_key_value(idx, 0)
		for k in a.track_get_key_count(idx):
			assert_float((a.track_get_key_value(idx, k) as Vector3).distance_to(p0)).override_failure_message(n).is_less(1.0)
	# The pelvis of the sinking clips is lifted (Z-up space) while a bone would be under the floor.
	for n: String in ["Fire_Box_Combo_A", "Fire_Stride_Strike_F", "Water_Whirl"]:
		assert_bool((BendingLibrary.info(n).get("lift", []) as Array).size() > 2).override_failure_message(n).is_true()
		var raw := src.get_animation(n)
		var lifted := BendingLibrary.prepare(raw, "Armature/Skeleton3D", BendingLibrary.info(n))
		var plain := BendingLibrary.prepare(raw, "Armature/Skeleton3D", {})
		var path := NodePath("Armature/Skeleton3D:pelvis")
		var peak := 0.0
		for f in int(lifted.length * 30.0):
			var t := float(f) / 30.0
			var d := (lifted.position_track_interpolate(lifted.find_track(path, Animation.TYPE_POSITION_3D), t) as Vector3) \
				- (plain.position_track_interpolate(plain.find_track(path, Animation.TYPE_POSITION_3D), t) as Vector3)
			peak = maxf(peak, d.length())
		assert_float(peak).override_failure_message(n + " is not lifted").is_greater(0.03)
	# Earth_Punch_Hold_Deep: the last pose is the first pose again (it used to end crouched).
	var h := BendingLibrary.prepare(src.get_animation("Earth_Punch_Hold_Deep"), "Armature/Skeleton3D", BendingLibrary.info("Earth_Punch_Hold_Deep"))
	assert_float(h.length).is_equal_approx(4.6, 0.01)
	for t in h.get_track_count():
		if h.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			var q0: Quaternion = h.track_get_key_value(t, 0)
			var q1: Quaternion = h.track_get_key_value(t, h.track_get_key_count(t) - 1)
			assert_float(q0.angle_to(q1)).override_failure_message(String(h.track_get_path(t))).is_less(0.02)
	inst.free()


func test_play_cast_routes_by_mode_and_lands_the_strike_on_the_windup() -> void:
	var s := StubAnimator.new()
	var lib := AnimationLibrary.new()
	lib.add_animation("Fire_Box_Combo_A", Animation.new())
	s.player.add_animation_library("bending", lib)
	var stock := AnimationLibrary.new()
	stock.add_animation("Spell_Simple_Shoot", Animation.new())
	s.player.add_animation_library("", stock)
	var def := {"anims": ["Fire_Box_Combo_A", "Spell_Simple_Shoot"], "anim_mode": "upper", "anim_speed": 1.0, "windup": 0.5}
	var r := BendingLibrary.play_cast(s, def)
	assert_str(String(r["clip"])).is_equal("bending/Fire_Box_Combo_A")
	assert_str(String(s.calls[0][0])).is_equal("upper")
	var hit := float(BendingLibrary.info("Fire_Box_Combo_A")["hit"])
	assert_float(float(r["speed"])).is_equal_approx(clampf(hit / 0.5, 0.75, 1.8), 0.001)
	# Full mode, a windup too short for the strike: the speed is capped.
	var r2 := BendingLibrary.play_cast(s, {"anims": ["Fire_Box_Combo_A"], "anim_mode": "full", "anim_speed": 1.0, "windup": 0.1})
	assert_str(String(s.calls[1][0])).is_equal("full")
	assert_float(float(r2["speed"])).is_less_equal(1.8)
	# A clip the rig does not have falls through to the stock clip, and no clip at all plays nothing.
	var r3 := BendingLibrary.play_cast(s, {"anims": ["Air_Evade_L", "Spell_Simple_Shoot"], "anim_mode": "upper", "anim_speed": 1.0})
	assert_str(String(r3["clip"])).is_equal("Spell_Simple_Shoot")
	assert_dict(BendingLibrary.play_cast(s, {"anims": ["Nope"], "anim_mode": "upper"})).is_empty()
	s.player.free()


func test_npc_caster_abilities_resolve_to_bending_clips() -> void:
	var n := 0
	for id: String in ["st_palm", "st_flowing_palm", "st_nine", "kn_guard", "kn_charge", "kn_shoulder_rush", "bn_water_whip"]:
		var def: Dictionary = AbilityLib.get_def(id)
		assert_bool(not def.is_empty()).override_failure_message(id).is_true()
		assert_bool(BendingLibrary.is_bending(def)).override_failure_message(id).is_true()
		n += 1
	assert_int(n).is_equal(7)
