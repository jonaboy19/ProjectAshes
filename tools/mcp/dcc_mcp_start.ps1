<#
Start the DCC-MCP back ends for this PC. Idempotent. Only touches processes it started (PIDs in Tools\dcc-mcp\run).
  -Blender            headless Blender 5.2 with the dcc-mcp-blender adapter (random port, registers with the gateway)
  -Godot <kingdomDir> headless Godot editor on that project (DCC-MCP Godot plugin + Godot LSP on port 6008 for Serena)
Claude Code reaches both through the gateway entry "dcc-mcp" in .mcp.json (http://127.0.0.1:9765/mcp).
#>
param(
  [switch]$Blender,
  [string]$Godot = "",
  [int]$LspPort = 6008,
  [string]$GodotExe = "C:\Users\Jonna\Downloads\Godot_v4.6.3-stable_win64\Godot_v4.6.3-stable_win64_console.exe",
  [string]$BlenderExe = "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
)
$ErrorActionPreference = "Stop"
$T = "C:\Users\Jonna\Tools\dcc-mcp"
$run = Join-Path $T "run"; $logs = Join-Path $T "logs"
New-Item -ItemType Directory -Force $run, $logs | Out-Null

function Test-Alive($pidFile) {
  if (-not (Test-Path $pidFile)) { return $false }
  $p = [int](Get-Content $pidFile -ErrorAction SilentlyContinue)
  return [bool](Get-Process -Id $p -ErrorAction SilentlyContinue)
}

if ($Blender) {
  $pf = Join-Path $run "blender.pid"
  if (Test-Alive $pf) { "blender MCP already running (pid $(Get-Content $pf))" }
  else {
    $env:PYTHONPATH = "$T\blender-site"
    $p = Start-Process -FilePath $BlenderExe -WindowStyle Hidden -PassThru -RedirectStandardOutput "$logs\blender_mcp.log" -RedirectStandardError "$logs\blender_mcp.err" `
      -ArgumentList @("--background","--factory-startup","--python","$T\blender-site\dcc_mcp_blender\blender_bootstrap.py")
    $p.Id | Set-Content $pf
    "started Blender MCP pid $($p.Id)"
  }
}

if ($Godot) {
  $proj = (Resolve-Path $Godot).Path
  if (-not (Test-Path "$proj\project.godot")) { throw "no project.godot in $proj" }
  $py = "$T\venv\Scripts\python.exe"; $cli = "$T\venv\Scripts\dcc-mcp-godot.exe"
  # 1. plugin installed + enabled in THIS checkout (opt-in; never commit the project.godot change, see tools/README_EXTERNAL_TOOLS.md)
  $enabled = (Test-Path "$proj\addons\dcc_mcp_godot\plugin.cfg") -and (Select-String -Path "$proj\project.godot" -SimpleMatch "dcc_mcp_godot/plugin.cfg" -Quiet)
  if (-not $enabled) {
    & $cli install $proj --dcc-path $GodotExe --python $py --yes --json | Out-Host
    $common = (git -C $proj rev-parse --git-common-dir) 2>$null
    if ($common) {
      $ex = Join-Path $common "info\exclude"; New-Item -ItemType Directory -Force (Split-Path $ex) | Out-Null
      foreach ($l in "kingdom/addons/dcc_mcp_godot/","kingdom/.dcc-mcp/") { if (-not (Select-String -Path $ex -SimpleMatch $l -Quiet -ErrorAction SilentlyContinue)) { Add-Content $ex $l } }
    }
  }
  # 2. adapter service (exactly "serve", no extra args)
  $sf = Join-Path $run "godot_serve.pid"
  if (-not (Test-Alive $sf)) {
    $p = Start-Process -FilePath $cli -ArgumentList "serve" -WindowStyle Hidden -PassThru -RedirectStandardOutput "$logs\godot_serve.log" -RedirectStandardError "$logs\godot_serve.err"
    $p.Id | Set-Content $sf; "started dcc-mcp-godot serve pid $($p.Id)"
  }
  # 3. headless editor with the plugin and the Godot LSP (Serena uses port $LspPort)
  $ef = Join-Path $run "godot_editor.pid"
  if (Test-Alive $ef) { "godot editor already running (pid $(Get-Content $ef))" }
  else {
    $p = Start-Process -FilePath $GodotExe -WorkingDirectory $proj -WindowStyle Hidden -PassThru -RedirectStandardOutput "$logs\godot_editor.log" -RedirectStandardError "$logs\godot_editor.err" `
      -ArgumentList @("--editor","--headless","--lsp-port","$LspPort","--path",".")
    $p.Id | Set-Content $ef; "started Godot editor pid $($p.Id) (first scan of the full project can take minutes)"
  }
  "wait for: $proj\.godot\dcc_mcp_godot_bootstrap.json (status ready) and TCP $LspPort"
}
