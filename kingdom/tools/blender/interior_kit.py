"""Interior kit: shared builder for the enterable-building interiors of Rising Ashes
(bpy, Blender 5.x). Used by make_interior_<name>.py.

    blender -b --python make_interior_inn.py -- [--no-preview]

Every interior is ONE GLB in kingdom/assets/generated/interiors/ with two meshes:

- "Room": the timber-frame-and-plaster shell, the floor, the ceiling and all the
  custom furniture, built with ra_kit.Kit. Exactly 3 materials, shared with the
  village buildings: RA_Wood and RA_Plaster (vertex colour x the shared tiling
  detail textures in generated/village_tex/, referenced by URI, not embedded) and
  RA_Ember (plain emissive: fire, coals, candle flames, lantern cores).
  CC0 Quaternius Fantasy Props MegaKit pieces (tables, benches, shelves of
  bottles, beds, anvil...) are merged into this mesh too: their trim-sheet
  colours are sampled per face into the vertex colours and warm-graded to the
  village palette, so they cost no extra materials or textures.
- "Props": the existing village props (generated/props/*.glb: barrels, crates,
  sacks, woodpile, weapon rack, anvil stump, water trough...) joined into one
  mesh with their single shared material RA_Props (props_atlas.png by URI).

So an interior is 4 materials / 4 draw calls (+ characters).

Lighting is BAKED into the vertex colours (COLOR_0): ra_polish's ambient
occlusion + weathering, then a custom point-light bake (fireplace, forge, candles,
lanterns, windows) with ray-cast shadows. The Godot scene only adds a warm
ambient term and at most two unshadowed OmniLights (fire glow, flicker).

Coordinates: metres, Blender +Z up, origin at the centre of the ground-floor
floor. The entrance door is always in the FRONT wall (Blender -Y = Godot +Z).
Blender (x, y, z) -> Godot (x, z, -y).

finish() also writes the Godot scene kingdom/scenes/interiors/<name>_interior.tscn
(room instance, box colliders, spawn + NPC markers, exit door, lights,
environment, preview camera) and renders the previews
docs/kingdom/blender_previews/interior_<name>_a.png / _b.png.
"""
import os, sys, math, random, json, struct
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy, bmesh
import numpy as np
from mathutils import Vector, Matrix, Euler, noise
from mathutils.bvhtree import BVHTree
from ra_kit import Kit, hexc, vary, mix, srgb
import ra_polish as RP

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
KINGDOM = os.path.join(ROOT, "kingdom")
OUT_DIR = os.path.join(KINGDOM, "assets", "generated", "interiors")
SCENE_DIR = os.path.join(KINGDOM, "scenes", "interiors")
PREV_DIR = os.path.join(ROOT, "docs", "kingdom", "blender_previews")
PROPS_DIR = os.path.join(KINGDOM, "assets", "generated", "props")
MEGA_DIR = os.path.join(KINGDOM, "assets", "incoming", "quaternius", "fantasy-props-megakit", "Exports", "glTF")
DOOR_SCRIPT = "res://scripts/interiors/interior_door.gd"
ROOM_SCRIPT = "res://scripts/interiors/interior_room.gd"

# ------------------------------------------------------------------ palette (sRGB)
TIMBER = hexc("5c3c25")
TIMBER_D = hexc("452b1b")
OAK = hexc("94653d")
OAK_D = hexc("6e4a2c")
HONEY = hexc("b27d47")
PL1, PL2 = hexc("f0e1c0"), hexc("e2cda3")
FLOORS = [hexc("8d5f3b"), hexc("7b5234"), hexc("9c6b44"), hexc("6f4b30"), hexc("a4754b"), hexc("86583a")]
STONES = [hexc("857a6a"), hexc("948672"), hexc("766c60"), hexc("9c8e78"), hexc("7f7264"), hexc("8c7c66")]
FLAGS = [hexc("7d766b"), hexc("8a8274"), hexc("6f685e"), hexc("938a7a"), hexc("7a7166"), hexc("857c6c")]
IRON = hexc("2f2c2a")
LINEN = hexc("ece2cc")
WAX = hexc("efe3c2")
POTS = [hexc("a95f3a"), hexc("6f8a5a"), hexc("c89b55"), hexc("938b7c"), hexc("7d4b30"), hexc("5f7486")]
HERBS = [hexc("6d7f45"), hexc("8a8a55"), hexc("9278a8"), hexc("5f7040"), hexc("a8904a"), hexc("7c8a5a"),
         hexc("8f6f45"), hexc("a6a070")]
GLASS_C = hexc("f4f8fa")

WARM = (1.0, 0.62, 0.30)       # linear-ish light colours for the bake
CANDLE = (1.0, 0.70, 0.40)
DAY = (0.70, 0.82, 1.0)


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def j(a=0.01):
    return random.uniform(-a, a)


def to_godot(p):
    return (p[0], p[2], -p[1])


def yaw_toward(dx, dy):
    """Godot rotation.y whose -Z forward points along Blender direction (dx, dy)."""
    return math.atan2(-dx, dy)


C_MAT = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))


def gd_transform(M):
    """Blender 4x4 (or 3x3 + origin tuple) -> Godot Transform3D() text."""
    if isinstance(M, tuple):
        R, t = M
    else:
        R, t = M.to_3x3(), M.to_translation()
    Rg = C_MAT @ R @ C_MAT.transposed()
    tg = C_MAT @ Vector(t)
    vals = [Rg[i][jj] for i in range(3) for jj in range(3)] + list(tg)
    return "Transform3D(" + ", ".join(f"{v:.5g}" if abs(v) > 1e-9 else "0" for v in vals) + ")"


def gd_yaw_transform(pos, yaw):
    c, s = math.cos(yaw), math.sin(yaw)
    g = to_godot(pos)
    vals = [c, 0, s, 0, 1, 0, -s, 0, c, g[0], g[1], g[2]]
    return "Transform3D(" + ", ".join(f"{v:.5g}" if abs(v) > 1e-9 else "0" for v in vals) + ")"


def gd_color(c, a=1.0):
    return f"Color({c[0]:.4g}, {c[1]:.4g}, {c[2]:.4g}, {a:.4g})"


