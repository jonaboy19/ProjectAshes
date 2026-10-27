# Rising Ashes: AAA tools and gap audit (2026-10-28)

Rising Ashes is measured here against how KCD2, Assassin's Creed, RDR2, Bellwright and Manor Lords are built, discipline by discipline. The audit covers what is on disk, whether it is actually used, what is missing, and the best free (commercial-OK) tool to close each gap.
Method: `ls kingdom/addons`, greps over `kingdom/scripts`, `scenes`, `autoload` and `project.godot` (addon dirs excluded), the plan docs (FULL_GAME_GAP_AUDIT, MECHANICS_AUDIT, MASTER_BACKLOG, BENCHMARK_SLICE, NPC_MOTION_RULES, CHARACTER_PLAN, ART_DIRECTION), the skills (best-tool-first, external-tools, aaa-gate) and `git log`. Licences were checked at the source (GitHub API licence field or LICENSE file, or the vendor page) on 2026-10-28. Nothing was installed.
Priority: **P0** = blocks the benchmark slice looking AAA · **P1** = v1 · **P2** = later. Effort: S (≤1 day), M (2-5 days), L (1-3 weeks).

## Ground truth: built-ins (file counts in game code)
| Built-in | Used? | Where / note |
|---|---|---|
| SDFGI | PC_HIGH/ULTRA only | `core/quality.gd`. LOW/MED have no GI at all |
| VoxelGI / LightmapGI | **0 / 0** | interiors and dungeons have no baked or probe GI |
| ReflectionProbe | **0** | interiors and wet streets have no local reflections |
| OccluderInstance3D | 1 file | `world/settlement_builder.gd` box occluders inside town lots only. Nothing for terrain, walls or interiors |
| visibility_range | 35 files | widely used, plus our own octahedral impostors (`core/impostor_baker.gd`) and VAT crowd |
| Decal | 15 files | footprints, ground decals, town decals |
| FogVolume | **0** | per-biome and local fog is global only. Volumetric fog is off outdoors on the slice (commit e83f51a9) |
| Compositor / CompositorEffect | **0** | grading is done through `Environment` only |
| TAA / upscaling | TAA off on all PC tiers; FSR2 → FSR1 when Terrain3D is on (`quality.gd:793`) | the slice therefore runs FSR1 + FXAA, which shimmers on foliage |
| GPUParticles3D | 84 files | particle collision and attractors are unused (0) |
| SpringBoneSimulator3D | player + horses | no NPC capes, hoods or hair |
| PhysicalBoneSimulator3D | `ragdoll.gd`, `partial_ragdoll`, `soldier.gd` | used |
| LookAtModifier3D | 7 files | used. Villagers hand-lerp instead of using `duration`/`transition_type` |
| 4.6 IK (TwoBoneIK3D, FABRIK3D, CCDIK3D, SplineIK3D) | TwoBoneIK3D in 5 files | FABRIK/CCD/Spline unused (spine lean, tails, reins and ropes are candidates) |
| RetargetModifier3D | 0 | retargeting is done in Blender (`mixamo_to_ual.py`). Fine as is |
| NavigationAgent3D / RVO avoidance / NavigationObstacle3D | **0 / 0 / 0** | NPCs use StreetGraph plus a hand-rolled push, so head-on pairs "dance" (NPC_MOTION_RULES rank 1) |
| AudioStreamPlayer3D | 3 files | almost every sound is 2D. There is one Interior reverb bus with room presets (`audio/audio_buses.gd`) and no reverb Area3D zones |
| ResourceLoader.load_threaded_request | 5 files (audio, loading screen, region dressing) | regions still load on the main thread (MASTER_BACKLOG §0.5) |
| InputMap remap | 5 files | PC rebinding works (`settings_screen.gd`) |
| TranslationServer | `core/app_services.gd` + `locale/strings.csv` (en, nl) | **bug:** `assets/audio/loudness*.csv` is imported as Translation resources (stray `.translation` files) |
| Movie Maker | `tools/qa/record_slice_move.sh`, video_to_sheets | used as the QA gate |

