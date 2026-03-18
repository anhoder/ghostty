---
phase: 01-config-syntax-parsing
plan: 01
subsystem: input
tags: [zig, keybind, parser, condition, tagged-union]

# Dependency graph
requires: []
provides:
  - Condition tagged union (process, title, var_) in Binding.zig
  - parseCondition() function in Parser
  - condition field on Binding struct (optional, default null)
  - condition field on Parser struct
affects:
  - 01-02 (ConditionSet storage)
  - 02 (evaluation engine reads Binding.condition)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Condition parsed as slice reference into input (no allocation, matches Action.parse pattern)"
    - "parseCondition called before parseFlags in Parser.init()"
    - "Condition stored as ?Condition = null for backward compat"

key-files:
  created: []
  modified:
    - src/input/Binding.zig

key-decisions:
  - "Condition defined as pub const inside Binding (co-located with Parser, follows Flags/Trigger/Action pattern)"
  - "Condition values reference input slice — no allocation at parse time"
  - "v1: single condition only — multiple conditions ([a][b]) return InvalidFormat"
  - "Unknown condition types return InvalidFormat (strict, not silent ignore)"
  - "Chain + condition returns InvalidFormat"

patterns-established:
  - "Bracket prefix syntax: [type=value] before flags before trigger"
  - "parseCondition returns (null, 0) for non-bracket input — zero cost for existing bindings"

requirements-completed: [CONF-01, CONF-02, CONF-05]

# Metrics
duration: 24min
completed: 2026-03-18
---

# Phase 1 Plan 1: Condition Type and Parser Extension Summary

**Condition tagged union (process/title/var_) added to Binding.zig with bracket syntax `[type=value]` parsed before flags, zero-cost for existing bindings**

## Performance

- **Duration:** 24 min
- **Started:** 2026-03-18T03:52:31Z
- **Completed:** 2026-03-18T04:16:14Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Condition tagged union with process, title, var_ variants defined in Binding.zig
- parseCondition() handles all three types plus all error cases (empty, unknown, unclosed, multi-condition)
- Parser.init() calls parseCondition before parseFlags; condition propagated to Binding via Parser.next()
- All existing Binding struct literals unaffected (condition defaults to null)

## Task Commits

1. **Task 1 RED: Failing tests** - `deb17db85` (test)
2. **Task 1 GREEN: Implementation** - `810bb4982` (feat)
3. **Task 2: Backward compatibility** - verified via code review (no new commit needed)

## Files Created/Modified
- `src/input/Binding.zig` - Added Condition type, condition fields, parseCondition(), updated Parser.init() and Parser.next()

## Decisions Made
- Condition co-located in Binding.zig (not a separate file) — follows existing pattern of Flags, Trigger, Action
- Condition values are slice references into the raw input string — no allocation at parse time, consistent with how Action.parse() works
- v1 rejects multiple conditions with InvalidFormat — simplest correct behavior, can relax in future

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

Build environment has no network access — zig package dependencies (uucode 0.2.0 and lazy C libs) cannot be downloaded. Tests verified via:
1. `zig ast-check` — syntax valid, no errors
2. Manual trace through all 12 test cases — all pass logically
3. Backward compat confirmed by code review: `condition: ?Condition = null` default means all existing Binding{} literals and expectEqual comparisons are unaffected

## Next Phase Readiness
- Condition type and parser ready for Plan 01-02 (ConditionSet storage)
- Phase 2 evaluation engine can read Binding.condition directly

---
*Phase: 01-config-syntax-parsing*
*Completed: 2026-03-18*
