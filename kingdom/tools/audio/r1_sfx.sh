#!/usr/bin/env bash
# L17 Region 1 SFX / loops / barks. Run from repo root with ffmpeg on PATH.
# One-shots: mono 44.1 kHz, trimmed, 3 ms fade-in, peak-normalised to -3.0 dBFS, OGG q4.
# Loops (rune hum, rift ambience): loudnorm to -26 / -24 LUFS integrated, seamless, OGG q4.
set -euo pipefail
FF="ffmpeg -nostdin -v error -y"
IN=kingdom/assets/incoming
OG=$IN/opengameart
BSB=$IN/audio/bigsoundbank
A=kingdom/assets/audio
OUT=$A/region1
TMP=${TMPDIR:-/tmp}/r1s
mkdir -p "$OUT/sfx" "$OUT/voice" "$OUT/ambience" "$TMP"
SR=44100
PK=-3.0   # peak target dBFS

peaknorm() { # in.wav out.ogg [fade_out_s]
  local in=$1 out=$2 fo=${3:-0.03}
  local mv; mv=$(ffmpeg -nostdin -hide_banner -i "$in" -af volumedetect -f null - 2>&1 | sed -n 's/.*max_volume: \(-\?[0-9.]*\) dB.*/\1/p')
  local g; g=$(awk -v p="$PK" -v m="$mv" 'BEGIN{printf "%.2f", p-m}')
  local dur; dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$in")
  local st; st=$(awk -v d="$dur" -v f="$fo" 'BEGIN{printf "%.3f", (d>f)?d-f:0}')
  $FF -i "$in" -af "volume=${g}dB,afade=t=in:d=0.003,afade=t=out:st=$st:d=$fo,alimiter=limit=0.708:level=false" -ac 1 -ar $SR -c:a libvorbis -q:a 4 "$out"
}
trimwav() { # in out : trim silence both ends (-45 dB), mono 44.1k
  $FF -i "$1" -ac 1 -ar $SR -af "silenceremove=start_periods=1:start_threshold=-45dB:stop_periods=1:stop_threshold=-45dB:stop_duration=0.05" "$2"
}
pitch() { echo "aresample=$SR,asetrate=$(awk -v r=$1 -v s=$SR 'BEGIN{printf "%d", s*r}'),aresample=$SR"; }

# ---------------- synthesised (own work, CC0) ----------------
# Glyph carve strokes: chisel scrape on stone + tiny completion ping
carve() { # name dur lo hi grit ping
  local n=$1 d=$2 lo=$3 hi=$4 g=$5 p=$6
  $FF -f lavfi -i "aevalsrc='(random(0)*2-1)*min(1,t/0.02)*min(1,($d-t)/0.08)*(0.55+0.45*sin(2*PI*$g*t))*0.7+0.18*exp(-(t-($d-0.12))*30)*gt(t,$d-0.12)*sin(2*PI*$p*t)':s=$SR:d=$d:c=mono" \
     -af "highpass=f=$lo,lowpass=f=$hi,equalizer=f=$(( (lo+hi)/2 )):t=q:w=1.2:g=5" "$TMP/$n.wav"
  peaknorm "$TMP/$n.wav" "$OUT/sfx/$n.ogg" 0.05
}
carve sfx_r1_glyph_carve_01 0.42 1400 5200 38 1760
carve sfx_r1_glyph_carve_02 0.55 1100 4200 31 1568
carve sfx_r1_glyph_carve_03 0.36 1800 6000 44 1976

# Ward activate: rising blue-rune chime (E major arpeggio, staggered) over a swell
$FF -f lavfi -i "aevalsrc='0.18*sin(2*PI*(220+180*t)*t)*min(1,t/0.5)*exp(-(t-0.9)*gt(t,0.9)*3)+0.55*gt(t,0.00)*exp(-(t-0.00)*3.2)*sin(2*PI*659.3*t)+0.50*gt(t,0.11)*exp(-(t-0.11)*3.2)*sin(2*PI*830.6*t)+0.45*gt(t,0.22)*exp(-(t-0.22)*3.2)*sin(2*PI*987.8*t)+0.42*gt(t,0.33)*exp(-(t-0.33)*2.6)*sin(2*PI*1318.5*t)+0.12*gt(t,0.33)*exp(-(t-0.33)*2.6)*sin(2*PI*2637*t)':s=$SR:d=1.9:c=mono" -af "lowpass=f=6500,aecho=0.7:0.5:70|140:0.3|0.15" "$TMP/ward_on.wav"
peaknorm "$TMP/ward_on.wav" "$OUT/sfx/sfx_r1_ward_activate.ogg" 0.25

