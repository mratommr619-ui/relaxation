import asyncio
import json
import re
import threading
from email.utils import formatdate
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Union
from urllib.parse import parse_qs, quote, unquote, urlparse

from telethon import TelegramClient
from telethon.errors import SessionPasswordNeededError
from telethon.sessions import StringSession

_phone_hashes: dict[str, str] = {}
_pending_password_session = ""
_server = None
_server_base_url = ""
_server_config = {}


def _config(args):
    api_id = int(args.get("apiId") or 0)
    api_hash = str(args.get("apiHash") or "").strip()
    session = str(args.get("sessionString") or "").strip()
    if not api_id or not api_hash:
        raise ValueError("Telegram API settings are missing.")
    return api_id, api_hash, session


async def _client(api_id: int, api_hash: str, session: str = ""):
    client = TelegramClient(StringSession(session), api_id, api_hash)
    await client.connect()
    return client


def status(args):
    return _json(asyncio.run(_status(args)))


async def _status(args):
    api_id, api_hash, session = _config(args)
    if not session:
        return {"authorized": False}
    client = await _client(api_id, api_hash, session)
    try:
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
            "sessionString": client.session.save(),
        }
    finally:
        await client.disconnect()


def send_code(args):
    return _json(asyncio.run(_send_code(args)))


async def _send_code(args):
    api_id, api_hash, session = _config(args)
    phone = str(args.get("phone") or "").strip()
    if not phone:
        raise ValueError("Phone number is required.")
    client = await _client(api_id, api_hash, session)
    try:
        sent = await client.send_code_request(phone)
        _phone_hashes[phone] = sent.phone_code_hash
        return {"ok": True, "sessionString": client.session.save()}
    finally:
        await client.disconnect()


def sign_in(args):
    return _json(asyncio.run(_sign_in(args)))


async def _sign_in(args):
    global _pending_password_session
    api_id, api_hash, session = _config(args)
    phone = str(args.get("phone") or "").strip()
    code = str(args.get("code") or "").strip()
    if not phone or not code:
        raise ValueError("Phone and code are required.")
    phone_hash = _phone_hashes.get(phone)
    if not phone_hash:
        raise ValueError("Request a Telegram login code first.")
    client = await _client(api_id, api_hash, session)
    try:
        try:
            await client.sign_in(phone=phone, code=code, phone_code_hash=phone_hash)
        except SessionPasswordNeededError:
            _pending_password_session = client.session.save()
            return {"ok": False, "passwordNeeded": True}
        return {**await _status_from_client(client), "ok": True, "passwordNeeded": False}
    finally:
        await client.disconnect()


def password(args):
    return _json(asyncio.run(_password(args)))


async def _password(args):
    global _pending_password_session
    api_id, api_hash, session = _config(args)
    password_value = str(args.get("password") or "")
    if not password_value:
        raise ValueError("Password is required.")
    client = await _client(api_id, api_hash, _pending_password_session or session)
    try:
        await client.sign_in(password=password_value)
        _pending_password_session = ""
        return {**await _status_from_client(client), "ok": True}
    finally:
        await client.disconnect()


async def _status_from_client(client):
    me = await client.get_me()
    return {
        "authorized": True,
        "id": me.id,
        "username": me.username or "",
        "phone": me.phone or "",
        "firstName": me.first_name or "",
        "lastName": me.last_name or "",
        "sessionString": client.session.save(),
    }


def resolve(args):
    return _json(asyncio.run(_resolve(args)))


async def _resolve(args):
    api_id, api_hash, session = _config(args)
    if not session:
        raise ValueError("Telegram login is required on this device.")
    telegram_url = str(args.get("telegramUrl") or "").strip()
    chat, message_id = _resolve_telegram_ref(telegram_url, "", 0)
    client = await _client(api_id, api_hash, session)
    try:
        if not await client.is_user_authorized():
            raise ValueError("Telegram login is expired on this device.")
        message = await client.get_messages(chat, ids=message_id)
        if not message or not message.media:
            raise ValueError("Telegram media message not found.")
        file_name = getattr(message.file, "name", None) or f"telegram-{message_id}"
        mime_type = getattr(message.file, "mime_type", None) or "application/octet-stream"
        size = getattr(message.file, "size", None) or 0
        base_url = _ensure_server(api_id, api_hash, client.session.save())
        encoded_url = quote(telegram_url, safe="")
        stream_url = f"{base_url}/stream?url={encoded_url}"
        download_url = f"{base_url}/download?url={encoded_url}"
        return {
            "chat": str(chat),
            "messageId": message_id,
            "telegramUrl": telegram_url,
            "streamUrl": stream_url,
            "downloadUrl": download_url,
            "fileName": file_name,
            "mimeType": mime_type,
            "size": size,
            "sessionString": client.session.save(),
        }
    finally:
        await client.disconnect()


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
            raise ValueError("Invalid Telegram public link.")
        return f"@{match.group(1)}", int(match.group(2))

    if not chat or not message_id:
        raise ValueError("Provide telegram_url or both chat and message_id.")
    if re.fullmatch(r"-?\d+", str(chat)):
        return int(chat), message_id
    return chat if str(chat).startswith("@") else f"@{chat}", message_id


