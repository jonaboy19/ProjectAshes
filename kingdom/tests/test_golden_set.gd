extends GdUnitTestSuite
## Golden set (docs/plans/AAA_FINISH_PLAN.md A3/B): schema, slots, resolution rules.

const STATUSES := ["gold", "probation", "banned"]


func before_test() -> void:
	GoldenSet.force_enforce = false
	GoldenSet.reload()


func after_test() -> void:
	GoldenSet.force_enforce = false


func test_schema_and_statuses() -> void:
	var d := GoldenSet.data()
	assert_bool(d.is_empty()).is_false()
	assert_int(int(d["version"])).is_equal(1)
	var clips: Dictionary = d["clips"]
	assert_int(clips.size()).is_greater(100)
	for k: String in clips:
		var c: Dictionary = clips[k]
		assert_bool(STATUSES.has(c["status"])).override_failure_message("%s: bad status" % k).is_true()
		if c["status"] == "gold":
			var rv: Dictionary = c.get("review", {})
			assert_str(String(rv.get("verdict", ""))).override_failure_message("%s: gold without a passing review" % k).is_equal("pass")
			assert_bool(String(rv.get("sheet", "")) != "").override_failure_message("%s: review has no sheet path" % k).is_true()


func test_slots_name_a_known_primary_clip() -> void:
	var d := GoldenSet.data()
	var clips: Dictionary = d["clips"]
	for sid: String in d["slots"]:
		var s: Dictionary = d["slots"][sid]
		assert_bool(clips.has(s["primary"])).override_failure_message("slot %s: primary %s is not a measured clip" % [sid, s["primary"]]).is_true()


func test_resolve_passes_good_clips_and_replaces_banned_ones_when_enforcing() -> void:
	var d := GoldenSet.data()
	var good := ""
	var bad := ""
	for k: String in d["clips"]:
		var st: String = d["clips"][k]["status"]
		if good == "" and st != "banned" and not k.contains("/"):
			good = k
		if bad == "" and st == "banned" and not k.contains("/"):
			bad = k
	assert_str(String(GoldenSet.resolve(StringName(good)))).is_equal(good)
	assert_str(String(GoldenSet.resolve(&"No_Such_Clip"))).is_equal("No_Such_Clip")
	if bad != "":
		assert_bool(GoldenSet.is_banned(StringName(bad))).is_true()
		assert_str(String(GoldenSet.resolve(StringName(bad)))).is_equal(bad)    # enforcement off: unchanged
		GoldenSet.force_enforce = true
		assert_str(String(GoldenSet.resolve(StringName(bad)))).is_not_equal(bad)
		assert_bool(GoldenSet.skip_in_library(StringName(bad))).is_true()


func test_slot_resolution_prefers_primary_then_variant_then_fallback() -> void:
	GoldenSet.force_enforce = true
	var d := GoldenSet.data()
	for sid: String in d["slots"]:
		var s: Dictionary = d["slots"][sid]
		var got := String(GoldenSet.resolve(StringName(s["primary"]), sid))
		if not GoldenSet.is_banned(StringName(s["primary"])):
			assert_str(got).override_failure_message("slot " + sid).is_equal(s["primary"])
		else:
			# a banned clip may only remain when the whole slot is a recorded gap (S3-S5 close these)
			var gap: bool = (d.get("accepted_gaps", []) as Array).has(s["primary"])
			assert_bool(got != s["primary"] or gap).override_failure_message("slot %s still plays banned %s" % [sid, s["primary"]]).is_true()


func test_gold_clips_carry_measured_metrics() -> void:
	var d := GoldenSet.data()
	for k: String in d["clips"]:
		var c: Dictionary = d["clips"][k]
		if c["status"] == "gold":
			assert_bool((c["metrics"] as Dictionary).has("pen_cm")).override_failure_message(k + ": gold without metrics").is_true()


func test_runtime_code_tables_do_not_name_unlisted_banned_clips() -> void:
	# Clips that gameplay code names directly. A banned one must be in accepted_gaps (S3-S5 replace them; see AAA_PROGRESS.md).
	var d := GoldenSet.data()
	var accepted: Array = d.get("accepted_gaps", [])
	var named: Array = []
	for v: Variant in CharacterAnimator.PREFERRED_CLIPS.values():
		named.append(String(v))
	for k: String in named:
		if GoldenSet.is_banned(StringName(k)):
			assert_bool(accepted.has(k)).override_failure_message("banned clip %s is used by CharacterAnimator.PREFERRED_CLIPS and not in accepted_gaps" % k).is_true()
