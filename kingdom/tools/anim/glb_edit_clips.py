# Edit the clips of an animation-library GLB in place (pure python + numpy, no Blender):
#   delete, rename, trim to a time window, remove double-counted pelvis travel.
# Used for the review fixes of the free clip libraries (docs/anim/free_library/review_results.md), so
# the GLB and its *.clips.json sidecar stay consistent without re-running the whole retarget.
#
#   python glb_edit_clips.py audit <glb> [<glb> ...]            pelvis start offset / root travel per clip
#   python glb_edit_clips.py edit  <glb> <edits.json>           apply edits, rewrite glb + <glb>.clips.json
#
# edits.json:
#   {"delete": ["ClipA"], "rename": {"Old": "New"}, "trim": {"Clip": [t0_s, t1_s]},
#    "pelvis_untravel": ["Clip"], "loop": ["Clip"]}
#  trim:            keeps [t0, t1], boundary keys are interpolated, times are re-based to 0
#  pelvis_untravel: some KayKit dodges carry their travel twice (root track AND pelvis translation). The
#                   horizontal pelvis translation (armature x / y, z is up) minus its own progress
#                   path is kept (sway only); the `root` track keeps the travel.
#  loop:            append "_Loop" to the name (Godot then imports it as looping)
# The animation names keep their "_Loop" suffix rule: rename to a name ending in _Loop to make it loop.
import json, struct, sys, os
import numpy as np

NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
CT = {5126: ("f4", 4), 5123: ("u2", 2), 5125: ("u4", 4), 5121: ("u1", 1), 5122: ("i2", 2), 5120: ("i1", 1)}


class Glb:
    def __init__(self, path):
        raw = open(path, "rb").read()
        assert raw[:4] == b"glTF"
        jl = struct.unpack("<I", raw[12:16])[0]
        self.J = json.loads(raw[20:20 + jl])
        off = 20 + jl
        bl = struct.unpack("<I", raw[off:off + 4])[0]
        self.BIN = raw[off + 8: off + 8 + bl]
        self.path = path

    def acc_bytes(self, a):
        bv = self.J["bufferViews"][a["bufferView"]]
        dt, sz = CT[a["componentType"]]
        n = NC[a["type"]] * a["count"] * sz
        s = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        return self.BIN[s:s + n]

    def acc_array(self, i):
        a = self.J["accessors"][i]
        dt, _ = CT[a["componentType"]]
        return np.frombuffer(self.acc_bytes(a), dtype="<" + dt).reshape(a["count"], NC[a["type"]]).astype(np.float64)

    def anims(self):
        """name -> list of channel dicts {node, path, t, v}"""
        out = {}
        for an in self.J.get("animations", []):
            chans = []
            for c in an["channels"]:
                s = an["samplers"][c["sampler"]]
                chans.append({"node": c["target"]["node"], "path": c["target"]["path"],
                              "t": self.acc_array(s["input"])[:, 0], "v": self.acc_array(s["output"])})
            out[an["name"]] = chans
        return out

    def node_name(self, i):
        return self.J["nodes"][i]["name"]

    def write(self, anims, path=None):
        J = self.J
        anim_acc = set()
        for an in J.get("animations", []):
            for s in an["samplers"]:
                anim_acc.add(s["input"]); anim_acc.add(s["output"])
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
            a2["bufferView"] = push(self.acc_bytes(a), tgt)
            a2.pop("byteOffset", None)
            remap[i] = len(new_acc)
            new_acc.append(a2)
        for m in J.get("meshes", []):
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

        def add_acc(arr, typ, minmax=False):
            arr = np.ascontiguousarray(arr, dtype="<f4")
            a = {"bufferView": push(arr.tobytes()), "componentType": 5126, "count": int(arr.shape[0]), "type": typ}
            if minmax:
                a["min"] = [float(arr.min())]; a["max"] = [float(arr.max())]
            new_acc.append(a)
            return len(new_acc) - 1

        new_anims = []
        for name, chans in anims.items():
            samplers, channels = [], []
            for c in chans:
                ia = add_acc(c["t"][:, None], "SCALAR", True)
                oa = add_acc(c["v"], "VEC4" if c["path"] == "rotation" else "VEC3")
                samplers.append({"input": ia, "output": oa, "interpolation": "LINEAR"})
                channels.append({"sampler": len(samplers) - 1, "target": {"node": c["node"], "path": c["path"]}})
            new_anims.append({"name": name, "channels": channels, "samplers": samplers})
        J["animations"] = new_anims
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
        open(path or self.path, "wb").write(out)


