"""Shared helpers for the AAA prop refine pipeline (Rising Ashes, Blender 5.2, background mode).

Used by refine_meshy.py (Task A: Meshy re-material) and build_village_props.py (Task B: procedural builds).
Pipeline per asset:
  1. geometry in metres, +Z up (glTF +Y), origin at the feet (object origin = centre of the footprint, z = 0)
  2. per-part material slots from LIB (real-scan CC0 Poly Haven textures, box-projected in object space at real-world
     tile size, bump from the scan's AO + luminance), each with the same weathering stack:
       edge wear (Cycles Bevel-vs-geometry normal), cavity grime (AO), ground mud (bottom 25 cm), low-frequency
       colour variation (object-space noise)
  3. new 'bake_uv' (smart project + pack), Cycles CPU bake to ONE texture set: albedo (sRGB), ORM (R=AO, G=rough,
     B=metal) and an OpenGL tangent normal map
  4. one glTF material (+ optional unbaked extra slots, e.g. water), GLB export with JPEG textures
Godot generates LODs on import (meshes/generate_lods=true is the default), so no LOD GLBs are written.
"""
import bpy, bmesh, math, os, glob
import numpy as np
from mathutils import Vector

REPO = r"C:\Users\Jonna\Documents\PA_wt_w3"
ASSETS = os.path.join(REPO, "kingdom", "assets")
TEX_DIRS = [os.path.join(ASSETS, "cc0", "textures"), os.path.join(ASSETS, "incoming", "polyhaven", "textures")]
HDRI = os.path.join(ASSETS, "incoming", "polyhaven", "hdris", "kloofendal_overcast_puresky_4k.hdr")


# ----------------------------------------------------------------------------------------------- textures
def tex_set(name):
    for d in TEX_DIRS:
        p = os.path.join(d, name)
        if os.path.isdir(p):
            def pick(*keys):
                for k in keys:
                    hits = [f for f in glob.glob(os.path.join(p, f"{name}_{k}_*.jpg"))]
                    if hits:
                        return sorted(hits)[0]
                return None
            return {"diff": pick("diff", "diffuse"), "nor": pick("nor_gl"), "arm": pick("arm")}
    raise FileNotFoundError(name)


def load_img(path, noncolor=False):
    key = os.path.basename(path)
    img = bpy.data.images.get(key) or bpy.data.images.load(path, check_existing=True)
    if noncolor:
        img.colorspace_settings.name = "Non-Color"
    return img


# ----------------------------------------------------------------------------------------------- node helpers
class NB:
    def __init__(self, mat):
        self.nt = mat.node_tree
        self.n = self.nt.nodes
        self.l = self.nt.links

    def new(self, t, **props):
        nd = self.n.new(t)
        for k, v in props.items():
            setattr(nd, k, v)
        return nd

    def link(self, a, b):
        self.l.new(a, b)

    def set(self, sock, v):
        if isinstance(v, bpy.types.NodeSocket):
            self.link(v, sock)
        else:
            sock.default_value = v

    def math(self, op, a, b=0.0, clamp=False):
        m = self.new("ShaderNodeMath", operation=op, use_clamp=clamp)
        self.set(m.inputs[0], a)
        self.set(m.inputs[1], b)
        return m.outputs[0]

    def mix(self, fac, a, b, blend="MIX", clamp=True):
        m = self.new("ShaderNodeMix", data_type="RGBA", blend_type=blend, clamp_result=clamp)
        ins = [s for s in m.inputs if s.type == "RGBA"]
        self.set(m.inputs[0], fac)
        self.set(ins[0], self._col(a))
        self.set(ins[1], self._col(b))
        return [s for s in m.outputs if s.type == "RGBA"][0]

    @staticmethod
    def _col(v):
        if isinstance(v, (int, float)):
            return (v, v, v, 1.0)
        if isinstance(v, tuple) and len(v) == 3:
            return (*v, 1.0)
        return v

    def maprange(self, v, a, b, c=0.0, d=1.0):
        m = self.new("ShaderNodeMapRange", clamp=True)
        self.set(m.inputs["Value"], v)
        m.inputs["From Min"].default_value = a
        m.inputs["From Max"].default_value = b
        m.inputs["To Min"].default_value = c
        m.inputs["To Max"].default_value = d
        return m.outputs["Result"]

    def noise(self, vec, scale, detail=4.0, rough=0.55):
        t = self.new("ShaderNodeTexNoise")
        self.set(t.inputs["Vector"], vec)
        t.inputs["Scale"].default_value = scale
        t.inputs["Detail"].default_value = detail
        t.inputs["Roughness"].default_value = rough
        return t

    def reroute(self, name, src):
        r = self.new("NodeReroute", name=name, label=name)
        if not isinstance(src, bpy.types.NodeSocket):
            if isinstance(src, tuple):
                c = self.new("ShaderNodeRGB")
                c.outputs[0].default_value = self._col(src)
            else:
                c = self.new("ShaderNodeValue")
                c.outputs[0].default_value = src
            src = c.outputs[0]
        self.link(src, r.inputs[0])
        return r


# ----------------------------------------------------------------------------------------------- material library
# kind: "scan" (CC0 texture set), "meshy" (Meshy albedo via the 'meshy_uv' layer), "proc" (procedural base colour)
MESHY_NRM = None          # set by refine_meshy.py: DeepBump normal image of the current Meshy albedo (or None)

