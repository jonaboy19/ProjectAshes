# Rising Ashes: reference video analysis (2026-10-27)

Source: 20 owner-uploaded TikTok clips (mostly 576x1024 portrait, 21–77 s each). Each video was sampled at 32 evenly spaced frames, and every contact sheet was viewed. The sheets are outside the repo at `C:\Users\Jonna\Documents\PA_plans\ref_videos_2026-10-27\<n>\sheet_{1,2}.jpg`.
Compared against `MECHANICS_AUDIT.md`, `FULL_GAME_GAP_AUDIT.md`, `GAME_VISION_OWNER_2026-10-26.md`, `PERF60_BRIEF.md`, `docs/world/REAL_WORLD.md`, `docs/qa/PC_QUALITY_STATUS_2026-10-26.md`, `kingdom/scripts/core/quality.gd`, and in-game captures (`docs/world/w5/reg_*.jpg`, `docs/qa/towns_medieval/*`). Godot was not run.

Status key: **HAVE** = in the game at roughly the shown quality. **PARTIAL** = system exists but is below the reference. **MISSING** = no code or content. Paths are relative to `kingdom/`.

Caveat: these are compressed vertical TikTok re-uploads with captions over the picture. Fine detail (texel density, hair cards, exact AA) can't be judged from them. Game identification is from on-screen logos, captions, UI and art style. Where an ID is uncertain it says so.

---

## 0. Where Rising Ashes is today (baseline)

- **Renderer and tiers.** Forward+ with `scripts/core/quality.gd` PC_LOW/MED/HIGH/ULTRA. HIGH and ULTRA already enable SDFGI, SSR, volumetric fog, SSAO and glow; ULTRA adds SSIL. **Risk:** PC_MED, HIGH and ULTRA set `"scaling": "fsr2"`, but Terrain3D 1.0.2 crashes with FSR2. These must be switched to FSR1 + TAA until Terrain3D 1.1 (WP-G0).
- **Look.** Stylised and toon-leaning (Sky3D, `terrain3d_ground.gdshader`, `tree_wind.gdshader`, `grass.gdshader`, impostors, `contact_shadow.gdshader`). In the w5 aerials, terrain reads flat and washed out: large uniform paint blobs, little macro variation, low-contrast haze. The ground-level forest shot (`reg_03` top right) is lush but painterly. Every reference video except #1 targets photoreal UE4/UE5.
- **Systems.** A very broad simulation already exists: survival needs, crafting, a Palworld-style build kit, recruitment, companions, armies/formation/morale (`scripts/army/*`), lordship, raids, careers, horses, a dialogue system and photo mode. Most gaps against the references are fidelity gaps (graphics, animation, combat feel), not missing systems.

---

## 1. Per-video analysis

### V1 `66a646e6`: Dungeons & Kingdoms (biffmatic showcase, 50 s). Stylised low-poly, Unity/UE.
Scenes: knight on horseback before a snowy castle, a giant troll in a misty pine forest, a dungeon crawl through a golden hall, a rowing boat with 4 companions over a clear turquoise shallow sea, a night torch camp, a castle-gate market city, a ship on a lake, a lava dungeon with a treasure hoard, timber villages, chopping logs, a mule ride, blueprint (holographic blue) building placement, download presets, a green spectral necromancer arena, a library.
| Area | Feature | RA |
|---|---|---|
| Graphics | Bright saturated stylised PBR, strong sun shadows, big volumetric cumulus | PARTIAL: Sky3D clouds, sun shadows (quality.gd) |
| Graphics | Shallow-water caustics, turquoise depth colour, visible sea floor | PARTIAL: `world/water_streamer.gd`, no depth-tint or caustics pass |
| Graphics | Forest fog with god-ray shafts | PARTIAL: vol fog on HIGH/ULTRA, no tuned light shafts |
| Graphics | Lava emissive + heat glow in dungeons | PARTIAL: element VFX exist, no lava material |
| Buildings | Castle gate with market stalls outside (tents, awnings) | PARTIAL: towns pass (`TOWNS_MEDIEVAL_PASS.md`), gate markets exist |
| Buildings | Modular building: foundation → blueprint ghost → finished cabin; download/share presets | PARTIAL: `build/build_mode.gd` ghost; **no blueprint presets / share** |
| World | Lake with sailing ship; coast | PARTIAL: water yes, ships no |
| Animation | Rowing (party in boat), log chopping, horse/mule riding | PARTIAL: chop + horse HAVE (`scripts/horses`), **rowing MISSING** |
| Systems | Boats / water travel with companions | **MISSING** |
| Systems | Dungeon delving with loot hoards, boss rooms | HAVE: `DUNGEON_VISION.md`, dungeon doors |
| Systems | Tech advancement | PARTIAL: crafting tiers |
| Systems | Village NPCs with dog/pet following | PARTIAL: critters, no pet companion |

### V2 `b38372a6`: Conqueror's Blade (agenterino, 42 s). UE-class, MMO siege.
Scenes: snowy wall with a spear line, massed Ming-style infantry, cavalry with banners, a burning castle, siege ladders/towers being climbed, a gate breach with an ally outline (blue ghost ally highlight), a cannon, archers, a fire-arrow volley, a red-white flag, unit ability glows.
| Area | Feature | RA |
|---|---|---|
| Graphics | Large-scale smoke columns, burning buildings, ember sparks, haze | PARTIAL: fire VFX (Effekseer, `vfx/*`), **no large smoke plumes / building fire states** |
| Graphics | Snow-covered terrain with footpath trampling | PARTIAL: snow line + footprints (`surface_feedback`) |
| Buildings | Stone curtain walls with walkways, gatehouses, siege towers, ladders on walls | PARTIAL: town walls; **no siege tower / ladder-on-wall assets** |
| Animation | Ladder climbing under fire, spear brace, cavalry charge, mass melee | PARTIAL: ladder HAVE (`traversal.gd`), cavalry charge PARTIAL |
| Systems | Player commands a unit of troops (formation, charge, hold) | PARTIAL: `army/formation.gd`, `squad.gd`, `morale.gd` |
| Systems | Siege battles: rams, ladders, towers, cannons, flag capture | **MISSING** (armies sim is strategic only) |
| Systems | Ally highlighting / outline, objective banners | PARTIAL: `enemy_rim.gdshader`, no ally outline |
| Audio | Battle ambience, war drums | PARTIAL: `audio_director.gd` |

