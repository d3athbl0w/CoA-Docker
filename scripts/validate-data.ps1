# ==============================================================================
# CoA-Docker Game Data Validator (PowerShell - Windows)
# ==============================================================================
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent $ScriptDir
$DataDir = Join-Path $RootDir "data"

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "Validating Game Data in $DataDir" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan

$Errors = 0

function Check-Dir {
    param(
        [string]$SubDir,
        [int]$MinFiles,
        [string]$Description
    )

    $Target = Join-Path $DataDir $SubDir
    if (-not (Test-Path $Target)) {
        Write-Host "[FAIL] Directory missing: $SubDir ($Description)" -ForegroundColor Red
        $script:Errors++
        return
    }

    $Files = Get-ChildItem -Path $Target -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne ".gitkeep" }
    $Count = ($Files | Measure-Object).Count

    if ($Count -lt $MinFiles) {
        Write-Host "[FAIL] $SubDir contains only $Count files (expected at least $MinFiles)" -ForegroundColor Red
        $script:Errors++
    } else {
        Write-Host "[OK]   $SubDir : $Count files found ($Description)" -ForegroundColor Green
    }
}

Check-Dir "dbc" 100 "Standard World of Warcraft 3.3.5a DBC files"
Check-Dir "dbc\Ascension" 3 "Conquest of Azeroth Ascension custom DBC files"
Check-Dir "maps" 1000 "Extracted terrain map tile files"
Check-Dir "vmaps" 5000 "Extracted vmap trees and building geometry"
Check-Dir "Cameras" 10 "Cinematic flyby camera definitions"

$MmapsDir = Join-Path $DataDir "mmaps"
if (Test-Path $MmapsDir) {
    $MmapsCount = (Get-ChildItem -Path $MmapsDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne ".gitkeep" } | Measure-Object).Count
    Write-Host "[INFO] mmaps : $MmapsCount files found (optional; navmeshes gracefully fall back when absent)" -ForegroundColor DarkCyan
}

Write-Host "==============================================================================" -ForegroundColor Cyan
if ($Errors -gt 0) {
    Write-Host "[ERROR] Game data validation failed ($Errors errors detected)!" -ForegroundColor Red
    Write-Host "Run '.\scripts\download-data.ps1' or '.\scripts\repack.ps1 download-data' to fetch required data." -ForegroundColor Yellow
    exit 1
} else {
    Write-Host "[SUCCESS] All required game data directories and files are present and valid." -ForegroundColor Green
    exit 0
}
