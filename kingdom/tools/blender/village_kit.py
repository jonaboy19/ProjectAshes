"""Village building kit for Rising Ashes (bpy, Blender 5.x).

Builds on ra_kit.Kit with the parts every village building shares, in the
style of make_adventurer_guild.py: bevelled timber framing over blotchy lime
plaster, stone plinths and masonry, shingle / slate / thatch roofs with ragged
courses and moss, windows with glazing bars, shutters and flower boxes, plank
doors with iron straps, awnings, hanging lanterns, chimneys and yard clutter
(barrels, crates, firewood, sacks, hay).

Palettes are what make a street of the same models not look copy-pasted:
every generator takes `--variant=N` (or infers N from an output name ending in
`_N.glb`) and picks a palette + layout flags for that variant.

Wall frames: `with k.side("front", hx, hy): ...` puts you in a local frame
where the wall face is the XZ plane at y=0, outward is -Y, x runs along the
wall (centred) and z is world height. All wall helpers (timber_wall,
stone_wall, window, door, wall_lantern, awning...) work in that frame.
"""
import os, sys, math, random, re
from contextlib import contextmanager
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ra_kit import Kit, hexc, vary, mix
import bmesh
from mathutils import Vector, Matrix

# ----------------------------------------------------------------- palettes
def H(*hs):
    return [hexc(h) for h in hs]

# Round-6 art direction (docs/art_reference): warm, saturated, hand-painted. Light warm stone,
# strongly varied slates in blue / red / green, bright limewash, deep timber.
STONE = {
    "grey": H("b3aca0", "a39d92", "c4bdae", "948e85", "bfb6a4", "aaa293", "9c968b"),
    "warm": H("c6b394", "b4a080", "d4c4a3", "a99776", "cab08a", "a08f73", "bba583"),
    "cool": H("a3a7a5", "93989a", "b2b7b1", "878c8d", "babcb3", "9ba09c", "aeb0a8"),
    "field": H("9a9082", "ad9f88", "80786c", "b7a88f", "766f66", "a08f78", "8e7f6b", "aca496"),
}
ROOF = {
    "shingle_brown": H("7c5a3c", "8c6a48", "6b4c35", "977050", "785a40", "84633f", "a07a52"),
    "shingle_grey": H("67615a", "736c62", "5a554f", "7e766a", "6a6258", "847a6c"),
    "slate_blue": H("3e5f88", "4a6d96", "34547c", "5a7ca3", "436690", "5f84ae", "2f4b70", "6a8fb6"),
    "slate_teal": H("3c6a78", "467886", "345d6a", "558896", "3f6f7c", "5e929e"),
    "slate_green": H("3c6e40", "477d48", "335f37", "548a50", "3d683c", "5f9654", "2c5530", "6aa05c"),
    "slate_grey": H("4b4f58", "565a63", "42464e", "60646c", "4d515a", "686c74"),
    "slate_purple": H("58506a", "645b78", "4b445c", "6e6584", "5a5064"),
    "clay": H("b24a30", "c25a3a", "9f412d", "cc6a4a", "a9503a", "913c2a", "d07350"),
}
THATCH = {
    "golden": H("a48349", "b89250", "c9a256", "d8b466", "c09a58", "ab8c58", "90784c"),
    "aged": H("8e7a54", "9e885e", "ad9868", "b8a372", "95805a", "7e6c4e", "a3926c"),
}
PLASTER = {
    "cream": hexc("eedcb6"), "white": hexc("f3ebd9"), "ochre": hexc("e0b374"), "rose": hexc("e2b39c"),
    "sage": hexc("ccd2ad"), "straw": hexc("ead28e"), "grey": hexc("d6d0c2"), "clay": hexc("d3956f"),
    "blue": hexc("bccbd0"),
}
TIMBER = {"dark": hexc("4a3020"), "oak": hexc("6b4a2f"), "grey": hexc("5d5045"), "black": hexc("2f2621"),
          "red": hexc("5e2f1f"), "honey": hexc("80592f")}
ACCENT = {"teal": hexc("2f6b73"), "oxblood": hexc("7a2e26"), "green": hexc("3f6b44"), "blue": hexc("3d5878"),
          "mustard": hexc("b0892f"), "natural": hexc("8a6238"), "sage": hexc("6f9a6a"), "plum": hexc("5d3a52"),
          "cream": hexc("d9ccb0")}
FLOWERS = H("ec4a5c", "f7c843", "fbf5ea", "b85ad6", "f08a34", "f78fb8", "6f95ec")
GLASS_C = hexc("58768e")
IRON = hexc("2e2d2c")
MORTAR = hexc("3d3935")


def palette(plaster="cream", timber="dark", accent="teal", roof="shingle_brown", stone="grey",
            thatch="golden", trim=None, door=None, flowers=None, box=None):
    return dict(plaster=PLASTER.get(plaster, plaster) if isinstance(plaster, str) else plaster,
                timber=TIMBER[timber], accent=ACCENT[accent], roof=ROOF[roof], stone=STONE[stone],
                thatch=THATCH[thatch], trim=TIMBER[trim] if trim in TIMBER else (ACCENT[trim] if trim else TIMBER[timber]),
                door=ACCENT[door] if door else ACCENT["natural"], flowers=flowers or FLOWERS,
                box=ACCENT[box] if box else TIMBER[timber], roof_kind=roof)


def isolated(fn):
    """Decorator: the call draws from its own random stream (seeded from the kit's
    prng) and leaves the global sequence untouched, so adding dressing to a
    generator never moves the rest of its layout."""
    def wrap(self, *a, **kw):
        st = random.getstate()
        random.seed(self.prng.random())
        try:
            return fn(self, *a, **kw)
        finally:
            random.setstate(st)
    wrap.__name__ = fn.__name__
    wrap.__doc__ = fn.__doc__
    return wrap


def variant_arg(default=1):
    """--variant=N on the command line, else a trailing _N in the .glb name."""
    for a in sys.argv[1:]:
        if a.startswith("--variant="):
            return int(a.split("=", 1)[1])
    for a in sys.argv[1:]:
        m = re.search(r"_(\d+)\.glb$", a)
        if m:
            return int(m.group(1))
    return default


MATSPEC = {
    "Matte": dict(rough=0.92),
    "Plaster": dict(rough=0.95, spec=0.3),
    "Wood": dict(rough=0.74),
    "Roof": dict(rough=0.7, spec=0.45),
    "Thatch": dict(rough=1.0, spec=0.2),
    "Plant": dict(rough=0.8, spec=0.3),
    "Cloth": dict(rough=0.9, spec=0.25),
    "Metal": dict(rough=0.4, metal=1.0),
    "Glass": dict(rough=0.12, metal=0.2, emission=hexc("ffb060"), strength=0.1, spec=0.8),
    "WindowLit": dict(rough=0.25, emission=hexc("ffb347"), strength=1.6, spec=0.5),
    "Lamp": dict(rough=0.3, emission=hexc("ffc46b"), strength=2.5),
    "Coals": dict(rough=0.6, emission=hexc("ff5a1a"), strength=7.0),
    "Water": dict(rough=0.04, spec=0.9),
}


