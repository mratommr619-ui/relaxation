$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $Root "build\app\outputs\relaxation-release"
New-Item -ItemType Directory -Force $OutDir | Out-Null
Remove-Item (Join-Path $OutDir "*.apk") -Force -ErrorAction SilentlyContinue

$env:RELAXATION_ABIS = "arm64-v8a"
flutter build apk --release `
  --target-platform android-arm64 `
  --obfuscate `
  --split-debug-info=build/app/outputs/symbols

$ReleaseApk = Join-Path $Root "build\app\outputs\flutter-apk\app-release.apk"
$Names = @(
  "relaxation-phone-arm64-v8a-release.apk",
  "relaxation-tablet-arm64-v8a-release.apk",
  "relaxation-tv-arm64-v8a-release.apk"
)

foreach ($name in $Names) {
  Copy-Item -Force $ReleaseApk (Join-Path $OutDir $name)
}

Remove-Item Env:\RELAXATION_ABIS -ErrorAction SilentlyContinue

Write-Host "Android release artifacts:"
Get-ChildItem $OutDir | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize
