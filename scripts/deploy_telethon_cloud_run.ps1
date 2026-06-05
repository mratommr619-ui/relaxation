param(
  [string]$ProjectId = "our-relaxation",
  [string]$Region = "asia-southeast1",
  [string]$ServiceName = "relaxation-telethon",
  [string]$ApiId,
  [string]$ApiHash,
  [string]$SessionString,
  [switch]$UseServiceAccountAuth
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$IngestDir = Join-Path $Root "telegram_ingest"
$ServiceAccount = Join-Path $Root "firebase-service-account.json"
$GcloudCandidates = @(
  "gcloud",
  "$env:LOCALAPPDATA\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd",
  "${env:ProgramFiles(x86)}\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd",
  "$env:ProgramFiles\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"
)
$Gcloud = $GcloudCandidates | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
if (-not $Gcloud) {
  throw "gcloud was not found. Install Google Cloud CLI, then rerun this script."
}

if (-not $ApiId) { $ApiId = Read-Host "Telegram API ID" }
if (-not $ApiHash) { $ApiHash = Read-Host "Telegram API HASH" }
if (-not $SessionString) { $SessionString = Read-Host "Telegram SESSION STRING" }
if (-not (Test-Path $ServiceAccount)) {
  throw "Firebase service account not found: $ServiceAccount"
}

if ($UseServiceAccountAuth) {
  & $Gcloud auth activate-service-account --key-file $ServiceAccount | Out-Host
} else {
  $activeAccount = & $Gcloud auth list --filter=status:ACTIVE --format="value(account)"
  if (-not $activeAccount) {
    throw "No active gcloud user account. Run: gcloud auth login"
  }
  Write-Host "Deploying with gcloud account: $activeAccount"
}
& $Gcloud config set project $ProjectId | Out-Host
& $Gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com | Out-Host

$Image = "gcr.io/$ProjectId/$ServiceName"
& $Gcloud builds submit $IngestDir --tag $Image | Out-Host

& $Gcloud secrets describe relaxation-firebase-service-account *> $null
if ($LASTEXITCODE -ne 0) {
  & $Gcloud secrets create relaxation-firebase-service-account --data-file $ServiceAccount | Out-Host
} else {
  & $Gcloud secrets versions add relaxation-firebase-service-account --data-file $ServiceAccount | Out-Host
}

& $Gcloud run deploy $ServiceName `
  --image $Image `
  --region $Region `
  --platform managed `
  --allow-unauthenticated `
  --memory 1Gi `
  --cpu 1 `
  --timeout 3600 `
  --set-env-vars "TELEGRAM_API_ID=$ApiId,TELEGRAM_API_HASH=$ApiHash,TELEGRAM_SESSION_STRING=$SessionString" `
  --set-secrets "FIREBASE_SERVICE_ACCOUNT=relaxation-firebase-service-account:latest" | Out-Host

$Url = & $Gcloud run services describe $ServiceName --region $Region --format "value(status.url)"
& $Gcloud run services update $ServiceName --region $Region --set-env-vars "PUBLIC_BASE_URL=$Url" | Out-Host

python -m pip install -q firebase-admin | Out-Host
python (Join-Path $PSScriptRoot "set_telethon_setting.py") --service-account $ServiceAccount --url $Url | Out-Host

Write-Host ""
Write-Host "Telethon server URL:"
Write-Host $Url
Write-Host ""
Write-Host "Saved into Firestore app_settings/telegram automatically."
