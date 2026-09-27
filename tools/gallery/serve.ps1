# Tiny static file server for the asset gallery (no Python/Node needed).
# Usage: powershell -ExecutionPolicy Bypass -File tools/gallery/serve.ps1 [-Port 8765]
# Then open http://localhost:8765/docs/asset_gallery/index.html
param([int]$Port = 8765)
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$types = @{ '.html'='text/html; charset=utf-8'; '.png'='image/png'; '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'; '.css'='text/css'; '.js'='text/javascript'; '.json'='application/json' }
$l = New-Object System.Net.HttpListener
$l.Prefixes.Add("http://localhost:$Port/")
$l.Start()
Write-Host "Serving $root on http://localhost:$Port/"
while ($l.IsListening) {
  $c = $l.GetContext()
  try {
    $rel = [Uri]::UnescapeDataString($c.Request.Url.AbsolutePath.TrimStart('/'))
    if ($rel -eq '') { $rel = 'docs/asset_gallery/index.html' }
    $path = [IO.Path]::GetFullPath((Join-Path $root $rel))
    if ($path.StartsWith($root) -and (Test-Path $path -PathType Leaf)) {
      $bytes = [IO.File]::ReadAllBytes($path)
      $ext = [IO.Path]::GetExtension($path).ToLower()
      $c.Response.ContentType = $(if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' })
      $c.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else { $c.Response.StatusCode = 404 }
  } catch { $c.Response.StatusCode = 500 }
  $c.Response.Close()
}
