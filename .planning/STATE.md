---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: Phase 4 — OSC 1337 & UserVar Conditions (In Progress)
status: Ready
last_updated: "2026-03-18T08:52:22.201Z"
progress:
  total_phases: 6
  completed_phases: 4
  total_plans: 8
  completed_plans: 8
  percent: 100
---

# Project State: Ghostty 条件性快捷键配置

**Last updated:** 2026-03-18
**Session:** 7

---

## Project Reference

**Core value:** 用户可以根据当前运行的程序、窗口标题或用户变量动态切换快捷键绑定
**Repo:** /Users/anhoder/Desktop/ghostty
**Planning dir:** .planning/

---

## Current Position

**Current phase:** Phase 5 — Window Title & Glob Matching
**Next phase:** Phase 6 — Platform Validation & Documentation
**Status:** Ready

```
Progress: [██████████] 100%
```

---

## Phase Status

| Phase | Status | Plans | Completed |
|-------|--------|-------|-----------|
| 1. Config Syntax & Parsing | Complete | 2/2 | 01-01, 01-02 |
| 2. Evaluation Engine | Complete | 1/1 | 02-01 |
| 3. Process Name Detection | Complete | 2/2 | 03-01, 03-02 |
| 4. OSC 1337 & UserVar Conditions | Complete | 3/3 | 04-01, 04-02, 04-03 |
| 5. Window Title & Glob Matching | Not started | 0/? | - |
| 6. Platform Validation & Documentation | Not started | 0/? | - |

---

## Accumulated Context

### Key Decisions

| Decision | Rationale | Status |
|----------|-----------|--------|
| Bracket syntax `[process=vim]` for conditions | Avoids collision with existing `=`, `:`, `>`, `/` delimiters in keybind parser | Pending maintainer confirmation |
| Separate `RuntimeContext` struct on `Surface` | `conditional.State` is intentionally static (config-time only); runtime state needs its own struct | Confirmed by research |
| 200ms async polling via xev timer in `Exec.zig` | Matches existing `TERMIOS_POLL_MS`; keeps keypress path syscall-free | Confirmed by research |
| Conditional bindings stored in `ConditionSet`, not `Binding.Set` | Clean overlay model; no modification to existing binding infrastructure | Confirmed by research |
| Glob compiled at config-load time | Prevents per-keypress pattern compilation (50–500 µs regression) | Confirmed by research |
| Condition co-located in Binding.zig (not separate file) | Follows existing pattern of Flags/Trigger/Action; keeps Parser and Condition together | Implemented in 01-01 |
| Condition values are slice refs into input (no allocation) | Consistent with Action.parse() pattern; allocation deferred to Set.parseAndPut() arena | Implemented in 01-01 |
| v1: single condition only, multiple conditions return InvalidFormat | Simplest correct behavior; can relax in future | Implemented in 01-01 |
| Separate conditional_bindings list on Set | Allows same trigger with different conditions to coexist without modifying unconditional HashMap | Implemented in 01-02 |
| getConditional returns null for .leader/.leaf_chained | Sequences not supported for conditional bindings in Phase 1; callers use existing get()/getEvent() | Implemented in 01-02 |
| Deep-clone actions in conditional_bindings during Set.clone | Consistent with Leaf.clone behavior; prevents dangling pointers after original input freed | Implemented in 01-02 |
| RuntimeContext uses ?*const RuntimeContext pointer | Avoids copy on every keypress; null means "no context available" | Implemented in 02-01 |
| maybeHandleBinding restructured to leaf: labeled block | Avoids entry: type mismatch when root-set returns ConditionalResult instead of Set.Entry | Implemented in 02-01 |
| Use WriteReq for process_name_update message | Consistent with pwd_change pattern; efficient string transfer via mailbox | Implemented in 03-01 |
| Return null for unsupported platforms in process detection | Graceful degradation; no error propagation needed | Implemented in 03-01 |
| Arena allocator for process name in I/O thread | Temporary allocation cleaned up periodically; ownership transferred via mailbox | Implemented in 03-02 |
| No deduplication in I/O thread | Surface handles deduplication if needed; simpler I/O thread logic | Implemented in 03-02 |
| Rename local name/data to var_name/var_data in iterm2.zig | Zig treats shadowing of outer const as compile error; rename required for correctness | Implemented in 04-01 |
| Empty data field returns null in SetUserVar parser | A SetUserVar with no base64 payload is meaningless; consistent with other iTerm2 parser validation | Implemented in 04-01 |
| Action.SetUserVar defined as own struct in stream.zig | Keeps handler API explicit rather than aliasing anonymous osc.Command struct | Implemented in 04-01 |
| Fixed-size arrays (name[63:0], value[191:0]) for set_user_var message | Follows desktop_notification pattern; predictable message size, no heap allocation | Implemented in 04-02 |
| Stack decode buffer (256 bytes) for base64 in setUserVar | Avoids heap allocation in hot path; sufficient for typical user var values | Implemented in 04-02 |
| Truncate-with-warn on oversized names/values | Prefer delivering partial data over dropping message silently | Implemented in 04-02 |
| Lazy-init user_vars hashmap on first set_user_var | Avoid empty hashmap overhead; init .{} only when first variable arrives | Implemented in 04-03 |
| Inline glob matcher (matchesGlob/globMatchImpl) | Zig 0.15.2 stdlib has no path.match or glob API; backtracking algorithm with fast exact-match short-circuit | Implemented in 04-03 |

