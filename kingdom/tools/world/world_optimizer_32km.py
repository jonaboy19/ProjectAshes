#!/usr/bin/env python3
"""
32km World Region Optimizer & Memory Budgeter for Project Ashes (Godot 4.6 / Jolt Physics)
Target Hardware: 8GB RAM PC / 4GB VRAM GPU (and higher)
Architecture:
- 32,768 m x 32,768 m continent of Valencious
- 512m x 512m Macro-Sectors (64 x 64 grid = 4,096 total sectors)
- 3x3 Active Sector Window (1,536m x 1,536m active memory footprint)
- WorkerThreadPool async chunk eviction and generation
- Octahedral Billboard Impostors for far horizons (>350m)
"""

import json
import os
import math

WORLD_SIZE_METERS = 32768
SECTOR_SIZE_METERS = 512
GRID_COUNT = WORLD_SIZE_METERS // SECTOR_SIZE_METERS # 64x64

RAM_BUDGET_MB = {
    "total_system_ram_mb": 8192,
    "os_and_background_mb": 3200,
    "godot_max_allowable_mb": 4200,
    "target_safety_margin_mb": 792,
    "breakdown": {
        "engine_core_and_jolt_mb": 450,
        "active_macro_sectors_9x_mb": 950, # 9 sectors x ~105 MB
        "high_poly_characters_visible_mb": 320, # 50-100 characters
        "texture_cache_streamed_mb": 1100, # VRAM / RAM mirrored staging
        "vfx_and_audio_pools_mb": 280,
        "limbo_ai_and_sim_actors_mb": 350, # 15,000 represented in data, 300 active in LimboAI
        "impostor_buffer_mb": 120, # MultiMesh GPU buffers for 50,000 trees/rocks
        "headroom_buffer_mb": 630
    }
}

BIOMES = [
    {"id": "rural_plains", "name": "Rural Plains & Farmlands", "density_trees": 120, "density_buildings": 35},
    {"id": "river_valleys", "name": "River Valleys & Bridges", "density_trees": 240, "density_buildings": 20},
    {"id": "hill_regions", "name": "Hill Regions & Vineyards", "density_trees": 180, "density_buildings": 15},
    {"id": "dense_forests", "name": "Ancient Sacred Forests (Redwoods/Banyans)", "density_trees": 650, "density_buildings": 10},
    {"id": "northern_mountains", "name": "Northern Snowy Peaks & Monasteries", "density_trees": 80, "density_buildings": 12},
    {"id": "swamps_marshes", "name": "Swamps & Marshes", "density_trees": 210, "density_buildings": 8},
    {"id": "borderlands", "name": "Contested Borderlands & Outposts", "density_trees": 90, "density_buildings": 25},
    {"id": "coastal_regions", "name": "Coastal Ports & Fishing Villages", "density_trees": 110, "density_buildings": 40},
    {"id": "rift_zones", "name": "Rift Zones (Dark Energy & Anomalies)", "density_trees": 30, "density_buildings": 5},
    {"id": "market_towns", "name": "Fortified Market Towns (Kingsreach etc)", "density_trees": 40, "density_buildings": 180}
]

def generate_sector_grid():
    sectors = {}
    center = GRID_COUNT // 2 # sector (32, 32) is center origin (0, 0)
    
    for gz in range(GRID_COUNT):
        for gx in range(GRID_COUNT):
            world_x = (gx - center) * SECTOR_SIZE_METERS
            world_z = (gz - center) * SECTOR_SIZE_METERS
            
            # Simple radial biome assignment matching Valencious map
            dist_from_center = math.hypot(world_x, world_z)
            norm_dist = dist_from_center / (WORLD_SIZE_METERS / 2.0)
            
            if norm_dist < 0.2:
                biome = "market_towns"
            elif world_z < -6000:
                biome = "northern_mountains"
            elif world_x < -7000 and world_z > 2000:
                biome = "swamps_marshes"
            elif world_x > 8000:
                biome = "coastal_regions"
            elif world_z > 8000:
                biome = "dense_forests"
            elif norm_dist > 0.85:
                biome = "borderlands"
            elif abs(world_x) < 3000 and abs(world_z) < 6000:
                biome = "river_valleys"
            else:
                biome = "rural_plains"
                
            key = f"{gx}_{gz}"
            sectors[key] = {
                "sector_coord": [gx, gz],
                "world_origin": [world_x, world_z],
                "biome": biome,
                "has_enterable_buildings": biome in ["market_towns", "rural_plains", "river_valleys", "coastal_regions"],
                "stream_priority": 1 if (abs(gx - center) <= 2 and abs(gz - center) <= 2) else 3
            }
    return sectors

def main():
    sectors = generate_sector_grid()
    
    output_data = {
        "world_name": "Valencious",
        "world_size_meters": WORLD_SIZE_METERS,
        "sector_size_meters": SECTOR_SIZE_METERS,
        "total_sectors": len(sectors),
        "target_spec": {
            "min_ram_gb": 8,
            "min_vram_gb": 4,
            "active_sector_window": "3x3 (1,536m x 1,536m)",
            "octahedral_impostor_distance_m": 350.0,
            "max_concurrent_in_flight_tasks": 2
        },
        "ram_budget_mb": RAM_BUDGET_MB,
        "biomes": BIOMES,
        "sectors": sectors
    }
    
    out_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../data/world")
    os.makedirs(out_dir, exist_ok=True)
    out_file = os.path.join(out_dir, "valencious_32km_sectors.json")
    
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(output_data, f, indent=2)
        
    print(f"[OK] Generated 32km sector configuration ({len(sectors)} sectors) at:")
    print(f"     {out_file}")
    print(f"     Memory Budget: {RAM_BUDGET_MB['godot_max_allowable_mb']} MB (Safe for 8GB RAM PCs)")

if __name__ == "__main__":
    main()
