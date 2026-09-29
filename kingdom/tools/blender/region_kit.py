"""Shared kit for the first-region asset sets (make_region_<set>.py), bpy / Blender 5.x.

- RB: a mesh accumulator (per-corner UV, colour, custom normal, material) with a frame stack and
  primitives (box, beam, cyl, tube, lathe, prism, sheet, card, poly). Metres, +Z up in Blender
  (glTF export -> Godot +Y up), origin at ground centre, the "front" faces Blender -Y (Godot +Z).
- Materials are shared by NAME across every region GLB and reference the painted textures in
  kingdom/assets/generated/region/textures/ by relative URI (never embedded), so Godot loads each
  texture once. Two COLOR_0 conventions, decided by the material:
    * nature materials (RG_Foliage, RG_Bark, RG_Rock, RG_Moss): COLOR_0 = WIND DATA
        R = sway weight (0 = rigid, 1 = free tip), G = per-cluster phase 0..1,
        B = baked ambient occlusion (multiply into albedo), A = 1
      Godot: the .glb.import files swap these materials for region/nature/*.tres (wind shader).
    * every other RG_* material: COLOR_0 = albedo tint (sRGB authored, stored linear) x baked
      grime; Godot's default glTF import multiplies it into albedo (no override needed).
- export(): glTF-separate then packed into one .glb that still points at ../textures/*.png.
- Previews: render_thumb() (Cycles, warm sun + sky) and sheet() (labelled contact sheet).
"""
import os, sys, math, random, json, struct
import bpy
from mathutils import Vector, Matrix, Euler, noise

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
REGION = os.path.join(ROOT, "kingdom", "assets", "generated", "region")
TEX = os.path.join(REGION, "textures")
PREV = os.path.join(ROOT, "docs", "kingdom", "blender_previews")
THUMBS = os.path.join(PREV, "region")


def lin(c):
    return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def vary(c, amt=0.08, rng=random):
    k = 1 + rng.uniform(-amt, amt)
    return tuple(min(1.0, x * k) for x in c)


def xf(loc=(0, 0, 0), rot=(0, 0, 0), scale=None):
    m = Matrix.LocRotScale(Vector(loc), Euler(rot), None)
    if scale is not None:
        m = m @ Matrix.Diagonal((*scale, 1.0))
    return m


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ================================================================================ materials
MATS = {
    # nature: COLOR_0 = wind data
    "RG_Foliage": dict(tex="foliage_atlas.png", kind="wind", alpha=True, rough=0.8),
    "RG_Bark": dict(tex="bark_atlas.png", kind="wind", rough=0.95),
    "RG_Rock": dict(tex="rock.png", kind="wind", scale=2.2, rough=0.9),
    "RG_Moss": dict(tex="moss.png", kind="wind", scale=1.4, rough=1.0),
    # structures: COLOR_0 = tint
    "RG_Planks": dict(tex="planks.png", scale=1.0, rough=0.8),
    "RG_Timber": dict(tex="timber.png", scale=2.0, rough=0.8),
    "RG_Stone": dict(tex="stone_wall.png", scale=2.0, rough=0.9),
    "RG_Ruin": dict(tex="ruin_stone.png", scale=3.2, rough=0.92),   # grey weathered masonry (make_ruin_stone_texture.py)
    "RG_Plaster": dict(tex="plaster.png", scale=2.0, rough=0.95),
    "RG_Thatch": dict(tex="thatch.png", scale=1.6, rough=1.0),
    "RG_Shingle": dict(tex="shingle.png", scale=1.6, rough=0.85),
    "RG_Slate": dict(tex="slate.png", scale=1.5, rough=0.6),
    "RG_Iron": dict(tex="iron.png", scale=0.7, rough=0.5, metal=0.6),
    "RG_Canvas": dict(tex="canvas.png", scale=1.5, rough=0.95),
    "RG_Hay": dict(tex="hay.png", scale=1.0, rough=1.0),
    "RG_Soil": dict(tex="soil.png", scale=2.0, rough=1.0),
    "RG_Cliff": dict(tex="rock.png", scale=3.5, rough=0.9),
    "RG_Log": dict(tex="bark_atlas.png", rough=0.95),
    "RG_Crop": dict(tex="foliage_atlas.png", alpha=True, rough=0.85),
    "RG_Glow": dict(tex=None, glow=True),
    "RG_Impostor": dict(tex="tree_impostors.png", kind="plain", alpha=True, rough=0.9),
}
WIND_MATS = {k for k, v in MATS.items() if v.get("kind") == "wind"}


def load_img(name, noncolor=False):
    p = os.path.join(TEX, name)
    im = bpy.data.images.get(name)
    if im is None:
        im = bpy.data.images.load(p)
        im.name = name
    return im


def _mul(nt, a, b):
    mx = nt.nodes.new("ShaderNodeMix")
    mx.data_type = "RGBA"
    mx.blend_type = "MULTIPLY"
    mx.inputs[0].default_value = 1.0
    ia = next(s for s in mx.inputs if s.identifier == "A_Color")
    ib = next(s for s in mx.inputs if s.identifier == "B_Color")
    nt.links.new(a, ia)
    nt.links.new(b, ib)
    return next(s for s in mx.outputs if s.identifier == "Result_Color")


