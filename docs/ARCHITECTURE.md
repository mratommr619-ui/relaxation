# Relaxation Architecture

Relaxation is split into three parts:

1. Flutter user app
   - Android/iOS/web capable.
   - Reads Firestore collection `media`.
   - Supports poster images from either `posterUrl` or `posterBase64`.
   - Opens `streamUrl` in the built-in video player.
   - Opens `downloadUrl` externally.

2. Relaxation Studio admin web app
   - Folder: `admin_panel`.
   - Builds as both web and Android.
   - Writes documents to Firestore collection `media`.
   - Uses Firebase Auth email/password.
   - Firestore rules require a Firebase custom claim: `admin == true`.

3. Telegram ingest service
   - Folder: `telegram_ingest`.
   - Python FastAPI + Telethon.
   - Keeps Telegram session on the server.
   - Creates stream/download proxy URLs.
   - Writes media metadata to Firestore.

Only publish content you own or have permission to distribute.

## Firestore `media` Document

```json
{
  "title": "Movie Title",
  "type": "movie",
  "genre": "Action",
  "quality": "1080p",
  "description": "Short description",
  "posterUrl": "https://example.com/poster.jpg",
  "posterBase64": "",
  "telegramUrl": "https://t.me/MagicChineseSeriesPage/18499",
  "streamUrl": "https://your-ingest-service/stream/channel/123",
  "downloadUrl": "https://your-ingest-service/download/channel/123",
  "watchLinks": [
    {"label": "Server 1", "url": "https://your-ingest-service/stream/channel/123"}
  ],
  "downloadLinks": [
    {"label": "Server 1", "url": "https://your-ingest-service/download/channel/123"}
  ],
  "telegramChat": "@channel",
  "telegramMessageId": 123,
  "createdAt": "server timestamp"
}
```

## Firebase Setup

Install tools:

```powershell
dart pub global activate flutterfire_cli
npm install -g firebase-tools
firebase login
```

Configure the user app:

```powershell
cd D:\Relaxation
flutterfire configure --project your-firebase-project-id
```

Configure the admin web app:

```powershell
cd D:\Relaxation\admin_panel
flutterfire configure --project your-firebase-project-id --platforms web
```

Configure the admin Android app too:

```powershell
cd D:\Relaxation\admin_panel
flutterfire configure --project your-firebase-project-id --platforms android,web --android-package-name com.mratom.relaxation.studio
```

Copy `.firebaserc.example` to `.firebaserc`, then replace project and hosting site names.

Build and deploy:

```powershell
cd D:\Relaxation
flutter build web
cd admin_panel
flutter build web
cd ..
firebase deploy --only firestore,hosting
```

Build the Studio Android APK:

```powershell
cd D:\Relaxation\admin_panel
flutter build apk --debug
```

## Public Telegram Links As Input

For a public post link like:

```text
https://t.me/MagicChineseSeriesPage/18499
```

Relaxation Studio parses:

- channel: `MagicChineseSeriesPage`
- message ID: `18499`

Then it can generate:

- `https://your-ingest-service.example.com/stream/MagicChineseSeriesPage/18499`
- `https://your-ingest-service.example.com/download/MagicChineseSeriesPage/18499`

The Flutter app should play/download through those service URLs. A raw `t.me`
post URL is a Telegram web page, not a stable direct video file URL.

So the admin workflow is:

1. Paste the `https://t.me/.../...` link into Relaxation Studio.
2. Set the ingest service base URL.
3. Click the parse button or just press Save.
4. Studio stores the original `telegramUrl` and generated stream/download proxy URLs.

Supported inputs:

- `https://t.me/MagicChineseSeriesPage/18499`
- `https://t.me/s/MagicChineseSeriesPage/18499`
- `https://t.me/c/1234567890/18499`
- `https://telegram.me/MagicChineseSeriesPage/18499`
- `MagicChineseSeriesPage/18499`

## Admin Claim

Create an email/password user in Firebase Authentication, then grant admin:

```powershell
pip install firebase-admin
python scripts\set_admin_claim.py --service-account path\to\service-account.json --email admin@example.com
```

## Access / Trial / License

User app flow:

1. User creates/logs in with Gmail email/password through Firebase Auth.
2. App calculates a device hash and creates/reads `access_devices/{deviceHash}`.
3. New devices get `trialExpiresAt = now + 3 days`.
4. If the same device signs in with another Gmail, the same device document is reused, so the trial does not restart.
5. When access expires, Watch and Download buttons show the license key dialog.
6. License keys live in `license_keys/{KEY}` and are created from Relaxation Studio.

Important: device IDs are best-effort on consumer platforms. This blocks casual account switching, but no client-side device fingerprint is perfect after OS resets, app reinstall, virtual machines, or privacy changes.

## Genre Order

Relaxation Studio writes `genre_sections`:

```json
{
  "title": "Action",
  "order": 0,
  "visible": true
}
```

The user app renders genre rails by this order. Unknown genres are appended after ordered genres.

## Cloudflare Cache

The Telegram ingest service emits:

```http
Cache-Control: public, max-age=3600, s-maxage=86400
CDN-Cache-Control: public, max-age=86400
```

Use the Worker in `cloudflare/worker.js` as a cache proxy in front of your ingest service. Replace `ORIGIN` with your deployed ingest URL, then deploy with Wrangler. Cloudflare docs note that static assets are cached by default, while dynamic content needs Cache Rules or Worker cache behavior.

Sources checked:

- Firebase Auth Flutter: https://firebase.google.com/docs/auth/flutter/start
- Firebase federated auth: https://firebase.google.com/docs/auth/flutter/federated-auth
- Cloudflare cache behavior: https://developers.cloudflare.com/cache/concepts/default-cache-behavior/
- Cloudflare cache control: https://developers.cloudflare.com/cache/concepts/cache-control/
- device_info_plus: https://pub.dev/packages/device_info_plus

## GitHub Builds

The workflow `.github/workflows/build-release.yml` builds:

- Android APK
- Web
- Windows
- Linux
- macOS
