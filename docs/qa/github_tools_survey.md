# Open-source tools survey: fixing Rising Ashes' current problems

**Date:** 2026-09-28. **Scope:** research only, no code changes. Candidates found via GitHub search/API, the Godot
Asset Library, godotshaders.com and Reddit leads, checked against `.claude/skills/ashes-open-source-sourcing/SKILL.md`
(licence gate: MIT/CC0/BSD/Apache-2.0/OFL fine, CC-BY needs a credit line, no GPL for shipped code, no NC, no unclear
licences) and `docs/OPEN_SOURCE_AUDIT.md` (what's already vendored in `kingdom/addons/`: GodotGAS, dialogue_manager,
gdUnit4, gloot, guide, limboai (disabled), mobile_texture_limit, proton_scatter, quest_weaver, road-generator, sky_3d,
terrain_3d). Nothing here is downloaded or vendored — this is a shortlist for a human decision.

**How licence/maintenance was checked:** GitHub repos via `gh api repos/<owner>/<repo>` (license SPDX id, `pushed_at`,
star count, archived flag) — this is a live API read, not a cached guess. godotshaders.com entries were fetched
directly; that site does not expose commit history, so "maintenance" there means "page states a licence explicitly."

---

## Adopt-now shortlist (max 6, ranked by visual/performance win per effort)