### V3 `dca3050a`: Blight: Survival (GameSpot, 35 s, "in development"). UE5. This is the owner's "blight" look target.
Scenes: a hooded knight in a ruined forest chapel under dense teal fog; a half-timbered house with warm window glow at night; a castle silhouette in fog over water; a misty marsh battlefield with smoke and stake walls; a ruined tower with smoke; a knight before a curtain-wall castle with a trebuchet and red grass; a blood-soaked interior; door-breach melee with a grapple-kill.
| Area | Feature | RA |
|---|---|---|
| Graphics | **Heavy height + volumetric fog, teal/desaturated grade, light shafts**: the signature look | PARTIAL: vol fog on HIGH+, no per-biome fog/grade profiles at this density |
| Graphics | Lumen-like soft GI: bounce on stone, warm interior light spilling out of windows | PARTIAL: SDFGI on HIGH+. Window spill needs emissive + OmniLights |
| Graphics | Photoreal PBR (scanned stone, mud, wet wood), high texel density | PARTIAL: Poly Haven 2k on disk (`assets/incoming/polyhaven`), stylised shaders dominate |
| Graphics | Water: dark reflective marsh, SSR reflections of the castle | PARTIAL: water SSR on HIGH+ (`water_ssr`) |
| Graphics | Blood pools, gore decals, red-tinted grass (blight biome) | PARTIAL: blood in `takedown.gd`/`evidence.gd`. **No persistent pooled-blood decals, no blight biome tint** |
| Graphics | Cinematic DoF, film grain, vignette, ACES | PARTIAL: DoF used in combat/traversal, no grain/LUT stack |
| Buildings | Ruined masonry, palisades, cheval-de-frise stakes, gibbets, cages | PARTIAL: ruins assets; **gibbet, cage, stake walls MISSING** |
| Animation | Heavy armoured locomotion with weight; contextual door-breach; grapple + execution kill | PARTIAL: takedown exists, **paired grapple kills MISSING** |
| Systems | Plague-infested hostile world, co-op | out of scope (co-op) |

### V4 `fba28d5b`: plague-era medieval colony survival, puls_games (38 s). Likely *The Nested* / a UE5 plague-village survival game (title partly shown as "...NESTED PULS").
Scenes: a peasant bashing at a tree trunk; misty pine forest with villagers; a lean-to stick shelter, then a log cabin interior/porch; a top-down camp with fires and resources; a tavern full of NPCs eating and drinking (close-up of a grotesque NPC drinking from a tankard); an alarm bell; a plague corpse; a night forest with village lights; an antlered masked cultist.
| Area | Feature | RA |
|---|---|---|
| Graphics | Low-key dark forest fog, warm torch pools, close-up DoF | PARTIAL |
| Buildings | Progressive shelter tiers: lean-to → log cabin → village | PARTIAL: construction tiers in `realm/construction.gd`; **lean-to stage MISSING as a visual** |
| Animation | Tavern life: sitting, eating, drinking from tankards, talking at tables | PARTIAL: seat interaction exists; **eat/drink-at-table clips + props in hand** limited |
| Animation | Facial close-ups with expression | **MISSING**: `hero_face_driver.gd` is hero-only, villagers have no facial rig |
| Systems | Settlers with needs (food, water), alarm bell to call villagers to defence | PARTIAL: raids (C9) yes; **alarm bell rally MISSING** |
| Systems | Disease / plague (corpses, infection) | **MISSING** (injuries only) |
| Systems | Night threats, cult enemies | PARTIAL: creature AI |

### V5 `cd976500`: Bellwright (wilfratgaming, 77 s). UE5.
Scenes: archer in golden-hour meadow, scavenging a cart, a flax field, thatched buildings with a windmill, a palisade under construction, a snow-covered village at night with warm windows, combat (directional melee with health bars over enemies), carrying a man, axe-swinging, shield wall, standing stones with poppies, ruined castle, organised villagers.
| Area | Feature | RA |
|---|---|---|
| Graphics | Golden-hour sun with long shadows, bloom, glowing atmosphere | PARTIAL: Sky3D time-of-day; grade too flat |
| Graphics | **Seasonal snow cover on roofs and ground** | PARTIAL: snow by altitude only (`snow_line`); **no seasonal / shader snow on roofs** |
| Graphics | Dense meadow grass with flowers, wind waves | PARTIAL: `grass.gdshader`, proton_scatter; density lower |
| Buildings | Thatch roofs, wattle walls, windmill with turning sails, blacksmith, palisade + watchtower | PARTIAL: towns have these types; **animated windmill sails MISSING/unknown** |
| Animation | Directional sword/axe, shield bash, bow draw, carry a body over the shoulder | PARTIAL: combat HAVE; **carry-body MISSING** |
| Systems | Villagers assigned to jobs (gathering, smithing), companions, real-time directional combat, armies you train | PARTIAL: recruit/companions HAVE; **settler job assignment MISSING** (FULL_GAME_GAP_AUDIT "still open") |
| Systems | Health bars over enemies | PARTIAL: HUD exists |

### V6 `f5bb7d8c`: ASKA ("Valheim meets Medieval Dynasty", xrealm_servers, 39 s). Unity HDRP.
Scenes: Viking longship on stormy sea, Viking village with palisade, swamp biome, desert-red biome, purple dusk lighting, snow gate, villagers at training dummies, a dragon/drake flying, rune stone with fire, docks with a ship.
| Area | Feature | RA |
|---|---|---|
| Graphics | Stormy ocean with waves, foam, spray; sea fog | **MISSING**: no ocean wave shader |
| Graphics | Strong stylised-real colour grading per time of day (purple dusk, gold sunset) | PARTIAL: Sky3D. Needs a LUT per time of day |
| Graphics | Blizzard / heavy snowfall with low visibility | PARTIAL: `weather.gd` snow; no blizzard state |
| World | Distinct biomes (swamp, red desert, snow, coast) | PARTIAL: biomes in WorldGen; colour/material identity weak in w5 aerials |
| Buildings | Longhouses, palisade gates, docks/piers, watchtowers | PARTIAL: **docks/piers MISSING** |
| Systems | Village management: villagers with roles, training dummies | PARTIAL |
| Systems | Flying monster boss (drake) | PARTIAL: `creature_models.gd` dragon |
| Systems | Sailing | **MISSING** |

