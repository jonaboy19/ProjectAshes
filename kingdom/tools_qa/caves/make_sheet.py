#!/usr/bin/env python3
"""Contact sheet of the caves QA shots: python3 make_sheet.py <shots dir> <out.png>"""
import sys, glob, os
from PIL import Image, ImageDraw
d, out = sys.argv[1], sys.argv[2]
files = sorted(glob.glob(os.path.join(d, "*.png")))
files = [f for f in files if not f.endswith("caves_sheet.png")]
cols, tw = 4, 480
th = tw * 9 // 16
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * tw, rows * (th + 18)), (20, 20, 24))
dr = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB").resize((tw, th))
    x, y = (i % cols) * tw, (i // cols) * (th + 18)
    sheet.paste(im, (x, y + 18))
    dr.text((x + 4, y + 3), os.path.basename(f)[:-4], fill=(230, 230, 230))
sheet.save(out)
print(out, len(files))
