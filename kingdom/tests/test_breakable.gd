extends GdUnitTestSuite
## Breakable street props: the global shard cap, shatter/restore bookkeeping and loot rolls.

const Breakable := preload("res://scripts/world/breakable.gd")


func before_test() -> void:
	Breakable.clear_shards()


func after_test() -> void:
	Breakable.clear_shards()


## A row of `n` breakable barrels (BoxMesh stand-ins) in one MultiMesh, 3 m apart.
func _row(n: int, kind := "barrel") -> Array:
	var world := Node3D.new()
	add_child(world)
	auto_free(world)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.6, 0.9, 0.6)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = n
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	world.add_child(mmi)
	var out: Array = []
	for i in n:
		var t := Transform3D(Basis.IDENTITY, Vector3(i * 3.0, 0.0, 0.0))
		mm.set_instance_transform(i, t)
		var b: StaticBody3D = Breakable.new()
		b.setup_instance(mm, i, t, mesh, kind)
		world.add_child(b)
		out.append(b)
	return out


func test_shatter_spawns_six_to_ten_shards_and_hides_the_prop() -> void:
	var b: StaticBody3D = _row(1)[0]
	assert_bool(b.is_in_group("breakable")).is_true()
	var n: int = b.shatter(b.global_position + Vector3(0, 0, -0.4), 3.0)
	assert_int(n).is_between(Breakable.MIN_SHARDS, Breakable.MAX_PER_BREAK)
	assert_int(Breakable.live_shard_count()).is_equal(n)
	assert_bool(b.broken).is_true()
	assert_bool(b.hidden_transform).is_true()
	assert_int(b.shatter(b.global_position, 3.0)).is_equal(0)   # already broken
	b.restore()
	assert_bool(b.broken).is_false()
	assert_bool(b.hidden_transform).is_false()
	assert_int(b.health).is_equal(int(Breakable.KINDS["barrel"][0]))


func test_live_shards_never_exceed_the_global_cap() -> void:
	var row := _row(8)
	for b: StaticBody3D in row:
		b.shatter(b.global_position + Vector3(0, 0, -0.4), 3.0)
		assert_int(Breakable.live_shard_count()).is_less_equal(Breakable.MAX_SHARDS)
	# 8 props x at least 6 shards overflow the cap: the oldest were recycled.
	assert_int(Breakable.live_shard_count()).is_equal(Breakable.MAX_SHARDS)


func test_damage_breaks_after_health_and_strong_impacts_break_at_once() -> void:
	var row := _row(2, "crate_stack")
	var stack: StaticBody3D = row[0]
	stack.take_damage(14, null, Vector3(0, 0, 1.5))
	assert_bool(stack.broken).is_false()
	stack.take_damage(30, null, Vector3(0, 0, 1.5))
	assert_bool(stack.broken).is_true()
	var other: StaticBody3D = row[1]
	other.take_damage(1, null, Vector3(0, 0, Breakable.STRONG_IMPACT))
	assert_bool(other.broken).is_true()


func test_loot_rolls() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for kind: String in ["barrel", "crate", "scan/wooden_crate_01", "crate_stack"]:
		var seen := {}
		var empty := 0
		for i in 2000:
			var loot := Breakable.roll_loot(kind, rng)
			if loot.is_empty():
				empty += 1
			for item: String in loot:
				assert_array(["gold", "apple", "firewood"]).contains([item])
				assert_int(int(loot[item])).is_between(1, 8)
				seen[item] = true
		assert_int(seen.size()).override_failure_message("%s never drops everything" % kind).is_equal(3)
		assert_int(empty).override_failure_message("%s always drops" % kind).is_greater(0)
	# Barrel gold is a few coins, about half the time.
	var gold_hits := 0
	for i in 2000:
		var loot := Breakable.roll_loot("barrel", rng)
		if loot.has("gold"):
			gold_hits += 1
			assert_int(int(loot["gold"])).is_between(1, 4)
	assert_int(gold_hits).is_between(700, 1100)
	# Baskets, buckets, sacks and unknown kinds drop nothing.
	for kind: String in ["scan/wicker_basket_01", "scan/wooden_bucket_01", "sack_pile", "cart", ""]:
		for i in 50:
			assert_bool(Breakable.roll_loot(kind, rng).is_empty()).is_true()


func test_same_seed_same_loot() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 99
	b.seed = 99
	for i in 100:
		assert_dict(Breakable.roll_loot("crate", a)).is_equal(Breakable.roll_loot("crate", b))


func test_mesh_slices_into_cached_chunks() -> void:
	var mesh := BoxMesh.new()
	mesh.subdivide_width = 3
	mesh.subdivide_height = 3
	mesh.subdivide_depth = 3
	var chunks := Breakable.chunks_for(mesh)
	assert_int(chunks.size()).is_between(2, 8)
	assert_bool(Breakable.chunks_for(mesh) == chunks).is_true()   # cached
	for c: Array in chunks:
		assert_object(c[0]).is_instanceof(ArrayMesh)
		assert_bool((c[1] as Vector3).is_finite()).is_true()
