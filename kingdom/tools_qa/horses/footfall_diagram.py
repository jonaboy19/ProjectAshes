"""Gait (Hildebrand) diagrams measured IN THE ENGINE from horse_demo --hoofs=1 logs, next to the reference footfall pattern.
Each gait gets 4 rows (LH, LF, RH, RF); a bar = hoof planted (toe < 2 cm), measured per frame at 30 fps.
Reference (real gaits): walk 4-beat lateral LH-LF-RH-RF; trot 2-beat diagonal LH+RF / RH+LF; canter (left lead) 3-beat
RH, LH+RF, LF + suspension; gallop (left lead) 4-beat RH, LH, RF, LF + suspension.
usage: py -3 footfall_diagram.py out.png Walk=log Trot=log Canter_L=log Gallop_L=log"""
import sys, re
from PIL import Image, ImageDraw, ImageFont

ROWS = [("LH", "hoof_H_L"), ("LF", "hoof_F_L"), ("RH", "hoof_H_R"), ("RF", "hoof_F_R")]
REF = {
    "Walk": "4-beat lateral: LH, LF, RH, RF (25% apart), duty ~0.60",
    "Trot": "2-beat diagonal: LH+RF, RH+LF, two suspensions, duty ~0.42",
    "Canter_L": "3-beat, left lead: RH | LH+RF | LF, then suspension",
    "Gallop_L": "4-beat, left lead: RH, LH, RF, LF, then suspension",
    "BackUp": "2-beat diagonal backwards",
}
COL = {"LH": (70, 120, 200), "LF": (110, 170, 240), "RH": (200, 90, 60), "RF": (240, 150, 100)}
out = sys.argv[1]
items = [a.split("=", 1) for a in sys.argv[2:]]
W, rowh, head, left = 1400, 26, 58, 90
H = sum(head + rowh * 4 + 20 for _ in items) + 20
img = Image.new("RGB", (W, H), (250, 247, 240))
d = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 18)
    small = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 14)
except Exception:
    font = small = ImageFont.load_default()
y = 10
for name, log in items:
    data = {}
    frames = []
    for line in open(log, errors="ignore"):
        if not line.startswith("HOOF f"):
            continue
        f = int(line.split()[1][1:])
        if f < 20:
            continue
        frames.append(f)
        for m in re.finditer(r"(hoof_\w+) (-?[\d.]+) (-?[\d.]+) (-?[\d.]+)", line):
            data.setdefault(m.group(1), {})[f] = float(m.group(3)) < 0.02
    f0, f1 = min(frames), max(frames)
    span = f1 - f0 + 1
    px = (W - left - 20) / span
    d.text((10, y), "%s   (engine, 30 fps, %d frames)   reference: %s" % (name, span, REF.get(name, "")), fill=(30, 30, 30), font=font)
    y += 30
    for i in range(0, span + 1, 5):
        x = left + i * px
        d.line([(x, y), (x, y + rowh * 4)], fill=(215, 210, 200))
        if i % 10 == 0:
            d.text((x + 2, y + rowh * 4 + 2), "%.2fs" % ((f0 + i) / 30.0), fill=(120, 120, 120), font=small)
    for r, (lab, bone) in enumerate(ROWS):
        d.text((10, y + r * rowh + 4), lab, fill=(30, 30, 30), font=font)
        run = None
        for k in range(f0, f1 + 2):
            on = data.get(bone, {}).get(k, False)
            if on and run is None:
                run = k
            if (not on or k == f1 + 1) and run is not None:
                x0 = left + (run - f0) * px
                x1 = left + (k - f0) * px
                d.rectangle([x0, y + r * rowh + 3, x1 - 1, y + r * rowh + rowh - 3], fill=COL[lab])
                d.text((x0 + 3, y + r * rowh + 5), "f%d" % run, fill=(255, 255, 255), font=small)
                run = None
    y += rowh * 4 + 20 + (head - 30)
img.save(out)
print("saved", out)
