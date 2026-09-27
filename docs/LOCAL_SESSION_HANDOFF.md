# Local PC session ↔ cloud session: coordination

The user runs **two Claude sessions on this branch at the same time**: the cloud session and a local PC session (with GPU, Blender GUI access and the Meshy MCP). This file keeps them from stepping on each other. **Read it after every pull.**

## Split of work (from 2026-09-27)
| Area | Owner | Notes |
|---|---|---|
| Game code, world layout, placing assets in scenes, lighting and grading | **cloud** | Keep doing what you're doing |
| New 3D assets (Meshy, Blender, open-source sourcing), optimization, previews | **local** | Only adds new files under `kingdom/assets/incoming/`, `kingdom/assets/generated/`, `tools/`, `docs/asset_gallery/` |
| Interiors (inn, blacksmith, guild, healer, houses) | **local** builds the room scenes in `kingdom/scenes/interiors/` (new files) | **cloud** wires the door triggers into the world (the local side will leave a small, self-contained `interior_door.gd` you can drop in) |

Rules:
- The local session **doesn't edit** existing game scripts or scenes unless this file says otherwise. If the local side needs a hook, it writes the request here instead.
- Both sides: `git fetch`, then merge before pushing (the cloud session pushes often).

## Ready for the cloud to integrate
Everything below is optimized for mobile, licence-checked (CC0/MIT, or CC-BY with credit), and has previews in `docs/asset_gallery/index.html`.

- `incoming/ai3d/meshy/`: 5 house types (`house_peasant_a/b`, `house_family`, `house_trader`, `house_manor`) and 2 market stalls, each with `_lod0`/`_lod1`. **These replace the Blender village houses.** Use the same near/far LOD swap as the hero buildings.
- `incoming/ai3d/meshy/creatures/`: goblin, orc, troll, wolf, boar, bear, spider and wyvern (rigged; clips idle/walk/run/attack/hit/death; `_lod1` files). Meshy bipeds have empty hands, so attach weapons to `RightHand`.
- `generated/props/`: 21 upgraded village props sharing `props_atlas.png` (replaces the old lamp post, notice board, signpost and fence).
- `incoming/characters/`: more NPCs on the UAL skeleton (G6, CDmir) plus 166 extra UAL clips. See the "Recommendation" section of its README for the `Assets.UAL_FILES` lines.
- `incoming/animals/`: 26 CC0 animals.
- `incoming/armor/`: armor library. Most plate pieces are off-style; armored characters are coming from Meshy instead (below).

## In progress on the local side
- Armored characters (Meshy, rebound to the UAL skeleton so they share every clip): town guard, knight, mercenary, bandit, noble, orc warchief.
- Interiors: inn and blacksmith first.

## Requests for the cloud session
- Place the new houses, stalls, props, animals and monsters when convenient. When they're in, add a note here so the local side can check the look on a real GPU.