def slerp(a, b, w):
    d = float(np.dot(a, b))
    if d < 0:
        b = -b; d = -d
    if d > 0.9995:
        r = a + (b - a) * w
        return r / np.linalg.norm(r)
    th = np.arccos(min(d, 1.0)); s = np.sin(th)
    return (np.sin((1 - w) * th) * a + np.sin(w * th) * b) / s


def sample(t, v, path, x):
    """value of a channel at time x (clamped)"""
    if x <= t[0]:
        return v[0].copy()
    if x >= t[-1]:
        return v[-1].copy()
    i = int(np.searchsorted(t, x) - 1)
    w = (x - t[i]) / (t[i + 1] - t[i])
    return slerp(v[i], v[i + 1], w) if path == "rotation" else v[i] * (1 - w) + v[i + 1] * w


def trim_channel(c, t0, t1):
    t, v = c["t"], c["v"]
    inner = [i for i in range(len(t)) if t0 + 1e-6 < t[i] < t1 - 1e-6]
    times = [t0] + [t[i] for i in inner] + [t1]
    vals = [sample(t, v, c["path"], t0)] + [v[i] for i in inner] + [sample(t, v, c["path"], t1)]
    c["t"] = np.array(times) - t0
    c["v"] = np.array(vals)


def untravel(g, chans):
    for c in chans:
        if g.node_name(c["node"]) == "pelvis" and c["path"] == "translation":
            v = c["v"].copy()
            h = v[:, :2]                                   # armature x / y (z is up)
            step = np.linalg.norm(np.diff(h, axis=0), axis=1)
            cum = np.concatenate([[0], np.cumsum(step)])
            u = cum / cum[-1] if cum[-1] > 1e-6 else np.zeros(len(cum))
            path = h[0] + (h[-1] - h[0]) * u[:, None]
            v[:, :2] = h - path + np.array([0.0, 0.05])   # rest pelvis y = 0.05
            c["v"] = v


def clip_len(chans):
    return max(float(c["t"][-1]) for c in chans)


def audit(paths):
    for p in paths:
        g = Glb(p)
        print("==", os.path.basename(p))
        for name, chans in g.anims().items():
            pel = [c for c in chans if g.node_name(c["node"]) == "pelvis" and c["path"] == "translation"]
            rt = [c for c in chans if g.node_name(c["node"]) == "root" and c["path"] == "translation"]
            s = "%-32s %.2fs" % (name, clip_len(chans))
            if pel:
                v = pel[0]["v"]
                s += "  pelvis0 x=%+.2f y=%+.2f  end x=%+.2f y=%+.2f  z %.2f..%.2f" % (v[0, 0], v[0, 1] - 0.05, v[-1, 0], v[-1, 1] - 0.05, v[:, 2].min(), v[:, 2].max())
            if rt:
                r = rt[0]["v"]
                s += "  root travel x=%+.2f y=%+.2f z=%+.2f" % tuple(r[-1] - r[0])
            print(s)


def edit(path, spec):
    g = Glb(path)
    anims = g.anims()
    for n in spec.get("delete", []):
        assert n in anims, "no clip " + n
        del anims[n]
    for n, (t0, t1) in spec.get("trim", {}).items():
        assert n in anims, "no clip " + n
        for c in anims[n]:
            trim_channel(c, t0, min(t1, clip_len(anims[n])))
    for n in spec.get("pelvis_untravel", []):
        untravel(g, anims[n])
    ren = dict(spec.get("rename", {}))
    for n in spec.get("loop", []):
        ren[n] = n + "_Loop"
    out = {}
    for n, ch in anims.items():
        out[ren.get(n, n)] = ch
    g.write(out)
    # sidecar
    side = path + ".clips.json"
    if os.path.exists(side):
        rows = json.load(open(side, encoding="utf-8"))
        keep = []
        for r in rows:
            if r["name"] in spec.get("delete", []):
                continue
            if r["name"] in spec.get("trim", {}):
                t0, t1 = spec["trim"][r["name"]]
                r["seconds"] = round(t1 - t0, 2)
                r["frames"] = int(round((t1 - t0) * 30))
                if r.get("range_s") and r["range_s"][0] is not None:
                    r["range_s"] = [round(r["range_s"][0] + t0, 2), round(r["range_s"][0] + t1, 2)]
                r["trimmed_from_s"] = [t0, t1]
            if r["name"] in ren:
                r["renamed_from"] = r["name"]
                r["name"] = ren[r["name"]]
            keep.append(r)
        json.dump(keep, open(side, "w", encoding="utf-8"), indent=1)
    print("edited %s: %d clips" % (path, len(out)))


if __name__ == "__main__":
    if sys.argv[1] == "audit":
        audit(sys.argv[2:])
    else:
        edit(sys.argv[2], json.load(open(sys.argv[3], encoding="utf-8")))
