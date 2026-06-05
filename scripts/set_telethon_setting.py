import argparse
from datetime import datetime, timedelta, timezone

import firebase_admin
from firebase_admin import credentials, firestore


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--service-account", required=True)
    parser.add_argument("--url", default="")
    parser.add_argument("--run-id", default="")
    parser.add_argument("--status", default="online")
    parser.add_argument("--ttl-minutes", type=int, default=360)
    parser.add_argument("--clear-if-run-id", default="")
    args = parser.parse_args()

    if not firebase_admin._apps:
        firebase_admin.initialize_app(credentials.Certificate(args.service_account))

    db = firestore.client()
    ref = db.collection("app_settings").document("telegram")

    if args.clear_if_run_id:
        snap = ref.get()
        data = snap.to_dict() or {}
        if str(data.get("runId", "")) == args.clear_if_run_id:
            ref.set(
                {
                    "ingestBaseUrl": "",
                    "status": args.status,
                    "stoppedAt": firestore.SERVER_TIMESTAMP,
                },
                merge=True,
            )
            print(f"Cleared Telethon URL for run {args.clear_if_run_id}")
        else:
            print("Skipped clear because a newer Telethon run is active")
        return

    url = args.url.strip().rstrip("/")
    payload = {
        "ingestBaseUrl": url,
        "status": args.status,
        "runId": args.run_id,
        "updatedAt": firestore.SERVER_TIMESTAMP,
        "expiresAt": datetime.now(timezone.utc) + timedelta(minutes=args.ttl_minutes),
    }
    ref.set(payload, merge=True)
    print(f"Saved Telethon URL to Firestore: {url}")


if __name__ == "__main__":
    main()
