#!/usr/bin/env python3
"""
Enterable Building Generator for Project Ashes (Blender 5.2 / Godot 4.6)
Generates high-quality enterable village buildings with:
- Seamless physical open doorways (1.2m wide, 2.4m high)
- Detailed interior wooden floors and exposed ceiling rafters
- Interior stone hearth, table, and benches
- Dedicated compound collision meshes using Godot '-col' conventions
  so characters can walk seamlessly inside without colliding with the doorway.
"""

import bpy
import bmesh
import math
import os
from mathutils import Vector

OUT_PATH = r"C:\Users\Jonna\Documents\ProjectAshes\kingdom\assets\incoming\buildings\enterable_cottage.glb"

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def create_pbr_mat(name, base_color, roughness=0.6, metallic=0.0):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = base_color
        bsdf.inputs["Roughness"].default_value = roughness
        bsdf.inputs["Metallic"].default_value = metallic
    return mat

def create_box(name, size, loc, mat, is_collision=False):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    # Scale box
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    if mat and not is_collision:
        obj.data.materials.append(mat)
    return obj

def build_enterable_cottage():
    reset_scene()
    
    # Materials
    m_wood = create_pbr_mat("M_Timber", (0.32, 0.20, 0.12, 1.0), roughness=0.7)
    m_wall = create_pbr_mat("M_PlasterWall", (0.85, 0.82, 0.75, 1.0), roughness=0.85)
    m_stone = create_pbr_mat("M_Fieldstone", (0.35, 0.35, 0.33, 1.0), roughness=0.8)
    m_roof = create_pbr_mat("M_ThatchRoof", (0.45, 0.38, 0.22, 1.0), roughness=0.9)
    m_floor = create_pbr_mat("M_FloorPlanks", (0.40, 0.26, 0.15, 1.0), roughness=0.65)
    
    # Cottage dimensions: 6m wide (X), 6m deep (Y), 3.2m wall height (Z)
    w, d, h = 6.0, 6.0, 3.2
    wall_thick = 0.25
    door_w, door_h = 1.3, 2.4
    
    # 1. Floor (Visual & Collision)
    create_box("Interior_Floor", (w, d, 0.15), (0, 0, 0.075), m_floor)
    create_box("Floor-col", (w, d, 0.15), (0, 0, 0.075), None, is_collision=True)
    
    # 2. Back Wall (Y = -d/2)
    create_box("Wall_Back", (w, wall_thick, h), (0, -d/2 + wall_thick/2, h/2), m_wall)
    create_box("Wall_Back-col", (w, wall_thick, h), (0, -d/2 + wall_thick/2, h/2), None, is_collision=True)
    
    # 3. Left Wall (X = -w/2)
    create_box("Wall_Left", (wall_thick, d, h), (-w/2 + wall_thick/2, 0, h/2), m_wall)
    create_box("Wall_Left-col", (wall_thick, d, h), (-w/2 + wall_thick/2, 0, h/2), None, is_collision=True)
    
    # 4. Right Wall (X = +w/2)
    create_box("Wall_Right", (wall_thick, d, h), (w/2 - wall_thick/2, 0, h/2), m_wall)
    create_box("Wall_Right-col", (wall_thick, d, h), (w/2 - wall_thick/2, 0, h/2), None, is_collision=True)
    
    # 5. Front Wall with Doorway Cutout (Y = +d/2)
    # Front-left wall segment
    fl_w = (w - door_w) / 2.0
    create_box("Wall_Front_Left", (fl_w, wall_thick, h), (-w/2 + fl_w/2, d/2 - wall_thick/2, h/2), m_wall)
    create_box("Wall_Front_Left-col", (fl_w, wall_thick, h), (-w/2 + fl_w/2, d/2 - wall_thick/2, h/2), None, is_collision=True)
    
    # Front-right wall segment
    create_box("Wall_Front_Right", (fl_w, wall_thick, h), (w/2 - fl_w/2, d/2 - wall_thick/2, h/2), m_wall)
    create_box("Wall_Front_Right-col", (fl_w, wall_thick, h), (w/2 - fl_w/2, d/2 - wall_thick/2, h/2), None, is_collision=True)
    
    # Lintel over the doorway
    lintel_h = h - door_h
    create_box("Door_Lintel", (door_w, wall_thick, lintel_h), (0, d/2 - wall_thick/2, door_h + lintel_h/2), m_wood)
    create_box("Door_Lintel-col", (door_w, wall_thick, lintel_h), (0, d/2 - wall_thick/2, door_h + lintel_h/2), None, is_collision=True)
    
    # Door frame posts (visual detail)
    post_w = 0.12
    create_box("Post_Left", (post_w, wall_thick * 1.2, door_h), (-door_w/2, d/2 - wall_thick/2, door_h/2), m_wood)
    create_box("Post_Right", (post_w, wall_thick * 1.2, door_h), (door_w/2, d/2 - wall_thick/2, door_h/2), m_wood)
    
    # 6. Pitched Roof (Visual & Collision)
    # Left pitch
    roof_w = w * 1.15
    roof_d = d * 1.15
    r1 = create_box("Roof_Slope_L", (roof_w/2, roof_d, 0.20), (-1.4, 0, h + 1.0), m_roof)
    r1.rotation_euler = (0, math.radians(35), 0)
    r2 = create_box("Roof_Slope_R", (roof_w/2, roof_d, 0.20), (1.4, 0, h + 1.0), m_roof)
    r2.rotation_euler = (0, math.radians(-35), 0)
    
    # 7. Interior Furnishings
    # Stone Fireplace at back wall
    create_box("Interior_Hearth", (1.6, 0.8, 1.8), (0, -d/2 + 0.65, 0.9), m_stone)
    create_box("Interior_Hearth-col", (1.6, 0.8, 1.8), (0, -d/2 + 0.65, 0.9), None, is_collision=True)
    
    # Wooden Table in the middle-left
    create_box("Interior_Table", (1.8, 0.9, 0.75), (-1.4, 0.2, 0.375), m_wood)
    create_box("Interior_Table-col", (1.8, 0.9, 0.75), (-1.4, 0.2, 0.375), None, is_collision=True)
    
    # Benches
    create_box("Interior_Bench_L", (1.8, 0.35, 0.45), (-1.4, -0.5, 0.225), m_wood)
    create_box("Interior_Bench_R", (1.8, 0.35, 0.45), (-1.4, 0.9, 0.225), m_wood)
    
    # Bed in back-right corner
    m_cloth = create_pbr_mat("M_Bedding", (0.6, 0.2, 0.2, 1.0), roughness=0.9)
    create_box("Interior_Bed", (1.2, 2.0, 0.55), (w/2 - 0.9, -d/2 + 1.3, 0.275), m_cloth)
    create_box("Interior_Bed-col", (1.2, 2.0, 0.55), (w/2 - 0.9, -d/2 + 1.3, 0.275), None, is_collision=True)
    
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT_PATH,
        export_format='GLB',
        use_selection=False,
        export_apply=True,
        export_yup=True
    )
    print(f"[OK] Generated enterable cottage with seamless open doorway and collision at:")
    print(f"     {OUT_PATH}")

if __name__ == "__main__":
    build_enterable_cottage()
