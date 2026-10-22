#!/usr/bin/env bash
# Before / after CPU profiles without a second 11 GB checkout: builds a throw-away project whose scripts/ and autoload/ come from a
# git ref (read-only `git archive`), everything else (data, scenes, shaders, tests, tools_qa, project settings) from the working tree,
# and assets / addons / the import cache symlinked. Run the same profile in both and compare:
#   tools_qa/cpu_mem/ab_overlay.sh <git-ref> /tmp/kbase
#   GODOT=/path/to/godot
#   $GODOT --headless --path /tmp/kbase -- --adult --quality=low --qa=res://tools_qa/cpu_mem/cpu_profile.gd --out=/tmp/before.json
#   $GODOT --headless --path kingdom   -- --adult --quality=low --qa=res://tools_qa/cpu_mem/cpu_profile.gd --out=/tmp/after.json
# Alternate the two runs (B A B A) and compare best-of: other processes on the machine move single runs by 20 %.
# Needs the profiling tools in the ref's scripts: scripts/core/perf_probe.gd is copied in from the working tree when the ref has none.
set -eu
REF="${1:?usage: ab_overlay.sh <git-ref> <output-dir>}"
OUT="${2:?usage: ab_overlay.sh <git-ref> <output-dir>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"          # kingdom/
REPO="$(cd "$ROOT/.." && pwd)"
mkdir -p "$OUT/.godot"
for d in assets addons godot_gas; do ln -sfn "$ROOT/$d" "$OUT/$d"; done
for d in data dialogue locale resources scenes shaders tools_qa tests; do rm -rf "$OUT/$d"; cp -r "$ROOT/$d" "$OUT/$d"; done
cp "$ROOT/project.godot" "$ROOT/default_bus_layout.tres" "$ROOT/export_presets.cfg" "$ROOT"/icon.svg* "$OUT/"
for f in global_script_class_cache.cfg uid_cache.bin extension_list.cfg scene_groups_cache.cfg; do cp "$ROOT/.godot/$f" "$OUT/.godot/"; done
ln -sfn "$ROOT/.godot/imported" "$OUT/.godot/imported"
rm -rf "$OUT/scripts" "$OUT/autoload"
(cd "$REPO" && git archive "$REF" kingdom/scripts kingdom/autoload) | tar -x -C "$OUT" --strip-components=1
[ -f "$OUT/scripts/core/perf_probe.gd" ] || cp "$ROOT/scripts/core/perf_probe.gd" "$OUT/scripts/core/perf_probe.gd"
echo "overlay of $REF ready in $OUT (scripts/ and autoload/ from the ref)"