## Ground truth: installed addons
| Addon | Size | Used in game code? | Verdict |
|---|---|---|---|
| terrain_3d 1.0.2 | 81 MB | yes, behind `terrain_backend` | keep. Instancer, colour map and wetness are under-used |
| proton_scatter | 1.4 MB | yes (`scatter_chunk.gd`) | keep |
| phantom_camera | 2 MB | 1 file (`region1/ashsight_camera.gd`) | **adopt for the gameplay, dialogue and cutscene cameras** |
| quest_weaver | 4 MB | yes (bridge in `radiant_quests`, `village_services`, `life.gd`) | keep |
| gloot | 0.5 MB | yes (items, crafting, equipment) | keep |
| godot-sqlite | 111 MB | 1 file (`core/world_db.gd`) | keep; prune non-Windows binaries from the export |
| debug_menu, debug_draw_3d, gdUnit4 | — | QA and debug only | keep |
| sky_3d | 12 MB | **no** (an HDRI + own sky shader is used) | adopt its time-of-day/cloud layer or remove it (decide in P1) |
| effekseer | 20 MB | **no** | adopt for hero VFX (sword sparks, blood, magic), or remove it. **Stray `~libeffekseer*.TMP` DLL copies sit in `bin/windows`; delete them** |
| limboai 1.8.1 | 63 MB | **no** | adopt for squad tactics only (one BTPlayer per bandit group) |
| GUIDE | 2.5 MB | **no** | adopt for contexts (on foot / horse / build / menu), glyphs and remapping UI |
| godot_material_footsteps | 1.1 MB | **no** | superseded by `surface_feedback.gd`. Remove it |
| simplegrasstextured | 0.8 MB | **no** | superseded by the Terrain3D instancer and own grass. Remove it |
| road-generator | 6.8 MB | **no** | adopt for the slice road (rutted road mesh + decals) or remove it |
| voronoishatter | 0.25 MB | **no** | adopt offline for breakables (barrels, crates, fences) |
| dialogue_manager | 1.1 MB | **no** (rejected in `dialogue_runner.gd`) | remove it, or keep it only as an authoring format |
| GodotGAS | 1.5 MB | **no** (rejected in `skills.gd`) | remove it |
| mobile_texture_limit | 12 KB | phone leftover | remove it (PC-only) |

Other PC-only leftovers: `project.godot` still says "Kingdom" / "Pixel-rendered 3D medieval sandbox", has `handheld/orientation`, `emulate_touch_from_mouse=true`, and Android and iOS export presets; `core/platform_services.gd` targets Play Games / Game Center; the `quality.gd` header says "runs on any phone".

---

## 1. Character art
| Area | What AAA games do | What we have | Gap | Best free tool | Effort | P |
|---|---|---|---|---|---|---|
| Hero body + face | scanned/sculpted head, 60-100k tris, 4K skin, SSS, wrinkle maps | Meshy `hero_meshy3` (soft head, painted folds, low-res hands); `hero_face_driver.gd` blend shapes | below the bar next to the Poly Haven props | **MPFB 2.0.17** (installed, CC0 output) + MakeHuman CC0 system assets (eyes, brows, lashes, teeth, hair) + DeepBump/Krita for pore and stubble detail normals | L | P0 |
| NPC bodies, variety | 20-40 bases, morphs, palette and outfit swaps | Quaternius UAL + Meshy UAL conversions; crowds read faceted | low variety, low-poly look | MPFB crowd set per CHARACTER_PLAN (seeded morphs, 6 atlases per settlement) | L | P0 (pilot villager) |
| Hair | hair cards with anisotropic shading, strand LOD | none on MPFB yet | missing | MakeHuman CC0 hair proxies as alpha-scissor cards; Blender hair → mesh for custom cards | M | P0 |
| Clothing / cloth | layered garments, cloth sim on capes and skirts | HeroOutfit overlay; no cloth on NPCs | no layering, no secondary motion | MPFB proxy-fit + Blender cloth one-frame fold bake; runtime `SpringBoneSimulator3D` chains on hood, cloak and skirt hems (NEAR tier only) | M | P0 hero / P1 crowd |
| Character LOD | 4-5 LODs + impostor crowd | CrowdAnimLOD NEAR/MID/FAR + VAT + sprites | good. Needs LODs for the new MPFB bodies | `lod_gen` / Decimate / gltfpack `-noq` | S | P1 |
| Skin shading | SSS, specular lobes, micro detail | StandardMaterial3D | no SSS on min-spec (by design) | Godot `subsurf_scatter` on HIGH+ only, plus a detail normal at LOD0 | S | P1 |

