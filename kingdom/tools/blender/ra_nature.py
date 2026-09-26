"""Shared helpers for the procedural nature set (trees, bushes, grass, flowers), bpy / Blender 5.x.

Used by make_nature.py (builds every GLB) and make_nature_forest_preview.py.
Unlike ra_kit (flat vertex-colour props) these assets are textured:

- Bark: tapered, noise-bent tubes with parallel-transport frames, UV-mapped so the bark texel
  aspect stays constant as branches thin (u around, v along). Root flare = lobed buttresses at
  the trunk base, which starts 0.25 m below ground.
- Foliage: alpha-cut leaf / needle CARDS (quads) whose bottom edge sits on a branch tip and
  whose texture is a whole leafy sprig from the atlas. Card vertex normals are replaced by
  "canopy normals" (pointing out from the canopy centre, blended a little toward +Z) so the
  crown shades like one soft volume instead of hundreds of flat planes. Blender custom split
  normals export as glTF NORMAL.
- COLOR_0 (vertex colour) on trees/bushes = albedo tint x fake ambient occlusion (inner and lower
  cards darker, bark darker/mossier at the base). Godot multiplies it into albedo automatically.
- COLOR_0 on grass / flowers = WIND DATA, not colour:
      R = bend weight, 0 at the ground -> 1 at the blade tips (linear in height)
      G = per-card random phase 0..1
      B = 0.5 (reserved), A = 1
  See nature/README.md and nature/foliage_wind.gdshader.
- Textures are not embedded: every GLB references ../nature/textures/*.png|jpg by relative URI,
  so all trees share one bark / one leaf texture in memory (Godot resolves the URI to the imported
  res:// texture).

Blender axes: metres, +Z up, origin at the base of the trunk / clump centre on the ground.
"""
import os, sys, math, json, struct, random
import bpy
from mathutils import Vector, Matrix, Quaternion, noise

UP = Vector((0, 0, 1))
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
NATURE = os.path.join(ROOT, "kingdom", "assets", "generated", "nature")
TEX = os.path.join(NATURE, "textures")
PREVIEWS = os.path.join(ROOT, "docs", "kingdom", "blender_previews", "nature")


def srgb(c):
    return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ============================================================================ mesh builder
class MeshBuilder:
    """Accumulates polygons with per-corner UV, colour (linear RGBA) and custom normal."""

    def __init__(self):
        self.verts = []
        self.faces = []
        self.mats = []
        self.uvs = []
        self.cols = []
        self.nrms = []
        self.mat_names = []

    def mat(self, name):
        if name not in self.mat_names:
            self.mat_names.append(name)
        return self.mat_names.index(name)

    def add_verts(self, vs):
        i0 = len(self.verts)
        self.verts.extend(vs)
        return i0

    def face(self, idx, mat, uvs, cols, nrms):
        self.faces.append(tuple(idx))
        self.mats.append(mat)
        self.uvs.extend(uvs)
        self.cols.extend(cols)
        self.nrms.extend(nrms)

    def tris(self):
        return sum(len(f) - 2 for f in self.faces)

    def tris_of(self, name):
        if name not in self.mat_names:
            return 0
        m = self.mat_names.index(name)
        return sum(len(f) - 2 for f, mm in zip(self.faces, self.mats) if mm == m)

    def build(self, name, materials):
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        me.polygons.foreach_set("material_index", self.mats)
        me.polygons.foreach_set("use_smooth", [True] * len(self.faces))
        uv = me.uv_layers.new(name="UVMap")
        uv.data.foreach_set("uv", [c for p in self.uvs for c in p])
        ca = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        ca.data.foreach_set("color", [c for p in self.cols for c in p])
        me.color_attributes.active_color = ca
        me.color_attributes.render_color_index = 0
        for mn in self.mat_names:
            me.materials.append(materials[mn])
        me.validate(clean_customdata=False)
        me.normals_split_custom_set([tuple(n) for n in self.nrms])
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


