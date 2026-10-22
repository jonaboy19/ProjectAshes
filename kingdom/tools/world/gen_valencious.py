"""Valencious macro heightmap + biome/splat generator (phase W1a of WORLD_BRIEF.md).

Deterministic (seed 1066), numpy/scipy/Pillow only. Run from the repo root:
    py -E -B kingdom/tools/world/gen_valencious.py            # writes kingdom/data/world/macro/*
    py -E -B kingdom/tools/world/gen_valencious.py --verify   # regenerates to a temp dir, asserts byte-identical to the committed files
(`py -I` would hide the user site-packages where numpy/scipy/Pillow live on this machine; -E -B is the same idea without that.)

Inputs  : docs/world/valencious_places.json  (bible: settlements, camps, rivers, lake)
          kingdom/data/world/valencious_regions.json (12 sub-regions: lobes, height band, roughness, ridged share, biome weights)
          kingdom/data/world/macro/raw_core.json (WorldGen._raw_height around Ashford/Kingsreach, from tools_qa/world/dump_raw_height.gd)
Outputs : kingdom/data/world/macro/height_16.png   4097 x 4097, 16-bit, corner-registered, 3 m/px, h = -20 + v/65535 * 320 (metres)
          kingdom/data/world/macro/biome_ids.png   1024 x 1024, 8-bit ids (0 grass 1 forest 2 meadow 3 farmland 4 marsh 5 highland 6 rift 7 snow)
          kingdom/data/world/macro/splat_weights.png 1024 x 1024 RGBA = meadow, farmland, marsh, rift-ash weights
          kingdom/data/world/macro/preview.png     2048 x 2048 hillshade + hypsometric tint + places
          kingdom/data/world/macro/meta.json
Pixel (i, j) <-> world x = -6144 + 3 i, z = -6144 + 3 j (row j = z; north = -z = row 0). Height texture sampling is bilinear.
"""
import hashlib
import io
import json
import os
import shutil
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import valencious_common as vc  # noqa: E402

N = 4097                # full-res samples (corner-registered)
MPP = 3.0
NC = 1025               # coarse grid for the large-scale composition (12 m)
CM = vc.WORLD / (NC - 1)
H_MIN, H_RANGE = -20.0, 320.0
BIOMES = ["grass", "forest", "meadow", "farmland", "marsh", "highland", "rift", "snow"]
BID = {b: i for i, b in enumerate(BIOMES)}
SEED = vc.SEED

RIFT_POS = (1130.0, 1004.0)
SCAR_POS = (2509.0, 2468.0)
MERE = (-420.0, 300.0)


def smoothstep(a, b, x):
    return vc.smoothstep(a, b, x)


def grid(n):
    c = (np.arange(n, dtype=np.float32) * (vc.WORLD / (n - 1))) - vc.HALF
    return np.meshgrid(c, c)  # X (cols), Z (rows)


def load_inputs():
    places = vc.load_json(vc.PLACES_JSON)
    regs = vc.load_json(vc.REGIONS_JSON)
    raw = vc.load_json(os.path.join(vc.MACRO_DIR, "raw_core.json"))
    return places, regs, raw


def densify(pts, step=12.0):
    pts = np.array(pts, np.float32)
    seg = np.hypot(*np.diff(pts, axis=0).T)
    s_ = np.concatenate([[0.0], np.cumsum(seg)])
    ss = np.arange(0.0, s_[-1], step)
    return np.stack([np.interp(ss, s_, pts[:, 0]), np.interp(ss, s_, pts[:, 1])], 1).astype(np.float32)


def dist_to_polyline(X, Z, pts):
    d, _ = cKDTree(densify(pts)).query(np.stack([X.ravel(), Z.ravel()], 1), k=1)
    return d.reshape(X.shape).astype(np.float32)


def polyline_path(rivers, idxs):
    pts = []
    for i in idxs:
        pts.extend([(p[0], p[1]) for p in rivers[i]])
    pts = np.array(pts, np.float32)
    seg = np.hypot(*np.diff(pts, axis=0).T)
    s = np.concatenate([[0.0], np.cumsum(seg)]).astype(np.float32)
    return pts, s


