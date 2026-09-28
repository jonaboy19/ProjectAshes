"""Quaternius Universal Animation Library skeleton (65 bones) read straight
from the UAL GLB, plus a minimal skinned-GLB writer that reproduces that
skeleton's node layout and rest orientations exactly.

Godot plays the UAL clips as rotation tracks on every bone plus one position
track on `pelvis`, so a mesh plays them correctly when (a) bone names match,
(b) every bone's rest *global orientation* equals the UAL one and (c) the
pelvis sits where UAL expects it (0.917 m above the root, 5 cm behind it).
Bone *positions* may differ (they are fitted to the MakeHuman body).
"""
import json, struct, os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
UAL_GLB = os.path.join(HERE, "..", "..", "assets", "incoming", "quaternius",
                       "universal-animation-library", "Unreal-Godot", "UAL1_Standard.glb")

# glTF (Y up, +Z forward) <-> Blender (Z up, -Y forward)
G2B = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]], dtype=float)
B2G = G2B.T


def read_glb_json(path):
    b = open(path, "rb").read()
    l = struct.unpack("<I", b[12:16])[0]
    return json.loads(b[20:20 + l])


def qmat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def matq(R):
    """Rotation matrix -> quaternion (x, y, z, w)."""
    m = R
    t = np.trace(m)
    if t > 0:
        s = np.sqrt(t + 1.0) * 2
        w = 0.25 * s
        x = (m[2, 1] - m[1, 2]) / s
        y = (m[0, 2] - m[2, 0]) / s
        z = (m[1, 0] - m[0, 1]) / s
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
        w = (m[2, 1] - m[1, 2]) / s
        x = 0.25 * s
        y = (m[0, 1] + m[1, 0]) / s
        z = (m[0, 2] + m[2, 0]) / s
    elif m[1, 1] > m[2, 2]:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
        w = (m[0, 2] - m[2, 0]) / s
        x = (m[0, 1] + m[1, 0]) / s
        y = 0.25 * s
        z = (m[1, 2] + m[2, 1]) / s
    else:
        s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
        w = (m[1, 0] - m[0, 1]) / s
        x = (m[0, 2] + m[2, 0]) / s
        y = (m[1, 2] + m[2, 1]) / s
        z = 0.25 * s
    q = np.array([x, y, z, w])
    return q / np.linalg.norm(q)


class UALSkeleton:
    def __init__(self, path=UAL_GLB):
        j = read_glb_json(path)
        nodes = j["nodes"]
        skin = j["skins"][0]
        self.joints = [nodes[i]["name"] for i in skin["joints"]]
        idx = {i: nodes[i]["name"] for i in skin["joints"]}
        parent = {}
        for i, n in enumerate(nodes):
            for c in n.get("children", []):
                parent[c] = i
        self.parent = {}
        self.local_rot = {}
        self.local_pos = {}
        G = {}

        def glob(i):
            if i in G:
                return G[i]
            n = nodes[i]
            M = np.eye(4)
            M[:3, :3] = qmat(n.get("rotation", [0, 0, 0, 1]))
            M[:3, 3] = n.get("translation", [0, 0, 0])
            if i in parent:
                M = glob(parent[i]) @ M
            G[i] = M
            return M
        self.global_g = {}          # glTF space 4x4
        for i, name in idx.items():
            p = parent.get(i)
            self.parent[name] = idx.get(p) if p in idx else None
            self.global_g[name] = glob(i)
            self.local_rot[name] = qmat(nodes[i].get("rotation", [0, 0, 0, 1]))
            self.local_pos[name] = np.array(nodes[i].get("translation", [0, 0, 0]))
        # order parents first
        order, seen = [], set()

        def visit(n):
            if n in seen:
                return
            if self.parent[n]:
                visit(self.parent[n])
            seen.add(n)
            order.append(n)
        for n in self.joints:
            visit(n)
        self.order = order

    def pos_b(self, name):
        return G2B @ self.global_g[name][:3, 3]

    def rot_b(self, name):
        """Global rest rotation in Blender space."""
        return G2B @ self.global_g[name][:3, :3] @ B2G

    def axis_b(self, name, k=1):
        """Bone-local axis k (1 = along the bone) as a Blender-space vector."""
        return G2B @ self.global_g[name][:3, k]