# ============================================================================ branches
class Branch:
    def __init__(self, pts, radii, level, cap=False):
        self.pts = pts          # list[Vector]
        self.radii = radii      # list[float]
        self.level = level
        self.cap = cap          # flat broken end instead of a point
        self.children = []
        # cumulative arc length
        self.arc = [0.0]
        for i in range(1, len(pts)):
            self.arc.append(self.arc[-1] + (pts[i] - pts[i - 1]).length)

    @property
    def length(self):
        return self.arc[-1]

    def at(self, t):
        """Point, tangent, radius at arc fraction t."""
        s = t * self.length
        for i in range(1, len(self.pts)):
            if self.arc[i] >= s or i == len(self.pts) - 1:
                seg = max(self.arc[i] - self.arc[i - 1], 1e-6)
                k = max(0.0, min(1.0, (s - self.arc[i - 1]) / seg))
                p = self.pts[i - 1].lerp(self.pts[i], k)
                d = (self.pts[i] - self.pts[i - 1]).normalized()
                r = lerp(self.radii[i - 1], self.radii[i], k)
                return p, d, r
        return self.pts[-1], (self.pts[-1] - self.pts[-2]).normalized(), self.radii[-1]


def grow(start, direction, length, r0, r1, level, rng, seg_len=0.6, wobble=0.25, tropism=0.0,
         freq=0.6, taper_pow=0.9, first=None, gravity_end=0.0, seed=0.0, cap=False):
    """Grow one noise-bent tapering branch. tropism > 0 bends up, < 0 droops.
    gravity_end adds extra droop toward the tip (weeping twigs)."""
    n = max(2, int(math.ceil(length / seg_len)))
    ts = [i / n for i in range(n + 1)]
    if first:                               # extra rings near the base (root flare)
        ts = sorted(set([0.0] + [f / length for f in first if f < length * 0.5] +
                        [t for t in ts if t > (max(first) / length) + 0.5 / n]))
    d = Vector(direction).normalized()
    p = Vector(start)
    pts, radii = [p.copy()], [r0]
    off = Vector((seed * 13.1, seed * 7.7, seed * 3.3))
    for i in range(1, len(ts)):
        t = ts[i]
        step = (ts[i] - ts[i - 1]) * length
        nz = noise.noise_vector(p * freq + off)
        d = d + nz * wobble * min(1.0, step / seg_len) + UP * tropism * step / max(length, 1e-3) * 2
        if gravity_end:
            d = d - UP * gravity_end * t * t * step
        d.normalize()
        p = p + d * step
        pts.append(p.copy())
        radii.append(r1 + (r0 - r1) * (1 - t) ** taper_pow)
    return Branch(pts, radii, level, cap)


def child_dir(tangent, angle, roll, up_bias=0.0, out=None, out_bias=0.0):
    t = tangent.normalized()
    perp = t.orthogonal().normalized()
    perp.rotate(Quaternion(t, roll))
    d = t * math.cos(angle) + perp * math.sin(angle)
    if out is not None and out_bias:
        o = Vector((out.x, out.y, 0))
        if o.length > 1e-4:
            d = d + o.normalized() * out_bias
    d = d + UP * up_bias
    return d.normalized()


GOLDEN = math.pi * (3 - math.sqrt(5))


def sides_for(r):
    if r > 0.22:
        return 10
    if r > 0.11:
        return 8
    if r > 0.05:
        return 6
    if r > 0.022:
        return 4
    return 3