LIB = {
    # weathered grey oak (cart, shingles, stall frame)
    "wood_grey":  dict(kind="scan", tex="rough_wood", tile=1.0, sat=0.75, val=0.95, tint=(0.98, 0.95, 0.90), bump=0.5, rough=0.0,
                       edge=(0.66, 0.62, 0.56), wear=0.25, grime=0.55, mud=0.5),
    # warm brown oak (posts, crates, benches)
    "wood_oak":   dict(kind="scan", tex="rough_wood", tile=1.0, sat=1.0, val=0.80, tint=(0.95, 0.74, 0.52), bump=0.5, rough=0.0,
                       edge=(0.72, 0.60, 0.45), wear=0.3, grime=0.6, mud=0.5),
    # dark stained oak (trestle table, sign board)
    "wood_dark":  dict(kind="scan", tex="rough_wood", tile=1.0, sat=1.1, val=0.52, tint=(0.88, 0.66, 0.46), bump=0.45, rough=-0.06,
                       edge=(0.50, 0.40, 0.30), wear=0.3, grime=0.5, mud=0.3),
    "bark":       dict(kind="scan", tex="bark_brown_02", tile=0.7, sat=0.9, val=0.9, tint=(1, 1, 1), bump=1.0, rough=0.0,
                       edge=(0.5, 0.42, 0.33), wear=0.1, grime=0.4, mud=0.4),
    # rough split timber face / end grain is done with the 'aux' UV rings (see endgrain)
    "wood_split": dict(kind="scan", tex="rough_wood", tile=0.8, sat=0.9, val=1.0, tint=(1.0, 0.86, 0.68), bump=0.6, rough=0.0,
                       edge=(0.85, 0.75, 0.6), wear=0.2, grime=0.45, mud=0.4),
    # fieldstone (well ring, hearth), granite (trough)
    "stone":      dict(kind="scan", tex="rock_face", tile=1.2, sat=0.35, val=1.05, tint=(0.95, 0.93, 0.88), bump=1.0, rough=0.0,
                       edge=(0.80, 0.78, 0.74), wear=0.3, grime=0.7, mud=0.6, moss=0.35, detail=0.75),
    "stone_soot": dict(kind="scan", tex="rock_face", tile=1.2, sat=0.2, val=0.35, tint=(0.9, 0.88, 0.86), bump=1.0, rough=0.0,
                       edge=(0.35, 0.33, 0.31), wear=0.1, grime=0.8, mud=0.0),
    "granite":    dict(kind="scan", tex="rock_face", tile=0.6, sat=0.0, val=1.0, tint=(1, 1, 1), bump=0.8, rough=0.02, granite=True, tooled=True,
                       edge=(0.42, 0.42, 0.40), wear=0.4, grime=0.95, mud=0.7, moss=0.85, drip=(0.6, 0.15, 0.7)),
    "plaster":    dict(kind="scan", tex="rough_plaster_03", tile=1.5, sat=0.6, val=0.75, tint=(0.95, 0.90, 0.82), bump=0.6, rough=0.0,
                       edge=(0.85, 0.82, 0.76), wear=0.2, grime=0.8, mud=0.3),
    "plaster_hood": dict(kind="scan", tex="rough_plaster_03", tile=1.2, sat=0.45, val=1.15, tint=(0.97, 0.94, 0.87), bump=0.5, rough=0.0,
                         edge=(0.92, 0.90, 0.85), wear=0.15, grime=0.3, mud=0.0, soot=(1.6, 2.0)),
    "straw":      dict(kind="scan", tex="thatch_roof_angled", tile=0.9, sat=1.25, val=1.3, tint=(1.0, 0.86, 0.52), bump=1.0, rough=0.05,
                       edge=(0.85, 0.78, 0.55), wear=0.15, grime=0.5, mud=0.3),
    # no real-scan iron / fabric / leather is on disk: procedural base, same weathering stack (see README "what still fails")
    "iron":       dict(kind="proc", color=(0.055, 0.05, 0.047), rust=(0.17, 0.085, 0.04), metal=0.85, rough0=0.6, bumpscale=180.0,
                       bump=0.35, edge=(0.24, 0.23, 0.22), wear=0.35, grime=0.4, mud=0.3, edge_dist=0.004),
    "leather":    dict(kind="proc", color=(0.16, 0.09, 0.05), metal=0.0, rough0=0.62, bumpscale=260.0, bump=0.25,
                       edge=(0.30, 0.20, 0.12), wear=0.5, grime=0.4, mud=0.2),
    "burlap":     dict(kind="proc", color=(0.50, 0.40, 0.27), metal=0.0, rough0=0.95, weave=420.0, bump=0.45,
                       edge=(0.58, 0.48, 0.34), wear=0.1, grime=0.5, mud=0.4),
    "rope":       dict(kind="proc", color=(0.28, 0.22, 0.13), metal=0.0, rough0=0.95, weave=300.0, bump=0.4,
                       edge=(0.55, 0.47, 0.33), wear=0.1, grime=0.4, mud=0.2, edge_dist=0.004),
    # keep Meshy's painted albedo but de-AI it: desaturate, add weave/noise breakup and the weathering stack
    "canvas":     dict(kind="meshy", sat=0.60, val=0.95, hue=0.525, tint=(1.0, 0.96, 0.84), rough0=0.9, weave=700.0, bump=0.3, edge=(0.7, 0.62, 0.45), wear=0.1, grime=0.6, mud=0.0),
    "meshy_leather": dict(kind="meshy", sat=0.9, val=0.9, rough0=0.55, bumpscale=900.0, bump=0.15, edge=(0.32, 0.22, 0.14), wear=0.25,
                          grime=0.3, mud=0.0, edge_dist=0.004),
    "meshy":      dict(kind="meshy", sat=0.85, val=0.95, rough0=0.65, bumpscale=120.0, bump=0.2, edge=(0.8, 0.75, 0.65), wear=0.05, grime=0.4, mud=0.0),
    "meshy_burlap": dict(kind="meshy", sat=0.75, val=0.78, rough0=0.95, weave=420.0, bump=0.45, edge=(0.6, 0.5, 0.36), wear=0.1, grime=0.5, mud=0.4),
    # trough water: not baked, its own small material
    "water":      dict(kind="water"),
    # painted sign board: dark oak with the emblem image (aux UV) mixed in
    "sign_board": dict(kind="scan", tex="rough_wood", tile=0.8, sat=1.0, val=0.55, tint=(0.88, 0.68, 0.48), bump=0.5, rough=0.0,
                       edge=(0.55, 0.45, 0.34), wear=0.3, grime=0.5, mud=0.0, paint=True),
    # end grain with rings on the 'aux' UV (u,v = cross-section metres around the pith)
    "endgrain":   dict(kind="scan", tex="rough_wood", tile=0.5, sat=0.8, val=1.15, tint=(1.0, 0.82, 0.60), bump=0.3, rough=0.0,
                       edge=(0.85, 0.75, 0.6), wear=0.1, grime=0.5, mud=0.3, rings=True),
}

