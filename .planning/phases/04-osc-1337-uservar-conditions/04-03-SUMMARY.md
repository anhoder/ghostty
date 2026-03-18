---
phase: 04-osc-1337-uservar-conditions
plan: 03
subsystem: keybindings
tags: [zig, hashmap, glob, user-vars, runtime-context, osc-1337]

# Dependency graph
requires:
  - phase: 04-02
    provides: set_user_var message in surface.zig Message union with fixed-size name/value arrays
  - phase: 02-01
    provides: RuntimeContext struct with matchesCondition on Surface
provides:
  - User variables stored in RuntimeContext.user_vars hashmap (lazy-init, owned keys+values)
  - Glob pattern matching for var_ conditions via matchesGlob/globMatchImpl
  - Memory-safe update and cleanup of user_vars on replacement and deinit
affects: [Phase 5 - Window Title Glob Matching, Phase 6 - Platform Validation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Lazy hashmap init on first use (null -> .{} on first set_user_var message)
    - fetchRemove pattern for key+value replacement without leaks
    - Private glob matcher with fast exact-match short-circuit (no wildcards check first)
    - Backtracking glob algorithm with star_pi/star_si tracking for * wildcard

key-files:
  created: []
  modified:
    - src/Surface.zig
    - src/input/Binding.zig

key-decisions:
  - "Lazy-init user_vars hashmap: initialize to .{} only on first set_user_var message to avoid empty hashmap overhead"
  - "fetchRemove pattern for old key+value cleanup: avoids get+remove dance, correctly frees both key and value"
  - "Fast path for exact match: check indexOfAny for wildcards first, skip glob engine when no * or ? present"
  - "Inline glob matcher (globMatchImpl): Zig 0.15.2 stdlib has no path.match or glob API; implemented backtracking algorithm"
  - "Renamed message capture from |msg| to |uvar|: Zig treats shadowing of function parameter as compile error"

patterns-established:
  - "Pattern: Glob matching with fast exact-match path - always check for wildcards before calling glob engine"
  - "Pattern: fetchRemove for hashmap value replacement - free old key+value atomically"

requirements-completed: [UVAR-01, UVAR-03, UVAR-04]

# Metrics
duration: 5min
completed: 2026-03-18
---

# Phase 4 Plan 03: User Variable Storage and Glob Matching Summary

**OSC 1337 SetUserVar stored in RuntimeContext hashmap with backtracking glob matcher for `*`/`?` wildcard patterns in var_ keybinding conditions**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-18T08:45:59Z
- **Completed:** 2026-03-18T08:51:00Z
- **Tasks:** 2 (Task 1 direct, Task 2 TDD with 2 commits)
- **Files modified:** 2

## Accomplishments
- Surface now handles `.set_user_var` messages: lazy-init hashmap, free old value on update, dupe name+value into Surface allocator
- deinit cleans up all user_vars entries (keys + values freed, hashmap deinitialized)
- matchesCondition var_ case now supports glob patterns via inline backtracking algorithm
- Fast path: exact match used when pattern has no `*` or `?` (avoids glob overhead for common case)

## Task Commits

Each task was committed atomically:

1. **Task 1: Handle set_user_var message in Surface** - `1a5a87b70` (feat)
2. **Task 2 RED: Add failing glob tests** - `d7b7503d6` (test)
3. **Task 2 GREEN: Add glob matching to var_ condition evaluation** - `5df325e25` (feat)

_Note: TDD Task 2 has two commits (test → feat)_

## Files Created/Modified
- `src/Surface.zig` - Added set_user_var handler and user_vars deinit cleanup
- `src/input/Binding.zig` - Added matchesGlob/globMatchImpl, updated var_ case, added 14 glob tests

## Decisions Made
- Lazy-init user_vars hashmap (null -> .{}) on first set_user_var message to avoid overhead
- fetchRemove pattern correctly frees old key+value atomically on variable replacement
- Renamed message capture `|msg|` to `|uvar|` to avoid Zig compile error on parameter shadowing
- Implemented inline glob matcher: Zig 0.15.2 stdlib has no glob API (confirmed: no std.fs.path.match, no std.mem.match)
- Fast path checks for wildcards first via `std.mem.indexOfAny(u8, pattern, "*?")` before calling glob engine

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Renamed message capture to avoid parameter shadowing compile error**
- **Found during:** Task 1 (set_user_var handler)
- **Issue:** `handleMessage` takes parameter `msg: Message`, capturing `.set_user_var => |msg|` shadows it — Zig compile error
- **Fix:** Renamed capture to `|uvar|` throughout the handler
- **Files modified:** src/Surface.zig
- **Verification:** `zig ast-check src/Surface.zig` passes
- **Committed in:** 1a5a87b70 (Task 1 commit)

**2. [Rule 3 - Blocking] Implemented inline glob matcher (no stdlib API available)**
- **Found during:** Task 2 (glob matching implementation)
- **Issue:** Plan referenced `std.mem.match` and `std.fs.path.match` but Zig 0.15.2 stdlib has neither
- **Fix:** Implemented `matchesGlob` (fast path) and `globMatchImpl` (backtracking) inline in RuntimeContext
- **Files modified:** src/input/Binding.zig
- **Verification:** `zig ast-check src/input/Binding.zig` passes; 14 test cases cover exact, *, ?, complex patterns
- **Committed in:** 5df325e25 (Task 2 GREEN commit)

---

**Total deviations:** 2 auto-fixed (1 bug/shadowing, 1 blocking/missing API)
**Impact on plan:** Both auto-fixes necessary for correctness. No scope creep.

## Issues Encountered
- Zig 0.15.2 standalone `zig test src/input/Binding.zig` fails due to cross-package imports; ast-check used for syntax verification instead.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Full OSC 1337 user variable pipeline is now operational end-to-end:
  iTerm2 OSC parser -> stream dispatch -> mailbox message -> Surface hashmap -> matchesCondition glob evaluation
- Phase 5 (Window Title & Glob Matching) can build on the glob infrastructure established here
- Phase 4 is complete: all 3 plans (04-01, 04-02, 04-03) done

---
*Phase: 04-osc-1337-uservar-conditions*
*Completed: 2026-03-18*
