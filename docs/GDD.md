# Rising Ashes — Game Design Document (v0.1)

> Status: first draft. Anything marked **[PLACEHOLDER]** was inferred from the
> four approved chapter titles in the README and must be replaced with the
> approved chapter text before it counts as canon.

## 1. Pitch

A stylized, mid-size open-world action RPG for mobile. Sugo Wataro, a naive boy
from the fenced village of Aramori, is the one child the Heavenly Way refuses to
bless. The world treats blessings as the measure of a person; Sugo has to find
another kind of strength, and eventually, a reason to defy Heaven.

- **Platform:** Android first (iOS later, needs a Mac for builds)
- **Engine:** Godot 4.4, GL Compatibility renderer (widest Android support)
- **Orientation:** landscape, one-thumb move / one-thumb act
- **Session length:** 10–30 minutes, with save anywhere
- **Target size:** ~1–3 GB installed at full scope; base download under 200 MB
  with regions delivered as Play Asset Delivery packs

## 2. Pillars

1. **The unblessed hero.** Most characters have an element. Sugo has nothing, and
   the game's mechanics make that absence felt. His "Bless" button starts locked.
2. **A world beyond the fence.** Exploration rewards curiosity: hidden shrines,
   Rift scars, lore fragments about the Church and the unclaimed children.
3. **Dark fantasy under a warm surface.** Bright, cosy art over a cruel world.
   The contrast is the point.

## 3. Core loop

Explore region → find a story beat, Rift scar or side quest → fight / talk / solve →
earn skills, gear, lore → unlock the next region or ability → return to a hub.

## 4. Systems (prototype status)

| System | Prototype | Notes |
|---|---|---|
| Third-person movement, run, dodge | ✅ | Camera-relative, touch joystick + keyboard |
| Touch controls | ✅ | Floating joystick, drag-to-look, Strike/Bless/Dodge/Talk buttons |
| Melee combat | ✅ | Wooden sword arc hit, enemy knockback feedback |
| Blessings (elemental casts) | ✅ data-driven | `data/blessings.json`; locked for Sugo at start **[PLACEHOLDER elements]** |
| Enemies | ✅ Rift beast | Wander, chase, bite; defeat counter drives quest |
| Dialogue | ✅ | JSON entries + per-NPC routing by flags and quest step |
| Quests | ✅ linear | `data/quests.json`; steps only advance in order |
| Save / load | ✅ basic | `user://save.json`, autosave on quest progress |
| World | ✅ procedural | Terrain, village, fence, bell tower, forest, lake, Rift scar |
| Audio | ⚠️ minimal | Synthesised bell tone only |
| Real art, animation, VFX | ❌ | Placeholder low-poly primitives |
| Inventory, gear, skill tree | ❌ | Next milestone |
| Region streaming | ❌ | Needed before region 2 |

## 5. Vertical slice: Aramori **[PLACEHOLDER flow]**

Quest *The Day of the Bells*, one step per approved chapter title:

1. **The World Beyond the Fence:** slip out of the south gate.
2. **The Thirteen Bells:** return; the Elder sends Sugo to the bell tower.
3. **When No Bell Rang:** twelve bells answer the other children; the thirteenth stays silent.
4. **The Examination:** the Church acolyte sends Sugo to prove himself against Rift beasts on the south road.

## 6. World structure (mid-size open world)

Semi-open regions of about 300×300 m each, joined by roads and passes and streamed
one at a time (the same structure as the 3D Zelda or Ys games). Proposed regions, names to confirm:

| # | Region | Role |
|---|---|---|
| 1 | Aramori & the Fence Lands | Tutorial, home hub |
| 2 | Church seat / examination grounds | Blessing politics, first city |
| 3 | Thal'ner | **[needs canon]** |
| 4 | Vorrag | **[needs canon]** |
| 5 | The Rift | Late-game, corrupted zone |

## 7. Art direction

- Stylized low-poly, flat/toon shading, warm palette with violet Rift accents
- Readable silhouettes at phone size; big heads, simple shapes
- Budget per region: ~150k tris on screen, ≤150 draw calls, 1–2 atlased 2K textures
- Sources: bought stylized packs (Synty-style), AI concept art for direction,
  then a hired artist for the hero characters

## 8. Mobile technical targets

- 30 FPS on a mid-range 2021 Android phone (Snapdragon 7-series)
- MultiMesh for foliage, baked lighting where possible, one shadowed light
- ETC2/ASTC textures, audio as OGG

## 9. Open questions for the author

1. Which elements exist, and do the thirteen bells map to them?
2. What happens in The Examination (Ch. 4)? Who runs it?
3. Names and roles of the Elder, the acolyte, Sugo's family and friends.
4. Is combat realistic/grounded or flashy?
5. Is Sugo the only playable character?
