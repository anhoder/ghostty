---
phase: 3
slug: process-name-detection
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-18
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | zig test (built-in) |
| **Config file** | build.zig |
| **Quick run command** | `zig build test -Dfilter="process"` |
| **Full suite command** | `zig build test` |
| **Estimated runtime** | ~5 seconds (filtered), ~30 seconds (full) |

---

## Sampling Rate

- **After every task commit:** Run `zig build test -Dfilter="process"`
- **After every plan wave:** Run `zig build test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 3-01-01 | 01 | 1 | PROC-03 | unit | `zig build test -Dfilter="process"` | ❌ W0 | ⬜ pending |
| 3-01-02 | 01 | 1 | PROC-04 | unit | `zig build test -Dfilter="process"` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `src/os/process.zig` — unit tests for getForegroundProcessName() on macOS and Linux
- [ ] Test fixtures for mocked PTY file descriptors
- [ ] Platform-conditional test compilation (@import("builtin").os.tag)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Process name updates within 200ms | PROC-03, PROC-04 | Timing-sensitive, requires real PTY | 1. Open Ghostty terminal<br>2. Run `vim`<br>3. Verify process-conditional keybind activates within 200ms<br>4. Exit vim<br>5. Verify keybind deactivates |
| Flatpak degradation | Success Criterion 4 | Requires Flatpak sandbox environment | 1. Run Ghostty in Flatpak<br>2. Check logs for one-time warning<br>3. Verify process= conditions don't match<br>4. Verify no crashes |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