# Ward break: glass shatter (rubberduck CC0) + sub thump + falling chime
trimwav "$OG/sfx/100-sfx-rubberduck/glass_04.ogg" "$TMP/glass.wav"
$FF -f lavfi -i "aevalsrc='0.9*exp(-t*9)*sin(2*PI*(58-14*t)*t)+0.35*(random(0)*2-1)*exp(-t*22)+0.35*gt(t,0.05)*exp(-(t-0.05)*3.5)*sin(2*PI*987.8*t*(1-0.18*(t-0.05)))+0.30*gt(t,0.18)*exp(-(t-0.18)*3.5)*sin(2*PI*659.3*t*(1-0.2*(t-0.18)))':s=$SR:d=1.6:c=mono" -af "lowpass=f=7000" "$TMP/break_syn.wav"
$FF -i "$TMP/break_syn.wav" -i "$TMP/glass.wav" -filter_complex "[1:a]volume=0.9,apad=whole_dur=1.6[g];[0:a][g]amix=inputs=2:normalize=0,aecho=0.6:0.4:60:0.25" "$TMP/ward_off.wav"
peaknorm "$TMP/ward_off.wav" "$OUT/sfx/sfx_r1_ward_break.ogg" 0.3

# ---------------- Stagborn calls (BigSoundBank CC0 recordings, pitched/layered) ----------------
# Bellow: deep cow low pitched down + rasp from a big-cat roar
$FF -i "$BSB/cow_moos_4_s2384.ogg" -i "$BSB/cat_roar_3_s1883.ogg" -filter_complex \
 "[0:a]$(pitch 0.72),volume=1.0[a];[1:a]$(pitch 0.8),lowpass=f=2500,volume=0.35[b];[a][b]amix=inputs=2:duration=first:normalize=0,lowpass=f=4500,aecho=0.6:0.5:120:0.22,acompressor=threshold=0.1:ratio=3" "$TMP/bellow.wav"
