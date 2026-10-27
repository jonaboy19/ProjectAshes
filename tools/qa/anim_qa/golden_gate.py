#!/usr/bin/env python
"""Golden-set gate (docs/plans/AAA_FINISH_PLAN.md section B).

Reads the per-clip measurements written by `anim_qa.gd --library=...` (docs/qa/golden/golden_library_*.json, every clip
of the game library on a reference rig) and the catalog CSV (creatures/animals, docs/qa/anim_qa_results.csv), grades each
clip against the B1 gold / probation / ban thresholds, merges the result and the human frame-sheet reviews
(docs/qa/golden/reviews.json) into kingdom/data/anim/golden_set.json and writes docs/qa/golden/golden_results.csv +
golden_report.md.

A clip is "gold" only if every automated metric is gold AND reviews.json has a `pass` verdict for it. Metrics-only
clips stay "probation"; metric failures are "banned" (whatever the review says).

  py -E -B tools/qa/anim_qa/golden_gate.py            # regenerate golden_set.json + reports
  py -E -B tools/qa/anim_qa/golden_gate.py --check    # exit 1 if a clip listed as gold now fails (no files written)

Deviation from the plan text: the plan names `golden_gate.gd`; the measurement lives in anim_qa.gd (library mode, it already
has the skinning/foot-contact code) and the grading/merging lives here.
"""
import csv
import datetime
import glob
import json
import os
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
QA = os.path.join(REPO, "docs", "qa")
GOLD_DIR = os.path.join(QA, "golden")
SET_PATH = os.path.join(REPO, "kingdom", "data", "anim", "golden_set.json")
SLOTS_PATH = os.path.join(REPO, "kingdom", "data", "anim", "golden_slots.json")
REVIEWS_PATH = os.path.join(GOLD_DIR, "reviews.json")
CANDIDATES_PATH = os.path.join(REPO, "kingdom", "data", "anim", "golden_candidates.json")

# B1 thresholds. Slide values in m/s (anim_qa reports cm/s). `pops`: the plan says any pop bans; anim_qa's own FAIL is > 3.
T = {
    "slide_mean": (0.03, 0.05), "slide_max": (0.10, 0.15),
    "pen_cm": (1.0, 2.0), "hover_cm": (2.0, 3.0),
    "seam_deg": (3.0, 6.0), "seam_cm": (1.0, 3.0),
    "stretch_pct": (0.5, 1.0), "scale_pct": (1.0, 5.0),
    "drift_cm": (3.0, 15.0),
}
POPS_BAN = 4          # 1-3 pops = probation, >= 4 = banned (decision recorded in AAA_PROGRESS.md)
ORDER = {"gold": 0, "probation": 1, "banned": 2}


def worse(a, b):
    return a if ORDER[a] >= ORDER[b] else b


def band(value, key):
    g, p = T[key]
    if value <= g:
        return "gold"
    if value <= p:
        return "probation"
    return "banned"


WATER_PREFIXES = ("Swim_", "Tread_", "Dive_")


