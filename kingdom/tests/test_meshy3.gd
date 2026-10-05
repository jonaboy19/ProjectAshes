extends GdUnitTestSuite
## Meshy batch 3 (assets/incoming/meshy_dl3, docs/art/meshy_dl3/README.md "Triage"): every placed model loads, stands on the ground
## (origin at its base, yaw-only placement settles on the lowest footprint ground), is not a reject, and the rejects ship nowhere.
## Looks: the re-rigged bipeds are on the UAL skeleton and play the game's clip names.

const FillStyle := preload("res://scripts/world/fill_style.gd")
const Props := preload("res://scripts/world/thornfield/wilds_props.gd")
const SITES := "res://data/region1/world/meshy3_sites.json"
const WILDS := "res://data/region1/world/thornfield_wilds.json"
const ROOT := "res://assets/incoming/meshy_dl3/"
const LOOK_FILES := ["guardian_hooded", "knight_plate_a", "merchant_cloaked", "peasant_hooded", "villager_green_vest", "villager_hat", "villager_white_shirt"]


func before() -> void:
	WorldGen.setup(1066)


## "dl3:cat/name@H" keys of every placement: [key, source].
func _placements() -> Array:
	var out: Array = []
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SITES))
	for site: Dictionary in d["sites"]:
		for part: Array in site["parts"]:
			if String(part[0]).begins_with("dl3:"):
				out.append([String(part[0]), String(site["id"])])
	var w: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WILDS))
	for host: String in ["outpost", "bandit_camp", "rift"]:
		for e: Array in (w[host] as Dictionary).get("extras", []):
			out.append([String(e[0]), host])
	return out


func _placed_models() -> Dictionary:
	var m := {}
	for p: Array in _placements():
		m[FillStyle.model_of(String(p[0]))] = true
	return m


## "dl3/cat/name" for every optimized LOD0 under meshy_dl3 (the characters_ual rerigs are looks, not models).
func _all_models() -> Array:
	var out: Array = []
	for dir: String in DirAccess.get_directories_at(ROOT):
		if dir == "characters_ual":
			continue
		for f: String in DirAccess.get_files_at(ROOT + dir):
			if f.ends_with("_lod0.glb"):
				out.append("dl3/%s/%s" % [dir, f.trim_suffix("_lod0.glb")])
	return out


func _exclude_filter() -> String:
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	for line in cfg.split("\n"):
		if line.begins_with("exclude_filter="):
			return line
	return ""


func test_placements_exist_and_are_not_rejects() -> void:
	assert_int(_placements().size()).is_greater(40)
	for p: Array in _placements():
		var m := FillStyle.model_of(String(p[0]))
		assert_bool(FillStyle.is_dropped(m)).override_failure_message("%s places a reject: %s" % [p[1], m]).is_false()
		assert_bool(FillStyle.DL3_UNPLACED.has(m)).override_failure_message("%s places an unplaced-listed model: %s" % [p[1], m]).is_false()
		assert_bool(ResourceLoader.exists(FillStyle.dl3_path(m, 0))).override_failure_message("missing " + m).is_true()
		if m.begins_with("dl3/buildings/") or m.begins_with("dl3/castle/"):
			assert_bool(ResourceLoader.exists(FillStyle.dl3_path(m, 1))).override_failure_message("no LOD1 for " + m).is_true()


func test_every_model_is_classified_once() -> void:
	var placed := _placed_models()
	for m: String in _all_models():
		var classes := 0
		classes += 1 if placed.has(m) else 0
		classes += 1 if FillStyle.DL3_REJECT.has(m) else 0
		classes += 1 if FillStyle.DL3_UNPLACED.has(m) else 0
		if m.begins_with("dl3/characters_rigged/"):         # Mixamo-skeleton originals: re-rigged to UAL (a look) or rejected
			var nm := m.get_file()
			classes = 1 if (FileAccess.file_exists("%scharacters_ual/%s.glb" % [ROOT, nm]) or FillStyle.DL3_REJECT.has(m)) else 0
		assert_int(classes).override_failure_message("%s: placed/reject/unplaced/rerigged must be exactly one (got %d)" % [m, classes]).is_equal(1)


func test_placed_models_are_grounded_and_sized() -> void:
	for m: String in _placed_models():
		var n := Assets.static_model(FillStyle.dl3_path(m, 0))
		assert_object(n).override_failure_message("no model " + m).is_not_null()
		var box := Assets.visual_aabb(n)
		assert_float(box.position.y).override_failure_message("%s base not at the origin (minY %.3f)" % [m, box.position.y]).is_between(-0.08, 0.08)
		assert_float(box.size.y).override_failure_message("%s degenerate height" % m).is_greater(0.3)
		var tris := 0
		for mi: Node in n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else []):
			if (mi as MeshInstance3D).mesh != null:
				tris += (mi as MeshInstance3D).mesh.get_faces().size() / 3
		assert_int(tris).override_failure_message("%s too heavy (%d tris)" % [m, tris]).is_less(15500)
		n.free()


func test_declared_heights_match_the_models() -> void:
	for p: Array in _placements():
		var spec := String(p[0]).split("@")
		var m := FillStyle.model_of(String(p[0]))
		if spec.size() < 2:
			continue
		var n := Assets.static_model(FillStyle.dl3_path(m, 0))
		var h := Assets.visual_aabb(n).size.y
		n.free()
		assert_float(float(spec[1])).override_failure_message("%s: @%s but the model is %.2f m" % [m, spec[1], h]).is_between(h * 0.85, h * 1.15)


