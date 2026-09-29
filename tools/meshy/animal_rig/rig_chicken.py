"""Rig + animate a Meshy chicken (hen or rooster; the rooster is the hen scaled 1.2x).
blender -b --python rig_chicken.py -- <in.glb> <out.glb>
11 bones. Clips: idle, walk, eat (peck), flap."""
import bpy, sys, os, math, json
sys.path.insert(0, os.path.dirname(__file__))
from rig_lib import *

src, out = sys.argv[sys.argv.index('--') + 1:][:2]
reset(30)
mesh = import_mesh(src)
P = verts_np(mesh)
H = P[:, 2].max()
k = H / 0.499                              # hen height = 0.499 m
low = P[P[:, 2] < 0.05 * H]
xL = float(low[low[:, 0] > 0][:, 0].mean()); xR = float(low[low[:, 0] < 0][:, 0].mean())
print("leg x", xL, xR, "k", k)


def S(y, z):
    return (0, y * k, z * k)


def SX(x, y, z):
    return (x, y * k, z * k)


hipz, anklez = 0.17, 0.075
bones = [
    ('root', None, S(0.0, 0.0), S(0.0, 0.05)),
    ('body', 'root', S(0.05, 0.20), S(-0.08, 0.245)),
    ('neck', 'body', S(-0.08, 0.245), S(-0.115, 0.36)),
    ('head', 'neck', S(-0.115, 0.36), S(-0.155, 0.46)),
    ('tail', 'body', S(0.07, 0.24), S(0.17, 0.40)),
    ('wing_L', 'body', SX(0.085 * 1.0, -0.09, 0.27), SX(0.105, 0.07, 0.21)),
    ('wing_R', 'body', SX(-0.085, -0.09, 0.27), SX(-0.105, 0.07, 0.21)),
    ('leg_L_up', 'root', (xL, 0.02 * k, hipz * k), (xL, 0.02 * k, anklez * k)),
    ('leg_L_low', 'leg_L_up', (xL, 0.02 * k, anklez * k), (xL, -0.005 * k, 0.008 * k)),
    ('leg_R_up', 'root', (xR, 0.02 * k, hipz * k), (xR, 0.02 * k, anklez * k)),
    ('leg_R_low', 'leg_R_up', (xR, 0.02 * k, anklez * k), (xR, -0.005 * k, 0.008 * k)),
]
arm = build_armature('ChickenRig', bones)
skin_via_proxy(mesh, arm, float(os.environ.get("VOXEL", 0.009)) * k)
fill_orphans(mesh, arm)

# ---- weight fixes: legs only below the belly, wing patches from the wing bone, no feather-to-leg leaks
W, names = weights_np(mesh, arm)
ix = {n: i for i, n in enumerate(names)}
belly = 0.115 * k
for side, bx in (('L', 1), ('R', -1)):
    up, lo = ix['leg_%s_up' % side], ix['leg_%s_low' % side]
    wrongside = (P[:, 0] * bx) < -0.02 * k
    for j in (up, lo):
        W[wrongside, j] = 0
    above = P[:, 2] > belly + 0.02 * k
    for j in (up, lo):
        W[above, j] *= np.clip(1 - (P[above, 2] - belly - 0.02 * k) / (0.04 * k), 0, 1)
for side in ('L', 'R'):   # leg weights only inside the leg column (thin tail-tip verts must not follow the feet)
    far = (np.abs(P[:, 1] - 0.02 * k) > 0.09 * k) | (P[:, 2] > 0.2 * k)
    for n in ('leg_%s_up' % side, 'leg_%s_low' % side):
        W[far, ix[n]] = 0
for n in ('wing_L', 'wing_R'):   # wing bones only own the wing patch on the flank, not rump feathers or the low dangling one
    off = (P[:, 1] > 0.10 * k) | (P[:, 2] < 0.13 * k) | (np.abs(P[:, 0]) < 0.05 * k)
    W[off, ix[n]] = 0
tot = W.sum(1)
W[tot < 1e-6, ix['body']] = 1
set_weights(mesh, W, names)
report_weights(mesh, arm)

poser = Poser(arm)
legL, legR = Leg2(arm, 'leg_L_up', 'leg_L_low'), Leg2(arm, 'leg_R_up', 'leg_R_low')
DEG = math.pi / 180
FWD = -1.0                                  # forward is -Y


def keys(t, pts):
    """periodic smooth interpolation through (t, value) keys, t in 0..1, first == last value"""
    for (t0, v0), (t1, v1) in zip(pts[:-1], pts[1:]):
        if t0 <= t <= t1:
            u = (t - t0) / max(t1 - t0, 1e-9)
            return v0 + (v1 - v0) * smooth(u)
    return pts[-1][1]


def legs(dz_hip=0.0, tgt=None, phase=None, stride=0, lift=0, duty=0.6, hang=0.0):
    for leg, ph in ((legL, 0.0), (legR, 0.5)):
        dy = dz = 0.0
        if phase is not None:
            dy, dz = foot_cycle(phase + ph, duty, stride, lift)
        F = leg.F0 + np.array([FWD * dy, dz + hang])
        leg.solve(poser, F)


