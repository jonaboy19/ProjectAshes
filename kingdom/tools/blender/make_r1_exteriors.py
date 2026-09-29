"""Region 1 L3 exteriors: Silverford guild hall + Dawn Throne chapel.

Harmonises two CC0 meshy_free buildings to the sunny storybook palette by recolouring their
baked texture (HSV remap) and adding a few hand-built accents (banners, guild sign, gold sun
emblem, weathervane sun). Writes LOD0 + LOD1 GLBs.

    blender -b --python make_r1_exteriors.py -- [guild] [chapel]

-> kingdom/assets/incoming/region1/silverford/{guildhall_silverford,chapel_dawn_throne}_lod{0,1}.glb
Sources (CC0): meshy_free/buildings/house_two_story_shingle, meshy_free/churches/church_white_red_spire.
Budget: house (LOD0 <= 20k tris / 1024 tex, LOD1 <= 6k / 512).
"""
import bpy, bmesh, os, sys, math
import numpy as np
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r1_common as C

OUT = os.path.join(C.R1, "silverford")
which = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["guild", "chapel"]


def hue_rules(img, rules, sat_mul=1.0, val_mul=1.0):
    a, (H, S, V) = C.get_hsv(img)
    H2, S2, V2 = H.copy(), S.copy(), V.copy()
    for r in rules:
        m = (H >= r["h0"]) & (H <= r["h1"]) & (S >= r.get("smin", 0)) & (S <= r.get("smax", 1)) & \
            (V >= r.get("vmin", 0.08)) & (V <= r.get("vmax", 1))
        if "nh" in r:
            H2[m] = r["nh"]
        S2[m] = np.clip(S[m] * r.get("sm", 1) + r.get("sadd", 0), 0, 1)
        V2[m] = np.clip(V[m] * r.get("vm", 1) + r.get("vadd", 0), 0, 1)
    S2 = np.clip(S2 * sat_mul, 0, 1); V2 = np.clip(V2 * val_mul, 0, 1)
    C.set_rgb(img, a, C.hsv2rgb(H2, S2, V2))


def sun_emblem(r=0.55, rays=12, depth=0.07):
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, radius=r * 0.42, segments=20)
    for i in range(rays):
        a = 2 * math.pi * i / rays
        L = r if i % 2 == 0 else r * 0.74
        w = 0.085 * r * (1.5 if i % 2 == 0 else 1.1)
        c, s = math.cos(a), math.sin(a)
        p0 = Vector((c * r * 0.38 - s * w, s * r * 0.38 + c * w, 0))
        p1 = Vector((c * L, s * L, 0))
        p2 = Vector((c * r * 0.38 + s * w, s * r * 0.38 - c * w, 0))
        bm.faces.new([bm.verts.new(p) for p in (p0, p1, p2)])
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=depth)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def _cube(bm, c, sx, sy, sz, rot_y=0.0):
    r = bmesh.ops.create_cube(bm, size=1.0)
    vs = r["verts"]
    bmesh.ops.scale(bm, vec=(sx, sy, sz), verts=vs)
    if rot_y:
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=__import__("mathutils").Matrix.Rotation(rot_y, 3, 'Y'), verts=vs)
    bmesh.ops.translate(bm, vec=c, verts=vs)


def banner_bm(w=0.8, h=2.0, tip=0.3):
    bm = bmesh.new()
    _cube(bm, (0, 0, -h / 2), w, 0.05, h)
    _cube(bm, (0, 0, -h), w / 1.414, 0.05, w / 1.414, math.radians(45))
    return bm


def diamond_bm(r=0.2):
    bm = bmesh.new()
    _cube(bm, (0, 0, 0), r * 1.2, 0.03, r * 2.0, math.radians(45))
    return bm


def front_hit(o, x, z, y0=-40.0):
    """First surface hit walking +Y from (x, y0, z): returns y (object space)."""
    ok, loc, nrm, idx = o.ray_cast(Vector((x, y0, z)), Vector((0, 1, 0)))
    return loc.y if ok else None


def run(kind, lod):
    src = {"chapel": ("churches", "church_white_red_spire"), "guild": ("buildings", "house_two_story_shingle")}[kind]
    C.reset()
    o = C.import_glb(os.path.join(C.MESHY_FREE, src[0], f"{src[1]}_lod{lod}.glb"))[0]
    img = C.tex_images(o)[0]
    extras = []
    if kind == "chapel":
        o.name = "ChapelDawnThrone"
        hue_rules(img, [
            dict(h0=0.0, h1=0.045, smin=0.3, vmax=0.75, nh=0.105, sm=0.9, vm=1.25, vadd=0.02),     # red roofs -> amber gold
            dict(h0=0.95, h1=1.0, smin=0.3, vmax=0.75, nh=0.105, sm=0.9, vm=1.25, vadd=0.02),
            dict(h0=0.42, h1=0.62, smin=0.15, nh=0.11, sm=2.0, vm=1.35, vadd=0.02),                # teal spire -> gold
            dict(h0=0.045, h1=0.13, smin=0.35, nh=0.115, sm=0.75, vm=1.0),                         # orange trim -> soft gold
        ])
        a, (H, S, V) = C.get_hsv(img)
        lo = (S < 0.2) & (V > 0.5)
        H[lo] = 0.11; S[lo] = np.clip(S[lo] + 0.10, 0, 0.3)
        C.set_rgb(img, a, C.hsv2rgb(H, S, V))
        gold = C.flat_mat("RA_Gold", "#e6a92e", rough=0.5, emit="#ffb640", emit_strength=0.3)
        y = front_hit(o, 0.0, 6.2)
        print("FRONT HIT", y)
        y = (y if y is not None else -4.0) - 0.05
        extras.append(C.add_obj(sun_emblem(0.85 if lod == 0 else 0.85), "SunEmblem", gold, (0.0, y, 6.2), (math.radians(90), 0, 0)))
        name = "chapel_dawn_throne"
    else:
        o.name = "GuildHallSilverford"
        o.scale = (1.3, 1.3, 1.3)      # a guild HQ, not a cottage
        C.apply_transforms(o)
        hue_rules(img, [
            dict(h0=0.0, h1=1.0, smin=0.0, smax=0.16, vmin=0.30, vmax=0.66, nh=0.60, sadd=0.36, vm=1.15, vadd=0.08),
        ], sat_mul=1.08, val_mul=1.15)
        blue = C.flat_mat("RA_GuildBlue", "#2f62b8", rough=0.8)
        silver = C.flat_mat("RA_Silver", "#dfe4ec", rough=0.5)
        for bx in (-1.75, 1.75):        # banners hung from the balcony rail (front wall probed with front_hit)
            yb = front_hit(o, bx, 3.0) - 0.06
            pole = C.add_obj(C.box_bm(0.86, 0.06, 0.06), "Bracket", silver, (bx, yb, 2.98))
            ban = C.add_obj(banner_bm(0.62, 1.05, 0.26), "Banner", blue, (bx, yb - 0.04, 2.95))
            emb = C.add_obj(diamond_bm(0.13), "BannerRune", silver, (bx, yb - 0.08, 2.3))
            extras += [pole, ban, emb]
        name = "guildhall_silverford"
    C.export(os.path.join(OUT, f"{name}_lod{lod}.glb"))
    print("TRIS", name, lod, C.tri_count(), [i.size[:] for i in C.tex_images(o)])


if __name__ == "__main__":
    for kind in which:
        for lod in (0, 1):
            run(kind, lod)
