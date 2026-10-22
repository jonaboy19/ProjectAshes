"""Format the METRICS.txt of docs/anim/free_library/frames/traversal_v2/ from the scan_motion.py JSON files (plain python, no Blender).
  python metrics_report.py <scan_before.json> <scan_after.json> <pivot_report.json> <out.txt>
"""
import sys, json

before = json.load(open(sys.argv[1]))
after = json.load(open(sys.argv[2]))
pivot = json.load(open(sys.argv[3]))
out = open(sys.argv[4], "w", newline="\n")


def w(s=""):
    out.write(s + "\n")


def gmax(d, key, groups):
    best = None
    for g in groups:
        v = d["groups"][g][key]
        if best is None or v[0] > best[0]:
            best = v
    return best


JOINTS = ["trunk(pelvis,spine,neck,head)", "hip(thigh)", "shoulder(upperarm)", "elbow(lowerarm)", "knee(calf)"]
ENDS = ["hand", "foot"]


def fmt(v, unit):
    return "%6.3f%s %s@%d" % (v[0], unit, v[1], v[2]) if unit == "m" else "%5.1f%s %s@%d" % (v[0], unit, v[1], v[2])


w("Traversal v2.1 - measured motion and contact numbers (30 fps, exported GLB, scan_motion.py + pivot180_rebuild.py)")
w("=" * 118)
w()
w("A. Per-frame motion limits: 0.12 m and 35 degrees per 30 fps frame")
w("   'charspace' = bone head delta with the root motion removed (the animation itself); 'world' includes the root travel.")
w("   Joints = trunk, hips, shoulders, elbows, knees. Hands / feet are end effectors (whips allowed: arm throw of a jump, leg swing over an obstacle, leg extension before a landing).")
w("   BEFORE = the committed UAL_Authored_Traversal.glb (14 clips), AFTER = this commit.")
w()
w("%-24s | %-44s | %-44s" % ("clip", "BEFORE worst joint charspace / rot", "AFTER worst joint charspace / rot"))
w("-" * 118)
for name in sorted(after):
    a = after[name]
    b = before.get(name)
    aj = gmax(a, "charspace_m", JOINTS)
    ar = gmax(a, "rot_deg", JOINTS)
    s_a = "%s | %s" % (fmt(aj, "m"), fmt(ar, "deg"))
    if b:
        bj = gmax(b, "charspace_m", JOINTS)
        br = gmax(b, "rot_deg", JOINTS)
        s_b = "%s | %s" % (fmt(bj, "m"), fmt(br, "deg"))
    else:
        s_b = "(new clip)"
    w("%-24s | %-44s | %-44s" % (name, s_b, s_a))
w()
w("Frames over the limit (character space, all body bones incl. hands / feet; the raw lists are in the JSON of the scan):")
w("%-24s | %-22s | %-22s" % ("clip", "BEFORE >0.12 m / >35 deg", "AFTER >0.12 m / >35 deg"))
for name in sorted(after):
    a = after[name]["n_frames_over_limit"]
    b = before.get(name, {}).get("n_frames_over_limit")
    w("%-24s | %-22s | %-22s" % (name, ("%d / %d frames" % (b["charspace_0.12m"], b["rot_35deg"])) if b else "(new)", "%d / %d frames" % (a["charspace_0.12m"], a["rot_35deg"])))
w()
w("A2. The vault calf snap (Vault_Low, Vault_Low_B)")
for name in ("Vault_Low", "Vault_Low_B"):
    b, a = before[name], after[name]
    w("  %-12s calf (knee) max move per frame   BEFORE world %s   charspace %s" % (name, fmt(b["groups"]["knee(calf)"]["world_m"], "m"), fmt(b["groups"]["knee(calf)"]["charspace_m"], "m")))
    w("  %-12s                                  AFTER  world %s   charspace %s" % ("", fmt(a["groups"]["knee(calf)"]["world_m"], "m"), fmt(a["groups"]["knee(calf)"]["charspace_m"], "m")))
    w("  %-12s calf rotation                    BEFORE %s   AFTER %s" % ("", fmt(b["groups"]["knee(calf)"]["rot_deg"], "deg"), fmt(a["groups"]["knee(calf)"]["rot_deg"], "deg")))
    w("  %-12s any joint, charspace             BEFORE %s   AFTER %s" % ("", fmt(gmax(b, "charspace_m", JOINTS), "m"), fmt(gmax(a, "charspace_m", JOINTS), "m")))
    w("  %-12s hand / foot (whips), charspace   BEFORE %s / %s   AFTER %s / %s" % ("", fmt(gmax(b, "charspace_m", ["hand"]), "m"), fmt(gmax(b, "charspace_m", ["foot"]), "m"),
                                                                                    fmt(gmax(a, "charspace_m", ["hand"]), "m"), fmt(gmax(a, "charspace_m", ["foot"]), "m")))
