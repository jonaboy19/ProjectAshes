// Headless export from Azgaar's Fantasy Map Generator (MIT; exported maps free for commercial use).
//   node tools/external/azgaar_export.mjs <seed> <out_dir> [width] [height]
// Serves C:\Users\Jonna\Tools\azgaar\dist on a temp port, drives it with Playwright
// (Edge, no browser download), writes <out_dir>/map_<seed>.png + .svg + .json (full map data).
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
const ROOT = process.env.AZGAAR_DIR || "C:/Users/Jonna/Tools/azgaar";
const require = createRequire(ROOT + "/package.json");
const { chromium } = require("@playwright/test");
const [seed = "ashes1", out = ".", w = "1600", h = "1000"] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const mime = { ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".json": "application/json", ".svg": "image/svg+xml", ".png": "image/png", ".webmanifest": "application/json", ".woff2": "font/woff2" };
const srv = http.createServer((req, res) => {
  let p = path.join(ROOT, "dist", decodeURIComponent(req.url.split("?")[0]).replace("/Fantasy-Map-Generator", ""));
  if (p.endsWith(path.sep) || !fs.existsSync(p)) p = path.join(ROOT, "dist", "index.html");
  res.writeHead(200, { "content-type": mime[path.extname(p)] || "application/octet-stream" });
  fs.createReadStream(p).pipe(res);
}).listen(0);
const port = srv.address().port;
const browser = await chromium.launch({ channel: "msedge", headless: true });
const ctx = await browser.newContext({ viewport: { width: +w, height: +h }, acceptDownloads: true });
const page = await ctx.newPage();
page.on("pageerror", e => console.log("PAGEERROR", String(e).slice(0, 200)));
await page.goto(`http://localhost:${port}/Fantasy-Map-Generator/?seed=${seed}&width=${w}&height=${h}&options=default`);
await page.waitForFunction(() => window.pack && window.pack.cells && window.pack.cells.h && window.pack.cells.h.length > 1000, null, { timeout: 90000 });
console.log("GENERATED cells:", await page.evaluate(() => pack.cells.i.length), "states:", await page.evaluate(() => pack.states.length), "burgs:", await page.evaluate(() => pack.burgs.length));
async function dl(fnCall, ext) {
  const [d] = await Promise.all([page.waitForEvent("download", { timeout: 60000 }), page.evaluate(fnCall)]);
  const f = path.join(out, `map_${seed}.${ext}`);
  await d.saveAs(f);
  console.log("SAVED", f, fs.statSync(f).size);
}
await dl("Services.ExportMap.exportToPng()", "png");
await dl("Services.ExportMap.exportToSvg()", "svg");
await dl("Services.ExportMap.saveGeoJsonRivers()", "rivers.geojson").catch(e => console.log("rivers skipped:", String(e).slice(0, 100)));
await dl("Services.ExportMap.saveGeoJsonCells()", "cells.geojson").catch(e => console.log("cells skipped:", String(e).slice(0, 100)));
await browser.close();
srv.close();
