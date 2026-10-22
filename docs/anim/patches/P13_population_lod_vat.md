# P13b: population_lod.gd — VAT crowd tier + animation LOD (cloud, small hook)

This patch touches only `scripts/population/population_lod.gd`, which is a cloud hot file. It adds about 20 lines,
and all the logic lives in `scripts/living_world/vat_residents.gd` and `crowd_anim_lod.gd`.

The tier stack it produces:

| distance (HIGH) | who | cost |
|---|---|---|
| < 14 m, nearest 8 | skeletal Villager, every frame, look-at, shadows | full |
| 14–40 m | skeletal Villager, AnimationPlayer stepped every 2–4 frames (exact phase), no look-at, no shadow past 18 m | ~1/3 |
| 40–150 m, and any resident without a full-model slot | **VAT** (VatResidents / VatCrowd): no node, one MultiMesh per look, animated in the vertex shader | ~0 CPU |
| 150–220 m | existing sprites (ImpostorBaker) | ~0 |

A side benefit: residents inside `SPRITE_MIN_DIST` (20 m) who lose the full-model race are no longer
invisible. They are drawn as VAT, which holds up at that distance.

```gdscript
# --- members
var _vat: VatResidents
var _anim_lod: CrowdAnimLOD
const VAT_RANGE := 120.0          # LOW: 70, MEDIUM: 95 (or read CrowdAnimLOD.BUDGETS[tier].far_dist)

# --- setup(baker), at the end
	_vat = VatResidents.new()
	_vat.height_fn = WorldGen.height
	add_child(_vat)
	_anim_lod = CrowdAnimLOD.new()
	_anim_lod.vat = _vat.crowd
	add_child(_anim_lod)

# --- _process(delta), first line
	if _anim_lod.camera == null or not is_instance_valid(_anim_lod.camera):
		_anim_lod.camera = get_viewport().get_camera_3d()

# --- refresh(): around the sprite loop
	_vat.begin()
	for entry in dists:
		...
		var id: int = entry[1]
		if _full.has(id):
			_sprite_hidden.erase(id)
			continue
		# NEW: VAT band (also catches close residents without a full-model slot)
		if entry[0] < VAT_RANGE * VAT_RANGE:
			var gp: Vector2 = WorldSim.pos[id]
			var cached: Array = _sprite_cache.get(id, [])
			var gy: float = (cached[1] as Vector3).y if not cached.is_empty() else WorldGen.height(gp.x, gp.y)
			if _vat.want(id, gp, WorldSim.target[id], WorldSim.job[id], WorldSim.phase[id], gy):
				_sprite_hidden.erase(id)
				continue
		if sprite_total >= sprite_budget:     # moved below the VAT check: VAT residents do not use sprite budget
			break
		... (unchanged sprite code)
	_vat.end()

# --- _spawn(id): register the skeletal body (after add_child(v))
	_anim_lod.register(id, v, v.model, v.anim, v.look_mod, VatResidents.look_of_model(v.model))
# --- where a Villager is freed (the demotion loop in refresh)
	_anim_lod.unregister(id)
```

This needs `Villager` to expose `model`, `anim` and `look_mod`, which are its current `model` local, `_anim` and the
`LookAtModifier3D` from `_add_head_look`. It also drops its own animation throttle; see P13a §7.

Hand-off: when a skeletal villager is demoted, its VAT twin appears in the same frame. A villager that drops out of
`_full` and is still inside `VAT_RANGE` goes through `_vat.want()` on the same refresh. There is no hitch or phase
jump in the other direction either, because CrowdAnimLOD seeks the skeleton to the VAT twin's clip time
(`VatCrowd.clip_time`).

Bakes: `res://assets/generated/vat/vat_<look>.res`, 9 looks, rebuilt with
`Godot --path kingdom res://tools_qa/living_world/vat_bake.tscn` (windowed, about 3 s per look). The texture total is
in HANDOFF.md.
