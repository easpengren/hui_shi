# Backlog - Hui Shi TTS Reader

## Purpose
Central backlog for app, server rollout, and reliability work. This consolidates action items previously split across handoff and rollout docs.

## Now
1. Runtime validation on device with assistant interruptions
- Verify audio focus behavior end to end: reader pauses on assistant speech, resumes only after transient focus gain.
- Confirm behavior for permanent focus loss does not auto-resume.

2. Resume unfinished chunk builds after app restart
- Persist build state (last completed chunk, queue state, book/session id).
- Resume generation safely when app process restarts.

3. Production voice picker parity
- Replace debug-only voice UI behavior with production UX.
- Show clear cloud voice selection and fallback voice visibility.

4. Home-to-Hetzner rollout gate execution
- Execute and record rollout gates from self-host plan (smoke, reliability, performance, rollback readiness).
- Keep home endpoint as rollback target for first 72 hours after cutover.

## Next
1. Fast mode for very large documents
- Smaller initial synthesis batch with immediate playback start.
- Continue background synthesis with robust progress tracking.

2. Integration tests for cloud and fallback transitions
- Add tests covering cloud success, cloud failure, and native fallback continuity.
- Include timeout and error-shape handling coverage.

3. Server-side cost and safety guardrails
- Deterministic chunk cache.
- Max chunk size enforcement.
- Early reject oversized requests.
- Failed-job expiry and synth-volume tracking.

## Later
1. WearOS companion trigger flow
- Watch tile/complication action to trigger phone assistant flow.

2. Enhanced observability
- Expand structured logs and metrics for synthesis latency, failure rates, and queue depth trends.

## Sources
- docs/HANDOFF.md (Recommended Next Steps)
- docs/SELF_HOST_ROLLOUT.md (Recommended Next Actions, Cost Guardrails)
