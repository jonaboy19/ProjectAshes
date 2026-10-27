"""Download AWS Terrain Tiles (terrarium) for the Rising Ashes 32 km real-terrain window and mosaic them.

Source: https://registry.opendata.aws/terrain-tiles/  (Mapzen / AWS Open Data; underlying SRTM, EU-DEM (Copernicus), OS Terrain 50 (OGL), ...).
Usage: py -E -B kingdom/tools/world/real_terrain_fetch.py <out_dir>
Writes <out_dir>/tiles/z13/x_y.png (raw, cached) and <out_dir>/mosaic_z13.npy (float32 metres) + mosaic_meta.json.
"""
import io, json, math, os, sys, urllib.request
import numpy as np
from PIL import Image

Z = 13
# Window bounds (padded a little beyond the 32 km square so reprojection never runs off the mosaic).
LAT_S, LAT_N = 54.40, 54.76
LON_W, LON_E = -3.68, -3.02


def tile_xy(lat, lon, z):
    n = 2 ** z
    x = (lon + 180) / 360 * n
    y = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n
    return x, y


def main(out):
    tdir = os.path.join(out, "tiles", f"z{Z}")
    os.makedirs(tdir, exist_ok=True)
    x0, y0 = tile_xy(LAT_N, LON_W, Z)
    x1, y1 = tile_xy(LAT_S, LON_E, Z)
    xs = range(int(x0), int(x1) + 1)
    ys = range(int(y0), int(y1) + 1)
    total = 0
    rows = []
    for ty in ys:
        row = []
        for tx in xs:
            p = os.path.join(tdir, f"{tx}_{ty}.png")
            if not os.path.exists(p):
                url = f"https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{Z}/{tx}/{ty}.png"
                data = urllib.request.urlopen(url, timeout=60).read()
                with open(p, "wb") as f:
                    f.write(data)
            total += os.path.getsize(p)
            a = np.asarray(Image.open(p).convert("RGB")).astype(np.float32)
            row.append(a[..., 0] * 256 + a[..., 1] + a[..., 2] / 256 - 32768)
        rows.append(np.hstack(row))
    big = np.vstack(rows).astype(np.float32)
    np.save(os.path.join(out, f"mosaic_z{Z}.npy"), big)
    meta = {"zoom": Z, "tile_x0": xs[0], "tile_y0": ys[0], "tiles_x": len(xs), "tiles_y": len(ys),
            "bytes_tiles": total, "shape": list(big.shape), "min": float(big.min()), "max": float(big.max()),
            "source": "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"}
    with open(os.path.join(out, "mosaic_meta.json"), "w") as f:
        json.dump(meta, f, indent=1)
    print(json.dumps(meta))


if __name__ == "__main__":
    main(sys.argv[1])