### Open Questions (resolve before or during implementation)

1. **Config syntax delimiter:** `when:process=vim>ctrl+w=action` vs `[process=vim]ctrl+w=action` — needs maintainer input before Phase 1
2. **`std.fs.path.match` vs custom glob:** Verify whether stdlib glob handles `*`/`?` without path-separator semantics for process names
3. **UserVar allocator strategy:** Use `Surface`'s GPA allocator; explicit dealloc on `deinit` and on key replacement
4. **Config-defined vs OSC-set UserVar precedence:** OSC takes precedence (runtime overrides static config)
5. **Flatpak degradation:** Log one-time warning at startup; treat `process=` conditions as always-false when detection unavailable

### Known Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Per-keypress syscall latency | HIGH | Cache all state; update only via mailbox + 200ms timer |
| Config syntax delimiter collision | HIGH | Use bracket prefix; run full Binding.zig test suite before merge |
| Process-change race condition | HIGH | Accept ~1–5ms window; document it; recommend UserVar for latency-critical cases |
| Config reload with active key table | MEDIUM | Call `deactivateAllKeyTables()` before swapping config |

### Key Files

| File | Role |
|------|------|
| `src/input/Binding.zig` | RuntimeContext, matchesCondition, getConditional/getEventConditional with ?*const RuntimeContext — Phase 2 complete |
| `src/config/Config.zig` | `Keybinds` struct — updated formatEntryDocs for conditional bindings |
| `src/Surface.zig` | runtime_context field, process_name_update handler, maybeHandleBinding/keyEventIsBinding use getEventConditional — Phase 3 complete |
| `src/termio/Exec.zig` | detectProcessName in termiosTimer, 200ms polling — Phase 3 complete |
| `src/os/process.zig` | Platform process detection — Phase 3 complete |
| `src/os/main.zig` | Export process module — Phase 3 complete |
| `src/apprt/surface.zig` | `Message` union with process_name_update — Phase 3 complete |
| `src/terminal/osc/parsers/iterm2.zig` | `SetUserVar` parser — Phase 4 plan 01 complete |
| `src/terminal/osc.zig` | `Command.set_user_var` variant — Phase 4 plan 01 complete |
| `src/terminal/stream.zig` | `oscDispatch` set_user_var case — Phase 4 plan 01 complete |
| `src/termio/stream_handler.zig` | OSC dispatch — Phase 4 complete (04-02) |
| `src/apprt/surface.zig` | `Message` union with set_user_var — Phase 4 plan 02 complete |
| `src/Surface.zig` | set_user_var handler, user_vars deinit — Phase 4 plan 03 complete |

