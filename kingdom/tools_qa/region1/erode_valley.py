#!/usr/bin/env python
r"""Erosion detail for a Region 1 terrain stamp (docs/regions/LOOK_R1.md).

Runs dandrino/terrain-erosion-3-ways (MIT) through tools/external/erode_heightmap.py's erode() over the stamped
heights exported by bake_valley.gd --export, and writes the high-pass part of the change (gullies, scree fans,
softened ledges) as float32 metres, ready for bake_valley.gd --detail (it is applied on the walls only).

  C:\Users\Jonna\Tools\terrain-erosion-3-ways\venv\Scripts\python.exe kingdom/tools_qa/region1/erode_valley.py \
      --dir <export dir> --id hollins_reach --nx 215 --nz 409 --cell 3 [--iters 320] [--clamp 7]
"""
import argparse, os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..", "..", "..", "tools", "external")))
from erode_heightmap import erode  # noqa: E402  (also puts the MIT repo on sys.path)
from scipy.ndimage import gaussian_filter  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True)
    ap.add_argument("--id", required=True)
    ap.add_argument("--nx", type=int, required=True)
    ap.add_argument("--nz", type=int, required=True)
    ap.add_argument("--cell", type=float, default=3.0)
    ap.add_argument("--iters", type=int, default=320)
    ap.add_argument("--clamp", type=float, default=7.0)
    ap.add_argument("--seed", type=int, default=5)
    a = ap.parse_args()
    h = np.fromfile(os.path.join(a.dir, a.id + "_h.raw"), dtype="<f4").reshape(a.nz, a.nx).astype(np.float64)
    lo, hi = h.min(), h.max()
    span = max(hi - lo, 1e-3)
    n = (h - lo) / span
    # The MIT eroder assumes a square grid: pad with edge values, erode, crop back.
    side = max(a.nx, a.nz)
    sq = np.pad(n, ((0, side - a.nz), (0, side - a.nx)), mode="edge")
    after_sq, _flow = erode(sq.copy(), a.iters, full_width=side * a.cell, seed=a.seed)
    after = after_sq[:a.nz, :a.nx]
    # Compare in metres; the eroder keeps the range, but re-anchor the mean so only the local change is kept.
    delta = (after - n) * span
    delta -= gaussian_filter(delta, sigma=6.0)          # high-pass: gullies and ledges, not a global shift
    delta = np.clip(delta, -a.clamp, a.clamp).astype("<f4")
    out = os.path.join(a.dir, a.id + "_detail.raw")
    delta.tofile(out)
    print("OK", out, "range m", float(delta.min()), float(delta.max()), "mean abs", float(np.abs(delta).mean()))


if __name__ == "__main__":
    main()
