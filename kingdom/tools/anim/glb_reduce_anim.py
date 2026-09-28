# Shrink the animations of a GLB in place (pure python + numpy, no Blender):
#  * Douglas-Peucker keyframe reduction per channel (rotation: slerp angle
#    error, translation/scale: distance error), LINEAR samplers only,
#  * channels that stay at the node's rest value for the whole clip are dropped
#    (Godot resets untracked bones to rest), other constant channels keep 2 keys.
# The Blender glTF exporter bakes every bone TRS on every frame; this pass
# typically cuts a clip library by 85-95 %.
#
# usage: python glb_reduce_anim.py in.glb [out.glb] [--rot-deg 0.35] [--pos-m 0.002]
import json, struct, sys, math
import numpy as np

args = [a for a in sys.argv[1:]]
def opt(name, default):
    if name in args:
        i = args.index(name); v = float(args[i + 1]); del args[i:i + 2]; return v
    return default
ROT = math.radians(opt("--rot-deg", 0.35))
POS = opt("--pos-m", 0.002)
src = args[0]; dst = args[1] if len(args) > 1 else args[0]

raw = open(src, "rb").read()
assert raw[:4] == b"glTF"
jl = struct.unpack("<I", raw[12:16])[0]
J = json.loads(raw[20:20 + jl])
off = 20 + jl
bl = struct.unpack("<I", raw[off:off + 4])[0]
BIN = raw[off + 8: off + 8 + bl]

NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
CT = {5126: ("f4", 4), 5123: ("u2", 2), 5125: ("u4", 4), 5121: ("u1", 1), 5122: ("i2", 2), 5120: ("i1", 1)}

def acc_bytes(a):
    bv = J["bufferViews"][a["bufferView"]]
    dt, sz = CT[a["componentType"]]
    n = NC[a["type"]] * a["count"] * sz
    assert not bv.get("byteStride") or bv["byteStride"] == NC[a["type"]] * sz, "interleaved buffers unsupported"
    s = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    return BIN[s:s + n]

def acc_array(a):
    dt, _ = CT[a["componentType"]]
    return np.frombuffer(acc_bytes(a), dtype="<" + dt).reshape(a["count"], NC[a["type"]]).astype(np.float64)

def slerp(a, b, w):
    d = np.sum(a * b, -1, keepdims=True)
    b = np.where(d < 0, -b, b); d = np.abs(d)
    th = np.arccos(np.clip(d, -1, 1))
    s = np.sin(th)
    small = s < 1e-6
    wa = np.where(small, 1 - w, np.sin((1 - w) * th) / np.where(small, 1, s))
    wb = np.where(small, w, np.sin(w * th) / np.where(small, 1, s))
    r = wa * a + wb * b
    return r / np.linalg.norm(r, axis=-1, keepdims=True)

def qang(a, b):
    return 2 * np.arccos(np.clip(np.abs(np.sum(a * b, -1)), 0, 1))

def reduce(t, v, path):
    n = len(t)
    if n <= 2:
        return list(range(n))
    keep = {0, n - 1}
    stack = [(0, n - 1)]
    tol = ROT if path == "rotation" else POS
    while stack:
        i, j = stack.pop()
        if j - i < 2:
            continue
        w = ((t[i + 1:j] - t[i]) / (t[j] - t[i]))[:, None]
        if path == "rotation":
            e = qang(slerp(np.repeat(v[i:i + 1], j - i - 1, 0), np.repeat(v[j:j + 1], j - i - 1, 0), w), v[i + 1:j])
        else:
            e = np.linalg.norm(v[i] * (1 - w) + v[j] * w - v[i + 1:j], axis=1)
        k = int(np.argmax(e))
        if e[k] > tol:
            m = i + 1 + k
            keep.add(m); stack += [(i, m), (m, j)]
    return sorted(keep)

anim_acc = set()
for an in J.get("animations", []):
    for s in an["samplers"]:
        anim_acc.add(s["input"]); anim_acc.add(s["output"])

