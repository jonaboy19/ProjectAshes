# One-time setup: venv next to the scripts (gitignored, ~1 GB with mediapipe/opencv) + pose model (30 MB, Apache-2.0).
# usage:  powershell -File setup.ps1 [-Python C:\path\to\python.exe]
param([string]$Python = "python")
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
& $Python -m venv "$here\.venv"
& "$here\.venv\Scripts\python.exe" -m pip install -r "$here\requirements.txt"
New-Item -ItemType Directory -Force "$here\models" | Out-Null
$m = "$here\models\pose_landmarker_heavy.task"
if (-not (Test-Path $m)) {
  Invoke-WebRequest "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task" -OutFile $m
}
Write-Host "ready"
