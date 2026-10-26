"""Adds the AAA NPC swing clips to animations/combat/combat_markers.json (frames at 30 fps, rate 1.0, keyed by the game clip name).

Inputs: the measure_events.gd output of each pack (the hands' speed peaks; run
  godot --headless --path kingdom -s tools/anim/measure_events.gd -- --glb=res://assets/incoming/animations/aaa/UAL_AAA_<Pack>.glb --json=<dir>/<Pack>.json --limbs=all
for Combat_Chains, Combat_Adv and Combat_Weapons) and the manifest (data/anim/aaa_clips.json, for the trim windows).
Run:  python kingdom/tools/anim/aaa/build_markers.py <events_dir>
The contact frame per clip is chosen from the measured strike list by eye on the review sheets (docs/anim/aaa_wiring/review/p07, p09-p11)
and written as HIT below (source-clip frame); trimmed clips are re-based by the trim start.
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
KING = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
MARK = os.path.join(KING, "assets", "incoming", "animations", "combat", "combat_markers.json")
MAN = os.path.join(KING, "data", "anim", "aaa_clips.json")
EV = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.environ.get("TEMP", "/tmp"), "aaa_events")

# game name -> (pack, source clip, contact frame in the source clip)
HIT = {
    "Bandit_Light_1": ("Combat_Chains", "Sword_Light_Attack_01", 26),
    "Bandit_Light_2": ("Combat_Chains", "Sword_Light_Attack_02", 22),
    "Bandit_Light_3": ("Combat_Chains", "Sword_Light_Attack_03", 32),
    "Bandit_Heavy_Chop": ("Combat_Chains", "Sword_Heavy_Charge_Chop", 51),
    "Duel_Parry_High": ("Combat_Adv", "Parry_High_Deflect", 46),
    "Duel_Riposte": ("Combat_Adv", "Parry_Sword_Riposte", 93),
    "Duel_Lunge": ("Combat_Adv", "Combat_Fencing_Lunge", 51),
    "GS_Overhead": ("Combat_Weapons", "2H_Greatsword_Overhead_Chop", 25),
    "GS_Slash": ("Combat_Weapons", "2H_Greatsword_Slash_Horizontal", 16),
    "GS_Spin": ("Combat_Weapons", "2H_Greatsword_Spin_Cleave", 38),
    "GS_Thrust": ("Combat_Weapons", "2H_Greatsword_Thrust_Lunge", 11),
}

man = json.load(open(MAN))
trims = {}
for pack, clips in man["packs"].items():
    for c, e in clips.items():
        if e.get("as") and e.get("trim"):
            trims[e["as"]] = e["trim"]
ev = {}
for p in ("Combat_Chains", "Combat_Adv", "Combat_Weapons"):
    ev[p] = json.load(open(os.path.join(EV, p + ".json")))

doc = json.load(open(MARK))
for name, (pack, src, hit) in HIT.items():
    c = ev[pack][src]
    t0 = trims.get(name, [0.0, c["len_s"]])[0]
    t1 = trims.get(name, [0.0, c["len_s"]])[1]
    off = int(round(t0 * 30))
    frames = int(round((t1 - t0) * 30))
    h = hit - off
    assert 0 < h < frames, (name, h, frames)
    peak = c["peak_frame"] - off
    doc["clips"][name] = {
        "frames": frames, "length_s": round(frames / 30.0, 3),
        "windup_end": max(h - 4, 0), "hit_start": max(h - 2, 0), "hit_end": min(h + 2, frames), "hits": [h],
        "trail_start": max(h - 5, 0), "trail_end": min(h + 3, frames),
        "combo_window": [min(h + 3, frames), frames], "cancel_window": [min(h + max((frames - h) // 2, 2), frames), frames],
        "step_in_m": 0.0, "contact_on_target": False, "peak_tip_speed": c["peak_speed"], "source": "measured",
    }
with open(MARK, "w", encoding="utf-8", newline="\n") as fh:
    json.dump(doc, fh, indent=1)
    fh.write("\n")
print("markers:", ", ".join(HIT))
