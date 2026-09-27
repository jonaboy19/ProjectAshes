@echo off
rem Opens the Rising Ashes (kingdom) project in the Godot 4.6 editor.
rem This window stays open and shows Godot's log, so if the editor closes you can read why.
set GODOT=%USERPROFILE%\Downloads\Godot_v4.6-stable_win64.exe\Godot_v4.6-stable_win64_console.exe
if not exist "%GODOT%" set GODOT=%USERPROFILE%\Downloads\Godot_v4.6-stable_win64_console.exe
if not exist "%GODOT%" (
  echo Godot 4.6 console exe not found. Edit the GODOT line in this file to point at it.
  pause
  exit /b 1
)
cd /d "%~dp0kingdom"
"%GODOT%" --path . -e
echo.
echo Godot exited with code %ERRORLEVEL%. The log above shows why.
pause
