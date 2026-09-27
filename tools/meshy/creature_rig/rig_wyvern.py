"""Procedural wyvern rig (spine, neck, tail, legs, arms, wings) + idle/walk/flap/attack/hit/death.
Landmarks were read off gridded ortho renders of the normalised mesh (3.0 m tall, facing -Y).
args: mesh.glb outdir [debug_png_prefix]"""
import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
from proc_common import *
from groundfix import fix_ground
import numpy as np

a = sys.argv[sys.argv.index('--') + 1:]
src, outdir = a[0], a[1]
dbg = a[2] if len(a) > 2 else None
reset(30)
mesh = load_normalised(src, 'height', 3.0)
mesh.name = "wyvern"

def mir(p): return (-p[0], p[1], p[2])
WING = {  # the Meshy wings are not symmetric: the right wing is folded tighter
    "L": dict(elbow=(0.42, -0.82, 2.42), wrist=(0.62, -0.72, 2.92), f1=(0.85, 0.95, 1.4), f2=(0.88, 0.3, 0.6), f3=(0.55, -0.27, 1.25)),
    "R": dict(elbow=(-0.33, -0.82, 2.42), wrist=(-0.44, -0.76, 2.95), f1=(-0.7, 0.73, 1.4), f2=(-0.88, 0.3, 0.45), f3=(-0.5, -0.27, 1.25))}
def wingbones(s):
    w = WING[s]; sx = 1 if s == "L" else -1
    return [dict(name=f"wing1_{s}", head=(sx * 0.22, -0.86, 1.9), tail=w["elbow"], parent="chest"),
            dict(name=f"wing2_{s}", head=w["elbow"], tail=w["wrist"], parent=f"wing1_{s}"),
            dict(name=f"finger1_{s}", head=w["wrist"], tail=w["f1"], parent=f"wing2_{s}"),
            dict(name=f"finger2_{s}", head=w["wrist"], tail=w["f2"], parent=f"wing2_{s}"),
            dict(name=f"finger3_{s}", head=w["wrist"], tail=w["f3"], parent=f"wing2_{s}")]
B = [dict(name="root", head=(0, 0, 0), tail=(0, 0.3, 0), deform=False),
     dict(name="hips", head=(0, -0.62, 0.98), tail=(0, -0.88, 1.32), parent="root"),
     dict(name="spine", head=(0, -0.88, 1.32), tail=(0, -1.0, 1.62), parent="hips"),
     dict(name="chest", head=(0, -1.0, 1.62), tail=(0, -1.1, 1.9), parent="spine"),
     dict(name="neck1", head=(0, -1.1, 1.9), tail=(0, -1.2, 2.12), parent="chest"),
     dict(name="neck2", head=(0, -1.2, 2.12), tail=(0, -1.28, 2.32), parent="neck1"),
     dict(name="head", head=(0, -1.28, 2.32), tail=(0, -1.74, 2.45), parent="neck2")]
tail = [(0, -0.62, 0.92), (0, -0.33, 0.64), (0, -0.03, 0.40), (-0.01, 0.35, 0.18), (-0.05, 0.8, 0.08),
        (-0.2, 1.15, 0.14), (-0.35, 1.42, 0.42), (-0.3, 1.6, 0.8)]
for i in range(len(tail) - 1):
    B.append(dict(name=f"tail{i+1}", head=tail[i], tail=tail[i + 1], parent="hips" if i == 0 else f"tail{i}"))
for s, sx in (("L", 1), ("R", -1)):
    def m(p): return (sx * p[0], p[1], p[2])
    B += [dict(name=f"thigh_{s}", head=m((0.28, -0.68, 1.0)), tail=m((0.4, -0.86, 0.58)), parent="hips"),
          dict(name=f"shin_{s}", head=m((0.4, -0.86, 0.58)), tail=m((0.45, -0.46, 0.24)), parent=f"thigh_{s}"),
          dict(name=f"foot_{s}", head=m((0.45, -0.46, 0.24)), tail=m((0.5, -0.86, 0.04)), parent=f"shin_{s}"),
          dict(name=f"ikfoot_{s}", head=m((0.45, -0.46, 0.24)), tail=m((0.5, -0.86, 0.04)), parent="root", deform=False),
          dict(name=f"upperarm_{s}", head=m((0.26, -1.02, 1.55)), tail=m((0.38, -1.25, 1.12)), parent="chest"),
          dict(name=f"forearm_{s}", head=m((0.38, -1.25, 1.12)), tail=m((0.36, -1.38, 0.88)), parent=f"upperarm_{s}"),
          dict(name=f"hand_{s}", head=m((0.36, -1.38, 0.88)), tail=m((0.36, -1.42, 0.72)), parent=f"forearm_{s}"),
          *wingbones(s)]