COLOR_DEBUG = {"wood_grey": (0.6, 0.6, 0.6), "wood_oak": (0.6, 0.35, 0.1), "wood_dark": (0.25, 0.12, 0.05), "bark": (0.3, 0.2, 0.1),
               "stone": (0.8, 0.8, 0.7), "stone_soot": (0.1, 0.1, 0.1), "granite": (0.5, 0.5, 0.55), "plaster": (0.9, 0.85, 0.7), "plaster_hood": (0.95, 0.9, 0.8),
               "straw": (0.9, 0.8, 0.3), "iron": (0.05, 0.05, 0.3), "leather": (0.4, 0.15, 0.05), "burlap": (0.8, 0.7, 0.4),
               "rope": (0.7, 0.6, 0.3), "canvas": (1.0, 0.6, 0.0), "meshy_leather": (0.3, 0.15, 0.1), "meshy": (1.0, 0.0, 1.0), "meshy_burlap": (0.9, 0.9, 0.2),
               "water": (0.0, 0.4, 0.6), "sign_board": (0.4, 0.2, 0.1), "endgrain": (0.9, 0.7, 0.4), "wood_split": (0.8, 0.6, 0.4)}


def gltf_group():
    g = bpy.data.node_groups.get("glTF Material Output")
    if g is None:
        g = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        g.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    return g


