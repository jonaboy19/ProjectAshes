#!/usr/bin/env python3
"""Side-by-side of a Style Lab render and a reference image. usage: make_compare.py <render.png> <reference.webp> <out.png> [label_left label_right]"""
import sys
from PIL import Image, ImageDraw, ImageFont
a, b, out = sys.argv[1:4]
la = sys.argv[4] if len(sys.argv) > 4 else "Style Lab render"
lb = sys.argv[5] if len(sys.argv) > 5 else "Reference"
W = 1500
ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
ia = ia.resize((W, int(ia.height * W / ia.width)), Image.LANCZOS)
ib = ib.resize((W, int(ib.height * W / ib.width)), Image.LANCZOS)
H = max(ia.height, ib.height)
sheet = Image.new("RGB", (W * 2 + 30, H + 50), (20, 17, 15))
f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 28)
d = ImageDraw.Draw(sheet)
sheet.paste(ia, (10, 44)); sheet.paste(ib, (W + 20, 44))
d.text((14, 6), la, font=f, fill=(255, 226, 170)); d.text((W + 24, 6), lb, font=f, fill=(255, 226, 170))
sheet.save(out); print("wrote", out, sheet.size)
