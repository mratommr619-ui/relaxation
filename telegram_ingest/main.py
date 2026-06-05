import os
import re
from email.utils import formatdate
from urllib.parse import quote
from contextlib import asynccontextmanager
from typing import AsyncIterator, Optional, Union

import firebase_admin
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response, StreamingResponse
from firebase_admin import credentials, firestore
from pydantic import BaseModel, Field
from telethon import TelegramClient
from telethon.errors import SessionPasswordNeededError
from telethon.sessions import StringSession

load_dotenv()

API_ID = int(os.environ.get("TELEGRAM_API_ID", "0"))
API_HASH = os.environ.get("TELEGRAM_API_HASH", "")
SESSION = os.environ.get("TELEGRAM_SESSION", "relaxation_ingest")
SESSION_STRING = os.environ.get("TELEGRAM_SESSION_STRING", "")
PUBLIC_BASE_URL = os.environ.get("PUBLIC_BASE_URL", "http://127.0.0.1:8088")
SERVICE_ACCOUNT = os.environ.get("FIREBASE_SERVICE_ACCOUNT", "")

client = TelegramClient(StringSession(SESSION_STRING) if SESSION_STRING else SESSION, API_ID, API_HASH)
db: Optional[firestore.Client] = None
phone_code_hashes: dict[str, str] = {}


class ImportRequest(BaseModel):
    chat: str = ""
    message_id: int = 0
    telegram_url: str = ""
    title: str
    type: str = Field(default="movie", pattern="^(movie|series)$")
    genre: str = "General"
    quality: str = "1080p"
    description: str = ""
    poster_url: str = ""
    poster_base64: str = ""


class ResolveRequest(BaseModel):
    chat: str = ""
    message_id: int = 0
    telegram_url: str = ""


class SendCodeRequest(BaseModel):
    phone: str


class SignInRequest(BaseModel):
    phone: str
    code: str


class PasswordRequest(BaseModel):
    password: str


@asynccontextmanager
async def lifespan(_: FastAPI):
    global db
    if not API_ID or not API_HASH:
        raise RuntimeError("Set TELEGRAM_API_ID and TELEGRAM_API_HASH in .env")
    if SERVICE_ACCOUNT and not firebase_admin._apps:
        cred = credentials.Certificate(SERVICE_ACCOUNT)
        firebase_admin.initialize_app(cred)
        db = firestore.client()

    await client.connect()
    yield
    await client.disconnect()


app = FastAPI(title="Relaxation Telegram Ingest", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=[
        "Accept-Ranges",
        "Content-Disposition",
        "Content-Length",
        "Content-Range",
        "Content-Type",
    ],
)


@app.get("/health")
async def health():
    return {"ok": True}


@app.get("/auth/status")
async def auth_status():
    if not await client.is_user_authorized():
        return {"authorized": False}
    me = await client.get_me()
    return {
        "authorized": True,
        "id": me.id,
        "username": me.username or "",
        "phone": me.phone or "",
        "firstName": me.first_name or "",
        "lastName": me.last_name or "",
        "sessionString": _save_session_string(),
    }


@app.post("/auth/send_code")
async def auth_send_code(payload: SendCodeRequest):
    phone = payload.phone.strip()
    if not phone:
        raise HTTPException(status_code=422, detail="Phone number is required")
    result = await client.send_code_request(phone)
    phone_code_hashes[phone] = result.phone_code_hash
    return {"ok": True, "phoneCodeHash": result.phone_code_hash}


@app.post("/auth/sign_in")
async def auth_sign_in(payload: SignInRequest):
    phone = payload.phone.strip()
    code = payload.code.strip()
    if not phone or not code:
        raise HTTPException(status_code=422, detail="Phone and code are required")
    phone_code_hash = phone_code_hashes.get(phone)
    if not phone_code_hash:
        raise HTTPException(status_code=400, detail="Request a login code first")
    try:
        await client.sign_in(phone=phone, code=code, phone_code_hash=phone_code_hash)
    except SessionPasswordNeededError:
        return {"ok": False, "passwordNeeded": True}
    return {**await auth_status(), "ok": True, "passwordNeeded": False}