def make_material(cls, meshy_img=None, paint_img=None):
    """A bakeable material: reroutes OUT_albedo / OUT_rough / OUT_metal / OUT_ao feed the bake, the Principled BSDF feeds the
    normal bake and the preview render."""
    spec = LIB[cls]
    m = bpy.data.materials.new("M_" + cls)
    m.use_nodes = True
    nb = NB(m)
    p = nb.n["Principled BSDF"]
    outn = nb.n["Material Output"]
    if spec["kind"] == "water":
        p.inputs["Base Color"].default_value = (0.035, 0.045, 0.035, 1)
        p.inputs["Roughness"].default_value = 0.04
        p.inputs["Specular IOR Level"].default_value = 0.5
        m["unbaked"] = True
        return m

    tc = nb.new("ShaderNodeTexCoord")
    obj = tc.outputs["Object"]
    geo = nb.new("ShaderNodeNewGeometry")
    height = None
    metal = 0.0
    if spec["kind"] == "scan":
        ts = tex_set(spec["tex"])
        mp = nb.new("ShaderNodeMapping")
        proj = "BOX"
        if spec.get("roof"):
            # roof courses follow the slope: u along the eave (face azimuth snapped to 45 deg so a whole roof plane shares
            # one direction), v = height * sqrt(2) (courses are horizontal lines; ~45 deg pitch)
            tn = nb.new("ShaderNodeSeparateXYZ")
            nb.link(geo.outputs["True Normal"], tn.inputs[0])
            ang = nb.math("ARCTAN2", tn.outputs["Y"], tn.outputs["X"])
            q = nb.math("MULTIPLY", nb.math("ROUND", nb.math("DIVIDE", ang, math.pi / 4)), math.pi / 4)
            px = nb.new("ShaderNodeSeparateXYZ")
            nb.link(obj, px.inputs[0])
            u = nb.math("ADD", nb.math("MULTIPLY", px.outputs["X"], nb.math("MULTIPLY", nb.math("SINE", q), -1.0)),
                        nb.math("MULTIPLY", px.outputs["Y"], nb.math("COSINE", q)))
            v = nb.math("MULTIPLY", px.outputs["Z"], 1.414)
            cv = nb.new("ShaderNodeCombineXYZ")
            nb.link(u, cv.inputs["X"])
            nb.link(v, cv.inputs["Y"])
            nb.link(cv.outputs[0], mp.inputs["Vector"])
            proj = "FLAT"
        else:
            nb.link(obj, mp.inputs["Vector"])
        s = 1.0 / spec["tile"]
        mp.inputs["Scale"].default_value = (s, s, s)
        # a fixed per-material offset so neighbouring parts don't share the same texture patch
        mp.inputs["Location"].default_value = (sum(map(ord, cls)) % 97 / 97.0, sum(map(ord, cls)) % 53 / 53.0, 0.0)

        def img(path, nc):
            t = nb.new("ShaderNodeTexImage", projection=proj, projection_blend=0.25)
            t.image = load_img(path, nc)
            nb.link(mp.outputs[0], t.inputs["Vector"])
            return t
        dt = img(ts["diff"], False)
        at = img(ts["arm"], True)
        hs = nb.new("ShaderNodeHueSaturation")
        hs.inputs["Saturation"].default_value = spec["sat"]
        hs.inputs["Value"].default_value = spec["val"]
        nb.link(dt.outputs["Color"], hs.inputs["Color"])
        alb = nb.mix(1.0, hs.outputs["Color"], spec["tint"], blend="MULTIPLY")
        if meshy_img is not None and spec.get("detail", 0.5) > 0:
            # detail transfer: Meshy's painted plank lines / stone joints (grey, overlay) keep the shapes it modelled readable
            uvd = nb.new("ShaderNodeUVMap", uv_map="meshy_uv")
            mt = nb.new("ShaderNodeTexImage")
            mt.image = meshy_img
            nb.link(uvd.outputs["UV"], mt.inputs["Vector"])
            mg = nb.new("ShaderNodeHueSaturation")
            mg.inputs["Saturation"].default_value = 0.0
            mg.inputs["Value"].default_value = spec.get("detail_val", 1.25)
            nb.link(mt.outputs["Color"], mg.inputs["Color"])
            alb = nb.mix(spec.get("detail", 0.5), alb, mg.outputs["Color"], blend="OVERLAY")
        sep = nb.new("ShaderNodeSeparateColor")
        nb.link(at.outputs["Color"], sep.inputs["Color"])
        rough = nb.math("ADD", sep.outputs["Green"], spec.get("rough", 0.0), clamp=True)
        bw = nb.new("ShaderNodeRGBToBW")
        nb.link(dt.outputs["Color"], bw.inputs["Color"])
        height = nb.math("ADD", nb.math("MULTIPLY", sep.outputs["Red"], 0.6), nb.math("MULTIPLY", bw.outputs[0], 0.4))
        if spec.get("frame") and meshy_img is not None:
            # half-timbering per PIXEL: Meshy painted the frame onto flat walls, so its albedo luminance decides
            # limewash (light) vs dark weathered timber (dark); decimated faces are far too coarse for this
            fr = spec["frame"]
            ts2 = tex_set(fr["tex"])
            mp2_ = nb.new("ShaderNodeMapping")
            nb.link(obj, mp2_.inputs["Vector"])
            s2 = 1.0 / fr["tile"]
            mp2_.inputs["Scale"].default_value = (s2, s2, s2)
            def img2(path, nc):
                t = nb.new("ShaderNodeTexImage", projection="BOX", projection_blend=0.25)
                t.image = load_img(path, nc)
                nb.link(mp2_.outputs[0], t.inputs["Vector"])
                return t
            dt2 = img2(ts2["diff"], False)
            at2 = img2(ts2["arm"], True)
            hs2 = nb.new("ShaderNodeHueSaturation")
            hs2.inputs["Saturation"].default_value = fr["sat"]
            hs2.inputs["Value"].default_value = fr["val"]
            nb.link(dt2.outputs["Color"], hs2.inputs["Color"])
            alb2 = nb.mix(1.0, hs2.outputs["Color"], fr["tint"], blend="MULTIPLY")
            sep2 = nb.new("ShaderNodeSeparateColor")
            nb.link(at2.outputs["Color"], sep2.inputs["Color"])
            uvf = nb.new("ShaderNodeUVMap", uv_map="meshy_uv")
            mtf = nb.new("ShaderNodeTexImage")
            mtf.image = meshy_img
            nb.link(uvf.outputs["UV"], mtf.inputs["Vector"])
            lum = nb.new("ShaderNodeRGBToBW")
            nb.link(mtf.outputs["Color"], lum.inputs["Color"])
            wood = nb.maprange(lum.outputs[0], fr["hi"], fr["lo"])          # 1 = timber (dark in Meshy's paint)
            alb = nb.mix(wood, alb, alb2)
            rough = nb.mix(wood, rough, sep2.outputs["Green"])
            # timber stands proud of the infill by a couple of cm
            height = nb.math("ADD", nb.math("MULTIPLY", height, 0.5), nb.math("MULTIPLY", wood, 0.8))
            spec = dict(spec, detail=0.0)
        if spec.get("speckle"):
            # granite: black mica / white feldspar speckle over the scan
            v = nb.new("ShaderNodeTexVoronoi")
            nb.link(obj, v.inputs["Vector"])
            v.inputs["Scale"].default_value = 160.0
            dark = nb.maprange(v.outputs["Distance"], 0.0, 0.12, 1.0, 0.0)
            alb = nb.mix(nb.math("MULTIPLY", dark, 0.55), alb, (0.04, 0.04, 0.045))
            n2 = nb.noise(obj, 220.0, 2.0)
            light = nb.maprange(n2.outputs["Fac"], 0.62, 0.70)
            alb = nb.mix(nb.math("MULTIPLY", light, 0.35), alb, (0.85, 0.83, 0.80))
        if spec.get("granite"):
            # grey granite: light feldspar base, scan luminance only as large-scale breakup (the scan itself is brown rock)
            gn = nb.noise(obj, 3.0, 4.0)
            base = nb.mix(gn.outputs["Fac"], (0.15, 0.15, 0.145), (0.24, 0.235, 0.225))
            alb = nb.mix(0.45, base, hs.outputs["Color"], blend="OVERLAY")
            v = nb.new("ShaderNodeTexVoronoi")
            nb.link(obj, v.inputs["Vector"])
            v.inputs["Scale"].default_value = 260.0
            dark = nb.maprange(v.outputs["Distance"], 0.0, 0.16, 1.0, 0.0)
            alb = nb.mix(nb.math("MULTIPLY", dark, 0.75), alb, (0.05, 0.05, 0.055))
            n2 = nb.noise(obj, 300.0, 1.0)
            light = nb.maprange(n2.outputs["Fac"], 0.6, 0.66)
            alb = nb.mix(nb.math("MULTIPLY", light, 0.5), alb, (0.55, 0.54, 0.52))
            height = nb.math("ADD", nb.math("MULTIPLY", height, 0.4), nb.math("MULTIPLY", dark, 0.15))
        if spec.get("tooled"):
            # hand-dressed stone: parallel point-chisel strokes (~12 mm pitch, slightly wavy, rotated per face axis) + pitting
            mp2 = nb.new("ShaderNodeMapping")
            nb.link(obj, mp2.inputs["Vector"])
            mp2.inputs["Rotation"].default_value = (0.6, 0.4, 0.8)
            wv = nb.new("ShaderNodeTexWave", wave_type="BANDS", bands_direction="DIAGONAL", wave_profile="SAW")
            nb.link(mp2.outputs[0], wv.inputs["Vector"])
            wv.inputs["Scale"].default_value = 55.0
            wv.inputs["Distortion"].default_value = 4.0
            wv.inputs["Detail"].default_value = 3.0
            pit = nb.noise(obj, 90.0, 2.0)
            pits = nb.maprange(pit.outputs["Fac"], 0.55, 0.7)
            tool = nb.math("SUBTRACT", nb.math("MULTIPLY", wv.outputs["Fac"], 0.5), nb.math("MULTIPLY", pits, 0.6))
            height = nb.math("ADD", height, tool)
        if spec.get("soot"):
            # soot: dense at the hood mouth, fading up, streaked
            sxyz = nb.new("ShaderNodeSeparateXYZ")
            nb.link(obj, sxyz.inputs[0])
            z0, z1 = spec["soot"]
            band = nb.maprange(sxyz.outputs["Z"], z0, z1, 1.0, 0.0)
            st = nb.new("ShaderNodeMapping")
            nb.link(obj, st.inputs["Vector"])
            st.inputs["Scale"].default_value = (14.0, 14.0, 1.5)
            sn = nb.new("ShaderNodeTexNoise")
            nb.link(st.outputs[0], sn.inputs["Vector"])
            sn.inputs["Detail"].default_value = 6.0
            streak = nb.maprange(sn.outputs["Fac"], 0.35, 0.65, 0.55, 1.0)
            soot = nb.math("MULTIPLY", nb.math("POWER", band, 0.7), streak, clamp=True)
            alb = nb.mix(soot, alb, (0.035, 0.03, 0.028))
            rough = nb.mix(soot, rough, 0.95)
        if spec.get("drip"):
            # rain/water staining: dark vertical streaks running down from the rim (z_top -> z_bottom), strength s
            zt_, zb_, st_ = spec["drip"]
            dx = nb.new("ShaderNodeSeparateXYZ")
            nb.link(obj, dx.inputs[0])
            fall = nb.maprange(dx.outputs["Z"], zt_, zb_, 1.0, 0.0)
            dm = nb.new("ShaderNodeMapping")
            nb.link(obj, dm.inputs["Vector"])
            dm.inputs["Scale"].default_value = (22.0, 22.0, 0.8)
            dn = nb.new("ShaderNodeTexNoise")
            nb.link(dm.outputs[0], dn.inputs["Vector"])
            dn.inputs["Detail"].default_value = 5.0
            dstreak = nb.maprange(dn.outputs["Fac"], 0.45, 0.7)
            dmask = nb.math("MULTIPLY", nb.math("MULTIPLY", fall, dstreak), st_, clamp=True)
            alb = nb.mix(dmask, alb, (0.05, 0.055, 0.04))
        if spec.get("rings") :
            # end grain: concentric growth rings around the pith on the 'aux' UV + radial checks
            uvn = nb.new("ShaderNodeUVMap", uv_map="aux")
            vl = nb.new("ShaderNodeVectorMath", operation="LENGTH")
            nb.link(uvn.outputs["UV"], vl.inputs[0])
            nz = nb.noise(obj, 30.0, 2.0)
            r = nb.math("ADD", vl.outputs["Value"], nb.math("MULTIPLY", nz.outputs["Fac"], 0.006))
            ring = nb.math("SINE", nb.math("MULTIPLY", r, 2 * math.pi * 160.0))
            ringm = nb.maprange(ring, 0.3, 1.0)
            alb = nb.mix(nb.math("MULTIPLY", ringm, 0.45), alb, (0.32, 0.20, 0.11), blend="MULTIPLY")
            heart = nb.maprange(vl.outputs["Value"], 0.0, 0.05, 1.0, 0.0)
            alb = nb.mix(nb.math("MULTIPLY", heart, 0.35), alb, (0.45, 0.28, 0.14))
            height = nb.math("ADD", height, nb.math("MULTIPLY", ringm, 0.3))
        if spec.get("paint") and paint_img is not None:
            # painted emblem on the 'aux' UV: alpha = paint coverage, chipped by noise where the wood shows through
            uvn = nb.new("ShaderNodeUVMap", uv_map="aux")
            pt = nb.new("ShaderNodeTexImage", extension="CLIP")
            pt.image = paint_img
            nb.link(uvn.outputs["UV"], pt.inputs["Vector"])
            chip = nb.noise(obj, 40.0, 6.0, 0.7)
            keep = nb.maprange(chip.outputs["Fac"], 0.33, 0.40)
            grain = nb.maprange(sep.outputs["Red"], 0.12, 0.4)          # paint sits on the raised grain, missing in the cracks
            cov = nb.math("MULTIPLY", nb.math("MULTIPLY", pt.outputs["Alpha"], keep), grain)
            faded = nb.mix(0.12, pt.outputs["Color"], (0.55, 0.50, 0.42))
            alb = nb.mix(cov, alb, faded)
            rough = nb.mix(cov, rough, 0.55)
            m["has_paint"] = True
    else:
        # proc / meshy: base colour + micro detail
        if spec["kind"] == "meshy":
            uvn = nb.new("ShaderNodeUVMap", uv_map="meshy_uv")
            t = nb.new("ShaderNodeTexImage")
            t.image = meshy_img
            nb.link(uvn.outputs["UV"], t.inputs["Vector"])
            hs = nb.new("ShaderNodeHueSaturation")
            hs.inputs["Saturation"].default_value = spec["sat"]
            hs.inputs["Value"].default_value = spec["val"]
            hs.inputs["Hue"].default_value = spec.get("hue", 0.5)
            nb.link(t.outputs["Color"], hs.inputs["Color"])
            alb = hs.outputs["Color"]
            if spec.get("tint"):
                alb = nb.mix(1.0, alb, spec["tint"], blend="MULTIPLY")
        else:
            alb = spec["color"]
        rough = spec["rough0"]
        metal = spec.get("metal", 0.0)
        if spec.get("weave"):
            # plain weave: two crossing sine waves (warp and weft) + slub noise
            w = spec["weave"]
            def wave(axis_mix):
                mp = nb.new("ShaderNodeMapping")
                nb.link(obj, mp.inputs["Vector"])
                mp.inputs["Rotation"].default_value = axis_mix
                wv = nb.new("ShaderNodeTexWave", wave_type="BANDS", bands_direction="X")
                nb.link(mp.outputs[0], wv.inputs["Vector"])
                wv.inputs["Scale"].default_value = w / 10.0
                wv.inputs["Distortion"].default_value = 1.5
                return wv.outputs["Fac"]
            a = wave((0.0, 0.0, 0.0))
            b = wave((0.0, 0.0, math.pi / 2))
            c = wave((0.0, math.pi / 2, 0.0))
            weave = nb.math("MAXIMUM", nb.math("MAXIMUM", a, b), c)
            slub = nb.noise(obj, w / 25.0, 3.0)
            height = nb.math("ADD", nb.math("MULTIPLY", weave, 0.6), nb.math("MULTIPLY", slub.outputs["Fac"], 0.4))
            alb = nb.mix(nb.math("MULTIPLY", weave, 0.4), alb, (0.6, 0.6, 0.6), blend="MULTIPLY")
            alb = nb.mix(nb.math("MULTIPLY", slub.outputs["Fac"], 0.3), alb, (0.75, 0.70, 0.62), blend="MULTIPLY")
        else:
            nz = nb.noise(obj, spec.get("bumpscale", 100.0), 6.0, 0.65)
            vz = nb.new("ShaderNodeTexVoronoi")
            nb.link(obj, vz.inputs["Vector"])
            vz.inputs["Scale"].default_value = spec.get("bumpscale", 100.0) * 0.5
            height = nb.math("ADD", nb.math("MULTIPLY", nz.outputs["Fac"], 0.6), nb.math("MULTIPLY", vz.outputs["Distance"], 0.4))
            alb = nb.mix(nb.math("MULTIPLY", nz.outputs["Fac"], 0.5), alb, (0.6, 0.6, 0.6), blend="MULTIPLY")
            if cls == "iron":
                # rust blooms in noise patches and runs down from the top
                rn = nb.noise(obj, 9.0, 8.0, 0.7)
                rust = nb.maprange(rn.outputs["Fac"], 0.52, 0.66)
                alb = nb.mix(rust, alb, spec["rust"])
                rough = nb.maprange(rust, 0.0, 1.0, spec["rough0"], 0.9)
                metal = nb.maprange(rust, 0.0, 1.0, spec["metal"], 0.2)

    # ---------------- weathering stack
    # convex edges = low "inside" AO over a short distance (robust on triangulated / smooth-shaded scans)
    aoi = nb.new("ShaderNodeAmbientOcclusion", samples=12, inside=True, only_local=True)
    aoi.inputs["Distance"].default_value = spec.get("edge_dist", 0.02)
    edge_n = nb.noise(obj, 14.0, 5.0, 0.7)
    edge = nb.maprange(nb.math("SUBTRACT", 1.0, aoi.outputs["AO"]), 0.25, 0.6)
    edge = nb.math("MULTIPLY", edge, nb.maprange(edge_n.outputs["Fac"], 0.35, 0.6), clamp=True)
    ao = nb.new("ShaderNodeAmbientOcclusion", samples=16, only_local=True)
    ao.inputs["Distance"].default_value = spec.get("edge_dist", 0.02) * 12
    cav = nb.math("SUBTRACT", 1.0, ao.outputs["AO"], clamp=True)
    sep_xyz = nb.new("ShaderNodeSeparateXYZ")
    nb.link(obj, sep_xyz.inputs[0])
    low = nb.maprange(sep_xyz.outputs["Z"], 0.0, spec.get("mud_h", 0.28), 1.0, 0.0)
    low_n = nb.noise(obj, 6.0, 4.0)
    low = nb.math("MULTIPLY", low, nb.maprange(low_n.outputs["Fac"], 0.3, 0.6, 0.4, 1.0), clamp=True)
    var = nb.noise(obj, 1.3, 2.0)
    vcol = nb.new("ShaderNodeValToRGB")
    nb.link(var.outputs["Fac"], vcol.inputs["Fac"])
    vcol.color_ramp.elements[0].position = 0.35
    vcol.color_ramp.elements[0].color = (0.88, 0.86, 0.84, 1)
    vcol.color_ramp.elements[1].position = 0.65
    vcol.color_ramp.elements[1].color = (1.06, 1.04, 1.0, 1)
    alb = nb.mix(1.0, alb, vcol.outputs["Color"], blend="MULTIPLY", clamp=True)
    alb = nb.mix(nb.math("MULTIPLY", edge, spec["wear"]), alb, spec["edge"])
    grime_n = nb.noise(obj, 4.0, 6.0, 0.6)
    gm = nb.math("MULTIPLY", nb.maprange(cav, 0.05, 0.6), nb.maprange(grime_n.outputs["Fac"], 0.3, 0.65, 0.5, 1.0), clamp=True)
    alb = nb.mix(nb.math("MULTIPLY", gm, spec["grime"]), alb, (0.07, 0.055, 0.04))
    alb = nb.mix(nb.math("MULTIPLY", low, spec["mud"] * 0.6), alb, (0.17, 0.13, 0.09))
    if spec.get("moss"):
        # moss: up-facing and in cavities/low, broken by noise
        upz = nb.new("ShaderNodeSeparateXYZ")
        nb.link(geo.outputs["Normal"], upz.inputs[0])
        mn = nb.noise(obj, 3.5, 8.0, 0.65)
        mmask = nb.math("MULTIPLY", nb.maprange(mn.outputs["Fac"], 0.5, 0.62),
                        nb.math("ADD", nb.maprange(upz.outputs["Z"], 0.3, 0.9), nb.math("MULTIPLY", nb.math("ADD", gm, low), 0.8)), clamp=True)
        mcol_n = nb.noise(obj, 25.0, 4.0)
        mcol = nb.mix(mcol_n.outputs["Fac"], (0.10, 0.13, 0.035), (0.20, 0.23, 0.07))
        alb = nb.mix(nb.math("MULTIPLY", mmask, spec["moss"]), alb, mcol)
        rough = nb.mix(mmask, rough, 0.95)
        height = nb.math("ADD", height, nb.math("MULTIPLY", mmask, 0.3))
    rough = nb.math("ADD", rough, nb.math("MULTIPLY", gm, 0.1), clamp=True)
    if cls == "iron":
        rough = nb.math("SUBTRACT", rough, nb.math("MULTIPLY", edge, 0.35), clamp=True)

    bump = nb.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = spec.get("bump", 0.5)
    bump.inputs["Distance"].default_value = 0.01
    if height is not None:
        nb.set(bump.inputs["Height"], height)
    if spec["kind"] == "meshy" and MESHY_NRM is not None:
        # DeepBump normal from Meshy's painted albedo (stitching, folds, fruit shapes) on the Meshy UV, under the micro bump
        uvn2 = nb.new("ShaderNodeUVMap", uv_map="meshy_uv")
        nt_ = nb.new("ShaderNodeTexImage")
        nt_.image = MESHY_NRM
        nb.link(uvn2.outputs["UV"], nt_.inputs["Vector"])
        nm = nb.new("ShaderNodeNormalMap", uv_map="meshy_uv")
        nm.inputs["Strength"].default_value = 0.8
        nb.link(nt_.outputs["Color"], nm.inputs["Color"])
        nb.link(nm.outputs["Normal"], bump.inputs["Normal"])
    nb.reroute("OUT_albedo", alb)
    nb.reroute("OUT_rough", rough)
    nb.reroute("OUT_metal", metal)
    nb.reroute("OUT_ao", ao.outputs["AO"])
    nb.set(p.inputs["Base Color"], alb)
    nb.set(p.inputs["Roughness"], rough)
    nb.set(p.inputs["Metallic"], metal)
    nb.link(bump.outputs["Normal"], p.inputs["Normal"])
    em = nb.new("ShaderNodeEmission", name="BAKE_EMIT")
    em.inputs["Strength"].default_value = 1.0
    return m


