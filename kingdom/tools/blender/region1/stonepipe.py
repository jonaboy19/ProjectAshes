"""Pipeline: build parts (LOD0/LOD1) -> pack charts -> paint atlas (blue + ancestor-gold) -> write textures + glb.
Part meta keys: seed, ppm (wanted px/m), layouts {chartkey: fn(draw, ctx)}, opts, z0, glow (bool), smooth (bool),
vcol fn(Vector world)->(r,g,b), sharp_deg."""
import bpy, bmesh, math, os, sys
import numpy as np
from mathutils import Vector
sys.path.insert(0, os.path.dirname(__file__))
import paint as P
import stonepaint as SP
import stonekit as SK


def chart_bounds(parts):
    bounds = {}
    for p in parts:
        for (f, key, co) in p['faces']:
            k = (p['name'], key)
            b = bounds.setdefault(k, [1e9, -1e9, 1e9, -1e9])
            for (u, v) in co:
                b[0] = min(b[0], u); b[1] = max(b[1], u); b[2] = min(b[2], v); b[3] = max(b[3], v)
    return bounds


def make_object(builder, name, rects, bounds, scales, atlas_wh, material, lod):
    bm = builder.bm
    W, H = atlas_wh
    uvl = bm.loops.layers.uv.new('UVMap')
    col = bm.loops.layers.color.new('Col')
    for p in builder.parts:
        meta = p['meta']
        vcol = meta.get('vcol')
        for (f, key, co) in p['faces']:
            b = bounds.get((p['name'], key))
            r = rects.get((p['name'], key))
            for l, (u, v) in zip(f.loops, co):
                if r is None:
                    l[uvl].uv = (0.5, 0.5)
                else:
                    ppm = scales[(p['name'], key)]
                    uu = min(max(u, b[0]), b[1]); vv = min(max(v, b[2]), b[3])
                    l[uvl].uv = ((r[0] + (uu - b[0]) * ppm) / W, 1.0 - (r[1] + (b[3] - vv) * ppm) / H)
                c = vcol(l.vert.co) if vcol else (0, 0, 0)
                l[col] = (c[0], c[1], c[2], 1.0)
            f.smooth = bool(meta.get('smooth', True))
        if meta.get('smooth', True):
            thr = math.radians(meta.get('sharp_deg', 58))
            es = {e for (f, k, c) in p['faces'] for e in f.edges}
            for e in es:
                if len(e.link_faces) == 2 and e.calc_face_angle(0) > thr:
                    e.smooth = False
                elif len(e.link_faces) == 1:
                    e.smooth = True
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(material)
    return ob


def run_set(name, build_fn, out_dir, atlas=(2048, 2048), lods=(0, 1), tex_dir=None, jpg_q=88, normal_down=True,
            normal_strength=1.4, emis_down=True, export_variants=('blue',), gold_suffix='ancestor_gold'):
    os.makedirs(out_dir, exist_ok=True)
    tex_dir = tex_dir or os.path.join(out_dir, 'textures')
    os.makedirs(tex_dir, exist_ok=True)
    W, H = atlas
    b0 = SK.Builder()
    build_fn(b0, 0)
    bounds = chart_bounds(b0.parts)
    pm = {p['name']: p['meta'] for p in b0.parts}
    charts = {}
    for k, b in bounds.items():
        charts[k] = (b[1] - b[0], b[3] - b[2], pm[k[0]].get('ppm', 100.0))
    rects, sc = SK.pack(charts, W, H)
    scales = {k: pm[k[0]].get('ppm', 100.0) * sc for k in charts}
    # rect sizes are ceil'd from w_m*ppm*scale; use the exact scale for uv
    print(f"[{name}] atlas {W}x{H}, pack scale {sc:.3f}, charts {len(charts)}")

    # ---- paint both variants
    tex = {}
    height_atlas = None
    for var in ('blue', 'gold'):
        alb = np.zeros((H, W, 3), np.float32)
        alb[:] = P.rgb(0.62, 0.56, 0.48)
        emi = np.zeros((H, W, 3), np.float32)
        hgt = np.zeros((H, W), np.float32)
        for k, (rx, ry, rw, rh) in rects.items():
            meta = pm[k[0]]
            b = bounds[k]
            ctx = SP.Ctx(k[1], rw, rh, scales[k], b[0], b[3], meta.get("seed", 1) + (sum(map(ord, k[0] + k[1])) % 97), var,
                         z0=meta.get('z0', 0.0), zmax=b[3], part=k[0])
            lay = meta.get('layouts', {}).get(k[1], lambda d, c: None)
            a_, h_, e_ = SP.paint_chart(ctx, lay, meta.get('opts'))
            alb[ry:ry + rh, rx:rx + rw] = a_
            hgt[ry:ry + rh, rx:rx + rw] = h_
            emi[ry:ry + rh, rx:rx + rw] = e_
        tex[var] = (alb, emi)
        height_atlas = hgt
    nrm = P.normal_from_height(height_atlas, normal_strength)
    # ---- write textures
    paths = {}
    tmp = os.path.join(tex_dir, '_tmp.png')
    nrm_out = SK.down2(nrm) if normal_down else nrm
    npath = os.path.join(tex_dir, f'{name}_normal.png')
    SK.write_png(npath, SK.to8(nrm_out))
    for var, (alb, emi) in tex.items():
        suf = '' if var == 'blue' else '_' + gold_suffix
        SK.write_png(tmp, SK.to8(alb))
        apath = os.path.join(tex_dir, f'{name}{suf}_albedo.jpg')
        SK.save_jpg(tmp, apath, jpg_q)
        e_out = SK.down2(emi) if emis_down else emi
        epath = os.path.join(tex_dir, f'{name}{suf}_emissive.png')
        SK.write_png(epath, SK.to8(e_out))
        paths[var] = (apath, epath)
    if os.path.exists(tmp):
        os.remove(tmp)
    # preview atlas
    SK.write_png(os.path.join(tex_dir, '_atlas_preview_blue.png'), SK.to8(tex['blue'][0]))

    # ---- build objects per lod
    objs = {}
    for lod in lods:
        bl = b0 if lod == 0 else SK.Builder()
        if lod != 0:
            build_fn(bl, lod)
        mats = {}
        for var in ('blue', 'gold'):
            mats[var] = SK.make_material(f'{name}_{var}_mat', paths[var][0], npath, paths[var][1])
        ob = make_object(bl, f'{name}_lod{lod}', rects, bounds, scales, (W, H), mats['blue'], lod)
        objs[lod] = (ob, mats)
    return objs, paths, npath, tex
