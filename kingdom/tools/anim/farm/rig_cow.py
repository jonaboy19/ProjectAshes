"""Rig + animate a Meshy cow. 21 bones. Clips: idle, walk, eat (graze).
blender -b --python rig_cow.py -- <in.glb> <out.glb> [part]      part = 0|1 splits cows_pair (the two cows are separate meshes, x<0 / x>0)
Template coordinates come from cow_spotted_lod0 (1.395 m tall, 1.48 m long, facing -Y); other cows are scaled/aligned onto it."""
import bpy, sys, os, math, json
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "tools", "meshy", "animal_rig"))
from rig_lib import *

a = sys.argv[sys.argv.index('--') + 1:]
src, out = a[0], a[1]
part = int(a[2]) if len(a) > 2 else None
reset(30)
mesh = import_mesh(src)
P = verts_np(mesh)
if part is not None:                      # split cows_pair
    keep = (P[:, 0] < 0) if part == 0 else (P[:, 0] >= 0)
    keep_verts(mesh, keep)
    P = verts_np(mesh)
    # drop the stray specks the split leaves behind (verts with no neighbours nearby)
    from mathutils.kdtree import KDTree
    kd = KDTree(len(P))
    for i, p_ in enumerate(P):
        kd.insert(Vector(p_), i)
    kd.balance()
    isolated = np.array([np.mean([d for _, _, d in kd.find_n(Vector(p_), 6)][1:]) > 0.12 for p_ in P])
    print("specks removed", int(isolated.sum()))
    keep_verts(mesh, ~isolated)
    P = verts_np(mesh)

# ---- align: principal axis -> Y, head (highest point) toward -Y, feet on z=0, centred under the body
xy = P[:, :2] - P[:, :2].mean(0)
best = (1e9, 0.0)
for deg in np.arange(-89, 90, 1.0):                      # minimum-area bounding box -> body axis (PCA is skewed by head/legs)
    t_ = math.radians(deg)
    r_ = np.array([[math.cos(t_), -math.sin(t_)], [math.sin(t_), math.cos(t_)]])
    q = xy @ r_.T
    area = np.ptp(q[:, 0]) * np.ptp(q[:, 1])
    if area < best[0] - 1e-9:
        best = (area, t_)
rz = best[1]
r_ = np.array([[math.cos(rz), -math.sin(rz)], [math.sin(rz), math.cos(rz)]])
q = xy @ r_.T
if np.ptp(q[:, 0]) > np.ptp(q[:, 1]):                    # long axis must be Y
    rz += math.pi / 2
    r_ = np.array([[math.cos(rz), -math.sin(rz)], [math.sin(rz), math.cos(rz)]])
    q = xy @ r_.T
P2 = P.copy()
P2[:, :2] = q
top = P2[P2[:, 2].argmax()]
if top[1] > 0:                                           # head (highest point) must face -Y
    rz += math.pi
print("align yaw deg", math.degrees(rz))
offset_mesh(mesh, Vector((0, 0, 0)), rz)                 # rotation about the origin
P = verts_np(mesh)
lowmask = P[:, 2] < 0.03 * P[:, 2].max()
low = P[lowmask]
cx = 0.5 * (P[:, 0].min() + P[:, 0].max())
cy = 0.5 * (P[:, 1].min() + P[:, 1].max())
offset_mesh(mesh, Vector((-cx, -cy, -P[:, 2].min())))
P = verts_np(mesh)
H = P[:, 2].max()
def feet_of(P):
    low = P[P[:, 2] < 0.05 * P[:, 2].max()]
    ymid = 0.5 * (low[:, 1].min() + low[:, 1].max())
    g = lambda c: low[c].mean(axis=0)
    return (g((low[:, 1] < ymid) & (low[:, 0] > 0)), g((low[:, 1] < ymid) & (low[:, 0] <= 0)),
            g((low[:, 1] >= ymid) & (low[:, 0] > 0)), g((low[:, 1] >= ymid) & (low[:, 0] <= 0)))


