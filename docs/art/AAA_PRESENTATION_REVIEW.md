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
