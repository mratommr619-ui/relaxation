import argparse
import asyncio
import mimetypes
import os
import re
import tempfile
import uuid
from pathlib import Path
from typing import Union
from urllib.parse import quote

import firebase_admin
from dotenv import load_dotenv
from firebase_admin import credentials, firestore, storage
from telethon import TelegramClient
from telethon.sessions import StringSession

load_dotenv()


def _resolve_telegram_ref(
    telegram_url: str,
    chat: str,
    message_id: int,
) -> tuple[Union[str, int], int]:
    if telegram_url:
        private_match = re.search(
            r"(?:t\.me|telegram\.me|telegram\.dog)/c/(\d+)/(\d+)",
            telegram_url,
        )
        if private_match:
            return int(f"-100{private_match.group(1)}"), int(private_match.group(2))

        match = re.search(
            r"(?:t\.me|telegram\.me|telegram\.dog)/(?:s/)?([^/?#]+)/(\d+)",
            telegram_url,
        )
        if not match and re.match(r"^[A-Za-z0-9_]+/\d+", telegram_url):
            match = re.match(r"^([A-Za-z0-9_]+)/(\d+)", telegram_url)
        if not match:
            raise ValueError("Invalid Telegram public link")
        return f"@{match.group(1)}", int(match.group(2))

    if not chat or not message_id:
        raise ValueError("Provide --telegram-url or both --chat and --message-id")
    if re.fullmatch(r"-?\d+", str(chat)):
        return int(chat), message_id
    return chat if chat.startswith("@") else f"@{chat}", message_id


def _firebase_download_url(bucket_name: str, blob_name: str, token: str) -> str:
    encoded = quote(blob_name, safe="")
    return (
        f"https://firebasestorage.googleapis.com/v0/b/{bucket_name}/o/{encoded}"
        f"?alt=media&token={token}"
    )


async def main() -> None:
    parser = argparse.ArgumentParser(
        description="Cache a Telegram media post to Firebase Storage and update Firestore.",
    )
    parser.add_argument("--service-account", required=True)
    parser.add_argument("--bucket", default=os.environ.get("FIREBASE_STORAGE_BUCKET", ""))
    parser.add_argument("--doc-id", default="")
    parser.add_argument("--telegram-url", default="")
    parser.add_argument("--chat", default="")
    parser.add_argument("--message-id", type=int, default=0)
    parser.add_argument("--title", default="")
    parser.add_argument("--collection", default="media")
    parser.add_argument("--folder", default="media")
    args = parser.parse_args()

    api_id = int(os.environ.get("TELEGRAM_API_ID", "0"))
    api_hash = os.environ.get("TELEGRAM_API_HASH", "")
    session_string = os.environ.get("TELEGRAM_SESSION_STRING", "")
    if not api_id or not api_hash or not session_string:
        raise RuntimeError("Set TELEGRAM_API_ID, TELEGRAM_API_HASH, and TELEGRAM_SESSION_STRING.")

    bucket_name = args.bucket.strip()
    if not bucket_name:
        raise RuntimeError("Set --bucket or FIREBASE_STORAGE_BUCKET.")

    if not firebase_admin._apps:
        firebase_admin.initialize_app(
            credentials.Certificate(args.service_account),
            {"storageBucket": bucket_name},
        )

    db = firestore.client()
    bucket = storage.bucket()
    chat, message_id = _resolve_telegram_ref(args.telegram_url, args.chat, args.message_id)

    async with TelegramClient(StringSession(session_string), api_id, api_hash) as client:
        message = await client.get_messages(chat, ids=message_id)
        if not message or not message.media:
            raise RuntimeError("Telegram media message not found.")

        file_name = getattr(message.file, "name", None) or f"telegram-{message_id}.mp4"
        mime_type = getattr(message.file, "mime_type", None)
        if not mime_type:
            mime_type = mimetypes.guess_type(file_name)[0] or "application/octet-stream"

        safe_name = re.sub(r'[\r\n"\\/:*?<>|]+', "_", file_name).strip() or f"telegram-{message_id}.mp4"
        object_name = f"{args.folder.strip('/')}/{uuid.uuid4().hex}-{safe_name}"

        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir) / safe_name
            await client.download_media(message, file=temp_path)
            blob = bucket.blob(object_name)
            token = str(uuid.uuid4())
            blob.metadata = {"firebaseStorageDownloadTokens": token}
            blob.cache_control = "public, max-age=31536000, immutable"
            blob.upload_from_filename(str(temp_path), content_type=mime_type)

    url = _firebase_download_url(bucket_name, object_name, token)
    payload = {
        "streamUrl": url,
        "downloadUrl": url,
        "watchLinks": [{"label": "HD", "url": url}],
        "downloadLinks": [{"label": "HD", "url": url}],
        "cachedStoragePath": object_name,
        "cachedMimeType": mime_type,
        "cachedAt": firestore.SERVER_TIMESTAMP,
    }
    if args.telegram_url:
        payload["telegramUrl"] = args.telegram_url.strip()
    if args.title:
        payload["title"] = args.title.strip()

    if args.doc_id:
        db.collection(args.collection).document(args.doc_id).set(payload, merge=True)
        print(f"Updated {args.collection}/{args.doc_id}")
    else:
        payload.setdefault("title", safe_name)
        payload.setdefault("type", "movie")
        payload.setdefault("genre", "General")
        payload.setdefault("quality", "HD")
        payload.setdefault("description", "")
        payload.setdefault("posterUrl", "")
        payload.setdefault("posterBase64", "")
        payload["createdAt"] = firestore.SERVER_TIMESTAMP
        doc = db.collection(args.collection).add(payload)[1]
        print(f"Created {args.collection}/{doc.id}")

    print(url)


if __name__ == "__main__":
    asyncio.run(main())
