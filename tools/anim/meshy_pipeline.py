"""meshy_pipeline.py - Meshy results straight into the game (motions; models are listed only).

  python tools/anim/meshy_pipeline.py all --downloads <dir> [--queue tools/anim/meshy_queue_2026-10-28.json]
  python tools/anim/meshy_pipeline.py wire [--apply]        # after the check sheets were looked at (reviews.json)

Steps (each also runs on its own: retarget | sheet | measure | grade | wire):
  retarget  <dir>/<id>.bvh (text-to-motion, rig meshy_bvh) or <id>.glb (rigged export, rig meshy, action = first) ->
            tools/anim/mixamo_to_ual.py (direction-matched retarget, foot lock, contact IK, knee lift, loop crossfade)
            -> kingdom/assets/incoming/animations/life/UAL_Life_Meshy.glb + .life.json sidecar from the queue
            (category, loop, props, contact_ik / hand_contact, seat_back, source prompt).
  sheet     tools/anim/mixamo_check_sheet.py -> docs/qa/golden/meshy/sheet_<n>.jpg  (LOOK at them)
  measure   Godot import, then anim_qa library mode on player_young + villager_man_a + villager_woman_a with the Meshy
            library temporarily appended to Assets.UAL_FILES (restored after, .import churn reverted).
  grade     golden_gate thresholds per rig (woman: dress-hem penetration ignored) -> docs/qa/golden/meshy/grades.json and
            golden_library_meshy.json (so golden_gate.py picks the clips up); prints gold / probation / banned + reasons.
  wire      clips that are metrics-gold on all rigs AND have a `pass` verdict in docs/qa/golden/reviews.json are added to
            their queue target (smart_objects.json type / key); targets with "enable": true are re-enabled (the audit
            disabled nail_plank, wash_tub, laundry_line). Dry run unless --apply.
One Godot at a time; never edits files other than the Meshy library, its sidecar, smart_objects.json (wire --apply) and
the docs/qa/golden/meshy reports.
"""
import json
import os
import re
import subprocess
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
K = os.path.join(REPO, "kingdom")
BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
GODOT = os.environ.get("GODOT", r"C:\Users\Jonna\Downloads\Godot_v4.6.3-stable_win64\Godot_v4.6.3-stable_win64.exe")
LIB = os.path.join(K, "assets", "incoming", "animations", "life", "UAL_Life_Meshy.glb")
LIB_RES = "res://assets/incoming/animations/life/UAL_Life_Meshy.glb"
OUT = os.path.join(REPO, "docs", "qa", "golden", "meshy")
SUBJECTS = "player_young,villager_man_a,villager_woman_a"


def args():
    global LIB, OUT, LIB_RES
    a = {"step": sys.argv[1] if len(sys.argv) > 1 else "all", "queue": os.path.join(REPO, "tools", "anim", "meshy_queue_2026-10-28.json"),
         "downloads": "", "apply": False}
    i = 2
    while i < len(sys.argv):
        k = sys.argv[i].lstrip("-")
        if k == "apply":
            a["apply"] = True
            i += 1
        else:
            a[k] = sys.argv[i + 1]
            i += 2
    if a.get("lib"):
        LIB = os.path.abspath(a["lib"])      # another library (Mixamo packs) or a scratch one for tests
        if LIB.replace("\\", "/").startswith(K.replace("\\", "/") + "/"):
            LIB_RES = "res://" + os.path.relpath(LIB, K).replace("\\", "/")
    if a.get("out"):
        OUT = os.path.abspath(a["out"])
    return a


def queue(a):
    return json.load(open(a["queue"], encoding="utf-8"))


def present(a, q):
    """Queue motions whose download exists: [(motion, path, rig)]."""
    out = []
    for m in q["motions"]:
        for ext, rig in ((".fbx", "meshy_fbx"), (".bvh", "meshy_bvh"), (".glb", "meshy")):
            p = os.path.join(a["downloads"], m["id"] + ext)
            if os.path.exists(p):
                out.append((m, p, rig))
                break
    return out


def spec_of(m, path, rig):
    c = {"name": m["clip"], "file": os.path.basename(path), "loop": bool(m.get("loop")), "inplace": m.get("inplace", "none")}
    for k in ("foot_lock", "knee_lift", "hand_margin_extra", "lift_m", "contact_ik", "lock_vel", "lock_wander", "ik_smooth", "toe_floor", "shift_m", "reverse", "lift_ramp", "yaw_deg", "yaw_shift"):
        if k in m and k != "contact_ik":
            c[k] = m[k]
    if m.get("contact_ik"):
        c["knee_lift"] = True
    if m.get("lift_to_floor"):
        c.update(floor="min", contact=True)
    if rig == "meshy":
        c["action"] = m.get("action", "")    # empty: mixamo_to_ual takes the GLB's first action
    return c


