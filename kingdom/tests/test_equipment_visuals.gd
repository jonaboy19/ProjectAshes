extends GdUnitTestSuite
## Equipment.changed -> item models on the skeleton bones (scripts/actors/equipment_visuals.gd): equip adds the
## BoneAttachment3D(s) named by data/items/visuals.json, unequip / swapping removes them, starter gear on the same bone makes way.

const Equipment := preload("res://scripts/sim/equipment.gd")
const EquipmentVisuals := preload("res://scripts/actors/equipment_visuals.gd")
const BONE_NAMES := ["pelvis", "spine_03", "Head", "lowerarm_l", "hand_l", "hand_r", "calf_l", "calf_r", "foot_l", "foot_r"]


func _skeleton() -> Skeleton3D:
	var root := Node3D.new()
	var sk := Skeleton3D.new()
	root.add_child(sk)
	for b in BONE_NAMES:
		sk.add_bone(b)
	add_child(root)
	auto_free(root)
	return sk


func _rig() -> Array:
	var sk := _skeleton()
	var eq := Equipment.new()
	var vis := EquipmentVisuals.new(sk, eq)
	return [sk, eq, vis]


func _eq_nodes(sk: Skeleton3D) -> Array:
	var out := []
	for c in sk.get_children():
		if String(c.name).begins_with("Eq_"):
			out.append(c)
	return out


func test_weapon_attaches_to_the_hand_and_unequip_removes_it() -> void:
	var r := _rig()
	var sk: Skeleton3D = r[0]
	var eq: Equipment = r[1]
	var vis = r[2]
	assert_int(_eq_nodes(sk).size()).is_equal(0)
	eq.equip("steel_sword")
	var nodes := _eq_nodes(sk)
	assert_int(nodes.size()).is_equal(1)
	assert_str((nodes[0] as BoneAttachment3D).bone_name).is_equal("hand_r")
	assert_object((nodes[0] as Node).get_child(0)).is_not_null()      # the item's model
	assert_int(vis.attachment_count()).is_equal(1)
	eq.unequip("main_hand")
	assert_int(_eq_nodes(sk).size()).is_equal(0)
	assert_int(vis.attachment_count()).is_equal(0)


func test_swapping_replaces_and_each_slot_has_its_own_bone() -> void:
	var r := _rig()
	var sk: Skeleton3D = r[0]
	var eq: Equipment = r[1]
	eq.equip("steel_sword")
	eq.equip("bronze_sword")                 # same slot: the old model goes
	assert_int(_eq_nodes(sk).size()).is_equal(1)
	eq.equip("wooden_shield")
	eq.equip("iron_helm")
	var bones := []
	for n in _eq_nodes(sk):
		bones.append((n as BoneAttachment3D).bone_name)
	bones.sort()
	assert_array(bones).is_equal(["Head", "hand_r", "lowerarm_l"])     # "head" resolves to the rig's "Head"
	eq.unequip("off_hand")
	assert_int(_eq_nodes(sk).size()).is_equal(2)


func test_pairs_get_both_sides_and_chest_uses_the_spine() -> void:
	var r := _rig()
	var sk: Skeleton3D = r[0]
	var eq: Equipment = r[1]
	eq.equip("hide_boots")
	var feet := []
	for n in _eq_nodes(sk):
		feet.append((n as BoneAttachment3D).bone_name)
	feet.sort()
	assert_array(feet).is_equal(["foot_l", "foot_r"])
	eq.equip("hardened_cuirass")
	assert_int(_eq_nodes(sk).size()).is_equal(3)
	eq.unequip("feet")
	eq.unequip("body")
	assert_int(_eq_nodes(sk).size()).is_equal(0)


func test_starter_gear_is_hidden_while_the_real_item_is_worn() -> void:
	var sk := _skeleton()
	var starter := BoneAttachment3D.new()
	starter.bone_name = "hand_r"
	sk.add_child(starter)
	var eq := Equipment.new()
	var vis := EquipmentVisuals.new(sk, eq)
	eq.equip("steel_sword")
	assert_bool(starter.visible).is_false()
	eq.unequip("main_hand")
	assert_bool(starter.visible).is_true()
	assert_object(vis).is_not_null()


func test_existing_gear_is_shown_at_creation_and_detach_cleans_up() -> void:
	var sk := _skeleton()
	var eq := Equipment.new()
	eq.equip("iron_helm")                    # worn before the body exists (a loaded save)
	var vis := EquipmentVisuals.new(sk, eq)
	assert_int(_eq_nodes(sk).size()).is_equal(1)
	vis.detach()
	assert_int(_eq_nodes(sk).size()).is_equal(0)
	eq.equip("steel_sword")                  # detached: no longer listens
	assert_int(_eq_nodes(sk).size()).is_equal(0)


func test_items_without_a_model_add_nothing() -> void:
	var r := _rig()
	var sk: Skeleton3D = r[0]
	var eq: Equipment = r[1]
	var ring := ""
	for id: String in ["bronze_ring", "copper_ring", "silver_ring"]:
		if Equipment.slot_of(id) == "ring":
			ring = id
			break
	if ring != "":
		eq.equip(ring)
	assert_int(_eq_nodes(sk).size()).is_equal(0)
