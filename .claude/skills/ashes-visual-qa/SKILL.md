---
name: ashes-visual-qa
description: Render in-game screenshots of Rising Ashes (headless cloud or PC) and judge them against the main art reference. Use after any visual change (assets, placement, lighting, UI, characters) and whenever the user asks to "show me" or "check visually".
---

# Visual QA for Rising Ashes

The user wants to SEE results. Every visual change ends with a screenshot compared side by side with
`docs/art/reference/00_MAIN_kingsreach_gate_market.webp` (see `ashes-art-style`), sent with SendUserFile.

## Render a shot (cloud container, Linux)
```bash
cd kingdom
G=/tmp/claude-0/godot/Godot_v4.6.2-stable_linux.x86_64
timeout 600 $G --headless --import --path .            # after adding/changing assets
timeout 300 xvfb-run -a -s "-screen 0 1280x720x24" $G --path . --rendering-driver vulkan \
  -- --shot=gate --out=/tmp/claude-0/shots/gate.png --hour=15 [--weather=clear] [--season=summer]
```
**Never pass `--headless` to a render** (it hangs or gives a black image). Kill stuck Godot only by PID.
On the Windows PC use the 4.6.3 console exe and the bench/playtest scripts instead (see `ashes-collab`).

## Built-in shots (`scripts/core/main.gd` `_screenshot`)
`gate` (Kingsreach gate market, the reference view), `street`, `city` (aerial capital), `explore` (Ashford plaza),
`homestead`, `lake`, `frontier`, `camp`, `aerial`, `vfx`, `site_<kind>`, `interior_<building>`, `birth`.
Also: `stall` (close-up of a Kingsreach gate-road market stall: `--n=8 --dist=5.5 --side=1 --pitch=-0.1`),
`settle` (any settlement from its first gate: `--town=2 --dist=20`, add `--air=55 --airback=30` for a look down at the square)
and `decal` (`--town=2 --kind=wall|ground|soot --n=0`). A/B switches: `--no-goods`, `--no-decals`, `--legacy-plaza`;
`--quality=medium|high` matters: xvfb/llvmpipe auto-detects LOW, which has no decals.
Add a new shot there when a new place needs regular checking.

## Custom captures (UI screens, menus, maps)
Write a scratch `extends SceneTree` script: instantiate `res://scenes/main.tscn` at frame 2, pass `-- --adult`
to skip the birth cutscene, act after ~500 frames (find the HUD: the CanvasLayer that has `show_menu`),
wait ~60 frames, `get_viewport().get_texture().get_image().save_png(...)`, `quit()`. Run it with `-s <script>`.

## Judge the shot (checklist)
1. Warm golden sun, blue-violet shadows, saturated blue sky with white clouds, light haze far away.
2. Red/gold heraldry repeated (banners, tabards), royal-blue roofs, striped awnings.
3. Density: nothing on bare ground — flowers, barrels, crates, stalls, lanterns, people at several depths.
4. Characters readable: coloured clothes, faces, no T-poses, no pink/white missing materials.
5. No holes, floating props, z-fighting, props culled next to the camera.
6. fps line at the bottom is meaningless under xvfb (software) — measure perf on the PC.

## Known pitfalls
- A town-wide MultiMesh gets its visibility range from its AABB centre (the plaza): props next to the player vanish.
  Batch per neighbourhood (`SettlementBuilder._multimesh_cells`).
- Camera yaw for `player.set_camera`: facing a world direction `d` is `atan2(-d.x, -d.y)`.
- Cached `WorldGen` plans change when `city_planner.gd` changes; re-render rather than trusting old shots.