for _ in range(2):                                        # refine heading so the two leg lines run parallel to Y
    fl, fr, hl, hr = feet_of(P)
    d = 0.5 * (math.atan2((hl - fl)[0], (hl - fl)[1]) + math.atan2((hr - fr)[0], (hr - fr)[1]))
    print("feet heading error deg", math.degrees(d))
    offset_mesh(mesh, Vector((0, 0, 0)), d)
    P = verts_np(mesh)
fl, fr, hl, hr = feet_of(P)
offset_mesh(mesh, Vector((-0.25 * (fl[0] + fr[0] + hl[0] + hr[0]), -0.5 * P[:, 1].min() - 0.5 * P[:, 1].max(), 0)))
P = verts_np(mesh)
H = P[:, 2].max()
ymin, ymax = P[:, 1].min(), P[:, 1].max()
s = H / 1.395
print("scale vs template", s, "size", P.max(0) - P.min(0))
low = P[P[:, 2] < 0.05 * H]
ymid = 0.5 * (low[:, 1].min() + low[:, 1].max())
FX = {}
for key, cond in (('FL', (low[:, 1] < ymid) & (low[:, 0] > 0)), ('FR', (low[:, 1] < ymid) & (low[:, 0] <= 0)),
                  ('HL', (low[:, 1] >= ymid) & (low[:, 0] > 0)), ('HR', (low[:, 1] >= ymid) & (low[:, 0] <= 0))):
    FX[key] = low[cond].mean(axis=0)
print("feet", {k: v.round(3) for k, v in FX.items()})
fyF = 0.5 * (FX['FL'][1] + FX['FR'][1])
fyH = 0.5 * (FX['HL'][1] + FX['HR'][1])


def Y(yt):   # template y -> this mesh, piecewise-linear between head end / front feet / hind feet / rump
    return float(np.interp(yt, [-0.739, -0.245, 0.475, 0.738], [ymin, fyF, fyH, ymax]))


def T(x, y, z):
    return (x * s, Y(y), z * s)


bones = [
    ('root', None, (0, Y(0.1), 0), (0, Y(0.1), 0.12 * s)),
    ('pelvis', 'root', T(0, .50, .83), T(0, .15, .85)),
    ('chest', 'pelvis', T(0, .15, .85), T(0, -.30, .90)),
    ('neck', 'chest', T(0, -.30, .90), T(0, -.50, 1.06)),
    ('head', 'neck', T(0, -.50, 1.06), T(0, -.72, .93)),
    ('ear_L', 'head', T(.10, -.58, 1.20), T(.32, -.60, 1.24)),
    ('ear_R', 'head', T(-.10, -.58, 1.20), T(-.32, -.60, 1.24)),
    ('tail1', 'pelvis', T(0, .68, 1.02), T(0, .72, .70)),
    ('tail2', 'tail1', T(0, .72, .70), T(0, .72, .30)),
]
legnames = []
for key, par in (('FL', 'chest'), ('FR', 'chest'), ('HL', 'pelvis'), ('HR', 'pelvis')):
    x = FX[key][0]
    fy = FX[key][1]
    if key[0] == 'F':
        pts = [(fy + .03 * s, .82 * s), (fy - .02 * s, .42 * s), (fy, .10 * s)]
    else:
        pts = [(fy + .03 * s, .86 * s), (fy + .10 * s, .43 * s), (fy, .10 * s)]
    bones += [(key + '_up', par, (x, pts[0][0], pts[0][1]), (x, pts[1][0], pts[1][1])),
              (key + '_low', key + '_up', (x, pts[1][0], pts[1][1]), (x, pts[2][0], pts[2][1])),
              (key + '_hoof', key + '_low', (x, pts[2][0], pts[2][1]), (x, pts[2][0] - 0.0, 0.004))]
    legnames.append(key)
arm = build_armature('CowRig', bones)
os.environ.setdefault("BONE_SLACK", "4")
skin_via_proxy(mesh, arm, 0.02 * s)
fill_orphans(mesh, arm)

