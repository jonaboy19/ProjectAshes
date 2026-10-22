# Horse body mesh stage (imported by horse_build.py): region ids from the Mesh2Motion palette, old tail removed,
# new hanging tail and storybook mane modelled procedurally, heat weights on the body, chain weights on the hair.
import bpy, bmesh, math
from mathutils import Vector, Matrix
import horse_build as HB

V = HB.V
log = HB.log

REGION = {  # region id per face (int attribute "region"); the coat painter (horse_coats.py) reads it
    "body": 1, "light": 2, "black": 3, "hoof": 4, "dark": 5, "mouth": 6, "hair": 7}


def classify(c):
    r, g, b = c[0], c[1], c[2]
    if r < 0.1 and g < 0.1 and b < 0.1:
        return "black"
    if r > 0.65 and g < 0.45 and b > 0.1:
        return "mouth"
    if r > 0.95 and 0.6 < g < 0.8:
        return "light"
    if 0.8 < r < 0.95 and g > 0.7:
        return "hoof"
    if r < 0.42 and g < 0.25:
        return "dark"
    return "body"


def _w(body, v, names):
    return sum(g.weight for g in v.groups if body.vertex_groups[g.group].name in names)


def prepare_body(body):
    me = body.data
    mat = me.materials[0]
    img = [n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE"][0]
    W, Hh = img.size
    px = img.pixels[:]
    uv = me.uv_layers[0].data
    face_region = []
    for p in me.polygons:
        u = sum(uv[i].uv[0] for i in p.loop_indices) / p.loop_total
        v = sum(uv[i].uv[1] for i in p.loop_indices) / p.loop_total
        x = min(W - 1, max(0, int(u * W))); y = min(Hh - 1, max(0, int(v * Hh)))
        k = (y * W + x) * 4
        cls = classify(px[k:k + 3])
        if cls == "mouth" and (body.matrix_world @ p.center).y > -1.0:
            cls = "body"
        face_region.append(REGION[cls])
    tailnames = {"tail_2", "tail_3", "tail_4", "tail_leaf"}
    kill_idx = set()
    for v in me.vertices:
        co = body.matrix_world @ v.co
        if _w(body, v, tailnames) > 0.25 or (_w(body, v, {"tail_1"}) > 0.5 and co.y > 0.70):
            kill_idx.add(v.index)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    rl = bm.faces.layers.int.new("region")
    for f, r in zip(bm.faces, face_region):
        f[rl] = r
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in kill_idx], context="VERTS")
    # the Mesh2Motion body is 28 loose pieces that touch: weld them into one closed surface
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.0005)
    edges = [e for e in bm.edges if e.is_boundary]
    if edges:
        res = bmesh.ops.holes_fill(bm, edges=edges, sides=0)
        for f in res["faces"]:
            f[rl] = REGION["body"]
        bmesh.ops.triangulate(bm, faces=res["faces"])
    bm.to_mesh(me)
    bm.free()
    for g in list(body.vertex_groups):
        body.vertex_groups.remove(g)
    for uvl in list(me.uv_layers):
        me.uv_layers.remove(uvl)
    for ca in list(me.color_attributes):
        me.color_attributes.remove(ca)
    me.materials.clear()
    body.name = "HorseBodyOnly"
    region_colors(body)
    sub = body.modifiers.new("sub", "SUBSURF")
    sub.levels = 1
    sub.render_levels = 1
    dec = body.modifiers.new("dec", "DECIMATE")
    dec.ratio = 0.27
    bpy.context.view_layer.objects.active = body
    for m in (sub, dec):
        bpy.ops.object.modifier_apply(modifier=m.name)
    log("body tris", sum(len(p.vertices) - 2 for p in me.polygons), "tail verts removed", len(kill_idx))
    return body


def _ring(center, T, N, rx, ry, sides, twist=0.0):
    B = T.cross(N)
    if B.length < 1e-6:
        B = T.orthogonal()
    B.normalize()
    N = B.cross(T).normalized()
    return [center + N * (math.cos(2 * math.pi * i / sides + twist) * rx) + B * (math.sin(2 * math.pi * i / sides + twist) * ry)
            for i in range(sides)]


def _tube(bm, rings, sides, cap=True):
    vs, out = [], []
    for ri, ring in enumerate(rings):
        row = [bm.verts.new(p) for p in ring]
        vs.append(row)
        out += [(v, ri) for v in row]
    for ri in range(len(vs) - 1):
        a, b = vs[ri], vs[ri + 1]
        for i in range(sides):
            j = (i + 1) % sides
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap:
        tip = bm.verts.new(sum(rings[-1], Vector()) / sides)
        out.append((tip, len(rings) - 1))
        for i in range(sides):
            bm.faces.new((vs[-1][i], vs[-1][(i + 1) % sides], tip))
        top = bm.verts.new(sum(rings[0], Vector()) / sides)
        out.append((top, 0))
        for i in range(sides):
            bm.faces.new((vs[0][(i + 1) % sides], vs[0][i], top))
    return out


