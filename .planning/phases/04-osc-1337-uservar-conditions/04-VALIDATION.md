---
phase: 4
slug: osc-1337-uservar-conditions
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-18
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Zig built-in test (`zig build test`) |
| **Config file** | build.zig (existing) |
| **Quick run command** | `zig build test -Dtest-filter="osc"` |
| **Full suite command** | `zig build test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `zig build test -Dtest-filter="osc"` (or relevant filter)
- **After every plan wave:** Run `zig build test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | UVAR-02 | unit | `zig ast-check src/terminal/osc/parsers/iterm2.zig` | ✅ | ⬜ pending |
| 04-01-02 | 01 | 1 | UVAR-02 | unit | `zig ast-check src/terminal/osc.zig` | ✅ | ⬜ pending |
| 04-01-03 | 01 | 1 | UVAR-02 | unit | `zig ast-check src/terminal/stream.zig && grep -n "set_user_var" src/terminal/stream.zig` | ✅ | ⬜ pending |
| 04-02-01 | 02 | 2 | UVAR-03 | unit | `zig ast-check src/apprt/surface.zig && grep -n "set_user_var:" src/apprt/surface.zig` | ✅ | ⬜ pending |
| 04-02-02 | 02 | 2 | UVAR-02 | unit | `zig ast-check src/termio/stream_handler.zig && grep -n "setUserVar" src/termio/stream_handler.zig` | ✅ | ⬜ pending |
| 04-03-01 | 03 | 3 | UVAR-01 | unit | `zig ast-check src/Surface.zig && grep -n "set_user_var" src/Surface.zig` | ✅ | ⬜ pending |
| 04-03-02 | 03 | 3 | UVAR-04 | unit | `zig ast-check src/input/Binding.zig && zig test src/input/Binding.zig -freference-trace` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements. Zig built-in test framework already in place.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Shell script emitting OSC 1337 SetUserVar updates RuntimeContext | UVAR-02 | End-to-end requires running terminal | 1. Run `printf '\e]1337;SetUserVar=in_vim=MQ==\a'` 2. Verify keybinding triggers |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
