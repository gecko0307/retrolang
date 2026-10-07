#!/bin/bash

# ==========================================
# RETROLANG BUILD SCRIPT
# Compiles RetroLang source code into a PlayStation 1 executable (PSX.EXE),
# packs it into a standard CD-ROM image (BIN/CUE) via mkpsxiso,
# and generates a binary sector index table (CU2) for PSIO hardware.
# ==========================================

# ==========================================
# CONFIGURATION (Set paths and filenames here)
# ==========================================
RLC_LOCAL="../../rlc/rlc"
MKPSXISO_LOCAL="../../mkpsxiso/mkpsxiso"
CUE2CU2_SCRIPT="../scripts/cue2cu2.py"

SRC_FILE="src/main.s"
OUT_EXE="iso/PSX.EXE"
ISO_XML="iso.xml"

GAME_CUE="game.cue"

# ==========================================
# 1. CHECK RLC AVAILABILITY
# ==========================================
RLC_CMD=""

if command -v rlc >/dev/null 2>&1; then
    echo "[INFO] Using rlc from PATH"
    RLC_CMD="rlc"
elif [ -f "$RLC_LOCAL" ]; then
    echo "[INFO] Using $RLC_LOCAL"
    RLC_CMD="$RLC_LOCAL"
fi

if [ -z "$RLC_CMD" ]; then
    echo "[ERROR] rlc not found in PATH or in $RLC_LOCAL"
    exit 1
fi

# ==========================================
# 2. COMPILE
# ==========================================
echo "[INFO] Compiling $OUT_EXE..."
"$RLC_CMD" -o "$OUT_EXE" "$SRC_FILE"
if [ $? -ne 0 ]; then
    exit $?
fi

# ==========================================
# 3. CHECK MKPSXISO AVAILABILITY
# ==========================================
MKPSXISO_CMD=""

if command -v mkpsxiso >/dev/null 2>&1; then
    MKPSXISO_CMD="mkpsxiso"
elif [ -f "$MKPSXISO_LOCAL" ]; then
    MKPSXISO_CMD="$MKPSXISO_LOCAL"
fi

if [ -z "$MKPSXISO_CMD" ]; then
    echo "[WARNING] mkpsxiso not found, omitting CD-ROM image generation"
    exit 0
fi

# ==========================================
# 4. BUILD CD-ROM IMAGE
# ==========================================
echo "[INFO] Building CD-ROM image..."
"$MKPSXISO_CMD" -y "$ISO_XML"
if [ $? -ne 0 ]; then
    echo "[ERROR] Error building CD-ROM image"
    exit $?
fi

# ==========================================
# 5. CHECK PYTHON AVAILABILITY
# ==========================================
PYTHON_CMD=""
if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_CMD="python"
fi

if [ -z "$PYTHON_CMD" ]; then
    echo "[WARNING] Python not installed, omitting CU2 generation"
    echo "[INFO] Generated game.bin, $GAME_CUE"
    exit 0
fi

# ==========================================
# 6. GENERATE CU2
# ==========================================
echo "[INFO] Generating CU2 for PSIO..."
$PYTHON_CMD "$CUE2CU2_SCRIPT" "$GAME_CUE"
if [ $? -ne 0 ]; then
    echo "[ERROR] Error generating CU2"
    exit $?
fi

echo "[INFO] Generated game.bin, $GAME_CUE, game.cu2"
