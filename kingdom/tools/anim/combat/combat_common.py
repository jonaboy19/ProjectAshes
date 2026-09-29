# Shared helpers for the combat clip modules (combat_clips_*.py), used by author_combat.py.
# World axes (Blender armature space): character faces -Y, +Z up, +X = character's LEFT. 30 fps.
# Feet are IK-pinned (ankle targets): a foot never moves unless a key moves it.
#
# The animation skeleton every combat clip follows (principles, not poses):
#   anticipation (weight shift opposite to the action, 4-12 f, slow-in) -> short moving hold (1-3 f) ->
#   snap (2-4 f, "in" easing, hips lead the chest lead the arm lead the hand/blade) -> CONTACT (2-4 f fastest) ->
#   overshoot (2-4 f past the extreme, "out" easing) -> follow-through (secondary drift, 6-12 f) -> recovery (to idle).
# Arcs: keys carry "_bow" offsets so hands/blades travel on curves, never on straight lines.
import math, types, random
from mathutils import Vector, Quaternion, Matrix

F = None


def init(g):
    global F
    F = types.SimpleNamespace(**g)


def V(x, y, z):
    return Vector((x, y, z))


CLIPS = {}


def clip(name, loop=False, events=None, note="", root_motion_m=0.0):
    def deco(fn):
        CLIPS[name] = {"poses": fn, "loop": loop, "events": events or {}, "note": note, "root_motion_m": root_motion_m}
        return fn
    return deco


TAU = 2 * math.pi


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def stance(lx=0.15, ly=0.0, rx=-0.15, ry=0.10, yl=8.0, yr=-15.0):
    """ankle targets: +x = left, -y = forward"""
    return {"foot_l": V(lx, ly, 0.104), "foot_r": V(rx, ry, 0.104), "fyaw_l": yl, "fyaw_r": yr}


def add(s, key, dv):
    s[key] = Vector(s[key]) + Vector(dv)


def addt(s, key, d):
    s[key] = tuple(a + b for a, b in zip(s[key], d))


def rel(out, fwd, z, yaw=0.0, pel=(0.0, 0.0)):
    """world point in the torso frame: `out` m to the character's left, `fwd` m in front of the spine axis, height z;
    yaw = torso yaw (deg, left +), pel = pelvis xy offset"""
    a = math.radians(yaw)
    x = out * math.cos(a) + fwd * math.sin(a)
    y = out * math.sin(a) - fwd * math.cos(a)
    return V(pel[0] + x, 0.065 + pel[1] + y, z)


def TF(out, fwd, up, yaw=0.0):
    """direction in the torso frame (left, forward, up) -> world"""
    a = math.radians(yaw)
    return (out * math.cos(a) + fwd * math.sin(a), out * math.sin(a) - fwd * math.cos(a), up)


def shake(fr, seed, amp=1.0, every=1, dim=3):
    """deterministic stepped noise for impact tremor"""
    rng = random.Random(seed * 1000 + fr // every)
    return Vector([rng.uniform(-1, 1) * amp for _ in range(dim)])


# ---------------------------------------------------------------- weapon orientation
# The game attaches the sword to hand_r (Assets._attach: offset (0.05,0.02,0), rotation (0,0,-90) in the bone's space).
# BLADE_REST = blade axis (grip -> tip) and blade flat normal in Blender world axes with the skeleton in its REST pose
# (T-pose), measured in Godot by tools_qa/combat_audit/combat_studio.gd --probe and converted (x, -z, y).
# F.hand_q keys a hand as R @ rest_hand, with R mapping the rest fingers f0 = (-1,0,0) / palm n0 = (0,0,-1) (right hand)
# to the keyed ones, so the blade follows the same R.
BLADE_REST = {"axis": (0.0, 0.0, 1.0), "flat": (0.0, -1.0, 0.0)}   # measured 2026-09-30: T-pose blade straight up, flat facing forward


def set_blade_rest(axis, flat):
    BLADE_REST["axis"] = tuple(axis)
    BLADE_REST["flat"] = tuple(flat)


def _frame(a, b):
    a = Vector(a).normalized()
    b = Vector(b)
    b = (b - a * b.dot(a)).normalized()
    c = a.cross(b)
    return Matrix(((a.x, b.x, c.x), (a.y, b.y, c.y), (a.z, b.z, c.z)))


def blade_o(blade_dir, flat_normal):
    """key value for ho_r: the sword points along blade_dir (world) with its flat facing flat_normal
    (for a slash: flat_normal = swing-plane normal, so the edge leads)."""
    Bh = _frame(BLADE_REST["axis"], BLADE_REST["flat"])
    Bw = _frame(blade_dir, flat_normal)
    R = Bw @ Bh.inverted()
    f = R @ Vector((-1, 0, 0))
    n = R @ Vector((0, 0, -1))
    return (tuple(f), tuple(n))
