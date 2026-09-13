#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# CoA-Docker Game Data Validator (Phase 2)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$ROOT_DIR/data"

echo "=============================================================================="
echo "Validating Game Data in $DATA_DIR"
echo "=============================================================================="

ERRORS=0

function check_dir() {
    local DIR_NAME="$1"
    local MIN_FILES="$2"
    local DESCRIPTION="$3"
    local TARGET="$DATA_DIR/$DIR_NAME"

    if [ ! -d "$TARGET" ]; then
        echo -e "[\033[31mFAIL\033[0m] Directory missing: $DIR_NAME ($DESCRIPTION)"
        ERRORS=$((ERRORS + 1))
        return
    fi

    local COUNT
    COUNT=$(find "$TARGET" -type f ! -name ".gitkeep" | wc -l || true)
    if [ "$COUNT" -lt "$MIN_FILES" ]; then
        echo -e "[\033[31mFAIL\033[0m] $DIR_NAME contains only $COUNT files (expected at least $MIN_FILES)"
        ERRORS=$((ERRORS + 1))
    else
        echo -e "[\033[32mOK\033[0m]   $DIR_NAME: $COUNT files found ($DESCRIPTION)"
    fi
}

check_dir "dbc" 100 "Standard World of Warcraft 3.3.5a DBC files"
check_dir "dbc/Ascension" 3 "Conquest of Azeroth Ascension custom DBC files"
check_dir "maps" 1000 "Extracted terrain map tile files"
check_dir "vmaps" 5000 "Extracted vmap trees and building geometry"
check_dir "Cameras" 10 "Cinematic flyby camera definitions"

if [ -d "$DATA_DIR/mmaps" ]; then
    MMAP_COUNT=$(find "$DATA_DIR/mmaps" -type f ! -name ".gitkeep" | wc -l || true)
    echo -e "[\033[34mINFO\033[0m] mmaps: $MMAP_COUNT files found (optional; navmeshes auto-fall back when absent)"
fi

echo "=============================================================================="
if [ "$ERRORS" -gt 0 ]; then
    echo -e "\033[31m[ERROR] Game data validation failed ($ERRORS errors detected)!\033[0m"
    echo "Run './scripts/download-data.sh' or './scripts/repack.sh download-data' to fetch required data."
    exit 1
else
    echo -e "\033[32m[SUCCESS] All required game data directories and files are present and valid.\033[0m"
    exit 0
fi
