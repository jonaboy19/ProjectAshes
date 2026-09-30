"""Author the wind-up/strike/follow-through clips (and locomotion / death ground fixes) for one creature and export a GLB.

  blender -b --python make_attacks.py -- <creature> <in.glb> <out.glb> [--save baked.json | --load baked.json] [clip ...]

--save   author from the specs_<creature>.py file and store the baked FK keys of every edited clip as JSON
--load   do NOT author: re-apply those baked keys (this is how LOD1 gets clips identical to LOD0)
"""
import sys, os, importlib, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from authoring import *

a = sys.argv[sys.argv.index('--') + 1:]
creature, gin, gout = a[0], a[1], a[2]
rest = a[3:]
save = load = None
only = []
i = 0
while i < len(rest):
    if rest[i] == '--save':
        save = rest[i + 1]; i += 2
    elif rest[i] == '--load':
        load = rest[i + 1]; i += 2
    else:
        only.append(rest[i]); i += 1

spec = importlib.import_module("specs_" + creature)
rig = Rig(gin)
edited = []


def dump(name):
    f0, f1 = rig.frames(name)
    return [{b: [list(v[0]), list(v[1])] for b, v in rig.basis_from(rig.base_at(name, f)).items()} for f in range(f0, f1 + 1)]


if load:
    data = json.load(open(load))
    for name, frames in data.items():
        fb = [{b: (Vector(v[0]), Quaternion(v[1])) for b, v in fr.items()} for fr in frames]
        rig.replace_action(name, fb)
        print("LOADED", name, len(fb), "frames")
else:
    for name, c in spec.CLIPS.items():
        if only and name not in only:
            continue
        opts = dict(spec.OPTS)
        opts.update(c.get("opts", {}))
        bc, bf = c["base"]
        pre = []
        if c.get("prefix"):        # keep the first frames of the ORIGINAL clip untouched (orc kneel + stand-up)
            pc, pf = c["prefix"]
            pre = [rig.basis_from(rig.base_at(pc, f)) for f in range(1, pf + 1)]
        fb = author_clip(rig, bc, bf, c["keys"], c["duration"], opts)
        if pre:
            fb = pre + fb[1:]
        rig.replace_action(name, fb)
        edited.append(name)
        print("AUTHORED", name, len(fb), "frames", round((len(fb) - 1) / 30.0, 2), "s impact", spec.IMPACT.get(name))
    for name in getattr(spec, "LOCO_LIFT", []):
        rig.replace_action(name, ground_lift_clip(rig, name))
        edited.append(name)
    for name in getattr(spec, "DEATH_LIFT", []):
        rig.replace_action(name, ground_lift_clip(rig, name, cyclic=False))
        edited.append(name)
    for name in getattr(spec, "INPLACE", []):
        rig.replace_action(name, inplace_clip(rig, name))
        edited.append(name)
    for name in getattr(spec, "LOOP_CLOSE", []):
        rig.replace_action(name, loop_close(rig, name))
        edited.append(name)
    if save:
        json.dump({n: dump(n) for n in edited}, open(save, 'w'), separators=(',', ':'))
        print("SAVED", save, edited)
rig.export(gout)