# ---------------------------------------------------------------- GLB writer

def _pad(b, fill=b"\x00"):
    while len(b) % 4:
        b += fill
    return b


def write_skinned_glb(path, skel, joint_pos_b, mesh, material, images, name="Character", extra=None):
    """Write a GLB with node tree  Armature > [root > ... bones, <name> mesh].

    joint_pos_b : {bone: global position, Blender space}
    mesh        : dict with numpy arrays  pos (N,3) nrm (N,3) uv (N,2) col (N,4)
                  joints (N,4) uint16 (indices into skel.joints) weights (N,4)
                  idx (M,) — all in Blender space
    material    : dict(name, rough, metal, normal_scale)
    images      : dict(albedo=uri, orm=uri or None, normal=uri or None)
    extra       : optional list of {"mesh": <same shape as `mesh`>, "images": {"albedo": uri},
                  "alpha": "MASK"|"BLEND"|"OPAQUE", "cutoff": float, "name": str} -- each becomes
                  an extra primitive (its own unlit-ish material) sharing this mesh's skin, e.g.
                  a small emblem/decal quad. Does not affect the primary primitive/material.
    """
    bin_ = bytearray()
    views, accs = [], []

    def add(arr, comp, typ, target=None, minmax=False, normalized=False):
        arr = np.ascontiguousarray(arr)
        off = len(bin_)
        bin_.extend(arr.tobytes())
        while len(bin_) % 4:
            bin_.append(0)
        v = {"buffer": 0, "byteOffset": off, "byteLength": arr.nbytes}
        if target:
            v["target"] = target
        views.append(v)
        a = {"bufferView": len(views) - 1, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
        if normalized:
            a["normalized"] = True
        if minmax:
            a["min"] = [float(x) for x in arr.min(axis=0)]
            a["max"] = [float(x) for x in arr.max(axis=0)]
        accs.append(a)
        return len(accs) - 1

    # joints: global transforms in glTF space
    names = skel.joints
    G = {}
    for n in skel.order:
        M = np.eye(4)
        M[:3, :3] = skel.global_g[n][:3, :3]
        if n == "root":
            M[:3, 3] = B2G @ joint_pos_b.get("root", np.zeros(3))
        else:
            M[:3, 3] = B2G @ joint_pos_b[n]
        G[n] = M
    nodes = [{"name": "Armature", "children": []}]
    node_of = {}
    for n in skel.order:
        node_of[n] = len(nodes)
        p = skel.parent[n]
        L = np.linalg.inv(G[p]) @ G[n] if p else G[n]
        R = L[:3, :3]
        nd = {"name": n, "rotation": [float(x) for x in matq(R)],
              "translation": [float(x) for x in L[:3, 3]]}
        nodes.append(nd)
    for n in skel.order:
        p = skel.parent[n]
        if p:
            nodes[node_of[p]].setdefault("children", []).append(node_of[n])
        else:
            nodes[0]["children"].append(node_of[n])
    ibm = np.stack([np.linalg.inv(G[n]).T.astype(np.float32) for n in names])  # column-major
    ibm_acc = add(ibm.reshape(len(names), 16), 5126, "MAT4")

    pos = (mesh["pos"] @ G2B).astype(np.float32)     # B->G : v @ G2B == B2G @ v
    nrm = (mesh["nrm"] @ G2B).astype(np.float32)
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-8)
    attrs = {
        "POSITION": add(pos, 5126, "VEC3", 34962, minmax=True),
        "NORMAL": add(nrm, 5126, "VEC3", 34962),
        "TEXCOORD_0": add(np.stack([mesh["uv"][:, 0], 1 - mesh["uv"][:, 1]], 1).astype(np.float32), 5126, "VEC2", 34962),
        "COLOR_0": add(mesh["col"].astype(np.float32), 5126, "VEC4", 34962),
        "JOINTS_0": add(mesh["joints"].astype(np.uint16), 5123, "VEC4", 34962),
        "WEIGHTS_0": add(mesh["weights"].astype(np.float32), 5126, "VEC4", 34962),
    }
    idx = mesh["idx"]
    ict = 5123 if idx.max() < 65535 else 5125
    iacc = add(idx.astype(np.uint16 if ict == 5123 else np.uint32), ict, "SCALAR", 34963)

    mesh_node = len(nodes)
    nodes.append({"name": name, "mesh": 0, "skin": 0})
    nodes[0]["children"].append(mesh_node)

    mat = {"name": material["name"],
           "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1],
                                    "metallicFactor": material.get("metal", 0.0),
                                    "roughnessFactor": material.get("rough", 1.0)}}
    textures, gimages = [], []

    def tex(uri):
        gimages.append({"uri": uri})
        textures.append({"source": len(gimages) - 1, "sampler": 0})
        return len(textures) - 1
    if images.get("albedo"):
        mat["pbrMetallicRoughness"]["baseColorTexture"] = {"index": tex(images["albedo"])}
    if images.get("orm"):
        t = tex(images["orm"])
        mat["pbrMetallicRoughness"]["metallicRoughnessTexture"] = {"index": t}
        mat["occlusionTexture"] = {"index": t}
    if images.get("normal"):
        mat["normalTexture"] = {"index": tex(images["normal"]), "scale": material.get("normal_scale", 1.0)}

    primitives = [{"attributes": attrs, "indices": iacc, "material": 0}]
    materials = [mat]
    if extra:
        for e in extra:
            em = e["mesh"]
            epos = (em["pos"] @ G2B).astype(np.float32)
            enrm = (em["nrm"] @ G2B).astype(np.float32)
            enrm /= np.maximum(np.linalg.norm(enrm, axis=1, keepdims=True), 1e-8)
            eattrs = {
                "POSITION": add(epos, 5126, "VEC3", 34962, minmax=True),
                "NORMAL": add(enrm, 5126, "VEC3", 34962),
                "TEXCOORD_0": add(np.stack([em["uv"][:, 0], 1 - em["uv"][:, 1]], 1).astype(np.float32), 5126, "VEC2", 34962),
                "COLOR_0": add(em["col"].astype(np.float32), 5126, "VEC4", 34962),
                "JOINTS_0": add(em["joints"].astype(np.uint16), 5123, "VEC4", 34962),
                "WEIGHTS_0": add(em["weights"].astype(np.float32), 5126, "VEC4", 34962),
            }
            eidx = em["idx"]
            eict = 5123 if eidx.max() < 65535 else 5125
            eiacc = add(eidx.astype(np.uint16 if eict == 5123 else np.uint32), eict, "SCALAR", 34963)
            alpha = e.get("alpha", "MASK")
            emat = {"name": e.get("name", "Decal"), "doubleSided": True, "alphaMode": alpha,
                    "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0,
                                            "roughnessFactor": 1.0}}
            if alpha == "MASK":
                emat["alphaCutoff"] = e.get("cutoff", 0.5)
            if e["images"].get("albedo"):
                emat["pbrMetallicRoughness"]["baseColorTexture"] = {"index": tex(e["images"]["albedo"])}
            materials.append(emat)
            primitives.append({"attributes": eattrs, "indices": eiacc, "material": len(materials) - 1})

    gl = {
        "asset": {"version": "2.0", "generator": "Rising Ashes make_humans.py"},
        "scene": 0,
        "scenes": [{"name": name, "nodes": [0]}],
        "nodes": nodes,
        "meshes": [{"name": name, "primitives": primitives}],
        "skins": [{"name": "Armature", "joints": [node_of[n] for n in names],
                   "inverseBindMatrices": ibm_acc, "skeleton": node_of["root"]}],
        "materials": materials,
        "accessors": accs,
        "bufferViews": views,
        "buffers": [{"byteLength": len(bin_)}],
    }
    if textures:
        gl["textures"] = textures
        gl["images"] = gimages
        gl["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]
    js = _pad(json.dumps(gl, separators=(",", ":")).encode(), b" ")
    bb = _pad(bytes(bin_))
    total = 12 + 8 + len(js) + 8 + len(bb)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A))
        f.write(js)
        f.write(struct.pack("<II", len(bb), 0x004E4942))
        f.write(bb)
    return path
