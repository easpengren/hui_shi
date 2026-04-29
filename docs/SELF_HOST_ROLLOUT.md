# Self-Host Rollout Runbook (Home Server -> Hetzner)

## Goal
Run Kokoro cloud-compatible synthesis on your own server for long-book workloads, validate at home first, then migrate to Hetzner with no app-side API changes.

## Fixed API Contract
Do not change these endpoints during rollout.

1. `POST /v1/tts/`
2. `GET /v1/speech/results/?uuid=<id>`

If your backend contract changes, the Android app will require additional work.

## Architecture Baseline
Use the same containerized layout at home and on Hetzner.

Reference starter implementation in [selfhost/README.md](../selfhost/README.md).

1. `reverse-proxy` (TLS, request size limits, auth passthrough)
2. `api` (request validation, cache lookup, queue enqueue, poll endpoint)
3. `redis` (job queue)
4. `worker` (Kokoro synthesis + result persistence)
5. `storage` (audio files on persistent volume)

## Required Environment Variables
Standardize names now so migration is copy/paste.

1. `APP_API_KEY`
2. `BASE_PUBLIC_URL`
3. `REDIS_URL`
4. `STORAGE_ROOT`
5. `KOKORO_MODEL`
6. `KOKORO_DEFAULT_VOICE`
7. `MAX_CHARS_PER_REQUEST`
8. `JOB_TIMEOUT_SECONDS`
9. `CACHE_TTL_DAYS`

## Phase 1: Home Server Validation

### Entry Criteria
1. Android app can target a custom base URL.
2. Home server has Docker + Docker Compose.
3. Domain or LAN URL is reachable from test phone.

### Test Set
Use real book-sized text, not toy samples.

1. One short text (smoke test)
2. One medium chapter (~15 to 30 minutes audio)
3. One long chapter (~45+ minutes audio)
4. One full-book batch run (or equivalent total size)

### Pass/Fail Gates (Home)
All gates must pass before Hetzner migration.

1. Gate A: API Contract
Pass: app successfully synthesizes and polls with current endpoints.
Fail: any endpoint shape mismatch or parsing failure.

2. Gate B: Queue Reliability
Pass: queued jobs complete under sustained load without stuck tasks.
Fail: jobs remain queued indefinitely or require manual intervention.

3. Gate C: Cache Reuse
Pass: rerun of same text+voice returns cached audio with near-zero synthesis time.
Fail: repeated synthesis for identical chunks.

4. Gate D: Fault Recovery
Pass: service restart during active jobs recovers cleanly and polling remains consistent.
Fail: orphaned jobs or missing status after restart.

5. Gate E: Long-Run Stability
Pass: at least one long-book run completes without service crash.
Fail: worker/process crashes or memory runaway.

6. Gate F: App Fallback
Pass: if backend is unavailable, app falls back to native voice and remains usable.
Fail: playback flow breaks when backend is down.

## Phase 2: Hetzner Deployment

### Provisioning Steps
1. Create Hetzner VPS with enough CPU/RAM for expected throughput.
2. Install Docker + Docker Compose.
3. Configure firewall (open only 80/443 + optional SSH source restrictions).
4. Set DNS to VPS IP.
5. Deploy same Compose stack and same env variable names.

### Security Minimum
1. HTTPS only.
2. API key required for synth and poll routes.
3. Request body limits and timeout limits enabled.
4. Rate limiting per key.

### Hetzner Pass/Fail Gates
1. Gate G: Connectivity
Pass: phone reaches Hetzner endpoint over HTTPS from mobile network and Wi-Fi.

2. Gate H: Functional Parity
Pass: the same test set used at home succeeds without app changes.

3. Gate I: Performance Floor
Pass: first audio chunks become available within acceptable user wait for your workflow.

4. Gate J: Operational Safety
Pass: logs, disk usage, and queue depth are observable and actionable.

## Cutover Plan
1. Freeze backend image tags and environment values.
2. Run home-server final regression on one full workload.
3. Deploy Hetzner stack.
4. Run smoke + medium + long tests on Hetzner.
5. Change app `KOKORO_API_BASE_URL` to Hetzner URL.
6. Keep home server as warm rollback for at least 72 hours.

## Rollback Plan
1. If any Hetzner gate fails, revert app base URL to home endpoint.
2. Keep same API key contract so rollback is one config change.
3. Open a fix ticket with failed gate ID and timestamped logs.

## Cost Guardrails
1. Cache every completed chunk by deterministic hash.
2. Cap max chunk length server-side.
3. Reject oversized requests early.
4. Expire stale failed jobs.
5. Track synth seconds per day to detect runaway load.

## Recommended Next Actions
1. Implement this backend contract on home server first.
2. Execute and record all Home gates (A-F).
3. Migrate to Hetzner only after all Home gates pass.