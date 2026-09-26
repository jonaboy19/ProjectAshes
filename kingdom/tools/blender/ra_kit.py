"""Shared helpers for the Rising Ashes procedural asset generators (bpy, Blender 5.x).

Every generator builds its asset into one `Kit` (a single bmesh with several
materials and a per-corner colour attribute "Col"), then calls `kit.finish()`
which exports the GLB and, when a second path ending in .png is given on the
command line, renders a Cycles preview (800x600, 3/4 view, sky background, sun).

    python3 make_xxx.py out.glb [preview.png]

Conventions shared by all assets
- Units are metres, +Z up in Blender (glTF export converts to Godot's +Y up).
- Origin at ground centre of the footprint.
- "Front" (door, sign face, carved face...) faces Blender -Y, which the glTF
  exporter maps to Godot +Z. So in Godot the asset faces +Z; rotate the node's
  Y axis to point it elsewhere.
- Colour lives in the vertex colour attribute COLOR_0 (sRGB values authored,
  stored linear); each material's Base Color is driven by it, so Godot imports
  it with vertex-colour-as-albedo. Materials only carry roughness/metal/emission.
"""
import sys, math, random
import bpy, bmesh
from mathutils import Vector, Matrix, Euler, noise


def srgb(c):
    """sRGB triple (0-1) -> linear."""
    return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def vary(c, amount=0.08, hue=0.0):
    """Randomly brighten/darken an sRGB colour (and optionally shift warm/cool)."""
    k = 1.0 + random.uniform(-amount, amount)
    w = random.uniform(-hue, hue)
    return (min(1, c[0] * k * (1 + w)), min(1, c[1] * k), min(1, c[2] * k * (1 - w)))


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


