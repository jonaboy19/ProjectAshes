extends GdUnitTestSuite
## Combat feel (docs/design/AAA_POLISH_PLAN.md P0): hit tiers and hit-stop frames, stacking limits, attack
## magnetism, reaction tiers, and the pooled impact / telegraph / highlight nodes (pooling and caps).

const Feel := preload("res://scripts/combat/combat_feel.gd")
const Moves := preload("res://scripts/combat/combat_moves.gd")
const Ragdoll := preload("res://scripts/actors/ragdoll.gd")
const ImpactPool := preload("res://scripts/vfx/impact_pool.gd")
const Rings := preload("res://scripts/vfx/telegraph_rings.gd")
const Highlight := preload("res://scripts/combat/enemy_highlight.gd")
const Telegraph := preload("res://scripts/combat/telegraph.gd")


func _world() -> Node3D:
	var w: Node3D = auto_free(Node3D.new())
	add_child(w)
	return w


func _actor(world: Node3D, meshes := 2) -> Node3D:
	var a := Node3D.new()
	world.add_child(a)
	for i in meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		a.add_child(mi)
	return a


# --- tiers ---------------------------------------------------------------------------------

func test_tiers_and_hit_stop_frames() -> void:
	assert_int(Feel.tier_for(false)).is_equal(Feel.Tier.LIGHT)
	assert_int(Feel.tier_for(false, false, 1.5, 14, 14.0)).is_equal(Feel.Tier.LIGHT)
	assert_int(Feel.tier_for(false, false, 4.0, 14)).is_equal(Feel.Tier.HEAVY)
	assert_int(Feel.tier_for(false, false, 1.5, 14, 14.0, true)).is_equal(Feel.Tier.HEAVY)   # riposte
	assert_int(Feel.tier_for(true)).is_equal(Feel.Tier.FINISHER)
	assert_int(Feel.tier_for(false, true)).is_equal(Feel.Tier.FINISHER)                       # guard break
	assert_float(Feel.hit_stop_seconds(Feel.Tier.LIGHT)).is_equal(0.0)
	assert_float(Feel.hit_stop_seconds(Feel.Tier.HEAVY)).is_equal_approx(2.0 / 60.0, 0.0001)
	assert_float(Feel.hit_stop_seconds(Feel.Tier.FINISHER)).is_equal_approx(3.0 / 60.0, 0.0001)


func test_the_real_sword_combo_maps_light_light_light_finisher() -> void:
	var steps := Moves.combo("sword")
	var tiers: Array = []
	for a: Resource in steps:
		tiers.append(Feel.tier_for(a.finisher, false, a.knockback, a.damage, a.poise_damage))
	assert_array(tiers).is_equal([0, 0, 0, 2])


func test_only_finishers_flash_and_cues_stay_inside_limits() -> void:
	assert_float(Feel.FLASH[Feel.Tier.LIGHT]).is_equal(0.0)
	assert_float(Feel.FLASH[Feel.Tier.HEAVY]).is_equal(0.0)
	assert_float(Feel.FLASH[Feel.Tier.FINISHER]).is_greater(0.0)
	for t in 3:
		assert_float(Feel.fov_punch(t)).is_less_equal(Feel.FOV_MAX)
		assert_float(Feel.roll(t)).is_less_equal(Feel.ROLL_MAX)
	assert_float(Feel.merge_fov(5.0, 4.0)).is_equal(5.0)          # max, not sum
	assert_float(Feel.merge_fov(5.0, 9.0)).is_equal(Feel.FOV_MAX)
	assert_float(absf(Feel.merge_roll(0.03, 0.03))).is_less_equal(Feel.ROLL_MAX)
	assert_float(absf(Feel.merge_roll(0.03, -0.09))).is_equal_approx(Feel.ROLL_MAX, 0.0001)


# --- stacking budget -----------------------------------------------------------------------

func test_hit_stop_never_stacks() -> void:
	var b := Feel.Budget.new()
	var fin := Feel.hit_stop_seconds(Feel.Tier.FINISHER)
	assert_float(b.request_stop(0.0, 0.0)).is_equal(0.0)                       # light = no stop
	assert_float(b.request_stop(fin, 1.0)).is_equal_approx(fin, 0.0001)
	assert_float(b.request_stop(fin, 1.04)).is_equal(0.0)                      # inside the gap
	var total := fin
	for i in 30:                                                               # a flurry every 0.11 s for 3.3 s
		total += b.request_stop(fin, 1.2 + i * 0.11)
	# At most STOP_WINDOW_MAX per rolling second: 3.3 s of flurry cannot exceed ~4 windows.
	assert_float(total).is_less_equal(Feel.STOP_WINDOW_MAX * 4.5)
	var b2 := Feel.Budget.new()
	var in_window := 0.0
	for i in 20:
		in_window += b2.request_stop(fin, 5.0 + i * 0.045)                     # 0.9 s of rapid requests
	assert_float(in_window).is_less_equal(Feel.STOP_WINDOW_MAX + 0.0001)


