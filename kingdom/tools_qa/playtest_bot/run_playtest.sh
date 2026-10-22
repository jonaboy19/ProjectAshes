#!/bin/bash
# Rising Ashes playtest bot runner (cloud container: xvfb + vulkan/llvmpipe, LOW tier, one run at a time).
#   tools_qa/playtest_bot/run_playtest.sh [stages]      stages = comma list (default all), e.g. "boot,intro,menus"
# Env: PLAYTEST_OUT, PLAYTEST_SHOTS, PLAYTEST_SHEET, PLAYTEST_ARGS (e.g. "--adult"), PLAYTEST_TIMEOUT.
# Output: /tmp/claude-0/playtest/{report.md,summary.json,run.log,out.txt}, shots in /tmp/claude-0/shots/playtest/,
# contact sheet /tmp/claude-0/shots/playtest_sheet.png.
KINGDOM="$(cd "$(dirname "$0")/../.." && pwd)"
G="${GODOT:-/tmp/claude-0/godot/Godot_v4.6.2-stable_linux.x86_64}"
OUT="${PLAYTEST_OUT:-/tmp/claude-0/playtest}"
SHOTS="${PLAYTEST_SHOTS:-/tmp/claude-0/shots/playtest}"
mkdir -p "$OUT" "$SHOTS"
exec 9>"$OUT/run.lock"
flock -n 9 || { echo "another playtest run is active"; exit 2; }
for attempt in 1 2 3; do
  for i in $(seq 200); do
    [ "$(free -m | awk '/Mem:/{print $7}')" -gt 8500 ] && break
    sleep 5
  done
  free -m | awk '/Mem:/{print "free mem MB (available):", $7}'
  rm -f "$OUT/run.log" "$OUT/out.txt" "$SHOTS"/*.png
  cd "$KINGDOM"
  PLAYTEST_STAGES="$1" PLAYTEST_OUT="$OUT" PLAYTEST_SHOTS="$SHOTS" timeout "${PLAYTEST_TIMEOUT:-1500}" \
    xvfb-run -a -s "-screen 0 1280x720x24" "$G" --path . scenes/main.tscn --rendering-driver vulkan \
    -- --quality=low $PLAYTEST_ARGS --qa=res://tools_qa/playtest_bot/playtest_bot.gd > "$OUT/out.txt" 2>&1
  rc=$?
  echo "godot exit $rc (attempt $attempt)"
  [ $rc -eq 137 ] || break      # 137 = OOM-killed by another agent's render: retry
done
python3 "$KINGDOM/tools_qa/playtest_bot/make_sheet.py" "$SHOTS" "${PLAYTEST_SHEET:-/tmp/claude-0/shots/playtest_sheet.png}"
echo "--- engine errors in stdout (uniq):"
grep -E "SCRIPT ERROR|^ERROR|^WARNING|Parse Error" "$OUT/out.txt" | grep -vi effekseer | sed 's/0x[0-9a-f]*//g' | sort | uniq -c | sort -rn | head -40
