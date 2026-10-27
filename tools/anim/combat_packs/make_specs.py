"""Clip specs for the owner's Mixamo combat packs (2026-10-27) -> mixamo_to_ual.py --clips.
Attacks/reactions keep their travel in the `root` track (inplace "smooth"): the game plays the body in place and
scripts/combat/combat_motion.gd moves the capsule along that curve (root-motion attacks + warping).
Loops (idle/walk/run/strafe) are treadmilled ("linear").
  python tools/anim/combat_packs/make_specs.py <packs_dir>   -> tools/anim/combat_packs/<pack>.json
"""
import json, os, re, sys

PACKS = {"pro_sword_and_shield": ("SnS", "sword and shield "), "great_sword": ("GS", "great sword "),
         "pro_melee_axe": ("Axe", "standing melee "), "pro_longbow": ("Bow", "standing "),
         "male_injured": ("Inj", "injured ")}
LOOP = re.compile(r"\b(idle|walk|run|strafe|crouching|loop|sneak)\b")
ONESHOT = re.compile(r"( to |turn|jump|stop|land)")


def clip_name(prefix, strip, stem):
    s = stem.lower()
    for p in (strip, "two handed sword ", "standing ", "great sword ", "sword and shield ", "melee "):
        if s.startswith(p):
            s = s[len(p):]
    s = re.sub(r"\((\d+)\)", r"\1", s).replace("ver.", "v").replace(".", "")
    parts = [w.capitalize() for w in re.split(r"[^a-z0-9]+", s) if w]
    return "Mx_%s_%s" % (prefix, "_".join(parts))


def main():
    src = sys.argv[1]
    here = os.path.dirname(os.path.abspath(__file__))
    for pack, (prefix, strip) in PACKS.items():
        d = os.path.join(src, pack)
        clips, seen = [], set()
        for f in sorted(os.listdir(d)):
            if not f.lower().endswith(".fbx") or f.lower() == "x bot.fbx":
                continue
            stem = f[:-4]
            name = clip_name(prefix, strip, stem)
            while name in seen:
                name += "_b"
            seen.add(name)
            low = stem.lower()
            loop = bool(LOOP.search(low)) and not ONESHOT.search(low)
            c = {"name": name, "file": f}
            if loop:
                c.update({"loop": True, "inplace": "linear"})
            else:
                c["inplace"] = "smooth"
                c["inplace_sigma"] = 0.08     # keep the step shape: the root follows the pelvis closely
            if re.search(r"death|knock|fall|impact|react", low):
                c["floor"] = "min"
            clips.append(c)
        with open(os.path.join(here, pack + ".json"), "w") as fh:
            json.dump({"clips": clips}, fh, indent=1)
        print(pack, len(clips), sum(1 for c in clips if c.get("loop")))


if __name__ == "__main__":
    main()
