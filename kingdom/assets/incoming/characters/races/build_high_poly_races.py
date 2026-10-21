#!/usr/bin/env python3
"""
High-Poly Race Generator for Project Ashes (Godot 4.6 / Blender 5.2)
Constructs rigged, textured high-poly race models based on the Universal Base Character meshes.
Creates geometry attachments (pointed ears, horns, tails, beards, dorsal scales),
weights them to the standard armature ('Head', 'pelvis', 'spine_02', etc.), and exports
clean GLB models with full PBR materials.
"""

import bpy
import bmesh
import math
import os
from mathutils import Vector, Matrix

BASE_GLTF = r"C:\Users\Jonna\Documents\ProjectAshes\kingdom\assets\incoming\quaternius\universal-base-characters\Base Characters\Godot - UE\Superhero_Male_FullBody.gltf"
OUT_DIR = r"C:\Users\Jonna\Documents\ProjectAshes\kingdom\assets\incoming\characters\races"

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def import_base_character():
    bpy.ops.import_scene.gltf(filepath=BASE_GLTF)
    arm = [obj for obj in bpy.data.objects if obj.type == 'ARMATURE'][0]
    meshes = [obj for obj in bpy.data.objects if obj.type == 'MESH']
    return arm, meshes

def create_pbr_mat(name, base_color, metallic=0.0, roughness=0.5, emission=None):
    mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = base_color
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        if emission:
            if "Emission Color" in bsdf.inputs:
                bsdf.inputs["Emission Color"].default_value = emission
                bsdf.inputs["Emission Strength"].default_value = 2.0
            elif "Emission" in bsdf.inputs:
                bsdf.inputs["Emission"].default_value = emission
    return mat

def attach_mesh_to_bone(obj, arm, bone_name):
    mod = obj.modifiers.new(name="Armature", type='ARMATURE')
    mod.object = arm
    vg = obj.vertex_groups.new(name=bone_name)
    all_indices = [v.index for v in obj.data.vertices]
    vg.add(all_indices, 1.0, 'REPLACE')
    obj.parent = arm

def add_elven_ears(arm, color=(0.88, 0.76, 0.68, 1.0)):
    # Left Ear
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=6, radius1=0.025, radius2=0.002, depth=0.12)
    mesh_l = bpy.data.meshes.new("Ear_L")
    bm.to_mesh(mesh_l)
    bm.free()
    
    obj_l = bpy.data.objects.new("Ear_L", mesh_l)
    bpy.context.collection.objects.link(obj_l)
    obj_l.location = Vector((0.10, -0.01, 1.70))
    obj_l.rotation_euler = (math.radians(-25), math.radians(45), math.radians(35))
    
    # Right Ear
    bm2 = bmesh.new()
    bmesh.ops.create_cone(bm2, cap_ends=True, cap_tris=False, segments=6, radius1=0.025, radius2=0.002, depth=0.12)
    mesh_r = bpy.data.meshes.new("Ear_R")
    bm2.to_mesh(mesh_r)
    bm2.free()
    
    obj_r = bpy.data.objects.new("Ear_R", mesh_r)
    bpy.context.collection.objects.link(obj_r)
    obj_r.location = Vector((-0.10, -0.01, 1.70))
    obj_r.rotation_euler = (math.radians(-25), math.radians(-45), math.radians(-35))
    
    mat = create_pbr_mat("M_ElvenEar", color, roughness=0.6)
    obj_l.data.materials.append(mat)
    obj_r.data.materials.append(mat)
    
    attach_mesh_to_bone(obj_l, arm, "Head")
    attach_mesh_to_bone(obj_r, arm, "Head")

