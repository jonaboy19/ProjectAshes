#!/bin/bash
# Rising Ashes v1 headless release harness: import -> full gdUnit suite -> playtest bot (headless).
#   tools_qa/v1/run_v1.sh [stages]     stages = comma list, default "boot,intro,menus,st_birth,st_a1"
# Env: GODOT (binary; default: godot on PATH, else /opt/godot/godot), OUT (default $PWD/v1_out),
#      V1_SKIP_IMPORT=1, V1_SKIP_GDUNIT=1, V1_GDUNIT_TARGET (default res://tests), V1_GDUNIT_TIMEOUT (s, 3600),
#      V1_BOT_TIMEOUT (s, 3600), V1_HOOKS_STRICT=1 (unlisted [HOOK] kinds fail the run), PLAYTEST_ARGS.
# Exit: 0 all green; 1 gdUnit failed; 2 bot failed (CHECK / SCRIPT ERROR / stuck or timed-out stage / no report); 3 setup.
# Output in $OUT: import.log, gdunit.log, bot_out.txt, report.md, summary.json, run.log, verdict.txt.
KINGDOM="$(cd "$(dirname "$0")/../.." && pwd)"
STAGES="${1:-boot,intro,menus,st_birth,st_a1}"
G="${GODOT:-$(command -v godot || true)}"
[ -x "$G" ] || G=/opt/godot/godot
[ -x "$G" ] || { echo "Godot binary not found: set GODOT=/path/to/Godot_v4.6.3-stable_linux.x86_64"; exit 3; }
OUT="${OUT:-$PWD/v1_out}"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
rm -f "$OUT"/{verdict.txt,report.md,summary.json,run.log,bot_out.txt}
cd "$KINGDOM" || exit 3
rc_total=0
verdict() { echo "$*" | tee -a "$OUT/verdict.txt"; }
echo "godot: $("$G" --version 2>/dev/null | head -1)  stages: $STAGES  out: $OUT"

# 1. import (builds the class cache; a second pass catches types that only resolve after the first)
if [ -z "$V1_SKIP_IMPORT" ]; then
  # the editor-mode import rewrites project.godot (drops renderer / shadow / AA keys): snapshot and put it back
  cp project.godot "$OUT/project.godot.orig"
  timeout 1800 "$G" --headless --path . --import > "$OUT/import.log" 2>&1
  timeout 1800 "$G" --headless --path . --import >> "$OUT/import.log" 2>&1
  cp "$OUT/project.godot.orig" project.godot
  verdict "import: done (rc $?), $(grep -c 'SCRIPT ERROR\|Parse Error' "$OUT/import.log") parse/script errors in import.log"
fi

# 2. whole gdUnit suite (exit 0 = pass, 101 = orphan warnings only = pass, 100 = failures)
if [ -z "$V1_SKIP_GDUNIT" ]; then
  timeout "${V1_GDUNIT_TIMEOUT:-3600}" "$G" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
    --add "${V1_GDUNIT_TARGET:-res://tests}" --ignoreHeadlessMode > "$OUT/gdunit.log" 2>&1
  rc=$?
  if [ $rc -eq 0 ] || [ $rc -eq 101 ]; then verdict "gdunit: PASS (rc $rc)"
  else verdict "gdunit: FAIL (rc $rc), see gdunit.log"; grep -E "FAILED|Failures:" "$OUT/gdunit.log" | head -20; rc_total=1; fi
fi

# 3. playtest bot, headless (no screenshots, no fps sampling: DisplayServer is "headless")
PLAYTEST_STAGES="$STAGES" PLAYTEST_OUT="$OUT" PLAYTEST_SHOTS="$OUT/shots" \
  timeout "${V1_BOT_TIMEOUT:-3600}" "$G" --headless --path . scenes/main.tscn \
  -- --quality=low $PLAYTEST_ARGS --qa=res://tools_qa/playtest_bot/playtest_bot.gd > "$OUT/bot_out.txt" 2>&1
brc=$?
verdict "bot: godot exit $brc"
python3 -I "$KINGDOM/tools_qa/v1/verdict.py" "$OUT" "$KINGDOM/tools_qa/v1/hooks_allowed.txt" "$STAGES" "$brc" "${V1_HOOKS_STRICT:-0}" | tee -a "$OUT/verdict.txt"
[ "${PIPESTATUS[0]}" -eq 0 ] || rc_total=$([ $rc_total -ne 0 ] && echo $rc_total || echo 2)
verdict "RESULT: $([ $rc_total -eq 0 ] && echo PASS || echo FAIL) (exit $rc_total)"
exit $rc_total
