# Screenshot & World Viewer Launcher
param(
    [string]$Mode = "open"
)

$OutDir = "C:\Users\Jonna\Documents\ProjectAshes\docs\img\actual_renders"
$HtmlViewer = "C:\Users\Jonna\Documents\ProjectAshes\docs\VALENCIOUS_WORLD_VIEWER.html"

if ($Mode -eq "open") {
    Write-Host "Opening Screenshot Folder & HTML Showcase..." -ForegroundColor Cyan
    explorer.exe $OutDir
    Start-Process "chrome.exe" "file:///$HtmlViewer"
} elseif ($Mode -eq "godot") {
    python "C:\Users\Jonna\Documents\ProjectAshes\tools\capture_screenshots.py" --godot town
} elseif ($Mode -eq "blender") {
    python "C:\Users\Jonna\Documents\ProjectAshes\tools\capture_screenshots.py" --blender
}
