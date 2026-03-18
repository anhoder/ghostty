---
phase: 5
slug: window-title-glob-matching
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-18
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Zig built-in test runner |
| **Config file** | none (inline `test` blocks in .zig files) |
| **Quick run command** | `zig build test -Dtest-cmd="src/input/Binding.zig"` |
| **Full suite command** | `zig ast-check src/Surface.zig && zig ast-check src/input/Binding.zig && zig build test -Dtest-cmd="src/input/Binding.zig"` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `zig ast-check src/input/Binding.zig && zig ast-check src/Surface.zig`
- **After every plan wave:** Run full suite command
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Wave 0 | Status |
|---------|------|------|-------------|-----------|-------------------|--------|--------|
| 05-01-00 | 01 | 1 | TITL-01, TITL-02, PROC-02 | unit | `zig ast-check src/input/Binding.zig` | W0 (creates stubs) | pending |
| 05-01-01 | 01 | 1 | TITL-01 | syntax | `zig ast-check src/Surface.zig` | n/a (Surface wiring) | pending |
| 05-01-02 | 01 | 1 | TITL-01, TITL-02, PROC-02 | unit | `zig build test -Dtest-cmd="src/input/Binding.zig"` | consumes W0 stubs | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [x] Task 0 writes failing test stubs in `src/input/Binding.zig` covering:
  - `[title=vim: main.zig]` exact match (TITL-01)
  - `[title=vim:*]` glob match (TITL-02)
  - `[process=nvim*]` glob match (PROC-02)
- [x] Test block `"RuntimeContext: matchesCondition title/process glob patterns"` covers wildcard edge cases
- [x] No new test files needed — all tests belong in existing `Binding.zig` test suite
- [x] Wave 0 is Task 0 in plan 05-01 — executes before Tasks 1 and 2

*Wave 0 addressed by Task 0 in 05-01-PLAN.md. Test stubs written before production code changes.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| runtime_context.title updated on set_title message | TITL-01 | Message handler in Surface cannot be unit-tested without full Surface init | Run ghostty, set title via `printf '\e]0;test title\a'`, verify binding fires |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (Task 0 creates stubs)
- [x] No watch-mode flags
- [x] Feedback latency < 15s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved
