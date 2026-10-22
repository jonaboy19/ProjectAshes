# Horse coats: UV unwrap of Horse_LOD0 + hand-painted-looking albedo textures for six coats.
# Cycles EMIT/AO bakes of procedural node trees (object position, region ids, normals, noise) give data maps in the UV
# layout; the painterly colour composition then runs in numpy (position-driven, so UV seams stay invisible).
#   used by horse_export.py (or: blender -b -P horse_coats.py)
import bpy, os, sys, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hx_common as X
from hx_common import V

RES = 1024
LO = np.array([-0.45, -1.65, -0.05])   # position bake bounds (object space, metres)
HI = np.array([0.45, 1.10, 2.15])


# ------------------------------------------------------------------ UV
def _hair_seams(bm, rl):
    """hair = separate tube strands: seam = shortest edge path between the two fan poles, so each strand unfolds as one strip."""
    from collections import deque
    hair = [f for f in bm.faces if f[rl] == 7]
    seen, comps = set(), []
    for f in hair:
        if f.index in seen:
            continue
        comp, dq = [], deque([f])
        seen.add(f.index)
        while dq:
            c = dq.popleft()
            comp.append(c)
            for e in c.edges:
                for n in e.link_faces:
                    if n.index not in seen and n[rl] == 7:
                        seen.add(n.index)
                        dq.append(n)
        comps.append(comp)
    for e in bm.edges:
        e.seam = False
    for comp in comps:
        vs = {v for f in comp for v in f.verts}
        poles = [v for v in vs if len(v.link_faces) >= 4 and all(len(f.verts) == 3 for f in v.link_faces)]
        if len(poles) < 2:
            continue
        a = poles[0]
        b = max(poles[1:], key=lambda v: (v.co - a.co).length)
        prev, dq = {a: None}, deque([a])
        while dq and b not in prev:
            c = dq.popleft()
            for e in c.link_edges:
                o = e.other_vert(c)
                if o in vs and o not in prev and all(f[rl] == 7 for f in e.link_faces):
                    prev[o] = (c, e)
                    dq.append(o)
        c = b
        while prev.get(c):
            c, e = prev[c][0], prev[c][1]
            e.seam = True
    return len(comps)


def unwrap(ob, margin=0.010):
    import bmesh
    X.select_only(ob)
    for uv in list(ob.data.uv_layers):
        ob.data.uv_layers.remove(uv)
    ob.data.uv_layers.new(name="UVMap")
    sc = bpy.context.scene
    sc.tool_settings.use_uv_select_sync = True
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(ob.data)
    rl = bm.faces.layers.int.get("region")
    n = _hair_seams(bm, rl)
    X.log("hair strands", n)
    for f in bm.faces:
        f.select_set(False)
    bm.select_flush(False)
    for f in bm.faces:
        if f[rl] != 7:
            f.select_set(True)
    bm.select_flush(True)
    bmesh.update_edit_mesh(ob.data)
    bpy.ops.uv.smart_project(angle_limit=math.radians(70), island_margin=0.003, area_weight=0.6, correct_aspect=True,
                             scale_to_bounds=False)
    for f in bm.faces:
        f.select_set(f[rl] == 7)
    bm.select_flush(True)
    bmesh.update_edit_mesh(ob.data)
    bpy.ops.uv.unwrap(method="ANGLE_BASED", margin=0.003)
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.average_islands_scale()
    bpy.ops.uv.pack_islands(rotate=True, margin=margin, margin_method="ADD")
    bpy.ops.object.mode_set(mode="OBJECT")
    uv = ob.data.uv_layers[0].data
    area = 0.0
    for p in ob.data.polygons:
        pts = [uv[i].uv for i in p.loop_indices]
        area += 0.5 * abs(sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts))))
    X.log("UV coverage %.1f%%" % (area * 100))


# ------------------------------------------------------------------ bake data maps
def _mat_for(ob):
    m = bpy.data.materials.get("hx_bake") or bpy.data.materials.new("hx_bake")
    m.use_nodes = True
    ob.data.materials.clear()
    ob.data.materials.append(m)
    return m


def _emit_tree(m, img, builder):
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    tx = nt.nodes.new("ShaderNodeTexImage")
    tx.image = img
    nt.nodes.active = tx
    tx.select = True
    col = builder(nt)
    nt.links.new(col, em.inputs["Color"])
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])