def _catmull(pts, t):
    n = len(pts) - 1
    x = max(0.0, min(0.99999, t)) * n
    i = int(x); u = x - i
    p0 = pts[max(i - 1, 0)]; p1 = pts[i]; p2 = pts[i + 1]; p3 = pts[min(i + 2, n)]
    return 0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (-p0 + 3 * p1 - 3 * p2 + p3) * u * u * u)


def _finish(bm, name, region="hair"):
    rl = bm.faces.layers.int.get("region") or bm.faces.layers.int.new("region")
    for f in bm.faces:
        f[rl] = REGION[region]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def build_tail(game):
    bones = ["tail_%d" % i for i in range(1, 6)]
    gb = game.data.bones
    W = game.matrix_world
    path = [W @ gb["tail_1"].head_local] + [W @ gb[b].tail_local for b in bones]
    bm = bmesh.new()
    recs = []
    # (angle around the chain, fan-out radius, length fraction)
    locks = [(0.0, 0.0, 1.0), (1.0, 0.040, 0.95), (2.2, 0.042, 0.92), (3.3, 0.040, 0.97), (4.4, 0.042, 0.90), (5.5, 0.040, 0.94),
             (2.8, 0.060, 0.82)]
    sides, nr = 6, 12
    for li, (ang, spread, length) in enumerate(locks):
        rings, us = [], []
        for k in range(nr):
            s = k / (nr - 1) * length
            c = _catmull(path, s)
            T = (_catmull(path, min(s + 0.01, 1)) - _catmull(path, max(s - 0.01, 0))).normalized()
            side = V(1, 0, 0)
            up = T.cross(side).normalized()
            fan = spread * (0.35 + 1.6 * math.sin(min(s, 0.8) / 0.8 * math.pi * 0.5)) * (1.0 - 0.45 * max(0, s - 0.75) / 0.25)
            wave = 0.018 * math.sin(s * 7.0 + li * 1.7) * s
            off = side * (math.cos(ang) * fan + wave) + up * (math.sin(ang) * fan)
            r = 0.046 * (0.55 + 0.9 * math.sin(math.pi * min(1.0, s / length * 0.85 + 0.12))) * (1.0 - 0.8 * (s / length) ** 3)
            rings.append(_ring(c + off, T, side, max(r, 0.004), max(r * 0.85, 0.004), sides, ang))
            us.append(s)
        for v, ri in _tube(bm, rings, sides):
            recs.append((v, us[ri]))
    bm.verts.index_update()
    ob = _finish(bm, "HorseTail")
    vg = {n: ob.vertex_groups.new(name=n) for n in ["hips"] + bones}
    for v, s in recs:
        i = v.index
        u = s * 5.0 - 0.5
        if s < 0.06:
            vg["hips"].add([i], 1.0 - s / 0.06, "ADD")
        for k, b in enumerate(bones):
            w = max(0.0, 1.0 - abs(u - k))
            if (k == 0 and u < 0) or (k == 4 and u > 4):
                w = 1.0
            if w > 0:
                vg[b].add([i], w, "ADD")
    bm.free()
    return ob


