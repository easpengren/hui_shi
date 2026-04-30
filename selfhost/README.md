# Self-Host (Kokoro Direct)

Single-container Kokoro TTS server. The Android app and assistant app both talk directly
to this service — no queue, no middleware.

## API
- `POST /v1/audio/speech` — OpenAI-compatible, returns audio stream directly
- `GET /health` — liveness check

## Quick Start

```bash
cd selfhost
```

Set your API key in the environment (or a `.env` file):

```bash
export KOKORO_API_KEY=your-key-here
```

Start the server:

```bash
docker compose up --build
```

Server is available at `http://localhost:8880`.

## Configure Android App

In `app/build.gradle.kts` or `gradle.properties`:

```
KOKORO_API_BASE_URL=http://<your-local-ip>:8880/
KOKORO_API_KEY=your-key-here
```

Use your machine's LAN IP (not `localhost`) so the Android device can reach it.

## Production (Hetzner)

Same image, different `KOKORO_API_BASE_URL` in the app. Set `KOKORO_API_KEY` to a strong
random value and put the server behind a reverse proxy with TLS.
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
