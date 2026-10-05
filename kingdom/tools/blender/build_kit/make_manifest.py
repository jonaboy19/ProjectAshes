"""Scans build_kit/*_lod0|lod1.glb and writes kit_manifest.json. blender -b --factory-startup --python make_manifest.py -- <dir>"""
import bpy, sys, os, json, glob

d = sys.argv[sys.argv.index('--') + 1]
meshy = {}
mp = os.path.join(d, '_meshy_manifest.json')
if os.path.exists(mp): meshy = json.load(open(mp))

def stats(path):
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)
    bpy.ops.import_scene.gltf(filepath=path)
    tris = 0; mn = [1e9] * 3; mx = [-1e9] * 3; mats = []
    for o in bpy.context.scene.objects:
        if o.type != 'MESH': continue
        me = o.data; M = o.matrix_world
        for pl in me.polygons: tris += len(pl.vertices) - 2
        for v in me.vertices:
            w = M @ v.co; g = (w.x, w.z, -w.y)
            for i in range(3): mn[i] = min(mn[i], g[i]); mx[i] = max(mx[i], g[i])
        for s in o.material_slots:
            if s.material and s.material.name not in mats: mats.append(s.material.name)
    return tris, [round(v, 3) for v in mn], [round(v, 3) for v in mx], mats

pieces = {}
for f in sorted(glob.glob(os.path.join(d, '*_lod0.glb'))):
    pid = os.path.basename(f)[:-9]
    t0, mn, mx, mats = stats(f)
    l1 = os.path.join(d, pid + '_lod1.glb')
    t1 = stats(l1)[0] if os.path.exists(l1) else None
    src = meshy.get(pid, {}).get('source', 'blender') if pid.startswith('meshy_') else 'blender'
    pieces[pid] = {'source': src, 'tris_lod0': t0, 'tris_lod1': t1, 'aabb_min': mn, 'aabb_max': mx, 'materials': mats}
    print(pid, t0, t1)
json.dump({'grid': 2.0, 'storey': 3.0, 'pieces': pieces}, open(os.path.join(d, 'kit_manifest.json'), 'w'), indent=1)