trimwav "$TMP/bellow.wav" "$TMP/bellow_t.wav"; peaknorm "$TMP/bellow_t.wav" "$OUT/sfx/sfx_r1_stagborn_bellow.ogg" 0.2
# Alert snort: horse breath, two pitches
for v in 01:0.85 02:0.7; do n=${v%%:*}; r=${v##*:}
  $FF -i "$A/sfx/animals/horse_snort.ogg" -af "$(pitch $r),highpass=f=90,acompressor=threshold=0.08:ratio=4,volume=2" "$TMP/snort$n.wav"
  trimwav "$TMP/snort$n.wav" "$TMP/snort${n}_t.wav"; peaknorm "$TMP/snort${n}_t.wav" "$OUT/sfx/sfx_r1_stagborn_alert_snort_$n.ogg" 0.08
done
# Warden roar: two big-cat roars pitched down + cow sub layer
$FF -i "$BSB/cat_roar_1_s1881.ogg" -i "$BSB/cat_roar_3_s1883.ogg" -i "$BSB/cow_moos_s0546.ogg" -filter_complex \
 "[0:a]$(pitch 0.55)[a];[1:a]$(pitch 0.7),volume=0.8[b];[2:a]$(pitch 0.5),volume=0.55[c];[a][b][c]amix=inputs=3:duration=longest:normalize=0,lowpass=f=4000,acompressor=threshold=0.08:ratio=4,aecho=0.6:0.5:90|180:0.3|0.15" "$TMP/roar.wav"
trimwav "$TMP/roar.wav" "$TMP/roar_t.wav"; peaknorm "$TMP/roar_t.wav" "$OUT/sfx/sfx_r1_stagborn_warden_roar.ogg" 0.4

# ---------------- barks ----------------
M="$OG/sfx/voice-clip-pack-male-adventurer-rpg/RPG Male Adventurer"
F="$OG/sfx/female-rpg-voice-starter-cicifyre"
bark() { trimwav "$2" "$TMP/b_$1.wav"; peaknorm "$TMP/b_$1.wav" "$OUT/voice/vo_r1_$1.ogg" 0.04; }
bark m_greet_01   "$M/greet0.wav"
bark m_effort_01  "$M/attack1.wav"
bark m_effort_02  "$M/attack5.wav"
bark m_effort_03  "$M/attackbig2.wav"
bark m_hurt_01    "$M/hurt1.wav"
bark m_hurt_02    "$M/hurt5.wav"
bark m_jump_01    "$M/jump0.wav"
bark m_yes_01     "$M/yes0.wav"
bark m_no_01      "$M/no0.wav"
bark m_victory_01 "$M/victory0.wav"
bark f_effort_01  "$F/t2_attack1.wav"
bark f_effort_02  "$F/t2_attack2.wav"
bark f_effort_03  "$F/t3_attack3.wav"
bark f_hurt_01    "$F/t2_damaged1.wav"
bark f_hurt_02    "$F/t3_damaged2.wav"
bark f_hurt_03    "$F/t2_damaged3.wav"
bark f_jump_01    "$F/t3_jump1.wav"
bark f_jump_02    "$F/t2_jump2.wav"
bark f_relief_01  "$F/t2_healed1.wav"
bark f_relief_02  "$F/t3_healed2.wav"

# ---------------- loops ----------------
lnorm() { bash kingdom/tools/audio/r1_loopnorm.sh "$1" "$2" "$3" 4; }
# Rune hum: all partials integer Hz and 0.5 Hz tremolo -> exactly periodic over 6 s; take a steady-state 6 s slice
$FF -f lavfi -i "aevalsrc='(0.50*sin(2*PI*110*t)+0.34*sin(2*PI*165*t)+0.22*sin(2*PI*220*t)+0.22*sin(2*PI*221*t)+0.12*sin(2*PI*330*t)+0.05*sin(2*PI*660*t)*(0.5+0.5*sin(2*PI*0.5*t)))*(0.86+0.14*sin(2*PI*0.5*t))':s=$SR:d=12:c=mono" \
   -af "lowpass=f=1400,atrim=3:9,asetpts=PTS-STARTPTS" "$TMP/hum.wav"
lnorm "$TMP/hum.wav" "$OUT/ambience/sfx_r1_rune_hum_loop.ogg" -26

# Scar / rift ambience: detuned open-fifth pad + slow airy shimmer + filtered noise, crossfade-looped (24 s)
XF=4; L=24
$FF -f lavfi -i "aevalsrc='0.35*sin(2*PI*55*t)*(0.7+0.3*sin(2*PI*0.083*t))+0.25*sin(2*PI*82.4*t+0.5*sin(2*PI*0.11*t))+0.16*sin(2*PI*110.7*t)*(0.6+0.4*sin(2*PI*0.14*t))+0.14*sin(2*PI*164.8*t)*(0.5+0.5*sin(2*PI*0.09*t))+0.06*sin(2*PI*987.8*t)*max(0,sin(2*PI*0.21*t))+0.05*sin(2*PI*1318.5*t)*max(0,sin(2*PI*0.17*t+1))+0.05*(random(0)*2-1)*(0.6+0.4*sin(2*PI*0.13*t))':s=$SR:d=$((L+XF+2)):c=stereo" \
   -af "lowpass=f=2400,highpass=f=40,aecho=0.7:0.6:400|760:0.35|0.2" "$TMP/rift_src.wav"
$FF -i "$TMP/rift_src.wav" -filter_complex "[0:a]asplit=3[a][b][c];[a]atrim=0:$XF,asetpts=PTS-STARTPTS[h];[b]atrim=$L:$((L+XF)),asetpts=PTS-STARTPTS[t];[c]atrim=$XF:$L,asetpts=PTS-STARTPTS[bd];[t][h]acrossfade=d=$XF:c1=qsin:c2=qsin[m];[m][bd]concat=n=2:v=0:a=1[o]" -map "[o]" "$TMP/rift.wav"
lnorm "$TMP/rift.wav" "$OUT/ambience/amb_r1_scar_rift_loop.ogg" -24
echo done