# ================================================================== the builder
class Interior:
    def __init__(self, name, seed=1, title=""):
        self.name = name
        self.title = title or name.title()
        self.k = Kit("Interior_" + name, seed=seed)
        k = self.k
        k.grime, k.grime_amt = 0.45, 0.1
        self.WOOD = k.material("Wood", rough=0.75)
        self.PL = k.material("Plaster", rough=0.92)
        self.GLOW = k.material("Ember", rough=0.9, emission=hexc("ff7424"), strength=2.6)
        self.atlas_props = []      # (file, loc, rot(euler), scale)
        self.colliders = []        # (Matrix world, size (x,y,z)) boxes in Blender space
        self.markers = []          # (name, pos, yaw_godot, meta dict)
        self.bake = []             # (pos, colour, energy, radius)
        self.rt_lights = []        # (name, pos, colour, energy, range, flicker)
        self.cams = []             # (suffix, loc, target, lens)
        self.exit_door = None      # (pos, size, yaw)
        self.spawn = None          # (pos, yaw)
        self.env = dict(ambient=(1.0, 0.90, 0.78), ambient_energy=0.9, bg=(0.035, 0.028, 0.022),
                        exposure=1.15)
        self.preview_ambient = 0.5
        self.levels = [0.0]
        self.cx = self.cy = self.z0 = 0.0
        self.notes = []
        self._tri = []
        self.stats = {}

    # ------------------------------------------------------------- bookkeeping
    def mark(self, label):
        self._tri.append((label, self.k.tri_count()))

    def collide(self, center, size, rz=0.0, rx=0.0, ry=0.0):
        M = Matrix.Translation(Vector(center)) @ Euler((rx, ry, rz)).to_matrix().to_4x4()
        self.colliders.append((M, tuple(size)))

    def collide_local(self, center, size, rz=0.0):
        """Collider given in the kit's current frame (push/pop)."""
        F = self.k.frames[-1]
        M = F @ Matrix.Translation(Vector(center)) @ Euler((0, 0, rz)).to_matrix().to_4x4()
        self.colliders.append((M, tuple(size)))

    def light(self, pos, colour=WARM, energy=1.0, radius=4.0):
        self.bake.append((Vector(self.k.world(pos)), colour, energy, radius))

    def npc(self, name, pos, face, look="Rogue_Hooded", height=1.75, anim="Idle", role=""):
        self.markers.append((name, tuple(pos), yaw_toward(*face), dict(look=look, height=height, anim=anim,
                                                                        role=role or name.lower())))

    def cam(self, suffix, loc, target, lens=24):
        self.cams.append((suffix, Vector(loc), Vector(target), lens))

    # ================================================================ shell
    def plaster(self, x0, x1, z0, z1, seed, step=0.5, col_fn=None):
        """Softly undulating plaster sheet in the local XZ plane facing -Y."""
        k = self.k
        nx = max(1, math.ceil((x1 - x0) / step))
        nz = max(1, math.ceil((z1 - z0) / step))
        t = bmesh.new()
        grid = []
        for jz in range(nz + 1):
            z = z0 + (z1 - z0) * jz / nz
            row = []
            for i in range(nx + 1):
                x = x0 + (x1 - x0) * i / nx
                n = noise.noise(Vector((x * 1.3, z * 1.3, seed)))
                n2 = noise.noise(Vector((x * 4.1, z * 4.1, seed + 5)))
                row.append(t.verts.new((x, -(0.006 + 0.009 * (n * 0.5 + 0.5) + 0.003 * n2), z)))
            grid.append(row)
        for jz in range(nz):
            for i in range(nx):
                t.faces.new((grid[jz][i], grid[jz][i + 1], grid[jz + 1][i + 1], grid[jz + 1][i]))
        fn = col_fn or self.plaster_col
        k._merge(t, self.PL, (1, 1, 1), None, 80, 0.0, None, False, loop_fn=lambda l: fn(l.vert.co))

    def plaster_col(self, p):
        n = noise.noise(p * 0.9 + Vector((3.1, 7.7, 1.3)))
        c = mix(PL1, PL2, clamp(0.5 + 0.6 * n))
        kk = 1 + 0.05 * noise.noise(p * 3.7 + Vector((9, 2, 5)))
        c = tuple(x * kk for x in c)
        if noise.noise(p * 0.55 + Vector((1, 1, 20))) > 0.38:
            c = mix(c, hexc("c9b186"), 0.25)
        zl = p.z - self.floor_z(p)
        if zl < 0.7:
            c = mix(c, hexc("8a7458"), 0.4 * (1 - zl / 0.7) ** 1.5)
        s = self.soot(p)
        return mix(c, hexc("3a2f27"), s) if s > 0 else c

    def floor_z(self, p):
        return max([z for z in self.levels if z <= p.z + 0.05] or [0.0])

    def soot(self, p):
        return 0.0

    def post(self, x, z0, z1, w=0.18, d=0.1, c=None):
        self.k.box((w, d, z1 - z0), (x + j(0.006), -d / 2 + 0.004, (z0 + z1) / 2), self.WOOD,
                   vary(c or TIMBER, 0.1, 0.02), bevel=0.014, rot=(j(0.006), j(0.006), 0))

    def rail(self, x0, x1, z, h=0.14, d=0.1, c=None):
        self.k.box((x1 - x0, d, h), ((x0 + x1) / 2, -d / 2 + 0.002, z), self.WOOD, vary(c or TIMBER, 0.1, 0.02),
                   bevel=0.014, rot=(0, j(0.004), 0))

    def brace(self, a, b):
        self.k.beam((a[0], -0.045, a[1]), (b[0], -0.045, b[1]), 0.09, self.WOOD, TIMBER, bevel=0.012, width=0.14)

    def wall(self, p0, p1, z0, H, holes=(), seed=1.0, stone_base=0.0, posts=1.3, braces=True, mid=1.1,
             collide=True, thick=0.3):
        """Timber-frame plaster wall from floor point p0 to p1 (room on the left of p0->p1,
        i.e. walk clockwise seen from above). holes: (x0, x1, hz0, hz1) along the wall
        (x from p0, z above z0). stone_base: fieldstone wainscot height."""
        k = self.k
        p0, p1 = Vector((p0[0], p0[1], 0)), Vector((p1[0], p1[1], 0))
        d = p1 - p0
        L = d.length
        ang = math.atan2(d.y, d.x)
        k.push((p0.x, p0.y, z0), (0, 0, ang))
        holes = sorted(holes)
        # --- plaster pieces (vertical strips around the holes)
        zb = stone_base
        xs = [0.0]
        strips = []
        cur = 0.0
        for (hx0, hx1, hz0, hz1) in holes:
            if hx0 > cur:
                strips.append((cur, hx0, [(zb, H)]))
            spans = []
            if hz0 > zb + 0.02:
                spans.append((zb, hz0))
            if hz1 < H - 0.02:
                spans.append((max(hz1, zb), H))
            strips.append((hx0, hx1, spans))
            cur = hx1
        if cur < L:
            strips.append((cur, L, [(zb, H)]))
        for (a, b, spans) in strips:
            for (za, zz) in spans:
                if zz - za > 0.01 and b - a > 0.01:
                    self.plaster(a, b, za, zz, seed)
        if stone_base > 0:
            sh = [(hx0, 0, hx1, hz1) for (hx0, hx1, hz0, hz1) in holes if hz0 < stone_base]
            k.box((L, 0.1, stone_base), (L / 2, 0.06, stone_base / 2), self.PL, hexc("2e2924"), var=0)
            k.grid_wall(L, stone_base, (L / 2, -0.005, 0), self.PL,
                        lambda: vary(random.choice(STONES), 0.08, 0.03), bw=0.55, bh=0.3, gap=0.03, push=0.03,
                        holes=[(h[0] - L / 2, h[1], h[2] - L / 2, h[3]) for h in sh])
            k.box((L, 0.14, 0.08), (L / 2, -0.05, stone_base + 0.02), self.WOOD, TIMBER_D, bevel=0.012)
        # --- timber frame
        def free(x, z, pad=0.12):
            for (hx0, hx1, hz0, hz1) in holes:
                if hx0 - pad < x < hx1 + pad and hz0 - pad < z < hz1 + pad:
                    return False
            return True
        if stone_base <= 0:
            segs = self._free_spans(0, L, holes, 0.08)
            for a, b in segs:
                self.rail(a, b, 0.08, h=0.16)
        self.rail(0, L, H - 0.11, h=0.22)
        px = [0.35]
        x = 0.35
        while x < L - 0.6:
            x += posts * random.uniform(0.85, 1.15)
            if x < L - 0.35:
                px.append(x)
        px.append(L - 0.35)
        # posts at hole edges
        edge_posts = []
        for (hx0, hx1, hz0, hz1) in holes:
            edge_posts += [hx0 - 0.09, hx1 + 0.09]
        px = [p for p in px if all(abs(p - e) > 0.35 for e in edge_posts)] + edge_posts
        px = sorted(p for p in px if 0.05 < p < L - 0.05)
        zp0 = max(0.16, stone_base + 0.06)
        for p in px:
            if all(not (hx0 - 0.02 < p < hx1 + 0.02) for (hx0, hx1, hz0, hz1) in holes):
                self.post(p, zp0, H - 0.22)
        # mid rail between posts, skipping holes
        if mid:
            for a, b in self._free_spans(0, L, [h for h in holes if h[2] < mid < h[3] + 0.1], 0.1):
                if b - a > 0.2:
                    self.rail(a, b, mid)
        # head / sill rails for holes
        for (hx0, hx1, hz0, hz1) in holes:
            if hz1 < H - 0.3:
                self.rail(hx0 - 0.1, hx1 + 0.1, hz1 + 0.07, h=0.14)
            if hz0 > 0.3:
                self.rail(hx0 - 0.1, hx1 + 0.1, hz0 - 0.06, h=0.12)
        # braces in some bays between posts
        if braces:
            for a, b in zip(px, px[1:]):
                if b - a < 0.7 or random.random() < 0.35:
                    continue
                za, zz = (mid + 0.08 if mid else zp0), H - 0.24
                if not all(free(x_, z_) for x_ in (a, (a + b) / 2, b) for z_ in (za, (za + zz) / 2, zz)):
                    continue
                if random.random() < 0.5:
                    self.brace((a + 0.09, za), (b - 0.09, zz))
                else:
                    self.brace((b - 0.09, za), (a + 0.09, zz))
        if collide:
            self.collide_local((L / 2, thick / 2 - 0.02, H / 2), (L + thick, thick, H))
        k.pop()
        return ang

    @staticmethod
    def _free_spans(a, b, holes, pad):
        spans = [(a, b)]
        for (hx0, hx1, *_rest) in holes:
            new = []
            for (x0, x1) in spans:
                if x1 <= hx0 - pad or x0 >= hx1 + pad:
                    new.append((x0, x1))
                    continue
                if x0 < hx0 - pad:
                    new.append((x0, hx0 - pad))
                if x1 > hx1 + pad:
                    new.append((hx1 + pad, x1))
            spans = new
        return spans

    def room(self, W, D, H, doors=None, windows=None, stone_base=0.0, posts=1.3, z0=0.0, skip=(), cx=0.0, cy=0.0):
        """Four walls around x in [cx-W/2, cx+W/2], y in [cy-D/2, cy+D/2], floor at z0. doors/windows:
        dict wall -> list of (center along the wall in world x or y, width, z0, z1) (z relative to
        the floor). Walls: 'back' (+Y), 'right' (+X), 'front' (-Y), 'left' (-X). Makes this room the
        active one for wall_frame()/window()/door()/lantern()..."""
        hw, hd = W / 2, D / 2
        self.W, self.D, self.H, self.cx, self.cy, self.z0 = W, D, H, cx, cy, z0
        if z0 not in self.levels:
            self.levels.append(z0)
        x0, x1, y0, y1 = cx - hw, cx + hw, cy - hd, cy + hd
        spec = {"back": ((x0, y1), (x1, y1), lambda c: c - x0),
                "right": ((x1, y1), (x1, y0), lambda c: y1 - c),
                "front": ((x1, y0), (x0, y0), lambda c: x1 - c),
                "left": ((x0, y0), (x0, y1), lambda c: c - y0)}
        openings = {}
        for wname, lst in list((doors or {}).items()) + list((windows or {}).items()):
            for (c, w, a, b) in lst:
                x = spec[wname][2](c)
                openings.setdefault(wname, []).append((x - w / 2, x + w / 2, a, b))
        for i, wname in enumerate(("back", "right", "front", "left")):
            if wname in skip:
                continue
            p0, p1, _ = spec[wname]
            self.wall(p0, p1, z0, H, openings.get(wname, []), seed=i + 1.0 + z0, stone_base=stone_base, posts=posts)
        for sx in (-1, 1):
            for sy in (-1, 1):
                self.k.box((0.24, 0.24, H), (cx + sx * (hw - 0.1), cy + sy * (hd - 0.1), z0 + H / 2), self.WOOD,
                           TIMBER_D, bevel=0.02)

    def wall_frame(self, wname):
        """push() the frame of wall `wname` of the active room: local x along the wall, local -y
        into the room, origin on the floor at the wall's start. Returns a mapper
        world-coordinate-along-wall -> local x."""
        hw, hd = self.W / 2, self.D / 2
        x0, x1, y0, y1, z0 = self.cx - hw, self.cx + hw, self.cy - hd, self.cy + hd, self.z0
        if wname == "back":
            self.k.push((x0, y1, z0), (0, 0, 0))
            return lambda c: c - x0
        if wname == "right":
            self.k.push((x1, y1, z0), (0, 0, -math.pi / 2))
            return lambda c: y1 - c
        if wname == "front":
            self.k.push((x1, y0, z0), (0, 0, math.pi))
            return lambda c: x1 - c
        self.k.push((x0, y0, z0), (0, 0, math.pi / 2))
        return lambda c: c - y0

    # ------------------------------------------------------------- openings
    def window(self, wname, c, w=1.0, z0=1.1, z1=2.1, day=0.55, sill_deco=True):
        """Leaded window in wall `wname` at world coordinate c (the hole must have been
        passed to room()). Adds a cool daylight bake light just inside."""
        k = self.k
        m = self.wall_frame(wname)
        x = m(c)
        k.box((w + 0.12, 0.3, 0.07), (x, -0.05, z0 - 0.02), self.WOOD, OAK, bevel=0.012)
        for sx in (-1, 1):
            k.box((0.05, 0.3, z1 - z0), (x + sx * (w / 2 + 0.01), 0.12, (z0 + z1) / 2), self.PL, hexc("dccaa2"),
                  var=0.03)
        k.box((w, 0.3, 0.05), (x, 0.12, z1 + 0.01), self.PL, hexc("dccaa2"), var=0.03)
        gy = 0.2
        k.quad(w, z1 - z0, (x, gy, (z0 + z1) / 2), self.PL, GLASS_C, var=0, grime=False)
        for xx in (x - w / 2 + 0.03, x, x + w / 2 - 0.03):
            k.box((0.05, 0.05, z1 - z0), (xx, gy - 0.03, (z0 + z1) / 2), self.WOOD, TIMBER_D, grime=False)
        for zz in (z0 + 0.03, (z0 + z1) / 2, z1 - 0.03):
            k.box((w, 0.05, 0.05), (x, gy - 0.03, zz), self.WOOD, TIMBER_D, grime=False)
        for s in (-1, 1):
            for off in (-w / 4, w / 4):
                k.box((min(0.6, w / 2) * 0.9, 0.012, 0.012), (x + off, gy - 0.01, (z0 + z1) / 2), self.PL, IRON,
                      rot=(0, s * math.pi / 4, 0), grime=False, var=0)
        if day > 0:
            self.light((x, -0.5, (z0 + z1) / 2), DAY, day, 4.5)
        if sill_deco and random.random() < 0.7:
            self.lathe([(0, 0), (0.05, 0), (0.06, 0.07), (0.05, 0.13), (0.04, 0.13), (0, 0.02)],
                       (x + random.uniform(-w / 3, w / 3), -0.1, z0 + 0.015), self.PL, random.choice(POTS))
        k.pop()

    def door(self, wname, c, w=1.2, h=2.2, arch=False):
        """Closed plank door (room side) in wall `wname`; the hole must be in room()."""
        k = self.k
        m = self.wall_frame(wname)
        x0, x1 = m(c) - w / 2, m(c) + w / 2
        n = max(4, round(w / 0.19))
        pw = w / n
        for i in range(n):
            k.box((pw - 0.008, 0.05, h - j(0.01)), (x0 + pw * (i + 0.5), 0.02, h / 2), self.WOOD,
                  vary(hexc("7a5234"), 0.08, 0.02), bevel=0.006, var=0)
        for zz in (0.35, h - 0.4):
            k.box((w - 0.08, 0.035, 0.13), ((x0 + x1) / 2, -0.025, zz), self.WOOD, hexc("6a452b"), bevel=0.01)
            k.box((w * 0.5, 0.012, 0.05), (x1 - w * 0.25, -0.05, zz), self.PL, IRON, var=0)
        k.beam((x0 + 0.1, -0.025, 0.42), (x1 - 0.1, -0.025, h - 0.47), 0.035, self.WOOD, hexc("6a452b"), bevel=0.008,
               width=0.12)
        k.ring(0.045, 0.062, 0.014, (x0 + 0.14, -0.06, 1.05), self.PL, IRON, segs=10)
        for sx in (x0 - 0.08, x1 + 0.08):
            k.box((0.16, 0.16, h + 0.1), (sx, -0.04, (h + 0.1) / 2), self.WOOD, TIMBER_D, bevel=0.015)
        k.box((w + 0.32, 0.18, 0.2), ((x0 + x1) / 2, -0.04, h + 0.1), self.WOOD, TIMBER_D, bevel=0.015)
        k.box((w + 0.2, 0.5, 0.04), ((x0 + x1) / 2, -0.25, 0.005), self.PL, hexc("8a8274"), var=0.03)  # threshold
        k.pop()

    # ============================================================== floors / ceilings
    def planks(self, x0, x1, y0, y1, z=0.0, along="y", palette=FLOORS, dark=None):
        """Plank floor (top at z). dark(x, y) -> 0..1 darkening (worn/sooty areas)."""
        k = self.k
        if along == "y":
            x = x0
            while x < x1 - 0.02:
                w = random.uniform(0.2, 0.3)
                if x1 - (x + w) < 0.12:
                    w = x1 - x
                y = y0
                n = max(1, int((y1 - y0) / 1.7))
                cuts = sorted(random.uniform(y0 + 0.5, y1 - 0.5) for _ in range(n)) if y1 - y0 > 1.2 else []
                for yb in cuts + [y1]:
                    L = yb - y
                    if L < 0.05:
                        continue
                    c = vary(random.choice(palette), 0.07, 0.03)
                    if dark:
                        c = mix(c, hexc("4a3222"), dark(x + w / 2, y + L / 2))
                    k.box((w - 0.008, L - 0.008, 0.04), (x + w / 2, y + L / 2, z - 0.02 + j(0.003)), self.WOOD, c,
                          bevel=0.0, var=0, rot=(j(0.004), j(0.004), j(0.002)))
                    y = yb
                x += w
        else:
            y = y0
            while y < y1 - 0.02:
                w = random.uniform(0.2, 0.3)
                if y1 - (y + w) < 0.12:
                    w = y1 - y
                x = x0
                n = max(1, int((x1 - x0) / 1.7))
                cuts = sorted(random.uniform(x0 + 0.5, x1 - 0.5) for _ in range(n)) if x1 - x0 > 1.2 else []
                for xb in cuts + [x1]:
                    L = xb - x
                    if L < 0.05:
                        continue
                    c = vary(random.choice(palette), 0.07, 0.03)
                    if dark:
                        c = mix(c, hexc("4a3222"), dark(x + L / 2, y + w / 2))
                    k.box((L - 0.008, w - 0.008, 0.04), (x + L / 2, y + w / 2, z - 0.02 + j(0.003)), self.WOOD, c,
                          bevel=0.0, var=0, rot=(j(0.004), j(0.004), j(0.002)))
                    x = xb
                y += w
        self.collide(((x0 + x1) / 2, (y0 + y1) / 2, z - 0.25), (x1 - x0, y1 - y0, 0.5))

    def flagstones(self, x0, x1, y0, y1, z=0.0, size=0.62, dark=None):
        k = self.k
        k.box((x1 - x0, y1 - y0, 0.06), ((x0 + x1) / 2, (y0 + y1) / 2, z - 0.035), self.PL, hexc("3b352f"), var=0)
        y = y0
        row = 0
        while y < y1 - 0.05:
            h = size * random.uniform(0.6, 1.2)
            if y1 - (y + h) < size * 0.4:
                h = y1 - y
            x = x0 - (size * random.uniform(0.2, 0.7) if row % 2 else 0)
            while x < x1 - 0.05:
                w = size * random.uniform(0.55, 1.5)
                a, b = max(x, x0), min(x + w, x1)
                if b - a > 0.08:
                    c = vary(random.choice(FLAGS), 0.14, 0.04)
                    if dark:
                        c = mix(c, hexc("2e2822"), dark((a + b) / 2, y + h / 2))
                    k.box((b - a - 0.03, h - 0.03, 0.05), ((a + b) / 2, y + h / 2, z - 0.015 + j(0.006)), self.PL, c,
                          var=0, rot=(j(0.01), j(0.01), j(0.01)))
                x += w
            y += h
            row += 1
        self.collide(((x0 + x1) / 2, (y0 + y1) / 2, z - 0.25), (x1 - x0, y1 - y0, 0.5))

    def ceiling(self, x0, x1, y0, y1, H, beams_x=(), joist_step=0.75, holes=(), board_c=hexc("6d4a30"),
                collide=True):
        """Joists along Y, summer beams along X at y in beams_x, boards on top (z=H).
        holes: (hx0, hx1, hy0, hy1) stairwell openings left free."""
        k = self.k
        for yy in beams_x:
            k.beam((x0, yy + j(0.02), H - 0.29 + j(0.01)), (x1, yy + j(0.02), H - 0.29 + j(0.01)), 0.26, self.WOOD,
                   TIMBER_D, bevel=0.022, width=0.26)
        n = max(2, round((x1 - x0) / joist_step))
        for i in range(n):
            xj = x0 + (i + 0.5) * (x1 - x0) / n + j(0.03)
            spans = [(y0, y1)]
            for (hx0, hx1, hy0, hy1) in holes:
                if hx0 - 0.1 < xj < hx1 + 0.1:
                    spans = [s for sp in spans for s in ((sp[0], min(sp[1], hy0)), (max(sp[0], hy1), sp[1]))
                             if s[1] - s[0] > 0.1]
            for (a, b) in spans:
                k.box((0.12, b - a, 0.15), (xj, (a + b) / 2, H - 0.085), self.WOOD, TIMBER, bevel=0.012,
                      rot=(j(0.003), 0, j(0.004)),
                      color_fn=lambda f, base=vary(TIMBER, 0.1): mix(base, hexc("2a1c13"), self.soot(f.calc_center_median())))
        yb = y0
        while yb < y1 - 0.02:
            w = min(random.uniform(0.2, 0.28), y1 - yb)
            xb = x0
            cuts = [random.uniform(x0 + 1, x1 - 1)] if x1 - x0 > 3 else []
            for xe in cuts + [x1]:
                segs = [(xb, xe)]
                for (hx0, hx1, hy0, hy1) in holes:
                    if hy0 - 0.01 < yb + w / 2 < hy1 + 0.01:
                        segs = [s for sg in segs for s in ((sg[0], min(sg[1], hx0)), (max(sg[0], hx1), sg[1]))
                                if s[1] - s[0] > 0.05]
                for (a, b) in segs:
                    base = vary(board_c, 0.1, 0.03)
                    k.box((b - a - 0.006, w - 0.008, 0.03), ((a + b) / 2, yb + w / 2, H + 0.015), self.WOOD, base, var=0,
                          color_fn=lambda f, bb=base: mix(bb, hexc("2a1c13"), self.soot(f.calc_center_median())))
                xb = xe
            yb += w
        if collide:
            self.collide(((x0 + x1) / 2, (y0 + y1) / 2, H + 0.25), (x1 - x0, y1 - y0, 0.4))

    # ============================================================== small shapes
    def lathe(self, profile, loc, mat, color, segs=12, smooth=50, rot=(0, 0, 0), var=0.05, grime=False,
              noise_amt=0.0, noise_scale=6.0, bend=(0.0, 0.0), scale=1.0):
        k = self.k
        t = bmesh.new()
        rings = []
        for r, z in profile:
            r, z = r * scale, z * scale
            if r < 1e-5:
                rings.append([t.verts.new((0, 0, z))])
            else:
                rings.append([t.verts.new((math.cos(a) * r, math.sin(a) * r, z))
                              for a in (jj / segs * math.tau for jj in range(segs))])
        for i in range(len(rings) - 1):
            A, B = rings[i], rings[i + 1]
            if len(A) == 1 and len(B) == 1:
                continue
            for jj in range(segs):
                j2 = (jj + 1) % segs
                if len(A) == 1:
                    t.faces.new((A[0], B[j2], B[jj]))
                elif len(B) == 1:
                    t.faces.new((A[jj], A[j2], B[0]))
                else:
                    t.faces.new((A[jj], A[j2], B[j2], B[jj]))
        zmax = max(z for _, z in profile) * scale or 1.0
        off = random.uniform(0, 100)
        for v in t.verts:
            f = v.co.z / zmax
            if noise_amt:
                d = Vector((v.co.x, v.co.y, 0))
                if d.length > 1e-6:
                    v.co += d.normalized() * noise.noise(v.co * noise_scale + Vector((off, 0, 0))) * noise_amt
            v.co.x += bend[0] * f * f
            v.co.y += bend[1] * f * f
        k._merge(t, mat, vary(color, var) if var else color, k.xf(loc, rot), smooth, 0.02, None, grime)

    def pot(self, x, y, z, s, kind=None, c=None, cloth=None):
        kind = random.randrange(3) if kind is None else kind
        c = c or random.choice(POTS)
        prof = ([(0, 0), (0.6, 0), (0.95, 0.35), (1.0, 0.6), (0.7, 0.95), (0.72, 1.05), (0.62, 1.05), (0, 0.95)],
                [(0, 0), (0.55, 0), (0.7, 0.3), (0.72, 1.1), (0.55, 1.4), (0.6, 1.5), (0, 1.5)],
                [(0, 0), (0.6, 0), (0.85, 0.4), (0.7, 0.9), (0.4, 1.2), (0.45, 1.35), (0.35, 1.35), (0, 1.25)])[kind]
        self.lathe([(r * s, zz * s) for r, zz in prof], (x, y, z), self.PL, c, segs=10)
        if cloth or (cloth is None and random.random() < 0.4):
            top = (1.05, 1.5, 1.35)[kind] * s
            self.k.cyl(0.66 * s, 0.1 * s, (x, y, z + top), self.PL, hexc("d8cba8"), segs=10, r2=0.5 * s)

    def bottle(self, x, y, z, s=1.0, c=None, cork=True):
        c = c or random.choice([hexc("3f7a5a"), hexc("7a3f5a"), hexc("3f5a8a"), hexc("8a6a2a"), hexc("5a8a3f"),
                                hexc("a33f2c"), hexc("6a4a8a")])
        self.lathe([(0, 0), (0.045, 0), (0.05, 0.1), (0.02, 0.15), (0.017, 0.21), (0, 0.21)],
                   (x, y, z), self.PL, c, segs=6, scale=s)

    def mug(self, x, y, z, s=1.0):
        self.lathe([(0, 0), (0.04, 0), (0.045, 0.1), (0.04, 0.1), (0.036, 0.015), (0, 0.015)], (x, y, z), self.WOOD,
                   vary(hexc("8a5a34"), 0.1), segs=8, scale=s)
        a = random.uniform(0, math.tau)
        self.k.tube([(x + math.cos(a) * 0.043 * s, y + math.sin(a) * 0.043 * s, z + 0.08 * s),
                     (x + math.cos(a) * 0.07 * s, y + math.sin(a) * 0.07 * s, z + 0.055 * s),
                     (x + math.cos(a) * 0.043 * s, y + math.sin(a) * 0.043 * s, z + 0.025 * s)],
                    [0.008 * s] * 3, self.WOOD, hexc("6a4428"), segs=4, point_end=False)

    def plate(self, x, y, z, s=1.0, food=True):
        self.lathe([(0, 0), (0.08, 0), (0.11, 0.018), (0.1, 0.02), (0.075, 0.006), (0, 0.006)], (x, y, z), self.PL,
                   hexc("d9c9a3"), segs=10, scale=s)
        if food:
            fc = random.choice([hexc("b87a3c"), hexc("8a4a2a"), hexc("c9a24a")])
            self.k.sphere(1.0, (x, y, z + 0.03 * s), self.PL, fc, scale=(0.06 * s, 0.045 * s, 0.028 * s), subdiv=1,
                          noise_amt=0.1, grime=False)

    def candle(self, x, y, z, h=0.14, holder=True, energy=0.35, radius=2.6):
        k = self.k
        r = random.uniform(0.02, 0.026)
        if holder:
            self.lathe([(0, 0), (0.055, 0), (0.06, 0.01), (0.052, 0.014), (0, 0.014)], (x, y, z), self.PL,
                       hexc("8e8a84"), segs=10)
            z += 0.014
        k.cyl(r, h, (x, y, z), self.PL, vary(WAX, 0.03), segs=8, grime=False)
        fz = z + h + 0.008
        self.lathe([(0, 0), (0.008, 0.005), (0.011, 0.015), (0.009, 0.028), (0.005, 0.04), (0, 0.052)], (x, y, fz),
                   self.GLOW, hexc("ffc060"), segs=6, smooth=80)
        if energy:
            self.light((x, y, fz + 0.03), CANDLE, energy, radius)

    def lantern(self, wname, c, z=2.0, energy=0.7, radius=4.5):
        """Iron wall lantern on a bracket, glowing core."""
        k = self.k
        m = self.wall_frame(wname)
        x = m(c)
        k.box((0.08, 0.04, 0.2), (x, -0.02, z + 0.35), self.PL, IRON, var=0)
        k.beam((x, -0.02, z + 0.4), (x, -0.32, z + 0.4), 0.025, self.PL, IRON, bevel=0)
        k.beam((x, -0.02, z + 0.28), (x, -0.25, z + 0.4), 0.018, self.PL, IRON, bevel=0)
        cy = -0.32
        k.box((0.1, 0.1, 0.03), (x, cy, z + 0.35), self.PL, IRON, var=0)
        self.lathe([(0, 0), (0.1, 0), (0.02, 0.07), (0, 0.07)], (x, cy, z + 0.365), self.PL, IRON, segs=4,
                   rot=(0, 0, math.pi / 4))
        k.box((0.16, 0.16, 0.03), (x, cy, z + 0.03), self.PL, IRON, var=0)
        for sx in (-1, 1):
            for sy in (-1, 1):
                k.box((0.018, 0.018, 0.3), (x + sx * 0.07, cy + sy * 0.07, z + 0.19), self.PL, IRON, var=0)
        k.box((0.12, 0.12, 0.26), (x, cy, z + 0.18), self.GLOW, hexc("ffc070"), var=0, grime=False)
        k.pop()
        p = self._wall_point(wname, c, 0.34, z + 0.2)
        self.bake.append((p, CANDLE, energy, radius))
        return p

    def _wall_point(self, wname, c, inset, z):
        hw, hd = self.W / 2, self.D / 2
        x0, x1, y0, y1 = self.cx - hw, self.cx + hw, self.cy - hd, self.cy + hd
        z += self.z0
        return Vector({"back": (c, y1 - inset, z), "front": (c, y0 + inset, z), "left": (x0 + inset, c, z),
                       "right": (x1 - inset, c, z)}[wname])

    def chandelier(self, x, y, H, r=0.55, n=6, drop=1.0, energy=1.5, radius=7.0):
        """Wagon-wheel chandelier on chains with candles."""
        k = self.k
        z = H - drop
        k.ring(r - 0.05, r + 0.04, 0.06, (x, y, z), self.WOOD, TIMBER_D, rot=(math.pi / 2, 0, 0), segs=16)
        for i in range(4):
            a = i / 4 * math.pi
            k.box((2 * r, 0.05, 0.05), (x, y, z), self.WOOD, TIMBER_D, rot=(0, 0, a))
        for i in range(3):
            a = i / 3 * math.tau
            k.beam((x + math.cos(a) * r * 0.9, y + math.sin(a) * r * 0.9, z + 0.03), (x, y, z + 0.7), 0.012, self.PL,
                   IRON, bevel=0)
        k.beam((x, y, z + 0.7), (x, y, H), 0.02, self.PL, IRON, bevel=0)
        for i in range(n):
            a = i / n * math.tau + 0.2
            self.candle(x + math.cos(a) * r, y + math.sin(a) * r, z + 0.03, h=random.uniform(0.08, 0.14), holder=False,
                        energy=0)
        self.light((x, y, z + 0.2), CANDLE, energy, radius)

    def rug(self, x, y, a, b, rings, rot=0.0, rect=False):
        k = self.k
        t = bmesh.new()
        lay = t.faces.layers.int.new("cid")
        keys = []
        if rect:
            nr = len(rings)
            for ri in range(nr):
                f0, f1 = ri / nr, (ri + 1) / nr
                for (sx, sy) in ((1, 0), (0, 1), (-1, 0), (0, -1)):
                    pass
            # concentric rectangles as frames
            prev = None
            for ri in range(nr, 0, -1):
                f = ri / nr
                q = [t.verts.new((sx * a * f, sy * b * f, 0.014)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
                if prev is None:
                    outer = q
                else:
                    for i in range(4):
                        fc = t.faces.new((prev[i], prev[(i + 1) % 4], q[(i + 1) % 4], q[i]))
                        keys.append(vary(rings[nr - ri - 1], 0.04))
                        fc[lay] = len(keys) - 1
                prev = q
            fc = t.faces.new(prev)
            keys.append(vary(rings[-1], 0.04))
            fc[lay] = len(keys) - 1
            ring = outer
            SEG = 4
        else:
            SEG = 28
            ctr = t.verts.new((0, 0, 0.014))
            prev = None
            for ri in range(1, len(rings) + 1):
                f = ri / len(rings)
                ring = []
                for s in range(SEG):
                    an = s / SEG * math.tau
                    wob = 1 + 0.015 * noise.noise(Vector((math.cos(an) * 2, math.sin(an) * 2, ri)))
                    ring.append(t.verts.new((math.cos(an) * a * f * wob, math.sin(an) * b * f * wob, 0.014)))
                for s in range(SEG):
                    s2 = (s + 1) % SEG
                    fc = t.faces.new((ctr, ring[s], ring[s2])) if prev is None else \
                        t.faces.new((prev[s], ring[s], ring[s2], prev[s2]))
                    keys.append(vary(rings[ri - 1], 0.05))
                    fc[lay] = len(keys) - 1
                prev = ring
        low = [t.verts.new((v.co.x * 1.0, v.co.y * 1.0, 0.002)) for v in ring]
        for s in range(SEG):
            s2 = (s + 1) % SEG
            fc = t.faces.new((ring[s], low[s], low[s2], ring[s2]))
            keys.append(hexc("2e241e"))
            fc[lay] = len(keys) - 1
        bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
        for f in t.faces:
            if f.normal.z < -0.5:
                f.normal_flip()
        k._merge(t, self.PL, (1, 1, 1), k.xf((x, y, 0), (0, 0, rot)), None, 0.0, lambda f: keys[f[lay]], False)

    def herbs(self, x, y, ztop, n=3, colours=HERBS):
        k = self.k
        L = random.uniform(0.05, 0.2)
        k.box((0.007, 0.007, L), (x, y, ztop - L / 2), self.PL, hexc("c9b78e"), var=0, grime=False)
        top = ztop - L
        c = random.choice(colours)
        k.cyl(0.02, 0.04, (x, y, top - 0.04), self.PL, hexc("8a6a40"), segs=6, grime=False)
        hl = random.uniform(0.24, 0.36)
        for s_ in range(n):
            a_ = s_ / n * math.tau + random.uniform(0, 1)
            sp = random.uniform(0.03, 0.06)
            tip = Vector((x + math.cos(a_) * sp, y + math.sin(a_) * sp, top - 0.03 - hl * random.uniform(0.8, 1.05)))
            cc = vary(mix(c, random.choice(colours), 0.3), 0.1)
            k.tube([(x, y, top - 0.03), (x + math.cos(a_) * sp * 0.5, y + math.sin(a_) * sp * 0.5, top - 0.03 - hl * 0.5),
                    tip], [0.006, 0.022, 0.028], self.PL, cc, segs=5, point_end=False)
            k.sphere(0.03, tip, self.PL, mix(cc, (0.12, 0.1, 0.05), 0.2), scale=(1, 1, 1.4), subdiv=0,
                     noise_amt=0.012, grime=False, rot=(0, 0, a_))

    def banner(self, wname, c, z_top, w=0.8, h=1.6, cloth=hexc("a83a2c"), trim=hexc("d9b04a"), emblem="cross",
               emblem_c=None):
        """Hanging wall banner with a pointed tail and an emblem (cross, star, anvil, leaf)."""
        k = self.k
        m = self.wall_frame(wname)
        x = m(c)
        emblem_c = emblem_c or trim
        k.box((w + 0.2, 0.06, 0.06), (x, -0.08, z_top), self.WOOD, TIMBER_D, bevel=0.01)
        for sx in (-1, 1):
            k.sphere(0.04, (x + sx * (w / 2 + 0.12), -0.08, z_top), self.PL, trim, subdiv=1, grime=False)
        pts = [(-w / 2, 0), (w / 2, 0), (w / 2, -h), (0, -h - w * 0.35), (-w / 2, -h)]
        self.cloth_sheet(x, -0.065, z_top - 0.03, w, h, w * 0.35, cloth)
        tb = 0.05
        for (a, b) in zip(pts, pts[1:] + pts[:1]):
            if a[1] == 0 and b[1] == 0:
                continue
            k.beam((x + a[0], -0.088, z_top - 0.03 + a[1]), (x + b[0], -0.088, z_top - 0.03 + b[1]), 0.012, self.PL,
                   trim, bevel=0, width=tb)
        cz = z_top - 0.03 - h * 0.45
        e = w * 0.32
        if emblem == "cross":
            k.box((e * 0.35, 0.02, e * 2), (x, -0.1, cz), self.PL, emblem_c, var=0)
            k.box((e * 1.6, 0.02, e * 0.35), (x, -0.1, cz + e * 0.3), self.PL, emblem_c, var=0)
        elif emblem == "star":
            sp = []
            for i in range(8):
                an = i / 8 * math.tau + math.pi / 2
                rr = e * (1.15 if i % 2 == 0 else 0.3)
                sp.append((math.cos(an) * rr, math.sin(an) * rr))
            k.prism(sp, 0.02, (x, -0.1, cz), self.PL, emblem_c, var=0)
            k.ring(e * 0.55, e * 0.68, 0.02, (x, -0.1, cz), self.PL, emblem_c, segs=16)
        elif emblem == "anvil":
            k.prism([(-e, 0.2 * e), (e * 1.1, 0.2 * e), (e * 0.5, -0.15 * e), (e * 0.3, -0.5 * e), (e * 0.6, -0.8 * e),
                     (-e * 0.6, -0.8 * e), (-e * 0.3, -0.5 * e), (-e * 0.45, -0.15 * e), (-e * 1.2, 0.05 * e)],
                    0.02, (x, -0.1, cz + 0.2 * e), self.PL, emblem_c, var=0)
        elif emblem == "leaf":
            k.box((e * 0.5, 0.02, e * 1.8), (x, -0.1, cz), self.PL, emblem_c, var=0)
            k.box((e * 1.8, 0.02, e * 0.5), (x, -0.1, cz), self.PL, emblem_c, var=0)
        k.pop()

    def cloth_sheet(self, x, y, ztop, w, h, tail, colour, nx=4):
        """Hanging cloth facing -Y (banner body): a subdivided sheet with a pointed tail and
        soft folds, so the vertex AO / light bake has interior vertices to work with."""
        k = self.k
        t = bmesh.new()
        nz = max(3, round(h / 0.22))
        rows = []
        for iz in range(nz + 1):
            rows.append([(-w / 2 + w * ix / nx, -h * iz / nz) for ix in range(nx + 1)])
        nt = 3
        for it in range(1, nt + 1):
            f = it / nt
            hw_ = w / 2 * (1 - f) + 1e-4
            rows.append([(-hw_ + 2 * hw_ * ix / nx, -h - tail * f) for ix in range(nx + 1)])
        grid = [[t.verts.new((px, -0.008 * math.sin((px / w + 0.5) * math.pi * 2) - 0.003 * math.sin(pz * 5), pz))
                 for (px, pz) in r] for r in rows]
        for iz in range(len(grid) - 1):
            for ix in range(nx):
                t.faces.new((grid[iz][ix], grid[iz][ix + 1], grid[iz + 1][ix + 1], grid[iz + 1][ix]))
        bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
        for f in t.faces:
            if f.normal.y > 0:
                f.normal_flip()
        k._merge(t, self.PL, vary(colour, 0.02), k.xf((x, y, ztop)), 60, 0.02, None, False)

    # ============================================================== furniture
    def table(self, x, y, L=1.8, W=0.8, h=0.76, rot=0.0, top_c=OAK, leg_c=TIMBER, collide=True):
        k = self.k
        k.push((x, y, 0), (0, 0, rot))
        n = max(2, round(W / 0.26))
        for i in range(n):
            k.box((L + j(0.01), W / n - 0.006, 0.05), (j(0.008), -W / 2 + (i + 0.5) * W / n, h - 0.025), self.WOOD,
                  vary(top_c, 0.08, 0.03), bevel=0.01, var=0, rot=(j(0.004), j(0.004), 0))
        for sx in (-1, 1):
            k.box((0.09, W - 0.12, 0.06), (sx * (L / 2 - 0.2), 0, h - 0.08), self.WOOD, leg_c, bevel=0.01)
            for sy in (-1, 1):
                k.beam((sx * (L / 2 - 0.2), sy * (W / 2 - 0.1), 0), (sx * (L / 2 - 0.22), sy * (W / 2 - 0.12), h - 0.05),
                       0.07, self.WOOD, leg_c, bevel=0.012)
            k.box((0.05, W - 0.2, 0.06), (sx * (L / 2 - 0.2), 0, 0.2), self.WOOD, leg_c, bevel=0.01)
        k.box((L - 0.45, 0.05, 0.07), (0, 0, 0.2), self.WOOD, leg_c, bevel=0.01)
        if collide:
            self.collide_local((0, 0, h / 2), (L, W, h))
        k.pop()

    def bench(self, x, y, L=1.6, h=0.45, rot=0.0, c=OAK_D, collide=True):
        k = self.k
        k.push((x, y, 0), (0, 0, rot))
        k.box((L, 0.3, 0.05), (0, 0, h - 0.025), self.WOOD, vary(c, 0.08), bevel=0.01)
        for sx in (-1, 1):
            k.prism([(-0.13, 0), (0.13, 0), (0.1, h - 0.05), (-0.1, h - 0.05)], 0.05, (sx * (L / 2 - 0.15), 0, 0),
                    self.WOOD, c, rot=(0, 0, math.pi / 2), bevel=0.006)
        k.box((L - 0.35, 0.04, 0.06), (0, 0, 0.16), self.WOOD, c, bevel=0.008)
        if collide:
            self.collide_local((0, 0, h / 2), (L, 0.34, h))
        k.pop()

    def stool(self, x, y, h=0.46, r=0.17):
        k = self.k
        for a in range(3):
            ang = a / 3 * math.tau + 0.3
            k.beam((x + math.cos(ang) * r * 1.1, y + math.sin(ang) * r * 1.1, 0),
                   (x + math.cos(ang) * r * 0.55, y + math.sin(ang) * r * 0.55, h - 0.04), 0.04, self.WOOD, TIMBER,
                   bevel=0.01)
        k.cyl(r, 0.05, (x, y, h - 0.05), self.WOOD, vary(OAK, 0.08), segs=10, smooth=40)

    def chair(self, x, y, rot=0.0, c=OAK_D):
        """Simple ladder-back chair; its back is at local +Y (faces -Y)."""
        k = self.k
        k.push((x, y, 0), (0, 0, rot))
        k.box((0.44, 0.42, 0.04), (0, 0, 0.45), self.WOOD, vary(c, 0.08), bevel=0.008)
        for sx in (-1, 1):
            k.box((0.04, 0.04, 0.45), (sx * 0.19, -0.18, 0.225), self.WOOD, c, var=0.04)
            k.box((0.045, 0.045, 1.0), (sx * 0.19, 0.18, 0.5), self.WOOD, c, var=0.04)
        for zz in (0.7, 0.85, 0.98):
            k.box((0.36, 0.03, 0.06), (0, 0.18, zz), self.WOOD, c, var=0.05)
        k.pop()

    def quilt(self, x0, x1, y0, y1, z, patches, border=hexc("3a3f5c"), ov=0.3, rr=0.06, nu=14, nv=16):
        """Draped patchwork quilt in the current frame (falls over x0/x1/y0 edges)."""
        k = self.k
        t = bmesh.new()
        lay = t.faces.layers.int.new("cid")
        keys = []
        grid = []
        for jv in range(nv + 1):
            v = (y0 - ov) + (y1 - y0 + ov) * jv / nv
            row = []
            for iu in range(nu + 1):
                u = (x0 - ov) + (x1 - x0 + 2 * ov) * iu / nu
                dx, dxl, dy = max(0.0, u - x1), max(0.0, x0 - u), max(0.0, y0 - v)
                ox, oy = dx - dxl, -dy
                d = math.hypot(ox, oy)
                px, py, pz = min(max(u, x0), x1), min(max(v, y0), y1), z
                n = noise.noise(Vector((u * 5, v * 5, 3.3)))
                if d > 1e-6:
                    nx_, ny_ = ox / d, oy / d
                    arcL = rr * math.pi / 2
                    if d < arcL:
                        out, down = rr * math.sin(d / rr), rr * (1 - math.cos(d / rr))
                    else:
                        out, down = rr, rr + (d - arcL)
                    fold = 0.018 * math.sin((u + v) * 22) * clamp((d - arcL) / 0.1)
                    px += nx_ * (out + fold * 0.6) - ny_ * fold * 0.3
                    py += ny_ * (out + fold * 0.6) + nx_ * fold * 0.3
                    pz -= down
                else:
                    e = min(u - x0, x1 - u, v - y0, y1 - v)
                    pz += 0.014 * n + 0.03 * clamp(e / 0.3)
                row.append((t.verts.new((px, py, pz)), u, v, d))
            grid.append(row)
        for jv in range(nv):
            for iu in range(nu):
                a, b, c2, d2 = grid[jv][iu], grid[jv][iu + 1], grid[jv + 1][iu + 1], grid[jv + 1][iu]
                f = t.faces.new((a[0], b[0], c2[0], d2[0]))
                uc, vc = (a[1] + c2[1]) / 2, (a[2] + c2[2]) / 2
                dd = (a[3] + b[3] + c2[3] + d2[3]) / 4
                if dd > 0.24:
                    col = border
                else:
                    pi_, pj_ = math.floor((uc - x0) / 0.275), math.floor((vc - y0) / 0.3)
                    col = patches[(pi_ * 3 + pj_ * 5 + (pi_ * pj_) % 3) % len(patches)]
                keys.append(vary(col, 0.03))
                f[lay] = len(keys) - 1
        bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
        for f in t.faces:
            if f.normal.z < -0.3 and f.calc_center_median().z > z - 0.02:
                f.normal_flip()
        k._merge(t, self.PL, (1, 1, 1), None, 70, 0.0, lambda f: keys[f[lay]], False)

    def bed(self, x, y, rot=0.0, w=1.2, l=2.1, patches=None, border=hexc("3a3f5c"), frame=OAK, pillows=1,
            posts=True):
        """Wooden bed, head at local +Y. Quilt with patches (or plain if one colour)."""
        k = self.k
        k.push((x, y, 0), (0, 0, rot))
        x0, x1, y0, y1 = -w / 2, w / 2, -l / 2, l / 2
        hp = 1.15 if posts else 0.9
        for (px, py, ph) in ((x0 + 0.05, y1 - 0.05, hp), (x1 - 0.05, y1 - 0.05, hp), (x0 + 0.05, y0 + 0.05, 0.72),
                             (x1 - 0.05, y0 + 0.05, 0.72)):
            k.box((0.09, 0.09, ph), (px, py, ph / 2), self.WOOD, frame, bevel=0.015)
            k.sphere(0.055, (px, py, ph + 0.035), self.WOOD, frame, subdiv=1, scale=(1, 1, 0.8))
        for sx in (x0 + 0.05, x1 - 0.05):
            k.box((0.06, l - 0.1, 0.16), (sx, 0, 0.32), self.WOOD, vary(frame, 0.06), bevel=0.012)
        k.box((w - 0.08, 0.05, 0.5), (0, y1 - 0.05, 0.72), self.WOOD, vary(frame, 0.06), bevel=0.012)
        k.box((w - 0.08, 0.05, 0.26), (0, y0 + 0.05, 0.47), self.WOOD, vary(frame, 0.06), bevel=0.012)
        k.box((w - 0.28, 0.012, 0.3), (0, y1 - 0.08, 0.72), self.WOOD, mix(frame, hexc("4a2e1c"), 0.3), var=0.02)
        k.box((w - 0.08, l - 0.08, 0.22), (0, 0.02, 0.47), self.PL, hexc("d9ccae"), bevel=0.06)
        for i in range(pillows):
            px = 0 if pillows == 1 else (-w / 4 if i == 0 else w / 4)
            k.sphere(1.0, (px, y1 - 0.25, 0.64), self.PL, LINEN, scale=(w / (2.6 if pillows == 1 else 5.2), 0.17, 0.08),
                     subdiv=2, noise_amt=0.06, grime=False)
        patches = patches or [hexc("a3453a"), hexc("c8963e"), hexc("3f5a86"), hexc("7d9460"), hexc("e6d8bb"),
                              hexc("b0603a"), hexc("6b4a6e"), hexc("d7b06a")]
        self.quilt(x0 + 0.05, x1 - 0.05, y0 + 0.05, y1 - 0.55, 0.585, patches, border=border, nu=12, nv=14)
        k.box((w - 0.06, 0.14, 0.035), (0.03, y1 - 0.5, 0.615), self.PL, LINEN, bevel=0.015, grime=False)
        self.collide_local((0, 0, 0.35), (w, l, 0.7))
        k.pop()

    def chest(self, x, y, rot=0.0, w=0.9, d=0.5, h=0.5, c=hexc("7a5234")):
        k = self.k
        k.push((x, y, 0), (0, 0, rot))
        k.box((w, d, h * 0.72), (0, 0, h * 0.36), self.WOOD, c, bevel=0.015)
        k.box((w + 0.02, d + 0.02, h * 0.28), (0, 0, h * 0.72 + h * 0.14), self.WOOD, vary(c, 0.08), bevel=0.03)
        for sx in (-0.34, 0.34):
            k.box((0.06, d + 0.035, h + 0.01), (sx * w, 0, h / 2), self.PL, IRON, var=0)
        k.box((0.08, 0.02, 0.1), (0, -d / 2 - 0.012, h * 0.7), self.PL, hexc("8a7a4a"), var=0)
        self.collide_local((0, 0, h / 2), (w, d, h))
        k.pop()

    def shelf_unit(self, wname, c, w=1.4, h=2.2, depth=0.36, levels=(0.45, 0.95, 1.45, 1.95), items="mixed",
                   c_wood=OAK_D):
        """Free-standing open shelf unit against wall `wname` (sides, back boards, shelves)
        filled per level: items is one kind or a list per level (pots/bottles/books/jars/mixed/None)."""
        k = self.k
        m = self.wall_frame(wname)
        x = m(c)
        y = -depth / 2 - 0.02
        for sx in (-1, 1):
            k.box((0.05, depth, h), (x + sx * (w / 2 - 0.025), y, h / 2), self.WOOD, c_wood, bevel=0.01)
        k.box((w, 0.02, h - 0.05), (x, -0.03, h / 2), self.WOOD, mix(c_wood, hexc("3a2616"), 0.3), var=0.03)
        k.box((w + 0.06, depth + 0.04, 0.05), (x, y, h + 0.02), self.WOOD, c_wood, bevel=0.01)
        k.box((w - 0.1, 0.04, 0.12), (x, y - depth / 2 + 0.03, 0.06), self.WOOD, c_wood, bevel=0.008)
        for i, z in enumerate(levels):
            k.box((w - 0.1, depth - 0.02, 0.035), (x, y, z), self.WOOD, vary(OAK, 0.06), bevel=0.006)
            kind = items[i] if isinstance(items, (list, tuple)) else items
            if kind is None:
                continue
            zt = z + 0.018
            xx = x - w / 2 + 0.1
            while xx < x + w / 2 - 0.12:
                kd = kind if kind != "mixed" else random.choice(["pots", "bottles", "bottles", "books", "jars"])
                yy = y + j(0.04)
                if kd == "pots":
                    s = random.uniform(0.06, 0.1)
                    if xx + 2 * s > x + w / 2 - 0.08:
                        break
                    self.pot(xx + s, yy, zt, s)
                    xx += 2.2 * s + 0.03
                elif kd == "bottles":
                    for bb in range(random.randint(2, 4)):
                        sc = random.uniform(0.7, 1.15)
                        if xx + 0.1 > x + w / 2 - 0.08:
                            break
                        self.bottle(xx + 0.05, yy + j(0.06), zt, sc)
                        xx += 0.1 * sc + 0.012
                    xx += 0.04
                elif kd == "jars":
                    s = random.uniform(0.05, 0.07)
                    if xx + 2 * s > x + w / 2 - 0.08:
                        break
                    self.pot(xx + s, yy, zt, s, kind=1, c=random.choice([hexc("c9d8c0"), hexc("d8cfb0"), hexc("b8c9c0"),
                                                                         hexc("a8b890")]), cloth=True)
                    xx += 2 * s + 0.04
                elif kd == "books":
                    for bi in range(random.randint(3, 7)):
                        bh = random.uniform(0.18, 0.28)
                        bw = random.uniform(0.035, 0.06)
                        if xx + bw > x + w / 2 - 0.08:
                            break
                        k.box((bw, 0.2, bh), (xx + bw / 2, yy, zt + bh / 2), self.PL,
                              random.choice([hexc("7a2e24"), hexc("2e4a6a"), hexc("5a6a2e"), hexc("6a4a2a"),
                                             hexc("8a6a3a")]), rot=(0, j(0.05), 0), var=0.05)
                        xx += bw + 0.004
                    xx += 0.05
        self.collide_local((x, y, h / 2), (w, depth, h))
        k.pop()

    def shelf(self, wname, c, z, L=1.4, depth=0.28, items="pots", n=None):
        """Wall shelf with brackets; items: pots | bottles | books | jars | mixed | None."""
        k = self.k
        m = self.wall_frame(wname)
        x = m(c)
        k.box((L, depth, 0.035), (x, -depth / 2 - 0.01, z), self.WOOD, vary(OAK, 0.06), bevel=0.008)
        for xx in (x - L / 2 + 0.15, x + L / 2 - 0.15):
            k.prism([(0, 0), (depth - 0.06, 0), (0, -0.2)], 0.035, (xx, -0.02, z - 0.018), self.WOOD, TIMBER,
                    rot=(0, 0, -math.pi / 2), bevel=0.006)
        zt = z + 0.018
        xx = x - L / 2 + 0.1
        while xx < x + L / 2 - 0.1:
            kind = items if items != "mixed" else random.choice(["pots", "bottles", "books", "jars"])
            yy = -depth / 2 + j(0.03)
            if kind == "pots":
                s = random.uniform(0.06, 0.1)
                self.pot(xx + s, yy, zt, s)
                xx += 2.2 * s + 0.04
            elif kind == "bottles":
                for bb in range(random.randint(2, 4)):
                    s = random.uniform(0.7, 1.15)
                    self.bottle(xx, yy + j(0.05), zt, s)
                    xx += 0.11 * s + 0.01
                xx += 0.05
            elif kind == "jars":
                s = random.uniform(0.05, 0.07)
                self.pot(xx + s, yy, zt, s, kind=1, c=random.choice([hexc("c9d8c0"), hexc("d8cfb0"), hexc("b8c9c0")]),
                         cloth=True)
                xx += 2 * s + 0.05
            elif kind == "books":
                nb = random.randint(3, 7)
                for bi in range(nb):
                    bh = random.uniform(0.18, 0.26)
                    bw = random.uniform(0.035, 0.06)
                    k.box((bw, 0.17, bh), (xx + bw / 2, yy, zt + bh / 2), self.PL,
                          random.choice([hexc("7a2e24"), hexc("2e4a6a"), hexc("5a6a2e"), hexc("6a4a2a"), hexc("8a6a3a")]),
                          rot=(0, j(0.06), 0), var=0.05)
                    xx += bw + 0.004
                xx += 0.06
            else:
                xx += 0.3
        k.pop()

    def fireplace(self, wname, c, width=1.8, H=None, sootfn=True, logs=True, energy=2.2, radius=7.0,
                  hood=True, stone_top=1.25):
        """Stone hearth against wall `wname` at world coordinate c: breast, firebox with
        fire (flames, embers glow), oak mantel, plastered smoke hood to the ceiling."""
        k = self.k
        H = H or self.H
        m = self.wall_frame(wname)
        cx = m(c)
        k.push((cx, 0, 0))
        BX, BY, BTOP = width / 2, -0.55, stone_top
        OX, OZ = min(0.62, width * 0.3), 0.92
        MORTAR = hexc("3a332c")

        def stone():
            cc = random.choice(STONES)
            if random.random() < 0.1:
                cc = mix(cc, hexc("6d5a48"), 0.35)
            return vary(cc, 0.08, 0.03)
        for (xa, xb, za, zb) in ((-BX + 0.02, -OX, 0, BTOP), (OX, BX - 0.02, 0, BTOP), (-OX, OX, OZ, BTOP)):
            k.box((xb - xa, 0.5, zb - za), ((xa + xb) / 2, BY + 0.3, (za + zb) / 2), self.PL, MORTAR, var=0)
        k.box((2 * OX, 0.1, OZ), (0, -0.02, OZ / 2), self.PL, hexc("1d1814"), var=0)
        k.grid_wall(2 * OX, OZ - 0.1, (0, -0.07, 0.1), self.PL,
                    lambda: vary(mix(random.choice(STONES), hexc("1a1511"), 0.75), 0.2), bw=0.3, bh=0.18, gap=0.02,
                    push=0.02, grime=False)
        for sx in (-1, 1):
            k.push((sx * OX, -0.3, 0.1), (0, 0, sx * math.pi / 2))
            k.grid_wall(0.5, OZ - 0.1, (0, 0, 0), self.PL,
                        lambda: vary(mix(random.choice(STONES), hexc("1a1511"), 0.7), 0.2), bw=0.25, bh=0.18, gap=0.02,
                        push=0.015, grime=False)
            k.pop()
        k.box((2 * OX, 0.5, 0.03), (0, -0.3, OZ - 0.01), self.PL, hexc("15110e"), var=0)
        k.box((2 * OX + 0.02, 0.5, 0.1), (0, -0.3, 0.05), self.PL, hexc("4a443e"), var=0.05)
        rows = [0.0, 0.24, 0.47, 0.7, OZ, 1.1, BTOP]
        for r in range(len(rows) - 1):
            za, zb = rows[r], rows[r + 1]
            if r == 4:
                spans = [(-BX, -OX - 0.1), (-OX - 0.1, OX + 0.1), (OX + 0.1, BX)]
            elif zb <= OZ + 1e-6:
                spans = []
                for (a, b) in ((-BX, -OX), (OX, BX)):
                    if r % 2 == 0:
                        spans.append((a, b))
                    else:
                        mm = (a + b) / 2 + j(0.05)
                        spans += [(a, mm), (mm, b)]
            else:
                xs = [-BX]
                while xs[-1] < BX - 0.4:
                    xs.append(xs[-1] + random.uniform(0.28, 0.45))
                xs.append(BX)
                spans = list(zip(xs[:-1], xs[1:]))
            for (a, b) in spans:
                outer = abs(a + BX) < 1e-6 or abs(b - BX) < 1e-6
                dep = 0.58 if outer else random.uniform(0.1, 0.14)
                cy = BY - 0.03 + dep / 2
                col = mix(stone(), hexc("2f2822"), 0.25) if r == 4 and a < 0 < b else stone()
                k.box((b - a - 0.025, dep, zb - za - 0.025), ((a + b) / 2, cy, (za + zb) / 2), self.PL, col,
                      bevel=0.025, jitter=0.006, rot=(j(0.012), j(0.012), j(0.01)), var=0)
        xs = [-BX - 0.15, -BX * 0.33, BX * 0.4, BX + 0.15]
        for (xa, xb) in zip(xs, xs[1:]):
            k.box((xb - xa - 0.02, 0.5, 0.09), ((xa + xb) / 2, BY - 0.25, 0.035), self.PL, vary(hexc("7a746b"), 0.08),
                  bevel=0.02, jitter=0.004, rot=(j(0.006), j(0.006), j(0.01)))
        k.box((width + 0.36, 0.36, 0.17), (0, BY + 0.14, BTOP + 0.085), self.WOOD, hexc("4d3120"), bevel=0.025)
        if hood:
            t = bmesh.new()
            bmesh.ops.create_cube(t, size=1.0)
            for v in t.verts:
                top = v.co.z > 0
                hw = width * 0.34 if top else width * 0.52
                y0 = -0.38 if top else -0.53
                v.co = Vector((math.copysign(hw, v.co.x), y0 if v.co.y < 0 else 0.0, H if top else BTOP + 0.17))
            bmesh.ops.bevel(t, geom=[e for e in t.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 0.5], offset=0.05,
                            segments=2, affect='EDGES')
            bmesh.ops.subdivide_edges(t, edges=[e for e in t.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 0.5],
                                      cuts=4)
            k._merge(t, self.PL, (1, 1, 1), None, 60, 0.0, None, False,
                     loop_fn=lambda l: mix(self.plaster_col(l.vert.co), hexc("2c241e"),
                                          0.15 + 0.3 * clamp((H - l.vert.co.z) / 1.6)))
        # fire
        FY, FZ = -0.3, 0.1
        for sx in (-1, 1):
            k.box((0.03, 0.4, 0.03), (sx * 0.2, FY, FZ + 0.06), self.PL, IRON, var=0)
            k.box((0.03, 0.03, 0.2), (sx * 0.2, FY - 0.19, FZ + 0.1), self.PL, IRON, var=0)
        k.sphere(0.36, (0, FY + 0.02, FZ - 0.01), self.PL, hexc("58514b"), scale=(1.0, 0.55, 0.12), subdiv=1,
                 noise_amt=0.02, grime=False)
        CHAR = hexc("2b1d14")
        k.log((-0.36, FY - 0.1, 0.19), (0.34, FY + 0.06, 0.2), 0.06, self.WOOD, hexc("4a3321"), segs=7,
              end_color=hexc("c46a2c"), grime=False, zfn=lambda cc, z: mix(cc, CHAR, 0.6))
        k.log((-0.3, FY + 0.1, 0.2), (0.36, FY - 0.08, 0.19), 0.055, self.WOOD, hexc("553a25"), segs=7,
              end_color=hexc("d9782f"), grime=False, zfn=lambda cc, z: mix(cc, CHAR, 0.5))
        for i in range(14):
            a = random.uniform(0, math.tau)
            rr = random.uniform(0, 1) ** 0.6
            s = random.uniform(0.022, 0.045)
            col = random.choice([hexc("c8380c"), hexc("d85010"), hexc("a02408"), hexc("e0681a"), hexc("7a1a06")])
            k.sphere(s, (math.cos(a) * rr * 0.34, FY + math.sin(a) * rr * 0.16, FZ + 0.025 + (1 - rr) * 0.03), self.GLOW,
                     col, scale=(1.2, 1.0, 0.6), subdiv=0, noise_amt=s * 0.3, rot=(0, 0, a), grime=False, smooth=None)
        FLAME = [(0, 0), (0.55, 0.04), (0.9, 0.16), (1.0, 0.3), (0.78, 0.5), (0.45, 0.72), (0.18, 0.9), (0, 1.0)]
        for (dx, dy, hh, rr) in ((0.0, 0.0, 0.44, 0.09), (-0.13, 0.03, 0.31, 0.075), (0.14, -0.02, 0.34, 0.075),
                                 (-0.24, 0.02, 0.2, 0.055), (0.25, 0.04, 0.21, 0.055)):
            bend = (j(0.06) - dx * 0.25, j(0.03))
            self.lathe([(r * rr, z * hh) for r, z in FLAME], (dx, FY + dy, FZ + 0.1), self.GLOW, hexc("ff8a2a"),
                       segs=6, smooth=85, noise_amt=0.2 * rr, noise_scale=9, bend=bend)
        if logs:
            for i, (lx, lz) in enumerate(((-BX - 0.5, 0.06), (-BX - 0.35, 0.06), (-BX - 0.2, 0.06), (-BX - 0.425, 0.17),
                                          (-BX - 0.275, 0.17), (-BX - 0.35, 0.28))):
                k.log((lx + j(0.01), -0.05, lz + j(0.01)), (lx + j(0.02), -0.49, lz + j(0.01)), 0.065, self.WOOD,
                      random.choice([hexc("6b4a30"), hexc("7a5638"), hexc("5e422c")]), segs=7,
                      end_color=hexc("c9a070"), noise_amt=0.012)
        k.pop()
        fire = Vector(k.world((cx, -0.75, 0.55)))
        self.collide_local((cx, -0.3, BTOP / 2 + 0.3), (width + 0.1, 0.62, BTOP + 0.6))
        k.pop()
        self.bake.append((fire, WARM, energy, radius))
        self.bake.append((fire + Vector((0, 0, -0.3)), (1.0, 0.45, 0.16), energy * 0.5, radius * 0.5))
        return fire

    # ============================================================== imported pieces
    def prop(self, name, loc, rz=0.0, s=1.0, rot=None, collide=False, pad=0.0):
        """Place a village prop (generated/props/<name>.glb, shared atlas)."""
        r = rot if rot is not None else (0, 0, rz)
        F = self.k.frames[-1]
        M = F @ Matrix.LocRotScale(Vector(loc), Euler(r), Vector((s, s, s)))
        self.atlas_props.append((name, M))
        if collide:
            bb = PROP_BOUNDS.get(name)
            if bb:
                (x0, y0, z0), (x1, y1, z1) = bb
                cc = Vector(((x0 + x1) / 2 * s, (y0 + y1) / 2 * s, (z0 + z1) / 2 * s))
                Mc = M @ Matrix.Translation(cc / s)
                R = Mc.to_3x3().normalized()
                self.colliders.append((Matrix.Translation(Mc.to_translation()) @ R.to_4x4(),
                                       ((x1 - x0) * s + pad, (y1 - y0) * s + pad, (z1 - z0) * s)))

    def mega(self, name, loc, rz=0.0, s=1.0, rot=None, collide=False, grade=1.0, tint=None, wood=None):
        """Merge a Quaternius Fantasy Props MegaKit piece (CC0) into the room mesh with its
        trim-sheet colours sampled per face into the vertex colours."""
        k = self.k
        parts = _mega_parts(name)
        r = rot if rot is not None else (0, 0, rz)
        X = k.xf(loc, r, (s, s, s))
        lo = Vector((1e9,) * 3)
        hi = Vector((-1e9,) * 3)
        for (verts, faces, target) in parts:
            t = bmesh.new()
            vs = [t.verts.new(v) for v in verts]
            lay = t.faces.layers.int.new("cid")
            cols = []
            for (idx, col) in faces:
                try:
                    f = t.faces.new([vs[i] for i in idx])
                except ValueError:
                    continue
                c = _grade(col, grade)
                if tint:
                    c = mix(c, tuple(c[i] * tint[i] for i in range(3)), 0.6)
                cols.append(c)
                f[lay] = len(cols) - 1
            for v in verts:
                lo = Vector(map(min, lo, v))
                hi = Vector(map(max, hi, v))
            mat = self.WOOD if (target == "wood" if wood is None else wood) else self.PL
            k._merge(t, mat, (1, 1, 1), X, 32, 0.015, lambda f, cl=cols, ly=lay: cl[f[ly]], True)
        if collide:
            cc = (lo + hi) / 2
            M = k.frames[-1] @ X @ Matrix.Translation(cc)
            R = M.to_3x3().normalized()
            size = (hi - lo) * s
            self.colliders.append((Matrix.Translation(M.to_translation()) @ R.to_4x4(), tuple(size)))
        return (lo * s, hi * s)

    # ============================================================== finishing
    def finish(self, preview=True):
        os.makedirs(OUT_DIR, exist_ok=True)
        os.makedirs(SCENE_DIR, exist_ok=True)
        k = self.k
        self.mark("end")
        for (n0, c0), (n1, c1) in zip(self._tri, self._tri[1:]):
            print(f"  {c1 - c0:7d} tris  {n0}")
        bm = RP.split_lod(k.bm, "lod", 0)
        k.bm.free()
        # faces nobody can see: undersides resting on the ground floor
        bm.normal_update()
        kill = [f for f in bm.faces if f.normal.z < -0.9 and f.calc_center_median().z < 0.035]
        bmesh.ops.delete(bm, geom=kill, context="FACES_ONLY")
        RP.deform(bm, 0.006, 0.01, seed=k.seed % 97)
        col = bm.loops.layers.float_color.get("Col")
        g = Vector(srgb(GLASS_C))
        bm.faces.index_update()
        glass = [f for f in bm.faces if (Vector(f.loops[0][col][:3]) - g).length < 1e-3]
        RP.weather(bm, col, k.mat_fam, k.emissive, k.sills, seed=k.seed,
                   building=True, ao_dist=0.9, ao_strength=0.55)
        for f in glass:                     # window panes: bright daylight, no AO / bake
            for l in f.loops:
                l[col] = (0.78, 0.86, 0.95, 1.0)
        bm.faces.index_update()
        self._glass = {f.index for f in glass}
        room_tris = RP.tri_count(bm)
        room = k.build_object(bm, "Room")
        props = self._build_props()
        objs = [room] + ([props] if props else [])
        self._light_bake(objs)
        out = os.path.join(OUT_DIR, f"interior_{self.name}.glb")
        prop_tris = sum(len(p.vertices) - 2 for p in props.data.polygons) if props else 0
        mats = [m.name for o in objs for m in o.data.materials]
        objs = _export(objs, out)
        _write_import(out)
        self.stats = dict(room_tris=room_tris, prop_tris=prop_tris, total=room_tris + prop_tris, materials=mats,
                          size_mb=os.path.getsize(out) / 1e6)
        print(f"wrote {out}  room={room_tris}  props={prop_tris}  total={room_tris + prop_tris}  materials={mats}  "
              f"{self.stats['size_mb']:.2f} MB")
        self._write_scene()
        with open(os.path.join(OUT_DIR, f"interior_{self.name}.json"), "w") as f:
            json.dump(dict(name=self.name, stats=self.stats,
                           markers=[(m[0], to_godot(m[1]), m[2], m[3]) for m in self.markers],
                           spawn=(to_godot(self.spawn[0]), self.spawn[1]),
                           lights=[(l[0], to_godot(l[1])) for l in self.rt_lights]), f, indent=1)
        if preview and "--no-preview" not in sys.argv:
            self._render(objs)

    def _build_props(self):
        if not self.atlas_props:
            return None
        objs = []
        for (name, M) in self.atlas_props:
            before = set(bpy.data.objects)
            bpy.ops.import_scene.gltf(filepath=os.path.join(PROPS_DIR, name + ".glb"))
            new = [o for o in bpy.data.objects if o not in before]
            for o in new:
                if o.type != "MESH":
                    continue
                o.matrix_world = M @ o.matrix_world
                objs.append(o)
            for o in new:
                if o.type != "MESH":
                    bpy.data.objects.remove(o, do_unlink=True)
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
            if o.parent:
                mw = o.matrix_world.copy()
                o.parent = None
                o.matrix_world = mw
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bpy.ops.object.join()
        ob = bpy.context.view_layer.objects.active
        ob.name = "Props"
        me = ob.data
        # one material: atlas x Col
        atlas = None
        for m in me.materials:
            if m and m.node_tree:
                for n in m.node_tree.nodes:
                    if n.type == "TEX_IMAGE" and n.image:
                        atlas = n.image
                        break
            if atlas:
                break
        if atlas is None or not atlas.filepath:
            atlas = bpy.data.images.load(os.path.join(PROPS_DIR, "props_atlas.png"), check_existing=True)
        ca = me.color_attributes
        src = ca[0] if len(ca) else None
        if src is None:
            src = ca.new("Col", "FLOAT_COLOR", "CORNER")
            n = len(me.loops) * 4
            src.data.foreach_set("color", [1.0] * n)
        if src.domain != "CORNER" or src.data_type != "FLOAT_COLOR":
            vals = np.zeros(len(me.loops) * 4, dtype=np.float32)
            if src.domain == "CORNER":
                src.data.foreach_get("color", vals)
            else:
                pv = np.zeros(len(me.vertices) * 4, dtype=np.float32)
                src.data.foreach_get("color", pv)
                li = np.zeros(len(me.loops), dtype=np.int32)
                me.loops.foreach_get("vertex_index", li)
                vals = pv.reshape(-1, 4)[li].reshape(-1)
            name = src.name
            ca.remove(src)
            src = ca.new("Col", "FLOAT_COLOR", "CORNER")
            src.data.foreach_set("color", vals)
        src.name = "Col"
        for extra in [a for a in ca if a.name != "Col"]:
            ca.remove(extra)
        m = bpy.data.materials.new("RA_Props")
        m.use_nodes = True
        nt = m.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Col"
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = atlas
        mx = nt.nodes.new("ShaderNodeMix")
        mx.data_type = "RGBA"
        mx.blend_type = "MULTIPLY"
        mx.inputs[0].default_value = 1.0
        nt.links.new(tex.outputs["Color"], next(s for s in mx.inputs if s.identifier == "A_Color"))
        nt.links.new(vc.outputs["Color"], next(s for s in mx.inputs if s.identifier == "B_Color"))
        nt.links.new(next(s for s in mx.outputs if s.identifier == "Result_Color"), bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.85
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.3
        m.use_backface_culling = True
        old = [mm for mm in me.materials if mm]
        me.materials.clear()
        me.materials.append(m)
        for mm in old:
            if mm.users == 0:
                bpy.data.materials.remove(mm)
        for mm in list(bpy.data.materials):
            if mm.name.startswith("RA_Props") and mm is not m and mm.users == 0:
                bpy.data.materials.remove(mm)
        m.name = "RA_Props"
        for p in me.polygons:
            p.material_index = 0
        return ob

    def _light_bake(self, objs):
        """Point-light bake (with ray-cast shadows) multiplied into COLOR "Col" of every object."""
        verts, polys = [], []
        for o in objs:
            M = o.matrix_world
            base = len(verts)
            verts += [M @ v.co for v in o.data.vertices]
            polys += [[base + i for i in p.vertices] for p in o.data.polygons]
        bvh = BVHTree.FromPolygons(verts, polys, epsilon=0.0)
        amb = Vector(self.bake_ambient if hasattr(self, "bake_ambient") else (0.60, 0.53, 0.50))
        lights = [(Vector(p), Vector(srgb(c)) if max(c) <= 1.0 else Vector(c), e, r) for (p, c, e, r) in self.bake]
        glow_idx = None
        for o in objs:
            me = o.data
            skip = {i for i, m in enumerate(me.materials) if m and m.name.startswith("RA_Ember")}
            attr = me.color_attributes.get("Col")
            cols = np.zeros(len(me.loops) * 4, dtype=np.float32)
            attr.data.foreach_get("color", cols)
            cols = cols.reshape(-1, 4)
            cn = me.corner_normals
            M = o.matrix_world
            N3 = M.to_3x3().inverted().transposed()
            cache = {}
            gl = np.array((0.78, 0.86, 0.95), dtype=np.float32)
            glass = {p.index for p in me.polygons if np.abs(cols[p.loop_start, :3] - gl).max() < 2e-3}
            for p in me.polygons:
                if p.material_index in skip or p.index in glass:
                    continue
                for li in p.loop_indices:
                    vi = me.loops[li].vertex_index
                    n = (N3 @ cn[li].vector).normalized()
                    key = (vi, round(n.x, 1), round(n.y, 1), round(n.z, 1))
                    f = cache.get(key)
                    if f is None:
                        f = self._irradiance(M @ me.vertices[vi].co, n, lights, amb, bvh)
                        cache[key] = f
                    cols[li, 0] *= f[0]
                    cols[li, 1] *= f[1]
                    cols[li, 2] *= f[2]
            np.clip(cols, 0.0, 1.0, out=cols)
            attr.data.foreach_set("color", cols.reshape(-1))
            print(f"light bake {o.name}: {len(cache)} samples")

    @staticmethod
    def _irradiance(p, n, lights, amb, bvh):
        L = amb.copy()
        o = p + n * 0.025
        for (lp, lc, e, r) in lights:
            d = lp - p
            dist = d.length
            if dist > r or dist < 1e-4:
                continue
            dn = d / dist
            ndl = (n.dot(dn) + 0.2) / 1.2
            if ndl <= 0:
                continue
            att = (1.0 - dist / r) ** 2
            w = e * ndl * att
            if w < 0.004:
                continue
            hit = bvh.ray_cast(o, dn, max(0.0, dist - 0.12))
            if hit[0] is not None:
                w *= 0.12
            L += lc * w
        # soft shoulder so hot spots don't clip
        return Vector(tuple(x / (1.0 + 0.22 * max(0.0, x - 1.0)) for x in L))

    # ------------------------------------------------------------- Godot scene
    def _write_scene(self):
        name = self.name
        node = "".join(p.title() for p in name.split("_")) + "Interior"
        subs = []
        nodes = []
        ext = [("PackedScene", f"res://assets/generated/interiors/interior_{name}.glb", "1_room"),
               ("Script", DOOR_SCRIPT, "2_door"),
               ("Script", ROOM_SCRIPT, "3_room")]
        e = self.env
        subs.append(("Environment", "Environment_room", [
            "background_mode = 1", f"background_color = {gd_color(e['bg'])}",
            "ambient_light_source = 2", f"ambient_light_color = {gd_color(e['ambient'])}",
            f"ambient_light_energy = {e['ambient_energy']}",
            "reflected_light_source = 1",
            "tonemap_mode = 4", f"tonemap_exposure = {e['exposure']}", "tonemap_white = 6.0",
            "glow_enabled = true", "glow_intensity = 0.7", "glow_bloom = 0.08", "glow_hdr_threshold = 0.95",
            "adjustment_enabled = true", "adjustment_saturation = 1.15", "adjustment_contrast = 1.05"]))
        nodes.append(f'[node name="{node}" type="Node3D"]\nscript = ExtResource("3_room")\n'
                     f'metadata/title = "{self.title}"\n')
        nodes.append('[node name="Room" parent="." instance=ExtResource("1_room")]\n')
        nodes.append('[node name="Colliders" type="StaticBody3D" parent="."]\n')
        for i, (M, size) in enumerate(self.colliders):
            sid = f"Box_{i}"
            subs.append(("BoxShape3D", sid, [f"size = Vector3({size[0]:.4g}, {size[2]:.4g}, {size[1]:.4g})"]))
            nodes.append(f'[node name="C{i}" type="CollisionShape3D" parent="Colliders"]\n'
                         f'transform = {gd_transform(M)}\nshape = SubResource("{sid}")\n')
        sp, syaw = self.spawn
        nodes.append(f'[node name="PlayerSpawn" type="Marker3D" parent="."]\ntransform = {gd_yaw_transform(sp, syaw)}\n')
        if self.exit_door:
            pos, size, yaw = self.exit_door
            subs.append(("BoxShape3D", "Box_exit", [f"size = Vector3({size[0]:.4g}, {size[2]:.4g}, {size[1]:.4g})"]))
            nodes.append(f'[node name="ExitDoor" type="Area3D" parent="."]\ntransform = {gd_yaw_transform(pos, yaw)}\n'
                         f'script = ExtResource("2_door")\nis_exit = true\nprompt_text = "Leave"\n')
            nodes.append('[node name="Shape" type="CollisionShape3D" parent="ExitDoor"]\n'
                         f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {size[2] / 2:.4g}, 0)\n'
                         'shape = SubResource("Box_exit")\n')
        nodes.append('[node name="NPCs" type="Node3D" parent="."]\n')
        for (mname, pos, yaw, meta) in self.markers:
            lines = [f'[node name="{mname}" type="Marker3D" parent="NPCs"]', f"transform = {gd_yaw_transform(pos, yaw)}"]
            for kk, vv in meta.items():
                lines.append(f'metadata/{kk} = ' + (f'"{vv}"' if isinstance(vv, str) else f"{vv}"))
            nodes.append("\n".join(lines) + "\n")
        for (lname, pos, col, en, rng, flick) in self.rt_lights:
            nodes.append(f'[node name="{lname}" type="OmniLight3D" parent="."]\n'
                         f'transform = {gd_yaw_transform(pos, 0.0)}\nlight_color = {gd_color(col)}\n'
                         f'light_energy = {en}\nlight_specular = 0.3\nshadow_enabled = false\nomni_range = {rng}\n'
                         f'omni_attenuation = 1.4\nmetadata/flicker = {"true" if flick else "false"}\n')
        nodes.append('[node name="WorldEnvironment" type="WorldEnvironment" parent="."]\n'
                     'environment = SubResource("Environment_room")\n')
        if self.cams:
            _, loc, tgt, lens = self.cams[0]
            d = tgt - loc
            q = d.to_track_quat('Y', 'Z')      # Godot camera: local -Z_godot = Blender +Y, up = +Z
            M = Matrix.Translation(loc) @ q.to_matrix().to_4x4()
            fov = math.degrees(2 * math.atan(18.0 / lens * 720 / 1280)) if lens else 60
            nodes.append(f'[node name="PreviewCamera" type="Camera3D" parent="."]\ntransform = {gd_transform(M)}\n'
                         f'current = true\nfov = {fov:.3g}\n')
        load_steps = len(ext) + len(subs) + 1
        out = [f"[gd_scene load_steps={load_steps} format=3]\n"]
        for (typ, path, rid) in ext:
            out.append(f'[ext_resource type="{typ}" path="{path}" id="{rid}"]')
        out.append("")
        for (typ, sid, lines) in subs:
            out.append(f'[sub_resource type="{typ}" id="{sid}"]\n' + "\n".join(lines) + "\n")
        out += nodes
        path = os.path.join(SCENE_DIR, f"{name}_interior.tscn")
        with open(path, "w", newline="\n") as f:
            f.write("\n".join(out))
        print("wrote", path)

    # ------------------------------------------------------------- previews
    def _render(self, objs):
        import addon_utils
        addon_utils.enable("cycles")
        sc = bpy.context.scene
        amb = self.preview_ambient
        # Godot-like shading: albedo (vertex colour incl. the bake) x ambient + the realtime lights.
        for o in objs:
            for m in o.data.materials:
                nt = m.node_tree
                b = nt.nodes["Principled BSDF"]
                if m.name.startswith("RA_Ember"):
                    b.inputs["Emission Strength"].default_value = 2.5
                    continue
                src = b.inputs["Base Color"].links[0].from_socket if b.inputs["Base Color"].links else None
                if src is not None:
                    nt.links.new(src, b.inputs["Emission Color"])
                    b.inputs["Emission Strength"].default_value = amb
        for (lname, pos, col, en, rng, flick) in self.rt_lights:
            ld = bpy.data.lights.new(lname, "POINT")
            ld.energy = en * 45.0
            ld.color = col
            ld.shadow_soft_size = 0.2
            ld.use_shadow = False
            o = bpy.data.objects.new(lname, ld)
            o.location = pos
            sc.collection.objects.link(o)
        w = bpy.data.worlds.new("Dark")
        w.use_nodes = True
        w.node_tree.nodes["Background"].inputs["Color"].default_value = (*self.env["bg"], 1)
        w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
        sc.world = w
        sc.render.engine = "CYCLES"
        sc.cycles.samples = int(os.environ.get("RA_SAMPLES", "40"))
        sc.cycles.use_denoising = True
        sc.cycles.max_bounces = 2
        try:
            sc.cycles.device = "GPU"
            prefs = bpy.context.preferences.addons["cycles"].preferences
            for dt in ("OPTIX", "CUDA", "HIP", "ONEAPI"):
                try:
                    prefs.compute_device_type = dt
                    prefs.get_devices()
                    if any(dd.type == dt for dd in prefs.devices):
                        for dd in prefs.devices:
                            dd.use = True
                        break
                except Exception:
                    pass
        except Exception:
            sc.cycles.device = "CPU"
        sc.render.resolution_x = 1280
        sc.render.resolution_y = 720
        try:
            sc.view_settings.view_transform = "AgX"
            sc.view_settings.look = "AgX - Punchy"
        except Exception:
            pass
        sc.view_settings.exposure = float(os.environ.get("RA_EXPOSURE", "0.5"))
        cd = bpy.data.cameras.new("Cam")
        cam = bpy.data.objects.new("Cam", cd)
        sc.collection.objects.link(cam)
        sc.camera = cam
        cd.clip_start = 0.05
        for (suffix, loc, tgt, lens) in self.cams:
            cd.lens = lens
            cam.location = loc
            cam.rotation_euler = (tgt - loc).to_track_quat('-Z', 'Y').to_euler()
            sc.render.filepath = os.path.join(PREV_DIR, f"interior_{self.name}_{suffix}.png")
            bpy.ops.render.render(write_still=True)
            print("preview", sc.render.filepath)


# ================================================================== megakit sampling
_MEGA = {}
_IMG = {}


def _img_array(img):
    key = img.name
    if key not in _IMG:
        w, h = img.size
        a = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(a)
        _IMG[key] = a.reshape(h, w, 4)
    return _IMG[key]


def _upstream(node, seen=None):
    seen = seen if seen is not None else set()
    for inp in node.inputs:
        for l in inp.links:
            n = l.from_node
            if n not in seen:
                seen.add(n)
                _upstream(n, seen)
    return seen


def _mat_info(m):
    if m is None or not m.node_tree:
        return (None, (0.6, 0.5, 0.4), False)
    b = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if b is None:
        return (None, (0.6, 0.5, 0.4), False)
    bc = b.inputs["Base Color"]
    if not bc.links:
        c = bc.default_value
        return (None, tuple(c[:3]), False)
    ups = _upstream(b.inputs["Base Color"].links[0].from_node) | {bc.links[0].from_node}
    img = None
    for n in ups:
        if n.type == "TEX_IMAGE" and n.image:
            nm = n.image.name.lower()
            if "normal" in nm or "orm" in nm:
                continue
            img = n.image
    vc = any(n.type in ("VERTEX_COLOR", "ATTRIBUTE") for n in ups)
    return (img, (1, 1, 1), vc)


def _lin2s(x):
    return x * 12.92 if x <= 0.0031308 else 1.055 * (max(x, 0.0) ** (1 / 2.4)) - 0.055


def _mega_parts(name):
    """-> [(verts, [(vert_indices, sRGB colour)], 'wood'|'other')] in the piece's own metres."""
    if name in _MEGA:
        return _MEGA[name]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(MEGA_DIR, name + ".gltf"))
    new = [o for o in bpy.data.objects if o not in before]
    groups = {}
    for o in new:
        if o.type != "MESH":
            continue
        me = o.data
        M = o.matrix_world
        uv = me.uv_layers.active
        ca = me.color_attributes[0] if len(me.color_attributes) else None
        cvals = None
        if ca is not None:
            n = len(me.loops) if ca.domain == "CORNER" else len(me.vertices)
            cvals = np.zeros(n * 4, dtype=np.float32)
            ca.data.foreach_get("color", cvals)
            cvals = cvals.reshape(-1, 4)
            srgb_attr = ca.data_type == "BYTE_COLOR"
        for p in me.polygons:
            m = me.materials[p.material_index] if me.materials else None
            mname = m.name if m else ""
            target = "wood" if "Furniture" in mname else "other"
            img, base, usevc = _mat_info(m)
            if img is not None and uv is not None:
                arr = _img_array(img)
                h, w = arr.shape[:2]
                us = [uv.data[li].uv for li in p.loop_indices]
                cu = sum(u.x for u in us) / len(us)
                cvv = sum(u.y for u in us) / len(us)
                samp = []
                for (uu, vv, wt) in [(cu, cvv, 2.0)] + [(u.x * 0.7 + cu * 0.3, u.y * 0.7 + cvv * 0.3, 1.0) for u in us]:
                    x = int((uu % 1.0) * (w - 1))
                    y = int((vv % 1.0) * (h - 1))
                    samp.append((arr[y, x, :3], wt))
                tw = sum(s[1] for s in samp)
                col = tuple(float(sum(s[0][i] * s[1] for s in samp) / tw) for i in range(3))
                if img.colorspace_settings.name.lower() in ("linear", "linear rec.709", "non-color") or img.is_float:
                    col = tuple(_lin2s(c) for c in col)
            else:
                col = tuple(_lin2s(c) for c in base)
            if usevc and cvals is not None:
                if ca.domain == "CORNER":
                    vc = cvals[list(p.loop_indices), :3].mean(axis=0)
                else:
                    vc = cvals[list(p.vertices), :3].mean(axis=0)
                vc = tuple(_lin2s(float(c)) for c in vc)      # .color is scene-linear for byte and float attributes
                col = tuple(col[i] * vc[i] for i in range(3))
            g = groups.setdefault(target, ([], [], {}))
            verts, faces, vmap = g
            idx = []
            for vi in p.vertices:
                key = (o.name, vi)
                if key not in vmap:
                    vmap[key] = len(verts)
                    verts.append(tuple(M @ me.vertices[vi].co))
                idx.append(vmap[key])
            faces.append((idx, col))
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    parts = [(v, f, t) for t, (v, f, _) in groups.items()]
    _MEGA[name] = parts
    return parts


def _grade(c, amount=1.0):
    """Warm, slightly muted grade that pulls MegaKit colours into the village palette."""
    lum = 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]
    sat = 0.88
    c = tuple(lum + (c[i] - lum) * sat for i in range(3))
    warm = (1.04, 0.98, 0.88)
    c = tuple(clamp(c[i] * (1 + (warm[i] - 1) * amount)) for i in range(3))
    return c


