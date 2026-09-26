"""Town wall: a straight 8 m curtain-wall section that tiles end to end along X.

Coursed grey rubble on both faces, a battered plinth with a chamfered string
course on the outer face, a crenellated outer parapet (merlons with arrow
slits, dressed copings in the crenels), a flagstone wall-walk, a low inner
parapet with a coping, putlog holes, a drain spout and moss at the foot.

Run: python3 make_town_wall.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. The section spans x in [-4, 4] exactly (8.0 m); the
merlon pattern (1.1 m merlon + 0.5 m crenel, 1.6 m period) starts and ends
with a half crenel and all courses have the same heights in every section,
so sections placed every 8.0 m along X join seamlessly. Wall body 2.4 m thick
(y in [-1.2, 1.2]) plus the plinth batter (to y=-1.5). Wall-walk at z=5.2,
merlon tops at 7.0 m. The OUTER (field) face is the front, Blender -Y
(Godot +Z); the town side is +Y. End faces are closed so a run can stop
anywhere (normally at a town_wall_tower or the town_gate).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK, palette, IRON, MORTAR, WALLSTONE, rect_hole
from ra_kit import hexc, vary, mix

k = TK("TownWall", seed=77, pal=palette(stone="grey"))
k.p["stone"] = WALLSTONE
MA, PL = k.M("Matte"), k.M("Plant")
k.grime = 1.4
k.grime_amt = 0.28
HL, T = 4.0, 1.2           # half length, half thickness
WALK = 5.2
BREAST = 6.1               # top of the parapet breast (crenel sill)
TOP = 7.0
PT_OUT, PT_IN = 0.6, 0.38  # parapet thicknesses
BAT_H, BAT_OUT = 1.3, 0.3
BW, BH = 0.72, 0.4

def st():
    c = k.stone()
    if random.random() < 0.06:
        c = mix(c, hexc("5d6b3e"), 0.35)
    return c

# ---------------------------------------------------------------- core
k.box((2 * HL, 2 * T - 0.3, WALK - 0.05), (0, 0, (WALK - 0.05) / 2), MA, MORTAR, var=0, grime=False)
k.box((2 * HL, PT_OUT - 0.16, BREAST - WALK + 0.1), (0, -T + PT_OUT / 2, (WALK + BREAST) / 2 - 0.05), MA, MORTAR,
      var=0, grime=False)
k.box((2 * HL, PT_IN - 0.14, 0.6), (0, T - PT_IN / 2, WALK + 0.3), MA, MORTAR, var=0, grime=False)

# ---------------------------------------------------------------- outer (field) face
ang = math.atan2(BAT_OUT, BAT_H)
k.stone_face(2 * HL, BAT_H / math.cos(ang), loc=(0, -T - BAT_OUT, 0), rot=(-ang, 0, 0), bw=1.0, bh=0.5, rows=3,
             color_fn=lambda: mix(st(), MORTAR, 0.12), push=0.03, sub=None)
k.box((2 * HL, 0.3, BAT_H + 0.02), (0, -T + 0.1, BAT_H / 2), MA, MORTAR, var=0, grime=False)
# chamfered string course on top of the batter
for i in range(8):
    x0 = -HL + i * 1.0
    k.push((x0 + 0.5, -T - 0.02, BAT_H - 0.02), (0, 0, math.pi / 2))
    k.prism([(-0.14, 0.0), (0.12, 0.0), (0.12, 0.18), (-0.02, 0.18), (-0.14, 0.1)], 0.985, (0, 0, 0), MA,
            vary(k.dressed(0.3), 0.04), var=0)
    k.pop()
holes = [rect_hole(-2.6, 2.1, -2.35, 2.35), rect_hole(1.3, 2.1, 1.55, 2.35), rect_hole(-0.7, 3.85, -0.45, 4.1),
         rect_hole(3.0, 3.85, 3.25, 4.1)]
k.stone_face(2 * HL, BREAST - BAT_H - 0.18, loc=(0, -T, BAT_H + 0.18), holes=holes, bw=BW, bh=BH, rows=11,
             color_fn=st)
for hl in holes:   # putlog holes: dark sockets
    k.quad(0.25, 0.25, ((hl["x0"] + hl["x1"]) / 2, -T + 0.12, hl["z0"] + BAT_H + 0.18 + 0.125), MA,
           hexc("1b1917"), var=0, grime=False)
# drain spout through the parapet at walk level
k.box((0.3, 0.7, 0.18), (0.4, -T - 0.2, WALK + 0.02), MA, k.dressed(0.25), var=0)
k.box((0.14, 0.72, 0.03), (0.4, -T - 0.2, WALK + 0.115), MA, hexc("2a2622"), var=0, grime=False)

# ---------------------------------------------------------------- inner (town) face
with k.side("back", HL, T):
    k.stone_face(2 * HL, WALK, loc=(0, 0, 0), bw=BW, bh=BH, rows=13, color_fn=st,
                 holes=[rect_hole(-1.9, 2.95, -1.65, 3.2), rect_hole(2.2, 2.95, 2.45, 3.2)])
    for x in (-1.775, 2.325):
        k.quad(0.25, 0.25, (x, 0.12, 3.075), MA, hexc("1b1917"), var=0, grime=False)
    # low inner parapet: outer (town-facing) side continues, then coping
    k.stone_face(2 * HL, 0.6, loc=(0, 0, WALK), bw=BW, bh=0.3, rows=2, color_fn=st)
    k.box((2 * HL, PT_IN + 0.06, 0.14), (0, PT_IN / 2 - 0.03, WALK + 0.67), MA, k.dressed(0.25), var=0)
    # walk-facing side of the inner parapet
    k.push((0, PT_IN, 0), (0, 0, math.pi))
    k.stone_face(2 * HL, 0.6, loc=(0, 0, WALK), bw=BW, bh=0.3, rows=2, color_fn=st)
    k.pop()

# ---------------------------------------------------------------- walk + outer parapet
k.flagstones(-HL, HL, -T + PT_OUT, T - PT_IN, WALK, size=(0.9, 0.55))
# walk side of the outer parapet
k.push((0, -T + PT_OUT, 0), (0, 0, math.pi))
k.stone_face(2 * HL, BREAST - WALK, loc=(0, 0, WALK), bw=BW, bh=0.3, rows=3, color_fn=st)
k.pop()
# crenel sills (dressed coping between merlons) and merlons
MW, CW = 1.1, 0.5
for i in range(6):
    xc = -HL + i * (MW + CW)            # crenel centres at -4, -2.4, ... 4 (ends are half crenels)
    a, b = max(-HL, xc - CW / 2 - 0.05), min(HL, xc + CW / 2 + 0.05)
    k.box((b - a, PT_OUT + 0.08, 0.14), ((a + b) / 2, -T + PT_OUT / 2 - 0.04, BREAST + 0.02), MA, k.dressed(0.3),
          var=0)
k.merlons(-HL, HL, BREAST, h=TOP - BREAST, th=PT_OUT, mw=MW, cw=CW, y=-T - 0.02, slits=0.5)

# ---------------------------------------------------------------- end faces (closed ends)
for s in ("left", "right"):
    with k.side(s, HL, T) as L:
        k.stone_face(2 * T, WALK, loc=(0, 0, 0), bw=0.7, bh=BH, rows=13, color_fn=st)
        k.stone_face(PT_OUT, BREAST - WALK, loc=((-T + PT_OUT / 2) * (1 if s == "right" else -1), 0, WALK), bw=0.6,
                     bh=0.3, rows=3, color_fn=st)

# ---------------------------------------------------------------- moss / grass at the foot
GR = [hexc("5f8a3e"), hexc("6f9448"), hexc("7f9a50"), hexc("4f7a34")]
for side, y in ((-1, -T - BAT_OUT - 0.05), (1, T + 0.05)):
    for i in range(10):
        x = random.uniform(-HL + 0.3, HL - 0.3)
        for j in range(4):
            k.cyl(random.uniform(0.014, 0.024), random.uniform(0.15, 0.4),
                  (x + random.uniform(-0.15, 0.15), y + side * random.uniform(0, 0.1), 0.0), PL,
                  vary(random.choice(GR), 0.1), segs=3, r2=0.0,
                  rot=(random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4), random.uniform(0, 3)), grime=False,
                  smooth=None, caps=False)

k.finish_checked((8.1, 3.3), 15000, cam_dir=(0.9, -1.6, 0.55), fit=0.95)
