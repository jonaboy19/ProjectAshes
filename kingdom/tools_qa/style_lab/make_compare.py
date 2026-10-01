#!/usr/bin/env python3
"""Side-by-side of a Style Lab render and a reference image + objective Style G metrics.
usage: make_compare.py <render.png> <reference.webp> <out.png> [label_left label_right]
Prints metrics for both images (used by the ashes-style-g-qa scorecard):
  warmth   = mean(R) / mean(B) over the whole frame        (target 03 = 1.34)
  sat      = mean HSV saturation                           (target 03 = 0.40)
  contrast = std of luminance                              (target 03 = 0.23)
  detail   = mean Sobel-like edge magnitude / 255          (material richness + density proxy; target 03 = 0.071)
  green    = fraction of pixels that are foliage-green     (ivy/trees/flowers presence)
  shadow_b = mean B-R in the darkest 20% pixels            (target 03 ~ -0.06: shadows only slightly warm; below -0.10 = muddy orange, aim for 0..-0.06)
"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

a, b, out = sys.argv[1:4]
la = sys.argv[4] if len(sys.argv) > 4 else "Style Lab render"
lb = sys.argv[5] if len(sys.argv) > 5 else "Reference"
W = 1500
ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")


def metrics(im):
    im = im.resize((960, int(im.height * 960 / im.width)), Image.LANCZOS)
    x = np.asarray(im).astype(np.float32)
    r, g, bl = x[..., 0], x[..., 1], x[..., 2]
    lum = (0.299 * r + 0.587 * g + 0.114 * bl) / 255.0
    mx, mn = x.max(-1), x.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1), 0)
    gy, gx = np.gradient(lum)
    edge = np.sqrt(gx * gx + gy * gy)
    dark = lum <= np.quantile(lum, 0.2)
    green = (g > r * 1.05) & (g > bl * 1.15) & (sat > 0.25)
    return {"warmth": float(r.mean() / max(bl.mean(), 1)), "sat": float(sat.mean()), "contrast": float(lum.std()),
            "detail": float(edge.mean()), "green": float(green.mean()), "shadow_b": float((bl[dark] - r[dark]).mean() / 255.0)}


ma, mb = metrics(ia), metrics(ib)
print("%-9s %10s %10s" % ("metric", "render", "target"))
for k in ma:
    print("%-9s %10.3f %10.3f" % (k, ma[k], mb[k]))

ia = ia.resize((W, int(ia.height * W / ia.width)), Image.LANCZOS)
ib = ib.resize((W, int(ib.height * W / ib.width)), Image.LANCZOS)
H = max(ia.height, ib.height)
sheet = Image.new("RGB", (W * 2 + 30, H + 50), (20, 17, 15))
f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 28)
d = ImageDraw.Draw(sheet)
sheet.paste(ia, (10, 44)); sheet.paste(ib, (W + 20, 44))
d.text((14, 6), la, font=f, fill=(255, 226, 170)); d.text((W + 24, 6), lb, font=f, fill=(255, 226, 170))
sheet.save(out); print("wrote", out, sheet.size)
