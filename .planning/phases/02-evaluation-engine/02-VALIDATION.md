---
phase: 2
slug: evaluation-engine
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-18
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Zig built-in test runner |
| **Config file** | none — `zig build test` runs all |
| **Quick run command** | `zig build test -Dtest-cmd=src/input/Binding.zig` |
| **Full suite command** | `zig build test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `zig build test -Dtest-cmd=src/input/Binding.zig`
- **After every plan wave:** Run `zig build test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 0 | PROC-01 | unit | `zig build test -Dtest-cmd=src/input/Binding.zig` | ❌ W0 | ⬜ pending |
| 02-01-02 | 01 | 1 | PROC-01 | unit | `zig build test -Dtest-cmd=src/input/Binding.zig` | ❌ W0 | ⬜ pending |
| 02-01-03 | 01 | 1 | PROC-01, PROC-05 | unit | `zig build test -Dtest-cmd=src/input/Binding.zig` | ❌ W0 | ⬜ pending |
| 02-01-04 | 01 | 2 | PROC-01 | unit | `zig build test -Dtest-cmd=src/input/Binding.zig` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Tests for `RuntimeContext.matchesCondition` — match hit, miss, null context, priority ordering (PROC-01)
- [ ] Tests for updated `getConditional` signature with `?*const RuntimeContext` (PROC-01)
- [ ] Tests for `getEventConditional` with RuntimeContext — end-to-end keypress path (PROC-01)

*All tests live in `src/input/Binding.zig` alongside existing conditional tests at line 5113+*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Keypress latency not measurably affected | PROC-05 | Requires real terminal + profiling | Run ghostty, open vim in terminal, press bound keys rapidly — no perceptible delay |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