def tube(mb, br, mat, tint, rng, tile_u=1.0, tile_v=1.3, flare=None, sides=None, col_fn=None,
         v_off=None):
    """Mesh a Branch as a tube. flare=(amount, height, n_roots) swells the base into buttresses.
    col_fn(point, t) -> linear rgb multiplier (for base darkening / moss)."""
    m = mb.mat(mat)
    ns = sides or sides_for(br.radii[0])
    circ = 2 * math.pi * br.radii[0]
    urep = max(1, round(circ / tile_u))
    vscale = urep / max(circ, 1e-4) * tile_u / tile_v      # keep texel aspect on thin twigs
    v0 = rng.random() if v_off is None else v_off
    # parallel transport frames
    frames = []
    t0 = (br.pts[1] - br.pts[0]).normalized()
    nrm = t0.orthogonal().normalized()
    phase = rng.random() * 6.283
    for i, p in enumerate(br.pts):
        if i == 0:
            tan = t0
        elif i == len(br.pts) - 1:
            tan = (br.pts[i] - br.pts[i - 1]).normalized()
        else:
            tan = (br.pts[i + 1] - br.pts[i - 1]).normalized()
        nrm = (nrm - tan * nrm.dot(tan)).normalized()
        frames.append((tan, nrm, tan.cross(nrm)))
    last = len(br.pts) - 1
    point_tip = not br.cap
    rings = []
    for i, p in enumerate(br.pts):
        if point_tip and i == last:
            break
        tan, a, b = frames[i]
        r = br.radii[i]
        z = br.arc[i]
        ring = []
        for j in range(ns + 1):
            th = j / ns * 2 * math.pi
            radial = a * math.cos(th) + b * math.sin(th)
            rr = r
            if flare:
                amt, h, nroots = flare
                lobes = 0.35 + 0.65 * abs(math.sin(th * nroots / 2 + phase)) ** 3
                rr = r * (1 + amt * math.exp(-max(z, 0) / h) * lobes)
            pos = p + radial * rr
            if flare and z < 0.9:           # buttress normals tilt up a bit
                nrmv = (radial + UP * 0.35 * math.exp(-z / 0.4)).normalized()
            else:
                nrmv = radial
            ring.append((pos, nrmv, (j / ns * urep, v0 + z * vscale)))
        rings.append(ring)
    def col_at(pos, t):
        c = tint if col_fn is None else tuple(x * y for x, y in zip(tint, col_fn(pos, t)))
        return (*c, 1.0)
    L = max(br.length, 1e-4)
    for i in range(len(rings) - 1):
        ra, rb = rings[i], rings[i + 1]
        ia = mb.add_verts([q[0] for q in ra])
        ib = mb.add_verts([q[0] for q in rb])
        ta, tb = br.arc[i] / L, br.arc[i + 1] / L
        for j in range(ns):
            idx = (ia + j, ia + j + 1, ib + j + 1, ib + j)
            qs = (ra[j], ra[j + 1], rb[j + 1], rb[j])
            tt = (ta, ta, tb, tb)
            mb.face(idx, m, [q[2] for q in qs], [col_at(q[0], t) for q, t in zip(qs, tt)],
                    [q[1] for q in qs])
    if point_tip:
        ra = rings[-1]
        tip = br.pts[-1]
        ia = mb.add_verts([q[0] for q in ra])
        it = mb.add_verts([tip] * ns)
        tan = frames[-1][0]
        vt = v0 + br.arc[-1] * vscale
        for j in range(ns):
            uvt = ((j + 0.5) / ns * urep, vt)
            mb.face((ia + j, ia + j + 1, it + j), m, [ra[j][2], ra[j + 1][2], uvt],
                    [col_at(ra[j][0], 0.99), col_at(ra[j + 1][0], 0.99), col_at(tip, 1.0)],
                    [ra[j][1], ra[j + 1][1], tan])
    else:                                    # broken stub: flat jagged cap
        ra = rings[-1]
        tan = frames[-1][0]
        c = br.pts[-1] + tan * br.radii[-1] * 0.4
        ic = mb.add_verts([c])
        ia = mb.add_verts([q[0] for q in ra])
        for j in range(ns):
            q0, q1 = ra[j], ra[j + 1]
            mb.face((ia + j, ia + j + 1, ic), m, [q0[2], q1[2], (0.5, q0[2][1] + 0.1)],
                    [col_at(q0[0], 1)] * 3, [tan, tan, tan])
    return mb