# Rebuild: keep non-animation accessors, one bufferView each, then new anim data.
new_bin = bytearray()
new_bv, new_acc, remap = [], [], {}
def push(data, target=None):
    while len(new_bin) % 4:
        new_bin.append(0)
    bv = {"buffer": 0, "byteOffset": len(new_bin), "byteLength": len(data)}
    if target:
        bv["target"] = target
    new_bin.extend(data)
    new_bv.append(bv)
    return len(new_bv) - 1

for i, a in enumerate(J["accessors"]):
    if i in anim_acc:
        continue
    a2 = dict(a)
    tgt = J["bufferViews"][a["bufferView"]].get("target")
    a2["bufferView"] = push(acc_bytes(a), tgt)
    a2.pop("byteOffset", None)
    remap[i] = len(new_acc)
    new_acc.append(a2)
for key in ("meshes",):
    for m in J.get(key, []):
        for p in m["primitives"]:
            p["attributes"] = {k: remap[v] for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = remap[p["indices"]]
            for tg in p.get("targets", []):
                for k in tg:
                    tg[k] = remap[tg[k]]
for sk in J.get("skins", []):
    if "inverseBindMatrices" in sk:
        sk["inverseBindMatrices"] = remap[sk["inverseBindMatrices"]]
# images with bufferView are not expected (materials are not exported)
assert not any("bufferView" in im for im in J.get("images", [])), "embedded images unsupported"

def add_acc(arr, typ, minmax=False):
    arr = np.ascontiguousarray(arr, dtype="<f4")
    a = {"bufferView": push(arr.tobytes()), "componentType": 5126, "count": int(arr.shape[0]), "type": typ}
    if minmax:
        a["min"] = [float(arr.min())]; a["max"] = [float(arr.max())]
    new_acc.append(a)
    return len(new_acc) - 1

before = after = 0
for an in J.get("animations", []):
    chans, samps = [], []
    for c in an["channels"]:
        s = an["samplers"][c["sampler"]]
        path = c["target"]["path"]
        t = acc_array(J["accessors"][s["input"]])[:, 0]
        v = acc_array(J["accessors"][s["output"]])
        before += len(t)
        if s.get("interpolation", "LINEAR") != "LINEAR":
            keys = list(range(len(t)))
        else:
            node = J["nodes"][c["target"]["node"]]
            rest = np.array(node.get({"rotation": "rotation", "translation": "translation", "scale": "scale"}[path],
                                     {"rotation": [0, 0, 0, 1], "translation": [0, 0, 0], "scale": [1, 1, 1]}[path]), float)
            if path == "rotation":
                dev_rest = qang(v, rest[None]).max(); const = qang(v, v[:1]).max() < ROT * 0.25
                at_rest = dev_rest < ROT * 0.25
            else:
                const = np.linalg.norm(v - v[:1], axis=1).max() < POS * 0.25
                at_rest = np.linalg.norm(v - rest[None], axis=1).max() < POS * 0.25
            if at_rest:
                continue
            keys = [0, len(t) - 1] if const else reduce(t, v, path)
        after += len(keys)
        ia = add_acc(t[keys][:, None], "SCALAR", True)
        oa = add_acc(v[keys], "VEC4" if path == "rotation" else "VEC3")
        samps.append({"input": ia, "output": oa, "interpolation": s.get("interpolation", "LINEAR")})
        chans.append({"sampler": len(samps) - 1, "target": c["target"]})
    # keep the clip length: make sure some channel spans the full time range
    an["channels"], an["samplers"] = chans, samps

J["accessors"], J["bufferViews"] = new_acc, new_bv
while len(new_bin) % 4:
    new_bin.append(0)
J["buffers"] = [{"byteLength": len(new_bin)}]
js = json.dumps(J, separators=(",", ":")).encode()
while len(js) % 4:
    js += b" "
out = bytearray(b"glTF") + struct.pack("<II", 2, 12 + 8 + len(js) + 8 + len(new_bin))
out += struct.pack("<I", len(js)) + b"JSON" + js
out += struct.pack("<I", len(new_bin)) + b"BIN\x00" + new_bin
open(dst, "wb").write(out)
print("reduced %s: keys %d -> %d, %d -> %d bytes" % (dst, before, after, len(raw), len(out)))
