extends SceneTree
const Preflight = preload("res://traversal_preflight.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var obstacle := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 0.92, 0.5)
	collider.shape = box
	obstacle.add_child(collider)
	world.add_child(obstacle)
	obstacle.position = Vector3(0, 0.46, 1.15)
	await physics_frame
	await physics_frame
	var roots: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../traversal_roots.json"))
	var probes: Array = [["thigh_l", "calf_l", 0.075], ["pelvis", "spine_01", 0.11]]
	var gate = Preflight.new()
	assert(gate.begin(roots.Vault_Low.samples, probes, Transform3D.IDENTITY))
	while gate.active:
		assert(gate.step(world.get_world_3d().direct_space_state, 4).queries_this_step <= 4)
	assert(gate.result.status == "blocked" and gate.result.frame == 18)
	assert(gate.begin(roots.Vault_Low.samples, probes, Transform3D(Basis.IDENTITY, Vector3(3, 0, 0))))
	while gate.active:
		gate.step(world.get_world_3d().direct_space_state, 4)
	assert(gate.result.status == "sampled_clear")
	assert(gate.begin(roots.Vault_Low.samples, probes, Transform3D.IDENTITY))
	gate.cancel()
	assert(gate.step(world.get_world_3d().direct_space_state).status == "cancelled")
	assert(gate.begin([{"body_points": {"thigh_l": [0, "bad", 0], "calf_l": [0, 1, 0]}}], probes, Transform3D.IDENTITY))
	var invalid: Dictionary = gate.step(world.get_world_3d().direct_space_state, 1)
	assert(invalid.status == "invalid_pose" and invalid.queries_this_step == 1 and invalid.queries == 0)
	assert(not gate.active)
	assert(not gate.begin(roots.Vault_Low.samples, [["pelvis", "spine_01", -1]], Transform3D.IDENTITY))
	print("TRAVERSAL_PREFLIGHT_PASS actual clip obstruction; aligned clear path; per-step budget; cancel")
	quit()
