"""Hitch matrix analysis: python analyze.py  -> prints a markdown table, writes hitch_before.png / hitch_after.png.
Reads raw/m_<scenario>_<legacy|fixed>_r<N>.csv (t, ms, ...) written by kingdom/tools_qa/perf/town_route.gd --hitchcsv."""
import csv, glob, os, re, statistics as st
from PIL import Image, ImageDraw, ImageFont

RAW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "raw")
AFTER = {"A": 75.0, "B": 21.0, "C": 75.0, "D": 75.0}     # steady window start (route t, includes the 6 s settle)


def load(path, t0):
    rows = list(csv.DictReader(open(path)))
    t = [float(r["t"]) for r in rows]
    ms = [float(r["ms"]) for r in rows]
    keep = [(a, b) for a, b in zip(t, ms) if a >= t0]
    return [a for a, _ in keep], [b for _, b in keep]


def stats(t, ms):
    s = sorted(ms)
    n = len(s)
    dur = max(1e-6, t[-1] - t[0]) if t else 1.0
    return {"n": n, "fps": 1000.0 * n / sum(ms), "p50": s[n // 2], "p95": s[int(n * 0.95)], "p99": s[min(n - 1, int(n * 0.99))],
            "max": s[-1], "gt33_min": sum(1 for m in ms if m > 33.4) * 60.0 / dur, "gt50_min": sum(1 for m in ms if m > 50) * 60.0 / dur,
            "gt100_min": sum(1 for m in ms if m > 100) * 60.0 / dur}


def main():
    runs = {}
    for f in sorted(glob.glob(os.path.join(RAW, "m_*.csv"))):
        m = re.match(r"m_(([A-D])_.+?)_(legacy|fixed)_r(\d+)\.csv", os.path.basename(f))
        if not m:
            continue
        t, ms = load(f, AFTER[m[2]])
        if len(ms) < 50:
            continue
        runs.setdefault((m[1], m[3]), []).append((int(m[4]), f, t, ms, stats(t, ms)))
    print("| scenario | build | runs | fps (median) | p50 ms | p95 ms | p99 ms | max ms | >33ms /min | >50ms /min | >100ms /min |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for (sc, var) in sorted(runs):
        rs = runs[(sc, var)]
        med = lambda k: st.median(r[4][k] for r in rs)
        print("| %s | %s | %d | %.1f | %.1f | %.1f | %.1f | %.0f | %.0f | %.0f | %.0f |" % (sc, "before" if var == "legacy" else "after", len(rs),
              med("fps"), med("p50"), med("p95"), med("p99"), med("max"), med("gt33_min"), med("gt50_min"), med("gt100_min")))
    # graphs for scenario A: the median-fps run of each build
    for var, out in (("legacy", "hitch_before.png"), ("fixed", "hitch_after.png")):
        rs = runs.get(("A_stand_1440", var))
        if not rs:
            continue
        rs = sorted(rs, key=lambda r: r[4]["fps"])
        pick = rs[len(rs) // 2]
        plot(pick, os.path.join(os.path.dirname(RAW), out), "Kingsreach gate market, 2560x1440, " + ("BEFORE" if var == "legacy" else "AFTER"))


def plot(run, out, title):
    _, f, t, ms, s = run
    W, H = 1500, 700
    im = Image.new("RGB", (W, H), (20, 22, 28))
    d = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype("arial.ttf", 16)
        big = ImageFont.truetype("arial.ttf", 22)
    except Exception:
        font = big = ImageFont.load_default()
    d.text((20, 12), title, fill=(240, 240, 240), font=big)
    d.text((20, 44), "fps %.1f  p50 %.1f ms  p95 %.1f ms  p99 %.1f ms  max %.0f ms  >33ms %.0f/min  >100ms %.0f/min   (%s)" % (
        s["fps"], s["p50"], s["p95"], s["p99"], s["max"], s["gt33_min"], s["gt100_min"], os.path.basename(f)), fill=(200, 200, 200), font=font)
    x0, y0, x1, y1 = 70, 90, 1000, 640
    ymax = 150.0
    d.rectangle([x0, y0, x1, y1], outline=(90, 90, 100))
    for v, col in ((16.7, (80, 200, 120)), (33.3, (230, 190, 70)), (100.0, (230, 90, 90))):
        y = y1 - (y1 - y0) * v / ymax
        d.line([x0, y, x1, y], fill=col, width=1)
        d.text((x1 + 6, y - 8), "%.1f ms" % v, fill=col, font=font)
    t0 = t[0]
    span = max(1e-6, t[-1] - t0)
    pts = [(x0 + (x1 - x0) * (a - t0) / span, y1 - (y1 - y0) * min(b, ymax) / ymax) for a, b in zip(t, ms)]
    for i in range(1, len(pts)):
        d.line([pts[i - 1], pts[i]], fill=(120, 170, 255), width=1)
    for p, b in zip(pts, ms):
        if b > 33.4:
            d.ellipse([p[0] - 2, p[1] - 2, p[0] + 2, p[1] + 2], fill=(255, 120, 90))
    d.text((x0, y1 + 8), "route time %.0f s -> %.0f s   (y: frame time ms, clipped at %.0f)" % (t0, t[-1], ymax), fill=(180, 180, 180), font=font)
    # histogram
    hx0, hy0, hx1, hy1 = 1130, 130, 1470, 640
    bins = [0, 8, 12, 16.7, 20, 25, 33.3, 50, 75, 100, 150, 1e9]
    names = ["<8", "8-12", "12-16.7", "16.7-20", "20-25", "25-33", "33-50", "50-75", "75-100", "100-150", ">150"]
    cnt = [sum(1 for m in ms if bins[i] <= m < bins[i + 1]) for i in range(len(names))]
    mx = max(cnt) or 1
    d.text((hx0, 96), "frame-time histogram (frames)", fill=(220, 220, 220), font=font)
    bh = (hy1 - hy0) / len(names)
    for i, c in enumerate(cnt):
        y = hy0 + i * bh
        col = (80, 200, 120) if bins[i + 1] <= 16.7 else ((230, 190, 70) if bins[i + 1] <= 33.4 else (230, 90, 90))
        d.rectangle([hx0 + 70, y + 4, hx0 + 70 + (hx1 - hx0 - 70) * c / mx, y + bh - 4], fill=col)
        d.text((hx0, y + 6), names[i], fill=(200, 200, 200), font=font)
        d.text((hx0 + 74, y + 6), str(c), fill=(10, 10, 10), font=font)
    im.save(out)


if __name__ == "__main__":
    main()
