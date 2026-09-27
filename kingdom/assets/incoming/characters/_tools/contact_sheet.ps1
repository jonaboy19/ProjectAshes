# Composite tiles/results.jsonl into a labelled contact sheet.
# usage: powershell -File contact_sheet.ps1 <results.jsonl> <out.png> [cols] [title]
param([string]$Results, [string]$Out, [int]$Cols = 8, [string]$Title = "Rising Ashes - character candidates")
Add-Type -AssemblyName System.Drawing
$rows = Get-Content $Results | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json }
$tw = 240; $th = 360; $lab = 44; $top = 40
$n = $rows.Count; $r = [math]::Ceiling($n / $Cols)
$bmp = New-Object System.Drawing.Bitmap ($tw * $Cols), ($top + ($th + $lab) * $r)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::FromArgb(40, 40, 44))
$g.InterpolationMode = "HighQualityBicubic"; $g.TextRenderingHint = "AntiAlias"
$fT = New-Object System.Drawing.Font "Segoe UI", 16, ([System.Drawing.FontStyle]::Bold)
$f1 = New-Object System.Drawing.Font "Segoe UI", 9, ([System.Drawing.FontStyle]::Bold)
$f2 = New-Object System.Drawing.Font "Segoe UI", 8
$w = [System.Drawing.Brushes]::White; $gr = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(200, 210, 170))
$g.DrawString($Title, $fT, $w, 8, 6)
for ($i = 0; $i -lt $n; $i++) {
  $e = $rows[$i]; $x = ($i % $Cols) * $tw; $y = $top + [math]::Floor($i / $Cols) * ($th + $lab)
  if (Test-Path $e.out) { $im = [System.Drawing.Image]::FromFile($e.out); $g.DrawImage($im, $x, $y, $tw, $th); $im.Dispose() }
  $g.DrawString($e.label, $f1, $w, ($x + 4), ($y + $th + 2))
  $g.DrawString(("{0:N0} tris" -f $e.tris), $f2, $gr, ($x + 4), ($y + $th + 22))
}
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
Write-Output "saved $Out"