arm = build_armature("wyvern", B)
# horns and the raised wing arms are close together: split them by the wing-arm line x_w(z)
XW = lambda P: np.where(P[:, 0] >= 0, 0.22 + 0.40 * (P[:, 2] - 1.9) / 1.02 - 0.09, 0.22 + 0.22 * (P[:, 2] - 1.9) / 1.05 - 0.07)
WINGB = [f"{b}_{s}" for b in ("wing1", "wing2", "finger1", "finger2", "finger3") for s in "LR"]
skin_nearest(mesh, arm, k=3, power=5.0, zones=[
    (lambda P: (P[:, 1] < -0.75) & (P[:, 2] > 2.15) & (np.abs(P[:, 0]) < XW(P)), ["head", "neck2", "neck1"]),
    (lambda P: (P[:, 2] > 2.15) & (np.abs(P[:, 0]) >= XW(P)), WINGB)])
print("UNWEIGHTED", sum(1 for v in mesh.data.vertices if not v.groups), "bones", len(arm.data.bones))

if dbg:
    sc = bpy.context.scene
    mat = bpy.data.materials.new("stick"); mat.diffuse_color = (1, 0.1, 0.1, 1)
    for b in arm.data.bones:
        h, t = b.head_local, b.tail_local
        bpy.ops.mesh.primitive_cylinder_add(radius=0.02, depth=(t - h).length, location=(h + t) / 2)
        c = bpy.context.object; c.rotation_mode = 'QUATERNION'
        c.rotation_quaternion = (t - h).to_track_quat('Z', 'Y'); c.data.materials.append(mat)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = 4.2
    sc.render.engine = 'BLENDER_WORKBENCH'; sh = sc.display.shading
    sh.color_type = 'MATERIAL'; sh.show_xray = True; sh.xray_alpha = 0.5
    sc.render.resolution_x = sc.render.resolution_y = 900
    for nm, loc, rot in (("front", (0, -10, 1.5), (math.radians(90), 0, 0)), ("side", (10, 0, 1.5), (math.radians(90), 0, math.radians(90)))):
        cam.location = loc; cam.rotation_euler = rot
        sc.render.filepath = f"{dbg}_{nm}.png"; bpy.ops.render.render(write_still=True)
    for o in [o for o in bpy.data.objects if o.name.startswith("Cylinder")]: bpy.data.objects.remove(o)
    bpy.data.objects.remove(cam)

for s in "LR":
    add_ik(arm, f"shin_{s}", f"ikfoot_{s}", 2)
    c = arm.pose.bones[f"foot_{s}"].constraints.new('COPY_ROTATION')
    c.target = arm; c.subtarget = f"ikfoot_{s}"
X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
TAILS = [f"tail{i}" for i in range(1, len(tail))]

def wings(an, f, spread, fore=0.0):
    """spread: degrees the wing swings outward/down from its raised rest pose (about the body's long axis)."""
    for s, sx in (("L", 1), ("R", -1)):
        an.rot(f, f"wing1_{s}", Y, sx * spread)
        if fore: an.rot(f, f"wing2_{s}", Y, sx * fore)

def tailwave(an, f, T, amp, phase=0.0, lift=0.0):
    for i, b in enumerate(TAILS):
        an.rot(f, b, Z, amp * (0.4 + 0.15 * i) * math.sin(2 * math.pi * f / T - 0.6 * i + phase))
        if lift: an.rot(f, b, X, lift)

out = {}
# idle 60f
an = Anim(arm, "idle"); T = 60
for f in range(0, T + 1, 2):
    s = math.sin(2 * math.pi * f / T)
    an.rot(f, "chest", X, 2.0 * s); an.rot(f, "spine", X, 1.0 * s)
    an.rot(f, "neck1", Z, 5 * math.sin(2 * math.pi * f / T + 1)); an.rot(f, "head", X, -3 * s)
    wings(an, f, 3 * s)
    tailwave(an, f, T, 5)
    for sd in "LR": an.loc(f, f"ikfoot_{sd}", (0, 0, 0))
    an.loc(f, "hips", (0, 0, -0.015 * (1 - s) / 2))
out["idle"] = an

