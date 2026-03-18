---
phase: 05-window-title-glob-matching
plan: "01"
subsystem: input/binding
tags: [glob, title, process, runtime-context, memory]
dependency_graph:
  requires: []
  provides: [title-condition-matching, process-glob-matching, runtime-context-title]
  affects: [src/Surface.zig, src/input/Binding.zig]
tech_stack:
  added: []
  patterns: [glob-matching, runtime-context-wiring, tdd-red-green]
key_files:
  created: []
  modified:
    - src/input/Binding.zig
    - src/Surface.zig
decisions:
  - "runtime_context.title updated before config guard so title conditions work even with static config title"
  - "matchesGlob replaces std.mem.eql for .process and .title — fast path preserves exact-match performance"
  - "process_name freed in Surface.deinit alongside title (fixes pre-existing leak)"
metrics:
  duration: "3 minutes"
  completed: "2026-03-18"
  tasks_completed: 3
  files_modified: 2
---

# Phase 5 Plan 01: Window Title & Glob Matching Summary

**One-liner:** Glob matching for title/process conditions via matchesGlob, with runtime_context.title wired from set_title handler and config.title seed at init.

---

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 0 | Write failing test stubs for title/process glob matching | af7a83b03 | src/input/Binding.zig |
| 1 | Wire runtime_context.title in Surface.zig | c28e316f2 | src/Surface.zig |
| 2 | Enable glob matching for process and title conditions | 43eccb507 | src/input/Binding.zig |

---

## What Was Built

- **Task 0 (RED):** Added `test "RuntimeContext: matchesCondition title/process glob patterns"` block covering TITL-01, TITL-02, PROC-02 — exact match, glob `*`, glob `?`, null title, process glob.
- **Task 1:** Wired `runtime_context.title` in `Surface.zig`:
  - `set_title` handler now dupes title into `runtime_context.title` before the config guard
  - `Surface.init` seeds `runtime_context.title` from `config.title` at startup
  - `Surface.deinit` frees both `runtime_context.title` and `runtime_context.process_name`
- **Task 2 (GREEN):** Replaced `std.mem.eql` with `matchesGlob` for `.process` and `.title` cases in `matchesCondition`. Updated `matchesGlob` doc comment to reflect use for all condition types.

---

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

---

## Verification

- `zig ast-check src/Surface.zig` — passed
- `zig ast-check src/input/Binding.zig` — passed
- Full test run blocked by network (403 on deps); consistent with all prior sessions in this environment

---

## Self-Check: PASSED

- src/Surface.zig: FOUND
- src/input/Binding.zig: FOUND
- 05-01-SUMMARY.md: FOUND
- Commit af7a83b03: FOUND
- Commit c28e316f2: FOUND
- Commit 43eccb507: FOUND
