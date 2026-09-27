#!/usr/bin/env bash
# Build docs/asset_gallery/index.html: every asset preview PNG/JPG in the repo, grouped by section.
# Run from the repo root:  bash tools/gallery/build_gallery.sh
set -e
out=docs/asset_gallery/index.html
mkdir -p docs/asset_gallery

section() { # $1 = title, rest = glob patterns
  local title="$1"; shift
  local files=()
  for p in "$@"; do for f in $p; do
    case "$f" in *.png|*.jpg|*.jpeg) [ -f "$f" ] && files+=("$f");; esac  # skip Godot .import sidecars
  done; done
  [ ${#files[@]} -eq 0 ] && return
  echo "<section><h2>$title <span>${#files[@]}</span></h2><div class=grid>"
  for f in "${files[@]}"; do
    local n; n=$(basename "$f"); n=${n%.*}
    echo "<figure><a href=\"../../$f\" target=_blank><img loading=lazy src=\"../../$f\" alt=\"$n\"></a><figcaption>$n</figcaption></figure>"
  done
  echo "</div></section>"
}

M=kingdom/assets/incoming/ai3d/meshy/_previews
B=docs/kingdom/blender_previews
{
cat <<'EOF'
<!doctype html><html lang=en><head><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>Rising Ashes Assets</title>
<style>
:root{--bg:#f4efe6;--fg:#2b2118;--card:#fffaf2;--line:#e2d6c3;--accent:#8a4b1f}
@media (prefers-color-scheme:dark){:root{--bg:#1c1814;--fg:#efe6d8;--card:#27211b;--line:#3a3128;--accent:#e0a36b}}
*{box-sizing:border-box}body{margin:0;padding:16px;background:var(--bg);color:var(--fg);font:15px/1.4 system-ui,sans-serif}
h1{margin:4px 0 2px;font-size:22px}p.sub{margin:0 0 12px;opacity:.75}
nav{position:sticky;top:0;background:var(--bg);padding:8px 0;display:flex;flex-wrap:wrap;gap:6px;z-index:2;border-bottom:1px solid var(--line)}
nav a{color:var(--accent);text-decoration:none;border:1px solid var(--line);border-radius:14px;padding:3px 10px;font-size:13px}
h2{font-size:17px;margin:22px 0 8px}h2 span{font-size:12px;opacity:.6;font-weight:400}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:10px}
figure{margin:0;background:var(--card);border:1px solid var(--line);border-radius:8px;overflow:hidden}
img{width:100%;display:block;background:#fff}figcaption{padding:6px 8px;font-size:12px;word-break:break-all}
</style></head><body>
<h1>Rising Ashes: asset gallery</h1><p class=sub>Every preview render in the repo. Click an image to open it full size. Rebuild with <code>bash tools/gallery/build_gallery.sh</code>.</p>
<nav><a href=#s1>Hero buildings</a><a href=#s2>Houses and stalls</a><a href=#s3>Creatures</a><a href=#s4>Armored characters</a><a href=#s5>Interiors</a><a href=#s6>Props</a><a href=#s7>Characters</a><a href=#s8>Animals</a><a href=#s9>Armor</a><a href=#s10>Concepts</a><a href=#s11>Game screenshots</a><a href=#s12>Older Blender builds</a></nav>
EOF
echo "<div id=s1></div>";  section "Hero buildings (Meshy)" "$M/guild_*" "$M/inn_*" "$M/blacksmith_lod*" "$M/healer_*"
echo "<div id=s2></div>";  section "Houses and market stalls (Meshy)" "$M/houses_round2_sheet.png" "$M/house_*" "$M/stall_*"
echo "<div id=s2b></div>"; section "Landmarks (Meshy)" "$M/landmarks_sheet.png" "$M/landmark_*"
echo "<div id=s3></div>";  section "Creatures (Meshy, rigged and animated)" "$M/creatures_lineup.png" "$M/*_anim.png"
echo "<div id=s4></div>";  section "Armored characters (Meshy)" "$M/armored_*"
echo "<div id=s5></div>";  section "Interiors" "$B/_interiors_sheet.png" "$B/interior_*"
echo "<div id=s6></div>";  section "Village props (Blender)" "$B/_props_round3_sheet.png" "$B/prop_*"
echo "<div id=s7></div>";  section "Characters and animations" "kingdom/assets/incoming/characters/_previews/*.png" "$B/characters*.png"
echo "<div id=s8></div>";  section "Animals (CC0)" "kingdom/assets/incoming/animals/_previews/*.png"
echo "<div id=s9></div>";  section "Armor library" "kingdom/assets/incoming/armor/_previews/*.jpg"
echo "<div id=s10></div>"; section "Concept art and references" "docs/art_reference/*.png" "$M/concepts_*.png"
echo "<div id=s11></div>"; section "Game screenshots" "docs/kingdom/*.png" "docs/screenshots/*.png"
echo "<div id=s12></div>"; section "Earlier Blender builds" "$B/village_*.png" "$B/adventurer_guild.png" "$B/healer_house.png" "$B/town_*.png" "$B/castle_keep.png" "$B/chapel.png" "$B/temple.png" "$B/bell_tower.png" "$B/nature/*.png"
echo "</body></html>"
} > "$out"
echo "wrote $out ($(grep -c '<figure>' "$out") images)"
