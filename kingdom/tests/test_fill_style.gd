extends GdUnitTestSuite
## Style G pass over the meshy_free fill models (scripts/world/fill_style.gd, data/region1/world/fill_sites.json):
## off-style models are never placed, every placed model exists, treatments only name placed models and stay in range.

const FillStyle := preload("res://scripts/world/fill_style.gd")
const FILL := "res://data/region1/world/fill_sites.json"
const PACK := "res://assets/incoming/meshy_free/"
const MESHY3 := "res://data/region1/world/meshy3_sites.json"
const WILDS := "res://data/region1/world/thornfield_wilds.json"


func _models() -> Dictionary:
	var out := {}
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FILL))
	for site: Dictionary in d["sites"]:
		for part: Array in site["parts"]:
			out[FillStyle.model_of(String(part[0]))] = true
	# Meshy batch 3 ("dl3:" keys, model ids "dl3/<cat>/<name>"): the yards and the wilds extras (tests/test_meshy3.gd covers them in depth).
	var m3: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MESHY3))
	for site: Dictionary in m3["sites"]:
		for part: Array in site["parts"]:
			out[FillStyle.model_of(String(part[0]))] = true
	var wilds: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WILDS))
	for host: Dictionary in [wilds["outpost"], wilds["bandit_camp"], wilds["rift"]]:
		for e: Array in host.get("extras", []):
			out[FillStyle.model_of(String(e[0]))] = true
	return out


func test_dropped_models_are_not_placed() -> void:
	var placed := _models()
	for m: String in FillStyle.DROPPED:
		assert_bool(placed.has(m)).override_failure_message("off-style model still placed: " + m).is_false()
		assert_bool(FillStyle.is_dropped(m)).is_true()


func test_every_placed_model_exists_and_no_pink_toy_models() -> void:
	for m: String in _models():
		var path := FillStyle.dl3_path(m) if m.begins_with("dl3/") else PACK + m + "_lod0.glb"
		assert_bool(ResourceLoader.exists(path)).override_failure_message("missing " + m).is_true()
		assert_bool(m.contains("pink") or m.contains("whimsical") or m.contains("cartoon_green_a")).override_failure_message(m).is_false()


func test_every_fill_site_keeps_at_least_one_part() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FILL))
	for site: Dictionary in d["sites"]:
		assert_int((site["parts"] as Array).size()).override_failure_message(String(site["id"])).is_greater(0)


func test_treatments_are_sane() -> void:
	var placed := _models()
	for m: String in FillStyle.TREAT:
		assert_bool(placed.has(m)).override_failure_message("treatment for an unplaced model: " + m).is_true()
		var spec: Dictionary = FillStyle.TREAT[m]
		assert_bool(FillStyle.is_dropped(m)).is_false()
		for k: String in spec:
			assert_bool(k in ["role", "saturation", "value_gain", "roughness", "spec"]).override_failure_message(m + ": " + k).is_true()
		if spec.has("saturation"):
			assert_float(float(spec["saturation"])).is_between(0.3, 1.0)
		if spec.has("value_gain"):
			assert_float(float(spec["value_gain"])).is_between(0.7, 1.0)
	assert_dict(FillStyle.spec_for("banners/banner_gold_finials")).is_not_empty()


func test_model_of_strips_prefix_and_height() -> void:
	assert_str(FillStyle.model_of("free:castle/castle_sandstone_a@17.32")).is_equal("castle/castle_sandstone_a")
	assert_str(FillStyle.model_of("dl3:props/keg_big@1.1")).is_equal("dl3/props/keg_big")
	assert_str(FillStyle.dl3_path("dl3:props/keg_big@1.1", 1)).is_equal("res://assets/incoming/meshy_dl3/props/keg_big_lod1.glb")


func test_meshy3_rejects_are_dropped_from_fills() -> void:
	var Fill := preload("res://scripts/world/region1_fill.gd")
	var raw := {"search": {}, "clear": 4, "parts": [["dl3:buildings/tavern_blue_porch@6.1", 0, 0, 0, 1, 0], ["dl3:props/keg_big@1.1", 1, 0, 0, 0, 0]]}
	var spec: Dictionary = Fill._expand(raw)
	assert_int((spec["parts"] as Array).size()).is_equal(1)
	assert_str(String((spec["parts"] as Array)[0][0])).contains("keg_big")


func test_fill_expand_filters_dropped_parts() -> void:
	var Fill := preload("res://scripts/world/region1_fill.gd")
	var raw := {"search": {}, "clear": 4, "parts": [["free:castle/tower_pink_flag@10.0", 0, 0, 0, 1, 0], ["free:fences/fence_picket_low@0.76", 1, 0, 0, 0, 0]]}
	var spec: Dictionary = Fill._expand(raw)
	assert_int((spec["parts"] as Array).size()).is_equal(1)
	assert_str(String((spec["parts"] as Array)[0][0])).contains("fence_picket_low")


func test_treated_material_is_a_matte_desaturated_copy() -> void:
	var StyleG := preload("res://scripts/style_g.gd")
	var src := StandardMaterial3D.new()
	src.albedo_color = Color(0.9, 0.3, 0.5)
	var base := StyleG.material_for("house", src, 1, "high", true)
	assert_object(base).is_not_null()
	var t := FillStyle.treated(base, {"saturation": 0.5, "roughness": 0.9})
	assert_object(t).is_not_null()
	assert_bool(t == base).is_false()
	assert_float(float(t.get_shader_parameter("saturation"))).is_equal(0.5)
	assert_float(float(t.get_shader_parameter("roughness"))).is_equal(0.9)
	assert_bool(StyleG.is_styled(t)).is_true()
	assert_object(FillStyle.treated(src, {"saturation": 0.5})).is_null()      # not a Style G material: left alone
