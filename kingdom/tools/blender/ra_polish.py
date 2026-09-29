"""Art-direction pass shared by every ra_kit generator (bpy, Blender 5.x).

Called from Kit (ra_kit.py). The aim is a more crafted look for the same or fewer
triangles, at no extra runtime cost:

- Materials: each material key maps to one of seven shared, tileable DETAIL texture
  sets in kingdom/assets/generated/village_tex/ (see make_village_textures.py):
  plaster, wood, stone, roof, thatch, cloth, iron. Every set has albedo-detail,
  normal and metallicRoughness maps. Base colour = detail albedo x COLOR_0, so
  the vertex colour stays a cheap palette tint. The GLBs reference the maps by
  relative URI (never embedded), so all buildings share one copy in memory, and
  the material names are the same in every GLB (RA_Wood, RA_Plaster...).
- UVs: box projection in the primitive's own local metres (grain follows the long
  axis of timbers), with the same texel density for every module.
- Weathering is baked into COLOR_0: ray-traced ambient occlusion with a ground
  plane (contact shadow), a damp tide line at wall bases, grime under window
  sills, sun-bleached upper roofs, moss on north-facing (+Y, Godot -Z) and
  upward-facing low stone, and low-frequency dirt so no surface is uniform.
- Shape: a smooth, very small displacement field (zero at the ground) sags long
  ridges and bows wall lines, so no edge is ruler-straight. Faces nobody can
  see (bottoms on the ground, faces sealed inside the building) are deleted.
- LOD: faces carry a tag (bit 0 = LOD0 only detail, bit 1 = LOD1 only stand-in);
  finish() writes <name>.glb and <name>_lod1.glb from the same build, and a
  remeshed <name>_lod2.glb proxy for landmarks.
"""
import os, math, json, struct, random
import bpy, bmesh
from mathutils import Vector, Matrix, noise
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
TEX_DIR = os.path.join(ROOT, "kingdom", "assets", "generated", "village_tex")
MEAN = 0.86          # mean of every detail albedo (make_village_textures.MEAN)

# material key -> detail texture family (None = plain vertex colour)
TYPE_OF = {
    "Plaster": "plaster", "Wood": "wood", "Plank": "wood", "Board": "wood", "Deck": "wood", "Hull": "wood",
    "Matte": "stone", "Stone": "stone", "Paving": "cobble", "Roof": "roof", "Shingle": "roof", "Thatch": "thatch",
    "Cloth": "cloth", "Rope": "cloth", "Hide": "cloth", "Canvas": "cloth", "Metal": "iron",
}
# texture repeat, metres per tile
TILE = {"plaster": 2.4, "wood": 1.2, "stone": 1.1, "roof": 1.0, "thatch": 0.9, "cloth": 0.7, "iron": 0.6}
# Hand-painted art textures (kingdom/assets/art/textures/, sRGB albedo only, shared by relative URI).
# These families REPLACE the generated detail sets of the same name (stone, wood) or add to them
# (slate = the blue slate roofs, cobble = paving); terracotta / shingle / thatch roofs keep the old sets.
#   tile  metres of asset space per texture repeat
#   mean  mean albedo (sRGB) of the PNG, so COLOR_0 tint = palette colour relative to the texture
#   k     how much of the palette tint is kept (1 = the old palette colours, 0 = pure painted texture)
#   rough constant roughness (no metallicRoughness / normal map for these)
ART_TEX_DIR = os.path.join(ROOT, "kingdom", "assets", "art", "textures")
ART_FAMS = {
    "stone": dict(file="stone_wall_blocks.png", tile=5.0, mean=(0.806, 0.709, 0.584), k=0.5, gain=1.15),
    "slate": dict(file="roof_slate_blue.png", tile=2.6, mean=(0.333, 0.462, 0.699), k=0.5),
    "wood": dict(file="wood_planks.png", tile=1.6, mean=(0.629, 0.450, 0.243), k=0.7),
    "cobble": dict(file="cobblestone.png", tile=2.4, mean=(0.590, 0.505, 0.398), k=0.5),
}
# plank interiors in the wood texture (U 0..1), clear of the dark joints, for narrow beams / boards
WOOD_PLANKS = [(0.006, 0.145), (0.157, 0.293), (0.305, 0.432), (0.445, 0.574), (0.586, 0.720), (0.733, 0.858),
               (0.871, 0.992)]
