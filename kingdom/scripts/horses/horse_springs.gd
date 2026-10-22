class_name HorseSprings
extends RefCounted
## Runtime secondary motion for the horse with Godot's SpringBoneSimulator3D (the clips already carry a baked spring
## pass; the simulator adds the reaction to the REAL movement: turns, stops, jumps, blends).
##   LOW (0):  none (baked motion only)
##   MED (1):  tail chain (5 joints)
##   HIGH (2): tail + 5 mane tufts + forelock + belly jiggle
## The simulator pulls every joint back toward the animated pose (stiffness), so baked and simulated motion add up.
## Cost measured in tools_qa/horses (docs/anim/horses/HANDOFF.md, "Performance").

const TAIL := ["tail_1", "tail_5"]
const MANE := [["mane_0_a", "mane_0_b"], ["mane_1_a", "mane_1_b"], ["mane_2_a", "mane_2_b"], ["mane_3_a", "mane_3_b"],
	["mane_4_a", "mane_4_b"], ["mane_5_a", "mane_5_b"]]


static func setup(skeleton: Skeleton3D, tier: int) -> Array[SpringBoneSimulator3D]:
	var out: Array[SpringBoneSimulator3D] = []
	if tier <= 0 or skeleton == null:
		return out
	var sim := SpringBoneSimulator3D.new()
	sim.name = "HorseSprings"
	var chains: Array = [[TAIL[0], TAIL[1], 0.55, 0.35, 0.4, 0.045]]
	if tier >= 2:
		for m: Array in MANE:
			chains.append([m[0], m[1], 2.6, 0.7, 0.4, 0.02])
		chains.append(["belly", "belly", 4.0, 0.8, 0.0, 0.0])
	sim.setting_count = chains.size()
	for i in chains.size():
		var c: Array = chains[i]
		sim.set_root_bone_name(i, c[0])
		sim.set_end_bone_name(i, c[1])
		sim.set_extend_end_bone(i, true)
		sim.set_end_bone_length(i, 0.12 if c[0] != "belly" else 0.2)
		sim.set_stiffness(i, c[2])
		sim.set_drag(i, c[3])
		sim.set_gravity(i, c[4])
		sim.set_radius(i, c[5])
	skeleton.add_child(sim)
	out.append(sim)
	return out
