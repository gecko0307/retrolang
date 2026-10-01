@echo off
"../../rlc/rlc.exe" -o iso/PSX.EXE gamepad.r
mkpsxiso -y iso.xml