class Kit:
    def __init__(self, name, seed=1):
        random.seed(seed)
        self.name = name
        bpy.ops.wm.read_factory_settings(use_empty=True)
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.float_color.new("Col")
        self.mats = {}
        self.grime = 0.8        # height (m) over which the base gets darker
        self.grime_amt = 0.22   # darkening at z=0
        self.grime_z0 = 0.0
        self.frames = [Matrix.Identity(4)]

    # ------------------------------------------------------------ frame stack
    def push(self, loc=(0, 0, 0), rot=(0, 0, 0)):
        """Subsequent primitives are placed relative to this local frame."""
        self.frames.append(self.frames[-1] @ self.xf(loc, rot))

    def pop(self):
        self.frames.pop()

    # ---------------------------------------------------------------- materials
    def material(self, key, rough=0.85, metal=0.0, emission=None, strength=0.0,
                 spec=0.4):
        m = bpy.data.materials.new(f"{self.name}_{key}")
        m.use_nodes = True
        nt = m.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = spec
        if emission:
            bsdf.inputs["Emission Color"].default_value = (*srgb(emission), 1)
            bsdf.inputs["Emission Strength"].default_value = strength
        self.mats[key] = (len(self.mats), m)
        return key

    # ------------------------------------------------------------------ merging
    def _merge(self, t, mat, color, xform, smooth_angle=None, face_var=0.03,
               color_fn=None, grime=True, loop_fn=None):
        """Copy temp bmesh `t` into the kit, transformed, coloured, material set."""
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
        for f in t.faces:
            try:
                nf = self.bm.faces.new([vmap[v] for v in f.verts])
            except ValueError:
                continue
            nf.material_index = idx
            nf.smooth = smooth_angle is not None
            c = color_fn(f) if color_fn else color
            c = vary(c, face_var) if face_var else c
            for l, sl in zip(nf.loops, f.loops):
                cc = loop_fn(sl) if loop_fn else c
                if grime:
                    z = l.vert.co.z - self.grime_z0
                    k = 1.0 - self.grime_amt * max(0.0, 1.0 - max(z, 0.0) / self.grime) if z < self.grime else 1.0
                    cc = (cc[0] * k, cc[1] * k, cc[2] * k)
                l[self.col] = (*srgb(cc), 1.0)
        t.free()

    @staticmethod
    def xf(loc=(0, 0, 0), rot=(0, 0, 0), scale=None):
        m = Matrix.LocRotScale(Vector(loc), Euler(rot), None)
        if scale is not None:
            m = m @ Matrix.Diagonal((*scale, 1.0))
        return m

    # ------------------------------------------------------------------ shapes
    def box(self, size, loc, mat, color, rot=(0, 0, 0), bevel=0.0, var=0.06,
            face_var=0.02, jitter=0.0, color_fn=None, smooth=None, grime=True):
        """Axis box of `size` centred at `loc` (then rotated by Euler `rot`)."""
        t = bmesh.new()
        bmesh.ops.create_cube(t, size=1.0)
        for v in t.verts:
            v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        if bevel > 0:
            bmesh.ops.bevel(t, geom=t.edges[:], offset=min(bevel, min(size) * 0.45),
                            segments=1, affect='EDGES')
        if jitter:
            for v in t.verts:
                v.co += Vector((random.uniform(-jitter, jitter) for _ in range(3)))
        c = vary(color, var) if var else color
        self._merge(t, mat, c, self.xf(loc, rot), smooth, face_var, color_fn, grime)

    def cyl(self, r, h, loc, mat, color, rot=(0, 0, 0), segs=10, r2=None,
            caps=True, var=0.06, smooth=50, noise_amt=0.0, noise_scale=2.0,
            base=True, face_var=0.02, grime=True, color_fn=None):
        """Cylinder/cone along local +Z, base at loc when base=True."""
        t = bmesh.new()
        bmesh.ops.create_cone(t, cap_ends=caps, cap_tris=False, segments=segs,
                              radius1=r, radius2=r if r2 is None else r2, depth=h)
        off = random.uniform(0, 100)
        for v in t.verts:
            if base:
                v.co.z += h / 2
            if noise_amt:
                d = Vector((v.co.x, v.co.y, 0))
                if d.length > 1e-5:
                    n = noise.noise(Vector((v.co.x, v.co.y, v.co.z + off)) * noise_scale)
                    v.co += d.normalized() * n * noise_amt
        c = vary(color, var) if var else color
        self._merge(t, mat, c, self.xf(loc, rot), smooth, face_var, color_fn, grime)

    def sphere(self, r, loc, mat, color, scale=(1, 1, 1), subdiv=2, var=0.06,
               noise_amt=0.0, smooth=70, rot=(0, 0, 0), face_var=0.03, grime=True):
        t = bmesh.new()
        bmesh.ops.create_icosphere(t, subdivisions=subdiv, radius=r)
        off = random.uniform(0, 100)
        for v in t.verts:
            if noise_amt:
                v.co += v.co.normalized() * noise.noise(v.co * 3 + Vector((off, 0, 0))) * noise_amt
            v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
        c = vary(color, var) if var else color
        self._merge(t, mat, c, self.xf(loc, rot), smooth, face_var, None, grime)

    def prism(self, pts, depth, loc, mat, color, rot=(0, 0, 0), bevel=0.0,
              var=0.05, face_var=0.02, smooth=None, grime=True, color_fn=None):
        """Extrude a 2D polygon given in the XZ plane (x, z) along +Y by depth,
        centred on Y. Handy for gables, shields, sign boards, blades."""
        t = bmesh.new()
        vs = [t.verts.new((x, -depth / 2, z)) for x, z in pts]
        f = t.faces.new(vs)
        bmesh.ops.recalc_face_normals(t, faces=[f])
        if f.normal.y > 0:
            f.normal_flip()
        r = bmesh.ops.extrude_face_region(t, geom=[f])
        nv = [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]
        bmesh.ops.translate(t, verts=nv, vec=(0, depth, 0))
        bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
        # triangulate n-gon caps so export is predictable
        big = [f for f in t.faces if len(f.verts) > 4]
        if big:
            bmesh.ops.triangulate(t, faces=big, quad_method='BEAUTY', ngon_method='BEAUTY')
        if bevel > 0:
            bmesh.ops.bevel(t, geom=t.edges[:], offset=bevel, segments=1, affect='EDGES',
                            clamp_overlap=True)
        c = vary(color, var) if var else color
        self._merge(t, mat, c, self.xf(loc, rot), smooth, face_var, color_fn, grime)

    def ring(self, r_in, r_out, depth, loc, mat, color, rot=(0, 0, 0), segs=16, var=0.05):
        """Annulus in the XZ plane extruded along Y (window frames, wheel rims)."""
        t = bmesh.new()
        inner, outer = [], []
        for y in (-depth / 2, depth / 2):
            inner.append([t.verts.new((math.cos(a) * r_in, y, math.sin(a) * r_in))
                          for a in (i / segs * math.tau for i in range(segs))])
            outer.append([t.verts.new((math.cos(a) * r_out, y, math.sin(a) * r_out))
                          for a in (i / segs * math.tau for i in range(segs))])
        for i in range(segs):
            j = (i + 1) % segs
            t.faces.new((outer[0][i], outer[0][j], inner[0][j], inner[0][i]))   # front
            t.faces.new((inner[1][i], inner[1][j], outer[1][j], outer[1][i]))   # back
            t.faces.new((outer[1][i], outer[1][j], outer[0][j], outer[0][i]))   # rim
            t.faces.new((inner[0][i], inner[0][j], inner[1][j], inner[1][i]))   # bore
        bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
        c = vary(color, var) if var else color
        self._merge(t, mat, c, self.xf(loc, rot), 40, 0.02, None, False)

    def tube(self, pts, radii, mat, color, segs=8, cap_start=True, point_end=True,
             smooth=60, var=0.05, grime=False, color_fn=None):
        """Sweep a circle along a polyline (horns, tusks, ropes, bent poles).
        `radii` is one radius per point; point_end closes the end to a tip."""
        pts = [Vector(p) for p in pts]
        t = bmesh.new()
        rings = []
        up = Vector((0, 0, 1))
        for i, p in enumerate(pts):
            if i == 0:
                d = pts[1] - pts[0]
            elif i == len(pts) - 1:
                d = pts[-1] - pts[-2]
            else:
                d = pts[i + 1] - pts[i - 1]
            d.normalize()
            ref = up if abs(d.dot(up)) < 0.95 else Vector((1, 0, 0))
            s1 = d.cross(ref).normalized()
            s2 = d.cross(s1).normalized()
            r = radii[i]
            if point_end and i == len(pts) - 1:
                rings.append([t.verts.new(p)])
                continue
            rings.append([t.verts.new(p + (s1 * math.cos(a) + s2 * math.sin(a)) * r)
                          for a in (j / segs * math.tau for j in range(segs))])
        for i in range(len(rings) - 1):
            A, B = rings[i], rings[i + 1]
            for j in range(segs):
                j2 = (j + 1) % segs
                if len(B) == 1:
                    t.faces.new((A[j], A[j2], B[0]))
                else:
                    t.faces.new((A[j], A[j2], B[j2], B[j]))
        if cap_start:
            t.faces.new(list(reversed(rings[0])))
        if not point_end:
            t.faces.new(rings[-1])
        bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
        c = vary(color, var) if var else color
        self._merge(t, mat, c, None, smooth, 0.02, color_fn, grime)

    def skull(self, loc, rot, s, mat, bone=(0.86, 0.82, 0.7), dark=(0.12, 0.09, 0.07),
              horns=True, horn_c=(0.35, 0.3, 0.25), tusks=False):
        """Stylised horned beast skull facing local -Y, about 0.5*s m long."""
        self.push(loc, rot)
        self.sphere(0.2 * s, (0, 0.05 * s, 0.05 * s), mat, bone, scale=(1.0, 1.1, 0.85), subdiv=2, smooth=70,
                    grime=False)
        # tapered snout
        t = bmesh.new()
        bmesh.ops.create_cube(t, size=1.0)
        for v in t.verts:
            y = v.co.y
            k2 = 1.0 - 0.35 * (0.5 - y)
            v.co = Vector((v.co.x * 0.22 * s * k2, (y - 0.5) * 0.32 * s, v.co.z * 0.16 * s * k2))
        bmesh.ops.bevel(t, geom=t.edges[:], offset=0.02 * s, segments=1, affect='EDGES')
        self._merge(t, mat, vary(bone, 0.03), self.xf((0, -0.08 * s, -0.02 * s)), 40, 0.02, None, False)
        for sx in (-1, 1):   # eye sockets + nostril
            self.sphere(0.055 * s, (sx * 0.1 * s, -0.12 * s, 0.07 * s), mat, dark, scale=(1, 0.5, 1), subdiv=1,
                        grime=False, smooth=None)
            self.box((0.03 * s, 0.03 * s, 0.05 * s), (sx * 0.03 * s, -0.405 * s, 0.0), mat, dark, grime=False)
            if horns:
                pts, rr = [], []
                for i in range(7):
                    a = i / 6
                    pts.append((sx * (0.15 + 0.3 * a) * s, (0.05 - 0.12 * a * a) * s, (0.12 + 0.25 * a - 0.18 * a ** 2.5) * s))
                    rr.append(0.065 * s * (1 - a) + 0.005)
                self.tube(pts, rr, mat, horn_c, segs=7)
            if tusks:
                pts = [(sx * 0.08 * s, -0.36 * s, -0.08 * s), (sx * 0.11 * s, -0.44 * s, -0.02 * s),
                       (sx * 0.1 * s, -0.48 * s, 0.07 * s)]
                self.tube(pts, [0.03 * s, 0.022 * s, 0.0], mat, bone, segs=6)
        self.box((0.2 * s, 0.26 * s, 0.05 * s), (0, -0.17 * s, -0.12 * s), mat, vary(bone, 0.05), bevel=0.01 * s,
                 grime=False)   # jaw
        self.pop()

    def quad(self, w, h, loc, mat, color, rot=(0, 0, 0), var=0.03, grime=True):
        """Single-sided rectangle in XZ facing -Y (decals: text lines, stains)."""
        t = bmesh.new()
        vs = [t.verts.new(p) for p in ((-w / 2, 0, -h / 2), (w / 2, 0, -h / 2),
                                       (w / 2, 0, h / 2), (-w / 2, 0, h / 2))]
        t.faces.new(vs)
        c = vary(color, var) if var else color
        self._merge(t, mat, c, self.xf(loc, rot), None, 0.0, None, grime)

    def sword(self, loc, rot, mat_blade, mat_hilt, length=1.0, blade_c=(0.8, 0.82, 0.86),
              hilt_c=(0.75, 0.6, 0.25), grip_c=(0.25, 0.15, 0.1)):
        """Flat stylised sword in the local XZ plane, point down (-Z), hilt at +Z."""
        bl = length * 0.72
        bw = length * 0.045
        pts = [(0, -bl), (bw, -bl + bw * 2.2), (bw, 0), (-bw, 0), (-bw, -bl + bw * 2.2)]
        m = self.xf(loc, rot)
        def put(pts2, depth, off, mat, c, bevel=0.0):
            t = bmesh.new()
            vs = [t.verts.new((x, -depth / 2, z)) for x, z in pts2]
            f = t.faces.new(vs)
            r = bmesh.ops.extrude_face_region(t, geom=[f])
            nv = [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]
            bmesh.ops.translate(t, verts=nv, vec=(0, depth, 0))
            bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
            bmesh.ops.translate(t, verts=t.verts, vec=off)
            self._merge(t, mat, c, m, None, 0.02, None, False)
        put(pts, length * 0.018, (0, 0, 0), mat_blade, blade_c)
        g = length * 0.13
        put([(-g, 0), (g, 0), (g, length * 0.035), (-g, length * 0.035)], length * 0.035, (0, 0, 0), mat_hilt, hilt_c)
        gw = length * 0.022
        put([(-gw, length * 0.035), (gw, length * 0.035), (gw, length * 0.22), (-gw, length * 0.22)],
            length * 0.035, (0, 0, 0), mat_hilt, grip_c)
        pw = length * 0.04
        put([(-pw, length * 0.22), (pw, length * 0.22), (pw * 0.6, length * 0.28), (-pw * 0.6, length * 0.28)],
            length * 0.045, (0, 0, 0), mat_hilt, hilt_c)

    def beam(self, a, b, thick, mat, color, bevel=0.02, var=0.08, roll=0.0,
             face_var=0.02, grime=True, width=None):
        """Square-section timber from point a to point b."""
        a, b = Vector(a), Vector(b)
        d = b - a
        L = d.length
        q = d.to_track_quat('Z', 'Y')
        t = bmesh.new()
        bmesh.ops.create_cube(t, size=1.0)
        w = thick if width is None else width
        for v in t.verts:
            v.co = Vector((v.co.x * w, v.co.y * thick, (v.co.z + 0.5) * L))
        if bevel:
            bmesh.ops.bevel(t, geom=t.edges[:], offset=min(bevel, thick * 0.4), segments=1,
                            affect='EDGES')
        m = Matrix.Translation(a) @ q.to_matrix().to_4x4() @ Matrix.Rotation(roll, 4, 'Z')
        c = vary(color, var) if var else color
        self._merge(t, mat, c, m, None, face_var, None, grime)

    def log(self, a, b, r, mat, color, segs=8, r_end=None, noise_amt=0.03,
            point=0.0, var=0.08, end_color=None, caps=True, grime=True, zfn=None, ring_step=0.6):
        """Round log from a to b (tapering to r_end), optional sharpened tip of
        length `point` at b. End grain faces get `end_color`."""
        a, b = Vector(a), Vector(b)
        d = b - a
        L = d.length
        r2 = r if r_end is None else r_end
        t = bmesh.new()
        rings = max(2, int(L / ring_step) + 1)
        off = random.uniform(0, 100)
        ring_verts = []
        for i in range(rings):
            z = L * i / (rings - 1)
            rr = r + (r2 - r) * i / (rings - 1)
            ring = []
            for s in range(segs):
                ang = s / segs * math.tau
                p = Vector((math.cos(ang) * rr, math.sin(ang) * rr, z))
                n = noise.noise(Vector((p.x * 3, p.y * 3, z * 1.5 + off)))
                p.x += math.cos(ang) * n * noise_amt
                p.y += math.sin(ang) * n * noise_amt
                ring.append(t.verts.new(p))
            ring_verts.append(ring)
        for i in range(rings - 1):
            for s in range(segs):
                s2 = (s + 1) % segs
                t.faces.new((ring_verts[i][s], ring_verts[i][s2], ring_verts[i + 1][s2], ring_verts[i + 1][s]))
        endfaces = []
        if caps:
            endfaces.append(t.faces.new(list(reversed(ring_verts[0]))))
        if point > 0:
            tip = t.verts.new((random.uniform(-0.02, 0.02), random.uniform(-0.02, 0.02), L + point))
            for s in range(segs):
                s2 = (s + 1) % segs
                t.faces.new((ring_verts[-1][s], ring_verts[-1][s2], tip))
        elif caps:
            endfaces.append(t.faces.new(ring_verts[-1]))
        bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
        q = d.to_track_quat('Z', 'Y')
        m = Matrix.Translation(a) @ q.to_matrix().to_4x4()
        c = vary(color, var) if var else color
        ec = end_color or mix(c, (0.85, 0.72, 0.5), 0.5)
        ends = set(endfaces)
        tipc = mix(c, (0.8, 0.66, 0.45), 0.45)
        def cf(f):
            if f in ends:
                return ec
            if point > 0 and len(f.verts) == 3:
                return tipc
            if zfn:   # colour by height (faces are already transformed here)
                return zfn(c, f.calc_center_median().z)
            return c
        self._merge(t, mat, c, m, 60, 0.04, cf, grime)

    def grid_wall(self, w, h, loc, mat, color_fn, rot=(0, 0, 0), bw=0.9, bh=0.45,
                  gap=0.025, push=0.03, holes=(), stagger=True, grime=True, top_fn=None):
        """Masonry face in the XZ plane (x centred, z from 0 to h) facing -Y.
        Each block is a separate slightly pushed-out/tilted quad with a gap, so
        whatever sits ~0.2 m behind (a dark core box) reads as deep mortar.
        `holes` are (x0, z0, x1, z1) rects kept free for doors/windows.
        `top_fn(x)` (optional) clips the wall to a sloped top, e.g. a gable end:
        blocks above it are dropped and blocks crossing it are cut to it."""
        t = bmesh.new()
        lay = t.faces.layers.int.new("cid")
        keys = []
        rows = max(1, round(h / bh))
        bh = h / rows
        for r in range(rows):
            z0, z1 = r * bh, (r + 1) * bh
            zc = (z0 + z1) / 2
            xs = [-w / 2]
            x = -w / 2 + bw * (random.uniform(0.35, 0.75) if (stagger and r % 2) else random.uniform(0.8, 1.2))
            while x < w / 2 - bw * 0.4:
                xs.append(x)
                x += bw * random.uniform(0.7, 1.3)
            xs.append(w / 2)
            segs = [(xs[i], xs[i + 1]) for i in range(len(xs) - 1)]
            for hx0, hz0, hx1, hz1 in holes:
                if hz0 <= zc <= hz1:
                    new = []
                    for a, b in segs:
                        if b <= hx0 or a >= hx1:
                            new.append((a, b))
                            continue
                        if a < hx0:
                            new.append((a, hx0))
                        if b > hx1:
                            new.append((hx1, b))
                    segs = new
            for a, b in segs:
                ta = tb = z1 - gap / 2
                if top_fn is not None:
                    # keep only the part of the block whose top is above its base
                    lim = z0 + gap + 0.04
                    n_s = 6
                    ok = [a + (b - a) * i / n_s for i in range(n_s + 1) if top_fn(a + (b - a) * i / n_s) > lim]
                    if not ok:
                        continue
                    a, b = min(ok), max(ok)
                    ta = min(ta, top_fn(a + gap / 2) - gap / 2)
                    tb = min(tb, top_fn(b - gap / 2) - gap / 2)
                if b - a < 0.08:
                    continue
                g = gap / 2
                y = -random.uniform(0.0, push)
                vs = [t.verts.new((a + g, y + random.uniform(-0.008, 0.008), z0 + g)),
                      t.verts.new((b - g, y + random.uniform(-0.008, 0.008), z0 + g)),
                      t.verts.new((b - g, y + random.uniform(-0.008, 0.008), tb)),
                      t.verts.new((a + g, y + random.uniform(-0.008, 0.008), ta))]
                f = t.faces.new(vs)
                keys.append(color_fn())
                f[lay] = len(keys) - 1
        # winding is already -Y facing: (a,z0)->(b,z0)->(b,z1)
        self._merge(t, mat, (1, 1, 1), self.xf(loc, rot), None, 0.0, lambda f: keys[f[lay]], grime)

    def shingle_side(self, x0, x1, run, rise, mat, color_fn, tile_w=(0.35, 0.6),
                     course=0.38, th=0.035, deck_mat=None, deck_color=(0.3, 0.2, 0.12),
                     loc=(0, 0, 0), rot=(0, 0, 0), gap=0.012, jag=0.05, butt_dark=0.72,
                     droop=0.0):
        """One roof slope made of individual shingles/tiles in stepped courses.
        Local space: ridge along X at y=0, z=rise; eave at y=-run, z=0 (so this
        slope faces -Y). Use rot/loc (or push) to place other slopes."""
        a = math.atan2(rise, run)
        L = math.hypot(run, rise)
        d = Vector((0, math.cos(a), math.sin(a)))
        nrm = Vector((0, -math.sin(a), math.cos(a)))
        base = Vector((0, -run, 0))
        def P(u, s, n):
            return Vector((u, 0, 0)) + base + d * s + nrm * n
        t = bmesh.new()
        lay = t.faces.layers.int.new("cid")
        keys = []
        n_c = max(1, math.ceil(L / course))
        cl = L / n_c
        for i in range(n_c):
            u = x0
            while u < x1 - 0.05:
                w = random.uniform(*tile_w)
                u2 = min(x1, u + w)
                if x1 - u2 < 0.15:
                    u2 = x1
                s_lo = i * cl - random.uniform(0.0, jag)
                s_hi = min(L + 0.02, (i + 1) * cl + cl * 0.55)
                lift = random.uniform(-0.006, 0.01)
                n_lo = 2 * th + lift - droop * random.random()
                n_hi = th * 0.3
                g = gap
                v = [t.verts.new(P(u + g, s_lo, n_lo)), t.verts.new(P(u2 - g, s_lo, n_lo + random.uniform(-0.006, 0.006))),
                     t.verts.new(P(u2 - g, s_hi, n_hi)), t.verts.new(P(u + g, s_hi, n_hi))]
                bottom = -0.06 if i == 0 else 0.0
                b0 = t.verts.new(P(u + g, s_lo, bottom))
                b1 = t.verts.new(P(u2 - g, s_lo, bottom))
                c = color_fn(i / max(1, n_c - 1))
                keys.append(c)
                f1 = t.faces.new(v)
                f1[lay] = len(keys) - 1
                f2 = t.faces.new((b0, b1, v[1], v[0]))
                keys.append(tuple(x * butt_dark for x in c))
                f2[lay] = len(keys) - 1
                u = u2
        # winding: tops face +nrm, butts face down-slope (-d); no recalc needed
        self._merge(t, mat, (1, 1, 1), self.xf(loc, rot), None, 0.0, lambda f: keys[f[lay]], False)
        # deck slab under the tiles: gives the eave edge and underside
        if deck_mat:
            dt = 0.1
            ctr = P((x0 + x1) / 2, L / 2, -dt / 2)
            m = self.xf(loc, rot) @ Matrix.Translation(ctr) @ Matrix.Rotation(a, 4, 'X')
            tb = bmesh.new()
            bmesh.ops.create_cube(tb, size=1.0)
            for vv in tb.verts:
                vv.co = Vector((vv.co.x * (x1 - x0), vv.co.y * L, vv.co.z * dt))
            self._merge(tb, deck_mat, deck_color, m, None, 0.02, None, False)

    def thatch_side(self, x0, x1, run, rise, mat, colors, th=0.32, du=0.2, band=0.5,
                    loc=(0, 0, 0), rot=(0, 0, 0), lump=0.025, deck_mat=None,
                    deck_color=(0.3, 0.22, 0.12), moss=(0.36, 0.42, 0.22), step=0.06,
                    ridge_color=None, ridge_band=0.55):
        """Thick thatch slope as one sculpted, smooth-shaded sheet with rolled
        verges and a rounded eave lip. Same local space as shingle_side."""
        a = math.atan2(rise, run)
        L = math.hypot(run, rise)
        d = Vector((0, math.cos(a), math.sin(a)))
        nrm = Vector((0, -math.sin(a), math.cos(a)))
        base = Vector((0, -run, 0))
        nu = max(2, math.ceil((x1 - x0) / du))
        seed = random.uniform(0, 100)
        t = bmesh.new()
        vlay = t.verts.layers.float_color.new("vc")
        rows = []
        # three rows per layer band; the pair at each band boundary makes the step
        svals = [-0.06, 0.0]
        nb = max(1, round(L / band))
        bl = L / nb
        for b in range(nb):
            sb = b * bl
            svals += [sb + bl * 0.45, sb + bl - 0.035, sb + bl]
        def layer(sv):
            if sv <= 0:
                return 0.0
            f = (sv % bl) / bl if sv < L - 1e-4 else 0.0
            return step * (1.0 - f)
        for j, sv in enumerate(svals):
            row = []
            for i in range(nu + 1):
                u = x0 + (x1 - x0) * i / nu
                if 0 < i < nu:
                    u += random.uniform(-0.25, 0.25) * du
                e_u = min(u - x0, x1 - u)
                edge = min(1.0, e_u / 0.4) ** 0.5
                eave = min(1.0, max(sv, 0.0) / 0.45) ** 0.6
                n = (th * edge * (0.35 + 0.65 * eave) + layer(sv) * edge
                     + noise.noise(Vector((u * 1.3, sv * 1.3, seed))) * lump)
                if j == 0:
                    n = -0.12
                elif sv >= L - 1e-4:
                    n = th * 0.6
                p = Vector((u, 0, 0)) + base + d * max(sv, 0.0) + nrm * n
                if j == 0:
                    p += d * -0.02
                v = t.verts.new(p)
                # straw streaks run down-slope: high frequency across u, low along s
                st = noise.noise(Vector((u * 4.0, sv * 0.5, seed + 3))) + random.uniform(-0.25, 0.25)
                c = colors[int(min(0.999, max(0.0, st * 0.5 + 0.5)) * len(colors))]
                if ridge_color is not None:
                    edge_s = L - ridge_band - 0.18 * abs(math.sin(u * math.pi / 0.6))
                    if sv > edge_s:
                        c = ridge_color
                k = 0.9 + 0.2 * noise.noise(Vector((u * 2.0, sv * 2.0, seed + 7)))
                if sv < 0.6:
                    k *= 0.8 + 0.2 * max(sv, 0) / 0.6          # darker, weathered eave
                if e_u < 0.3:
                    k *= 0.85
                c = tuple(x * k for x in c)
                mz = noise.noise(Vector((u * 0.8, sv * 0.8, seed + 11)))
                if mz > 0.35:
                    c = mix(c, moss, min(0.6, (mz - 0.35) * 2.0))
                v[vlay] = (*c, 1.0)
                row.append(v)
            rows.append(row)
        for j in range(len(rows) - 1):
            for i in range(nu):
                t.faces.new((rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i]))
        self._merge(t, mat, (1, 1, 1), self.xf(loc, rot), 85, 0.0, None, False,
                    loop_fn=lambda l: tuple(l.vert[vlay])[:3])
        if deck_mat:
            dt = 0.12
            ctr = Vector(((x0 + x1) / 2, 0, 0)) + base + d * (L / 2) + nrm * (-dt / 2 - 0.1)
            m = self.xf(loc, rot) @ Matrix.Translation(ctr) @ Matrix.Rotation(a, 4, 'X')
            tb = bmesh.new()
            bmesh.ops.create_cube(tb, size=1.0)
            for vv in tb.verts:
                vv.co = Vector((vv.co.x * (x1 - x0 - 0.1), vv.co.y * (L - 0.1), vv.co.z * dt))
            self._merge(tb, deck_mat, deck_color, m, None, 0.02, None, False)

    def panel_wall(self, w, h, loc, mat, color, rot=(0, 0, 0), holes=(), cell=0.5, var=0.07,
                   hue=0.025, blotch=0.8, speckle=0.02, top_fn=None, top_breaks=(), grime=True,
                   streaks=0.0):
        """Rendered / lime-plastered wall face in the XZ plane (x centred, z 0..h)
        facing -Y, like grid_wall. One shared-vertex grid whose vertex colours get
        soft low-frequency blotches (`var` brightness, `hue` warm/cool shift) plus a
        little per-vertex speckle, so a flat plaster panel reads as hand-applied.
        `holes` (x0, z0, x1, z1) are cut out exactly; `top_fn(x)` clips to a sloped
        top (gables) and `top_breaks` adds x values where that slope has a kink
        (the ridge). `streaks` (0-1) adds faint vertical weathering streaks."""
        def axis(lo, hi, extra):
            n = max(1, math.ceil((hi - lo) / cell))
            req = {round(lo, 5), round(hi, 5)} | {round(v, 5) for v in extra if lo < v < hi}
            vals = sorted(req | {round(lo + (hi - lo) * i / n, 5) for i in range(n + 1)})
            out = [vals[0]]
            for v in vals[1:]:
                if v - out[-1] > 0.04:
                    out.append(v)
                elif v in req and out[-1] not in req:
                    out[-1] = v
            return out
        xs = axis(-w / 2, w / 2, [c for hh in holes for c in (hh[0], hh[2])] + list(top_breaks))
        zs = axis(0.0, h, [c for hh in holes for c in (hh[1], hh[3])])
        t = bmesh.new()
        vlay = t.verts.layers.float_color.new("vc")
        off = Vector((random.uniform(0, 100), random.uniform(0, 100), random.uniform(0, 100)))
        grid = {}

        def V(i, j):
            if (i, j) in grid:
                return grid[(i, j)]
            x, z = xs[i], zs[j]
            if top_fn is not None:
                z = min(z, top_fn(x))
            v = t.verts.new((x, 0.0, z))
            q = Vector((x * blotch, z * blotch, 0.0)) + off
            n1 = noise.noise(q)
            n2 = noise.noise(q * 2.3 + Vector((7.1, 3.3, 1.9)))
            k = 1.0 + var * (0.7 * n1 + 0.3 * n2) + random.uniform(-speckle, speckle)
            wv = hue * n2
            c = (color[0] * k * (1 + wv), color[1] * k, color[2] * k * (1 - wv))
            if streaks:
                s = max(0.0, noise.noise(Vector((x * 4.0, 0.3, 0.0)) + off)) * min(1.0, max(0.0, z / max(h, 0.1)))
                c = tuple(cc * (1.0 - 0.25 * streaks * s) for cc in c)
            v[vlay] = (*[min(1.0, max(0.0, cc)) for cc in c], 1.0)
            grid[(i, j)] = v
            return v

        for i in range(len(xs) - 1):
            for j in range(len(zs) - 1):
                xc, zc = (xs[i] + xs[i + 1]) / 2, (zs[j] + zs[j + 1]) / 2
                if any(hx0 < xc < hx1 and hz0 < zc < hz1 for hx0, hz0, hx1, hz1 in holes):
                    continue
                if top_fn is not None and zs[j] >= max(top_fn(xs[i]), top_fn(xs[i + 1])) - 1e-4:
                    continue
                pts = []
                for v in (V(i, j), V(i + 1, j), V(i + 1, j + 1), V(i, j + 1)):
                    if not pts or (v.co - pts[-1].co).length > 1e-4:
                        pts.append(v)
                if len(pts) > 1 and (pts[0].co - pts[-1].co).length < 1e-4:
                    pts.pop()
                if len(pts) < 3:
                    continue
                try:
                    t.faces.new(pts)
                except ValueError:
                    pass
        for v in [v for v in t.verts if not v.link_faces]:
            t.verts.remove(v)
        self._merge(t, mat, (1, 1, 1), self.xf(loc, rot), None, 0.0, None, grime,
                    loop_fn=lambda l: tuple(l.vert[vlay])[:3])

    def plank_wall(self, w, h, loc, mat, color_fn, rot=(0, 0, 0), holes=(), plank=(0.2, 0.32),
                   gap=0.014, push=0.025, top_fn=None, grime=True, ragged=0.03):
        """Vertical board siding in the XZ plane (x centred, z 0..h) facing -Y: each
        board is its own quad, slightly pushed out/tilted, with a gap so a dark
        backing box reads as the joints. Boards are cut around `holes` and to
        `top_fn(x)` (gables); bottoms are ragged by up to `ragged` m."""
        t = bmesh.new()
        lay = t.faces.layers.int.new("cid")
        keys = []
        edges = sorted({v for hh in holes for v in (hh[0], hh[2]) if -w / 2 < v < w / 2})
        x = -w / 2
        while x < w / 2 - 0.02:
            x2 = min(w / 2, x + random.uniform(*plank))
            if w / 2 - x2 < 0.08:
                x2 = w / 2
            for e in edges:            # boards stop exactly at door/window edges
                if x + 0.02 < e < x2:
                    x2 = e
                    break
            xc = (x + x2) / 2
            spans = [(random.uniform(0, ragged), h)]
            for hx0, hz0, hx1, hz1 in holes:
                if not (hx0 < xc < hx1):
                    continue
                new = []
                for s0, s1 in spans:
                    if s1 <= hz0 or s0 >= hz1:
                        new.append((s0, s1))
                        continue
                    if s0 < hz0:
                        new.append((s0, hz0))
                    if s1 > hz1:
                        new.append((hz1, s1))
                spans = new
            c = color_fn()
            g = gap / 2
            y = -random.uniform(0.0, push)
            tl = random.uniform(-0.006, 0.006)
            for s0, s1 in spans:
                ta = tb = s1
                if top_fn is not None:
                    ta, tb = min(s1, top_fn(x + g)), min(s1, top_fn(x2 - g))
                    if ta <= s0 + 0.02 and tb <= s0 + 0.02:
                        continue
                    ta, tb = max(ta, s0 + 0.02), max(tb, s0 + 0.02)
                vs = [t.verts.new((x + g, y + tl, s0)), t.verts.new((x2 - g, y - tl, s0)),
                      t.verts.new((x2 - g, y - tl, tb)), t.verts.new((x + g, y + tl, ta))]
                f = t.faces.new(vs)
                keys.append(c)
                f[lay] = len(keys) - 1
            x = x2
        self._merge(t, mat, (1, 1, 1), self.xf(loc, rot), None, 0.0, lambda f: keys[f[lay]], grime)

    def sheet(self, corners, nu, nv, mat, color_fn, sag=0.0, sag_fn=None, both=True, smooth=70,
              grime=False):
        """Bilinear cloth/canvas patch between corners (p00, p10, p01, p11) with nu x nv
        cells (in the current frame). `sag` pulls the interior down (-Z) by a sine bump;
        `sag_fn(u, v)` overrides that with any offset vector. `color_fn(u, v)` colours
        vertices (stripes, dirt). `both` adds the reversed side so the underside shows."""
        p00, p10, p01, p11 = (Vector(p) for p in corners)
        t = bmesh.new()
        vlay = t.verts.layers.float_color.new("vc")
        rows = []
        for j in range(nv + 1):
            v_ = j / nv
            row = []
            for i in range(nu + 1):
                u = i / nu
                p = (p00 * (1 - u) + p10 * u) * (1 - v_) + (p01 * (1 - u) + p11 * u) * v_
                if sag_fn is not None:
                    p = p + Vector(sag_fn(u, v_))
                elif sag:
                    p.z -= sag * math.sin(math.pi * u) * math.sin(math.pi * v_)
                vv = t.verts.new(p)
                vv[vlay] = (*color_fn(u, v_), 1.0)
                row.append(vv)
            rows.append(row)
        for j in range(nv):
            for i in range(nu):
                q = (rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i])
                t.faces.new(q)
                if both:
                    dup = [t.verts.new(v.co) for v in q]
                    for a, b in zip(dup, q):
                        a[vlay] = b[vlay]
                    t.faces.new(list(reversed(dup)))
        self._merge(t, mat, (1, 1, 1), None, smooth, 0.0, None, grime,
                    loop_fn=lambda l: tuple(l.vert[vlay])[:3])

    def mirror_x(self):
        """Mirror everything built so far across X=0, keeping outward normals and
        colours. Used for layout variants (door / chimney / shed swap sides)."""
        bmesh.ops.scale(self.bm, vec=(-1.0, 1.0, 1.0), verts=self.bm.verts[:])
        bmesh.ops.reverse_faces(self.bm, faces=self.bm.faces[:])

    def bounds(self):
        """((xmin, ymin, zmin), (xmax, ymax, zmax)) of everything built so far."""
        vs = [v.co for v in self.bm.verts]
        return (tuple(min(v[i] for v in vs) for i in range(3)),
                tuple(max(v[i] for v in vs) for i in range(3)))

    # --------------------------------------------------------------- finishing
    def tri_count(self):
        return sum(max(0, len(f.verts) - 2) for f in self.bm.faces)

    def build_object(self):
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.collection.objects.link(ob)
        for key, (i, m) in sorted(self.mats.items(), key=lambda kv: kv[1][0]):
            me.materials.append(m)
        me.validate()
        return ob

    def finish(self, preview_kind="ground", cam_dir=(1.1, -1.6, 0.75), fit=1.0,
               focus_z=None, extra_preview=None):
        tris = self.tri_count()
        args = [a for a in sys.argv[1:]]
        out = next((a for a in args if a.endswith(".glb")), f"{self.name}.glb")
        png = next((a for a in args if a.endswith(".png")), None)
        ob = self.build_object()
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=True,
                                  use_selection=True, export_vertex_color="MATERIAL")
        print(f"wrote {out}  triangles={tris}")
        import os
        if os.environ.get("RA_CAM"):   # detail shots: RA_CAM="x,y,z" RA_FIT=0.4 RA_FOCUS=z
            cam_dir = tuple(float(v) for v in os.environ["RA_CAM"].split(","))
            fit = float(os.environ.get("RA_FIT", fit))
            focus_z = float(os.environ["RA_FOCUS"]) if os.environ.get("RA_FOCUS") else focus_z
        if png:
            render_preview(ob, png, preview_kind, cam_dir, fit, focus_z, extra_preview)
        return ob