@app.post("/auth/password")
async def auth_password(payload: PasswordRequest):
    password = payload.password.strip()
    if not password:
        raise HTTPException(status_code=422, detail="Password is required")
    await client.sign_in(password=password)
    return {**await auth_status(), "ok": True}


@app.post("/import")
async def import_media(payload: ImportRequest):
    chat, message_id = _resolve_telegram_ref(
        payload.telegram_url,
        payload.chat,
        payload.message_id,
    )
    message = await client.get_messages(chat, ids=message_id)
    if not message or not message.media:
        raise HTTPException(status_code=404, detail="Telegram media message not found")

    safe_chat = _chat_route_key(chat)
    stream_url = f"{PUBLIC_BASE_URL}/stream/{safe_chat}/{message_id}"
    download_url = f"{PUBLIC_BASE_URL}/download/{safe_chat}/{message_id}"
    telegram_url = payload.telegram_url or _public_telegram_url(chat, message_id)

    doc = {
        "title": payload.title,
        "type": payload.type,
        "genre": payload.genre,
        "quality": payload.quality,
        "description": payload.description,
        "posterUrl": payload.poster_url,
        "posterBase64": payload.poster_base64,
        "streamUrl": stream_url,
        "downloadUrl": download_url,
        "watchLinks": [{"label": "Server 1", "url": stream_url}],
        "downloadLinks": [{"label": "Server 1", "url": download_url}],
        "telegramUrl": telegram_url,
        "telegramChat": chat,
        "telegramMessageId": message_id,
        "ingestBaseUrl": PUBLIC_BASE_URL,
        "episodes": [],
        "createdAt": firestore.SERVER_TIMESTAMP,
    }
    if db is None:
        raise HTTPException(
            status_code=503,
            detail="Firestore is not configured on this ingest server",
        )
    ref = db.collection("media").add(doc)[1]
    return {"id": ref.id, "streamUrl": stream_url, "downloadUrl": download_url}


@app.post("/resolve")
async def resolve_media(payload: ResolveRequest):
    chat, message_id = _resolve_telegram_ref(
        payload.telegram_url,
        payload.chat,
        payload.message_id,
    )
    message = await client.get_messages(chat, ids=message_id)
    if not message or not message.media:
        raise HTTPException(status_code=404, detail="Telegram media message not found")

    safe_chat = _chat_route_key(chat)
    stream_url = f"{PUBLIC_BASE_URL}/stream/{safe_chat}/{message_id}"
    download_url = f"{PUBLIC_BASE_URL}/download/{safe_chat}/{message_id}"
    telegram_url = payload.telegram_url or _public_telegram_url(chat, message_id)
    return {
        "chat": chat,
        "messageId": message_id,
        "telegramUrl": telegram_url,
        "streamUrl": stream_url,
        "downloadUrl": download_url,
        "fileName": getattr(message.file, "name", None) or f"telegram-{message_id}",
        "mimeType": getattr(message.file, "mime_type", None) or "application/octet-stream",
        "size": getattr(message.file, "size", None) or 0,
    }


@app.get("/download/{chat}/{message_id}")
async def download(chat: str, message_id: int):
    return await _telegram_media_response(chat, message_id, as_attachment=True)


@app.get("/stream/{chat}/{message_id}")
async def stream(chat: str, message_id: int, request: Request):
    range_header = request.headers.get("range")
    return await _telegram_media_response(chat, message_id, range_header=range_header)


@app.head("/download/{chat}/{message_id}")
async def download_head(chat: str, message_id: int):
    return await _telegram_media_response(
        chat,
        message_id,
        as_attachment=True,
        metadata_only=True,
    )


@app.head("/stream/{chat}/{message_id}")
async def stream_head(chat: str, message_id: int, request: Request):
    range_header = request.headers.get("range")
    return await _telegram_media_response(
        chat,
        message_id,
        range_header=range_header,
        metadata_only=True,
    )


