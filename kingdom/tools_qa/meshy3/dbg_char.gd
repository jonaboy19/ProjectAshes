extends SceneTree
func _initialize() -> void:
	for nm in ["guardian_hooded","knight_plate_a","merchant_cloaked","peasant_hooded","villager_green_vest","villager_hat","villager_white_shirt"]:
		var n: Node3D = Assets.mh_character("res://assets/incoming/meshy_dl3/characters_ual/" + nm, 1.75)
		var sk := n.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		print("BONES ", nm, " ", sk.get_bone_count(), " head ", sk.get_bone_global_rest(sk.find_bone("Head")).origin.y)
	quit()
