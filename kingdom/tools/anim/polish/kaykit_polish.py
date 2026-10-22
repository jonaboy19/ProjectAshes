# Review fixes for the four KayKit clip libraries in kingdom/assets/incoming/animations_free2/ (pure numpy, no Blender).
#
# README
# ------
# Reproducible: the script first restores the four GLBs + *.clips.json from git HEAD (the state before this pass, use --no-restore to
# work on the current files), then applies the per-clip operations of the CONFIG table below and writes GLB + sidecar back.
#   python kaykit_polish.py            (from anywhere; repo root is found from this file)
# Operations (all keep the arms/hands as they are, only legs / pelvis / time / world travel change):
#   trim(t0, t1)          cut the clip to [t0, t1] s (glb_edit_clips.trim_channel), used for frozen tails, doubled cycles, intros of hold loops
#   loop(k)               loop closure: cross-blend the last k frames into the first pose (last frame == first frame)
#   travel(s)             scale the horizontal WORLD travel of the pelvis by s (root + pelvis double travel of the KayKit death / wake-up clips)
#   straighten(target)    kaykit_straighten.straighten: pelvis raise + two-bone leg IK on pinned ankles (knees open, feet do not slide)
#   floor()               kaykit_straighten.floor_shift: constant pelvis shift so the lowest sole touches z = 0
#   drop(f0, f1, dy)      lying-pose fix: pelvis shifted by 0 -> dy between frames f0..f1 (smoothstep) with the ankles pinned (leg IK)
#   rename                {old: new} (loop clips keep the _Loop suffix)      delete: [names]   (every rename / delete is printed)
# The metrics that decided each operation come from render_clips.py (foot slide, leg_straight, loop gap, root travel), the sheets from make_sheets.sh.
import os, sys, json, subprocess
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, ".."))
from glb_edit_clips import Glb, clip_len, trim_channel   # noqa: E402
from glb_fk import Rig, FPS, qrot, qconj, qslerp, qnorm    # noqa: E402
import kaykit_straighten as ks                              # noqa: E402
REPO = os.path.abspath(os.path.join(HERE, "../../../.."))
BASE = "kingdom/assets/incoming/animations_free2/"
LIBS = {"combat": "kaykit_combat_reactions/UAL_Kay_combat_reactions.glb", "move": "kaykit_movement_ext/UAL_Kay_movement_ext.glb",
        "ranged": "kaykit_ranged/UAL_Kay_ranged.glb", "undead": "kaykit_undead/UAL_Kay_undead.glb"}

