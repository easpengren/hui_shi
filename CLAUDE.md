# lu_ji — AI agent rules
## Investigate before you edit (applies to every change)

Before changing code to fix a bug or behavior:

1. **Reproduce it first.** Run the actual code path / endpoint and observe the real failure. Never fix from a guess or a description of the symptom.
2. **Trace the real path.** grep/search for where it actually happens and read it end-to-end across every layer it touches. The bug is usually **not** where the symptom appears.
3. **Name the root cause in plain words** before you edit. If you can't, you haven't found it — keep looking.
4. **If the symptom is in an LLM/model reply, the bug is almost always the wiring** — routing, env/config, the request that gets built, the data passed in — **not** the prompt. Don't tweak the prompt and declare victory.
5. **Verify the fix the way you reproduced it** (re-run; before/after). "It should work now" is not verification.

Skipping these produces symptom-patches that regress — the "keeps getting fixed but isn't" loop.
