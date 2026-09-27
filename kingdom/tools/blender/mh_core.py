"""MakeHuman (MPFB2, CC0) base-mesh loading, macro targets, joints and posing.

Pure numpy; used by make_humans.py. Conventions (Blender space): metres, +Z up,
the character faces -Y, its left side is +X.
"""
import gzip, json, os, math
import numpy as np

MPFB = os.environ.get("MPFB_DATA", "/tmp/claude-0/mh/mpfb2/src/mpfb/data")
MHDATA = os.environ.get("MH_DATA", "/tmp/claude-0/mh/mh/makehuman/data")
TARGETS = os.path.join(MPFB, "targets")

# ---------------------------------------------------------------- base mesh

class BaseMesh:
    """hm08 base mesh: vertices (MH units, Y up), UVs, faces grouped by name."""

    def __init__(self, path=None):
        path = path or os.path.join(MPFB, "3dobjs", "base.obj")
        verts, uvs, faces, fuv, fgroup = [], [], [], [], []
        groups = []
        cur = -1
        with open(path) as f:
            for line in f:
                if line.startswith("v "):
                    verts.append([float(x) for x in line.split()[1:4]])
                elif line.startswith("vt "):
                    uvs.append([float(x) for x in line.split()[1:3]])
                elif line.startswith("g "):
                    groups.append(line.split(None, 1)[1].strip())
                    cur = len(groups) - 1
                elif line.startswith("f "):
                    vi, ti = [], []
                    for tok in line.split()[1:]:
                        p = tok.split("/")
                        vi.append(int(p[0]) - 1)
                        ti.append(int(p[1]) - 1 if len(p) > 1 and p[1] else 0)
                    faces.append(vi)
                    fuv.append(ti)
                    fgroup.append(cur)
        self.v = np.array(verts, dtype=np.float64)
        self.uv = np.array(uvs, dtype=np.float64)
        self.faces = faces
        self.fuv = fuv
        self.fgroup = np.array(fgroup)
        self.groups = groups
        with open(os.path.join(MPFB, "mesh_metadata", "basemesh_vertex_groups.json")) as f:
            self.vgroups = json.load(f)

    def group_verts(self, name):
        out = []
        for a, b in self.vgroups[name]:
            out.extend(range(a, b + 1))
        return np.array(out, dtype=np.int64)

    def faces_of_group(self, name):
        gi = self.groups.index(name)
        return [i for i, g in enumerate(self.fgroup) if g == gi]


# ---------------------------------------------------------------- targets

_target_cache = {}


def load_target(rel):
    """rel like 'macrodetails/caucasian-female-young' -> (idx, offsets)."""
    if rel in _target_cache:
        return _target_cache[rel]
    path = os.path.join(TARGETS, rel + ".target.gz")
    idx, off = [], []
    with gzip.open(path, "rt") as f:
        for line in f:
            p = line.split()
            if len(p) < 4 or line.startswith("#"):
                continue
            idx.append(int(p[0]))
            off.append([float(p[1]), float(p[2]), float(p[3])])
    r = (np.array(idx, dtype=np.int64), np.array(off, dtype=np.float64).reshape(-1, 3))
    _target_cache[rel] = r
    return r


with open(os.path.join(TARGETS, "macrodetails", "macro.json")) as _f:
    MACRO = json.load(_f)["macrotargets"]


def _interp(name, value):
    comps = []
    for part in MACRO[name]["parts"]:
        lo, hi = part["lowest"], part["highest"]
        if lo < value < hi:
            pct = (value - lo) / (hi - lo)
            if part["low"]:
                comps.append((part["low"], 1 - pct))
            if part["high"]:
                comps.append((part["high"], pct))
    return comps


def age_to_macro(years):
    """MakeHuman age slider: 0 = 1 yr, 0.1875 = 11 yr, 0.5 = 25 yr, 1 = 90 yr."""
    if years < 11:
        return max(0.0, (years - 1) / 10 * 0.1875)
    if years < 25:
        return 0.1875 + (years - 11) / 14 * 0.3125
    return min(1.0, 0.5 + (years - 25) / 65 * 0.5)


def macro_stack(gender, age_years, muscle=0.5, weight=0.5, height=0.5,
                proportions=0.5, race=None, cupsize=0.5, firmness=0.5, cutoff=0.01):
    """Port of MPFB TargetService.calculate_target_stack_from_macro_info_dict."""
    race = race or {"caucasian": 1.0}
    tot = sum(race.values())
    race = {k: v / tot for k, v in race.items()}
    c = {
        "gender": _interp("gender", gender),
        "age": _interp("age", age_to_macro(age_years)),
        "muscle": _interp("muscle", muscle),
        "weight": _interp("weight", weight),
        "height": _interp("height", height),
        "proportions": _interp("proportions", proportions),
        "cupsize": _interp("cupsize", cupsize),
        "firmness": _interp("firmness", firmness),
    }
    out = []
    for r, rw in race.items():
        if rw <= 1e-4:
            continue
        for a, aw in c["age"]:
            for g, gw in c["gender"]:
                w = rw * gw * aw
                if w > cutoff:
                    out.append((f"macrodetails/{r}-{g}-{a}", w))
    for g, gw in c["gender"]:
        for a, aw in c["age"]:
            for m, mw in c["muscle"]:
                for wt, ww in c["weight"]:
                    w = gw * aw * mw * ww
                    if w > cutoff:
                        out.append((f"macrodetails/universal-{g}-{a}-{m}-{wt}", w))
                    for h, hw in c["height"]:
                        if w * hw > cutoff:
                            out.append((f"macrodetails/height/{g}-{a}-{m}-{wt}-{h}", w * hw))
                    for p, pw in c["proportions"]:
                        if w * pw > cutoff and a != "baby":
                            out.append((f"macrodetails/proportions/{g}-{a}-{m}-{wt}-{p}", w * pw))
                    if g == "female":
                        for cu, cw in c["cupsize"]:
                            for fi, fw in c["firmness"]:
                                w2 = aw * mw * ww * cw * fw
                                name = f"breast/{g}-{a}-{m}-{wt}-{cu}-{fi}"
                                if w2 > cutoff and "averagecup-averagefirmness" not in name and a != "baby":
                                    out.append((name, w2))
    return out


