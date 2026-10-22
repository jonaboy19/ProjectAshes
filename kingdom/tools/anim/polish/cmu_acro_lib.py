# Shared helpers of the CMU-mocap acrobatics polish (numpy only, on top of glb_fk.py): dense clip sampling, contact points
# (soles, palms, head, torso, knees, elbows), floor analysis, contact segments and channel write-back.
# glTF space: +Y up, the character faces +Z. Root bone parent is the Armature node (identity); `root` carries the travel,
# `pelvis` is a child of root whose local frame is rotated -90 deg about X (local +Z = world up).
import os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from glb_fk import Rig, Glb, qmul, qconj, qnorm, qrot, qaxis, q_from_two, qslerp, clip_len, replace_channels, FPS  # noqa: E402

GLB = os.path.normpath(os.path.join(HERE, "../../../assets/incoming/animations_free/acrobatics/UAL_Free_Acrobatics.glb"))
UP = np.array([0, 1.0, 0])


class Clip:
    """dense (30 fps) local T/Q + world P/R of one clip"""

    def __init__(self, rig, chans, name=""):
        self.rig, self.name = rig, name
        self.nf = int(round(clip_len(chans) * FPS))
        self.T, self.Q = rig.dense(chans, self.nf)
        # channels that the clip really animates (translation only for root / pelvis)
        self.tracks = {(c["node"], c["path"]) for c in chans}
        self.P, self.R = rig.fk(self.T, self.Q)
        self._rest()

    def _rest(self):
        rig = self.rig
        P0, R0 = rig.fk(rig.rest_t[None], rig.rest_q[None])
        self.P0, self.R0 = P0[0], R0[0]

    def refk(self):
        self.P, self.R = self.rig.fk(self.T, self.Q)

    def pt(self, joint, rest_offset):
        """world position of a point fixed in a bone frame, defined by its offset in world axes at rest"""
        i = self.rig.idx[joint]
        loc = qrot(qconj(self.R0[i]), np.asarray(rest_offset, float))
        return self.P[:, i] + qrot(self.R[:, i], loc)

    # ---- named contact points (world, (F,3)); the floor is y = 0
    def points(self):
        I = self.rig.idx
        d = {}
        for s in "lr":
            d["toe_" + s] = self.P[:, I["ball_leaf_" + s]]
            d["ball_" + s] = self.P[:, I["ball_" + s]]
            d["heel_" + s] = self.pt("foot_" + s, (0, -0.10, -0.03))      # rest ankle is 0.104 above the sole
            d["palm_" + s] = self.pt("hand_" + s, (0, -0.03, 0))
            d["fing_" + s] = self.P[:, I["middle_04_leaf_" + s]]
            d["knee_" + s] = self.P[:, I["calf_" + s]]
            d["elbow_" + s] = self.P[:, I["lowerarm_" + s]]
        d["head"] = self.pt("Head", (0, 0.10, 0))
        d["chest"] = self.P[:, I["spine_03"]]
        d["belly"] = self.P[:, I["spine_01"]]
        d["pelvis"] = self.P[:, I["pelvis"]]
        return d

    RADIUS = {"toe": 0.0, "ball": 0.0, "heel": 0.0, "palm": 0.0, "fing": 0.0, "knee": 0.06, "elbow": 0.04, "head": 0.10,
              "chest": 0.10, "belly": 0.09, "pelvis": 0.10}

    def clearance(self):
        """dict name -> height minus radius (negative = below floor)"""
        return {k: v[:, 1] - self.RADIUS[k.split("_")[0]] for k, v in self.points().items()}

    def facing(self):
        """yaw of the pelvis facing (degrees, 0 = +Z, positive turns towards +X) from the hip line"""
        I = self.rig.idx
        d = self.P[:, I["thigh_l"]] - self.P[:, I["thigh_r"]]        # points to the character's left = +X when facing +Z? (l = +x at rest)
        return np.degrees(np.arctan2(-d[:, 2], d[:, 0]))

    def heading_torso(self):
        I = self.rig.idx
        d = self.P[:, I["clavicle_l"]] - self.P[:, I["clavicle_r"]]
        return np.degrees(np.arctan2(-d[:, 2], d[:, 0]))

    def pelvis_world(self):
        return self.P[:, self.rig.idx["pelvis"]]

    def root_world(self):
        return self.P[:, self.rig.idx["root"]]


def load(path=None):
    g = Glb(path or GLB)
    return g, Rig(g), g.anims()


def segments(mask, min_len=2):
    out, s = [], None
    for i, m in enumerate(list(mask) + [False]):
        if m and s is None:
            s = i
        if not m and s is not None:
            if i - s >= min_len:
                out.append((s, i - 1))
            s = None
    return out


def contact_segments(c, thr=0.045):
    """planted segments per end effector: (start, end, min_h, slide_max_m, speed_max_mps)"""
    pts = c.points()
    res = {}
    for eff, names in (("foot_l", ("toe_l", "ball_l", "heel_l")), ("foot_r", ("toe_r", "ball_r", "heel_r")),
                       ("hand_l", ("palm_l", "fing_l")), ("hand_r", ("palm_r", "fing_r"))):
        h = np.min([pts[n][:, 1] for n in names], axis=0)
        ref = pts[names[0] if eff.startswith("foot") else names[0]]
        segs = []
        for a, b in segments(h < thr, 2):
            # anchor = the lowest point of the effector, horizontal position of the palm / ball
            anc = pts["ball_" + eff[-1]] if eff.startswith("foot") else pts["palm_" + eff[-1]]
            xz = anc[a:b + 1][:, [0, 2]]
            slide = float(np.max(np.linalg.norm(xz - xz[0], axis=1)))
            sp = float(np.max(np.linalg.norm(np.diff(xz, axis=0), axis=1)) * FPS) if b > a else 0.0
            segs.append((a, b, round(float(h[a:b + 1].min()), 3), round(slide, 3), round(sp, 2)))
        res[eff] = segs
    return res
