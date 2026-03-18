---
phase: 04-osc-1337-uservar-conditions
plan: "01"
subsystem: terminal
tags: [osc, iterm2, uservar, osc-1337, parser, stream]

requires:
  - phase: 03-process-name-detection
    provides: process_name_update message pipeline and Surface runtime_context

provides:
  - OSC 1337 SetUserVar parsing (name + base64 data as null-terminated slices)
  - Command.set_user_var variant in osc.zig
  - oscDispatch routing set_user_var to handler.vt in stream.zig

affects:
  - 04-02 (handler implementation that consumes set_user_var action)
  - Surface.zig (will need set_user_var vt handler)

tech-stack:
  added: []
  patterns:
    - "OSC parser: split value_ on first '=' to extract sub-fields as null-terminated slices"
    - "Command union: add variant + Key enum entry + reset() switch arm together"
    - "Stream dispatch: add Action field + Key enum entry + oscDispatch case together"

key-files:
  created: []
  modified:
    - src/terminal/osc/parsers/iterm2.zig
    - src/terminal/osc.zig
    - src/terminal/stream.zig

key-decisions:
  - "Rename local name/data to var_name/var_data in iterm2.zig to avoid shadowing outer 'data' constant"
  - "Empty data treated as invalid (return null) — base64 payload must be non-empty"
  - "SetUserVar struct defined inline in Action (not reusing osc.Command type) for clean handler API"

patterns-established:
  - "SetUserVar parser: value_ split on first '=' gives name slice; remainder is base64 data slice"

requirements-completed: [UVAR-02]

duration: 6min
completed: 2026-03-18
---

# Phase 4 Plan 01: OSC 1337 SetUserVar Parsing Summary

**OSC 1337 SetUserVar parsed end-to-end: iterm2.zig extracts name+base64 slices, Command.set_user_var carries them, stream.zig routes to handler.vt**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-03-18T08:27:26Z
- **Completed:** 2026-03-18T08:32:41Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments
- SetUserVar case moved out of unimplemented catch-all; parses `<name>=<base64>` wire format
- `Command.set_user_var` variant added to osc.zig with correct size constraint compliance
- `oscDispatch` routes `.set_user_var` to `handler.vt(.set_user_var, ...)` in stream.zig
- 5 tests added covering valid parse and all invalid edge cases

## Task Commits

1. **Task 1: SetUserVar parser in iterm2.zig** - `71553e1b0` (feat)
2. **Task 2: set_user_var Command variant in osc.zig** - `eee08608e` (feat)
3. **Task 3: set_user_var dispatch in stream.zig** - `55da6226d` (feat)

## Files Created/Modified
- `src/terminal/osc/parsers/iterm2.zig` - SetUserVar case + 5 tests
- `src/terminal/osc.zig` - Command.set_user_var struct, Key enum, reset() arm
- `src/terminal/stream.zig` - Action.set_user_var, Key enum, oscDispatch case

## Decisions Made
- Renamed local `name`/`data` to `var_name`/`var_data` to avoid shadowing the outer `data` constant from `writer.buffered()` — Zig treats this as a compile error.
- Empty `data` field returns null (invalid) — a SetUserVar with no base64 payload is meaningless.
- `Action.SetUserVar` defined as its own struct in stream.zig rather than aliasing `osc.Command.set_user_var` anonymous struct, keeping the handler API explicit.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Variable shadowing in iterm2.zig**
- **Found during:** Task 1 (SetUserVar parser)
- **Issue:** Local `const data` shadowed outer `const data = writer.buffered()` — `zig ast-check` error
- **Fix:** Renamed to `var_name` / `var_data`
- **Files modified:** src/terminal/osc/parsers/iterm2.zig
- **Verification:** `zig ast-check` passes with no output
- **Committed in:** 71553e1b0 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - bug)
**Impact on plan:** Necessary correctness fix, no scope change.

## Issues Encountered
None beyond the shadowing fix above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- OSC 1337 SetUserVar parse pipeline complete
- Next: implement `set_user_var` vt handler on Surface to store variables in `runtime_context` and trigger conditional binding re-evaluation

---
*Phase: 04-osc-1337-uservar-conditions*
*Completed: 2026-03-18*