def region_weights(regs, X, Z):
    """Soft per-region weights on the coarse grid: warped hard partition, then gaussian blend (blend_m)."""
    regions = regs["regions"]
    wx, wz = vc.warp_fields(NC, SEED, regs["border_warp"])
    idx, _ = vc.region_index(regions, X, Z, (wx, wz))
    sigma = regs["blend_m"] / CM / 2.0
    W = np.zeros((len(regions),) + X.shape, np.float32)
    for i in range(len(regions)):
        W[i] = ndimage.gaussian_filter((idx == i).astype(np.float32), sigma, mode="nearest")
    W /= np.maximum(W.sum(0, keepdims=True), 1e-6)
    return W, idx


def generate():
    places, regs, raw = load_inputs()
    regions = regs["regions"]
    X, Z = grid(NC)
    W, idx = region_weights(regs, X, Z)

    def pmap(key, default=0.0):
        return sum(W[i] * float(r.get(key, default)) for i, r in enumerate(regions))
    hmin = pmap("h_min")
    hmax = pmap("h_max")
    rough = pmap("roughness")
    ridge_share = pmap("ridged")
    terr_s = sum(W[i] * float(r["terrace"][0]) if "terrace" in r else 0.0 * W[i] for i, r in enumerate(regions))
    terr_step = sum(W[i] * float(r["terrace"][1]) if "terrace" in r else W[i] * 6.0 for i, r in enumerate(regions))

    # ---- large-scale relief shapes (0..1) -------------------------------------------------------
    low = vc.fbm(NC, 130, 4, SEED + 1)                  # ~1.5 km swells
    mid = vc.fbm(NC, 36, 4, SEED + 2)                   # ~430 m hills
    # massifs: E-W stretched ridged multifractal, domain-warped, masked by a low-frequency envelope
    wxm, wzm = vc.warp_fields(NC, SEED + 5, 600.0)
    Xw, Zw = X + wxm, Z + wzm
    rid = vc.ridged(NC, 190, 5, SEED + 3, aniso=1.7)
    rid2 = vc.ridged(NC, 70, 4, SEED + 4, aniso=1.2)
    env = np.clip(0.5 + 0.9 * vc.fbm(NC, 110, 3, SEED + 6), 0.0, 1.0)
    smooth_shape = np.clip(0.5 + 0.40 * low + 0.34 * rough * mid, 0.0, 1.0)
    mount_shape = np.clip(0.04 + 1.55 * (0.65 * rid + 0.35 * rid2 - 0.10) * (0.45 + 0.55 * env) + 0.10 * low, 0.0, 1.0)
    generic = (1.0 - ridge_share) * smooth_shape + ridge_share * mount_shape
    # coherent ranges: spines (distance falloff x ridged noise), a plateau, broken mesas
    spines = {sp["id"]: sp for sp in regs["spines"]}
    S_main = np.zeros(X.shape, np.float32)
    for sid in ("grimfen_spine", "spur_west", "spur_east", "highwatch_ridge"):
        sp = spines[sid]
        dd = dist_to_polyline(X, Z, sp["pts"])
        crest = np.exp(-np.power(dd / sp["half_width_m"], 2.2)) * (0.62 + 0.38 * rid) * sp.get("scale", 1.0)
        if "notch" in sp:
            dn = np.hypot(X - sp["notch"]["at"][0], Z - sp["notch"]["at"][1])
            crest = crest * (1.0 - sp["notch"]["cut"] * np.exp(-np.square(dn / sp["notch"]["radius_m"])))
        S_main = np.maximum(S_main, crest)
    rr_ = 0.65 * rid + 0.35 * rid2
    ridn = np.clip(rr_ / float(np.percentile(rr_, 80)), 0.0, 1.3)
    spine_shape = np.clip(0.08 + 1.0 * S_main * (0.35 + 0.65 * ridn) + 0.10 * low + 0.30 * np.square(ridn) * S_main, 0.0, 1.0)
    sp = spines["ironmarch_scarp"]
    S_iron = np.exp(-np.power(dist_to_polyline(X, Z, sp["pts"]) / sp["half_width_m"], 1.7)) * (0.6 + 0.4 * rid2) * sp["scale"]
    mesa = smoothstep(-0.02, 0.10, vc.fbm(NC, 45, 2, SEED + 14) + 0.5 * vc.fbm(NC, 14, 3, SEED + 16))
    mesa_shape = np.clip(0.18 + 0.42 * mesa + 0.30 * S_iron + 0.08 * mid, 0.0, 1.0)
    pl = regs["plateau"]["dunhallow"]
    de = np.hypot((X - pl["centre"][0]) / pl["radii_m"][0], (Z - pl["centre"][1]) / pl["radii_m"][1]) + 0.07 * low + 0.10 * vc.fbm(NC, 40, 3, SEED + 15)
    pmask = 1.0 - smoothstep(0.86, 1.0, de)
    plateau_shape = np.clip(pl["level"] * pmask + (0.16 + 0.10 * mid) * (1.0 - pmask) + 0.07 * rid * pmask + 0.04 * mid * pmask, 0.0, 1.0)
    shape = np.zeros(X.shape, np.float32)
    for i, r in enumerate(regions):
        st = r.get("style")
        shape += W[i] * {"spine": spine_shape, "plateau": plateau_shape, "mesa": mesa_shape}.get(st, generic)
    shape = np.maximum(shape, spine_shape * smoothstep(0.08, 0.5, S_main))   # the range is continuous across region borders
    H = hmin + (hmax - hmin) * shape

    # ---- scarred / broken ground ----------------------------------------------------------------
    if np.any(terr_s > 0.01):
        t = H / np.maximum(terr_step, 1.0)
        fr = t - np.floor(t)
        Ht = (np.floor(t) + smoothstep(0.30, 0.70, fr)) * terr_step
        H = H + (Ht - H) * np.clip(terr_s, 0.0, 1.0)
    rift_w = np.exp(-np.square(np.hypot(X - RIFT_POS[0], Z - RIFT_POS[1]) / 260.0)) + np.exp(-np.square(np.hypot(X - SCAR_POS[0], Z - SCAR_POS[1]) / 420.0))
    crack = vc.ridged(NC, 24, 3, SEED + 8)
    H -= 4.0 * smoothstep(0.55, 0.85, crack) * np.clip(W[[i for i, r in enumerate(regions) if r["id"] in ("rift_marches", "ashen_scar")]].sum(0), 0, 1)
    # the Rift: shallow scarred depression with a raised lip; the Ashen Scar: wide broken crater
    r_rift = np.hypot(X - RIFT_POS[0], Z - RIFT_POS[1])
    H -= 9.0 * np.exp(-np.square(r_rift / 170.0)) - 4.0 * np.exp(-np.square((r_rift - 300.0) / 70.0))
    r_scar = np.hypot(X - SCAR_POS[0], Z - SCAR_POS[1])
    H -= 16.0 * np.exp(-np.square(r_scar / 300.0)) - 7.0 * np.exp(-np.square((r_scar - 460.0) / 110.0))
    gul = vc.ridged(NC, 7, 3, SEED + 12)
    H -= 5.0 * smoothstep(0.58, 0.85, gul) * W[[i for i, r in enumerate(regions) if r["id"] == "ashen_scar"][0]] * (1.0 - 0.7 * np.exp(-np.square(r_scar / 250.0)))

    # ---- grand tilt: the Northern Ridge and the NE highlands are the 'high' of the world; the SW river country the low ----
    Hbase = H.copy()

    # ---- river valleys: carve the Ashrun (through the Mere) and the Silverrun --------------------
    rivers = places["rivers"]
    mere_pen = None
    valley_d = np.full(X.shape, 1e9, np.float32)
    for name, idxs in (("ashrun", [0, 1]), ("silverrun", [2])):
        pts, s = polyline_path(rivers, idxs)
        # densify to ~12 m
        tot = float(s[-1])
        ss = np.arange(0.0, tot, 12.0, dtype=np.float32)
        px_ = np.interp(ss, s, pts[:, 0])
        pz_ = np.interp(ss, s, pts[:, 1])
        # the macro valley meanders +-80 m around WorldGen's straight-ish polyline (the channel stays inside the 150 m half-width)
        ln = ndimage.gaussian_filter1d(np.random.default_rng(SEED + 31 + len(name)).standard_normal(len(ss)), 40, mode="nearest")
        ln = ln / (ln.std() + 1e-6)
        tx_, tz_ = np.gradient(px_), np.gradient(pz_)
        nn = np.maximum(np.hypot(tx_, tz_), 1e-6)
        taper = smoothstep(0.0, 500.0, ss) * (smoothstep(0.0, 700.0, np.hypot(px_ - MERE[0], pz_ - MERE[1])) if name == "ashrun" else 1.0)
        off = np.clip(80.0 * ln, -80.0, 80.0) * taper
        px_ = (px_ + (-tz_ / nn) * off).astype(np.float32)
        pz_ = (pz_ + (tx_ / nn) * off).astype(np.float32)
        ci = np.clip((px_ + vc.HALF) / CM, 0, NC - 1)
        cj = np.clip((pz_ + vc.HALF) / CM, 0, NC - 1)
        along = ndimage.map_coordinates(Hbase, [cj, ci], order=1, mode="nearest")
        sm = ndimage.gaussian_filter1d(along, 28, mode="nearest")        # ~340 m
        fl = np.minimum.accumulate(sm - 6.0)                            # never rises downstream
        fl = fl - 0.0012 * ss                                           # and always falls a little
        fl = np.maximum(fl, 1.2)
        tree = cKDTree(np.stack([px_, pz_], 1))
        d, k = tree.query(np.stack([X.ravel(), Z.ravel()], 1), k=1)
        d = d.reshape(X.shape).astype(np.float32)
        kk = k.reshape(X.shape)
        f = fl[kk]
        T = f + 15.0 * smoothstep(0.0, 150.0, d) + 0.02 * np.maximum(d - 150.0, 0.0)
        wv = 1.0 - smoothstep(150.0, 330.0, d)
        H = H + (T - H) * wv
        valley_d = np.minimum(valley_d, d)
        if name == "ashrun":
            # the Mere sits in a flat low basin at the floor level of its valley
            m_k = int(np.argmin(np.hypot(px_ - MERE[0], pz_ - MERE[1])))
            f_m = float(fl[m_k])
            rm = np.hypot(X - MERE[0], Z - MERE[1])
            Tm = f_m + 2.2 * smoothstep(0.0, 300.0, rm)
            H = H + (Tm - H) * (1.0 - smoothstep(260.0, 520.0, rm))
            mere_pen = f_m

    # ---- relief around registered places: settlements, camps -------------------------------------
    def plateau(H, cx, cz, r, k_in=1.2, k_out=2.8):
        ci_ = (cx + vc.HALF) / CM
        cj_ = (cz + vc.HALF) / CM
        lvl = float(ndimage.map_coordinates(ndimage.gaussian_filter(H, 3, mode="nearest"), [[cj_], [ci_]], order=1)[0])
        d = np.hypot(X - cx, Z - cz)
        w = 1.0 - smoothstep(r * k_in, r * k_out, d)
        return H + (lvl - H) * w
    for p in places["places"]:
        if p["category"] == "settlement":
            H = plateau(H, p["x"], p["z"], float(p["radius"]))
        elif p["kind"] in ("goblin_warren", "orc_village"):
            H = plateau(H, p["x"], p["z"], max(float(p.get("radius", 30.0)), 30.0) * 1.15, 1.0, 2.6)

    # ---- hold the two cores: raw noise terrain inside 600 m, blended (smoothstep 600..1600 m) into the macro, raw smoothed in the band ----
    for w in raw["windows"]:
        n = w["n"]
        arr = np.array(w["h_x10"], np.float32).reshape(n, n) / 10.0
        arr_s = ndimage.gaussian_filter(arr, 60.0 / w["step"], mode="nearest")
        cx, cz, half, step = w["cx"], w["cz"], w["half"], w["step"]
        gx = np.clip((X - (cx - half)) / step, 0, n - 1)
        gz = np.clip((Z - (cz - half)) / step, 0, n - 1)
        v1 = ndimage.map_coordinates(arr, [gz, gx], order=1, mode="nearest")
        v2 = ndimage.map_coordinates(arr_s, [gz, gx], order=1, mode="nearest")
        r = np.hypot(X - cx, Z - cz)
        rs = 300.0 if w["name"] == "ashford" else 350.0   # strict hold radius (tutorial/stamps live there)
        band = smoothstep(rs, rs + 500.0, r)
        vals = v1 * (1.0 - band) + v2 * band
        vals = H + (vals - H) * (1.0 - 0.6 * smoothstep(rs, rs + 400.0, r))   # damp the raw relief in the band so no rim forms
        hw = 1.0 - smoothstep(rs, 1600.0, r)
        H = H + (vals - H) * hw

    # ---- edge rim (as WorldGen._raw_height) -----------------------------------------------------
    edge = np.maximum(np.abs(X), np.abs(Z))
    rim = np.power(smoothstep(vc.HALF - 250.0, vc.HALF, edge), 1.5) * float(regs["rim_m"])
    # the rim is added where the core hold does not already include it (hold never reaches the edge)
    H = H + rim

    # ---- upsample to full res and add fine relief ------------------------------------------------
    cc = np.linspace(0.0, NC - 1.0, N, dtype=np.float64)
    cj_, ci_ = np.meshgrid(cc, cc, indexing="ij")
    Hf = ndimage.map_coordinates(H, [cj_, ci_], order=3, mode="nearest").astype(np.float32)
    upl = smoothstep(35.0, 110.0, hmax)
    amp_c = (0.2 + 0.9 * rough) * (0.25 + 0.75 * upl)          # ~50 % of before; smooth in the lowlands, bolder in the uplands
    holdc = np.zeros_like(amp_c)
    for w in raw["windows"]:
        r = np.hypot(X - w["cx"], Z - w["cz"])
        holdc = np.maximum(holdc, 1.0 - smoothstep(300.0, 1600.0, r))
    vald = 1.0 - 0.7 * (1.0 - smoothstep(0.0, 200.0, valley_d))
    amp_c = amp_c * (1.0 - holdc) * vald
    amp_f = ndimage.map_coordinates(amp_c.astype(np.float32), [cj_, ci_], order=1, mode="nearest").astype(np.float32)
    del cj_, ci_
    detail = vc.fbm(N, 40, 4, SEED + 9, gain=0.45)    # ~120 m ... 15 m
    Hf = Hf + detail * amp_f
    # the Rift: a jagged trench ~600 m long (stamp-style), applied at full resolution
    half_px = 160
    ci0 = int(round((RIFT_POS[0] + vc.HALF) / MPP)) - half_px
    cj0 = int(round((RIFT_POS[1] + vc.HALF) / MPP)) - half_px
    xs_ = -vc.HALF + MPP * (ci0 + np.arange(2 * half_px))
    zs_ = -vc.HALF + MPP * (cj0 + np.arange(2 * half_px))
    tx_g, tz_g = np.meshgrid(xs_ - RIFT_POS[0], zs_ - RIFT_POS[1])
    ang = np.deg2rad(25.0)
    u = tx_g * np.cos(ang) + tz_g * np.sin(ang)
    v = -tx_g * np.sin(ang) + tz_g * np.cos(ang)
    joff = 28.0 * np.sin(u / 57.0) + 17.0 * np.sin(u / 23.0 + 1.3) + 9.0 * np.sin(u / 11.0 + 0.4)
    wid = 16.0 + 6.0 * np.sin(u / 37.0 + 2.0)
    endf = 1.0 - smoothstep(160.0, 300.0, np.abs(u))
    vv = np.abs(v - joff)
    trench = 15.0 * np.exp(-np.square(vv / wid)) - 2.5 * np.exp(-np.square((vv - wid * 1.9) / 7.0))
    Hf[cj0:cj0 + 2 * half_px, ci0:ci0 + 2 * half_px] -= (trench * endf).astype(np.float32)
    Hf = ndimage.gaussian_filter(Hf, 1.2, mode="nearest")
    Hf = np.clip(Hf, H_MIN, H_MIN + H_RANGE)

    # ---- biome ids + splat weights (1024 grid, 12 m) ---------------------------------------------
    NB = 1024
    Hc = Hf[::4, ::4][:NB, :NB]                         # 12 m samples
    Xb, Zb = X[:NB, :NB], Z[:NB, :NB]
    Wb = W[:, :NB, :NB]                                 # same 12 m pitch as the coarse grid
    bw = np.zeros((len(BIOMES), NB, NB), np.float32)
    for i, r in enumerate(regions):
        for b, v in r["biomes"].items():
            bw[BID[b]] += Wb[i] * float(v)
    gy, gx = np.gradient(ndimage.gaussian_filter(Hc, 1.0), 12.0)
    slope = np.hypot(gx, gy)
    for b in range(len(BIOMES)):
        bw[b] *= 0.65 + 0.35 * np.clip(0.5 + 0.9 * vc.fbm(NB, 26, 3, SEED + 40 + b), 0.0, 1.0) * 1.6
    # lush valleys and farmland rings around settlements
    vd = valley_d[:NB, :NB]
    lush = 1.0 - smoothstep(60.0, 260.0, vd)
    bw[BID["meadow"]] += 0.35 * lush * (Hc < 90)
    for p in places["places"]:
        if p["category"] != "settlement":
            continue
        d = np.hypot(Xb - p["x"], Zb - p["z"])
        ring = np.exp(-np.square(d / (float(p["radius"]) * 4.5))) * (Hc < 110)
        bw[BID["farmland"]] += 0.9 * ring
        bw[BID["forest"]] *= 1.0 - 0.7 * ring
    bw[BID["rift"]] += 1.2 * rift_w_at(Xb, Zb, 0.55)
    bw[BID["marsh"]] += 0.9 * (Hc < 7.0) * (Wb[[i for i, r in enumerate(regions) if r["id"] == "westfen_marsh"][0]] > 0.25)
    bw[BID["highland"]] += 1.3 * smoothstep(0.35, 0.9, slope) + 0.8 * smoothstep(90.0, 160.0, Hc)
    bw[BID["forest"]] *= 1.0 - 0.8 * smoothstep(0.55, 1.0, slope)
    bw[BID["snow"]] = 0.0
    bw[BID["snow"]] = 3.0 * smoothstep(float(regs["snow_line_m"]) - 8.0, float(regs["snow_line_m"]) + 10.0, Hc + 6.0 * vc.fbm(NB, 20, 2, SEED + 77))
    bw = np.maximum(bw, 0.0)
    ids = np.argmax(bw, axis=0).astype(np.uint8)
    norm = np.maximum(bw.sum(0), 1e-6)
    sp = np.stack([bw[BID["meadow"]], bw[BID["farmland"]], bw[BID["marsh"]], bw[BID["rift"]]], -1) / norm[..., None]
    sp = ndimage.gaussian_filter(sp, (1.0, 1.0, 0.0), mode="nearest")
    splat = np.clip(sp * 255.0 * 1.15, 0, 255).astype(np.uint8)
    return Hf, ids, splat, (W, idx, mere_pen), places, regs


