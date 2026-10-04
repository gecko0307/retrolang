@echo off
"../../rlc/rlc.exe" -o iso/PSX.EXE src/main.r
if %ERRORLEVEL% neq 0 (exit /b %ERRORLEVEL%)
mkpsxiso -y iso.xml
