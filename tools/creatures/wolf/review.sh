#!/usr/bin/env bash
# usage: review.sh <glb> <rootmotion.json> <out_root> spec...   spec = clip:view:step[:cols:rows]
# Renders each spec (camera follows the root motion so a fixed grid shows foot sliding) and tiles numbered contact sheets.
glb=$1; export RC_ROOT=$(cygpath -m "$2"); root=$3; shift 3
export RC_FOLLOW=1; export RC_DIST=${RC_DIST:-1.7}
cd "$(dirname "$0")"
for spec in "$@"; do
  IFS=: read c v s cols rows <<< "$spec"
  ./rc.sh "$glb" $c $v $s 0 "$root" 640 ${cols:-4} ${rows:-3} | tail -1 | sed "s|^|$c $v |"
done
