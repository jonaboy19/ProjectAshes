// Recolour the felt cloak/hood of a generated MakeHuman villager GLB in place.
// Villager clothes take their colour from COLOR_0 (vertex colours) times a
// near-grey fabric tile, and the felt tile (atlas u 0.75-1, v 0-0.25 in Blender = glTF v 0.75-1, see
// make_humans.py REG) is used only by cloaks and hoods, so scaling COLOR_0
// on those vertices changes the cloak colour and keeps its grime variation.
// Mirrors a palette change in make_humans.py without a full MPFB regeneration.
//   node recolor_cloak.js <file.glb> <old r,g,b sRGB> <new r,g,b sRGB> [--dry]
const fs = require('fs');
const [file, oldS, newS, dry] = process.argv.slice(2);
const lin = (c) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
const o = oldS.split(',').map(Number).map(lin), n = newS.split(',').map(Number).map(lin);
const b = fs.readFileSync(file);
const jl = b.readUInt32LE(12);
const json = JSON.parse(b.slice(20, 20 + jl).toString());
const binStart = 20 + jl + 8;
let count = 0, sum = [0, 0, 0];
for (const mesh of json.meshes) for (const pr of mesh.primitives) {
  const acc = (k) => { const a = json.accessors[pr.attributes[k]]; const bv = json.bufferViews[a.bufferView];
    if (a.componentType !== 5126 || bv.byteStride) throw new Error(k + ': expected tightly packed float');
    return [binStart + (bv.byteOffset || 0) + (a.byteOffset || 0), a.count]; };
  const [uvOff, cnt] = acc('TEXCOORD_0'), [colOff] = acc('COLOR_0');
  for (let i = 0; i < cnt; i++) {
    const u = b.readFloatLE(uvOff + i * 8), v = b.readFloatLE(uvOff + i * 8 + 4);
    if (u < 0.75 || u > 1.0 || v < 0.75 || v > 1.0) continue;
    count++;
    for (let c = 0; c < 3; c++) {
      const at = colOff + i * 16 + c * 4, val = b.readFloatLE(at);
      sum[c] += val;
      if (!dry) b.writeFloatLE(Math.min(1, val * n[c] / o[c]), at);
    }
  }
}
console.log(file, 'felt verts', count, 'mean linear', sum.map((s) => (s / Math.max(count, 1)).toFixed(3)).join(','));
if (!dry) fs.writeFileSync(file, b);