def rift_w_at(Xb, Zb, scale):
    a = np.exp(-np.square(np.hypot(Xb - RIFT_POS[0], Zb - RIFT_POS[1]) / (420.0 * scale + 200.0)))
    b = np.exp(-np.square(np.hypot(Xb - SCAR_POS[0], Zb - SCAR_POS[1]) / (700.0 * scale + 300.0)))
    return np.maximum(a, b)


def to_u16(Hf):
    v = np.round((Hf - H_MIN) / H_RANGE * 65535.0)
    return np.clip(v, 0, 65535).astype(np.uint16)


def png16_bytes(arr):
    """16-bit grayscale PNG with filter type 0 on every row (so the game can decode it without unfiltering: see world_macro.gd)."""
    import struct
    import zlib
    h, w = arr.shape
    rows = np.zeros((h, 1 + 2 * w), np.uint8)
    rows[:, 1:] = arr.astype(">u2").view(np.uint8).reshape(h, 2 * w)

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (bytes([137, 80, 78, 71, 13, 10, 26, 10]) + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 16, 0, 0, 0, 0)) +
            chunk(b"IDAT", zlib.compress(rows.tobytes(), 9)) + chunk(b"IEND", b""))


def png_bytes(arr, mode=None):
    bio = io.BytesIO()
    im = Image.fromarray(arr)
    im.save(bio, "PNG", compress_level=9, optimize=False)
    return bio.getvalue()


