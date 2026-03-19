---
phase: 6
slug: platform-validation-documentation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-19
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Zig built-in test runner |
| **Config file** | none — inline `test` blocks in .zig files |
| **Quick run command** | `zig ast-check src/config/Config.zig` |
| **Full suite command** | `zig build test -Dtest-filter="RuntimeContext" && zig build test -Dtest-filter="conditional" && zig build test -Dtest-filter="getConditional"` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `zig ast-check src/config/Config.zig`
- **After every plan wave:** Run `zig build test -Dtest-filter="RuntimeContext"`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 06-01-01 | 01 | 1 | PLAT-01, PLAT-02 | unit | `zig build test -Dtest-filter="RuntimeContext"` | ✅ | ⬜ pending |
| 06-01-02 | 01 | 1 | PLAT-01, PLAT-02 | syntax | `zig ast-check src/config/Config.zig` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `src/config/Config.zig` — `## Conditional Bindings` doc section (covers PLAT-01, PLAT-02 documentation requirement)
- No new test files needed — existing test infrastructure covers all automated requirements

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| macOS process detection happy-path | PLAT-01 | Requires live PTY with libproc | Open Ghostty on macOS, run `vim`, verify `[process=vim]` binding fires |
| Linux process detection happy-path | PLAT-02 | Requires live PTY with /proc/comm | Open Ghostty on Linux, run `vim`, verify `[process=vim]` binding fires |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
