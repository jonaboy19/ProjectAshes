extends GdUnitTestSuite
## P1 powers and VFX: the technique timing template (AbilityRunner-driven), the element language table, the toon
## shaders / pooled burst, pooled ground decals and the omni-free torch lamps (street_lamp group kept).

const Lang := preload("res://scripts/vfx/element_language.gd")
const Toon := preload("res://scripts/vfx/toon_vfx.gd")
const Decals := preload("res://scripts/vfx/ground_decals.gd")
const TechniqueVfx := preload("res://scripts/vfx/technique_vfx.gd")
const Runner := preload("res://scripts/abilities/ability_runner.gd")
const AbilityDef := preload("res://scripts/abilities/ability_def.gd")
const LampGlow := preload("res://scripts/world/lamp_glow.gd")
const LampNode := preload("res://scripts/world/lamp_node.gd")
const TorchProps := preload("res://scripts/world/torch_props.gd")
const NpcWorldScript := preload("res://scripts/population/npc_world.gd")


func _def(id: String, shape := "projectile", windup := 0.4, element := "fire", extra := {}) -> Dictionary:
	var row := {"id": id, "name": id, "path": "magic", "element": element, "cooldown": 1.0, "windup": windup,
		"damage": 10, "costs": {}, "targeting": {"kind": shape, "range": 12.0, "radius": 2.5}}
	row.merge(extra, true)
	return AbilityDef.normalise(row)


func _rig() -> Dictionary:
	var world := Node3D.new()
	add_child(world)
	auto_free(world)
	var caster := Node3D.new()
	world.add_child(caster)
	caster.global_position = Vector3(0, 1.2, 0)
	var tv: Node = TechniqueVfx.new()
	caster.add_child(tv)
	return {"world": world, "caster": caster, "tv": tv}


# --- element language -----------------------------------------------------------------

func test_language_covers_every_element_and_path() -> void:
	for id in ["fire", "water", "earth", "wind", "lightning", "qi", "knight"]:
		var l := Lang.get_lang(id)
		assert_str(String(l["id"])).is_equal(id)
		assert_bool(l["core"] is Color and l["mid"] is Color and l["edge"] is Color and l["hud"] is Color).is_true()
		assert_str(String(l["shape"])).is_not_empty()
		assert_str(String(l["decal"])).is_not_empty()
	var shapes := {}
	for id in ["fire", "water", "earth", "wind", "lightning", "qi", "knight"]:
		shapes[Lang.shape(id)] = true
	assert_int(shapes.size()).is_equal(7)               # tongues ribbons chunks spirals forks rings aura
	assert_str(Lang.canon("frost")).is_equal("ice")
	assert_str(Lang.canon("none", "knight")).is_equal("knight")
	assert_str(Lang.canon("sect")).is_equal("qi")
	assert_str(Lang.canon("nonsense")).is_equal("qi")
	assert_that(Lang.tint("fire")).is_equal(Lang.color("fire", "hud"))
	assert_bool(Lang.tint("fire") != Lang.tint("water")).is_true()


# --- timing template ----------------------------------------------------------------------

func test_schedule_order_and_residue_window() -> void:
	for shape in ["projectile", "aoe", "melee", "chain", "cone"]:
		var s := TechniqueVfx.schedule(_def("x", shape, 0.4), 10.0)
		var prev := -1.0
		for ph in ["anticipation", "flash", "travel", "impact", "residue"]:
			var w: Array = s[ph]
			assert_float(float(w[0])).is_greater_equal(prev)
			assert_float(float(w[1])).is_greater_equal(float(w[0]))
			prev = float(w[0])
		var res := float((s["residue"] as Array)[1]) - float((s["residue"] as Array)[0])
		assert_float(res).is_between(0.5, 1.0)
		assert_float(float((s["flash"] as Array)[0])).is_less_equal(float(s["release"]))
	assert_float(float((TechniqueVfx.schedule(_def("p", "projectile"), 12.0)["travel"] as Array)[1])
		- float((TechniqueVfx.schedule(_def("p", "projectile"), 12.0)["travel"] as Array)[0])).is_greater(0.2)
	var melee := TechniqueVfx.schedule(_def("m", "melee"), 12.0)
	assert_float(float((melee["travel"] as Array)[1]) - float((melee["travel"] as Array)[0])).is_equal(0.0)


