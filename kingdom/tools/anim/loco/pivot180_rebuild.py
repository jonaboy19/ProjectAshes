"""Rebuild the middle of Loco_Pivot180_Run_L / _R (UAL_Loco_Transitions.glb) - pure python + numpy, no Blender.

The two clips are stitched from three CMU takes (brake -> spin on the spot -> first strides back). The stitched middle is stiff: the torso
is carried rigidly by the pelvis, the pivot foot drifts a few cm while the body spins over it, and the swing foot lands 25 cm away from
where it stays. This script keeps the clip names, the start / end poses (overlays fade to zero before the last frames), the root track
(root motion) and every other clip of the library byte-identical in content, and rewrites the rotation channels of the body bones:

  1. PLANT   the pivot foot (the outside foot: right for the left-turn clip) is locked in world space (ball of the foot) for the whole spin
             while the foot yaw follows the body (pivots on the ball); the push-off foot lands directly on its final spot (no slide) and is
             locked until it pushes off. Both legs are solved with an analytic two-bone IK (the pole is the knee of the source pose).
  2. LEAN    the torso leans into the turn (roll toward the inside, up to LEAN_ROLL degrees) while the hips lead the heading (pelvis yaw ahead
             of the root yaw, up to HIP_LEAD degrees) and the spine counter-rotates (shoulders lag), the head looks ahead into the exit.
  3. PUSH    after the spin the opposite leg pushes off and the torso pitches forward (up to PUSH_PITCH degrees) into the run; everything
             fades to the original over the last frames so the clip still hands over to Jog_Fwd_Loop exactly as before.

  usage: python pivot180_rebuild.py <UAL_Loco_Transitions.glb> [--report out.json]
"""
import os, sys, json, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glb_fk as F

HIP_LEAD = 26.0        # degrees, pelvis heading ahead of the root heading at the middle of the spin
COUNTER = 1.25         # spine counter-rotation as a multiple of the hip lead (shoulders lag the hips)
HEAD_LEAD = 32.0       # degrees the head looks into the exit direction before the shoulders
LEAN_ROLL = 11.0       # degrees of lean into the turn (centripetal)
PUSH_PITCH = 13.0      # degrees of forward lean while pushing off into the run
FOOT_YAW_FOLLOW = 0.85  # share of the body yaw the pivot foot follows (pivot on the ball)

# per clip: frames of the turn (source yaw goes from y0 to y1), the pivot foot and the push-off foot
CLIPS = {
    "Loco_Pivot180_Run_L": dict(sign=1.0, turn=(6, 21), pivot=("r", 7, 19), pivot_ref=(8, 12), push=("l", 16, 21, 26, 31), push_ref=25,
                                push_lean=(21, 34), window=(3, 34)),
    "Loco_Pivot180_Run_R": dict(sign=-1.0, turn=(10, 24), pivot=("l", 13, 23), pivot_ref=(14, 22), push=("r", 19, 23, 29, 34), push_ref=28,
                                push_lean=(24, 38), window=(6, 38)),
}
UP = np.array([0.0, 1.0, 0.0])


def smooth(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3 - 2 * t)


def ramp(f, a0, a1, b0, b1):
    """0 before a0, smooth up to 1 at a1, 1 until b0, smooth down to 0 at b1"""
    if f <= a0 or f >= b1:
        return 0.0
    if f < a1:
        return smooth((f - a0) / float(a1 - a0))
    if f <= b0:
        return 1.0
    return 1.0 - smooth((f - b0) / float(b1 - b0))