### V7 `a6b781ec`: Chivalry 2 / similar first-person medieval melee (joysticknews "The medieval game online", 63 s). UE4.
Scenes: first-person halberd, red-tabard infantry, beach with ships and siege engines, objective "PUSH THE BATTERING RAMS", heavy blood spray and pools, kill feed, rank-up toast ("Halberd rank increased"), counter icon.
| Area | Feature | RA |
|---|---|---|
| Graphics | Blood spray particles + ground blood pools that persist | PARTIAL: impact pool, **no persistent blood decals** |
| Graphics | Large crowd of fully animated soldiers | PARTIAL: crowd LOD (VAT, sprites) |
| Animation | First-person weapon arms, windup/release/recovery, chambers, feints | **MISSING**: no first-person mode (deliberate; third-person game) |
| Systems | Objective-based battle (push rams), kill feed, weapon mastery ranks | PARTIAL: war system; **weapon-mastery ranks MISSING** |

### V8 `c8909f2d`: Knight's Path (pre-alpha, biffmatic, 46 s). UE5.
Scenes: plate-armoured knights duel in a castle yard and on a rocky path; KCD2 comparison; gatehouse bridge; cave mouth with sun spill; thatched village; huge dragon in fog; giant snail in poppies; martial-arts-inspired positional fencing; parries.
| Area | Feature | RA |
|---|---|---|
| Graphics | Photoreal plate armour (anisotropic metal, clear reflections), cloth tabards | PARTIAL: armour PBR, no anisotropy |
| Graphics | Cave-mouth light spill with GI | PARTIAL: SDFGI |
| Animation | **Historical fencing**: guards (ox, plough, roof), half-swording, positional footwork, parry → riposte, grapples | PARTIAL: block/parry HAVE (`hit_resolver.gd`), **guard stances + half-sword + bind MISSING** |
| Animation | Cloth tabards and capes reacting to motion | PARTIAL: cloth/spring bones exist for hero (`hero_outfit.gd`), not NPC |
| Systems | Skill progression in combat, creatures (dragon, giant snail) | PARTIAL |

### V9 `4b359dc7`: Blight: Survival (gameplay trailer cut, game.rush67, 21 s, 1080p). UE5.
Scenes: a knight lifts and slams an enemy before a ruined castle; misty ruins; a stone arch fight; a dark forest with a burning cart; a night teal battlefield with fires; a two-hand sword kill.
| Area | Feature | RA |
|---|---|---|
| Graphics | Desaturated teal night, fire point lights casting into fog, wet ground reflection | PARTIAL |
| Animation | **Paired animations**: lift + slam, shove, kick, two-person grapple, execution | **MISSING** (only `takedown.gd` single-sided) |
| Animation | Hit reactions with momentum, full-body stagger, ragdoll blend | PARTIAL: `knockdown_state.gd`; **no physical-animation blend** |
| Systems | Grim co-op melee | n/a |

### V10 `98f25868`: Medieval Dynasty (bluethunder review, 65 s). UE4.
Scenes: horse riding through autumn forest, aerial of a thatched village, winter wolves/bears chasing, the character creator, FP bow hunting a deer, a radial build menu over a lake, NPC dialogue with name + age + options, a market square, herb gathering ("Henbane – Collect"), farm fields of wheat, windmill, inventory paper-doll with character parameters, felling a log, diplomacy level-up, a cradle (bloodline/children), co-op "Oxbow" map.
| Area | Feature | RA |
|---|---|---|
| Graphics | Seasons (autumn leaves, winter snow, summer); dense temperate forests | **MISSING**: no seasonal system (weather only) |
| Graphics | Wheat fields with wind waves | PARTIAL: farm spots exist, field mass/wind unknown |
| Systems | **Radial build menu** | PARTIAL: build menu exists (not radial) |
| Systems | Character creator | HAVE: `ui/character_creation.gd` |
| Systems | Dialogue shows NPC name + age + numbered choices | HAVE: `talk_session.gd`, `dialogue_manager` |
| Systems | **Marriage, children, bloodline / play as heir** | PARTIAL: `realm/dynasties.gd` Stub; **heir play MISSING** |
| Systems | Farming cycle (plough, sow, harvest), animals to feed | PARTIAL: `farm_work_spot.gd`; no full seasonal crop cycle |
| Systems | Skills with level-up toasts (Diplomacy) | HAVE: careers/skills |
| Systems | Village of NPCs with jobs | PARTIAL (job assignment missing) |
| Animation | FP-style bow draw, tree felling, herb pick | PARTIAL/HAVE (third-person) |

### V11 `977a0930`: For Honor (robbiegaming1104 streamer, 24 s). Ubisoft AnvilNext.
Scenes: a duel in a snowy Chinese temple courtyard; the guard-direction reticle (3-way directional indicator); heavy blood; executions; HUD bars with enemy name.
| Area | Feature | RA |
|---|---|---|
| Systems | **Directional guard UI (left/right/top)** with readable telegraphs | PARTIAL: `telegraph_rings.gd`; no 3-way guard |
| Animation | Executions, heavy-weapon flourishes, dodge-steps | PARTIAL: takedowns |
| Graphics | Blood splats on snow; weapon trails | HAVE (`weapon_trail.gd`), blood PARTIAL |

### V12 `61ba177a`: Mount & Blade II: Bannerlord (steam.cursed, 44 s). TaleWorlds engine.
Scenes: a review overlay (looters, recruiting peasants, accidental marriage, caravans, workshops, betrayal) over massed cavalry charges, shield walls, sieges, snow battles.
| Area | Feature | RA |
|---|---|---|
| Systems | Recruit peasants into an army, caravans, workshops, marriage, kingdom politics, betrayal | PARTIAL: recruitment, enterprises (`enterprise_screen.gd`), nobility; **caravans as moving world entities MISSING**, marriage Stub |
| Systems | Large field battles (hundreds of units) with order commands | PARTIAL: `army/*` squads; scale limited by perf |
| Animation | Mounted combat (couched lance, swing from horse) | PARTIAL: horses; **mounted melee clips** limited |

### V13 `aaec0757`: Medieval Dynasty (wilfratgaming, 70 s). UE4.
Scenes: a busy village market, valley vista, a green-ghost build placement (valid = green, preview cyan), hunting, a torch cave, a female NPC with a dialogue box, winter torch walk, FP bow, hammering a fence (FP), two maps, villager bringing produce, crossbow.
| Area | Feature | RA |
|---|---|---|
| Graphics | Bright sun-bloom, sun flare, soft fog layers over valley | PARTIAL |
| Graphics | Torch-lit cave with orange GI bounce | PARTIAL: SDFGI HIGH+ |
| Systems | Green/red placement validity ghost | HAVE: `build_mode.gd` ghost (check colour feedback) |
| Systems | Mines/caves you can enter with torches | HAVE: caves + dungeons |
| Animation | Hammering, crossbow reload | PARTIAL |

