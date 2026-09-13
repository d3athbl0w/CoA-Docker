# ==============================================================================
# CoA-Docker Game Data Downloader & Integrator (PowerShell - Windows)
# ==============================================================================
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir = Split-Path -Parent $ScriptDir

$DownloadUrl = "https://github.com/d3athbl0w/CoA-Docker/releases/download/master/Data.zip"
$ExpectedSha256 = "92BA82EBC19BA820E004E8D4D4B89EE7C415D9E4124D92F29312F0E049C61079"

$DownloadDir = Join-Path $RootDir "downloads"
$DataDir = Join-Path $RootDir "data"
$ArchivePath = Join-Path $DownloadDir "Data.zip"

if (-not (Test-Path $DownloadDir)) {
    New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
}
if (-not (Test-Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
}

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "Conquest of Azeroth (CoA) Game Data Downloader (Windows PowerShell)" -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "Source: $DownloadUrl"
Write-Host "Target: $DataDir"
Write-Host "=============================================================================="

# Check if data already exists
$DbcDir = Join-Path $DataDir "dbc"
$MapsDir = Join-Path $DataDir "maps"
$VmapsDir = Join-Path $DataDir "vmaps"

if (-not $Force -and (Test-Path $DbcDir) -and (Test-Path $MapsDir) -and (Test-Path $VmapsDir)) {
    $DbcCount = (Get-ChildItem -Path $DbcDir -File -ErrorAction SilentlyContinue).Count
    $MapsCount = (Get-ChildItem -Path $MapsDir -File -ErrorAction SilentlyContinue).Count
    if ($DbcCount -gt 50 -and $MapsCount -gt 100) {
        Write-Host "[INFO] Valid game data already detected ($DbcCount DBCs, $MapsCount maps)." -ForegroundColor Green
        $Confirm = Read-Host "Do you want to re-download and overwrite existing data? (y/N)"
        if ($Confirm -notmatch "^[Yy]$") {
            Write-Host "[INFO] Skipping download. Existing data preserved." -ForegroundColor Green
            exit 0
        }
    }
}

# Check if local archive exists and verify hash
$DownloadNeeded = $true
if (Test-Path $ArchivePath) {
    Write-Host "[INFO] Verifying checksum of existing archive..." -ForegroundColor Yellow
    $ActualHash = (Get-FileHash -Path $ArchivePath -Algorithm SHA256).Hash
    if ($ActualHash -eq $ExpectedSha256) {
        Write-Host "[INFO] Local archive verified (SHA256 matched)." -ForegroundColor Green
        $DownloadNeeded = $false
    } else {
        Write-Host "[WARN] Local archive checksum mismatch. Re-downloading..." -ForegroundColor Yellow
    }
}

if ($DownloadNeeded) {
    Write-Host "[INFO] Downloading Data.zip (~466 MB)..." -ForegroundColor Cyan
    try {
        # Use curl.exe if available (much faster in Windows Terminal), fallback to Invoke-WebRequest
        if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
            & curl.exe -fL -o $ArchivePath --progress-bar $DownloadUrl
        } else {
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $ArchivePath
        }
    } catch {
        Write-Error "Failed to download Data.zip: $_"
        exit 1
    }

    Write-Host "[INFO] Verifying download checksum..." -ForegroundColor Yellow
    $ActualHash = (Get-FileHash -Path $ArchivePath -Algorithm SHA256).Hash
    if ($ActualHash -ne $ExpectedSha256) {
        Write-Error "Download corrupt! Expected: $ExpectedSha256, Actual: $ActualHash"
        exit 1
    }
    Write-Host "[INFO] Checksum verification passed." -ForegroundColor Green
}

Write-Host "[INFO] Extracting archive to $DataDir..." -ForegroundColor Cyan
if (Get-Command tar.exe -ErrorAction SilentlyContinue) {
    & tar.exe -xf $ArchivePath -C $DataDir
} else {
    Expand-Archive -Path $ArchivePath -DestinationPath $DataDir -Force
}

Write-Host "[INFO] Extraction complete. Running validation..." -ForegroundColor Green
& (Join-Path $ScriptDir "validate-data.ps1")
