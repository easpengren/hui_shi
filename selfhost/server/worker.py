import json

import math
import os
import struct
import time
import wave
from pathlib import Path
import requests
from redis import Redis


def get_env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


REDIS_URL = get_env("REDIS_URL", "redis://redis:6379/0")
STORAGE_ROOT = Path(get_env("STORAGE_ROOT", "/data"))
SYNTH_BACKEND = get_env("SYNTH_BACKEND", "stub").lower()
JOB_TIMEOUT_SECONDS = int(get_env("JOB_TIMEOUT_SECONDS", "120"))

FILES_DIR = STORAGE_ROOT / "files"
FILES_DIR.mkdir(parents=True, exist_ok=True)

redis_client = Redis.from_url(REDIS_URL, decode_responses=True)


def job_key(job_id: str) -> str:
    return f"tts:job:{job_id}"


def update_job(job_id: str, **changes):
    raw = redis_client.get(job_key(job_id))
    if not raw:
        return
    payload = json.loads(raw)
    payload.update(changes)
    redis_client.set(job_key(job_id), json.dumps(payload))


def synthesize_stub(text: str, output: Path):
    # Deterministic short waveform for contract and queue testing.
    sample_rate = 16000
    duration_s = min(16.0, max(1.0, len(text) / 180.0))
    freq = 440.0
    total_samples = int(sample_rate * duration_s)
    amplitude = 12000

    with wave.open(str(output), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        for i in range(total_samples):
            value = int(amplitude * math.sin(2 * math.pi * freq * i / sample_rate))
            wav_file.writeframes(struct.pack("<h", value))


def synthesize_kokoro(text: str, output: Path, voice: str = "en_US-amy-medium", model: str = "kokoro", format: str = "wav"):
    """
    Calls the local kokoro-web TTS API and saves the result to output.
    """
        api_url = os.getenv("KOKORO_API_URL", "http://localhost:3000/v1/audio/speech")
    api_key = os.getenv("KOKORO_API_KEY", "")
    payload = {
        "text": text,
        "voice": voice,
        "model": model,
        "format": format
    }
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    response = requests.post(api_url, json=payload, headers=headers)
    response.raise_for_status()
    with open(output, "wb") as f:
        f.write(response.content)


def process_job(job_id: str):
    raw = redis_client.get(job_key(job_id))
    if not raw:
        return

    payload = json.loads(raw)
    request = payload.get("request", {})
    text = request.get("text", "")

    update_job(job_id, status="processing", started_at=int(time.time()))

    try:
        output = FILES_DIR / f"{job_id}.wav"
        voice = request.get("voice", "en_US-amy-medium")
        model = request.get("model", "kokoro")
        format = request.get("format", "wav")

        if SYNTH_BACKEND == "stub":
            synthesize_stub(text, output)
        elif SYNTH_BACKEND == "kokoro":
            synthesize_kokoro(text, output, voice=voice, model=model, format=format)
        else:
            raise RuntimeError(
                f"SYNTH_BACKEND={SYNTH_BACKEND} is not supported. "
                "Use 'stub' or 'kokoro'."
            )

        cache_key = payload.get("cache_key")
        if cache_key:
            redis_client.set(cache_key, str(output))

        update_job(
            job_id,
            status="completed",
            result_file=str(output),
            completed_at=int(time.time()),
        )
    except Exception as exc:
        update_job(
            job_id,
            status="failed",
            error=str(exc),
            completed_at=int(time.time()),
        )


def main():
    print("Worker started")
    while True:
        job = redis_client.blpop("tts:jobs", timeout=5)
        if not job:
            continue
        _, job_id = job
        started = time.time()
        process_job(job_id)
        elapsed = time.time() - started
        if elapsed > JOB_TIMEOUT_SECONDS:
            print(f"Warning: job {job_id} exceeded JOB_TIMEOUT_SECONDS ({elapsed:.2f}s)")


if __name__ == "__main__":
    main()
