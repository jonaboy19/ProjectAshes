#!/usr/bin/env python3
"""Re-runs the model-usage scan of docs/qa/ASSET_AUDIT.md ("How it was checked") and reports used / dynamic / TOOLS-ONLY / UNREF counts.
Usage (repo root, about a minute):
    python3 tools/qa/asset_audit.py [--dump unused.csv] [--dump-all every_model.csv]
Scans every .gd .tscn .tres .json .cfg .gdshader and project.godot under kingdom/ (not addons/, tests/, tools*/) for each .glb/.gltf:
its res:// path or uid ("used"), a path-suffix string literal ("used": how `Q + "..."` constants resolve), the key `<cat>/<name>` of a
free:/r1:/gen: table entry or its bare base name ("dynamic": a few are accidents such as a common word like `barrel`), names found
only in tests/tools ("TOOLS-ONLY"), nothing ("UNREF"). Differences from the 2026-09-30 audit: a meshy_free / region1 model needs its
`cat/name` key (a bare word elsewhere no longer counts), and a file under a `.gdignore`d folder or matched by the export
exclude_filter counts as NOT shipped (Godot never imports .gdignore folders, so they were never in the APK)."""
import os, re, sys, glob, csv, json
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
K = os.path.join(ROOT, "kingdom")
EXT = {".gd", ".tscn", ".tres", ".json", ".cfg", ".gdshader", ".godot"}
def read_all(dirs, skip):
    out = []
    for base in dirs:
        for dp, dn, fn in os.walk(base):
            rel = os.path.relpath(dp, K)
            if any(rel == s or rel.startswith(s + os.sep) for s in skip):
                dn[:] = []; continue
            dn[:] = [d for d in dn if d != ".godot"]
            for f in fn:
                if os.path.splitext(f)[1] in EXT or f == "project.godot":
                    try: out.append(open(os.path.join(dp, f), encoding="utf-8", errors="ignore").read())
                    except OSError: pass
    return "\n".join(out)
runtime = read_all([K], ["addons", "tests", "tools", "tools_qa", "reports", "docs"])
tools = read_all([os.path.join(K, "tests"), os.path.join(K, "tools"), os.path.join(K, "tools_qa")], [])
TOK = re.compile(r"[A-Za-z0-9_/]+")
def toks(t):
    out = set()
    for m in TOK.findall(t):
        out.add(m)
        if "/" in m:
            parts = m.split("/")
            for i in range(len(parts)):
                out.add("/".join(parts[i:i+2])); out.add(parts[i])
    return out
rt_tok = toks(runtime)
tl_tok = toks(tools)
LIT = set(m.replace("res://", "") for m in re.findall(r'["\']([^"\'\n]{4,}\.(?:glb|gltf))["\']', runtime))
def suffix_hit(p):
    parts = p.split("/")
    return any("/".join(parts[i:]) in LIT for i in range(len(parts)))
def base_of(p):
    b = os.path.splitext(os.path.basename(p))[0]
    return re.sub(r"_lod\d$", "", b)
def uid_of(p):
    f = os.path.join(K, p + ".import")
    if os.path.exists(f):
        m = re.search(r'uid="(uid://[a-z0-9]+)"', open(f, errors="ignore").read())
        if m: return m.group(1)
def status(p):
    full = "res://" + p
    u = uid_of(p)
    if full in runtime or (u and u in runtime) or suffix_hit(p): return "used"
    b = base_of(p)
    parts = p.split("/")
    keys = [b]
    # kit keys: free:cat/name, r1:dir/name, gen:dir/name -> require cat/name for kit packs (a bare common word would be a false hit)
    if "meshy_free" in parts:
        i = parts.index("meshy_free"); keys = [("/".join(parts[i+1:-1]) + "/" + b)]
        if parts[i+1] == "maybe": keys = [("/".join(parts[i+2:-1]) + "/" + b)]
    elif "region1" in parts:
        i = parts.index("region1"); keys = ["/".join(parts[i+1:-1]) + "/" + b]
    elif len(b) < 5: keys = []
    if any(k in rt_tok for k in keys): return "dynamic"
    if any(k in tl_tok for k in keys + [b]) or full in tools: return "TOOLS-ONLY"
    return "UNREF"
def excluded(p, filt):
    for f in filt:
        f = f.strip().replace("res://", "")
        if f.endswith("*"):
            if p.startswith(f[:-1]) or (f.startswith("*") and f[1:-1] in p): return True
        elif f == p: return True
        elif f.startswith("*/") and f.endswith("/*") and f[1:-1] in "/" + p: return True
    return False
GDIGNORE = set()
for dp, dn, fn in os.walk(os.path.join(K, "assets")):
    if ".gdignore" in fn:
        GDIGNORE.add(os.path.relpath(dp, K))
def gdignored(p):
    parts = p.split("/")
    return any("/".join(parts[:i]) in GDIGNORE for i in range(1, len(parts)))
def export_filter():
    t = open(os.path.join(K, "export_presets.cfg")).read()
    m = re.search(r'exclude_filter="([^"]*)"', t)
    return [x for x in m.group(1).split(",") if x.strip()] if m else []
if __name__ == "__main__":
    filt = export_filter()
    rows = []
    allm = []
    for ext in ("glb", "gltf"):
        allm += [os.path.relpath(f, K) for f in glob.glob(K + "/assets/**/*." + ext, recursive=True)]
    cnt = {}
    for p in sorted(allm):
        s = status(p); sz = os.path.getsize(os.path.join(K, p)); ex = excluded(p, filt) or gdignored(p)   # a .gdignore'd folder is invisible to Godot: never imported, never exported
        c = cnt.setdefault(s, [0, 0.0, 0, 0.0]); c[0] += 1; c[1] += sz / 1e6
        if ex: c[2] += 1; c[3] += sz / 1e6
        rows.append((p, sz, s, "no" if ex else "yes"))
    print("status files MB | of which export-excluded files MB")
    for s in ("used", "dynamic", "TOOLS-ONLY", "UNREF"):
        c = cnt.get(s, [0, 0, 0, 0]); print("%-11s %5d %7.1f | %5d %7.1f" % (s, c[0], c[1], c[2], c[3]))
    un = [r for r in rows if r[2] in ("UNREF", "TOOLS-ONLY")]
    print("unused by game: %d files %.1f MB; of those still shipped in APK: %d files %.1f MB" % (
        len(un), sum(r[1] for r in un) / 1e6, sum(1 for r in un if r[3] == "yes"), sum(r[1] for r in un if r[3] == "yes") / 1e6))
    if "--dump-all" in sys.argv:
        w = csv.writer(open(sys.argv[sys.argv.index("--dump-all") + 1], "w", newline=""))
        w.writerow(["path", "bytes", "status", "shipped_in_apk"]); [w.writerow(r) for r in rows]
    if "--dump" in sys.argv:
        w = csv.writer(open(sys.argv[sys.argv.index("--dump") + 1], "w", newline=""))
        w.writerow(["path", "bytes", "status", "shipped_in_apk"]); [w.writerow(r) for r in un]