def build_mane(game, body):
    gb = game.data.bones
    W = game.matrix_world
    neck = [W @ gb["withers"].head_local] + [W @ gb[n].tail_local for n in ("withers", "neck_1", "neck_2", "neck_3", "neck_4")]
    poll = W @ gb["head"].head_local
    tufts = ["mane_%d_a" % i for i in range(1, 6)]
    tuft_y = [(W @ gb[t].head_local).y for t in tufts]
    t = HB._bvh(body)
    inv = body.matrix_world.inverted()
    bm = bmesh.new()
    recs = []
    NL = 15
    y0, y1 = poll.y + 0.06, neck[1].y + 0.02
    for li in range(NL):
        c = li / (NL - 1)
        y = y0 + (y1 - y0) * c
        best = min(range(len(neck) - 1), key=lambda i: abs((neck[i].y + neck[i + 1].y) * 0.5 - y))
        a, b = neck[best], neck[best + 1]
        k = max(0.0, min(1.0, (y - a.y) / (b.y - a.y))) if abs(b.y - a.y) > 1e-5 else 0.0
        axis_p = a.lerp(b, k)
        ax = (b - a).normalized()
        up = (V(0, 0, 1) - ax * ax.z).normalized()
        right = V(-1, 0, 0)
        length = 0.13 + 0.12 * math.sin(math.pi * min(1.0, c * 1.15))
        width = 0.050 + 0.028 * math.sin(math.pi * c)
        rings, us = [], []
        nr = 8
        for kk in range(nr):
            s = kk / (nr - 1)
            th = -0.30 + s * (1.45 + 0.35 * length / 0.25)
            d = up * math.cos(th) + right * math.sin(th)
            d = (d - ax * d.dot(ax)).normalized()
            o = inv @ (axis_p + d * 0.8)
            hit = t.ray_cast(o, (inv.to_3x3() @ (-d)).normalized())
            base = (body.matrix_world @ hit[0]) if hit[0] is not None else axis_p + d * 0.12
            lift = 0.010 + 0.028 * math.sin(math.pi * min(1.0, s * 1.2)) * (length / 0.25)
            ctr = base + d * lift + V(0.0, 0.02 * s + 0.010 * math.sin(li * 2.3) * s, 0.0)
            T = (up * -math.sin(th) + right * math.cos(th))
            T = (T - ax * T.dot(ax)).normalized()
            w = width * (1.0 - 0.85 * s ** 2.2)
            rings.append(_ring(ctr, T, ax, max(w, 0.006), 0.018 * (1 - 0.6 * s) + 0.005, 5))
            us.append(s)
        for v, ri in _tube(bm, rings, 5):
            recs.append((v, us[ri], y, "neck"))
    fa = W @ gb["mane_0_a"].head_local
    fdir = (W @ gb["mane_0_b"].tail_local - fa)
    for li, dx in enumerate((-0.035, 0.0, 0.035)):
        rings, us = [], []
        for kk in range(7):
            s = kk / 6.0
            ctr = fa + V(dx, 0, 0) + fdir * s * (0.85 + 0.15 * (li % 2)) + V(dx * s * 0.6, 0, 0.02 * math.sin(math.pi * s))
            w = 0.028 * (1 - 0.8 * s ** 2)
            rings.append(_ring(ctr, fdir.normalized(), V(1, 0, 0), max(w, 0.005), 0.011, 5))
            us.append(s)
        for v, ri in _tube(bm, rings, 5):
            recs.append((v, us[ri], None, "forelock"))
    bm.verts.index_update()
    ob = _finish(bm, "HorseMane")
    names = tufts + ["mane_%d_b" % i for i in range(1, 6)] + ["mane_0_a", "mane_0_b", "head", "neck_1", "neck_2", "neck_3", "neck_4", "withers"]
    vg = {n: ob.vertex_groups.new(name=n) for n in names}
    parent_of = {tf: gb[tf].parent.name for tf in tufts}
    for v, s, y, kind in recs:
        i = v.index
        if kind == "forelock":
            vg["head"].add([i], max(0.0, 1.0 - s / 0.3), "ADD")
            vg["mane_0_a"].add([i], max(0.0, 1.0 - abs(s - 0.4) / 0.4), "ADD")
            vg["mane_0_b"].add([i], max(0.0, (s - 0.35) / 0.65), "ADD")
            continue
        order = sorted(range(5), key=lambda kq: abs(tuft_y[kq] - y))
        k0, k1 = order[0], order[1]
        d0, d1 = abs(tuft_y[k0] - y), abs(tuft_y[k1] - y)
        a = d1 / max(d0 + d1, 1e-6)
        for kk, wk in ((k0, a), (k1, 1 - a)):
            t0 = tufts[kk]
            root = max(0.0, 1.0 - s / 0.22)
            vg[parent_of[t0]].add([i], wk * root, "ADD")
            vg[t0].add([i], wk * (1.0 - root) * max(0.0, 1.0 - max(0.0, s - 0.45) / 0.55), "ADD")
            vg["mane_%d_b" % (kk + 1)].add([i], wk * max(0.0, (s - 0.45) / 0.55), "ADD")
    bm.free()
    return ob


def skin_body(body, game):
    no_heat = [b.name for b in game.data.bones if b.name.startswith("mane_") or b.name in ("tail_2", "tail_3", "tail_4", "tail_5")
               or b.name.startswith("rein_grip")]
    saved = {n: game.data.bones[n].use_deform for n in no_heat}
    for n in no_heat:
        game.data.bones[n].use_deform = False
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    game.select_set(True)
    bpy.context.view_layer.objects.active = game
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for n, d in saved.items():
        game.data.bones[n].use_deform = d
    missing = [v.index for v in body.data.vertices if not v.groups]
    if missing:
        from mathutils.kdtree import KDTree
        vs = body.data.vertices
        good = [v.index for v in vs if v.groups]
        kd = KDTree(len(good))
        for i, gi in enumerate(good):
            kd.insert(vs[gi].co, i)
        kd.balance()
        for mi in missing:
            co, i, d = kd.find(vs[mi].co)
            for g in vs[good[i]].groups:
                body.vertex_groups[g.group].add([mi], g.weight, "REPLACE")
    log("heat weights: unweighted verts fixed", len(missing))
    return missing


def finalize_weights(ob, maxinf=4):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
    bpy.ops.object.vertex_group_clean(group_select_mode="ALL", limit=0.01)
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=maxinf)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    bpy.ops.object.mode_set(mode="OBJECT")


def attach(ob, game):
    ob.parent = game
    mods = [m for m in ob.modifiers if m.type == "ARMATURE"]
    m = mods[0] if mods else ob.modifiers.new("Armature", "ARMATURE")
    m.object = game


def region_colors(ob):
    """face int attribute 'region' -> byte colour corner attribute 'regions' (R = id * 25 / 255), kept through joins/decimation."""
    me = ob.data
    reg = me.attributes.get("region")
    ca = me.color_attributes.get("regions") or me.color_attributes.new("regions", "BYTE_COLOR", "CORNER")
    for p in me.polygons:
        r = reg.data[p.index].value if reg else REGION["body"]
        for li in p.loop_indices:
            ca.data[li].color = (r * 25 / 255.0, 0, 0, 1)
