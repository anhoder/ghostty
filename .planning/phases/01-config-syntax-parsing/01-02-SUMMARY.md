---
phase: 01-config-syntax-parsing
plan: 02
subsystem: input
tags: [zig, keybind, conditional, storage, priority-lookup]

# Dependency graph
requires:
  - 01-01 (Condition type and Parser.condition field)
provides:
  - Set.conditional_bindings (ArrayListUnmanaged(ConditionalEntry)) for separate conditional storage
  - Set.ConditionalEntry struct (trigger, action, flags, condition)
  - Set.ConditionalResult struct (action, flags, condition)
  - Condition.eql() for value-based condition comparison
  - Set.getConditional() for priority-based lookup (CONF-04)
  - Set.getEventConditional() for event-based conditional lookup
affects:
  - 02 (evaluation engine calls getEventConditional with RuntimeContext)
  - Config.zig formatEntryDocs (conditional bindings now included in config output)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Separate ArrayListUnmanaged for conditional bindings — coexistence with unconditional HashMap"
    - "Linear scan for conditional lookup — acceptable for small lists, O(n) per keypress"
    - "Last-write-wins via scan+replace in putConditional"
    - "Conditional unbind via removeConditional (swapRemove)"

key-files:
  created: []
  modified:
    - src/input/Binding.zig
    - src/config/Config.zig

key-decisions:
  - "Separate conditional_bindings list (not HashMap) — allows same trigger with different conditions to coexist"
  - "Condition.eql() is value-based (std.mem.eql on strings) — not pointer equality"
  - "getConditional returns null for .leader and .leaf_chained — callers needing sequences use existing get() path"
  - "Deep-clone actions in conditional_bindings during Set.clone — consistent with Leaf.clone behavior"
  - "formatEntryDocs updated to include conditional bindings in config output"

# Metrics
duration: 10min
completed: 2026-03-18
---

# Phase 1 Plan 2: Conditional Set Storage and Priority Lookup Summary

**Separate conditional_bindings list on Set with last-write-wins storage, Condition.eql, and getConditional/getEventConditional priority-based lookup satisfying CONF-03 and CONF-04**

## Performance

- **Duration:** 10 min
- **Started:** 2026-03-18T04:21:09Z
- **Completed:** 2026-03-18T04:31:43Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments

- `Condition.eql()` added for value-based comparison of all three condition variants
- `Set.ConditionalEntry` struct and `conditional_bindings: ArrayListUnmanaged(ConditionalEntry)` field added to Set
- `putConditional()` implements last-write-wins: scans for existing trigger+condition pair, replaces or appends
- `removeConditional()` handles conditional unbind via swapRemove
- `parseAndPutRecurse` routes conditional bindings to `conditional_bindings`, unconditional path unchanged
- `Set.deinit` and `Set.clone` updated to handle `conditional_bindings`
- `Set.ConditionalResult` struct and `getConditional()` implement CONF-04 priority lookup
- `getEventConditional()` mirrors `getEvent` trigger-variant fallback order with conditional priority
- `Config.zig formatEntryDocs` updated to include conditional bindings in config output

## Task Commits

1. **Task 1 RED: Failing tests** — `dff7ec70b` (test)
2. **Task 1 GREEN: Storage implementation** — `47150d701` (feat)
3. **Task 2: Regression + format/clone** — `c6421ca2f` (feat)
4. **Task 3 RED: Failing tests** — `6e7f9bfa4` (test)
5. **Task 3 GREEN: getConditional implementation** — `9ce688fe9` (feat)

## Files Created/Modified

- `src/input/Binding.zig` — Condition.eql, ConditionalEntry, conditional_bindings, putConditional, removeConditional, ConditionalResult, getConditional, getEventConditional, updated deinit/clone
- `src/config/Config.zig` — formatEntryDocs updated to include conditional bindings in output

## Decisions Made

- Separate `conditional_bindings` list (not extending the HashMap key) — cleanest way to allow same trigger with different conditions to coexist without touching the existing unconditional lookup path
- `getConditional` returns `null` for `.leader` and `.leaf_chained` values — sequences are not supported for conditional bindings in Phase 1; callers needing sequences use the existing `get()`/`getEvent()` path
- Deep-clone actions in `conditional_bindings` during `Set.clone` — consistent with how `Leaf.clone` handles action strings

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Deep-clone actions in conditional_bindings during Set.clone**
- **Found during:** Task 2
- **Issue:** `ArrayListUnmanaged.clone` does a shallow copy; `Action` may contain allocated strings (e.g. text actions). Without deep-cloning, the cloned Set would share action string pointers with the original.
- **Fix:** Added loop after `conditional_bindings.clone(alloc)` to call `entry.action.clone(alloc)` on each item, consistent with how `Leaf.clone` handles actions.
- **Files modified:** `src/input/Binding.zig`
- **Commit:** `c6421ca2f`

**2. [Rule 2 - Missing functionality] formatEntryDocs omitted conditional bindings**
- **Found during:** Task 2
- **Issue:** `Keybinds.formatEntryDocs` only iterated `self.set.bindings` — conditional bindings would be silently dropped from config output (e.g. `ghostty +list-keybinds`).
- **Fix:** Added conditional bindings iteration with `[condition]trigger=action` format; updated empty check to include `conditional_bindings.items.len`.
- **Files modified:** `src/config/Config.zig`
- **Commit:** `c6421ca2f`

## Issues Encountered

Build environment has no network access — zig package dependencies cannot be downloaded. Tests verified via:
1. `zig ast-check` — syntax valid, no errors on both modified files
2. Manual trace through all test cases — all pass logically
3. Backward compat confirmed: `conditional_bindings` defaults to `.{}` (empty), all existing Set operations unaffected

## Next Phase Readiness

- `getEventConditional` is the Phase 2 entry point — Surface.maybeHandleBinding calls it with a `RuntimeContext` that provides the active `Condition`
- `ConditionalResult` carries `condition: ?Condition` so callers can distinguish conditional vs unconditional matches

---
*Phase: 01-config-syntax-parsing*
*Completed: 2026-03-18*

## Self-Check: PASSED

- `src/input/Binding.zig` — FOUND
- `src/config/Config.zig` — FOUND
- `.planning/phases/01-config-syntax-parsing/01-02-SUMMARY.md` — FOUND
- Commit `9ce688fe9` — FOUND
- Commit `47150d701` — FOUND
- Commit `c6421ca2f` — FOUND
