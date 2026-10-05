---
name: ashes-aaa-camera-hud
description: How Rising Ashes frames the third-person camera and keeps the screen clean the AAA way (shoulder camera, occluder see-through, collision recovery, contextual HUD, no debug text in the world), with the before/after harness on the Ashford benchmark views. Use for any change to chase_camera.gd / player.gd camera code, HUD layout, nameplates, prompts, barks, alert glyphs, or when the owner says the game "doesn't feel AAA".
---

# AAA camera + clean screen

Owner verdict (S22, 2026-10-06): "looks good, doesn't feel AAA". Causes, ranked: camera too high/far/wide and clipping
into roofs, world full of debug text, inconsistent art (flat horses, cone braziers, tile patches), flat lighting.
Review: `docs/art/AAA_PRESENTATION_REVIEW.md`. Evidence: `docs/qa/aaa_feel/` (before_*, after_*, after_walk_sheet.png).

## Camera rules (player.gd `VIEW_RIG`, `SHOULDER_*`; chase_camera.gd `BASE_FOV`)
| | Value | Why |
|---|---|---|
| Distance | 3.9 m (THIRD) | hero ~40% of screen height on a 19.5:9 phone |
| Pivot | 1.62 m (shoulder), +0.42 m right (camera-local, rotated by `_yaw`) | over-the-shoulder; the player root never turns, so offsets MUST be rotated |
| Pitch | -0.2 rad | eye-level, sky + horizon in frame; -0.32 read as a strategy view |
| FOV | 54 vertical | 65 vertical = ~110 deg horizontal on a phone |
| Sprint / combat / talk | chase_camera.gd offsets on top (open ground only +0.35 m) | framing adapts, never a big pull-out |
| Collision | ray pull-in is instant; release eases (3/s for 0.35 s hold, then 7/s) | no pumping past posts |
| See-through | `shaders/camera_see_through.gdshaderinc` in lab_polished(_lite) and lab_grounded: Bayer dither within ~2 m of the lens and in the cone lens -> hero; player.gd writes global `hero_cam_dist` (0 = off) | town props are MultiMesh batches: per-node fades cannot reach them |
| Node fade | `scripts/actors/camera_occluders.gd`: RenderingServer.instances_cull_ray/aabb at 12 Hz, `transparency` on single MeshInstance3D (NPCs, loose props), never MultiMesh | StandardMaterial props and NPC heads next to the lens |
New world shader? Include the see-through file and call it first thing in `fragment()`.

## Clean screen rules
- World text: NPC plate = name only, the single nearest within ~4.5 m (`population_lod.gd`); job/gold/state only with
  Settings > Developer Simulation Overlay (`dev_sim_overlay`, default off). Nameplates: 12 m, 3 shown (`nameplates.gd`).
- Barks: within 11 m, max 2 on screen, smaller font (`villager.gd _say`, `npc_world.gd MAX_BUBBLES`).
- Alert ?/!: smooth SDF glyphs, 14 m (`alert_glyphs.gd`). Squad standards: command view only (`squad.gd`).
- Tutorial prompts: button lessons are a small tag beside their button (`tutorial_prompt_view.gd _beside_button`);
  a calm prompt self-settles after 9 s (`tutorial_director.gd MAX_CALM_SHOW`).
- HUD chrome fades to 22% after 7 s calm (no combat, damage, gold or menu), back at once (`hud.gd _update_calm_fade`);
  hidden in dialogue (existing `_set_chrome_visible`). Touch controls never fade.

## Verify (PC GPU, Mobile renderer; never --headless for renders; never touch the phone while release QA runs)
```
G=".../Godot_v4.6.3-stable_win64_console.exe"
"$G" --path kingdom --rendering-method mobile --resolution 2340x1080 res://tools_qa/aaa_camera/feel_views.tscn -- --adult --skipintro --out=<dir> --tag=after
"$G" --path kingdom --rendering-method mobile --resolution 1170x540 --write-movie <dir>/f.png --fixed-fps 30 res://tools_qa/aaa_camera/feel_views.tscn -- --adult --skipintro --walk
"$G" --headless --path kingdom -s res://tools_qa/aaa_camera/frame_sheet.gd -- --dir=<dir> --out=<sheet.png>
```
Views: 1 village (spawn), 2 street (gate apron + thatch), 3 aftermath (house front, banner pole), 4 horse. `--probe` prints
what the renderer finds near the lens (class, AABB, shader) - use it when something still fills the screen.
A segfault at exit after "FEELVIEW DONE" is a known engine shutdown crash; the PNGs are fine.
A fresh worktree needs the gitignored `*_lod_bake.jpg` sidecars copied from another checkout before it renders.

## Still open (see docs/STATUS_LOCAL.md backlog)
Thatch house material glints like crystal (lab_polished spec/bump on Meshy thatch); walk bot snags on stalls; world-anchored
interaction icon (the tag is beside the button, not the object); lock-on finisher shot.
