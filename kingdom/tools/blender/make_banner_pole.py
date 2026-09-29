"""Freestanding banner pole: a tapered wooden pole with a wooden crossbar and
gold ball finials, holding a long vertical red-and-gold cloth banner with a
gold crown/gate emblem (the tower_crown.png decal) and a forked
swallow-tail foot. The cloth has a slight outward curve (a gentle midline
bow), as if caught by a light breeze.

Run: python3 make_banner_pole.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Pole ~3.85 m to the finial ball; crossbar at z=3.55,
1.15 m wide. Banner hangs from the crossbar, 0.85 m wide x ~2.45 m long
(cloth front faces Blender -Y / Godot +Z, the same side the crown reads
correctly on). Origin at ground centre of the pole. Budget: <= 1500 triangles.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette, IRON
from ra_kit import hexc, vary, mix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
CROWN = os.path.join(ROOT, "kingdom", "assets", "art", "emblems", "tower_crown.png")

k = VK("BannerPole", seed=4141, pal=palette(timber="oak"))
k.pbr = dict(size=512, seed=2, ao_dist=0.3, cage=0.03, ray=0.08)   # high-to-low PBR bake (pbr_kit.py)
k.weather_ao = 0.34
W, MT, CL = k.M("Wood"), k.M("Metal"), k.M("Cloth")
CRIMSON, GOLD = hexc("9b1d24"), hexc("d4a63a")
tc = hexc("5a3e26")
k.grime, k.grime_amt = 0.4, 0.15

# ---------------------------------------------------------------- pole, crossbar, finials
POLE_H = 3.7
k.cyl(0.055, POLE_H, (0, 0, 0), W, tc, segs=8, r2=0.04, color_fn=lambda f: vary(tc, 0.06))
k.sphere(0.05, (0, 0, POLE_H + 0.04), MT, GOLD, subdiv=1, grime=False)
CBZ = POLE_H - 0.15
k.box((1.15, 0.06, 0.06), (0, 0, CBZ), W, mix(tc, (0, 0, 0), 0.08), bevel=0.012, var=0)
for sx in (-1, 1):
    k.sphere(0.045, (sx * 0.58, 0, CBZ), MT, GOLD, subdiv=1, grime=False)
    k.bar((sx * 0.42, 0.0, CBZ - 0.32), (0, 0.0, CBZ - 0.02), 0.03, 0.03, W, mix(tc, (0, 0, 0), 0.1), up=(-sx, 0, 1),
          bevel=0)

# ---------------------------------------------------------------- banner: main sail with a slight curve
BW = 0.85
BODY_H = 1.85
TAIL_H = 0.6
ztop = CBZ - 0.1
zmid = ztop - BODY_H


Y0 = -0.09   # the cloth hangs just clear of the pole, in front of it (-Y, toward the viewer)


def sag(u, v):
    bow = -0.07 * math.sin(u * math.pi) * (0.25 + 0.75 * v)
    return (0, bow, 0)


def col(u, v):
    if v < 0.06:
        return GOLD
    return vary(CRIMSON, 0.03)


k.sheet(((-BW / 2, Y0, ztop), (BW / 2, Y0, ztop), (-BW / 2, Y0, zmid), (BW / 2, Y0, zmid)), 6, 5, CL, col,
        sag_fn=sag, smooth=60)
# gold trim band along the top edge, a hair proud of the cloth
k.prism([(-BW / 2, ztop - 0.06), (BW / 2, ztop - 0.06), (BW / 2, ztop - 0.14), (-BW / 2, ztop - 0.14)], 0.012,
        (0, Y0 - 0.012, 0), CL, GOLD, var=0, grime=False)
# crown emblem, front and back (double-sided so it reads from either side of the pole)
EW = 0.5
k.image_quad(CROWN, EW, EW, (0, Y0 - 0.09, zmid + BODY_H * 0.62), key="Crown", double_sided=True)

# forked swallow-tail foot below the sail
hw = BW / 2
notch = TAIL_H * 0.42
tail_l = [(-hw, 0.0), (0.0, 0.0), (0.0, -notch), (-hw, -TAIL_H)]
tail_r = [(0.0, 0.0), (hw, 0.0), (hw, -TAIL_H), (0.0, -notch)]
for pts in (tail_l, tail_r):
    k.prism([(px, zmid + py) for px, py in pts], 0.02, (0, Y0, 0), CL, CRIMSON, var=0.02, grime=False)
# thin gold edging along the outer slanted edges of each tail
k.prism([(-hw, zmid), (-hw + 0.06, zmid), (-hw + 0.06, zmid - TAIL_H), (-hw, zmid - TAIL_H + 0.05)], 0.014,
        (0, Y0 - 0.012, 0), CL, GOLD, var=0, grime=False)
k.prism([(hw - 0.06, zmid), (hw, zmid), (hw, zmid - TAIL_H + 0.05), (hw - 0.06, zmid - TAIL_H)], 0.014,
        (0, Y0 - 0.012, 0), CL, GOLD, var=0, grime=False)

# small stone cairn / packed earth at the foot of the pole
k.sphere(0.14, (0, 0, 0.0), k.M("Matte"), vary(hexc("bba583"), 0.06), scale=(1.3, 1.1, 0.35), subdiv=1,
         noise_amt=0.02)

k.finish_checked((1.3, 1.3), 1500, cam_dir=(1.1, -1.6, 0.55), fit=0.9)
