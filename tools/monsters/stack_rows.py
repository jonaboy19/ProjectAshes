# Stack PNG rows vertically (same width) into one sheet: blender -b --python stack_rows.py -- out.png a.png b.png ...
import bpy, sys, numpy as np
args = sys.argv[sys.argv.index("--") + 1:]
out, rows = args[0], args[1:]
arrs = []
for p in rows:
    im = bpy.data.images.load(p); w, h = im.size
    a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4); arrs.append(a)
W = max(a.shape[1] for a in arrs)
arrs = [np.pad(a, ((0, 0), (0, W - a.shape[1]), (0, 0)), constant_values=1.0) for a in arrs]
sheet = np.concatenate(arrs[::-1], axis=0)  # Blender pixel rows start at the bottom
H = sheet.shape[0]
img = bpy.data.images.new("sheet", W, H, alpha=True); img.pixels = sheet.ravel()
img.filepath_raw = out; img.file_format = 'PNG'; img.save()
print("STACK", out, W, H)