### V14 `66827901`: medieval MMO with Polish UI (wilfratgaming, 49 s). Unidentified (UE5; "Gael Holy Site", "Małe piwo" item, territory map with "Get More Grace"). Treat as "UE5 medieval MMO".
Scenes: players in plate overlooking a valley town; a face tattoo close-up; balcony; vistas; gathering a chamois goat ("(Hold) Harvest"); an item tooltip with stat buffs; stone arcade; combat XP popups (+20 XP, damage numbers); a skill tree list; a territory map with holy sites; golden-hour fields.
| Area | Feature | RA |
|---|---|---|
| Graphics | **UE5-grade vistas**: layered mountains, aerial perspective, sunlit clouds, dense forest at distance | PARTIAL: horizon mesh (`REAL_WORLD.md`), Terrain3D. **Distance detail and atmospheric perspective weak** |
| Graphics | Detailed faces with tattoos, skin SSS | PARTIAL |
| Systems | Hold-to-harvest prompts on animals | HAVE (corpse_loot) |
| Systems | Item tooltips with buff stats, durations | HAVE (gloot UI) |
| Systems | Damage numbers + XP popups | PARTIAL (check HUD) |
| Systems | Territory map with holy sites, fast travel | PARTIAL: `world_map.gd`; fast-travel status unknown |

### V15 `431e1ffc`: Manor Lords (stridahsangels, 77 s). UE4/5.
Scenes: aerial views of castles being built, a wall-drawing tool (white ghost walls following a drawn path), a red invalid wall, river valley, region borders, unit formations (red/blue), crossbowmen on walls, a burning castle at night, a trebuchet, a woodcutter building card, windmill, a tournament field.
| Area | Feature | RA |
|---|---|---|
| Graphics | Aerial-camera realism: rivers with banks, rocky outcrops, field patchwork | PARTIAL: w5 aerials show flat blob painting |
| Buildings | **Spline wall drawing** (draw a curtain wall along a path, towers auto-inserted) | **MISSING**: build kit is piece-by-piece |
| Buildings | Organic plots (burgage plots drawn freehand, houses grow) | **MISSING** |
| Systems | RTS strategic camera over your settlement | **MISSING** (lord hall UI only) |
| Systems | Region borders, factions | PARTIAL: realm map |
| Systems | Siege: troops on walls, ladders, trebuchets, fire | **MISSING** (tactical) |
| Systems | Tournaments | PARTIAL: academy mention only |

### V16 `e25b54ad`: Bellwright (puls_games, 47 s).
Scenes: ruined tower on cliffs, a vista, an outskirts village, standing stones, a windmill, snow villages day and night, directional combat (rewards mastering swords), shields and bows, tactical lines, hanging meat on a drying rack, an archer.
Same feature set as V5. Extra items:
| Area | Feature | RA |
|---|---|---|
| Graphics | Snow-covered roofs + smoke from chimneys | **MISSING**: chimney smoke particles in towns unknown; roof snow MISSING |
| Buildings | Meat drying rack with meat | PARTIAL: drying rack prop on disk |
| Systems | Forming tactical lines with your recruits | PARTIAL: `formation.gd` |

### V17 `3f2d64b5`: Chivalry 2 (French UI "Défendre la grand-porte", labrutegameplay, 54 s). UE4.
Scenes: third-person view of a plated knight with a lion tabard defending a great gate; extreme blood sprays; kill feed; "rank de classe Messer augmenté"; a burning village; a riposte icon.
| Area | Feature | RA |
|---|---|---|
| Graphics | **Massive volumetric blood sprays**, lingering blood on armour/weapons | PARTIAL: no wet-blood mask on characters |
| Systems | Objective defence timers, team kill feed | PARTIAL |
| Animation | Riposte, counter, heavy overhead, kick | PARTIAL |

### V18 `62b9e652`: Chrono Odyssey (bluethunder, 66 s). UE5.
Scenes: horse through a grand gothic city, magic blasts, a riverside village, forging at an anvil with sparks, an airship crash with explosions, a giant boss raid in water, purple spell particles, desert caravan wagons, an arena.
| Area | Feature | RA |
|---|---|---|
| Graphics | UE5 Nanite-density cities, high-end VFX (bloom, particles, distortion) | PARTIAL: Effekseer VFX |
| Graphics | Water splash / interaction during boss fight | PARTIAL: ambient splash shader |
| Animation | Forging (hammer on anvil with sparks) | PARTIAL: blacksmith career task, anim unknown |
| Systems | Boss raids, crafting, magic + melee, mounts | HAVE/PARTIAL: elements + creatures |
| Systems | Caravans | **MISSING** |

### V19 `82f11aca`: cinematic medieval trailer (kreyzogaming, 27 s). Likely *Bellwright* or *Kingmakers*-style UE5 cinematic. Uncertain.
Scenes: an aerial over a dusty village; a crowded market with merchants; an army of plate knights with checkered banners; banners in a sunset field; a trebuchet at night; a man silhouetted before a burning house; a close-up of a helm with a crest.
| Area | Feature | RA |
|---|---|---|
| Graphics | **Fire + ember-filled night, strong backlight silhouettes**, cinematic grade | PARTIAL |
| Graphics | Dense market crowds with merchandise | PARTIAL: PERF60 crowd tiers |
| Systems | Burning buildings / arson | **MISSING** |
| Animation | Army march, banner cloth | PARTIAL: banner props static |

### V20 `6ddabdac`: Bellwright (itsmephiz, 56 s).
Scenes: meat on a rack, a sword fight, an overthrow-the-crown story, a village overview, sunset, chainmail soldiers, wooden stake defences, crossbows on walls, butchering a chicken, recruiting/training villagers, liberating villages, a fog castle with siege engines, a tall statue, a man carrying a pig carcass.
| Area | Feature | RA |
|---|---|---|
| Animation | Carry a carcass / heavy sack on the shoulder, butcher at a table | **MISSING** (carry) / PARTIAL (butcher) |
| Systems | Liberate villages from an oppressive crown, then recruit there | PARTIAL: raids/lordship. **Region liberation loop MISSING** |
| Buildings | Stake palisade defences, wooden walls with crossbowmen | PARTIAL |

---

## 2. Consolidated gap matrix (ranked by player impact)

Impact counts how many videos show the feature and how central it is to RA's vision (survival + NPCs + kingdom).

