# Character plan: hero + crowd bodies from MPFB (MakeHuman, CC0)

Owner: player-animation worker. Status 2026-10-27: **plan only**. The 1-character pilot starts after the slice movement pass.
This supersedes `PLAYER_MODEL_MPFB_PLAN.md` (hero-only draft).

Why: next to the realistic Poly Haven and refined props, the Ashford crowd reads as faceted low-poly bodies, and the hero (Meshy hero_meshy3) has a soft head, painted-on folds and low-res hands. This is now the biggest visual gap in the benchmark slice (ref 01 KCD2).

## 1. Tools (best-tool-first)
- **MPFB 2.0.17** (installed in Blender 5.2, `extensions/user_default/mpfb`): base mesh, shape targets (age, gender, weight, muscle, height, proportions, and a full face set), skin materials, proxies, and **`rig.game_engine.json` with `weights.game_engine.json`**. The game-engine rig uses Unreal names (Root, pelvis, spine_01-03, neck_01, head, clavicle/upperarm/lowerarm/hand, thigh/calf/foot/ball, finger chains). These are the names the UAL library and our code use (CharacterAnimator, ProceduralRig sockets and foot lock, the traversal hand contacts). Every existing clip plays without a retarget step; only a rest-pose and scale check is needed.
- **MakeHuman asset packs (CC0, makehumancommunity.org):** system assets (eyes, brows, lashes, teeth, hair) and the community clothing packs. **Not on disk yet.** The download needs the owner's OK (I'll state file, source and size). Only CC0 items are used, each recorded in a LICENSE.txt.
- **Blender 5.2 headless scripts** in `tools/blender/mpfb/`: build, tailor, bake, LOD, export. Also the cloth sim for one-frame fold bakes, Decimate for LODs, and the existing `tools/blender/props/refine_lib.py` bake helpers.
- **Godot:** an `Assets.mh_character` look family, CrowdAnimLOD for the skeletal tiers, and the VAT baker plus `vat_crowd.gd` for the far crowd tier.
- **Reference only, not shipped:** the kept Meshy characters (`ProjectAshes_art_staging/meshy_keep/characters`, CATALOG.md C01-C61) set the target silhouettes and clothing layering:
  - C06 villager (tunic and cap), C11 peasant duo, C14 two maidens, C36-C38 maidens (linen, blue and brown kirtles).
  - C09 cloaked traveller, C25 armorer apron, C49 hooded beggar, C22 and C23 elders, C29-C32 guards (kettle hat, tabard).
  - The rigged ZIPs (C52-C56: guardian, knight, peasant, villager, merchant) already have UAL conversions in `meshy_dl3/characters_ual/`. They are a fallback for crowd variety if MPFB clothing falls short.

## 2. Body set
| Base | MPFB targets | Use |
|---|---|---|
| Hero (male, 18-20) | lean-muscular, weathered face, stubble/scar detail normal | player |
| Adult male x3 | thin / average / heavy, 3 face presets each | crowd, guards (under armour) |
| Adult female x3 | thin / average / sturdy, 3 face presets each | crowd |
| Elder M/F | age 65+, stooped rest offset, thinning hair | crowd |
| Child (8-12) | age target, proportions | crowd. The player's child phase also uses it, so `stride_scale` and the foot-lock policy keep working |

Variation within a base: seeded shape-key blends (2-3 face mixes, weight ±), skin tint and hair colour from a palette, and swappable clothing layers. All variants share one skeleton.

## 3. Clothing layers (medieval, about 14th century, per the lore)
- **Under:** linen shirt / chemise.
- **Mid:**
  - Men: wool tunic (knee).
  - Women: kirtle (ankle).
  - Workers: apron (leather or linen).
- **Outer:** hood (liripipe or shoulder cape), cloak pinned at the shoulder, belt with pouch and knife.
- **Legs and feet:** hose and turnshoes / ankle boots.
- **Hair:** MakeHuman CC0 hair as alpha-tested cards (2 LODs) and coif / straw hat options.

Method: MPFB proxy-fit each garment to the base, a one-frame cloth-sim for real folds baked to normal/AO, and hidden-body-face deletion per layer combination. That deletion prevents poke-through in the run, ladder and sit clips, and cuts tris.