# ----------------------------------------------------------------------------------------------- mesh utils
def apply_all(ob):
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.scene.objects:
        o.select_set(o == ob)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def origin_to_feet(ob):
    """Move the mesh so the footprint centre is at (0,0) and the lowest point at z = 0."""
    vs = [v.co for v in ob.data.vertices]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    off = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    for v in ob.data.vertices:
        v.co -= off
    ob.location = (0, 0, 0)


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def smart_uv(ob, name="bake_uv", angle=66.0, margin=0.004):
    me = ob.data
    uv = me.uv_layers.get(name) or me.uv_layers.new(name=name)
    me.uv_layers.active = uv
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.scene.objects:
        o.select_set(o == ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(rotate=True, margin=margin)
    bpy.ops.object.mode_set(mode="OBJECT")
    return uv


def join(obs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


# ----------------------------------------------------------------------------------------------- bake + export
def _setup_cycles(samples):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"        # the GPU is shared with Godot workers (8 GB nearly full): CPU bakes are safe
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    sc.render.bake.margin = 8
    sc.render.bake.use_clear = True


def bake_asset(ob, size, tmpdir, tag, samples=24, high=None, extrusion=0.04, ray=0.12):
    """Bake every bakeable material slot of ob into one albedo / ORM / normal set on the 'bake_uv' layer.
    Returns the final glTF material (images packed, saved as files in tmpdir)."""
    _setup_cycles(samples)
    os.makedirs(tmpdir, exist_ok=True)
    me = ob.data
    me.uv_layers.active = me.uv_layers["bake_uv"]
    for i, uv in enumerate(me.uv_layers):
        uv.active_render = uv.name == "bake_uv"
    bpy.context.view_layer.objects.active = ob
    for o in bpy.context.scene.objects:
        o.select_set(o == ob)

    def new_img(n, noncolor, alpha=False):
        im = bpy.data.images.new(f"{tag}_{n}", size, size, alpha=alpha, float_buffer=False)
        if noncolor:
            im.colorspace_settings.name = "Non-Color"
        return im
    imgs = {k: new_img(k, k != "albedo") for k in ("albedo", "rough", "metal", "ao", "normal")}
    mats = [s.material for s in ob.material_slots if s.material and not s.material.get("unbaked")]

    def target(img):
        for m in mats:
            nt = m.node_tree
            t = nt.nodes.get("BAKE_TARGET") or nt.nodes.new("ShaderNodeTexImage")
            t.name = "BAKE_TARGET"
            t.image = img
            for nd in nt.nodes:
                nd.select = False
            t.select = True
            nt.nodes.active = t

    def surface(kind):
        for m in mats:
            nt = m.node_tree
            out = nt.nodes["Material Output"]
            for l in list(out.inputs["Surface"].links):
                nt.links.remove(l)
            if kind is None:
                nt.links.new(nt.nodes["Principled BSDF"].outputs[0], out.inputs["Surface"])
            else:
                em = nt.nodes["BAKE_EMIT"]
                for l in list(em.inputs["Color"].links):
                    nt.links.remove(l)
                nt.links.new(nt.nodes[kind].outputs[0], em.inputs["Color"])
                nt.links.new(em.outputs[0], out.inputs["Surface"])
    # unbaked slots (water) would occlude nothing useful: give them a black emission so they don't break the bake
    for k, node in (("albedo", "OUT_albedo"), ("rough", "OUT_rough"), ("metal", "OUT_metal"), ("ao", "OUT_ao")):
        target(imgs[k])
        surface(node)
        bpy.ops.object.bake(type="EMIT", margin=8, use_clear=True)
        print("BAKED", tag, k, flush=True)
    surface(None)
    target(imgs["normal"])
    bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", normal_r="POS_X", normal_g="POS_Y", normal_b="POS_Z", margin=8)
    print("BAKED", tag, "normal", flush=True)
    if high is not None:
        # geometry detail the decimation removed: bake the original high-poly onto the low (selected -> active) and
        # whiteout-blend it with the material normal (n = normalize(a.xy + b.xy, a.z * b.z))
        geo_img = new_img("geonormal", True)
        target(geo_img)
        high.hide_render = False
        high.select_set(True)
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", normal_r="POS_X", normal_g="POS_Y", normal_b="POS_Z", margin=8,
                            use_selected_to_active=True, cage_extrusion=extrusion, max_ray_distance=ray)
        high.select_set(False)
        def pxn(im):
            a_ = np.empty(size * size * 4, dtype=np.float32)
            im.pixels.foreach_get(a_)
            return a_.reshape(size, size, 4)
        na = pxn(imgs["normal"])
        nbm = pxn(geo_img)
        A = na[..., :3] * 2 - 1
        B = nbm[..., :3] * 2 - 1
        Nn = np.stack([A[..., 0] + B[..., 0], A[..., 1] + B[..., 1], A[..., 2] * B[..., 2]], -1)
        Nn /= np.maximum(np.linalg.norm(Nn, axis=-1, keepdims=True), 1e-6)
        na[..., :3] = Nn * 0.5 + 0.5
        imgs["normal"].pixels.foreach_set(na.ravel())
        bpy.data.images.remove(geo_img)
        print("BAKED", tag, "high->low normal", flush=True)

    # ORM pack (R = AO, G = roughness, B = metallic)
    def px(im):
        a = np.empty(size * size * 4, dtype=np.float32)
        im.pixels.foreach_get(a)
        return a.reshape(size, size, 4)
    orm = np.ones((size, size, 4), dtype=np.float32)
    ao = px(imgs["ao"])[..., 0]
    orm[..., 0] = 0.35 + 0.65 * ao       # soften: Godot's SSAO adds on top on high tiers
    orm[..., 1] = px(imgs["rough"])[..., 0]
    orm[..., 2] = px(imgs["metal"])[..., 0]
    orm_img = new_img("orm", True)
    orm_img.pixels.foreach_set(orm.ravel())
    # bake a little AO into the albedo too (low tier runs without SSAO)
    alb = px(imgs["albedo"])
    alb[..., :3] *= (0.55 + 0.45 * ao)[..., None] ** 0.6
    imgs["albedo"].pixels.foreach_set(alb.ravel())
    out = {}
    for k, im in (("albedo", imgs["albedo"]), ("orm", orm_img), ("normal", imgs["normal"])):
        path = os.path.join(tmpdir, f"{tag}_{k}.png")
        im.filepath_raw = path
        im.file_format = "PNG"
        im.save()
        out[k] = im
    for k in ("rough", "metal", "ao"):
        bpy.data.images.remove(imgs[k])

    # final glTF material
    fm = bpy.data.materials.new(tag)
    fm.use_nodes = True
    nt = fm.node_tree
    p = nt.nodes["Principled BSDF"]
    uvn = nt.nodes.new("ShaderNodeUVMap")
    uvn.uv_map = "bake_uv"
    ta = nt.nodes.new("ShaderNodeTexImage"); ta.image = out["albedo"]
    to = nt.nodes.new("ShaderNodeTexImage"); to.image = out["orm"]
    tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = out["normal"]
    for t in (ta, to, tn):
        nt.links.new(uvn.outputs["UV"], t.inputs["Vector"])
    nt.links.new(ta.outputs["Color"], p.inputs["Base Color"])
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(to.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], p.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], p.inputs["Metallic"])
    g = nt.nodes.new("ShaderNodeGroup"); g.node_tree = gltf_group()
    nt.links.new(sep.outputs["Red"], g.inputs["Occlusion"])
    nm = nt.nodes.new("ShaderNodeNormalMap"); nm.uv_map = "bake_uv"
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], p.inputs["Normal"])
    return fm


