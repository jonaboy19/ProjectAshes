"""blender -b --python glbinfo.py -- a.glb [b.glb]   (or plain python): dump animation summary; with two files compare rest TRS of nodes by name"""
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glbtools import *
fs = sys.argv[sys.argv.index('--')+1:]
J = []
for f in fs:
    j, b = read_glb(f); J.append(j)
    print(f, "nodes", len(j['nodes']), "meshes", len(j['meshes']), "skins", len(j['skins']), "anims", [(a['name'], len(a['channels'])) for a in j.get('animations', [])], "bin", len(b))
    for a in j.get('animations', [])[:1]:
        s = a['samplers'][0]; acc = j['accessors'][s['input']]; print("  first anim", a['name'], "samples", acc['count'], "t", acc.get('min'), acc.get('max'))
        tps = {}
        for c in a['channels']: tps[c['target']['path']] = tps.get(c['target']['path'], 0) + 1
        print("  paths", tps)
if len(J) == 2:
    n1 = {n.get('name'): n for n in J[1]['nodes']}; worst = 0
    for n in J[0]['nodes']:
        m = n1.get(n.get('name'))
        if m is None: print("missing", n.get('name')); continue
        for k in ('translation', 'rotation', 'scale'):
            a = np.array(n.get(k, [0,0,0,1] if k=='rotation' else ([1,1,1] if k=='scale' else [0,0,0]))); c = np.array(m.get(k, a))
            d = min(np.abs(a - c).max(), np.abs(a + c).max() if k == 'rotation' else 9)
            worst = max(worst, d)
            if d > 1e-4: print("REST DIFF", n.get('name'), k, a, c)
    print("worst rest diff", worst)
