---
name: ashes-style-g-assets
description: How to make or adapt any asset (house, stall, prop, gate, wall, character, foliage) so it matches Style G - proportions, silhouettes, painterly-real texture rules, weathering, tri and texture budgets, LODs, role names, CC0 sources, bpy steps for code-built pieces (lab_gate.gd patterns), and the hooded-traveller hero, townsfolk and guard specs. Use before modelling, importing or retexturing anything for Rising Ashes.
---

# Style G assets

Look recipe: `ashes-style-g`. Judge: `ashes-style-g-qa`. Generic pipeline and licences: `ashes-asset-pipeline`, `ashes-open-source-sourcing`, `ashes-cloud-blender`.
Rule of thumb: **the material shader (`StyleG.material_for(role, orig)`) does the colour grade, bounce and AO; the asset supplies shape + a clean albedo atlas.** Never bake lighting or strong AO into the atlas (the shader adds height AO: 0.5 on houses).

## 1. Roles (set as `set_meta("role", ...)` on the node or mesh; the style restyles by role)
ground, house, stall, goods, wood, lamp, tree, flowers, ivy, gate_stone, gate_trim, iron, banner, flag, hero_new, villager, guard.
Name meshes so the character skin kind resolves: `*hair*|brow|lash|beard` hair, `*head|hands|body|skin|face|eye*` skin, `*boot|glove|shoe|belt*` leather, everything else cloth.
Anything not in the list gets role "wood" treatment (saturation 1.12). Unlisted roles must be added to `StyleG._polished` and the QA skill.

## 2. Proportions and silhouettes (storybook-chunky, slightly exaggerated)
- Townhouse: 7.75 m wide x 10.5 m deep x ~14 m tall at scale 1.0, placed at 0.8; 3 storeys, each jettied out ~0.4 m; stone ground floor, white plaster + dark timber above, steep roof (blue slate or terracotta), dormer, chimney. Timber frame is THICK (>= 0.18 m) and readable at 40 m.
- Stall: 3.5 x 2.5 x 2.5 m, striped awning (red/white or green/white) with scalloped valance, counter top at 0.9 m, front beam at z 1.13, y 1.92.
- Props are oversized by 10-20 %: barrels 0.9 m tall, crates 0.85 m, sacks 0.7 m, lamps 3.8 m, shop signs 1.3 m. Chunky bevels, no thin parts under 3 cm.
- Gatehouse: two round towers r 5-5.3 m, 17 m tall + crenellated cap (16 merlons) + slit windows; curtain wall 7.5 m with merlons 1.5 m; gate block 12 m with a **pointed arch** (r = 1.3 x half-width, half-width 4.4, springing 5.4), voussoir ring (alternating 0.95/1.3 m stones, keystone 1.5), raised portcullis, banners 2.3 x 5.2 m; conical turret roofs (cone r x1.35, height 3 r) with finial + flag.
- Trees: round leafy crowns with yellow-green rim light. Ivy: leaf clumps of 11 kite leaves 0.16-0.26 m, vines every 0.19 m.
- Silhouette test: fill the asset black at 64 px; the type (house/stall/tower) must read at once.

## 3. Texture rules (painterly-real)
- Albedo: warm, readable, hand-painted feel on a photo-real base: Poly Haven CC0 sets tinted, not raw. Used: `cobblestone_floor_01`, `castle_wall_slates`, `brown_mud_02`, `leafy_grass` (ground and gate); candidates for new work: `medieval_blocks_02`, `medieval_wood`, `clay_plaster`, `damaged_plaster`, `red_slate_roof_tiles_01`, `clay_roof_tiles`, `mossy_stone_wall`, `thatch_roof_angled`, `grassy_cobblestone`, `brown_planks_05`.
- Weathering: dirt climbing from the foot (grime 0.35 on gate stone), moss on top faces (0.12), light chipped edges on stone and plaster, sun-faded paint on awnings, rope/iron wear on timber. Edge wear lighter than the face, never white.
- Colour: palette in `StyleG.PALETTE`; no value below 0.06, no pure white. Plaster `efe3c8`, not white.
- Size: atlas 1K on phone (HIGH may use 2K for ground/gate only); one atlas per asset family; normal+ARM only for ground and gate stone (7 taps, HIGH/MEDIUM), albedo only elsewhere. Mipmaps and anisotropic filtering on.
- Do not use the SSS pass or toon outlines; do not bake rim light.

## 4. Budgets
| Asset | LOD0 | LOD1 | LOD2 | Draws |
|---|---|---|---|---|
| Townhouse | <= 13k (current kit 13.2k; prefer 8k) | 4.5k | 1.4k (1 surface) | <= 4 surfaces, shared lamp/window/glass materials across the kit |
| Stall | 2.8k | | | 2 |
| Prop (barrel, crate, sack) | 260-700 | | | merged per material |
| Character | 3-5k | 1.5k beyond 24 m | | 1-3 |
| Goods piece | <= 260 (fruit 100) | | | one merged mesh per street side |
| Ivy clump | 22 tris | | | MultiMesh |
Scene: LOW <= 150 draws and <= 300k visible tris; HIGH <= 200 / 600k (see `ashes-style-g` section 9). Name LODs `<key>:lod1`, `<key>:lod2` (`Assets.building_mesh`). Switch distance in the lab: LOD1 beyond 22 m, LOD2 beyond 36 m (LOW: LOD1 min, LOD2 beyond 20 m).
Repeated identical props: MultiMesh with per-instance colour (`COLOR` is vertex x instance colour in `lab_polished`). Unique static props: merge per material into one `ArrayMesh` (`SurfaceTool.append_from`).

