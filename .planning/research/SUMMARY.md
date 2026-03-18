# Research Summary: Ghostty Conditional Keybindings

**Project:** Ghostty Conditional Keybindings
**Domain:** Terminal emulator runtime keybinding evaluation
**Researched:** 2026-03-18
**Confidence:** HIGH

---

## Executive Summary

Ghostty already contains the vast majority of infrastructure needed to implement conditional keybindings. The existing `conditional.zig` system, key-table stack, keybind parser flags, OSC 1337 parser stub, and process-group utilities in `termio/Exec.zig` form a nearly complete foundation. The recommended implementation strategy is to build on top of these primitives rather than invent new systems: extend the keybind parser with a `when:` (or bracket-prefixed) condition clause, maintain a `RuntimeContext` struct on `Surface` that caches dynamic state (process name, window title, user variables), and evaluate conditions inline during `maybeHandleBinding` as an overlay layer between the key-table stack and the root binding set.

The competitive landscape strongly validates this feature. WezTerm supports equivalent functionality via Lua scripting, but requires coding. Kitty has no native equivalent despite community requests. Alacritty explicitly rejects it. Ghostty has the opportunity to be the first mainstream terminal to offer native, zero-script conditional keybindings with a simple declarative syntax. The OSC 1337 `SetUserVar` path, already parsed but marked unimplemented, connects Ghostty to the broader shell integration ecosystem (fish, neovim, iTerm2 scripts) with no additional protocol work.

The primary risks are (1) introducing per-keypress syscalls that degrade input latency — mitigated strictly by caching all runtime state asynchronously, (2) breaking existing keybind syntax — mitigated by choosing a new delimiter that does not collide with `=`, `:`, `>`, or `/`, and (3) the inherent race condition between process changes and cached state — accepted as a known limitation with a documented 1–5 ms window. None of these risks block implementation; all have clear mitigations established during research.

---

## Stack Recommendations

Ghostty is a Zig project with no scripting layer. All new code should be written in Zig, building on in-repo infrastructure. No new dependencies are required.

**Core technologies and extension points:**

- `src/config/conditional.zig` — existing conditional evaluation engine; note the `State` struct is intentionally static (for config-time use), so **runtime conditions require a separate `RuntimeContext` struct on `Surface`**, not an extension of `conditional.State`
- `src/input/Binding.zig` / `Binding.Parser.parseFlags` — entry point for new `when:` syntax; currently handles `all:`, `global:`, `unconsumed:`, `performable:` — the same flag-prefix mechanism is the right extension point
- `src/Surface.zig:maybeHandleBinding` — the key-dispatch hot path; condition evaluation is inserted here between the table stack (step 2) and the root set (step 4)
- `src/terminal/osc/parsers/iterm2.zig` — OSC 1337 `SetUserVar` is already parsed but discarded; the `Command` enum variant and `stream_handler.zig` dispatch are the only missing pieces
- `src/os/systemd.zig` — exact pattern for Linux `/proc/{pid}/comm` reads, directly reusable in a new `src/os/process.zig`
- `oniguruma` (vendored at `pkg/oniguruma`, used in `src/renderer/link.zig`) — available for regex matching in v1.x; not needed for v1 exact/glob matching
- `std.base64.standard.Decoder` — stdlib, no new dependency, needed for OSC 1337 value decoding

**Critical version/API notes:**
- macOS: `proc_name(pid, buf, bufsize)` from `<libproc.h>`, available macOS 10.5+, returns basename up to 16 bytes (`MAXCOMLEN`)
- Linux: `/proc/{pgid}/comm` truncates to 15 chars; fall back to `/proc/{pgid}/status` `Name:` field for longer names
- `tcgetpgrp(pty_fd)` is POSIX, available on both platforms; must be called from the I/O thread (which owns the PTY fd)

---

## Feature Prioritization

### Must have (P1 — launch blockers)

