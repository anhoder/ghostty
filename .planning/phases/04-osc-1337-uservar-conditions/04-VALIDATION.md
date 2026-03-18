---
phase: 4
slug: osc-1337-uservar-conditions
status: draft
nyquist_compliant: false
wave_0_complete: false
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
| 04-01-01 | 01 | 1 | UVAR-02 | unit | `zig build test -Dtest-filter="iterm2"` | ✅ | ⬜ pending |
| 04-01-02 | 01 | 1 | UVAR-02 | unit | `zig build test -Dtest-filter="osc"` | ✅ | ⬜ pending |
| 04-01-03 | 01 | 1 | UVAR-02 | unit | `zig build test -Dtest-filter="stream"` | ✅ | ⬜ pending |
| 04-02-01 | 02 | 1 | UVAR-03 | unit | `zig build test -Dtest-filter="Surface"` | ✅ | ⬜ pending |
| 04-02-02 | 02 | 1 | UVAR-01 | unit | `zig build test -Dtest-filter="Binding"` | ✅ | ⬜ pending |
| 04-02-03 | 02 | 1 | UVAR-04 | unit | `zig build test -Dtest-filter="Binding"` | ✅ | ⬜ pending |

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

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