def get_mat(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    spec = MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    kind = spec.get("kind", "tint")
    tex = None
    if spec.get("tex"):
        tn = nt.nodes.new("ShaderNodeTexImage")
        tn.image = load_img(spec["tex"])
        tn.interpolation = "Linear"
        tn.name = "RG_Tex"
        tex = tn
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    vc.name = "RG_VC"
    if spec.get("glow"):
        nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(vc.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 3.0
    elif kind == "tint":
        nt.links.new(_mul(nt, tex.outputs["Color"], vc.outputs["Color"]) if tex else vc.outputs["Color"],
                     bsdf.inputs["Base Color"])
    else:   # wind / plain: texture only (preview_patch() adds the AO multiply for renders)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = spec.get("rough", 0.85)
    bsdf.inputs["Metallic"].default_value = spec.get("metal", 0.0)
    try:
        bsdf.inputs["Specular IOR Level"].default_value = 0.3
    except KeyError:
        pass
    if spec.get("alpha"):
        lt = nt.nodes.new("ShaderNodeMath")
        lt.operation = "LESS_THAN"
        lt.inputs[1].default_value = 0.5
        nt.links.new(tex.outputs["Alpha"], lt.inputs[0])
        sub = nt.nodes.new("ShaderNodeMath")
        sub.operation = "SUBTRACT"
        sub.inputs[0].default_value = 1.0
        nt.links.new(lt.outputs[0], sub.inputs[1])
        nt.links.new(sub.outputs[0], bsdf.inputs["Alpha"])
        m.use_backface_culling = False
        try:
            m.surface_render_method = "DITHERED"
        except Exception:
            pass
    else:
        m.use_backface_culling = True
    return m


def preview_patch(translucency=0.5):
    """PREVIEW ONLY (after export): multiply wind materials by the baked AO in COLOR_0.B and let
    light through leaves (Godot's equivalent is the shader's backlight)."""
    for m in bpy.data.materials:
        if m.name.split(".")[0] not in WIND_MATS or m.get("rg_patched"):
            continue
        m["rg_patched"] = True
        nt = m.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        tex = nt.nodes["RG_Tex"]
        vc = nt.nodes["RG_VC"]
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(vc.outputs["Color"], sep.inputs[0])
        comb = nt.nodes.new("ShaderNodeCombineColor")
        for i in range(3):
            nt.links.new(sep.outputs[2], comb.inputs[i])
        col = _mul(nt, tex.outputs["Color"], comb.outputs[0])
        nt.links.new(col, bsdf.inputs["Base Color"])
        if MATS[m.name.split(".")[0]].get("alpha") and translucency:
            out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
            tr = nt.nodes.new("ShaderNodeBsdfTranslucent")
            nt.links.new(col, tr.inputs["Color"])
            mx = nt.nodes.new("ShaderNodeMixShader")
            mx.inputs[0].default_value = translucency
            nt.links.new(bsdf.outputs[0], mx.inputs[1])
            nt.links.new(tr.outputs[0], mx.inputs[2])
            tp = nt.nodes.new("ShaderNodeBsdfTransparent")
            mx2 = nt.nodes.new("ShaderNodeMixShader")
            nt.links.new(bsdf.inputs["Alpha"].links[0].from_socket, mx2.inputs[0])
            nt.links.new(tp.outputs[0], mx2.inputs[1])
            nt.links.new(mx.outputs[0], mx2.inputs[2])
            nt.links.new(mx2.outputs[0], out.inputs["Surface"])


# ================================================================================ builder
def newell(pts):
    n = Vector((0, 0, 0))
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n


class RB:
    def __init__(self, name, seed=1):
        self.name = name
        self.rng = random.Random(seed)
        self.V, self.F, self.FM, self.UV, self.C, self.N = [], [], [], [], [], []
        self.mnames = []
        self.frames = [Matrix.Identity(4)]
        self.grime = 0.7
        self.grime_amt = 0.3

    # ---------------------------------------------------------------- frames
    def push(self, loc=(0, 0, 0), rot=(0, 0, 0), scale=None):
        self.frames.append(self.frames[-1] @ xf(loc, rot, scale))

    def pop(self):
        self.frames.pop()

    def M(self):
        return self.frames[-1]

    # ---------------------------------------------------------------- low level
    def _mi(self, mat):
        if mat not in self.mnames:
            self.mnames.append(mat)
        return self.mnames.index(mat)

    def tint_col(self, tint, p):
        z = p.z
        k = 1.0 - self.grime_amt * max(0.0, 1.0 - max(z, 0.0) / self.grime) if z < self.grime else 1.0
        c = lin(tint)
        return (c[0] * k, c[1] * k, c[2] * k, 1.0)

    def face(self, pts, uvs, cols, nrms, mat):
        """pts in asset space. cols linear RGBA per corner, nrms per corner (or None = flat)."""
        n = newell(pts)
        if n.length < 1e-10:
            return
        if nrms is None:
            nn = n.normalized()
            nrms = [nn] * len(pts)
        i0 = len(self.V)
        self.V.extend([tuple(p) for p in pts])
        self.F.append(tuple(range(i0, i0 + len(pts))))
        self.FM.append(self._mi(mat))
        self.UV.extend([tuple(u) for u in uvs])
        self.C.extend([tuple(c) for c in cols])
        self.N.extend([tuple(Vector(v).normalized()) for v in nrms])

    def add(self, faces, mat, tint=(1, 1, 1), M=None, scale=None, grain=None, uvs=None, nrm_fn=None,
            col_fn=None, uoff=None):
        """faces: lists of local Vectors. Box-projected UVs in LOCAL space (grain = local axis the
        texture U follows). tint (sRGB) for tint materials; col_fn(p_world, n_world) -> linear RGBA
        overrides (wind data for nature materials)."""
        M = self.M() @ (M if M is not None else Matrix.Identity(4))
        R = M.to_3x3().inverted().transposed()
        s = scale or MATS[mat].get("scale", 1.0)
        if uoff is None:
            uoff = (self.rng.uniform(0, 1), self.rng.uniform(0, 1))
        for fi, f in enumerate(faces):
            f = [Vector(p) for p in f]
            if uvs is not None:
                fuv = uvs[fi]
            else:
                n = newell(f)
                ax = max(range(3), key=lambda i: abs(n[i]))
                axes = [i for i in range(3) if i != ax]
                if grain is not None and grain in axes:
                    U = grain
                    V = axes[0] if axes[1] == grain else axes[1]
                elif ax == 2:
                    U, V = 0, 1
                else:
                    U, V = axes[0], 2
                sg = 1 if n[ax] >= 0 else -1
                fuv = [((p[U] * (sg if ax != 2 else 1)) / s + uoff[0], p[V] / s + uoff[1]) for p in f]
            wp = [M @ p for p in f]
            if nrm_fn:
                wn = [(R @ Vector(nrm_fn(p))).normalized() for p in f]
            else:
                wn = None
            fn_ = newell(wp).normalized() if newell(wp).length > 0 else Vector((0, 0, 1))
            if col_fn:
                cols = [col_fn(p, wn[i] if wn else fn_) for i, p in enumerate(wp)]
            else:
                cols = [self.tint_col(tint, p) for p in wp]
            self.face(wp, fuv, cols, wn, mat)

    # ---------------------------------------------------------------- primitives
    def box(self, size, loc, mat, tint=(1, 1, 1), rot=(0, 0, 0), grain=None, skip=(), **kw):
        """Box of `size` centred at loc. skip: face names to omit ('-z' bottom, '+z' top ...)."""
        sx, sy, sz = (x / 2 for x in size)
        P = lambda x, y, z: Vector((x * sx, y * sy, z * sz))
        F = {"-z": [P(-1, -1, -1), P(-1, 1, -1), P(1, 1, -1), P(1, -1, -1)],
             "+z": [P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1)],
             "-y": [P(-1, -1, -1), P(1, -1, -1), P(1, -1, 1), P(-1, -1, 1)],
             "+y": [P(1, 1, -1), P(-1, 1, -1), P(-1, 1, 1), P(1, 1, 1)],
             "-x": [P(-1, 1, -1), P(-1, -1, -1), P(-1, -1, 1), P(-1, 1, 1)],
             "+x": [P(1, -1, -1), P(1, 1, -1), P(1, 1, 1), P(1, -1, 1)]}
        self.add([v for k, v in F.items() if k not in skip], mat, tint, xf(loc, rot), grain=grain, **kw)

    def beam(self, a, b, w, d, mat, tint=(1, 1, 1), up=(0, 0, 1), ext=0.0, **kw):
        """Rectangular timber from a to b; `w` across `up`, `d` the other way."""
        a, b = Vector(a), Vector(b)
        z = (b - a).normalized()
        a, b = a - z * ext, b + z * ext
        L = (b - a).length
        u = Vector(up)
        x = u - z * u.dot(z)
        if x.length < 1e-5:
            x = Vector((1, 0, 0)) - z * z.x
            if x.length < 1e-5:
                x = Vector((0, 1, 0))
        x.normalize()
        y = z.cross(x)
        m = Matrix(((x.x, y.x, z.x, a.x), (x.y, y.y, z.y, a.y), (x.z, y.z, z.z, a.z), (0, 0, 0, 1)))
        hw, hd = w / 2, d / 2
        P = lambda i, j, k: Vector((i * hw, j * hd, k * L))
        faces = [[P(-1, -1, 0), P(-1, 1, 0), P(1, 1, 0), P(1, -1, 0)],
                 [P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1), P(-1, 1, 1)],
                 [P(-1, -1, 0), P(1, -1, 0), P(1, -1, 1), P(-1, -1, 1)],
                 [P(1, 1, 0), P(-1, 1, 0), P(-1, 1, 1), P(1, 1, 1)],
                 [P(-1, 1, 0), P(-1, -1, 0), P(-1, -1, 1), P(-1, 1, 1)],
                 [P(1, -1, 0), P(1, 1, 0), P(1, 1, 1), P(1, -1, 1)]]
        self.add(faces, mat, tint, m, grain=2, **kw)

    def _ring(self, r, z, segs, phase=0.0, jitter=0.0, nfn=None):
        out = []
        for i in range(segs):
            a = phase + i / segs * math.tau
            rr = r * (1 + (self.rng.uniform(-jitter, jitter) if jitter else 0))
            out.append(Vector((math.cos(a) * rr, math.sin(a) * rr, z)))
        return out

    def cyl(self, r, h, loc, mat, tint=(1, 1, 1), rot=(0, 0, 0), segs=10, r2=None, caps=(True, True),
            smooth=True, col_fn=None, bark=None, jitter=0.0):
        r2 = r if r2 is None else r2
        prof = [(r, 0.0), (r2, h)]
        self.lathe(prof, loc, mat, tint, rot=rot, segs=segs, caps=caps, smooth=smooth, col_fn=col_fn,
                   bark=bark, jitter=jitter)

    def lathe(self, prof, loc, mat, tint=(1, 1, 1), rot=(0, 0, 0), segs=10, caps=(True, True), smooth=True,
              col_fn=None, bark=None, jitter=0.0, uscale=None):
        """Surface of revolution from profile [(r, z), ...] around local Z. U wraps around in whole
        texture tiles (seamless); bark=column index maps into bark_atlas columns."""
        s = uscale or MATS[mat].get("scale", 1.0)
        rings = []
        jit = [1 + self.rng.uniform(-jitter, jitter) for _ in range(segs)] if jitter else [1] * segs
        for r, z in prof:
            rings.append([Vector((math.cos(i / segs * math.tau) * r * jit[i], math.sin(i / segs * math.tau) * r * jit[i], z))
                          for i in range(segs)])
        rmax = max(p[0] for p in prof)
        tiles = max(1, round(math.tau * rmax / s))
        arc = [0.0]
        for i in range(1, len(prof)):
            arc.append(arc[-1] + math.hypot(prof[i][0] - prof[i - 1][0], prof[i][1] - prof[i - 1][1]))
        faces, uvs, nrm = [], [], {}
        for k in range(len(prof) - 1):
            dr = prof[k + 1][0] - prof[k][0]
            dz = prof[k + 1][1] - prof[k][1]
            for i in range(segs):
                j = (i + 1) % segs
                q = [rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]]
                if (q[0] - q[3]).length < 1e-7 and (q[1] - q[2]).length < 1e-7:
                    continue
                if bark is not None:
                    u0, u1 = bark / 4 + i / segs * 0.25, bark / 4 + (i + 1) / segs * 0.25
                    vs = 2.0
                else:
                    u0, u1 = i / segs * tiles, (i + 1) / segs * tiles
                    vs = s
                faces.append(q)
                uvs.append([(u0, arc[k] / vs), (u1, arc[k] / vs), (u1, arc[k + 1] / vs), (u0, arc[k + 1] / vs)])
        M0 = xf(loc, rot)

        def nfn(p):
            rr = math.hypot(p.x, p.y)
            if rr < 1e-6:
                return (0, 0, 1)
            # slope from the profile segment closest in z
            best = min(range(len(prof) - 1), key=lambda k: abs((prof[k][1] + prof[k + 1][1]) / 2 - p.z))
            dr = prof[best + 1][0] - prof[best][0]
            dz = prof[best + 1][1] - prof[best][1]
            L = math.hypot(dr, dz) or 1
            return (p.x / rr * dz / L, p.y / rr * dz / L, -dr / L)
        self.add(faces, mat, tint, M0, uvs=uvs, nrm_fn=nfn if smooth else None, col_fn=col_fn)
        capf, capuv = [], []
        if caps[0] and prof[0][0] > 1e-6:
            capf.append(list(reversed(rings[0])))
        if caps[1] and prof[-1][0] > 1e-6:
            capf.append(rings[-1])
        for f in capf:
            r0 = max(1e-6, max(math.hypot(p.x, p.y) for p in f))
            if bark is not None:
                capuv.append([(0.875 + 0.115 * p.x / r0, 0.875 + 0.115 * p.y / r0) for p in f])
            else:
                capuv.append([(p.x / s + 0.3, p.y / s + 0.7) for p in f])
        if capf:
            self.add(capf, mat, tint, M0, uvs=capuv, col_fn=col_fn)

    def tube(self, pts, radii, mat, tint=(1, 1, 1), segs=8, cap_start=True, cap_end=True, col_fn=None,
             bark=None, vscale=2.0, tip=False, noise_amt=0.0):
        """Sweep along a polyline with parallel-transport frames (branches, logs, ropes).
        bark=column -> bark atlas mapping (U within column, V wraps along the length)."""
        pts = [Vector(p) for p in pts]
        n = len(pts)
        tans = []
        for i in range(n):
            d = (pts[min(n - 1, i + 1)] - pts[max(0, i - 1)])
            tans.append(d.normalized() if d.length > 1e-9 else Vector((0, 0, 1)))
        ref = Vector((1, 0, 0)) if abs(tans[0].x) < 0.9 else Vector((0, 1, 0))
        nrm0 = (ref - tans[0] * ref.dot(tans[0])).normalized()
        frames = [nrm0]
        for i in range(1, n):
            prev = frames[-1]
            nn = prev - tans[i] * prev.dot(tans[i])
            frames.append(nn.normalized() if nn.length > 1e-6 else prev)
        arc = [0.0]
        for i in range(1, n):
            arc.append(arc[-1] + (pts[i] - pts[i - 1]).length)
        s = MATS[mat].get("scale", 1.0)
        rmax = max(radii)
        tiles = max(1, round(math.tau * rmax / s))
        rings, rnorm = [], []
        off = self.rng.uniform(0, 100)
        for i in range(n):
            if tip and i == n - 1:
                rings.append(None)
                continue
            b1 = frames[i]
            b2 = tans[i].cross(b1)
            ring, rn = [], []
            for j in range(segs):
                a = j / segs * math.tau
                d = b1 * math.cos(a) + b2 * math.sin(a)
                rr = radii[i]
                if noise_amt:
                    rr *= 1 + noise_amt * noise.noise(pts[i] * 1.7 + d * 0.8 + Vector((off, 0, 0)))
                ring.append(pts[i] + d * rr)
                rn.append(d)
            rings.append(ring)
            rnorm.append(rn)
        M = self.M()
        R = M.to_3x3().inverted().transposed()

        def U(j):
            return (bark / 4 + j / segs * 0.25) if bark is not None else j / segs * tiles
        vs = vscale if bark is not None else s
        for i in range(n - 1):
            A, B_ = rings[i], rings[i + 1]
            for j in range(segs):
                j2 = (j + 1) % segs
                u0, u1 = U(j), U(j + 1)
                if B_ is None:
                    q = [A[j], A[j2], pts[-1]]
                    uv = [(u0, arc[i] / vs), (u1, arc[i] / vs), ((u0 + u1) / 2, arc[i + 1] / vs)]
                    nr = [rnorm[i][j], rnorm[i][j2], tans[-1]]
                else:
                    q = [A[j], A[j2], B_[j2], B_[j]]
                    uv = [(u0, arc[i] / vs), (u1, arc[i] / vs), (u1, arc[i + 1] / vs), (u0, arc[i + 1] / vs)]
                    nr = [rnorm[i][j], rnorm[i][j2], rnorm[i + 1][j2], rnorm[i + 1][j]]
                wp = [M @ p for p in q]
                wn = [(R @ v).normalized() for v in nr]
                if col_fn:
                    cols = [col_fn(p, wn[k], arc[min(i + (1 if k >= 2 else 0), n - 1)] / max(arc[-1], 1e-6))
                            for k, p in enumerate(wp)]
                else:
                    cols = [self.tint_col(tint, p) for p in wp]
                self.face(wp, uv, cols, wn, mat)
        caps = []
        if cap_start:
            caps.append((list(reversed(rings[0])), 0))
        if cap_end and rings[-1] is not None:
            caps.append((rings[-1], n - 1))
        for ring, i in caps:
            c = pts[i]
            b1 = frames[i]
            b2 = tans[i].cross(b1)
            r0 = max(radii[i], 1e-6)
            if bark is not None:
                uv = [(0.875 + 0.115 * (p - c).dot(b1) / r0, 0.875 + 0.115 * (p - c).dot(b2) / r0) for p in ring]
            else:
                uv = [((p - c).dot(b1) / s, (p - c).dot(b2) / s) for p in ring]
            wp = [M @ p for p in ring]
            fnn = newell(wp)
            fn_ = fnn.normalized() if fnn.length > 0 else Vector((0, 0, 1))
            cols = [col_fn(p, fn_, 0.0 if i == 0 else 1.0) for p in wp] if col_fn else \
                [self.tint_col(tint, p) for p in wp]
            self.face(wp, uv, cols, None, mat)

    def prism(self, pts2, depth, loc, mat, tint=(1, 1, 1), rot=(0, 0, 0), **kw):
        """Polygon in local XZ (x, z) extruded along Y (centred)."""
        h = depth / 2
        front = [Vector((x, -h, z)) for x, z in pts2]
        back = [Vector((x, h, z)) for x, z in reversed(pts2)]
        if newell(front).y > 0:
            front.reverse()
            back.reverse()
        faces = [front, back]
        n = len(pts2)
        fr = [Vector((x, -h, z)) for x, z in pts2]
        bk = [Vector((x, h, z)) for x, z in pts2]
        sgn = 1 if newell(fr).y < 0 else -1
        for i in range(n):
            j = (i + 1) % n
            # outline winding decides the side-face order (works for concave outlines too)
            q = [fr[j], fr[i], bk[i], bk[j]] if sgn > 0 else [fr[i], fr[j], bk[j], bk[i]]
            faces.append(q)
        self.add(faces, mat, tint, xf(loc, rot), **kw)

    def poly(self, pts, mat, tint=(1, 1, 1), uvs=None, both=False, **kw):
        pts = [Vector(p) for p in pts]
        self.add([pts], mat, tint, uvs=[uvs] if uvs else None, **kw)
        if both:
            self.add([list(reversed(pts))], mat, tint, uvs=[list(reversed(uvs))] if uvs else None, **kw)

    def sheet(self, corners, nu, nv, mat, col_fn=None, tint=(1, 1, 1), sag_fn=None, both=True, scale=None,
              smooth=True):
        """Bilinear patch p00,p10,p01,p11 (local) with nu x nv cells; sag_fn(u,v)->offset;
        col_fn(u, v) -> sRGB tint."""
        p00, p10, p01, p11 = (Vector(p) for p in corners)
        s = scale or MATS[mat].get("scale", 1.0)
        G = []
        for j in range(nv + 1):
            row = []
            for i in range(nu + 1):
                u, v = i / nu, j / nv
                p = (p00 * (1 - u) + p10 * u) * (1 - v) + (p01 * (1 - u) + p11 * u) * v
                if sag_fn:
                    p = p + Vector(sag_fn(u, v))
                row.append(p)
            G.append(row)
        lu = (p10 - p00).length
        lv = (p01 - p00).length
        M = self.M()
        R = M.to_3x3().inverted().transposed()

        def nrm(i, j):
            a = G[j][min(nu, i + 1)] - G[j][max(0, i - 1)]
            b = G[min(nv, j + 1)][i] - G[max(0, j - 1)][i]
            n = a.cross(b)
            return n.normalized() if n.length > 0 else Vector((0, 0, 1))
        for side in ((1, -1) if both else (1,)):
            for j in range(nv):
                for i in range(nu):
                    idx = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
                    if side < 0:
                        idx = list(reversed(idx))
                    # back side 4 mm behind so the two sides are never coplanar
                    pts = [M @ (G[b][a] - (nrm(a, b) * 0.004 if side < 0 else Vector())) for a, b in idx]
                    uv = [(a / nu * lu / s, b / nv * lv / s) for a, b in idx]
                    nr = [(R @ (nrm(a, b) * side)).normalized() for a, b in idx] if smooth else None
                    cols = [self.tint_col(col_fn(a / nu, b / nv) if col_fn else tint, p) for (a, b), p in zip(idx, pts)]
                    self.face(pts, uv, cols, nr, mat)

    def card(self, center, right, up, w, h, cell, mat="RG_Foliage", cols=None, nrms=None, base=False,
             segs=1, bend=0.0, grid=4):
        """Alpha card in world space (already transformed): `cell` = (row, col) of the 4x4 atlas.
        base=True: `center` is the bottom-middle. segs>1 splits along height with `bend` (m) sag."""
        c = Vector(center)
        r = Vector(right).normalized()
        u = Vector(up).normalized()
        row, col = cell
        ins = 1.5 / 1024
        u0, u1 = col / grid + ins, (col + 1) / grid - ins
        v0, v1 = 1 - (row + 1) / grid + ins, 1 - row / grid - ins
        bottom = c if base else c - u * (h / 2)
        fwd = r.cross(u)
        prev = None
        for k in range(segs + 1):
            t = k / segs
            p = bottom + u * (h * t) + fwd * (bend * t * t)
            left, right_ = p - r * (w / 2), p + r * (w / 2)
            vv = v0 + (v1 - v0) * t
            cur = (left, right_, vv, t)
            if prev:
                pl, pr, pv, pt = prev
                pts = [pl, pr, right_, left]
                uv = [(u0, pv), (u1, pv), (u1, vv), (u0, vv)]
                cc = [cols(p_, t_) for p_, t_ in zip(pts, (pt, pt, t, t))] if callable(cols) else \
                    [cols or (1, 1, 1, 1)] * 4
                nn = [nrms(p_) for p_ in pts] if callable(nrms) else None
                if nn is not None and newell(pts).dot(sum(nn, Vector())) < 0:
                    # winding must agree with the custom normal, or renderers flip it on the back face
                    pts, uv, cc, nn = pts[::-1], uv[::-1], cc[::-1], nn[::-1]
                self.face(pts, uv, cc, nn, mat)
            prev = cur

    # ---------------------------------------------------------------- stats / build
    def tris(self):
        return sum(len(f) - 2 for f in self.F)

    def bounds(self):
        return (tuple(min(v[i] for v in self.V) for i in range(3)), tuple(max(v[i] for v in self.V) for i in range(3)))

    def build(self, name=None):
        name = name or self.name
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.V, [], self.F)
        me.polygons.foreach_set("material_index", self.FM)
        me.polygons.foreach_set("use_smooth", [True] * len(self.F))
        uv = me.uv_layers.new(name="UVMap")
        uv.data.foreach_set("uv", [c for p in self.UV for c in p])
        ca = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        ca.data.foreach_set("color", [c for p in self.C for c in p])
        me.color_attributes.active_color = ca
        me.color_attributes.render_color_index = 0
        for mn in self.mnames:
            me.materials.append(get_mat(mn))
        me.validate(clean_customdata=False)
        if len(me.loops) == len(self.N):
            me.normals_split_custom_set(self.N)
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


