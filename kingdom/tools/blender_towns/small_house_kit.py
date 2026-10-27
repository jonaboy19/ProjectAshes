# Towns medieval pass: the small / poor house kit (docs/plans/TOWNS_MEDIEVAL_PASS.md).
# blender -b --factory-startup -P small_house_kit.py -- <out_dir>
# Narrow burgage houses (2.6-4.6 m street frontage, 2-3 storeys, jettied, gable to the street), hovels with a lean-to.
# Origin at the footprint centre on the ground; the street front (door) is +Y in Blender = +Z in Godot. Flat colour
# materials named by role (plaster / timber / thatch / shingle / boards / stone / dark): Style G gives them CC0 detail,
# weathering and moss. Poor variants: sagging roof ridge, missing-plaster patches, boarded windows, leaning posts.
import bpy, bmesh, sys, math, random
from mathutils import Vector, Matrix

out = sys.argv[sys.argv.index("--") + 1]
SIMPLE = False   # LOD1 pass: walls, roofs, chimneys and sills only (no frame, windows, shutters, patches)
MATS = {
    "RA_plaster": (0.93, 0.89, 0.79), "RA_plaster_dirty": (0.8, 0.75, 0.64), "RA_timber": (0.22, 0.15, 0.1),
    "RA_thatch": (0.62, 0.52, 0.32), "RA_shingle": (0.3, 0.27, 0.25), "RA_boards": (0.42, 0.33, 0.24),
    "RA_stone": (0.5, 0.48, 0.44), "RA_dark": (0.06, 0.05, 0.045), "RA_window": (0.07, 0.06, 0.05), "RA_kit": (1.0, 1.0, 1.0),
}


# Benchmark slice (AAA gate: no flat colours): 4 surfaces per house, each a Style G role with a CC0 real-scan detail texture;
# the part colours stay in the vertex colours (TK_ = town kit: StyleG reads the vertex colours of these as linear).
SURF = {"RA_plaster": "TK_plaster", "RA_plaster_dirty": "TK_plaster", "RA_stone": "TK_plaster", "RA_timber": "TK_timber",
        "RA_boards": "TK_timber", "RA_dark": "TK_timber", "RA_thatch": "TK_thatch", "RA_shingle": "TK_shingle", "RA_window": "TK_window"}
for _k in ("TK_plaster", "TK_timber", "TK_thatch", "TK_shingle", "TK_window"):
    MATS[_k] = (1.0, 1.0, 1.0) if _k != "TK_window" else (0.07, 0.06, 0.05)


