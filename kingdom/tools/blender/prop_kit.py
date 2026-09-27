"""Prop kit for the Rising Ashes village props, round 3 (bpy, Blender 5.x).

Extends town_kit.TK (same primitives, palettes and frame stack as every other
Blender asset in the repo) with what small props need on mobile:

- ONE shared material for every prop ("RA_Props"): vertex colour x a shared
  512 x 512 hand-painted detail atlas (kingdom/assets/generated/props/props_atlas.png).
  The GLBs reference the atlas by URI (not embedded), so Godot imports the PNG
  once and every prop shares the same texture in VRAM.
  Emissive parts (lantern glass) use a second tiny material "RA_PropsGlow"
  (vertex colour + emission, no texture). Nothing else.
- The atlas is 8 horizontal strips (512 x 64 px), each tileable along U:
  0 wood grain, 1 bark / rough split wood, 2 fieldstone, 3 hammered iron,
  4 woven cloth, 5 straw / wicker, 6 leaves, 7 plain painted.
  Every face gets planar UVs in its primitive's own frame (grain follows the
  length of a plank / the axis of a barrel), placed in the strip for its
  material key (Wood -> wood, Matte -> stone, Metal -> iron, ...). U wraps,
  V stays inside the strip, so no atlas bleeding and no seams to hide.
- Colour/hue still lives in the vertex colours (COLOR_0), the atlas only adds
  the painted grain, chisel marks and weave (its mean is ~0.9, so colours keep
  their value).

Conventions (same as ra_kit): metres, +Z up, origin at ground centre, front
faces -Y (Godot +Z). No Draco / meshopt.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK
from village_kit import palette, IRON
from ra_kit import hexc, vary, mix, srgb, render_preview
import bpy, bmesh
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT_DIR = os.path.join(ROOT, "kingdom", "assets", "generated", "props")
PREV_DIR = os.path.join(ROOT, "docs", "kingdom", "blender_previews")
ATLAS = os.path.join(OUT_DIR, "props_atlas.png")
ATLAS_PX = 512
NSTRIP = 8
STRIPS = {"wood": 0, "bark": 1, "stone": 2, "metal": 3, "cloth": 4, "straw": 5, "leaf": 6, "flat": 7}
MAT_STRIP = {"Wood": "wood", "Matte": "stone", "Metal": "metal", "Cloth": "cloth", "Thatch": "straw",
             "Plant": "leaf", "Plaster": "flat", "Lamp": "flat", "Water": "flat", "Roof": "wood",
             "Glass": "flat", "Coals": "flat"}
GLOW_KEYS = {"Lamp", "Coals"}
WORLD_U = 3.2      # metres of surface across the atlas width  (160 px / m)
WORLD_V = 0.42     # metres of surface across one strip height (~140 px / m)

# ------------------------------------------------------------------ palette
OAK = hexc("7a5230")        # mid oak, warm
OAK_DK = hexc("553722")     # dark oak (posts, frames)
OAK_LT = hexc("9a6c40")     # fresh / light boards
PINE = hexc("a8804e")
BARK = hexc("5b4130")
ENDGRAIN = hexc("c89a64")
IRON_C = hexc("3a3633")     # warm dark iron
IRON_LT = hexc("5a5550")
STONE_C = [hexc(h) for h in ("9a958a", "8a867e", "a8a193", "857f75", "b0a896", "8e8578")]
CANVAS = hexc("e2d6b8")
RED = hexc("a83a2c")
ROPE = hexc("a88d5e")
STRAW = hexc("d0b064")
SOIL = hexc("4a3526")
LEAF = hexc("4f7a34")


# ------------------------------------------------------------------ atlas
def make_atlas(path=ATLAS, seed=7):
    """Paint the shared detail atlas procedurally (periodic FFT noise per strip)."""
    import numpy as np
    rng = np.random.default_rng(seed)
    W, Hs = ATLAS_PX, ATLAS_PX // NSTRIP
    fx = np.fft.fftfreq(W)[None, :]
    fy = np.fft.fftfreq(Hs)[:, None]

    def fn(su, sv, shape_pow=2.0):
        w = rng.standard_normal((Hs, W))
        f = np.exp(-((np.abs(fx) / su) ** shape_pow + (np.abs(fy) / sv) ** shape_pow))
        f[0, 0] = 0
        r = np.real(np.fft.ifft2(np.fft.fft2(w) * f))
        r -= r.mean()
        return r / (r.std() + 1e-9)

    def norm(a, lo, hi):
        a0, a1 = np.percentile(a, 1), np.percentile(a, 99)
        return lo + (hi - lo) * np.clip((a - a0) / (a1 - a0 + 1e-9), 0, 1)

    X = np.arange(W)[None, :] / W
    Y = np.arange(Hs)[:, None] / Hs
    strips = {}
    # wood: long painted streaks along U, a few darker grain lines, soft brush blotches
    g = fn(0.006, 0.09)
    lines = np.abs(np.sin(g * 2.6 + fn(0.004, 0.05) * 1.2)) ** 14
    blot = fn(0.02, 0.2)
    strips["wood"] = norm(0.9 * g + 0.25 * fn(0.03, 0.4) + 0.35 * blot, 0.78, 1.0) - 0.13 * lines
    # bark / rough: coarse, higher contrast with cracks
    g = fn(0.012, 0.14)
    cr = np.abs(np.sin(fn(0.008, 0.06) * 3.0)) ** 10
    strips["bark"] = norm(g + 0.4 * fn(0.05, 0.4), 0.66, 1.0) - 0.2 * cr
    # stone: chisel blotches + speckle + faint veins
    s = fn(0.035, 0.28) + 0.5 * fn(0.1, 0.8) + 0.25 * rng.standard_normal((Hs, W))
    vein = np.abs(np.sin(fn(0.02, 0.16) * 2.2)) ** 18
    strips["stone"] = norm(s, 0.76, 1.0) - 0.08 * vein
    # iron: soft hammered blotches, a few dents, bright edge-like scratches
    m = fn(0.03, 0.25) + 0.4 * fn(0.1, 0.8)
    strips["metal"] = norm(m, 0.72, 1.0)
    # cloth: fine weave + soft stains
    weave = 0.5 + 0.25 * (np.sin(X * W * math.pi / 2) + np.sin(Y * Hs * math.pi / 2 * 1.0))
    strips["cloth"] = norm(fn(0.015, 0.12) * 0.8 + weave * 0.5, 0.8, 1.0)
    # straw / wicker: strong fibres along U
    st = fn(0.004, 0.6) + 0.35 * fn(0.02, 0.9)
    strips["straw"] = norm(st, 0.6, 1.0)
    # leaves: clumpy blotches
    strips["leaf"] = norm(fn(0.06, 0.5) + 0.5 * fn(0.14, 0.9), 0.7, 1.0)
    # plain painted: very soft blotch
    strips["flat"] = norm(fn(0.02, 0.15), 0.9, 1.0)

    img = np.ones((ATLAS_PX, ATLAS_PX, 4), dtype=np.float32)
    tint = {"wood": (1.0, 0.97, 0.93), "bark": (1.0, 0.97, 0.94), "stone": (1.0, 1.0, 1.0),
            "metal": (1.0, 0.99, 0.97), "cloth": (1.0, 0.99, 0.96), "straw": (1.0, 0.97, 0.9),
            "leaf": (0.97, 1.0, 0.95), "flat": (1.0, 1.0, 1.0)}
    for name, k in STRIPS.items():
        a = np.clip(strips[name], 0, 1)
        for c in range(3):
            img[k * Hs:(k + 1) * Hs, :, c] = a * tint[name][c]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im = bpy.data.images.new("props_atlas", ATLAS_PX, ATLAS_PX, alpha=False)
    im.colorspace_settings.name = "sRGB"
    im.pixels.foreach_set(img.ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)
    print("atlas", path)


def shared_material():
    m = bpy.data.materials.get("RA_Props")
    if m:
        return m
    m = bpy.data.materials.new("RA_Props")
    m.use_nodes = True
    m.use_backface_culling = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(ATLAS, check_existing=True)
    tex.interpolation = "Linear"
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    mx = nt.nodes.new("ShaderNodeMix")
    mx.data_type = "RGBA"
    mx.blend_type = "MULTIPLY"
    mx.inputs["Factor"].default_value = 1.0
    nt.links.new(tex.outputs["Color"], mx.inputs["A"])
    nt.links.new(vc.outputs["Color"], mx.inputs["B"])
    nt.links.new(mx.outputs["Result"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8
    bsdf.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.35
    return m


def glow_material():
    m = bpy.data.materials.get("RA_PropsGlow")
    if m:
        return m
    m = bpy.data.materials.new("RA_PropsGlow")
    m.use_nodes = True
    m.use_backface_culling = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.35
    bsdf.inputs["Emission Color"].default_value = (*srgb(hexc("ffbf66")), 1)
    bsdf.inputs["Emission Strength"].default_value = 3.0
    return m


class PK(TK):
    """TK + per-face atlas UVs + single shared material export."""

    def __init__(self, name, seed=1, pal=None):
        super().__init__(name, seed, pal or palette(stone="grey", timber="dark"))
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.strip = None      # force a strip for the next primitives (e.g. "bark")
        self._grain = None     # local axis the grain follows (None = longest extent)
        self.grime = 0.5
        self.grime_amt = 0.2

    # ------------------------------------------------------------ uv helpers
    def _uvs(self, t, mat, cont=False):
        sname = self.strip or MAT_STRIP.get(mat, "flat")
        k = STRIPS[sname]
        t.normal_update()
        if not t.verts:
            return {}
        lo = [min(v.co[i] for v in t.verts) for i in range(3)]
        hi = [max(v.co[i] for v in t.verts) for i in range(3)]
        ext = [hi[i] - lo[i] for i in range(3)]
        g = self._grain if self._grain is not None else max(range(3), key=lambda i: ext[i])
        uoff = random.random()
        v0 = (k * (ATLAS_PX // NSTRIP) + 3) / ATLAS_PX
        vspan = (ATLAS_PX // NSTRIP - 6) / ATLAS_PX
        out = {}
        for f in t.faces:
            n = f.normal
            a = max(range(3), key=lambda i: abs(n[i]))
            axes = [i for i in range(3) if i != a]
            if g in axes:
                ua = g
                va = axes[0] if axes[1] == g else axes[1]
            else:
                fe = [max(l.vert.co[i] for l in f.loops) - min(l.vert.co[i] for l in f.loops) for i in axes]
                ua, va = (axes[0], axes[1]) if fe[0] >= fe[1] else (axes[1], axes[0])
            vs = [l.vert.co[va] for l in f.loops]
            if cont:   # smooth organic shapes: one origin for all faces, paint flows across
                vmin = lo[va]
                sc = min(1.0, WORLD_V / max(1e-6, max(ext)))
                voff, fu = 0.0, 0.0
            else:
                vmin, vext = min(vs), max(vs) - min(vs)
                sc = 1.0 if vext <= WORLD_V else WORLD_V / vext
                voff = random.uniform(0, max(0.0, WORLD_V - vext * sc))
                fu = random.uniform(0, 0.15)
            out[f] = [((l.vert.co[ua] / WORLD_U) + uoff + fu,
                       v0 + vspan * ((l.vert.co[va] - vmin) * sc + voff) / WORLD_V) for l in f.loops]
        return out

    def _merge(self, t, mat, color, xform, smooth_angle=None, face_var=0.03,
               color_fn=None, grime=True, loop_fn=None):
        uvs = self._uvs(t, mat, smooth_angle is not None and smooth_angle >= 45)
        uv_list = [uvs.get(f) for f in t.faces]
        if xform is None:
            xform = Matrix.Identity(4)
        xform = self.frames[-1] @ xform
        bmesh.ops.transform(t, matrix=xform, verts=t.verts)
        t.normal_update()
        if smooth_angle is not None:
            sharp = [e for e in t.edges if len(e.link_faces) == 2 and
                     e.calc_face_angle(0) > math.radians(smooth_angle)]
            if sharp:
                bmesh.ops.split_edges(t, edges=sharp)
        idx = self.mats[mat][0]
        vmap = {v: self.bm.verts.new(v.co) for v in t.verts}
        for f, fuv in zip(t.faces, uv_list):
            try:
                nf = self.bm.faces.new([vmap[v] for v in f.verts])
            except ValueError:
                continue
            nf.material_index = idx
            nf.smooth = smooth_angle is not None
            c = color_fn(f) if color_fn else color
            c = vary(c, face_var) if face_var else c
            for i, (l, sl) in enumerate(zip(nf.loops, f.loops)):
                cc = loop_fn(sl) if loop_fn else c
                if grime:
                    z = l.vert.co.z - self.grime_z0
                    kk = 1.0 - self.grime_amt * max(0.0, 1.0 - max(z, 0.0) / self.grime) if z < self.grime else 1.0
                    cc = (cc[0] * kk, cc[1] * kk, cc[2] * kk)
                l[self.col] = (*srgb(cc), 1.0)
                if fuv:
                    l[self.uv].uv = fuv[i]
        t.free()

    # grain along the primitive axis for round things
    def cyl(self, *a, **kw):
        self._grain = 2
        try:
            super().cyl(*a, **kw)
        finally:
            self._grain = None

    def lathe(self, *a, **kw):
        self._grain = 2
        try:
            super().lathe(*a, **kw)
        finally:
            self._grain = None

    def log(self, *a, **kw):
        self._grain = 2
        old = self.strip
        self.strip = self.strip or "bark"
        try:
            super().log(*a, **kw)
        finally:
            self._grain = None
            self.strip = old

    # ------------------------------------------------------------ prop parts
    def plank(self, a, b, w, t, color=None, up=(0, 0, 1), bevel=0.012, var=0.1):
        self.bar(a, b, w, t, self.M("Wood"), color or vary(OAK, var, 0.03), up=up, bevel=bevel, var=0)

    def fruit(self, loc, r, color, squash=0.9, segs=6, stem=True, rot=(0, 0, 0)):
        prof = [(0, -r * squash * 0.95), (r * 0.72, -r * squash * 0.7), (r, 0), (r * 0.72, r * squash * 0.72),
                (0, r * squash * 0.8)]
        self.lathe(prof, loc, self.M("Plant"), vary(color, 0.08), segs=segs, smooth=80, rot=rot, var=0)

    def sack(self, loc, s=1.0, rot=(0, 0, 0), c=None, tie=True):
        """Tied grain sack, ~0.62 m tall at s=1, lathe body with a pinched neck."""
        c = c or vary(hexc("b8996a"), 0.07)
        CL = self.M("Cloth")
        prof = [(0.0, 0.0), (0.2, 0.01), (0.265, 0.1), (0.285, 0.26), (0.27, 0.43), (0.2, 0.57),
                (0.08, 0.65), (0.055, 0.68)]
        prof = [(r * s, z * s) for r, z in prof]
        off = random.uniform(0, 50)
        from mathutils import noise as mn

        def vfn(v):
            n = mn.noise(Vector((v.x * 4, v.y * 4, v.z * 4 + off)))
            rr = Vector((v.x, v.y, 0))
            if rr.length > 1e-5:
                v += rr.normalized() * n * 0.02 * s
            v.z *= 1.0 - 0.08 * max(0.0, v.x) / max(0.01, 0.3 * s)
            v.x *= 1.08
            v.y *= 0.9
            return v
        self.push(loc, rot)
        self.lathe(prof, (0, 0, 0), CL, c, segs=10, smooth=85, vfn=vfn, grime=True, var=0)
        if tie:
            self.cyl(0.05 * s, 0.09 * s, (0, 0, 0.65 * s), CL, mix(c, (0, 0, 0), 0.06), segs=6, r2=0.085 * s,
                     noise_amt=0.012 * s, grime=False)
            self.cyl(0.062 * s, 0.025 * s, (0, 0, 0.65 * s), CL, ROPE, segs=6, caps=False, grime=False)
        self.pop()
        return c

    def split_log(self, a, b, r, kind="quarter", roll=0.0, bark=None, cut=None, end=None):
        """Split firewood from a to b ('quarter', 'half' or 'round' section), bark on
        the round side, pale cut faces, end grain at both ends."""
        a, b = Vector(a), Vector(b)
        d = b - a
        L = d.length
        t = bmesh.new()
        lay = t.faces.layers.int.new("k")
        if kind == "quarter":
            pts = [(0.0, 0.0)] + [(r * math.cos(math.radians(g)), r * math.sin(math.radians(g))) for g in (0, 30, 60, 90)]
            arc = set(range(1, 5))
        elif kind == "half":
            pts = [(r * math.cos(math.radians(g)), r * math.sin(math.radians(g))) for g in (0, 45, 90, 135, 180)]
            arc = set(range(0, 5))
        else:
            pts = [(r * math.cos(g), r * math.sin(g)) for g in (i / 6 * math.tau for i in range(6))]
            arc = set(range(6))
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        pts = [(x - cx, y - cy) for x, y in pts]
        n = len(pts)
        lo = [t.verts.new((x, y, 0.0)) for x, y in pts]
        hi = [t.verts.new((x * random.uniform(0.9, 1.05), y * random.uniform(0.9, 1.05), L)) for x, y in pts]
        for i in range(n):
            j = (i + 1) % n
            f = t.faces.new((lo[i], lo[j], hi[j], hi[i]))
            full = kind == "round"
            f[lay] = 1 if (full or (i in arc and j in arc and not (kind == "half" and {i, j} == {0, n - 1}))) else 0
        f0 = t.faces.new(list(reversed(lo)))
        f1 = t.faces.new(hi)
        f0[lay] = 2
        f1[lay] = 2
        bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
        m = Matrix.Translation(a) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4() @ Matrix.Rotation(roll, 4, 'Z')
        cols = {0: cut or vary(hexc("c09060"), 0.1, 0.03), 1: bark or vary(BARK, 0.12, 0.03),
                2: end or vary(ENDGRAIN, 0.1, 0.03)}
        self._grain = 2
        old = self.strip
        self.strip = "bark"
        self._merge(t, self.M("Wood"), cols[1], m, None, 0.03, lambda f: cols[f[lay]], True)
        self._grain = None
        self.strip = old

    def board_c(self, base=None, var=0.1):
        c = base or OAK
        if random.random() < 0.12:
            c = mix(c, hexc("8a8274"), 0.3)
        return vary(c, var, 0.03)

    # ------------------------------------------------------------ finishing
    def build_object(self):
        # remap: every non-glow key -> slot 0 (RA_Props), glow keys -> slot 1
        idx_key = {i: key for key, (i, m) in self.mats.items()}
        has_glow = False
        for f in self.bm.faces:
            g = idx_key.get(f.material_index) in GLOW_KEYS
            has_glow |= g
            f.material_index = 1 if g else 0
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.collection.objects.link(ob)
        me.materials.append(shared_material())
        if has_glow:
            me.materials.append(glow_material())
        me.validate()
        self.has_glow = has_glow
        return ob

    def finish_prop(self, name, budget, cam_dir=(1.1, -1.5, 0.6), fit=1.0, focus_z=None, preview=None,
                    extra=None):
        if preview is None:
            preview = getattr(PK, "preview", True)
        tris = self.tri_count()
        (x0, y0, z0), (x1, y1, z1) = self.bounds()
        os.makedirs(OUT_DIR, exist_ok=True)
        out = os.path.join(OUT_DIR, f"{name}.glb")
        ob = self.build_object()
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=True, use_selection=True,
                                  export_vertex_color="MATERIAL", export_keep_originals=True,
                                  export_draco_mesh_compression_enable=False, export_yup=True)
        fix_glb(out)
        status = "OK" if tris <= budget else "OVER"
        line = (f"PROP {name}: tris={tris} budget={budget} {status}  size {x1 - x0:.2f} x {y1 - y0:.2f} x "
                f"{z1:.2f} m  zmin={z0:.3f}  materials={1 + int(self.has_glow)}")
        print(line)
        if preview:
            png = os.path.join(PREV_DIR, f"prop_{name}.png")
            render_preview(ob, png, "ground", cam_dir, fit, focus_z, extra)
        return line




def fix_glb(path):
    """Post-process an exported GLB: images referenced by URI must not also carry
    a bufferView (Blender writes both with keep_originals), drop the specular
    extension (Godot ignores it) so the file stays plain glTF 2.0 core."""
    import json, struct
    with open(path, "rb") as f:
        data = f.read()
    magic, ver, total = struct.unpack_from("<III", data, 0)
    jlen, jtype = struct.unpack_from("<II", data, 12)
    js = json.loads(data[20:20 + jlen].decode("utf-8"))
    rest = data[20 + jlen:]
    for im in js.get("images", []):
        if "uri" in im:
            im.pop("bufferView", None)
            im.pop("mimeType", None)
    for m in js.get("materials", []):
        ext = m.get("extensions", {})
        ext.pop("KHR_materials_specular", None)
        if not ext:
            m.pop("extensions", None)
    used = js.get("extensionsUsed", [])
    if "KHR_materials_specular" in used:
        used.remove("KHR_materials_specular")
        if not used:
            js.pop("extensionsUsed", None)
    jb = json.dumps(js, separators=(",", ":")).encode("utf-8")
    jb += b" " * ((4 - len(jb) % 4) % 4)
    out = struct.pack("<III", magic, ver, 12 + 8 + len(jb) + len(rest)) + struct.pack("<II", len(jb), jtype) + jb + rest
    with open(path, "wb") as f:
        f.write(out)