def render_preview(ob, png, kind="ground", cam_dir=(1.1, -1.6, 0.75), fit=1.0,
                   focus_z=None, extra=None):
    import addon_utils
    addon_utils.enable("cycles")
    sc = bpy.context.scene
    bb = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    lo = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
    hi = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
    ctr = (lo + hi) / 2
    if focus_z is not None:
        ctr.z = focus_z
    rad = (hi - lo).length / 2

    # Ground or water plane for context
    def plane(z, size, color, rough):
        bpy.ops.mesh.primitive_plane_add(size=size, location=(ctr.x, ctr.y, z))
        p = bpy.context.active_object
        m = bpy.data.materials.new("PreviewGround")
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (*srgb(color), 1)
        b.inputs["Roughness"].default_value = rough
        p.data.materials.append(m)
        return p
    if kind == "water":
        S = rad * 8
        shore = plane(0.0, S, (0.42, 0.53, 0.29), 1.0)
        shore.location.y = hi.y - 0.6 + S / 2
        w = plane(-0.6, S * 1.5, (0.20, 0.52, 0.58), 0.12)
        b = w.data.materials[0].node_tree.nodes["Principled BSDF"]
        b.inputs["Transmission Weight"].default_value = 0.75
        b.inputs["IOR"].default_value = 1.33
        bed = plane(-2.2, S * 1.5, (0.55, 0.52, 0.40), 1.0)
    else:
        plane(0.0, rad * 10, (0.42, 0.53, 0.29), 1.0)
    if extra:
        extra(ctr, rad)

    # Camera
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = 40
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    sc.collection.objects.link(cam)
    d = Vector(cam_dir).normalized()
    fov = 2 * math.atan(36 / 2 / cam_data.lens) * 0.75  # vertical-ish fov for 4:3
    dist = rad / math.tan(fov / 2) * 0.92 * fit
    cam.location = ctr + d * dist
    cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    cam_data.clip_end = dist * 20

    # Sun + sky
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 4.2
    sun.data.color = (1.0, 0.93, 0.82)
    sun.data.angle = math.radians(2.5)
    sun.rotation_euler = (math.radians(50), math.radians(8), math.radians(-35))
    sc.collection.objects.link(sun)
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*srgb((0.62, 0.80, 0.98)), 1)
    bg.inputs["Strength"].default_value = 1.1
    sc.world = world

    sc.render.engine = "CYCLES"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    try:
        sc.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    sc.cycles.max_bounces = 4
    sc.render.resolution_x = 800
    sc.render.resolution_y = 600
    sc.render.film_transparent = False
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass
    sc.render.filepath = png
    bpy.ops.render.render(write_still=True)
    print("preview", png)
