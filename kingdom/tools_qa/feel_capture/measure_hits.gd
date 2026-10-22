extends Node
## Measures the strike frame of attack clips on the in-game player rig: the time the
## weapon hand moves fastest (the blade passes through its arc) and the time of its
## furthest forward reach. Used to line up damage, hitstop and slash VFX with the
## blade (docs/anim/FEEL_AUDIT.md). Headless is fine (no rendering needed):
##   Godot --headless --path kingdom res://tools_qa/feel_capture/measure_hits.tscn -- --clips=A,B
const DEFAULT := ["1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice_Diagonal",
	"1H_Melee_Attack_Slice_Horizontal", "1H_Melee_Attack_Stab", "Block_Hit", "Hit_A"]
const RATE := 120.0


func _ready() -> void:
	var clips: Array = DEFAULT
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clips="):
			clips = Array(a.substr(8).split(","))
	var body: Node3D = Assets.character("Player", 1.8, ["1H_Sword", "Round_Shield"])
	add_child(body)
	var ap := Assets.animation_player(body)
	var sk: Skeleton3D = body.find_children("*", "Skeleton3D", true, false)[0]
	var hand := sk.find_bone("hand_r")
	if hand < 0:
		hand = sk.find_bone("Hand_R")
	var chest := sk.find_bone("spine_03")
	for c: String in clips:
		if not ap.has_animation(c):
			print("MEASURE %s missing" % c)
			continue
		var anim := ap.get_animation(c)
		ap.play(c)
		var n := int(anim.length * RATE)
		var prev := Vector3.INF
		var best_v := 0.0
		var best_t := 0.0
		var reach_t := 0.0
		var reach := -INF
		for i in n + 1:
			var t := i / RATE
			ap.seek(t, true)
			sk.force_update_all_bone_transforms()
			var p := sk.get_bone_global_pose(hand).origin
			var ch := sk.get_bone_global_pose(chest).origin
			var fwd := (p - ch).z          # rig forward is +Z
			if fwd > reach:
				reach = fwd
				reach_t = t
			if prev != Vector3.INF:
				var v := (p - prev).length() * RATE
				if v > best_v:
					best_v = v
					best_t = t
			prev = p
		print("MEASURE %s len=%.3f peak_speed_t=%.3f (%.1f m/s) max_reach_t=%.3f" % [c, anim.length, best_t, best_v, reach_t])
	get_tree().quit()
