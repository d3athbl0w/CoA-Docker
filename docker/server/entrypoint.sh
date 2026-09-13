#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# AzerothCore Conquest of Azeroth (CoA) Docker Container Entrypoint
# ==============================================================================

CONF_DIR="${AC_CONF_DIR:-/azerothcore/env/dist/etc}"
LOGS_DIR="${AC_LOGS_DIR:-/azerothcore/env/dist/logs}"
DATA_DIR="${AC_DATA_DIR:-/azerothcore/env/dist/data}"
TEMP_DIR="${AC_TEMP_DIR:-/azerothcore/env/dist/temp}"

# Ensure required directories exist
mkdir -p "$CONF_DIR" "$LOGS_DIR" "$DATA_DIR" "$TEMP_DIR" 2>/dev/null || true

# Test write permissions
if ! touch "$CONF_DIR/.perm_test" 2>/dev/null || ! touch "$LOGS_DIR/.perm_test" 2>/dev/null; then
    cat <<'EOF'
================================================================================
[WARNING] Permission check failed!
The current container user cannot write to the configuration directory:
  - Config: $CONF_DIR
  - Logs:   $LOGS_DIR

If running on Linux, verify the host directory permissions match the container UID/GID:
  sudo chown -R 1000:1000 env/etc env/logs
================================================================================
EOF
else
    rm -f "$CONF_DIR/.perm_test" "$LOGS_DIR/.perm_test" 2>/dev/null || true
fi

# Populate reference configuration templates if the directory is empty or missing them
if [ -d "/azerothcore/env/ref/etc" ]; then
    cp -rn /azerothcore/env/ref/etc/* "$CONF_DIR/" 2>/dev/null || true
fi

# Component-specific bootstrapping
ACORE_COMPONENT="${ACORE_COMPONENT:-unknown}"

if [ "$ACORE_COMPONENT" != "unknown" ]; then
    CONF="$CONF_DIR/$ACORE_COMPONENT.conf"
    CONF_DIST="$CONF_DIR/$ACORE_COMPONENT.conf.dist"

    # If the active .conf does not exist, initialize it from .conf.dist
    if [ ! -f "$CONF" ]; then
        if [ -f "$CONF_DIST" ]; then
            echo "[ENTRYPOINT] Initializing default configuration: $CONF"
            cp "$CONF_DIST" "$CONF"
        else
            echo "[ENTRYPOINT] Creating empty configuration: $CONF"
            touch "$CONF"
        fi
    fi
fi

echo "[ENTRYPOINT] Starting AzerothCore $ACORE_COMPONENT..."
exec "$@"
