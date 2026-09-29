# ONE COMMAND: phone video -> UAL-skeleton GLB clip + review sheets.
#   powershell -File video_to_clip.ps1 <video.mp4> <ClipName> [-Loop] [-Fps 30] [extra options for video_to_clip.py, e.g. --root none --face travel --start 1.0 --end 4.5]
# Output: kingdom/assets/incoming/animations_video/<ClipName>/UAL_Video_<ClipName>.glb (+ .clips.json)
#         docs/anim/advanced/video_mocap/out/<ClipName>/sheet_001.png ...
# First time: powershell -File setup.ps1   (venv + pose model, ~1 GB, once)
param(
  [Parameter(Mandatory = $true, Position = 0)][string]$Video,
  [Parameter(Mandatory = $true, Position = 1)][string]$ClipName,
  [switch]$Loop,
  [double]$Fps = 30,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$py = $null
if ($env:VIDEO_MOCAP_PY -and (Test-Path $env:VIDEO_MOCAP_PY)) { $py = $env:VIDEO_MOCAP_PY }
elseif (Test-Path "$here\.venv\Scripts\python.exe") { $py = "$here\.venv\Scripts\python.exe" }
else {   # git worktree: reuse the main checkout's venv
  $common = (& git -C $here rev-parse --git-common-dir 2>$null)
  if ($common) {
    $main = Split-Path -Parent ([IO.Path]::GetFullPath([IO.Path]::Combine($here, $common)))
    $cand = "$main\kingdom\tools\anim\video_mocap\.venv\Scripts\python.exe"
    if (Test-Path $cand) { $py = $cand }
  }
}
if (-not $py) {
  Write-Error "No python venv found. Run once:  powershell -File `"$here\setup.ps1`"  (or set env VIDEO_MOCAP_PY to a python with mediapipe, opencv, numpy, matplotlib)"
  exit 2
}
if (-not (Test-Path $Video)) { Write-Error "Video not found: $Video"; exit 2 }
$argv = @("$here\video_to_clip.py", (Resolve-Path $Video).Path, $ClipName, "--fps", $Fps)
if ($Loop) { $argv += "--loop" }
if ($Rest) { $argv += $Rest }
& $py @argv
exit $LASTEXITCODE
