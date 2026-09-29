extends RefCounted
## (3) Cape with SpringBoneSimulator3D. Left: same cape, springs OFF (rigid, welded to the back).
## Right: springs ON. Both jog along +X, stop, turn round and idle so the cloth trails, swings
## forward and settles; a light wind blows the whole time.

const U := preload("res://tools_qa/anim_tech/lib/at_util.gd")
const Cape := preload("res://tools_qa/anim_tech/lib/cape.gd")
const SNAP_AT := [0.9, 1.6, 2.3, 3.1, 3.5, 3.9, 4.6, 5.6]


func run(d: Node3D, my: int) -> void:
	var a: Dictionary = d.spawn(Vector3(-2.2, 0, 0.0), PI * 0.5)
	var b: Dictionary = d.spawn(Vector3(-4.4, 0, 0.0), PI * 0.5)
	var run_clip := U.find_clip(a["ap"], ["Jog_Fwd", "Running_A", "Run_Female"])
	var idle := U.find_clip(a["ap"], ["Idle", "Idle_Subtle"])
	for c: Dictionary in [a, b]:
		c["ap"].play(run_clip)
	var ca := Cape.attach(a["model"])
	var cb := Cape.attach(b["model"])
	ca.wind = Vector3(0.0, 0.0, -1.5)
	cb.wind = Vector3(0.0, 0.0, -1.5)
	var l1: Label3D = d.label3d("springs OFF", Vector3(0, 2.1, 0))
	l1.reparent(a["actor"], false)
	var l2: Label3D = d.label3d("SpringBoneSimulator3D", Vector3(0, 2.1, 0))
	l2.reparent(b["actor"], false)
	d.set_cam(Vector3(-2.8, 1.5, 6.5), Vector3(-2.8, 1.0, 0.0), 40.0)
	var snaps: Array = SNAP_AT.duplicate()
	var t := 0.0
	var x := -2.2
	while t < 6.0:
		await d.get_tree().process_frame
		if not d.alive(my):
			return
		var dt: float = d.get_process_delta_time()
		t += dt
		var speed := 3.5 if t < 3.2 else 0.0
		if t >= 3.2 and a["ap"].current_animation != idle:
			a["ap"].play(idle, 0.2)
			b["ap"].play(idle, 0.2)
		x += speed * dt
		var yaw := PI * 0.5 if t < 4.2 else lerp_angle(PI * 0.5, -PI * 0.5, minf((t - 4.2) / 0.5, 1.0))
		for c: Dictionary in [a, b]:
			c["actor"].position.x = x - (2.2 if c == b else 0.0)
			c["actor"].rotation.y = yaw
		ca._sim.active = false
		cb._sim.active = d.tech_on
		d.cam.position.x = x - 0.6
		d.cam.look_at(Vector3(x - 0.6, 1.0, 0.0))
		if not snaps.is_empty() and t >= snaps[0]:
			snaps.pop_front()
			await d.snap()
	d.write_strip("springs", 4)
