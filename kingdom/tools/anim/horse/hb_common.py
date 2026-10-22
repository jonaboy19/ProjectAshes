# Shared constants for the horse pipeline (Blender 5.2 side).
# Horse faces -Y, +Z up, +X is the horse's LEFT (Rigify ".L" side). Metres. 30 fps.
# Exported to glTF (+Y up) the horse faces +Z, the same as the UAL characters in Godot.
import os

HERE = os.path.dirname(os.path.abspath(__file__))
KINGDOM = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
REPO = os.path.normpath(os.path.join(KINGDOM, ".."))
SRC_GLB = os.path.join(KINGDOM, "assets", "incoming", "characters", "mesh2motion", "horse-animations.glb")   # CC0 (Mesh2Motion)
OUT_DIR = os.path.join(KINGDOM, "assets", "generated", "horses")
BLEND = os.path.join(HERE, "source", "horse_rig.blend")
DOCS = os.path.join(REPO, "docs", "anim", "horses")
FPS = 30

# ------------------------------------------------------------------ game skeleton (own extraction of the Rigify DEF bones)
# (game bone, parent, [Rigify DEF bones merged head->tail], deform)
# 57 deform bones + sockets. Rigify splits limbs into twist halves (.001); the game skeleton merges them.
GAME_BONES = [
    ("root", None, None, False),
    ("hips", "root", ["DEF-spine.001"], True),
    ("spine_1", "hips", ["DEF-spine.002"], True),
    ("spine_2", "spine_1", ["DEF-spine.003"], True),
    ("spine_3", "spine_2", ["DEF-spine.004"], True),
    ("chest", "spine_3", ["DEF-spine.005"], True),
    ("withers", "chest", ["DEF-spine.006"], True),
    ("neck_1", "withers", ["DEF-neck.001"], True),
    ("neck_2", "neck_1", ["DEF-neck.002"], True),
    ("neck_3", "neck_2", ["DEF-neck.003"], True),
    ("neck_4", "neck_3", ["DEF-neck.004"], True),
    ("head", "neck_4", ["DEF-head"], True),
    ("jaw", "head", ["DEF-jaw", "DEF-jaw.001"], True),
    ("ear_1_L", "head", ["DEF-ear.L"], True),
    ("ear_2_L", "ear_1_L", ["DEF-ear.L.001"], True),
    ("ear_1_R", "head", ["DEF-ear.R"], True),
    ("ear_2_R", "ear_1_R", ["DEF-ear.R.001"], True),
    ("belly", "spine_2", ["DEF-chest"], True),
    ("tail_1", "hips", ["DEF-tail.001"], True),
    ("tail_2", "tail_1", ["DEF-tail.002"], True),
    ("tail_3", "tail_2", ["DEF-tail.003"], True),
    ("tail_4", "tail_3", ["DEF-tail.004"], True),
    ("tail_5", "tail_4", ["DEF-tail.005"], True),
]
for _i, (_n, _p) in enumerate((("06", "head"), ("01", "neck_4"), ("02", "neck_3"), ("03", "neck_2"), ("04", "neck_1"), ("05", "withers"))):
    # mane_0 = forelock (Rigify mane .06), mane_1..5 from the poll back to the withers
    GAME_BONES.append(("mane_%d_a" % _i, _p, ["DEF-mane_base.%s" % _n], True))
    GAME_BONES.append(("mane_%d_b" % _i, "mane_%d_a" % _i, ["DEF-mane_top.%s" % _n], True))
for S in ("L", "R"):
    GAME_BONES += [
        ("scapula_" + S, "chest", ["DEF-shoulder." + S], True),
        ("humerus_" + S, "scapula_" + S, ["DEF-upper_arm." + S, "DEF-upper_arm.%s.001" % S], True),
        ("forearm_" + S, "humerus_" + S, ["DEF-forearm." + S, "DEF-forearm.%s.001" % S], True),
        ("cannon_F_" + S, "forearm_" + S, ["DEF-forefoot." + S, "DEF-forefoot.%s.001" % S], True),
        ("pastern_F_" + S, "cannon_F_" + S, ["DEF-f_toe." + S], True),
        ("hoof_F_" + S, "pastern_F_" + S, ["DEF-f_hoof." + S], True),
        ("thigh_" + S, "hips", ["DEF-thigh." + S, "DEF-thigh.%s.001" % S], True),
        ("gaskin_" + S, "thigh_" + S, ["DEF-lower_leg." + S, "DEF-lower_leg.%s.001" % S], True),
        ("cannon_H_" + S, "gaskin_" + S, ["DEF-hind_foot." + S, "DEF-hind_foot.%s.001" % S], True),
        ("pastern_H_" + S, "cannon_H_" + S, ["DEF-r_toe." + S], True),
        ("hoof_H_" + S, "pastern_H_" + S, ["DEF-r_hoof." + S], True),
    ]
# Sockets: not in Rigify, placed from the fitted body (horse_build.place_sockets). rein_grip_* are deform (the reins mesh).
SOCKETS = [
    ("saddle", "spine_3", False),   # seat: top of the saddle where the rider's pelvis sits (rider root in Godot)
    ("stirrup_L", "saddle", False),          # stirrup tread centre (ball of the rider's foot)
    ("stirrup_R", "saddle", False),
    ("rein_grip_L", "withers", True),         # where the rider's hands hold the reins (reins mesh end, hand IK target)
    ("rein_grip_R", "withers", True),
    ("bit", "head", False),                   # bit ring centre (reins mesh start)
    ("tug_L", "spine_2", False),              # harness tugs (cart shafts)
    ("tug_R", "spine_2", False),
    ("cart_hitch", "hips", False),            # breeching point behind the hindquarters (cart pull reference)
]
DEFORM = [n for n, p, s, d in GAME_BONES if d] + [n for n, p, d in SOCKETS if d]

FRONT = ("scapula", "humerus", "forearm", "cannon_F", "pastern_F", "hoof_F")
HIND = ("thigh", "gaskin", "cannon_H", "pastern_H", "hoof_H")
