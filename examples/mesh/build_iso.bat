@echo off
setlocal enabledelayedexpansion

:: Check RLC availability
where rlc >nul 2>nul
if %ERRORLEVEL% equ 0 (
    set "RLC_CMD=rlc"
) else (
    if exist "../../rlc/rlc.exe" (
        set "RLC_CMD=../../rlc/rlc.exe"
    )
)
if not defined RLC_CMD (
    echo [ERROR] rlc.exe not found in PATH or in ../../rlc/
    exit /b 1
)

:: Compile
"!RLC_CMD!" -o iso/PSX.EXE src/main.r
if %ERRORLEVEL% neq 0 (
    exit /b %ERRORLEVEL%
)

:: Check mkpsxiso availability
where mkpsxiso >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [WARNING] mkpsxiso not found, omitting CD-ROM image generation
    exit /b %ERRORLEVEL%
)

:: Build image
echo Building CD-ROM image...
mkpsxiso -y iso.xml

:: Check Python availability
where python >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [WARNING] Python not installed, omitting CU2 generation
    echo Generated game.bin, game.cue
    exit /b %ERRORLEVEL%
)

:: Generating CU2
echo Generating CU2 for PSIO...
python cue2cu2.py game.cue
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Error generating CU2
    exit /b %ERRORLEVEL%
)
echo Generated game.bin, game.cue, game.cu2