# ================================================================================ export
def export_glb(ob, out_glb, vcol=True, extra=()):
    """glTF-separate export (textures by relative URI into ../textures/), packed into one .glb."""
    bpy.ops.object.select_all(action="DESELECT")
    ob.hide_set(False)
    ob.select_set(True)
    for e in extra:
        e.select_set(True)
    bpy.context.view_layer.objects.active = ob
    os.makedirs(os.path.dirname(out_glb), exist_ok=True)
    base = os.path.splitext(out_glb)[0]
    tmp = base + "__tmp.gltf"
    bpy.ops.export_scene.gltf(filepath=tmp, export_format="GLTF_SEPARATE", use_selection=True,
                              export_apply=True, export_keep_originals=True,
                              export_vertex_color="ACTIVE" if vcol else "NONE",
                              export_normals=True, export_texcoords=True, export_yup=True)
    with open(tmp) as f:
        gl = json.load(f)
    bin_path = os.path.join(os.path.dirname(tmp), gl["buffers"][0]["uri"])
    with open(bin_path, "rb") as f:
        binary = f.read()
    del gl["buffers"][0]["uri"]
    gl["buffers"][0]["byteLength"] = len(binary)
    for img in gl.get("images", []):
        img["uri"] = img["uri"].replace("\\", "/")
        img.pop("bufferView", None)
    for m in gl.get("materials", []):
        ext = m.get("extensions", {})
        ext.pop("KHR_materials_specular", None)
        if not ext:
            m.pop("extensions", None)
    used = gl.get("extensionsUsed", [])
    if "KHR_materials_specular" in used:
        used.remove("KHR_materials_specular")
        if not used:
            gl.pop("extensionsUsed", None)
    js = json.dumps(gl, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    binary += b"\0" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary)
    with open(out_glb, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(js), b"JSON"))
        f.write(js)
        f.write(struct.pack("<I4s", len(binary), b"BIN\0"))
        f.write(binary)
    os.remove(tmp)
    os.remove(bin_path)
    return gl


