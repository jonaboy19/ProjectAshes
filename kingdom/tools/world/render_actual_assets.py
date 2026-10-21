#!/usr/bin/env python3
"""
Renders high-quality photos/screenshots of the ACTUAL 3D models created in Blender:
1. render_enterable_cottage_exterior.png (Open doorway & timber architecture)
2. render_enterable_cottage_interior.png (Fireplace hearth, table, benches, bed)
3. render_orc_evolution_lineup.png (Noble Warlord vs Beast Juggernaut side-by-side)
4. render_races_lineup.png (Dwarf, Elf, Tiefling, Dragonnewt, Wight lineup)
5. render_draco_horse.png (Draco-Horse mount with dragon horns & dorsal spines)
"""

import bpy
import math
import os
from mathutils import Vector

OUT_DIRS = [
    r"C:\Users\Jonna\Documents\ProjectAshes\docs\img\actual_renders",
    r"C:\Users\Jonna\.gemini\antigravity\brain\3da776b7-bb83-47d1-9df4-df5aec1eeb7f\img\actual_renders"
]

ASSETS = {
    "cottage": r"C:\Users\Jonna\Documents\ProjectAshes\kingdom\assets\incoming\buildings\enterable_cottage.glb",
    "noble_ork": r"C:\Users\Jonna\Documents\ProjectAshes\kingdom\assets\incoming\characters\races\race_ork_noble_warlord.glb",
    "beast_ork": r"C:\Users\Jonna\Documents\ProjectAshes\kingdom\assets\incoming\characters\races\race_ork_beast_juggernaut.glb",
    "elf": r"C:\Users\Jonna\Documents\ProjectAshes\kingdom\assets\incoming\characters\races\race_elf.glb",
    "tiefling": r"C:\Users\Jonna\Documents\ProjectAshes\kingdom\assets\incoming\characters\races\race_tiefling.glb",
    "draken": r"C:\Users\Jonna\Documents\ProjectAshes\kingdom\assets\incoming\characters\races\race_draken_dragonnewt.glb",
    "dwarf": r"C:\Users\Jonna\Documents\ProjectAshes\kingdom\assets\incoming\characters\races\race_dwarf.glb",
    "wight": r"C:\Users\Jonna\Documents\ProjectAshes\kingdom\assets\incoming\characters\races\race_undead_wight.glb",
    "draco_horse": r"C:\Users\Jonna\Documents\ProjectAshes\kingdom\assets\incoming\animals\fantasy\horse_draco.glb"
}

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # Configure render settings
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.film_transparent = False

def setup_lighting(ground_y=0.0):
    # World background
    world = bpy.data.worlds.new("World")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.05, 0.06, 0.09, 1.0)
        bg.inputs["Strength"].default_value = 0.8
        
    # Sun light
    sun_data = bpy.data.lights.new(name="Sun", type='SUN')
    sun_data.energy = 2.5
    sun_data.color = (1.0, 0.95, 0.85)
    sun_obj = bpy.data.objects.new("Sun", sun_data)
    bpy.context.collection.objects.link(sun_obj)
    sun_obj.location = (6, -8, 10)
    sun_obj.rotation_euler = (math.radians(45), math.radians(20), math.radians(-30))
    
    # Blue rim light
    rim_data = bpy.data.lights.new(name="Rim", type='POINT')
    rim_data.energy = 800.0
    rim_data.color = (0.2, 0.6, 1.0)
    rim_obj = bpy.data.objects.new("Rim", rim_data)
    bpy.context.collection.objects.link(rim_obj)
    rim_obj.location = (-4, 5, 4)

def setup_camera(loc, rot, fov=45):
    cam_data = bpy.data.cameras.new(name="Camera")
    cam_data.angle = math.radians(fov)
    cam_obj = bpy.data.objects.new("Camera", cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = Vector(loc)
    cam_obj.rotation_euler = tuple(math.radians(r) for r in rot)
    bpy.context.scene.camera = cam_obj
    return cam_obj

def save_render(filename):
    for d in OUT_DIRS:
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, filename)
        bpy.context.scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print(f"[OK] Rendered: {path}")

# --- Render 1: Enterable Cottage Exterior ---
def render_cottage_exterior():
    reset_scene()
    setup_lighting()
    bpy.ops.import_scene.gltf(filepath=ASSETS["cottage"])
    # Front-quarter camera showing open doorway
    setup_camera(loc=(4.5, 7.5, 3.2), rot=(72, 0, 150), fov=50)
    save_render("render_enterable_cottage_exterior.png")

# --- Render 2: Enterable Cottage Interior ---
def render_cottage_interior():
    reset_scene()
    setup_lighting()
    bpy.ops.import_scene.gltf(filepath=ASSETS["cottage"])
    # Inside camera looking at stone hearth fireplace and table
    setup_camera(loc=(0.0, 2.2, 1.5), rot=(82, 0, 180), fov=65)
    save_render("render_enterable_cottage_interior.png")

# --- Render 3: Orc Evolution Dual Lineup ---
def render_orc_lineup():
    reset_scene()
    setup_lighting()
    
    # Import Noble Warlord
    bpy.ops.import_scene.gltf(filepath=ASSETS["noble_ork"])
    noble = bpy.context.selected_objects
    for o in noble:
        o.location.x -= 1.3
        
    # Import Beast Juggernaut
    bpy.ops.import_scene.gltf(filepath=ASSETS["beast_ork"])
    beast = bpy.context.selected_objects
    for o in beast:
        o.location.x += 1.3
        
    setup_camera(loc=(0.0, -5.2, 1.6), rot=(85, 0, 0), fov=48)
    save_render("render_orc_evolution_lineup.png")

# --- Render 4: Races Multi-Lineup ---
def render_races_lineup():
    reset_scene()
    setup_lighting()
    
    races = [
        ("dwarf", -3.2),
        ("elf", -1.6),
        ("tiefling", 0.0),
        ("draken", 1.6),
        ("wight", 3.2)
    ]
    
    for key, x_pos in races:
        bpy.ops.import_scene.gltf(filepath=ASSETS[key])
        objs = bpy.context.selected_objects
        for o in objs:
            o.location.x += x_pos
            
    setup_camera(loc=(0.0, -7.5, 1.7), rot=(85, 0, 0), fov=52)
    save_render("render_races_lineup.png")

# --- Render 5: Draco Horse Mount ---
def render_draco_horse():
    reset_scene()
    setup_lighting()
    bpy.ops.import_scene.gltf(filepath=ASSETS["draco_horse"])
    setup_camera(loc=(2.8, -3.2, 1.8), rot=(72, 0, 42), fov=45)
    save_render("render_draco_horse.png")

def main():
    print("Rendering Actual 3D Assets...")
    render_cottage_exterior()
    render_cottage_interior()
    render_orc_lineup()
    render_races_lineup()
    render_draco_horse()
    print("[ALL DONE] All actual 3D asset renders generated successfully.")

if __name__ == "__main__":
    main()
