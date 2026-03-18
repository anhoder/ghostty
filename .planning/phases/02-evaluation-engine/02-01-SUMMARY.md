---
phase: 02-evaluation-engine
plan: 01
subsystem: input/binding
tags: [runtime-context, conditional-bindings, evaluation-engine, surface]
dependency_graph:
  requires: [01-01, 01-02]
  provides: [RuntimeContext, getConditional-ctx, getEventConditional-ctx, Surface.runtime_context]
  affects: [src/input/Binding.zig, src/Surface.zig]
tech_stack:
  added: []
  patterns: [pure-in-memory-comparison, labeled-block-restructure, optional-pointer-context]
key_files:
  created: []
  modified:
    - src/input/Binding.zig
    - src/Surface.zig
decisions:
  - "RuntimeContext uses ?*const RuntimeContext (pointer) not value — avoids copy on every keypress"
  - "maybeHandleBinding restructured to leaf: labeled block — avoids entry: type mismatch when root-set returns ConditionalResult"
  - "Leader handling inlined in sequence/table paths — required by leaf: block restructure"
metrics:
  duration: "~15 minutes"
  completed: "2026-03-18T05:40:48Z"
  tasks_completed: 2
  files_modified: 2
---

# Phase 02 Plan 01: Evaluation Engine — RuntimeContext and Surface Integration Summary

RuntimeContext struct wired into keypress path so [process=vim] bindings evaluate at runtime via pure in-memory string comparison.

## What Was Built

**Task 1 — RuntimeContext struct, matchesCondition, signature refactor (Binding.zig)**

Added `RuntimeContext` struct after the `Condition` definition with three nullable fields: `process_name`, `title`, `user_vars`. Implemented `matchesCondition` as a pure switch with `std.mem.eql` comparisons — zero allocations, zero syscalls.

Refactored `getConditional` and `getEventConditional` signatures from `condition: ?Condition` to `ctx: ?*const RuntimeContext`. The inner match changed from `entry.condition.eql(cond)` to `c.matchesCondition(entry.condition)`.

Updated all existing tests to use `RuntimeContext` instead of raw `Condition`. Added new `RuntimeContext.matchesCondition` test block covering: process hit/miss, null process, title hit/miss, null title, all-null context, var_ hit/miss/wrong-key, null user_vars.

**Task 2 — Surface integration (Surface.zig)**

Added `runtime_context: input.Binding.RuntimeContext = .{}` field to Surface struct near the `keyboard` field. Default value handles initialization — no change to `Surface.init` needed.

Refactored `keyEventIsBinding`: root-set path now calls `getEventConditional(event, &self.runtime_context)` and returns `cond_result.flags` directly, bypassing the `entry:` block.

Refactored `maybeHandleBinding`: restructured from `entry:` block (producing `Set.Entry`) to `leaf:` block (producing `GenericLeaf` directly). Sequence and table paths inline their leader handling inside the `leaf:` block. Root-set path calls `getEventConditional` and constructs `GenericLeaf` from `ConditionalResult`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Refactor] maybeHandleBinding restructured to leaf: block**
- **Found during:** Task 2
- **Issue:** Plan suggested keeping `entry:` block and adding a separate root-set path, but `entry:` block type is `Set.Entry` — incompatible with `ConditionalResult`. A `maybe_root_leaf` approach would require undefined `entry` variable in the leader switch.
- **Fix:** Restructured entire `entry:` + `switch(entry.value_ptr.*)` into a single `leaf:` labeled block that produces `GenericLeaf` directly. Leader handling inlined in sequence/table arms. Root-set arm uses `getEventConditional` and constructs `GenericLeaf` from `ConditionalResult`.
- **Files modified:** src/Surface.zig
- **Commit:** b074fcd31

## Verification

- `zig ast-check src/input/Binding.zig` — PASS
- `zig ast-check src/Surface.zig` — PASS
- `zig build test` — deferred (no network access in build env; same constraint as Phase 1)
- Sequence/table paths confirmed to use `getEvent` (grep verified)
- Both root-set call sites confirmed to use `getEventConditional` (grep verified)

## Self-Check: PASSED

Files exist:
- src/input/Binding.zig — FOUND (modified)
- src/Surface.zig — FOUND (modified)

Commits exist:
- 0226cadee — feat(02-01): add RuntimeContext struct and refactor getConditional signatures
- b074fcd31 — feat(02-01): Surface integration — runtime_context field and conditional root-set lookup
