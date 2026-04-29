import hashlib
import json
import os
import uuid
from pathlib import Path

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from redis import Redis


def get_env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


APP_API_KEY = get_env("APP_API_KEY")
REDIS_URL = get_env("REDIS_URL", "redis://redis:6379/0")
STORAGE_ROOT = Path(get_env("STORAGE_ROOT", "/data"))
BASE_PUBLIC_URL = get_env("BASE_PUBLIC_URL", "http://localhost:8080")
MAX_CHARS_PER_REQUEST = int(get_env("MAX_CHARS_PER_REQUEST", "2800"))

FILES_DIR = STORAGE_ROOT / "files"
FILES_DIR.mkdir(parents=True, exist_ok=True)

redis_client = Redis.from_url(REDIS_URL, decode_responses=True)

app = FastAPI(title="Kokoro Self-Host API", version="0.1.0")


class TtsRequest(BaseModel):
    text: str = Field(min_length=1)
    voice: str = "af_bella"
    model: str = "kokoro"
    format: str = "mp3"


class TtsQueuedResponse(BaseModel):
    uuid: str
    job_id: str
    status: str = "queued"


class TtsResultResponse(BaseModel):
    status: str
    result_url: str | None = None
    error: str | None = None


def auth_guard(authorization: str | None = Header(default=None)):
    if not APP_API_KEY:
        raise HTTPException(status_code=500, detail="Server APP_API_KEY is not configured")
    expected = f"Bearer {APP_API_KEY}"
    if authorization != expected:
        raise HTTPException(status_code=401, detail="Invalid or missing Authorization bearer token")


def job_key(job_id: str) -> str:
    return f"tts:job:{job_id}"


def cache_key(payload: TtsRequest) -> str:
    normalized = " ".join(payload.text.split())
    raw = f"{payload.model}|{payload.voice}|{payload.format}|{normalized}".encode("utf-8")
    digest = hashlib.sha256(raw).hexdigest()
    return f"tts:cache:{digest}"


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.post("/v1/tts/")
def synthesize(request: TtsRequest, _: None = Depends(auth_guard)):
    if len(request.text) > MAX_CHARS_PER_REQUEST:
        raise HTTPException(
            status_code=400,
            detail=f"Text exceeds MAX_CHARS_PER_REQUEST ({len(request.text)}/{MAX_CHARS_PER_REQUEST})",
        )

    c_key = cache_key(request)
    cached_path = redis_client.get(c_key)
    if cached_path and Path(cached_path).exists():
        return FileResponse(path=cached_path, media_type="audio/wav")

    job_id = str(uuid.uuid4())
    payload = {
        "id": job_id,
        "status": "queued",
        "request": request.model_dump(),
        "cache_key": c_key,
    }

    redis_client.set(job_key(job_id), json.dumps(payload))
    redis_client.rpush("tts:jobs", job_id)

    return TtsQueuedResponse(uuid=job_id, job_id=job_id, status="queued")


@app.get("/v1/speech/results/")
def poll_result(uuid: str = Query(...), _: None = Depends(auth_guard)):
    raw = redis_client.get(job_key(uuid))
    if not raw:
        raise HTTPException(status_code=404, detail="Unknown job uuid")

    payload = json.loads(raw)
    status = payload.get("status", "queued")
    if status == "completed":
        result_file = payload.get("result_file")
        return TtsResultResponse(
            status="completed",
            result_url=f"{BASE_PUBLIC_URL}/v1/audio/{uuid}" if result_file else None,
        )
    if status == "failed":
        return TtsResultResponse(status="failed", error=payload.get("error", "unknown error"))
    return TtsResultResponse(status=status)


@app.get("/v1/audio/{job_id}")
def get_audio(job_id: str, _: None = Depends(auth_guard)):
    raw = redis_client.get(job_key(job_id))
    if not raw:
        raise HTTPException(status_code=404, detail="Unknown job id")

    payload = json.loads(raw)
    if payload.get("status") != "completed":
        raise HTTPException(status_code=409, detail="Audio is not ready")

    result_file = payload.get("result_file")
    if not result_file or not Path(result_file).exists():
        raise HTTPException(status_code=404, detail="Audio file missing")

    return FileResponse(path=result_file, media_type="audio/wav")
