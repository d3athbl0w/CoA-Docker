#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# AzerothCore Conquest of Azeroth (CoA) Docker Repack CLI
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"

function show_help() {
    cat <<EOF
==============================================================================
CoA-Docker Repack Management Script
==============================================================================
Usage: ./scripts/repack.sh [command] [options]

Commands:
  build             Build server Docker images using BuildKit cache
  build:nocache     Rebuild images without cache
  up | start        Start all server services in background (-d)
  down | stop       Stop and remove containers (preserves database data)
  restart           Restart all running services
  status | ps       Show current container status and health
  logs [service]    View real-time logs (e.g. ./scripts/repack.sh logs ac-worldserver)
  console           Attach to interactive World Server console
  submodule:init    Initialize or update the AzerothCore git submodule
  reset:data        [DESTRUCTIVE] Stop stack and delete database persistent volumes
  help              Display this help message
==============================================================================
EOF
}

COMMAND="${1:-help}"

case "$COMMAND" in
    build)
        echo "[REPACK] Building Docker images..."
        docker compose build
        ;;
    build:nocache)
        echo "[REPACK] Rebuilding Docker images (no-cache)..."
        docker compose build --no-cache
        ;;
    up|start)
        echo "[REPACK] Starting services in background..."
        docker compose up -d
        ;;
    down|stop)
        echo "[REPACK] Stopping server services..."
        docker compose down
        ;;
    restart)
        echo "[REPACK] Restarting server services..."
        docker compose restart
        ;;
    status|ps)
        docker compose ps
        ;;
    logs)
        shift || true
        docker compose logs -f "$@"
        ;;
    console)
        echo "[REPACK] Attaching to World Server console..."
        echo "[HINT] To detach without stopping the server, press: CTRL+P followed by CTRL+Q"
        docker attach ac-worldserver
        ;;
    submodule:init)
        echo "[REPACK] Initializing git submodules..."
        git submodule update --init --recursive
        ;;
    reset:data)
        echo "=============================================================================="
        echo "[DANGER] THIS WILL PERMANENTLY ERASE ALL DATABASE TABLES, CHARACTERS, AND ACCOUNTS!"
        echo "=============================================================================="
        read -r -p "Are you sure you want to delete persistent database volumes? (type 'yes' to proceed): " CONFIRM
        if [ "$CONFIRM" == "yes" ]; then
            echo "[REPACK] Purging containers and persistent volumes..."
            docker compose down -v
            echo "[REPACK] Volumes wiped."
        else
            echo "[REPACK] Operation aborted. Data untouched."
        fi
        ;;
    help|*)
        show_help
        ;;
esac
