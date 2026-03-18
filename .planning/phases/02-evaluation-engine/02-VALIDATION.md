---
phase: 2
slug: evaluation-engine
status: draft
nyquist_compliant: true
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
| 02-01-01 | 01 | 1 | PROC-01 | unit (TDD) | `zig build test -Dtest-cmd=src/input/Binding.zig` | ⬜ TDD (written in-task) | ⬜ pending |
| 02-01-02 | 01 | 1 | PROC-01, PROC-05 | unit | `zig build test -Dtest-cmd=src/input/Binding.zig` | ✅ (created by Task 1) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Test Creation Strategy

Task 1 is `tdd="true"` — tests are written RED before implementation within the same task (Wave 1). No separate Wave 0 task is needed because:
- TDD task writes tests first (RED phase), then implements (GREEN phase)
- Tests exist and run before implementation code is written
- The Nyquist requirement (tests before code) is satisfied by the TDD workflow itself

Tests created by Task 1:
- `RuntimeContext.matchesCondition` — match hit, miss, null context, priority ordering (PROC-01)
- Updated `getConditional` signature with `?*const RuntimeContext` (PROC-01)
- `getEventConditional` with RuntimeContext — end-to-end keypress path (PROC-01)

*All tests live in `src/input/Binding.zig` alongside existing conditional tests at line 5113+*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Keypress latency not measurably affected | PROC-05 | Requires real terminal + profiling | Run ghostty, open vim in terminal, press bound keys rapidly — no perceptible delay |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify commands that run tests (not just ast-check)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Test creation covered by TDD task (no separate Wave 0 needed)
- [x] No watch-mode flags
- [x] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
