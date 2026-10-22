extends GdUnitTestSuite
## LOW-tier gating of the cloud-added decorative content (scripts/world/low_budget.gd, docs/LOCAL_SESSION_HANDOFF.md "Cloud LOW budget audit"):
## fence sections are proxied, heavy loose clutter is thinned, wilds extras use LOD1 or are left out, re-rigged Meshy looks use LOD1,
## gameplay objects (colliders) are never touched, nothing changes off LOW, and the Style G treatment shares materials between instances.

const LowBudget := preload("res://scripts/world/low_budget.gd")
const FillStyle := preload("res://scripts/world/fill_style.gd")
const Props := preload("res://scripts/world/thornfield/wilds_props.gd")
const FILL := "res://data/region1/world/fill_sites.json"
const MESHY3 := "res://data/region1/world/meshy3_sites.json"
const WILDS := "res://data/region1/world/thornfield_wilds.json"
const REGION := "res://assets/generated/region/"
## LOW: no single fill / Meshy3 yard may put more than this many LOD0 triangles in a baked mesh (all tiers: the worst yard is ~90k).
const LOW_SITE_TRIS := 60000
## LOW: the whole fill + Meshy3 set must shrink by at least this share.
const LOW_MIN_CUT := 0.20


func before() -> void:
	WorldGen.setup(1066)


func after_test() -> void:
	LowBudget.force_low = -1


func _sites() -> Array:
	var out: Array = []
	for f: String in [FILL, MESHY3]:
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(f))
		for s: Dictionary in d["sites"]:
			s["fill"] = true
			out.append(s)
	return out


func test_tris_table_covers_every_placed_model() -> void:
	for s: Dictionary in _sites():
		for part: Array in s["parts"]:
			var m := FillStyle.model_of(String(part[0]))
			if FillStyle.is_dropped(m):
				continue
			assert_int(int(LowBudget.model_tris(m)[0])).override_failure_message("model_tris.json lacks " + m).is_greater(0)
	var w: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WILDS))
	for host: String in ["outpost", "bandit_camp", "rift"]:
		for e: Array in (w[host] as Dictionary).get("extras", []):
			var m := FillStyle.model_of(String(e[0]))
			assert_int(int(LowBudget.model_tris(m)[0])).override_failure_message("model_tris.json lacks " + m).is_greater(0)


func test_nothing_changes_off_low() -> void:
	LowBudget.force_low = 0
	for s: Dictionary in _sites():
		for part: Array in s["parts"]:
			assert_bool(LowBudget.skip_part(s, part)).is_false()
			assert_bool(LowBudget.proxy_for(String(part[0])).is_empty()).is_true()
	assert_bool(LowBudget.skip_extra("dl3/market/stall_rug_wood", 2.65)).is_false()
	assert_int(LowBudget.dl3_lod("dl3/creatures/horse_saddled_brown")).is_equal(0)
	assert_float(LowBudget.lod_distance(55.0)).is_equal(55.0)


func test_low_shrinks_the_fill_and_meshy3_yards() -> void:
	var all := 0
	var low := 0
	var worst := 0
	var worst_id := ""
	for s: Dictionary in _sites():
		all += LowBudget.site_tris(s, false)
		var t := LowBudget.site_tris(s, true)
		low += t
		if t > worst:
			worst = t
			worst_id = String(s["id"])
		assert_int(t).override_failure_message("%s: %d LOD0 tris on LOW" % [s["id"], t]).is_less_equal(LOW_SITE_TRIS)
	assert_float(float(low) / float(all)).override_failure_message("LOW %d of %d tris (worst %s %d)" % [low, all, worst_id, worst]).is_less(1.0 - LOW_MIN_CUT)
	print("LOWBUDGET fill+meshy3 tris all=%d low=%d worst=%s %d" % [all, low, worst_id, worst])


func test_fences_are_proxied_with_generated_pieces_that_exist() -> void:
	LowBudget.force_low = 1
	var n := 0
	for s: Dictionary in _sites():
		for part: Array in s["parts"]:
			var px := LowBudget.proxy_for(String(part[0]))
			if px.is_empty():
				continue
			n += 1
			assert_bool(FillStyle.model_of(String(part[0])).begins_with("fences/")).is_true()
			assert_bool(ResourceLoader.exists(REGION + String(px["path"]) + ".glb")).override_failure_message(String(px["path"])).is_true()
			assert_float(float(px["length"])).is_between(1.5, 3.0)
	assert_int(n).is_greater(100)         # 150+ fence sections across the yards


