"""Build the combat markers sidecar (res://assets/incoming/animations/combat/combat_markers.json) for gameplay timing.

usage: python build_markers.py <out.json> --authored <clips.json>... --metrics <combat_studio metrics.json>... [--aliases]

Per clip (frames at 30 fps, playback rate 1.0; seconds = frame / 30 / rate):
  windup_end     last frame of the anticipation (the loaded pose)
  hit_start/hit_end  the active window: damage may land in [hit_start, hit_end]
  hits           contact frame(s) - hit-stop, sparks, damage; for authored clips the authored contact, else the frame
                 the blade passes through a target 1.3 m in front (combat_studio target_contact), else the tip-speed peak
  trail_start/trail_end  weapon-trail window (WeaponTrail.swing), the blade's fast frames +- 2
  combo_window   [a, b] next attack input accepted/queued -> chain
  cancel_window  [a, b] dodge / move may cancel the recovery
  step_in_m      forward travel the capsule lunge should match (root motion of authored clips, pelvis travel otherwise)
  source         "authored" (events from the key poses) or "measured" (combat_studio)
Authored events win; measured values fill the rest. Library clips with no strike are skipped.
"""
import json, sys

args = sys.argv[1:]
out = args[0]
authored, metrics = [], []
mode = None
aliases = False
for a in args[1:]:
    if a == "--authored":
        mode = authored
    elif a == "--metrics":
        mode = metrics
    elif a == "--aliases":
        aliases = True
    else:
        mode.append(a)

clips = {}
contacts = {}   # clip -> frames the blade crosses the 1.3 m target (all strikes)
# measured first
for p in metrics:
    for c in json.load(open(p)):
        if abs(c.get("rate", 1.0) - 1.0) < 1e-3:
            contacts[c["clip"]] = c.get("target_contact", [])
        if not c.get("strikes") or "markers" not in c:
            continue
        m = c["markers"]
        rate = c.get("rate", 1.0)
        if abs(rate - 1.0) > 1e-3:
            continue          # markers are stored at playback rate 1.0 only
        st = max(c["strikes"], key=lambda s: s["peak_speed"])
        tc = [f for f in c.get("target_contact", []) if st["windup_end"] <= f <= st["follow_end"] + 2]
        hits = [tc[0]] if tc else m["hits"]
        clips[c["clip"]] = {
            "frames": c["frames_at_rate"], "length_s": c["length_s"],
            "windup_end": m["windup_end"], "hit_start": m["hit_start"], "hit_end": m["hit_end"], "hits": hits,
            "trail_start": m["trail_start"], "trail_end": m["trail_end"],
            "combo_window": m["combo_window"], "cancel_window": m["cancel_window"],
            "step_in_m": c.get("step_in_m", 0.0), "contact_on_target": bool(tc),
            "peak_tip_speed": st["peak_speed"], "source": "measured",
        }
# authored events override
for p in authored:
    for c in json.load(open(p)):
        e = c.get("events", {})
        if "hit" not in e and "release" not in e and "contact" not in e:
            clips.setdefault(c["name"], {}).update({"frames": c["frames"], "length_s": c["seconds"], "events": e,
                                                     "source": "authored", "step_in_m": c.get("root_motion_m", 0.0)})
            continue
        d = clips.setdefault(c["name"], {})
        hit = e.get("hit", e.get("release", e.get("contact")))
        hs = e.get("hit_start", hit)
        he = e.get("hit_end", hit)
        d.update({
            "frames": c["frames"], "length_s": c["seconds"],
            "windup_end": e.get("windup_end", max(hit - 3, 0)), "hit_start": hs, "hit_end": he,
            "hits": e.get("hits", [hit]),
            "trail_start": max(hs - 2, 0), "trail_end": he + 2,
            "combo_window": e.get("combo_window", []), "cancel_window": e.get("cancel_window", [he + 4, c["frames"] - 1]),
            "step_in_m": c.get("root_motion_m", 0.0), "source": "authored", "events": e,
        })
        if "step" in e:
            d["step_frames"] = e["step"]
        tc = contacts.get(c["name"], [])
        d["contact_on_target"] = any(abs(f - h) <= 1 for f in tc for h in d["hits"])

doc = {"version": 1, "fps": 30,
       "doc": "docs/anim/COMBAT_AUDIT.md; built by kingdom/tools/anim/combat/build_markers.py. Frames at 30 fps, rate 1.0.",
       "clips": dict(sorted(clips.items()))}
if aliases:
    doc["aliases"] = {"1H_Melee_Attack_Chop": "Sword_Regular_A", "1H_Melee_Attack_Slice_Diagonal": "Sword_Regular_B",
                      "1H_Melee_Attack_Slice_Horizontal": "Sword_Regular_C", "1H_Melee_Attack_Stab": "Sword_Attack",
                      "Block_Hit": "Sword_Block", "Hit_A": "Hit_Chest", "Hit_B": "Hit_Knockback"}
json.dump(doc, open(out, "w"), indent=1)
print("markers:", len(clips), "clips ->", out)
