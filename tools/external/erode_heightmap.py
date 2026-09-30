#!/usr/bin/env python
r"""Hydraulic erosion of a heightmap with dandrino/terrain-erosion-3-ways (MIT).

Runs in the tool's own venv (numpy/scipy/pillow/matplotlib/scikit-image):
  C:\Users\Jonna\Tools\terrain-erosion-3-ways\venv\Scripts\python.exe \
      tools/external/erode_heightmap.py --generate 512 --seed 7 --out <dir>/valley
  ...  --in some_height.png --out <dir>/eroded          (16-bit or 8-bit grey PNG, square)

Outputs: <out>_before.png/_after.png (16-bit heights, load into Terrain3D or
Blender), <out>_r16.raw (little-endian uint16, Terrain3D 'r16' import),
<out>_flow.png (normalised water accumulation = river mask),
<out>_compare.png (hillshaded before | after | flow).
Height range is 0..1 (normalised); scale in Terrain3D by your max height.
"""
import argparse, os, sys
import numpy as np
from PIL import Image

TOOL = os.environ.get("EROSION_REPO", r"C:\Users\Jonna\Tools\terrain-erosion-3-ways")
sys.path.insert(0, TOOL)
import util  # noqa: E402  (from the MIT repo)
from simulation import apply_slippage  # noqa: E402


def erode(terrain, iterations, full_width=200.0, seed=0, rain=0.0008, evap=0.0005,
          repose=0.03, gravity=30.0, capacity=50.0, dissolve=0.25, deposit=0.001):
    rng = np.random.default_rng(seed)
    shape = terrain.shape
    cell_width = full_width / shape[0]
    rain_rate = rain * cell_width ** 2
    sediment = np.zeros_like(terrain)
    water = np.zeros_like(terrain)
    velocity = np.zeros_like(terrain)
    flow = np.zeros_like(terrain)
    min_hd = 0.05
    for i in range(iterations):
        water += rng.random(shape) * rain_rate
        g = util.simple_gradient(terrain)
        g = np.select([np.abs(g) < 1e-10], [np.exp(2j * np.pi * rng.random(shape))], g)
        g /= np.abs(g)
        nh = util.sample(terrain, -g)
        hd = terrain - nh
        cap = (np.maximum(hd, min_hd) / cell_width) * velocity * water * capacity
        dep = np.select([hd < 0, sediment > cap],
                        [np.minimum(hd, sediment), deposit * (sediment - cap)],
                        dissolve * (sediment - cap))
        dep = np.maximum(-hd, dep)
        sediment -= dep
        terrain += dep
        sediment = util.displace(sediment, g)
        water = util.displace(water, g)
        flow += water
        terrain = apply_slippage(terrain, repose, cell_width)
        velocity = gravity * hd / cell_width
        water *= 1 - evap
        if i % 50 == 0:
            print(f"iter {i+1}/{iterations}", flush=True)
    return terrain, flow


def save16(a, path):
    Image.fromarray((np.clip(a, 0, 1) * 65535).astype(np.uint16)).save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp")
    ap.add_argument("--generate", type=int, help="generate fBm terrain of this size")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--iterations", type=int, default=0, help="default 1.4*size")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    np.random.seed(a.seed)
    if a.inp:
        im = Image.open(a.inp)
        arr = np.asarray(im).astype(np.float64)
        if arr.ndim == 3:
            arr = arr[..., 0]
        arr = util.normalize(arr)
    else:
        n = a.generate or 512
        arr = util.normalize(util.fbm([n, n], -2.0))
    before = arr.copy()
    iters = a.iterations or int(1.4 * arr.shape[0])
    after, flow = erode(arr.copy(), iters, seed=a.seed)
    after = util.normalize(after)
    flowm = util.normalize(np.log1p(flow / (flow.mean() + 1e-9)))
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    save16(before, a.out + "_before.png")
    save16(after, a.out + "_after.png")
    save16(flowm, a.out + "_flow.png")
    (np.clip(after, 0, 1) * 65535).astype("<u2").tofile(a.out + "_r16.raw")
    def shade(h):
        s = util.hillshaded(h)
        s = np.asarray(s)
        if s.ndim == 3:
            s = s[..., :3]
            return (np.clip(s, 0, 1) * 255).astype(np.uint8)
        return np.repeat((np.clip(s, 0, 1) * 255).astype(np.uint8)[..., None], 3, 2)
    fl = (np.repeat(flowm[..., None], 3, 2) * 255).astype(np.uint8)
    Image.fromarray(np.hstack([shade(before), shade(after), fl])).save(a.out + "_compare.png")
    print("OK", a.out, "size", arr.shape, "iters", iters)


if __name__ == "__main__":
    main()