def _n(nt, typ, **kw):
    n = nt.nodes.new(typ)
    for k, v in kw.items():
        setattr(n, k, v)
    return n


def _combine(nt, r, g, b):
    c = _n(nt, "ShaderNodeCombineColor")
    for i, s in enumerate((r, g, b)):
        if s is None:
            continue
        if isinstance(s, (int, float)):
            c.inputs[i].default_value = s
        else:
            nt.links.new(s, c.inputs[i])
    return c.outputs[0]


def _mapped(nt, scale, extra_off=(0, 0, 0)):
    tc = _n(nt, "ShaderNodeTexCoord")
    mp = _n(nt, "ShaderNodeMapping")
    mp.inputs["Scale"].default_value = scale
    mp.inputs["Location"].default_value = extra_off
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    return mp.outputs[0]


def b_position(nt):
    tc = _n(nt, "ShaderNodeTexCoord")
    mp = _n(nt, "ShaderNodeMapping")
    rng = HI - LO
    mp.inputs["Scale"].default_value = tuple(1.0 / rng)
    mp.inputs["Location"].default_value = tuple(-LO / rng)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    return mp.outputs[0]


def b_region(nt):
    at = _n(nt, "ShaderNodeAttribute", attribute_name="regions", attribute_type="GEOMETRY")
    sp = _n(nt, "ShaderNodeSeparateColor")
    nt.links.new(at.outputs["Color"], sp.inputs[0])
    return _combine(nt, sp.outputs[0], 0.0, 0.0)


def b_normal(nt):
    g = _n(nt, "ShaderNodeNewGeometry")
    mp = _n(nt, "ShaderNodeVectorMath", operation="MULTIPLY_ADD")
    mp.inputs[1].default_value = (0.5, 0.5, 0.5)
    mp.inputs[2].default_value = (0.5, 0.5, 0.5)
    nt.links.new(g.outputs["Normal"], mp.inputs[0])
    return mp.outputs[0]


def _vor(nt, scale, rnd=1.0):
    v = _n(nt, "ShaderNodeTexVoronoi", voronoi_dimensions="3D", feature="F1", distance="EUCLIDEAN")
    v.inputs["Scale"].default_value = 1.0
    v.inputs["Randomness"].default_value = rnd
    nt.links.new(_mapped(nt, (scale,) * 3, (3.1, 1.7, 5.3)), v.inputs["Vector"])
    return v.outputs["Distance"]


def _noise(nt, scale3, detail=3.0, off=(0, 0, 0)):
    n = _n(nt, "ShaderNodeTexNoise", noise_dimensions="3D")
    n.inputs["Scale"].default_value = 1.0
    n.inputs["Detail"].default_value = detail
    n.inputs["Roughness"].default_value = 0.55
    nt.links.new(_mapped(nt, scale3, off), n.inputs["Vector"])
    return n.outputs["Fac"]


def b_noise1(nt):   # R voronoi F1 (dapples), G streaks along the body (fur), B big mottling
    return _combine(nt, _vor(nt, 9.0), _noise(nt, (46.0, 9.0, 46.0), 2.0, (1, 2, 3)), _noise(nt, (4.5, 4.5, 4.5), 3.0, (7, 1, 4)))


def b_noise2(nt):   # R streaks along Z (mane / tail hair), G fine paper grain, B second voronoi (small dapples / speckle)
    return _combine(nt, _noise(nt, (26.0, 26.0, 5.0), 2.0, (5, 5, 1)), _noise(nt, (150.0, 150.0, 150.0), 1.0, (2, 8, 3)), _vor(nt, 22.0))


