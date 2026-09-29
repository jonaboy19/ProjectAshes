extends SceneTree
## Loads the locomotion library the way the game does and checks names, lengths, loops and that every track resolves on the UAL skeleton.
## godot --headless --path kingdom -s tools/anim/loco/verify_loco.gd
const LIB := "res://assets/incoming/animations_free2/loco_transitions/UAL_Loco_Transitions.glb"
const EXPECT := ["Loco_WalkStart_F", "Loco_RunStart_F", "Loco_RunStop_L", "Loco_RunStop_R", "Loco_WalkStop", "Loco_Sprint_Stop_Skid",
	"Loco_TurnInPlace_90_L", "Loco_TurnInPlace_90_R", "Loco_TurnInPlace_180", "Loco_TurnInPlace_180_R", "Loco_Pivot180_Run_L",
	"Loco_Pivot180_Run_R", "Jump_Start", "Jump_Rise", "Jump_Fall", "Jump_Land_Soft", "Jump_Land_Hard", "Jump_Land_Roll",
	"Jump_Running_Start", "Jump_Land_Running"]


func _init() -> void:
	var bad := 0
	var scene: PackedScene = load(LIB)
	if scene == null:
		print("LOCOVERIFY FAIL: cannot load ", LIB)
		quit(1)
		return
	var inst := scene.instantiate()
	var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
	var sk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	print("bones ", sk.get_bone_count(), " clips ", ap.get_animation_list().size())
	for n in EXPECT:
		if not ap.has_animation(n):
			print("MISSING ", n)
			bad += 1
			continue
		var a := ap.get_animation(n)
		var unresolved := 0
		for t in a.get_track_count():
			var p := String(a.track_get_path(t))
			var c := p.find(":")
			if c > 0 and sk.find_bone(p.substr(c + 1)) < 0:
				unresolved += 1
		var loops := a.loop_mode != Animation.LOOP_NONE
		var want_loop: bool = (n == "Jump_Rise" or n == "Jump_Fall")
		if loops != want_loop or unresolved > 0:
			bad += 1
		print("%-24s %.3fs tracks %d loop %s unresolved %d" % [n, a.length, a.get_track_count(), loops, unresolved])
	print("LOCOVERIFY ", "OK" if bad == 0 else "FAIL %d" % bad)
	inst.free()
	quit(1 if bad else 0)
