"""treadmill_ual.py - retarget a gait cfg (retarget_bvh.py) and clean the planted-foot slide INSIDE the clips.

  blender -b --python tools/anim/loco/treadmill_ual.py -- <cfg.json>          (cfg_loco_gaits.json, cfg_loco_mixamo.json ...)

For every looping clip: per foot, a stance window = frames where the ball is within 3.5 cm of the clip floor and the ankle within
4.5 cm of its lowest height, >= 4 frames. Inside a window the ankle is moved onto the least-squares LINE through its own xy path
(constant speed backwards = what a planted foot does on a treadmill) with an analytic two-bone IK on thigh/calf (knee stays in its
plane, foot keeps its world rotation), 3-frame smoothstep blend in/out. The clip keeps its average ground speed, loses the
heel-strike wobble / mid-stance creep. mixamo_to_ual.py's lock pins STATIONARY plants; this one is for travelling gaits.
Report: <out>.treadmill.json with stance slip mean/max (m/s, relative to the clip's own average stance speed) before/after.
"""
import json, math, os, runpy, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
RETARGET = os.path.normpath(os.path.join(HERE, "..", "retarget_bvh.py"))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "tools", "anim")))
import mixamo_to_ual as MX   # noqa: E402  (export helper; bpy is imported lazily there)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    cfg_path = os.path.abspath(argv[0])
    cfg = json.load(open(cfg_path, encoding="utf-8"))
    sys.argv = [RETARGET, "--", cfg_path]
    g = runpy.run_path(RETARGET, run_name="__retarget__")
    import bpy
    from mathutils import Vector, Matrix
    scene = bpy.context.scene
    bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"
    tgt, made, assign = g["tgt"], g["made"], g["assign"]
    ad = tgt.animation_data
    ad.use_nla = False
    pb = tgt.pose.bones
    mw = tgt.matrix_world
    base_out = os.path.normpath(os.path.join(os.path.dirname(cfg_path), cfg["out"]))
    report = {}
    spec = {c["name"] + ("_Loop" if c.get("loop") else ""): c for c in cfg["clips"]}

    def upd():
        bpy.context.view_layer.update()

    def sample(n):
        A, B = {"l": [], "r": []}, {"l": [], "r": []}
        for f in range(n):
            scene.frame_set(f)
            for s in ("l", "r"):
                A[s].append((mw @ pb["foot_" + s].head).copy())
                B[s].append((mw @ pb["ball_" + s].head).copy())
        return A, B

    def segments(A, B, s, n):
        zmin = min(a.z for a in A[s]); bmin = min(b.z for b in B[s])
        low = [(A[s][t].z - zmin < 0.045) and (B[s][t].z - bmin < 0.035) for t in range(n)]
        segs, t = [], 0
        while t < n:
            if low[t]:
                e = t
                while e + 1 < n and low[e + 1]:
                    e += 1
                if e - t + 1 >= 4:
                    segs.append((t, e))
                t = e + 1
            else:
                t += 1
        return segs

    def slip(A, B, n):
        """mean / max deviation of the planted ankle from a constant-speed line, as a speed (m/s)."""
        out = []
        for s in ("l", "r"):
            for (s0, s1) in segments(A, B, s, n):
                f = np.arange(s0, s1 + 1)
                for ax in (0, 1):
                    pass
                P = np.array([[A[s][t].x, A[s][t].y] for t in f])
                sp = np.linalg.norm(np.diff(P, axis=0), axis=1) * 30.0
                mean_sp = np.linalg.norm(P[-1] - P[0]) / max(1, len(f) - 1) * 30.0
                out.extend(np.abs(sp - mean_sp).tolist())
        return (float(np.mean(out)), float(np.max(out))) if out else (0.0, 0.0)

    def key(names, f):
        for nm in names:
            pb[nm].keyframe_insert("rotation_quaternion", frame=f)

    for name, act in made:
        c = spec.get(name, {})
        if not c.get("loop") or c.get("no_treadmill"):
            continue
        assign(tgt, act)
        n = int(round(act.frame_range[1])) + 1
        A, B = sample(n)
        rec = {"before": [round(x, 3) for x in slip(A, B, n)]}
        fixed = 0
        R = 3
        for s in ("l", "r"):
            th, ca, fo = "thigh_" + s, "calf_" + s, "foot_" + s
            for (s0, s1) in segments(A, B, s, n):
                f = np.arange(s0, s1 + 1)
                X = np.array([A[s][t].x for t in f]); Y = np.array([A[s][t].y for t in f])
                fx = np.polyval(np.polyfit(f, X, 1), f); fy = np.polyval(np.polyfit(f, Y, 1), f)
                lo, hi = max(0, s0 - R), min(n - 1, s1 + R)
                orig = {}
                for t in range(lo, hi + 1):
                    scene.frame_set(t)
                    orig[t] = {k: pb[k].matrix.copy() for k in (th, ca, fo)}
                for t in ([lo - 1] if lo > 0 else []) + ([hi + 1] if hi < n - 1 else []):
                    scene.frame_set(t)
                    key((th, ca, fo), t)
                for t in range(lo, hi + 1):
                    if t < s0:
                        w = (t - lo + 1) / (R + 1)
                    elif t > s1:
                        w = (hi - t + 1) / (R + 1)
                    else:
                        w = 1.0
                    w = w * w * (3 - 2 * w)
                    cur = A[s][t]
                    ti = min(max(t, s0), s1) - s0
                    want = cur.lerp(Vector((fx[ti], fy[ti], cur.z)), w)
                    T = mw.inverted() @ want
                    scene.frame_set(t)
                    mt, mc, mf = orig[t][th], orig[t][ca], orig[t][fo]
                    hip, knee, ank = mt.translation, mc.translation, mf.translation
                    la, lb = (knee - hip).length, (ank - knee).length
                    d = min((T - hip).length, (la + lb) * 0.9995)
                    u = (T - hip).normalized()
                    v = (knee - hip) - u * (knee - hip).dot(u)
                    if v.length < 1e-6:
                        continue
                    v.normalize()
                    al = math.acos(max(-1.0, min(1.0, (la * la + d * d - lb * lb) / (2 * la * d))))
                    knee2 = hip + (u * math.cos(al) + v * math.sin(al)) * la
                    T2 = hip + u * d
                    r1 = (knee - hip).rotation_difference(knee2 - hip)
                    r2 = (r1 @ (ank - knee)).rotation_difference(T2 - knee2)
                    pb[th].matrix = Matrix.Translation(hip) @ (r1.to_matrix().to_4x4() @ mt.to_3x3().to_4x4()); upd()
                    pb[ca].matrix = Matrix.Translation(knee2) @ ((r2 @ r1).to_matrix().to_4x4() @ mc.to_3x3().to_4x4()); upd()
                    pb[fo].matrix = Matrix.Translation(T2) @ mf.to_3x3().to_4x4(); upd()
                    key((th, ca, fo), t)
                    fixed += 1
        for fc in act.fcurves if hasattr(act, "fcurves") else []:
            for kp in fc.keyframe_points:
                kp.interpolation = "LINEAR"
        A2, B2 = sample(n)
        rec["after"] = [round(x, 3) for x in slip(A2, B2, n)]
        rec["frames_fixed"] = fixed
        report[name] = rec
        print("TREADMILL", name, json.dumps(rec))
    assign(tgt, None)
    ad.use_nla = True
    MX.export(g, base_out)
    json.dump(report, open(base_out + ".treadmill.json", "w"), indent=1)
    print("TREADMILL_DONE", base_out, len(report))


if __name__ == "__main__":
    main()
