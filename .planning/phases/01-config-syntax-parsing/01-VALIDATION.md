---
phase: 1
slug: config-syntax-parsing
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-18
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Zig built-in test (`zig build test`) |
| **Config file** | build.zig — no separate test config |
| **Quick run command** | `zig test src/input/Binding.zig` |
| **Full suite command** | `zig build test` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `zig test src/input/Binding.zig`
- **After every plan wave:** Run `zig build test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 0 | CONF-01 | unit | `zig test src/input/Binding.zig -Dtest-filter="parse: conditional"` | ❌ W0 | ⬜ pending |
| 01-01-02 | 01 | 0 | CONF-01 | unit | `zig test src/input/Binding.zig -Dtest-filter="parse: conditional errors"` | ❌ W0 | ⬜ pending |
| 01-01-03 | 01 | 0 | CONF-03 | unit | `zig test src/input/Binding.zig -Dtest-filter="Set.parseAndPut: conditional"` | ❌ W0 | ⬜ pending |
| 01-01-04 | 01 | 0 | CONF-05 | unit | `zig test src/input/Binding.zig` | ✅ | ⬜ pending |
| 01-01-05 | 01 | 1 | CONF-02 | unit | `zig test src/input/Binding.zig` (full suite) | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test "parse: conditional bindings"` — stubs for CONF-01 (valid syntax parsing)
- [ ] `test "parse: conditional errors"` — stubs for CONF-01 (error cases: empty value, unknown type, unclosed bracket, multi-condition)
- [ ] `test "Set.parseAndPut: conditional overwrite"` — stubs for CONF-03 (last-write-wins)
- [ ] Extend existing tests with `condition == null` assertions — covers CONF-05

*Existing infrastructure covers CONF-02 and CONF-05 via 400+ existing test cases in Binding.zig lines 2810-3275.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Conditional priority over unconditional | CONF-04 | Requires ConditionSet runtime lookup (Phase 2) | Verify in Phase 2 when runtime evaluation is implemented |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