## 2. Animation
| Area | What AAA games do | What we have | Gap | Best free tool | Effort | P |
|---|---|---|---|---|---|---|
| Locomotion | motion matching (AC, RDR2, KCD2) over hours of mocap | AnimationTree + BlendSpace sync, root motion, start/stop/turn clips for the player | owner: "no real motion"; one cycle per gait | first: more varied clips (Mixamo + CMU + Meshy text-to-motion) with distance matching and stride warping in code; trial **godot-motion-matching** (MIT, GDExtension, built for 4.4, v0.2.1) in a branch on the player only | M (clips) / L (MM trial) | P0 clips, P1 MM |
| IK | full-body IK, foot and hand placement, look-at | TwoBoneIK3D feet and hands, ContactIK, LookAt, GuardLegs, lean_aim | NPC foot IK off (perf); no hand-to-prop IK on NPCs | 4.6 `FABRIK3D`/`CCDIK3D` for spine and tails, budgeted NEAR-only like ContactIK | M | P1 |
| Facial + lip sync | FACS rigs, performance capture, audio-driven visemes | `hero_face_driver.gd` (blink, expressions, `talk` flap) | no visemes, no lip sync | **Rhubarb Lip Sync 1.14.0** (MIT) offline → viseme tracks on MPFB face shape keys | M | P1 (P0 if the slice talk scene uses close-ups) |
| Cloth / secondary | runtime cloth + springs | SpringBone on player props and horses | none on NPCs | `SpringBoneSimulator3D`; Wiggle 2 / Bone Dynamics bakes for cutscenes | S-M | P1 |
| Retarget | in-engine retargeting | Blender `mixamo_to_ual.py`, Expy Kit, `retarget` extension | works | keep. MPFB `game_engine` rig needs no retarget | — | — |
| Mocap sources | in-house stage | Mixamo (owner login), CMU (free for any use), RTMPose 2D, Meshy text-to-motion | missing clips (NPC_MOTION_RULES §5: startle, scared run, stairs, tired, onlooker) | Mixamo first, CMU via `retarget_bvh.py`, Meshy swift (3 credits). **Rejected:** LAFAN1 and Bandai-Namco (non-commercial), SMPL tools | S each | P0 (slice clips) |

## 3. NPC AI and crowds
| Area | What AAA games do | What we have | Gap | Best free tool | Effort | P |
|---|---|---|---|---|---|---|
| Steering / avoidance | RVO/ORCA, pass sides, lanes | StreetGraph + `_neighbour_push` | head-on "dance", clipping | **built-in NavigationServer3D avoidance** (agents on a map, routing stays on StreetGraph) | M | P0 |
| Attention / reactions | shared look budget, startle, crowd ripples | reaction_adapter (16 kinds), perception, alert_net | no shared budget; clip hints map to no clips | NPC_MOTION_RULES layer + missing clips | M | P0 |
| Schedules / smart objects | RDR2 daily lives | utility_brain (27 acts), 33 smart objects, carry errands | no hand IK on props, one queue type | ContactIK extension | M | P1 |
| Group tactics | surround, flank, regroup, flee | attack tokens per creature | no squad brain | **LimboAI** (installed): one BT per squad | M | P1 |
| Crowd LOD | 100s of agents | CrowdAnimLOD + VAT + sprites | good | — | — | — |

## 4. Combat
| Area | What AAA games do | What we have | Gap | Best free tool | Effort | P |
|---|---|---|---|---|---|---|
| Melee feel | KCD2 directional, AC warping, hitstop, reactions | hit_resolver, combat_motion warp, reactions, partial ragdoll, hitstop, lock-on, GuardLegs (passes 8-11) | owner verdict "AI slop" on older footage; clip quality and contact | more paired and directional clips (Mixamo sword set), camera framing via Phantom Camera | M | P0 |
| Hit VFX / SFX | layered sparks, blood, cloth tears, whooshes | impact_pool, weapon_trail, surface_impact | generic particles | Effekseer (installed) or Kenney particle-pack (on disk); Sonniss whooshes and impacts | M | P0 |
| Locational damage, bleeding, grapples | KCD2 | thin (MASTER_BACKLOG §0.2) | missing | code | L | P1 |