# ================================================================================ rendering
def world_sky(strength=1.35, sun_rot=(52, 6, -40), sun_energy=3.6, sun_col=(1.0, 0.88, 0.72)):
    sc = bpy.context.scene
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes["Background"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    rp = nt.nodes.new("ShaderNodeValToRGB")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], rp.inputs["Fac"])
    rp.color_ramp.elements[0].position = 0.0
    rp.color_ramp.elements[0].color = (*lin((0.93, 0.9, 0.82)), 1)
    rp.color_ramp.elements[1].position = 0.35
    rp.color_ramp.elements[1].color = (*lin((0.48, 0.68, 0.93)), 1)
    nt.links.new(rp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = strength
    sc.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = sun_energy
    sun.data.color = sun_col
    sun.data.angle = math.radians(3.0)
    sun.rotation_euler = tuple(math.radians(a) for a in sun_rot)
    sc.collection.objects.link(sun)
    return sun


def ground_mat(color=(0.36, 0.50, 0.22), color2=None, scale=0.35):
    m = bpy.data.materials.new("PreviewGround")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = scale
    nz.inputs["Detail"].default_value = 6.0
    rp = nt.nodes.new("ShaderNodeValToRGB")
    rp.color_ramp.elements[0].color = (*lin(tuple(c * 0.72 for c in color)), 1)
    rp.color_ramp.elements[1].color = (*lin(color2 or tuple(min(1, c * 1.2) for c in color)), 1)
    nt.links.new(nz.outputs["Fac"], rp.inputs["Fac"])
    nt.links.new(rp.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 1.0
    return m


def ground_plane(size, loc=(0, 0, 0), color=(0.36, 0.50, 0.22)):
    me = bpy.data.meshes.new("Ground")
    s = size / 2
    me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    ob = bpy.data.objects.new("Ground", me)
    ob.location = loc
    me.materials.append(ground_mat(color))
    bpy.context.scene.collection.objects.link(ob)
    return ob


def render_setup(png, res=(480, 360), samples=32, transparent=False, look="AgX - Base Contrast"):
    import addon_utils
    addon_utils.enable("cycles")
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    try:
        sc.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    sc.cycles.max_bounces = 4
    sc.cycles.transparent_max_bounces = 48
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = transparent
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = look
    except Exception:
        pass
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    sc.render.filepath = png


def camera(loc, target, lens=40, ortho=None):
    cd = bpy.data.cameras.new("Cam")
    cd.lens = lens
    if ortho:
        cd.type = "ORTHO"
        cd.ortho_scale = ortho
    cam = bpy.data.objects.new("Cam", cd)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = Vector(loc)
    d = Vector(target) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    cd.clip_end = 2000
    bpy.context.scene.camera = cam
    return cam


def render_thumb(obs, png, cam_dir=(1.0, -1.45, 0.62), fit=1.0, res=(480, 360), samples=32, lens=45,
                 ground=True, focus=None):
    pts = []
    for ob in obs:
        pts += [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), max(0.0, min(p.z for p in pts))))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    ctr = (lo + hi) / 2
    if focus is not None:
        ctr.z = focus
    rad = (hi - lo).length / 2
    if ground:
        ground_plane(max(rad * 30, 40))
    d = Vector(cam_dir).normalized()
    vfov = 2 * math.atan(36 * res[1] / res[0] / 2 / lens)
    dist = rad / math.sin(vfov / 2) * 0.78 * fit
    camera(ctr + d * dist, ctr, lens)
    world_sky()
    preview_patch()
    render_setup(png, res, samples)
    os.makedirs(os.path.dirname(png), exist_ok=True)
    bpy.ops.render.render(write_still=True)


