"""Rope-lashed wooden ladder parts (benchmark slice ladder, ref 02): exported as two pieces so the engine (scripts/interaction/kinds/ladder.gd)
can build a ladder of any height with the rung spacing the climb animation needs (0.31 m: Ladder_Climb_Up hand/foot contacts):
  ladder_rail.glb : one split-log rail, 1.0 m along +Y (origin at the bottom), ~5.5 x 4.5 cm, irregular (bark side round, split face flat),
                    knots, slight bow; UVs run along the length (world-stretch friendly), so it is scaled in Y to the ladder height
  ladder_rung.glb : one round rung 0.5 m across X (rails at x = +-0.22), 3.2 cm diameter, slightly bent and tapered, with a rope lashing
                    wrapped around each rail joint (cross-lashing over the rail), origin at the rung centre
Material: weathered wood (no texture baked in: the engine assigns Poly Haven medieval_wood with triplanar + a grey weathering tint) and
hemp rope. Units metres, +Y up (export_yup False after building in Blender Y-up convention by rotation).
Usage: blender -b --python tools/blender/props/build_ladder.py -- <out_dir>
"""
import bpy, bmesh, sys, math, random
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "."
random.seed(7)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, rgb, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes["Principled BSDF"]
    p.inputs["Base Color"].default_value = (*rgb, 1.0)
    p.inputs["Roughness"].default_value = rough
    return m


def finish(obs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
        for poly in o.data.polygons:
            poly.use_smooth = True
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    # built Z-up in Blender; the glTF exporter converts Blender +Z to glTF / Godot +Y
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=True)
    print("LADDER", path, len(ob.data.polygons))


def rail():
    reset()
    wood = mat("LadderWood", (0.42, 0.33, 0.24), 0.9)
    bm = bmesh.new()
    rings, segs = 24, 10
    rows = []
    for r in range(rings + 1):
        z = r / rings
        bow = 0.006 * math.sin(math.pi * z)                       # a slight bow along the length
        row = []
        for s in range(segs):
            a = 2 * math.pi * s / segs
            rx, ry = 0.045, 0.04
            x, y = math.cos(a) * rx, math.sin(a) * ry
            if x < -0.02:
                x = -0.02                                          # the split face: flat on the inside
            jitter = 1.0 + random.uniform(-0.07, 0.07) * (1.0 if x > 0 else 0.3)
            knot = 0.0
            if abs(z - 0.37) < 0.04 and 0.5 < a < 1.6 or abs(z - 0.81) < 0.035 and 3.6 < a < 4.6:
                knot = 0.007                                        # knots
            row.append(bm.verts.new((x * jitter + bow + (knot if x > 0 else 0), y * jitter, z)))
        rows.append(row)
    for r in range(rings):
        for s in range(segs):
            bm.faces.new((rows[r][s], rows[r][(s + 1) % segs], rows[r + 1][(s + 1) % segs], rows[r + 1][s]))
    bm.faces.new(list(reversed(rows[0])))
    bm.faces.new(rows[-1])
    me = bpy.data.meshes.new("Rail")
    bm.to_mesh(me)
    bm.free()
    uv = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv = (math.atan2(co.y, co.x) / (2 * math.pi) * 0.2 + 0.5, co.z)
    ob = bpy.data.objects.new("Rail", me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(wood)
    finish([ob], OUT + "/ladder_rail.glb")


def tube(name, pts, radius, segs, material):
    """A tube along a polyline of points."""
    bm = bmesh.new()
    rows = []
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        side = d.cross(up).normalized()
        up2 = side.cross(d).normalized()
        row = [bm.verts.new(p + (side * math.cos(2 * math.pi * s / segs) + up2 * math.sin(2 * math.pi * s / segs)) * radius)
               for s in range(segs)]
        rows.append(row)
    for i in range(len(rows) - 1):
        for s in range(segs):
            bm.faces.new((rows[i][s], rows[i][(s + 1) % segs], rows[i + 1][(s + 1) % segs], rows[i + 1][s]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.materials.append(material)
    return ob


def rung():
    reset()
    wood = mat("LadderWood", (0.42, 0.33, 0.24), 0.9)
    rope = mat("HempRope", (0.55, 0.47, 0.33), 0.95)
    # rung along X from -0.25 to 0.25 (the rails' centres are at +-0.22), slight bend and taper
    pts = [Vector((x, 0.0, -0.005 * (1 - (x / 0.29) ** 2))) for x in [i * 0.058 - 0.29 for i in range(11)]]
    obs = [tube("Rung", pts, 0.023, 12, wood)]
    # rope lashing at each rail: a helix around the rail (vertical, radius 3.6 cm) crossing over the rung
    for sx in (-0.26, 0.26):
        hp = []
        turns = 4.5
        n = 90
        for i in range(n + 1):
            t = i / n
            a = 2 * math.pi * turns * t
            z = -0.05 + 0.1 * t + 0.012 * math.sin(a * 2)        # wraps above and below the rung (cross-lashing)
            hp.append(Vector((sx + math.cos(a) * 0.052, math.sin(a) * 0.047, z)))
        obs.append(tube("Lash", hp, 0.008, 6, rope))
    finish(obs, OUT + "/ladder_rung.glb")


rail()
rung()
