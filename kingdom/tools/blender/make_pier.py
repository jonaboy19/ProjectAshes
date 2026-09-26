"""Wooden pier / fishing dock: log pilings driven 2 m below the origin, cap
beams, stringers and cross-bracing, a weathered plank deck (a few replaced
planks), kerbs, mooring bollards with rope, rope coils, a ladder down to the
water, a lantern post, a crate and a stone shore abutment.

Run: python3 make_pier.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Deck 4.0 m wide (X) x 18.0 m long (Y), deck top at
z=+0.20. Origin at the centre of the deck footprint at shore-ground height
z=0. Pilings go down to z=-2.0; design water surface is z=-0.6 (the algae
band on the pilings sits there), so place the water plane 0.5-0.8 m below the
origin. The landward end (stone abutment) is at +Y; the seaward end with the
ladder and lantern faces Blender -Y = Godot +Z.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ra_kit import Kit, hexc, vary, mix

k = Kit("Pier", seed=5)
k.grime_amt = 0.0     # we colour the waterline ourselves
WOOD = k.material("Wood", rough=0.8)
DECK = k.material("Deck", rough=0.85)
ROPE = k.material("Rope", rough=1.0, spec=0.2)
STONE = k.material("Stone", rough=0.92)
METAL = k.material("Metal", rough=0.4, metal=1.0)
GLASS = k.material("Glass", rough=0.2, emission=hexc("ffc070"), strength=2.0)

LEN, WID = 18.0, 4.0
TOP = 0.20
WATER = -0.6
PILE = hexc("5e4a36")
BEAM = hexc("6b5139")
PLANKS = [hexc("9c7b56"), hexc("8d6d4a"), hexc("a88663"), hexc("7f6346"), hexc("b09070")]
NEW_PLANK = hexc("c7a57a")
ROPE_C = hexc("b89c6a")

def wet(c, z):
    """Darken below the waterline, green algae band just above/below it."""
    if z < WATER - 0.35:
        return mix(c, hexc("24302a"), 0.65)
    if z < WATER + 0.15:
        return mix(c, hexc("3f5a35"), 0.6)
    if z < WATER + 0.5:
        return mix(c, hexc("3a3a30"), 0.3)
    return c

# ------------------------------------------------------------------ pilings + frame
bays = 7
ys = [-LEN / 2 + 0.3 + i * (LEN - 0.6) / bays for i in range(bays + 1)]
PX = WID / 2 - 0.12
for i, y in enumerate(ys):
    for sx in (-1, 1):
        top = TOP - 0.06
        k.log((sx * PX + random.uniform(-0.03, 0.03), y + random.uniform(-0.03, 0.03), -2.0),
              (sx * PX, y, top), 0.15, WOOD, vary(PILE, 0.1), segs=9, noise_amt=0.02, zfn=wet)
    # cap beam across each piling pair
    k.box((WID + 0.2, 0.22, 0.2), (0, y, TOP - 0.16), WOOD, vary(BEAM, 0.08), bevel=0.02,
          color_fn=None)
    # cross brace between the pair (below deck, above water mostly)
    if i % 2 == 0:
        k.beam((-PX, y + 0.1, WATER - 0.4), (PX, y + 0.1, TOP - 0.3), 0.1, WOOD, mix(BEAM, (0.1, 0.1, 0.08), 0.3),
               bevel=0.0, width=0.08)
    else:
        k.beam((PX, y + 0.1, WATER - 0.4), (-PX, y + 0.1, TOP - 0.3), 0.1, WOOD, mix(BEAM, (0.1, 0.1, 0.08), 0.3),
               bevel=0.0, width=0.08)
# stringers along the length
for x in (-PX, -0.65, 0.65, PX):
    k.box((0.14, LEN - 0.2, 0.18), (x, 0, TOP - 0.13 - 0.12), WOOD, vary(BEAM, 0.08))
# longitudinal diagonal braces on the outer piling lines
for sx in (-1, 1):
    for i in range(bays):
        y0, y1 = ys[i], ys[i + 1]
        if i % 2:
            y0, y1 = y1, y0
        k.beam((sx * (PX + 0.12), y0, WATER - 0.2), (sx * (PX + 0.12), y1, TOP - 0.28), 0.1, WOOD,
               mix(BEAM, (0.1, 0.1, 0.08), 0.25), bevel=0.0, width=0.08)

# ------------------------------------------------------------------ deck planks
y = -LEN / 2
while y < LEN / 2 - 0.1:
    w = random.uniform(0.2, 0.26)
    c = random.choice(PLANKS)
    if random.random() < 0.06:
        c = NEW_PLANK                          # a recently replaced plank
    c = vary(c, 0.06, 0.03)
    length = WID + random.uniform(-0.12, 0.06)
    k.box((length, w - 0.02, 0.05), (random.uniform(-0.04, 0.04), y + w / 2, TOP - 0.025 + random.uniform(-0.006, 0.006)),
          DECK, c, rot=(random.uniform(-0.01, 0.01), 0, random.uniform(-0.01, 0.01)), bevel=0.006, var=0,
          face_var=0.0)
    # nail heads
    for sx in (-1, 1):
        k.quad(0.025, 0.025, (sx * PX, y + w / 2, TOP + 0.002), METAL, hexc("3a3632"), rot=(-math.pi / 2, 0, 0), var=0)
    y += w
# kerbs
for sx in (-1, 1):
    k.box((0.14, LEN - 0.4, 0.12), (sx * (WID / 2 - 0.1), 0.2, TOP + 0.06), WOOD, vary(BEAM, 0.05), bevel=0.015)

# ------------------------------------------------------------------ bollards, rope, ladder, lantern
def bollard(x, y, h=0.85):
    k.log((x, y, -2.0), (x, y, TOP + h), 0.19, WOOD, vary(PILE, 0.08), segs=10, noise_amt=0.015, zfn=wet)
    k.cyl(0.21, 0.08, (x, y, TOP + h - 0.02), WOOD, mix(PILE, (0.8, 0.7, 0.5), 0.3), segs=10, r2=0.17)
    for j in range(4):   # rope turns
        k.cyl(0.215, 0.05, (x, y, TOP + 0.3 + j * 0.055), ROPE, vary(ROPE_C, 0.05), segs=10, caps=False,
              rot=(random.uniform(-0.08, 0.08), random.uniform(-0.08, 0.08), 0))
for (bx, by) in ((-WID / 2 + 0.05, -LEN / 2 + 0.25), (WID / 2 - 0.05, -LEN / 2 + 0.25),
                 (-WID / 2 + 0.05, -1.0), (WID / 2 - 0.05, 3.5)):
    bollard(bx, by)
# a rope hanging from a bollard down to the water
k.beam((WID / 2 + 0.12, -LEN / 2 + 0.25, TOP + 0.35), (WID / 2 + 0.55, -LEN / 2 - 0.4, WATER + 0.05), 0.04, ROPE,
       ROPE_C, bevel=0)

def rope_coil(x, y, r=0.32, turns=4):
    for j in range(turns):
        rr = r - j * 0.02
        t_ring = 0.045
        k.ring(rr - t_ring, rr, 0.05, (x, y, TOP + 0.025 + j * 0.045), ROPE, vary(ROPE_C, 0.06),
               rot=(math.pi / 2, 0, random.uniform(0, 1)), segs=14)
rope_coil(-1.2, -6.6)
rope_coil(1.1, 1.8, r=0.28, turns=3)

# ladder on the seaward end, +X side
LX = 1.0
for sx in (-1, 1):
    k.box((0.07, 0.07, TOP + 2.0 + 0.8), (LX + sx * 0.25, -LEN / 2 - 0.1, (TOP + 0.8 - 2.0) / 2), WOOD,
          vary(BEAM, 0.05), color_fn=lambda f: wet(BEAM, f.calc_center_median().z))
z = TOP - 0.3
while z > -1.9:
    k.box((0.5, 0.05, 0.05), (LX, -LEN / 2 - 0.1, z), WOOD, wet(BEAM, z))
    z -= 0.32
for sx in (-1, 1):
    k.cyl(0.035, 0.6, (LX + sx * 0.25, -LEN / 2 - 0.1, TOP + 0.8), METAL, hexc("6b645a"), rot=(math.pi / 2, 0, 0),
          segs=6)

# lantern post near the end
LPX, LPY = -WID / 2 + 0.25, -LEN / 2 + 1.4
k.box((0.14, 0.14, 2.3), (LPX, LPY, TOP + 1.15), WOOD, vary(BEAM, 0.05), bevel=0.015)
k.box((0.06, 0.55, 0.06), (LPX, LPY - 0.22, TOP + 2.2), WOOD, BEAM)
k.box((0.04, 0.04, 0.12), (LPX, LPY - 0.45, TOP + 2.12), METAL, hexc("2e2d2c"))
k.box((0.22, 0.22, 0.05), (LPX, LPY - 0.45, TOP + 2.03), METAL, hexc("2e2d2c"))
k.box((0.16, 0.16, 0.26), (LPX, LPY - 0.45, TOP + 1.88), GLASS, hexc("ffd08a"), var=0)
k.cyl(0.17, 0.12, (LPX, LPY - 0.45, TOP + 2.02), METAL, hexc("2e2d2c"), segs=4, r2=0.02, rot=(0, 0, math.pi / 4))
k.box((0.2, 0.2, 0.04), (LPX, LPY - 0.45, TOP + 1.74), METAL, hexc("2e2d2c"))

# crate + fish basket
k.cyl(0.25, 0.3, (0.55, -4.9, TOP), WOOD, hexc("b89a64"), segs=10, r2=0.3)
k.sphere(0.26, (0.55, -4.9, TOP + 0.28), WOOD, hexc("8fa0a8"), scale=(1, 1, 0.3), subdiv=1)

# buoys hanging off the +X kerb
for i, by in enumerate((-2.6, -2.0, 0.2)):
    bz = TOP - 0.55 - 0.1 * i
    k.beam((WID / 2 - 0.05, by, TOP + 0.1), (WID / 2 + 0.1, by, bz + 0.25), 0.02, ROPE, ROPE_C, bevel=0)
    k.sphere(0.2, (WID / 2 + 0.12, by, bz), WOOD, hexc("d8452f") if i != 1 else hexc("f0ece0"), scale=(1, 1, 1.25),
             subdiv=2, smooth=70)
    k.cyl(0.205, 0.08, (WID / 2 + 0.12, by, bz - 0.04), WOOD, hexc("f0ece0") if i != 1 else hexc("d8452f"), segs=12,
          caps=False)

# fishing net draped over the -X kerb, with cork floats
import bmesh
from mathutils import Vector, noise as mnoise
nt = bmesh.new()
NU, NV = 12, 9
verts = []
for j in range(NV + 1):
    row = []
    for i in range(NU + 1):
        u = i / NU
        v = j / NV
        y = -3.2 + u * 2.4 + mnoise.noise(Vector((u * 3, v * 3, 1))) * 0.08
        if v < 0.45:            # lying on the deck
            x = -WID / 2 + 0.2 + (0.45 - v) * 1.6
            z = TOP + 0.02 + max(0.0, mnoise.noise(Vector((u * 4, v * 4, 2)))) * 0.08
        elif v < 0.6:           # over the kerb
            x = -WID / 2 + 0.1 - (v - 0.45) * 0.8
            z = TOP + 0.14
        else:                   # hanging down the side
            x = -WID / 2 - 0.05 - (v - 0.6) * 0.1
            z = TOP + 0.12 - (v - 0.6) * 2.0 - math.sin(u * math.pi) * 0.25 * (v - 0.6)
        row.append(nt.verts.new((x, y, z)))
    verts.append(row)
for j in range(NV):
    for i in range(NU):
        nt.faces.new((verts[j][i], verts[j][i + 1], verts[j + 1][i + 1], verts[j + 1][i]))
k._merge(nt, ROPE, hexc("4d5a4a"), None, 60, 0.08, None, False)
for i in range(5):
    k.sphere(0.06, (-WID / 2 - 0.06, -3.1 + i * 0.55, TOP - 0.62 - math.sin(i / 4 * math.pi) * 0.1), WOOD,
             hexc("c89a5a"), scale=(1, 1.6, 1), subdiv=1)

# second crate and a barrel near the shore end
k.box((0.6, 0.6, 0.5), (1.35, -4.2, TOP + 0.25), WOOD, hexc("8f6c48"), bevel=0.03, rot=(0, 0, -0.2))
k.box((0.55, 0.55, 0.45), (1.25, -4.4, TOP + 0.55 + 0.225), WOOD, hexc("a3805a"), bevel=0.03, rot=(0, 0, 0.35))
k.cyl(0.3, 0.8, (-1.3, 6.8, TOP), WOOD, hexc("7a5230"), segs=12, r2=0.28)
for hz in (0.12, 0.66):
    k.cyl(0.31, 0.05, (-1.3, 6.8, TOP + hz), METAL, hexc("3a3836"), segs=12, caps=False)
# fishing rods leaning on the lantern post
for i in range(2):
    k.beam((LPX + 0.3 + i * 0.12, LPY + 0.2, TOP), (LPX + 0.05, LPY + 0.05 + i * 0.1, TOP + 2.4), 0.025, WOOD,
           hexc("a88a5a"), bevel=0)

# ------------------------------------------------------------------ shore abutment
for r in range(4):
    z0 = -1.2 + r * 0.35
    xs = -WID / 2 - 0.4
    while xs < WID / 2 + 0.4:
        bw = random.uniform(0.6, 1.0)
        bw = min(bw, WID / 2 + 0.4 - xs)
        c = vary(random.choice([hexc("8e8a80"), hexc("7b776f"), hexc("9c968a")]), 0.08)
        k.box((bw - 0.03, 0.9, 0.33), (xs + bw / 2, LEN / 2 + 0.2, z0 + 0.165), STONE, wet(c, z0 + 0.165),
              bevel=0.04, jitter=0.02)
        xs += bw
k.box((WID + 0.9, 0.95, 0.12), (0, LEN / 2 + 0.2, TOP - 0.06), STONE, hexc("8a857b"), bevel=0.03)

print("triangles:", k.tri_count())
k.finish(preview_kind="water", cam_dir=(1.3, -1.1, 0.75), fit=0.8)
