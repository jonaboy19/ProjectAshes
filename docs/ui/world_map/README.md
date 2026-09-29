# World map review (2026-09-30)

Shots captured in the windowed game with `kingdom/tools_qa/map/map_capture.gd` (start of a new life, then all places discovered).
Baseline (the map as it ships): `docs/ui/world_map/*_2400x1080.jpg` and `*_1600x1200.jpg` (4:3).
Files: `01_full` (start state, 7 of 66 places known), `02_zoom_ashford`, `03_zoom_kingsreach`, `04_marker_card` (player marker + place card + fast travel),
`05_full_all_discovered`, `06_mid_all_discovered`, `07_menu_map_tab` (the map inside the game menu).
With the new painted layer (mock-up, hook applied in a scratch copy only): `docs/ui/world_map/parchment/`.

## What exists
`world_map.gd` (1600 lines): baked 1024 px terrain (worker thread, once), vector roads and rivers, MapIcons badges, discovery fog, legend, place card with fast travel,
quest ping, player marker. It is hosted by the game menu Map tab (`gamemenu/tab_map.gd`) with a filter list. It works and is complete. It is not yet in the poster style.

## Review
**Readability.** At the start only 7 of 66 places are known, so the full view (`01_full`) is one green field with a small clump of icons at the centre; the first impression is emptiness.
On the 2400x1080 screen the square 8 km region only uses the middle 43% of the width; the rest is hatched "Unexplored lands" (`01_full_2400x1080`). 4:3 uses the space much better.
Label collisions in the core valley: the player arrow covers the first letters of KINGSREACH and the Ashford label (`01_full`, `02_zoom_ashford`), "Kingsroad Bastion" sits on the Kingsreach
icon, Millbrook / The Rift / Eastmere overlap, and "Kingsreach Academy of Arms and Arts" is very long (`02_zoom_ashford`). Saltwick's label runs into the scale bar (`05_full_all_discovered_1600x1200`).
Icons stay the same size when zoomed out, so 66 icons pile up around Ashford and Kingsreach (700 m apart = about 65 px at fit zoom).

**Style against the posters.** The posters' region maps are sepia ink on cream: hachured mountains, a pale road ribbon, serif italic names, a compass rose in a corner, misty edges.
The in-game map is a saturated green "game minimap": pixel-stamped tree discs and small triangles, a violet rift stain, cream and red UI plaques. It matches the sunny storybook UI but not the poster maps.
The terrain is baked at 1024 px for 8 km (8 m/px), so zoomed views are visibly soft and the tree discs are blocky (`02_zoom_ashford`, `03_zoom_kingsreach`).

**Names.** All names are data names (Oakvale, Highcliff, Kingsroad Bastion). None of the poster names is on screen: Highwatch Keep, Silverford, Crownstead, Greenhollow, Elden Road, Elder Stones.
Water and forest names are drawn as spaced caps, which is good. There is no name for the roads.

**Icons.** The MapIcons set is clear and consistent: ink-outlined coin badges, red crossed circles for hostile camps, cyan diamonds for runestones, a gold diamond for the marker.
Distinguishing farms / waystations / wayshrines at small size is hard (`05_full_all_discovered`). Icons are much heavier than the terrain, which is what makes the core unreadable.

**Touch UX.** Good: one-finger pan, two-finger pinch about the midpoint, tap radius 34 px, 14 px tap slop, big + / - / recentre buttons (about 85 px), a tap card with a full-width Fast Travel button and the travel time,
a legend that starts closed on touch devices, an emulated-mouse guard. Missing: no fling / inertia after a pan, no double-tap to zoom, the Legend button and the compass overlap on 4:3 (`07_menu_map_tab_1600x1200`),
the tab layout leaves the map only about 1190x650 px of the 2400x1080 screen (the left filter list plus the hatched neighbour regions).

**Performance.** Redraws are cheap on the PC: five forced redraws with 66 places took about 60 ms including vsync, and the terrain is one texture. But every pan event re-records all vector
roads, rivers, icons and labels in GDScript (no caching), and the terrain texture is uncompressed RGBA8 1024 px (4 MB, no mipmaps, so the zoomed-out view shimmers).
The first open waits for the worker-thread bake ("Surveying the realm"). Fog is rebuilt only when the discovery signature changes. I have not measured a phone.

## Painted parchment layer (new)
`kingdom/assets/ui/maps/region1_parchment.png` (2048 px, sepia ink on parchment, from the real WorldGen data) plus `region1_parchment.json` (world to pixel transform, alias table, place list),
drawn by `kingdom/scripts/ui/map_parchment_layer.gd` through the H6 hook (`docs/regions/HOOKS_FOR_CLOUD.md`, "H6: parchment map layer").
- Mock-up with the existing markers: `parchment/01_full_2400x1080.jpg` (fog of war), `parchment/05_full_all_discovered_2400x1080.jpg`, `parchment/02_zoom_ashford_2400x1080.jpg`,
  `parchment/07_menu_map_tab_1600x1200.jpg`; fog off: `parchment/*nofog*`. The sheet alone: `kingdom/assets/ui/maps/region1_parchment.png`.
- Comparison with the poster map: `parchment/poster_vs_parchment.jpg` (left the poster, right the game sheet at 1:1.2).
- Known limits of the mock-up: the game's coin icons still cover the baked pictograms and some baked names (the baked sheet has its own small pictograms; the hook could shrink game icons while the layer is on);
  the 2048 px sheet is soft when zoomed in past about 0.5 px/m; the game's fog reveals circles around known places only.