## 4. Budgets (min-spec: integrated GPU)
| Tier | Tris | Textures | Notes |
|---|---|---|---|
| Hero LOD0 | 15-20k | 2K body (albedo / normal / ORM) + 2K clothing atlas + 1K hair | most texel density on the face and hands |
| Hero LOD1 | about 6k | same set, mip-biased | beyond about 8 m |
| Crowd LOD0 | about 8k | 1K body + 1K shared clothing atlas | CrowdAnimLOD NEAR |
| Crowd LOD1 | about 3k | shared | MID |
| Crowd LOD2 | about 1k | 512 | far skeletal |
| VAT far tier | about 1k (LOD2 baked) | 512 + VAT texture | existing `vat_crowd.gd` path |

Skin: one StandardMaterial3D with a subsurface-tinted albedo (no SSS pass on min-spec) and a pore detail normal at LOD0 only. Hair: alpha scissor, never alpha blend. Crowd looks merge body and clothing into one surface per LOD (atlas), so each person is 1 draw at MID and far. Cap: 6 clothing atlases per settlement, with palette tints in the shader.

## 5. Steps
1. **Asset packs:** list the exact CC0 packs with size, get the owner's OK, download to `ProjectAshes_art_staging/downloads/makehuman/`, record licences.
2. **`build_body.py --base hero|m|f|elder|child --seed N`:** MPFB human from targets, game_engine rig, A-pose matched to the UAL rest (measure the arm angle; bake a rest correction if needed), and the eyes/brows/lashes/teeth proxies.
3. **`tailor.py`:** fit layers, cloth-sim fold bake, delete hidden faces, atlas-pack each look.
4. **`bake_lod.py`:** textures to budget, LOD0/1/2, export GLB with the skin. LOD2 also goes through the VAT baker.
5. **Godot:** add an `mpfb` look family behind a flag. Re-measure the ProceduralRig sockets (hip, back, shield, carry) per base with `equip_matrix --list_attach`. HeroOutfit is not used on MPFB bodies, because their clothing is real geometry.
6. **Animation check (no retarget needed):** rest pose, scale (`REF_LEG_HEIGHT` / stride), finger curl. Run `loco_slide` (child and adult), `equip_matrix` (idle/walk/run/ladder/sit/combat/carry) and `ladder_movie`.
7. **Gate:**
   - Pilot: the slice route side by side, plus equip_matrix sheets at gameplay distance against ref 01.
   - Crowd: Ashford market at 11:00 and 19:00 with 40 NPCs, judged by eye.
   - Perf: crowd frame time on the min-spec profile against the current looks.
   - Log both in AAA_GATE_LOG; switch defaults only on PASS.

## 6. Pilot (one character, after the movement pass)
**Ashford villager man** (crowd LOD0 8k / LOD1 3k / LOD2 1k / VAT): average build, linen shirt, brown wool tunic, hood, belt and pouch, hose, turnshoes. It exercises every crowd stage (skeletal NEAR/MID, VAT far) and needs no hero-only features. Exit criteria:
- every Life_* and loco clip plays without poke-through;
- feet planted (loco_slide);
- reads realistic next to the Poly Haven props at 3 m and at 15 m;
- the VAT bake matches the skeletal pose at the tier switch.

The hero follows once the pilot passes.

## 7. Risks
- **Uncanny-smooth faces** (a MakeHuman default): detail normal (pores, stubble), roughness variation, slightly asymmetric blends; review at 3 m.
- **Shoulder/hip weights** under UAL's wide arm swing and the deep ladder knees: test run, ladder and sit on the naked base before any clothing; add corrective smoothing if needed.
- **Clothing poke-through** across 65-bone deformation: hidden-face deletion per combination, and a small normal push on the outer layers.
- **Licensing:** CC0 items only (some community items are CC-BY); keep a LICENSE.txt next to every GLB.
- **Disk and RAM** (about 6 GB free, 16 GB shared): one headless Blender job at a time; source .blend files in art_staging (not git); commit only GLBs within budget.
- **Variety vs batching:** too many atlases break batching, so use the settlement cap above.
