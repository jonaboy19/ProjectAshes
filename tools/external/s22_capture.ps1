# Passive capture from the S22 (adb serial R5CT849XNVF). Record only, sends NO input, safe while another agent plays.
#   powershell -File tools/external/s22_capture.ps1 -Kind video -Seconds 10 -Out C:\out\s22.mp4
#   powershell -File tools/external/s22_capture.ps1 -Kind trace -Seconds 10 -Out C:\out\s22.pftrace   # CPU sched, freq, gfx/frames
#   trace_processor_shell.exe -q query.sql trace.pftrace     (C:\Users\Jonna\Tools\perfetto\windows-amd64)
# Always forces adb to Tools' platform-tools copy so a different adb version does not restart the shared adb server.
param([ValidateSet("video", "trace")][string]$Kind = "video", [int]$Seconds = 10, [Parameter(Mandatory)][string]$Out, [string]$Serial = "R5CT849XNVF")
$env:ADB = "C:\Users\Jonna\platform-tools\adb.exe"; $env:PATH = "C:\Users\Jonna\platform-tools;" + $env:PATH
if ($Kind -eq "video") {
  & "C:\Users\Jonna\Tools\scrcpy\scrcpy-win64-v4.1\scrcpy.exe" -s $Serial --no-control --no-playback --no-window --time-limit $Seconds --record $Out
} else {
  & "C:\Users\Jonna\AppData\Local\Python\bin\python.exe" "C:\Users\Jonna\Tools\perfetto\record_android_trace.py" -s $Serial -t "${Seconds}s" -b 32mb -o $Out --no-open sched freq idle gfx view
}