class Body:
    """per-frame state: local rotations R (n,4) / translations T (n,3); helpers around the rig"""

    def __init__(self, rig, T, R):
        self.rig, self.T, self.R = rig, T.copy(), R.copy()
        self.update()

    def update(self):
        self.P, self.Q = self.rig.fk(self.T, self.R)

    def id(self, name):
        return self.rig.idx[name]

    def basis(self):
        i = self.rig.idx
        left = self.P[i["thigh_l"]] - self.P[i["thigh_r"]]
        left[1] = 0.0
        left = left / np.linalg.norm(left)
        fwd = np.cross(left, UP)
        return left, fwd

    def yaw(self):
        _, fwd = self.basis()
        return math.atan2(fwd[0], fwd[2])

    def world_rot(self, name, Rw):
        """rotate the node about its own origin by the world rotation Rw (children follow)"""
        i = self.id(name)
        p = self.rig.parent[i]
        Qp = self.Q[p] if p >= 0 else np.array([0, 0, 0, 1.0])
        self.R[i] = F.qnorm(F.qmul(F.qinv(Qp), F.qmul(Rw, F.qmul(Qp, self.R[i]))))
        self.update()

    def set_world_rot(self, name, W):
        i = self.id(name)
        p = self.rig.parent[i]
        Qp = self.Q[p] if p >= 0 else np.array([0, 0, 0, 1.0])
        self.R[i] = F.qnorm(F.qmul(F.qinv(Qp), W))
        self.update()

    def leg_ik(self, side, ankle_T, foot_W):
        """two-bone IK: put the ankle (foot node origin) on ankle_T, foot world rotation = foot_W. Returns the reach error (m)."""
        i = self.rig.idx
        th, ca, fo = i["thigh_" + side], i["calf_" + side], i["foot_" + side]
        hip, knee, ank = self.P[th].copy(), self.P[ca].copy(), self.P[fo].copy()
        l1, l2 = np.linalg.norm(knee - hip), np.linalg.norm(ank - knee)
        axis = ankle_T - hip
        d = np.linalg.norm(axis)
        err = 0.0
        if d > (l1 + l2) * 0.998:
            err = d - (l1 + l2) * 0.998
            axis = axis / d * (l1 + l2) * 0.998
            d = np.linalg.norm(axis)
            ankle_T = hip + axis
        an = axis / d
        cur = (ank - hip) / np.linalg.norm(ank - hip)
        kperp = (knee - hip) - cur * np.dot(knee - hip, cur)
        pole = kperp - an * np.dot(kperp, an)
        if np.linalg.norm(pole) < 1e-6:
            pole = np.cross(self.basis()[0], an)
        pole = pole / np.linalg.norm(pole)
        a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
        h = math.sqrt(max(l1 * l1 - a * a, 0.0))
        knee_new = hip + an * a + pole * h
        self.world_rot("thigh_" + side, F.qfromto(knee - hip, knee_new - hip))
        # after the thigh swing the calf origin is at knee_new; swing the calf so that the ankle lands on the target
        knee_now = self.P[ca]
        ank_now = self.P[fo]
        self.world_rot("calf_" + side, F.qfromto(ank_now - knee_now, ankle_T - knee_now))
        self.set_world_rot("foot_" + side, foot_W)
        return err


def contact_slip(rig, T, R, side, f0, f1):
    """largest horizontal distance (m) of the ball of the foot from its mean position over [f0, f1] (world)"""
    pts = []
    for f in range(f0, f1 + 1):
        P, _ = rig.fk(T[f], R[f])
        pts.append(P[rig.idx["ball_" + side]][[0, 2]])
    pts = np.array(pts)
    return float(np.max(np.linalg.norm(pts - pts.mean(axis=0), axis=1)))