def grade_library_row(m, clip=""):
    """B1 grading of one library-mode measurement. Returns (verdict, reasons).
    Water clips (WATER_PREFIXES) are played floating in water, never on the ground plane the library measures against: their
    ground metrics (penetration, float, slide) are not graded (the body hangs below the surface by design); everything else is."""
    kind = m["kind"]
    verdict = "gold"
    reasons = []

    def hit(v, why):
        nonlocal verdict
        if v != "gold":
            reasons.append("%s: %s" % (v, why))
        verdict = worse(verdict, v)

    tp = m["checks"].get("tpose")          # only graded for bipeds by anim_qa; quadruped rests are not T-poses
    if tp == "FAIL":
        hit("banned", "%d T-pose frame(s)" % m["tpose_frames"])
    elif tp == "WARN":
        hit("probation", "1 T-pose frame")
    if m["checks"].get("direction") == "FAIL":
        hit("banned", "planted feet move forward (moonwalk)")
    if m["stretch_pct"] > 0:
        hit(band(m["stretch_pct"], "stretch_pct"), "bone stretch %.1f%%" % m["stretch_pct"])
    if m["scale_pct"] > 0:
        hit(band(m["scale_pct"], "scale_pct"), "scale keys %.1f%%" % m["scale_pct"])
    if m["pops"] > 0:
        hit("banned" if m["pops"] >= POPS_BAN else "probation", "%d pop(s)" % m["pops"])
    upper = m.get("upper", False)
    if clip.startswith(WATER_PREFIXES):
        reasons.append("note: water clip, ground metrics not graded")
    elif not upper:
        hit(band(m["pen_cm"], "pen_cm"), "ground penetration %.1f cm" % m["pen_cm"])
        if kind in ("loco", "loop"):
            hit(band(m["hover_cm"], "hover_cm"), "float %.1f cm" % m["hover_cm"])
            if m["slide_mean"] >= 0:
                hit(band(m["slide_mean"] / 100.0, "slide_mean"), "slide mean %.2f m/s" % (m["slide_mean"] / 100.0))
                hit(band(m["slide_max"] / 100.0, "slide_max"), "slide max %.2f m/s" % (m["slide_max"] / 100.0))
            else:
                reasons.append("note: slide unscored (no usable ground-speed reference)")
                verdict = worse(verdict, "probation")
    if kind in ("loco", "loop"):
        hit(band(m["seam_deg"], "seam_deg"), "loop seam %.1f deg" % m["seam_deg"])
        hit(band(m["seam_cm"], "seam_cm"), "loop seam hips %.1f cm" % m["seam_cm"])
        if m["drift_cm"] > T["drift_cm"][0]:
            hit("banned" if m["drift_cm"] > T["drift_cm"][1] else "probation", "hips drift %.0f cm per loop" % m["drift_cm"])
    if kind == "death" and m["checks"].get("death_rest") == "FAIL":
        hit("probation", "death ends far above the floor")
    return verdict, reasons


def category_of(clip):
    c = clip
    if c.startswith(("Loco_", "Walk", "Jog", "Run", "Sprint", "Strafe", "Idle", "Crouch", "Turn", "Swim")):
        return "locomotion"
    if c.startswith(("Vault", "Mantle", "Ledge", "Climb", "Wall", "Ladder", "Slide", "Jump", "Fall", "Land", "Roll", "Drop")):
        return "traversal"
    if c.startswith(("Life_", "Sit", "Farm", "Interact", "PickUp", "Pickup", "TreeChopping", "Fishing", "Talk", "Push", "Pull",
                     "Chest", "Consume", "Walk_Carry", "Idle_Talking", "Cheer", "Yes", "No")):
        return "interaction"
    if c.startswith(("Death", "Dead", "Down")):
        return "death"
    return "combat"


CATEGORY_FALLBACK = {"locomotion": "Idle", "traversal": "Idle", "interaction": "Idle", "combat": "Idle", "death": "Death01",
                     "creature": "Idle"}


def load_library_jsons():
    out = {}
    for p in sorted(glob.glob(os.path.join(GOLD_DIR, "golden_library_*.json"))):
        with open(p, encoding="utf-8") as f:
            for subject, clips in json.load(f).items():
                out.setdefault(subject, {}).update(clips)
    return out


