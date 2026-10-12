# AAA presentation review (owner + ChatGPT, 2026-10-06), from the S22 screenshots

**Verdict:** the systems are ahead of the presentation. To feel premium we need consistency across lighting, materials, animation, composition, camera, effects, sound, UI and interaction polish. Polygon count matters much less.

**Order of work (follow it):**
1. player character model
2. player locomotion and animation
3. camera
4. lighting and colour grade
5. materials
6. UI/HUD
7. NPC models
8. NPC animation
9. environmental clutter
10. effects
11. dialogue presentation
12. sound
13. LOD and performance

**Golden rule:** don't build another big town. Polish ONE Ashford street block (100–150 m) into a **quality benchmark scene** that looks finished:
- tavern, smithy, market, houses and an alley
- 10–20 NPCs, a horse and a cart
- interiors, day/night and rain
- one fight and one conversation

Every future settlement copies that standard.

## Key points
- **Character tiers:**
  - A: player, companions and story characters: best face, eyes, skin, hair, clothing layers, hands, expressions and physics
  - B: important NPCs
  - C: citizens
  - D: distant crowds (VAT)
- **Skin:** faked shading with a normal map, varied roughness, redness at the ears, nose and cheeks, facial ambient occlusion, and a proper eye material. Eyes matter most.
- **Clothing material identity:** linen, wool, leather, steel, iron, silk, wood, mud and stone should be readable from roughness and normals, not just colour.
- **Animation:**
  - full locomotion: walk, jog, run, sprint, strafe, turn in place, start/stop, 180° turns, slopes and stairs;
  - weight;
  - foot and hand IK (sitting, doors, tools);
  - NPC work broken into modular steps (walk to the field row, pick up the tool, hoe, inspect, carry, wipe brow, chat, go home).
- **Lighting:** less saturation and exposure, warm sun with cool shadows, controlled bloom, atmospheric haze for depth, strong contact shadows and AO, and ground decals so buildings sit into the earth.
- **Roads:** wheel ruts, mud, stones, grass creeping in at the edges, puddles and footprints, done with decals and material blending.
- **Clutter:** controlled clutter (ropes, tools, laundry, herbs, firewood, carts, signs, baskets, troughs, feed). Connect each house to its surroundings: mud at the door, stacked wood, ivy, a drain, a barrel, washing lines.
- **Asset consistency:** a "Rising Ashes material pass" that normalises every Meshy import (texel density, roughness range, saturation range, normal strength, scale).
- **HUD:**
  - default: move, camera, attack, dodge, ability, context, plus small lock-on and switch;
  - everything else contextual: Mount, Talk, Search, Climb, Takedown;
  - fade the HUD out when calm and hide it in dialogue.
- **Remove floating debug text** (name · job · gold · state). Show only a small name when close, and put the rest in a Developer Simulation Overlay.
- **Interaction prompt:** a small icon next to the object, not a big black "Tap to use" box in the middle.
- **Dialogue:**
  - the camera reframes, the NPC and player look at each other, with idles and expressions;
  - the world keeps moving behind;
  - compact choices.
- **Character creator:** a real lit environment (a room with firelight and a mirror) and camera moves; improve the model first.
- **Main menu:** RISING ASHES dominates, with a small "A Total Showdown Studios Game" credit.
- **Map:** a real cartographic object (terrain, roads, forests, rivers, forts, fog of war, annotations). Unknown land fades out instead of showing "UNEXPLORED" boxes. Exploring, buying and stealing maps reveal more.
- **Camera:**
  - closer, with dynamic FOV when sprinting, subtle lag, shoulder bias in combat;
  - lock-on framing that keeps both fighters in view, a brief finisher shot;
  - collision and light shake.
- **Elemental abilities affect the world:** earth raises cover, water puts out fires and freezes, air moves cloth and pushes things, fire ignites and makes smoke. Animation first, effects second, with tiers (small, medium, spectacle).
- **NPC faces:** basic expressions, plus eye, then head, then body tracking.
- **Audio layers** for town, forest, combat and magic. Audio is the big hidden upgrade.
- **Performance by design:**
  - 0–15 m full detail, 15–40 m medium, 40–100 m low, then impostors;
  - 30–60 physical NPCs near the player, with the rest simulated.
- **Fake expensive lighting:** baked lighting, probes and selective shadows.

## Audit 2 scorecard (2026-10-12, PC Mobile renderer 2340x1080, target 00_MAIN)

Cells are before/after where a fix changed the scene; single number = unchanged. Axes: Comp / Light / Mat / Silh / HUD / Motion / Pacing. Motion and Pacing were NOT measured (no Movie Maker run), shown "-". Scores are my honest read of each JPG; draws from the harness (`AUDIT` lines), gate LOW authoritative via `--shot=gate` x3.