def idle(t, f):
    breath = math.sin(2 * math.pi * t * 3)
    poser.move('root', (0, 0, 0.0025 * k * breath))
    poser.scale('body', 1 + 0.012 * breath)
    poser.rot('body', 'x', 1.0 * DEG * breath)
    yaw = keys(t, [(0, 0), (.12, 0), (.22, 28 * DEG), (.40, 28 * DEG), (.48, -8 * DEG), (.60, -22 * DEG), (.80, -22 * DEG), (.90, 0), (1, 0)])
    poser.rot('neck', 'z', yaw * 0.6)
    poser.rot('head', 'z', yaw * 0.5)
    pit = keys(t, [(0, 0), (.15, 0), (.20, 6 * DEG), (.25, -4 * DEG), (.30, 0), (.6, 0), (.66, 7 * DEG), (.72, 0), (1, 0)])
    poser.rot('head', 'x', pit)
    poser.rot('tail', 'x', 2.5 * DEG * math.sin(2 * math.pi * t * 3 + 1))
    poser.rot('tail', 'z', keys(t, [(0, 0), (.45, 0), (.5, 8 * DEG), (.55, -6 * DEG), (.6, 0), (1, 0)]))
    poser.apply()
    legs()


def walk(t, f):
    duty = 0.6
    bob = 0.006 * k * math.cos(4 * math.pi * t)
    poser.move('root', (0, 0, bob))
    poser.rot('body', 'y', 3.5 * DEG * math.sin(2 * math.pi * t))
    poser.rot('body', 'x', 2 * DEG * math.cos(4 * math.pi * t))
    # head-bob: neck thrust forward then held (chicken head stays still in world while the body moves)
    thrust = math.sin(2 * math.pi * t + 0.6)
    poser.rot('neck', 'x', -10 * DEG * thrust)
    poser.rot('head', 'x', 8 * DEG * thrust)
    poser.rot('tail', 'x', 4 * DEG * math.sin(4 * math.pi * t))
    poser.rot('tail', 'z', 5 * DEG * math.sin(2 * math.pi * t))
    poser.apply()
    legs(phase=t, stride=0.11 * k, lift=0.035 * k, duty=duty)


def eat(t, f):
    # two pecks: 0-0.1 wind-up, strike, hold on the ground, rise; second peck a bit later
    dip = keys(t, [(0, 0), (.06, 0.25), (.14, 1), (.22, 0.45), (.30, 1), (.38, 0.5), (.52, 0), (.62, 0), (.68, 0.3), (.76, 1), (.84, 0.5), (.92, 0), (1, 0)])
    body = 34 * DEG * dip
    poser.rot('body', 'x', body)
    poser.rot('neck', 'x', 52 * DEG * dip)
    poser.rot('head', 'x', 30 * DEG * dip)
    poser.rot('tail', 'x', -18 * DEG * dip)
    poser.move('root', (0, 0, -0.004 * k * dip))
    poser.rot('neck', 'z', 6 * DEG * math.sin(2 * math.pi * t * 2))
    poser.apply()
    legs()


def flap(t, f):
    n = 3
    ph = (t * n) % 1.0
    up = 0.5 - 0.5 * math.cos(2 * math.pi * ph)         # 0 = wings down, 1 = wings up
    hop = 0.05 * k * (0.5 + 0.5 * math.sin(2 * math.pi * (ph - 0.25)))
    poser.move('root', (0, 0, hop))
    poser.rot('body', 'x', -12 * DEG * (0.6 + 0.4 * up))          # chest up, tail down
    for w, side in (('wing_L', 1), ('wing_R', -1)):
        a = (-1 if side > 0 else 1) * (6 + 92 * up) * DEG        # hinge along the top edge: lower edge swings outward
        poser.rot(w, 'y', a)
        poser.rot(w, 'z', side * -8 * DEG * up)
    poser.rot('neck', 'x', -8 * DEG)
    poser.rot('head', 'x', 6 * DEG * up)
    poser.rot('tail', 'x', 15 * DEG * up)
    poser.apply()
    legs(hang=0.07 * k * (0.4 + 0.6 * math.sin(math.pi * ph)))   # feet lift off, dangle


clips = [('idle', 96, idle), ('walk', 20, walk), ('eat', 60, eat), ('flap', 30, flap)]
for name, n, fn in clips:
    author_clip(arm, poser, name, n, fn)
bpy.context.scene.frame_end = 96
os.makedirs(os.path.dirname(out), exist_ok=True)
export_glb(mesh, arm, out)
stride = 0.11 * k
print("RIGGED", out, "bones", len(arm.data.bones), "walk speed m/s", stride / (0.6 * 20 / 30))
json.dump({'bones': len(arm.data.bones), 'walk_speed_mps': stride / (0.6 * 20 / 30), 'fps': 30,
           'clips': {n: nn for n, nn, _ in clips}}, open(out.replace('.glb', '.json'), 'w'))
poser.clear(); eat(0.14, 0); poser.apply()
print("PECK head tip", [round(x, 3) for x in arm.pose.bones['head'].tail], "(beak is ~0.04 further forward, comb above)")