# ================================================================================ contact sheet
FONT = {
    "A": "01110 10001 10001 11111 10001 10001 10001", "B": "11110 10001 10001 11110 10001 10001 11110",
    "C": "01111 10000 10000 10000 10000 10000 01111", "D": "11110 10001 10001 10001 10001 10001 11110",
    "E": "11111 10000 10000 11110 10000 10000 11111", "F": "11111 10000 10000 11110 10000 10000 10000",
    "G": "01111 10000 10000 10011 10001 10001 01111", "H": "10001 10001 10001 11111 10001 10001 10001",
    "I": "11111 00100 00100 00100 00100 00100 11111", "J": "00111 00010 00010 00010 00010 10010 01100",
    "K": "10001 10010 10100 11000 10100 10010 10001", "L": "10000 10000 10000 10000 10000 10000 11111",
    "M": "10001 11011 10101 10101 10001 10001 10001", "N": "10001 11001 10101 10011 10001 10001 10001",
    "O": "01110 10001 10001 10001 10001 10001 01110", "P": "11110 10001 10001 11110 10000 10000 10000",
    "Q": "01110 10001 10001 10001 10101 10010 01101", "R": "11110 10001 10001 11110 10100 10010 10001",
    "S": "01111 10000 10000 01110 00001 00001 11110", "T": "11111 00100 00100 00100 00100 00100 00100",
    "U": "10001 10001 10001 10001 10001 10001 01110", "V": "10001 10001 10001 10001 10001 01010 00100",
    "W": "10001 10001 10001 10101 10101 10101 01010", "X": "10001 10001 01010 00100 01010 10001 10001",
    "Y": "10001 10001 01010 00100 00100 00100 00100", "Z": "11111 00001 00010 00100 01000 10000 11111",
    "0": "01110 10001 10011 10101 11001 10001 01110", "1": "00100 01100 00100 00100 00100 00100 01110",
    "2": "01110 10001 00001 00010 00100 01000 11111", "3": "11110 00001 00001 01110 00001 00001 11110",
    "4": "00010 00110 01010 10010 11111 00010 00010", "5": "11111 10000 11110 00001 00001 10001 01110",
    "6": "00110 01000 10000 11110 10001 10001 01110", "7": "11111 00001 00010 00100 01000 01000 01000",
    "8": "01110 10001 10001 01110 10001 10001 01110", "9": "01110 10001 10001 01111 00001 00010 01100",
    "_": "00000 00000 00000 00000 00000 00000 11111", " ": "00000 00000 00000 00000 00000 00000 00000",
    "=": "00000 00000 11111 00000 11111 00000 00000", ".": "00000 00000 00000 00000 00000 01100 01100",
    "/": "00001 00010 00010 00100 01000 01000 10000", "(": "00010 00100 01000 01000 01000 00100 00010",
    ")": "01000 00100 00010 00010 00010 00100 01000", "-": "00000 00000 00000 11111 00000 00000 00000",
    ":": "00000 01100 01100 00000 01100 01100 00000", ",": "00000 00000 00000 00000 01100 00100 01000",
    "+": "00000 00100 00100 11111 00100 00100 00000", "|": "00100 00100 00100 00100 00100 00100 00100",
    "M2": "",
}


