---
name: ashes-open-source-sourcing
description: Find, licence-check and import free open-source assets and code (models, rigs, animations, armor, textures, audio, Godot addons) for Rising Ashes, so nothing is made from scratch that already exists. Use whenever pulling anything from GitHub, Reddit, itch.io, OpenGameArt, Quaternius, KayKit, Kenney, Poly Haven and similar.
---

# Open-source sourcing for Rising Ashes

The game ships **commercially** on the Play Store and App Store. Every asset must be **free and allowed for commercial use**.

## Licence gate (check at the actual source page, never from a Reddit post)
| OK | Only with credit | Never |
|---|---|---|
| CC0, public domain, MIT, BSD, Apache-2.0, SIL OFL, Unlicense | CC-BY 3.0/4.0: copy the exact credit line into the pack's LICENSE file and the pack README | CC-BY-**NC**, CC-BY-**SA** on code we link (ask first), personal use only, "free for non-commercial", Unreal/Unity-only EULAs, raw Mixamo redistribution, **Hunyuan3D**, **Higgsfield**, free tiers of Tripo/Suno/ElevenLabs, unclear or missing licence |

Save the licence file and **licence URL** in every pack folder.

## Where to look
- **Assets:** Quaternius (CC0; Universal Animation Library, Ultimate Modular Men/Women, fantasy packs), KayKit on GitHub (CC0), Kenney (CC0), Poly Haven and ambientCG (CC0), Poly Pizza (filter to CC0), OpenGameArt (filter to CC0/CC-BY), MakeHuman/MPFB assets (CC0).
- **Projects and code:** GitHub topic searches (`godot`, `godot4`, `gdscript`, `medieval`, `rpg`, `character-controller`), Godot Asset Library (MIT addons), Godot demo projects.
- **Discovery:** Reddit r/godot, r/gamedev, r/blender, r/GameAssets, r/proceduralgeneration and AI game-dev threads. Treat these as leads only and verify the licence at the source.

## Make it look natural in our world (required for every import)
Packs from different authors clash unless they're harmonised. Before anything is accepted:
- **Style:** compare against `docs/art_reference/village_target_1.png`. Pick the pack that fits best per category, and don't mix flat-colour toy packs with detailed painted ones in the same scene.
- **Colour:** natural, warm, slightly saturated tones. Retexture or recolour in Blender (hand-painted gradient textures, shared palette atlas) when a pack is neon, grey-flat or too dark.
- **Scale:** real-world metres (door 2.1 m, human 1.75 m, chicken 0.4 m, sheep 0.9 m, cow 1.4 m at the shoulder, horse 1.6 m at the shoulder). Put the origin at the feet or base.
- **Consistency:** similar stylisation and proportions within a category (all animals, all villagers), with shared materials where possible.
- **Check:** render the new asset next to an existing accepted asset (for example a Meshy house or villager) and look at it before accepting.

## Categories and where they live
| Category | Folder | Source preference |
|---|---|---|
| Hero buildings, house types, stalls, monsters | `incoming/ai3d/meshy/` | Meshy (paid plan) |
| Village props | `kingdom/tools/blender/make_*.py` | Blender scripts plus CC0 packs |
| Player, NPCs, animations | `incoming/characters/` | Quaternius UAL, KayKit, MakeHuman (CC0) |
| Armor and medieval gear | `incoming/armor/` | Quaternius outfits, Creatus, KayKit, OGA |
| Ordinary animals | `incoming/animals/` | Quaternius animals, Kenney, Poly Pizza CC0 |
| Weapons and items | the user makes these; don't source unless asked | |

## Import conventions
- New packs go in `kingdom/assets/incoming/<source>/<pack>/`. Keep the LICENSE file and add a `.gdignore` until the game uses the pack.
- Characters go in `incoming/characters/`, armor in `incoming/armor/`, Meshy output in `incoming/ai3d/meshy/`.
- Convert to GLB (Blender 5.2 headless, no Draco/meshopt) and optimize to the `ashes-asset-pipeline` budgets.
- Render a labelled contact sheet into the pack's `_previews/` and look at it before reporting.
- Record each pack in the matching README table (source, licence, credit, tri counts, notes).
