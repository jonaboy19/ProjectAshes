# Legacy (Blender 2.7x) materials have no image nodes: rebuild a Principled material
# per mesh from the best-matching loaded image (name-token match, colour maps only).
import bpy, os, re
BAD = re.compile(r"(norm|spec|_ao|-ao|rough|Render Result)", re.I)
def _tokens(s):
    s = s.lower().replace("default", "1")
    return set(t for t in re.split(r"[^a-z0-9]+", s) if t and t not in ("tex", "png", "human", "skin"))
def pick_image(obj):
    imgs = [i for i in bpy.data.images if i.size[0] > 0 and not BAD.search(i.name + os.path.basename(i.filepath))]
    if not imgs:
        return None
    want = _tokens(obj.name)
    def score(i):
        t = _tokens(os.path.basename(i.filepath) or i.name)
        return (len(want & t) - 0.01 * len(t - want), i.size[0])
    return max(imgs, key=score)
def fix(obj):
    has_img = any(n.type == "TEX_IMAGE" for s in obj.material_slots if s.material and s.material.node_tree for n in s.material.node_tree.nodes)
    if has_img:
        return None
    img = pick_image(obj)
    if img is None:
        return None
    m = bpy.data.materials.new("auto_" + obj.name); m.use_nodes = True
    nt = m.node_tree; bsdf = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = img
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.2
    obj.data.materials.clear(); obj.data.materials.append(m)
    return img.name
