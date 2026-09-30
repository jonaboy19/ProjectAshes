// Headless SFX generator on top of jsfxr (Unlicense). Seeded, so a seed reproduces the same sound.
//   node tools/external/jsfxr_gen.js <preset> <seed> <out.wav> [count]
// presets: pickupCoin laserShoot explosion powerUp hitHurt jump blipSelect synth tone click random
// count > 1 writes out_1.wav, out_2.wav ... (seed, seed+1, ...) = cheap variations for footsteps, hits, UI ticks.
const path = require("path"), fs = require("fs");
const sfxr = require(path.join(process.env.JSFXR_DIR || "C:/Users/Jonna/Tools/jsfxr", "node_modules/jsfxr/sfxr.js"));
const [preset, seedArg, out, countArg] = process.argv.slice(2);
if (!preset || !out) { console.error("usage: node jsfxr_gen.js <preset> <seed> <out.wav> [count]"); process.exit(1); }
function mulberry32(a) { return function () { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
const count = parseInt(countArg || "1", 10);
for (let i = 0; i < count; i++) {
  Math.random = mulberry32(parseInt(seedArg || "1", 10) + i);
  const p = sfxr.sfxr.generate(preset);
  const wav = new sfxr.SoundEffect(p).generate();
  const m = wav.dataURI.match(/^data:.+\/(.+);base64,(.*)$/);
  const f = count > 1 ? out.replace(/\.wav$/, "_" + (i + 1) + ".wav") : out;
  fs.writeFileSync(f, Buffer.from(m[2], "base64"));
  console.log("wrote", f, "seed", parseInt(seedArg || "1", 10) + i);
}


