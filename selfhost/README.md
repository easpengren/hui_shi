# Self-Host Starter (Home Server First)

This starter gives you a local Docker stack that matches the Android app contract:

1. `POST /v1/tts/`
2. `GET /v1/speech/results/?uuid=<id>`

It is intended for queue/contract testing first.

## What Is Included
1. FastAPI API service (`api.py`)
2. Redis queue
3. Worker process (`worker.py`)
4. Persistent local storage (`./data`)

## Important
The worker currently uses `SYNTH_BACKEND=stub` by default and generates deterministic WAV audio.
This validates your app integration and long-job flow, but it is not real Kokoro inference yet.

To add real Kokoro, replace `synthesize_stub(...)` in `worker.py` with your inference pipeline and set `SYNTH_BACKEND=kokoro`.

## Quick Start
1. Copy env template:

```bash
cd selfhost
cp .env.example .env
```

2. Set required values in `.env`:
   - `APP_API_KEY`
   - `BASE_PUBLIC_URL` (for home server URL; `http://localhost:8080` for local testing)

3. Run stack:

```bash
docker compose up --build
```

4. Health check:

```bash
curl http://localhost:8080/health
```

5. Test synth enqueue:

```bash
curl -X POST http://localhost:8080/v1/tts/ \
  -H "Authorization: Bearer YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"text":"Hello from self host","voice":"af_bella","model":"kokoro","format":"mp3"}'
```

6. Poll result:

```bash
curl "http://localhost:8080/v1/speech/results/?uuid=YOUR_UUID" \
  -H "Authorization: Bearer YOUR_KEY"
```

## Android App Wiring
Set these in your app config (`gradle.properties`):

1. `KOKORO_API_BASE_URL=http://<server-ip>:8080/`
2. `KOKORO_API_KEY=<same APP_API_KEY from selfhost .env>`

Then run the app and build audio as usual.

## Migration to Hetzner
Keep this folder unchanged and move it as-is.

1. Copy `selfhost` directory to server.
2. Set `BASE_PUBLIC_URL` to your Hetzner domain.
3. Run `docker compose up --build -d`.
4. Follow pass/fail gates in `docs/SELF_HOST_ROLLOUT.md`.
