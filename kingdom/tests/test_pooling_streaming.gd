extends GdUnitTestSuite
## F12: the generic node pool (cap, reuse, oldest-steal, hooks), pooled creatures that reset fully, and the one cell
## manager (tiers with hysteresis, listeners, spawner sleep, quality tiers).

const NodePool := preload("res://scripts/core/node_pool.gd")
const CreaturePool := preload("res://scripts/core/creature_pool.gd")
const CellStreamer := preload("res://scripts/core/cell_streamer.gd")
const Quality3 := preload("res://scripts/core/quality.gd")

const HOOKED := """
extends Node3D
var acquired := 0
var released := 0
var resets := 0
func on_acquire() -> void:
	acquired += 1
func on_release() -> void:
	released += 1
func reset() -> void:
	resets += 1
"""


func after_test() -> void:
	NodePool.clear_all()
	NodePool.enabled = true
	CellStreamer.reset_shared()


func _hooked_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = HOOKED
	s.reload()
	return s


# --- NodePool ---------------------------------------------------------------------------------------------

func test_pool_cap_and_reuse_without_growth() -> void:
	var pool := NodePool.new(func() -> Node: return Node3D.new(), 4, false, "t")
	pool.prewarm(2)
	assert_int(pool.idle_count()).is_equal(2)
	var held: Array[Node] = []
	for i in 4:
		held.append(pool.acquire())
	assert_int(pool.total()).is_equal(4)
	assert_object(pool.acquire()).is_null()           # at the cap, no stealing: nothing more is created
	for n in held:
		assert_bool(pool.release(n)).is_true()
	assert_bool(pool.release(held[0])).is_false()      # already idle
	for i in 200:
		var n := pool.acquire()
		assert_object(n).is_not_null()
		pool.release(n)
	var s := pool.stats()
	assert_int(int(s["created"])).is_equal(4)
	assert_int(int(s["total"])).is_equal(4)
	assert_int(int(s["peak_live"])).is_equal(4)
	assert_int(int(s["reuses"])).is_greater(190)
	pool.clear()


func test_pool_steals_the_oldest_live_node_at_the_cap() -> void:
	var pool := NodePool.new(func() -> Node: return Node3D.new(), 3, true, "steal")
	var a := pool.acquire()
	var b := pool.acquire()
	var c := pool.acquire()
	var d := pool.acquire()                            # steals a, the oldest
	assert_object(d).is_same(a)
	assert_int(int(pool.stats()["steals"])).is_equal(1)
	assert_int(pool.total()).is_equal(3)
	assert_bool(pool.is_live(b)).is_true()
	assert_bool(pool.is_live(c)).is_true()
	pool.clear()
	for n in [b, c, d]:
		if is_instance_valid(n):
			n.free()


func test_pool_hooks_run_in_order_and_nodes_leave_the_tree() -> void:
	var script := _hooked_script()
	var pool := NodePool.new(func() -> Node: return script.new(), 2, true, "hooks")
	var world: Node = auto_free(Node3D.new())
	add_child(world)
	var n := pool.acquire()
	assert_int(int(n.get("acquired"))).is_equal(1)
	world.add_child(n)
	assert_bool(pool.release(n)).is_true()
	assert_int(int(n.get("released"))).is_equal(1)
	assert_int(int(n.get("resets"))).is_equal(1)
	assert_object(n.get_parent()).is_null()
	assert_object(pool.acquire()).is_same(n)
	assert_int(int(n.get("acquired"))).is_equal(2)
	pool.clear()
	n.free()


func test_recycle_of_a_foreign_node_frees_it() -> void:
	var n := Node3D.new()
	add_child(n)
	assert_bool(NodePool.recycle(n)).is_false()
	assert_bool(n.is_queued_for_deletion()).is_true()


func test_pool_switched_off_allocates_plainly() -> void:
	NodePool.enabled = false
	var w := CreaturePool.critter("test", "chicken")
	assert_bool(w.has_meta(NodePool.META)).is_false()
	w.free()
	NodePool.enabled = true


# --- creatures -----------------------------------------------------------------------------------------------