## 5. Camera
| Area | What AAA games do | What we have | Gap | Best free tool | Effort | P |
|---|---|---|---|---|---|---|
| Gameplay camera | spring arm, collision, framing per state, shoulder swap | own camera; Phantom Camera used once | state blends (combat, dialogue, interior) are hand-rolled | **Phantom Camera** (installed): follow, third-person, priority blends, shake, noise | M | P0 |
| Dialogue / cutscene camera | shot/reverse-shot, rails | `cutscene_player.gd`, birth cutscene | no shot language | Phantom Camera + AnimationPlayer tracks | M | P1 |

## 6. Rendering
| Area | What AAA games do | What we have | Gap | Best free tool | Effort | P |
|---|---|---|---|---|---|---|
| GI outdoors | Lumen/SVOGI, baked probes | SDFGI on HIGH+; nothing on LOW/MED | iGPU tiers look flat | SDFGI HIGH; on LOW/MED use a sun-bounce fill light + ambient from sky | S | P1 |
| GI interiors | baked lightmaps / probes | **none** (LightmapGI 0, VoxelGI 0) | slice interior lit by omnis only | **LightmapGI** baked per interior scene (works on iGPU, near-free at runtime) | M | **P0** |
| Reflections | SSR + probes | SSR on HIGH; **no ReflectionProbe** | interiors and wet cobbles look dull | `ReflectionProbe` per interior and plaza (update once) | S | P0 |
| Shadows | cascades + contact shadows | 4 splits, soft PCF | ok; check acne on the new trees | — | S | P1 |
| AO | GTAO / RTAO | SSAO HIGH+ | LOW has none | baked AO in lightmaps and vertex AO in kits | S | P1 |
| Volumetrics | god rays, local fog | volumetric fog off outdoors; FogVolume 0 | no morning mist, interior shafts, swamp fog | `FogVolume` (box/ellipsoid) per biome and per interior, HIGH+; height fog on LOW | S | P0 (route mist) |
| AA / upscaling | TAA/TSR/DLSS | FSR1 + FXAA (FSR2 crashes with Terrain3D 1.0.2) | foliage shimmer | test **TAA alone** at native scale on HIGH; re-test FSR2 on the next Terrain3D release | S | P0 |
| Grading | LUTs, custom post | Environment adjustments | no LUT, no per-biome grade asset | `Environment.adjustment_color_correction` LUT (Krita/Resolve-free LUTs) and per-biome profiles; `CompositorEffect` only if needed | S | P0 |
| Clouds / sky | volumetric clouds, ToD | Poly Haven HDRI + sun-aligned sky shader | static sky, no time-of-day clouds | **SunshineClouds2** (MIT, Godot 4.4+) on HIGH/ULTRA, or Sky3D (installed) | M | P1 |
| LOD / HLOD / impostors | Nanite, HLOD cells | auto mesh LOD, octahedral impostors, VAT, draw merge | no HLOD for distant towns | merge far town cells into one mesh + impostor (Blender batch) | M | P1 |
| Occlusion | precomputed + HW occlusion | box occluders in town lots only | terrain hills, castle walls and interiors don't occlude | `OccluderInstance3D` baked on wall and terrain-ridge meshes | S | P1 |
| Streaming | async world streaming | threaded only for audio and dressing | hitches on region transitions | `load_threaded_request` + `WorkerThreadPool` for region cells (WP-05) | L | P1 |
| Perf on the slice | 60 fps target per tier | **HIGH 26.6 fps / LOW 60.7 fps** on the route (v14) | HIGH misses 60 by 2x | Visual Profiler, RenderDoc (installed), **Tracy via a `profiler=tracy` engine build** (BSD-3) | M | P0 |