def finalize_materials(ob, final_mat):
    """Collapse all baked slots into final_mat; keep unbaked slots (water) as their own material."""
    me = ob.data
    keep = [s.material for s in ob.material_slots if s.material and s.material.get("unbaked")]
    remap = {}
    new_list = [final_mat] + keep
    for i, s in enumerate(ob.material_slots):
        remap[i] = new_list.index(s.material) if s.material in keep else 0
    idx = [remap[p.material_index] for p in me.polygons]
    me.materials.clear()
    for m in new_list:
        me.materials.append(m)
    for p, i in zip(me.polygons, idx):
        p.material_index = i


def export_glb(ob, path):
    me = ob.data
    for uv in list(me.uv_layers):
        if uv.name != "bake_uv":
            me.uv_layers.remove(uv)
    for o in bpy.context.scene.objects:
        o.select_set(o == ob)
    bpy.context.view_layer.objects.active = ob
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
                              export_image_format="JPEG", export_jpeg_quality=88, export_tangents=False,
                              export_materials="EXPORT")
    print("EXPORTED", path, tri_count(ob), flush=True)


def write_license(folder, name, source):
    with open(os.path.join(folder, "LICENSE.txt"), "w", encoding="utf-8") as f:
        f.write(f"Asset: {name} (Rising Ashes, refined 2026-10-28)\n")
        f.write(source + "\n")
        f.write("Materials: CC0 1.0 Poly Haven texture scans (polyhaven.com; rough_wood, bark_brown_02, rock_face, rough_plaster_03, "
                "thatch_roof_angled) baked with procedural wear/grime in Blender; no attribution required.\n")
        f.write("Pipeline: tools/blender/props/refine_lib.py\n")


