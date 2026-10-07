:: ==========================================
:: RETROLANG BUILD SCRIPT
:: Compiles RetroLang source code into a PlayStation 1 executable (PSX.EXE),
:: packs it into a standard CD-ROM image (BIN/CUE) via mkpsxiso,
:: and generates a binary sector index table (CU2) for PSIO hardware.
:: ==========================================

@echo off
setlocal enabledelayedexpansion

:: ==========================================
:: CONFIGURATION
:: ==========================================
set "RLC_LOCAL=../../rlc/rlc.exe"
set "MKPSXISO_LOCAL=../../mkpsxiso/mkpsxiso.exe"
set "CUE2CU2_SCRIPT=../scripts/cue2cu2.py"

set "SRC_FILE=src/main.s"
set "OUT_EXE=iso/PSX.EXE"
set "ISO_XML=iso.xml"

set "GAME_CUE=game.cue"

:: ==========================================
:: 1. CHECK RLC AVAILABILITY
:: ==========================================
set "RLC_CMD="
where rlc >nul 2>nul
if %ERRORLEVEL% equ 0 (
    echo [INFO] Using rlc from PATH
    set "RLC_CMD=rlc"
) else (
    if exist "%RLC_LOCAL%" (
        echo [INFO] Using %RLC_LOCAL%
        set "RLC_CMD=%RLC_LOCAL%"
    )
)
if not defined RLC_CMD (
    echo [ERROR] rlc.exe not found in PATH or in %RLC_LOCAL%
    exit /b 1
)

:: ==========================================
:: 2. COMPILE
:: ==========================================
echo [INFO] Compiling %OUT_EXE%...
"!RLC_CMD!" -o "%OUT_EXE%" "%SRC_FILE%"
if %ERRORLEVEL% neq 0 (
    exit /b %ERRORLEVEL%
)

:: ==========================================
:: 3. CHECK MKPSXISO AVAILABILITY
:: ==========================================
set "MKPSXISO_CMD="
where mkpsxiso >nul 2>nul
if %ERRORLEVEL% equ 0 (
    echo [INFO] Using mkpsxiso from PATH
    set "MKPSXISO_CMD=mkpsxiso"
) else (
    if exist "%MKPSXISO_LOCAL%" (
        echo [INFO] Using %MKPSXISO_LOCAL%
        set "MKPSXISO_CMD=%MKPSXISO_LOCAL%"
    )
)
if not defined MKPSXISO_CMD (
    echo [ERROR] mkpsxiso.exe not found in PATH or in %MKPSXISO_LOCAL%
    exit /b 1
)

:: ==========================================
:: 4. BUILD CD-ROM IMAGE
:: ==========================================
echo [INFO] Building CD-ROM image...
"!MKPSXISO_CMD!" -y "%ISO_XML%"
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Error building CD-ROM image
    exit /b %ERRORLEVEL%
)

:: ==========================================
:: 5. CHECK PYTHON AVAILABILITY
:: ==========================================
where python >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [WARNING] Python not installed, omitting CU2 generation
    echo [INFO] Generated game.bin, %GAME_CUE%
    exit /b 0
)

:: ==========================================
:: 6. GENERATE CU2
:: ==========================================
echo [INFO] Generating CU2 for PSIO...
python "%CUE2CU2_SCRIPT%" "%GAME_CUE%"
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Error generating CU2
    exit /b %ERRORLEVEL%
)
echo [INFO] Generated game.bin, %GAME_CUE%, game.cu2