# GLB animation name (with _Loop) -> operations, applied in order.  Numbers come from the metrics + sheets of this pass.
CONFIG = {
    "combat": {
        "Kay_Hit_React_A": [("floor",)],
        "Kay_Hit_React_B": [("floor",)],                                    # dipped 1.8 cm under the floor
        "Kay_Death_Fall_B": [("drop", 34, 58, -0.15), ("floor",)],          # corpse hovered ~0.2 m above the floor: lower the pelvis, ankles pinned
        "Kay_Block_Counter": [("floor",)],                                  # lunge floated 5.6 cm (no foot ever touched z=0)
        "Kay_Stance_2H_Idle_Loop": [("floor",)],
        "Kay_Stance_Fists_Idle_Loop": [("straighten", 0.92, 0.10), ("floor",)],   # deep lunge, legs 0.80 -> ~0.92
        "Kay_Dodge_Fwd": [("floor",)],
    },
    "move": {
        "Kay_Crouch_Idle_Loop": [("floor",)],                               # sank 9 cm; is a crouch WALK cycle (renamed)
        "Kay_Walk_Back_Loop": [("floor",)],
        "Kay_Walk_Kay_A_Loop": [("floor",)],
        "Kay_Walk_Kay_C_Casual_Loop": [("floor",)],
        "Kay_Run_Kay_A_Loop": [("floor",)],
        "Kay_Run_Kay_B_Loop": [("floor",)],
        "Kay_Run_Strafe_L_Loop": [("floor",)],
        "Kay_Run_Strafe_R_Loop": [("floor",)],
        "Kay_Idle_Kay_B_Loop": [("floor",)],                                # hovered 2.6 cm
        "Kay_Jump_Start_Kay": [("floor",)],
        "Kay_Jump_Short_Kay": [("floor",)],
        "Kay_Jump_Land_Kay": [("floor",)],
        "Kay_Jump_Long_Kay": [("floor",)],
    },
    "ranged": {
        "Kay_Pistol_Aim_Loop": [("trim", 0.37, 1.07), ("loop", 4)],        # first 0.37 s is the raise from the ready pose, then a hold
        "Kay_Rifle_Aim_Loop": [("trim", 8 / 30.0, 1.6), ("loop", 4)],      # same; frame 8 == last frame, breathing cycle stays
        "Kay_Bow_Draw": [("trim", 0.0, 1.2)],                               # frozen tail (5 frames)
        "Kay_Bow_Draw_Up": [("trim", 0.0, 1.03)],                           # frozen tail (12 frames)
        "Kay_Bow_Aim_Idle_Loop": [("floor",)],
        "Kay_Bow_Release_Up": [("floor",)],
        "Kay_Run_Holding_Bow_Loop": [("floor",)],
        "Kay_Run_Holding_Rifle_Loop": [("floor",)],
    },
    "undead": {
        "Kay_Undead_Idle_Loop": [("straighten", 0.92, 0.14), ("floor",)],
        "Kay_Undead_Walk_Loop": [("straighten", 0.93, 0.12), ("floor",)],
        "Kay_Undead_Taunt": [("straighten", 0.90, 0.12), ("floor",)],
        "Kay_Undead_Taunt_Long": [("straighten", 0.90, 0.12), ("floor",)],
        "Kay_Undead_Awaken_Stand": [("floor",)],
        "Kay_Undead_Collapse": [("travel", 0.21), ("floor",)],              # was hurled 5.65 m
        "Kay_Undead_Resurrect": [("trim", 0.0, 2.4), ("travel", 0.21), ("floor",)],   # frozen 10-frame tail cut
    },
}
RENAME = {"move": {"Kay_Crouch_Idle_Loop": "Kay_Crouch_Walk_Loop"}}
# rejected: Awaken_Floor has a 133 deg thigh snap + 0.69 m pelvis pop at 0.47 s (crawl -> stand); Rise_Ground floats 1-1.9 m above the ground
DELETE = {"undead": ["Kay_Undead_Awaken_Floor", "Kay_Undead_Rise_Ground"]}