# ----------------------------------------------------------------------------------------------- gate render
def setup_world(strength=1.0):
    sc = bpy.context.scene
    w = bpy.data.worlds.get("GateWorld") or bpy.data.worlds.new("GateWorld")
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(HDRI, check_existing=True)
    mp = nt.nodes.new("ShaderNodeMapping")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp.inputs["Rotation"].default_value = (0, 0, math.radians(40))
    nt.links.new(tc.outputs["Generated"], mp.inputs["Vector"])
    nt.links.new(mp.outputs[0], env.inputs["Vector"])
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = strength
    out = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(env.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs[0], out.inputs["Surface"])
    sc.world = w
    # a soft overcast key so forms read (the overcast HDRI alone is very flat)
    if "GateSun" not in bpy.data.objects:
        sd = bpy.data.lights.new("GateSun", "SUN")
        sd.energy = 1.6
        sd.angle = math.radians(12)
        sd.color = (1.0, 0.96, 0.9)
        so = bpy.data.objects.new("GateSun", sd)
        so.rotation_euler = (math.radians(50), 0, math.radians(-35))
        sc.collection.objects.link(so)
    if "GateGround" not in bpy.data.objects:
        bpy.ops.mesh.primitive_plane_add(size=60)
        g = bpy.context.active_object
        g.name = "GateGround"
        gm = bpy.data.materials.new("GateGround")
        gm.use_nodes = True
        pp = gm.node_tree.nodes["Principled BSDF"]
        pp.inputs["Base Color"].default_value = (0.16, 0.15, 0.135, 1)
        pp.inputs["Roughness"].default_value = 0.95
        g.data.materials.append(gm)


