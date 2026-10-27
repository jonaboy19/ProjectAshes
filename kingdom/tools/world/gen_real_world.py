"""Rising Ashes real-world macro terrain (owner decision 2026-10-26): a 32 x 32 km window of the English Lake District
(AWS Terrain Tiles / terrarium z13, ~11 m/px; see docs/plans/DOWNLOADS.md) reprojected to the game grid, mirrored north-south
so the high Scafell/Wasdale fells become the snowy game NORTH, with sea, lakes, rivers and a northern highland uplift.

Usage:  py -E -B kingdom/tools/world/gen_real_world.py [--src <dir with mosaic_z13.npy>] [--out kingdom/data/world/real]

Outputs (kingdom/data/world/real/):
  height_16.png   4097 x 4097 16-bit grey, 8 m/px, corner registration px i <-> x = -16384 + 8 i, row j <-> z = -16384 + 8 j,
                  h = H_MIN + v/65535 * H_RANGE  (same filter-0 PNG layout WorldMacro already decodes)
  water.png       1024 x 1024 L8 at 32 m/px: 0 land, 1 sea, 2 lake, 3 river (from flow accumulation)
  flow.npy        (not committed) flow accumulation at 32 m for the mock-up
  meta.json       window, projection, stats, lake list
Game coords: metres from Ashford, x east, z south (north = -z). Real-world mapping: x = east offset, z = +north offset (mirrored).
"""
import argparse, json, math, os, zlib, struct, hashlib
import numpy as np
from scipy import ndimage

H_MIN, H_RANGE = -40.0, 1540.0
SIZE, MPP, HALF = 4097, 8.0, 16384.0
# Ashford (game origin) in the real world: Lorton Vale between Loweswater and Crummock Water.
ASH_LAT, ASH_LON = 54.5773, -3.3407
R_EARTH = 6371000.0
SEA_LEVEL = 0.0
HSCALE = 1.30            # 1 game metre = 1.3 real metres (fantasy compression: coast, lakes and fells inside 32 km; steeper, more dramatic slopes)
VSCALE = 1.15            # global vertical exaggeration
NORTH_UPLIFT = 1.6       # relief multiplier at the far game-north edge (Scottish-Highland style blend), 1.0 south of z=+2 km


def write_png16(path, arr_u16):
    h, w = arr_u16.shape
    raw = b"".join(b"\x00" + arr_u16[r].astype(">u2").tobytes() for r in range(h))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 16, 0, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(png)