def process(rig, name, chans, cfg):
    nfr = int(round(max(float(c["t"][-1]) for c in chans) * 30)) + 1
    T, R = rig.sample_clip(chans, nfr)
    orig = [Body(rig, T[f], R[f]) for f in range(nfr)]
    new = [Body(rig, T[f], R[f]) for f in range(nfr)]
    sgn = cfg["sign"]
    yaw = np.unwrap([b.yaw() for b in orig])
    y0, y1 = yaw[cfg["turn"][0]], yaw[cfg["turn"][1]]
    win0, win1 = cfg["window"]
    ball_local = {s: rig.rest_t[rig.idx["ball_" + s]] for s in "lr"}

    # ---- lock targets from the source pose
    pv_side, pa, pb = cfg["pivot"]
    r0, r1 = cfg["pivot_ref"]
    pv_ball = np.mean([orig[f].P[rig.idx["ball_" + pv_side]] for f in range(r0, r1 + 1)], axis=0)
    pv_ref_f = (r0 + r1) // 2
    pv_W0 = orig[pv_ref_f].Q[rig.idx["foot_" + pv_side]]
    pv_psi0 = yaw[pv_ref_f]
    ps_side, qa0, qa1, qb0, qb1 = cfg["push"]
    ps_ball = orig[cfg["push_ref"]].P[rig.idx["ball_" + ps_side]].copy()
    ps_W = orig[cfg["push_ref"]].Q[rig.idx["foot_" + ps_side]].copy()

    errs = {"pivot": 0.0, "push": 0.0}
    for f in range(nfr):
        b = new[f]
        w = ramp(f, win0 - 3, win0 + 3, win1 - 8, win1) if f < win1 else 0.0
        # turn progress s (0..1), bell = 0 at the start / end of the spin, 1 in the middle
        s = min(1.0, max(0.0, (yaw[f] - y0) / (y1 - y0))) if y1 != y0 else 0.0
        bell = math.sin(math.pi * s) ** 0.85
        left, fwd = b.basis()
        if w > 0:
            lead = sgn * HIP_LEAD * bell * w
            # hips lead: pelvis heading ahead of the root; spine counter-rotates (shoulders lag); head looks into the exit
            b.world_rot("pelvis", F.qaxis(UP, lead))
            for nm, share in (("spine_01", 0.30), ("spine_02", 0.35), ("spine_03", 0.35)):
                b.world_rot(nm, F.qaxis(UP, -COUNTER * lead * share))
            b.world_rot("neck_01", F.qaxis(UP, sgn * HEAD_LEAD * 0.4 * bell * w))
            b.world_rot("Head", F.qaxis(UP, sgn * HEAD_LEAD * 0.6 * bell * w))
            # lean into the turn: roll about the forward axis toward the inside (left turn -> lean left = -x for +z forward)
            left, fwd = b.basis()
            roll = -sgn * LEAN_ROLL * bell * w
            for nm, share in (("spine_01", 0.4), ("spine_02", 0.35), ("spine_03", 0.25)):
                b.world_rot(nm, F.qaxis(fwd, roll * share))
            b.world_rot("Head", F.qaxis(fwd, -roll * 0.6))           # keep the eyes level
            # push-off: forward pitch about the left axis
            pw = ramp(f, cfg["push_lean"][0] - 5, cfg["push_lean"][0] + 3, cfg["push_lean"][1] - 8, cfg["push_lean"][1]) * w
            if pw > 0:
                left, fwd = b.basis()
                pitch = PUSH_PITCH * pw
                for nm, share in (("pelvis", 0.25), ("spine_01", 0.3), ("spine_02", 0.25), ("spine_03", 0.2)):
                    b.world_rot(nm, F.qaxis(left, pitch * share))
                b.world_rot("Head", F.qaxis(left, -pitch * 0.5))
        # ---- feet
        wp = ramp(f, pa - 2, pa, pb, pb + 3)
        if wp > 0:
            g = FOOT_YAW_FOLLOW * (yaw[f] - pv_psi0)
            Wd = F.qmul(F.qaxis(UP, math.degrees(g)), pv_W0)
            Wcur = b.Q[rig.idx["foot_" + pv_side]]
            Wf = F.qslerp(Wcur, Wd, wp)
            ballT = b.P[rig.idx["ball_" + pv_side]] * (1 - wp) + pv_ball * wp
            ankle = ballT - F.qrot(Wf, ball_local[pv_side])
            errs["pivot"] = max(errs["pivot"], b.leg_ik(pv_side, ankle, Wf))
        wq = ramp(f, qa0, qa1, qb0, qb1)
        if wq > 0:
            Wcur = b.Q[rig.idx["foot_" + ps_side]]
            Wf = F.qslerp(Wcur, ps_W, wq)
            ballT = b.P[rig.idx["ball_" + ps_side]] * (1 - wq) + ps_ball * wq
            ankle = ballT - F.qrot(Wf, ball_local[ps_side])
            errs["push"] = max(errs["push"], b.leg_ik(ps_side, ankle, Wf))
    # quaternion continuity + report
    rep = {"clip": name, "frames": nfr}
    rep["pivot_slip_cm_before"] = round(100 * contact_slip(rig, T, R, pv_side, pa, pb), 1)
    Tn = np.array([b.T for b in new]); Rn = np.array([b.R for b in new])
    rep["pivot_slip_cm_after"] = round(100 * contact_slip(rig, Tn, Rn, pv_side, pa, pb), 1)
    rep["pivot_foot"] = pv_side
    rep["pivot_lock_frames"] = [pa, pb]
    rep["push_foot"] = ps_side
    rep["push_lock_frames"] = [qa1, qb0]
    rep["push_slip_cm_before"] = round(100 * contact_slip(rig, T, R, ps_side, qa1, qb0), 1)
    rep["push_slip_cm_after"] = round(100 * contact_slip(rig, Tn, Rn, ps_side, qa1, qb0), 1)
    rep["ik_reach_err_cm"] = {k: round(100 * v, 1) for k, v in errs.items()}
    # angular speed check of every body bone
    worst = (0.0, "", 0)
    for f in range(1, nfr):
        for nm in ("pelvis", "spine_01", "spine_02", "spine_03", "Head", "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r"):
            i = rig.idx[nm]
            d = abs(float(np.dot(Rn[f, i], Rn[f - 1, i])))
            a = math.degrees(2 * math.acos(min(1.0, d)))
            if a > worst[0]:
                worst = (a, nm, f)
    rep["max_bone_rot_deg_per_frame_after"] = [round(worst[0], 1), worst[1], worst[2]]
    worst = (0.0, "", 0)
    for f in range(1, nfr):
        for nm in ("pelvis", "spine_01", "spine_02", "spine_03", "Head", "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r"):
            i = rig.idx[nm]
            d = abs(float(np.dot(R[f, i], R[f - 1, i])))
            a = math.degrees(2 * math.acos(min(1.0, d)))
            if a > worst[0]:
                worst = (a, nm, f)
    rep["max_bone_rot_deg_per_frame_before"] = [round(worst[0], 1), worst[1], worst[2]]
    # max torso twist between pelvis and spine_03 (deg) and lean
    tw = []
    for f in range(nfr):
        Qp = new[f].Q[rig.idx["pelvis"]]; Qs = new[f].Q[rig.idx["spine_03"]]
        rel = F.qmul(F.qinv(Qp), Qs)
        tw.append(math.degrees(2 * math.acos(min(1.0, abs(rel[3])))))
    rep["max_pelvis_to_chest_angle_deg_after"] = round(max(tw), 1)
    tw = []
    for f in range(nfr):
        Qp = orig[f].Q[rig.idx["pelvis"]]; Qs = orig[f].Q[rig.idx["spine_03"]]
        rel = F.qmul(F.qinv(Qp), Qs)
        tw.append(math.degrees(2 * math.acos(min(1.0, abs(rel[3])))))
    rep["max_pelvis_to_chest_angle_deg_before"] = round(max(tw), 1)
    # rewrite the rotation channels of every bone whose rotation changed
    changed = []
    for i in range(rig.n):
        if np.max(np.abs(Rn[:, i] - R[:, i])) > 1e-7 and rig.name[i] not in ("root",):
            changed.append(i)
    out = []
    keep = [c for c in chans if not (c["path"] == "rotation" and c["node"] in changed)]
    times = np.arange(nfr) / 30.0
    for i in changed:
        v = Rn[:, i].copy()
        for f in range(1, nfr):                                        # keep the hemisphere continuous
            if np.dot(v[f], v[f - 1]) < 0:
                v[f] = -v[f]
        keep.append({"node": i, "path": "rotation", "t": times.copy(), "v": v})
    rep["rewritten_bones"] = sorted(rig.name[i] for i in changed)
    return keep, rep


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    path = args[0]
    rep_path = sys.argv[sys.argv.index("--report") + 1] if "--report" in sys.argv else None
    rig = F.Rig(path)
    anims = rig.g.anims()
    reports = []
    for name, cfg in CLIPS.items():
        anims[name], rep = process(rig, name, anims[name], cfg)
        reports.append(rep)
        print(json.dumps(rep))
    rig.g.write(anims)
    if rep_path:
        json.dump(reports, open(rep_path, "w"), indent=1)
    by_name = dict((r["clip"], r) for r in reports)
    note = "middle rebuilt by tools/anim/loco/pivot180_rebuild.py (pivot foot locked, hips lead, torso counter-rotates + leans, push-off pitch); root track and start / end poses unchanged"
    side = path + ".clips.json"
    if os.path.exists(side):
        rows = json.load(open(side, encoding="utf-8"))
        for r in rows:
            if r["name"] in by_name:
                r["pivot_rebuild"] = by_name[r["name"]]
                r["note"] = (r.get("note") or "") + (" | " if r.get("note") else "") + note
        json.dump(rows, open(side, "w", encoding="utf-8"), indent=1)
    side = path + ".contacts.json"
    if os.path.exists(side):
        d = json.load(open(side, encoding="utf-8"))
        for n, r in by_name.items():
            if n in d.get("clips", {}):
                d["clips"][n]["pivot_rebuild"] = r
        json.dump(d, open(side, "w", encoding="utf-8"), indent=1)
    print("written", path)


if __name__ == "__main__":
    main()
