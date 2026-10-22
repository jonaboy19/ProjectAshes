# Stop only what dcc_mcp_start.ps1 started (PID files). Never kills other Godot/Blender processes.
$run = "C:\Users\Jonna\Tools\dcc-mcp\run"
foreach ($f in "godot_editor","godot_serve","blender") {
  $pf = Join-Path $run "$f.pid"
  if (Test-Path $pf) {
    $id = [int](Get-Content $pf)
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
    if ($p) {
      # the Godot launcher exe can spawn a child console exe; stop the tree under that pid only
      Get-CimInstance Win32_Process -Filter "ParentProcessId=$id" | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
      Stop-Process -Id $id -Force -ErrorAction SilentlyContinue; "stopped $f ($id)"
    }
    Remove-Item $pf
  }
}