| # | Gap | Seen in | RA now | Impact | Area |
|---|---|---|---|---|---|
| 1 | **Look/grade gap**: photoreal-leaning materials, fog density, per-biome LUT grading, atmospheric perspective at distance | 3,5,9,13,14,16,18,19 | PARTIAL (stylised, flat aerials) | Very high | Graphics |
| 2 | **Settler job assignment** (villagers work stations/fields, gather, smith) | 4,5,10,13,16,20 | MISSING | Very high | Systems |
| 3 | **Combat fidelity**: directional guards, paired grapples/executions, hit reactions with physical blend, blood decals | 3,7,8,9,11,17 | PARTIAL | Very high | Anim/Combat |
| 4 | **Seasons**: snow cover on roofs/ground, autumn foliage, crop cycle | 5,6,10,13,16 | MISSING | High | Graphics/Systems |
| 5 | **Siege warfare** (ladders, rams, towers, trebuchets, burning) | 2,3,7,15,17,19,20 | MISSING (tactical) | High | Systems |
| 6 | **Town ambience life**: tavern eating/drinking, chimney smoke, windmills turning, market haggling | 4,5,10,13,19 | PARTIAL | High | Anim/World |
| 7 | **Water**: ocean waves + foam, lake shore depth tint, caustics | 1,6,9,15 | PARTIAL | High | Graphics |
| 8 | **Wall/plot drawing** (spline walls, palisades, burgage plots) + blueprint presets | 1,15 | MISSING | Medium-high | Building |
| 9 | **Carry bodies/carcasses/sacks** | 5,20 | MISSING | Medium | Anim |
| 10 | **Fire spread / burning buildings / smoke columns** | 2,3,15,19 | MISSING | Medium | VFX/Systems |
| 11 | **Boats** (rowing, sailing, docks) | 1,6 | MISSING | Medium | Systems |
| 12 | **Marriage/children/heir** (bloodline) | 10,12 | Stub | Medium | Systems |
| 13 | **NPC facial expression + lip movement** in dialogue | 4,10,13,14 | MISSING (villagers) | Medium | Anim |
| 14 | **Caravans** moving between towns | 12,18 | MISSING | Medium | Systems |
| 15 | **Strategic/RTS camera over your settlement** | 15 | MISSING | Medium | Camera |
| 16 | Radial build/action menu | 10 | PARTIAL | Low-medium | UI |
| 17 | Disease/plague | 3,4 | MISSING | Low-medium | Systems |
| 18 | Weapon mastery ranks, damage numbers | 7,14,17 | PARTIAL | Low | Systems |
| 19 | Alarm bell rally | 4 | MISSING | Low | Systems |
| 20 | Tournaments | 15 | Stub | Low | Systems |
| — | First-person mode | 7,10,13 | MISSING by design | (skip) | — |
| — | Co-op/MMO | 3,10,14,18 | out of scope | (skip) | — |

---

## 3. High-end graphics tier plan (Godot 4.6 Forward+)

### 3.1 Honest verdict
Godot 4.6 can reach a **"late UE4 / Bellwright / Medieval Dynasty" look** on high-end PCs: soft GI, volumetric fog, SSR, photoreal PBR, a good grade. It **cannot match UE5 Blight/Chrono Odyssey 1:1**:
- **No Nanite.** There's no virtualised micro-geometry. Closest options: authored LOD chains plus Godot's automatic mesh LOD (`lod_threshold`), HLOD/impostors (`core/impostor_baker.gd` already exists), and normal/parallax detail in place of geometry.
- **No Lumen.** SDFGI is the closest dynamic GI, but it is coarser, leaks light in thin interiors and has no screen-trace refinement. Mitigate with SSIL on top, VoxelGI or baked LightmapGI in interiors and dungeons, and authored fill lights.
- **No virtual shadow maps.** Use 4-split PSSM 4096–8192 plus contact shadows (`shaders/contact_shadow.gdshader`).
- **No hardware ray tracing and no DLSS.** FSR1/FSR2/TAA only. **FSR2 must stay off while Terrain3D is 1.0.2** (crash). Use FSR1 + TAA until Terrain3D 1.1 ships.
- **No built-in tessellation or displacement.** Use parallax occlusion (`heightmap_enabled` + deep parallax in StandardMaterial3D) on ground, cobble and walls, and real mesh rocks/debris.
- **No volumetric clouds.** Sky3D gives 2D/procedural clouds. A raymarched cloud shader is possible on ULTRA (~1–2 ms).
- **Strand hair and cloth simulation are not available.** Use hair cards with alpha-to-coverage plus `SpringBoneSimulator3D` (4.4+) for capes, tabards and hair. Cloth by spring bones only.
The UE5 look is mostly **art direction**: fog, grade, material density and lighting placement. That part is fully achievable. The biggest single upgrade is replacing the toon/washed terrain and grade with a photoreal material set and a per-biome atmosphere profile.

### 3.2 Feature decisions
| Feature | Choice | Notes |
|---|---|---|
| Outdoor GI | SDFGI (HIGH/ULTRA), off on LOW/MED with ambient + SSAO | already in `quality.gd`. Tune `sdfgi_energy`, `use_occlusion`, bounce feedback; set `sdfgi_y_scale` 75% for terrain |
| Interiors / dungeons | **LightmapGI bake** for static dungeon/hall interiors (instanced scenes), VoxelGI only for small hero rooms on ULTRA | towns are procedural, so no bakes there; dungeon prefabs can bake |
| SSIL | ULTRA (+HIGH at half res) | ~0.8–1.5 ms |
| SSAO | MED+ | have |
| SSR | HIGH+ | have; add rough-water fallback via reflection probes |
| Volumetric fog | MED+ (lower res), HIGH/ULTRA full; **per-biome fog profiles** (marsh dense teal, forest god rays, mountain thin) | `vfog_size` already tiered. Add `FogVolume`s in marsh/ruins for local density |
| Light shafts | volumetric fog + directional light `volumetric_fog_energy`; screen-space godray shader for LOW/MED | |
| AA / upscaling | LOW: FSR1 0.75 + FXAA; MED/HIGH: FSR1 + TAA; ULTRA: native + TAA (FSR2 after Terrain3D 1.1) | **fix quality.gd fsr2 rows now** |
| Grade | ACES tonemap + auto exposure + **3D LUT per biome/time** (`Environment.adjustment_color_correction` takes a 3D texture) | LUTs authored in DaVinci Resolve (free) or Krita |
| DoF / bloom | Camera attributes: DoF for dialogue, photo mode and cinematics only; glow on all PC tiers | |
| Film grain, vignette, chromatic aberration | one cheap post shader (CompositorEffect) on HIGH+ | ~0.2 ms |
| PBR textures | Poly Haven / ambientCG CC0, **4k on ULTRA, 2k on HIGH, 1k on LOW** via import variants or `mobile_texture_limit` | already started |
| Terrain | Terrain3D with 8–12 photoreal layers (grass, dirt, mud, cobble, rock, sand, snow, forest floor, gravel), height-blend, macro variation, world-space detail normal | biggest look win |
| POM | ground cobbles, castle walls, roads on HIGH+ (`heightmap_deep_parallax`) | ~0.3–0.6 ms |
| Foliage | photoreal grass cards + wind (`grass.gdshader` rework), SpeedTree-like trees from CC0 sources, two-sided translucency, distance impostors (have) | |
| Water | new water shader: depth-tinted absorption, shore foam, flow maps for rivers, Gerstner waves for coast/lake, screen-space refraction, caustics projector | MED+ |
| Snow / wet | global `wetness` and `snow_cover` shader params (top-facing normal mask), driven by weather/season | |
| Characters | skin SSS (`subsurf_scatter` on HIGH+), anisotropic metal for plate, hair cards, spring-bone capes | |
| Decals | persistent blood, mud, scorch decals, pooled (Decal nodes, cap per tier) | |
| Clouds | Sky3D on all tiers; raymarched volumetric cloud sky shader on ULTRA (optional) | |
| Particles | GPU particles for smoke columns, embers, chimney smoke; Effekseer for combat VFX | |

