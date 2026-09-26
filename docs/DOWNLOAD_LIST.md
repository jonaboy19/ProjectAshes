# Kingdom: asset download list

**For:** the person or Claude instance downloading on a normal PC/phone (the
cloud dev environment can't reach these sites).
**Goal:** replace the toy-like placeholder art with modern, commercially safe
assets, and get horses, animations, sound and proper cities.

## How to deliver

1. Download the items below (free unless marked **PAID**).
2. Unzip each into the repo at `kingdom/assets/incoming/<source>/<pack-name>/`
   (example: `kingdom/assets/incoming/quaternius/medieval-village-megakit/`).
3. **Keep each pack's licence/readme file** inside its folder.
4. Prefer **glTF/GLB**; FBX is fine if there's no glTF. For textures take the **2K**
   version (1K is fine for mobile), PNG or JPG.
5. Commit and push to branch `claude/focused-curie-m09hbd` of
   `jonaboy19/ProjectAshes`. Large binary files are fine; if a single file is
   over 100 MB, skip it or use Git LFS.
6. Leave a note in `kingdom/assets/incoming/README.md` listing what was added.

Licence rule: only **CC0**, **CC-BY** (credit it), or royalty-free commercial
licences. Nothing "personal use only". Nothing Unreal-only if it's meant for Godot.

---

## Priority 1: makes the biggest visual difference

| # | What | Where | Licence | Why |
|---|---|---|---|---|
| 1 | **Medieval Village MegaKit** (modular walls, roofs, doors, windows, stairs) | quaternius.com → search "Medieval Village" | CC0 | Build **full cities** street by street from modular parts |
| 2 | **Stylized Nature MegaKit** (trees, bushes, grass, rocks, flowers) | quaternius.com → "Nature MegaKit" | CC0 | Real-looking forests and grass instead of toy cones |
| 3 | **Universal Animation Library** (+ Universal Base Characters) | quaternius.com → "Universal Animation" | CC0 | Hundreds of humanoid animations, one shared rig |
| 4 | **Animated horse** (in "Ultimate Animated Animal Pack" or a standalone horse) | quaternius.com → "Animal" / "Horse" | CC0 | Riding and cavalry |
| 5 | **HDRI skies ×3** (a clear day, an overcast day, a sunset), 4K .hdr/.exr | polyhaven.com/hdris | CC0 | Realistic sky and lighting |
| 6 | **PBR ground textures** (forest ground, grass, dirt path, rocky terrain, mud, cobblestone), 2K | polyhaven.com/textures **or** ambientcg.com | CC0 | Detailed terrain up close |
| 7 | **PBR building textures** (castle stone/brick, plaster, wood planks, roof tiles, thatch), 2K | polyhaven.com/textures **or** ambientcg.com | CC0 | Walls and roofs that don't look plastic |

## Priority 2: characters and combat

| # | What | Where | Licence | Why |
|---|---|---|---|---|
| 8 | **Mixamo characters + animations**: a knight, a peasant, a soldier; animations: sword combos, shield block, dodge, hit reactions, deaths, walk/run, **horse riding** | mixamo.com (free Adobe account). Download FBX "with skin", 30 fps | Free for games; **no redistribution of the raw files** | Most realistic free human motion. Keep the repo **private** if these are committed |
| 9 | **Medieval weapons & armour props** | quaternius.com "Fantasy Props MegaKit", or kenney.nl | CC0 | Swords, shields, spears, bows |
| 10 | **Kenney Castle Kit + Fantasy Town Kit** | kenney.nl/assets | CC0 | Extra walls, towers, gates for castles |

## Priority 3: sound, music and UI

| # | What | Where | Licence |
|---|---|---|---|
| 11 | Kenney **RPG Audio**, **Impact Sounds**, **UI Audio** | kenney.nl/assets (Audio category) | CC0 |
| 12 | Sword clashes, footsteps, crowd, horses, ambience | freesound.org (filter licence: **CC0**) | CC0 |
| 13 | Big royalty-free SFX library | sonniss.com/gameaudiogdc (free yearly bundles) | Royalty-free commercial |
| 14 | Medieval music (2-4 tracks: village, battle, castle, night) | opengameart.org (filter CC0 / CC-BY) or incompetech.com (CC-BY, credit Kevin MacLeod) | CC0 / CC-BY |
| 15 | Fonts: **Cinzel**, **IM Fell English** | fonts.google.com | SIL OFL (free commercial) |

## Optional PAID (best value if budget allows)

| What | Where | Approx. | Notes |
|---|---|---|---|
| **Synty POLYGON Fantasy Kingdom** + **POLYGON Knights** | syntystore.com | ~$100–150 each | The clean modern low-poly look many hit mobile games use. Commercial use OK, can't redistribute; keep the repo private |
| Realistic medieval town/castle packs | fab.com (check the licence is "all engines", not Unreal-only) | varies | Only if we go realistic or move to Unreal |

## Not needed (already have)

- KayKit Adventurers + Medieval Hexagon (CC0): already in `kingdom/assets/kaykit/` and kept as fallback/placeholders.

---
When it's pushed, tell the dev Claude: *"New assets are in `kingdom/assets/incoming/`,
please integrate them."*
