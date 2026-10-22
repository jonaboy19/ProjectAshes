"""Per-swing sync report from combat_capture telemetry.csv (docs/anim/COMBAT_AUDIT.md).

For every player swing (swing_id increments) it prints, in movie frames relative to the swing start:
  - the blade tip speed curve (per rendered frame) and its peak frame,
  - the first hit-stop frame (Engine.time_scale < 0.5) and how many frames the freeze lasted,
  - the frames the tip is 'fast' (>= 60 % of the swing's peak),
and for enemies the wind-up length and contact frame.
usage: python analyse_capture.py <capture dir> [scenario_prefix]
"""
import csv, sys, os, collections

d = sys.argv[1]
pref = sys.argv[2] if len(sys.argv) > 2 else ""
rows = list(csv.DictReader(open(os.path.join(d, "telemetry.csv"))))
by = collections.OrderedDict()
for r in rows:
    if r["scenario"] in ("gap", "boot") or not r["scenario"].startswith(pref):
        continue
    by.setdefault(r["scenario"], []).append(r)
for scn, rs in by.items():
    print("==", scn, len(rs), "frames")
    swings = collections.OrderedDict()
    for i, r in enumerate(rs):
        sid = int(r["swing_id"])
        if float(r["swing"]) > 0 or (swings and sid in swings):
            swings.setdefault(sid, []).append((i, r))
    prev_id = None
    for sid, lst in swings.items():
        i0 = lst[0][0]
        seg = rs[i0:i0 + 30]
        sp = [float(x["tip_speed"]) for x in seg]
        if not sp:
            continue
        pk = max(range(len(sp)), key=lambda k: sp[k])
        fast = [k for k, v in enumerate(sp) if v >= 0.6 * sp[pk]]
        hs = [k for k, x in enumerate(seg) if float(x["time_scale"]) < 0.5]
        clip = seg[0]["upper_clip"]
        print("  swing %d %-34s start f%s | tip peak f+%d (%.1f m/s) fast %s | hitstop %s | curve %s" % (
            sid, clip, seg[0]["sf"], pk, sp[pk], (fast[0], fast[-1]) if fast else "-",
            ("f+%d x%d" % (hs[0], len(hs))) if hs else "none",
            " ".join("%.0f" % v for v in sp[:22])))
    # enemy wind-ups
    wind = []
    for i, r in enumerate(rs):
        w = float(r["e_winding"] or 0)
        pw = float(rs[i - 1]["e_winding"] or 0) if i else 0
        if w > 0 and pw <= 0:
            wind.append([i, None])
        if w <= 0 and pw > 0 and wind and wind[-1][1] is None:
            wind[-1][1] = i
    for a, b in wind:
        hp0 = int(rs[a]["player_hp"])
        hit = next((k for k in range(a, min(len(rs), (b or a) + 12)) if int(rs[k]["player_hp"]) < hp0), None)
        print("  enemy windup f%d..f%s (%s frames) clip %s | player hp drop at %s" % (
            a, b, (b - a) if b else "?", rs[a]["e_clip"], ("f%d" % hit) if hit is not None else "none"))
