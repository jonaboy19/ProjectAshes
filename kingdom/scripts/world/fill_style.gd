extends RefCounted
## Style G treatment for the meshy_free pack models placed by region1_fill / fill_sites.json (and any other "free:" kit
## piece with the same name). Assets.static_model already gives every surface its role material (palette atlas kept);
## this adds the per-model remap on top: desaturate toward the Style G palette, pull value down, matte the gloss
## (roughness up, specular down) and optionally force another role (trees, flowers, goods, wood).
## Models in DROPPED are not placed at all (fill_sites.json no longer lists them; the list is the test contract).
## Preload; no class_name.

const StyleG := preload("res://scripts/style_g.gd")

## Off-style even after treatment: pink/pastel castle tower, white-and-orange toy church, saturated dragons, candy crystals
## and glowing orbs/mushrooms, yellow/blue whimsical lantern, flat toy hay bales, neon chickens and the neon cartoon tree.
const DROPPED := [
	"castle/tower_pink_flag", "churches/church_white_red_spire", "creatures/dragon_fire_small", "creatures/dragon_green_armored",
	"magic/crystal_egg_purple", "magic/crystal_red_pedestal", "magic/orb_purple_roots", "lighting/street_lantern_whimsical",
	"farm/chicken_hen", "farm/chicken_rooster", "farm/hay_bale_lowpoly", "farm/hay_bale_yellow_large",
	"nature/tree_cartoon_green_a", "flora/mushroom_glow_brown",
]

## model (category/name) -> shader overrides {role?, saturation?, value_gain?, roughness?, spec?}.
const TREAT := {
	"castle/castle_sandstone_a": {"saturation": 0.72, "value_gain": 0.94, "roughness": 0.9},
	"castle/castle_sandstone_b": {"saturation": 0.6, "value_gain": 0.86, "roughness": 0.9},
	"castle/gate_twin_towers_blue": {"saturation": 0.55, "value_gain": 0.92, "roughness": 0.9},
	"churches/church_gothic_red": {"saturation": 0.7, "value_gain": 0.95},
	"buildings/house_cottage_chimney": {"saturation": 0.72, "value_gain": 0.9},
	"buildings/butcher_house": {"saturation": 0.75, "value_gain": 0.92},
	"buildings/blacksmith_thatch_stone": {"saturation": 0.8},
	"farm/shed_plank_low": {"saturation": 0.65, "value_gain": 0.9},
	"farm/shed_thatch_small": {"saturation": 0.55, "value_gain": 0.85},
	"farm/shed_wood_shingle": {"saturation": 0.65, "value_gain": 0.9},
	"farm/chicken_coop_fenced": {"saturation": 0.7, "value_gain": 0.92},
	"farm/hay_bale_round": {"role": "goods", "saturation": 0.5, "value_gain": 0.82},
	"farm/hay_bale_rect_a": {"role": "goods", "saturation": 0.55, "value_gain": 0.88},
	"fences/fence_board_gate": {"saturation": 0.6, "value_gain": 0.9},
	"fences/fence_gate_rail": {"saturation": 0.7},
	"fences/fence_picket_low": {"saturation": 0.72, "value_gain": 0.92},
	"fences/fence_picket_tall": {"saturation": 0.72, "value_gain": 0.92},
	"fences/fence_broken_rail": {"saturation": 0.8},
	"nature/tree_pine": {"role": "tree", "saturation": 0.75, "value_gain": 0.9},
	"nature/tree_cartoon_green_b": {"role": "tree", "saturation": 0.65, "value_gain": 0.88},
	"flora/bouquet_wild": {"role": "flowers", "saturation": 0.6, "value_gain": 0.88},
	"flora/bush_raspberry": {"role": "foliage", "saturation": 0.75},
	"lighting/street_lamp_twin_gold": {"saturation": 0.55, "value_gain": 0.82, "roughness": 0.9, "spec": 0.12},
	"lighting/lamp_post_purple_bracket": {"saturation": 0.4, "roughness": 0.9, "spec": 0.12},
	"lighting/lantern_post_purple": {"saturation": 0.4, "roughness": 0.9, "spec": 0.12},
	"props/chest_blue_iron": {"role": "wood", "saturation": 0.55, "roughness": 0.9, "spec": 0.12},
	"props/chest_copper_lock": {"role": "wood", "saturation": 0.55, "roughness": 0.9, "spec": 0.12},
	"props/chest_metal_wood": {"role": "wood", "saturation": 0.7, "roughness": 0.9, "spec": 0.12},
	"props/chest_orange_riveted": {"role": "wood", "saturation": 0.5, "roughness": 0.9, "spec": 0.12},
	"props/chest_orange_wood": {"role": "wood", "saturation": 0.5, "roughness": 0.9, "spec": 0.12},
	"props/chest_red_black": {"role": "wood", "saturation": 0.55, "roughness": 0.9, "spec": 0.12},
	"props/chest_silver_lock": {"role": "wood", "saturation": 0.7, "roughness": 0.9, "spec": 0.12},
	"furniture/tavern_set_barrels_b": {"role": "goods"},
	"furniture/table_barrel_top": {"role": "goods"},
	"water/boat_longship_sail": {"saturation": 0.75},
	"creatures/wolf_brown": {"roughness": 0.95, "spec": 0.1},
	"creatures/wolf_ghost": {"roughness": 0.95, "spec": 0.1},
}
## banners (all banners/*): sun-faded cloth, not candy
const BANNER := {"saturation": 0.78, "value_gain": 0.95}

static var _cache := {}


static func is_dropped(model: String) -> bool:
	return DROPPED.has(model)


## "free:castle/castle_sandstone_a@17.32" or "castle/castle_sandstone_a" -> "castle/castle_sandstone_a".
static func model_of(asset: String) -> String:
	return asset.trim_prefix("free:").split("@")[0]


## The override dictionary for a model ({} = untreated, the role material alone).
static func spec_for(model: String) -> Dictionary:
	if TREAT.has(model):
		return TREAT[model]
	if model.begins_with("banners/"):
		return BANNER
	return {}


## Per-instance surface overrides on every MeshInstance3D under `root` (the mesh stays shared and untouched).
static func apply(root: Node, asset: String) -> int:
	var spec := spec_for(model_of(asset))
	if spec.is_empty() or root == null or OS.get_cmdline_user_args().has("--fillstyleoff"):     # flag: QA before/after renders
		return 0
	var n := 0
	var nodes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		nodes.append(root)
	for node in nodes:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := treated(mi.get_active_material(i), spec)
			if m != null:
				mi.set_surface_override_material(i, m)
				n += 1
	return n


## A copy of a Style G material with the overrides applied (cached per source material and spec). null when the material is not
## a Style G polished material (emissive / transparent surfaces keep their own look).
static func treated(mat: Material, spec: Dictionary) -> ShaderMaterial:
	if not StyleG.is_styled(mat):
		return null
	var key := "%d|%s" % [mat.get_instance_id(), str(spec)]
	if _cache.has(key) and is_instance_valid(_cache[key]):
		return _cache[key]
	var base: Material = mat
	if spec.has("role"):
		var src := StyleG.source_of(mat)
		var by_role := StyleG.material_for(String(spec["role"]), src, 1, StyleG.current_tier(), true)
		if by_role is ShaderMaterial:
			base = by_role
	var sm := (base as ShaderMaterial).duplicate() as ShaderMaterial
	sm.set_meta("g_src", StyleG.source_of(mat))
	for k: String in ["saturation", "value_gain", "roughness", "spec"]:
		if spec.has(k):
			sm.set_shader_parameter(k, float(spec[k]))
	_cache[key] = sm
	return sm
