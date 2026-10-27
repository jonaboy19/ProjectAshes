"""Contact sheet for the refined props: Meshy original | refined pairs (Task A), then the procedural builds (Task B).
Usage: python tools/blender/props/make_sheet.py <gate_dir> <stats.txt> <out.jpg> [pairs]
  pairs: generic Meshy|refined pairs for every key in stats.txt (used for the buildings batch, gate_b/stats_b.txt)
"""
import sys
from PIL import Image, ImageDraw, ImageFont

gate, stats, out = sys.argv[1:4]
A = ["cart", "well", "crate_stack", "trestle_table", "hearth", "market_stall", "belt_pouch"]
B = ["bench_hewn", "trough_granite", "tavern_sign", "barrel_rack", "fence_wattle", "fence_post_rail", "haystack", "hay_bundle",
     "firewood_stack", "scabbard_arming"]
info = {}
for line in open(stats):
    p = line.rstrip("\n").split("\t")
    if len(p) >= 4:
        info[p[0]] = f"{int(p[1]) / 1000:.1f}k tris, {int(p[2]) // 1024}K, {p[3]} m"
TW, TH = 480, 360
try:
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 17)
    small = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 14)
except OSError:
    font = small = ImageFont.load_default()
tiles = []
if len(sys.argv) > 4 and sys.argv[4] == "pairs":
    # generic mode (buildings): every <key>_A_meshy.jpg / <key>_B_refined.jpg pair in the gate dir, keys from stats order
    A, B = [k for k in info], []
    for k in A:
        tiles.append((f"{gate}/{k}_A_meshy.jpg", f"{k}: Meshy original", ""))
        tiles.append((f"{gate}/{k}_B_refined.jpg", f"{k}: refined", info.get(k, "")))
    A = []
for n in A:
    tiles.append((f"{gate}/{n}_A_meshy.jpg", f"{n}: Meshy original", ""))
    tiles.append((f"{gate}/{n}_B_refined.jpg", f"{n}: refined", info.get(n, "")))
for n in B:
    tiles.append((f"{gate}/{n}_B_refined.jpg", f"{n}: procedural", info.get(n, "")))
cols = 4
rows = (len(tiles) + cols - 1) // cols
sheet = Image.new("RGB", (cols * TW, rows * TH + 40), (24, 24, 24))
d = ImageDraw.Draw(sheet)
d.text((10, 10), "Rising Ashes props_refined 2026-10-28: Eevee, kloofendal_overcast HDRI + soft sun, gameplay 3/4 camera; "
       "Meshy | refined pairs" + ("" if len(sys.argv) > 4 else ", then procedural builds") + " (red figure = 1.75 m where shown)",
       fill=(230, 210, 150), font=font)
for i, (path, title, sub) in enumerate(tiles):
    x, y = (i % cols) * TW, 40 + (i // cols) * TH
    try:
        im = Image.open(path).convert("RGB").resize((TW, TH), Image.LANCZOS)
        sheet.paste(im, (x, y))
    except OSError:
        d.text((x + 10, y + 150), "missing", fill=(255, 80, 80), font=font)
    d.rectangle((x, y + TH - 44, x + TW, y + TH), fill=(18, 18, 18))
    d.text((x + 8, y + TH - 42), title, fill=(240, 240, 240), font=font)
    d.text((x + 8, y + TH - 21), sub, fill=(170, 170, 170), font=small)
sheet.save(out, quality=86)
print("SHEET", out, sheet.size)