for _f, _d in ART_FAMS.items():
    TILE[_f] = _d["tile"]
ROOFY = ("roof", "thatch", "slate")   # families that get sun-bleach / moss
EMISSIVE = {"Glass", "WindowLit", "Lamp", "Coals", "Water", "Crystal", "Ember", "Flame", "FlameCore", "CandleFlame", "Rune"}
MOSS = (0.36, 0.42, 0.22)


def to_srgb(c):
    return tuple(x * 12.92 if x <= 0.0031308 else 1.055 * (max(x, 0.0) ** (1 / 2.4)) - 0.055 for x in c)


def to_lin(c):
    return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def smoothstep(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# ================================================================== materials
def _img(path, noncolor=False):
    name = os.path.basename(path)
    img = bpy.data.images.get(name)
    if img is None:
        img = bpy.data.images.load(path)
    if noncolor:
        img.colorspace_settings.name = "Non-Color"
    return img


def textured_nodes(m, fam):
    """Wire detail albedo x vertex colour, normal map and metallicRoughness (the node
    patterns the glTF exporter turns into baseColorTexture/normalTexture/
    metallicRoughnessTexture plus COLOR_0)."""
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    art = ART_FAMS.get(fam)
    vc = next((n for n in nt.nodes if n.type == "VERTEX_COLOR"), None)
    if vc is None:
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Col"
    alb = nt.nodes.new("ShaderNodeTexImage")
    alb.image = _img(os.path.join(ART_TEX_DIR, art["file"]) if art else os.path.join(TEX_DIR, f"ra_{fam}_alb.png"))
    mx = nt.nodes.new("ShaderNodeMix")
    mx.data_type = "RGBA"
    mx.blend_type = "MULTIPLY"
    mx.inputs[0].default_value = 1.0
    nt.links.new(alb.outputs["Color"], next(s for s in mx.inputs if s.identifier == "A_Color"))
    nt.links.new(vc.outputs["Color"], next(s for s in mx.inputs if s.identifier == "B_Color"))
    nt.links.new(next(s for s in mx.outputs if s.identifier == "Result_Color"), bsdf.inputs["Base Color"])
    if art:
        return          # painted albedo x vertex colour only; roughness stays the material's constant
    mr = nt.nodes.new("ShaderNodeTexImage")
    mr.image = _img(os.path.join(TEX_DIR, f"ra_{fam}_mr.png"), noncolor=True)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(mr.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    if fam == "iron":
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    nm_img = nt.nodes.new("ShaderNodeTexImage")
    nm_img.image = _img(os.path.join(TEX_DIR, f"ra_{fam}_nrm.png"), noncolor=True)
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nm.inputs["Strength"].default_value = 1.0
    nt.links.new(nm_img.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])


# ================================================================== UVs
def project_uvs_art(t, fam, rng, grain, xform):
    """UVs for the hand-painted art families. Stone / cobble / slate use ASSET-space
    metres (`xform` = primitive -> asset), so neighbouring blocks, slabs and roof
    pieces sample one continuous texture (mortar courses run level, slate rows run
    along the eave and up the slope). Wood planks run the grain along texture V; narrow
    beams and boards are mapped into the interior of one random plank so no dark joint
    splits a 15 cm timber."""
    tile = TILE[fam]
    t.normal_update()
    if not t.verts:
        return {}
    M3 = xform.to_3x3()
    out = {}
    if fam == "wood":
        lo = [min(v.co[i] for v in t.verts) for i in range(3)]
        hi = [max(v.co[i] for v in t.verts) for i in range(3)]
        ext = [hi[i] - lo[i] for i in range(3)]
        la = None
        if grain:
            la = "xyz".index(grain)
        else:
            order = sorted(range(3), key=lambda i: -ext[i])
            if ext[order[0]] > 1.6 * max(ext[order[1]], 1e-4):
                la = order[0]
        offu, offv = rng.random(), rng.random()
        pl = WOOD_PLANKS[int(rng.random() * len(WOOD_PLANKS)) % len(WOOD_PLANKS)]
        for f in t.faces:
            n = f.normal
            an = (abs(n.x), abs(n.y), abs(n.z))
            d = an.index(max(an))
            a, b = ((0, 1), (1, 2), (0, 2))[(2, 0, 1).index(d)]
            if la is not None and la in (a, b):
                ua, va = la, (b if la == a else a)
            elif d != 2:
                ua, va = 2, a
            else:
                ua, va = a, b
            narrow = ext[va] <= (pl[1] - pl[0]) * tile * 1.02
            uvs = []
            for l in f.loops:
                if narrow:
                    u = pl[0] + (l.vert.co[va] - lo[va]) / tile
                else:
                    u = l.vert.co[va] / tile + offu
                uvs.append((u, l.vert.co[ua] / tile + offv))
            out[f.index] = uvs
        return out
    for f in t.faces:
        nw = (M3 @ f.normal)
        if nw.length < 1e-9:
            nw = f.normal
        nw = nw.normalized()
        uvs = []
        if fam == "slate":
            if abs(nw.z) > 0.985:
                ud, vd = Vector((1, 0, 0)), Vector((0, 1, 0))
            else:
                ud = Vector((0, 0, 1)).cross(nw).normalized()
                vd = nw.cross(ud)
            for l in f.loops:
                pw = xform @ l.vert.co
                uvs.append((pw.dot(ud) / tile, pw.dot(vd) / tile))
        else:
            up = abs(nw.z) > 0.7
            for l in f.loops:
                pw = xform @ l.vert.co
                if up:
                    uvs.append((pw.x / tile, pw.y / tile))
                elif abs(nw.x) > abs(nw.y):
                    uvs.append((pw.y / tile, pw.z / tile))
                else:
                    uvs.append((pw.x / tile, pw.z / tile))
        out[f.index] = uvs
    return out


def project_uvs(t, fam, rng, grain=None, xform=None):
    """Per-loop UVs for temp bmesh `t` in its own local metres: box projection by
    face normal. Wood grain (texture U) follows the primitive's long axis, or the
    vertical for upright pieces; `grain` ('x'|'y'|'z') forces it."""
    if fam in ART_FAMS and xform is not None:
        return project_uvs_art(t, fam, rng, grain, xform)
    tile = TILE[fam]
    t.normal_update()
    if not t.verts:
        return {}
    lo = [min(v.co[i] for v in t.verts) for i in range(3)]
    hi = [max(v.co[i] for v in t.verts) for i in range(3)]
    ext = [hi[i] - lo[i] for i in range(3)]
    la = None
    if fam == "wood":
        if grain:
            la = "xyz".index(grain)
        else:
            order = sorted(range(3), key=lambda i: -ext[i])
            if ext[order[0]] > 1.6 * max(ext[order[1]], 1e-4):
                la = order[0]
    off = (rng.random(), rng.random())
    out = {}
    for f in t.faces:
        n = f.normal
        an = (abs(n.x), abs(n.y), abs(n.z))
        d = an.index(max(an))
        if d == 2:
            a, b = 0, 1
        elif d == 0:
            a, b = 1, 2
        else:
            a, b = 0, 2
        if fam == "wood":
            if la is not None and la in (a, b):
                ua, va = la, (b if la == a else a)
            elif d != 2:
                ua, va = 2, a          # upright faces: grain runs up
            else:
                ua, va = a, b
        else:
            ua, va = a, b
        out[f.index] = [(l.vert.co[ua] / tile + off[0], l.vert.co[va] / tile + off[1]) for l in f.loops]
    return out


# ================================================================== geometry passes
def subdivide_long(t, max_len=2.6):
    """Cut a primitive along its long axis so a later displacement can bend it."""
    if not t.verts:
        return
    lo = [min(v.co[i] for v in t.verts) for i in range(3)]
    hi = [max(v.co[i] for v in t.verts) for i in range(3)]
    ext = [hi[i] - lo[i] for i in range(3)]
    ax = ext.index(max(ext))
    L = ext[ax]
    if L <= max_len * 1.2:
        return
    n = math.ceil(L / max_len)
    no = Vector((0, 0, 0))
    no[ax] = 1.0
    for i in range(1, n):
        co = Vector((0, 0, 0))
        co[ax] = lo[ax] + L * i / n
        geom = t.verts[:] + t.edges[:] + t.faces[:]
        bmesh.ops.bisect_plane(t, geom=geom, plane_co=co, plane_no=no)


def deform(bm, amp, sag, seed=0.0):
    """Smooth, tiny displacement: walls bow and lean a little, long ridges sag.
    Zero at the ground so footprints and contact stay put."""
    if not bm.verts or amp <= 0:
        return
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    x0, x1, y0, y1, z1 = min(xs), max(xs), min(ys), max(ys), max(zs)
    long_x = (x1 - x0) >= (y1 - y0)
    c, h = ((x0 + x1) / 2, (x1 - x0) / 2) if long_x else ((y0 + y1) / 2, (y1 - y0) / 2)
    off = Vector((seed * 13.1, seed * 7.7, seed * 3.3))
    for v in bm.verts:
        p = v.co
        if p.z <= 0.02:
            continue
        a = amp * min(1.0, p.z / 2.5)
        q = p * 0.21 + off
        d = Vector((noise.noise(q), noise.noise(q + Vector((17.3, 0, 0))), noise.noise(q + Vector((0, 31.7, 0)))))
        u = ((p.x if long_x else p.y) - c) / max(h, 0.5)
        hz = min(1.0, p.z / max(z1, 0.5))
        # sag is linear in height so a flat slope stays flat across its pitch (roof decks
        # and the shingles on them bend together); along the ridge it is a smooth bow
        dz = -sag * hz * max(0.0, 1.0 - u * u)
        v.co = Vector((p.x + d.x * a, p.y + d.y * a, p.z + d.z * a * 0.15 + dz))


def ground_cut(bm, zc, span=0.5):
    """Cut tall faces that start at the ground at height zc, so the baked contact
    shadow / damp band has a vertex row to fade out on instead of smearing up
    the whole face (a 2 m post with vertices only at 0 and 2 m)."""
    faces = []
    for f in bm.faces:
        zs = [v.co.z for v in f.verts]
        if min(zs) < zc * 0.5 and max(zs) > zc + span and abs(f.normal.z) < 0.7:
            faces.append(f)
    if not faces:
        return 0
    verts = list({v for f in faces for v in f.verts})
    edges = list({e for f in faces for e in f.edges})
    bmesh.ops.bisect_plane(bm, geom=verts + edges + faces, plane_co=(0, 0, zc), plane_no=(0, 0, 1))
    return len(faces)


def _hemi_dirs(n=32, min_cos=0.06, cosine=False, seed=0):
    """Fibonacci directions on the +Z hemisphere."""
    out = []
    ga = math.pi * (3 - math.sqrt(5))
    for i in range(n):
        t = (i + 0.5) / n
        if cosine:
            r = math.sqrt(t)
            z = math.sqrt(max(0.0, 1 - t))
        else:
            z = 1 - t * (1 - min_cos)
            r = math.sqrt(max(0.0, 1 - z * z))
        a = i * ga + seed
        out.append(Vector((math.cos(a) * r, math.sin(a) * r, max(z, min_cos))).normalized())
    return out


def _basis(n):
    ref = Vector((0, 0, 1)) if abs(n.z) < 0.9 else Vector((1, 0, 0))
    t = n.cross(ref).normalized()
    b = n.cross(t)
    return Matrix((t, b, n)).transposed()


def _bvh(bm, ground=True, gs=500.0):
    verts = [v.co.copy() for v in bm.verts]
    polys = [[v.index for v in f.verts] for f in bm.faces]
    gi = -1
    if ground:
        b = len(verts)
        verts += [Vector((-gs, -gs, 0.0)), Vector((gs, -gs, 0.0)), Vector((gs, gs, 0.0)), Vector((-gs, gs, 0.0))]
        polys.append([b, b + 1, b + 2, b + 3])
        gi = len(polys) - 1
    return BVHTree.FromPolygons(verts, polys, epsilon=0.0), gi


def remove_hidden(bm, ground_reach=0.4, keep=None):
    """Delete faces no camera outside the asset can see: every ray from every
    sample point on the face is blocked by the asset itself (any distance) or by
    the ground within `ground_reach` (a camera could stand anywhere further out).
    Catches bottoms resting on the ground and faces sealed inside the shell."""
    bm.verts.ensure_lookup_table()
    bm.verts.index_update()
    bm.faces.index_update()
    bvh, gi = _bvh(bm)
    dirs = _hemi_dirs(40, min_cos=0.05)
    dirs.sort(key=lambda d: -d.z)
    kill = []
    for f in bm.faces:
        if keep is not None and keep(f):
            continue
        if f.calc_area() < 1e-7:
            kill.append(f)
            continue
        n = f.normal
        M = _basis(n)
        wd = [M @ d for d in dirs]
        c = f.calc_center_median()
        vs = [v.co for v in f.verts]
        pts = [c] + [c.lerp(v, 0.96) for v in vs] + [c.lerp((a + b) / 2, 0.96) for a, b in zip(vs, vs[1:] + vs[:1])]
        if f.calc_area() > 1.0:      # big faces: an extra ring of samples
            pts += [c.lerp(v, 0.5) for v in vs]
        hidden = True
        for p in pts:
            o = p + n * 0.004
            for d in wd:
                loc, _, idx, dist = bvh.ray_cast(o, d, 1000.0)
                if loc is None or (idx == gi and dist > ground_reach):
                    hidden = False
                    break
            if not hidden:
                break
        if hidden:
            kill.append(f)
    if kill:
        bmesh.ops.delete(bm, geom=kill, context="FACES_ONLY")
        loose = [v for v in bm.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context="VERTS")
    return len(kill)


# ================================================================== weathering
def weather(bm, col, fam_of_index, emissive_index, sills, seed=1, building=True, ao_dist=None,
            ao_strength=0.62, compensate=True):
    """Bake weathering into the per-corner colour layer `col` (linear floats)."""
    if not bm.faces:
        return
    rng = random.Random(seed * 7919 + 13)
    bm.verts.index_update()
    bm.faces.index_update()
    bm.normal_update()
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    size = max(max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs), 0.3)
    zmax = max(zs)
    ao_dist = ao_dist or min(2.2, max(0.25, size * 0.28))
    bvh, gi = _bvh(bm)
    base_dirs = _hemi_dirs(18, cosine=True)
    rz = [f.calc_center_median().z for f in bm.faces if fam_of_index.get(f.material_index) in ROOFY]
    rz0, rz1 = (min(rz), max(rz)) if rz else (0.0, 1.0)
    rz1 = max(rz1, rz0 + 0.5)
    off = Vector((seed * 3.7, seed * 1.9, seed * 5.3))
    cache = {}

    def ao_at(p, n):
        key = (round(p.x, 3), round(p.y, 3), round(p.z, 3), round(n.x, 1), round(n.y, 1), round(n.z, 1))
        if key in cache:
            return cache[key]
        M = _basis(n)
        rot = rng.random() * math.tau
        cr, sr = math.cos(rot), math.sin(rot)
        o = p + n * 0.01
        occ = 0.0
        for d in base_dirs:
            dd = M @ Vector((d.x * cr - d.y * sr, d.x * sr + d.y * cr, d.z))
            loc, _, idx, dist = bvh.ray_cast(o, dd, ao_dist)
            if loc is not None:
                occ += (1.0 - dist / ao_dist) ** 0.7
        a = 1.0 - occ / len(base_dirs)
        cache[key] = a
        return a

    tide_h = 0.55 if building else min(0.25, size * 0.2)
    for f in bm.faces:
        mi = f.material_index
        if mi in emissive_index:
            continue
        fam = fam_of_index.get(mi)
        fn = f.normal
        for l in f.loops:
            p = l.vert.co
            nn = l.vert.normal if f.smooth else fn
            c = to_srgb(l[col][:3])
            c_base = c
            k = max(0.38, 1.0 - ao_strength * (1.0 - ao_at(p, nn)))
            # contact darkening right at the ground line
            band = 0.28 if building else 0.12
            if p.z < band:
                k *= 1.0 - 0.28 * (1.0 - p.z / band) ** 2
            # low-frequency dirt / fading so no big surface is flat
            k *= 1.0 + 0.08 * noise.noise(p * 0.45 + off) + 0.04 * noise.noise(p * 2.1 + off)
            c = [x * k for x in c]
            vertical = abs(nn.z) < 0.6
            if fam in ("plaster", "stone", "wood", "cobble") and vertical:
                # damp tide line at the base: darker, a touch greener, ragged top edge
                th = tide_h * (1.0 + 0.45 * noise.noise(Vector((p.x * 1.3, p.y * 1.3, 4.0)) + off))
                if p.z < th:
                    d = (1.0 - p.z / max(th, 0.05)) ** 1.5
                    c = [c[0] * (1 - 0.3 * d), c[1] * (1 - 0.26 * d), c[2] * (1 - 0.3 * d)]
                # rain streaks run down from ledges: faint vertical banding on walls
                if building and fam == "plaster":
                    s = max(0.0, noise.noise(Vector((p.x * 2.7 + p.y * 2.7, 0.5, 1.0)) + off))
                    k2 = 1.0 - 0.1 * s * min(1.0, p.z / 2.0)
                    c = [x * k2 for x in c]
                for (sc, st, sn, sw) in sills:
                    rel = p - sc
                    if nn.dot(sn) < 0.5 or abs(rel.dot(sn)) > 0.45:
                        continue
                    u = rel.dot(st)
                    dz = sc.z - p.z
                    if dz < -0.02 or dz > 1.7 or abs(u) > sw / 2 + 0.25:
                        continue
                    edge = 1.0 - smoothstep(sw * 0.2, sw / 2 + 0.25, abs(u))
                    fall = (1.0 - max(dz, 0.0) / 1.7) ** 1.3
                    st_n = 0.65 + 0.35 * noise.noise(Vector((u * 5.0, 0.0, sc.x + sc.y)))
                    kk = 1.0 - 0.34 * edge * fall * st_n
                    c = [c[0] * kk, c[1] * kk, c[2] * kk * 0.98]
            if fam in ROOFY and nn.z > 0.15:
                t = min(1.0, max(0.0, (p.z - rz0) / (rz1 - rz0)))
                lum = 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]
                bl = 0.26 * t * min(1.0, nn.z * 1.5)
                grey = (lum * 1.18, lum * 1.14, lum * 1.05)
                c = [c[i] * (1 - bl) + grey[i] * bl for i in range(3)]
                c = [x * (1.0 + 0.1 * t) for x in c]
                if nn.y > 0.12 and t < 0.45:     # north slope: moss creeping up from the eave
                    m = smoothstep(0.05, 0.6, noise.noise(p * 0.9 + off + Vector((5, 5, 5)))) * (1 - t / 0.45)
                    m *= min(1.0, nn.y * 2.5) * 0.55
                    c = [c[i] * (1 - m) + MOSS[i] * 0.8 * m for i in range(3)]
            if fam in ("stone", "cobble"):
                facing = max(nn.y, 0.0) * 0.9 + max(nn.z, 0.0) * 0.5
                low = max(0.0, 1.0 - p.z / (1.8 if building else 0.6))
                if facing > 0 and low > 0:
                    m = smoothstep(-0.1, 0.55, noise.noise(p * 1.4 + off)) * min(1.0, facing) * low * 0.6
                    c = [c[i] * (1 - m) + MOSS[i] * m for i in range(3)]
            if fam == "wood" and nn.z > 0.6:     # sun-greyed tops of exposed timber
                lum = 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]
                c = [c[i] * 0.85 + lum * 0.15 * 1.1 for i in range(3)]
            if compensate and fam in ART_FAMS:
                # painted texture x tint: tint = (palette colour / texture mean) blended toward 1 by `k`,
                # then the weathering ratio (AO, damp, moss...) on top
                a = ART_FAMS[fam]
                kt = a["k"]
                lb = 0.3 * c_base[0] + 0.59 * c_base[1] + 0.11 * c_base[2]
                lc = 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]
                sh = min(2.0, max(0.2, lc / max(lb, 1e-3)))          # brightness change from AO / damp / bleach
                tint = [(1 - kt) + kt * c_base[i] / a["mean"][i] for i in range(3)]
                # colour change from moss / greying (not multiplicative), scaled to the texture's own range
                c = [tint[i] * sh + (c[i] - c_base[i] * sh) * kt / a["mean"][i] * 0.5 for i in range(3)]
                c = [x * a.get("gain", 1.0) for x in c]
            elif compensate and fam is not None:
                c = [x / MEAN for x in c]
            c = [min(1.0, max(0.0, x)) for x in c]
            l[col] = (*to_lin(c), 1.0)


