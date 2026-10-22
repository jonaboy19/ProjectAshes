"""Print every animation's first/last key time and key counts straight from a GLB's JSON chunk (no Blender).  usage: python glb_times.py a.glb [b.glb ...]"""
import sys, json, struct
for path in sys.argv[1:]:
    b = open(path, 'rb').read(); l = struct.unpack('<I', b[12:16])[0]; j = json.loads(b[20:20 + l])
    print(path.split('/')[-1], "nodes", len(j['nodes']), "skins", len(j.get('skins', [])), "meshes", len(j['meshes']))
    tot = 0
    for m in j['meshes']:
        for pr in m['primitives']:
            a = j['accessors'][pr['indices']]; tot += a['count'] // 3
    print("  tris", tot)
    for an in sorted(j['animations'], key=lambda a: a['name']):
        acc = [j['accessors'][s['input']] for s in an['samplers']]
        t0 = min(a['min'][0] for a in acc); t1 = max(a['max'][0] for a in acc)
        print(f"  {an['name']:16s} t {t0:.4f} .. {t1:.4f}  channels {len(an['channels'])}  keys/curve {acc[0]['count']}")