# village prop bounds (min, max) in their own metres, filled lazily
PROP_BOUNDS = {
    "barrel": ((-0.345, -0.345, 0.0), (0.345, 0.345, 0.9)),
    "crate": ((-0.325, -0.325, 0.0), (0.325, 0.325, 0.64)),
    "crate_stack": ((-0.73, -0.645, 0.0), (0.73, 0.645, 1.21)),
    "sack_pile": ((-1.12, -0.51, 0.0), (1.12, 0.51, 1.0)),
    "woodpile": ((-1.2, -0.45, 0.0), (1.2, 0.45, 1.13)),
    "weapon_rack": ((-1.0, -0.4, 0.0), (1.0, 0.4, 2.29)),
    "anvil_stump": ((-0.45, -0.4, 0.0), (0.45, 0.4, 0.93)),
    "water_trough": ((-1.13, -0.45, 0.0), (1.13, 0.45, 0.56)),
    "bench": ((-0.8, -0.235, 0.0), (0.8, 0.235, 0.61)),
    "hay_bales": ((-1.14, -1.0, 0.0), (1.14, 1.0, 1.45)),
    "basket_produce": ((-0.36, -0.34, 0.0), (0.36, 0.34, 0.63)),
    "produce_table": ((-0.9, -0.68, 0.0), (0.9, 0.68, 1.1)),
    "flower_planter": ((-0.55, -0.23, 0.0), (0.55, 0.23, 0.64)),
    "notice_board": ((-1.0, -0.42, 0.0), (1.0, 0.42, 2.47)),
}