func test_a_released_wolf_resets_fully() -> void:
	var world: Node3D = auto_free(Node3D.new())
	add_child(world)
	var w = CreaturePool.wolf("test", "wolf")
	world.add_child(w)
	if w.is_queued_for_deletion():
		return          # no wolf model in this checkout: nothing to pool
	var full: int = w.health
	assert_int(full).is_greater(0)
	var calls := [0]
	w.died.connect(func(_x: Variant) -> void: calls[0] += 1)
	w.add_to_group("thornfield_wolf")
	w.set_meta("prey", world)
	w.den_id = 7
	w.scale = Vector3.ONE * 1.7
	w.take_damage(5)
	assert_int(w.health).is_less(full)
	w.state = 3                          # FLEE
	w.take_damage(100000)
	assert_bool(w.dead).is_true()
	assert_int(calls[0]).is_equal(1)
	assert_bool(NodePool.recycle(w)).is_true()
	assert_object(w.get_parent()).is_null()
	assert_bool(w.dead).is_false()
	assert_int(w.health).is_equal(w.max_health)
	assert_int(w.state).is_equal(0)      # ROAM
	assert_int(w.den_id).is_equal(-1)
	assert_vector(w.scale).is_equal(Vector3.ONE)
	assert_bool(w.is_in_group("thornfield_wolf")).is_false()
	assert_bool(w.has_meta("prey")).is_false()
	assert_int(w.died.get_connections().size()).is_equal(0)
	var again = CreaturePool.wolf("test", "wolf")
	assert_object(again).is_same(w)       # the same body comes back, ready to fight
	world.add_child(again)
	assert_bool(again.is_in_group("team1")).is_true()
	assert_bool(again.is_in_group("combatant")).is_true()
	again.take_damage(3)
	assert_int(again.health).is_equal(again.max_health - 3)
	NodePool.recycle(again)


func test_a_released_monster_resets_fully() -> void:
	var world: Node3D = auto_free(Node3D.new())
	add_child(world)
	var m = CreaturePool.monster("test", "goblin")
	world.add_child(m)
	if m.is_queued_for_deletion():
		return
	var calls := [0]
	m.died.connect(func(_x: Variant) -> void: calls[0] += 1)
	m.take_damage(100000)                 # 75%: yields instead of dying
	m.take_damage(100000)                 # striking a yielded monster, or the finishing blow
	assert_bool(m.dead).is_true()
	assert_int(calls[0]).is_equal(1)
	assert_bool(NodePool.recycle(m)).is_true()
	assert_bool(m.dead).is_false()
	assert_int(m.health).is_equal(m.max_health)
	assert_int(m.state).is_equal(0)       # WANDER
	assert_bool(m.hostile).is_true()
	assert_int(m.died.get_connections().size()).is_equal(0)
	var again = CreaturePool.monster("test", "goblin")
	assert_object(again).is_same(m)
	world.add_child(again)
	assert_bool(again.is_in_group("team1")).is_true()
	assert_bool(again.is_in_group("combatant")).is_true()
	NodePool.recycle(again)


func test_a_released_critter_is_alive_and_upright_again() -> void:
	var world: Node3D = auto_free(Node3D.new())
	add_child(world)
	var c = CreaturePool.critter("test", "deer")
	world.add_child(c)
	if c.is_queued_for_deletion():
		return
	var hp: int = c.health
	c.dead = true
	c.rotation.z = 1.5
	c.scale = Vector3(1, 0.01, 1)
	assert_bool(NodePool.recycle(c)).is_true()
	assert_bool(c.dead).is_false()
	assert_int(c.health).is_equal(hp)
	assert_float(c.rotation.z).is_equal(0.0)
	assert_vector(c.scale).is_equal(Vector3.ONE)


# --- CellStreamer ----------------------------------------------------------------------------------------------

func _streamer(qt := Quality3.HIGH) -> RefCounted:
	var cs: RefCounted = (load("res://scripts/core/cell_streamer.gd") as GDScript).new()
	cs.quality_tier = qt
	return cs


func test_tier_hysteresis_keeps_a_cell_until_it_is_well_past_the_edge() -> void:
	var cs := _streamer()
	var load_m: float = cs.distance("dressing", "load")
	var hyst: float = cs.distance("dressing", "hyst")
	var cell := Vector2i(0, 0)
	var seen: Array = []
	cs.watch("dressing", func(c: Vector2i, t: int, old: int) -> void:
		if c == cell:
			seen.append([t, old]))
	# Stand at +x so the box distance to cell (0,0) is simply x - 64.
	cs.update(Vector3(CellStreamer.CELL + load_m + 20.0, 0, 32.0))
	assert_int(cs.cell_tier("dressing", cell)).is_equal(CellStreamer.Tier.UNLOADED)
	cs.update(Vector3(CellStreamer.CELL + load_m - 4.0, 0, 32.0))      # just inside: loads
	assert_int(cs.cell_tier("dressing", cell)).is_equal(CellStreamer.Tier.LOW)
	cs.update(Vector3(CellStreamer.CELL + load_m + hyst * 0.5, 0, 32.0))   # a little outside: keeps its tier
	assert_int(cs.cell_tier("dressing", cell)).is_equal(CellStreamer.Tier.LOW)
	cs.update(Vector3(CellStreamer.CELL + load_m - 1.0, 0, 32.0))
	assert_int(cs.cell_tier("dressing", cell)).is_equal(CellStreamer.Tier.LOW)
	cs.update(Vector3(CellStreamer.CELL + load_m + hyst + 10.0, 0, 32.0))   # well outside: unloads
	assert_int(cs.cell_tier("dressing", cell)).is_equal(CellStreamer.Tier.UNLOADED)
	assert_array(seen).is_equal([[CellStreamer.Tier.LOW, CellStreamer.Tier.UNLOADED], [CellStreamer.Tier.UNLOADED, CellStreamer.Tier.LOW]])
	# Dithering across the load edge never flips the tier.
	var flips := 0
	for i in 40:
		var before: int = cs.cell_tier("dressing", cell)
		cs.update(Vector3(CellStreamer.CELL + load_m + (-6.0 if i % 2 == 0 else 6.0), 0, 32.0))
		flips += 1 if cs.cell_tier("dressing", cell) != before else 0
	assert_int(flips).is_less_equal(1)


