extends GdUnitTestSuite
## PC1 WP1: PC_TIERS shape, phone-capability keys, GROUPS coverage and the unchanged phone rows.

const Q := preload("res://scripts/core/quality.gd")

const CAPS := ["draw_merge", "prop_cull", "impostor_cap", "vat_crowd", "lite_world", "lod1_dressing", "stream_mul", "grass_mul"]
const PC_ONLY := ["scale", "taa", "ssao_half", "sdfgi_cascades", "sdfgi_cell", "sdfgi_rays", "sdfgi_converge", "gi_half",
	"vfog_size", "vfog_depth", "ssr_steps", "water_ssr", "crowd"]

## The original phone rows (key -> LOW, MEDIUM, HIGH, ULTRA) must never change.
const MOBILE_SNAPSHOT := {
	"max_3d_height": [720, 720, 1080, 0],
	"scaling": ["bilinear", "fsr", "fsr", "bilinear"],
	"fps": [30, 60, 60, 0],
	"shadow": [1, 1, 2, 4],
	"shadow_size": [1024, 2048, 4096, 4096],
	"shadow_dist": [24.0, 50.0, 60.0, 140.0],
	"ssao": [false, false, true, true],
	"sdfgi": [false, false, false, true],
	"vol_fog": [false, false, false, true],
	"lod_threshold": [8.0, 2.0, 1.0, 1.0],
	"range": [0.55, 0.75, 1.0, 1.0],
	"scatter": [0.3, 0.6, 1.0, 1.0],
	"aniso": [0, 1, 2, 3],
	"msaa": [0, 0, 0, 2],
	"fxaa": [false, true, true, true],
	"npc_full": [5, 8, 14, 16],
	"rig_budget": [0, 3, 6, 10],
	"npc_sprites": [10, 22, 32, 45],
	"view_radius": [2, 3, 4, 5],
	"light_fade": [35.0, 50.0, 80.0, 0.0],
	"town_far": [200.0, 600.0, 0.0, 0.0],
}


func test_pc_rows_have_all_mobile_and_capability_keys() -> void:
	assert_int(Q.PC_TIERS.size()).is_equal(4)
	for t in 4:
		var row: Dictionary = Q.PC_TIERS[t]
		for k: String in Q.TIERS[0]:
			assert_bool(row.has(k)).override_failure_message("PC row %d lacks %s" % [t, k]).is_true()
		for k: String in CAPS + PC_ONLY:
			assert_bool(row.has(k)).override_failure_message("PC row %d lacks %s" % [t, k]).is_true()


func test_mobile_rows_have_capability_keys() -> void:
	for t in 4:
		for k: String in CAPS:
			assert_bool((Q.TIERS[t] as Dictionary).has(k)).override_failure_message("mobile row %d lacks %s" % [t, k]).is_true()


func test_pc_rows_do_not_use_phone_hacks() -> void:
	for t in 4:
		var row: Dictionary = Q.PC_TIERS[t]
		assert_bool(bool(row["draw_merge"])).is_false()
		assert_int(int(row["prop_cull"])).is_equal(0)
		assert_float(float(row["impostor_cap"])).is_equal(0.0)
		assert_bool(bool(row["lite_world"])).is_false()
		assert_bool(bool(row["vat_crowd"])).is_true()


func test_mobile_capabilities_reproduce_phone_behaviour() -> void:
	assert_bool(bool(Q.TIERS[0]["draw_merge"])).is_true()
	assert_bool(bool(Q.TIERS[1]["draw_merge"])).is_false()
	assert_array([Q.TIERS[0]["prop_cull"], Q.TIERS[1]["prop_cull"], Q.TIERS[2]["prop_cull"], Q.TIERS[3]["prop_cull"]]).is_equal([1, 2, 0, 0])
	assert_array([Q.TIERS[0]["impostor_cap"], Q.TIERS[1]["impostor_cap"], Q.TIERS[2]["impostor_cap"]]).is_equal([150.0, 220.0, 0.0])
	assert_array([Q.TIERS[0]["vat_crowd"], Q.TIERS[1]["vat_crowd"]]).is_equal([false, true])
	assert_array([Q.TIERS[0]["lite_world"], Q.TIERS[1]["lite_world"]]).is_equal([true, false])
	assert_array([Q.TIERS[0]["lod1_dressing"], Q.TIERS[1]["lod1_dressing"], Q.TIERS[2]["lod1_dressing"]]).is_equal([true, true, false])


func test_groups_keys_exist_in_both_tables() -> void:
	for g: String in Q.GROUPS:
		for k: String in Q.GROUPS[g]:
			assert_bool((Q.TIERS[0] as Dictionary).has(k) or k in PC_ONLY).override_failure_message("mobile lacks group key %s" % k).is_true()
			assert_bool((Q.PC_TIERS[0] as Dictionary).has(k)).override_failure_message("PC lacks group key %s" % k).is_true()


func test_mobile_rows_unchanged() -> void:
	for k: String in MOBILE_SNAPSHOT:
		var want: Array = MOBILE_SNAPSHOT[k]
		for t in 4:
			assert_that(Q.TIERS[t][k]).override_failure_message("TIERS[%d][%s]" % [t, k]).is_equal(want[t])


func test_pc_high_is_the_4070_target() -> void:
	var h: Dictionary = Q.PC_TIERS[Q.HIGH]
	assert_str(h["scaling"]).is_equal("fsr2")
	assert_bool(bool(h["sdfgi"])).is_true()
	assert_int(int(h["msaa"])).is_equal(0)
	assert_float(float(h["scale"])).is_equal(0.77)