# walk 32f: digitigrade biped steps, feet slide back while planted
an = Anim(arm, "walk"); T = 32; stride = 0.55; duty = 0.58
for f in range(T + 1):
    for sd, ph in (("L", 0.0), ("R", 0.5)):
        u = (f / T + ph) % 1.0
        if u < duty:
            y = -stride / 2 + stride * (u / duty); z = 0.0
        else:
            t = (u - duty) / (1 - duty); y = stride / 2 - stride * t; z = 0.22 * math.sin(math.pi * t)
        an.loc(f, f"ikfoot_{sd}", (0, y, z))
    c2 = math.cos(4 * math.pi * f / T); s1 = math.sin(2 * math.pi * f / T)
    an.loc(f, "hips", (0.05 * s1, 0, -0.06 + 0.035 * c2))
    an.rot(f, "hips", Z, 5 * s1); an.rot(f, "chest", Z, -4 * s1); an.rot(f, "neck1", Z, -3 * s1)
    an.rot(f, "chest", X, 4)
    for sd, sg in (("L", 1), ("R", -1)):
        an.rot(f, f"upperarm_{sd}", X, 12 * sg * s1)
    wings(an, f, 4 * c2)
    tailwave(an, f, T, 7, phase=1.5)
out["walk"] = an

# flap 24f: standing wing beat, body lifts on the down-stroke
an = Anim(arm, "flap"); T = 24
for f in range(T + 1):
    ph = 2 * math.pi * f / T
    down = 0.5 - 0.5 * math.cos(ph)
    wings(an, f, 85 * down, fore=-20 * math.sin(ph))
    an.loc(f, "hips", (0, 0, 0.08 * math.sin(ph - 0.8)))
    an.rot(f, "chest", X, -6 * down); an.rot(f, "neck1", X, 5 * down); an.rot(f, "head", X, -4 * down)
    for sd in "LR": an.loc(f, f"ikfoot_{sd}", (0, 0, 0))
    tailwave(an, f, T, 4, lift=3 * down)
out["flap"] = an

def pose(an, f, chest=0.0, neck=0.0, head=0.0, hips_z=0.0, hips_y=0.0, wing=0.0, tail_lift=0.0, arms=0.0, root_roll=0.0, knees=None):
    an.rot(f, "chest", X, chest); an.rot(f, "spine", X, chest * 0.5)
    an.rot(f, "neck1", X, neck); an.rot(f, "neck2", X, neck * 0.6); an.rot(f, "head", X, head)
    an.loc(f, "hips", (0, hips_y, hips_z))
    wings(an, f, wing)
    for b in TAILS: an.rot(f, b, X, tail_lift)
    for sd in "LR":
        an.rot(f, f"upperarm_{sd}", X, arms)
        an.loc(f, f"ikfoot_{sd}", (0, 0, 0))
    if root_roll: an.rot(f, "root", Y, root_roll)

# attack: rear back, then lunge-bite forward and down
an = Anim(arm, "attack")
pose(an, 0)
pose(an, 10, chest=-14, neck=-12, head=10, hips_z=-0.04, hips_y=0.05, wing=25, tail_lift=3, arms=-20)
pose(an, 17, chest=22, neck=28, head=-12, hips_z=-0.12, hips_y=-0.12, wing=40, tail_lift=4, arms=35)
pose(an, 23, chest=18, neck=22, head=-8, hips_z=-0.1, hips_y=-0.1, wing=30, tail_lift=3, arms=25)
pose(an, 36)
out["attack"] = an

an = Anim(arm, "hit")
pose(an, 0)
pose(an, 4, chest=-12, neck=-15, head=12, hips_y=0.08, wing=20, arms=-15)
pose(an, 9, chest=-4, neck=-5, head=4, hips_y=0.03, wing=8)
pose(an, 16)
out["hit"] = an

# death: knees buckle, then the whole body topples onto its side
an = Anim(arm, "death")
pose(an, 0)
pose(an, 8, chest=-10, neck=-18, head=15, hips_z=0.0, wing=30, arms=-10)
pose(an, 20, chest=15, neck=20, head=-10, hips_z=-0.45, wing=45, tail_lift=2, arms=20, root_roll=8)
pose(an, 34, chest=20, neck=35, head=-15, hips_z=-0.5, wing=60, tail_lift=3, arms=25, root_roll=72)
pose(an, 50, chest=20, neck=38, head=-18, hips_z=-0.5, wing=62, tail_lift=3, arms=25, root_roll=78)
out["death"] = an

for nm, an in out.items():
    ctl, f0, f1 = an.write()
    bake(arm, ctl, f0, f1, nm)
clear_constraints(arm)
fix_ground(arm, mesh, "root", skip=("death", "attack", "flap"), tol=0.02)
for tag, t, px in (("", 15000, 1024), ("_lod1", 5000, 512)):
    n = decimate_to(mesh, t); cap_images(px)
    print("TIER wyvern", tag or "lod0", n, px, "bones", len(arm.data.bones))
    export(os.path.join(outdir, f"wyvern{tag}.glb"), [arm, mesh])