def _json(value):
    return json.dumps(value, ensure_ascii=False)


def _ensure_server(api_id: int, api_hash: str, session: str) -> str:
    global _server, _server_base_url, _server_config
    _server_config = {"api_id": api_id, "api_hash": api_hash, "session": session}
    if _server is not None:
        return _server_base_url
    _server = ThreadingHTTPServer(("127.0.0.1", 0), _TelethonHttpHandler)
    _server_base_url = f"http://127.0.0.1:{_server.server_port}"
    thread = threading.Thread(target=_server.serve_forever, daemon=True)
    thread.start()
    return _server_base_url


class _TelethonHttpHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_HEAD(self):
        self._serve(metadata_only=True)

    def do_GET(self):
        if self.path == "/health":
            payload = b'{"ok":true}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        self._serve(metadata_only=False)

    def log_message(self, format, *args):
        return

    def _serve(self, metadata_only: bool):
        try:
            parsed = urlparse(self.path)
            if parsed.path not in {"/stream", "/download"}:
                self.send_error(404)
                return
            query = parse_qs(parsed.query)
            telegram_url = unquote((query.get("url") or [""])[0])
            as_attachment = parsed.path == "/download"
            asyncio.run(self._serve_async(telegram_url, as_attachment, metadata_only))
        except Exception as error:
            message = str(error).encode("utf-8", errors="replace")
            self.send_response(500)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(message)))
            self.end_headers()
            if not metadata_only:
                self.wfile.write(message)

    async def _serve_async(self, telegram_url: str, as_attachment: bool, metadata_only: bool):
        config = _server_config
        client = await _client(config["api_id"], config["api_hash"], config["session"])
        try:
            chat, message_id = _resolve_telegram_ref(telegram_url, "", 0)
            message = await client.get_messages(chat, ids=message_id)
            if not message or not message.media:
                self.send_error(404)
                return

            file_size = getattr(message.file, "size", None) or 0
            mime = getattr(message.file, "mime_type", None) or "application/octet-stream"
            filename = getattr(message.file, "name", None) or f"telegram-{message_id}.mp4"
            offset = 0
            limit = file_size
            status_code = 200
            range_header = self.headers.get("Range")
            if range_header and file_size:
                offset, limit = _parse_range(range_header, file_size)
                status_code = 206

            self.send_response(status_code)
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Type", mime)
            self.send_header("Last-Modified", formatdate(usegmt=True))
            self.send_header("Cache-Control", "no-store")
            if range_header and file_size:
                self.send_header(
                    "Content-Range",
                    f"bytes {offset}-{offset + limit - 1}/{file_size}",
                )
                self.send_header("Content-Length", str(limit))
            elif file_size:
                self.send_header("Content-Length", str(file_size))
            if as_attachment:
                self.send_header(
                    "Content-Disposition",
                    f"attachment; filename*=UTF-8''{quote(filename)}",
                )
            self.end_headers()
            if metadata_only:
                return

            sent = 0
            async for chunk in client.iter_download(
                message.media,
                offset=offset,
                request_size=512 * 1024,
            ):
                if limit and sent + len(chunk) > limit:
                    chunk = chunk[: limit - sent]
                sent += len(chunk)
                self.wfile.write(chunk)
                self.wfile.flush()
                if limit and sent >= limit:
                    break
        finally:
            await client.disconnect()


def _parse_range(range_header: str, file_size: int) -> tuple[int, int]:
    value = range_header.replace("bytes=", "")
    start_text, end_text = value.split("-", 1)
    if start_text:
        start = int(start_text)
        end = int(end_text) if end_text else file_size - 1
    else:
        suffix_length = int(end_text)
        start = max(file_size - suffix_length, 0)
        end = file_size - 1
    end = min(end, file_size - 1)
    if start > end:
        raise ValueError("Invalid range")
    return start, end - start + 1
