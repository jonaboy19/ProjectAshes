"""Contact sheets of render_rider.py frames: side | 3/4 per frame, labelled '#frame clip', tiled with ffmpeg (read left->right, top->bottom).
usage: py -3 make_sheets.py <frames_root> <clip> <out.png> [cols=3] [max_width=2000] [first:last]"""
import os, sys, glob, subprocess, tempfile, shutil
from PIL import Image, ImageDraw, ImageFont

root, clip, out = sys.argv[1], sys.argv[2], sys.argv[3]
cols = int(sys.argv[4]) if len(sys.argv) > 4 else 3
maxw = int(sys.argv[5]) if len(sys.argv) > 5 else 2000
rng = sys.argv[6] if len(sys.argv) > 6 else None
d = os.path.join(root, clip)
frames = sorted(int(os.path.basename(p)[2:6]) for p in glob.glob(os.path.join(d, "s_*.png")))
if rng:
    a, b = (int(x) for x in rng.split(":"))
    frames = [f for f in frames if a <= f <= b]
try:
    font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 18)
except OSError:
    font = ImageFont.load_default()
tmp = tempfile.mkdtemp()
cell = None
for i, f in enumerate(frames):
    s = Image.open(os.path.join(d, "s_%04d.png" % f)).convert("RGB")
    q = Image.open(os.path.join(d, "q_%04d.png" % f)).convert("RGB")
    im = Image.new("RGB", (s.width + q.width + 4, s.height), (30, 30, 30))
    im.paste(s, (0, 0)); im.paste(q, (s.width + 4, 0))
    dr = ImageDraw.Draw(im)
    dr.rectangle((0, 0, 150, 24), fill=(0, 0, 0))
    dr.text((5, 2), "#%d %.2fs" % (f, f / 30.0), fill=(255, 255, 80), font=font)
    im.save(os.path.join(tmp, "c_%04d.png" % i))
    cell = im.size
n = len(frames)
rows = (n + cols - 1) // cols
scale = min(1.0, maxw / float(cell[0] * cols))
w = int(cell[0] * scale) // 2 * 2
h = int(cell[1] * scale) // 2 * 2
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(tmp, "c_%04d.png"),
                "-vf", "scale=%d:%d,tile=%dx%d:padding=2:color=black" % (w, h, cols, rows), "-frames:v", "1", out], check=True)
shutil.rmtree(tmp)
print("sheet", out, n, "frames", cols, "x", rows)