func test_runner_phases_drive_the_template() -> void:
	var rig := _rig()
	var tv: Node = rig["tv"]
	tv.visuals = false
	var def := _def("firebolt", "projectile", 0.4)
	var r := Runner.new()
	r.costs_enabled = false
	r.hooks = {"lookup": func(_id: String) -> Dictionary: return def}
	tv.bind_runner(r, {"origin": func() -> Vector3: return Vector3(0, 1.2, 0), "aim": func() -> Vector3: return Vector3.FORWARD,
		"world": func() -> Node: return rig["world"]})
	var seen: Array[String] = []
	tv.phase_entered.connect(func(_id: String, ph: String, _run: Dictionary) -> void: seen.append(ph))
	var res := r.begin("firebolt", {})
	assert_bool(bool(res["ok"])).is_true()
	assert_array(seen).is_equal(["anticipation"])
	var t := 0.0
	while t < 3.0 and tv.active_runs() > 0:
		r.update(0.05)
		tv.advance(0.05)
		t += 0.05
	assert_array(seen).is_equal(["anticipation", "flash", "glow", "travel", "impact", "residue"])
	assert_int(tv.active_runs()).is_equal(0)


func test_flash_comes_before_the_release_and_interrupt_cancels() -> void:
	var rig := _rig()
	var tv: Node = rig["tv"]
	tv.visuals = false
	var def := _def("quake", "aoe", 0.5, "earth")
	var r := Runner.new()
	r.costs_enabled = false
	r.hooks = {"lookup": func(_id: String) -> Dictionary: return def}
	tv.bind_runner(r, {})
	var seen: Array[String] = []
	tv.phase_entered.connect(func(_id: String, ph: String, _run: Dictionary) -> void: seen.append(ph))
	r.begin("quake", {})
	r.update(0.42)
	tv.advance(0.42)
	assert_bool(seen.has("flash")).is_true()
	assert_bool(seen.has("impact")).is_false()          # not released yet: impact waits for the runner's execute
	r.interrupt()
	assert_int(tv.active_runs()).is_equal(0)
	r.update(1.0)
	tv.advance(1.0)
	assert_bool(seen.has("impact")).is_false()


func test_template_with_visuals_pools_and_stays_in_budget() -> void:
	var rig := _rig()
	var tv: Node = rig["tv"]
	Decals.clear()
	var before := Toon.live_count()
	for i in 6:
		tv.begin("t%d" % i, _def("t%d" % i, "aoe", 0.2, ["fire", "water", "earth", "knight", "wind", "lightning"][i]),
			{"to": Vector3(i, 0, -4)})
	for i in 60:
		tv.advance(0.05)
	assert_int(Toon.live_count()).is_less_equal(Toon.MAX_LIVE)
	assert_int(Decals.active_count()).is_less_equal(Decals.cap())
	for i in 80:
		tv.advance(0.05)
	assert_int(tv.active_runs()).is_equal(0)
	assert_int(Toon.live_count()).is_less_equal(before + Toon.MAX_LIVE)


# --- toon shaders / burst -------------------------------------------------------------------

func test_toon_shaders_and_burst_preset() -> void:
	assert_str(Toon.MASK_SHADER.code).contains("step(threshold")
	assert_str(Toon.BURST_SHADER.code).contains("progress")
	var world := Node3D.new()
	add_child(world)
	auto_free(world)
	var ring: MeshInstance3D = Toon.ring(world, Vector3.ZERO, "fire", 3.0, 1.0)
	assert_object(ring).is_not_null()
	var m := ring.material_override as ShaderMaterial
	assert_that(m.get_shader_parameter("mid_color")).is_equal(Lang.color("fire", "mid"))
	for i in 40:
		Toon.burst(world, Vector3(i, 0, 0), "earth", 2.0)
	assert_int(Toon.live_count()).is_less_equal(Toon.MAX_LIVE)
	var shell: MeshInstance3D = Toon.shell(world, "knight", 1.0, 0.5)
	assert_object(shell).is_not_null()
	Toon.release(shell, 0.0)
	assert_bool(shell.visible).is_false()


# --- decals ---------------------------------------------------------------------------------------