func test_full_tier_is_nearest_and_hysteresis_applies_to_it_too() -> void:
	var cs := _streamer()
	var f: float = cs.distance("population", "full")
	assert_int(cs.tier_for("population", f - 1.0, CellStreamer.Tier.UNLOADED)).is_equal(CellStreamer.Tier.FULL)
	assert_int(cs.tier_for("population", f + 1.0, CellStreamer.Tier.UNLOADED)).is_equal(CellStreamer.Tier.LOW)
	assert_int(cs.tier_for("population", f + 1.0, CellStreamer.Tier.FULL)).is_equal(CellStreamer.Tier.FULL)
	assert_int(cs.tier_for("population", f + cs.distance("population", "hyst") + 1.0, CellStreamer.Tier.FULL)).is_equal(CellStreamer.Tier.LOW)
	assert_int(cs.tier_for("population", 1000.0, CellStreamer.Tier.FULL)).is_equal(CellStreamer.Tier.UNLOADED)


func test_subsystems_receive_tier_changes() -> void:
	var cs := _streamer()
	var terrain_events := [0]
	var site_events: Array = []
	cs.watch("terrain", func(_c: Vector2i, _t: int, _o: int) -> void: terrain_events[0] += 1)
	cs.add_site("dressing", "farm", Vector2(500, 0), func(id: Variant, t: int, o: int) -> void: site_events.append([id, t, o]))
	cs.add_site("gather", "berries", Vector2(0, 10), func(id: Variant, t: int, o: int) -> void: site_events.append([id, t, o]))
	cs.update(Vector3(0, 0, 0))
	assert_int(terrain_events[0]).is_greater(0)
	# The terrain ring around the focus is exactly Quality's view_radius of cells.
	assert_int(cs.radius_cells("terrain")).is_equal(Quality3.TIERS[Quality3.HIGH]["view_radius"])
	assert_int(cs.cell_tier("terrain", Vector2i(0, 0))).is_equal(CellStreamer.Tier.FULL)
	assert_bool(cs.cells_in_tier("terrain", CellStreamer.Tier.LOW) > 0).is_true()
	assert_array(site_events).is_equal([["berries", CellStreamer.Tier.FULL, CellStreamer.Tier.UNLOADED]])
	var before: int = terrain_events[0]
	cs.update(Vector3(1.0, 0, 0))                      # below MOVE_EPS: nothing recomputed
	assert_int(terrain_events[0]).is_equal(before)
	cs.update(Vector3(400, 0, 0))                      # the farm wakes, the berries sleep
	assert_bool(site_events.has(["farm", CellStreamer.Tier.LOW, CellStreamer.Tier.UNLOADED])).is_true()
	assert_int(cs.site_tier("gather", "berries")).is_equal(CellStreamer.Tier.UNLOADED)
	assert_int(terrain_events[0]).is_greater(before)


