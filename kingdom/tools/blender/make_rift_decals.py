"""Region 1 L4: rift ground decals (procedural, no source art needed).

    blender -b --python make_rift_decals.py

Three 512 px RGBA ground decals for the spreading Scar: a soft lilac patch with a cracked-crystal network
(patch_a), a smaller patch with sparkles (patch_b) and a long fissure with lilac fringe (crack). Each comes
with an emission map (only the cyan cracks glow). Sunny storybook, not grimdark: the ground goes pale
lilac-lavender and semi-transparent with a fine cyan crack line, it never goes black or burnt.
Also writes the two scenes rift_decal.tscn (Godot Decal projector, HIGH/MEDIUM) and rift_decal_card.tscn
(a flat alpha quad for the LOW tier, which has no decals).

-> kingdom/assets/incoming/region1/rift/decals/
"""
import bpy, os, sys, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r1_common as C

OUT = os.path.join(C.R1, "rift", "decals")
N = 512
RES = "res://assets/incoming/region1/rift/decals/"
rng = np.random.default_rng(1066)


def fbm(seed, octaves=4, base=6):
    r = np.random.default_rng(seed)
    out = np.zeros((N, N), np.float32); amp, tot = 1.0, 0.0
    for o in range(octaves):
        g = base * 2 ** o
        grid = r.random((g + 1, g + 1)).astype(np.float32)
        xs = np.linspace(0, g, N, endpoint=False)
        x0 = xs.astype(int); fx = xs - x0
        fx = fx * fx * (3 - 2 * fx)
        a = grid[np.ix_(x0, x0)]; b = grid[np.ix_(x0, x0 + 1)]
        c = grid[np.ix_(x0 + 1, x0)]; d = grid[np.ix_(x0 + 1, x0 + 1)]
        top = a * (1 - fx)[None, :] + b * fx[None, :]
        bot = c * (1 - fx)[None, :] + d * fx[None, :]
        out += (top * (1 - fx)[:, None] + bot * fx[:, None]) * amp
        tot += amp; amp *= 0.5
    return out / tot


def voronoi_edges(npts, seed, spread=1.0):
    """distance-difference to the two nearest cell centres: ~0 on cell borders."""
    r = np.random.default_rng(seed)
    pts = r.random((npts, 2)) * spread + (1 - spread) / 2
    ys, xs = np.mgrid[0:N, 0:N].astype(np.float32) / N
    d1 = np.full((N, N), 9.0, np.float32); d2 = np.full((N, N), 9.0, np.float32)
    for (px, py) in pts:
        d = np.sqrt((xs - px) ** 2 + (ys - py) ** 2)
        m = d < d1
        d2 = np.where(m, d1, np.minimum(d2, d))
        d1 = np.where(m, d, d1)
    return d2 - d1


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def compose(kind, seed):
    ys, xs = np.mgrid[0:N, 0:N].astype(np.float32) / N
    cx, cy = xs - 0.5, ys - 0.5
    warp = fbm(seed, 4, 4)
    if kind == "crack":
        # long fissure: distance to a wavy line along x
        line = 0.5 + 0.09 * np.sin(xs * 9 + seed) + 0.05 * (fbm(seed + 3, 3, 5) - 0.5) * 4
        dist = np.abs(ys - line)
        fall = smooth(0.5 - np.abs(cx) * 1.0, 0.0, 0.18) * smooth(0.16 - dist * (0.9 + warp), 0.0, 0.14)
        crack = smooth(0.011 - dist, 0.0, 0.010) * smooth(0.5 - np.abs(cx), 0.02, 0.2)
        edges = voronoi_edges(28, seed, 0.7)
        crack = np.maximum(crack, smooth(0.010 - edges, 0.0, 0.010) * fall * 0.7)
    else:
        rad = np.sqrt(cx ** 2 + cy ** 2) * 2.0
        rad = rad + (warp - 0.5) * 0.5
        fall = 1 - smooth(rad, 0.55, 0.98)
        edges = voronoi_edges(46 if kind == "patch_a" else 30, seed, 0.9)
        crack = smooth(0.012 - edges, 0.0, 0.011) * smooth(1 - rad, 0.0, 0.5)
    # colour: pale lilac ground stain, slightly lighter near the middle; cracks cyan-white
    lil = np.array([0.66, 0.55, 0.88], np.float32)
    lav = np.array([0.80, 0.72, 0.96], np.float32)
    t = np.clip(fbm(seed + 7, 4, 5), 0, 1)[..., None]
    base = lil[None, None, :] * (1 - t) + lav[None, None, :] * t
    cyan = np.array([0.55, 0.97, 1.0], np.float32)
    rgb = base * (1 - crack[..., None]) + cyan[None, None, :] * crack[..., None]
    alpha = np.clip(fall * (0.72 + 0.28 * t[..., 0]) + crack * fall.clip(0.4, 1), 0, 1) * 0.92
    if kind == "patch_b":
        # sparkles: tiny crystal glints
        sp = (rng.random((N, N)) > 0.9985).astype(np.float32)
        k = np.ones((5, 5), np.float32)
        from numpy.lib.stride_tricks import sliding_window_view
        pad = np.pad(sp, 2)
        spd = sliding_window_view(pad, (5, 5)).max(axis=(2, 3))
        crack = np.clip(crack + spd * 0.9 * fall, 0, 1)
        rgb = rgb * (1 - spd[..., None] * 0.8) + np.array([0.9, 1.0, 1.0])[None, None, :] * spd[..., None] * 0.8
    emis = np.clip(crack * fall.clip(0.35, 1), 0, 1)
    return rgb, alpha, emis