| Scene | Tier | Comp | Light | Mat | Silh | HUD | Mean before | Mean after | Draws | Fixes | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|
| title_menu | high | 8 | 8 | 8 | 8 | 8 | 8.0 | 8.0 | - | - | audit2_title_menu_high_before.png |
| creator | high | 6 | 6/6.5 | 7 | 7 | 7 | 6.6 | 6.7 | - | F10 | audit2_creator_high_before/after.png |
| first_exterior | high | 7 | 7 | 7 | 7 | 5 | 6.6 | 6.6 | 454 | - | audit2_first_exterior_high_before.jpg |
| first_exterior | low | 6 | 6 | 6 | 7 | 5 | 6.0 | 6.0 | 156 | - | audit2_first_exterior_low_before.jpg |
| road | high | 7 | 7 | 7 | 8 | 7 | 7.2 | 7.2 | 544 | - | audit2_road_high_before.jpg |
| road | low | 7 | 7 | 6 | 8 | 7 | 7.0 | 7.0 | 75 | - | audit2_road_low_before.jpg |
| gate | high | 8 | 8 | 7 | 8 | 7 | 7.6 | 7.6 | 544 | - | audit2_gate_high_before.jpg |
| gate | low | 7 | 7 | 6 | 7 | 7 | 6.8 | 6.8 | 124 (harness) / 129-132 (--shot) | - | audit2_gate_low_before.jpg |
| dialogue | high | 6 | 7 | 7 | 6 | 8 | 6.8 | 6.8 | 368-636 (partner varies) | F10 (bust unchanged) | audit2_dialogue_high_before/after.jpg |
| dialogue | low | 6 | 7 | 6 | 6 | 8 | 6.6 | 6.6 | 94 | - | audit2_dialogue_low_before.jpg |
| wolf / wolf_lock | high | 7 | 8 | 8 | 7 | 7 | 7.4 | 7.4 | 330/342 | - | audit2_wolf_lock_high_before.jpg |
| wolf / wolf_lock | low | 6 | 7 | 6 | 6 | 7 | 6.4 | 6.4 | 81/77 | - | audit2_wolf_lock_low_before.jpg |
| dusk | high | 7 | 8 | 7 | 7 | 7 | 7.2 | 7.4 | 705 | F2 | audit2_dusk_high_before/after.jpg |
| dusk | low | 7 | 7 | 6 | 6 | 7 | 6.6 | 6.8 | 145 | F2 | audit2_dusk_low_before/after.jpg |
| night | high | 7 | 7/8 | 7 | 6/7 | 7 | 6.8 | 7.4 | 695 | F2 | audit2_night_high_before/after.jpg |
| night | low | 6 | 7/7.5 | 6 | 6/6.5 | 7 | 6.4 | 6.8 | 146 | F2 | audit2_night_low_before/after.jpg |
| map (discovered) | high | 9 | 8 | 9 | - | 8 | 8.5 | 8.5 | - | - | audit2_map_discovered_high_before.png |
| map (undiscovered) | high | 6 | 6 | 7 | - | 7 | 6.5 | 6.5 | - | - | audit2_map_high_before.png |

Gate LOW authoritative draws (3 runs): 132 / 131 / 129 (budget 135). HIGH harness gate: 544 (budget 560); the 3 HIGH `--shot` confirmations timed out and were not run. Baseline p14 images were not re-scored.

Open after audit 2:
- Stacked interactable labels in Ashford square (Notice Board / Steward / Market Trader) in `first_exterior`: one-name-pill rule across Label3D interactables.
- Dialogue framing: partner choice is random per run; in `dialogue_high` after-run the speaker sits behind the sheet edge and a foreground NPC fills the lens. Add a talk-target nearest-in-front rule in `qa_open`/`set_talk_framing` (not done: constants alone did not need change).
- T-posed NPCs visible at mid range in `night_high` (population LOD/anim owner).
- Wolf lock on LOW: wolves are far (12-22 m) and read small; the red spirit companion overlaps the hero.
- F11 first-minute pacing needs a Movie Maker boot_flow run (not measured).
- Creator preview change (F10) is subtle; the panel backdrop is near-black UI, so a lit portrait card would help more.
- Undiscovered parchment map is a flat pale square with hard border against navy (by design: unexplored lands), fog itself is soft.
- `assets/region1/scar_mask_default.png` is a 68-byte placeholder PNG (4x4).

Not changed on purpose:
- F3 dusk keys: dusk gradient is smooth and not banded.
- F4/F5 grade and glow: `gate_high` shows three depth planes and no haloing; lantern glow visible at night.
- F6/F7 camera constants: faces are in the top 60% and the sheet covers <=34%; `wolf_lock` shows both fighters.
- F8 HUD: <=7 controls, no debug line; the label stacking comes from Label3Ds (villager/interactable code), not HUD constants.
- F9 clutter: `gate_high` edges are already framed; LOW untouched.
- F12 map fog: all-discovered map is 8.5/10 and fog fades; no change.
- Environment: this worktree's `.godot` was stale; I re-imported (3 passes) and copied 119 missing git-ignored `*_lod_bake.jpg` sidecars from the main repo. Unverified on phone.