class VK(Kit):
    def __init__(self, name, seed, pal):
        super().__init__(name, seed=seed)
        self.p = pal

    def M(self, key):
        if key not in self.mats:
            self.material(key, **MATSPEC[key])
        return key

    # ------------------------------------------------------------ colours
    def stone(self):
        c = random.choice(self.p["stone"])
        if random.random() < 0.07:
            c = mix(c, hexc("6f7a5a"), 0.35)
        return vary(c, 0.15, 0.035)

    def tile(self, t):
        c = random.choice(self.p["roof"])
        r = random.random()
        if r < 0.03 + 0.09 * (1 - t):            # moss creeping up from the eave
            c = mix(c, hexc("68753f"), random.uniform(0.3, 0.55))
        elif r < 0.12:                             # lichen / sun-bleached tile
            c = mix(c, hexc("b3ad96"), random.uniform(0.15, 0.3))
        elif r < 0.2:                              # odd paler replacement tile
            c = mix(c, (0.95, 0.95, 0.95), 0.16)
        elif r < 0.27:                             # darker, wetter tile
            c = tuple(x * 0.8 for x in c)
        return vary(c, 0.13, 0.04)

    def timber(self, amt=0.08):
        return vary(self.p["timber"], amt, 0.02)

    def plank_c(self, base=None):
        c = base or hexc("8a6a48")
        if random.random() < 0.15:
            c = mix(c, hexc("7d7a70"), 0.35)       # silvered board
        return vary(c, 0.12, 0.03)

    # ------------------------------------------------------------ frames
    @contextmanager
    def side(self, s, hx, hy, cx=0.0, cy=0.0):
        if s == "front":
            self.push((cx, cy - hy, 0)); L = 2 * hx
        elif s == "back":
            self.push((cx, cy + hy, 0), (0, 0, math.pi)); L = 2 * hx
        elif s == "right":
            self.push((cx + hx, cy, 0), (0, 0, math.pi / 2)); L = 2 * hy
        else:
            self.push((cx - hx, cy, 0), (0, 0, -math.pi / 2)); L = 2 * hy
        try:
            yield L
        finally:
            self.pop()

    # ------------------------------------------------------------ primitives
    def bar(self, a, b, w, d, mat, color, up=(0, 0, 1), bevel=0.015, var=0.06, grime=True, ext=0.0):
        """Rectangular timber from a to b; its `w` side lies along `up` (projected),
        its `d` side across. `ext` lengthens both ends."""
        a, b = Vector(a), Vector(b)
        z = (b - a).normalized()
        a, b = a - z * ext, b + z * ext
        L = (b - a).length
        u = Vector(up)
        x = (u - z * u.dot(z))
        if x.length < 1e-5:
            x = Vector((1, 0, 0)) - z * z.x
        x.normalize()
        y = z.cross(x)
        m = Matrix((
            (x.x, y.x, z.x, a.x),
            (x.y, y.y, z.y, a.y),
            (x.z, y.z, z.z, a.z),
            (0, 0, 0, 1)))
        t = bmesh.new()
        bmesh.ops.create_cube(t, size=1.0)
        for v in t.verts:
            v.co = Vector((v.co.x * w, v.co.y * d, (v.co.z + 0.5) * L))
        if bevel:
            bmesh.ops.bevel(t, geom=t.edges[:], offset=min(bevel, w * 0.4, d * 0.4), segments=1, affect='EDGES')
        c = vary(color, var) if var else color
        if bevel and self.polish and not self.lod_tag:
            with self.detail():
                self._merge(t, mat, c, m, None, 0.02, None, grime, subdiv=True)
            with self.lod1_only():
                t = bmesh.new()
                bmesh.ops.create_cube(t, size=1.0)
                for v in t.verts:
                    v.co = Vector((v.co.x * w, v.co.y * d, (v.co.z + 0.5) * L))
                self._merge(t, mat, c, m, None, 0.02, None, grime, subdiv=True)
            return
        self._merge(t, mat, c, m, None, 0.02, None, grime, subdiv=True)

    def strut(self, x0, z0, x1, z1, w=0.14, y=-0.045, d=0.1, color=None):
        """Diagonal timber in the wall plane (wall frame)."""
        self.bar((x0, y, z0), (x1, y, z1), w, d, self.M("Wood"), color or self.timber(),
                 up=(-(z1 - z0), 0, (x1 - x0)), bevel=0, var=0)

    # ------------------------------------------------------------ walls
    def _open_holes(self, opens, zbase):
        holes = []
        for o in opens:
            if o["kind"] == "win":
                holes.append((o["x"] - o["w"] / 2, o["z0"] - zbase, o["x"] + o["w"] / 2, o["z0"] + o["h"] - zbase))
            elif o["kind"] == "door":
                holes.append((o["x"] - o["w"] / 2, o.get("z0", zbase) - zbase - 0.01, o["x"] + o["w"] / 2,
                              o.get("z0", zbase) + o["h"] - zbase))
            elif o["kind"] == "hole":
                holes.append((o["x"] - o["w"] / 2, o["z0"] - zbase, o["x"] + o["w"] / 2, o["z0"] + o["h"] - zbase))
        return holes

    def _place_opens(self, opens, stone=False, depth=None):
        for o in opens:
            if o["kind"] == "win":
                self.window(o["x"], o["z0"], o["w"], o["h"], depth=depth or o.get("depth", 0.12),
                            shutters=o.get("shutters", False), flowers=o.get("flowers", False), stone=stone,
                            panes=o.get("panes", (2, 2)), shutter_angle=o.get("shutter_angle"))
            elif o["kind"] == "door":
                self.door(o["x"], o["w"], o["h"], z0=o.get("z0", 0.0), depth=depth or o.get("depth", 0.14),
                          arch=o.get("arch", False), awning=o.get("awning", False), lantern=o.get("lantern"),
                          step=o.get("step", True), stone=stone, color=o.get("color"), open_leaf=o.get("open", 0.0),
                          detail=o.get("detail", 1))

    def timber_wall(self, L, z0, z1, posts, bays, t=0.18, ext=0.0, plaster=None, place=True, streaks=0.4,
                    detail=1):
        """Half-timbered storey on the current wall frame, x in [-L/2, L/2], z0..z1.
        `bays[i]` fills the bay between posts[i] and posts[i+1]: a brace kind
        ("x", "up", "dn", "chev", "vee", "rail", "studs", "plain") or an opening
        dict {"kind": "win"|"door", ...}; missing x/w/z0/h default to the bay.
        `ext` stretches plates and the end posts past the wall ends (to wrap the
        corner of the neighbouring wall). Returns the list of resolved openings."""
        opens = []
        for i, b in enumerate(bays):
            if not isinstance(b, dict):
                continue
            a, c = posts[i], posts[i + 1]
            o = dict(b)
            o.setdefault("x", (a + c) / 2)
            if o["kind"] == "win":
                o.setdefault("w", min(1.05, (c - a) - t - 0.36))
                o.setdefault("z0", z0 + min(0.95, (z1 - z0) * 0.34))
                o.setdefault("h", min(1.3, z1 - t - 0.25 - o["z0"]))
            else:
                o.setdefault("w", min(1.05, (c - a) - t - 0.1))
                o.setdefault("h", min(2.15, z1 - z0 - t - 0.3))
                o.setdefault("z0", z0)
            opens.append(o)
        pc = plaster or self.p["plaster"]
        self.panel_wall(L, z1 - z0, (0, 0, z0), self.M("Plaster"), pc, holes=self._open_holes(opens, z0),
                        streaks=streaks, cell=0.8)
        W = self.M("Wood")
        y = -0.045
        # sole plate, interrupted by doors that start below it
        cuts = sorted((o["x"] - o["w"] / 2 - 0.02, o["x"] + o["w"] / 2 + 0.02) for o in opens
                      if o["kind"] == "door" and o["z0"] < z0 + t)
        a = -L / 2 - ext
        for c0, c1 in cuts + [(L / 2 + ext, None)]:
            if c0 - a > 0.05:
                self.box((c0 - a, 0.13, t), ((a + c0) / 2, y, z0 + t / 2), W, self.timber(), bevel=0.02, var=0)
            a = c1 if c1 is not None else a
        self.box((L + 2 * ext, 0.13, t), (0, y, z1 - t / 2), W, self.timber(), bevel=0.02, var=0)
        zi0, zi1 = z0 + t, z1 - t
        for j, x in enumerate(posts):
            wdt = t
            xx = x
            if ext and j in (0, len(posts) - 1):
                wdt = t + ext
                xx = x + (-ext / 2 if j == 0 else ext / 2)
            self.box((wdt, 0.125, zi1 - zi0 + 0.02), (xx, y, (zi0 + zi1) / 2), W, self.timber(),
                     rot=(0, random.uniform(-0.008, 0.008), 0), var=0,
                     bevel=0.018 if (detail and j in (0, len(posts) - 1)) else 0.0)
        mid = zi0 + (zi1 - zi0) * 0.45
        for i, b in enumerate(bays):
            a, c = posts[i] + t / 2, posts[i + 1] - t / 2
            cx = (a + c) / 2
            if isinstance(b, dict):
                o = next(o for o in opens if abs(o["x"] - (b.get("x", (posts[i] + posts[i + 1]) / 2))) < 1e-6)
                if o["kind"] == "win":
                    sill = o["z0"] - 0.1
                    head = o["z0"] + o["h"] + 0.09
                    self.box((c - a + 0.02, 0.11, 0.14), (cx, y, sill), W, self.timber(), bevel=0.012, var=0)
                    if zi1 - head > 0.2:
                        self.box((c - a + 0.02, 0.11, 0.14), (cx, y, head), W, self.timber(), bevel=0.012, var=0)
                    if detail and sill - zi0 > 0.45 and c - a > 0.7:       # little cross under the sill
                        self.strut(a, zi0, cx, sill - 0.07, w=0.11)
                        self.strut(c, zi0, cx, sill - 0.07, w=0.11)
                else:
                    head = o["z0"] + o["h"] + 0.08
                    if zi1 - head > 0.15:
                        self.box((c - a + 0.02, 0.11, 0.15), (cx, y, head), W, self.timber(), bevel=0.012, var=0)
                continue
            if b == "x":
                self.strut(a, zi0, c, zi1)
                self.strut(c, zi0, a, zi1)
            elif b == "up":
                self.strut(a, zi0, c, zi1)
            elif b == "dn":
                self.strut(a, zi1, c, zi0)
            elif b == "chev":
                self.strut(a, zi0, cx, zi1)
                self.strut(c, zi0, cx, zi1)
            elif b == "vee":
                self.strut(a, zi1, cx, zi0)
                self.strut(c, zi1, cx, zi0)
            elif b == "rail":
                self.box((c - a + 0.02, 0.11, 0.14), (cx, y, mid), W, self.timber(), bevel=0.012, var=0)
            elif b == "k":
                self.box((c - a + 0.02, 0.11, 0.14), (cx, y, mid), W, self.timber(), bevel=0.012, var=0)
                self.strut(a, mid + 0.07, c, zi1)
                self.strut(a, zi0, c, mid - 0.07)
            elif b == "studs":
                self.box((0.14, 0.115, zi1 - zi0), (cx, y, (zi0 + zi1) / 2), W, self.timber(), bevel=0.012, var=0)
                self.box((c - a + 0.02, 0.11, 0.13), (cx, y, mid), W, self.timber(), bevel=0.012, var=0)
        if place:
            self._place_opens(opens)
        return opens

    def plaster_wall(self, L, z0, z1, opens, place=True, trim=True):
        """Plain rendered storey (no framing) with openings on the wall frame."""
        self.panel_wall(L, z1 - z0, (0, 0, z0), self.M("Plaster"), self.p["plaster"],
                        holes=self._open_holes(opens, z0), streaks=0.5)
        if place:
            self._place_opens(opens)

    def stone_wall(self, L, z0, z1, opens, bw=0.6, bh=0.3, top_fn=None, place=True, depth=0.24):
        """Coursed rubble / ashlar face (pair it with a dark core box ~0.2 m behind)."""
        tf = None
        if top_fn is not None:
            tf = lambda x: top_fn(x) - z0
        self.grid_wall(L, z1 - z0, (0, 0, z0), self.M("Matte"), self.stone, bw=bw, bh=bh,
                       holes=self._open_holes(opens, z0), gap=0.03, push=0.035, top_fn=tf)
        if place:
            self._place_opens(opens, stone=True, depth=depth)

    def core(self, x0, x1, y0, y1, z0, z1, inset=0.2, color=MORTAR):
        self.box((x1 - x0 - 2 * inset, y1 - y0 - 2 * inset, z1 - z0), ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
                 self.M("Matte"), color, var=0)

    def quoins(self, x0, x1, y0, y1, z0, z1, n=None, c=None):
        n = n or max(2, round((z1 - z0) / 0.42))
        h = (z1 - z0) / n
        with self.detail():
            self._quoins(x0, x1, y0, y1, z0, n, h, c)

    def _quoins(self, x0, x1, y0, y1, z0, n, h, c):
        for cx, cy in ((x0, y0), (x1, y0), (x0, y1), (x1, y1)):
            sxs = 1 if cx == x0 else -1
            sys_ = 1 if cy == y0 else -1
            for r in range(n):
                lx = (r % 2 == 0)
                sx, sy = (0.62, 0.36) if lx else (0.36, 0.62)
                sx += random.uniform(-0.05, 0.05)
                col = vary(c, 0.06) if c else mix(self.stone(), hexc("c8bfae"), 0.35)
                self.box((sx, sy, h - 0.03), (cx + sxs * (sx / 2 - 0.05), cy + sys_ * (sy / 2 - 0.05), z0 + (r + 0.5) * h),
                         self.M("Matte"), col, var=0)

    def plinth(self, x0, x1, y0, y1, h, over=0.12, c=None):
        c = c or mix(self.p["stone"][3], hexc("6c6862"), 0.4)
        self.box((x1 - x0 + 2 * over, y1 - y0 + 2 * over, h), ((x0 + x1) / 2, (y0 + y1) / 2, h / 2),
                 self.M("Matte"), c, bevel=0.04)

    def stone_skirt(self, hx, hy, h, cx=0.0, cy=0.0, out=0.06, bw=0.44, bh=0.2, opens_front=()):
        """Low fieldstone base course around a box (under timber/plaster walls)."""
        self.box((2 * hx - 0.3, 2 * hy - 0.3, h), (cx, cy, h / 2), self.M("Matte"), MORTAR, var=0)
        for s in ("front", "back", "left", "right"):
            with self.side(s, hx + (out if s in ("left", "right") else 0), hy + (out if s in ("front", "back") else 0),
                           cx, cy) as L:
                holes = []
                if s == "front":
                    holes = [(o["x"] - o["w"] / 2, -0.1, o["x"] + o["w"] / 2, h + 0.1) for o in opens_front]
                self.grid_wall(L + (2 * out if s in ("front", "back") else 0), h, (0, 0, 0), self.M("Matte"),
                               lambda: mix(self.stone(), MORTAR, 0.18), bw=bw, bh=bh, gap=0.026, push=0.03,
                               holes=holes)

    # ------------------------------------------------------------ openings
    def window(self, x, z0, w, h, depth=0.12, shutters=False, flowers=False, stone=False, panes=(2, 2),
               shutter_angle=None, frame_c=None):
        zc = z0 + h / 2
        W, P = self.M("Wood"), self.M("Plaster")
        if self.prng.random() < getattr(self, "lit_ratio", 0.4):
            self.quad(w, h, (x, depth, zc), self.M("WindowLit"), vary(hexc("ffc27a"), 0.08), var=0.04, grime=False)
        else:
            self.quad(w, h, (x, depth, zc), self.M("Glass"), vary(GLASS_C, 0.08), var=0.04, grime=False)
        rc = mix(self.p["plaster"], (0.4, 0.38, 0.35), 0.18) if not stone else mix(self.p["stone"][0], MORTAR, 0.3)
        rm = P if not stone else self.M("Matte")
        for sx in (-1, 1):
            self.quad(depth, h, (x + sx * w / 2, depth / 2, zc), rm, rc, rot=(0, 0, -sx * math.pi / 2), grime=False)
        self.quad(w, depth, (x, depth / 2, z0 + h), rm, mix(rc, (0, 0, 0), 0.2), rot=(math.pi / 2, 0, 0), grime=False)
        fc = frame_c or self.p["trim"]
        yf = depth - 0.035
        ft = 0.065
        for sx in (-1, 1):
            self.box((ft, 0.06, h), (x + sx * (w / 2 - ft / 2), yf, zc), W, fc, var=0.04)
        for zz in (z0 + ft / 2, z0 + h - ft / 2):
            self.box((w, 0.06, ft), (x, yf, zz), W, fc, var=0.04)
        nx, nz = panes
        with self.detail():
            for i in range(1, nx):
                self.box((0.035, 0.04, h - 2 * ft), (x - w / 2 + i * w / nx, yf - 0.005, zc), W, fc, var=0.03)
            for j in range(1, nz):
                self.box((w - 2 * ft, 0.035, 0.03), (x, yf - 0.01, z0 + ft + j * (h - 2 * ft) / nz), W, fc, var=0.03)
        self.add_sill(x, z0 - 0.08, w + 0.2)
        if stone:
            self.box((w + 0.3, depth + 0.18, 0.11), (x, depth / 2 - 0.1, z0 - 0.055), self.M("Matte"),
                     mix(self.stone(), hexc("c8bfae"), 0.4), var=0)
            self.box((w + 0.46, 0.14, 0.26), (x, -0.03, z0 + h + 0.13), self.M("Matte"),
                     mix(self.stone(), hexc("c8bfae"), 0.3), var=0)
        else:
            self.box((w + 0.26, 0.2, 0.065), (x, -0.06, z0 - 0.03), W, self.timber(), bevel=0.012, var=0)
        if shutters:
            a0 = shutter_angle if shutter_angle is not None else random.uniform(0.12, 0.45)
            lw = w / 2 + 0.03
            for sx in (-1, 1):
                a = a0 + random.uniform(-0.08, 0.08)
                self.push((x + sx * (w / 2 + 0.08), -0.07, zc), (0, 0, -sx * a))
                sc = vary(self.p["accent"], 0.05)
                with self.detail():
                    for i in range(2):
                        px = sx * (lw * (i + 0.5) / 2)
                        self.box((lw / 2 - 0.012, 0.035, h + 0.04), (px, 0, 0), W, vary(sc, 0.05), var=0)
                    for zz in (-h * 0.32, h * 0.32):
                        self.box((lw - 0.04, 0.025, 0.08), (sx * lw / 2, 0.03, zz), W, mix(sc, (0, 0, 0), 0.25), var=0)
                with self.lod1_only():
                    self.box((lw - 0.012, 0.035, h + 0.04), (sx * lw / 2, 0, 0), W, sc, var=0)
                self.pop()
        if flowers:
            self.flower_box(x, z0 - (0.06 if stone else 0.07), w + 0.2)

    def flower_box(self, x, ztop, L, y=-0.22):
        W, PL = self.M("Wood"), self.M("Plant")
        bc = vary(self.p["box"], 0.06)
        self.box((L, 0.24, 0.2), (x, y, ztop - 0.12), W, bc, var=0)
        with self.lod1_only():     # a green top stands in for the plants
            self.box((L - 0.04, 0.2, 0.12), (x, y, ztop + 0.04), self.M("Plant"), hexc("4f7a34"), var=0)
        with self.detail():
            self._flower_box_plants(x, ztop, L, y)

    def _flower_box_plants(self, x, ztop, L, y):
        PL = self.M("Plant")
        self.box((L - 0.06, 0.18, 0.02), (x, y, ztop - 0.03), self.M("Matte"), hexc("3f2f24"), var=0)
        n = max(3, int(L / 0.3))
        greens = [hexc("4f7a34"), hexc("5d8a3a"), hexc("3f6b2e"), hexc("6b8f3f")]
        flw = random.sample(self.p["flowers"], 2)
        for i in range(n):
            fx = x - L / 2 + (i + 0.5) * L / n + random.uniform(-0.03, 0.03)
            r = random.uniform(0.11, 0.14)
            self.sphere(r, (fx, y - random.uniform(-0.02, 0.03), ztop + 0.01), PL, vary(random.choice(greens), 0.12),
                        scale=(1.15, 0.9, 0.85), subdiv=1, noise_amt=0.05, rot=(0, 0, random.uniform(0, 3)), grime=False)
            bloom = flw[i % 2]
            for j in range(2):
                a = random.uniform(0, math.tau)
                self.box((0.07, 0.07, 0.06), (fx + math.cos(a) * 0.08, y - 0.04 + math.sin(a) * 0.08 - 0.03,
                                              ztop + random.uniform(0.07, 0.13)), PL, vary(bloom, 0.1),
                         rot=(0.6, 0.4, a), grime=False)
        for i in range(1):   # a trailing stem over the front edge
            fx = x + random.uniform(-L / 2 + 0.15, L / 2 - 0.15)
            for j in range(2):
                self.sphere(0.06 - j * 0.012, (fx + j * 0.02, y - 0.14, ztop - 0.08 - j * 0.08), PL,
                            vary(hexc("46723a"), 0.1), subdiv=0, grime=False)

    def door(self, x, w=1.0, h=2.1, z0=0.0, depth=0.14, arch=False, awning=False, lantern=None, step=True,
             stone=False, color=None, open_leaf=0.0, detail=1):
        W, MT = self.M("Wood"), self.M("Metal")
        dc = color or self.p["door"]
        rc = mix(self.p["plaster"], (0.4, 0.38, 0.35), 0.18) if not stone else mix(self.p["stone"][0], MORTAR, 0.3)
        rm = self.M("Plaster") if not stone else self.M("Matte")
        for sx in (-1, 1):
            self.quad(depth, h, (x + sx * w / 2, depth / 2, z0 + h / 2), rm, rc, rot=(0, 0, -sx * math.pi / 2),
                      grime=False)
        self.quad(w, depth, (x, depth / 2, z0 + h), rm, mix(rc, (0, 0, 0), 0.2), rot=(math.pi / 2, 0, 0), grime=False)
        self.box((w, depth + 0.02, 0.04), (x, depth / 2, z0 + 0.02), self.M("Matte"), hexc("5a544c"), var=0)
        n = max(4, round(w / 0.17))
        pw = w / n
        R = w / 2
        spring = h - R if arch else h

        def top(xx):
            return spring + (math.sqrt(max(0.0, R * R - xx * xx)) if arch else 0.0) - 0.01
        # the leaf (optionally swung inward about the left jamb)
        self.push((x - w / 2, depth - 0.04, z0), (0, 0, open_leaf))
        with self.lod1_only():
            if arch:
                pts = [(0.006, 0.0), (w - 0.006, 0.0)] + [(R + R * math.cos(a_), top(R * math.cos(a_)))
                                                          for a_ in (math.pi * i_ / 6 for i_ in range(7))]
                self.prism(pts, 0.06, (0, 0, 0), W, dc, var=0)
            else:
                self.box((w - 0.012, 0.06, h - 0.02), (R, 0, (h - 0.02) / 2), W, dc, var=0)
        self._door_leaf(n, w, pw, R, arch, top, dc, h, W, MT, detail)
        self.pop()
        self._door_frame(x, w, h, z0, arch, stone, spring, R, W, step, awning, lantern)

    def _door_leaf(self, n, w, pw, R, arch, top, dc, h, W, MT, detail):
      with self.detail():
        for i in range(n):
            x0 = -w / 2 + i * pw
            x1 = x0 + pw
            xc = (x0 + x1) / 2
            c = vary(dc, 0.09, 0.03)
            if arch:
                pts = [(x0 + 0.006 + R, 0.0), (x1 - 0.006 + R, 0.0), (x1 - 0.006 + R, top(x1)), (x0 + 0.006 + R, top(x0))]
                self.prism(pts, 0.06, (0, 0, 0), W, c, var=0)
            else:
                self.box((pw - 0.012, 0.06, h - 0.02), (xc + R, 0, (h - 0.02) / 2), W, c, var=0)
        for zz in (0.35, h - 0.5):
            self.box((w * 0.78, 0.025, 0.075), (w * 0.39 + 0.02, -0.04, zz), MT, IRON, var=0)
            if not detail:
                continue
            self.cyl(0.05, 0.025, (w * 0.78, -0.04, zz), MT, IRON, rot=(math.pi / 2, 0, 0), segs=6, base=False)
            for j in range(2):
                self.box((0.035, 0.02, 0.035), (0.15 + j * w * 0.35, -0.05, zz), MT, IRON, var=0, rot=(0, 0.785, 0))
        self.ring(0.06, 0.08, 0.02, (w * 0.82, -0.06, 1.05), MT, hexc("8c7a4a"), segs=6)
        self.box((0.08, 0.02, 0.14), (w * 0.82, -0.035, 1.14), MT, IRON, var=0)

    def _door_frame(self, x, w, h, z0, arch, stone, spring, R, W, step, awning, lantern):
        # frame
        if not stone:
            tc = self.timber()
            for sx in (-1, 1):
                self.box((0.16, 0.16, h + 0.08), (x + sx * (w / 2 + 0.07), -0.03, z0 + (h + 0.08) / 2), W, tc,
                         bevel=0.018, var=0.04)
            if not arch:
                self.box((w + 0.5, 0.17, 0.18), (x, -0.035, z0 + h + 0.09), W, tc, bevel=0.02, var=0.04)
        else:
            if arch:
                nv = 9
                for i in range(nv):
                    a0 = math.pi * i / nv
                    a1 = math.pi * (i + 1) / nv
                    r0, r1 = R, R + 0.3
                    pts = [(math.cos(a0) * r0, spring + math.sin(a0) * r0), (math.cos(a0) * r1, spring + math.sin(a0) * r1),
                           (math.cos(a1) * r1, spring + math.sin(a1) * r1), (math.cos(a1) * r0, spring + math.sin(a1) * r0)]
                    self.prism(pts, 0.3, (x, 0.05, z0), self.M("Matte"), mix(self.stone(), hexc("c8bfae"), 0.35),
                               var=0)
            else:
                self.box((w + 0.5, 0.3, 0.3), (x, 0.03, z0 + h + 0.15), self.M("Matte"),
                         mix(self.stone(), hexc("c8bfae"), 0.3), bevel=0.02, var=0)
            jc = []
            with self.detail():
                for sx in (-1, 1):
                    for r in range(4):
                        wd = 0.34 if r % 2 == 0 else 0.24
                        jc.append(mix(self.stone(), hexc("c8bfae"), 0.3))
                        self.box((wd, 0.3, spring / 4 - 0.025), (x + sx * (w / 2 + wd / 2), 0.05, z0 + (r + 0.5) * spring / 4),
                                 self.M("Matte"), jc[-1], var=0)
            with self.lod1_only():
                for sx in (-1, 1):
                    self.box((0.3, 0.3, spring), (x + sx * (w / 2 + 0.15), 0.05, z0 + spring / 2), self.M("Matte"), jc[0],
                             var=0)
        if step:
            nst = max(1, round(z0 / 0.17)) if z0 > 0.1 else 1
            for i in range(nst):
                hh = z0 - i * (z0 / nst) if z0 > 0.1 else 0.14
                self.box((w + 0.5 + 0.1 * i, 0.42 + 0.36 * i, hh), (x, -0.21 - 0.18 * i, hh / 2), self.M("Matte"),
                         vary(hexc("8d877c"), 0.06), bevel=0.03, var=0)
        if awning:
            off = awning if isinstance(awning, float) else (0.75 if not arch else 0.5)
            self.awning(x, w + 1.0, z0 + h + off, run=0.95, rise=0.4)
        if lantern:
            self.wall_lantern(x + lantern * (w / 2 + 0.45), z0 + h + 0.2)

    def awning(self, x, aw, ztop, run=0.9, rise=0.4, posts=False):
        """Little pent roof on brackets over a door (wall frame)."""
        W = self.M("Wood")
        tc = self.timber()
        for sx in (-1, 1):
            bx = x + sx * (aw / 2 - 0.18)
            with self.detail():
                self.bar((bx, -0.02, ztop - rise - 0.75), (bx, -run + 0.2, ztop - rise - 0.06), 0.1, 0.1, W, tc,
                         up=(0, 1, 1), bevel=0.012)
            self.bar((bx, 0.0, ztop - rise - 0.05), (bx, -run + 0.05, ztop - rise - 0.05), 0.12, 0.1, W, tc,
                     up=(0, 0, 1), bevel=0.0)
        self.box((aw - 0.1, 0.12, 0.12), (x, -0.06, ztop - 0.05), W, tc, bevel=0.012)
        self.push((x, 0.02, ztop - rise))
        kind = self.p.get("roof_kind", "")
        if kind.startswith("slate"):
            self.shingle_side(-aw / 2, aw / 2, run, rise, self.M("Roof"), self.tile, tile_w=(0.26, 0.42),
                              course=0.24, th=0.025, deck_mat=W, deck_color=self.timber())
        else:
            self.shingle_side(-aw / 2, aw / 2, run, rise, self.M("Roof"), self.tile, tile_w=(0.16, 0.28),
                              course=0.2, th=0.022, deck_mat=W, deck_color=self.timber())
        self.pop()

    def wall_lantern(self, x, z, arm=0.42, y0=0.0):
        """Iron bracket and hanging lantern (wall frame); lantern hangs at y=-arm."""
        MT = self.M("Metal")
        with self.detail():
            self.box((0.12, 0.04, 0.34), (x, y0 - 0.02, z), MT, IRON, bevel=0.008, var=0)
            self.box((0.04, arm + 0.05, 0.04), (x, y0 - arm / 2 - 0.02, z + 0.12), MT, IRON, var=0)
            self.bar((x, y0 - 0.02, z - 0.14), (x, y0 - arm * 0.6, z + 0.11), 0.03, 0.03, MT, IRON, bevel=0)
        self.lantern((x, y0 - arm, z + 0.1))

    def lantern(self, top, s=1.0):
        """Hanging lantern whose hook is at `top` (frame coords)."""
        with self.detail():
            self._lantern(top, s)
        with self.lod1_only():
            x, y, z = top
            self.box((0.16 * s, 0.16 * s, 0.34 * s), (x, y, z - 0.12 * s - 0.28 * s), self.M("Lamp"), hexc("ffd08a"),
                     var=0, grime=False)

    def _lantern(self, top, s=1.0):
        MT = self.M("Metal")
        x, y, z = top
        self.box((0.015, 0.015, 0.12 * s), (x, y, z - 0.06 * s), MT, IRON, var=0)
        zc = z - 0.12 * s
        self.cyl(0.13 * s, 0.13 * s, (x, y, zc - 0.13 * s), MT, IRON, segs=4, r2=0.02, rot=(0, 0, math.pi / 4),
                 smooth=None)
        self.box((0.2 * s, 0.2 * s, 0.03 * s), (x, y, zc - 0.14 * s), MT, IRON, var=0)
        self.box((0.13 * s, 0.13 * s, 0.24 * s), (x, y, zc - 0.28 * s), self.M("Lamp"), hexc("ffd08a"), var=0,
                 grime=False)
        for dx in (-1, 1):
            for dy in (-1, 1):
                self.box((0.02 * s, 0.02 * s, 0.26 * s), (x + dx * 0.075 * s, y + dy * 0.075 * s, zc - 0.28 * s), MT,
                         IRON, var=0)
        self.box((0.17 * s, 0.17 * s, 0.03 * s), (x, y, zc - 0.42 * s), MT, IRON, var=0)
        self.cyl(0.03 * s, 0.06 * s, (x, y, zc - 0.5 * s), MT, IRON, segs=6, r2=0.0)

    # ------------------------------------------------------------ roofs
    def gable_roof(self, kind, x0, x1, y0, y1, wall_top, pitch_deg, over=0.45, verge=0.35, along="x", lift=0.14,
                   barge=True, ridge=True, deck_c=None, tile_w=None, course=None, th_thatch=0.34):
        """Two roof slopes over the box x0..x1, y0..y1 whose walls end at wall_top.
        along="x": ridge parallel to X (gables at +-X); along="y": ridge along Y
        (gable facing the street). Returns dict(eave, ridge, rise, gable(u)->z)."""
        p = math.radians(pitch_deg)
        if along == "x":
            hd, c_span = (y1 - y0) / 2, (y0 + y1) / 2
            l0, l1 = x0 - verge, x1 + verge
        else:
            hd, c_span = (x1 - x0) / 2, (x0 + x1) / 2
            l0, l1 = y0 - verge, y1 + verge
        tanp = math.tan(p)
        wall_top = wall_top + lift      # slope clears the top plates that stand proud of the wall
        eave = wall_top - over * tanp
        ridge_z = wall_top + hd * tanp
        run = hd + over
        rise = ridge_z - eave
        W = self.M("Wood")
        dc = deck_c or self.timber()
        if along == "x":
            self.push((0, c_span, eave))
            sides = [((l0, l1), (0, 0, 0)), ((-l1, -l0), (0, 0, math.pi))]
        else:
            self.push((c_span, 0, eave))
            sides = [((l0, l1), (0, 0, math.pi / 2)), ((-l1, -l0), (0, 0, -math.pi / 2))]
        for (a, b), rot in sides:
            if kind == "thatch":
                self.thatch_side(a, b, run, rise, self.M("Thatch"), self.p["thatch"], th=th_thatch, rot=rot, du=0.26,
                                 deck_mat=self.M("Thatch"), deck_color=hexc("5e4628"), ridge_color=hexc("6f5733"))
            elif kind == "slate":
                self.shingle_side(a, b, run, rise, self.M("Roof"), self.tile, tile_w=tile_w or (0.34, 0.56),
                                  course=course or 0.34, th=0.03, rot=rot, deck_mat=W, deck_color=dc, jag=0.04,
                                  droop=0.012)
            else:
                self.shingle_side(a, b, run, rise, self.M("Roof"), self.tile, tile_w=tile_w or (0.22, 0.4),
                                  course=course or 0.3, th=0.026, rot=rot, deck_mat=W, deck_color=dc, jag=0.035,
                                  droop=0.018)
        self.pop()

        def P(u, s, n=0.0):   # u along ridge, s = signed horizontal distance from ridge line
            if along == "x":
                return Vector((u, c_span + s, 0))
            return Vector((c_span + s, u, 0))
        if kind == "thatch":
            rz = ridge_z + 0.2
            a3, b3 = P(l0 - 0.05, 0), P(l1 + 0.05, 0)
            self.log((a3.x, a3.y, rz), (b3.x, b3.y, rz), 0.28, self.M("Thatch"), hexc("6f5733"), segs=10,
                     noise_amt=0.04)
            nb = max(4, round((l1 - l0) / 0.6))
            for i in range(nb + 1):
                q = P(l0 + 0.15 + i * (l1 - l0 - 0.3) / nb, 0)
                rot = (0, math.pi / 2, 0) if along == "x" else (math.pi / 2, 0, 0)
                with self.detail():
                    self.cyl(0.295, 0.05, (q.x, q.y, rz), W, hexc("5a4128"), rot=rot, segs=10, base=False, caps=False)
        elif ridge:
            rc = mix(self.p["roof"][0], (0, 0, 0), 0.3)
            for s in (-1, 1):
                a3 = P(l0 - 0.04, s * 0.1)
                b3 = P(l1 + 0.04, s * 0.1)
                upv = P(0, s * math.cos(p)) - P(0, 0)
                upv.z = -math.sin(p)
                zz = ridge_z + 0.06 - 0.1 * tanp + 0.03
                self.bar((a3.x, a3.y, zz), (b3.x, b3.y, zz), 0.26, 0.045, self.M("Roof"), rc, up=upv, bevel=0.01)
        if barge and kind != "thatch":
            bc = self.timber()
            for u in (l0 - 0.03, l1 + 0.03):
                for s in (-1, 1):
                    a3 = P(u, s * (run + 0.02))
                    b3 = P(u, 0)
                    dirv = Vector((b3.x - a3.x, b3.y - a3.y, rise))
                    upv = Vector((0, 0, 1)) - dirv.normalized() * dirv.normalized().z
                    self.bar((a3.x, a3.y, eave - 0.1), (b3.x, b3.y, ridge_z - 0.02), 0.24, 0.07, W, bc,
                             up=upv, bevel=0.015)

        def gable(u):
            return wall_top + max(0.0, hd - abs(u)) * tanp - 0.03
        return dict(eave=eave, ridge=ridge_z, rise=rise, gable=gable, run=run, tan=tanp, span_c=c_span, hd=hd)

    def gable_wall(self, hd, wall_top, top_fn, style="timber", window=True, vent=False):
        """Gable triangle in the wall frame; wall spans x in [-hd, hd], from wall_top
        up to top_fn(x). style: "timber" (plaster + frame), "plaster", "stone",
        "boards"."""
        W = self.M("Wood")
        apex = top_fn(0.0)
        rise = apex - wall_top
        tf = lambda xx: top_fn(xx) - wall_top
        win_h = min(0.8, rise * 0.35)
        wz = wall_top + rise * 0.28
        holes = [(-0.3, wz - wall_top, 0.3, wz - wall_top + win_h)] if window and rise > 1.6 else []
        if style in ("timber", "plaster"):
            self.panel_wall(2 * hd, rise, (0, 0, wall_top), self.M("Plaster"), self.p["plaster"], holes=holes,
                            top_fn=tf, top_breaks=(0.0,))
        elif style == "stone":
            self.prism([(-hd + 0.2, 0), (hd - 0.2, 0), (0, rise - 0.2)], 0.3, (0, 0.2, wall_top), self.M("Matte"),
                       MORTAR, var=0)
            self.grid_wall(2 * hd, rise, (0, 0, wall_top), self.M("Matte"), self.stone, bw=0.6, bh=0.3,
                           holes=holes, gap=0.03, push=0.035, top_fn=tf)
        elif style == "boards":
            self.prism([(-hd + 0.2, 0), (hd - 0.2, 0), (0, rise - 0.2)], 0.1, (0, 0.1, wall_top), self.M("Matte"),
                       hexc("2a221c"), var=0)
            self.plank_wall(2 * hd, rise, (0, 0, wall_top), W, lambda: self.plank_c(), holes=holes, top_fn=tf,
                            plank=(0.18, 0.28))
        if style == "timber":
            y = -0.045
            self.box((2 * hd + 0.1, 0.13, 0.18), (0, y, wall_top + 0.09), W, self.timber(), bevel=0.02, var=0)
            if rise > 1.0:
                self.box((0.18, 0.12, rise - 0.3), (0, y, wall_top + (rise - 0.3) / 2 + 0.1), W, self.timber(), var=0)
            zc = wall_top + rise * 0.5
            half = hd * 0.5
            if rise > 1.4:
                self.box((2 * half + 0.1, 0.12, 0.16), (0, y, zc), W, self.timber(), var=0)
                for sx in (-1, 1):
                    self.strut(sx * hd * 0.92, wall_top + 0.12, sx * half * 0.85, zc - 0.05, w=0.13)
                    if not holes:
                        self.strut(sx * half * 0.8, zc + 0.05, sx * 0.1, wall_top + rise * 0.82, w=0.12)
        if holes:
            self.window(0, wz, 0.6, win_h, depth=0.1, stone=(style == "stone"), panes=(2, 2))
        if vent and rise > 1.2:
          with self.detail():
            for i in range(3):
                self.box((0.08, 0.05, 0.45 - i * 0.1), (-0.12 + i * 0.12, -0.03, apex - 0.9), W, hexc("2a221c"), var=0)

    def chimney(self, cx, cy, z0, z1, sx=0.8, sy=0.8, pots=1, shoulder=None):
        """Stone chimney stack with a cap slab and clay pots. `shoulder=(z, bx, by)`
        widens everything below z to bx x by (an external breast)."""
        MA = self.M("Matte")
        z = z0
        r = 0
        segs_ = []
        tag0 = self.lod_tag
        self.lod_tag = tag0 | 1          # individual stones: LOD0 detail
        while z < z1:
            h = random.uniform(0.24, 0.34)
            wx, wy = (sx, sy)
            if shoulder and z < shoulder[0]:
                wx, wy = shoulder[1], shoulder[2]
            elif shoulder and z < shoulder[0] + 0.6:
                f = (z - shoulder[0]) / 0.6
                wx, wy = shoulder[1] + (sx - shoulder[1]) * f, shoulder[2] + (sy - shoulder[2]) * f
            ccx = cx
            self.box((wx - 0.06, wy - 0.06, h), (ccx, cy, z + h / 2), MA, MORTAR, var=0)
            along_x = (r % 2 == 0)
            span = wx if along_x else wy
            cut = random.uniform(0.35, 0.65) * span
            for (a, b) in ((0, cut), (cut, span)):
                if along_x:
                    self.box((b - a - 0.025, wy + random.uniform(-0.02, 0.02), h - 0.025),
                             (ccx - wx / 2 + (a + b) / 2, cy + random.uniform(-0.01, 0.01), z + h / 2), MA, self.stone(),
                             var=0)
                else:
                    self.box((wx + random.uniform(-0.02, 0.02), b - a - 0.025, h - 0.025),
                             (ccx + random.uniform(-0.01, 0.01), cy - wy / 2 + (a + b) / 2, z + h / 2), MA, self.stone(),
                             var=0)
            segs_.append((z, h, wx, wy))
            z += h
            r += 1
        self.lod_tag = tag0
        with self.lod1_only():      # one block per width change
            i = 0
            while i < len(segs_):
                j = i
                while j + 1 < len(segs_) and abs(segs_[j + 1][2] - segs_[i][2]) < 0.02 and abs(segs_[j + 1][3] - segs_[i][3]) < 0.02:
                    j += 1
                za, zb = segs_[i][0], segs_[j][0] + segs_[j][1]
                self.box((segs_[i][2], segs_[i][3], zb - za), (cx, cy, (za + zb) / 2), MA,
                         mix(self.p["stone"][0], MORTAR, 0.15), var=0)
                i = j + 1
        self.box((sx + 0.16, sy + 0.16, 0.12), (cx, cy, z + 0.06), MA, mix(self.stone(), hexc("6c6862"), 0.3),
                 bevel=0.025, var=0)
        pc = [hexc("a4553a"), hexc("b0663f"), hexc("8e4a34")]
        for i in range(pots):
            off = (i - (pots - 1) / 2) * min(sx, sy) * 0.5
            px, py = (cx + off, cy) if sx >= sy else (cx, cy + off)
            self.cyl(0.12, 0.38, (px, py, z + 0.12), MA, random.choice(pc), segs=8, r2=0.1)
            with self.detail():
                self.cyl(0.13, 0.06, (px, py, z + 0.46), MA, random.choice(pc), segs=8)
        top = z + (0.52 if pots else 0.12)
        self.add_marker("chimney_top", (cx, cy, top))
        return z + 0.12

    def jetty(self, x0, x1, y0, y1, z, jf=0.4, jb=0.0, t=0.26, joists=True):
        """Floor band of a jettied upper storey: lower walls y0..y1, upper floor
        overhangs jf at the front and jb at the back."""
        W = self.M("Wood")
        self.box((x1 - x0 + 0.1, (y1 - y0) + jf + jb + 0.1, t), ((x0 + x1) / 2, (y0 + y1 - jf + jb) / 2, z + t / 2),
                 W, self.timber(), bevel=0.025, var=0)
        if not joists:
            return
        with self.detail():
            self._joists(x0, x1, y0, y1, z, jf, jb, joists, W)

    def _joists(self, x0, x1, y0, y1, z, jf, jb, joists, W):
        n = max(4, round((x1 - x0) / 0.55))
        for yy, j, s in ((y0, jf, -1), (y1, jb, 1)):
            if j <= 0.05 or (s > 0 and joists != "both"):
                continue
            for i in range(n):
                x = x0 + 0.2 + i * (x1 - x0 - 0.4) / (n - 1)
                self.box((0.14, j + 0.12, 0.14), (x, yy + s * (j / 2 - 0.02), z - 0.06), W, self.timber(0.1), var=0)
            nb = max(2, round((x1 - x0) / 2.6))
            for i in range(nb + 1):
                x = x0 + 0.25 + i * (x1 - x0 - 0.5) / nb
                self.bar((x, yy + s * 0.02, z - 0.75), (x, yy + s * (j - 0.03), z - 0.02), 0.15, 0.14, W, self.timber(),
                         up=(0, -s, 1), bevel=0.0)

    # ------------------------------------------------------------ props
    def barrel(self, x, y, z=0.0, r=0.33, h=0.9, lid=True, water=False, open_top=False, segs=10):
        with self.detail():
            W, MT = self.M("Wood"), self.M("Metal")
            base = vary(hexc("7a5230"), 0.1)
            staves = lambda f: vary(base, 0.12, 0.03)
            self.cyl(r * 0.9, h / 2, (x, y, z), W, base, segs=segs, r2=r, color_fn=staves, caps=True)
            self.cyl(r, h / 2, (x, y, z + h / 2), W, base, segs=segs, r2=r * 0.9, color_fn=staves,
                     caps=not water and not open_top)
            for hz in (0.12, 0.5, 0.88):
                rr = r * (0.9 + 0.1 * (1 - abs(hz - 0.5) * 2)) + 0.012
                self.cyl(rr, 0.05, (x, y, z + h * hz - 0.025), MT, IRON, segs=segs, caps=False)
            if water:
                self.cyl(r * 0.86, 0.02, (x, y, z + h - 0.06), self.M("Water"), hexc("35607a"), segs=segs)
            elif lid and not open_top:
                self.cyl(r * 0.92, 0.03, (x, y, z + h), W, vary(base, 0.1), segs=segs)
        with self.lod1_only():
            self.cyl(r, h, (x, y, z), self.M("Wood"), hexc("7a5230"), segs=6, caps=True, var=0, smooth=None)

    def crate(self, x, y, z=0.0, s=0.6, rz=0.0, c=None):
        with self.detail():
            W = self.M("Wood")
            c = c or vary(hexc("8e6a42"), 0.1)
            self.push((x, y, z), (0, 0, rz))
            self.box((s - 0.04, s - 0.04, s - 0.02), (0, 0, s / 2), W, c, var=0)
            dk = mix(c, (0, 0, 0), 0.2)
            for zz in (0.05, s - 0.05):
                self.box((s, s, 0.09), (0, 0, zz), W, dk, var=0.03)
            for sx in (-1, 1):
                self.box((0.07, s + 0.01, s - 0.02), (sx * (s / 2 - 0.03), 0, s / 2), W, dk, var=0.03)
            self.bar((-s / 2 + 0.05, -s / 2 - 0.005, 0.1), (s / 2 - 0.05, -s / 2 - 0.005, s - 0.1), 0.07, 0.02, W, dk,
                     up=(-1, 0, 1), bevel=0)
            self.pop()
        with self.lod1_only():
            self.box((s, s, s), (x, y, z + s / 2), self.M("Wood"), c or hexc("8e6a42"), rot=(0, 0, rz), var=0)

    def firewood(self, x, y, L=1.8, H=1.1, D=0.45, rz=0.0, r=0.105, roof=False):
        """Stacked split logs (end grain facing local -Y) between two stakes."""
        with self.detail():
            W = self.M("Wood")
            self.push((x, y, 0), (0, 0, rz))
            self.box((L - 0.1, D - 0.1, H - 0.1), (0, 0, H / 2), W, hexc("3b2a1c"), var=0)
            rows = max(2, int(H / (r * 1.75)))
            for j in range(rows):
                n = max(2, int(L / (r * 2.05)))
                off = (r if j % 2 else 0.0)
                for i in range(n):
                    lx = -L / 2 + r + off + i * (L - 2 * r - off) / max(1, n - 1) if n > 1 else 0
                    lz = r + j * r * 1.72
                    rr = r * random.uniform(0.8, 1.1)
                    yj = random.uniform(-0.04, 0.04)
                    bark = vary(hexc("5a4330"), 0.15, 0.04)
                    self.log((lx, -D / 2 + yj, lz), (lx, D / 2 + yj, lz), rr, W, bark, segs=6, noise_amt=0.012,
                             end_color=vary(hexc("c79c68"), 0.12, 0.04), ring_step=2.0)
            for sx in (-1, 1):
                self.log((sx * (L / 2 + 0.06), 0, 0), (sx * (L / 2 + 0.06), 0, H + 0.1), 0.05, W, hexc("5a4330"), segs=6,
                         noise_amt=0.01, ring_step=2.0)
            if roof:
                self.push((0, D / 2 + 0.1, H + 0.3))
                self.shingle_side(-L / 2 - 0.2, L / 2 + 0.2, D + 0.4, 0.25, self.M("Roof"), self.tile,
                                  tile_w=(0.16, 0.28), course=0.2, th=0.02, deck_mat=W, deck_color=self.timber())
                self.pop()
            self.pop()
        with self.lod1_only():
            self.push((x, y, 0), (0, 0, rz))
            self.box((L, D, H), (0, 0, H / 2), self.M("Wood"), hexc("8a6a4a"), var=0)
            self.pop()

    def bench(self, x, y, L=1.4, rz=0.0, c=None):
        with self.detail():
            W = self.M("Wood")
            c = c or vary(hexc("8a6238"), 0.08)
            self.push((x, y, 0), (0, 0, rz))
            self.box((L, 0.36, 0.06), (0, 0, 0.46), W, c, bevel=0.012)
            for sx in (-1, 1):
                self.box((0.07, 0.3, 0.44), (sx * (L / 2 - 0.15), 0, 0.22), W, mix(c, (0, 0, 0), 0.2))
            self.box((L - 0.3, 0.05, 0.06), (0, 0, 0.18), W, mix(c, (0, 0, 0), 0.2))
            self.pop()

    def bucket(self, x, y, z=0.0, r=0.16):
        with self.detail():
            W, MT = self.M("Wood"), self.M("Metal")
            self.cyl(r * 0.85, r * 1.6, (x, y, z), W, vary(hexc("8a6238"), 0.1), segs=10, r2=r,
                     color_fn=lambda f: vary(hexc("8a6238"), 0.1))
            for hz in (0.25, 0.8):
                self.cyl(r * (0.87 + 0.13 * hz) + 0.01, 0.03, (x, y, z + r * 1.6 * hz), MT, IRON, segs=10, caps=False)

    def sack(self, x, y, z=0.0, s=1.0, rz=0.0, c=None):
        with self.detail():
            PL = self.M("Cloth")
            c = c or vary(hexc("b7a27c"), 0.08)
            self.sphere(0.26 * s, (x, y, z + 0.26 * s), PL, c, scale=(1.0, 0.8, 1.2), subdiv=1, noise_amt=0.04 * s,
                        rot=(0, 0, rz))
            self.cyl(0.08 * s, 0.14 * s, (x, y, z + 0.52 * s), PL, mix(c, (0, 0, 0), 0.1), segs=6, r2=0.05 * s,
                     noise_amt=0.01)

    def hay_bale(self, x, y, z=0.0, rz=0.0, s=(1.0, 0.5, 0.42), rx=0.0):
        with self.detail():
            TH = self.M("Thatch")
            c = vary(hexc("c9ab62"), 0.08, 0.03)
            self.box(s, (x, y, z + s[2] / 2), TH, c, rot=(rx, 0, rz), bevel=0.05, jitter=0.012,
                     color_fn=lambda f: vary(c, 0.06))
            for dx in (-0.25, 0.25):
                ca, sa = math.cos(rz), math.sin(rz)
                self.box((0.025, s[1] + 0.012, s[2] + 0.012), (x + ca * dx * s[0], y + sa * dx * s[0], z + s[2] / 2),
                         TH, hexc("7a5a3a"), rot=(rx, 0, rz), var=0)
        with self.lod1_only():
            self.box(s, (x, y, z + s[2] / 2), self.M("Thatch"), hexc("c9ab62"), rot=(rx, 0, rz), var=0)

    def jug(self, x, y, z=0.0, r=0.11, h=0.24, c=None, handle=True):
        """Squat pottery jug (market-stall goods): footring, bulging body, short
        neck, lip and a loop handle."""
        with self.detail():
            MA = self.M("Matte")
            c = c or vary(hexc("9a6a44"), 0.08)
            self.cyl(r * 0.55, h * 0.16, (x, y, z), MA, mix(c, (0, 0, 0), 0.1), segs=8, r2=r * 0.8, grime=False)
            self.cyl(r, h * 0.5, (x, y, z + h * 0.16), MA, c, segs=8, r2=r * 0.85, grime=False)
            self.cyl(r * 0.8, h * 0.22, (x, y, z + h * 0.66), MA, c, segs=8, r2=r * 0.38, grime=False)
            self.cyl(r * 0.36, h * 0.1, (x, y, z + h * 0.88), MA, mix(c, (0, 0, 0), 0.12), segs=8, r2=r * 0.42,
                     grime=False)
            if handle:
                self.tube([(x + r * 0.82, y, z + h * 0.5), (x + r * 1.5, y, z + h * 0.66),
                           (x + r * 0.82, y, z + h * 0.8)], [0.016, 0.016, 0.016], MA, c, segs=5, point_end=False,
                          cap_start=False)
        with self.lod1_only():
            self.cyl(r * 0.9, h, (x, y, z), self.M("Matte"), c or hexc("9a6a44"), segs=6, r2=r * 0.45, var=0)

    def basket(self, x, y, z=0.0, r=0.22, h=0.2, goods="apple", n=None):
        with self.detail():
            W = self.M("Wood")
            wc = vary(hexc("b08a55"), 0.08)
            self.cyl(r * 0.8, h, (x, y, z), W, wc, segs=10, r2=r, color_fn=lambda f: vary(wc, 0.1))
            self.cyl(r + 0.015, 0.035, (x, y, z + h - 0.03), W, mix(wc, (0, 0, 0), 0.15), segs=10, caps=False)
            self.produce(x, y, z + h - 0.02, r * 0.9, goods, n)

    def produce(self, x, y, z, r, goods, n=None):
        with self.detail():
            PL = self.M("Plant")
            if goods == "apple":
                cols, rr, sc = [hexc("b8322b"), hexc("c9452c"), hexc("9e2a24"), hexc("d6a338")], 0.045, (1, 1, 0.9)
            elif goods == "pear":
                cols, rr, sc = [hexc("b5b84a"), hexc("a6a640"), hexc("c2b457")], 0.045, (1, 1, 1.25)
            elif goods == "cabbage":
                cols, rr, sc = [hexc("7da54c"), hexc("8fb45e"), hexc("6b9442")], 0.09, (1, 1, 0.9)
            elif goods == "carrot":
                cols, rr, sc = [hexc("e07a2c"), hexc("d86c24")], 0.03, (1, 1, 3.5)
            elif goods == "bread":
                cols, rr, sc = [hexc("b8834a"), hexc("c99459"), hexc("a8723e")], 0.07, (1.5, 1, 0.7)
            elif goods == "onion":
                cols, rr, sc = [hexc("a8633a"), hexc("c28a5a"), hexc("e0d0b0")], 0.045, (1, 1, 0.95)
            elif goods == "fish":
                cols, rr, sc = [hexc("8b9aa3"), hexc("a3adb3"), hexc("76858d")], 0.04, (3.2, 1, 0.7)
            else:
                cols, rr, sc = [hexc("6b3a6e"), hexc("4b2a5a")], 0.03, (1, 1, 1)   # grapes / plums
            # a heaped pile: a low mound in the dominant colour so the container reads full,
            # then items packed in rings (outer ring low, inner ring higher, one on top)
            base_c = vary(cols[0], 0.04)
            if goods not in ("fish", "bread", "carrot"):
                self.sphere(r * 0.92, (x, y, z + r * 0.05), PL, mix(base_c, (0, 0, 0), 0.2), scale=(1, 1, 0.32),
                            subdiv=0, grime=False, face_var=0.0, smooth=80)
            sub = 1 if goods == "cabbage" else 0
            n = n or 12
            rings = []
            rad = r - rr * 1.05
            lvl = 0
            while rad > rr * 0.6 and lvl < 3:
                cnt = max(1, int(math.tau * rad / (rr * 2.1)))
                rings.append((rad, cnt, lvl))
                rad -= rr * 1.9
                lvl += 1
            rings.append((0.0, 1, lvl))
            placed = 0
            for rad, cnt, lvl in rings:
                ph = random.uniform(0, math.tau)
                for j in range(cnt):
                    if n and placed >= n:
                        break
                    a = ph + j * math.tau / cnt + random.uniform(-0.12, 0.12)
                    px, py = x + math.cos(a) * rad, y + math.sin(a) * rad
                    pz = z + rr * sc[2] * 0.75 + lvl * rr * 1.1 * sc[2]
                    rot = (random.uniform(-0.3, 0.3), 0.0, a + random.uniform(-0.3, 0.3))
                    if goods == "carrot":
                        rot = (random.uniform(1.3, 1.8), 0, a)
                    elif goods in ("fish", "bread"):
                        rot = (0.0, 0.0, a + math.pi / 2)
                    self.sphere(rr, (px, py, pz), PL, vary(random.choice(cols), 0.1), scale=sc, subdiv=sub, rot=rot,
                                grime=False, smooth=70, face_var=0.0)
                    placed += 1

    def wheel(self, x, y, z=0.0, r=0.5, rz=0.0, lean=0.25):
        with self.detail():
            W, MT = self.M("Wood"), self.M("Metal")
            self.push((x, y, z + r * math.cos(lean)), (lean, 0, rz))
            self.ring(r - 0.07, r, 0.08, (0, 0, 0), W, hexc("6b4a2f"), segs=12)
            self.ring(r, r + 0.015, 0.07, (0, 0, 0), MT, IRON, segs=12)
            self.cyl(0.09, 0.16, (0, -0.08, 0), W, hexc("5a3e26"), rot=(-math.pi / 2, 0, 0), segs=8)
            for i in range(4):
                a = i * math.pi / 4
                self.box((2 * r - 0.1, 0.04, 0.045), (0, 0, 0), W, hexc("6b4a2f"), rot=(0, a, 0))
            self.pop()

    def chopping_block(self, x, y, axe=True):
        with self.detail():
            W, MT = self.M("Wood"), self.M("Metal")
            self.log((x, y, 0), (x, y, 0.5), 0.26, W, hexc("5a4330"), segs=9, noise_amt=0.02,
                     end_color=hexc("b89068"))
            if axe:
                self.bar((x + 0.02, y, 0.46), (x + 0.4, y - 0.35, 0.95), 0.04, 0.035, W, hexc("8a6a48"), up=(0, 0, 1))
                self.box((0.16, 0.03, 0.14), (x - 0.02, y + 0.03, 0.48), MT, hexc("6a6c70"), rot=(0, 0.3, 0.8), var=0)
            for i in range(3):
                a = random.uniform(0, math.tau)
                self.box((0.3, 0.07, 0.06), (x + math.cos(a) * 0.4, y + math.sin(a) * 0.4, 0.03), W,
                         vary(hexc("c79c68"), 0.1), rot=(0, 0, a + 1.3))

    def plant_pot(self, x, y, r=0.18, flowers=True):
        with self.detail():
            MA, PL = self.M("Matte"), self.M("Plant")
            self.cyl(r * 0.75, r * 1.3, (x, y, 0), MA, vary(hexc("a4553a"), 0.08), segs=10, r2=r)
            self.sphere(r * 1.05, (x, y, r * 1.5), PL, vary(hexc("4f7a34"), 0.12), scale=(1, 1, 0.9), subdiv=1,
                        noise_amt=0.03, grime=False)
            if flowers:
                fc = random.choice(self.p["flowers"])
                for i in range(4):
                    a = random.uniform(0, math.tau)
                    self.box((0.06, 0.06, 0.05), (x + math.cos(a) * r * 0.7, y + math.sin(a) * r * 0.7,
                                                 r * 1.5 + random.uniform(0.08, 0.16)), PL, vary(fc, 0.08),
                             rot=(0.6, 0.4, a), grime=False)

    def bush(self, x, y, r=0.45, h=None, c=None):
        with self.detail():
            c = c or hexc("4f7a34")
            h = h or r * 1.1
            for i in range(3):
                a = i * 2.1 + random.uniform(-0.3, 0.3)
                self.sphere(r * random.uniform(0.6, 0.8), (x + math.cos(a) * r * 0.35, y + math.sin(a) * r * 0.35,
                                                           h * 0.5 + random.uniform(-0.05, 0.1)),
                            self.M("Plant"), vary(c, 0.12), scale=(1, 1, h / r), subdiv=1, noise_amt=0.06, grime=False)
        with self.lod1_only():
            self.sphere(r * 0.95, (x, y, (h or r * 1.1) * 0.5), self.M("Plant"), c or hexc("4f7a34"), scale=(1, 1, (h or r * 1.1) / r), subdiv=1, var=0, grime=False)

    # ------------------------------------------------------------ round-6 dressing
    # Signs, banners, dormers, awnings, balconies, planters, ivy. Everything here
    # draws its randomness from self.prng so adding dressing never shifts a layout.
    def star_pts(self, r, n=4, inner=0.28, r2=None, phase=math.pi / 2):
        """Compass star outline (x, z): n long points, n short ones between."""
        pts = []
        r2 = r * 0.62 if r2 is None else r2
        for i in range(n * 4):
            a = phase + i * math.tau / (n * 4)
            k = i % 4
            rr = r if k == 0 else (r2 if k == 2 else r * inner)
            pts.append((math.cos(a) * rr, math.sin(a) * rr))
        return pts

    @isolated
    def emblem(self, kind, cx, cz, s, y, color, depth=0.02, mat=None):
        """Flat emblem in the XZ plane at depth y (wall/board frame), facing -Y."""
        MT = mat or self.M("Metal")
        if kind == "star":
            self.prism(self.star_pts(s), depth, (cx, y, cz), MT, color, var=0)
        elif kind == "cross":
            a, b = s, s * 0.34
            self.prism([(-b, -a), (b, -a), (b, -b), (a, -b), (a, b), (b, b), (b, a), (-b, a), (-b, b), (-a, b),
                        (-a, -b), (-b, -b)], depth, (cx, y, cz), MT, color, var=0)
        elif kind == "tankard":
            self.prism([(-0.5 * s, -0.8 * s), (0.4 * s, -0.8 * s), (0.45 * s, 0.6 * s), (-0.55 * s, 0.6 * s)], depth,
                       (cx, y, cz), MT, color, var=0)
            self.prism([(-0.62 * s, 0.55 * s), (0.52 * s, 0.55 * s), (0.45 * s, 0.9 * s), (0.1 * s, 1.0 * s),
                        (-0.3 * s, 0.95 * s), (-0.62 * s, 0.8 * s)], depth, (cx, y - 0.003, cz), MT,
                       mix(color, (1, 1, 1), 0.55), var=0)
            self.prism([(0.4 * s, 0.35 * s), (0.85 * s, 0.35 * s), (0.85 * s, -0.5 * s), (0.4 * s, -0.5 * s),
                        (0.4 * s, -0.3 * s), (0.65 * s, -0.3 * s), (0.65 * s, 0.15 * s), (0.4 * s, 0.15 * s)], depth,
                       (cx, y, cz), MT, color, var=0)
        elif kind == "anvil":
            self.prism([(-0.95 * s, 0.35 * s), (0.9 * s, 0.35 * s), (0.7 * s, 0.05 * s), (0.25 * s, 0.0),
                        (0.25 * s, -0.35 * s), (0.55 * s, -0.7 * s), (-0.55 * s, -0.7 * s), (-0.25 * s, -0.35 * s),
                        (-0.25 * s, 0.0), (-0.55 * s, 0.1 * s)], depth, (cx, y, cz), MT, color, var=0)
        elif kind == "shield":
            self.prism([(0, -1.0 * s), (0.7 * s, -0.45 * s), (0.75 * s, 0.7 * s), (-0.75 * s, 0.7 * s),
                        (-0.7 * s, -0.45 * s)], depth, (cx, y, cz), MT, color, var=0)
        elif kind == "leaf":
            self.prism([(0, -0.9 * s), (0.45 * s, -0.2 * s), (0.3 * s, 0.5 * s), (0, 0.9 * s), (-0.3 * s, 0.5 * s),
                        (-0.45 * s, -0.2 * s)], depth, (cx, y, cz), MT, color, var=0)

    @isolated
    def banner(self, x, ztop, w=0.9, h=2.2, color=None, trim=None, emblem="star", emb_c=None, y=-0.12,
               rod=True, tail="point"):
        """Hanging cloth banner on a rod (wall frame): coloured field, gold trim band,
        pointed or swallow-tail foot and a flat emblem. ~60 triangles."""
        CL, MT = self.M("Cloth"), self.M("Metal")
        color = color or hexc("2c4f96")
        trim = trim or hexc("d9a93c")
        emb_c = emb_c or trim
        if rod:
            self.box((w + 0.26, 0.05, 0.05), (x, y, ztop + 0.05), MT, IRON, var=0)
            for sx in (-1, 1):
                self.sphere(0.055, (x + sx * (w / 2 + 0.14), y, ztop + 0.05), MT, trim, subdiv=0, grime=False)
                self.box((0.04, abs(y) + 0.02, 0.04), (x + sx * (w / 2 + 0.05), y / 2, ztop + 0.05), MT, IRON,
                         var=0)
        hw = w / 2
        foot = [(hw, -h + 0.25), (0.0, -h), (-hw, -h + 0.25)] if tail == "point" else \
            [(hw, -h), (0.0, -h + 0.32), (-hw, -h)]
        self.prism([(-hw, 0.0), (hw, 0.0)] + foot, 0.025, (x, y, ztop), CL, color, var=0.02, grime=False)
        # trim bands (top + along the foot) and the emblem sit a hair proud of the cloth
        self.prism([(-hw, -0.04), (hw, -0.04), (hw, -0.13), (-hw, -0.13)], 0.012, (x, y - 0.018, ztop), CL, trim,
                   var=0, grime=False)
        fo = [(px, pz + 0.1) for px, pz in foot]
        self.prism([foot[0], fo[0], fo[1], foot[1]], 0.012, (x, y - 0.018, ztop), CL, trim, var=0, grime=False)
        self.prism([foot[1], fo[1], fo[2], foot[2]], 0.012, (x, y - 0.018, ztop), CL, trim, var=0, grime=False)
        if emblem:
            self.emblem(emblem, x, ztop - h * 0.45, min(w * 0.36, h * 0.2), y - 0.022, emb_c, depth=0.012,
                        mat=CL)

    @isolated
    def hanging_sign(self, x, z, emblem="tankard", board_c=None, emb_c=None, arm=1.25, size=0.8, lantern=True,
                     shape="shield", y0=0.0):
        """Iron bracket from the wall (wall frame) with a board hung square to the
        street (YZ plane) carrying the emblem on both faces, optional lantern."""
        MT, W = self.M("Metal"), self.M("Wood")
        board_c = board_c or hexc("5a3a24")
        emb_c = emb_c or hexc("e0b040")
        self.box((0.14, 0.08, 0.6), (x, y0 - 0.04, z - 0.1), MT, IRON, var=0)
        self.box((0.07, arm, 0.07), (x, y0 - arm / 2, z + 0.12), MT, IRON, var=0)
        self.bar((x, y0 - 0.05, z - 0.35), (x, y0 - arm * 0.62, z + 0.1), 0.045, 0.045, MT, IRON, bevel=0)
        with self.detail():
            self.cyl(0.13, 0.03, (x, y0 - arm * 0.45, z + 0.12), MT, IRON, rot=(0, math.pi / 2, 0), segs=8,
                     caps=False, base=False)
        bx = y0 - arm * 0.55
        for dy in (-size * 0.38, size * 0.38):
            self.box((0.02, 0.02, 0.2), (x, bx + dy, z + 0.0), MT, IRON, var=0)
        self.push((x, bx, z - 0.1 - size * 0.55), (0, 0, math.pi / 2))
        s = size / 2
        if shape == "shield":
            pts = [(0, -1.0 * s), (0.8 * s, -0.55 * s), (0.95 * s, 0.35 * s), (0.9 * s, 0.9 * s), (-0.9 * s, 0.9 * s),
                   (-0.95 * s, 0.35 * s), (-0.8 * s, -0.55 * s)]
        else:
            pts = [(-s, -s), (s, -s), (s, s), (-s, s)]
        self.prism([(px * 1.1, pz * 1.1) for px, pz in pts], 0.07, (0, 0, 0), MT, IRON, var=0)
        self.prism(pts, 0.09, (0, 0, 0), W, board_c, var=0.03)
        for sd in (-1, 1):
            self.emblem(emblem, 0, 0.02, s * 0.55, sd * 0.052, emb_c, depth=0.016)
        self.pop()
        if lantern:
            self.lantern((x, y0 - arm + 0.05, z + 0.08), s=0.85)

    @isolated
    def finial(self, x, y, z, h=0.55, color=None):
        """Turned timber / iron spike on a gable apex."""
        c = color or self.timber()
        W = self.M("Wood")
        self.cyl(0.07, h * 0.45, (x, y, z), W, c, segs=6, var=0)
        self.sphere(0.1, (x, y, z + h * 0.5), W, c, subdiv=0, scale=(1, 1, 1.2), grime=False)
        self.cyl(0.06, h * 0.45, (x, y, z + h * 0.55), W, c, segs=6, r2=0.0, var=0)

    @isolated
    def dormer(self, u, eave, run, rise, cy=0.0, side=-1, along="x", w=1.3, wall_h=1.25, inset=0.8, pitch=50,
               kind=None, style="timber", flowers=True, win_w=None):
        """Gable dormer on a roof slope. The slope rises from the eave line (height
        `eave`, horizontal distance `run` from the ridge line at `cy`) to the ridge
        (`rise` above the eave). side=-1 is the slope facing -Y (along="x") or -X
        (along="y"); u is the position along the ridge. `inset` = how far up the
        slope (horizontally, from the eave) the dormer front stands."""
        tanp = rise / run
        W, P = self.M("Wood"), self.M("Plaster")
        kind = kind or ("slate" if self.p.get("roof_kind", "").startswith("slate") else "shingle")
        # local frame: x along the ridge (u), -Y = down-slope outward, z world height
        if along == "x":
            self.push((u, cy + side * run, 0.0), (0, 0, 0 if side < 0 else math.pi))
        else:
            self.push((cy + side * run, u, 0.0), (0, 0, -math.pi / 2 if side < 0 else math.pi / 2))
        yf = inset                      # dormer front, measured in from the eave line
        zs = eave + yf * tanp           # roof surface at the front
        z0 = zs - 0.12
        zt = zs + wall_h
        yb = yf + (zt - eave) / tanp - yf + 0.25   # back end, buried in the roof
        yb = (zt - eave) / tanp + 0.25
        hw = w / 2
        dp = math.tan(math.radians(pitch))
        apex = zt + hw * dp
        # front wall (plaster/boards) with a window, cheeks and a small gable
        win_w = win_w or min(0.75, w - 0.5)
        wz0 = z0 + 0.3
        wh = min(0.8, wall_h - 0.45)
        self.push((0, yf, 0))
        # plaster face with a real opening, dark backing behind it (the room)
        self.panel_wall(w, wall_h + 0.12, (0, 0, z0), P, self.p["plaster"], cell=0.6,
                        holes=[(-win_w / 2, wz0 - z0, win_w / 2, wz0 - z0 + wh)])
        self.box((w - 0.1, 0.06, wall_h), (0, 0.22, z0 + wall_h / 2), self.M("Matte"), MORTAR, var=0)
        self.prism([(-hw, 0), (hw, 0), (0, apex - zt)], 0.12, (0, 0.06, zt), P, self.p["plaster"], var=0)
        for sx in (-1, 1):
            self.box((0.13, 0.13, wall_h + 0.1), (sx * (hw - 0.065), -0.02, z0 + (wall_h + 0.1) / 2), W,
                     self.timber(), var=0)
        self.box((w + 0.06, 0.14, 0.14), (0, -0.02, zt - 0.02), W, self.timber(), var=0)
        self.window(0, wz0, win_w, wh, depth=0.1, flowers=flowers, panes=(2, 2))
        self.pop()
        # cheeks: triangles from the front wall back to the roof surface
        for sx in (-1, 1):
            pts = [(yf, z0), (yb, zt), (yf, zt)]
            self.push((sx * hw, 0, 0), (0, 0, math.pi / 2))
            self.prism([(p0, p1) for p0, p1 in pts], 0.1, (0, sx * 0.05, 0), P, mix(self.p["plaster"],
                       (0.5, 0.5, 0.5), 0.08), var=0)
            self.pop()
        # mini gable roof, ridge running up-slope (local +Y)
        mrun = hw + 0.22
        mrise = mrun * dp
        self.push((0, 0, zt - 0.22 * dp))
        for sd in (-1, 1):
            a0, a1 = (yf - 0.28, yb) if sd < 0 else (-yb, -(yf - 0.28))
            self.shingle_side(a0, a1, mrun, mrise, self.M("Roof"), self.tile,
                              tile_w=(0.22, 0.36), course=0.24, th=0.022, deck_mat=W, deck_color=self.timber(),
                              rot=(0, 0, -sd * math.pi / 2))
        self.pop()
        self.bar((0, yf - 0.3, apex + 0.04), (0, yb, apex + 0.04), 0.1, 0.08, self.M("Roof"),
                 mix(self.p["roof"][0], (0, 0, 0), 0.3), bevel=0)
        for sx in (-1, 1):   # barge boards
            self.bar((sx * (mrun + 0.02), yf - 0.29, zt - 0.22 * dp - 0.05), (0, yf - 0.29, apex + 0.02), 0.16, 0.05,
                     W, self.timber(), up=(0, 0, 1), bevel=0)
        self.finial(0, yf - 0.3, apex + 0.05, h=0.4)
        self.pop()

    @isolated
    def striped_awning(self, x0, x1, z_wall, run, drop, colors, y=0.0, valance=0.2, posts=False, scallop=True,
                       sag=0.08):
        """Canvas awning out from a wall (wall frame, face at y=0): stripes run down
        the slope, sagging cloth, scalloped valance, iron/timber support arms."""
        CL, W = self.M("Cloth"), self.M("Wood")
        width = x1 - x0
        ns = max(2, round(width / 0.45))
        sw = width / ns
        zf = z_wall - drop
        for i in range(ns):
            c = colors[i % len(colors)]
            a0 = x0 + i * sw

            def sg(u, v, i=i):
                gu = (i + u) / ns
                return (0, 0, -sag * math.sin(math.pi * v) * (0.6 + 0.4 * math.sin(math.pi * gu)))
            self.sheet(((a0, y - run, zf), (a0 + sw, y - run, zf), (a0, y - 0.02, z_wall), (a0 + sw, y - 0.02, z_wall)),
                       1, 3, CL, lambda u, v, c=c: tuple(ch * (0.9 + 0.1 * v) for ch in c), sag_fn=sg, smooth=None)
            pts = [(0, 0), (sw, 0), (sw, -valance)]
            if scallop:
                for j in range(1, 4):
                    a = j / 4 * math.pi
                    pts.append((sw / 2 + math.cos(a) * sw / 2, -valance - math.sin(a) * valance * 0.45))
            pts.append((0, -valance))
            self.prism(pts, 0.012, (a0, y - run, zf + 0.004), CL, c, var=0.02, grime=False)
        self.bar((x0 - 0.03, y - run, zf + 0.02), (x1 + 0.03, y - run, zf + 0.02), 0.04, 0.04, W, self.timber(),
                 up=(0, 0, 1), bevel=0)
        for xx in (x0 + 0.05, x1 - 0.05):
            if posts:
                self.bar((xx, y - run + 0.02, 0.0), (xx, y - run + 0.02, zf + 0.04), 0.1, 0.1, W, self.timber(),
                         bevel=0.012)
            else:
                self.bar((xx, y - 0.02, zf - 0.55), (xx, y - run + 0.05, zf), 0.04, 0.04, self.M("Metal"), IRON,
                         bevel=0)

    @isolated
    def balcony(self, x0, x1, z, depth, y=0.0, rail_h=0.95, posts_to_ground=True, flowers=True, returns=True):
        """Timber balcony along a wall (wall frame): plank deck on joists, turned
        balusters in groups, a top rail, flower boxes on the rail, optional posts."""
        W = self.M("Wood")
        tc = self.timber()
        self.box((x1 - x0, depth, 0.12), ((x0 + x1) / 2, y - depth / 2, z - 0.06), W, mix(tc, (1, 1, 1), 0.12),
                 bevel=0.02)
        with self.detail():
            n = max(3, round((x1 - x0) / 0.6))
            for i in range(n + 1):
                xx = x0 + 0.1 + i * (x1 - x0 - 0.2) / n
                self.box((0.12, depth + 0.05, 0.12), (xx, y - depth / 2, z - 0.18), W, tc, var=0)
        yf = y - depth + 0.06
        self.box((x1 - x0 + 0.08, 0.1, 0.1), ((x0 + x1) / 2, yf, z + rail_h), W, tc, bevel=0.015)
        self.box((x1 - x0, 0.08, 0.07), ((x0 + x1) / 2, yf, z + 0.12), W, tc, var=0)
        nb = max(4, round((x1 - x0) / 0.24))
        with self.detail():
            for i in range(nb):
                xx = x0 + 0.12 + i * (x1 - x0 - 0.24) / (nb - 1)
                self.box((0.05, 0.05, rail_h - 0.1), (xx, yf, z + 0.12 + (rail_h - 0.1) / 2), W, tc, var=0)
        with self.lod1_only():
            self.box((x1 - x0 - 0.1, 0.03, rail_h - 0.1), ((x0 + x1) / 2, yf, z + 0.12 + (rail_h - 0.1) / 2), W,
                     mix(tc, (0, 0, 0), 0.25), var=0)
        if returns:
            for xx in (x0 + 0.04, x1 - 0.04):
                self.box((0.08, depth - 0.06, 0.1), (xx, y - depth / 2 + 0.03, z + rail_h), W, tc, var=0)
                with self.detail():
                    for j in range(max(1, int(depth / 0.3))):
                        self.box((0.05, 0.05, rail_h - 0.1), (xx, y - 0.2 - j * 0.3, z + 0.12 + (rail_h - 0.1) / 2),
                                 W, tc, var=0)
        if posts_to_ground:
            np_ = max(2, round((x1 - x0) / 2.6) + 1)
            for i in range(np_):
                xx = x0 + 0.1 + i * (x1 - x0 - 0.2) / (np_ - 1)
                self.box((0.18, 0.18, z - 0.12), (xx, yf, (z - 0.12) / 2), W, tc, bevel=0.02)
                with self.detail():
                    self.bar((xx, yf, z - 0.8), (xx, y - 0.05, z - 0.14), 0.1, 0.1, W, tc, up=(0, 1, 1), bevel=0)
        if flowers:
            nf = max(1, int((x1 - x0) / 2.2))
            for i in range(nf):
                fx = x0 + (i + 0.5) * (x1 - x0) / nf
                self.flower_box(fx, z + rail_h + 0.22, min(1.2, (x1 - x0) / nf - 0.3), y=yf - 0.12)

    @isolated
    def ivy(self, pts, width=0.35, density=1.0, color=None, y=-0.06):
        """Climbing ivy along a polyline of (x, z) points on a wall (wall frame): a few
        flattened, noisy leaf clumps (low icospheres). Cheap: ~20-80 tris per clump."""
        PL = self.M("Plant")
        pts = [(p[0], 0.0, p[1]) if len(p) == 2 else p for p in pts]
        base = color or hexc("4d7d34")
        rng = self.prng
        with self.detail():
            for a, b in zip(pts[:-1], pts[1:]):
                a, b = Vector(a), Vector(b)
                L = (b - a).length
                n = max(1, int(L / 0.42 * density))
                for i in range(n):
                    p = a + (b - a) * ((i + rng.random()) / n)
                    r = width * rng.uniform(0.35, 0.6)
                    c = mix(base, hexc("78a83f") if rng.random() < 0.4 else hexc("2f5a26"), rng.uniform(0, 0.5))
                    self.sphere(r, (p.x + rng.uniform(-0.1, 0.1), y - r * 0.3, p.z), PL, c,
                                scale=(1.0, 0.45, 0.85), subdiv=1, var=0, noise_amt=r * 0.35, grime=False, smooth=None)
        with self.lod1_only():
            for a, b in zip(pts[:-1], pts[1:]):
                a, b = Vector(a), Vector(b)
                m = (a + b) / 2
                L = (b - a).length
                ang = math.atan2(b.z - a.z, b.x - a.x)
                self.box((L + width * 0.6, 0.12, width * 0.9), (m.x, y - 0.04, m.z), PL, base, rot=(0, -ang, 0), var=0,
                         grime=False)

    @isolated
    def planter(self, x, y, L=0.9, D=0.4, H=0.4, rz=0.0, flowers=None, box_c=None, kind="box"):
        """Wooden planter box (or clay pot when kind='pot') with a mound of foliage
        and a few flower heads. ~150 tris."""
        W, PL = self.M("Wood"), self.M("Plant")
        rng = self.prng
        fl = flowers or rng.sample(self.p["flowers"], 2)
        self.push((x, y, 0), (0, 0, rz))
        if kind == "pot":
            r = L / 2
            self.cyl(r * 0.72, H, (0, 0, 0), self.M("Matte"), vary(hexc("b8623e"), 0.0), segs=8, r2=r, var=0)
            self.cyl(r + 0.02, 0.06, (0, 0, H - 0.06), self.M("Matte"), hexc("a4553a"), segs=8, var=0, caps=False)
            top_w, top_d = L * 0.9, L * 0.9
        else:
            c = box_c or vary(hexc("7a5634"), 0.0)
            self.box((L, D, H), (0, 0, H / 2), W, c, var=0)
            with self.detail():
                for sx in (-1, 1):
                    self.box((0.06, D + 0.03, H + 0.02), (sx * (L / 2 - 0.02), 0, H / 2), W, mix(c, (0, 0, 0), 0.25),
                             var=0)
            top_w, top_d = L - 0.06, D - 0.06
        greens = [hexc("4f8a34"), hexc("5f9a3a"), hexc("3f7a2e"), hexc("6fa044")]
        n = max(2, round(top_w / 0.28))
        for i in range(n):
            fx = -top_w / 2 + (i + 0.5) * top_w / n
            r = rng.uniform(0.13, 0.18) * (top_d / 0.34) ** 0.3
            self.sphere(r, (fx, rng.uniform(-0.04, 0.04), H + r * 0.35), PL, rng.choice(greens),
                        scale=(1.2, 1.0, 0.8), subdiv=1, var=0, noise_amt=0.02, grime=False, smooth=180, face_var=0.0)
            with self.detail():
                for j in range(3):
                    a = rng.uniform(0, math.tau)
                    self.box((0.07, 0.07, 0.06), (fx + math.cos(a) * r * 0.7, math.sin(a) * r * 0.6,
                                                  H + r * 0.7 + rng.uniform(0.0, 0.08)), PL, fl[j % len(fl)],
                             rot=(0.6, 0.4, a), var=0, grime=False)
        self.pop()

    def stage(self, name):
        """Triangle count per build stage (printed when RA_STAGES is set)."""
        if not os.environ.get("RA_STAGES"):
            return
        ly = self.lodl
        l0 = sum(len(f.verts) - 2 for f in self.bm.faces if not f[ly] & 2)
        l1 = sum(len(f.verts) - 2 for f in self.bm.faces if not f[ly] & 1)
        p0, p1 = getattr(self, "_last_tris", (0, 0))
        print(f"  stage {name:<14} lod0 +{l0 - p0:<6} lod1 +{l1 - p1}")
        self._last_tris = (l0, l1)

    def finish_checked(self, fp, budget, **kw):
        """Build/export (see Kit.finish), then print footprint + tris of the exported
        LOD0 and fail loudly if over the size or triangle budget."""
        self.finish(**kw)
        (x0, y0, z0), (x1, y1, z1) = self.stats["bounds"]
        tris = self.stats["tris0"]
        extra = "".join(f"  lod{i} {self.stats['tris' + str(i)]}" for i in (1, 2) if f"tris{i}" in self.stats)
        print(f"footprint: x {x0:.2f}..{x1:.2f} ({x1 - x0:.2f} m)  y {y0:.2f}..{y1:.2f} ({y1 - y0:.2f} m)  "
              f"height {z1:.2f} m  triangles {tris}{extra}")
        ok = True
        if x1 - x0 > fp[0] + 0.05 or y1 - y0 > fp[1] + 0.05:
            print(f"WARNING footprint over {fp[0]} x {fp[1]}")
            ok = False
        if tris > budget:
            print(f"WARNING triangles over budget {budget}")
            ok = False
        return ok
