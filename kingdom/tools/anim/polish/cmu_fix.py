# Re-review fixes for the CMU defense + reactions clip libraries (UAL skeleton, 30 fps GLB + .clips.json sidecar). Pure numpy.
#   python cmu_fix.py stage1 <lib.glb>   trim static heads / frozen tails (glb_edit_clips), re-zero root travel, blend get-ups into the UAL idle pose
#   python cmu_fix.py floor  <lib.glb> <mesh.json>   raise the pelvis per frame so the skinned mesh never dips below y=0
#                                        (mesh.json from cmu_mesh_floor.py run on the stage1 result)
# Start from the pristine GLB (git show HEAD:<path> > <path>), then stage1 -> cmu_mesh_floor.py -> floor -> cmu_mesh_floor.py (verify).
# Lifting is done on the pelvis (a child of root), never on the root track, so root motion stays horizontal.
import os, sys, json, math
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, ".."))
import glb_edit_clips as gec                                                    # noqa: E402
from glb_fk import (Glb, Rig, qslerp, qnorm, leg_ik, FPS, clip_len)            # noqa: E402

UAL = os.path.normpath(os.path.join(HERE, "../../../assets/incoming/quaternius/universal-animation-library/Unreal-Godot/UAL1_Standard.glb"))

# seconds inside the CURRENT clip that are kept  (name -> [t0, t1]); anything else is left alone
TRIMS = {
    "UAL_Free_Defense": {
        "MA_Block_R_A": [0.25, 1.13],            # 0.3 s static stand before the block starts
        "MA_Dodge_Duck": [0.55, 3.40],           # 0.7 s static crouch before the duck
        "MA_Evade_AttackerCover": [0.45, 2.30],  # 0.6 s idle before the cover
    },
    "UAL_Free_Reactions": {
        "Fall_Slip_Back": [0.8, 3.0],            # 1 s of walking in; legs-in-the-air tail frozen from 2.5 s
        "Fall_RugPull_Back": [0.0, 1.2],         # lying frozen from 0.9 s
        "Fall_BackflipTwist": [1.7, 3.5],        # 1.7 s of standing / arm stretching before the flip
        "GetUp_FaceDown_A": [0.0, 3.4],          # hunched wait 3.6-5.0 s
        "GetUp_FaceDown_B": [0.0, 3.0],
        "GetUp_Side": [0.0, 4.8],
        "GetUp_Back_A": [0.0, 4.2],
        "GetUp_Back_B": [0.0, 3.8],
    },
}
IDLE_BLEND = {"UAL_Free_Reactions": ["GetUp_FaceDown_A", "GetUp_FaceDown_B", "GetUp_Side", "GetUp_Back_A", "GetUp_Back_B"]}
BLEND_S = 0.9


# ------------------------------------------------------------------ dense <-> sparse
def smooth(s):
    return s * s * (3 - 2 * s)


def decimate(t, v, tol):
    """Ramer-Douglas-Peucker on (t, v) with linear interpolation; keeps first and last key."""
    keep = np.zeros(len(t), bool); keep[0] = keep[-1] = True
    stack = [(0, len(t) - 1)]
    while stack:
        i, j = stack.pop()
        if j - i < 2:
            continue
        w = ((t[i + 1:j] - t[i]) / (t[j] - t[i]))[:, None]
        err = np.abs(v[i + 1:j] - (v[i] * (1 - w) + v[j] * w)).max(axis=1)
        k = int(np.argmax(err))
        if err[k] > tol:
            keep[i + 1 + k] = True
            stack += [(i, i + 1 + k), (i + 1 + k, j)]
    return t[keep], v[keep]