# ---- weight fixes -------------------------------------------------------------------
W, names = weights_np(mesh, arm)
ix = {n: i for i, n in enumerate(names)}
for key in legnames:
    xk = FX[key][0]
    yk = FX[key][1]
    cols = [ix[key + '_up'], ix[key + '_low'], ix[key + '_hoof']]
    bad = (np.abs(P[:, 0] - xk) > 0.20 * s) | (np.abs(P[:, 1] - yk) > 0.30 * s) | (P[:, 2] > 0.95 * s)
    for j in cols:
        W[bad, j] = 0
    # low parts (hoof/fetlock) only for the low verts
    for j in (ix[key + '_hoof'],):
        W[P[:, 2] > 0.2 * s, j] = 0
# tail bones only around the tail (x near 0, behind the rump, hanging)
rear = (P[:, 1] > Y(0.60)) & (np.abs(P[:, 0]) < 0.12 * s) & (P[:, 2] > 0.25 * s) & (P[:, 2] < 1.1 * s)
for n in ('tail1', 'tail2'):
    W[~rear, ix[n]] = 0
# ears only near the head sides
for n, sg in (('ear_L', 1), ('ear_R', -1)):
    near = dist_to_seg(P, *bone_seg(arm, n)) < 0.22 * s
    W[~near, ix[n]] = 0
# head: everything in front of the poll and above the jaw line belongs to the head bone (horns, hair tuft, muzzle); blend into the neck behind
yh0, yh1 = Y(-0.56), Y(-0.44)
hz = P[:, 2] > 0.80 * s
u = np.clip((yh1 - P[:, 1]) / (yh1 - yh0), 0, 1)
for j in range(W.shape[1]):
    pass
for i in np.where(hz & (P[:, 1] < yh1))[0]:
    ear = W[i, ix['ear_L']] + W[i, ix['ear_R']]
    keep = W[i, [ix['ear_L'], ix['ear_R']]].copy()
    W[i, :] = 0
    W[i, ix['head']] = u[i] * (1 - ear)
    W[i, ix['neck']] = (1 - u[i]) * (1 - ear)
    W[i, [ix['ear_L'], ix['ear_R']]] = keep
# verts behind the neck pivot must not follow the neck (they would flip up as a plank when the head goes down)
fac = np.clip((Y(-0.20) - P[:, 1]) / (Y(-0.20) - Y(-0.30)), 0, 1)
moved = W[:, ix['neck']] * (1 - fac)
W[:, ix['neck']] -= moved
W[:, ix['chest']] += moved
tot = W.sum(1)
W[tot < 1e-6, ix['chest']] = 1
set_weights(mesh, W, names)
report_weights(mesh, arm)

poser = Poser(arm)
legs = {k: Leg2(arm, k + '_up', k + '_low') for k in legnames}
DEG = math.pi / 180
FWD = -1.0


def keys(t, pts):
    for (t0, v0), (t1, v1) in zip(pts[:-1], pts[1:]):
        if t0 <= t <= t1:
            return v0 + (v1 - v0) * smooth((t - t0) / max(t1 - t0, 1e-9))
    return pts[-1][1]


def do_legs(phase=None, offs=None, stride=0, lift=0, duty=0.7, targets=None):
    for key in legnames:
        lg = legs[key]
        dy = dz = 0.0
        if phase is not None:
            dy, dz = foot_cycle(phase + offs[key], duty, stride, lift)
        F = lg.F0 + np.array([FWD * dy, dz])
        d1, d2 = lg.solve(poser, F)
        # FIX (farm anim polish): the solver returns absolute world angles, but the parent (pelvis/chest) pitch is already
        # applied on top of the local rotation, so subtract it or the feet miss their ground targets while the body pitches.
        par = arm.pose.bones[key + '_up'].parent
        R = par.matrix.to_3x3() @ arm.data.bones[par.name].matrix_local.to_3x3().inverted()
        pitch = math.atan2(R[2][1], R[1][1])
        poser.rot(key + '_up', 'x', -pitch)
        # keep the hoof flat on the ground during stance, curl it a little while lifted
        poser.rot(key + '_hoof', 'x', -(d1 + d2) + (18 * DEG * (dz / max(lift, 1e-6)) if lift else 0))


