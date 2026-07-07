# Sprint 1 Bake-off Results — 2026-07-06

Hardware: Ryzen 7 7730U, CPU-only backend (Vulkan not picked up by Ollama 0.31.1 — 100% CPU per `ollama ps`; irrelevant, CPU passes the gate).
No mining running during tests.

## Generation speed (--verbose, single run)

| Model               | Prompt tok/s | Gen tok/s | Gate ≥8 tok/s                                  |
| ------------------- | -----------: | --------: | ---------------------------------------------- |
| lfm2.5 (8B-A1B MoE) |         64.7 |  **20.7** | ✅ 2.6×                                        |
| granite4.1:3b       |         44.7 |  **19.3** | ✅ 2.4×                                        |
| qwen3.5:4b          |         33.2 |       7.2 | ❌ (thinking burned 363 tok on trivial prompt) |

Cold load: lfm2.5 ~53 s (one-time; mitigate with keep_alive).

## Schema compliance (advisor-style JSON prompt)

| Model         | Valid JSON   | Evidence cited correctly  | Thinking overhead         |
| ------------- | ------------ | ------------------------- | ------------------------- |
| granite4.1:3b | ✅ first try | ✅ ts + reason_code exact | none — instant JSON       |
| lfm2.5        | ✅ first try | ✅ ts + reason_code exact | ~250 tok visible thinking |

## Decision

- **PRIMARY (QUERY mode): granite4.1:3b** — zero thinking latency, instant
  valid JSON, 19.3 tok/s, 2.1 GB, Apache 2.0.
- **SECONDARY (REFLECT mode): lfm2.5** — fastest raw generation, thinking
  mode is an asset for nightly deep analysis; use `think:false` via API if
  used interactively.
- **DROPPED: qwen3.5:4b** — thinking not economical at this size on CPU.

Launch config: default `ollama serve` (CPU), `keep_alive=30m`, `num_ctx=4096`.

## Sprint 1 done criteria

- [x] All 3 candidate models cached under F:\Dev\ollama
- [x] ≥8 tok/s sustained (both leaders: ~20 tok/s)
- [x] Schema compliance (2/2 first-try valid on spot check; full 10-shot audit in Sprint 3)
- [x] Winner + launch command documented
- [ ] Package temp under sustained generation — verify during Sprint 2 self-test
