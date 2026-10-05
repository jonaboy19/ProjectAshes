"""List texture files that ship only because their GLB/glTF was excluded.

Godot's export_filter="all_resources" packs every resource; an exclude entry for a
model does not drop the external textures the model points at (Meshy
*_lod_bake.jpg sidecars). This finds textures whose every referencing model is
excluded and that no text resource (.gd/.tscn/.tres/.json/.cfg) names, and
prints them as res:// paths. With --apply it appends them to the Android and iOS
exclude_filter in export_presets.cfg.

Usage (from kingdom/): py tools_qa/asset_use/sidecar_excludes.py [--apply]
"""
import fnmatch, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PRESETS = os.path.join(ROOT, "export_presets.cfg")
TEX = (".jpg", ".jpeg", ".png", ".webp", ".tga")
MODELS = (".glb", ".gltf")
# Only folders whose models are placed by literal name (free:/dl3 tables); kits
# such as kaykit/medieval or the nature megakit build names in code.
MESHY = ("res://assets/incoming/meshy_dl3/", "res://assets/incoming/meshy_free/")
TEXT = (".gd", ".tscn", ".tres", ".json", ".cfg", ".godot", ".gdshader")


def excludes():
    for line in open(PRESETS, encoding="utf-8"):
        if line.startswith("exclude_filter="):
            return [p.strip() for p in line.split("=", 1)[1].strip().strip('"').split(",") if p.strip()]
    return []


def excluded(res, pats):
    return any(fnmatch.fnmatchcase(res, p) for p in pats)


def main():
    pats = excludes()
    models, texts, texs = [], [], []
    for d, dirs, files in os.walk(ROOT):
        dirs[:] = [x for x in dirs if not x.startswith(".") and x != "addons"]
        if os.path.exists(os.path.join(d, ".gdignore")):
            dirs[:] = []
            continue
        for f in files:
            p = os.path.join(d, f)
            res = "res://" + os.path.relpath(p, ROOT).replace("\\", "/")
            low = f.lower()
            if low.endswith(MODELS):
                models.append((res, p))
            elif low.endswith(TEX):
                texs.append(res)
            elif low.endswith(TEXT):
                texts.append(p)
    # which model mentions which texture file name
    users = {}
    for res, p in models:
        data = open(p, "rb").read()
        if res.endswith(".glb"):
            data = data[:4096 + int.from_bytes(data[12:16], "little")]  # JSON chunk only
        for name in set(re.findall(rb'"uri"\s*:\s*"([^"]+)"', data)):
            base = os.path.basename(name.decode("utf-8", "ignore")).replace("%20", " ")
            users.setdefault((os.path.dirname(res), base), []).append(res)
    # embedded images are extracted on import as <model stem>_<image name>.<ext>
    stems = {}
    for res, p in models:
        stems.setdefault(os.path.dirname(res), []).append((os.path.splitext(os.path.basename(res))[0] + "_", res))
    for t in texs:
        d, b = os.path.dirname(t), os.path.basename(t)
        for stem, res in stems.get(d, []):
            if b.startswith(stem):
                users.setdefault((d, b), []).append(res)
    blob = "\n".join(open(t, encoding="utf-8", errors="ignore").read() for t in texts)
    out = []
    if "--models" in sys.argv:
        # Unreferenced models: the stem (minus _lodN) is named by no game text file
        # (tools_qa/, tests/ and addons/ do not count). Conservative: any substring
        # hit, e.g. a name in a placement table, keeps the model.
        game = [t for t in texts if not re.search(r"[\\/](tools_qa|tests?|addons)[\\/]", os.path.relpath(t, ROOT))]
        gblob = "\n".join(open(t, encoding="utf-8", errors="ignore").read() for t in game)
        for res, p in models:
            if excluded(res, pats) or not res.startswith(MESHY):
                continue
            stem = re.sub(r"_lod\d+$", "", os.path.splitext(os.path.basename(res))[0])
            if stem not in gblob:
                out.append(res)
                pats.append(res)  # so its sidecars follow below
        if "--apply" not in sys.argv:
            for t in out:
                print(t)
    for t in texs:
        if excluded(t, pats):
            continue
        u = users.get((os.path.dirname(t), os.path.basename(t)))
        if not u or not all(excluded(m, pats) for m in u):
            continue
        if os.path.basename(t) in blob:
            continue
        out.append(t)
    for t in out:
        print(t)
    print("%d sidecar textures" % len(out), file=sys.stderr)
    if "--apply" in sys.argv and out:
        txt = open(PRESETS, encoding="utf-8").read()
        add = ", " + ", ".join(out)
        txt = re.sub(r'(?m)^(exclude_filter=".*)"$', lambda m: m.group(1) + add + '"', txt)
        open(PRESETS, "w", encoding="utf-8", newline="\n").write(txt)


main()