async def _telegram_media_response(
    chat: str,
    message_id: int,
    range_header: Optional[str] = None,
    as_attachment: bool = False,
    metadata_only: bool = False,
):
    entity = _telegram_entity(chat)
    message = await client.get_messages(entity, ids=message_id)
    if not message or not message.media:
        raise HTTPException(status_code=404, detail="Telegram media message not found")

    file_size = getattr(message.file, "size", None) or 0
    mime = getattr(message.file, "mime_type", None) or "application/octet-stream"
    filename = getattr(message.file, "name", None) or f"telegram-{message_id}"

    offset = 0
    limit = file_size
    status_code = 200
    headers = {
        "Accept-Ranges": "bytes",
        "Content-Type": mime,
        "Cache-Control": "public, max-age=3600, s-maxage=86400",
        "CDN-Cache-Control": "public, max-age=86400",
        "Last-Modified": formatdate(usegmt=True),
    }

    if as_attachment:
        headers["Content-Disposition"] = _content_disposition(filename)

    if range_header and file_size:
        offset, limit = _parse_range(range_header, file_size)
        status_code = 206
        headers["Content-Range"] = f"bytes {offset}-{offset + limit - 1}/{file_size}"
        headers["Content-Length"] = str(limit)
    elif file_size:
        headers["Content-Length"] = str(file_size)

    if metadata_only:
        return Response(status_code=status_code, headers=headers)

    async def iterator() -> AsyncIterator[bytes]:
        sent = 0
        async for chunk in client.iter_download(
            message.media,
            offset=offset,
            request_size=512 * 1024,
        ):
            if limit and sent + len(chunk) > limit:
                chunk = chunk[: limit - sent]
            sent += len(chunk)
            yield chunk
            if limit and sent >= limit:
                break

    return StreamingResponse(iterator(), status_code=status_code, headers=headers)


def _parse_range(range_header: str, file_size: int) -> tuple[int, int]:
    try:
        value = range_header.replace("bytes=", "")
        start_text, end_text = value.split("-", 1)
        if start_text:
            start = int(start_text)
            end = int(end_text) if end_text else file_size - 1
        else:
            suffix_length = int(end_text)
            if suffix_length <= 0:
                raise ValueError
            start = max(file_size - suffix_length, 0)
            end = file_size - 1
        end = min(end, file_size - 1)
        if start > end:
            raise ValueError
        return start, end - start + 1
    except ValueError as exc:
        raise HTTPException(status_code=416, detail="Invalid range") from exc


def _content_disposition(filename: str) -> str:
    safe_name = re.sub(r'[\r\n"\\]', "_", filename).strip() or "telegram-media"
    return f"attachment; filename*=UTF-8''{quote(safe_name)}"


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
            chat = f"-100{private_match.group(1)}"
            message_id = int(private_match.group(2))
            return int(chat), message_id

        match = re.search(
            r"(?:t\.me|telegram\.me|telegram\.dog)/(?:s/)?([^/?#]+)/(\d+)",
            telegram_url,
        )
        if not match and re.match(r"^[A-Za-z0-9_]+/\d+", telegram_url):
            match = re.match(r"^([A-Za-z0-9_]+)/(\d+)", telegram_url)
        if not match:
            raise HTTPException(status_code=422, detail="Invalid Telegram public link")
        chat = f"@{match.group(1)}"
        message_id = int(match.group(2))

    if not chat or not message_id:
        raise HTTPException(
            status_code=422,
            detail="Provide telegram_url or both chat and message_id",
        )

    if re.fullmatch(r"-?\d+", str(chat)):
        return int(chat), message_id
    if not str(chat).startswith("@"):
        chat = f"@{chat}"
    return chat, message_id


def _telegram_entity(chat: str) -> Union[str, int]:
    if re.fullmatch(r"-?\d+", chat):
        return int(chat)
    return f"@{chat}" if not chat.startswith("@") else chat


def _chat_route_key(chat: Union[str, int]) -> str:
    return str(chat).replace("@", "")


def _public_telegram_url(chat: Union[str, int], message_id: int) -> str:
    chat_key = _chat_route_key(chat)
    if chat_key.startswith("-100"):
        return f"https://t.me/c/{chat_key[4:]}/{message_id}"
    return f"https://t.me/{chat_key}/{message_id}"


def _save_session_string() -> str:
    if isinstance(client.session, StringSession):
        return client.session.save()
    return StringSession.save(client.session)
