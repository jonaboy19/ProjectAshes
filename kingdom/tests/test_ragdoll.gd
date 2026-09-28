extends GdUnitTestSuite
## Ragdolls: the world-wide cap on simulating bodies, heavy-hit detection, and a
## death on a small code-built humanoid that is refused while the cap is full.

const Ragdoll := preload("res://scripts/actors/ragdoll.gd")


func before_test() -> void:
	Ragdoll.reset_slots()


func after_test() -> void:
	Ragdoll.reset_slots()


func test_at_most_three_slots() -> void:
	assert_int(Ragdoll.MAX_LIVE).is_equal(3)
	var owners: Array = []
	for i in 5:
		owners.append(RefCounted.new())
	var got: Array = []
	for o: RefCounted in owners:
		got.append(Ragdoll.acquire(o))
	assert_array(got).is_equal([true, true, true, false, false])
	assert_int(Ragdoll.live_count()).is_equal(3)
	# Asking again for a slot you hold doesn't take a second one.
	assert_bool(Ragdoll.acquire(owners[0])).is_true()
	assert_int(Ragdoll.live_count()).is_equal(3)
	# Releasing one lets the next in.
	Ragdoll.release(owners[1])
	assert_bool(Ragdoll.acquire(owners[3])).is_true()
	assert_bool(Ragdoll.acquire(owners[4])).is_false()
	assert_int(Ragdoll.live_count()).is_equal(3)


func test_freed_owner_gives_its_slot_back() -> void:
	var gone := Node.new()
	assert_bool(Ragdoll.acquire(gone)).is_true()
	assert_bool(Ragdoll.acquire(RefCounted.new())).is_true()
	assert_int(Ragdoll.live_count()).is_equal(2)
	gone.free()
	assert_int(Ragdoll.live_count()).is_equal(1)


func test_heavy_hits() -> void:
	assert_bool(Ragdoll.is_heavy(20, null, Vector3(6.0, 0, 0))).is_true()
	assert_bool(Ragdoll.is_heavy(20, null, Vector3(0, 0, -7.0))).is_true()
	assert_bool(Ragdoll.is_heavy(20, null, Vector3(5.9, 0, 0))).is_false()
	# player.gd's parry sends the attacker take_damage(0, player, push).
	var p := auto_free(Node.new()) as Node
	add_child(p)
	p.add_to_group("player")
	assert_bool(Ragdoll.is_heavy(0, p, Vector3(3.5, 0, 0))).is_true()
	assert_bool(Ragdoll.is_heavy(0, p, Vector3.ZERO)).is_false()
	var other := auto_free(Node.new()) as Node
	add_child(other)
	assert_bool(Ragdoll.is_heavy(0, other, Vector3(3.5, 0, 0))).is_false()


## A floor and a CharacterBody3D wearing a 24-bone-style humanoid skeleton
## (Meshy bone names), 1 m tall. Returns [actor, skeleton].
func _humanoid() -> Array:
	var world := Node3D.new()
	add_child(world)
	auto_free(world)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 1, 10)
	cs.shape = box
	cs.position.y = -0.5
	floor.add_child(cs)
	world.add_child(floor)
	var actor := CharacterBody3D.new()
	actor.collision_layer = 4
	world.add_child(actor)
	var model := Node3D.new()
	actor.add_child(model)
	var sk := Skeleton3D.new()
	model.add_child(sk)
	# name, parent, rest position relative to the parent
	var bones := [
		["Hips", "", Vector3(0, 0.5, 0)], ["Spine01", "Hips", Vector3(0, 0.12, 0)],
		["neck", "Spine01", Vector3(0, 0.18, 0)], ["Head", "neck", Vector3(0, 0.06, 0)],
		["head_end", "Head", Vector3(0, 0.14, 0)],
		["LeftArm", "Spine01", Vector3(0.12, 0.15, 0)], ["LeftForeArm", "LeftArm", Vector3(0.15, 0, 0)],
		["LeftHand", "LeftForeArm", Vector3(0.14, 0, 0)],
		["RightArm", "Spine01", Vector3(-0.12, 0.15, 0)], ["RightForeArm", "RightArm", Vector3(-0.15, 0, 0)],
		["RightHand", "RightForeArm", Vector3(-0.14, 0, 0)],
		["LeftUpLeg", "Hips", Vector3(0.08, -0.03, 0)], ["LeftLeg", "LeftUpLeg", Vector3(0, -0.22, 0)],
		["LeftFoot", "LeftLeg", Vector3(0, -0.22, 0)],
		["RightUpLeg", "Hips", Vector3(-0.08, -0.03, 0)], ["RightLeg", "RightUpLeg", Vector3(0, -0.22, 0)],
		["RightFoot", "RightLeg", Vector3(0, -0.22, 0)],
	]
	for b: Array in bones:
		var i := sk.add_bone(b[0])
		if b[1] != "":
			sk.set_bone_parent(i, sk.find_bone(b[1]))
		sk.set_bone_rest(i, Transform3D(Basis.IDENTITY, b[2]))
	sk.reset_bone_poses()
	return [actor, sk]


func test_death_is_refused_while_the_cap_is_full() -> void:
	var h := _humanoid()
	var actor: CharacterBody3D = h[0]
	await get_tree().physics_frame
	var rd: Node = Ragdoll.attach(actor, actor.get_child(0), [])
	assert_object(rd).is_not_null()
	var busy: Array = [RefCounted.new(), RefCounted.new(), RefCounted.new()]
	for o: RefCounted in busy:
		Ragdoll.acquire(o)
	assert_bool(rd.die(Vector3(3, 0, 0))).is_false()
	assert_str(rd.why).is_equal("cap")
	assert_int(rd.mode).is_equal(Ragdoll.Mode.IDLE)
	Ragdoll.release(busy[0])
	assert_bool(rd.die(Vector3(3, 0, 0))).is_true()
	assert_int(rd.mode).is_equal(Ragdoll.Mode.DYING)
	assert_int(Ragdoll.live_count()).is_equal(3)
	# Built lazily: bodies exist only now, one per main bone found.
	assert_int(rd._bodies.size()).is_equal(11)
	for b: PhysicalBone3D in rd._bodies:
		assert_int(b.collision_layer).is_equal(0)
		assert_int(b.collision_mask).is_equal(1)
	# A second death on the same ragdoll never takes another slot.
	assert_bool(rd.die()).is_false()
	assert_int(Ragdoll.live_count()).is_equal(3)
