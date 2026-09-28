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
"%GODOT%" --path .
echo.
echo Game exited with code %ERRORLEVEL%. The log above shows why.
pause
