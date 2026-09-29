#!/bin/bash
# usage: render_trav.sh <glb> <out dir> ; renders every authored traversal clip with its prop
G="${GODOT:-/c/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe}"
K="$(cd "$(dirname "$0")/../../.." && pwd)"; GL="$1"; O="$2"; mkdir -p "$O"
r(){ timeout 60 "$G" --path "$K" -s tools/anim/free2/preview_rm.gd -- --glb="$GL" --out="$O/$1.png" --clip=$1 --prop=$2 --frames=${3:-8} --cell=${4:-1.3} --height=${5:-3.4} $6 2>&1 | grep -E "NOT FOUND"; }
r Ladder_Climb_Up ladder 8 1.3 3.4 "--to=0.97"
r Ladder_Climb_Down ladder 8 1.3 3.4 "--to=0.97"
r Wall_Climb_Up wall 8 1.3 3.4 "--to=0.97"
r Ledge_Hang_Idle ledge 6 1.2 3.0 "--to=0.97"
r Ledge_Shimmy_L ledge 8 1.3 3.0 "--to=0.97"
r Vault_Low vault 10 1.5 2.4
r Ride_Idle horse 4 2.4 2.6 "--to=0.97"
r Ride_Walk horse 6 2.4 2.6 "--to=0.97"
r Ride_Trot horse 6 2.4 2.6 "--to=0.97"
r Ride_Gallop horse 6 2.4 2.6 "--to=0.97"
