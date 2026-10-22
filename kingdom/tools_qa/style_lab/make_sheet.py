#!/usr/bin/env python3
"""Labelled contact sheet for the Style Lab renders.
usage: make_sheet.py <prefix> <out.png>   (prefix = the --out of the render, e.g. /tmp/claude-0/shots/style_lab)
Rows A..E, columns: 3/4 overview | character close-up. Footer line per row = draw calls / triangles from the stats json."""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

prefix, out = sys.argv[1], sys.argv[2]
titles = {
    "A": "A  Current look (baseline)", "B": "B  Storybook painterly (toon + ink)",
    "C": "C  Grounded medieval (PBR + AO + height fog)", "D": "D  Polished stylised (wrap + rim + bloom)",
    "E": "E  Low-end safe (D lite: vertex lit, no bloom)",
    "F": "F  Concept target (golden hour, painted backdrop)",
    "G": "G  Recreation of target 03 (gate market, 3rd-person camera)",
}
stats = {}
try:
    stats = json.load(open(prefix + "_stats.json"))["boxes"]
except Exception:
    pass
font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 26)
small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 20)
W, H = 900, 416
rows = [k for k in "ABCDEFG" if os.path.exists(f"{prefix}_{k}_over.png")]
REF = os.path.join(os.path.dirname(os.path.abspath(prefix)), "..", "..") 
refs = [p for p in ["/home/user/ProjectAshes/docs/art/reference/00_MAIN_kingsreach_gate_market.webp",
                    "/home/user/ProjectAshes/docs/art/reference/03_TARGET_gate_market_detailed.webp"] if os.path.exists(p)]
top = (H + 52) if refs else 0
sheet = Image.new("RGB", (W * 2 + 30, top + (H + 52) * len(rows) + 10), (20, 17, 15))
d = ImageDraw.Draw(sheet)
for ri, rp in enumerate(refs):
    im = Image.open(rp).convert("RGB").resize((W, H), Image.LANCZOS)
    sheet.paste(im, (10 + ri * (W + 10), 42))
    d.text((14 + ri * (W + 10), 8), ["REFERENCE 00 (main art target)", "REFERENCE 03 (chosen target)"][ri], font=font, fill=(150, 220, 255))
for r, k in enumerate(rows):
    y = 10 + top + r * (H + 52)
    d.text((14, y + 4), titles[k], font=font, fill=(255, 226, 170))
    s = stats.get(k, {})
    if s:
        o, c = s.get("over", {}), s.get("close", {})
        d.text((W * 2 - 560, y + 8),
               f"overview: {o.get('draw_calls','?')} draws {int(o.get('primitives',0))//1000}k tris   "
               f"close-up: {c.get('draw_calls','?')} draws {int(c.get('primitives',0))//1000}k tris", font=small, fill=(200, 200, 190))
    for ci, cam in enumerate(["over", "close"]):
        p = f"{prefix}_{k}_{cam}.png"
        if os.path.exists(p):
            im = Image.open(p).convert("RGB").resize((W, H), Image.LANCZOS)
            sheet.paste(im, (10 + ci * (W + 10), y + 42))
sheet.save(out)
print("wrote", out, sheet.size)
