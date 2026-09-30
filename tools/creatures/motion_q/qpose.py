"""Keyframed pose authoring on top of qrig/qgait: world-axis rotations about bone heads, root translation and IK-driven feet.
A clip is described by KEYS = [(t_seconds, {param: value}, ease_name)]. Params:
  root.x / root.y / root.z          metres, translation of the whole skeleton (x = creature's left, -y = forward, z = up)
  <Bone>.rx / .ry / .rz             degrees, rotation about the bone's HEAD around the WORLD axes (applied down the hierarchy in order)
  foot.<F>.x / .y / .z              metres, offset of foot F's IK target from its base position (F from the feet dict)
  free.<F>                          1 = do not IK this foot (it just follows the FK chain)
Unlisted params are 0. Between keys values ease with the ease of the key that ENDS the segment (smooth|snap|lin|out|in).
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qrig import *
from qgait import Foot, ccd_foot, quad_feet, lock_clip

EASE = {'smooth': smooth, 'snap': ease_snap, 'lin': lambda t: max(0.0, min(1.0, t)), 'out': ease_out, 'in': ease_in}
AX = {'x': (1, 0, 0), 'y': (0, 1, 0), 'z': (0, 0, 1)}


def build_tracks(keys):
    params = set()
    for k in keys: params |= set(k[1])
    tr = {}
    for p in params:
        seq = []
        for k in keys:
            e = EASE[k[2]] if len(k) > 2 else smooth
            seq.append((k[0], float(k[1].get(p, 0.0)), e))
        tr[p] = seq
    return tr


def sample(tr, t):
    out = {}
    for p, seq in tr.items(): out[p] = interp_keys(seq, t)
    return out


def author(rig, feet, base_ch, keys, dur, extra=None, base_at=None, verbose=True):
    """returns list of channel dicts for frames 0..N (N = round(dur*30)); base_ch: channel dict, or base_at(f)->channel dict"""
    n = int(round(dur * 30)) + 1
    tr = build_tracks(keys); s = rig.s
    F0 = {}
    P0 = rig.fk(base_ch if base_at is None else base_at(0))
    for k, ft in feet.items(): F0[k] = ft.point(P0)
    out = []; worst = {}
    for f in range(n):
        t = f / 30.0
        v = sample(tr, t)
        if extra: v = extra(t, v)
        bc = base_ch if base_at is None else base_at(f)
        P = rig.fk(bc)
        # rotations in hierarchy order
        for b in rig.names:
            rx, ry, rz = v.get(b + '.rx', 0.0), v.get(b + '.ry', 0.0), v.get(b + '.rz', 0.0)
            if rx == 0 and ry == 0 and rz == 0: continue
            h = P[b].translation.copy()
            for ax, d in (('z', rz), ('y', ry), ('x', rx)):
                if d != 0: rig.rotate_subtree(P, b, h, AX[ax], d)
        # root translation (metres -> arm units)
        rt = Vector((v.get('root.x', 0.0), v.get('root.y', 0.0), v.get('root.z', 0.0))) / s
        if rt.length > 0:
            M = T(rt)
            for b in rig.names: P[b] = M @ P[b]
        # feet
        for k, ft in feet.items():
            if v.get('free.' + k, 0.0) > 0.5: continue
            off = Vector((v.get(f'foot.{k}.x', 0.0), v.get(f'foot.{k}.y', 0.0), v.get(f'foot.{k}.z', 0.0))) / s
            tgt = F0[k] + off
            err = ccd_foot(rig, P, ft, tgt) * s
            worst[k] = max(worst.get(k, 0.0), err)
        out.append(rig.channels(P, prev=(out[-1] if out else base_ch)))
    if verbose: print("AUTHOR frames", n, "max foot IK residual cm", {k: round(x * 100, 2) for k, x in worst.items()})
    return out
