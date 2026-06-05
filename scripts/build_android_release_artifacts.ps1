$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$OutDir = Join-Path $Root "build\app\outputs\relaxation-release"
New-Item -ItemType Directory -Force $OutDir | Out-Null

$Targets = @(
  @{ Abi = "arm64-v8a"; Target = "android-arm64"; Name = "relaxation-phone-tablet-tv-arm64-v8a-release.apk" },
  @{ Abi = "armeabi-v7a"; Target = "android-arm"; Name = "relaxation-phone-tablet-armeabi-v7a-release.apk" }
)

foreach ($item in $Targets) {
  $env:RELAXATION_ABIS = $item.Abi
  flutter build apk --release `
    --target-platform $item.Target `
    --obfuscate `
    --split-debug-info=build/app/outputs/symbols
  Copy-Item -Force `
    (Join-Path $Root "build\app\outputs\flutter-apk\app-release.apk") `
    (Join-Path $OutDir $item.Name)
}

Remove-Item Env:\RELAXATION_ABIS -ErrorAction SilentlyContinue

Write-Host "Android release artifacts:"
Get-ChildItem $OutDir | Select-Object Name,Length,LastWriteTime | Format-Table -AutoSize