def _bake(ob, kind, builder, samples=1, float_img=True):
    img_name = "hx_bake_" + kind
    if img_name in bpy.data.images:
        bpy.data.images.remove(bpy.data.images[img_name])
    img = bpy.data.images.new(img_name, RES, RES, alpha=False, float_buffer=True)
    img.colorspace_settings.name = "Non-Color"
    m = _mat_for(ob)
    if kind == "ao":
        _emit_tree(m, img, lambda nt: _combine(nt, 0.5, 0.5, 0.5))
    else:
        _emit_tree(m, img, builder)
    X.select_only(ob)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    if kind == "ao":
        sc.world = sc.world or bpy.data.worlds.new("hxw")
        sc.world.light_settings.distance = 0.32
        sc.world.light_settings.ao_factor = 1.0 if hasattr(sc.world.light_settings, "ao_factor") else 1.0
    bpy.ops.object.bake(type="AO" if kind == "ao" else "EMIT", margin=12, margin_type="EXTEND", use_clear=True)
    a = np.empty(RES * RES * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    a = a.reshape(RES, RES, 4)[:, :, :3].copy()
    bpy.data.images.remove(img)
    return a


def bake_data(ob):
    """dict of float maps (RES, RES, 3), row 0 = bottom (Blender image order)."""
    d = {}
    d["pos"] = _bake(ob, "pos", b_position)
    d["reg"] = _bake(ob, "reg", b_region)
    d["nrm"] = _bake(ob, "nrm", b_normal)
    d["n1"] = _bake(ob, "n1", b_noise1)
    d["n2"] = _bake(ob, "n2", b_noise2)
    d["ao"] = _bake(ob, "ao", None, samples=128)
    return d


# ------------------------------------------------------------------ painting (numpy)
def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def blur(a, k=2):
    """cheap separable box blur on (H,W) or (H,W,C) arrays (soft region edges)"""
    out = a.astype(np.float32)
    for _ in range(k):
        out = (np.roll(out, 1, 0) + out + np.roll(out, -1, 0)) / 3.0
        out = (np.roll(out, 1, 1) + out + np.roll(out, -1, 1)) / 3.0
    return out


def C(*rgb):
    return np.array(rgb, dtype=np.float32)


def mix(a, b, t):
    return a + (b - a) * t[..., None]


# coat definitions (sRGB-ish painted colours)
COATS = {
    "bay": dict(body=C(.56, .27, .12), top=C(.40, .18, .09), belly=C(.68, .38, .19), points=C(.12, .09, .09), point_legs=True,
                hair=C(.11, .09, .09), muzzle=C(.20, .14, .11), hoof=C(.22, .19, .18), ear_rim=True, socks=True, sheen=C(1.0, .78, .55),
                sheen_k=.10, shadow=C(.55, .50, .72)),
    "chestnut": dict(body=C(.74, .36, .14), top=C(.62, .28, .10), belly=C(.84, .48, .22), points=None, point_legs=False,
                     hair=C(.93, .66, .32), muzzle=C(.66, .40, .28), hoof=C(.46, .35, .26), ear_rim=False, blaze=True,
                     leg=C(.68, .32, .12), sheen=C(1.0, .82, .55), sheen_k=.14, shadow=C(.62, .48, .70)),
    "grey": dict(body=C(.80, .77, .71), top=C(.72, .69, .65), belly=C(.88, .85, .79), points=C(.50, .48, .48), point_legs=True,
                 hair=C(.88, .90, .94), muzzle=C(.45, .43, .43), hoof=C(.74, .69, .60), ear_rim=False, sheen=C(1.0, .90, .72),
                 sheen_k=.08, shadow=C(.62, .64, .84), point_soft=True),
    "black": dict(body=C(.115, .105, .125), top=C(.075, .07, .09), belly=C(.16, .14, .15), points=None, point_legs=False,
                  hair=C(.09, .09, .12), muzzle=C(.19, .16, .16), hoof=C(.14, .13, .14), ear_rim=False, sheen=C(.46, .56, .92),
                  sheen_k=.42, shadow=C(.50, .52, .85)),
    "dappled": dict(body=C(.62, .62, .64), top=C(.50, .50, .54), belly=C(.74, .73, .72), points=C(.25, .25, .28), point_legs=True,
                    hair=C(.30, .30, .34), muzzle=C(.30, .29, .30), hoof=C(.21, .20, .20), ear_rim=False, dapple=True,
                    sheen=C(1.0, .90, .75), sheen_k=.08, shadow=C(.56, .58, .82), hair_mix=C(.72, .72, .76)),
    "warhorse": dict(body=C(.27, .13, .075), top=C(.15, .075, .055), belly=C(.36, .19, .11), points=C(.075, .065, .065), point_legs=True,
                     hair=C(.055, .05, .05), muzzle=C(.14, .10, .09), hoof=C(.13, .12, .12), ear_rim=True, sheen=C(1.0, .72, .5),
                     sheen_k=.12, shadow=C(.48, .44, .68)),
}


def paint(name, D):
    cfg = COATS[name]
    pos = LO + D["pos"] * (HI - LO)
    x, y, z = pos[..., 0], pos[..., 1], pos[..., 2]
    rid = np.rint(D["reg"][..., 0] * 255.0 / 25.0).astype(np.int32)
    filled = rid > 0
    nrm = D["nrm"] * 2 - 1
    ao = np.clip(D["ao"][..., 0], 0, 1)
    vor, streak, big = D["n1"][..., 0], D["n1"][..., 1], D["n1"][..., 2]
    hstreak, grain, vor2 = D["n2"][..., 0], D["n2"][..., 1], D["n2"][..., 2]
    sm = lambda m, k=2: blur(m.astype(np.float32), k)
    R = lambda i: sm(rid == i, 1)
    r_body, r_light, r_black, r_hoof, r_dark, r_mouth, r_hair = (R(i) for i in range(1, 8))
    H_ = np.zeros_like(x)[..., None]

    # ---- body base: darker topline, lighter belly, big soft mottling, muscle glows
    top = sstep(1.25, 1.55, z) * (0.35 + 0.65 * sstep(-0.3, 0.6, -np.abs(x) * 2 + 0.6))
    belly = 1.0 - sstep(0.95, 1.22, z)
    col = mix(np.broadcast_to(cfg["body"], x.shape + (3,)).copy(), np.broadcast_to(cfg["top"], x.shape + (3,)), top * 0.85)
    col = mix(col, np.broadcast_to(cfg["belly"], x.shape + (3,)), belly * 0.7)
    col = col * (1.0 + 0.10 * (big[..., None] - 0.5) * 2.0)
    glow = np.exp(-(((x - 0.22) ** 2 + (y + 0.70) ** 2 + (z - 1.20) ** 2) / 0.05)) + np.exp(-(((x - 0.24) ** 2 + (y - 0.55) ** 2 + (z - 1.28) ** 2) / 0.06))
    glow = np.maximum(glow, np.exp(-(((x + 0.22) ** 2 + (y + 0.70) ** 2 + (z - 1.20) ** 2) / 0.05)) + np.exp(-(((x + 0.24) ** 2 + (y - 0.55) ** 2 + (z - 1.28) ** 2) / 0.06)))
    col = col * (1.0 + 0.09 * glow[..., None])

    # ---- legs / points
    legs = 1.0 - sstep(0.46, 0.72, z)                              # knee / hock line
    if "leg" in cfg:
        col = mix(col, np.broadcast_to(cfg["leg"], col.shape), legs * 0.8)
    if cfg.get("points") is not None:
        pt = cfg["points"]
        if cfg.get("point_soft"):
            legs = legs * (0.65 + 0.35 * big)
        pm = legs if cfg["point_legs"] else np.zeros_like(legs)
        col = mix(col, np.broadcast_to(pt, col.shape), pm)
        if cfg.get("ear_rim"):
            col = mix(col, np.broadcast_to(pt, col.shape), sstep(1.86, 1.93, z))
    # ---- dapples (grey): light discs ringed by darker rim, mostly on body / rump / shoulder, none on legs
    if cfg.get("dapple"):
        d1 = vor
        disc = 1.0 - sstep(0.17, 0.27, d1)                          # light centre
        ring = sstep(0.22, 0.30, d1) * (1.0 - sstep(0.34, 0.50, d1))
        zone = sstep(0.62, 0.95, z) * (1.0 - 0.55 * sstep(1.55, 1.85, z))
        sp = 0.6 + 0.4 * (vor2 > 0.25)
        col = col * (1.0 - 0.22 * ring[..., None] * zone[..., None]) + 0.13 * disc[..., None] * zone[..., None] * sp[..., None]
    # ---- white markings
    white = C(.95, .91, .82)
    if cfg.get("socks"):
        hind = sstep(0.05, 0.25, y)
        socks = (1.0 - sstep(0.30, 0.40, z + 0.05 * (big - 0.5))) * hind
        col = mix(col, np.broadcast_to(white, col.shape), socks)
        sock_mask = socks
    else:
        sock_mask = np.zeros_like(x)
    if cfg.get("blaze"):
        front = (nrm[..., 1] * -0.63 + nrm[..., 2] * 0.78)
        band = (1.0 - sstep(0.020, 0.040, np.abs(x) - 0.012 * sstep(-1.25, -1.42, y))) * sstep(0.55, 0.8, front)
        band = band * sstep(-1.14, -1.20, y) * (1.0 - sstep(-1.44, -1.47, y))
        col = mix(col, np.broadcast_to(white, col.shape), band * r_body)

    # ---- painted brush strokes (along body y) + fine grain
    col = col * (1.0 + 0.14 * (streak[..., None] - 0.5) * 2.0)
    col = col * (1.0 + 0.04 * (grain[..., None] - 0.5) * 2.0)
    # ---- sheen highlight on upward facing fur (warm; blue for black)
    up = np.clip(nrm[..., 2] * 0.85 - nrm[..., 1] * 0.15 + 0.1, 0, 1)
    sheen = cfg["sheen"]
    col = col + cfg["sheen_k"] * (up ** 1.6)[..., None] * (0.55 + 0.9 * streak[..., None]) * sheen * (0.5 + 0.5 * top[..., None])

    # ---- regions
    hair_col = np.broadcast_to(cfg["hair"], col.shape).copy()
    if "hair_mix" in cfg:
        hair_col = mix(hair_col, np.broadcast_to(cfg["hair_mix"], col.shape), 0.5 * np.clip((hstreak - 0.4) * 3, 0, 1) * (1.0 - sstep(0.5, 1.0, ao)))
    hair_col = hair_col * (1.0 + 0.30 * (hstreak[..., None] - 0.5) * 2.0)
    hair_col = hair_col + 0.10 * sheen * (np.clip(nrm[..., 2], 0, 1) ** 1.5)[..., None] * cfg["sheen_k"] * 3.0
    col = mix(col, hair_col, r_hair)
    muz = np.broadcast_to(cfg["muzzle"], col.shape)
    col = mix(col, muz * (1.0 + 0.08 * (streak[..., None] - 0.5) * 2.0), r_light)
    col = mix(col, np.broadcast_to(cfg["hoof"], col.shape) * (1.0 + 0.18 * (grain[..., None] - 0.5) * 2.0), r_hoof)
    if name == "chestnut" or name == "grey":
        pass
    col = mix(col, np.broadcast_to(cfg["hoof"] * 0.85, col.shape) if False else col, np.zeros_like(x))
    col = mix(col, np.broadcast_to(C(.035, .03, .032), col.shape), r_black)
    col = mix(col, np.broadcast_to(cfg["muzzle"] * 0.7 + C(.10, .04, .04), col.shape), r_dark)
    col = mix(col, np.broadcast_to(C(.60, .27, .28), col.shape) * (0.8 + 0.2 * ao[..., None]), r_mouth)
    # socks: light horn on white feet
    if cfg.get("socks"):
        col = mix(col, np.broadcast_to(C(.78, .70, .58), col.shape), r_hoof * sock_mask)

    # ---- baked AO multiplied in with cool tinted shadows
    aoc = np.clip(ao, 0, 1)[..., None]
    shadow = cfg["shadow"]
    col = col * (aoc + (1.0 - aoc) * shadow * 0.85)
    # warm rim light bounce from below (warm bounce)
    col = col + 0.025 * (np.clip(-nrm[..., 2], 0, 1))[..., None] * C(1.0, .7, .45)
    col = np.clip(col, 0.0, 1.0)
    # empty texels: fill with body colour so mips do not bleed black
    fillc = np.broadcast_to(cfg["body"] * 0.8, col.shape)
    col = np.where(filled[..., None], col, fillc)
    out = np.dstack([col, np.ones_like(x)])
    return out.astype(np.float32)


COAT_ORDER = ["bay", "chestnut", "grey", "black", "dappled", "warhorse"]


def build_all(lod0, out_dir=None, only=None):
    """Unwrap LOD0, bake data maps, paint the six coats. Returns {coat: png path} and the baked data."""
    out_dir = out_dir or X.OUT
    os.makedirs(out_dir, exist_ok=True)
    unwrap(lod0)
    D = bake_data(lod0)
    paths = {}
    for c in COAT_ORDER:
        if only and c not in only:
            continue
        img = paint(c, D)
        p = os.path.join(out_dir, "horse_coat_%s.png" % c)
        X.write_png(p, img)
        X.write_tres(os.path.join(out_dir, "horse_coat_%s.tres" % c), "horse_coat_%s.png" % c, 0.75)
        paths[c] = p
        X.log("coat", c, p)
    # leave the scene clean (bake material, bake engine)
    lod0.data.materials.clear()
    pass
    return paths, D


if __name__ == "__main__":
    arm, lod0 = X.open_rig()
    build_all(lod0)