func test_colliders_and_non_clutter_are_never_skipped() -> void:
	LowBudget.force_low = 1
	for s: Dictionary in _sites():
		for part: Array in s["parts"]:
			if int(part[3]) != 0:
				assert_bool(LowBudget.skip_part(s, part)).override_failure_message("%s: collider part skipped: %s" % [s["id"], part[0]]).is_false()
	# a site that is not a fill / Meshy3 site is never thinned
	var plain := {"parts": [["free:flora/bouquet_wild@0.5", 0, 0, 0, 0], ["free:flora/bouquet_wild@0.5", 1, 0, 0, 0]]}
	for part: Array in plain["parts"]:
		assert_bool(LowBudget.skip_part(plain, part)).is_false()


func test_thinning_keeps_one_in_n() -> void:
	LowBudget.force_low = 1
	var s := {"fill": true, "parts": []}
	for i in 6:
		(s["parts"] as Array).append(["free:flora/bouquet_wild@0.5", float(i), 0.0, 0.0, 0, 0])
	var kept := 0
	for part: Array in s["parts"]:
		if not LowBudget.skip_part(s, part):
			kept += 1
	assert_int(kept).is_equal(2)           # THIN bouquets: 1 in 3


func test_wilds_extras_use_lod1_or_are_left_out_on_low() -> void:
	LowBudget.force_low = 1
	assert_int(LowBudget.dl3_lod("dl3/creatures/horse_saddled_brown")).is_equal(1)
	assert_bool(LowBudget.skip_extra("dl3/market/stall_rug_wood", 2.65)).is_true()            # 4.5k tris, no LOD1
	assert_bool(LowBudget.skip_extra("dl3/creatures/horse_saddled_brown", 2.19)).is_false()   # has a LOD1
	assert_bool(LowBudget.skip_extra("dl3/props/chest_iron_banded", 0.0)).is_false()          # no declared height: never left out
	var parent := auto_free(Node3D.new()) as Node3D
	add_child(parent)
	assert_object(Props.model(parent, "dl3:market/stall_rug_wood@2.65", Vector2(120, 80))).is_null()
	var horse := Props.model(parent, "dl3:creatures/horse_saddled_brown@2.19", Vector2(130, 80))
	assert_object(horse).is_not_null()
	var tris := 0
	for mi: Node in horse.find_children("*", "MeshInstance3D", true, false):
		assert_int((mi as MeshInstance3D).cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)      # small extra: no sun shadow
		tris += (mi as MeshInstance3D).mesh.get_faces().size() / 3
	assert_int(tris).override_failure_message("horse %d tris on LOW" % tris).is_less(2500)


func test_rerigged_meshy_looks_use_lod1_on_low() -> void:
	LowBudget.force_low = 1
	var n := Assets.character("Meshy_Traveller", 1.74, [])
	assert_object(n).is_not_null()
	var tris := 0
	for mi: Node in n.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh != null:
			tris += (mi as MeshInstance3D).mesh.get_faces().size() / 3
	n.free()
	assert_int(tris).override_failure_message("re-rigged look %d tris on LOW (LOD1 is ~2.9k, the UAL villager 6.8k)" % tris).is_less(3500)


func test_fill_style_shares_materials_between_instances() -> void:
	var path := FillStyle.dl3_path("dl3/buildings/cottage_blue_roof", 0)
	var a := Assets.static_model(path)
	var b := Assets.static_model(path)
	var n_a := FillStyle.apply(a, "dl3:buildings/cottage_blue_roof@5")
	var n_b := FillStyle.apply(b, "dl3:buildings/cottage_blue_roof@5")
	assert_int(n_a).is_greater(0)
	assert_int(n_b).is_equal(n_a)
	var ma: Array = []
	var mb: Array = []
	for mi: Node in a.find_children("*", "MeshInstance3D", true, false) + ([a] if a is MeshInstance3D else []):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			ma.append((mi as MeshInstance3D).get_surface_override_material(i))
	for mi: Node in b.find_children("*", "MeshInstance3D", true, false) + ([b] if b is MeshInstance3D else []):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			mb.append((mi as MeshInstance3D).get_surface_override_material(i))
	assert_int(ma.size()).is_equal(mb.size())
	for i in ma.size():
		assert_bool(ma[i] == mb[i]).override_failure_message("surface %d: per-instance material copy" % i).is_true()
	a.free()
	b.free()


func test_squad_shields_are_left_off_on_low_only() -> void:
	var keep: Array[String] = ["Knight_Helmet", "1H_Sword", "Round_Shield"]
	LowBudget.force_low = 1
	assert_array(LowBudget.gear(keep)).contains_exactly(["Knight_Helmet", "1H_Sword"])
	LowBudget.force_low = 0
	assert_array(LowBudget.gear(keep)).contains_exactly(keep)
