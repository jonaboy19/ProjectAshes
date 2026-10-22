# Capture one frame of a Godot run with RenderDoc 1.46 and print draw-call stats (local PC only, needs a GPU).
#   powershell -File tools/external/renderdoc_godot.ps1 -Project C:\path\to\project [-Script x.gd -ScriptArgs "a.glb b.glb"] -Out C:\out\dir [-Wait 8]
# Uses D3D12 because the Vulkan layer is not registered (registering it edits HKCU; not done). Mobile renderer like the phone build.
# Launches the NON-console Godot exe (the console exe is a wrapper process RenderDoc would not hook).
param([Parameter(Mandatory)][string]$Project, [Parameter(Mandatory)][string]$Out, [string]$Script = "", [string]$ScriptArgs = "", [int]$Wait = 8,
      [string]$Driver = "d3d12", [string]$Godot = "C:\Users\Jonna\Downloads\Godot_v4.6.3-stable_win64\Godot_v4.6.3-stable_win64.exe")
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$args2 = "--path `"$Project`" --rendering-driver $Driver --rendering-method mobile"
if ($Script) { $args2 += " -s `"$Script`" -- $ScriptArgs" }
$env:RD_APP = $Godot; $env:RD_ARGS = $args2; $env:RD_OUT = $Out; $env:RD_WAIT = "$Wait"
New-Item -ItemType Directory -Force $Out | Out-Null
$q = Start-Process "C:\Users\Jonna\Tools\renderdoc\RenderDoc_1.46_64\qrenderdoc.exe" -ArgumentList "--python", "`"$here\renderdoc_capture.py`"" -PassThru
$t0 = Get-Date
while (-not (Test-Path "$Out\drawcalls.json") -and ((Get-Date) - $t0).TotalSeconds -lt 120 -and -not $q.HasExited) { Start-Sleep 2 }
if (Test-Path "$Out\app.pid") { Stop-Process -Id ([int](Get-Content "$Out\app.pid")) -Force -ErrorAction SilentlyContinue }  # only the Godot we launched
if (-not $q.HasExited) { Stop-Process -Id $q.Id -Force }
if (Test-Path "$Out\drawcalls.json") { Get-Content "$Out\drawcalls.json" } else { Get-Content "$Out\capture_log.txt" }