def draw_text(img, text, x, y, scale=2, color=(1, 1, 1)):
    cx = x
    H, W = img.shape[:2]
    for ch in text.upper():
        g = FONT.get(ch, FONT[" "])
        for r, row in enumerate(g.split()):
            for c, bit in enumerate(row):
                if bit == "1":
                    y0, x0 = y + r * scale, cx + c * scale
                    if 0 <= y0 < H - scale and 0 <= x0 < W - scale:
                        img[y0:y0 + scale, x0:x0 + scale, :3] = color
        cx += 6 * scale


def load_png(path):
    import numpy as np
    im = bpy.data.images.load(path)
    w, h = im.size
    a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1]
    bpy.data.images.remove(im)
    return a


def save_png(path, arr):
    import numpy as np
    h, w = arr.shape[:2]
    im = bpy.data.images.new(os.path.basename(path), w, h, alpha=False)
    im.pixels.foreach_set(np.ascontiguousarray(arr[::-1]).astype(np.float32).ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)


def sheet(entries, out, title, cols=5, tw=480, th=360):
    """entries: [(png, label line 1, label line 2)]"""
    import numpy as np
    lab = 44
    rows = (len(entries) + cols - 1) // cols
    head = 56
    W, H = cols * tw, head + rows * (th + lab)
    img = np.zeros((H, W, 4), np.float32)
    img[..., :3] = (0.12, 0.11, 0.1)
    img[..., 3] = 1
    draw_text(img, title, 14, 14, 4, (0.95, 0.84, 0.58))
    for i, (png, l1, l2) in enumerate(entries):
        r, c = divmod(i, cols)
        y0, x0 = head + r * (th + lab), c * tw
        if os.path.exists(png):
            a = load_png(png)
            h, w = a.shape[:2]
            img[y0 + lab:y0 + lab + min(th, h), x0:x0 + min(tw, w)] = a[:th, :tw]
        draw_text(img, l1, x0 + 8, y0 + 6, 3, (0.97, 0.95, 0.9))
        draw_text(img, l2, x0 + 8, y0 + 30, 2, (0.75, 0.85, 0.7))
    save_png(out, img)
    print("sheet", out)


def argv():
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