# ============================================================================ leaf cards
ATLAS2 = {0: (0.0, 0.0), 1: (0.5, 0.0), 2: (0.0, 0.5), 3: (0.5, 0.5)}   # 2x2 atlas cell origins


def card(mb, mat, base, up, facing, w, h, cell, col, flip=False, sink=0.08, cell_size=(0.5, 0.5),
         segs=1, bend=0.0, custom_nrm=None, vcol_fn=None):
    """Quad (or vertical strip of `segs` quads) with its bottom-centre at base, extending along
    `up`, facing `facing`. cell = (u0, v0) atlas origin. bend curls the top backwards along
    -facing (droop). custom_nrm(pos) -> normal. vcol_fn(pos, t) -> rgba overrides col."""
    m = mb.mat(mat)
    up = up.normalized()
    side = up.cross(facing).normalized()
    fwd = side.cross(up).normalized()
    base = base - up * h * sink
    u0, v0 = cell
    cw, ch = cell_size
    rows = []
    for k in range(segs + 1):
        t = k / segs
        c = base + up * (h * t) - fwd * (bend * h * t * t)
        rows.append((c - side * w / 2, c + side * w / 2, t))
    ul, ur = (u0 + cw, u0) if flip else (u0, u0 + cw)
    for k in range(segs):
        (a0, b0, t0), (a1, b1, t1) = rows[k], rows[k + 1]
        i = mb.add_verts([a0, b0, b1, a1])
        pos = [a0, b0, b1, a1]
        ts = [t0, t0, t1, t1]
        uvs = [(ul, v0 + ch * t0), (ur, v0 + ch * t0), (ur, v0 + ch * t1), (ul, v0 + ch * t1)]
        nrms = [custom_nrm(p) if custom_nrm else fwd for p in pos]
        cols = [vcol_fn(p, t) if vcol_fn else col for p, t in zip(pos, ts)]
        mb.face((i, i + 1, i + 2, i + 3), m, uvs, cols, nrms)


class Canopy:
    """Ellipsoidal canopy frame used for outward normals and fake AO on the leaf cards."""

    def __init__(self, points, up_blend=0.25, shrink=1.0, axis_mode=False, ao=(0.5, 1.0)):
        n = len(points)
        c = sum(points, Vector()) / max(n, 1)
        self.c = c
        ext = Vector((max(abs(p.x - c.x) for p in points), max(abs(p.y - c.y) for p in points),
                      max(abs(p.z - c.z) for p in points)))
        self.R = Vector((max(ext.x, 0.3), max(ext.y, 0.3), max(ext.z, 0.3))) * shrink
        self.zmin = min(p.z for p in points)
        self.zmax = max(p.z for p in points)
        self.up_blend = up_blend
        self.axis_mode = axis_mode
        self.ao = ao

    def local(self, p):
        d = p - self.c
        return Vector((d.x / self.R.x, d.y / self.R.y, d.z / self.R.z))

    def normal(self, p):
        if self.axis_mode:                    # cone / column: out from the trunk axis
            d = Vector((p.x - self.c.x, p.y - self.c.y, 0))
            if d.length < 1e-3:
                d = Vector((0.0, 0.0, 1.0))
            n = d.normalized() + UP * 0.45
        else:
            n = self.local(p)
            if n.length < 1e-3:
                n = UP.copy()
            n = n.normalized()
        return (n.normalized() * (1 - self.up_blend) + UP * self.up_blend).normalized()

    def shade(self, p):
        """0..1 depth shade: 1 on the sunny outer shell, lower inside / underneath."""
        if self.axis_mode:
            q = Vector((p.x - self.c.x, p.y - self.c.y, 0)).length
            h = (p.z - self.zmin) / max(self.zmax - self.zmin, 1e-3)
            rmax = max(self.R.x, self.R.y) * max(0.08, 1.0 - h) * 1.1
            depth = min(1.0, q / max(rmax, 0.2))
        else:
            depth = min(1.0, self.local(p).length)
        lo, hi = self.ao
        under = smoothstep(-0.9, 0.5, (p.z - self.c.z) / self.R.z)
        return lerp(lo, hi, 0.65 * smoothstep(0.15, 1.0, depth) + 0.35 * under)