# ================================================================== LOD split / proxy
def split_lod(bm, lay, level):
    """Copy of `bm` with only the faces that belong to LOD `level` (0 or 1)."""
    out = bm.copy()
    ly = out.faces.layers.int.get(lay)
    bit = 2 if level == 0 else 1
    kill = [f for f in out.faces if f[ly] & bit]
    if kill:
        bmesh.ops.delete(out, geom=kill, context="FACES_ONLY")
    loose = [v for v in out.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(out, geom=loose, context="VERTS")
    return out


def collapse(ob, goal_tris):
    """Collapse-decimate `ob` in place to about goal_tris; returns the new count."""
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    dm = ob.modifiers.new("dec", "DECIMATE")
    dm.decimate_type = "COLLAPSE"
    dm.ratio = max(0.05, min(1.0, goal_tris / max(1, tris)))
    dm.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=dm.name)
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def tri_count(bm):
    return sum(max(0, len(f.verts) - 2) for f in bm.faces)


def make_proxy(src_ob, target_tris, voxel, fam_of_index, col_name="Col", uv_name="UVMap"):
    """Very-low proxy of `src_ob` (distant landmark LOD): voxel remesh (closes the
    shape), collapse-decimate to ~target_tris, then per face take material and
    colour from the nearest source face; box-projected UVs."""
    me = src_ob.data.copy()
    ob = bpy.data.objects.new(src_ob.name + "_lod2", me)
    bpy.context.collection.objects.link(ob)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    rm = ob.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = voxel
    rm.adaptivity = 0.0
    bpy.ops.object.modifier_apply(modifier=rm.name)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    dm = ob.modifiers.new("dec", "DECIMATE")
    dm.decimate_type = "COLLAPSE"
    dm.ratio = min(1.0, target_tris / max(1, tris))
    dm.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=dm.name)
    # nearest-face transfer
    sbm = bmesh.new()
    sbm.from_mesh(src_ob.data)
    sbm.faces.ensure_lookup_table()
    scol = sbm.loops.layers.float_color.get(col_name)
    sbvh = BVHTree.FromBMesh(sbm)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for layer in list(bm.loops.layers.float_color):
        bm.loops.layers.float_color.remove(layer)
    col = bm.loops.layers.float_color.new(col_name)
    uvl = bm.loops.layers.uv.get(uv_name) or bm.loops.layers.uv.new(uv_name)
    bm.normal_update()
    for f in bm.faces:
        c = f.calc_center_median()
        loc, nrm, idx, dist = sbvh.find_nearest(c)
        if idx is None:
            continue
        sf = sbm.faces[idx]
        f.material_index = sf.material_index
        fam = fam_of_index.get(sf.material_index) or "stone"
        tile = TILE.get(fam, 1.0)
        for l in f.loops:
            # colour of the nearest source point for this corner
            loc2, _, idx2, _ = sbvh.find_nearest(l.vert.co)
            sf2 = sbm.faces[idx2] if idx2 is not None else sf
            cc = [0.0, 0.0, 0.0]
            for sl in sf2.loops:
                for i in range(3):
                    cc[i] += sl[scol][i]
            nn = len(sf2.loops)
            l[col] = (cc[0] / nn, cc[1] / nn, cc[2] / nn, 1.0)
            n = f.normal
            an = (abs(n.x), abs(n.y), abs(n.z))
            d = an.index(max(an))
            a, b = ((0, 1), (1, 2), (0, 2))[(2, 0, 1).index(d)]
            l[uvl].uv = (l.vert.co[a] / tile, l.vert.co[b] / tile)
    bm.to_mesh(ob.data)
    bm.free()
    sbm.free()
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob


