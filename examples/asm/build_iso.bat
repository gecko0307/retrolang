@echo off
"../../rlc/rlc.exe" -o iso/PSX.EXE src/main.s
mkpsxiso -y iso.xml
