"""Hand-held tools missing from assets/generated/life_props: pickaxe and torch (WP-01 equipment states).
Same convention as the life_props tools: metres, the long axis is +Y, the origin is the grip (where the fist closes), so
EquipmentVisuals seats them like the KayKit weapons without fitting.
  pickaxe : ash haft 0.78 m (grip near the butt), iron head 0.46 m wide with a pointed pick and a flat adze end, wedge
  torch   : 0.55 m stick, pitch-soaked rag wrap at the top (the flame / light is added in the engine)
Usage: blender -b --python tools/blender/props/build_hand_tools.py -- <out_dir>
"""
import bpy, bmesh, sys, math
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "."


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, rgb, rough=0.85, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*rgb, 1.0)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    return m


def cyl(name, r0, r1, length, y0, segs=10, material=None):
    """A tapered cylinder along +Y from y0 to y0+length (Blender Z is used as Y via the export conversion off)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r0, radius2=r1, depth=length)
    # create_cone is along Z: rotate onto Y and move
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(-math.pi / 2, 3, "X"))
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, y0 + length / 2, 0))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    if material:
        me.materials.append(material)
    for p in me.polygons:
        p.use_smooth = True
    return ob


def box(name, size, at, material=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, verts=bm.verts, vec=size)
    bmesh.ops.translate(bm, verts=bm.verts, vec=at)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    if material:
        me.materials.append(material)
    return ob


def join_export(path):
    obs = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.join()
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=False, export_apply=True)
    print("TOOL", path, len(obs[0].data.polygons))


# --- pickaxe ------------------------------------------------------------------------------------------------------
reset()
wood = mat("Ash", (0.42, 0.29, 0.17), 0.8)
iron = mat("Iron", (0.32, 0.33, 0.35), 0.45, 0.8)
cyl("Haft", 0.018, 0.016, 0.78, -0.12, 10, wood)
# head: two tapering arms from the eye at the top of the haft
y_head = 0.6
box("Eye", (0.055, 0.075, 0.05), (0, y_head, 0), iron)
for side, (tip_w, tip_h, length) in ((1, (0.012, 0.012, 0.24)), (-1, (0.06, 0.012, 0.2))):
    bm = bmesh.new()
    # tapered arm along +-Z (forward / back of the pick), slightly curved down
    rings = 6
    prev = None
    for i in range(rings + 1):
        t = i / rings
        w = 0.05 * (1 - t) + tip_w * t
        h = 0.045 * (1 - t) + tip_h * t
        z = side * (0.025 + length * t)
        y = y_head - 0.06 * t * t
        ring = [bm.verts.new((sx * w / 2, y + sy * h / 2, z)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        if prev:
            for k in range(4):
                bm.faces.new((prev[k], prev[(k + 1) % 4], ring[(k + 1) % 4], ring[k]))
        else:
            bm.faces.new(ring)
        prev = ring
    bm.faces.new(list(reversed(prev)))
    me = bpy.data.meshes.new("Arm")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Arm", me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(iron)
join_export(OUT + "/pickaxe.glb")

# --- torch --------------------------------------------------------------------------------------------------------
reset()
wood = mat("Stick", (0.36, 0.24, 0.14), 0.9)
rag = mat("PitchRag", (0.12, 0.09, 0.07), 0.95)
cyl("Stick", 0.017, 0.021, 0.55, -0.12, 10, wood)
# rag wrap: a few overlapping bands, wider in the middle
for i, (y, r) in enumerate(((0.33, 0.032), (0.36, 0.036), (0.39, 0.037), (0.42, 0.033))):
    cyl("Wrap%d" % i, r, r * 0.95, 0.032, y, 12, rag)
join_export(OUT + "/torch.glb")