def preview(Hf, places, regs, mere_pen):
    """2048 hillshade + hypsometric tint, rivers, places."""
    P = 2048
    Hs = ndimage.zoom(Hf, P / (N - 1), order=1, mode="nearest")[:P, :P]
    cell = vc.WORLD / P
    gy, gx = np.gradient(Hs, cell)
    ex = 4.0
    sh = np.clip(0.55 + ex * (gx * -0.7 + gy * -0.7) * 0.9 / (1.0 + 0.0), 0.0, 1.0)  # light from NW
    sh = np.clip(0.5 + 2.2 * (-gx * 0.62 - gy * 0.78), 0.12, 1.0)
    stops = [(-20, (46, 90, 60)), (4, (78, 128, 70)), (20, (140, 170, 90)), (45, (196, 186, 110)), (90, (150, 118, 78)), (150, (120, 104, 96)),
             (190, (206, 206, 210)), (300, (250, 250, 252))]
    hv = np.array([s[0] for s in stops], np.float32)
    col = np.stack([np.interp(Hs, hv, np.array([s[1][c] for s in stops], np.float32)) for c in range(3)], -1)
    img = np.clip(col * (0.45 + 0.75 * sh[..., None]), 0, 255).astype(np.uint8)
    im = Image.fromarray(img)
    d = ImageDraw.Draw(im, "RGBA")
    f_s = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 13)
    f_b = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 15)

    def px(x, z):
        return ((x + vc.HALF) / vc.WORLD * P, (z + vc.HALF) / vc.WORLD * P)
    for rv in places["rivers"]:
        d.line([px(p[0], p[1]) for p in rv[::2]], fill=(70, 140, 230, 255), width=3)
    lc = px(*places["lake"]["center"])
    rr = places["lake"]["radius"] / vc.WORLD * P
    d.ellipse([lc[0] - rr, lc[1] - rr, lc[0] + rr, lc[1] + rr], fill=(70, 140, 230, 255))
    for p in places["places"]:
        q = px(p["x"], p["z"])
        if p["category"] == "settlement":
            rad = {"castle": 6, "town": 5, "frontier_town": 4, "village": 3}.get(p["kind"], 3)
            d.ellipse([q[0] - rad, q[1] - rad, q[0] + rad, q[1] + rad], fill=(255, 60, 40, 255) if p["kind"] == "castle" else (20, 20, 20, 255), outline=(255, 255, 255, 255))
            d.text((q[0] + rad + 3, q[1] - 8), p["display_name"], fill=(255, 255, 255, 255), font=f_b, stroke_width=2, stroke_fill=(0, 0, 0, 255))
        elif p["kind"] in ("rift", "elder_stone", "waterfall", "pass", "keep", "glade", "bones", "lake", "scar_arena"):
            c = (230, 80, 255, 255) if p["kind"] in ("rift", "scar_arena") else (255, 230, 90, 255)
            d.rectangle([q[0] - 3, q[1] - 3, q[0] + 3, q[1] + 3], outline=c, width=2)
            if p["kind"] in ("rift", "waterfall", "pass", "keep", "glade", "bones", "lake"):
                d.text((q[0] + 5, q[1] - 7), p["name"], fill=c, font=f_s, stroke_width=2, stroke_fill=(0, 0, 0, 255))
    for r in regs["regions"]:
        lx, lz, lr = r["lobes"][0]
        q = px(lx, lz)
        w = d.textlength(r["name"].upper(), font=f_b)
        d.text((q[0] - w / 2, q[1] + 10), r["name"].upper(), fill=(255, 255, 255, 150), font=f_b, stroke_width=1, stroke_fill=(0, 0, 0, 120))
    d.rectangle([6, P - 40, 760, P - 6], fill=(0, 0, 0, 150))
    d.text((12, P - 36), "Valencious macro heightmap preview: 12 288 m, north up, hillshade from the NW, tint = height (white > 190 m)", fill=(255, 255, 255, 255), font=f_s)
    d.text((12, P - 20), "Blue = Ashrun/Mere/Silverrun (WorldGen polylines), red dot = Kingsreach, magenta = Rift/Scar, yellow = Elder Stones/landmarks", fill=(255, 255, 255, 255), font=f_s)
    bio = io.BytesIO()
    im.save(bio, "PNG", compress_level=9)
    return bio.getvalue(), Hs


