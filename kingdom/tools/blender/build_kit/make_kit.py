"""Builds every Blender-made piece of the modular build kit (structure + props) in one deterministic run.
Run: blender -b --factory-startup --python make_kit.py -- <out_dir> [piece ids...]
Authoring is in Godot coordinates, see kitlib.py. Grid: cell 2 m, storey 3 m."""
import sys, os, math, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kitlib import *
import kit_structure, kit_props
from kitlib import P

REG = {}
REG.update(kit_structure.REG)
REG.update(kit_props.REG)

def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    out = argv[0]; only = argv[1:]
    os.makedirs(out, exist_ok=True)
    info = {}
    for pid, fn in REG.items():
        if only and pid not in only: continue
        p = P(pid); fn(p)
        ob, tris, mn, mx = p.build()
        export(ob, os.path.join(out, pid + '_lod0.glb'))
        info[pid] = {'tris_lod0': tris, 'aabb_min': [round(v, 3) for v in mn], 'aabb_max': [round(v, 3) for v in mx],
                     'materials': p.slots}
        me = ob.data; bpy.data.objects.remove(ob); bpy.data.meshes.remove(me)
        print('PIECE', pid, tris, [round(v, 2) for v in mn], [round(v, 2) for v in mx])
    jp = os.path.join(out, '_blender_manifest.json')
    old = {}
    if only and os.path.exists(jp):
        old = json.load(open(jp))
    old.update(info)
    json.dump(old, open(jp, 'w'), indent=1)

main()