# ================================================================== export
def add_markers(ob, markers):
    """Empties (glTF nodes, Node3D in Godot) parented to `ob`, e.g. chimney_top."""
    out = []
    for name, p in markers:
        e = bpy.data.objects.new(name, None)
        e.empty_display_type = "PLAIN_AXES"
        e.empty_display_size = 0.2
        e.location = p
        bpy.context.collection.objects.link(e)
        e.parent = ob
        out.append(e)
    return out


ART_DIR = os.path.join(ROOT, "kingdom", "assets", "art")   # hand-painted textures/emblems: also shared, not embedded


def _is_shared_tex(im):
    d = os.path.dirname(os.path.abspath(bpy.path.abspath(im.filepath)))
    return d == TEX_DIR or (os.path.commonpath([d, ART_DIR]) == ART_DIR if os.path.isdir(ART_DIR) else False)


def export_glb(ob, out_glb, extra=()):
    """glTF-separate export (textures stay in village_tex/ or assets/art/ by relative
    URI), then pack .gltf + .bin into one .glb that still points at the shared textures."""
    bpy.ops.object.select_all(action="DESELECT")
    for e in extra:
        e.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    out_glb = os.path.abspath(out_glb)
    used = {n.image for m in ob.data.materials if m and m.node_tree for n in m.node_tree.nodes
            if n.type == "TEX_IMAGE" and n.image}
    if any(not im.filepath or not _is_shared_tex(im) for im in used):
        # an asset with its own generated texture (e.g. field_crops' wheat cards): embed as before
        bpy.ops.export_scene.gltf(filepath=out_glb, export_format="GLB", export_apply=True, use_selection=True,
                                  export_vertex_color="MATERIAL")
        return None
    base = os.path.splitext(out_glb)[0]
    tmp = base + "__tmp.gltf"
    bpy.ops.export_scene.gltf(filepath=tmp, export_format="GLTF_SEPARATE", use_selection=True,
                              export_apply=True, export_keep_originals=True,
                              export_vertex_color="MATERIAL", export_normals=True, export_texcoords=True,
                              export_yup=True)
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
