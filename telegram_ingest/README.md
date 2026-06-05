# Relaxation Telegram Ingest

This service keeps Telegram access on your server and writes media metadata to
Firestore. Use it only for movies/series you own or have permission to publish.

## Setup

You only need to provide your Telegram `API_ID`, `API_HASH`, and one login
session. The deploy script can build the server, deploy it to Cloud Run, and
save the final URL into Firestore automatically.

```powershell
cd D:\Relaxation\telegram_ingest
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env
```

Fill `.env`, then start:

```powershell
uvicorn main:app --reload --port 8088
```

First run will ask for Telegram login in the terminal and create a local
`.session` file. Keep that file private.

## Generate a Cloud Session

```powershell
cd D:\Relaxation\telegram_ingest
copy .env.example .env
# Fill TELEGRAM_API_ID and TELEGRAM_API_HASH in .env
python generate_session.py
```

Copy the printed `TELEGRAM_SESSION_STRING`.

## Deploy to Cloud Run

Install and login to Google Cloud CLI once, then run:

```powershell
cd D:\Relaxation
.\scripts\deploy_telethon_cloud_run.ps1 `
  -ApiId "YOUR_API_ID" `
  -ApiHash "YOUR_API_HASH" `
  -SessionString "YOUR_SESSION_STRING"
```

The script writes the Cloud Run URL to Firestore:

`app_settings/telegram.ingestBaseUrl`

After that, the admin panel only needs Telegram movie/episode links.

## Firestore Collection

Documents are written to `media`:

- `title`
- `type`: `movie` or `series`
- `genre`
- `quality`
- `description`
- `posterUrl`
- `posterBase64`
- `streamUrl`
- `downloadUrl`
- `telegramChat`
- `telegramMessageId`
- `createdAt`

## Import Example

```powershell
curl -X POST http://127.0.0.1:8088/import `
  -H "Content-Type: application/json" `
  -d "{\"chat\":\"@your_channel\",\"message_id\":123,\"title\":\"Movie Title\",\"type\":\"movie\",\"quality\":\"1080p\"}"
```

Or import from a public Telegram link. This is the preferred flow when your
source is a `https://t.me/...` post:

```powershell
curl -X POST http://127.0.0.1:8088/import `
  -H "Content-Type: application/json" `
  -d "{\"telegram_url\":\"https://t.me/MagicChineseSeriesPage/18499\",\"title\":\"Magic Chinese Series\",\"type\":\"series\",\"quality\":\"1080p\"}"
```

The service also accepts `https://t.me/s/...`, private `https://t.me/c/...`
links when the session account has access, `telegram.me/...`, and raw
`ChannelName/12345` values.

## Production Scale: Cache to Firebase Storage

For large public traffic, do not stream Telegram through Telethon for every
viewer. Cache each Telegram file once, then serve Android/Web users from
Firebase Storage or a CDN-backed storage bucket.

```powershell
$env:TELEGRAM_API_ID="YOUR_API_ID"
$env:TELEGRAM_API_HASH="YOUR_API_HASH"
$env:TELEGRAM_SESSION_STRING="YOUR_SESSION_STRING"
$env:FIREBASE_STORAGE_BUCKET="our-relaxation.firebasestorage.app"

python telegram_ingest/cache_to_storage.py `
  --service-account .\firebase-service-account.json `
  --telegram-url "https://t.me/Head_Over_Heels_mmsub/97" `
  --doc-id "FIRESTORE_MEDIA_DOC_ID"
```

The script uploads the video to Storage, creates a long-lived Firebase download
URL, and updates:

- `streamUrl`
- `downloadUrl`
- `watchLinks`
- `downloadLinks`
- `cachedStoragePath`