def retarget(a, q):
    items = present(a, q)
    if not items:
        sys.exit("no downloads found in %s (expect <id>.bvh / <id>.glb)" % a["downloads"])
    os.makedirs(OUT, exist_ok=True)
    by_rig = {}
    for m, p, rig in items:
        by_rig.setdefault(rig, []).append(spec_of(m, p, rig))
    libs = []
    for rig, clips in by_rig.items():
        sp = os.path.join(OUT, "spec_%s.json" % rig)
        json.dump({"clips": clips}, open(sp, "w"), indent=1)
        out = LIB if len(by_rig) == 1 else LIB.replace(".glb", "_%s.glb" % rig)
        r = subprocess.run([BLENDER, "-b", "--python", os.path.join(REPO, "tools", "anim", "mixamo_to_ual.py"), "--", "--rig", rig,
                            "--src", a["downloads"], "--out", out, "--clips", sp], capture_output=True, text=True)
        for l in r.stdout.splitlines():
            if l.startswith("POST") or "Traceback" in l or "Error" in l:
                print(l[:220])
        libs.append(out)
    if len(libs) > 1:
        print("NOTE: two rigs in one run -> %s; merge them with tools/anim/glb_edit_clips.py or list both in LifeLibrary.LIBS" % libs)
    _sidecar(q, items)


def _sidecar(q, items):
    rep = {}
    rp = LIB + ".mixamo.json"
    if os.path.exists(rp):
        rep = json.load(open(rp))["clips"]
    clips = {}
    for m, p, rig in items:
        r = rep.get(m["clip"] + ("_Loop" if m.get("loop") else ""), rep.get(m["clip"], {}))
        e = {"category": m["category"], "loop": bool(m.get("loop")), "layer": "full", "props": m.get("props", []), "enter": None,
             "exit": None, "blend_in": 0.3, "blend_out": 0.3, "events": {}, "anchor": None, "speed_mps": 0.0, "pair": None,
             "ik_l_on_prop": None, "mask_from": None, "tags": [], "note": m["prompt"], "source": "Meshy text-to-motion (%s, %s)" % (m.get("mode", "prime"), m["id"]),
             "frames": r.get("frames", 0), "seconds": round((r.get("frames", 1) - 1) / 30.0, 3)}
        for k in ("contact_ik", "hand_contact", "seat_back", "entry_offset", "exit_offset", "exit_yaw"):
            if k in m:
                e[k] = m[k]
        clips[m["clip"]] = e
    json.dump({"library": LIB_RES, "fps": 30, "clips": clips}, open(LIB + ".life.json", "w"), indent=1)
    print("sidecar", LIB + ".life.json", len(clips), "clips")


def sheet(a, q):
    os.makedirs(OUT, exist_ok=True)
    png = os.path.join(OUT, "sheet.png")
    subprocess.run([BLENDER, "-b", "--python", os.path.join(REPO, "tools", "anim", "mixamo_check_sheet.py"), "--", LIB, png, "0", "8"],
                   capture_output=True)
    try:
        from PIL import Image
        im = Image.open(png)
        n = 0
        for y in range(0, im.size[1], 2100):
            im.crop((0, y, im.size[0], min(im.size[1], y + 2100))).convert("RGB").save(os.path.join(OUT, "sheet_%d.jpg" % n), quality=82)
            n += 1
        os.remove(png)
        print("sheets:", n, "in", OUT, "- look at every row before `wire`")
    except ImportError:
        print("sheet:", png)


def _git_import_dirty():
    r = subprocess.run(["git", "-C", REPO, "status", "--porcelain"], capture_output=True, text=True)
    return {l[3:] for l in r.stdout.splitlines() if l.startswith(" M ") and l.endswith(".import")}


