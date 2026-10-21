# Valencious 32km World, High-Quality Races & Slime Evolution System
**Document for:** Claude, Codex, and Project Ashes Dev Team  
**Branch:** `antigravity/aaa-mocap-animations`  
**Target Hardware:** 8GB RAM PC / 4GB VRAM GPU (and higher) | 60+ FPS Target

---

## 1. Executive Summary & Vision Alignment

In response to the transition from low-poly prototype to **high-fidelity PC Open-World Action RPG**, the world of **Valencious** is expanded to a **32km × 32km region streaming architecture**, complete with **20 diverse fantasy races**, a **Tensura / Slime-inspired Monster Naming & Evolution System**, **enterable buildings with seamless door transitions**, and **high-poly PBR character models**.

All systems adhere strictly to an **8GB RAM PC runtime memory envelope**, utilizing asynchronous worker thread streaming, GPU multi-mesh impostor horizons, and dynamic interior occlusion culling.

---

## 2. Races of Valencious (Full 20-Race Manifest)

Located in: `kingdom/data/world/races.json`

| Race | Archetype | Lifespan | Magicules | Evolution Chain (Naming & Cultivation) | Unique Racial Traits |
| :--- | :--- | :---: | :---: | :--- | :--- |
| **Human** | Civilised | 70 / 110 | 0.45 | Human → Awakened Human → Human Saint | Adaptable, fast learner, wide affinity spread. Primordial clay for bloodline pacts. |
| **Elf (Veyl)** | Civilised | 450 / 900 | 0.85 | Elf → High Elf → Star Elf (Aeldir) | *Rootsong* nature communion, bow mastery, gravity lightness. |
| **Dark Elf (Umbral Veyl)** | Civilised | 450 / 900 | 0.88 | Dark Elf → Shadow Weaver → Abyssal Archon | Subterranean stealth, shadow-meld, superior night sight, void whispers. |
| **Dwarf (Durrow)** | Civilised | 240 / 350 | 0.50 | Dwarf → Deepforged Dwarf → Rune Titan Dwarf | Master craftsmanship, iron skin, forge breath, tectonic strike. |
| **Beastkin** | Civilised | 65 / 100 | 0.40 | Beastkin → Greater Beastkin → Primal Sovereign | Lupine, feline, ursine, vulpid, falconkin lineages; feral haste, totem roar. |
| **Half-Breed** | Civilised | 120 / 250 | 0.60 | Half-Breed → Harmonized Ascendant | Hybrid vigor, dual affinities (half-elf, half-orc, wyrmvein). |
| **Aetherborn** | Civilised | 200 / 500 | 0.98 | Aetherborn → Aether Archon → Cosmic Conduit | Mana conductive veins, crystalline hair, chantless spellcasting, levitation. |
| **Draken / Dragonnewt** | Civilised | 350 / 1500 | 0.95 | Lizardfolk → Dragonnewt → Wyrmblooded → Dragon Sovereign | Draconic breath, wing gliding, draconic scales, cataclysmic roar. |
| **Ork (Urrokai)** | Civilised / Monster | 55 / 90 | 0.35 | Ork → High Ork → Ork Warlord → Ork Sovereign | Great physical strength, *Bloodroar*, devouring hunger, quake slam. |
| **Halfling** | Civilised | 110 / 160 | 0.40 | Halfling → Fortune Seeker | Small stature, culinary genius, uncanny luck, evasion mastery. |
| **Gnome** | Civilised | 300 / 450 | 0.70 | Gnome → Clockwork Savant | Clockwork automaton summons, alchemy, esoteric mechanical engineering. |
| **Tiefling (Netherborn)** | Civilised | 85 / 140 | 0.75 | Tiefling → Hellion Blade → Arch-Infernal Sovereign | Hellfire burst, horns & spade tail, nether step, flame immunity. |
| **Aasimar** | Civilised | 130 / 200 | 0.90 | Aasimar → Radiant Seraph → Celestial Paragon | Celestial radiance, luminous wings, radiant healing, holy smite aegis. |
| **Lizardfolk** | Monster | 50 / 80 | 0.30 | Lizardfolk → **Dragonnewt** (via Naming) | Swamp swimmer, thick scales, primal tracking, ascends upon naming. |
| **Serpentkin** | Civilised | 180 / 300 | 0.82 | Serpentkin → Naga Mystic | Hypnotic gaze, venom transmutation, water gliding, silent coiling. |
| **Avian** | Civilised | 70 / 120 | 0.65 | Avian → Storm Falcon Sovereign | Winged aerial flight, supersonic cloud dive, cliff aerie mastery. |
| **Spiritkin** | Civilised | 600 / 9999 | 0.99 | Spiritkin → Elemental Archon | Translucent ethereal body, physical damage immunity, leyline phase. |
| **Giant (Titan)** | Civilised / Monster | 600 / 1500 | 0.70 | Giant → Frost/Stone Titan → Mountain Colossus | 4m–7m colossi, boulder throw, shockwave stomp, mountain cleaver. |
| **Intelligent Undead** | Civilised / Monster | Eternal | 0.80 | Skeleton → Wight (via Naming) → Death Knight *or* Elder Lich → Nether Sovereign | No fatigue, bleed/poison immune, soul harvest, conscious intellect. |

---

## 3. Slime / Tensura Monster Naming & Evolution Metaphysics

Located in: `kingdom/scripts/sim/race_evolution_system.gd`