| # | Tool | Fixes | Licence | Effort | Why it's top of the list |
|---|---|---|---|---|---|
| 1 | **ProtonScatter — wire in the ground-projection modifier** (already in `kingdom/addons/proton_scatter`, MIT, unused) | #1 pasted-on props, #4 clutter/variety | MIT (own code; demo textures excluded) | S | Zero new dependency — it's already vendored and unused. Its "Project on collider" position modifier snaps scattered instances onto the ground/rock surface normal, which directly fixes floating/pasted props and gives free clutter variety (grass, rocks, debris) around building bases. Biggest win for the least new risk. |
| 2 | **Ultimate Toon/Painterly Shader** (godotshaders.com, Binbun) | #3 flat lighting / hand-painted look | CC0 | S | Drop-in spatial shader (not a whole render pipeline change): step-based toon shading with a "painterly" pattern mode driven by a grayscale texture, tintable shadows. CC0, apply per-material to buildings/terrain/characters incrementally. |
| 3 | **blackears/terrain_layered_shader** | #1 ground blending at prop bases, #2 terrain uniformity | MIT | M | Actively maintained (pushed 2025-11-19, 37 stars). Ships both a base terrain shader with a tile-scrambling anti-tiling algorithm *and* a mesh-terrain blending shader/Blender project for softening object-to-ground transitions — covers two problems from one MIT repo. |
| 4 | **antzGames/Godot_Vertex_Animation_Textures_Plugin** (VAT crowds) | #6 NPC crowds and performance | MIT | M | Actively maintained (pushed 2026-09-27, 125 stars). Extends `MultiMeshInstance3D` with baked vertex-animation-texture playback; the author's own benchmark shows the **Mobile renderer as the fastest** target (458–768 fps at 2000 instances). Needs a Blender bake step per animated NPC type (the "Godot VAT Blender Tools" add-on) — that's the integration cost. |
| 5 | **Godot's built-in 4.6 IK framework (two-bone IK skeleton modifier) + SeaKrill/Godot-Foot-IK as a reference** | #5 foot IK on slopes | Engine-native (no licence issue) + MIT reference | M | Godot 4.6 shipped a native modular IK stack (two-bone IK, FABRIK, CCDIK) as `SkeletonModifier3D` resources — no GDExtension binary risk on mobile, which matters because our iOS export already has two disabled addons blocked on missing `.dylib`s (see `OPEN_SOURCE_AUDIT.md` red flag 7). Use `SeaKrill/Godot-Foot-IK` (MIT, small sample project) purely as an implementation reference for raycast-to-ground foot placement, not as a binary dependency. |
| 6 | **Godot's built-in "Snap Object to Floor" (4.6 editor Transform menu)** | #7 objects floating or buried | Engine-native | S | Confirmed present in the Godot 4.6 3D editor's Transform menu — no addon needed at all. Free fix for manually-placed building/prop instances; use it as the standard step before accepting any new placement. (If more precision is needed later, `jgillich/godot-snappy`, MIT, adds vertex-to-vertex snapping — but it fights the move/rotate gizmo per its own README, so only reach for it if floor-snap alone isn't enough.) |

---

## Per-problem tables

### 1. Objects look pasted on the ground

| Candidate | URL | Licence | Godot ver. | Mobile | Maintained | Size | Fixes | Effort | Risks |
|---|---|---|---|---|---|---|---|---|---|
| ProtonScatter ground-projection modifier | github.com/HungryProton/scatter | MIT (verified: `license.spdx_id` via API) | 4.x, "v4" branch | Not stated; MultiMesh output is mobile-friendly by construction | pushed 2026-09-27, 2,992 stars | ~13 MB (already in repo) | Snaps prop instances to the ground/collider normal at placement time — kills the "floating" look and adds AO-blob-style clutter around bases for free | S (already vendored, unused — just author the modifier stack) | It's editor-time/non-destructive baking, not a runtime system; won't help anything spawned procedurally at runtime without a re-bake |
| blackears/terrain_layered_shader (mesh-terrain blend shader) | github.com/blackears/terrain_layered_shader | MIT (verified) | not pinned to a specific 4.x point release | Not stated — triplanar + multiple samplers, worth profiling on a mid-tier Android device before wide use | pushed 2025-11-19, 37 stars | small (shader + Blender project) | A dedicated shader that blends a building/prop's base texture into the surrounding ground texture using triplanar sampling and a transition mask | M (per-material setup, needs a matching ground shader) | Triplanar + multi-sampler cost; verify frame cost on Mobile renderer |
| "Mesh-Terrain Blending" shader | godotshaders.com/shader/mesh-terrain-blending/ | MIT (stated on page) | "works for Godot 4.0 as well" | Not stated | Asset page, not a repo — no commit history to check | tiny (code snippet) | Same idea as above (triplanar mesh-to-ground blend with AO/roughness blending) — a simpler single-file alternative if the blackears repo is too heavy | S–M | No maintenance signal; copy-paste code, so verify it compiles on 4.6 before relying on it |

### 2. The terrain is too uniform

| Candidate | URL | Licence | Godot ver. | Mobile | Maintained | Size | Fixes | Effort | Risks |
|---|---|---|---|---|---|---|---|---|---|
| blackears/terrain_layered_shader (base + masked layers) | github.com/blackears/terrain_layered_shader | MIT | not pinned | Not stated | pushed 2025-11-19, 37 stars | small | Tile-scrambling anti-tiling base shader plus stackable masked layers (splat-map-style macro variation) | M | Same triplanar cost caveat as above; needs texture set authored to its layer format |
| acegiak/Godot4TerrainShader | github.com/acegiak/Godot4TerrainShader | **Apache-2.0** (OK per licence gate) | Godot 4 | Not stated | pushed 2023-02-14 (stale, 31 stars) — treat as reference code, not a living dependency | small | Stochastic triplanar sampling split into wall/top surfaces with independent scaling/colour — reduces obvious tiling on slopes and cliffs | M | Unmaintained since 2023; read the shader and adapt rather than pulling it live |
| "Stochastic Procedural Texture Shader" | godotshaders.com/shader/stochastic-procedural-texture-shader/ | MIT (stated) | not specified | Not stated; uses Heitz's histogram-preserving blending operator, which is heavier than simple triplanar — profile before shipping | Asset page, no commit history | tiny | True by-example stochastic texturing (kills regular tiling patterns entirely, not just triplanar seams) | M–L (LUT setup, extra samples per pixel) | Likely too expensive for low-end Android/iOS without cutting sample count; test on the actual mobile perf budget first |
| Terrain3D (already vendored, unused) | github.com/TokisanGames/Terrain3D | MIT | Godot 4 | Yes, widely used in shipped mobile titles; iOS `.dylib` currently missing from the repo per audit red flag 7 | pushed 2026-09-26, 4,305 stars, very active | 44 MB in repo | A full splat-mapped terrain system with macro variation built in — but this replaces our current `terrain_streamer.gd`, not a drop-in shader | L | Already flagged in the audit as blocked for iOS export; only worth it if we're willing to replace the terrain pipeline, which is a much bigger call than a shader swap |

### 3. Flat lighting and a hand-painted look

| Candidate | URL | Licence | Godot ver. | Mobile | Maintained | Size | Fixes | Effort | Risks |
|---|---|---|---|---|---|---|---|---|---|
| Ultimate Toon Shader (Binbun) | godotshaders.com/shader/ultimate-toon-shader/ ; itch.io/Binbun3D | **CC0** (stated on page) | Godot 4.x | Not stated, but it's a standard cel-shading spatial shader (cheap: step functions on NdotL), typically mobile-safe | Asset page; itch devlogs show active updates | tiny | Toon/cel shading with a "painterly" pattern option driven by a grayscale mask — closest single asset to "hand-painted" without a full post pipeline | S | No formal maintenance signal (itch, not git); re-verify CC0 statement at import time and save a copy of the licence text |
| "Toon Shader" (MIT) | godotshaders.com/shader/toon-shader-2/ | MIT (stated) | Godot 4 | Not stated | Asset page | tiny | Simpler hard-shadow-band toon shader, good fallback if the CC0 one doesn't fit our palette | S | Same as above — no git history to check |
| Colour grading LUT post-processing | (native Godot `Environment` LUT/adjustment — no third-party tool needed) | Engine-native | 4.x | Yes | n/a | n/a | Godot's own `Environment.adjustment_*` + a colour-grading LUT texture gives cheap, mobile-safe stylised grading without any addon | S | Not really a "tool" — flagging so nobody builds/adopts a whole post-processing addon when the built-in adjustment stage already does LUT grading |

### 4. Too clean / no variety (scattering)

| Candidate | URL | Licence | Godot ver. | Mobile | Maintained | Size | Fixes | Effort | Risks |
|---|---|---|---|---|---|---|---|---|---|
| ProtonScatter (full modifier stack: Random, Along Edge, Project, Cluster-via-multiple-Scatter-nodes) | github.com/HungryProton/scatter | MIT | Godot 4.x | MultiMesh output; already the repo's own scatter tool of choice per `DEPENDENCIES.md` | pushed 2026-09-27, 2,992 stars, very active | in repo | It's unused per the audit (`2c`) despite being vendored — this is exactly the "unused, solves the problem" case the sourcing skill calls out. Combining Random + Project-on-collider + a second negative-shape pass gives rule-based clustering (dense near trees/rocks, sparse in paths) for clutter variety | S–M (author modifier stacks per biome, no new dependency) | Editor-time bake, not runtime; `demos/` folder has non-redistributable Textures.com textures per audit red flag 6 — don't touch that folder |

*(No second/third candidate is listed here — ProtonScatter already covers this problem completely and is unused, so pulling in a second scattering addon would be redundant per the sourcing skill's "don't recommend what's already there" rule, except that this one needs to move from "vendored" to "wired in.")*

### 5. Natural player movement (controller, locomotion, foot IK)

| Candidate | URL | Licence | Godot ver. | Mobile | Maintained | Size | Fixes | Effort | Risks |
|---|---|---|---|---|---|---|---|---|---|
| Jeh3no/Godot-Third-Person-Controller | github.com/Jeh3no/Godot-Third-Person-Controller | MIT | 4.4–4.7 (should work 4.0–4.3 after deleting `.uid` files) | Not documented | pushed 2026-06-22, 118 stars, active | small | Full FSM-based TPS controller: slope/hill traversal, accel/decel blending, jump — a speed-matched-locomotion reference to compare our own controller against | M (reference/port, not drop-in — bundles its own demo character) | No Jolt-specific or mobile-specific notes; verify against our existing `player.gd` rather than replacing it wholesale |
| etherealxx/Godot-Third-Person-Controller-Mobile (fork of the above) | github.com/etherealxx/Godot-Third-Person-Controller-Mobile | MIT | Godot 4 | **Explicitly targets mobile**: swaps in Godot Jolt physics and virtual joysticks, built for Android export testing | pushed 2024-01-01 (stale, 5 stars) — small project, low confidence | small | Shows exactly the touch-input + Jolt physics changes needed to take a desktop TPS controller mobile | M | Low star count/stale — treat as a worked example of the mobile adaptation, not a dependency to pull in |
| Godot 4.6 native IK framework (two-bone IK `SkeletonModifier3D`) + SeaKrill/Godot-Foot-IK as reference | godotengine docs; github.com/SeaKrill/Godot-Foot-IK | Engine-native + MIT reference | 4.6 native; sample project undated (pushed 2023-11-19) | Engine-native = safe on mobile, no GDExtension binary needed | Engine: current; sample: stale but small enough to just read | tiny | Two-bone IK chain (hip→knee→ankle) driven by ground raycasts, keeps feet planted on slopes/steps without buying a whole IK plugin | M | The sample project is old (2023) — expect to adapt it to the 4.6 modifier API rather than using it as-is |
| monxa/GodotIK | github.com/monxa/GodotIK | MIT | 4.3+ | **GDExtension (C++/godot-cpp)** — ships one generic release zip (`godot-libik-plugin-v1.3.1.zip`); per-platform (Android/iOS) binary coverage isn't confirmed from the repo metadata | pushed 2025-06-09, 259 stars, well-regarded | small | FABRIK-based multi-chain IK, more powerful than a bespoke two-bone script if we need spine/arm IK too, not just feet | M–L | GDExtension binaries are exactly the class of problem already biting us on iOS (LimboAI/Terrain3D missing `.dylib`s per audit) — verify Android + iOS builds exist in the release before considering it over the native 4.6 framework |

### 6. NPC crowds and performance

| Candidate | URL | Licence | Godot ver. | Mobile | Maintained | Size | Fixes | Effort | Risks |
|---|---|---|---|---|---|---|---|---|---|
| antzGames/Godot_Vertex_Animation_Textures_Plugin | github.com/antzGames/Godot_Vertex_Animation_Textures_Plugin | MIT | 4.5+ | **Explicitly benchmarked on Mobile renderer as fastest target** (458–768 fps @ 2000 instances) | pushed 2026-09-27, 125 stars, very active, shipped in a released game | small (plugin) + per-NPC Blender bake | Bakes NPC animation into a texture, plays it back through `MultiMeshInstance3D` — the standard "animate thousands of instances cheaply" pattern, ideal for background villager/crowd rendering with distance-based animation LOD | M (needs the matching "Godot VAT Blender Tools" Blender add-on to bake each animated NPC/animal rig — non-trivial per-asset pipeline step, but a one-time cost per creature type) | Baked animation is not skeletal — no per-instance runtime blending/IK on VAT instances; use it for background crowd only, keep foreground NPCs on the normal skeleton+AnimationTree pipeline |
| shadecoredev/AnimatedMultimeshInstance3D | github.com/shadecoredev/AnimatedMultimeshInstance3D | **NOASSERTION (no LICENSE file)** | Godot 4 | Not documented | pushed 2025-10-22, 43 stars | small | Same VAT-for-MultiMesh idea, plus per-instance animation blending and a downsampling option to shrink the baked texture | — | **Rejected on licence grounds** — no LICENSE file means unclear rights, which the sourcing skill rules out outright. Revisit only if the author adds an explicit MIT/CC0 licence file. |
| Godot's built-in Visibility Range (HLOD) + distance-based `AnimationTree` throttling | engine-native | Engine-native | 4.x | Yes | n/a | n/a | Not a repo, but the correct first lever before adopting VAT crowds: swap far NPCs to lower-poly meshes and cut animation update rate at distance | S | None — just flagging so the VAT investment targets background crowds specifically, once cheap native LOD is already applied |

### 7. Objects floating or buried

| Candidate | URL | Licence | Godot ver. | Mobile | Maintained | Size | Fixes | Effort | Risks |
|---|---|---|---|---|---|---|---|---|---|
| Godot 4.6 editor "Snap Object to Floor" (Transform menu) | engine-native | Engine-native | 4.6 | n/a (editor-only) | Current | n/a | Built-in raycast-down snap for any selected node in the 3D editor — the direct, zero-dependency fix for manually placed buildings/props that are floating or clipped into terrain | S | Editor-time only, and community reports say it's not real-time/can be slow on large scenes — fine for our placement workflow (buildings/props placed once, not per-frame) |
| jgillich/godot-snappy | github.com/jgillich/godot-snappy | MIT | Godot 4 (separate 3.x branch) | n/a (editor-only) | pushed 2024-07-12, 71 stars | small | Vertex-to-vertex snapping (hold `V`, drag to target vertex) — more precise than a floor raycast when aligning a prop's base exactly to a foundation mesh | S | Own README admits the move/rotate gizmo "can get in the way"; only reach for it when the built-in floor snap isn't precise enough |
| ProtonScatter "Project on collider" modifier | github.com/HungryProton/scatter | MIT | 4.x | in repo | pushed 2026-09-27 | in repo | For *procedurally scattered* items (not hand-placed ones), the same modifier from problem #1/#4 keeps every instance's Y position and normal glued to the ground it's projected onto | S (already vendored) | Same caveat as above: bake-time, not runtime |

### 8. General mobile performance

| Candidate | URL | Licence | Godot ver. | Mobile | Maintained | Size | Fixes | Effort | Risks |
|---|---|---|---|---|---|---|---|---|---|
| Godot 4.6 native OccluderInstance3D + Visibility Range (built-in) | engine-native | Engine-native | 4.x (raster occlusion since 4.0) | Yes — the Mobile renderer has no depth prepass, so this is *more* valuable there than on Forward+ | Current | n/a | The correct first step before any third-party culling/LOD addon: place occluder meshes in large blocking geometry (buildings, walls) and set Visibility Ranges on detailed meshes | S–M | Needs occluder meshes authored per building type; not a repo pull, but should be exhausted before reaching for an addon |
| AndreaCatania/godot_tracy / Pineapple/GodotTracy | github.com/AndreaCatania/godot_tracy ; github.com/Pineapple/GodotTracy | MIT (both) | Custom Godot build (compiled module) | Desktop-profiling tool used against builds; not something that ships in the mobile binary itself | AndreaCatania: pushed 2024-01-02, 128 stars; Pineapple: pushed 2024-08-08, 128 stars — both stalled ~1.5–2 years | module source, no binary shipped | Frame-by-frame CPU/GPU profiling with Tracy's UI — far more actionable than the built-in Godot profiler for chasing a specific frame-time spike | L (requires building a custom Godot editor/export binary from source with the module enabled) | High integration cost for a profiling-only tool; Godot's upstream engine has also been adding native Tracy support directly (PR #113279, landed towards 4.7), which will make a custom module unnecessary soon — worth waiting for upstream rather than building this now |
| necat101/Material-Merger-Godot | github.com/necat101/Material-Merger-Godot | **No LICENSE file** | Godot 4.x | Not documented | pushed 2025-05-23, 4 stars | small | Merges StandardMaterial3D instances + atlases textures to cut draw calls (mesh-merging/HLOD-adjacent) | — | **Rejected on licence grounds** (no stated licence) — otherwise exactly the "mesh merging" tool the brief asked for; worth re-checking if the author adds a licence, since draw-call reduction is a real mobile win |

---

## Rejected (with reasons)

| Tool | Reason rejected |
|---|---|
| shadecoredev/AnimatedMultimeshInstance3D | No LICENSE file (`NOASSERTION`) — unclear licence, excluded by the licence gate regardless of how well it fits the crowd-VAT problem. |
| necat101/Material-Merger-Godot | No LICENSE file at all — same unclear-licence exclusion, despite being a good functional fit for draw-call/HLOD-style mesh merging. |
| acegiak/Godot4TerrainShader | Licence is fine (Apache-2.0), but unmaintained since Feb 2023 (31 stars, no activity since) — listed as a code reference under problem #2, not a living dependency to pull in. |
| GDQuest 3D third-person controller / demo art | Already flagged in `OPEN_SOURCE_AUDIT.md` §3: code is MIT but its bundled art is **CC-BY-NC-SA 4.0**, which fails the "no NC" gate. The audit confirms no GDQuest art is in the repo — keep it that way; only take ideas from the MIT code, never the assets. |
| monxa/GodotIK, as a first choice over the native 4.6 IK framework | Not rejected outright (MIT, active, 259 stars) but demoted below the engine-native two-bone IK modifier: it's a GDExtension shipping a single generic release zip, and per-platform Android/iOS binary coverage isn't confirmed — the same class of problem already blocking LimboAI and Terrain3D on iOS per the audit. Revisit if the native 4.6 IK stack proves insufficient for our rig. |
| Tracy modules (godot_tracy / GodotTracy) as an immediate adopt | Licence is fine (MIT) but both require building a custom Godot binary from source and have been stalled ~2 years; upstream Godot is landing native Tracy/Perfetto hooks (PR #113279) which will make a bespoke module redundant. Wait for upstream rather than adopting now. |
| Stochastic Procedural Texture Shader (Heitz histogram-preserving operator) as the *first* terrain-variation pick | Licence is fine (MIT) and it's the "correct" academic technique for eliminating tiling, but it's the heaviest of the anti-tiling candidates (LUT sampling, colour-space transforms) with no mobile cost data — ranked behind `terrain_layered_shader`'s simpler tile-scrambling approach for a mobile-first game; keep it as a stretch upgrade if the cheaper shader isn't enough. |
| A second/third scattering addon (e.g. `lucacicada/godot-scatter`) | ProtonScatter is already vendored, MIT, actively maintained and unused — pulling in a second scatter tool would duplicate a solved problem per the sourcing skill's "don't recommend what's already there" rule. |
| Terrain3D as the pick for "terrain too uniform" | Already vendored and unused (fits the "unused, solves the problem" allowance), and it is the most capable terrain system found — but adopting it means replacing the whole `terrain_streamer.gd` pipeline, not applying a shader, and it's currently blocked on a missing iOS `.dylib` per the audit. Listed under problem #2 as the "L effort" option, not the shortlist, because the ask was the biggest win *per effort*. |

---

## Notes for whoever picks this up

- Every MIT-licensed item added to the shortlist still needs its licence text copied into the pack/plugin's folder and a line in `kingdom/CREDITS.md` once actually imported, per the audit's existing MIT-notice red flag (#1).
- Nothing in this survey has been downloaded, vendored, or added to `kingdom/addons/`. This is a research document only.
