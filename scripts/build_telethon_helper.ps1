param(
  [string]$Python = "python",
  [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$IngestDir = Join-Path $Root "telegram_ingest"
if (-not $OutputDir) {
  $OutputDir = Join-Path $Root "build\telethon_helper"
}

Push-Location $IngestDir
try {
  & $Python -m pip install --upgrade pip pyinstaller | Out-Host
  & $Python -m pip install -r requirements.txt | Out-Host
  & $Python -m PyInstaller `
    --clean `
    --onefile `
    --name telethon_helper `
    --distpath $OutputDir `
    desktop_entry.py | Out-Host
} finally {
  Pop-Location
}

Write-Host ""
Write-Host "Telethon helper built in:"
Write-Host $OutputDir
Write-Host ""
Write-Host "Copy telethon_helper(.exe) into your desktop app bundle data folder."
