#!/bin/bash
# usage: run_hitch.sh NAME RES SECONDS [extra game args...]   (retries up to 3x if the engine crashes before STALL_SUM)
# Writes docs/qa/perf/raw/NAME.{log,csv}. Prints power/load context first.
export MSYS_NO_PATHCONV=1
G="C:/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe"
ROOT="C:/Users/Jonna/Documents/PA_wt_audit"
N=$1; RES=$2; SEC=$3; shift 3
R=$ROOT/docs/qa/perf/raw
for w in $(seq 1 60); do [ "$(powershell -c '(Get-CimInstance Win32_Battery).BatteryStatus')" = "2" ] && break; sleep 10; done   # wait for AC: DC power halves the CPU
echo "CTX $N battery=$(powershell -c '(Get-CimInstance Win32_Battery).BatteryStatus') godot_others=$(powershell -c '(Get-Process Godot* -ErrorAction SilentlyContinue).Count') freeMB=$(powershell -c '[int]((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1024)') cpu=$(powershell -c '(Get-CimInstance Win32_Processor).LoadPercentage')" | tee -a $R/context.txt
for try in 1 2 3; do
  timeout 590 "$G" --path "$ROOT/kingdom" --rendering-method forward_plus --resolution $RES -- --adult --skipintro --qa=res://tools_qa/perf/town_route.gd --seconds=$SEC --uncap --hitchcsv=$R/$N.csv "$@" > $R/$N.log 2>&1
  grep -q STALL_SUM $R/$N.log && break
  echo "crash/timeout try $try" | tee -a $R/context.txt
done
grep -E "STALL_SUM|ROUTE_SUM" $R/$N.log | cut -c1-200