- **Process-name conditional keybind syntax** — the core vim/shell use case; users cannot benefit from the feature without this
- **Exact match support** (`process=vim`) — zero-cost string comparison; glob and regex are v1.x
- **Conditional priority over unconditional bindings** — without this, any existing `ctrl+w = close_surface` silently wins over the conditional version; functionally broken otherwise
- **Backward compatibility** — existing keybind configs must parse and behave identically; validated by running the full existing `Binding.zig` test suite

### Should have (P2 — add after core validation)

- **Window title conditional matching** — covers tmux/SSH/screen cases where process name is always `bash`; infrastructure already exists (`Surface` tracks title via `set_title` messages), only wiring needed
- **Glob pattern matching** (`process=nvim*`) — catches neovim variants and similar; ~30-line custom implementation, no new dependency
- **OSC 1337 SetUserVar** — prerequisite for UserVar conditions; enables the entire shell integration ecosystem (fish, neovim)
- **UserVar conditional matching** (`var=in_vim`) — fine-grained app-controlled conditions; more reliable than process name for apps that support it

### Defer to v2+

- **Automatic key table activation based on conditions** — requires a state machine to manage table lifecycle; powerful but significantly more complex
- **Multi-condition AND/OR logic** — needs a boolean expression parser; most users don't need it in v1
- **Config-file predefined UserVar initial values** — quality-of-life improvement; depends on UserVar adoption
- **Shell integration prompt-state awareness** — deep coupling to `shell_integration.zig`; assess after v1 user feedback
- **Regex matching via oniguruma** — infrastructure exists; defer until exact/glob proves insufficient

### Anti-features (explicitly out of scope)

- Kitty `when_focus_on` syntax compatibility — Kitty does not actually implement this natively; do not design around it
- Conditional application to non-keybind config (fonts, colors) — scope creep; these are better controlled by OSC sequences from the application itself
- GUI configuration interface — contradicts Ghostty's plain-text config philosophy
- Real-time event-driven process monitoring — PTY does not provide foreground-process-change events; timer polling is the correct model

---

## Architecture Overview

The feature requires three new components and modifications to five existing ones. The design is a clean overlay pattern: conditional bindings are stored in a separate `ConditionSet`, and `RuntimeContext` holds cached dynamic state. Neither the existing `Binding.Set` nor the `conditional.State` struct is modified.

**New components (in build order):**

1. `src/input/ConditionSet.zig` — parses and stores `ConditionalBinding` entries (condition + trigger + action + flags); built at config-load time; supports `clone`, `equal`, `formatEntry` for the `Config` interface
2. `RuntimeContext` struct on `Surface` — caches `process_name`, `window_title`, `user_vars`; updated via surface mailbox messages; never accessed from the I/O thread directly
3. `src/input/condition_eval.zig` — pure, side-effect-free `matches(condition, ctx)` function; O(n) on name length (< 256 bytes), effectively O(1); no syscalls
4. `src/os/process.zig` — platform-specific foreground process name lookup; dispatches to macOS `proc_name` or Linux `/proc/{pgid}/comm`; called only from the I/O thread timer, never from the keypress path

**Modified existing components:**

- `src/config/Config.zig` `Keybinds` — add `conditional_bindings: ConditionSet`; detect `when:` prefix in `parseCLI` and route to `ConditionSet` instead of `Binding.Set`
- `src/Surface.zig` — add `runtime_ctx: RuntimeContext`; modify `maybeHandleBinding` to scan conditional bindings between table stack and root set; handle `set_process_name` and `set_user_var` mailbox messages
- `src/apprt/surface.zig` `Message` union — add `set_process_name` and `set_user_var` variants
- `src/terminal/osc/parsers/iterm2.zig` + `src/termio/stream_handler.zig` — implement the `SetUserVar` OSC 1337 handler (currently a stub)
- `src/termio/Exec.zig` — add a 200ms xev timer to poll foreground process group and push `set_process_name` messages when the name changes

**Key binding evaluation priority order (highest to lowest):**
1. Active key sequence (leader keys)
2. Active key table stack
3. Conditional bindings matching current `RuntimeContext` (new)
4. Root unconditional binding set

---

## Critical Risks

