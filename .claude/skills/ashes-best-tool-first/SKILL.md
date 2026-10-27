---
name: ashes-best-tool-first
description: MANDATORY first step for every Rising Ashes task (code, art, animation, world, towns, perf, QA) - check whether a Godot built-in, an installed addon, a Terrain3D feature, an external tool, a free asset pack, Mixamo/Meshy or cloud offloading already does it faster and better, and use that instead of writing it by hand. Owner rule (2026-10-27). Use before planning or coding anything.
---

# Best tool first (owner rule)

Owner: "Every time you want to do something, check if there is any addon or anything that could help us out faster and better, and use that." Hand-writing something that an engine feature, addon or tool already does is a defect.

## The 60-second check (do it, then say in your report what you chose and why)
1. **Godot 4.6.3 built-ins** — table below. Verify the class/property exists in 4.6.3 (`ClassDB`, docs, or `godot --doctool`) before relying on it.
2. **Installed addons** — `ls kingdom/addons/` (LimboAI, Phantom Camera, Dialogue Manager, GLoot, ProtonScatter, Sky3D, Terrain3D, GdUnit4, Debug Menu, Road Generator, …). Prefer them over new code.
3. **Terrain3D features** — table below.
4. **External tools / MCPs** — skill `ashes-external-tools` (Blender + add-ons, DCC-MCP Godot/Blender, gltfpack, Real-ESRGAN, Piper, …).
5. **Free assets/code** — skill `ashes-open-source-sourcing` (CC0/MIT/Apache/BSD only; Quaternius, KayKit, Kenney, Poly Haven, ambientCG, Mixamo).
6. **Animation sources** — skill `ashes-mixamo-meshy` (Mixamo via the owner's login in the browser pane; Meshy text-to-motion/3D with credits; pipelines already built).
7. **Offload** — skill `ashes-cloud-offload`: anything headless-testable goes to a cloud routine, not the 16 GB laptop.
8. Only then write custom code — and say why nothing above fitted.

Rules: no paid tools (Meshy credits only, owner-approved); licences free + commercial-OK; log downloads in `docs/plans/DOWNLOADS.md`; min-spec is a regular PC possibly with integrated graphics (provide a low tier).

## Godot 4.6.3 built-ins to reach for
| Need | Built-in |
|---|---|
| Blend gaits without foot phase drift | `AnimationNodeBlendSpace1D/2D.sync`, sync groups |
| Retarget animation between skeletons | importer bone map / `SkeletonProfileHumanoid`, `RetargetModifier3D` |
| Cloth, capes, hair, straps | `SpringBoneSimulator3D` (+ collision shapes) |
| Hit reactions / death physics | `PhysicalBoneSimulator3D` partial ragdoll blended with animation |
| Head/eye tracking | `LookAtModifier3D` |
| Feet on stairs, hands on ledges | 4.6 IK modifiers (two-bone/chain) — check availability vs `procedural_rig.gd` |
| Movement from animation | `AnimationMixer` root motion |
| Camera rails/framing | Phantom Camera addon |
| Physics speed/stability | Jolt (built in since 4.4) |
| Hide what's behind buildings | `OccluderInstance3D` occlusion culling |
| Distant simplification | visibility ranges / HLOD, auto mesh LOD |
| Cheap interior light | `LightmapGI`; probes `ReflectionProbe` |
| Grading / custom post | `Compositor` effects, `Environment` adjustments |
| Fog | volumetric fog + `FogVolume` per biome |
| Dirt/moss/footprints | `Decal` |
| Many copies | `MultiMeshInstance3D` |
| Background loading | `ResourceLoader.load_threaded_request` |
| NPC navigation at scale | `NavigationRegion3D` chunk baking, `NavigationLink3D`, avoidance |
| Line of sight | `RayCast3D`/`PhysicsDirectSpaceState3D` with layers (staggered) |
| Particles | `GPUParticles3D` with collision/attractors/trails |
| Videos for the owner | Movie Maker mode (`--write-movie`) |
| Profiling | Profiler, Visual Profiler, `Performance` monitors |

## Movie Maker for QA (owner rule)
Check every visual change with a Movie Maker recording, not only screenshots: `godot --write-movie out.avi --fixed-fps 30` with a scripted camera/bot path, windowed, HUD hidden. Movie Maker renders every frame at a fixed timestep, so there are no dropped frames and runs are repeatable. Then analyse it: ffmpeg scene/contact sheets (e.g. one frame per 0.5 s), frame-difference spikes (`select='gt(scene,0.3)'`) to find pops, flicker, LOD swaps and teleports, and side-by-side before/after. Look at the sheets yourself, then send the owner a short MP4 (H.264, under 30 MB, in `Documents\PA_plans\videos\`).

## Terrain3D (1.0.2) features to use before custom terrain code
Instancer (trees/bushes/rocks/grass per region, `add_transforms`) · auto-shader (slope/height texturing) · macro variation + detail noise · steep-slope projection · colour map (biome tint/seasons) · wetness/roughness · holes (caves/mine mouths) · dynamic collision · navmesh baking from terrain · `Terrain3DData` height/normal/texture queries (feed SurfaceQuery). FSR2 crashes with Terrain3D 1.0.2 → FSR1 + TAA.

## Skills index (read the one that matches)
ashes-external-tools · ashes-open-source-sourcing · ashes-mixamo-meshy · ashes-cloud-offload · ashes-animation-pipeline · ashes-performance · ashes-visual-qa · ashes-environment-look · ashes-art-style · ashes-world-interaction · ashes-melee-combat · ashes-build-kit · ashes-perception-ai · ashes-agent-orchestration · ashes-cloud-testing · ashes-work-package.
