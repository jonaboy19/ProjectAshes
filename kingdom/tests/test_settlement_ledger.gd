extends GdUnitTestSuite
## Settlement ledger (Realm > Land "Your settlements"): rows for the player's foundings only, next-scale needs, progress, actions.

const Ledger := preload("res://scripts/realm/settlement_ledger.gd")
const Founding := preload("res://scripts/realm/founding.gd")
const Unify := preload("res://tests/test_v1_settlement_unify.gd")


func test_row_from_info_progress_and_needs() -> void:
	var info := {"name": "Newhold", "scale": "camp", "stage_words": "Surviving", "next": ["no finished water yet"],
		"facts": {"pop": 3, "services": 2, "infra": 0}, "services": ["shelter", "storage"], "problems": [{"words": "Food is short"}]}
	var r := Ledger.row_from_info(4, info, 0, 2, false)
	assert_str(String(r["next_scale"])).is_equal("hamlet")
	assert_int(int(r["pop_need"])).is_equal(Founding.SCALE_POP[1])
	assert_float(float(r["progress"])).is_equal_approx(minf(3.0 / Founding.SCALE_POP[1], 2.0 / Founding.SCALE_SERVICES[1]), 0.001)
	assert_array(r["blockers"]).contains(["no finished water yet"])
	assert_array(r["problems"]).contains(["Food is short"])
	assert_array(r["actions"]).is_empty()


func test_actions_by_stage() -> void:
	assert_array(Ledger.row_from_info(1, {}, 2, 6, false)["actions"]).contains(["appoint"])
	assert_array(Ledger.row_from_info(1, {}, 2, 7, false)["actions"]).contains(["petition"])
	assert_array(Ledger.row_from_info(1, {}, 2, 7, true)["actions"]).is_empty()


func test_top_scale_has_no_next() -> void:
	var r := Ledger.row_from_info(1, {"facts": {"pop": 999, "services": 9, "infra": 9}}, Founding.SCALES.size() - 1, 7, true)
	assert_str(String(r["next_scale"])).is_equal("")
	assert_float(float(r["progress"])).is_equal(1.0)


func test_rows_list_only_player_foundings() -> void:
	var u: Node = auto_free(Unify.new())
	var hub: RefCounted = u._mk()
	var spots: Array = u._spots(hub, 1)
	var r: Dictionary = hub.mod("build_kit").claim(u._w(spots[0]), "squat", "Newhold")
	assert_bool(bool(r["ok"])).is_true()
	var rows := Ledger.rows(hub.mod("founding"))
	assert_int(rows.size()).is_equal(1)
	assert_str(String(rows[0]["name"])).is_equal("Newhold")
	assert_str(String(rows[0]["scale"])).is_equal("camp")
	assert_bool(rows[0]["service_list"] is Array).is_true()


func test_realm_tab_script_compiles() -> void:
	var s: GDScript = load("res://scripts/ui/gamemenu/tab_realm.gd")
	assert_object(s).is_not_null()
	assert_bool(s.can_instantiate()).is_true()


func test_petition_verdict() -> void:
	assert_bool(Founding.petition_verdict(2, 2, 0)).is_true()
	assert_bool(Founding.petition_verdict(1, 3, 0)).is_false()
	assert_bool(Founding.petition_verdict(3, 1, 0)).is_false()
	assert_bool(Founding.petition_verdict(3, 3, 5)).is_false()


func test_touched_ui_scripts_compile() -> void:
	for p: String in ["res://scripts/ui/world_map.gd", "res://scripts/actors/camera_occluders.gd"]:
		var s: GDScript = load(p)
		assert_bool(s != null and s.can_instantiate()).override_failure_message(p).is_true()


func test_occluders_never_fade_the_talk_partner() -> void:
	var Occ := preload("res://scripts/actors/camera_occluders.gd")
	var o: Node = auto_free(Occ.new())
	var hero := Node3D.new()
	hero.set_script(null)
	var partner := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	partner.add_child(mi)
	add_child(partner)
	auto_free(partner)
	auto_free(hero)
	var host := _Host.new()
	auto_free(host)
	host._talk_partner = partner
	o.ignore_root = host
	assert_bool(o._fadeable(mi, Vector3(100, 0, 0))).is_false()
	host._talk_partner = null
	assert_bool(o._fadeable(mi, Vector3(100, 0, 0))).is_true()


class _Host extends Node3D:
	var _talk_partner: Node = null
