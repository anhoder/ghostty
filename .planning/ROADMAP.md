# Roadmap: Ghostty 条件性快捷键配置

**Project:** Ghostty Conditional Keybindings
**Created:** 2026-03-18
**Granularity:** Standard (6 phases)
**Coverage:** 18/18 v1 requirements mapped

---

## Phases

- [x] **Phase 1: Config Syntax & Parsing** - Extend the keybind parser with conditional syntax; establish ConditionSet data model (completed 2026-03-18)
- [x] **Phase 2: Evaluation Engine** - Wire RuntimeContext into Surface and implement condition evaluation on the keypress path (completed 2026-03-18)
- [x] **Phase 3: Process Name Detection** - Platform-specific foreground process polling; end-to-end process-name exact match (completed 2026-03-18)
- [x] **Phase 4: OSC 1337 & UserVar Conditions** - Implement SetUserVar pipeline; add UserVar condition type (completed 2026-03-18)
- [ ] **Phase 5: Window Title & Glob Matching** - Add window_title condition type; add glob pattern support for all condition types
- [ ] **Phase 6: Platform Validation & Documentation** - Cross-platform verification; keybind doc comment update

---

## Phase Details

### Phase 1: Config Syntax & Parsing
**Goal**: Users can write conditional keybindings in their config file using Ghostty-native syntax, and existing configs continue to work unchanged
**Depends on**: Nothing (first phase)
**Requirements**: CONF-01, CONF-02, CONF-03, CONF-04, CONF-05
**Success Criteria** (what must be TRUE):
  1. A user can add `keybind = [process=vim]ctrl+w=close_surface` to their config and Ghostty loads it without error
  2. All existing keybind entries in a real config file parse identically before and after the change (full Binding.zig test suite passes)
  3. A later conditional binding for the same trigger+condition overwrites an earlier one (last-write wins)
  4. A conditional binding for a trigger takes priority over an unconditional binding for the same trigger
  5. An invalid condition clause (e.g. `[unknown=foo]`) produces a clear parse error, not a silent no-op
**Plans:** 2/2 plans complete

Plans:
- [ ] 01-01-PLAN.md — Define Condition tagged union, parseCondition(), extend Parser/Binding structs
- [ ] 01-02-PLAN.md — Extend Set storage for conditional bindings, last-write-wins, coexistence model

### Phase 2: Evaluation Engine
**Goal**: Conditional bindings are evaluated on every keypress using cached runtime state, with correct priority and zero syscalls on the hot path
**Depends on**: Phase 1
**Requirements**: PROC-01, PROC-05
**Success Criteria** (what must be TRUE):
  1. When `RuntimeContext.process_name` is set to `"vim"`, pressing a key bound with `[process=vim]` triggers the conditional action instead of the unconditional fallback
  2. When no condition matches, the unconditional binding fires as before — no regression
  3. Keypress latency is not measurably affected (condition evaluation reads only in-memory strings, no syscalls)
  4. Unit tests cover: match hit, match miss, empty context, and priority ordering
**Plans:** 1/1 plans complete

Plans:
- [ ] 02-01-PLAN.md — RuntimeContext struct, matchesCondition, signature refactor, Surface integration

### Phase 3: Process Name Detection
**Goal**: Ghostty detects the foreground process name asynchronously and keeps RuntimeContext current, on both macOS and Linux
**Depends on**: Phase 2
**Requirements**: PROC-03, PROC-04
**Success Criteria** (what must be TRUE):
  1. Opening vim in a Ghostty terminal on macOS causes `RuntimeContext.process_name` to update to `"vim"` within ~200ms
  2. Opening vim in a Ghostty terminal on Linux causes `RuntimeContext.process_name` to update to `"vim"` within ~200ms
  3. Exiting vim and returning to the shell updates the process name back to the shell name within ~200ms
  4. When process detection is unavailable (e.g. Flatpak sandbox), Ghostty logs a one-time warning and treats all `process=` conditions as non-matching rather than crashing
**Plans:** 2/2 plans complete


