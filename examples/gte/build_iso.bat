@echo off
"../../rlc/rlc.exe" -v -o iso/PSX.EXE src/main.r
mkpsxiso -y iso.xml