func test_decals_are_pooled_capped_and_fade() -> void:
	var world := Node3D.new()
	add_child(world)
	auto_free(world)
	Decals.clear()
	for k in Decals.KINDS:
		assert_object(Decals.texture(k)).is_not_null()
	assert_str(Decals.for_element("fire")).is_equal("scorch")
	assert_str(Decals.for_element("ice")).is_equal("frost")
	for i in 40:
		Decals.spawn(world, Decals.KINDS[i % Decals.KINDS.size()], Vector3(i, 0, 0), 2.0, 0.6)
	assert_int(Decals.active_count()).is_less_equal(Decals.cap())
	Decals.force_quad = true                              # the Compatibility renderer path: projected quads
	Decals.clear()
	var q := Decals.spawn(world, "scorch", Vector3.ZERO, 2.0, 0.5)
	assert_bool(q is MeshInstance3D).is_true()
	Decals.force_quad = false
	var d := Decals.spawn(world, "frost", Vector3(3, 0, 0), 2.0, 0.5)
	assert_bool(d is Decal or d is MeshInstance3D).is_true()
	Decals.clear()
	assert_int(Decals.active_count()).is_equal(0)


func test_crack_decal_is_sized_to_the_technique_radius_not_the_floor() -> void:
	var quake := Lang.get_lang("earth")
	assert_str(String(quake["decal"])).is_equal("cracks")
	# earth_quake radius 6.5 m: a few metres across (it used to be radius * 1.3 = 8.5 m, plus a 13 m ground plane)
	var sz := Decals.size_for(quake, 6.5)
	assert_float(sz).is_between(2.0, 5.0)
	assert_float(Decals.crack_size(6.5)).is_less_equal(Decals.CRACK_MAX)
	assert_float(Decals.crack_size(0.5)).is_equal(Decals.CRACK_MIN)
	assert_float(Decals.size_for(quake, 2.5)).is_less(Decals.size_for(quake, 6.5) + 0.001)
	assert_float(Decals.size_for(Lang.get_lang("fire"), 3.0)).is_equal_approx(3.9, 0.001)   # other decal kinds keep radius * 1.3
	# spawn() caps a crack whatever the caller asks, and it fades out (pooled, retired after its life)
	var world := Node3D.new()
	add_child(world)
	auto_free(world)
	Decals.clear()
	Decals.force_quad = true
	var q := Decals.spawn(world, "cracks", Vector3.ZERO, 14.0, 0.5) as MeshInstance3D
	Decals.force_quad = false
	assert_object(q).is_not_null()
	assert_float(q.global_transform.basis.get_scale().x).is_less_equal(Decals.CRACK_MAX + 0.01)
	assert_object(q.get_meta("tw")).is_not_null()
	Decals.clear()


# --- torches / lamps --------------------------------------------------------------------------------

func test_lamps_have_no_omni_on_low_and_medium_but_keep_the_group() -> void:
	var q := get_node_or_null("/root/Quality")
	var old_tier: int = int(q.get("tier")) if q else 2
	var root := Node3D.new()
	add_child(root)
	auto_free(root)
	var br := TorchProps.brazier(root, Vector3(4, 0, 4))
	assert_int((br["node"] as MeshInstance3D).mesh.get_surface_count()).is_equal(3)   # iron, fire, coals (AAA pass 2 wrought basket with a coal heap)
	var specs := [{"pos": Vector3(0, 3, 0), "range": 9.0}, {"pos": Vector3(6, 3, 0), "range": 8.0}, {"pos": br["glow_pos"], "range": 7.0}]
	if q:
		q.set("tier", 0)
	var lamps := LampGlow.build(root, specs)
	assert_int(lamps.size()).is_equal(3)
	for tier in [0, 1]:
		if q:
			q.set("tier", tier)
		for l: LampNode in lamps:
			l._on_quality()
			assert_bool(l.has_omni()).is_false()
			assert_bool(l.is_in_group("street_lamp")).is_true()
		assert_int(root.find_children("*", "OmniLight3D", true, false).size()).is_equal(0)
	# night switch as main.gd does it: light_energy on every group member
	for l in get_tree().get_nodes_in_group("street_lamp"):
		l.set("light_energy", 1.6)
		(l as Node3D).visible = true
	assert_float(float((lamps[0] as Node3D).get("light_energy"))).is_equal(1.6)
	assert_float(float((lamps[0] as Node3D).get("omni_range"))).is_equal(9.0)
	var batch := root.get_node("LampGlowBatch") as MultiMeshInstance3D
	assert_bool(batch.visible).is_true()
	assert_float(float((batch.material_override as ShaderMaterial).get_shader_parameter("lit"))).is_equal(1.0)
	assert_int(batch.multimesh.instance_count).is_equal(3)
	# HIGH tier adds the real light
	if q:
		q.set("tier", 2)
		(lamps[0] as LampNode)._on_quality()
		assert_bool((lamps[0] as LampNode).has_omni()).is_true()
		q.set("tier", old_tier)
	for l: LampNode in lamps:
		l.light_energy = 0.0
		l.queue_free()
