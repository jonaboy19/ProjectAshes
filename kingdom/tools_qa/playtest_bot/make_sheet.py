#!/usr/bin/env python3
"""Contact sheet of the playtest bot screenshots: make_sheet.py <shot_dir> <out.png> [cols]"""
import sys, glob, os
from PIL import Image, ImageDraw
src, out = sys.argv[1], sys.argv[2]
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 6
files = sorted(glob.glob(os.path.join(src, "*.png")))
tw, th = 320, 180
rows = max(1, (len(files) + cols - 1) // cols)
sheet = Image.new("RGB", (cols * tw, rows * (th + 16)), (20, 20, 20))
d = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB").resize((tw, th))
    x, y = (i % cols) * tw, (i // cols) * (th + 16)
    sheet.paste(im, (x, y + 16))
    d.text((x + 4, y + 2), os.path.basename(f)[:-4], fill=(255, 255, 255))
sheet.save(out)
print("sheet", len(files), "shots ->", out, sheet.size)
