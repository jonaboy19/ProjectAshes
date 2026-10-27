@echo off
rem Runs Rising Ashes directly (no editor). The log stays visible if it closes.
rem Godot 4.6.3 first: 4.6.0 crashed on every quit (docs/qa/stability.md).
set GODOT=%USERPROFILE%\Downloads\Godot_v4.6.3-stable_win64\Godot_v4.6.3-stable_win64_console.exe
if not exist "%GODOT%" set GODOT=%USERPROFILE%\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe
if not exist "%GODOT%" set GODOT=%USERPROFILE%\Downloads\Godot_v4.6-stable_win64_console.exe
if not exist "%GODOT%" (
  echo Godot 4.6 console exe not found. Edit the GODOT line in this file to point at it.
  pause
  exit /b 1
)
cd /d "%~dp0kingdom"
rem World: Terrain3D ground + the real-elevation world (W6, docs/world/REAL_WORLD.md). The pc profile keeps FSR1+TAA with Terrain3D.
"%GODOT%" --path . -- --terrain_backend=terrain3d --world_macro=real
echo.
echo Game exited with code %ERRORLEVEL%. The log above shows why.
pause
