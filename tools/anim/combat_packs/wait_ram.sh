#!/usr/bin/env bash
# Block until Windows reports at least ${1:-1500} MB available (shared 16 GB laptop).
need=${1:-1500}
while true; do
  a=$(powershell -NoProfile -c "(Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes" | tr -d '\r ')
  [ "${a:-0}" -ge "$need" ] && { echo "RAM ok: $a MB"; exit 0; }
  sleep 20
done
