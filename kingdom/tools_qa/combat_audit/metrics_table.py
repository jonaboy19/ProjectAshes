"""Scores combat_studio metrics.json files against animation principles -> markdown table.
usage: python metrics_table.py <metrics.json> [...]   (prints markdown)
Score columns (per main strike = fastest strike):
  antic  frames from clip start (or previous strike end) to windup_end + the backswing distance
  fast   contact frames (tip >= 60 % of the strike peak): 2-4 is snappy, >5 floaty, 1 = a pop
  chain  kinetic-chain order hips<=shoulders<=arm<=hand<=tip (violations count)
  flat   share of blade velocity along the blade flat normal: <0.35 edge leads, >0.6 flat slap
  arc    tip path / chord over the fast frames (1.0 = straight line)
  follow tip travel after the fast frames (m)
  slide  planted-foot slide (cm, l/r)  clipN  frames the blade passes through the body
"""
import json, sys


def grade(s, st):
    issues = []
    ant = st["windup_end"] - s.get("_prev", 0)
    if ant < 3 and st["backswing_m"] < 0.15:
        issues.append("no anticipation")
    cf = st["contact_frames"]
    if cf > 5:
        issues.append("floaty strike (%d fast f)" % cf)
    if cf < 2:
        issues.append("1-frame pop")
    ch = st["chain"]
    order = [ch["hips"], ch["shoulders"], ch["arm"], ch["hand"], ch["tip"]]
    viol = sum(1 for a, b in zip(order, order[1:]) if a > b)
    if order[0] >= order[-1] and viol == 0 and order[0] == order[-1]:
        issues.append("no overlap (all joints peak together)")
    elif viol:
        issues.append("chain out of order")
    if st.get("flat_ratio", 0) > 0.6:
        issues.append("flat slap")
    if st["arc_ratio"] < 1.1:
        issues.append("straight path")
    if st["follow_m"] < 0.25:
        issues.append("no follow-through")
    return issues, viol


rows = []
for p in sys.argv[1:]:
    for c in json.load(open(p)):
        if not c["strikes"]:
            rows.append((c["clip"], c, None, [], 0))
            continue
        st = max(c["strikes"], key=lambda x: x["peak_speed"])
        iss, viol = grade(c, st)
        sl = c["foot_slide_cm"]
        if max(sl["l"], sl["r"]) > 8:
            iss.append("foot slide")
        if c["body_clip_frames"]:
            iss.append("blade through body x%d" % len(c["body_clip_frames"]))
        rows.append((c["clip"], c, st, iss, viol))
print("| clip | len s | hits | windup_end | fast f | peak m/s | chain h/s/a/h/t | flat | arc | follow m | step m | slide cm l/r | issues |")
print("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
for n, c, st, iss, viol in rows:
    if st is None:
        print("| %s | %.2f | 0 | - | - | - | - | - | - | - | - | %s/%s | no strike |" % (n, c["length_s"], c["foot_slide_cm"]["l"], c["foot_slide_cm"]["r"]))
        continue
    ch = st["chain"]
    print("| %s | %.2f | %d | %d | %d | %.0f | %d/%d/%d/%d/%d | %s | %.2f | %.2f | %s | %.0f/%.0f | %s |" % (
        n, c["length_s"], len(c["strikes"]), st["windup_end"], st["contact_frames"], st["peak_speed"],
        ch["hips"], ch["shoulders"], ch["arm"], ch["hand"], ch["tip"], st.get("flat_ratio", "-"), st["arc_ratio"],
        st["follow_m"], c.get("step_in_m", 0), c["foot_slide_cm"]["l"], c["foot_slide_cm"]["r"], "; ".join(iss)))