def mat(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        c = MATS[name]
        bsdf.inputs["Base Color"].default_value = (c[0], c[1], c[2], 1.0)
        bsdf.inputs["Roughness"].default_value = 0.95
    return m


class B:
    def __init__(self, name):
        self.bm = bmesh.new()
        self.name = name
        self.mats = []

    def mi(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    def box(self, c, s, m, rot=0.0, tilt=0.0, roll=0.0):
        r = bmesh.ops.create_cube(self.bm, size=1.0)
        vs = r["verts"]
        M = (Matrix.Translation(Vector(c)) @ Matrix.Rotation(rot, 4, "Z") @ Matrix.Rotation(tilt, 4, "X")
             @ Matrix.Rotation(roll, 4, "Y") @ Matrix.Diagonal((s[0], s[1], s[2], 1.0)))
        bmesh.ops.transform(self.bm, matrix=M, verts=vs)
        idx = self.mi(m)
        for f in {f for v in vs for f in v.link_faces}:
            f.material_index = idx

    def poly(self, pts, m):
        vs = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(vs)
        f.material_index = self.mi(m)

    def gable_roof(self, w, d, z0, h, over, m, sag=0.0, wall="RA_plaster"):
        # ridge along Y, gable facing the street (+Y); two thick slabs; `sag` drops the ridge middle (old, poor roofs)
        hw = w * 0.5 + over
        hd = d * 0.5 + over
        t = 0.14
        n = 4
        for side in (-1, 1):
            for k in range(n):
                y0 = -hd + 2 * hd * k / n
                y1 = -hd + 2 * hd * (k + 1) / n
                s0 = sag * math.sin(math.pi * k / n)
                s1 = sag * math.sin(math.pi * (k + 1) / n)
                a = Vector((side * hw, y0, z0 - 0.05 - s0 * 0.3))
                b = Vector((0, y0, z0 + h - s0))
                c = Vector((0, y1, z0 + h - s1))
                dd = Vector((side * hw, y1, z0 - 0.05 - s1 * 0.3))
                top = [a, b, c, dd] if side > 0 else [dd, c, b, a]
                self.poly(top, m)
                self.poly([p + Vector((0, 0, -t)) for p in reversed(top)], m)
        for y in (-d * 0.5, d * 0.5):
            pts = [Vector((-w * 0.5, y, z0)), Vector((w * 0.5, y, z0)), Vector((0, y, z0 + h - 0.15))]
            self.poly(pts if y > 0 else list(reversed(pts)), wall)

    def finish(self):
        # iGPU draw-call budget: every part colour goes into vertex colours on ONE material (RA_kit); only the windows keep
        # their own material (RA_window, the night glow). 2 surfaces per house instead of 8.
        me = bpy.data.meshes.new(self.name)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        col = self.bm.loops.layers.color.new("Col")
        used = []
        for f in self.bm.faces:
            n = self.mats[f.material_index]
            c = MATS[n]
            for lp in f.loops:
                lp[col] = (c[0], c[1], c[2], 1.0)
            sn = SURF[n]
            if sn not in used:
                used.append(sn)
            f.material_index = used.index(sn)
        self.bm.to_mesh(me)
        # make "Col" the only, active and render colour attribute, so glTF COLOR_0 carries the part colours
        for ca in list(me.color_attributes):
            if ca.name != "Col":
                me.color_attributes.remove(ca)
        me.color_attributes.active_color_name = "Col"
        me.color_attributes.render_color_index = me.color_attributes.find("Col")
        for sn in used:
            me.materials.append(mat(sn))
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


def frame(b, w, z0, hgt, fy, rng, poor):
    if SIMPLE:
        return
    t = 0.16
    for x in (-w * 0.5 + 0.06, w * 0.5 - 0.06):
        b.box((x, fy, z0 + hgt * 0.5), (t, t, hgt), "RA_timber", roll=rng.uniform(-0.03, 0.03) if poor else 0.0)
    b.box((0, fy, z0 + 0.07), (w, t, 0.14), "RA_timber")
    b.box((0, fy, z0 + hgt - 0.08), (w + 0.1, t, 0.16), "RA_timber")
    if w > 3.0:
        b.box((0, fy, z0 + hgt * 0.5), (t * 0.9, t * 0.9, hgt), "RA_timber")
    # close studding (KCD / Kuttenberg street fronts): uprights every ~0.55 m and a mid rail, so no wall is a blank plane
    n = max(2, int(w / 0.55))
    for k in range(1, n):
        x = -w * 0.5 + w * k / n
        b.box((x, fy + 0.03, z0 + hgt * 0.5), (0.1, 0.08, hgt - 0.1), "RA_timber")     # proud of the plaster face
    b.box((0, fy + 0.03, z0 + hgt * 0.42), (w, 0.08, 0.11), "RA_timber")
    if rng.random() < 0.75:   # one diagonal brace
        L = math.hypot(w * 0.45, hgt * 0.9)
        ang = math.atan2(hgt * 0.9, w * 0.45) * rng.choice((-1, 1))
        b.box((rng.choice((-1, 1)) * w * 0.24, fy + 0.01, z0 + hgt * 0.5), (L, 0.12, 0.12), "RA_timber", roll=-ang)


def side_frame(b, d, z0, hgt, sx, y0, rng, poor, win=True):
    if SIMPLE:
        return
    # timber frame + a small window on a side wall (x = sx); a row hides it, an end-of-row house shows it
    t = 0.15
    sgn = 1 if sx > 0 else -1
    for y in (y0 - d * 0.5 + 0.08, y0 + d * 0.5 - 0.08, y0):
        b.box((sx, y, z0 + hgt * 0.5), (t, t, hgt), "RA_timber")
    b.box((sx, y0, z0 + 0.07), (t, d, 0.14), "RA_timber")
    b.box((sx, y0, z0 + hgt - 0.08), (t, d, 0.16), "RA_timber")
    b.box((sx, y0, z0 + hgt * 0.5), (t, d, 0.12), "RA_timber")
    n = max(2, int(d / 0.6))
    for k in range(1, n):
        b.box((sx, y0 - d * 0.5 + d * k / n, z0 + hgt * 0.5), (0.08, 0.09, hgt - 0.1), "RA_timber")
    if rng.random() < 0.8:
        L = math.hypot(d * 0.45, hgt * 0.45)
        b.box((sx, y0 - d * 0.25, z0 + hgt * 0.25), (0.12, L, 0.12), "RA_timber", tilt=math.atan2(hgt * 0.45, d * 0.45))
    if win:
        b.box((sx + sgn * 0.04, y0 + d * 0.22, z0 + hgt * 0.62), (0.06, 0.55, 0.6), "RA_window")
        b.box((sx + sgn * 0.08, y0 + d * 0.22, z0 + hgt * 0.62 - 0.34), (0.12, 0.7, 0.07), "RA_timber")


def window(b, x, fy, z, w, h, boarded):
    if SIMPLE:
        return
    b.box((x, fy + 0.04, z), (w, 0.06, h), "RA_window")
    b.box((x, fy + 0.09, z - h * 0.5 - 0.04), (w + 0.14, 0.14, 0.07), "RA_timber")
    if boarded:
        for k in range(3):
            b.box((x, fy + 0.11, z - h * 0.3 + k * h * 0.3), (w + 0.12, 0.04, 0.13), "RA_boards", roll=0.08 * (k - 1))
    else:
        for s in (-1, 1):
            b.box((x + s * (w * 0.5 + 0.17), fy + 0.08, z), (0.3, 0.04, h), "RA_boards")


def narrow(name, w, d, storeys, roof, poor, seed):
    rng = random.Random(seed)
    b = B(name)
    sh = 2.5
    b.box((0, 0, 0.2), (w, d, 0.4), "RA_stone")
    z = 0.4
    jet = 0.0
    for s in range(storeys):
        ww = w + 0.06 * s
        fy = d * 0.5 + jet
        wall = "RA_plaster_dirty" if poor or rng.random() < 0.35 else "RA_plaster"
        b.box((0, jet * 0.5, z + sh * 0.5), (ww - 0.04, d + jet - 0.04, sh), wall)
        frame(b, ww, z, sh, fy, rng, poor)
        for sx in (-ww * 0.5 + 0.02, ww * 0.5 - 0.02):
            side_frame(b, d + jet - 0.04, z, sh, sx, jet * 0.5, rng, poor, win=(s > 0 or rng.random() < 0.5))
        n = 1 if w < 3.3 else 2
        for k in range(n):
            x = 0.0 if n == 1 else (-w * 0.23 if k == 0 else w * 0.23)
            if s == 0 and (k == n - 1):
                b.box((x, fy + 0.05, z + 1.0), (0.95, 0.08, 2.0), "RA_boards")
                continue
            window(b, x, fy, z + sh * 0.56, 0.68, 0.85, poor and rng.random() < 0.5)
        if poor:
            for _ in range(2):
                b.box((rng.uniform(-w * 0.3, w * 0.3), fy + 0.03, z + rng.uniform(0.6, sh - 0.6)),
                      (rng.uniform(0.4, 0.9), 0.04, rng.uniform(0.3, 0.7)), "RA_boards")
        z += sh
        if s == 0 and storeys > 1:
            jet = 0.45
            b.box((0, d * 0.5 + 0.22, z - 0.06), (w + 0.1, 0.5, 0.14), "RA_timber")
    rh = max(2.3, w * 0.95) + rng.uniform(-0.2, 0.4)
    sag = rng.uniform(0.2, 0.45) if poor else rng.uniform(0.0, 0.12)
    b.gable_roof(w + 0.06 * storeys, d + jet, z, rh, 0.35, roof, sag, "RA_plaster_dirty" if poor else "RA_plaster")
    if rng.random() < 0.85:
        b.box((rng.uniform(-w * 0.2, w * 0.2), -d * 0.2, z + rh * 0.6), (0.55, 0.55, rh * 0.95), "RA_stone",
              rot=rng.uniform(-0.05, 0.05), roll=rng.uniform(-0.04, 0.04) if poor else 0.0)
    return b.finish()


def hovel(name, w, d, roof, seed, lean=False):
    rng = random.Random(seed)
    b = B(name)
    b.box((0, 0, 0.15), (w + 0.1, d + 0.1, 0.3), "RA_stone")
    h = 2.0
    b.box((0, 0, 0.3 + h * 0.5), (w, d, h), "RA_plaster_dirty", roll=rng.uniform(-0.015, 0.015))
    frame(b, w, 0.3, h, d * 0.5, rng, True)
    for sx in (-w * 0.5 + 0.02, w * 0.5 - 0.02):
        side_frame(b, d, 0.3, h, sx, 0.0, rng, True, win=rng.random() < 0.5)
    b.box((w * 0.18, d * 0.5 + 0.05, 1.2), (0.85, 0.08, 1.8), "RA_boards")
    window(b, -w * 0.25, d * 0.5, 1.5, 0.5, 0.5, rng.random() < 0.5)
    if lean:
        b.box((w * 0.5 + 0.8, 0, 0.9), (1.6, d * 0.8, 1.6), "RA_boards", roll=0.04)
        b.box((w * 0.5 + 0.85, 0, 1.78), (1.9, d * 0.95, 0.08), "RA_shingle", roll=-0.25)
    rh = max(1.9, w * 0.7)
    b.gable_roof(w, d, 2.3, rh, 0.5, roof, rng.uniform(0.3, 0.55), "RA_plaster_dirty")
    for _ in range(3):   # patched roof
        b.box((rng.uniform(-w * 0.25, w * 0.25), rng.uniform(-d * 0.3, d * 0.3), 2.3 + rh * 0.5),
              (0.7, 0.6, 0.05), "RA_boards", roll=0.7 * rng.choice((-1, 1)))
    return b.finish()


def export(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=f"{out}/{ob.name}.glb", use_selection=True, export_format="GLB",
                              export_yup=True, export_apply=True, export_vertex_color="ACTIVE")


bpy.ops.wm.read_factory_settings(use_empty=True)
kit = [
    narrow("house_narrow_a", 2.8, 6.0, 3, "RA_shingle", False, 1),
    narrow("house_narrow_b", 3.4, 6.5, 2, "RA_thatch", False, 2),
    narrow("house_narrow_c", 4.6, 7.0, 3, "RA_shingle", False, 3),
    narrow("house_narrow_poor_a", 2.6, 5.5, 2, "RA_thatch", True, 4),
    narrow("house_narrow_poor_b", 3.2, 5.8, 2, "RA_shingle", True, 5),
    hovel("house_hovel_a", 3.6, 4.4, "RA_thatch", 6),
    hovel("house_hovel_b", 3.0, 4.0, "RA_thatch", 7, lean=True),
]
for ob in kit:
    export(ob)
SIMPLE = True
bpy.ops.wm.read_factory_settings(use_empty=True)
lods = [
    narrow("house_narrow_a_lod1", 2.8, 6.0, 3, "RA_shingle", False, 1),
    narrow("house_narrow_b_lod1", 3.4, 6.5, 2, "RA_thatch", False, 2),
    narrow("house_narrow_c_lod1", 4.6, 7.0, 3, "RA_shingle", False, 3),
    narrow("house_narrow_poor_a_lod1", 2.6, 5.5, 2, "RA_thatch", True, 4),
    narrow("house_narrow_poor_b_lod1", 3.2, 5.8, 2, "RA_shingle", True, 5),
    hovel("house_hovel_a_lod1", 3.6, 4.4, "RA_thatch", 6),
    hovel("house_hovel_b_lod1", 3.0, 4.0, "RA_thatch", 7, lean=True),
]
for ob in lods:
    export(ob)
print("KIT_DONE", len(kit) + len(lods))
