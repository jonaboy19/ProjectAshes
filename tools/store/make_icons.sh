#!/usr/bin/env bash
# Export every app-icon variant from the Blender layers (tools/store/make_icon.py).
# Usage: tools/store/make_icons.sh            (renders the layers first if missing)
# Needs ffmpeg and Blender 5.x.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
BLENDER="${BLENDER:-/c/Program Files/Blender Foundation/Blender 5.2/blender.exe}"
WORK="$REPO/store/_work"
ICON="$REPO/store/icon"
GAME="$REPO/kingdom/assets/generated/app_icon"
mkdir -p "$WORK" "$ICON/android" "$ICON/ios/AppIcon.appiconset" "$ICON/checks" "$GAME"
if [ ! -f "$WORK/icon_fg_1024.png" ] || [ "${RERENDER:-0}" = 1 ]; then
	"$BLENDER" -b --python "$HERE/make_icon.py" -- "$(cygpath -m "$WORK" 2>/dev/null || echo "$WORK")" | grep "ICON DONE"
fi
ff() { ffmpeg -loglevel error -y "$@"; }
L="flags=lanczos"

# Master and store icons (opaque).
ff -i "$WORK/icon_master_1024.png" -pix_fmt rgb24 "$ICON/icon_master_1024.png"
ff -i "$WORK/icon_master_1024.png" -vf "scale=512:512:$L" -pix_fmt rgb24 "$ICON/play_store_icon_512.png"

# Android adaptive icon layers, 432x432 (108 dp at xxxhdpi). The foreground is scaled to
# 85% and anchored to the bottom edge, so the ring sits inside the 66 dp safe circle and
# the runestone runs out of the bottom of the layer (never a visible cut).
FGS=368   # 432 * 0.85
ff -i "$WORK/icon_fg_1024.png" -vf "scale=$FGS:$FGS:$L,pad=432:432:(432-$FGS)/2:432-$FGS:color=black@0,format=rgba" "$ICON/android/adaptive_foreground_432.png"
ff -i "$WORK/icon_bg_1024.png" -vf "scale=432:432:$L" -pix_fmt rgb24 "$ICON/android/adaptive_background_432.png"
ff -i "$WORK/icon_mono_1024.png" -vf "scale=$FGS:$FGS:$L,pad=432:432:(432-$FGS)/2:432-$FGS:color=white@0,format=rgba" "$ICON/android/adaptive_monochrome_432.png"
ff -i "$WORK/icon_master_1024.png" -vf "scale=192:192:$L" -pix_fmt rgb24 "$ICON/android/main_192.png"

# iOS AppIcon set: opaque PNGs (the App Store rejects alpha in the 1024 icon).
for s in 20 29 40 58 60 76 80 87 120 152 167 180 1024; do
	ff -i "$WORK/icon_master_1024.png" -vf "scale=$s:$s:$L" -pix_fmt rgb24 "$ICON/ios/AppIcon.appiconset/icon_$s.png"
done

# Copies inside the Godot project for kingdom/export_presets.cfg (res:// paths).
cp "$ICON/icon_master_1024.png" "$GAME/icon_1024.png"
cp "$ICON/android/main_192.png" "$GAME/icon_192.png"
cp "$ICON/android/adaptive_foreground_432.png" "$GAME/adaptive_foreground_432.png"
cp "$ICON/android/adaptive_background_432.png" "$GAME/adaptive_background_432.png"
cp "$ICON/android/adaptive_monochrome_432.png" "$GAME/adaptive_monochrome_432.png"

# Checks: 48 px and 96 px (shown enlarged), adaptive circle/squircle masks, monochrome tint.
ff -i "$ICON/icon_master_1024.png" -filter_complex "\
[0]scale=48:48:$L,scale=192:192:flags=neighbor[a];[0]scale=96:96:$L,scale=192:192:flags=neighbor[b];[0]scale=48:48:$L[c];\
color=c=0x303030:s=640x220[bg];[bg][a]overlay=12:14[t1];[t1][b]overlay=224:14[t2];[t2][c]overlay=460:86" -frames:v 1 "$ICON/checks/downscale_48_96.png"
ff -i "$ICON/android/adaptive_background_432.png" -i "$ICON/android/adaptive_foreground_432.png" -i "$ICON/android/adaptive_monochrome_432.png" -filter_complex "\
[0][1]overlay=0:0,crop=288:288:72:72,format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='if(lte(hypot(X-144,Y-144),144),255,0)'[circle];\
[0][1]overlay=0:0,crop=288:288:72:72,format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='if(lte(pow(abs(X-144)/144,4)+pow(abs(Y-144)/144,4),1),255,0)'[squircle];\
[2]crop=288:288:72:72,format=rgba,geq=r='90':g='200':b='230':a='if(lte(hypot(X-144,Y-144),144),alpha(X,Y),0)'[mono];\
color=c=0xe8e8e8:s=940x320[bg];[bg][circle]overlay=16:16[t1];[t1][squircle]overlay=326:16[t2];color=c=0x1c2433:s=300x300[mb];[mb][mono]overlay=6:6[m2];[t2][m2]overlay=630:10" -frames:v 1 "$ICON/checks/android_masks.png"
echo "icons written to $ICON and $GAME"
