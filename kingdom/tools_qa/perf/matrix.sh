#!/bin/bash
# usage: matrix.sh REPS  -> interleaved legacy/fixed runs of the four hitch scenarios (A/B on one build via --perf-legacy)
R=${1:-3}
D="$(dirname "$0")"
for rep in $(seq 1 $R); do
  for sc in "A_stand_1440:2560x1440:--stand --approach=250 --after=70" "B_walk_1440:2560x1440:--walkk --approach=300 --after=15" "C_stand_1080:1920x1080:--stand --approach=250 --after=70" "D_t3d_stand_1440:2560x1440:--stand --approach=250 --after=70 --terrain_backend=terrain3d --world_macro=valencious"; do
    IFS=: read name res args <<< "$sc"
    for var in legacy fixed; do
      extra=""; [ $var = legacy ] && extra="--perf-legacy"
      $D/run_hitch.sh m_${name}_${var}_r$rep $res 100 --quality=high $args $extra > /dev/null 2>&1
    done
  done
done
echo MATRIX_DONE
