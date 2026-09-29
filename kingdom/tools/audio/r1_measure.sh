#!/usr/bin/env bash
# Measure every kingdom/assets/audio/region1 OGG: duration, size, integrated LUFS, max momentary LUFS, true peak, sample peak.
# Output CSV on stdout: file,sec,kb,lufs_i,true_peak_dbtp,sample_peak_db
cd "$(dirname "$0")/../.." || exit 1
echo "file,sec,kb,lufs_i,true_peak_dbtp,sample_peak_db"
find assets/audio/region1 -name '*.ogg' | sort | while read -r f; do
  out=$(ffmpeg -nostdin -v verbose -i "$f" -af apad=whole_dur=1,ebur128=peak=true+sample -f null - 2>&1)
  sum=$(echo "$out" | sed -n '/Summary:/,$p')
  I=$(echo "$sum" | awk '/^ *I:/{print $2}')
  TP=$(echo "$sum" | awk '/True peak/{f=1} f&&/Peak:/{print $2; exit}')
  SP=$(echo "$sum" | awk '/Sample peak/{f=1} f&&/Peak:/{print $2; exit}')
  M=$(echo "$out" | grep -oE "M:-?[0-9.]+" | sed "s/M://" | sort -n | tail -1)
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
  kb=$(( $(stat -c %s "$f") / 1024 ))
  printf '%s,%.2f,%d,%s,%s,%s,%s\n' "${f#assets/audio/}" "$dur" "$kb" "$I" "$TP" "$SP"
done
