"""Make every shipped 3D texture VRAM-compressed (ETC2/ASTC on phones, BC on desktop).

Godot imports a texture as "Lossless" until the *editor* sees it used in 3D
(detect_3d). This project is mostly built from scripts, so ~1000 model textures
were still Lossless: on a phone that is 4 bytes/px uncompressed RGBA in VRAM
(a 2048 texture = 22 MB with mips) instead of 1 byte/px ASTC/ETC2.

  py tools/qa/texture_vram.py            # dry run: list what would change
  py tools/qa/texture_vram.py --write    # rewrite the .import files
  then: godot --headless --path kingdom --import

Scope: texture .import files under kingdom/assets/ that the Android export ships
(its exclude_filter is honoured), except UI (assets/ui, app_icon) and HDR skies.
Sets compress/mode=2 and mipmaps; files named like normal maps get
compress/normal_map=1 (RG compression, the shader rebuilds Z). Sizes are not
touched here: the mobile-only size caps are applied at export time by
addons/mobile_texture_limit (desktop keeps full resolution).
"""
import fnmatch, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
KINGDOM = os.path.normpath(os.path.join(HERE, "..", "..", "kingdom"))
SKIP_PREFIX = ("res://assets/ui/", "res://assets/generated/app_icon/", "res://assets/audio/")
NORMAL = re.compile(r"(_nor(_gl|_dx)?[_.]|normal|_n\.)", re.I)


def exclude_filters():
    cfg = open(os.path.join(KINGDOM, "export_presets.cfg"), encoding="utf-8").read()
    m = re.search(r'^exclude_filter="([^"]*)"', cfg, re.M)
    return [f.strip() for f in m.group(1).split(",") if f.strip()] if m else []


def main():
    write = "--write" in sys.argv
    filters = exclude_filters()
    changed = 0
    for dp, _dn, fn in os.walk(os.path.join(KINGDOM, "assets")):
        for f in fn:
            if not f.endswith(".import"):
                continue
            path = os.path.join(dp, f)
            res = "res://" + os.path.relpath(path, KINGDOM).replace(os.sep, "/")[:-len(".import")]
            if res.startswith(SKIP_PREFIX) or res.lower().endswith((".hdr", ".exr", ".svg")):
                continue
            if any(fnmatch.fnmatch(res, flt) for flt in filters):
                continue
            s = open(path, encoding="utf-8").read()
            if 'importer="texture"' not in s:
                continue
            new = re.sub(r"^compress/mode=\d", "compress/mode=2", s, flags=re.M)
            new = re.sub(r"^mipmaps/generate=\w+", "mipmaps/generate=true", new, flags=re.M)
            if NORMAL.search(os.path.basename(res)):
                new = re.sub(r"^compress/normal_map=\d", "compress/normal_map=1", new, flags=re.M)
            if new != s:
                changed += 1
                print(("write " if write else "would ") + res)
                if write:
                    open(path, "w", encoding="utf-8", newline="\n").write(new)
    print(f"{changed} texture imports {'updated' if write else 'to update'}")


if __name__ == "__main__":
    main()