### 3.3 Tier table (target 60 fps; costs are estimates on an RTX 4070 laptop at 1440p, iGPU at 1080p)
| Setting | iGPU-low (PC_LOW) | mid (PC_MED, GTX 1660/RX 6600) | high (PC_HIGH, RTX 4070L 1440p) | ultra (PC_ULTRA, 4080+) | est. cost at HIGH |
|---|---|---|---|---|---|
| Render scale / AA | 0.67–0.75 FSR1 + FXAA | 0.77 FSR1 + TAA | 0.77 FSR1 + TAA (FSR2 later) | 1.0 TAA | — |
| Shadows | 2 splits 2048, 60–90 m | 4 splits 4096, 140 m | 4 splits 4096, 220 m + contact | 8192, 300 m, soft 4 | 2–3 ms |
| GI | none (ambient + light probes) | none / SSIL half | SDFGI 4 cascades | SDFGI 6 + SSIL full | 2–4 ms |
| Interiors | baked lightmaps (cheap everywhere) | lightmaps | lightmaps + SDFGI | + VoxelGI hero rooms | 0–1 ms |
| AO | off | SSAO half | SSAO full | SSAO + SSIL | 0.8 ms |
| Fog | depth/height fog only | vol fog 96×64 | 128×96 + FogVolumes | 160×128 | 1–1.5 ms |
| Reflections | probes | probes + water SSR 16 | SSR 48 | SSR 64 | 1 ms |
| Textures | 1k | 2k | 2k (4k hero) | 4k | VRAM |
| POM | off | off | ground/walls | everything | 0.5 ms |
| Grass | 30% density, 40 m | 60%, 70 m | 100%, 100 m | 130%, 140 m | 1–2 ms |
| Post | grade LUT + glow | + DoF in cutscenes | + grain/vignette | + volumetric clouds | 0.3 ms |
| Water | flat tint | Gerstner light | full shader + refraction | + caustics | 0.5 ms |
| NPC full bodies | 8 | 10 | 14 | 18 | (PERF60) |
Total HIGH budget fits 16.7 ms only if the PERF60 script work lands (scripts ≤ 9 ms). Graphics adds about 8–11 ms of GPU time at HIGH.

---

## 4. Animation plan (everything seen that RA lacks)

Sources, in order of preference: the existing **golden set** (`scripts/actors/golden_set.gd`, `ANIM_AAA_BRIEF.md`); **Mixamo** (free, needs an Adobe account, owner); **Meshy text-to-motion** (credits, owner OK needed); **Rokoko Video** (free tier, video-to-mocap, account); **Cascadeur** (cleanup and physics fixes, free tier ≤ 300 frames per export for non-commercial use, Indie paid; see tools). Retarget everything to the project humanoid via Godot's BoneMap.

| Need | Seen | Mixamo clip names (search exactly) | Meshy text-to-motion prompt | Cleanup |
|---|---|---|---|---|
| Carry body over shoulder: pick up, walk, drop | 5,20 | "Picking Up Object", "Carrying" (carry walk), "Put Down" | "a man lifts a limp body onto his right shoulder and walks forward slowly, heavy load" | Cascadeur: fix hand contact, two-bone IK on carried ragdoll |
| Carry sack/carcass | 20 | "Box Walk Carry", "Lifting" | "medieval peasant carries a heavy sack on his shoulder, slow walk" | — |
| Eat / drink at table, tankard toast | 4,10 | "Sitting Drinking", "Sitting Eating"? (closest "Sitting Talking", "Sitting Idle"); "Drinking" (standing) | "seated man drinks from a large tankard, then sets it down and laughs" | prop sockets for tankard/bowl |
| Tavern banter gestures | 4,19 | "Talking", "Arguing", "Laughing", "Sitting Laughing" | — | — |
| Rowing | 1 | "Rowing"? (not in Mixamo; use Meshy) | "sitting man rows a boat with two oars, steady rhythm loop" | Cascadeur loop |
| Forging at an anvil | 18 | "Hammering" | "blacksmith strikes glowing metal on an anvil with a hammer, loop" | prop + spark VFX event |
| Butchering | 20 | "Chopping" (closest) | "butcher cuts meat on a wooden table with a cleaver, loop" | — |
| Paired grapple / lift-slam / shove / kick | 3,8,9 | "Kicking", "Shoving", "Standing Melee Kick" (attacker); "Hit Reaction", "Falling Back Death" (victim) | "knight grabs opponent by the collar and throws him to the ground" + victim pair | **Rokoko Video** of two people from reference, or Cascadeur paired authoring; sync via AnimationPlayer markers |
| Executions (sword thrust kill, pommel strike) | 3,9,11 | "Sword And Shield Kill", "Stabbing", "Great Sword Kill" | "knight stabs a kneeling enemy through the chest with a longsword, then pulls the blade out" | paired victim clip |
| Historical fencing guards + transitions (ox/plough/roof/fool), half-sword, bind | 8 | "Great Sword Idle", "Great Sword Slash", "Great Sword Blocking", "Great Sword Casting"(skip) | "longsword fighter shifts from high guard to low guard with a step, HEMA" ×4 | Cascadeur |
| Directional attacks L/R/overhead/thrust for each weapon | 7,11,17 | "Sword And Shield Slash" ×3, "Great Sword High Spin Attack", "Standing Melee Attack Horizontal", "Standing Melee Attack Downward" | — | windup/release markers |
| Riposte / counter / feint | 7,17 | "Sword And Shield Block", "Counterstrike" (Great Sword pack) | "fighter parries then immediately counterattacks with a fast slash" | — |
| Shield bash, shield wall brace | 2,5,16 | "Shield Block", "Sword And Shield Impact", "Shield Bash"? | "soldier braces shield in a wall formation, crouched, spear over shield" | — |
| Physical hit reactions | 3,9 | — (procedural) | — | Godot `PhysicalBoneSimulator3D` partial-body blend on hit |
| Climbing siege ladder under attack | 2 | "Climbing Ladder" (have) + "Climbing To Top" | — | — |
| Push battering ram (group) | 7 | "Pushing", "Push Start" | "soldiers push a heavy siege ram forward, loop" | — |
| Mounted melee (swing, couched lance) | 12 | (no Mixamo horse rider) | "rider on horseback swings a sword to the right side" | Cascadeur; rider-on-horse IK |
| Pet dog follow, sit, sniff | 1 | — | Quaternius CC0 animated dog (has follow/sit) | — |
| Windmill sails, banners, capes | 5,19 | — | — | shader/vertex anim; SpringBone for capes |
| NPC facial: blink, talk visemes, emotions | 4,10,13,14 | — | — | ARKit-style blendshapes on NPC heads (MetaHuman not usable). Rhubarb Lip Sync (MIT) for visemes from VO |
| Alarm bell ring | 4 | "Pulling Rope"? | "man pulls a bell rope repeatedly" | — |
| Archery draw/hold/release polish | 5,10,13 | "Standing Draw Arrow", "Standing Aim Overdraw", "Standing Aim Recoil" | — | have partially |
| Crossbow reload (stirrup) | 13,20 | — | "crossbowman reloads a crossbow with a foot stirrup and pulls the string back" | — |