w("  Cause (see traversal_v2_HANDOFF.md): pelvis anchor released 0.5 m in 3 frames + knee pole direction changed 0.6 in one frame + landing leg extension in 5 frames.")
w("  Fix: continuous pelvis path, smoothed pole keys, 8-frame leg extension, pole continuity in the bake (trav_lib.solve_continuous).")
w()
w("Worst end-effector whips per clip (AFTER, charspace; hand / foot):")
for name in sorted(after):
    a = after[name]
    w("  %-24s hand %s   foot %s" % (name, fmt(a["groups"]["hand"]["charspace_m"], "m"), fmt(a["groups"]["foot"]["charspace_m"], "m")))
w()
w("B. World-locked contacts on the exported GLB (largest drift of the wrist / ball of the foot from its mean over the window, cm)")
for name in sorted(after):
    c = after[name].get("contact_drift_cm")
    if not c:
        continue
    w("  %-16s max %.2f cm   %s" % (name, max(x[3] for x in c), ", ".join("%s f%d-%d %.2f" % (x[0], x[1], x[2], x[3]) for x in c)))
w()
w("C. Loop points (last frame vs first frame, root travel removed): max bone position gap (cm) / max bone rotation gap (deg)")
for name in sorted(after):
    a = after[name]
    if "loop_gap_cm" in a:
        w("  %-24s %6.2f cm / %5.2f deg" % (name, a["loop_gap_cm"], a["loop_gap_deg"]))
w()
w("D. Ride_Trot_Loop (rising trot): pelvis height range above the ground (m) per clip AFTER")
for name in ("Ride_Idle_Loop", "Ride_Walk_Loop", "Ride_Trot_Loop", "Ride_Gallop_Loop"):
    a = after[name]
    b = before[name]
    w("  %-18s pelvis z %.3f..%.3f (range %.3f m)   BEFORE %.3f..%.3f (range %.3f m)" % (name, a["pelvis_z_range_m"][0], a["pelvis_z_range_m"][1], a["pelvis_z_range_m"][1] - a["pelvis_z_range_m"][0],
                                                                                         b["pelvis_z_range_m"][0], b["pelvis_z_range_m"][1], b["pelvis_z_range_m"][1] - b["pelvis_z_range_m"][0]) if "pelvis_z_range_m" in b else
      "  %-18s pelvis z %.3f..%.3f (range %.3f m)" % (name, a["pelvis_z_range_m"][0], a["pelvis_z_range_m"][1], a["pelvis_z_range_m"][1] - a["pelvis_z_range_m"][0]))
w()
w("E. Loco_Pivot180_Run_L / _R (tools/anim/loco/pivot180_rebuild.py)")
for r in pivot:
    w("  %s (%d frames): pivot foot %s locked f%d-%d, slip BEFORE %.1f cm -> AFTER %.1f cm; push-off foot %s locked f%d-%d, slide BEFORE %.1f cm -> AFTER %.1f cm; IK reach error %s cm"
      % (r["clip"], r["frames"], r["pivot_foot"], r["pivot_lock_frames"][0], r["pivot_lock_frames"][1], r["pivot_slip_cm_before"], r["pivot_slip_cm_after"], r["push_foot"],
         r["push_lock_frames"][0], r["push_lock_frames"][1], r["push_slip_cm_before"], r["push_slip_cm_after"], r["ik_reach_err_cm"]))
    w("     max bone rotation per frame BEFORE %s AFTER %s; max pelvis-to-chest twist/lean BEFORE %.1f deg AFTER %.1f deg" % (r["max_bone_rot_deg_per_frame_before"],
      r["max_bone_rot_deg_per_frame_after"], r["max_pelvis_to_chest_angle_deg_before"], r["max_pelvis_to_chest_angle_deg_after"]))
w()
out.close()
