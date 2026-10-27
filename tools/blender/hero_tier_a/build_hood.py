"""Hood-up cowl for the hero (character creator 'hood' look), replacing the procedural ellipsoid shell of
hero_tier_a.add_hood_up (smooth dome, thin lip, dark void, no folds: docs/plans/AAA_PROGRESS.md S3.0 defect 1).
Built in the Head bone attachment space the engine uses (metres, +Y up the neck, +Z forward = face), so it drops onto the
same BoneAttachment3D without fitting:
  crown   : a skull-hugging shell 1.5-2.5 cm off the head (not the old 4 cm dome), with a soft liripipe point at the back
  opening : a narrower oval face opening with a rolled, 1.6 cm thick hem (solidify + rim), inner edge turned in
  capelet : below the jaw the cloth flares onto the shoulders as a short gugel cape
  folds   : radial drape folds on the capelet, soft gathers from the hem back over the crown, a few creases at the neck
  uv      : cylindrical projection (wool noise in the shader is triplanar-safe either way)
Usage: tools/external/blender.sh tools/blender/hero_tier_a/build_hood.py -- <out.glb>
"""
import bpy, bmesh, sys, math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "hood_up.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)

# --- shell ------------------------------------------------------------------------------------------------------
CTR = Vector((0.0, 0.120, -0.026))   # measured: eyes at y 0.11, crown at 0.25 in Head-bone space
RAD = Vector((0.122, 0.156, 0.152))
OPEN_C = Vector((0.0, 0.085))         # face opening centre (x, y), on +Z
OPEN_R = (0.080, 0.110)               # half width, half height
RINGS, SEGS = 44, 72
LIRIPIPE = False          # the drawn-out point tore a hole at the back after decimation: off

bm = bmesh.new()
grid = []
for r in range(RINGS + 1):
    th = math.pi * r / RINGS
    row = []
    for s in range(SEGS):
        ph = 2.0 * math.pi * s / SEGS
        p = Vector((math.sin(th) * math.sin(ph), math.cos(th), math.sin(th) * math.cos(ph)))
        v = CTR + Vector((p.x * RAD.x, p.y * RAD.y, p.z * RAD.z))
        # liripipe: the back of the crown is drawn out into a soft point
        if LIRIPIPE and p.z < -0.2 and p.y > -0.1:
            k = min(1.0, (-p.z - 0.2) / 0.8) * max(0.0, min(1.0, (p.y + 0.1) / 0.9))
            v.z -= 0.045 * k * k
            v.y += 0.012 * k
        # capelet: below the jaw the cloth flares out and down onto the shoulders
        low = 0.015 - v.y
        if low > 0.0:
            flare = 1.0 + low * 3.4
            v.x *= flare
            v.z = (v.z + 0.012) * (1.0 + low * 2.2) - 0.012
            v.y -= low * 0.9
        row.append(bm.verts.new(v))
    grid.append(row)

for r in range(RINGS):
    for s in range(SEGS):
        a, b_ = grid[r][s], grid[r][(s + 1) % SEGS]
        c, d = grid[r + 1][s], grid[r + 1][(s + 1) % SEGS]
        bm.faces.new((a, c, d, b_))

# cut the face opening (faces whose centre lies inside the oval on the front)
dead = []
for f in bm.faces:
    cen = f.calc_center_median()
    if cen.z > 0.0 and ((cen.x - OPEN_C.x) / OPEN_R[0]) ** 2 + ((cen.y - OPEN_C.y) / OPEN_R[1]) ** 2 < 1.0:
        dead.append(f)
bmesh.ops.delete(bm, geom=dead, context="FACES")
# snap the boundary of the opening onto the oval (smooth hem line) and turn it slightly inward
bound = [v for v in bm.verts if v.is_boundary]
for v in bound:
    if v.co.z <= 0.0:
        continue
    ox = (v.co.x - OPEN_C.x) / OPEN_R[0]
    oy = (v.co.y - OPEN_C.y) / OPEN_R[1]
    e = math.sqrt(ox * ox + oy * oy)
    if e > 0.0001:
        v.co.x = OPEN_C.x + ox / e * OPEN_R[0]
        v.co.y = OPEN_C.y + oy / e * OPEN_R[1]
    v.co.z -= 0.01                       # hem tucks in toward the face
# delete the bottom cap (open under the cape)
low_faces = [f for f in bm.faces if f.calc_center_median().y < -0.26]   # the cape covers the shirt collar
bmesh.ops.delete(bm, geom=low_faces, context="FACES")
loose = [v for v in bm.verts if not v.link_faces]
bmesh.ops.delete(bm, geom=loose, context="VERTS")

# outward normals (the quad winding above faces inward: the far wall showed through a culled near wall)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
if sum((f.calc_center_median() - CTR).dot(f.normal) for f in bm.faces) < 0.0:
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
# --- folds --------------------------------------------------------------------------------------------------------
bm.normal_update()
for v in bm.verts:
    co = v.co
    ang = math.atan2(co.x, co.z)            # 0 = front
    n = v.normal.copy()
    disp = 0.0
    # capelet drape: 11 radial folds, deeper toward the hem
    depth = max(0.0, min(1.0, (0.0 - co.y) / 0.2))
    disp += 0.011 * depth * math.sin(ang * 11.0 + 0.6) * (0.6 + 0.4 * math.sin(ang * 3.0))
    # crown gathers: soft folds running back from the hem, fading toward the back point
    if co.y > 0.0:
        front = max(0.0, math.cos(ang))
        disp += 0.0065 * math.sin(ang * 7.0) * (1.0 - front * 0.6)
    # neck creases: a horizontal ripple where the hood meets the cape
    neck = math.exp(-((co.y + 0.02) / 0.03) ** 2)
    disp += 0.004 * neck * math.sin(ang * 5.0 + co.y * 40.0)
    v.co = co + n * disp

me = bpy.data.meshes.new("HoodUp")
bm.to_mesh(me)
bm.free()
ob = bpy.data.objects.new("HoodUp", me)
bpy.context.collection.objects.link(ob)

# cylindrical UV
uv = me.uv_layers.new(name="UVMap")
for poly in me.polygons:
    for li in poly.loop_indices:
        co = me.vertices[me.loops[li].vertex_index].co
        uv.data[li].uv = ((math.atan2(co.x, co.z) / (2 * math.pi)) + 0.5, (co.y + 0.25) / 0.55)

# thickness and a rolled hem
bpy.context.view_layer.objects.active = ob
sol = ob.modifiers.new("Solid", "SOLIDIFY")
sol.thickness = 0.008
sol.offset = -1.0
sol.use_rim = True
sol.use_even_offset = True
sub = ob.modifiers.new("Sub", "SUBSURF")
sub.levels = 1
sub.render_levels = 1
bpy.ops.object.modifier_apply(modifier="Solid")
bpy.ops.object.modifier_apply(modifier="Sub")
for p in me.polygons:
    p.use_smooth = True
wn = ob.modifiers.new("WN", "WEIGHTED_NORMAL")
wn.keep_sharp = False
bpy.ops.object.modifier_apply(modifier="WN")

# decimate to a game budget
dec = ob.modifiers.new("Dec", "DECIMATE")
dec.ratio = 0.2
bpy.ops.object.modifier_apply(modifier="Dec")

mat = bpy.data.materials.new("HoodWool")
mat.use_nodes = True
mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.36, 0.25, 0.16, 1.0)
mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
me.materials.append(mat)

print("HOOD tris", sum(len(p.vertices) - 2 for p in me.polygons), "verts", len(me.vertices))
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False, export_apply=True, export_yup=False)
print("HOOD_DONE", OUT)