### The Naming Ritual Rules:
1. **Soul Corridor Formation:** When a player/cultivator of level 10+ confers a true name upon an unnamed monster (e.g. Goblin, Lizardman, Skeleton):
   * A portion of the namer's current magicules is permanently consumed or locked into the soul bond.
   * `Magicule Depletion (Coma/Backlash)` triggers if the naming cost exceeds 65% of the namer's max pool.
2. **Biological Metamorphosis:**
   * **Lizardfolk → Dragonnewt:** The slouching reptilian frame transforms into a sleek, noble humanoid warrior with draconic horns, wings, and draconic breath.
   * **Goblin → Hobgoblin:** The small scavenger grows from 1.1m to 1.85m tall, gaining human speech, tool mastery, and muscular refinement.
   * **Skeleton → Wight:** Necrotic bone restores spectral muscle and flesh, regaining sentient speech and combat discipline.
3. **Loyalty & Bond:** Evolved monsters gain 100 loyalty and unlock specialized combat skill trees.

---

## 4. 32km World Streaming Architecture for 8GB RAM PCs

Tool & Partition Spec: `kingdom/tools/world/world_optimizer_32km.py` & `kingdom/data/world/valencious_32km_sectors.json`

### The 8GB RAM Budget Allocation:
```
Total System RAM: 8,192 MB
├── OS & Background Applications: ~3,200 MB
└── Godot 4.6 Engine Envelope: 4,200 MB Max
    ├── Engine Core & Jolt Physics: 450 MB
    ├── Active 3x3 Sectors (1,536m x 1,536m): 950 MB
    ├── High-Poly Visible Characters (50-100): 320 MB
    ├── Streamed Texture Cache (PBR Albedo/Normal/ORM): 1,100 MB
    ├── Audio & Particle Pools: 280 MB
    ├── Virtual Population Sim (15,000 data / 300 LimboAI): 350 MB
    ├── GPU MultiMesh Impostor Buffer (50,000 trees/rocks): 120 MB
    └── Safety Margin Buffer: 630 MB
```

### 3-Tier Distance Hierarchy:
* **Core Detail (0m – 80m):** High-poly meshes (15k–30k tris), full PBR shaders, dynamic shadows, cloth physics, active Jolt physics bodies.
* **Mid-Range Simulation (80m – 350m):** LOD1/LOD2 simplified meshes, simplified raycasts, reduced LimboAI tick rates.
* **Horizon & Far Vistas (350m – 32,768m):** GPU Octahedral billboard impostors. 50,000 distant trees and landmarks render in a single multi-mesh draw call (<120 MB VRAM).
* **Global World Simulation:** 4,096 macro-sectors (512m × 512m each). Sectors beyond 1,536m are purely simulated via background threads as mathematical data (wars, caravan trade, monster ecology).

---

## 5. Enterable Buildings & Seamless Doorways

Scripts & Models:
* `kingdom/scripts/world/enterable_building_manager.gd`
* `kingdom/assets/incoming/buildings/enterable_cottage.glb`
* `kingdom/tools/world/build_enterable_buildings.py`

### Key Features:
1. **Physical Open Doorway (1.3m × 2.4m):** Open doorway frame allowing players to walk straight from the dirt road into the tavern or cottage without loading screens.
2. **Godot Compound Collision (`-col` naming):** Uses Godot's automatic collision importer. Walls, floors, lintels, and hearths have precise convex colliders, leaving the doorway opening completely hollow for collision-free passage.
3. **Dynamic Prop Occlusion Culling:**
   * When >18m from the building, interior clutter (plates, cups, small props) is hidden.
   * When crossing the threshold, interior props enable instantly and the camera dynamically adapts its ceiling collision margin.

---

## 6. High-Poly Rigged Race Models

Exported in: `kingdom/assets/incoming/characters/races/`

| File | Size | Visual & Rigging Specifications |
| :--- | :---: | :--- |
| **`race_elf.glb`** | 15.5 MB | High-poly base, swept pointed elven ears, slender 1.05z frame, PBR fair skin, golden eyes. |
| **`race_dark_elf.glb`** | 816 KB | Pointed ears, obsidian-ash skin, amethyst glowing eyes, night-weave silhouette. |
| **`race_tiefling.glb`** | 821 KB | Dual curved ram horns (weighted to `Head`), segmented prehensile spade tail (weighted to `pelvis`), crimson-slate skin. |
| **`race_draken_dragonnewt.glb`** | 829 KB | Draconic crown horns, dorsal back spines (`spine_02`, `spine_03`), draconic tail, emerald-obsidian scales. |
| **`race_beastkin_lupine.glb`** | 15.5 MB | Pointed furred beast ears on head, bushy wolf tail, amber eyes, feral athletic posture. |
| **`race_dwarf.glb`** | 15.5 MB | Stocky 0.78z / 1.28x proportions, braided beard geometry (weighted to `Head`), weathered bronze skin. |
| **`race_undead_wight.glb`** | 829 KB | Ashen desaturated skin, dual glowing cyan soul emissive eyes (`EyeGlow_L`, `EyeGlow_R`). |

*All race models share the Universal Animation Library (UAL) bone hierarchy and work with all 158 MoCap animations.*

---

## 7. LimboAI Race Behavior Profiles

Located in: `kingdom/data/ai/race_behavior_profiles.json`

Provides behavioral weighting for every race:
* **Combat Doctrines:** Shield phalanx, ranged kiting, aerial dive, stealth ambush, berserk charge.
* **Schedules:** Diurnal (Humans, Halflings), Nocturnal (Dark Elves, Undead), Crepuscular (Beastkin dawn/dusk), Continuous (Dwarves).
* **Hangouts:** Taverns, sacred groves, forge halls, crypt sanctums, high perches.