def bbox_of(obs):
    pts = [o.matrix_world @ Vector(c) for o in obs for c in o.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return mn, mx


def render_view(obs, path, res=(640, 480), yaw=35.0, pitch=22.0, engine="BLENDER_EEVEE", hide=()):
    """Gameplay-like 3/4 view (camera ~22 deg down, like a third-person camera at standing height), framed on obs."""
    sc = bpy.context.scene
    setup_world()
    for o in sc.objects:
        if o.type == "MESH" and o.name != "GateGround":
            o.hide_render = o not in obs
    mn, mx = bbox_of(obs)
    bpy.data.objects["GateGround"].location.z = mn.z      # wall-mounted props (sign) hang below their origin
    c = (mn + mx) / 2
    rad = max((mx - mn).length / 2, 0.15)
    cam = bpy.data.objects.get("GateCam")
    if cam is None:
        cd = bpy.data.cameras.new("GateCam")
        cam = bpy.data.objects.new("GateCam", cd)
        sc.collection.objects.link(cam)
    cam.data.lens = 50
    cam.data.clip_start = 0.01
    fov = 2 * math.atan(36 / 2 / 50) * min(1.0, res[1] / res[0])
    dist = rad / math.sin(fov / 2) * 0.78
    yr, pr = math.radians(yaw), math.radians(pitch)
    d = Vector((math.sin(yr) * math.cos(pr), -math.cos(yr) * math.cos(pr), math.sin(pr)))
    cam.location = c + d * dist
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sc.render.engine = engine
    if engine == "CYCLES":
        sc.cycles.samples = 48
        sc.cycles.use_denoising = True
    else:
        try:
            sc.eevee.taa_render_samples = 32
            sc.eevee.use_shadows = True
        except Exception:
            pass
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.exposure = 0.0
    try:
        sc.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "JPEG"
    sc.render.image_settings.quality = 88
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("RENDERED", path, flush=True)