def write_back(rig, chans, T0, Q0, T1, Q1):
    """Replace every (node, path) channel whose dense values changed by a decimated dense channel."""
    nf = T1.shape[0]
    t = np.arange(nf) / FPS
    have = {(c["node"], c["path"]): i for i, c in enumerate(chans)}
    n0 = T0.shape[0]
    for n in range(T1.shape[1]):
        for path, A0, A1, tol in (("translation", T0, T1, 2e-4), ("rotation", Q0, Q1, 3e-4)):
            same = n0 == nf and np.abs(A1[:, n] - A0[:, n]).max() < 1e-6
            if path == "rotation":
                same = same or (n0 == nf and (1 - np.abs((A1[:, n] * A0[:, n]).sum(-1))).max() < 1e-9)
            if same:
                continue
            v = A1[:, n].copy()
            if path == "rotation":
                for i in range(1, len(v)):
                    if np.dot(v[i], v[i - 1]) < 0:
                        v[i] = -v[i]
            tt, vv = decimate(t, v, tol)
            new = {"node": n, "path": path, "t": tt, "v": vv}
            if (n, path) in have:
                chans[have[(n, path)]] = new
            else:
                chans.append(new); have[(n, path)] = len(chans) - 1
    return chans


def rezero_root(rig, chans):
    r = rig.idx["root"]
    for c in chans:
        if c["node"] == r and c["path"] == "translation":
            c["v"] = c["v"] - c["v"][0]


# ------------------------------------------------------------------ idle blend
def idle_pose(rig):
    """dense frame 0 of UAL Idle_Loop, mapped onto this rig's node order by name"""
    gu = Glb(UAL); ru = Rig(gu)
    T, Q = ru.dense(gu.anims()["Idle_Loop"], 0)
    Ti = rig.rest_t.copy(); Qi = rig.rest_q.copy()
    for n, i in rig.idx.items():
        if n in ru.idx:
            Ti[i] = T[0, ru.idx[n]]; Qi[i] = Q[0, ru.idx[n]]
    return Ti, Qi


def blend_to_idle(rig, T, Q, nblend):
    """append nblend frames that blend the last pose into the idle pose, pelvis kept over the same spot, both feet stepping to
    their idle stance positions (leg IK, pelvis lowered if the legs cannot reach)."""
    Ti, Qi = idle_pose(rig)
    P0, R0 = rig.fk(T[-1:], Q[-1:])
    Pi, Ri = rig.fk(Ti[None], Qi[None])
    pel, root = rig.idx["pelvis"], rig.idx["root"]
    F = nblend
    s = smooth(np.arange(1, F + 1) / F)[:, None]
    Tn = np.repeat(T[-1:], F, axis=0); Qn = np.repeat(Q[-1:], F, axis=0)
    for n in range(Q.shape[1]):
        if n == root:
            continue
        Qn[:, n] = qslerp(np.repeat(Q[-1:, n], F, axis=0), np.repeat(Qi[None, n], F, axis=0), s)
    # pelvis local translation: z (up) blends to the idle height, x/y (horizontal) stay
    Tn[:, pel, 2] = T[-1, pel, 2] + (Ti[pel, 2] - T[-1, pel, 2]) * s[:, 0]
    tgt = {}
    for side in ("l", "r"):
        a = rig.idx["foot_" + side]
        a0 = P0[0, a]
        rel = Pi[0, a] - Pi[0, pel]
        end = np.array([P0[0, pel, 0] + rel[0], Pi[0, a, 1], P0[0, pel, 2] + rel[2]])
        moved = np.linalg.norm((end - a0)[[0, 2]])
        tg = a0[None] + (end - a0)[None] * s
        tg[:, 1] += 0.04 * np.sin(np.pi * s[:, 0]) * (1.0 if moved > 0.08 else 0.0)
        tgt[side] = tg
    Qb = Qn.copy()
    th = {sd: rig.idx["thigh_" + sd] for sd in ("l", "r")}
    ca = {sd: rig.idx["calf_" + sd] for sd in ("l", "r")}
    fo = {sd: rig.idx["foot_" + sd] for sd in ("l", "r")}
    for it in range(8):
        Qn = Qb.copy()
        P, R = rig.fk(Tn, Qn)
        excess = np.zeros(F)
        for sd in ("l", "r"):
            H = P[:, th[sd]]
            reach = np.linalg.norm(P[:, ca[sd]] - H, axis=-1) + np.linalg.norm(P[:, fo[sd]] - P[:, ca[sd]], axis=-1)
            d = np.linalg.norm(tgt[sd] - H, axis=-1)
            excess = np.maximum(excess, d - 0.985 * reach)
        if excess.max() <= 1e-4:
            break
        Tn[:, pel, 2] -= np.maximum(excess, 0) * 1.4
    P, R = rig.fk(Tn, Qn)
    for sd in ("l", "r"):
        P, R = leg_ik(rig, Tn, Qn, sd, tgt[sd], np.ones(F), P=P, R=R, pole_hint=np.array([0, 0, 1.0]))
    return np.concatenate([T, Tn]), np.concatenate([Q, Qn])


