---
phase: 5
slug: window-title-glob-matching
status: draft
nyquist_compliant: false
wave_0_complete: false
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

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | TITL-01 | unit | `zig ast-check src/Surface.zig` | ❌ W0 | ⬜ pending |
| 05-01-02 | 01 | 1 | TITL-01 | unit | `zig build test -Dtest-cmd="src/input/Binding.zig"` | ❌ W0 | ⬜ pending |
| 05-02-01 | 02 | 2 | TITL-02, PROC-02 | unit | `zig build test -Dtest-cmd="src/input/Binding.zig"` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Extend `test "RuntimeContext: matchesCondition"` in `src/input/Binding.zig` to cover:
  - `[title=vim: main.zig]` exact match (TITL-01)
  - `[title=vim:*]` glob match (TITL-02)
  - `[process=nvim*]` glob match (PROC-02)
- [ ] Add `test "RuntimeContext: matchesCondition title/process glob patterns"` block covering wildcard edge cases
- [ ] No new test files needed — all tests belong in existing `Binding.zig` test suite

*Existing infrastructure covers framework needs. Only test cases need adding.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| runtime_context.title updated on set_title message | TITL-01 | Message handler in Surface cannot be unit-tested without full Surface init | Run ghostty, set title via `printf '\e]0;test title\a'`, verify binding fires |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
