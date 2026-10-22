#!/usr/bin/env python3
"""Tile the frames of events_capture.gd into numbered contact sheets: sheet.py <dir> <out.png> [cols] [scale]"""
import sys, glob, os
from PIL import Image, ImageDraw
d = sys.argv[1]; out = sys.argv[2]
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 4
scale = float(sys.argv[4]) if len(sys.argv) > 4 else 0.3
files = sorted(glob.glob(os.path.join(d, "*.png")))
order = ["gates_opening", "shift_change", "delivery", "bread_queue", "sermon", "children", "drills", "town_crier", "funeral", "noble_carriage", "broken_cart",
         "festival", "performer", "recruiters", "thief", "market_closing", "lamp_lighter", "gates_closing", "drunk", "night_watch"]
def key(f):
    n = os.path.basename(f)[:-4]
    base = n.rsplit("_", 1)[0]
    return (order.index(base) if base in order else 99, n)
files.sort(key=key)
if not files:
    sys.exit("no frames")
im0 = Image.open(files[0]); w = int(im0.width * scale); h = int(im0.height * scale)
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w, rows * h), (20, 20, 20))
for i, f in enumerate(files):
    im = Image.open(f).convert("RGB").resize((w, h), Image.LANCZOS)
    dr = ImageDraw.Draw(im)
    label = "%d %s" % (i + 1, os.path.basename(f)[:-4])
    dr.rectangle([0, 0, 8 * len(label) + 10, 18], fill=(0, 0, 0))
    dr.text((5, 3), label, fill=(255, 235, 150))
    sheet.paste(im, ((i % cols) * w, (i // cols) * h))
sheet.save(out)
print(out, sheet.size, len(files))
