"""Real-world layout + mock-up: re-anchors every Valencious place (settlements, sites, Elder Stones, shrines, camps ...) from the
old 12 km WorldGen world onto the 32 km real terrain, paints biomes per sub-region and renders a fantasy map.

Usage: py -E -B kingdom/tools/world/real_layout.py [--png <mockup.png>]
Inputs : kingdom/data/world/real/{height_16.png, water.png, meta.json, anchors.json}, docs/world/valencious_places.json
Outputs: kingdom/data/world/real/layout.json  (old id -> new x,z per place; region box; road list unchanged by id)
         kingdom/data/world/real/biome_ids.png (1024 px, 32 m/px, WorldMacro biome ids) and the mock-up PNG.
Re-anchoring: a thin-plate RBF warp from old sub-region anchors to new ones (anchors.json, hand-picked on the real terrain),
then every settlement is snapped to the best ground within its search radius (dry, gentle, kind-specific height/water wishes).
Sites keep their offset to the nearest settlement (scaled by spread) so clusters stay together, then step off water.
"""
import argparse, json, math, os, struct, zlib
import numpy as np
from scipy import ndimage
from scipy.interpolate import RBFInterpolator
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
RD = os.path.join(ROOT, "kingdom", "data", "world", "real")
G = 1024; GM = 32.0; HALF = 16384.0


def read16(p, hmin, hr):
    f = open(p, "rb").read(); pos = 8; idat = b""
    while pos < len(f):
        n = struct.unpack(">I", f[pos:pos + 4])[0]; t = f[pos + 4:pos + 8]
        if t == b"IHDR": w, h = struct.unpack(">II", f[pos + 8:pos + 16])
        if t == b"IDAT": idat += f[pos + 8:pos + 8 + n]
        pos += 12 + n
    raw = np.frombuffer(zlib.decompress(idat), np.uint8).reshape(h, 1 + 2 * w)[:, 1:]
    return raw.copy().view(">u2").astype(np.float32) * hr / 65535 + hmin


def to_px(x, z):
    return (x + HALF) / GM, (z + HALF) / GM