def measure(a, q):
    before = _git_import_dirty()
    os.makedirs(OUT, exist_ok=True)
    subprocess.run([GODOT, "--headless", "--path", K, "--import"], capture_output=True)
    ag = os.path.join(K, "scripts", "world", "assets.gd")
    raw = open(ag, "rb").read()
    txt = raw.decode("utf-8")
    m = re.search(r'const UAL_FILES := \[.*?(\.glb")\]', txt, re.S)   # last entry of the list, whatever it is
    if not m:
        sys.exit("assets.gd UAL_FILES anchor not found")
    try:
        e = m.end(1)
        open(ag, "wb").write((txt[:e] + ', "%s"' % LIB_RES + txt[e:]).encode("utf-8"))
        names = ",".join(json.load(open(LIB + ".life.json"))["clips"].keys())
        subprocess.run([GODOT, "--headless", "--path", K, "-s", os.path.join(REPO, "tools", "qa", "anim_qa", "anim_qa.gd"), "--",
                        "--library=" + SUBJECTS, "--tag=" + os.path.basename(OUT), "--clips=" + names, "--out-dir=" + OUT], capture_output=True)
    finally:   # take out only our entry: other workers may have edited assets.gd while Godot ran
        cur = open(ag, "rb").read().decode("utf-8")
        open(ag, "wb").write(cur.replace(', "%s"' % LIB_RES, "", 1).encode("utf-8"))
    for f in _git_import_dirty() - before:
        subprocess.run(["git", "-C", REPO, "checkout", "--", f])
    print("measured ->", os.path.join(OUT, "golden_library_%s.json" % os.path.basename(OUT)))


def grade(a, q):
    sys.path.insert(0, os.path.join(REPO, "tools", "qa", "anim_qa"))
    import golden_gate as g
    d = json.load(open(os.path.join(OUT, "golden_library_%s.json" % os.path.basename(OUT))))
    res = {}
    for sub, clips in d.items():
        for k, m in clips.items():
            if "woman" in sub:
                m = dict(m)
                m["pen_cm"] = 0.0           # floor-length dress hem: garment, not the clip (ContactIK clamps it at runtime)
            v, r = g.grade_library_row(m)
            if k not in res or g.ORDER[v] > g.ORDER[res[k][0]]:
                res[k] = (v, [sub + ": " + x for x in r])
            elif v == res[k][0]:
                res[k] = (v, res[k][1] + [sub + ": " + x for x in r])
    json.dump({k: {"auto": v, "why": w} for k, (v, w) in res.items()}, open(os.path.join(OUT, "grades.json"), "w"), indent=1)
    # golden_gate.py reads docs/qa/golden/golden_library_*.json (player subject): copy the player row set there
    gl = {"player_young": d.get("player_young", {})}
    json.dump(gl, open(os.path.join(REPO, "docs", "qa", "golden", "golden_library_%s.json" % os.path.basename(OUT)), "w"), indent=1)
    for k, (v, w) in sorted(res.items()):
        print("%-28s %-9s %s" % (k, v, "; ".join(w)[:150]))


def wire(a, q):
    grades = json.load(open(os.path.join(OUT, "grades.json")))
    reviews = json.load(open(os.path.join(REPO, "docs", "qa", "golden", "reviews.json"), encoding="utf-8"))
    sop = os.path.join(K, "data", "living_world", "smart_objects.json")
    s = open(sop, encoding="utf-8", newline="").read()
    lines = s.split("\n")
    changed = 0
    for m in q["motions"]:
        c = m["clip"]
        g = grades.get(c, {}).get("auto")
        rv = reviews.get(c, {}).get("verdict")
        t = m.get("target")
        if g != "gold" or rv != "pass" or not t:
            print("skip %-28s auto=%s review=%s target=%s" % (c, g, rv, t and t["type"]))
            continue
        for i, l in enumerate(lines):
            mm = re.match(r'  "%s": (\{.*\})(,?)\s*$' % re.escape(t["type"]), l)
            if not mm:
                continue
            body = json.loads(mm.group(1))
            act = body.setdefault("activity", {})
            if t["key"] in ("loop", "between"):
                lst = act.setdefault(t["key"], [])
                if c not in lst:
                    lst.insert(0, c)
            else:
                act[t["key"]] = c
            if t.get("enable") and body.get("_disabled"):
                body.pop("_disabled")
                body["hours"] = body.get("hours_before_disable", [7, 18])
            lines[i] = '  "%s": %s%s' % (t["type"], json.dumps(body), mm.group(2))
            changed += 1
            print("wire %-28s -> %s.%s%s" % (c, t["type"], t["key"], " (re-enabled)" if t.get("enable") else ""))
    if a["apply"] and changed:
        out = "\n".join(lines)
        json.loads(out)
        open(sop, "w", encoding="utf-8", newline="").write(out)
        print("smart_objects.json updated (%d)" % changed)
    elif changed:
        print("dry run: add --apply")


def main():
    a = args()
    q = queue(a)
    steps = {"retarget": retarget, "sheet": sheet, "measure": measure, "grade": grade, "wire": wire}
    if a["step"] == "all":
        for s in ("retarget", "sheet", "measure", "grade"):
            print("==", s)
            steps[s](a, q)
        print("== next: look at docs/qa/golden/meshy/sheet_*.jpg, write verdicts into docs/qa/golden/reviews.json, then `wire --apply`")
    else:
        steps[a["step"]](a, q)


if __name__ == "__main__":
    main()
