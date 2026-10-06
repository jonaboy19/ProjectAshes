#!/usr/bin/env bash
# S22 perf route: fresh QA world (never the owner's Continue save), the town route of tools_qa/perf/town_route.gd.
#   bash tools/qa/phone/route.sh <seconds> <outdir> [low|medium|high] [extra user args, ';' separated]
# Out: godot.log (ROUTE / PERF / THERMAL lines), samples.csv (t, pss_mb, gfx_mb, native_mb, code_mb, thermal, skin_c),
#      meminfo_end.txt, end.jpg. The game quits itself at the end (the run has a hard timeout too).
set -u
DUR=${1:-120}; OUT=${2:-/tmp/route}; TIER=${3:-low}; EXTRA=${4:-}
mkdir -p "$OUT"
A="${ADB:-/c/Users/Jonna/platform-tools/adb.exe}"   # the shared adb version (a different one restarts the server)
D=R5CT849XNVF; P=com.risingashes.game
a() { "$A" -s $D "$@"; }
# Needs a QA APK exported with command_line/extra_args="-- --adult --qa=res://tools_qa/perf/town_route.gd" (the S22 shell
# cannot pass intent extras to GodotApp). Tier, length and census come from user://qa_args.txt (debug builds only).
{ echo "--quality=$TIER"; echo "--seconds=$DUR"; for e in $(echo "$EXTRA" | tr ';' ' '); do echo "$e"; done; } > "$OUT/qa_args.txt"
a shell am force-stop $P; a logcat -G 16M; a logcat -c
a exec-in run-as $P sh -c 'cat > files/qa_args.txt' < "$OUT/qa_args.txt"
a shell run-as $P cat files/qa_args.txt
a shell monkey -p $P -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
echo "t,pss_mb,gfx_mb,native_mb,code_mb,thermal,skin_c" > "$OUT/samples.csv"
t0=$(date +%s)
LIMIT=$((DUR + 240))
while [ $(( $(date +%s) - t0 )) -lt $LIMIT ]; do
  sleep 20
  t=$(( $(date +%s) - t0 ))
  m=$(a shell dumpsys meminfo $P)
  pss=$(echo "$m" | awk '/TOTAL PSS:/{print int($3/1024); exit}')
  gfx=$(echo "$m" | awk '/^ *Graphics:/{print int($2/1024); exit}')
  nat=$(echo "$m" | awk '/^ *Native Heap:/{print int($3/1024); exit}')
  code=$(echo "$m" | awk '/^ *Code:/{print int($2/1024); exit}')
  th=$(a shell dumpsys thermalservice | awk -F': ' '/Thermal Status/{print $2; exit}')
  skin=$(a shell dumpsys thermalservice | grep -m1 -o 'mValue=[0-9.]*, mType=3, mName=SKIN' | sed 's/mValue=//;s/, mType.*//')
  echo "$t,$pss,$gfx,$nat,$code,$th,$skin" >> "$OUT/samples.csv"
  [ -z "$pss" ] && grep -q ROUTE_SUM "$OUT/godot.log" && break
  a logcat -d -v time -s godot > "$OUT/godot.log"
  if grep -q ROUTE_SUM "$OUT/godot.log"; then a shell dumpsys meminfo $P > "$OUT/meminfo_end.txt"; break; fi
  [ ! -f "$OUT/meminfo_mid.txt" ] && [ $t -ge 100 ] && a shell dumpsys meminfo $P > "$OUT/meminfo_mid.txt"
done
a exec-out screencap -p > "$OUT/end.png" 2>/dev/null
a logcat -d -v time -s godot > "$OUT/godot.log"
a shell am force-stop $P
a shell run-as $P rm -f files/qa_args.txt
grep -a 'ROUTE\|PERF\|THERMAL\|SCRIPT ERROR\|CENSUS' "$OUT/godot.log" | sed 's/.*godot([ 0-9]*): //' > "$OUT/route.log"
cat "$OUT/route.log" | grep -v CENSUS; tail -3 "$OUT/samples.csv"
