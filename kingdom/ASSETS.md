# Asset licences

Every third-party file in this project is **CC0 (public domain)**: free for
commercial use, no attribution required, no royalties. Credit is given anyway.

| Folder | Source | Licence |
|---|---|---|
| `assets/kaykit/characters/` | KayKit Adventurers Character Pack 1.0, Kay Lousberg (kaylousberg.com), github.com/KayKit-Game-Assets | CC0 (`LICENSE.txt` included) |
| `assets/kaykit/weapons/` | same pack, weapon models | CC0 |
| `assets/kaykit/medieval/` | KayKit Medieval Hexagon Pack 1.0, Kay Lousberg | CC0 (`LICENSE.txt` included) |
| `assets/incoming/kenney/impact-sounds/` | Kenney Impact Sounds 1.0 | CC0 (`License.txt` included); used for terrain-aware steps |

Everything else (code, shaders, generated terrain, UI) was written for this
project, except:

| File | Source | Licence |
|---|---|---|
| `scripts/actors/camera_shake.gd` | Ported from the Godot TPS demo, © 2018-2021 Juan Linietsky & Godot Engine contributors | MIT |

## Rules for adding assets

- Only add assets with a licence that allows commercial use **and** redistribution
  in a game build. CC0 is safest; CC-BY is fine if we credit it here.
- Keep the source's licence file next to the asset and add a row above.
- Avoid: "free for personal use", ripped game assets, unlicensed Sketchfab
  downloads. Mixamo animations are allowed in games but can't be
  redistributed as raw files, so keep them out of a public repo.
- Candidates for later (download on a PC, since this cloud environment can't
  reach these sites): Quaternius (CC0 animals and **horses**, characters,
  animation library), Kenney (CC0), Poly Pizza (check each model's licence).