func test_flash_has_a_cooldown() -> void:
	var b := Feel.Budget.new()
	assert_bool(b.request_flash(2.0)).is_true()
	assert_bool(b.request_flash(2.1)).is_false()
	assert_bool(b.request_flash(2.0 + Feel.FLASH_GAP + 0.01)).is_true()


# --- magnetism -----------------------------------------------------------------------------

func test_magnet_picks_a_valid_target_inside_the_cone_only() -> void:
	var o := Vector3.ZERO
	var f := Vector3(0, 0, 1)
	var ahead := Vector3(0.3, 0, 2.5)
	var side := Vector3(2.0, 0, 0.1)           # ~90 degrees: outside the cone
	var behind := Vector3(0, 0, -1.5)
	var far := Vector3(0, 0, 6.0)
	assert_object(Feel.pick_target(o, f, [behind, far, side])["pos"]).is_null()
	var pick := Feel.pick_target(o, f, [side, ahead, far])
	assert_int(pick["index"]).is_equal(1)
	assert_vector(pick["pos"]).is_equal(ahead)
	# a lock wins even when another enemy is nearer
	var locked := Feel.pick_target(o, f, [ahead], Vector3(0, 0, 3.4))
	assert_vector(locked["pos"]).is_equal(Vector3(0, 0, 3.4))
	assert_object(Feel.pick_target(o, f, [ahead], Vector3(0, 0, 30.0))["pos"]).is_not_null()   # far lock: falls back to cone


func test_lunge_is_a_small_capped_step_that_stops_at_the_standoff() -> void:
	var decel := 12.0
	for d: float in [0.5, 1.3, 2.0, 3.0, 3.8]:
		for fin: bool in [false, true]:
			var v := Feel.lunge_speed(d, decel, fin)
			var step := Feel.lunge_distance(v, decel)
			var cap := Feel.MAGNET_STEP_CAP_FINISHER if fin else Feel.MAGNET_STEP_CAP
			assert_float(step).is_less_equal(cap + 0.001)
			assert_float(step).is_less_equal(maxf(d - Feel.MAGNET_STANDOFF, 0.0) + 0.001)
	assert_float(Feel.lunge_speed(1.0, decel)).is_equal(0.0)     # already inside the standoff: no push


# --- reactions -----------------------------------------------------------------------------

func test_reaction_tiers() -> void:
	assert_str(Ragdoll.reaction(10, null, Vector3(1.5, 0, 0))).is_equal("stagger")
	assert_str(Ragdoll.reaction(10, null, Vector3(0, 0, 4.5))).is_equal("launch")
	assert_str(Ragdoll.reaction(30, null, Vector3(7.0, 0, 0))).is_equal("knockdown")        # the finisher
	assert_float(Ragdoll.LAUNCH_LIFT).is_greater(1.0)
	assert_float(Ragdoll.LAUNCH_KNOCK).is_less(Ragdoll.HEAVY_KNOCK)


func test_telegraph_worthy_moves() -> void:
	assert_bool(Feel.is_heavy_move(Moves.find("troll", "troll_smash"))).is_true()
	assert_bool(Feel.is_heavy_move(Moves.find("orc", "orc_overhead"))).is_true()
	assert_bool(Feel.is_heavy_move(Moves.find("goblin", "goblin_slash"))).is_false()
	assert_bool(Feel.is_heavy_move(Moves.find("bandit", "bandit_slash"))).is_false()
	assert_bool(Feel.is_heavy_move(null)).is_false()


# --- pooled impact -------------------------------------------------------------------------

func test_impact_pool_is_pooled_and_capped() -> void:
	var w := _world()
	var pool := ImpactPool.at(w)
	assert_object(pool).is_same(ImpactPool.at(w))
	assert_int(pool.slot_count()).is_equal(ImpactPool.MAX_ACTIVE)
	var nodes: int = pool.node_count()
	for i in 60:
		var el: String = ImpactPool.element_names()[i % ImpactPool.element_names().size()]
		pool.play(Vector3(i * 0.1, 1.0, 0), el, i % 3, Vector3.FORWARD)
		assert_int(pool.active_count()).is_less_equal(ImpactPool.MAX_ACTIVE)
	assert_int(pool.node_count()).is_equal(nodes)                 # nothing allocated while playing
	assert_int(w.get_child_count()).is_equal(1)
	# full pool: a light hit is dropped, a finisher takes the oldest slot
	assert_int(pool.active_count()).is_equal(ImpactPool.MAX_ACTIVE)
	assert_bool(pool.play(Vector3.ZERO, "physical", 0)).is_false()
	assert_bool(pool.play(Vector3.ZERO, "physical", 2)).is_true()
	assert_int(pool.active_count()).is_equal(ImpactPool.MAX_ACTIVE)


