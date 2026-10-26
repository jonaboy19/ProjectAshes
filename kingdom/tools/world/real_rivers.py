"""Rivers for the real-world terrain: priority-flood depression filling (lakes and pits drain over their spill points),
then D8 flow accumulation. Pure numpy + heapq, ~1M cells in a few seconds.
Usage as a module: rivers(h, sea_mask, lake_mask, cell_m) -> (acc_km2, river_mask, filled)
"""
import heapq, math
import numpy as np


def priority_flood(h, sea):
    H, W = h.shape
    filled = h.astype(np.float64).copy()
    done = np.zeros(h.shape, bool)
    pq = []
    seed = sea.copy()
    seed[0, :] = seed[-1, :] = True
    seed[:, 0] = seed[:, -1] = True
    for j, i in zip(*np.nonzero(seed)):
        heapq.heappush(pq, (filled[j, i], j, i)); done[j, i] = True
    eps = 1e-4
    while pq:
        z, j, i = heapq.heappop(pq)
        for dj in (-1, 0, 1):
            for di in (-1, 0, 1):
                jj, ii = j + dj, i + di
                if (dj or di) and 0 <= jj < H and 0 <= ii < W and not done[jj, ii]:
                    done[jj, ii] = True
                    if filled[jj, ii] <= z:
                        filled[jj, ii] = z + eps
                    heapq.heappush(pq, (filled[jj, ii], jj, ii))
    return filled


def rivers(h, sea, lake, cell_m, min_km2=4.0):
    f = priority_flood(h, sea)
    H, W = f.shape
    pad = np.pad(f, 1, constant_values=1e9)
    idx = np.arange(H * W).reshape(H, W)
    pidx = np.pad(idx, 1, constant_values=-1)
    best = np.full(f.shape, -1, np.int64); bestd = np.zeros(f.shape)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            nb = pad[1 + dy:1 + dy + H, 1 + dx:1 + dx + W]
            drop = (f - nb) / math.hypot(dx, dy)
            take = drop > bestd
            bestd = np.where(take, drop, bestd)
            best = np.where(take, pidx[1 + dy:1 + dy + H, 1 + dx:1 + dx + W], best)
    acc = np.ones(H * W)
    bf = best.ravel()
    for i in np.argsort(-f, axis=None):
        j = bf[i]
        if j >= 0:
            acc[j] += acc[i]
    acc = acc.reshape(H, W) * cell_m * cell_m / 1e6
    return acc, (acc > min_km2) & ~sea & ~lake, f