---

## Session Log

### Session 1 — 2026-03-18
- Initialized project via `/gsd:new-project`
- Research completed (HIGH confidence)
- Requirements defined: 18 v1, 4 v2
- Roadmap created: 6 phases, 18/18 requirements mapped
- Next: `/gsd:plan-phase 1`

### Session 2 — 2026-03-18
- Executed plan 01-01: Condition type and parser extension
- Implemented Condition tagged union, parseCondition(), updated Parser.init/next
- Tests written (TDD); syntax verified via zig ast-check
- Build env has no network access — full test run deferred
- Stopped at: Completed 01-config-syntax-parsing-01-01-PLAN.md

### Session 3 — 2026-03-18
- Executed plan 01-02: Conditional Set storage and priority lookup
- Implemented conditional_bindings, Condition.eql, putConditional, removeConditional
- Implemented getConditional, getEventConditional (CONF-03, CONF-04)
- Fixed formatEntryDocs to include conditional bindings in config output
- Phase 1 complete — all 2 plans done
- Stopped at: Completed 01-config-syntax-parsing-01-02-PLAN.md

### Session 4 — 2026-03-18
- Executed plan 02-01: RuntimeContext and Surface integration
- Added RuntimeContext struct with matchesCondition (zero-alloc, zero-syscall)
- Refactored getConditional/getEventConditional to ?*const RuntimeContext
- Added Surface.runtime_context field; wired both root-set call sites to getEventConditional
- Restructured maybeHandleBinding to leaf: block (deviation from plan — required by type system)
- Stopped at: Completed 02-evaluation-engine-02-01-PLAN.md

### Session 5 — 2026-03-18
- Executed plan 03-01: Process detection infrastructure
- Created src/os/process.zig with getForegroundProcessName API
- Linux: tcgetpgrp + /proc/<pid>/comm lookup
- macOS: tcgetpgrp + libproc proc_pidinfo
- Added process_name_update message type to surface.zig
- Stopped at: Completed 03-process-name-detection-03-01-PLAN.md

### Session 6 — 2026-03-18
- Executed plan 03-02: Async process detection integration
- Added detectProcessName to termiosTimer (200ms polling)
- Implemented process_name_update handler in Surface
- Exported process module in os/main.zig
- Phase 3 complete — end-to-end process detection operational
- Stopped at: Completed 03-process-name-detection-03-02-PLAN.md

### Session 7 — 2026-03-18
- Executed plan 04-01: OSC 1337 SetUserVar parsing
- Implemented SetUserVar parser in iterm2.zig (name + base64 slices, 5 tests)
- Added Command.set_user_var to osc.zig (Key enum, reset() arm)
- Added set_user_var dispatch in stream.zig (Action type, Key enum, oscDispatch case)
- Auto-fixed: variable shadowing (var_name/var_data rename)
- Stopped at: Completed 04-osc-1337-uservar-conditions-04-01-PLAN.md

### Session 8 — 2026-03-18
- Executed plan 04-02: SetUserVar mailbox bridge
- Added set_user_var message variant to surface.zig (fixed-size name[63:0]/value[191:0] arrays)
- Implemented setUserVar handler in stream_handler.zig (base64 decode, truncate-with-warn, surfaceMessageWriter)
- Wired set_user_var case into vtFallible switch
- Stopped at: Completed 04-osc-1337-uservar-conditions-04-02-PLAN.md

### Session 9 — 2026-03-18
- Executed plan 04-03: User variable storage and glob matching
- Added set_user_var handler in Surface.zig (lazy-init hashmap, fetchRemove on update, dupe to Surface allocator)
- Added user_vars deinit cleanup in Surface.deinit
- Implemented matchesGlob/globMatchImpl (backtracking * and ? glob matching) in RuntimeContext
- Updated matchesCondition var_ case to use glob matching with fast exact-match short-circuit
- Phase 4 complete: all 3 plans done, full user variable pipeline operational
- Stopped at: Completed 04-osc-1337-uservar-conditions-04-03-PLAN.md

---