1. **Per-keypress syscall latency (HIGH)** — Calling `tcgetpgrp` + `proc_name`/`/proc/comm` on the keypress path adds 8–33 µs per keypress, a measurable regression for a terminal targeting sub-millisecond latency. Prevention: cache all runtime state; update only via surface mailbox messages and a 200ms background timer; the keypress path reads only cached in-memory strings (10–50 ns).

2. **Config syntax delimiter collision (HIGH)** — The keybind parser uses `=`, `:`, `>`, and `/` as load-bearing delimiters. A condition syntax that reuses any of these risks silently misparsing existing valid configs. Prevention: use a bracket prefix (`[process=vim]trigger=action`) which is unambiguous, or carefully verify `when:` prefix is consumed before the existing flag parser runs. Run the complete existing `Binding.zig` test suite before merging any parser change.

3. **Process-change race condition (HIGH)** — The cached process name can lag reality by 1–5 ms during rapid process transitions (e.g., exiting vim and typing immediately). Prevention: accept this as a fundamental limitation of async process detection; document it explicitly; recommend UserVar-based conditions for latency-critical use cases (app sets its own state proactively via OSC 1337).

4. **Config reload with active key table (MEDIUM)** — `Surface.keyboard.table_stack` holds raw pointers to `Binding.Set` values in config memory. A config reload frees that memory while the stack may still reference it, causing use-after-free. Prevention: call `deactivateAllKeyTables()` before swapping config on any reload.

5. **Regex/glob recompilation per keypress (MEDIUM)** — If pattern matching compiles patterns at match time rather than config-load time, each keypress triggers oniguruma compilation (50–500 µs). Prevention: compile all patterns at config parse time; store compiled form in the condition struct; use `std.mem.eql` exact-match fast path when no wildcards are present.

---

## Implementation Roadmap Implications

Research establishes a clear build order based on hard dependencies. Each phase is independently testable.

### Phase 1: Config Syntax and Parsing
**Rationale:** All downstream work depends on a stable, backward-compatible syntax. Parser changes are the highest-risk backward-compatibility surface. Establishing and testing syntax first isolates risk.
**Delivers:** `ConditionSet.zig`; parser extension in `Keybinds.parseCLI`; round-trip `clone`/`equal`/`formatEntry`
**Addresses:** Process-name exact match (P1 feature), backward compatibility (P1 feature)
**Avoids pitfall:** Delimiter collision — choose bracket syntax, run full existing test suite
**Research flag:** Standard pattern for Ghostty parser extension; no additional research needed

### Phase 2: RuntimeContext and Condition Evaluation
**Rationale:** The evaluation logic is pure (no I/O, no side effects) and can be fully unit-tested before any OS integration. Establishing the data model early prevents threading design mistakes later.
**Delivers:** `RuntimeContext` struct on `Surface`; `condition_eval.zig`; wired into `maybeHandleBinding` with the correct priority order
**Addresses:** Conditional priority semantics (P1 feature)
**Avoids pitfall:** Condition priority confusion — overlay model, not flat merge
**Research flag:** Standard pattern; no additional research needed

### Phase 3: OSC 1337 SetUserVar
**Rationale:** This is a prerequisite for UserVar conditions (P2), and it unblocks the shell integration ecosystem. The implementation is well-scoped (stub to full in iterm2.zig + stream_handler). Completing it early means Phase 4 UserVar conditions can be added incrementally.
**Delivers:** Full OSC 1337 `SetUserVar` parse → decode → `RuntimeContext.user_vars` pipeline; UserVar condition type in `ConditionSet`
**Addresses:** UserVar conditional matching (P2 feature), OSC 1337 SetUserVar (P2 feature)
**Avoids pitfall:** "UserVar never triggers" — implement as a complete prerequisite, not deferred
**Research flag:** Standard pattern; OSC protocol and Ghostty parser structure are well-understood