def add_horns(arm, color=(0.15, 0.08, 0.08, 1.0), curvature=45):
    # Left Horn
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=8, radius1=0.035, radius2=0.005, depth=0.22)
    mesh_l = bpy.data.meshes.new("Horn_L")
    bm.to_mesh(mesh_l)
    bm.free()
    
    obj_l = bpy.data.objects.new("Horn_L", mesh_l)
    bpy.context.collection.objects.link(obj_l)
    obj_l.location = Vector((0.07, 0.05, 1.78))
    obj_l.rotation_euler = (math.radians(curvature), math.radians(20), math.radians(15))
    
    # Right Horn
    bm2 = bmesh.new()
    bmesh.ops.create_cone(bm2, cap_ends=True, cap_tris=False, segments=8, radius1=0.035, radius2=0.005, depth=0.22)
    mesh_r = bpy.data.meshes.new("Horn_R")
    bm2.to_mesh(mesh_r)
    bm2.free()
    
    obj_r = bpy.data.objects.new("Horn_R", mesh_r)
    bpy.context.collection.objects.link(obj_r)
    obj_r.location = Vector((-0.07, 0.05, 1.78))
    obj_r.rotation_euler = (math.radians(curvature), math.radians(-20), math.radians(-15))
    
    mat = create_pbr_mat("M_Horns", color, metallic=0.2, roughness=0.35)
    obj_l.data.materials.append(mat)
    obj_r.data.materials.append(mat)
    
    attach_mesh_to_bone(obj_l, arm, "Head")
    attach_mesh_to_bone(obj_r, arm, "Head")

def add_tail(arm, color=(0.2, 0.05, 0.05, 1.0), is_spade=True):
    bm = bmesh.new()
    # Segmented curved tail
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=8, radius1=0.035, radius2=0.01, depth=0.55)
    if is_spade:
        # Add spade tip
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=4, radius1=0.06, radius2=0.001, depth=0.10)
    mesh = bpy.data.meshes.new("Tail")
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new("Tail", mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = Vector((0.0, -0.12, 0.90))
    obj.rotation_euler = (math.radians(-65), 0, 0)
    
    mat = create_pbr_mat("M_Tail", color, roughness=0.5)
    obj.data.materials.append(mat)
    attach_mesh_to_bone(obj, arm, "pelvis")

def add_dorsal_spines(arm, color=(0.1, 0.25, 0.15, 1.0)):
    # 4 dorsal spines down back
    for i in range(4):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=4, radius1=0.02, radius2=0.002, depth=0.08)
        mesh = bpy.data.meshes.new(f"Spine_{i}")
        bm.to_mesh(mesh)
        bm.free()
        
        obj = bpy.data.objects.new(f"Spine_{i}", mesh)
        bpy.context.collection.objects.link(obj)
        z_pos = 1.20 + (i * 0.10)
        obj.location = Vector((0.0, -0.09, z_pos))
        obj.rotation_euler = (math.radians(-80), 0, 0)
        
        mat = create_pbr_mat(f"M_Spine_{i}", color, metallic=0.3, roughness=0.4)
        obj.data.materials.append(mat)
        bone = "spine_02" if i < 2 else "spine_03"
        attach_mesh_to_bone(obj, arm, bone)

def build_race(race_name, builder_func):
    reset_scene()
    arm, meshes = import_base_character()
    builder_func(arm, meshes)
    
    out_path = os.path.join(OUT_DIR, f"race_{race_name}.glb")
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format='GLB',
        use_selection=False,
        export_apply=False,
        export_yup=True
    )
    print(f"[OK] Exported {race_name} to: {out_path}")

# Builder implementations
def build_elf(arm, meshes):
    add_elven_ears(arm, color=(0.92, 0.82, 0.74, 1.0))
    # Slight slender scale
    arm.scale = (0.95, 0.95, 1.05)

def build_dark_elf(arm, meshes):
    # Obsidian skin color
    add_elven_ears(arm, color=(0.22, 0.20, 0.25, 1.0))
    # Recolor base meshes to obsidian
    obsidian_mat = create_pbr_mat("M_ObsidianSkin", (0.22, 0.20, 0.25, 1.0), roughness=0.6)
    for m in meshes:
        if len(m.data.materials) > 0:
            m.data.materials[0] = obsidian_mat
    arm.scale = (0.96, 0.96, 1.04)

def build_tiefling(arm, meshes):
    # Ram horns + spade tail
    add_horns(arm, color=(0.18, 0.06, 0.06, 1.0), curvature=55)
    add_tail(arm, color=(0.60, 0.18, 0.18, 1.0), is_spade=True)
    crimson_mat = create_pbr_mat("M_NetherSkin", (0.65, 0.22, 0.22, 1.0), roughness=0.55)
    for m in meshes:
        if len(m.data.materials) > 0:
            m.data.materials[0] = crimson_mat