def morph(base, stack, extras=None):
    """Apply weighted targets to a copy of the base vertices (MH units)."""
    v = base.v.copy()
    for rel, w in list(stack) + list((extras or {}).items()):
        path = os.path.join(TARGETS, rel + ".target.gz")
        if not os.path.exists(path):
            print("missing target", rel)
            continue
        idx, off = load_target(rel)
        v[idx] += off * w
    return v


def to_blender(v):
    """MH (Y up, decimetres, facing +Z) -> Blender (Z up, metres, facing -Y)."""
    return np.stack([v[:, 0], -v[:, 2], v[:, 1]], axis=1) * 0.1


# ---------------------------------------------------------------- rig

with open(os.path.join(MPFB, "rigs", "standard", "rig.game_engine.json")) as _f:
    MH_RIG = json.load(_f)
with open(os.path.join(MPFB, "rigs", "standard", "weights.game_engine.json")) as _f:
    MH_WEIGHTS = json.load(_f)["weights"]


def ue_name(mh):
    return "Head" if mh == "head" else mh


def joint_positions(base, vb):
    """Centroid of every joint-* cube (Blender space)."""
    out = {}
    for name in base.vgroups:
        if name.startswith("joint-"):
            out[name] = vb[base.group_verts(name)].mean(axis=0)
    return out


def _pos(spec, joints, vb):
    if spec["strategy"] == "CUBE":
        return joints[spec["cube_name"]]
    if spec["strategy"] == "MEAN":
        return vb[spec["vertex_indices"]].mean(axis=0)
    return np.array(spec["default_position"])


def mh_bones(base, vb):
    """{bone: (head, tail, parent)} for the MH game_engine rig (no Root)."""
    joints = joint_positions(base, vb)
    out = {}
    for name, b in MH_RIG.items():
        if name == "Root":
            continue
        par = b.get("parent")
        out[name] = (_pos(b["head"], joints, vb), _pos(b["tail"], joints, vb),
                     None if par in (None, "Root") else par)
    return out, joints


def weight_matrix(nverts, bone_names):
    """Dense (nverts, nbones) weights from the MH game_engine weights."""
    W = np.zeros((nverts, len(bone_names)))
    for bi, bn in enumerate(bone_names):
        for vi, w in MH_WEIGHTS.get(bn, []):
            if vi < nverts:
                W[vi, bi] = w
    s = W.sum(axis=1, keepdims=True)
    return W, s[:, 0]


def rot_between(a, b):
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    if c < -0.9999:
        axis = np.cross(a, [1, 0, 0])
        if np.linalg.norm(axis) < 1e-6:
            axis = np.cross(a, [0, 1, 0])
        axis /= np.linalg.norm(axis)
        return axis_angle(axis, math.pi)
    vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + vx + vx @ vx * (1 / (1 + c))


def axis_angle(axis, ang):
    axis = np.asarray(axis, dtype=float)
    axis = axis / np.linalg.norm(axis)
    x, y, z = axis
    c, s = math.cos(ang), math.sin(ang)
    C = 1 - c
    return np.array([[c + x * x * C, x * y * C - z * s, x * z * C + y * s],
                     [y * x * C + z * s, c + y * y * C, y * z * C - x * s],
                     [z * x * C - y * s, z * y * C + x * s, c + z * z * C]])


def frame(primary, secondary):
    y = primary / np.linalg.norm(primary)
    x = secondary - y * np.dot(secondary, y)
    x /= np.linalg.norm(x)
    z = np.cross(x, y)
    return np.stack([x, y, z], axis=1)


def topo(bones):
    order, seen = [], set()

    def visit(n):
        if n in seen:
            return
        p = bones[n][2]
        if p:
            visit(p)
        seen.add(n)
        order.append(n)
    for n in bones:
        visit(n)
    return order


def pose_to_targets(vb, bones, W, bone_names, target_dir, second=None):
    """Rotate every MH bone so head->tail points along target_dir[bone]
    (Blender space); `second` = {bone: (mh_vec_fn, target_vec)} fixes the roll
    of selected bones. Linear-blend skins the vertices. Returns (verts, T)."""
    T = {}
    for n in topo(bones):
        h, t, p = bones[n]
        M = T[p].copy() if p else np.eye(4)
        if n in target_dir:
            hh = M[:3, :3] @ h + M[:3, 3]
            cur = M[:3, :3] @ (t - h)
            if second and n in second:
                mh_sec, tgt_sec = second[n]
                cs = M[:3, :3] @ mh_sec
                R = frame(target_dir[n], tgt_sec) @ frame(cur, cs).T
            else:
                R = rot_between(cur, target_dir[n])
            A = np.eye(4)
            A[:3, :3] = R
            A[:3, 3] = hh - R @ hh
            M = A @ M
        T[n] = M
    Ts = np.stack([T[n] for n in bone_names])          # (B,4,4)
    vh = np.concatenate([vb, np.ones((len(vb), 1))], axis=1)
    s = W.sum(axis=1, keepdims=True)
    Wn = np.where(s > 0, W / np.maximum(s, 1e-9), 0)
    out = np.einsum("vb,bij,vj->vi", Wn, Ts, vh)[:, :3]
    none = s[:, 0] <= 0
    out[none] = vb[none]
    return out, T