## 7. Environment
| Area | What AAA games do | What we have | Gap | Best free tool | Effort | P |
|---|---|---|---|---|---|---|
| Terrain | photogrammetry materials, erosion, authored roads | Terrain3D + real-world data, erosion tool, Azgaar | road ruts and edges | **road-generator** (installed) or a Terrain3D-painted road + rut decals; Poly Haven/ambientCG mud and gravel | M | P0 |
| Vegetation | authored clusters, wind, interaction | Sapling trees with Poly Haven bark, Terrain3D instancer, ProtonScatter, interactor globals | clustered placement along walls and fences | ProtonScatter path/edge modifiers + Terrain3D instancer per region | M | P0 |
| Water | rivers with flow, foam, wetness | own water shader + `water_streamer.gd` | flow maps on rivers | Waterways (MIT) is Godot 3 era: borrow its flowmap baking technique, don't install it | M | P1 |
| Weather / ToD / seasons / snow | dynamic sky, wet surfaces, snow accumulation | `weather.gd`, season and snow shader globals, puddles, Terrain3D wetness | wetness not on props or kits | shared `wetness` global in the kit and prop shaders | S | P1 |

## 8. VFX
| Area | What AAA games do | What we have | Gap | Best free tool | Effort | P |
|---|---|---|---|---|---|---|
| Combat, fire, smoke, dust, magic | Houdini flipbooks + GPU particles | 84 GPUParticles files, flipbook_fx, toon_vfx, Kenney particle/smoke packs on disk | "paper debris" look; toon leftovers clash with the realism | **Blender Mantaflow** smoke and fire baked to flipbooks (GPL tool, output free) + Effekseer (MIT, installed) for hits; particle collision for sparks on ground | M | P0 (hit, dust, fire) |

## 9. Audio
| Area | What AAA games do | What we have | Gap | Best free tool | Effort | P |
|---|---|---|---|---|---|---|
| Footsteps per surface | per-material, per-shoe, scuffs, jumps | `surface_feedback.gd` (wood/stone/cobble/dirt/leaves/grass/water/snow), NPC steps | no scuffs or turn/stop foley; few variants | **Sonniss GDC bundles** (free, commercial OK, no attribution; licence v2.0 forbids redistributing the raw sounds and AI training) + Freesound CC0 | S | P0 |
| Ambience layers | 3D emitters (birds, smithy, crowd walla) over beds | 14 seamless 2D beds + spots; only 3 files use AudioStreamPlayer3D | town and forest sound flat and non-positional | positional `AudioStreamPlayer3D` spot emitters on smart objects (anvil, well, chickens, market walla) | M | P0 |
| Reverb / occlusion | zone reverb, occlusion, early reflections | one Interior reverb bus with room presets; underwater muffle | no street/alley/forest zones, no occlusion | Area3D `reverb_bus` zones (built-in); trial **godot-steam-audio** (MIT; Steam Audio Apache-2.0) for occlusion on HIGH | S / M | P1 |
| Music | adaptive stems, stingers | `adaptive_music.gd`, 9 CC0 tracks | little variety; no stems | more CC0/CC-BY tracks (OpenGameArt), stems split in Audacity | S | P1 |
| Dialogue VO | full VO, barks | 41 region1 voice files, Kenney voiceover packs, Piper (PD voices) | most lines silent | Piper `norman/john/kristin/cori` (public domain) + CC-BY libritts; owner or friends' recordings for the hero | M | P1 |
| Weapon and impact SFX | layered | Kenney impact sounds, rFXGen/jsfxr | thin, synthetic | Sonniss (metal, leather, body impacts) | S | P0 |

## 10. UI/UX
| Area | What AAA games do | What we have | Gap | Best free tool | Effort | P |
|---|---|---|---|---|---|---|
| HUD restraint | KCD2 / RDR2 minimal, contextual | HUD, compass, markers; slice rule "only when needed" | markers and popups still dominate (BENCHMARK_SLICE) | design pass, not a tool | S | P0 |
| Remapping / glyphs / contexts | full remap, device glyphs | InputMap rebinding, `input_glyphs.gd` | no context stacks or Steam Input | **GUIDE** (installed, unused) | M | P1 |
| Accessibility | subtitles, colour-blind, text size, screen reader | subtitles, daltonisation, photo mode | screen reader | Godot 4.5+ AccessKit (built in) for menus | S | P2 |
| Localisation | 10-15 languages | `strings.csv` en/nl, `tr()` | gettext workflow, pluralisation | built-in POT generation + `.po` (gettext) | M | P2 |
| Loading / branding | — | the coordinator saw "Total Showdown" branding on a loading screen (BENCHMARK_SLICE); recheck it | project name is "Kingdom" in `project.godot` | rename the config and description | S | P0 |

