"""Minimal GLB reader/writer + animation grafting (pure python/numpy; run inside Blender's python or any python with numpy).
graft(orig_glb, anim_glb, clip_names, out_glb): copy the named animations (and only those) from anim_glb into a copy of
orig_glb. Meshes, skins, materials and textures of orig_glb are kept byte for byte; unused buffer data is dropped."""
import json, struct, numpy as np

def read_glb(path):
    b = open(path, 'rb').read()
    magic, ver, total = struct.unpack_from('<4sII', b, 0)
    assert magic == b'glTF' and ver == 2
    off = 12; js = None; bn = b''
    while off < total:
        ln, ty = struct.unpack_from('<II', b, off); data = b[off + 8: off + 8 + ln]; off += 8 + ln
        if ty == 0x4E4F534A: js = json.loads(data.decode('utf8'))
        elif ty == 0x004E4942: bn = data
    return js, bn

def write_glb(path, js, bn):
    j = json.dumps(js, separators=(',', ':')).encode('utf8'); j += b' ' * ((4 - len(j) % 4) % 4)
    bn = bn + b'\0' * ((4 - len(bn) % 4) % 4)
    total = 12 + 8 + len(j) + 8 + len(bn)
    with open(path, 'wb') as f:
        f.write(struct.pack('<4sII', b'glTF', 2, total))
        f.write(struct.pack('<II', len(j), 0x4E4F534A)); f.write(j)
        f.write(struct.pack('<II', len(bn), 0x004E4942)); f.write(bn)

def acc_bytes(js, bn, ai):
    a = js['accessors'][ai]; bv = js['bufferViews'][a['bufferView']]
    ncomp = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
    csz = {5126: 4, 5123: 2, 5125: 4, 5121: 1, 5120: 1, 5122: 2}[a['componentType']]
    elem = ncomp * csz; stride = bv.get('byteStride', elem)
    start = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    if stride == elem: return bn[start: start + elem * a['count']]
    return b''.join(bn[start + i * stride: start + i * stride + elem] for i in range(a['count']))

def repack(js, bn):
    """rebuild the BIN chunk keeping only bufferViews referenced by accessors/images; returns (js, bn)"""
    used = set()
    for a in js['accessors']:
        if 'bufferView' in a: used.add(a['bufferView'])
    for im in js.get('images', []):
        if 'bufferView' in im: used.add(im['bufferView'])
    order = sorted(used); remap = {}; out = bytearray(); nbv = []
    for i in order:
        bv = js['bufferViews'][i]; d = bn[bv.get('byteOffset', 0): bv.get('byteOffset', 0) + bv['byteLength']]
        while len(out) % 4: out += b'\0'
        nb = dict(bv); nb['byteOffset'] = len(out); nb['buffer'] = 0; out += d; remap[i] = len(nbv); nbv.append(nb)
    for a in js['accessors']:
        if 'bufferView' in a: a['bufferView'] = remap[a['bufferView']]
    for im in js.get('images', []):
        if 'bufferView' in im: im['bufferView'] = remap[im['bufferView']]
    js['bufferViews'] = nbv; js['buffers'] = [{'byteLength': len(out)}]
    return js, bytes(out)

def graft(orig, anim, clips, out, keep_others=True):
    j0, b0 = read_glb(orig); j1, b1 = read_glb(anim)
    n0 = {n.get('name'): i for i, n in enumerate(j0['nodes'])}; n1 = {n.get('name'): i for i, n in enumerate(j1['nodes'])}
    b0 = bytearray(b0)
    anims = {a['name']: a for a in j0.get('animations', [])}
    for clip in clips:
        an = [a for a in j1['animations'] if a['name'] == clip][0]
        cache = {}
        def copy_acc(ai):
            if ai in cache: return cache[ai]
            a = dict(j1['accessors'][ai]); raw = acc_bytes(j1, b1, ai)
            while len(b0) % 4: b0.append(0)
            bv = {'buffer': 0, 'byteOffset': len(b0), 'byteLength': len(raw)}; b0.extend(raw)
            j0['bufferViews'].append(bv)
            a['bufferView'] = len(j0['bufferViews']) - 1; a.pop('byteOffset', None); a.pop('sparse', None)
            j0['accessors'].append(a); cache[ai] = len(j0['accessors']) - 1
            return cache[ai]
        samplers = []; chans = []; smap = {}
        for ch in an['channels']:
            nm = j1['nodes'][ch['target']['node']].get('name')
            if nm not in n0: print("WARN node not in orig:", nm); continue
            si = ch['sampler']
            if si not in smap:
                s = an['samplers'][si]; smap[si] = len(samplers)
                samplers.append({'input': copy_acc(s['input']), 'output': copy_acc(s['output']), 'interpolation': s.get('interpolation', 'LINEAR')})
            chans.append({'sampler': smap[si], 'target': {'node': n0[nm], 'path': ch['target']['path']}})
        anims[clip] = {'name': clip, 'samplers': samplers, 'channels': chans}
    # keep original animation order, append new ones at the end
    order = [a['name'] for a in j0.get('animations', [])]
    for c in clips:
        if c not in order: order.append(c)
    j0['animations'] = [anims[n] for n in order]
    j0, nb = repack(j0, bytes(b0))
    write_glb(out, j0, nb)
    return j0
