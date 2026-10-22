extends RefCounted
## Style G treatment for the meshy_free pack models placed by region1_fill / fill_sites.json (and any other "free:" kit
## piece with the same name). Assets.static_model already gives every surface its role material (palette atlas kept);
## this adds the per-model remap on top: desaturate toward the Style G palette, pull value down, matte the gloss
## (roughness up, specular down) and optionally force another role (trees, flowers, goods, wood).
## Models in DROPPED are not placed at all (fill_sites.json no longer lists them; the list is the test contract).
## Meshy batch 3 (assets/incoming/meshy_dl3, asset keys "dl3:<cat>/<name>@H") goes through the same pass; its models are keyed
## "dl3/<cat>/<name>" in DROPPED / TREAT (see DL3_REJECT, DL3_UNPLACED and docs/art/meshy_dl3/README.md "Triage").
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
	# Meshy batch 3 (dl3): realistic PBR bakes, brighter and more saturated than Style G; models not listed are kept as they are.
	"dl3/buildings/cottage_blue_roof": {"saturation": 0.55, "value_gain": 0.92, "roughness": 0.9},
	"dl3/buildings/cottage_orange_roof": {"saturation": 0.6, "value_gain": 0.92, "roughness": 0.9},
	"dl3/buildings/cottage_thatch_timber": {"saturation": 0.75, "value_gain": 0.95},
	"dl3/buildings/house_orange_thatch": {"saturation": 0.5, "value_gain": 0.88},
	"dl3/buildings/house_straw_thatch": {"saturation": 0.75, "value_gain": 0.95},
	"dl3/buildings/tavern_red_roof": {"saturation": 0.6, "value_gain": 0.92, "roughness": 0.9},
	"dl3/camp/tent_shop_canopy": {"saturation": 0.8},
	"dl3/carts/wagon_shields_covered": {"saturation": 0.6, "value_gain": 0.9},
	"dl3/market/stall_rug_wood": {"saturation": 0.65, "value_gain": 0.92},
	"dl3/castle/fortress_grey_blue": {"saturation": 0.6, "value_gain": 0.92, "roughness": 0.9},
	"dl3/creatures/horse_saddled_brown": {"saturation": 0.8, "roughness": 0.95, "spec": 0.1},
	"dl3/creatures/elemental_earth_golem": {"saturation": 0.75, "value_gain": 0.9},
	"dl3/furniture/table_bench_set": {"saturation": 0.8},
	"dl3/furniture/bench_lantern_posts": {"saturation": 0.8},
	"dl3/furniture/table_long_wood": {"saturation": 0.8},
	"dl3/magic/rack_elixirs": {"saturation": 0.55, "value_gain": 0.88},
	"dl3/props/keg_big": {"saturation": 0.8},
	"dl3/props/chest_iron_banded": {"saturation": 0.75, "value_gain": 0.9, "roughness": 0.9},
	"dl3/props/firewood_stack_oven": {"saturation": 0.8},
	"dl3/props/shield_round_wood": {"saturation": 0.6, "value_gain": 0.9},
	"dl3/props/swords_scabbards_trio": {"saturation": 0.8},
}
## banners (all banners/*): sun-faded cloth, not candy
const BANNER := {"saturation": 0.78, "value_gain": 0.95}

const DL3_ROOT := "res://assets/incoming/meshy_dl3/"
## Meshy batch 3 rejects (every model with a LOD0 in assets/incoming/meshy_dl3 that is NOT placed, shipped or kept for later use):
## toy/cartoon colour (teal or sky-blue roofs), glowing/burning or ruined shells, diorama bases, flat UI-like icon plates, candy eggs,
## VFX-like flame/ice elementals, untextured or failed-rig characters. They are in export_presets.cfg's exclude_filter and
## never placed (DROPPED includes them; tests/test_fill_style.gd checks both).
const DL3_REJECT := [
	"dl3/buildings/cottage_straw_roof_a", "dl3/buildings/cottage_straw_roof_b", "dl3/buildings/tavern_blue_porch",
	"dl3/buildings/tavern_drunken_dragon", "dl3/castle/armory_keep", "dl3/castle/tower_round_orange_roof", "dl3/camp/tent_hide_conical",
	"dl3/creatures/elemental_fire", "dl3/creatures/elemental_water",
	"dl3/magic/eggs_elemental_four", "dl3/magic/runestones_elemental_four", "dl3/magic/sigils_elemental_eight",
	"dl3/magic/circle_elemental_platform", "dl3/magic/emblem_four_elements", "dl3/magic/potion_green_vine_base",
	"dl3/characters_static/knight_plate_shield",
	"dl3/characters_rigged/knight_plate_grey", "dl3/characters_rigged/noblewoman_cape", "dl3/characters_rigged/soldier_shield_sword",
]
## Kept models with no placement yet (too small, no water/plinth/interior to put them in): excluded from the export until used.
const DL3_UNPLACED := [
	"dl3/churches/cathedral_romanesque", "dl3/characters_static/ser_duncan_knight", "dl3/characters_static/hobo_hooded_beggar",
	"dl3/loot/coin_gold", "dl3/loot/coin_silver", "dl3/props/door_round_wood", "dl3/props/helmet_sentinel",
	"dl3/props/pier_plain", "dl3/props/pier_rope_rails", "dl3/props/pier_stairs_bench",
]

static var _cache := {}


static func is_dropped(model: String) -> bool:
	return DROPPED.has(model) or DL3_REJECT.has(model)


## "free:castle/castle_sandstone_a@17.32" or "castle/castle_sandstone_a" -> "castle/castle_sandstone_a".
static func model_of(asset: String) -> String:
	if asset.begins_with("dl3:"):
		return "dl3/" + asset.substr(4).split("@")[0]
	return asset.trim_prefix("free:").split("@")[0]


## "dl3:buildings/cottage_blue_roof@5" or "dl3/buildings/cottage_blue_roof" -> res:// path of its LOD (0 or 1).
static func dl3_path(asset: String, lod := 0) -> String:
	var m := model_of(asset) if asset.begins_with("dl3:") else asset
	return DL3_ROOT + m.trim_prefix("dl3/") + "_lod%d.glb" % lod


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