def idle(t, f):
    br = math.sin(2 * math.pi * t * 2)
    poser.move('root', (0, 0, 0.004 * s * br))
    poser.scale('chest', 1 + 0.010 * br)
    poser.rot('chest', 'x', 0.8 * DEG * br)
    yaw = keys(t, [(0, 0), (.10, 0), (.24, 24 * DEG), (.42, 24 * DEG), (.55, -3 * DEG), (.68, -20 * DEG), (.86, -20 * DEG), (.96, 0), (1, 0)])
    poser.rot('neck', 'z', yaw * .6)
    poser.rot('head', 'z', yaw * .5)
    poser.rot('head', 'x', keys(t, [(0, 0), (.3, 0), (.42, 6 * DEG), (.55, 0), (.7, 0), (.8, -5 * DEG), (.9, 0), (1, 0)]))
    poser.rot('neck', 'x', 2 * DEG * br)
    e = keys(t, [(0, 0), (.30, 0), (.33, 1), (.38, -0.3), (.42, 0), (.75, 0), (.78, 1), (.83, -.3), (.87, 0), (1, 0)])
    poser.rot('ear_L', 'z', 18 * DEG * e)
    poser.rot('ear_R', 'z', -8 * DEG * math.sin(2 * math.pi * t * 2 + 1) * 0.5)
    sw = math.sin(2 * math.pi * t) * 0.6 + math.sin(2 * math.pi * t * 2 + 1) * 0.4
    poser.rot('tail1', 'y', 9 * DEG * sw)
    poser.rot('tail2', 'y', 14 * DEG * math.sin(2 * math.pi * t - 0.8))
    poser.apply()
    do_legs()


WALK_N, WALK_DUTY, WALK_STRIDE = 42, 0.70, 0.62 * s
PH = {'HL': 0.0, 'FL': 0.25, 'HR': 0.5, 'FR': 0.75}


def walk(t, f):
    ph = 2 * math.pi * t
    poser.move('root', (0, 0, 0.012 * s * math.cos(4 * ph) - 0.004 * s))
    poser.rot('pelvis', 'z', 2.5 * DEG * math.sin(ph))
    poser.rot('chest', 'z', -3.5 * DEG * math.sin(ph))
    poser.rot('pelvis', 'y', 1.5 * DEG * math.sin(ph))
    poser.rot('pelvis', 'x', 1.0 * DEG * math.sin(2 * ph))
    poser.rot('neck', 'x', 5 * DEG * math.sin(2 * ph - 0.6))
    poser.rot('head', 'x', -3 * DEG * math.sin(2 * ph - 1.0))
    poser.rot('head', 'z', 4 * DEG * math.sin(ph + 0.5))
    poser.rot('ear_L', 'z', 6 * DEG * math.sin(2 * ph))
    poser.rot('ear_R', 'z', -6 * DEG * math.sin(2 * ph + 1))
    poser.rot('tail1', 'y', 10 * DEG * math.sin(ph - 0.5))
    poser.rot('tail2', 'y', 16 * DEG * math.sin(ph - 1.4))
    poser.apply()
    do_legs(phase=t, offs=PH, stride=WALK_STRIDE, lift=0.11 * s, duty=WALK_DUTY)


PP, CP, NP, HP, NS, DROP = 14.0, 6.0, 62.0, 30.0, 1.0, 0.0


def eat_pose(m, tear=0.0):
    poser.rot('pelvis', 'x', PP * DEG * m)                 # front dips about the hind hips; front legs bend by IK
    poser.rot('chest', 'x', CP * DEG * m)
    poser.rot('neck', 'x', NP * DEG * m + 6 * DEG * tear)
    poser.rot('head', 'x', HP * DEG * m - 10 * DEG * tear)
    poser.scale('neck', (1, 1 + (NS - 1) * m, 1))          # the neck reaches down (this cow's neck is short)