def smooth(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


def densify(chans, nf=None):
    """resample every channel to the 30 fps frame grid (keeps interpolation semantics: slerp / lerp)"""
    if nf is None:
        nf = int(round(clip_len(chans) * FPS))
    t = np.arange(nf + 1) / FPS
    from glb_edit_clips import sample
    for c in chans:
        c["v"] = np.array([sample(c["t"], c["v"], c["path"], x) for x in t])
        c["t"] = t.copy()
    return nf


def op_trim(chans, t0, t1):
    for c in chans:
        trim_channel(c, t0, min(t1, clip_len(chans)))


def op_loop(chans, k):
    nf = densify(chans)
    w = smooth((np.arange(nf + 1) - (nf - k)) / k)
    for c in chans:
        v = c["v"]
        if c["path"] == "rotation":
            c["v"] = qslerp(v, np.broadcast_to(v[0], v.shape), w[:, None])
        else:
            c["v"] = v * (1 - w[:, None]) + v[0] * w[:, None]


def op_travel(rig, chans, s):
    """scale the world xz travel of root + pelvis by s, recentred so the clip starts at the origin (root motion keeps s * travel)"""
    I = rig.idx
    nf = int(round(clip_len(chans) * FPS))
    T, Q = rig.dense(chans, nf)
    P, _ = rig.fk(T, Q)
    h = P[:, I["pelvis"]]
    want = (h - h[0]) * s
    T2 = T.copy()
    T2[:, I["root"]] = (T[:, I["root"]] - T[0, I["root"]]) * s
    P2, _ = rig.fk(T2, Q)
    delta = want - P2[:, I["pelvis"]]
    delta[:, 1] = 0
    Rroot = np.broadcast_to(rig.rest_q[I["root"]], (nf + 1, 4))
    T2[:, I["pelvis"]] += qrot(qconj(Rroot), delta)
    ks.commit(rig, chans, T2, Q, with_pelvis=True, extra_t=[I["root"]])


def op_straighten(rig, chans, target, max_dy, circular=False):
    nf = int(round(clip_len(chans) * FPS))
    T, Q = rig.dense(chans, nf)
    dy = ks.solve_dy(rig, T, Q, target, max_dy)
    if dy > 0.005:
        T, Q = ks.straighten(rig, T, Q, dy * ks.planted_weight(rig, T, Q, circular=circular))
        ks.commit(rig, chans, T, Q)
    return dy


def op_floor(rig, chans):
    nf = int(round(clip_len(chans) * FPS))
    T, Q = rig.dense(chans, nf)
    dy = ks.floor_shift(rig, T, Q)
    if abs(dy) > 0.004:
        ks.commit(rig, chans, ks.raise_pelvis(rig, T, dy), Q)
    return dy


def op_drop(rig, chans, f0, f1, dy):
    nf = int(round(clip_len(chans) * FPS))
    T, Q = rig.dense(chans, nf)
    d = dy * smooth((np.arange(nf + 1) - f0) / float(f1 - f0))
    T2, Q2 = ks.straighten(rig, T, Q, d)
    ks.commit(rig, chans, T2, Q2)


def restore(libs):
    for k in libs:
        for suf in ("", ".clips.json"):
            p = BASE + LIBS[k] + suf
            data = subprocess.run(["git", "show", "HEAD:" + p], cwd=REPO, capture_output=True, check=True).stdout
            open(os.path.join(REPO, p), "wb").write(data)


def run(libs, restore_first=True):
    if restore_first:
        restore(libs)
    log = []
    for k in libs:
        path = os.path.join(REPO, BASE + LIBS[k])
        g = Glb(path)
        rig = Rig(g)
        anims = g.anims()
        rows = {r["name"] + ("_Loop" if r.get("loop") else ""): r for r in json.load(open(path + ".clips.json", encoding="utf-8"))}
        notes = {}
        for name, ops in CONFIG.get(k, {}).items():
            chans = anims[name]
            done = []
            for op in ops:
                kind, args = op[0], op[1:]
                if kind == "trim":
                    op_trim(chans, *args)
                elif kind == "loop":
                    op_loop(chans, *args)
                elif kind == "travel":
                    op_travel(rig, chans, *args)
                elif kind == "straighten":
                    dy = op_straighten(rig, chans, *args, circular=name.endswith("_Loop"))
                    done.append("straighten +%.3f m" % dy)
                    continue
                elif kind == "floor":
                    dy = op_floor(rig, chans)
                    done.append("floor %+.3f m" % dy)
                    continue
                elif kind == "drop":
                    op_drop(rig, chans, *args)
                done.append("%s%s" % (kind, list(args)))
            notes[name] = done
        out = {}
        for name, chans in anims.items():
            if name in DELETE.get(k, []):
                log.append("DELETE %s %s" % (k, name))
                continue
            out[RENAME.get(k, {}).get(name, name)] = chans
        g.write(out)
        side = []
        for name, r in rows.items():
            if name in DELETE.get(k, []):
                continue
            chans = out[RENAME.get(k, {}).get(name, name)]
            L = clip_len(chans)
            if name in notes and notes[name]:
                r["polish"] = notes[name]
                r["seconds"] = round(L, 2)
                r["frames"] = int(round(L * FPS)) + 1
                r["keys"] = int(sum(len(c["t"]) for c in chans))
            if name in RENAME.get(k, {}):
                r["renamed_from"] = r["name"]
                r["name"] = RENAME[k][name].replace("_Loop", "")
                log.append("RENAME %s %s -> %s" % (k, name, RENAME[k][name]))
            side.append(r)
        json.dump(side, open(path + ".clips.json", "w", encoding="utf-8"), indent=1)
        print("wrote", path, len(out), "clips")
    print("\n".join(log))


if __name__ == "__main__":
    libs = [a for a in sys.argv[1:] if not a.startswith("--")] or list(LIBS)
    run(libs, "--no-restore" not in sys.argv)
