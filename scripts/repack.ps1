# ==============================================================================
# AzerothCore Conquest of Azeroth (CoA) Docker Repack CLI (Windows PowerShell)
# ==============================================================================
[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Command = "help",
    [Parameter(Position=1, ValueFromRemainingArguments=$true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent $ScriptDir

Set-Location $RootDir

function Show-Help {
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host "CoA-Docker Repack Management Script (Windows PowerShell)" -ForegroundColor Cyan
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host "Usage: .\scripts\repack.ps1 [command] [options]"
    Write-Host ""
    Write-Host "Setup & Data Commands:" -ForegroundColor Yellow
    Write-Host "  setup             Full first-time setup (submodule init + download data + validate)"
    Write-Host "  download-data     Download and extract required CoA game data (DBC, maps, vmaps)"
    Write-Host "  validate-data     Verify all required game data files and directories are present"
    Write-Host "  submodule:init    Initialize or update the AzerothCore git submodule"
    Write-Host ""
    Write-Host "Server Lifecycle Commands:" -ForegroundColor Yellow
    Write-Host "  build             Build server Docker images using BuildKit cache"
    Write-Host "  build:nocache     Rebuild images without cache"
    Write-Host "  up | start        Start all server services in background (-d)"
    Write-Host "  down | stop       Stop and remove containers (preserves database data)"
    Write-Host "  restart           Restart all running services"
    Write-Host "  status | ps       Show current container status and health"
    Write-Host "  logs [service]    View real-time logs (e.g. .\scripts\repack.ps1 logs ac-worldserver)"
    Write-Host "  console           Attach to interactive World Server console"
    Write-Host "  reset:data        [DESTRUCTIVE] Stop stack and delete database persistent volumes"
    Write-Host "  help              Display this help message"
    Write-Host "==============================================================================" -ForegroundColor Cyan
}

switch ($Command.ToLower()) {
    "setup" {
        Write-Host "[REPACK] Running complete first-time setup..." -ForegroundColor Cyan
        Write-Host "[REPACK] Step 1/3: Initializing Git submodules..." -ForegroundColor Yellow
        git submodule update --init --recursive
        Write-Host "[REPACK] Step 2/3: Downloading and extracting game data..." -ForegroundColor Yellow
        & (Join-Path $ScriptDir "download-data.ps1")
        Write-Host "[REPACK] Step 3/3: Validating game data..." -ForegroundColor Yellow
        & (Join-Path $ScriptDir "validate-data.ps1")
        Write-Host "==============================================================================" -ForegroundColor Green
        Write-Host "[SUCCESS] Setup complete! You can now run: .\scripts\repack.ps1 build" -ForegroundColor Green
        Write-Host "==============================================================================" -ForegroundColor Green
    }
    "download-data" {
        & (Join-Path $ScriptDir "download-data.ps1")
    }
    "validate-data" {
        & (Join-Path $ScriptDir "validate-data.ps1")
    }
    "submodule:init" {
        Write-Host "[REPACK] Initializing git submodules..." -ForegroundColor Cyan
        git submodule update --init --recursive
    }
    "build" {
        Write-Host "[REPACK] Building Docker images..." -ForegroundColor Cyan
        docker compose build
    }
    "build:nocache" {
        Write-Host "[REPACK] Rebuilding Docker images (no-cache)..." -ForegroundColor Cyan
        docker compose build --no-cache
    }
    { $_ -in "up", "start" } {
        Write-Host "[REPACK] Starting services in background..." -ForegroundColor Cyan
        docker compose up -d
    }
    { $_ -in "down", "stop" } {
        Write-Host "[REPACK] Stopping server services..." -ForegroundColor Cyan
        docker compose down
    }
    "restart" {
        Write-Host "[REPACK] Restarting server services..." -ForegroundColor Cyan
        docker compose restart
    }
    { $_ -in "status", "ps" } {
        docker compose ps
    }
    "logs" {
        if ($RemainingArgs) {
            docker compose logs -f $RemainingArgs
        } else {
            docker compose logs -f
        }
    }
    "console" {
        Write-Host "[REPACK] Attaching to World Server console..." -ForegroundColor Cyan
        Write-Host "[HINT] To detach without stopping the server, press: CTRL+P followed by CTRL+Q" -ForegroundColor Yellow
        docker attach ac-worldserver
    }
    "reset:data" {
        Write-Host "==============================================================================" -ForegroundColor Red
        Write-Host "[DANGER] THIS WILL PERMANENTLY ERASE ALL DATABASE TABLES, CHARACTERS, AND ACCOUNTS!" -ForegroundColor Red
        Write-Host "==============================================================================" -ForegroundColor Red
        $Confirm = Read-Host "Are you sure you want to delete persistent database volumes? (type 'yes' to proceed)"
        if ($Confirm -eq "yes") {
            Write-Host "[REPACK] Purging containers and persistent volumes..." -ForegroundColor Yellow
            docker compose down -v
            Write-Host "[REPACK] Volumes wiped." -ForegroundColor Green
        } else {
            Write-Host "[REPACK] Operation aborted. Data untouched." -ForegroundColor Yellow
        }
    }
    Default {
        Show-Help
    }
}