### Phase 4: Process Name Detection
**Rationale:** OS process detection is the most platform-specific work and carries the most risk (macOS sandboxing, Linux Flatpak, PTY fd threading). Isolating it in its own phase allows targeted testing on both platforms.
**Delivers:** `src/os/process.zig`; I/O thread 200ms polling timer in `Exec.zig`; `set_process_name` surface message; `RuntimeContext.process_name` updates
**Addresses:** Process-name conditional matching (P1 feature, now fully wired end-to-end)
**Avoids pitfalls:** Per-keypress syscall (async update only), macOS entitlement restriction (basename from `proc_name`), Linux Flatpak isolation (detect and degrade gracefully), PTY fd thread ownership (call only from I/O thread)
**Research flag:** Platform-specific; needs explicit test on macOS non-sandboxed and Linux Flatpak builds

### Phase 5: Window Title Matching
**Rationale:** Title infrastructure already exists in `Surface` (tracked via `set_title` messages). This phase is primarily wiring `RuntimeContext.window_title` and adding the `window_title` condition type to the evaluator. Low complexity, high value for tmux/SSH users.
**Delivers:** `window_title` condition type; sync of `set_title` handler into `runtime_ctx`
**Addresses:** Window title conditional matching (P2 feature)
**Avoids pitfall:** Title encoding — operate on already-decoded title bytes; document 256-byte limit
**Research flag:** No research needed; pattern is established by earlier phases

### Phase 6: Glob Pattern Matching
**Rationale:** Exact matching is validated by Phase 4. Adding glob extends coverage to `nvim*`, `vi*`, and title wildcards without any new dependencies. Small, self-contained change.
**Delivers:** `globMatch` implementation; `process_name_glob` and `window_title_glob` condition variants in the evaluator
**Addresses:** Glob pattern matching (P2 feature)
**Avoids pitfall:** Pattern compile at config time — store compiled glob AST alongside raw string
**Research flag:** No research needed; standard algorithm

### Phase 7: Documentation
**Rationale:** Final step, after all condition types are stable. The `keybind` doc comment in `Config.zig` generates the man page. Write it once with the complete picture.
**Delivers:** Updated `keybind` documentation; examples for all condition types; explicit note on process-name eventual consistency
**Research flag:** No research needed

### Phase Ordering Rationale

- Phases 1-2 establish the static skeleton (syntax + evaluation) with no OS dependencies — fully testable in unit tests
- Phase 3 (OSC 1337) is a prerequisite for UserVar conditions and unblocks shell integration users early
- Phase 4 (process detection) is isolated because it carries the most platform-specific risk
- Phases 5-6 are additive extensions to the already-working system
- This order means a usable v1 (process name exact match) is deliverable after Phase 4, with P2 features added incrementally in Phases 3, 5, and 6

### Research Flags

Phases needing deeper investigation during implementation:
- **Phase 4 (Process Detection):** macOS `libproc` entitlement behavior under different distribution modes; Linux Flatpak PID namespace behavior — test on actual hardware before finalizing

Phases with well-established patterns (no additional research needed):
- Phase 1 (Config Parsing) — Ghostty parser extension is well-documented in the codebase
- Phase 2 (Evaluation) — pure function, no external dependencies
- Phase 3 (OSC 1337) — stub-to-implementation, protocol is documented
- Phases 5, 6, 7 — additive, no new technical unknowns

---

## Open Questions

These questions were not fully resolved during research and require design decisions before or during implementation:

1. **Config syntax delimiter choice:** `when:process=vim>ctrl+w=action` vs `[process=vim]ctrl+w=action`. The bracket form is safer against parser collisions but departs from Ghostty's existing flag syntax style. Requires maintainer input before Phase 1.

2. **`conditional.State` vs `RuntimeContext` naming:** STACK.md suggests extending `conditional.State` while ARCHITECTURE.md correctly identifies that `conditional.State` is intentionally static. The implementation must use a separate `RuntimeContext` — but the final naming convention and module location should be confirmed to fit Ghostty's code organization conventions.

3. **Thread safety model for `user_vars` memory:** `RuntimeContext` is on `Surface` (main thread). Updates arrive via surface mailbox (safe). But the allocator strategy for the `StringHashMapUnmanaged` needs explicit design: use `Surface`'s GPA allocator with careful dealloc on `deinit` and on each `setUserVar` call that replaces an existing key.

