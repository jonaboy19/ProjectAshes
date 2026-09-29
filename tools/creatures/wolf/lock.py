"""Foot-lock re-targeting of an existing (hand-animated) action: keep the body/spine/neck/tail motion of the source clip, pin the
feet to the ground during their stance frames (world-fixed under the given root motion) and solve the legs with IK.
Used for walk / run (fix sliding) and run_turn_l/r (source run + lean, spine bend, head lead; feet locked on the arc)."""
import math
import numpy as np
import bpy
from mathutils import Vector, Matrix, Quaternion
from wlib import mesh_world_np, assign, frame_range
from gait import *
from clips_base import Clip, home_fl

LEG_TAIL_BONES = {"FL": ["FrontUpperLeg.L", "FrontLowerLeg.L"], "FR": ["FrontUpperLeg.R", "FrontLowerLeg.R"],
                  "BL": ["BackLeg.L", "BackUpperLeg.L", "BackLowerLeg.L"], "BR": ["BackLeg.R", "BackUpperLeg.R", "BackLowerLeg.R"]}
STANCE_M = 0.03           # paw sole below this many metres = planted in the source clip


def sample(E, arm, mesh, ps, act):
    R = E.R
    assign(arm, act)
    f0, f1 = frame_range(act)
    out = []
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f)
        A = {b: arm.pose.bones[b].matrix @ R.rest[b].inverted() for b in R.names}
        P = mesh_world_np(mesh) / E.s
        cen, zmin = {}, {}
        for k, idx in ps.items():
            p = P[idx]
            cen[k] = p.mean(0)
            zmin[k] = p[:, 2].min()
        out.append(dict(A=A, cen=cen, zmin=zmin))
    return out


def source_ground_speed(E, src):
    """m/s the planted paws move backward in the source clip (mean over stance frames)"""
    v = []
    for k in LEGS:
        for i in range(1, len(src) - 1):
            if all(src[j]['zmin'][k] * E.s < STANCE_M for j in (i - 1, i, i + 1)):
                v.append((src[i + 1]['cen'][k][1] - src[i - 1]['cen'][k][1]) * E.s * 15.0)
    return float(np.mean(v)) if v else 0.0


def stance_runs(pl):
    """contiguous True runs of a bool list, on a 3x periodic extension: returns [(a, b)] in extended indices"""
    n = len(pl)
    ext = list(pl) * 3
    runs = []
    i = 0
    while i < len(ext):
        if ext[i]:
            j = i
            while j + 1 < len(ext) and ext[j + 1]:
                j += 1
            runs.append((i - n, j - n))
            i = j + 1
        else:
            i += 1
    return runs


def lock_clip(E, name, src, T_frames, vf, omega=0.0, extras=None, ramp=2.0, loop=True, notes="", strict_loop=True):
    """src: sample() output (frames 0..N, N = T_frames). vf/omega: root motion the game will apply (m/s, rad/s, body frame).
    extras(t) -> {'rots': {bone: (q, pivot)}, 'trans': {...}, 'dz':.., ...} additional frame keys composed on the source pose."""
    R = E.R
    n = T_frames
    T = n / 30.0
    world = World(vf, 0.0, omega, -3 * T, 3 * T)
    nsrc = len(src) - 1                                  # last frame duplicates the first for loops
    per = nsrc if loop else None
    # planted flags per leg over one period (frames 0..n-1)
    plant = {}
    for k in LEGS:
        pl = [src[i]['zmin'][k] * E.s < STANCE_M for i in range(n)]
        plant[k] = stance_runs(pl)
    # world plant spot per run (extended index space); the anchor = mean source paw position over the run
    def src_at(i, k):
        j = i % n if loop else min(max(i, 0), n)
        return src[j]['cen'][k], src[j]['zmin'][k]
    Q = {}
    for k in LEGS:
        for (a, b) in plant[k]:
            cs = np.array([src_at(i, k)[0] for i in range(a, b + 1)])
            m = cs.mean(0)
            tm = 0.5 * (a + b) / 30.0
            Q[(k, a, b)] = world.from_body(tm, -m[1] * E.s, m[0] * E.s)
    fdirs = {}

    def fn(t):
        i = int(round(t * 30))
        Fr = {}
        ex = extras(t) if extras else {}
        for kk, vv in ex.items():
            Fr[kk] = vv
        own = {}
        own_leg = {}
        A = src[i % n if loop else min(i, n)]['A']
        for b in R.names:
            p = R.par[b]
            m = (A[p].inverted() @ A[b]) if p else A[b]
            if any(b in v for v in LEG_TAIL_BONES.values()):
                own_leg[b] = m
            else:
                own[b] = m
        Fr['own'] = own
        Fr['own_leg'] = own_leg
        Fr['paw_w'] = {}
        paws = {}
        pl_flags = {}
        for k in LEGS:
            cen, zmin = src_at(i, k)
            best_w, best = 0.0, None
            for (a, b) in plant[k]:
                d = 0.0 if a <= i <= b else min(abs(i - a), abs(i - b))
                w = 1.0 if d == 0 else max(0.0, 1.0 - d / (ramp + 1.0))
                w = sstep(w) if d > 0 else 1.0
                if w > best_w:
                    best_w, best = w, (a, b)
            if best is not None and best_w > 0:
                Qk = Q[(k, best[0], best[1])]
                bF, bL = world.to_body(i / 30.0, *Qk)
                tx, ty = bL / E.s, -bF / E.s
                x = lerp(cen[0], tx, best_w)
                y = lerp(cen[1], ty, best_w)
                z = lerp(zmin, 0.0, best_w)
                pl_flags[k] = best_w >= 0.999
            else:
                x, y, z = cen[0], cen[1], zmin
                pl_flags[k] = False
            fd = None
            if k[0] == "B":
                Al = A[LEG_TAIL_BONES[k][-1]]
                J = R.leg[k]["joints"]
                hock = (Al @ J[2].to_4d()).to_3d()
                paw = (Al @ J[3].to_4d()).to_3d()
                fd = (hock - paw).normalized()
            if best_w > 0.0:
                paws[k] = (Vector((x, y, max(z, 0.0))), fd if fd is not None else 0.0)
                Fr['paw_w'][k] = best_w
        Fr['paw'] = paws
        Fr['planted'] = pl_flags
        return Fr
    return Clip(name, T, fn, loop=loop, world=world, notes=notes)