func test_spawner_sleeps_in_an_unloaded_cell_and_wakes_near() -> void:
	var cs := _streamer()
	var camp := {"residents": [], "bodies": 0}
	var wake := func(_id: Variant, t: int, _o: int) -> void:
		if t == CellStreamer.Tier.UNLOADED:
			camp["bodies"] = 0                         # asleep: bodies given back to their pool
		elif int(camp["bodies"]) == 0:
			camp["bodies"] = 5                         # awake: the pack is spawned
	cs.add_site("camps", "orc_camp", Vector2(0, 0), wake)
	cs.update(Vector3(2000, 0, 0))
	assert_bool(cs.asleep("camps", "orc_camp")).is_true()
	assert_int(int(camp["bodies"])).is_equal(0)
	cs.update(Vector3(cs.distance("camps", "load") - 10.0, 0, 0))
	assert_bool(cs.asleep("camps", "orc_camp")).is_false()
	assert_int(int(camp["bodies"])).is_equal(5)
	# Inside the hysteresis band it stays awake; past it, asleep again.
	cs.update(Vector3(cs.distance("camps", "load") + 40.0, 0, 0))
	assert_bool(cs.asleep("camps", "orc_camp")).is_false()
	cs.update(Vector3(cs.distance("camps", "free") + 30.0, 0, 0))
	assert_bool(cs.asleep("camps", "orc_camp")).is_true()
	assert_int(int(camp["bodies"])).is_equal(0)


func test_spawner_helper_follows_the_manager_only_for_its_own_focus() -> void:
	var cs := _streamer()
	var holder := {}
	var here := Vector2(0, 0)
	assert_int(cs.spawner_tier("ambient", holder, Vector2(300, 0), here)).is_equal(-1)     # manager not fed yet
	cs.update(Vector3(0, 0, 0))
	assert_int(cs.spawner_tier("ambient", holder, Vector2(300, 0), here)).is_equal(CellStreamer.Tier.UNLOADED)
	assert_int(cs.spawner_tier("ambient", holder, Vector2(300, 0), Vector2(500, 500))).is_equal(-1)   # another focus: own distance check
	cs.update(Vector3(250, 0, 0))
	assert_bool(cs.spawner_tier("ambient", holder, Vector2(300, 0), Vector2(250, 0)) >= CellStreamer.Tier.LOW).is_true()
	cs.release_spawner("ambient", holder)
	assert_int(cs.site_count("ambient")).is_equal(0)


func test_quality_tier_changes_the_radii() -> void:
	var cs := _streamer()
	var rings: Array = []
	for t in [Quality3.LOW, Quality3.MEDIUM, Quality3.HIGH, Quality3.ULTRA]:
		rings.append(cs.distance_at("terrain", "load", t))
		assert_float(cs.distance_at("terrain", "load", t)).is_equal(float(Quality3.TIERS[t]["view_radius"]) * CellStreamer.CELL)
	assert_bool(rings[0] < rings[1] and rings[1] < rings[2] and rings[2] < rings[3]).is_true()
	cs.quality_tier = Quality3.LOW
	assert_int(cs.radius_cells("terrain")).is_equal(2)
	cs.quality_tier = Quality3.ULTRA
	assert_int(cs.radius_cells("terrain")).is_equal(5)
	# Changing tier is picked up by the next update, which re-tiers the cells.
	cs.quality_tier = Quality3.HIGH
	cs.watch("terrain", func(_c: Vector2i, _t: int, _o: int) -> void: pass)
	cs.update(Vector3.ZERO)
	var high_cells: int = cs.cells_in_tier("terrain", CellStreamer.Tier.LOW) + cs.cells_in_tier("terrain", CellStreamer.Tier.FULL)
	cs.quality_tier = Quality3.LOW
	cs.update(Vector3.ZERO)
	var low_cells: int = cs.cells_in_tier("terrain", CellStreamer.Tier.LOW) + cs.cells_in_tier("terrain", CellStreamer.Tier.FULL)
	assert_bool(low_cells < high_cells).is_true()


func test_default_radii_match_the_old_hardcoded_distances() -> void:
	var cs := _streamer()
	assert_float(cs.distance("settlement", "full")).is_equal(70.0)        # hero LOD
	assert_float(cs.distance("settlement", "load")).is_equal(650.0)
	assert_float(cs.distance("settlement", "free")).is_equal(850.0)
	assert_float(cs.distance("dressing", "load")).is_equal(240.0)
	assert_float(cs.distance("dressing", "free")).is_equal(330.0)
	assert_float(cs.distance("population", "full")).is_equal(45.0)
	assert_float(cs.distance("population", "load")).is_equal(220.0)
	assert_float(cs.distance("ambient", "load")).is_equal(110.0)
	assert_float(cs.distance("ambient", "free")).is_equal(170.0)
	assert_float(cs.distance("camps", "load")).is_equal(260.0)
	assert_float(cs.distance("camps", "free")).is_equal(420.0)
	assert_float(cs.distance("gather", "load")).is_equal(55.0)
	assert_float(cs.distance("gather", "free")).is_equal(80.0)
	assert_int(cs.radius_cells("terrain")).is_equal(4)                       # HIGH, as test_world_12km expects
	assert_int(cs.radius_cells("terrain", "full")).is_equal(1)