func test_props_model_sits_on_the_lowest_ground() -> void:
	var parent := auto_free(Node3D.new()) as Node3D
	add_child(parent)
	for at: Vector2 in [Vector2(120, 80), Vector2(-300, 210), Vector2(40, -500)]:
		var n := Props.model(parent, "dl3:props/keg_big@1.1", at, 0.7)
		assert_object(n).is_not_null()
		var bottom := n.global_position.y
		var centre := WorldGen.height(at.x, at.y)
		assert_float(bottom).override_failure_message("keg floats at %s: %.2f vs ground %.2f" % [at, bottom, centre]).is_less_equal(centre + 0.001)
		assert_float(centre - bottom).override_failure_message("keg sunk at %s" % at).is_less(2.0)
		assert_float(n.global_transform.basis.y.dot(Vector3.UP)).is_greater(0.999)         # upright: yaw only
	assert_object(Props.model(parent, "dl3:props/no_such_model", Vector2.ZERO)).is_null()


func test_wilds_extras_are_in_the_data() -> void:
	var w: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WILDS))
	assert_int((w["outpost"]["extras"] as Array).size()).is_greater(5)
	assert_int((w["bandit_camp"]["extras"] as Array).size()).is_greater(2)
	assert_int((w["rift"]["extras"] as Array).size()).is_greater(0)
	for host: String in ["outpost", "bandit_camp", "rift"]:
		for e: Array in w[host]["extras"]:
			assert_bool(String(e[0]).begins_with("dl3:")).is_true()
			assert_int((e as Array).size()).is_greater_equal(5)


func test_thornfield_yards_are_planned_off_the_roads() -> void:
	var seen := {}
	for s in WorldGen.sites:
		var id := String(s.get("fill_id", ""))
		if id.begins_with("m3_"):
			seen[id] = true
			var p: Vector2 = s["pos"]
			assert_bool(WorldGen.is_water(p.x, p.y)).override_failure_message(id + " in water").is_false()
			assert_float(WorldGen.road_distance(p.x, p.y)).override_failure_message(id + " on a road").is_greater(float(s["clear"]))
	for id in ["m3_thornfield_lane", "m3_thornfield_carters", "m3_thornfield_wayhouse"]:
		assert_bool(seen.has(id)).override_failure_message("not planned: " + id).is_true()


func test_rejects_and_unplaced_do_not_ship_placed_do() -> void:
	var ex := _exclude_filter()
	assert_str(ex).is_not_empty()
	for m: String in FillStyle.DL3_REJECT + FillStyle.DL3_UNPLACED:
		assert_bool(ex.contains(FillStyle.dl3_path(m, 0))).override_failure_message("not excluded: " + m).is_true()
	for m: String in _placed_models():
		assert_bool(ex.contains(FillStyle.dl3_path(m, 0))).override_failure_message("placed but excluded from the export: " + m).is_false()
	assert_bool(ex.contains("meshy_dl3/characters_ual")).override_failure_message("rerigged looks must ship").is_false()
	assert_bool(ex.contains("meshy_dl3/characters_rigged/villager_hat_lod0.glb")).override_failure_message("Mixamo originals are dead weight").is_true()


func test_credits_cover_the_batch() -> void:
	var credits := FileAccess.get_file_as_string("res://CREDITS.md")
	assert_str(credits).contains("meshy_dl3")
	assert_str(credits).contains("characters_ual")
	assert_bool(FileAccess.file_exists("res://assets/incoming/meshy_dl3/CREDITS.md")).is_true()


func test_rigged_looks_are_on_the_ual_skeleton() -> void:
	for look: String in ["Meshy_Villager", "Meshy_Traveller", "Meshy_Knight"]:
		assert_bool(Assets.MH_LOOKS.has(look)).override_failure_message("no look " + look).is_true()
	for nm: String in LOOK_FILES:
		var path := "%scharacters_ual/%s.glb" % [ROOT, nm]
		assert_bool(ResourceLoader.exists(path)).override_failure_message("missing " + path).is_true()
		assert_bool(ResourceLoader.exists("%scharacters_ual/%s_lod1.glb" % [ROOT, nm])).is_true()
		var n: Node3D = Assets.mh_character(Assets.MESHY3 + nm, 1.75)
		add_child(n)
		var sk := n.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		# 65 UAL bones; the glTF exporter may add one "neutral_bone" for a few stray unweighted vertices (merchant_cloaked: 22 of 8.7k)
		assert_int(sk.get_bone_count()).override_failure_message(nm + " bones").is_between(65, 66)
		for bone in ["pelvis", "Head", "hand_r", "hand_l", "foot_l"]:
			assert_int(sk.find_bone(bone)).override_failure_message("%s lacks bone %s" % [nm, bone]).is_greater_equal(0)
		var head := sk.get_bone_global_rest(sk.find_bone("Head")).origin.y
		assert_float(head).override_failure_message("%s head rest y %.3f" % [nm, head]).is_between(1.5, 1.65)
		var ap := Assets.animation_player(n)
		assert_object(ap).is_not_null()
		for clip in ["Walk", "Idle", "Sword_Regular_A", "Death01"]:
			assert_bool(ap.has_animation(clip)).override_failure_message("%s lacks clip %s" % [nm, clip]).is_true()
		n.queue_free()
	# the look pickers hand out real nodes (merged NPC body path)
	for look: String in ["Meshy_Villager", "Meshy_Traveller", "Meshy_Knight", "Bandit", "Trader"]:
		for i in 6:
			var c: Node3D = Assets.character(look, 1.72, [])
			assert_object(c).override_failure_message(look).is_not_null()
			assert_bool(c.find_children("*", "MeshInstance3D", true, false).size() > 0).is_true()
			c.free()