Plans:
- [ ] 03-01-PLAN.md — Platform-specific process detection API (src/os/process.zig) + mailbox message type
- [ ] 03-02-PLAN.md — Timer integration in Exec.zig + Surface message handler
### Phase 4: OSC 1337 & UserVar Conditions
**Goal**: Terminal programs can set named variables via OSC 1337 SetUserVar, and users can write keybindings that match on those variable values
**Depends on**: Phase 2
**Requirements**: UVAR-01, UVAR-02, UVAR-03, UVAR-04
**Success Criteria** (what must be TRUE):
  1. A shell script that emits `\e]1337;SetUserVar=in_vim=MQ==\a` (base64 "1") causes `RuntimeContext.user_vars["in_vim"]` to be set to `"1"`
  2. A keybinding `[var=in_vim:1]ctrl+w=close_surface` fires when `in_vim` equals `"1"` and falls through to the unconditional binding otherwise
  3. Setting a UserVar to a new value via OSC 1337 replaces the previous value without memory leaks
  4. UserVar exact match and glob match both work (e.g. `[var=mode:insert*]`)
**Plans:** 3/3 plans complete

Plans:
- [ ] 04-01-PLAN.md — OSC 1337 SetUserVar parser and stream dispatch
- [ ] 04-02-PLAN.md — Base64 decode and mailbox messaging to Surface
- [ ] 04-03-PLAN.md — RuntimeContext storage and glob pattern matching

### Phase 5: Window Title & Glob Matching
**Goal**: Users can match on window title, and all condition types support glob wildcards for flexible pattern matching
**Depends on**: Phase 2
**Requirements**: TITL-01, TITL-02, PROC-02
**Success Criteria** (what must be TRUE):
  1. A keybinding `[title=vim: main.zig]ctrl+s=write_scrollback_file` fires when the window title exactly matches `"vim: main.zig"`
  2. A glob pattern `[title=vim:*]ctrl+s=write_scrollback_file` fires for any title starting with `"vim:"`
  3. A glob pattern `[process=nvim*]ctrl+w=close_surface` matches both `"nvim"` and `"nvim-qt"` process names
  4. Glob patterns are compiled at config-load time; no pattern compilation occurs on the keypress path
**Plans:** 1 plan

Plans:
- [ ] 05-01-PLAN.md — Wire runtime_context.title + enable glob matching for process/title conditions

### Phase 6: Platform Validation & Documentation
**Goal**: All conditional keybinding features work correctly on both macOS and Linux, and the keybind config documentation covers all condition types with examples
**Depends on**: Phase 3, Phase 4, Phase 5
**Requirements**: PLAT-01, PLAT-02
**Success Criteria** (what must be TRUE):
  1. The full conditional keybinding test suite passes on macOS (process, title, uservar, glob)
  2. The full conditional keybinding test suite passes on Linux (process, title, uservar, glob)
  3. The `keybind` doc comment in `Config.zig` (which generates the man page) documents all condition types with at least one example each
  4. The documentation explicitly notes the ~200ms eventual-consistency window for process-name conditions
**Plans**: TBD

---

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Config Syntax & Parsing | 2/2 | Complete   | 2026-03-18 |
| 2. Evaluation Engine | 1/1 | Complete   | 2026-03-18 |
| 3. Process Name Detection | 2/2 | Complete   | 2026-03-18 |
| 4. OSC 1337 & UserVar Conditions | 3/3 | Complete   | 2026-03-18 |
| 5. Window Title & Glob Matching | 0/1 | Not started | - |
| 6. Platform Validation & Documentation | 0/? | Not started | - |

---

## Coverage Map

| Requirement | Phase |
|-------------|-------|
| CONF-01 | Phase 1 |
| CONF-02 | Phase 1 |
| CONF-03 | Phase 1 |
| CONF-04 | Phase 1 |
| CONF-05 | Phase 1 |
| PROC-01 | Phase 2 |
| PROC-05 | Phase 2 |
| PROC-03 | Phase 3 |
| PROC-04 | Phase 3 |
| UVAR-01 | Phase 4 |
| UVAR-02 | Phase 4 |
| UVAR-03 | Phase 4 |
| UVAR-04 | Phase 4 |
| TITL-01 | Phase 5 |
| TITL-02 | Phase 5 |
| PROC-02 | Phase 5 |
| PLAT-01 | Phase 6 |
| PLAT-02 | Phase 6 |

**Total mapped: 18/18 ✓**

---
*Roadmap created: 2026-03-18*
