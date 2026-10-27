"""Arming sword for the player (benchmark slice): 95 cm overall, double-edged blade 79 cm with a fuller tapering to a point,
crossguard 20 cm, leather-wrapped grip 10 cm, wheel pommel 4.5 cm. Worn steel, dark leather grip. Origin = grip centre,
blade along +Y (glTF), flat of the blade in the YZ plane (edges along +-X): the same convention as the KayKit weapons
(EquipmentVisuals WEAPON_FIT "sword" seats it with origin = grip).
Usage: blender -b --python tools/blender/props/build_arming_sword.py -- <out.glb>
"""
import bpy, bmesh, sys, math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "arming_sword.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, rgb, rough, metal):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*rgb, 1.0)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    return m


steel = mat("WornSteel", (0.72, 0.72, 0.7), 0.42, 0.55)    # half metallic: reads as steel without an environment probe
leather = mat("GripLeather", (0.12, 0.08, 0.05), 0.75, 0.0)
iron = mat("GuardIron", (0.42, 0.4, 0.38), 0.5, 0.5)

GRIP = 0.10
Z0 = GRIP / 2            # top of the grip (blade side), grip centre at 0 (Blender Z = glTF Y)


def link(name, bm, material):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(material)
    return ob


def blade():
    """Lenticular section with a fuller: per station a 7-point outline (edge, flat, fuller, centre ...), tapering to the point."""
    bm = bmesh.new()
    L = 0.79
    stations = 26
    rows = []
    for i in range(stations + 1):
        t = i / stations
        z = Z0 + 0.025 + L * t                       # the blade starts just above the guard
        w = 0.022 * (1.0 - t) ** 0.55 + 0.0006        # half width: 4.4 cm at the base to a point
        if t > 0.86:
            w *= max(0.02, 1.0 - (t - 0.86) / 0.14) ** 0.8
        th = 0.0032 * (1.0 - 0.6 * t) + 0.0005       # half thickness at the spine
        fuller = 0.0012 if t < 0.7 else 0.0012 * max(0.0, 1.0 - (t - 0.7) / 0.1)
        fw = w * 0.32
        pts = [(w, 0.0), (fw, th * 0.85), (0.0, th - fuller), (-fw, th * 0.85), (-w, 0.0),
               (-fw, -th * 0.85), (0.0, -(th - fuller)), (fw, -th * 0.85)]
        rows.append([bm.verts.new((x, y, z)) for x, y in pts])
    n = len(rows[0])
    for i in range(stations):
        for k in range(n):
            bm.faces.new((rows[i][k], rows[i][(k + 1) % n], rows[i + 1][(k + 1) % n], rows[i + 1][k]))
    bm.faces.new(list(reversed(rows[0])))
    tip = bm.verts.new((0, 0, Z0 + 0.025 + 0.79 + 0.004))
    for k in range(n):
        bm.faces.new((rows[-1][k], rows[-1][(k + 1) % n], tip))
    # ricasso / shoulder block between guard and blade
    return link("Blade", bm, steel)


def box(name, size, at, material, taper=1.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0] * (taper if abs(v.co.x) > 0 and v.co.x > 0 else 1.0)
        v.co.y *= size[1]
        v.co.z *= size[2]
        v.co += Vector(at)
    return link(name, bm, material)


def guard():
    bm = bmesh.new()
    # a bar 20 cm wide, square-ish section, ends slightly flared and bent toward the blade
    segs = 16
    rows = []
    for i in range(segs + 1):
        x = -0.10 + 0.2 * i / segs
        e = abs(x) / 0.10
        hw = 0.006 + 0.003 * e ** 3
        zc = Z0 + 0.008 + 0.006 * e ** 2
        rows.append([bm.verts.new((x, sy * hw, zc + sz * 0.008)) for sy, sz in ((1, 1), (-1, 1), (-1, -1), (1, -1))])
    for i in range(segs):
        for k in range(4):
            bm.faces.new((rows[i][k], rows[i][(k + 1) % 4], rows[i + 1][(k + 1) % 4], rows[i + 1][k]))
    bm.faces.new(rows[0])
    bm.faces.new(list(reversed(rows[-1])))
    return link("Guard", bm, iron)


def grip():
    bm = bmesh.new()
    segs, rings = 12, 14
    rows = []
    for r in range(rings + 1):
        z = -GRIP / 2 + GRIP * r / rings
        rad = 0.0145 + 0.0012 * math.sin(math.pi * r / rings) + 0.0006 * (r % 2)   # leather wraps
        rows.append([bm.verts.new((math.cos(2 * math.pi * s / segs) * rad * 1.15, math.sin(2 * math.pi * s / segs) * rad, z))
                     for s in range(segs)])
    for r in range(rings):
        for s in range(segs):
            bm.faces.new((rows[r][s], rows[r][(s + 1) % segs], rows[r + 1][(s + 1) % segs], rows[r + 1][s]))
    return link("Grip", bm, leather)


def pommel():
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=0.0225, radius2=0.0225, depth=0.018)
    # the wheel stands in the blade plane: rotate the disc so its axis is Y (thickness across the flat)
    for v in bm.verts:
        x, y, z = v.co
        v.co = Vector((x, z, y - GRIP / 2 - 0.022))
    # a raised centre boss
    ob = link("Pommel", bm, iron)
    return ob


obs = [blade(), guard(), grip(), pommel()]
for o in obs:
    for p in o.data.polygons:
        p.use_smooth = True
bpy.ops.object.select_all(action="DESELECT")
for o in obs:
    o.select_set(True)
bpy.context.view_layer.objects.active = obs[0]
bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
ob.name = "ArmingSword"
ws = ob.modifiers.new("WN", "WEIGHTED_NORMAL")
bpy.ops.object.modifier_apply(modifier="WN")
print("SWORD tris", sum(len(p.vertices) - 2 for p in ob.data.polygons), "dims", tuple(round(d, 3) for d in ob.dimensions))
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True)
print("SWORD_DONE", OUT)
