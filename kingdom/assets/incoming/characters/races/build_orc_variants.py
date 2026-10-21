#!/usr/bin/env python3
"""
Generates the dual-evolution Orc models:
1. race_ork_noble_warlord.glb (Refined noble high orc, upright posture, sleek armor)
2. race_ork_beast_juggernaut.glb (Hulking bestial orc juggernaut, colossal tusks, massive frame)
"""

import bpy
import bmesh
import math
import os
from mathutils import Vector

BASE_GLTF = r"C:\Users\Jonna\Documents\ProjectAshes\kingdom\assets\incoming\quaternius\universal-base-characters\Base Characters\Godot - UE\Superhero_Male_FullBody.gltf"
OUT_DIR = r"C:\Users\Jonna\Documents\ProjectAshes\kingdom\assets\incoming\characters\races"

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def import_base():
    bpy.ops.import_scene.gltf(filepath=BASE_GLTF)
    arm = [obj for obj in bpy.data.objects if obj.type == 'ARMATURE'][0]
    meshes = [obj for obj in bpy.data.objects if obj.type == 'MESH']
    return arm, meshes

def create_pbr_mat(name, base_color, metallic=0.0, roughness=0.5):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = base_color
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
    return mat

def attach_to_bone(obj, arm, bone_name):
    mod = obj.modifiers.new(name="Armature", type='ARMATURE')
    mod.object = arm
    vg = obj.vertex_groups.new(name=bone_name)
    vg.add([v.index for v in obj.data.vertices], 1.0, 'REPLACE')
    obj.parent = arm

def add_tusks(arm, size=0.10, tusk_color=(0.85, 0.80, 0.70, 1.0), spread=0.045):
    # Left tusk
    bm_l = bmesh.new()
    bmesh.ops.create_cone(bm_l, cap_ends=True, cap_tris=False, segments=6, radius1=size*0.35, radius2=0.005, depth=size)
    m_l = bpy.data.meshes.new("Tusk_L")
    bm_l.to_mesh(m_l)
    bm_l.free()
    obj_l = bpy.data.objects.new("Tusk_L", m_l)
    bpy.context.collection.objects.link(obj_l)
    obj_l.location = Vector((spread, 0.08, 1.62))
    obj_l.rotation_euler = (math.radians(-40), math.radians(15), 0)
    
    # Right tusk
    bm_r = bmesh.new()
    bmesh.ops.create_cone(bm_r, cap_ends=True, cap_tris=False, segments=6, radius1=size*0.35, radius2=0.005, depth=size)
    m_r = bpy.data.meshes.new("Tusk_R")
    bm_r.to_mesh(m_r)
    bm_r.free()
    obj_r = bpy.data.objects.new("Tusk_R", m_r)
    bpy.context.collection.objects.link(obj_r)
    obj_r.location = Vector((-spread, 0.08, 1.62))
    obj_r.rotation_euler = (math.radians(-40), math.radians(-15), 0)
    
    mat = create_pbr_mat("M_IvoryTusk", tusk_color, roughness=0.3)
    obj_l.data.materials.append(mat)
    obj_r.data.materials.append(mat)
    attach_to_bone(obj_l, arm, "Head")
    attach_to_bone(obj_r, arm, "Head")

def build_noble_warlord():
    reset_scene()
    arm, meshes = import_base()
    # Refined olive skin, upright athletic proportions
    arm.scale = (1.15, 1.15, 1.25)
    skin_mat = create_pbr_mat("M_NobleOrkSkin", (0.35, 0.42, 0.28, 1.0), roughness=0.6)
    for m in meshes:
        if len(m.data.materials) > 0:
            m.data.materials[0] = skin_mat
    add_tusks(arm, size=0.12, spread=0.045)
    
    out_path = os.path.join(OUT_DIR, "race_ork_noble_warlord.glb")
    bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB', export_yup=True)
    print(f"[OK] Exported noble warlord orc to: {out_path}")

def build_beast_juggernaut():
    reset_scene()
    arm, meshes = import_base()
    # Colossal bulky juggernaut proportions
    arm.scale = (1.55, 1.60, 1.35)
    skin_mat = create_pbr_mat("M_BeastOrkSkin", (0.28, 0.38, 0.22, 1.0), roughness=0.75)
    for m in meshes:
        if len(m.data.materials) > 0:
            m.data.materials[0] = skin_mat
    # Colossal jutting tusks
    add_tusks(arm, size=0.24, spread=0.065)
    
    out_path = os.path.join(OUT_DIR, "race_ork_beast_juggernaut.glb")
    bpy.ops.export_scene.gltf(filepath=out_path, export_format='GLB', export_yup=True)
    print(f"[OK] Exported beast juggernaut orc to: {out_path}")

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    build_noble_warlord()
    build_beast_juggernaut()

if __name__ == "__main__":
    main()
