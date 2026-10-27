# Rising Ashes — Art direction decision (2026-10-27)

Owner delegated the choice ("do what you think is best for the game"). Decision: **grounded stylised-realism.**

## What it means
- Realistic proportions, materials and lighting logic (PBR, real-world scale, believable architecture and clothing) — the reference games' grounded medieval feel (KCD, Bellwright, Medieval Dynasty, Manor Lords).
- Slightly stylised shapes and painterly colour: cleaner silhouettes, curated palettes per region, soft hand-tuned grading — not photogrammetry, not cartoon.
- Fantasy reads through landmarks, magic light, Rift effects and regional colour, not through toy-like proportions.

## Why
1. **Min-spec (regular PC / iGPU):** full photorealism needs dense geometry, 4K textures and heavy GI that iGPUs can't run; stylised-realism stays readable at low settings and scales up on high-end with SDFGI, volumetric fog, SSR and denser foliage.
2. **Our assets:** Quaternius UAL characters, KayKit/Kenney props, Meshy NPCs and the Blender house kits are stylised-leaning; this direction lets us keep them (with material upgrades) instead of replacing everything.
3. **Godot 4.6 limits:** no Nanite/Lumen equivalents; art direction (fog, grade, light placement, material density) is where the "Blight look" really comes from and is fully achievable.
4. **Meshy:** consistent output is easier with a stated style prompt than with photoreal matching.
5. **Ageing:** stylised-realism ages better and hides small animation/clipping imperfections less harshly than photoreal.

## Rules for every worker
- PBR materials with Poly Haven / ambientCG CC0 textures, tinted to the regional palette; texture budget 1K–2K (4K only for hero assets on high/ultra).
- Per-biome fog + colour grade profiles (top visual win from the video analysis).
- Human proportions realistic; faces understated, not anime; clothing layered and worn.
- Meshy prompt suffix: "medieval, grounded stylised realism, realistic proportions, hand-painted PBR textures, muted natural palette".
- Quality tiers: iGPU-low (baked/cheap lighting, no SDFGI, short draw distance) → mid → high (SDFGI, volumetric fog, SSR) → ultra (denser foliage, higher-res textures, more shadow cascades).