def load_catalog_csv():
    rows = {}
    p = os.path.join(QA, "anim_qa_results.csv")
    if not os.path.exists(p):
        return rows
    with open(p, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            rows[(r["subject"], r["clip"])] = r
    return rows


def load_json(path, default):
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    return default


def main():
    check = "--check" in sys.argv
    lib = load_library_jsons()
    csv_rows = load_catalog_csv()
    reviews = load_json(REVIEWS_PATH, {})
    slots_src = load_json(SLOTS_PATH, {"slots": {}})
    candidates = load_json(CANDIDATES_PATH, {"clips": {}})
    old = load_json(SET_PATH, {"clips": {}})
    clips = {}
    today = datetime.date.today().isoformat()

    # --- humanoid library (rig "ual"): measured on the reference subject(s); worst verdict over subjects wins
    for subject, measured in lib.items():
        group = "ual"
        if subject.startswith("animal_") or subject.startswith("q_") or subject.startswith("meshy_"):
            group = subject
        for clip, m in measured.items():
            key = clip if group == "ual" else "%s/%s" % (subject, clip)
            verdict, reasons = grade_library_row(m, clip)
            cat = category_of(clip) if group == "ual" else "creature"
            entry = clips.get(key)
            if entry is not None:
                verdict = worse(verdict, entry["auto"])
                reasons = entry["why_list"] + reasons
            clips[key] = {"rig": group, "category": cat, "auto": verdict, "why_list": reasons, "kind": m["kind"],
                          "length_s": round(m["length"], 3),
                          "metrics": {"slide_mean": round(max(m["slide_mean"], 0.0) / 100.0, 3) if m["slide_mean"] >= 0 else None,
                                      "slide_max": round(max(m["slide_max"], 0.0) / 100.0, 3) if m["slide_max"] >= 0 else None,
                                      "pen_cm": round(m["pen_cm"], 2), "float_cm": round(m["hover_cm"], 2), "pops": m["pops"],
                                      "seam_deg": round(m["seam_deg"], 2) if m["kind"] in ("loco", "loop") else None,
                                      "drift_cm": round(m["drift_cm"], 1), "speed": round(m["ground_speed"], 2) or None,
                                      "stretch_pct": round(m["stretch_pct"], 2)},
                          "foot_contacts": {b: w for b, w in (m.get("contacts") or {}).items()},
                          "contacts_fps": m.get("contacts_fps", 30), "upper": m.get("upper", False)}

    # --- catalog CSV rows for subjects that were not measured in library mode (seed: PASS/WARN -> probation, FAIL -> banned)
    for (subject, clip), r in csv_rows.items():
        group = r["group"]
        if group in ("villagers", "armored"):
            continue                  # the UAL library measurement is authoritative for humanoids
        key = "%s/%s" % (subject, clip)
        if key in clips:
            continue
        st = r["status"]
        verdict = "banned" if st == "FAIL" else "probation"
        clips[key] = {"rig": subject, "category": "creature", "auto": verdict,
                      "why_list": [r["notes"]] if r["notes"] else [], "kind": r["kind"], "length_s": float(r["length_s"] or 0),
                      "metrics": {"slide_p75": float(r["slide_cm_s"] or -1) / 100.0 if r["slide_cm_s"] not in ("", "-1.0") else None,
                                  "pen_cm": float(r["penetration_cm"] or 0), "float_cm": float(r["hover_cm"] or 0),
                                  "pops": int(r["pops"] or 0), "seam_deg": float(r["seam_deg"] or 0),
                                  "stretch_pct": float(r["stretch_pct"] or 0)},
                      "foot_contacts": {}, "contacts_fps": 30, "upper": False, "seed": "anim_qa_results.csv"}

    # --- candidate clips that do not exist in the library yet (Meshy, UAL2 extras ...): probation until retargeted + measured
    for name, c in candidates.get("clips", {}).items():
        if name in clips:
            continue
        clips[name] = {"rig": c.get("rig", "ual"), "category": c.get("category", "interaction"), "auto": "probation",
                       "why_list": ["candidate: " + c.get("why", "not yet retargeted/measured")], "kind": c.get("kind", "once"),
                       "length_s": c.get("length_s", 0), "metrics": {}, "foot_contacts": {}, "contacts_fps": 30, "upper": False,
                       "candidate": True, "source": c.get("source", "")}

    # --- status = auto verdict, promoted to gold only by a passing review
    failures = []
    out_clips = {}
    for key in sorted(clips):
        c = clips[key]
        auto = c.pop("auto")
        why = c.pop("why_list")
        rv = reviews.get(key)
        status = auto
        if auto == "gold":
            status = "gold" if (rv and rv.get("verdict") == "pass") else "probation"
            if status == "probation":
                why = why + ["metrics gold, no passing frame-sheet review yet"]
        if rv and rv.get("verdict") == "fail" and status != "banned":
            status = "banned"
            why = why + ["frame-sheet review: fail (%s)" % rv.get("note", "")]
        if rv:
            c["review"] = rv
        if c.get("candidate"):
            status = "probation"
        was = old.get("clips", {}).get(key, {}).get("status")
        if was == "gold" and status != "gold":
            failures.append((key, why))
        c["status"] = status
        c["why"] = "; ".join(w for w in why if w)
        if key in ("Idle",) or c["category"] == "creature":
            pass
        out_clips[key] = c

    if check:
        for k, why in failures:
            print("GOLD CLIP NOW FAILS:", k, why)
        print("gold:", sum(1 for c in out_clips.values() if c["status"] == "gold"), "failures:", len(failures))
        sys.exit(1 if failures else 0)

    # --- slots: authored in golden_slots.json; validated against the clip table
    slots = {}
    for sid, s in slots_src.get("slots", {}).items():
        slots[sid] = dict(s)
        slots[sid].setdefault("variants", [])
        names = [s.get("primary", "")] + list(s.get("variants", []))
        missing = [n for n in names if n and n not in out_clips]
        if missing:
            slots[sid]["missing_clips"] = missing

    # banned clips that gameplay code still names (CharacterAnimator.PREFERRED_CLIPS values): accepted until S3-S5 replace them
    import re
    ca = open(os.path.join(REPO, "kingdom", "scripts", "actors", "character_animator.gd"), encoding="utf-8").read()
    m_pc = re.search(r"const PREFERRED_CLIPS := \{([^}]*)\}", ca)
    named = re.findall(r':\s*"([A-Za-z0-9_]+)"', m_pc.group(1)) if m_pc else []
    accepted_gaps = sorted(n for n in set(named) if out_clips.get(n, {}).get("status") == "banned")

    data = {"_doc": "Generated by tools/qa/anim_qa/golden_gate.py from docs/qa/golden/golden_library_*.json + reviews.json + "
                    "golden_slots.json + golden_candidates.json. See docs/plans/AAA_FINISH_PLAN.md A3/B. Do not hand-edit statuses.",
            "version": 1, "enforce": bool(old.get("enforce", False)), "generated": today,
            "category_fallback": CATEGORY_FALLBACK, "accepted_gaps": accepted_gaps, "slots": slots, "clips": out_clips}
    os.makedirs(os.path.dirname(SET_PATH), exist_ok=True)
    with open(SET_PATH, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=1, sort_keys=False)
        f.write("\n")

    # --- reports
    os.makedirs(GOLD_DIR, exist_ok=True)
    with open(os.path.join(GOLD_DIR, "golden_results.csv"), "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["clip", "rig", "category", "kind", "length_s", "status", "slide_mean", "slide_max", "pen_cm", "float_cm", "pops",
                    "seam_deg", "drift_cm", "stretch_pct", "review", "why"])
        for k, c in out_clips.items():
            m = c["metrics"]
            w.writerow([k, c["rig"], c["category"], c["kind"], c["length_s"], c["status"], m.get("slide_mean"), m.get("slide_max"),
                        m.get("pen_cm"), m.get("float_cm"), m.get("pops"), m.get("seam_deg"), m.get("drift_cm"),
                        m.get("stretch_pct"), c.get("review", {}).get("verdict", ""), c["why"]])
    counts = {}
    for c in out_clips.values():
        counts.setdefault(c["category"], {"gold": 0, "probation": 0, "banned": 0})[c["status"]] += 1
    lines = ["# Golden set report", "", "Generated %s by `tools/qa/anim_qa/golden_gate.py`." % today, "",
             "| category | gold | probation | banned |", "|---|---:|---:|---:|"]
    tot = {"gold": 0, "probation": 0, "banned": 0}
    for cat in sorted(counts):
        n = counts[cat]
        lines.append("| %s | %d | %d | %d |" % (cat, n["gold"], n["probation"], n["banned"]))
        for k in tot:
            tot[k] += n[k]
    lines.append("| **total** | %d | %d | %d |" % (tot["gold"], tot["probation"], tot["banned"]))
    gaps = [(sid, s) for sid, s in slots.items() if s.get("missing_clips")]
    lines += ["", "## Slots", "", "%d slots; %d reference clips that are not in the library." % (len(slots), len(gaps))]
    for sid, s in gaps:
        lines.append("- `%s`: missing %s" % (sid, ", ".join(s["missing_clips"])))
    with open(os.path.join(GOLD_DIR, "golden_report.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(json.dumps(counts))
    print("total", tot, "slots", len(slots))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
