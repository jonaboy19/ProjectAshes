class_name ScatterWorldModifier
extends ScatterBaseModifier
## ProtonScatter modifier that ties the scatter to the game world (terrain_backend = terrain3d). Sits after "Create Inside (Random)":
##   - projects every point onto WorldGen.height (so trees stand on exactly the ground navigation/collision/building use),
##   - keeps it only if the world wants that kind of thing there (forest_density, height, water) AND ScatterExclusion allows it
##     (roads, streets, settlements, site clearings, build-kit grids, founded settlements),
##   - gives it a yaw, a scale and the slope-aware sink the legacy forest used.
## Pure maths on static WorldGen data: safe on ProtonScatter's worker thread.

@export_enum("tree", "undergrowth", "meadow", "rock") var role := "tree"
## Chance that a candidate point that passes the world rules is kept (undergrowth/meadow/rock thin themselves with it).
@export var keep_chance := 1.0
@export var scale_min := 0.8
@export var scale_max := 1.25
@export var salt := 0
## Written by the worker thread when a pass ends (ProtonScatter emits no build_completed for an empty result).
var runs := 0
var last_kept := -1


func _init() -> void:
	display_name = "World rules (WorldGen height + exclusion zones)"
	category = "Edit"
	can_override_seed = false
	warning_ignore_no_shape = true
	warning_ignore_no_transforms = true


## "tree" / "rock" / "plant": the ScatterExclusion kind of a role.
func exclusion_kind() -> String:
	return "tree" if role == "tree" else ("rock" if role == "rock" else "plant")


## Whether the world allows `role` at (x, z) (no randomness; the keep_chance roll comes after).
func allows(x: float, z: float) -> bool:
	var h := WorldGen.height(x, z)
	var biome := WorldBiomes.at(x, z)   # LEGACY (-1) unless the Valencious macro is on: then the biome sets the height cap and tree share
	if h > WorldBiomes.max_height(role, biome):
		return false
	var density := WorldBiomes.tree_density(biome, WorldGen.forest_density(x, z))
	match role:
		"tree":
			if density < 0.02:
				return false
		"undergrowth":
			if density <= 0.35:
				return false
		"meadow":
			if density > 0.35:
				return false
	if role == "rock":
		# Legacy rule: no rocks on a settlement's flatten-to-natural slope band (radius..radius*1.8).
		var near := WorldGen.nearest_settlement(Vector2(x, z))
		if not near.is_empty() and Vector2(x, z).distance_to(near["pos"]) < float(near["radius"]) * 1.8:
			return false
	return not ScatterExclusion.blocked(x, z, exclusion_kind())


func _process_transforms(transforms, _domain, random_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed ^ salt
	var kept: Array[Transform3D] = []
	for t: Transform3D in transforms.list:
		var x := t.origin.x
		var z := t.origin.z
		# Always draw the same numbers per candidate so a rejected neighbour never shifts the survivors.
		var roll := rng.randf()
		var yaw := rng.randf() * TAU
		var s := rng.randf_range(scale_min, scale_max)
		if not allows(x, z):
			continue
		var biome := WorldBiomes.at(x, z)
		var density := WorldBiomes.tree_density(biome, WorldGen.forest_density(x, z))
		if role == "tree" and roll >= density:
			continue
		if role != "tree":
			var keep := keep_chance
			if biome >= 0:
				var scar := 1.0
				if biome == WorldBiomes.RIFT and role != "meadow":
					scar += WorldBiomes.scar_boost(x, z) * 1.5      # scar slot: more dead wood and rock round the breaches
				keep = minf(1.0, keep * WorldBiomes.keep_mult(role, biome) * scar)
			if roll >= keep:
				continue
		var h := WorldGen.height(x, z)
		var slope := absf(WorldGen.height(x + 0.6, z) - h) + absf(WorldGen.height(x, z + 0.6) - h)
		var sink := 0.15 + minf(slope * 0.7, 0.55)
		kept.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(x, h - sink, z)))
	transforms.list = kept
	last_kept = kept.size()
	runs += 1
