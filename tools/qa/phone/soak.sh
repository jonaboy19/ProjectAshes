#!/usr/bin/env bash
# S22 soak: boot -> Continue -> walk/turn loop with adb input; samples memory, thermal and PERF.
#   bash tools/qa/phone/soak.sh <seconds> <outdir> [--nolaunch]
# Out: samples.csv (t, pss_mb, thermal_status, skin_c), perf.log (game PERF lines, debug builds),
#      shot_*.jpg every 120 s. Coordinates are for 2340x1080 landscape.
set -u
DUR=${1:-120}; OUT=${2:-/tmp/soak/run}; mkdir -p "$OUT"
A="${ADB:-/c/Program Files (x86)/Touch Portal/plugins/adb/platform-tools/adb}"
D=R5CT849XNVF; P=com.risingashes.game
a() { "$A" -s $D "$@"; }
shot() { a exec-out screencap -p > "$OUT/$1.png"; py -c "from PIL import Image; Image.open(r'$(cygpath -w "$OUT/$1.png")').convert('RGB').resize((1170,540)).save(r'$(cygpath -w "$OUT/$1.jpg")',quality=80)"; rm -f "$OUT/$1.png"; }
if [ "${3:-}" != "--nolaunch" ]; then
  a shell am force-stop $P; a logcat -c
  a shell monkey -p $P -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 30; a shell input tap 1170 830; sleep 4; a shell input tap 240 430   # tap to start, Continue
  sleep 75; shot load
fi
a logcat -v time -s godot > "$OUT/godot.log" & LC=$!
echo "t,pss_mb,thermal_status,skin_c" > "$OUT/samples.csv"
t0=$(date +%s); i=0
while [ $(( $(date +%s) - t0 )) -lt "$DUR" ]; do
  # walk forward 4 s on the joystick, then swing the camera right
  a shell input swipe 330 860 330 700 4000
  a shell input swipe 1600 600 1800 600 500
  i=$((i+1))
  if [ $((i % 5)) -eq 0 ]; then
    t=$(( $(date +%s) - t0 ))
    pss=$(a shell dumpsys meminfo $P | awk '/TOTAL PSS:/{print int($3/1024); exit} /^ *TOTAL /{print int($2/1024); exit}')
    th=$(a shell dumpsys thermalservice | awk -F': ' '/Thermal Status/{print $2; exit}')
    skin=$(a shell dumpsys thermalservice | grep -m1 -o 'mValue=[0-9.]*, mName=SKIN' | sed 's/mValue=//;s/, mName=SKIN//')
    echo "$t,$pss,$th,$skin" | tee -a "$OUT/samples.csv"
  fi
  [ $((i % 24)) -eq 0 ] && shot "shot_$(( $(date +%s) - t0 ))"
done
shot end
kill $LC 2>/dev/null
grep -a 'PERF\|THERMAL\|ERROR' "$OUT/godot.log" > "$OUT/perf.log"