def place_cards(mb, mat, anchors, canopy, rng, count, size, cells, tint, var=0.1, facing_mode="random",
                aspect=1.0, out_push=0.25, up_follow=0.55):
    """anchors: list of (point, tangent). Places `count` cards chosen from anchors
    (outer anchors preferred). size=(min, max) card height in metres."""
    if not anchors:
        return 0
    scored = []
    for p, d in anchors:
        depth = canopy.local(p).length if not canopy.axis_mode else 1.0
        scored.append((rng.random() * 0.6 + min(depth, 1.2), p, d))
    scored.sort(key=lambda s: -s[0])
    chosen = [s for s in scored[:count]]
    while len(chosen) < count:          # reuse anchors if we have too few
        chosen.append(scored[rng.randrange(len(scored))])
    for _, p, d in chosen:
        out = canopy.normal(p)
        up = (d * up_follow + out * out_push + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1),
                                                         rng.uniform(-0.6, 1))) * 0.45)
        if up.length < 1e-3:
            up = UP.copy()
        up.normalize()
        if facing_mode == "flat":       # spray lies roughly horizontal, facing the sky
            f = UP + Vector((rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), 0))
        elif facing_mode == "out":
            f = out + Vector((rng.uniform(-0.7, 0.7), rng.uniform(-0.7, 0.7), rng.uniform(-0.5, 0.5)))
        else:
            f = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
        f = f - up * f.dot(up)
        if f.length < 1e-3:
            f = up.orthogonal()
        f.normalize()
        # front face (the one engines don't normal-flip) must look outward: otherwise half the
        # visible cards would shade with an inward (flipped) canopy normal and read as dark holes
        if f.dot(out) < 0:
            f = -f
        h = rng.uniform(*size)
        cell = ATLAS2[rng.choice(cells)]
        k = 1 + rng.uniform(-var, var)
        hue = rng.uniform(-var, var)
        base_tint = (tint[0] * k * (1 + hue), tint[1] * k, tint[2] * k * (1 - hue * 0.5))

        def vc(pos, t, base_tint=base_tint):
            s = canopy.shade(pos)
            return (base_tint[0] * s, base_tint[1] * s, base_tint[2] * s, 1.0)
        card(mb, mat, p, up, f, h * aspect, h, cell, None, flip=rng.random() < 0.5,
             custom_nrm=canopy.normal, vcol_fn=vc)
    return count


def anchors_from(branches, t0=0.3, spacing=0.35, levels=None, tip=True):
    out = []
    for br in branches:
        if levels is not None and br.level not in levels:
            continue
        L = br.length
        n = max(1, int(L * (1 - t0) / spacing))
        for i in range(n):
            t = t0 + (1 - t0) * (i + 0.5) / n
            p, d, r = br.at(t)
            out.append((p, d))
        if tip:
            p, d, r = br.at(1.0)
            out.append((p, d))
    return out


# ============================================================================ materials
def _img(path, noncolor=False):
    name = os.path.basename(path)
    img = bpy.data.images.get(name) or bpy.data.images.load(path)
    if noncolor:
        img.colorspace_settings.name = "Non-Color"
    return img


def _mix_multiply(nt, a, b):
    mx = nt.nodes.new("ShaderNodeMix")
    mx.data_type = "RGBA"
    mx.blend_type = "MULTIPLY"
    mx.inputs[0].default_value = 1.0
    ia = next(s for s in mx.inputs if s.identifier == "A_Color")
    ib = next(s for s in mx.inputs if s.identifier == "B_Color")
    nt.links.new(a, ia)
    nt.links.new(b, ib)
    return next(s for s in mx.outputs if s.identifier == "Result_Color")


