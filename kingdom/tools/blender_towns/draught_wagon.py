# Towns medieval pass: a horse-drawn wagon with separate wheel nodes (road_traffic.gd spins them by distance travelled).
# blender -b --factory-startup -P draught_wagon.py -- <out_dir>
# Forward (toward the horse) = +Y in Blender = +Z in Godot. Wheel nodes: wheel_fl, wheel_fr, wheel_rl, wheel_rr (origin at the hub,
# axle along X). Bench top at 1.35 m, 0.95 m ahead of the centre (driver seat). Shaft tips at +Y 3.6 m (horse between them).
import bpy, bmesh, sys, math
from mathutils import Vector, Matrix

out = sys.argv[sys.argv.index("--") + 1]
COL = {"RA_timber": (0.3, 0.2, 0.12), "RA_boards": (0.45, 0.35, 0.24), "RA_canvas": (0.78, 0.72, 0.58), "RA_iron": (0.12, 0.12, 0.13)}


def mat(n):
    m = bpy.data.materials.get(n)
    if m is None:
        m = bpy.data.materials.new(n)
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*COL[n], 1.0)
    return m


def obj(name, build, loc=(0, 0, 0)):
    bm = bmesh.new()
    mats = []

    def box(c, s, m, rx=0.0, ry=0.0):
        if m not in mats:
            mats.append(m)
        r = bmesh.ops.create_cube(bm, size=1.0)
        M = Matrix.Translation(Vector(c)) @ Matrix.Rotation(rx, 4, "X") @ Matrix.Rotation(ry, 4, "Y") @ Matrix.Diagonal((*s, 1.0))
        bmesh.ops.transform(bm, matrix=M, verts=r["verts"])
        for f in {f for v in r["verts"] for f in v.link_faces}:
            f.material_index = mats.index(m)

    build(box)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    for m in mats:
        me.materials.append(mat(m))
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    bpy.context.scene.collection.objects.link(ob)
    return ob


def body(box):
    box((0, 0, 0.95), (1.4, 3.0, 0.1), "RA_boards")                  # bed
    for x in (-0.72, 0.72):
        box((x, 0, 1.2), (0.06, 3.0, 0.4), "RA_boards")              # sides
    box((0, -1.5, 1.2), (1.4, 0.06, 0.4), "RA_boards")
    for y in (-1.0, 1.0):
        box((0, y, 0.6), (1.7, 0.12, 0.12), "RA_timber")             # axles
    box((0, 1.25, 1.3), (1.3, 0.35, 0.08), "RA_boards")              # bench
    for x in (-0.3, 0.3):
        box((x, 2.4, 0.85), (0.08, 2.4, 0.08), "RA_timber", rx=-0.12)  # shafts to the horse
    for k in range(4):                                                # canvas hoops + cover
        y = -1.3 + k * 0.8
        box((0, y, 1.95), (1.5, 0.05, 0.05), "RA_timber")
    box((0, -0.15, 2.0), (1.45, 2.5, 0.06), "RA_canvas")
    for x in (-0.74, 0.74):
        box((x, -0.15, 1.65), (0.04, 2.5, 0.65), "RA_canvas")
    for k in range(3):                                                # load: sacks / barrels as boxes
        box((-0.35 + k * 0.35, -0.9, 1.15), (0.3, 0.45, 0.35), "RA_boards")


def wheel(box):
    r = 0.6
    n = 12
    for k in range(n):                                               # rim segments
        a = 2 * math.pi * k / n
        box((0, math.cos(a) * r, math.sin(a) * r), (0.08, 2 * math.pi * r / n + 0.02, 0.08), "RA_timber", rx=a + math.pi / 2)
    for k in range(6):                                               # spokes
        a = math.pi * k / 6
        box((0, 0, 0), (0.05, 0.05, 2 * r), "RA_timber", rx=a)
    box((0, 0, 0), (0.2, 0.18, 0.18), "RA_iron")


bpy.ops.wm.read_factory_settings(use_empty=True)
root = bpy.data.objects.new("draught_wagon", None)
bpy.context.scene.collection.objects.link(root)
b = obj("wagon_body", body)
b.parent = root
for name, x, y in (("wheel_fl", -0.9, 1.0), ("wheel_fr", 0.9, 1.0), ("wheel_rl", -0.9, -1.0), ("wheel_rr", 0.9, -1.0)):
    w = obj(name, wheel, (x, y, 0.6))
    w.parent = root
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=f"{out}/draught_wagon.glb", use_selection=True, export_format="GLB", export_yup=True)
print("WAGON_DONE")
