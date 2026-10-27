extends SceneTree
## Bakes data/anim/clip_lift.json (scripts/actors/clip_lift.gd): for each clip, plays it raw on the adult player body (animation
## tree, foot IK and springs off, the clip's current lift NOT applied), CPU-skins the body every frame (30 fps), takes the lowest
## vertex below the ground plane and stores the pelvis offset that lifts it to the ground (+3 mm), max-filtered over +-3 frames
## and blurred so the lift eases in and out. Headless is fine:
##   godot --headless --path kingdom -s res://tools_qa/anim_states/clip_lift_bake.gd -- [--clips=A,B] [--dry]
const BASE := 600.0
const DEFAULT_CLIPS := ["Jump_Fall", "Jump_Land_Hard", "Jump_Land_Roll", "Jump_Land_Running", "Jump_Land_Soft", "Jump_Rise",
	"Jump_Running_Start", "Loco_Pivot180_Run_L", "Loco_Pivot180_Run_R", "Loco_RunStart_F", "Loco_TurnInPlace_180",
	"Loco_TurnInPlace_180_R", "Loco_TurnInPlace_90_L", "Souls_Roll", "Death01", "Hit_Knockback", "Slide"]
const FPS := 30.0
var MARGIN := 0.003

var _p: Node3D
var _sk: Skeleton3D
var _ap: AnimationPlayer


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var clips: Array = DEFAULT_CLIPS.duplicate()
	var dry := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clips="):
			clips = Array(a.substr(8).split(",", false))
		elif a.begins_with("--margin="):
			MARGIN = float(a.substr(9))
		elif a == "--dry":
			dry = true
	var r3 := Node3D.new()
	root.add_child(r3)
	_p = (load("res://scripts/actors/player.gd") as GDScript).new()
	r3.add_child(_p)
	_p.global_position = Vector3(0, BASE, 0)
	for i in 20:
		await physics_frame
	var life: Node = root.get_node("Life")
	life.life_path.set_age(16, root.get_node("WorldSim").day, root.get_node("WorldSim").time_of_day)
	_p.call("apply_age")
	for i in 10:
		await physics_frame
	_p.set_physics_process(false)
	var rig: Variant = _p.get("_rig")
	if rig is Object:
		(rig as Object).call("set_paused", true)
	_sk = _p.find_children("*", "Skeleton3D", true, false)[0]
	var an: Object = _p.get("_animator")
	_ap = an.get("player")
	var tree: Variant = an.get("tree")
	if tree is AnimationTree:
		(tree as AnimationTree).active = false
	var out := {}
	var existing := {}
	if FileAccess.file_exists("res://data/anim/clip_lift.json"):
		var ex: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/anim/clip_lift.json"))
		if ex is Dictionary:
			existing = (ex as Dictionary).get("clips", {})
	var pel := _sk.find_bone("pelvis")
	var ground := _p.global_position.y
	for clip: String in clips:
		if not _ap.has_animation(StringName(clip)):
			print("LIFT skip (missing) ", clip)
			continue
		var anim := _ap.get_animation(StringName(clip))
		if anim.has_meta(&"clip_lift"):
			print("LIFT note: ", clip, " already lifted in this library; measuring on top of it")
		var n := int(ceil(anim.length * FPS)) + 1
		var lifts := PackedFloat32Array()
		var worst := 0.0
		for f in n:
			var t := minf(float(f) / FPS, anim.length)
			_ap.play(StringName(clip))
			_ap.seek(t, true)
			_ap.pause()
			_sk.force_update_all_bone_transforms()
			var low := _lowest()
			var need := maxf(0.0, ground - low)
			worst = maxf(worst, need)
			lifts.append(need)
		# max filter +-3 frames, then a 5-tap blur
		var mx := PackedFloat32Array()
		for f in n:
			var m := 0.0
			for k in range(-3, 4):
				m = maxf(m, lifts[clampi(f + k, 0, n - 1)])
			mx.append(m)
		var deltas: Array = []
		var parent := _sk.get_bone_parent(pel)
		for f in n:
			var s := 0.0
			var wsum := 0.0
			for k in range(-2, 3):
				var w := 3.0 - absf(float(k))
				s += mx[clampi(f + k, 0, n - 1)] * w
				wsum += w
			var lift := s / wsum
			lift = lift + MARGIN if lift > 0.0005 else 0.0
			# world up -> pelvis track space (the pelvis parent's global rest basis, skeleton units)
			var up_skel := _sk.global_basis.inverse() * Vector3(0.0, lift, 0.0)
			var pb := _sk.get_bone_global_rest(parent).basis if parent >= 0 else Basis()
			var dv := pb.inverse() * up_skel
			deltas.append([snappedf(dv.x, 0.0001), snappedf(dv.y, 0.0001), snappedf(dv.z, 0.0001)])
		print("LIFT %s frames %d worst %.1f cm" % [clip, n, worst * 100.0])
		if worst > 0.002:
			out[clip] = {"bone": "pelvis", "fps": FPS, "worst_cm": snappedf(worst * 100.0, 0.1), "d": deltas}
	if dry:
		quit()
		return
	for k: String in existing:
		if not out.has(k) and not clips.has(k):
			out[k] = existing[k]
	var f := FileAccess.open("res://data/anim/clip_lift.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"_doc": "Pelvis lift per clip (scripts/actors/clip_lift.gd), baked by tools_qa/anim_states/clip_lift_bake.gd. Do not edit by hand.", "clips": out}))
	f.close()
	print("LIFT_DONE ", out.size())
	quit()


## Lowest skinned vertex (world y) of the visible skinned meshes, every 2nd vertex.
var _arrays := {}


func _lowest() -> float:
	var low := INF
	for mi: MeshInstance3D in _sk.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var key := mi.get_instance_id()
		if not _arrays.has(key):
			_arrays[key] = mi.mesh.surface_get_arrays(0)
		var a: Array = _arrays[key]
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bs: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var ws: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var per := bs.size() / maxi(vs.size(), 1)
		var skin := mi.skin
		var mats: Array[Transform3D] = []
		for b in skin.get_bind_count():
			var bone := skin.get_bind_bone(b)
			if bone < 0:
				bone = _sk.find_bone(skin.get_bind_name(b))
			mats.append(_sk.get_bone_global_pose(maxi(bone, 0)) * skin.get_bind_pose(b))
		var xf := mi.global_transform
		var i := 0
		while i < vs.size():
			var p := Vector3.ZERO
			for k in per:
				var w := ws[i * per + k]
				if w > 0.0:
					p += (mats[bs[i * per + k]] * vs[i]) * w
			var y := (xf * p).y
			if y < low:
				low = y
			i += 2
	return low
