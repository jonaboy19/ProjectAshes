"""Scabbard for the player's arming sword (tools/blender/props/build_arming_sword.py): dark leather over a wooden core, iron
throat (locket) and chape, two leather lacing bands and a belt-frog tab rising from the throat. Built in the SWORD's own frame
(origin = grip centre, blade along +Y in glTF, edges along +-X), so the game places it with the same transform the rig gives the
sheathed sword (ProceduralRig hip socket) and the blade sits exactly inside it.
Usage: blender -b --python tools/blender/props/build_scabbard.py -- <out.glb>
"""
import bpy, bmesh, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "scabbard.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)

GRIP = 0.10
Z0 = GRIP / 2
BLADE_Z0 = Z0 + 0.025          # blade base (just above the guard)
BLADE_L = 0.79
THROAT_Z = Z0 + 0.016          # the scabbard mouth sits just under the guard
TIP_Z = BLADE_Z0 + BLADE_L + 0.03


def mat(name, rgb, rough, metal):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*rgb, 1.0)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    return m


leather = mat("ScabbardLeather", (0.035, 0.024, 0.017), 0.72, 0.0)     # near-black oiled leather (gate: mid-brown read too light)
strap = mat("FrogLeather", (0.07, 0.048, 0.03), 0.8, 0.0)
iron = mat("ScabbardIron", (0.30, 0.29, 0.27), 0.55, 0.5)


def link(name, bm, material):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(material)
    return ob


def half_w(z):
    """Half width at height z: the blade's own taper plus 8 mm of wood and leather, never under 1.1 cm."""
    t = min(max((z - BLADE_Z0) / BLADE_L, 0.0), 1.0)
    w = 0.022 * (1.0 - t) ** 0.55
    return max(w + 0.008, 0.011)


def body():
    bm = bmesh.new()
    stations = 30
    seg = 14
    rows = []
    import math
    for i in range(stations + 1):
        z = THROAT_Z + (TIP_Z - 0.03 - THROAT_Z) * i / stations
        w = half_w(z)
        th = 0.0105 - 0.004 * i / stations
        ring = []
        for k in range(seg):
            a = 2.0 * math.pi * k / seg
            # a flattened lens: wide across the edges (x), thin across the flats (y)
            x = math.cos(a) * w
            y = math.sin(a) * th * (0.55 + 0.45 * abs(math.sin(a)))
            ring.append(bm.verts.new((x, y, z)))
        rows.append(ring)
    for i in range(stations):
        for k in range(seg):
            bm.faces.new((rows[i][k], rows[i][(k + 1) % seg], rows[i + 1][(k + 1) % seg], rows[i + 1][k]))
    bm.faces.new(rows[0])
    tip = bm.verts.new((0, 0, TIP_Z - 0.012))
    for k in range(seg):
        bm.faces.new((rows[-1][k], rows[-1][(k + 1) % seg], tip))
    return link("ScabbardBody", bm, leather)


def band(name, z0, z1, grow, material, taper_to_point=False):
    import math
    bm = bmesh.new()
    seg = 14
    rows = []
    n = 4 if not taper_to_point else 6
    for i in range(n + 1):
        z = z0 + (z1 - z0) * i / n
        w = half_w(z) + grow
        th = 0.0105 + grow
        if taper_to_point:
            f = 1.0 - (i / n) ** 1.6 * 0.85
            w *= f
            th *= max(f, 0.35)
        rows.append([bm.verts.new((math.cos(2 * math.pi * k / seg) * w, math.sin(2 * math.pi * k / seg) * th, z)) for k in range(seg)])
    for i in range(n):
        for k in range(seg):
            bm.faces.new((rows[i][k], rows[i][(k + 1) % seg], rows[i + 1][(k + 1) % seg], rows[i + 1][k]))
    bm.faces.new(list(reversed(rows[0])))
    bm.faces.new(rows[-1])
    return link(name, bm, material)


def frog():
    """Belt-frog tab: a leather strap rising from the throat on the outer flat, toward the belt."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= 0.03
        v.co.y *= 0.006
        v.co.z *= 0.085
        v.co += Vector((0.0, 0.016, THROAT_Z - 0.01))
    return link("Frog", bm, strap)


def hanger(name, a, b, width=0.016, thick=0.004):
    """A flat leather strap from a (on the scabbard's inner flat) up to b (the belt): a thin box along a->b."""
    a = Vector(a)
    b = Vector(b)
    d = b - a
    ln = d.length
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * width, v.co.y * thick, (v.co.z + 0.5) * ln))
    z = d.normalized()
    x = Vector((1.0, 0.0, 0.0))
    x = (x - z * x.dot(z)).normalized()
    y = z.cross(x)
    from mathutils import Matrix
    m = Matrix((x, y, z)).transposed()
    for v in bm.verts:
        v.co = m @ v.co + a
    return link(name, bm, strap)


# Two hanger straps from the throat and from a quarter down the scabbard up to the belt (the inner flat faces -Y, the body):
# the front one short and steep, the rear one long, so the scabbard hangs at its angle from the belt instead of floating.
HANGERS = [hanger("HangerFront", (0.022, -0.012, THROAT_Z + 0.03), (0.03, -0.035, Z0 - 0.09)),
           hanger("HangerRear", (-0.018, -0.011, THROAT_Z + 0.21), (-0.05, -0.04, Z0 - 0.07))]

obs = HANGERS + [body(),
       band("Throat", THROAT_Z - 0.004, THROAT_Z + 0.045, 0.0025, iron),
       band("LaceA", THROAT_Z + 0.11, THROAT_Z + 0.125, 0.0018, strap),
       band("LaceB", THROAT_Z + 0.33, THROAT_Z + 0.345, 0.0018, strap),
       band("Chape", TIP_Z - 0.11, TIP_Z, 0.0022, iron, True),
       frog()]
for o in obs:
    for p in o.data.polygons:
        p.use_smooth = True
bpy.ops.object.select_all(action="DESELECT")
for o in obs:
    o.select_set(True)
bpy.context.view_layer.objects.active = obs[0]
bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
ob.name = "Scabbard"
bpy.ops.object.modifier_add(type="WEIGHTED_NORMAL")
bpy.ops.object.modifier_apply(modifier="WeightedNormal")
print("SCABBARD tris", sum(len(p.vertices) - 2 for p in ob.data.polygons), "dims", tuple(round(d, 3) for d in ob.dimensions))
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True)
print("SCABBARD_DONE", OUT)