def _export(objs, out_glb):
    """glTF-separate export (textures stay where they are, referenced by relative URI:
    ../village_tex/*.png and ../props/props_atlas.png), packed into one .glb."""
    # Blender 5.2's glTF exporter writes COLOR_0 only for the FIRST material's primitive of a
    # multi-material mesh (the others get white). Export one object per material instead.
    split = []
    for o in objs:
        if len(o.data.materials) > 1:
            bpy.ops.object.select_all(action="DESELECT")
            o.select_set(True)
            bpy.context.view_layer.objects.active = o
            before = set(bpy.data.objects)
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.mesh.separate(type="MATERIAL")
            bpy.ops.object.mode_set(mode="OBJECT")
            parts = [o] + [x for x in bpy.data.objects if x not in before]
            for x in parts:
                used = {p.material_index for p in x.data.polygons}
                mats = [m for i, m in enumerate(x.data.materials) if i in used]
                keep = mats[0] if mats else None
                x.data.materials.clear()
                if keep:
                    x.data.materials.append(keep)
                    x.name = o.name.split("_")[0] + "_" + keep.name.replace("RA_", "")
                for p in x.data.polygons:
                    p.material_index = 0
            split += parts
        else:
            split.append(o)
    objs = split
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
        ca = o.data.color_attributes
        if "Col" in ca:
            ca.active_color = ca["Col"]
            ca.render_color_index = ca.find("Col")
    bpy.context.view_layer.objects.active = objs[0]
    out_glb = os.path.abspath(out_glb)
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
    print("images:", [i["uri"] for i in gl.get("images", [])])
    return objs


def _write_import(glb):
    """<glb>.import that maps RA_Wood / RA_Plaster to the shared village_tex/ra_*.tres materials
    (same convention as write_village_godot_materials.py), so every interior and building shares
    one material resource per family."""
    import re
    import write_village_godot_materials as WV
    mats, _ = WV.glb_materials(glb)
    imp = glb + ".import"
    txt = open(imp).read() if os.path.exists(imp) else WV.GLB_IMPORT.format(name="interiors/" + os.path.basename(glb))
    sub = WV.subresources(mats)
    txt2 = re.sub(r"_subresources=\{.*?\n\}\n(?=gltf/)|_subresources=\{\}\n", "_subresources=" + sub + "\n", txt,
                  flags=re.S)
    with open(imp, "w", newline="\n") as f:
        f.write(txt2)
