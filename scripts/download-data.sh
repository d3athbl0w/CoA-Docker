#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# CoA-Docker Game Data Downloader & Integrator (Phase 2)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DOWNLOAD_URL="https://github.com/d3athbl0w/CoA-Docker/releases/download/master/Data.zip"
EXPECTED_SHA256="92ba82ebc19ba820e004e8d4d4b89ee7c415d9e4124d92f29312f0e049c61079"

DOWNLOAD_DIR="$ROOT_DIR/downloads"
DATA_DIR="$ROOT_DIR/data"
ARCHIVE_PATH="$DOWNLOAD_DIR/Data.zip"

mkdir -p "$DOWNLOAD_DIR" "$DATA_DIR"

echo "=============================================================================="
echo "Conquest of Azeroth (CoA) Game Data Downloader"
echo "=============================================================================="
echo "Source: $DOWNLOAD_URL"
echo "Target: $DATA_DIR"
echo "=============================================================================="

# Check if data is already extracted and valid
if [ -d "$DATA_DIR/dbc" ] && [ -d "$DATA_DIR/maps" ] && [ -d "$DATA_DIR/vmaps" ]; then
    DBC_COUNT=$(find "$DATA_DIR/dbc" -maxdepth 1 -type f | wc -l || true)
    MAPS_COUNT=$(find "$DATA_DIR/maps" -maxdepth 1 -type f | wc -l || true)
    if [ "$DBC_COUNT" -gt 50 ] && [ "$MAPS_COUNT" -gt 100 ]; then
        echo "[INFO] Valid game data already detected in $DATA_DIR ($DBC_COUNT DBCs, $MAPS_COUNT maps)."
        read -r -p "Do you want to re-download and overwrite existing data? (y/N): " REEXTRACT
        if [[ ! "$REEXTRACT" =~ ^[Yy]$ ]]; then
            echo "[INFO] Skipping download. Existing data retained."
            exit 0
        fi
    fi
fi

# Download archive if not present or hash mismatch
DOWNLOAD_NEEDED=true
if [ -f "$ARCHIVE_PATH" ]; then
    echo "[INFO] Existing archive detected at $ARCHIVE_PATH. Verifying integrity..."
    if command -v sha256sum &>/dev/null; then
        ACTUAL_SHA256=$(sha256sum "$ARCHIVE_PATH" | awk '{print $1}')
    elif command -v shasum &>/dev/null; then
        ACTUAL_SHA256=$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')
    else
        ACTUAL_SHA256=""
    fi

    if [ "$ACTUAL_SHA256" == "$EXPECTED_SHA256" ]; then
        echo "[INFO] Archive integrity verified (SHA256 match)."
        DOWNLOAD_NEEDED=false
    else
        echo "[WARN] Checksum mismatch. Re-downloading..."
    fi
fi

if [ "$DOWNLOAD_NEEDED" = true ]; then
    echo "[INFO] Downloading Data.zip (~466 MB)..."
    if command -v curl &>/dev/null; then
        curl -fL -o "$ARCHIVE_PATH" --progress-bar "$DOWNLOAD_URL"
    elif command -v wget &>/dev/null; then
        wget -O "$ARCHIVE_PATH" --show-progress "$DOWNLOAD_URL"
    else
        echo "[ERROR] Neither curl nor wget was found. Install one to continue." >&2
        exit 1
    fi

    echo "[INFO] Verifying download checksum..."
    if command -v sha256sum &>/dev/null; then
        ACTUAL_SHA256=$(sha256sum "$ARCHIVE_PATH" | awk '{print $1}')
    elif command -v shasum &>/dev/null; then
        ACTUAL_SHA256=$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')
    else
        ACTUAL_SHA256="$EXPECTED_SHA256"
    fi

    if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
        echo "[ERROR] Checksum verification failed!" >&2
        echo "Expected: $EXPECTED_SHA256" >&2
        echo "Actual:   $ACTUAL_SHA256" >&2
        exit 1
    fi
    echo "[INFO] Download checksum valid."
fi

echo "[INFO] Extracting game data into $DATA_DIR..."
if command -v unzip &>/dev/null; then
    unzip -q -o "$ARCHIVE_PATH" -d "$DATA_DIR"
elif command -v tar &>/dev/null; then
    tar -xf "$ARCHIVE_PATH" -C "$DATA_DIR"
else
    echo "[ERROR] Neither unzip nor tar was found to extract archive." >&2
    exit 1
fi

echo "[INFO] Extraction complete. Validating extracted files..."
"$SCRIPT_DIR/validate-data.sh"
