# Kingdom — pixel-rendered 3D medieval sandbox (Godot 4.4)

A real 3D world rendered at low resolution with a pixel-art finish. Start as a
peasant, enlist, lead a militia, clear raider camps and rise toward the crown.
Design and architecture: [`../docs/KINGDOM_DESIGN.md`](../docs/KINGDOM_DESIGN.md).
Screenshots: `../docs/kingdom/`.

## Run it

1. Install **Godot 4.4** (standard build).
2. Import `kingdom/project.godot`, press **F5**.

| Action | Keyboard | Touch |
|---|---|---|
| Move / run | WASD / Shift | left stick (push far = run) |
| Look | right-drag | drag right half |
| Strike | J | Strike |
| Talk / enlist / recruit | E | Talk button when near |
| First ↔ third person | V | 1st/3rd |
| Zoom: third → town → command | mouse wheel, − / = | Zoom − / Zoom + |
| Orders: follow / hold / charge | 1 / 2 / 3 | buttons (once you have soldiers) |

## What's in this first build

- **Pixel renderer:** 3D at 1/3 resolution, nearest-neighbour upscale, colour quantise and dither shader (`shaders/pixel_post.gdshader`), crisp full-res UI on top
- **Four camera scales:** first person (sword viewmodel), third person, town, command
- **4 × 4 km world** streamed in 64 m chunks, with forests as MultiMeshes
- **Settlements:** 10 villages and towns plus a walled castle, built from CC0 models when you approach
- **~5,300 simulated people** as pure data (job, money, daily schedule, wages, market spending), embodied at three levels of detail: data only, directional sprite, animated character
- **Formations:** squads keep formation slots behind you; soldiers steer, engage and fight; orders are Follow, Hold and Charge
- **Impostors:** every unit type is rendered from 4 sides into a sprite atlas at startup, so distant soldiers and crowds cost almost nothing
- **Progression loop:** Peasant → Militia → Sergeant → Captain → … (rank caps army size, gold buys recruits)
- **Day/night cycle** driving light, fog and sprite brightness

## Layout

```
autoload/    game.gd (ranks, gold, input)   world_sim.gd (population database)
scripts/
  core/      main.gd (pixel pipeline, game loop), impostor_baker.gd
  world/     world_gen.gd, terrain_streamer.gd, settlement_builder.gd, assets.gd
  actors/    player.gd (movement, combat, 4 camera scales), captain.gd
  army/      squad.gd (formation AI), soldier.gd (unit + LOD)
  population/ population_lod.gd, villager.gd
  ui/        hud.gd, virtual_joystick.gd
shaders/     pixel_post.gdshader, impostor.gdshader
assets/      KayKit CC0 models (see ASSETS.md)
```

## Preview screenshots without a GPU

```
godot --path kingdom --rendering-driver opengl3 -- --shot=explore --out=/tmp/x.png
```
Shots: `explore`, `first`, `town`, `battle`, `command`, `castle`.
