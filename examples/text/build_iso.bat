@echo off
"../../rlc/rlc.exe" -o iso/PSX.EXE src/main.r
mkpsxiso -y iso.xml