def save(a, name):
    im = bpy.data.images.new(name, N, N, alpha=True)
    im.pixels = a.ravel(); im.filepath_raw = os.path.join(OUT, name); im.file_format = 'PNG'; im.save()
    print("WROTE", name)


def tscn():
    dec = f'''[gd_scene load_steps=3 format=3]

[ext_resource type="Texture2D" path="{RES}rift_decal_patch_a.png" id="1"]
[ext_resource type="Texture2D" path="{RES}rift_decal_patch_a_em.png" id="2"]

[node name="RiftDecal" type="Decal"]
size = Vector3(5, 2, 5)
texture_albedo = ExtResource("1")
texture_emission = ExtResource("2")
emission_energy = 1.1
albedo_mix = 0.9
upper_fade = 0.3
lower_fade = 0.3
distance_fade_enabled = true
distance_fade_begin = 70.0
distance_fade_length = 20.0
cull_mask = 1
'''
    card = f'''[gd_scene load_steps=5 format=3]

[ext_resource type="Texture2D" path="{RES}rift_decal_patch_a.png" id="1"]
[ext_resource type="Texture2D" path="{RES}rift_decal_patch_a_em.png" id="2"]

[sub_resource type="StandardMaterial3D" id="Mat"]
transparency = 1
shading_mode = 0
albedo_texture = ExtResource("1")
emission_enabled = true
emission = Color(0.55, 0.97, 1, 1)
emission_energy_multiplier = 0.9
emission_texture = ExtResource("2")

[sub_resource type="PlaneMesh" id="Plane"]
size = Vector2(5, 5)
material = SubResource("Mat")

[node name="RiftDecalCard" type="MeshInstance3D"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0.02, 0, 0, 0.03, 0)
mesh = SubResource("Plane")
cast_shadow = 0
'''
    card = card.replace("Transform3D(1, 0, 0, 0, 1, 0, 0, 0.02, 0, 0, 0.03, 0)", "Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.03, 0)")
    for name, txt in (("rift_decal.tscn", dec), ("rift_decal_card.tscn", card)):
        with open(os.path.join(OUT, name), "w", newline="\n") as f:
            f.write(txt)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for kind, seed in (("patch_a", 5), ("patch_b", 17), ("crack", 29)):
        rgb, alpha, emis = compose(kind, seed)
        out = np.zeros((N, N, 4), np.float32); out[..., :3] = rgb; out[..., 3] = alpha
        e = np.zeros((N, N, 4), np.float32); e[..., 0] = e[..., 1] = e[..., 2] = emis; e[..., 3] = 1
        save(out, f"rift_decal_{kind}.png"); save(e, f"rift_decal_{kind}_em.png")
    tscn()
