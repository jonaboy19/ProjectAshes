extends GdUnitTestSuite
## ResidentIndex (scripts/population/resident_index.gd): the 16 m cell grid WorldSim keeps over the resident rows.
## people_near / people_in_ring must return exactly what the old scan over every row of every settlement in range returned,
## before and after the world has moved, and cell membership must stay consistent through kills and external ownership.

const CASES := 200


func before_test() -> void:
	WorldSim.reset()


func after_test() -> void:
	WorldSim.reset()


## The pre-index implementation of WorldSim.people_near, verbatim.
func _scan(p: Vector2, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r2 := radius * radius
	for s in WorldGen.settlements:
		if p.distance_to(s["pos"]) > radius + s["radius"] * 2.0:
			continue
		var range_i: Vector2i = WorldSim.ranges[s["id"]]
		for i in range(range_i.x, range_i.y):
			if WorldSim.health[i] != 0 and WorldSim.pos[i].distance_squared_to(p) < r2:
				out.append(i)
	return out


func _random_query(rng: RandomNumberGenerator) -> Array:
	var s: Dictionary = WorldGen.settlements[rng.randi() % WorldGen.settlements.size()]
	var c: Vector2 = s["pos"]
	var p := c + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * float(s["radius"]) * 2.5
	return [p, rng.randf_range(4.0, 260.0)]


func _assert_parity(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var total := 0
	for _c in CASES:
		var q := _random_query(rng)
		var p: Vector2 = q[0]
		var r: float = q[1]
		var want := _scan(p, r)
		var got := WorldSim.people_near(p, r)
		assert_array(Array(got)).is_equal(Array(want))
		var ring := WorldSim.people_in_ring(p, 0.0, r, 1_000_000)
		var ring_sorted := Array(ring)
		ring_sorted.sort()
		assert_array(ring_sorted).is_equal(Array(want))
		# nearest first
		var last := -1.0
		for i in ring:
			var d2 := WorldSim.pos[i].distance_squared_to(p)
			assert_bool(d2 + 0.001 >= last).is_true()      # keys are quantised to 1/4096 m^2
			last = d2
		total += want.size()
	assert_int(total).is_greater(0)       # the cases do hit people


func test_people_near_and_ring_match_the_old_scan() -> void:
	_assert_parity(7)


func test_parity_holds_after_ten_simulated_hours() -> void:
	var player := Node3D.new()
	add_child(player)
	player.add_to_group("player")
	var c: Vector2 = WorldGen.settlements[1]["pos"]
	player.global_position = Vector3(c.x, 0.0, c.y)
	auto_free(player)
	for _h in 10:
		WorldSim.advance_hours(1.0)
		for _f in 4:
			WorldSim._clock += 15.0
			WorldSim._near_next = 0.0
			WorldSim._simulate_slice(15.0)       # walks the near ring; the far loop gets its credit
	assert_bool(_consistent()).is_true()
	_assert_parity(11)


func test_ring_returns_the_nearest_n_in_order() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for _c in 60:
		var q := _random_query(rng)
		var p: Vector2 = q[0]
		var r1: float = maxf(q[1], 30.0)
		var r0 := r1 * rng.randf_range(0.0, 0.6)
		var n := rng.randi_range(1, 40)
		var all := []
		for i in _scan(p, r1):
			var d2 := WorldSim.pos[i].distance_squared_to(p)
			if d2 >= r0 * r0:
				all.append([d2, i])
		all.sort_custom(func(a: Array, b: Array) -> bool:
			var qa := floorf(a[0] * 4096.0)
			var qb := floorf(b[0] * 4096.0)
			return qa < qb or (qa == qb and a[1] < b[1]))
		var want := []
		for k in mini(n, all.size()):
			want.append(all[k][1])
		assert_array(Array(WorldSim.people_in_ring(p, r0, r1, n))).is_equal(want)


func test_kill_and_external_ownership_keep_cells_consistent() -> void:
	var s: Dictionary = WorldGen.settlements[0]
	var r: Vector2i = WorldSim.ranges[0]
	var row := r.x + 3
	var p: Vector2 = WorldSim.pos[row]
	assert_bool(Array(WorldSim.people_near(p, 1.0)).has(row)).is_true()
	WorldSim.kill_person(row)
	assert_bool(Array(WorldSim.people_near(p, 1.0)).has(row)).is_false()
	assert_bool(_consistent()).is_true()
	var other := r.x + 5
	var far: Vector2 = (s["pos"] as Vector2) + Vector2(float(s["radius"]) * 0.9, -float(s["radius"]) * 0.5)
	WorldSim.set_external_position_owner(other, 4242, true, far)
	assert_bool(Array(WorldSim.people_near(far, 1.0)).has(other)).is_true()
	assert_bool(_consistent()).is_true()
	WorldSim.set_external_position_owner(other, 4242, false, p)
	assert_bool(Array(WorldSim.people_near(far, 1.0)).has(other)).is_false()
	assert_bool(Array(WorldSim.people_near(p, 1.0)).has(other)).is_true()
	assert_bool(_consistent()).is_true()


## Every row is filed in exactly the cell its position says, in its home settlement's grid, once.
func _consistent() -> bool:
	var idx = WorldSim.index
	var seen := 0
	for sid in idx.grids.size():
		for k: int in idx.grids[sid]:
			seen += (idx.grids[sid][k] as PackedInt32Array).size()
	if seen != WorldSim.population():
		return false
	for i in WorldSim.population():
		var k: int = idx.key_of(WorldSim.pos[i])
		if idx.cell_of[i] != k:
			return false
		var cell: PackedInt32Array = idx.grids[WorldSim.home[i]].get(k, PackedInt32Array())
		if cell.count(i) != 1:
			return false
	return true