def fbm(shape, seed, octaves, base_px):
    rng = np.random.default_rng(seed)
    out = np.zeros(shape, np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = max(2, int(shape[0] / (base_px / 2 ** o)))
        g = rng.standard_normal((s + 1, s + 1)).astype(np.float32)
        out += amp * ndimage.zoom(g, shape[0] / (s + 1), order=3)[: shape[0], : shape[1]]
        tot += amp
        amp *= 0.5
    return out / tot


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=r"C:\Users\Jonna\Documents\ProjectAshes_art_staging\terrain_real")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "..", "data", "world", "real"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    meta_src = json.load(open(os.path.join(a.src, "mosaic_meta.json")))
    big = np.load(os.path.join(a.src, "mosaic_z13.npy"))
    n = 2 ** meta_src["zoom"]

    g = -HALF + MPP * np.arange(SIZE, dtype=np.float64)
    X, Zg = np.meshgrid(g, g)                    # X east, Zg game-south
    north = Zg * HSCALE                           # mirrored: game south (+z) = real north
    lat = ASH_LAT + np.degrees(north / R_EARTH)
    lon = ASH_LON + np.degrees(X * HSCALE / (R_EARTH * math.cos(math.radians(ASH_LAT))))
    px = (lon + 180) / 360 * n * 256 - meta_src["tile_x0"] * 256
    py = (1 - np.arcsinh(np.tan(np.radians(lat))) / math.pi) / 2 * n * 256 - meta_src["tile_y0"] * 256
    del lat, lon
    h = ndimage.map_coordinates(big, [py, px], order=3, mode="nearest").astype(np.float32)
    del px, py
    h = ndimage.gaussian_filter(h, 0.8) * VSCALE  # kill terrarium/SRTM stair steps at 8 m

    # --- sea: connected to the map edge at <= 0.3 m
    low = h <= 0.3
    lab, _ = ndimage.label(low)
    edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    sea = np.isin(lab, edge[edge > 0])
    dsea = ndimage.distance_transform_edt(sea) * MPP
    h = np.where(sea, -1.5 - np.minimum(dsea * 0.012, 30.0), h)
    dland = ndimage.distance_transform_edt(~sea) * MPP
    h = np.where(~sea & (dland < 120), np.maximum(h, 0.4 + dland * 0.01), h)   # beach lip, never below sea

    # --- lakes: big very flat basins above sea (terrarium water surfaces are flat)
    gy, gx = np.gradient(h, MPP)
    slope = np.hypot(gx, gy)
    flat = (ndimage.uniform_filter(slope, 7) < 0.0045) & ~sea & (h > 2)
    lab, nl = ndimage.label(flat)
    sizes = ndimage.sum(np.ones_like(h), lab, range(1, nl + 1)) * MPP * MPP
    lakes = []
    lake = np.zeros_like(sea)
    for i, s in enumerate(sizes, 1):
        if s < 60000:
            continue
        m = lab == i
        lvl = float(np.median(h[m]))
        if np.ptp(h[m]) > 6:                     # flat farmland, not water
            continue
        # keep only cells close to the level, then fill holes (islands stay land by height)
        m = ndimage.binary_fill_holes(m & (np.abs(h - lvl) < 1.2))
        ys, xs = np.nonzero(m)
        lakes.append({"level": round(lvl, 2), "area_km2": round(float(m.sum()) * MPP * MPP / 1e6, 3),
                      "centre": [round(float(-HALF + xs.mean() * MPP)), round(float(-HALF + ys.mean() * MPP))]})
        dl = ndimage.distance_transform_edt(m) * MPP
        h = np.where(m, lvl - 1.0 - np.minimum(dl * 0.06, 25.0), h)
        lake |= m

    # --- northern uplift (game north = -z): more relief, more height -> snow realm
    t = np.clip((-Zg - (-2000.0)) / (HALF - (-2000.0)), 0, 1).astype(np.float32)   # 0 at z>=+2 km, 1 at the north edge
    t = t * t * (3 - 2 * t)
    base = ndimage.gaussian_filter(h, 60)                                           # ~0.5 km valley floor trend
    uplift = 1.0 + (NORTH_UPLIFT - 1.0) * t
    land = ~sea & ~lake
    h = np.where(land, base + (h - base) * uplift + 40.0 * t, h)
    h = np.where(lake, h + 40.0 * t, h)           # lakes ride the uplift (stay level with their shores)
    for L in lakes:
        cz = L["centre"][1]
        tt = float(np.clip((-cz + 2000.0) / (HALF + 2000.0), 0, 1))
        L["level"] = round(L["level"] + 40.0 * tt * tt * (3 - 2 * tt), 2)
        L["centre_real_note"] = ""

    # --- sub-30 m detail: slope-weighted fBm (1-4 m), none on water
    det = fbm(h.shape, 1066, 5, 512)
    gy, gx = np.gradient(h, MPP)
    slope = np.hypot(gx, gy)
    h = np.where(land, h + det * (1.0 + 3.0 * np.clip(slope, 0, 1)), h)

    # --- rivers: D8 flow accumulation on a 32 m grid
    c = h[::4, ::4][:1024, :1024].copy()
    cs = c.shape[0]
    wsea = sea[::4, ::4][:1024, :1024]
    wlake = lake[::4, ::4][:1024, :1024]
    import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from real_rivers import rivers
    acc, river, _ = rivers(c, wsea, wlake, 32.0, 20.0)
    water = np.zeros((cs, cs), np.uint8)
    water[wsea] = 1
    water[wlake] = 2
    water[river] = 3
    np.save(os.path.join(a.out, "flow.npy"), acc.astype(np.float32))

    # carve rivers into the 8 m height: width 6-20 m by catchment, depth 1.5-3 m
    rv = ndimage.zoom(np.where(river, np.sqrt(acc), 0).astype(np.float32), 4, order=1)[:SIZE, :SIZE]
    rv = np.pad(rv, ((0, SIZE - rv.shape[0]), (0, SIZE - rv.shape[1])), mode="edge")
    rmask = rv > 1.0
    dr = ndimage.distance_transform_edt(~rmask) * MPP
    depth = np.clip(1.5 + rv * 0.15, 1.5, 3.0) * np.clip(1 - dr / 14.0, 0, 1)
    hs = ndimage.gaussian_filter(h, 1.5)
    h = np.where(land & (dr < 14), np.minimum(h, hs) - depth, h)

    h = np.clip(h, H_MIN, H_MIN + H_RANGE)
    q = np.round((h - H_MIN) / H_RANGE * 65535).astype(np.uint16)
    write_png16(os.path.join(a.out, "height_16.png"), q)
    from PIL import Image
    Image.fromarray(water).save(os.path.join(a.out, "water.png"))
    landh = h[land]
    meta = {
        "generator": "kingdom/tools/world/gen_real_world.py",
        "source": "AWS Terrain Tiles terrarium z13 (Mapzen/AWS Open Data; SRTM, EU-DEM/Copernicus, OS Terrain 50 via Mapzen). See docs/plans/DOWNLOADS.md",
        "real_area": "English Lake District, Cumbria UK: Lorton Vale / Loweswater / Crummock / Ennerdale / Wasdale / Scafell, coast Whitehaven-Workington",
        "ashford_latlon": [ASH_LAT, ASH_LON],
        "mirror": "north-south mirrored: game north (-z) = real south (Scafell massif), game south (+z) = real north (Cockermouth / Derwent plain / Skiddaw)",
        "size": SIZE, "m_per_px": MPP, "world_half_m": HALF,
        "registration": "corner: px i <-> x = -16384 + 8 i, row j <-> z = -16384 + 8 j",
        "h_min_m": H_MIN, "h_range_m": H_RANGE, "height_formula": "h = -40 + v/65535*1540", "sea_level_m": SEA_LEVEL,
        "north_uplift": NORTH_UPLIFT, "hscale": HSCALE, "vscale": VSCALE,
        "water_png": "1024x1024 L8 32 m/px: 0 land 1 sea 2 lake 3 river",
        "lakes": lakes,
        "height_stats_m": {"land_min": float(landh.min()), "max": float(h.max()), "land_mean": float(landh.mean()),
                           "sea_pct": float(sea.mean() * 100), "lake_pct": float(lake.mean() * 100)},
        "sha256_height": hashlib.sha256(open(os.path.join(a.out, "height_16.png"), "rb").read()).hexdigest(),
    }
    json.dump(meta, open(os.path.join(a.out, "meta.json"), "w"), indent=1)
    print(json.dumps(meta["height_stats_m"]), len(lakes), "lakes")


if __name__ == "__main__":
    main()