4. **Config-defined vs OSC-set UserVar precedence:** If a user defines `user_var = in_editor=0` in their config and an OSC sequence later sets `in_editor=1`, which wins? Recommend: OSC takes precedence (runtime state overrides static config), with config providing initial/default values only.

5. **`std.fs.path.match` vs custom glob:** ARCHITECTURE.md suggests `std.fs.path.match` for glob; STACK.md suggests a custom 30-line implementation. Verify whether `std.fs.path.match` handles the `*` and `?` semantics users expect for process names (it may have path-separator semantics that do not apply here). If not, the custom implementation is the right choice.

6. **Polling interval configurability:** 200ms is the established Ghostty cadence (`TERMIOS_POLL_MS`). Whether this should be user-configurable is a product decision. Recommendation: hardcode at 200ms for v1; make configurable only if user feedback identifies specific use cases that need faster updates.

7. **Flatpak graceful degradation:** When process detection is unavailable (Flatpak sandbox), should Ghostty silently ignore `when:process=...` conditions (treating them as always-false), or warn the user? Recommend: log a one-time warning at startup when Flatpak is detected and process detection is unavailable.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All extension points directly verified in source code; no new dependencies required |
| Features | HIGH | Based on direct source analysis of Ghostty + competitor documentation review |
| Architecture | HIGH | Component boundaries clear; threading model verified against existing mailbox patterns |
| Pitfalls | HIGH | Identified from direct code analysis, not inference; mitigations match existing Ghostty patterns |

**Overall confidence:** HIGH

### Gaps to Address

- **Flatpak process detection behavior:** Not confirmed empirically; needs a test build inside a Flatpak sandbox to verify whether child PIDs are visible from `/proc`
- **`std.fs.path.match` glob semantics:** Needs a quick check against Zig stdlib docs to confirm `*`/`?` behavior matches user expectations for process-name patterns
- **Maintainer syntax preference:** The `when:` vs `[condition]` syntax question is a style decision that should be resolved with Ghostty maintainers before any parser code is written
- **`conditional.State` static design intent:** STACK.md proposes extending `conditional.State`; ARCHITECTURE.md identifies this as architecturally incorrect. The separate `RuntimeContext` model is correct — but this discrepancy between research files should be resolved explicitly in Phase 2 design

---

## Sources

### Primary — HIGH confidence (direct source analysis)

- `src/config/conditional.zig` — existing conditional system; confirmed static-only design
- `src/input/Binding.zig` — binding parser, `Flags` struct, `Set` implementation
- `src/config/Config.zig` — `Keybinds` struct, `parseCLI`, config lifecycle
- `src/Surface.zig` — `maybeHandleBinding`, `keyCallback`, `handleMessage`, table stack
- `src/terminal/osc/parsers/iterm2.zig` — `SetUserVar` stub confirmed at lines 187-194
- `src/termio/Exec.zig` — I/O thread structure, PTY fd ownership, `TERMIOS_POLL_MS = 200`
- `src/termio/stream_handler.zig` — OSC dispatch, `windowTitle` encoding details
- `src/os/systemd.zig` — Linux `/proc/{pid}/comm` pattern (directly reusable)
- `src/apprt/surface.zig` — `Message` union structure for new message variants
- Apple developer docs — `proc_name(pid, buf, bufsize)` from `<libproc.h>`, macOS 10.5+

### Secondary — MEDIUM confidence (external documentation)

- WezTerm Pane API docs — `get_foreground_process_name()`, `get_user_vars()` Lua APIs
- WezTerm Key Tables docs — stack-based table model (confirmed Ghostty already matches this design)
- Kitty Actions/Shell Integration docs — confirmed no native process-aware keybind feature
- iTerm2 Profile Keys docs — Profile-based conditional keybind via OSC 1337 (the model Ghostty improves on)

---

*Research completed: 2026-03-18*
*Ready for roadmap: yes*
