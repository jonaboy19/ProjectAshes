"""Planter box for house fronts: a plank trough on little feet with corner posts,
dark soil, leafy mounds, flower heads (five-petal stars, no alpha) in two or
three colours and a trailing stem over the front edge.

Run: python3 make_planter_box.py <out.glb> [preview.png] [--variant=N]

Scale/facing: metres. 1.0 m (X) x 0.42 m (Y) x ~0.75 m tall with the plants.
Origin at ground centre; the long front faces Blender -Y (Godot +Z), so set it
against a wall with its back (+Y) to the wall. < 1000 triangles, one draw per
material (Wood, Matte soil, Plant), all shared village materials.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette, variant_arg, FLOWERS
from ra_kit import hexc, mix, vary
import bmesh
from mathutils import Vector

V = variant_arg()
k = VK("PlanterBox" + ("" if V == 1 else f"_{V}"), seed=909 + V * 3, pal=palette())
W, PL, MA = k.M("Wood"), k.M("Plant"), k.M("Matte")


def flower(pts, c):
    """Flat five-petal flower head (one polygon, 8 triangles) facing the frame's -Y."""
    t = bmesh.new()
    vs = [t.verts.new((x, 0.0, z)) for x, z in pts]
    t.faces.new(vs)
    bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
    if t.faces[0].normal.y > 0:
        t.faces[0].normal_flip()
    # back side (4 mm behind) so the head shows from every angle with back-face culling on
    t.faces.new([t.verts.new(v.co + Vector((0, 0.004, 0))) for v in reversed(list(t.faces[0].verts))])
    k._merge(t, PL, c, k.xf((0, 0, 0)), None, 0.0, None, False)

k.grime, k.grime_amt = 0.25, 0.15
L, D, H = 1.0, 0.42, 0.42
BOX = {1: hexc("7a5634"), 2: hexc("4f6a52"), 3: hexc("8a4a36")}[V]
FL = {1: [FLOWERS[0], FLOWERS[2], FLOWERS[1]], 2: [FLOWERS[3], FLOWERS[2], FLOWERS[6]],
      3: [FLOWERS[4], FLOWERS[1], FLOWERS[5]]}[V]

# trough: boards on the long sides, corner posts with little feet, a rim
with k.grain_axis("x"):
    for sy in (-1, 1):
        for j in range(2):
            k.box((L - 0.08, 0.035, H / 2 - 0.01), (0, sy * (D / 2 - 0.018), 0.07 + H / 4 + j * H / 2 - 0.03), W,
                  vary(BOX, 0.07), var=0)
for sx in (-1, 1):
    k.box((0.035, D - 0.07, H - 0.08), (sx * (L / 2 - 0.058), 0, 0.07 + (H - 0.08) / 2), W, vary(BOX, 0.06), var=0)
    for sy in (-1, 1):
        k.box((0.07, 0.07, H + 0.02), (sx * (L / 2 - 0.035), sy * (D / 2 - 0.035), (H + 0.02) / 2), W,
              mix(BOX, (0, 0, 0), 0.25), bevel=0.01, var=0)
for sy in (-1, 1):
    k.box((L + 0.02, 0.06, 0.035), (0, sy * (D / 2 - 0.01), H + 0.01), W, mix(BOX, (1, 1, 1), 0.1), var=0)
k.box((L - 0.1, D - 0.08, 0.03), (0, 0, H - 0.05), MA, hexc("3f2f24"), var=0)

# foliage: overlapping soft mounds, each crowned with flower heads
greens = [hexc("4f8a34"), hexc("5f9a3a"), hexc("3f7a2e"), hexc("6fa044")]


def petals(r):
    return [(math.cos(j * math.pi / 5) * (r if j % 2 == 0 else r * 0.45),
             math.sin(j * math.pi / 5) * (r if j % 2 == 0 else r * 0.45)) for j in range(10)]


n = 6
for i in range(n):
    x = -L / 2 + 0.11 + i * (L - 0.22) / (n - 1) + random.uniform(-0.02, 0.02)
    y = random.uniform(-0.05, 0.05)
    r = random.uniform(0.11, 0.14)
    h = r * 0.85
    zc = H + r * 0.25
    k.sphere(r, (x, y, zc), PL, random.choice(greens), scale=(1.1, 1.0, 0.85), subdiv=1, noise_amt=0.012,
             grime=False, face_var=0.0, smooth=180)
    c = FL[i % len(FL)]
    for j in range(3):
        a = j * math.tau / 3 + random.uniform(-0.5, 0.5) - math.pi / 2
        rr = r * random.uniform(0.2, 0.7)
        up = 1.0 - (rr / r) ** 2
        k.push((x + math.cos(a) * rr, y + math.sin(a) * rr, zc + h * (0.35 + 0.65 * up ** 0.5) + 0.01),
               (-math.pi / 2 + (rr / r) * 0.9, 0, a - math.pi / 2))
        flower(petals(random.uniform(0.045, 0.058)), vary(c, 0.06))
        k.pop()
# trailing leaves over the front edge
for j in range(3):
    k.sphere(0.06 - j * 0.01, (0.25 + j * 0.03, -D / 2 - 0.02, H - 0.02 - j * 0.09), PL, vary(hexc("46723a"), 0.08),
             scale=(1.0, 0.5, 0.8), subdiv=1, grime=False, smooth=180, face_var=0.0)
k.finish_checked((1.2, 0.6), 1000, cam_dir=(0.9, -1.6, 0.9), fit=0.9)