def write_all(out_dir):
    Hf, ids, splat, aux, places, regs = generate()
    W, idx, mere_pen = aux
    h16 = to_u16(Hf)
    files = {}
    files["height_16.png"] = png16_bytes(h16)
    files["biome_ids.png"] = png_bytes(ids)
    files["splat_weights.png"] = png_bytes(splat, "RGBA")
    pv, Hs = preview(Hf, places, regs, mere_pen)
    files["preview.png"] = pv
    Hq = h16.astype(np.float32) / 65535.0 * H_RANGE + H_MIN
    stats = {"min": float(Hq.min()), "max": float(Hq.max()), "mean": float(Hq.mean()), "p5": float(np.percentile(Hq[::7, ::7], 5)), "p50": float(np.percentile(Hq[::7, ::7], 50)),
             "p95": float(np.percentile(Hq[::7, ::7], 95)), "pct_above_snow": float((Hq > regs["snow_line_m"]).mean() * 100.0)}
    meta = {"generator": "kingdom/tools/world/gen_valencious.py", "seed": SEED, "size": N, "m_per_px": MPP, "registration": "corner: px i <-> x = -6144 + 3 i (i = 0..4096), row j <-> z = -6144 + 3 j",
            "world_half_m": vc.HALF, "h_min_m": H_MIN, "h_range_m": H_RANGE, "height_formula": "h = -20 + v/65535*320",
            "biome_grid": 1024, "biome_registration": "px i <-> x = -6144 + 12 i (i = 0..1023), row j <-> z = -6144 + 12 j", "biome_ids": {str(i): b for i, b in enumerate(BIOMES)}, "splat_channels": ["meadow", "farmland", "marsh", "rift_ash"],
            "height_stats_m": stats, "mere_floor_m": mere_pen,
            "inputs_sha256": {"docs/world/valencious_places.json": vc.sha256_file(vc.PLACES_JSON), "kingdom/data/world/valencious_regions.json": vc.sha256_file(vc.REGIONS_JSON),
                              "kingdom/data/world/macro/raw_core.json": vc.sha256_file(os.path.join(vc.MACRO_DIR, "raw_core.json")),
                              "kingdom/tools/world/gen_valencious.py": vc.sha256_file(os.path.abspath(__file__)),
                              "kingdom/tools/world/valencious_common.py": vc.sha256_file(os.path.join(vc.HERE, "valencious_common.py"))},
            "outputs_sha256": {k: hashlib.sha256(v).hexdigest() for k, v in files.items()}}
    files["meta.json"] = (json.dumps(meta, indent=1) + "\n").encode()
    os.makedirs(out_dir, exist_ok=True)
    for k, v in files.items():
        with open(os.path.join(out_dir, k), "wb") as f:
            f.write(v)
    print("wrote", out_dir, {k: len(v) for k, v in files.items()})
    print("height stats", stats)
    return files


def main():
    if "--verify" in sys.argv:
        tmp = tempfile.mkdtemp(prefix="valen_macro_")
        try:
            new = write_all(tmp)
            bad = []
            for k, v in new.items():
                p = os.path.join(vc.MACRO_DIR, k)
                if not os.path.exists(p) or open(p, "rb").read() != v:
                    bad.append(k)
            print("VERIFY", "PASS byte-identical" if not bad else "FAIL: " + ", ".join(bad))
            sys.exit(1 if bad else 0)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    write_all(vc.MACRO_DIR)


if __name__ == "__main__":
    main()