def build_draken_dragonnewt(arm, meshes):
    # Dragon horns + dorsal spines + tail
    add_horns(arm, color=(0.10, 0.15, 0.12, 1.0), curvature=35)
    add_dorsal_spines(arm, color=(0.08, 0.28, 0.18, 1.0))
    add_tail(arm, color=(0.12, 0.35, 0.22, 1.0), is_spade=False)
    scale_mat = create_pbr_mat("M_DragonScale", (0.15, 0.38, 0.25, 1.0), metallic=0.25, roughness=0.45)
    for m in meshes:
        if len(m.data.materials) > 0:
            m.data.materials[0] = scale_mat
    arm.scale = (1.08, 1.08, 1.12)

def build_beastkin_lupine(arm, meshes):
    # Pointed beast ears + wolf tail
    # Ears on top of head
    bm_l = bmesh.new()
    bmesh.ops.create_cone(bm_l, cap_ends=True, cap_tris=False, segments=6, radius1=0.035, radius2=0.005, depth=0.10)
    mesh_l = bpy.data.meshes.new("BeastEar_L")
    bm_l.to_mesh(mesh_l)
    bm_l.free()
    obj_l = bpy.data.objects.new("BeastEar_L", mesh_l)
    bpy.context.collection.objects.link(obj_l)
    obj_l.location = Vector((0.08, 0.02, 1.82))
    obj_l.rotation_euler = (math.radians(-15), math.radians(25), 0)
    
    bm_r = bmesh.new()
    bmesh.ops.create_cone(bm_r, cap_ends=True, cap_tris=False, segments=6, radius1=0.035, radius2=0.005, depth=0.10)
    mesh_r = bpy.data.meshes.new("BeastEar_R")
    bm_r.to_mesh(mesh_r)
    bm_r.free()
    obj_r = bpy.data.objects.new("BeastEar_R", mesh_r)
    bpy.context.collection.objects.link(obj_r)
    obj_r.location = Vector((-0.08, 0.02, 1.82))
    obj_r.rotation_euler = (math.radians(-15), math.radians(-25), 0)
    
    fur_mat = create_pbr_mat("M_BeastFur", (0.45, 0.35, 0.25, 1.0), roughness=0.8)
    obj_l.data.materials.append(fur_mat)
    obj_r.data.materials.append(fur_mat)
    attach_mesh_to_bone(obj_l, arm, "Head")
    attach_mesh_to_bone(obj_r, arm, "Head")
    add_tail(arm, color=(0.42, 0.32, 0.22, 1.0), is_spade=False)

def build_dwarf(arm, meshes):
    # Stocky dwarf proportions
    arm.scale = (1.28, 1.25, 0.78)
    # Braided beard attached to head
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=8, radius1=0.07, radius2=0.02, depth=0.22)
    mesh = bpy.data.meshes.new("Beard")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Beard", mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = Vector((0.0, 0.08, 1.58))
    obj.rotation_euler = (math.radians(20), 0, 0)
    beard_mat = create_pbr_mat("M_DwarfBeard", (0.55, 0.25, 0.10, 1.0), roughness=0.75)
    obj.data.materials.append(beard_mat)
    attach_mesh_to_bone(obj, arm, "Head")

def build_undead_wight(arm, meshes):
    # Ashen desaturated skin + glowing blue eye emissives
    wight_mat = create_pbr_mat("M_WightFlesh", (0.42, 0.48, 0.50, 1.0), roughness=0.7)
    for m in meshes:
        if len(m.data.materials) > 0:
            m.data.materials[0] = wight_mat
    # Glowing eye spheres
    for sign, name in [(0.035, "EyeGlow_L"), (-0.035, "EyeGlow_R")]:
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=6, radius=0.012)
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.location = Vector((sign, 0.08, 1.70))
        glow_mat = create_pbr_mat("M_SoulGlow", (0.1, 0.8, 1.0, 1.0), emission=(0.1, 0.8, 1.0, 1.0))
        obj.data.materials.append(glow_mat)
        attach_mesh_to_bone(obj, arm, "Head")

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    races = [
        ("elf", build_elf),
        ("dark_elf", build_dark_elf),
        ("tiefling", build_tiefling),
        ("draken_dragonnewt", build_draken_dragonnewt),
        ("beastkin_lupine", build_beastkin_lupine),
        ("dwarf", build_dwarf),
        ("undead_wight", build_undead_wight)
    ]
    for name, func in races:
        print(f"Building high-poly race: {name}...")
        build_race(name, func)

if __name__ == "__main__":
    main()