Pipeline: Mixamo FBX (without skin) → Blender (Rokoko Studio Live add-on or Auto-Rig Pro retarget, or Godot BoneMap directly) → Cascadeur for paired/contact fixes → GLB → golden-set validation (`docs/qa/anim_qa_report.md` tooling).

---

## 5. External tools list
| Tool | Purpose | Licence / cost | Owner account? | Download size |
|---|---|---|---|---|
| **Blender 4.x** | DCC, retarget, LOD, impostors, GLB export | GPL, free | no | ~350 MB |
| **Cascadeur** | animation cleanup, physics-assisted keys, paired anims | Free tier: non-commercial, export limits. **Indie ~$12/mo (commercial OK, revenue cap) — PAID for shipping** | yes | ~1 GB |
| **Rokoko Video** | video-to-mocap from phone/reference video | free tier (limited exports), Plus paid | yes | web |
| **DeepMotion Animate 3D** | video-to-mocap, multi-person (paired grapples) | free ~60 s/mo; paid tiers | yes | web |
| **Mixamo** | stock humanoid clips | free, royalty-free in games | yes (Adobe ID) | web |
| **Meshy** | text-to-3D props, text-to-motion | credits (owner's plan); **do not spend without OK** | yes | web |
| **Material Maker** | node-based procedural PBR (Substance alternative) | MIT, free | no | ~80 MB |
| **ArmorPaint** | 3D texture painting | free source / ~€19 binary (**paid binary**) | no | ~100 MB |
| **Poly Haven** | CC0 textures, HDRIs, models | CC0 | no | per asset (2k ≈ 20–60 MB/set) |
| **ambientCG** | CC0 PBR materials | CC0 | no | per asset |
| **Quixel Megascans via Fab** | photoscans | **Fab "Standard" licence: free Megascans for use in any engine, but not CC0**; check per-asset licence. Redistributing raw files is not allowed | yes (Epic) | large (4k ~200 MB/asset) |
| **KayKit / Quaternius / Kenney** | CC0 low-poly packs, animated animals (dog/horse/sheep) | CC0 | no | 10–200 MB |
| **Gaea 2** | terrain erosion heightmaps for Terrain3D | Community edition free (non-commercial, 1k export cap); **Indie/Pro paid for commercial** | yes | ~500 MB |
| **World Machine** | terrain heightmaps | Basic free (non-commercial, 513px), **Indie paid** | yes | ~200 MB |
| **Instant Terra / free alternative: Blender + A.N.T. Landscape / "TerrainGen" (open)** | open terrain | free | no | — |
| **DaVinci Resolve** | authoring the 3D LUT grade (.cube → Godot 3D texture) | free | yes (registration) | ~3 GB |
| **Rhubarb Lip Sync** | visemes from voice audio | MIT | no | ~20 MB |
| **Godot addons** (already in repo): Terrain3D (MIT), Sky3D (MIT), proton_scatter (MIT), LimboAI (MIT), phantom_camera (MIT), Effekseer (MIT), road-generator (MIT) | | | | |
| **Godot addons to add**: *Waterways* (river flow-map tool, MIT; 4.x port check), *Godot-Ocean / Boujie Water Shader* (MIT/CC0), *SpatialGardener* (MIT, foliage painting), *GodotSteam* later | | MIT | no | small |
| **AMD FSR / TAA** | built into Godot | free | no | — |
| **Blender add-ons**: Rokoko Studio Live (free, retarget), Auto-Rig Pro (**paid ~$40**), Simple Bake (paid), Botaniq/Grassblade (paid) — prefer free *Sapling Tree Gen* (bundled) and *Tree-It* (free, Windows) | | mixed; flagged | | |
Paid items, flagged for an owner decision: Cascadeur Indie, ArmorPaint binary, Gaea/World Machine commercial, Auto-Rig Pro, Fab licence review.

---

## 6. Implementation plan (phased work packages)

Effort: S ≤ 1 day, M 2–4 days, L 1–2 weeks (one agent). Perf numbers are at PC_HIGH.

### Phase G: graphics (look-dev lane, owner's GPU for verification)
| WP | Work | Files | Effort | Depends | Perf per tier |
|---|---|---|---|---|---|
| **G0** | **Switch fsr2 → FSR1 + TAA on PC_MED/HIGH/ULTRA (Terrain3D 1.0.2 crash)** | `scripts/core/quality.gd` PC rows, `settings_screen.gd` AA choice 3 | S | — | ±0 |
| G1 | Photoreal terrain material set (10 Terrain3D layers from Poly Haven/ambientCG, height-blend, macro variation, detail normal); replace blob paint with slope/height/moisture rules | `shaders/terrain3d_ground.gdshader`, Terrain3D assets, `WorldGen.color_at` | L | owner decision D1 (style) | +0.3 ms all |
| G2 | Atmosphere profiles per biome and time: fog density/colour, vol-fog albedo, sun energy, 3D LUT, exposure; marsh/ruin FogVolumes | new `scripts/world/atmosphere_profiles.gd`, `data/atmosphere/*.tres`, `main.gd` env | M | G0 | MED +0.5, HIGH +1 ms |
| G3 | Post stack: ACES + auto exposure + LUT + grain/vignette CompositorEffect, cinematic DoF in dialogue | `scripts/core/main.gd`, new `shaders/post_film.gdshader` | M | G2 | +0.3 ms |
| G4 | Water shader v2 (depth absorption, foam, flow map, Gerstner waves, refraction, caustics on ULTRA) | `world/water_streamer.gd`, new `shaders/water_v2.gdshader` | L | — | +0.5 ms |
| G5 | Global snow-cover/wetness shader params (roofs, ground, rocks) driven by weather and season | `weather.gd`, shared `shaders/environment/surface_weather.gdshaderinc` | M | G1 | +0.1 ms |
| G6 | Interior LightmapGI bakes for dungeon/hall prefabs; window glow emissive + spill lights in towns at night | dungeon scenes, `interiors/*` | M | — | −GI cost indoors |
| G7 | Foliage v2: photoreal grass/flower cards, tree translucency, denser meadows per tier | `shaders/grass.gdshader`, `tree_wind.gdshader`, scatter presets | L | G1 | +1 ms HIGH |
| G8 | Persistent decals: blood pools, scorch, mud (pooled, tier-capped) | `vfx/ground_decals.gd`, `combat/hit_resolver.gd` hook | S | — | +0.1 ms |
| G9 | Smoke/fire: chimney smoke in towns, smoke columns, building fire states | `vfx/*`, `world/ambient_fx.gd` | M | — | +0.3 ms |
| G10 | Characters: skin SSS, anisotropic plate, spring-bone capes/tabards for NPCs (near tier only) | `actors/hero_outfit.gd`, NPC materials | M | — | +0.5 ms |
| G11 | POM on cobble roads and castle walls (HIGH+) | town materials | S | G1 | +0.4 ms |

### Phase A: animation (a93 / animation lane)
| WP | Work | Effort | Depends |
|---|---|---|---|
| A1 | Directional melee: 3-way guard input + UI indicator, L/R/overhead/thrust sets, riposte/feint | L | Mixamo clips (owner account) |
| A2 | Paired animations framework (attacker/victim sync, alignment warp) + 4 pairs: execution stab, lift-slam, shove, kick | L | Rokoko/DeepMotion or Cascadeur |
| A3 | Physical hit reactions (PhysicalBoneSimulator3D partial blend) | M | — |
| A4 | Carry system: bodies, carcasses, sacks (IK hands, slower locomotion) | M | A clips |
| A5 | Tavern/market life clips: seated eat/drink, toast, laugh, haggle, forge, butcher | M | Mixamo + Meshy |
| A6 | NPC facial: blink, emotion blendshapes, Rhubarb visemes in dialogue | L | head meshes with blendshapes (owner decision D4) |
| A7 | Mounted melee, rowing, crossbow stirrup reload | M | Meshy motion credits |

### Phase S: systems (realm / sim lane)
| WP | Work | Files | Effort |
|---|---|---|---|
| S1 | **Settler job assignment** (stations, fields, gathering, smith; UI + daily loop) | `realm/construction.gd`, new `realm/settler_jobs.gd`, Realm UI | L |
| S2 | Seasons (4 seasons over N days → G5 snow, foliage tint, crop cycle, prices) | `world_sim.gd`, `weather.gd`, `farm_work_spot.gd` | L |
| S3 | Siege battles v1: ladders, ram, gate HP, defenders on walls, fire arrows | `army/*`, `realm/armies.gd`, new `army/siege.gd` | L |
| S4 | Spline wall/palisade drawing + blueprint presets | `build/build_mode.gd`, `realm/build_kit.gd` | M |
| S5 | Fire spread on wooden buildings (arson, raids, lightning) | new `world/fire_spread.gd` | M |
| S6 | Boats: rowboat (party), docks, simple sailing on lakes | new `actors/boat.gd` | L |
| S7 | Marriage → children → heir play | `realm/dynasties.gd`, `sim/*` | L |
| S8 | Caravans as moving world entities (trade + ambush) | `realm/*`, PopulationLOD tier | M |
| S9 | Strategic settlement camera (lord view, phantom_camera) | `ui/*` | M |
| S10 | Alarm bell rally, radial action menu, weapon-mastery ranks, damage numbers toggle, disease (later) | various | S–M each |

### Order (player impact first)
1. **G0** (crash risk, today), **G2 + G3** (fastest visible look win), **G1** (terrain).
2. **S1** settler jobs, **A1** directional combat, **G8** blood decals, **A3** hit reactions.
3. **S2 + G5** seasons and snow, **G4** water, **G7** foliage, **A5** town life clips, **G9** smoke.
4. **S3** siege + **A2** paired anims + **S5** fire, **A4** carry, **S4** wall drawing.
5. **S6** boats, **S7** bloodline, **S8** caravans, **A6** facial, **S9**, **S10**.

### Owner decisions needed
- **D1 Art direction:** move from stylised/toon to photoreal-leaning (Bellwright/Medieval Dynasty), or keep stylised with a better grade (like V1 Dungeons & Kingdoms)? Every reference except V1 is photoreal. G1/G7/G10 depend on this.
- **D2** Paid tools: Cascadeur Indie, Gaea commercial, Auto-Rig Pro (all optional; free paths exist).
- **D3** Meshy credits for motion and props (about 190 credits already listed in the gap audit, plus about 100 for motions here).
- **D4** NPC head pipeline for facial blendshapes (regenerate heads, or keep faceless distance NPCs and only do named NPCs).
- **D5** Scope of siege/boats/bloodline for v1 vs later (`READY_V1.md`).
- **D6** Accounts: Mixamo (Adobe), Rokoko, DeepMotion, Epic/Fab.
