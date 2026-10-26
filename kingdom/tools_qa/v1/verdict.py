#!/usr/bin/env python3
"""Judge a headless playtest-bot run. usage: verdict.py OUT HOOKS_ALLOWED STAGES GODOT_RC STRICT. Exit 0 = pass, 1 = fail."""
import json, os, re, sys

out, allow_path, stages, grc, strict = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5] == "1"
fails, warns = [], []
try:
    summary = json.load(open(os.path.join(out, "summary.json")))
except Exception as e:
    print("bot: FAIL no readable summary.json (%s): the bot crashed or never reached a stage" % e)
    sys.exit(1)
ran = {s["name"]: s for s in summary.get("stages", [])}
for want in [s for s in stages.split(",") if s]:
    if want not in ran:
        fails.append("stage %s did not run" % want)
for name, st in ran.items():
    if st.get("timed_out"):
        fails.append("%s: stuck / hit its stage deadline" % name)
    for c in st.get("checks", []):
        if not c.get("ok"):
            fails.append("%s: CHECK FAIL %s %s" % (name, c.get("label"), c.get("detail", "")))
    for i in st.get("issues", []):
        if i.startswith(("stuck", "timeout", "check", "engine")):
            continue          # already counted from checks / errors / timed_out
        fails.append("%s: issue %s" % (name, i))
    for e in st.get("errors", []):
        if e.startswith("SCRIPT ERROR") or e.startswith("ERROR") or e.startswith("SHADER ERROR"):
            fails.append("%s: %s" % (name, e[:200]))
        else:
            warns.append("%s: %s" % (name, e[:160]))
for b in summary.get("bugs", []):
    if b.get("kind") == "stuck":
        fails.append("%s: stuck: %s" % (b["stage"], b["text"]))
# SCRIPT ERROR anywhere on stdout (also outside the bot's logger, e.g. while the stage list was still booting)
txt = open(os.path.join(out, "bot_out.txt"), errors="replace").read() if os.path.exists(os.path.join(out, "bot_out.txt")) else ""
script_errs = sorted(set(re.sub(r"0x[0-9a-f]+", "", l) for l in txt.splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l))
for l in script_errs[:20]:
    fails.append("stdout: " + l.strip()[:200])
if "all stages done" not in txt and not fails:
    fails.append("bot never reported 'all stages done' (godot exit %d)" % grc)
# [HOOK] kinds vs allow-list (digits and decimals normalised away)
def norm(l):
    l = l.split("[HOOK]", 1)[1].strip()
    return re.sub(r"-?\d+(\.\d+)?", "N", l)
hooks = {}
for l in txt.splitlines():
    if "[HOOK]" in l:
        hooks[norm(l)] = hooks.get(norm(l), 0) + 1
allowed = set()
if os.path.exists(allow_path):
    allowed = {l.strip() for l in open(allow_path) if l.strip() and not l.startswith("#")}
unlisted = sorted(h for h in hooks if h not in allowed)
print("hooks: %d kinds, %d uses, %d not in allow-list%s" % (len(hooks), sum(hooks.values()), len(unlisted), "" if strict else " (non-blocking; V1_HOOKS_STRICT=1 to enforce)"))
for h in unlisted[:30]:
    print("  unlisted hook: %s (x%d)" % (h, hooks[h]))
if strict and unlisted:
    fails.append("%d [HOOK] kinds not in hooks_allowed.txt" % len(unlisted))
for w in warns[:10]:
    print("  warning:", w)
for f in fails:
    print("  FAIL:", f)
print("bot: %s (%d stages ran, %d failures)" % ("FAIL" if fails else "PASS", len(ran), len(fails)))
sys.exit(1 if fails else 0)