func test_impact_pool_frees_its_slots_after_the_effect() -> void:
	var w := _world()
	var pool := ImpactPool.at(w)
	pool.play(Vector3(0, 1, 0), "fire", 1)
	assert_int(pool.active_count()).is_equal(1)
	await get_tree().create_timer(1.1).timeout
	assert_int(pool.active_count()).is_equal(0)


func test_every_element_has_a_distinct_warm_variant() -> void:
	assert_array(ImpactPool.element_names()).contains_exactly_in_any_order(
		["physical", "fire", "water", "earth", "wind", "lightning", "qi"])
	var seen := {}
	for el: String in ImpactPool.element_names():
		var v := ImpactPool.variant(el)
		var tint: Color = v["pal"]["tint"]
		assert_bool(seen.has(tint)).is_false()
		seen[tint] = true
		assert_float(tint.r).is_greater(0.2)                      # every hue keeps red in it: no cold neon
	assert_dict(ImpactPool.variant("nonsense")).is_equal(ImpactPool.variant("physical"))


func test_landing_puff_uses_the_same_pool() -> void:
	var w := _world()
	var pool := ImpactPool.at(w)
	assert_bool(pool.play(Vector3(0, 0.3, 0), "earth", 1, Vector3.ZERO, true)).is_true()
	assert_int(pool.active_count()).is_equal(1)


# --- telegraph rings and highlight --------------------------------------------------------

func test_telegraph_rings_cap_and_free() -> void:
	var w := _world()
	var rings := Rings.at(w)
	assert_int(rings.slot_count()).is_equal(Rings.MAX_ACTIVE)
	var nodes: int = rings.node_count()
	var actors: Array = []
	for i in Rings.MAX_ACTIVE + 2:
		actors.append(_actor(w, 0))
	var granted := 0
	for a: Node3D in actors:
		if rings.begin(a, 2.4, 0.5):
			granted += 1
	assert_int(granted).is_equal(Rings.MAX_ACTIVE)
	assert_int(rings.active_count()).is_equal(Rings.MAX_ACTIVE)
	assert_bool(rings.begin(actors[0], 2.4, 0.5)).is_true()       # same actor restarts its own ring
	rings.end(actors[0])
	assert_int(rings.active_count()).is_equal(Rings.MAX_ACTIVE - 1)
	assert_bool(rings.begin(actors[Rings.MAX_ACTIVE], 2.4, 0.4, "fire")).is_true()   # the freed slot
	assert_int(rings.node_count()).is_equal(nodes)
	await get_tree().create_timer(0.7).timeout                    # windups end: every ring expires by itself
	assert_int(rings.active_count()).is_equal(0)


func test_highlight_applies_caps_and_restores() -> void:
	var w := _world()
	var h := Highlight.at(w)
	var actors: Array = []
	for i in 5:
		actors.append(_actor(w))
	h.lock(actors[0])
	assert_bool(h.is_highlighted(actors[0])).is_true()
	for m in actors[0].get_children():
		assert_object(m.material_overlay).is_not_null()
	h.strike(actors[1], 5.0)
	h.strike(actors[2], 5.0)
	h.strike(actors[3], 5.0)                                      # cap 3: the oldest makes room
	assert_int(h.active_count()).is_less_equal(Highlight.MAX_ACTIVE)
	assert_bool(h.is_highlighted(actors[3])).is_true()
	h.clear(actors[3])
	for m in actors[3].get_children():
		assert_object(m.material_overlay).is_null()
	h.unlock()
	for a: Node3D in actors:
		h.clear(a)
	assert_int(h.active_count()).is_equal(0)
	for a: Node3D in actors:
		for m in a.get_children():
			assert_object(m.material_overlay).is_null()


func test_telegraph_helper_rings_only_heavy_attacks() -> void:
	var w := _world()
	var a := _actor(w)
	Telegraph.begin(a, Moves.find("goblin", "goblin_slash"), 2.2, 0.4)
	assert_int(Rings.at(w).active_count()).is_equal(0)
	assert_bool(Highlight.at(w).is_highlighted(a)).is_true()
	Telegraph.begin(a, Moves.find("troll", "troll_smash"), 3.2, 0.6)
	assert_int(Rings.at(w).active_count()).is_equal(1)
	Telegraph.end(a)
	assert_int(Rings.at(w).active_count()).is_equal(0)
	assert_bool(Highlight.at(w).is_highlighted(a)).is_false()
	Telegraph.begin_cast(a, "fire", 3.0, 0.6)
	assert_int(Rings.at(w).active_count()).is_equal(1)
	Telegraph.end(a)
