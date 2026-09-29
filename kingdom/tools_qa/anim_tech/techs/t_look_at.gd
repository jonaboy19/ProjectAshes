extends RefCounted
## (2) Head look-at with LookAtModifier3D (neck + head, angle limits, ease back when the target
## leaves the cone). Left character: raw Idle clip. Right character: LookAtRig.
## The target sweeps left -> front -> right -> behind (out of limits) -> back to the front.

const U := preload("res://tools_qa/anim_tech/lib/at_util.gd")
const LookAtRig := preload("res://tools_qa/anim_tech/lib/look_at.gd")
const PATH_SECONDS := 9.0
const SNAP_AT := [0.4, 1.8, 3.3, 4.6, 5.6, 6.6, 7.6, 8.7]


func _path(t: float) -> Vector3:
	# angle in the XZ plane around the characters, 0 = straight ahead (+Z)
	var k := t / PATH_SECONDS
	var ang: float
	if k < 0.5:
		ang = lerpf(-1.1, 1.1, k / 0.5)                 # sweep across the front, +-72 deg
	elif k < 0.7:
		ang = lerpf(1.1, 2.9, (k - 0.5) / 0.2)           # swings round behind
	else:
		ang = lerpf(2.9, 0.15, (k - 0.7) / 0.3)
	return Vector3(sin(ang) * 1.6, 1.72 + sin(t * 1.3) * 0.08, cos(ang) * 1.6)


func run(d: Node3D, my: int) -> void:
	var a: Dictionary = d.spawn(Vector3(-0.9, 0, 0), 0.0)
	var b: Dictionary = d.spawn(Vector3(0.9, 0, 0), 0.0)
	var idle := U.find_clip(a["ap"], ["Idle", "Idle_Subtle", "Sword_Idle"])
	a["ap"].play(idle)
	b["ap"].play(idle)
	var target := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	target.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.25, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.2, 0.1)
	target.material_override = mat
	d.stage.add_child(target)
	var rig := LookAtRig.attach(b["model"], target)
	d.label3d("no look-at", Vector3(-0.9, 2.0, 0))
	d.label3d("LookAtModifier3D", Vector3(0.9, 2.0, 0))
	d.set_cam(Vector3(0.0, 1.95, 5.6), Vector3(0.0, 1.45, 0.0), 32.0)
	var t := 0.0
	var snaps: Array = SNAP_AT.duplicate()
	while t < PATH_SECONDS:
		await d.get_tree().process_frame
		if not d.alive(my):
			return
		t += d.get_process_delta_time()
		target.position = _path(t)
		if rig:
			rig.active = d.tech_on
		if not snaps.is_empty() and t >= snaps[0]:
			snaps.pop_front()
			await d.snap()
	d.write_strip("look_at", 4)
