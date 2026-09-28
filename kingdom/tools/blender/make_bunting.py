"""Bunting: an 8 m rope sagging in a gentle catenary between two mounting
points, strung with small triangular pennants alternating red, gold and
royal blue. Strung across the market street between stall poles / eaves.

Run: python3 make_bunting.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Rope runs from x=-4 to x=+4, sagging in a gentle
catenary; the two mounting points (rope ends) sit at z=+0.9 and the lowest
pennant tip at the centre just clears the ground at z=0, so the whole prop
sits above its own origin like every other kit asset ("origin at ground
centre of the footprint") -- in Godot, position the node at the height you
want the rope ends to hang from minus 0.9 m. Budget: <= 600 triangles.
"""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette
from ra_kit import hexc, vary

k = VK("Bunting", seed=808, pal=palette())
CL, W = k.M("Cloth"), k.M("Wood")
ROPE_C = hexc("b7a27c")
COLORS = (hexc("a8302a"), hexc("d4a63a"), hexc("2c4f96"))
# skip the ground-plane weathering pass: it assumes z=0 is a solid floor and
# would misjudge this open, swaying rope shape (not needed for a thin prop).
k.polish = False

SPAN = 8.0
SAG = 0.42
MOUNT_Z = 0.9


def sag_z(x):
    t = (x + SPAN / 2) / SPAN
    return MOUNT_Z - SAG * math.sin(math.pi * t)


N = 11
pts = [(-SPAN / 2 + SPAN * i / (N - 1), 0.0, sag_z(-SPAN / 2 + SPAN * i / (N - 1))) for i in range(N)]
k.tube(pts, [0.018] * N, CL, ROPE_C, segs=5, point_end=False, cap_start=False, grime=False)
for sx in (-1, 1):
    k.sphere(0.025, (sx * SPAN / 2, 0, 0.0), k.M("Metal"), hexc("2e2d2c"), subdiv=0, grime=False)

# pennants hanging at regular intervals, alternating colours
NP = 15
PW, PH = 0.34, 0.4
for i in range(NP):
    x = -SPAN / 2 + 0.35 + (SPAN - 0.7) * i / (NP - 1)
    z = sag_z(x) - 0.02
    c = COLORS[i % 3]
    pts2 = [(-PW / 2, 0.0), (PW / 2, 0.0), (0.0, -PH)]
    k.prism(pts2, 0.012, (x, 0.0, z), CL, vary(c, 0.03), var=0, grime=False)
    # a thin gold hem along the top edge
    k.prism([(-PW / 2, 0.0), (PW / 2, 0.0), (PW / 2, -0.05), (-PW / 2, -0.05)], 0.014, (x, -0.006, z), CL,
            hexc("d4a63a"), var=0, grime=False)

k.finish_checked((8.1, 0.6), 600, cam_dir=(1.6, -3.4, 1.0), fit=1.25)
