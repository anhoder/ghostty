---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: Phase 2 — Evaluation Engine (Plan 01 complete)
status: planning
last_updated: "2026-03-18T05:47:31.329Z"
progress:
  total_phases: 6
  completed_phases: 2
  total_plans: 3
  completed_plans: 3
  percent: 100
---

# Project State: Ghostty 条件性快捷键配置

**Last updated:** 2026-03-18
**Session:** 4

---

## Project Reference

**Core value:** 用户可以根据当前运行的程序、窗口标题或用户变量动态切换快捷键绑定
**Repo:** /Users/anhoder/Desktop/ghostty
**Planning dir:** .planning/

---

## Current Position

**Current phase:** Phase 2 — Evaluation Engine (Plan 01 complete)
**Next phase:** Phase 3 — Process Name Detection
**Status:** Ready to plan

```
Progress: [██████████] 100%
```

---

## Phase Status

| Phase | Status | Plans | Completed |
|-------|--------|-------|-----------|
| 1. Config Syntax & Parsing | Complete | 2/2 | 01-01, 01-02 |
| 2. Evaluation Engine | In Progress | 1/? | 02-01 |
| 3. Process Name Detection | Not started | 0/? | - |
| 4. OSC 1337 & UserVar Conditions | Not started | 0/? | - |
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
| `src/Surface.zig` | runtime_context field, maybeHandleBinding/keyEventIsBinding use getEventConditional — Phase 2 complete |
| `src/termio/Exec.zig` | I/O thread, polling timer — Phase 3 |
| `src/os/process.zig` | New file — platform process detection — Phase 3 |
| `src/terminal/osc/parsers/iterm2.zig` | `SetUserVar` stub — Phase 4 |
| `src/termio/stream_handler.zig` | OSC dispatch — Phase 4 |
| `src/apprt/surface.zig` | `Message` union — Phases 3 & 4 |

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

---
*State initialized: 2026-03-18*