## 5. Blender (bpy) for code-built pieces
Pattern from `lab_gate.gd` / `lab_gate_extra.gd`, ported to bpy (`ashes-cloud-blender` runs bpy headless):
1. Silhouette polygon in the XY plane (wall with arch opening: pointed arch points `y = spring + sqrt(r^2 - (|x| + (r - w))^2)`, r = 1.3 w), `bmesh` triangulate, extrude along -Z by the wall depth; tunnel walls from the opening polyline with normals toward the passage.
2. Round towers: cylinder 20 segments (r 5 top / 5.3 bottom), cap ring 1.3 m, 16 merlon boxes at r 5.45, slit windows 0.35 x 1.2 m at 3 levels.
3. Voussoirs: for each arch segment a box (length 0.9 x segment, thickness 0.95/1.3/1.5 keystone, depth 0.35 proud of the face) rotated to the tangent; base blocks 1.2 x 1.8 and 1.2 x 1.2 at the springing.
4. Turret: cylinder r 1.5-2.3, h 4-6, cone roof (bottom r x1.35, h 3r, 14 segments), finial 1.4 m, flag 1.1 x 0.6.
5. Materials by role names (`gate_stone`, `gate_trim`, `iron`, `flag`, `banner`) as separate material slots; export GLB with the roles as material names; UVs only needed for banners (lion texture) and atlas props - gate stone is triplanar.
6. Cull-disabled stone shader copy is used because hand-built winding may be mixed; in Blender recalc normals outside and keep back-face culling ON.
Verify in the lab with `--box=G` and the `gate` camera (QA skill).

## 6. Characters (all on the UAL skeleton: every existing clip works)
- Proportions 6.5-7 heads, not chibi. Heights: men 1.70-1.84, women 1.56-1.70, guards 1.85. Hands and face readable at 1.8 m; clothes in 2-3 flat colours + one trim.
- **Hero (hooded traveller, target 03)**: young man, brown hair, green tunic to mid-thigh, brown leather jerkin with the hood down as a collar, satchel on the right hip, bracers, belt + pouch, boots, dark trousers.
  Built by `lab_chars.hero_g()` and the game's default hero (`player.gd _build_body`, no appearance): G6 `HERO_LOOK` (Villager Tunic body 0, head 2, hair 3, colour 3) + `HeroOutfit.tint_tunic()` (tunic x (0.62,0.86,0.5), hair `8a5a32`) + `HeroOutfit.dress()`.
  **Recipe for skinned garments on the UAL skeleton** (`scripts/actors/hero_outfit.gd`): build vertices in SKELETON space from `get_bone_global_rest()`; fit radii to the visible body mesh (body verts -> skeleton space via `bone_global_rest(bind_bone(0)) * skin.get_bind_pose(0)`, torso band |x| < 0.2 so the T-pose arms do not count); per-vertex bones/weights with `SurfaceTool.set_skin_weight_count(SKIN_4_WEIGHTS)` BEFORE `begin()`; add the MeshInstance3D as a child of the Skeleton3D, `skeleton = ".."`, `skin = sk.create_skin_from_rest_transforms()`. UAL faces +Z, character's left = +X. Rings that go DOWN need the other winding (normals flip, the piece renders black). Vertex colours need `vertex_color_is_srgb`. One extra skinned draw, ~1.3k tris. Check with `tools_qa/style_lab/hero_preview.gd` (several walk phases) before the street render.
  Open: diagonal satchel strap (disabled: it fins through the arms; lay it on the jerkin shell), shaggy hair (G6 has only crops), a real hood mesh.
- **Townsfolk** (`Extra.folk`, models `villager_man_a|b`, `villager_farmer`, `villager_baker`, `elder_man`, `father`, `villager_smith`, `villager_merchant`, women `villager_woman_a|b`, `elder_woman`, `mother`, `villager_healer`): blue / red / orange / green / purple dresses and tunics, linen aprons, hats on a few. Clips: idle `Idle_Talking`, `Idle_FoldArms`, `Idle_Listening`, `Idle_Subtle`, `Greeting`, `Interact`; walk `Walk`, `Walk_Formal`, `Walking_A`, `Walk_Carry`, `Walk_Female`. Offset each clip by a random phase; beyond 24 m use the `lod1` model.
- **Guards** (`assets/incoming/ai3d/meshy/armored/guard`, 1.85 m): steel helmet and mail, blue tabard with the crest, spear 2.6 m (shaft 0.025 r, steel head), idle clip; two at stalls, two at the gate facing the street.

## 7. Free sources that fit (licence rules in `ashes-open-source-sourcing`)
Poly Haven (CC0 textures, already in `assets/incoming/polyhaven/`), Quaternius Fantasy Props MegaKit and Ultimate Food (CC0, the market goods kit), KayKit, Kenney, System G6 modular RPG humans (CC0), CDmir (CC0), ambientCG. Credit CC-BY items in `CREDITS.md`. Never raw scans without tint; never Higgsfield.