# ------------------------------------------------------------------ stages
def lib_key(path):
    return os.path.basename(path).split(".")[0]


def stage1(path):
    key = lib_key(path)
    spec = {"trim": TRIMS.get(key, {})}
    if spec["trim"]:
        gec.edit(path, spec)
    g = Glb(path)
    rig = Rig(g)
    anims = g.anims()
    side = path + ".clips.json"
    rows = json.load(open(side, encoding="utf-8")) if os.path.exists(side) else []
    for name, chans in anims.items():
        rezero_root(rig, chans)
        if name in IDLE_BLEND.get(key, []):
            nf = int(round(clip_len(chans) * FPS))
            T0, Q0 = rig.dense(chans, nf)
            nb = int(round(BLEND_S * FPS))
            T1, Q1 = blend_to_idle(rig, T0, Q0, nb)
            write_back(rig, chans, T0, Q0, T1, Q1)
            for r in rows:
                if r["name"] == name:
                    r["seconds"] = round((nf + nb) / FPS, 2); r["frames"] = nf + nb + 1
                    r["idle_blend_s"] = BLEND_S
            print("%-24s %.2fs -> %.2fs (idle blend %.2fs)" % (name, nf / FPS, (nf + nb) / FPS, BLEND_S))
    g.write(anims)
    if rows:
        json.dump(rows, open(side, "w", encoding="utf-8"), indent=1)


def floor(path, meshjson, margin=0.0):
    g = Glb(path)
    rig = Rig(g)
    anims = g.anims()
    mesh = json.load(open(meshjson))
    pel = rig.idx["pelvis"]
    for name, chans in anims.items():
        if name not in mesh:
            continue
        mz = np.array(mesh[name]["minz"])
        nf = len(mz) - 1
        need = np.maximum(0.0, margin - mz)
        if need.max() < 0.004:                        # under 4 mm: not visible, leave the clip bit-exact
            continue
        # smooth, never below the need: max filter (+-3 frames) then a short gaussian, then max with the need again
        k = 3
        pad = np.pad(need, k, mode="edge")
        mf = np.max([pad[i:i + len(need)] for i in range(2 * k + 1)], axis=0)
        x = np.arange(-6, 7); w = np.exp(-x ** 2 / (2 * 2.0 ** 2)); w /= w.sum()
        sm = np.convolve(np.pad(mf, 6, mode="edge"), w, mode="valid")
        dz = np.maximum(sm, need)
        T0, Q0 = rig.dense(chans, nf)
        T1 = T0.copy(); T1[:, pel, 2] += dz           # pelvis local z is up (root is rotated -90 deg about x)
        write_back(rig, chans, T0, Q0, T1, Q0.copy())
        print("%-24s floor lift max %.3f m, mean %.3f m, frames lifted %d/%d" % (name, dz.max(), dz.mean(), int((dz > 5e-4).sum()), nf + 1))
    g.write(anims)


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "stage1":
        stage1(sys.argv[2])
    elif cmd == "floor":
        floor(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit(__doc__)
