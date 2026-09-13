#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Helper to attach directly to the interactive World Server Console
# ==============================================================================

echo "=============================================================================="
echo "Attaching to World Server console (ac-worldserver)..."
echo ""
echo "CRITICAL SAFETY HINT:"
echo "Do NOT press CTRL+C while attached! (It terminates the worldserver process)."
echo "To safely detach, press: CTRL+P followed immediately by CTRL+Q"
echo "=============================================================================="
echo ""

docker attach ac-worldserver