def eat(t, f):
    # lower -> tear grass x3 (chomp sideways/forward) -> raise -> chew with head up -> settle
    m = keys(t, [(0, 0), (.14, 1), (.52, 1), (.66, 0), (1, 0)])
    tear = 0.0
    if .16 < t < .50:
        u = (t - .16) / .34
        tear = max(0.0, math.sin(2 * math.pi * u * 3)) * 1.0
    chew = math.sin(2 * math.pi * t * 9) if (.62 < t < .96) else 0.0
    eat_pose(m, tear)
    poser.rot('head', 'x', 3.5 * DEG * chew)
    poser.rot('head', 'z', 2.5 * DEG * math.sin(2 * math.pi * t * 4.5) * (0.4 + 0.6 * m))
    poser.move('root', (0, 0, -(0.006 + DROP) * s * m))
    poser.rot('ear_L', 'z', 9 * DEG * math.sin(2 * math.pi * t * 3))
    poser.rot('ear_R', 'z', -9 * DEG * math.sin(2 * math.pi * t * 3 + 1.5))
    poser.rot('tail1', 'y', 12 * DEG * math.sin(2 * math.pi * t * 2))
    poser.rot('tail2', 'y', 16 * DEG * math.sin(2 * math.pi * t * 2 - 1))
    poser.rot('chest', 'z', 1.5 * DEG * math.sin(2 * math.pi * t * 2))
    poser.apply()
    do_legs()


# ---- FIX: solve the grazing dip on the SKINNED MESH so the muzzle reaches the grass (old script used the head bone tail,
# which is ~20 cm above the real muzzle). Muzzle = front 12 cm of the verts owned by the head bone.
_Wn, _nm = weights_np(mesh, arm)
_hv = np.where(_Wn[:, _nm.index('head')] > 0.4)[0]
MUZ = _hv[P[_hv, 1] < P[_hv, 1].min() + 0.12]


def muzzle_z():
    dg = bpy.context.evaluated_depsgraph_get()
    ev = mesh.evaluated_get(dg)
    me = ev.to_mesh()
    n_ = len(me.vertices)
    a_ = np.empty(n_ * 3)
    me.vertices.foreach_get('co', a_)
    ev.to_mesh_clear()
    return float(a_.reshape(n_, 3)[MUZ][:, 2].min())


GRASS_Z = float(os.environ.get("GRASS_Z", 0.045))       # muzzle rests ~4.5 cm above the ground (grass blades reach it)
# base dip tuned on the spotted cow (muzzle 3 cm above ground); every cow bisects one intensity g on its own skinned mesh
BASE = dict(PP=21.0, CP=8.0, NP=79.0, HP=55.0, NS=0.27, DROP=0.03)
lo, hi = 0.2, 1.4
for _ in range(14):
    g = 0.5 * (lo + hi)
    PP, CP, NP, HP, NS, DROP = (BASE['PP'] * g, BASE['CP'] * g, BASE['NP'] * g, BASE['HP'] * g, 1 + BASE['NS'] * g, BASE['DROP'] * g)
    poser.clear(); eat(0.16, 0); poser.apply()
    mz = muzzle_z()
    if mz > GRASS_Z: lo = g
    else: hi = g
print("GRAZE g %.3f: pelvis %.1f chest %.1f neck %.1f head %.1f neck scale %.2f drop %.3f -> muzzle z %.3f" % (g, PP, CP, NP, HP, NS, DROP, mz))

clips = [('idle', 120, idle), ('walk', WALK_N, walk), ('eat', 150, eat)]
for name, n, fn in clips:
    author_clip(arm, poser, name, n, fn)
os.makedirs(os.path.dirname(out), exist_ok=True)
export_glb(mesh, arm, out)
speed = WALK_STRIDE / (WALK_DUTY * WALK_N / 30)
print("RIGGED", out, "bones", len(arm.data.bones), "walk speed m/s", speed)
json.dump({'bones': len(arm.data.bones), 'walk_speed_mps': speed, 'fps': 30, 'clips': {n: nn for n, nn, _ in clips}}, open(out.replace('.glb', '.json'), 'w'))
