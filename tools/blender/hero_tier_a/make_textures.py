"""Tier-A hero textures (py + PIL): face albedo = baked atlas * AO, hair strand cards, lash/brow cards.
py tools/blender/hero_tier_a/make_textures.py <build_dir> <out_dir>"""
import sys, os, random, math
from PIL import Image, ImageChops, ImageDraw, ImageFilter

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
random.seed(3)

# face: AO multiplied at 65 %, slight warm lift so the baked MH atlas does not read grey under Style G light
alb = Image.open(os.path.join(src, "hero_face_albedo_raw.png")).convert("RGB")
ao = Image.open(os.path.join(src, "hero_face_ao.png")).convert("L")
ao = ao.point(lambda v: int(255 - (255 - v) * 0.65))
face = ImageChops.multiply(alb, Image.merge("RGB", (ao, ao, ao)))
r, g, b = face.split()
face = Image.merge("RGB", (r.point(lambda v: min(255, int(v * 1.02))), g, b.point(lambda v: int(v * 0.96))))
face.save(os.path.join(out, "hero_face_albedo.png"))

# hair: 4 strand clumps side by side (u 0-.25, .25-.5, ...), v = root(0) -> tip(1); RGBA, grey value = strand brightness
W, H = 512, 512
hair = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(hair)
for clump in range(4):
    x0 = clump * W // 4
    for s in range(260):
        u = random.gauss(0.0, 0.22)                   # strands bunch in the clump centre -> soft card edges
        if abs(u) > 0.48:
            continue
        cx = x0 + W / 8 + u * W / 4
        taper = random.uniform(0.7, 1.0)
        bright = random.randint(150, 255)
        wav = random.uniform(0.0, 3.0)
        pts = []
        for i in range(25):
            t = i / 24
            # strands converge toward the clump centre at the tip
            x = cx + (x0 + W / 8 - cx) * t * 0.55 + math.sin(t * 6 + wav) * 2.0
            pts.append((x, t * H * taper))
        a = int(random.randint(150, 255) * (1.0 - abs(u) * 1.6))
        for i in range(len(pts) - 1):
            t = i / 24
            d.line([pts[i], pts[i + 1]], fill=(bright, bright, bright, int(a * (1 - t ** 3))), width=2 if t < 0.6 else 1)
hair = hair.filter(ImageFilter.GaussianBlur(0.6))
hair.save(os.path.join(out, "hero_hair_strands.png"))

# lashes (top half, v 0..0.5: root at v=0) and brows (bottom half: v .5..1, root at .5), 256 x 256
lb = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
d = ImageDraw.Draw(lb)
for i in range(70):
    x = 6 + i * 244 / 70 + random.uniform(-1, 1)
    ln = 100 * (0.55 + 0.45 * math.sin(math.pi * i / 70)) * random.uniform(0.8, 1.0)
    d.line([(x, 2), (x + random.uniform(-4, 4) + (i - 35) * 0.25, ln)], fill=(25, 18, 14, 230), width=2)
for i in range(260):
    t = random.random()
    x = 6 + t * 244
    y0 = 128 + random.uniform(20, 100) * (1.0 - 0.5 * t)
    ang = math.radians(-25 + 40 * t) + random.uniform(-0.2, 0.2)
    ln = random.uniform(18, 34)
    d.line([(x, y0), (x + math.cos(ang) * ln, y0 - math.sin(ang) * ln * 0.5 - 10)], fill=(60, 38, 24, random.randint(120, 220)), width=2)
lb = lb.filter(ImageFilter.GaussianBlur(0.5))
lb.save(os.path.join(out, "hero_lash_brow.png"))
print("textures ->", out)