## 11. Narrative tools
| Area | What AAA games do | What we have | Gap | Best free tool | Effort | P |
|---|---|---|---|---|---|---|
| Dialogue | node editor, conditions, VO hooks | `dialogue_runner.gd` (own JSON); Dialogue Manager rejected | no visual authoring | keep our own runner (Dialogic/Dialogue Manager don't fit the sim) | — | — |
| Quests | graph editor | Quest Weaver + radiant quests | works | — | — | — |
| Cutscenes | sequencer | `cutscene_player.gd`, AnimationPlayer | camera language | Phantom Camera | M | P1 |

## 12. Systems
| Area | Status | Gap | Tool | P |
|---|---|---|---|---|
| Save | `save_manager.gd` v4, slots, autosave | late-game round-trip test | gdUnit | P1 |
| Economy / crafting | works (`economy.gd`, `crafting.gd`, GLoot) | sim not visible to the player | UI | P1 |
| Stealth / crime | perception, witness, theft, crime (60 files) | no player stealth readout | — | P1 |
| Breakables | `breakable.gd` | no fractures | VoronoiShatter offline (installed) | P2 |

## 13. Tools and pipeline
| Area | What AAA studios do | What we have | Gap | Best free tool | Effort | P |
|---|---|---|---|---|---|---|
| Asset validation | import gates (tris, texture size, naming, licence) | `tools/qa/asset_audit.py`, `texture_vram.py`, `gd_extra_lint.py` | no glTF spec check before import | **Khronos glTF-Validator** (Apache-2.0, CLI) in `asset_audit.py` | S | P1 |
| Import presets | per-type presets | per-file `.import` | none shared | Godot import defaults per folder (`.import` templates) | S | P1 |
| Profiling | Tracy, PIX, Superluminal | Godot profiler, PerfOverlay, RenderDoc, perf_probe | no CPU timeline across threads | **Tracy** (BSD-3) via a Godot 4.6 build with `profiler=tracy` | M | P1 |
| Crash reporting | Sentry/Backtrace | `tools/install_sentry.sh` (Sentry Godot 2.2.0, MIT), not installed | no crashes collected | install for playtest builds; Sentry free developer tier | S | P1 |
| Tests | 1000s of tests, bots | ~512 gdUnit files, playtest bot, Movie Maker gates | — | — | — | — |
| CI | build farm, nightly | `.github/workflows/tests.yml` | **pins Godot 4.6.2 (game is 4.6.3)**; triggers on `main` and `claude/**` only, so `aaa/finish` pushes are untested | bump to 4.6.3, add `aaa/**` | S | P0 |
| Build / export | nightly signed builds | Windows Desktop preset (+ Android/iOS leftovers) | no scripted PC export or artifact | `godot --export-release "Windows Desktop"` in CI | S | P1 |
| Telemetry | heatmaps, funnels | none | — | **Talo** (MIT Godot plugin; open-source backend you can self-host) | M | P2 |

## 14. Performance, QA and release
| Area | What AAA games do | What we have | Gap | Best free tool | Effort | P |
|---|---|---|---|---|---|---|
| Budgets per tier | ms budgets per discipline | PC_LOW/MED/HIGH/ULTRA tiers; PERF60_BRIEF | no ms budget table; iGPU not measured (WP-23) | a budget table in `ashes-performance` + a measured iGPU run | S | P0 |
| QA bots / gates | automated playthroughs, video diff | playtest bot, Movie Maker + contact sheets, AAA gate log | good | — | — | — |
| Steam release | Steamworks: achievements, cloud saves, overlay | `platform_services.gd` (mobile backends, TODOs) | no Steam backend | **GodotSteam** 4.23.2 (MIT, GDExtension; Codeberg). The Steamworks app fee is the only cost | M | P1 |
| Cloud saves | Steam Auto-Cloud | local slots | — | Steam Auto-Cloud (config only) or GodotSteam RemoteStorage | S | P1 |

---

## (1) Install/enable now (not on disk yet; nothing installed by this audit)
| # | What | Source | Licence (checked at source) | Size | Worker |
|---|---|---|---|---|---|
| 1 | MakeHuman CC0 system assets (eyes, brows, lashes, teeth, hair) + CC0-only clothing | makehumancommunity.org asset repo (licence FAQ: https://static.makehumancommunity.org/makehuman/faq/are_makehuman_files_free.html) | core assets CC0; community assets CC0 **or CC-BY** (check each item) | few hundred MB (check per pack) | player / character worker (CHARACTER_PLAN step 1) |
| 2 | Sonniss GDC Game Audio Bundle (pick foley, footsteps, metal, cloth, ambience folders) | https://gdc.sonniss.com, licence https://sonniss.com/gdc-bundle-license/ | royalty-free, commercial, no attribution. **No redistributing the raw files** (keep sources in `ProjectAshes_art_staging`, never in the public repo); no AI training | 10-30 GB per year (download selectively) | audio / video-QA worker |
| 3 | Freesound CC0 clips (filter licence = CC0) | https://freesound.org | per-file (use CC0 only) | small | audio worker (needs the owner's free login) |
| 4 | Rhubarb Lip Sync 1.14.0 | https://github.com/DanielSWolf/rhubarb-lip-sync/releases | MIT (LICENSE.md: output belongs to you) | 87 MB zip | character / dialogue worker |
| 5 | Khronos glTF-Validator CLI | https://github.com/KhronosGroup/glTF-Validator | Apache-2.0 | ~10 MB | asset pipeline (`asset_audit.py`) |
| 6 | Tracy profiler 0.13 + a Godot 4.6.3 build with `profiler=tracy` | https://github.com/wolfpld/tracy, https://docs.godotengine.org/en/4.6/engine_details/development/profiling/tracy.html | BSD-3 (Tracy); MIT (Godot) | ~50 MB + engine build | perf worker |
| 7 | godot-motion-matching (trial branch, player only) | https://github.com/GuilhermeGSousa/godot-motion-matching (v0.2.1) | MIT | small GDExtension | player-animation worker (P1 trial; built for 4.4, check that it loads on 4.6.3) |
| 8 | SunshineClouds2 (HIGH/ULTRA sky) | https://github.com/Bonkahe/SunshineClouds2 | MIT | small | world worker (P1) |
| 9 | godot-steam-audio v0.3.1 (trial: occlusion + reverb) | https://github.com/stechyo/godot-steam-audio | MIT (Steam Audio Apache-2.0) | ~60 MB demo zip | audio worker (P1) |
| 10 | GodotSteam 4.23.2 GDExtension | https://codeberg.org/godotsteam/godotsteam | MIT | ~10 MB | release worker (P1, after the Steamworks app exists) |
| 11 | Sentry Godot SDK 2.2.0 (script already present) | `tools/install_sentry.sh` → getsentry/sentry-godot | MIT | 43 MB pruned | release / QA (P1 playtests) |
| — | Rejected | LAFAN1, Bandai-Namco motion (non-commercial), BBC SFX (non-commercial), EmberGen/Houdini/FMOD/Wwise (paid or licence-gated), Waterways (Godot 3), FreeMoCap (AGPL) | — | — | — |

## (2) Use what we have (installed or built in, but unused)
| What | Adopt where | P |
|---|---|---|
| **LightmapGI** | bake the slice interior (house/tavern) and every interior scene; LOW/iGPU tier gains the most | P0 |
| **ReflectionProbe** | slice interior, Ashford market square (wet cobbles), smithy | P0 |
| **FogVolume** | morning mist on the countryside route, interior light shafts, marsh; HIGH+ only | P0 |
| **TAA** (`use_taa`) | test it on HIGH at native scale against FSR1 + FXAA foliage shimmer | P0 |
| **Phantom Camera** | gameplay camera states (explore, combat, dialogue, interior) + the slice talk scene | P0 |
| **NavigationServer3D avoidance (RVO)** | villagers, micro actors and followers in Ashford (NPC_MOTION_RULES S1+S2) | P0 |
| **AudioStreamPlayer3D spot emitters** | smithy anvil, well, market walla, chickens, campfire on the slice | P0 |
| **Effekseer** | sword sparks, blood, dust, magic hits (or delete the addon and its stray TMP DLLs) | P0 |
| **road-generator** | the Kingsreach road on the slice route (or delete it) | P0 |
| **SpringBoneSimulator3D on NPCs** | hoods, cloaks and skirt hems on NEAR-tier villagers and bandits | P1 |
| **LimboAI** | bandit squad tactics (one BT per group) | P1 |
| **GUIDE** | input contexts, glyphs and the remap UI | P1 |
| **4.6 FABRIK3D / CCDIK3D** | spine lean on NPCs, horse neck, tails, ropes and reins | P1 |
| **OccluderInstance3D** (beyond town lots) | town walls, castle, terrain ridges, interiors | P1 |
| **load_threaded_request + WorkerThreadPool** | region cell streaming (WP-05) | P1 |
| **Sky3D** | time-of-day clouds on LOW/MED if SunshineClouds2 is too heavy (or delete it) | P1 |
| **Area3D reverb_bus zones** | alleys, church, cave and forest reverb | P1 |
| **VoronoiShatter** | offline fractures for barrels, crates and fences | P2 |
| **AccessKit / POT generation** | screen reader for menus; gettext workflow | P2 |
| **Remove** | godot_material_footsteps, simplegrasstextured, GodotGAS, dialogue_manager, mobile_texture_limit; Android/iOS presets; mobile `project.godot` keys | P1 hygiene |

## (3) Top 15 gaps by impact on looking and feeling like KCD2 / AC
| # | Gap | Fix (tool) | P |
|---|---|---|---|
| 1 | Hero and crowd bodies read low-poly/toy next to the realistic props | MPFB + MakeHuman CC0 assets, the pilot villager then the hero | P0 |
| 2 | Locomotion and combat motion: one cycle per gait, contact and weight off | more clips (Mixamo/CMU/Meshy), distance matching, stride warp; MM trial later | P0 |
| 3 | NPCs dance and clip in streets; synced idles | built-in RVO avoidance + NPC_MOTION_RULES variety and attention | P0 |
| 4 | Perf: HIGH 26.6 fps on the slice route; iGPU unmeasured | profile (Visual Profiler, RenderDoc, Tracy), budgets per tier | P0 |
| 5 | Interiors have no GI or reflections | LightmapGI + ReflectionProbe | P0 |
| 6 | AA: FSR1 + FXAA shimmer on foliage | TAA test; FSR2 once Terrain3D is fixed | P0 |
| 7 | Atmosphere: no local fog, mist or shafts; no grade LUT | FogVolume + per-biome LUT/profiles | P0 |
| 8 | Sound is flat: 2D beds, few positional emitters, thin foley | AudioStreamPlayer3D emitters + Sonniss/Freesound CC0 foley | P0 |
| 9 | Camera framing per state (combat, dialogue) hand-rolled | Phantom Camera | P0 |
| 10 | Road and ground: ruts, edges, clustered vegetation | road-generator / Terrain3D paint + ProtonScatter edge clusters | P0 |
| 11 | Combat VFX look generic/toon ("paper debris") | Effekseer + Mantaflow flipbooks, particle collision | P0 |
| 12 | No cloth or hair secondary motion on NPCs; hero hair missing | SpringBone chains + MakeHuman hair cards | P1 |
| 13 | No lip sync or facial performance in dialogue | Rhubarb → MPFB visemes | P1 |
| 14 | Region streaming on the main thread (hitches) | threaded loading + occlusion beyond towns | P1 |
| 15 | Pipeline: CI on the wrong Godot version and branch, no glTF validation, no crash reports, no Steam layer | CI fix (P0, S), glTF-Validator, Sentry, GodotSteam | P1 |