BIOME = {"grass": 0, "forest": 1, "meadow": 2, "farmland": 3, "marsh": 4, "highland": 5, "rift": 6, "snow": 7}
COL = {0: (118, 160, 80), 1: (52, 98, 52), 2: (150, 178, 92), 3: (186, 176, 104), 4: (92, 112, 82), 5: (138, 128, 104), 6: (110, 70, 130), 7: (236, 240, 248)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--png", default=r"C:\Users\Jonna\Documents\PA_plans\terrain_candidates\mockup_biomes.png")
    a = ap.parse_args()
    meta = json.load(open(os.path.join(RD, "meta.json")))
    anc = json.load(open(os.path.join(RD, "anchors.json")))
    H = read16(os.path.join(RD, "height_16.png"), meta["h_min_m"], meta["h_range_m"])
    h = H[::4, ::4][:G, :G].copy(); del H
    water = np.asarray(Image.open(os.path.join(RD, "water.png")))
    gy, gx = np.gradient(h, GM)
    slope = np.hypot(gx, gy)
    wet = water > 0
    dwater = ndimage.distance_transform_edt(~wet) * GM
    dsea = ndimage.distance_transform_edt(water != 1) * GM
    places = json.load(open(os.path.join(ROOT, "docs", "world", "valencious_places.json")))

    # --- warp old -> new
    old = np.array([v["old"] for v in anc["anchors"].values()], float)
    new = np.array([v["new"] for v in anc["anchors"].values()], float)
    warp = RBFInterpolator(old, new, kernel="thin_plate_spline", smoothing=0.0)

    box = anc["valencious_box"]  # [x0, z0, x1, z1]
    inbox = lambda x, z: box[0] <= x <= box[2] and box[1] <= z <= box[3]

    def cost(kind, px, pz):
        i, j = int(px), int(pz)
        if not (0 <= i < G and 0 <= j < G) or wet[j, i]:
            return 1e9
        c = slope[j, i] * 40.0
        hh = h[j, i]
        if kind == "port":
            c += min(dsea[j, i], 3000) / 40.0
        elif kind == "castle":
            c += abs(hh - 90) / 15.0 + (0 if dwater[j, i] < 900 else 8)      # river-plain capital: low, near water
        elif kind == "keep":
            c = abs(slope[j, i] - 0.18) * 30 - hh / 60.0                        # ridge top: high, moderate slope
        elif kind == "lakeside":
            c += min(dwater[j, i], 2000) / 60.0 + max(0, hh - 200) / 20
        else:
            c += max(0, hh - 350) / 25.0 + (0 if dwater[j, i] < 1200 else 3)
        return c

    special = anc.get("settlement_kind", {})
    pinned = anc.get("pinned", {})
    sets = [p for p in places["places"] if p["category"] == "settlement"]
    new_pos = {}
    for p in sets:
        name = p["name"]
        if name in pinned:
            new_pos[p["id"]] = tuple(pinned[name]); continue
        tx, tz = warp(np.array([[p["x"], p["z"]]]))[0]
        kind = special.get(name, "village")
        r = anc.get("snap_radius_m", 700) / GM
        ci, cj = to_px(tx, tz)
        best, bp = 1e18, (tx, tz)
        for dj in range(-int(r), int(r) + 1):
            for di in range(-int(r), int(r) + 1):
                if di * di + dj * dj > r * r: continue
                c = cost(kind, ci + di, cj + dj) + math.hypot(di, dj) * 0.08
                for q in new_pos.values():   # keep settlements >= 900 m apart
                    if math.hypot(q[0] - ((ci + di) * GM - HALF), q[1] - ((cj + dj) * GM - HALF)) < 900: c += 50
                if c < best: best, bp = c, ((ci + di) * GM - HALF, (cj + dj) * GM - HALF)
        bx = min(max(bp[0], box[0] + 400), box[2] - 400); bz = min(max(bp[1], box[1] + 400), box[3] - 400)
        new_pos[p["id"]] = (bx, bz)
    sid = {p["settlement_id"]: p for p in sets}
    sxy_old = np.array([[p["x"], p["z"]] for p in sets]); sids = [p["id"] for p in sets]
    out = {}
    for p in places["places"]:
        if p["category"] == "proposed":
            continue
        if p["id"] in new_pos:
            nx, nz = new_pos[p["id"]]
        else:
            d = np.hypot(sxy_old[:, 0] - p["x"], sxy_old[:, 1] - p["z"])
            k = int(np.argmin(d))
            if d[k] < 450:   # stays with its settlement
                s = sets[k]; nx = new_pos[sids[k]][0] + (p["x"] - s["x"]) * anc["spread"]; nz = new_pos[sids[k]][1] + (p["z"] - s["z"]) * anc["spread"]
            else:
                nx, nz = warp(np.array([[p["x"], p["z"]]]))[0]
            i, j = to_px(nx, nz)
            i, j = int(np.clip(i, 0, G - 1)), int(np.clip(j, 0, G - 1))
            if wet[j, i]:   # step off water to the nearest dry cell
                _, (jj, ii) = ndimage.distance_transform_edt(wet, return_indices=True)
                nx, nz = ii[j, i] * GM - HALF + GM / 2, jj[j, i] * GM - HALF + GM / 2
        if p["kind"] == "map_edge_text":
            pass                                            # deliberately in the locked realms (future content labels)
        elif p["kind"] == "border_gate" or p["id"] == "site:eastern_gate_outer":
            nx = box[2] - (40 if p["kind"] == "border_gate" else -60); nz = min(max(nz, box[1] + 400), box[3] - 400)
        else:
            nx = min(max(nx, box[0] + 300), box[2] - 300); nz = min(max(nz, box[1] + 300), box[3] - 300)
        out[p["id"]] = {"x": round(float(nx), 1), "z": round(float(nz), 1), "old": [p["x"], p["z"]], "kind": p["kind"], "name": p.get("display_name", p["name"]),
                        "in_valencious": bool(inbox(nx, nz))}

    # --- sub-regions on the new map: old lobes warped -> weighted Voronoi
    regs = json.load(open(os.path.join(ROOT, "kingdom", "data", "world", "valencious_regions.json")))["regions"]
    xs = (np.arange(G) + 0.5) * GM - HALF
    X, Z = np.meshgrid(xs, xs)
    rng = np.random.default_rng(7)
    warpx = (ndimage.gaussian_filter(rng.standard_normal((G, G)), 24) * 60 + ndimage.gaussian_filter(rng.standard_normal((G, G)), 6) * 12) * 1000
    warpz = (ndimage.gaussian_filter(rng.standard_normal((G, G)), 24) * 60 + ndimage.gaussian_filter(rng.standard_normal((G, G)), 6) * 12) * 1000
    hs = ndimage.gaussian_filter(h, 4); ss = ndimage.gaussian_filter(slope, 4)
    aff = {  # terrain affinity per region (subtracted from the normalised lobe distance)
        "westfen_marsh": 0.9 * np.clip(1 - hs / 160, 0, 1) * np.clip(1 - ss / 0.08, 0, 1) * np.clip(1 - dwater / 2500, 0, 1),
        "harrowgate_steppe": 0.7 * np.clip(1 - ss / 0.10, 0, 1) * np.clip(dwater / 1500, 0, 1),
        "northern_ridge": 0.5 * np.clip((hs - 300) / 400, 0, 1), "ironmarch_highlands": 0.4 * np.clip((hs - 250) / 400, 0, 1),
        "dunhallow_uplands": 0.3 * np.clip((hs - 150) / 300, 0, 1), "heartvale": 0.4 * np.clip(1 - ss / 0.12, 0, 1) * np.clip(1 - hs / 300, 0, 1)}
    best = np.full((G, G), 1e18); rid = np.zeros((G, G), np.int16)
    for k, r in enumerate(regs):
        a_ = aff.get(r["id"], 0.0)
        for lx, lz, lr in r["lobes"]:
            nx, nz = warp(np.array([[lx, lz]]))[0]
            d = np.hypot(X - nx + warpx, Z - nz + warpz) / (lr * anc["spread"] * 1.6) - a_
            m = d < best; best[m] = d[m]; rid[m] = k
    outer = ~((X >= box[0]) & (X <= box[2]) & (Z >= box[1]) & (Z <= box[3]))

    noise = ndimage.gaussian_filter(rng.standard_normal((G, G)), 3)
    noise2 = ndimage.gaussian_filter(rng.standard_normal((G, G)), 10)
    biome = np.zeros((G, G), np.uint8)
    for k, r in enumerate(regs):
        m = rid == k
        ws = r["biomes"]; names = list(ws); cum = np.cumsum([ws[n] for n in names]); cum /= cum[-1]
        u = (ndimage.gaussian_filter(rng.random((G, G)), 4) - 0.5) * 3.4 + 0.5
        u = np.clip(u, 0, 0.999)
        b = np.array([BIOME[names[np.searchsorted(cum, v)]] for v in u[m]], np.uint8)
        biome[m] = b
    # terrain rules over the region mix
    biome[(slope > 0.55)] = BIOME["highland"]
    biome[(h > 420) & (slope > 0.2)] = BIOME["highland"]
    biome[(slope < 0.35) & (slope > 0.12) & (h < 380) & (noise > 0.05)] = BIOME["forest"]
    for rn in ("westfen_marsh",):
        k = [r["id"] for r in regs].index(rn); biome[(rid == k) & (slope < 0.08)] = BIOME["marsh"]
    # farmland rings round settlements
    for pid, q in out.items():
        if q["kind"] in ("village", "town", "castle", "frontier_town"):
            i, j = to_px(q["x"], q["z"])
            rr = {"castle": 1500, "town": 1000}.get(q["kind"], 650)
            m = (np.hypot(X - q["x"], Z - q["z"]) < rr + noise2 * 400) & (slope < 0.15) & (h < 350)
            biome[m] = BIOME["farmland"]
    # outer realms: own biomes (north snow realm, east forest/highland, south steppe)
    biome[outer & (Z < box[1])] = np.where(slope[outer & (Z < box[1])] > 0.2, BIOME["highland"], BIOME["forest"])
    so = outer & (Z > box[3]); biome[so] = np.where(noise[so] > 0.3, BIOME["grass"], BIOME["meadow"])
    eo = outer & (X > box[2]) & (Z >= box[1]) & (Z <= box[3]); biome[eo] = np.where(noise[eo] > 0, BIOME["forest"], BIOME["highland"])
    # snow: by altitude and latitude (north = -z snowier); outer north realm is a snow realm
    north = np.clip((-Z) / HALF, -1, 1)
    # same rule as Terrain3DBridge.snow_line(z)
    snow_line = 520 - 220 * np.clip(-Z / 7000, 0, 1) - 150 * np.clip((-Z - 7000) / 9000, 0, 1) + 100 * np.clip(Z / 9000, 0, 1)
    snow = h + noise * 60 > snow_line
    biome[snow] = BIOME["snow"]
    k_rift = [r["id"] for r in regs].index("rift_marches")
    Image.fromarray(biome).save(os.path.join(RD, "biome_ids.png"))

    # --- render
    col = np.zeros((G, G, 3), np.float32)
    for b, c in COL.items():
        col[biome == b] = c
    # fantasy grading per region
    tint = {"mistwood_west": (0.85, 1.0, 1.15), "ashen_scar": (1.2, 0.85, 0.7), "rift_marches": (1.0, 0.85, 1.15), "northern_ridge": (0.95, 1.0, 1.12),
            "duskbriar_wood": (0.9, 1.05, 0.9), "harrowgate_steppe": (1.12, 1.05, 0.8), "westfen_marsh": (0.9, 1.0, 0.95)}
    for k, r in enumerate(regs):
        if r["id"] in tint: col[(rid == k) & ~snow & ~outer] *= np.array(tint[r["id"]])
    sh = np.clip(0.78 + (gx - gy) * 0.9, 0.35, 1.35)
    col *= sh[..., None]
    col[water == 1] = (34, 70, 128); col[water == 2] = (58, 118, 190); col[water == 3] = (64, 128, 200)
    col[outer] = col[outer] * 0.62 + np.array([40, 34, 44]) * 0.38
    S = 2
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).resize((G * S, G * S), Image.BICUBIC)
    d = ImageDraw.Draw(img)
    try:
        f = ImageFont.truetype("georgia.ttf", 18); fb = ImageFont.truetype("georgiab.ttf", 30); fs = ImageFont.truetype("georgia.ttf", 14)
    except Exception:
        f = fb = fs = ImageFont.load_default()
    P = lambda x, z: ((x + HALF) / GM * S, (z + HALF) / GM * S)
    # roads (same ids/topology as WorldGen.roads)
    byid = {p["settlement_id"]: p["id"] for p in sets}
    rw = {"kingdom": 6, "rural": 4, "frontier": 2}
    for r in places["roads"]:
        A, B = out[byid[r["a"]]], out[byid[r["b"]]]
        d.line([P(A["x"], A["z"]), P(B["x"], B["z"])], fill=(120, 84, 52), width=rw.get(r["tier"], 2))
    # border
    x0, z0 = P(box[0], box[1]); x1, z1 = P(box[2], box[3])
    for o in range(3):
        d.rectangle([x0 - o, z0 - o, x1 + o, z1 + o], outline=(200, 40, 40))
    d.text((x0 + 8, z0 + 6), "KINGDOM OF VALENCIOUS", font=fb, fill=(250, 235, 200))
    # outer realms
    for lbl, (x, z) in anc["outer_labels"].items():
        d.text(P(x, z), lbl, font=fb, fill=(235, 225, 240), anchor="mm")
    for lbl, (x, z) in anc.get("region_labels", {}).items():
        d.text(P(x, z), lbl, font=f, fill=(255, 250, 225), anchor="mm", stroke_width=2, stroke_fill=(40, 30, 20))
    # places
    sym = {"castle": ((230, 200, 60), 12), "town": ((240, 240, 240), 8), "frontier_town": ((220, 220, 220), 7), "village": ((250, 250, 250), 5)}
    for pid, q in out.items():
        x, y = P(q["x"], q["z"])
        if q["kind"] in sym:
            c, r = sym[q["kind"]]
            d.ellipse([x - r, y - r, x + r, y + r], fill=c, outline=(30, 20, 10), width=2)
            d.text((x + r + 3, y - 9), q["name"], font=f if q["kind"] != "village" else fs, fill=(255, 255, 240), stroke_width=2, stroke_fill=(30, 20, 10))
        elif q["kind"] in ("elder_stone",):
            d.regular_polygon((x, y, 7), 4, fill=(120, 220, 255), outline=(0, 0, 0))
        elif q["kind"] in ("keep", "fort", "watchfort"):
            d.rectangle([x - 4, y - 4, x + 4, y + 4], fill=(170, 60, 50), outline=(0, 0, 0))
        elif q["kind"] in ("rift", "scar_arena"):
            d.ellipse([x - 14, y - 14, x + 14, y + 14], outline=(210, 90, 255), width=4)
        elif q["kind"] in ("wayshrine", "shrine"):
            d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(255, 210, 120))
    # legend
    lx, ly = 20, G * S - 250
    d.rectangle([lx - 10, ly - 10, lx + 330, G * S - 10], fill=(20, 18, 24))
    for n_, (k_, c_) in enumerate([("grass", 0), ("forest", 1), ("meadow", 2), ("farmland", 3), ("marsh", 4), ("highland", 5), ("rift", 6), ("snow", 7)]):
        d.rectangle([lx, ly + n_ * 26, lx + 20, ly + n_ * 26 + 18], fill=COL[c_]); d.text((lx + 30, ly + n_ * 26), k_, font=f, fill=(240, 240, 240))
    d.text((lx + 140, ly), "red: Valencious border", font=fs, fill=(240, 160, 160))
    d.text((lx + 140, ly + 24), "dim: region-locked", font=fs, fill=(200, 200, 200))
    d.text((lx + 140, ly + 48), "blue diamond: Elder Stone", font=fs, fill=(200, 230, 255))
    d.text((lx + 140, ly + 72), "violet ring: Rift / Scar", font=fs, fill=(220, 180, 255))
    d.text((lx + 140, ly + 96), "32 x 32 km, 2 km grid", font=fs, fill=(200, 200, 200))
    d.text((lx + 140, ly + 120), "base: Lake District DEM,", font=fs, fill=(200, 200, 200))
    d.text((lx + 140, ly + 138), "mirrored N-S, x1.3 compressed", font=fs, fill=(200, 200, 200))
    img.save(a.png)
    # --- engine exports -----------------------------------------------------------------------------------------------
    # TPS remap (old -> new) for anything not in the place table: f(p) = a0 + a1 x + a2 z + sum w_i r^2 log r
    def tps_fit(src, dst):
        n = len(src)
        r = np.hypot(src[:, None, 0] - src[None, :, 0], src[:, None, 1] - src[None, :, 1])
        K = np.where(r > 0, r * r * np.log(np.maximum(r, 1e-9)), 0.0)
        P = np.hstack([np.ones((n, 1)), src])
        A = np.zeros((n + 3, n + 3)); A[:n, :n] = K; A[:n, n:] = P; A[n:, :n] = P.T
        b = np.zeros((n + 3, 2)); b[:n] = dst
        return np.linalg.solve(A, b)
    sol = tps_fit(old, new)
    tps = {"centres": old.tolist(), "w": sol[:len(old)].tolist(), "affine": sol[len(old):].tolist()}
    # lakes: id map (1-based, dilated one cell so the shore band has a level) + levels
    lab, nlab = ndimage.label(water == 2)
    lakes_out = []
    lid = np.zeros((G, G), np.uint8)
    for k in range(1, nlab + 1):
        m = lab == k
        if m.sum() < 4:
            continue
        ys, xs = np.nonzero(m)
        cx, cz = xs.mean() * GM - HALF + GM / 2, ys.mean() * GM - HALF + GM / 2
        best_l = min(meta["lakes"], key=lambda L: math.hypot(L["centre"][0] - cx, L["centre"][1] - cz))
        lakes_out.append({"id": len(lakes_out) + 1, "level": best_l["level"], "centre": [round(cx), round(cz)], "area_km2": round(float(m.sum()) * GM * GM / 1e6, 3)})
        lid[ndimage.binary_dilation(m, iterations=1) & (lid == 0)] = len(lakes_out)
    lid[ndimage.binary_dilation(water == 1, iterations=1) & (lid == 0)] = 255   # sea, level 0
    Image.fromarray(lid).save(os.path.join(RD, "lake_ids.png"))
    # name the lake nearest Ashford "Emberglass Mere"
    if lakes_out:
        em = min(lakes_out, key=lambda L: math.hypot(*L["centre"]))
        em["name"] = "Emberglass Mere"
    # rivers: trace D8 paths of river cells downstream (flow.npy from gen_real_world.py), 32 m points, widths by catchment
    acc = np.load(os.path.join(RD, "flow.npy"))
    river = water == 3
    def down(j, i):
        best, bj, bi = 0.0, -1, -1
        for dj in (-1, 0, 1):
            for di in (-1, 0, 1):
                jj, ii = j + dj, i + di
                if (dj or di) and 0 <= jj < G and 0 <= ii < G and acc[jj, ii] > acc[j, i] and acc[jj, ii] > best:
                    best, bj, bi = acc[jj, ii], jj, ii
        return bj, bi
    srcs = []
    for j, i in zip(*np.nonzero(river)):
        up = False
        for dj in (-1, 0, 1):
            for di in (-1, 0, 1):
                jj, ii = j + dj, i + di
                if (dj or di) and 0 <= jj < G and 0 <= ii < G and river[jj, ii] and acc[jj, ii] < acc[j, i]:
                    if (jj, ii) != (j, i) and down(jj, ii) == (j, i):
                        up = True
        if not up:
            srcs.append((acc[j, i], j, i))
    srcs.sort(reverse=True)
    seen = set()
    rivers_out = []
    for _, j, i in sorted(srcs, key=lambda s: s[0]):
        pts = []
        while 0 <= j < G and 0 <= i < G:
            pts.append((i * GM - HALF + GM / 2, j * GM - HALF + GM / 2, float(acc[j, i])))
            if (j, i) in seen or water[j, i] in (1, 2):
                break
            seen.add((j, i))
            j, i = down(j, i)
            if j < 0:
                break
        if len(pts) >= 6:
            p = np.array(pts)
            for _ in range(2):   # Chaikin smoothing keeps both ends
                q = np.empty((len(p) * 2 - 2, 3)); q[0::2] = p[:-1] * 0.75 + p[1:] * 0.25; q[1::2] = p[:-1] * 0.25 + p[1:] * 0.75
                p = np.vstack([p[:1], q, p[-1:]])
            rivers_out.append({"points": [[round(a, 1), round(b, 1)] for a, b, _ in p],
                               "width": [round(float(np.clip(3.0 + 1.1 * math.sqrt(w), 4.0, 22.0)), 1) for _, _, w in p]})
    rivers_out.sort(key=lambda r: -max(r["width"]))
    names = ["The Silverrun", "The Ashrun", "The Greyfell", "The Westwater", "The Coldbeck", "The Emberrun"]
    for k, r in enumerate(rivers_out[:len(names)]):
        r["name"] = names[k]
    # soft biome field for WorldBiomes (256 px over 32 km, 8 channels, 150 m-ish blur)
    soft = np.zeros((G, G, 8), np.float32)
    for b in range(8):
        soft[..., b] = ndimage.gaussian_filter((biome == b).astype(np.float32), 3)
    soft = soft[2::4, 2::4]
    soft = soft / np.maximum(soft.sum(-1, keepdims=True), 1e-6)
    sb = np.clip(np.round(soft * 255), 0, 255).astype(np.uint8)
    Image.fromarray(sb[..., :4], "RGBA").save(os.path.join(RD, "biome_soft_a.png"))
    Image.fromarray(sb[..., 4:], "RGBA").save(os.path.join(RD, "biome_soft_b.png"))
    print("lakes", len(lakes_out), "rivers", len(rivers_out))
    # vertical-slice anchors (MASTER_BACKLOG.md section 3): bandit camp midway on the Ashford-Kingsreach road (150-250 m off it, gentle,
    # dry), cave entrance in the fells above (north of) Ashford: steep-ish slope face, 1-2.5 km out, well above the vale floor.
    def gi(x, z):
        return int(np.clip((z + HALF) / GM, 0, G - 1)), int(np.clip((x + HALF) / GM, 0, G - 1))
    ash = np.array([out["settlement:ashford"]["x"], out["settlement:ashford"]["z"]])
    kr = np.array([out["settlement:kingsreach"]["x"], out["settlement:kingsreach"]["z"]])
    mid = (ash + kr) / 2; dirv = (kr - ash) / np.linalg.norm(kr - ash); nrm = np.array([-dirv[1], dirv[0]])
    best_c = None
    for off in (-250, -200, -150, 150, 200, 250):
        for along in (-150, -75, 0, 75, 150):
            p = mid + nrm * off + dirv * along
            j, i = gi(*p)
            if wet[j, i] or dwater[j, i] < 60:
                continue
            c = slope[j, i] * 50 + abs(off) / 200
            if best_c is None or c < best_c[0]:
                best_c = (c, p)
    ash_h = h[gi(*ash)]
    best_v = None
    for r in range(1000, 2600, 100):
        for a in np.linspace(-0.6, 0.6, 13):   # around game north (-z)
            p = ash + np.array([math.sin(a), -math.cos(a)]) * r
            j, i = gi(*p)
            if wet[j, i]:
                continue
            c = abs(slope[j, i] - 0.45) * 20 - (h[j, i] - ash_h) / 100 + r / 3000
            if best_v is None or c < best_v[0]:
                best_v = (c, p)
    slice_ = {"ashford": ash.tolist(), "kingsreach": kr.tolist(),
              "bandit_camp": [round(float(v), 1) for v in best_c[1]] if best_c else None,
              "cave_entrance": [round(float(v), 1) for v in best_v[1]] if best_v else None}
    print("slice", slice_)
    # pin the slice's camp and dungeon-floor-1 entrance (mine theme) onto those anchors so every reader (WorldGen sites, lore, discovery) agrees
    for pid, key in (("site:Bandit Camp:490:612", "bandit_camp"), ("site:Kestrel's Folly:-665:-1133", "cave_entrance")):
        if pid in out and slice_.get(key):
            out[pid]["x"], out[pid]["z"] = slice_[key]
            out[pid]["slice"] = key
    lay = {"version": 1, "tps": tps, "slice": slice_, "lakes": lakes_out, "rivers": rivers_out, "box_note": "x0,z0,x1,z1", "world_version": 3, "generator": "kingdom/tools/world/real_layout.py", "valencious_box": box, "spread": anc["spread"],
           "places": out}
    json.dump(lay, open(os.path.join(RD, "layout.json"), "w"), indent=0)
    print("places", len(out), "outside box", sum(1 for q in out.values() if not q["in_valencious"]))
    for p in sets:
        q = out[p["id"]]; i, j = to_px(q["x"], q["z"])
        print(f'{p["name"]:14s} {q["x"]:8.0f} {q["z"]:8.0f} h={h[int(j), int(i)]:5.0f} slope={slope[int(j), int(i)]:.2f}')


if __name__ == "__main__":
    main()