def mat_bark(name, color_tex, normal_tex=None, rough=0.92, normal_strength=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = _img(os.path.join(TEX, color_tex))
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    nt.links.new(_mix_multiply(nt, tex.outputs["Color"], vc.outputs["Color"]), bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    if normal_tex:
        nt_ = nt.nodes.new("ShaderNodeTexImage")
        nt_.image = _img(os.path.join(TEX, normal_tex), noncolor=True)
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = normal_strength
        nt.links.new(nt_.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    m.use_backface_culling = True
    return m


def mat_foliage(name, tex_name, rough=0.8, cutoff=0.4, vcol=True, translucent=0.0):
    """Alpha-MASK, double-sided foliage. Alpha wired as 1 - (alpha < cutoff), the pattern
    the glTF exporter turns into alphaMode MASK + alphaCutoff."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = _img(os.path.join(TEX, tex_name))
    tex.interpolation = "Linear"
    if vcol:
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Col"
        nt.links.new(_mix_multiply(nt, tex.outputs["Color"], vc.outputs["Color"]), bsdf.inputs["Base Color"])
    else:
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    lt = nt.nodes.new("ShaderNodeMath")
    lt.operation = "LESS_THAN"
    lt.inputs[1].default_value = cutoff
    nt.links.new(tex.outputs["Alpha"], lt.inputs[0])
    sub = nt.nodes.new("ShaderNodeMath")
    sub.operation = "SUBTRACT"
    sub.inputs[0].default_value = 1.0
    nt.links.new(lt.outputs[0], sub.inputs[1])
    nt.links.new(sub.outputs[0], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = rough
    try:
        bsdf.inputs["Specular IOR Level"].default_value = 0.3
    except KeyError:
        pass
    if translucent:   # preview only (glTF ignores it): light through leaves
        bsdf.inputs["Subsurface Weight"].default_value = 0.0
        try:
            bsdf.inputs["Transmission Weight"].default_value = 0.0
        except KeyError:
            pass
    m.use_backface_culling = False
    try:
        m.surface_render_method = "DITHERED"
    except Exception:
        pass
    return m


def standard_materials():
    return {
        "Bark_Oak": mat_bark("Bark_Oak", "bark_oak_color.jpg", "bark_oak_normal.jpg"),
        "Bark_Pine": mat_bark("Bark_Pine", "bark_pine_color.jpg", "bark_pine_normal.jpg"),
        "Bark_Birch": mat_bark("Bark_Birch", "bark_birch_color.png", "bark_birch_normal.png", rough=0.8,
                               normal_strength=0.6),
        "Leaves_Broadleaf": mat_foliage("Leaves_Broadleaf", "leaves_broadleaf.png"),
        "Needles_Conifer": mat_foliage("Needles_Conifer", "needles_conifer.png", rough=0.75),
        "Meadow": mat_foliage("Meadow", "meadow_atlas.png", rough=0.85, vcol=False, cutoff=0.4),
    }


# ============================================================================ export
def export_glb(ob, out_glb, wind_vcol=False):
    """Export as glTF-separate (textures stay in textures/ by relative URI) then pack .gltf+.bin
    into a single .glb that still references the shared external textures."""
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    base = os.path.splitext(out_glb)[0]
    tmp = base + "__tmp.gltf"
    bpy.ops.export_scene.gltf(filepath=tmp, export_format="GLTF_SEPARATE", use_selection=True,
                              export_apply=True, export_keep_originals=True,
                              export_vertex_color="ACTIVE" if wind_vcol else "MATERIAL",
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


# ============================================================================ preview
def setup_world(sun_rot=(48, 8, -35), sun_energy=3.2):
    sc = bpy.context.scene
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes["Background"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    cr = ramp.color_ramp
    cr.elements[0].position = 0.0
    cr.elements[0].color = (*srgb((0.80, 0.86, 0.90)), 1)
    cr.elements[1].position = 0.3
    cr.elements[1].color = (*srgb((0.40, 0.62, 0.92)), 1)
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 1.5
    sc.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = sun_energy
    sun.data.color = (1.0, 0.95, 0.86)
    sun.data.angle = math.radians(2.0)
    sun.rotation_euler = tuple(math.radians(a) for a in sun_rot)
    sc.collection.objects.link(sun)


def ground_plane(size, color=(0.30, 0.40, 0.18), loc=(0, 0, 0)):
    bpy.ops.mesh.primitive_plane_add(size=size, location=loc)
    p = bpy.context.active_object
    m = bpy.data.materials.new("PreviewGround")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 0.6
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*srgb(tuple(c * 0.75 for c in color)), 1)
    ramp.color_ramp.elements[1].color = (*srgb(tuple(min(1, c * 1.15) for c in color)), 1)
    nt.links.new(nz.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Roughness"].default_value = 1.0
    p.data.materials.append(m)
    return p


def render_setup(png, samples=48, res=(800, 600)):
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
    sc.cycles.transparent_max_bounces = 64
    if os.environ.get("RA_QUICK"):     # fast iteration renders
        res, sc.cycles.samples = (res[0] // 2, res[1] // 2), 16
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.film_transparent = False
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "None"
    except Exception:
        pass
    sc.render.filepath = png


def look_at(cam, target):
    d = (Vector(target) - cam.location)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def preview_translucency(amount=0.3):
    """PREVIEW ONLY (called after export): thin-leaf light transmission. Path-traced canopies are
    darker inside than Godot's (unoccluded) ambient; this compensates. In Godot the equivalent is
    StandardMaterial3D.backlight (see nature/README.md)."""
    for m in bpy.data.materials:
        if not m.use_nodes or m.use_backface_culling or m.name == "PreviewGround":
            continue
        nt = m.node_tree
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        bsdf = nt.nodes["Principled BSDF"]
        tr = nt.nodes.new("ShaderNodeBsdfTranslucent")
        base_link = bsdf.inputs["Base Color"].links[0].from_socket
        nt.links.new(base_link, tr.inputs["Color"])
        mix = nt.nodes.new("ShaderNodeMixShader")
        mix.inputs[0].default_value = amount
        nt.links.new(bsdf.outputs[0], mix.inputs[1])
        nt.links.new(tr.outputs[0], mix.inputs[2])
        # keep the alpha cut: transparent where the principled would be
        tp = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix2 = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(bsdf.inputs["Alpha"].links[0].from_socket, mix2.inputs[0])
        nt.links.new(tp.outputs[0], mix2.inputs[1])
        nt.links.new(mix.outputs[0], mix2.inputs[2])
        nt.links.new(mix2.outputs[0], out.inputs["Surface"])


def render_asset(ob, png, cam_dir=(1.0, -1.7, 0.28), fit=1.0, lens=40, samples=48):
    sc = bpy.context.scene
    bb = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    lo = Vector((min(v.x for v in bb), min(v.y for v in bb), max(0.0, min(v.z for v in bb))))
    hi = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
    ctr = (lo + hi) / 2
    size = max(hi.z - lo.z, (hi.x - lo.x) * 0.75, (hi.y - lo.y) * 0.75)
    ground_plane(max(size * 20, 30))
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = lens
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    sc.collection.objects.link(cam)
    d = Vector(cam_dir).normalized()
    vfov = 2 * math.atan(24 / 2 / lens)
    dist = size * 0.62 / math.tan(vfov / 2) * fit
    cam.location = ctr + d * dist
    look_at(cam, ctr)
    cam_data.clip_end = dist * 50
    sc.camera = cam
    setup_world()
    preview_translucency()
    render_setup(png, samples)
    bpy.ops.render.render(write_still=True)
    print("preview", png)
