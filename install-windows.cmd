@echo off
rem Double-click to install Doc Reader on this PC (no administrator rights needed).
rem Options pass through, for example:  install-windows.cmd -NoStartup
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-windows.ps1" %*
echo.
pause
