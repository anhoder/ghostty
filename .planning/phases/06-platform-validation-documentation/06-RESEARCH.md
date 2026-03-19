# Phase 6: Platform Validation & Documentation — Research

**Researched:** 2026-03-19
**Domain:** Zig test infrastructure, cross-platform validation, Config.zig doc comment authoring
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PLAT-01 | All conditional matching features work correctly on macOS | All logic is in `src/input/Binding.zig` (platform-agnostic); macOS-specific path is `getForegroundProcessNameBSD` in `src/os/process.zig` using `libproc`; unit tests in Binding.zig run on both platforms |
| PLAT-02 | All conditional matching features work correctly on Linux | Linux-specific path is `getForegroundProcessNameLinux` in `src/os/process.zig` using `/proc/<pid>/comm`; same Binding.zig unit tests cover the shared logic |
</phase_requirements>

---

## Summary

Phase 6 has two distinct deliverables: (1) confirm the full conditional keybinding test suite passes on both macOS and Linux, and (2) add documentation to the `keybind` doc comment in `Config.zig` covering all condition types with examples and the ~200ms eventual-consistency note.

The implementation across Phases 1–5 is complete. All core logic lives in `src/input/Binding.zig` (platform-agnostic) and `src/os/process.zig` (platform-specific process detection). The unit test suite in `Binding.zig` already covers all condition types (process, title, var, glob). PLAT-01 and PLAT-02 are satisfied by running `zig build test -Dtest-filter="RuntimeContext"` on each platform and confirming green.

The documentation gap is in `src/config/Config.zig` at the `keybind:` doc comment (line 1679). The existing comment documents prefixes (`all:`, `global:`, `unconsumed:`, `performable:`), key sequences, chained actions, and key tables — but has no mention of conditional bindings. A new `## Conditional Bindings` section must be added before the `keybind:` field declaration (line 1868), covering all three condition types with at least one example each, plus the ~200ms eventual-consistency note for process conditions.

**Primary recommendation:** Phase 6 is documentation-first. Write the `## Conditional Bindings` doc section in Config.zig, then verify the test suite passes on both platforms via `zig build test -Dtest-filter="RuntimeContext"`.

---

## Standard Stack

### Core
| File | Purpose | Why Standard |
|------|---------|--------------|
| `src/config/Config.zig` | `keybind` doc comment (generates man page) | The `///` doc comment above `keybind:` field is the canonical user-facing documentation |
| `src/input/Binding.zig` | All conditional binding logic + unit tests | Platform-agnostic; tests run on both macOS and Linux |
| `src/os/process.zig` | Platform-specific process name detection | macOS: `libproc proc_pidinfo`; Linux: `/proc/<pid>/comm` |

### Supporting
| File | Purpose | When to Use |
|------|---------|-------------|
| `src/termio/Exec.zig` | 200ms polling timer (`detectProcessName`) | Reference for documenting the eventual-consistency window |
| `src/Surface.zig` | `runtime_context` wiring | Reference for understanding title/process_name update paths |

No new dependencies. This phase is documentation + test verification only.

**Test commands:**
```bash
# Quick: unit tests for all conditional binding logic
zig build test -Dtest-filter="RuntimeContext"

# Full: all conditional binding tests
zig build test -Dtest-filter="RuntimeContext" && zig build test -Dtest-filter="parse: conditional" && zig build test -Dtest-filter="set: getConditional"

# Syntax check only (no network required)
zig ast-check src/config/Config.zig
zig ast-check src/input/Binding.zig
```

---

## Architecture Patterns

### Recommended Project Structure

No new files. All changes are in-place edits:

```
src/
├── config/Config.zig     # Add ## Conditional Bindings doc section
└── input/Binding.zig     # Existing tests — verify they pass on both platforms
```

### Pattern 1: Config.zig Doc Comment Structure

The `keybind` field in `Config.zig` uses `///` doc comments that are parsed to generate the man page. The existing comment uses `##` markdown headers for major sections:

```
## Chained Actions    (line 1779)
## Key Tables         (line 1815)
keybind: Keybinds = .{};   (line 1868)
```

The new `## Conditional Bindings` section must be inserted between `## Key Tables` and the `keybind:` field declaration. It follows the same style: `##` header, prose explanation, `ini` code blocks for examples.

### Pattern 2: Existing Doc Comment Style

From the existing `keybind` doc comment, the style is:

```zig
/// ## Section Name
///
/// Prose explanation.
///
/// ```ini
/// keybind = example=action
/// ```
///
/// Additional notes.
///
```

All examples use `ini` code fences. Condition syntax uses bracket prefix: `[process=vim]ctrl+w=close_surface`.

### Pattern 3: Confirmed Condition Syntax (from parseCondition + tests)

All three condition types verified from `src/input/Binding.zig` `parseCondition` (line 328) and `test "parse: conditional bindings"` (line 5211):

| Condition type | Config syntax | Example |
|----------------|--------------|---------|
| process | `[process=<name>]` | `[process=vim]ctrl+w=close_surface` |
| title | `[title=<pattern>]` | `[title=vim: main.zig]ctrl+s=write_scrollback_file` |
| var | `[var=<name>:<value>]` | `[var=in_vim:1]ctrl+w=close_surface` |

The `var` condition type key is `var` (not `var_`). The name and value are separated by `:` within the bracket value. The internal Zig type is `Condition.var_` but the config syntax uses `var=name:value`.

### Pattern 4: Test Verification on Both Platforms

The test suite in `Binding.zig` is platform-agnostic (pure string matching, no syscalls). The tests that cover PLAT-01 and PLAT-02 are:

| Test block | What it covers |
|------------|---------------|
| `"RuntimeContext: matchesCondition"` | process exact, title exact, var exact, null cases |
| `"RuntimeContext: matchesCondition var_ glob patterns"` | var glob `*` and `?` |
| `"RuntimeContext: matchesCondition title/process glob patterns"` | TITL-01, TITL-02, PROC-02 |
| `"set: getConditional priority"` | CONF-03, CONF-04 priority rules |
| `"parse: conditional bindings"` | CONF-01, CONF-02 syntax parsing |

Platform-specific process detection (`src/os/process.zig`) has its own tests:
- `"unsupported platform returns null"` — skips unless Windows
- `"invalid fd returns null"` — runs on all platforms

### Anti-Patterns to Avoid

- **Don't add conditional binding docs inside the prefix list:** The `all:`, `global:`, `unconsumed:`, `performable:` prefixes are listed as a bullet list. Conditional bindings use bracket syntax, not a prefix — they belong in a separate `##` section.
- **Don't document v2 features (ADV-01 through ADV-04):** Multiple conditions, auto key table activation, config-defined UserVar defaults, and shell integration state are out of scope.
- **Don't claim Linux CI passes without running it:** The build environment in prior sessions had no network access. The plan must include a step to run tests locally on Linux (or note that CI covers it).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cross-platform test runner | Custom test harness | `zig build test -Dtest-filter=...` | Built-in Zig test runner handles platform differences |
| Doc generation | Custom tooling | Existing `///` doc comment convention | Ghostty already parses these for man page generation |
| Process detection validation | New integration test | Existing `"invalid fd returns null"` test + manual smoke test | Unit tests cover the logic; integration requires a live PTY |

**Key insight:** PLAT-01 and PLAT-02 are satisfied by the existing unit test suite passing on both platforms. There is no new code to write — only documentation and test verification.

---

## Common Pitfalls

### Pitfall 1: Confusing "conditional bindings" with "conditional configuration"
**What goes wrong:** `Config.zig` already has a `conditional.zig` module for dark/light theme switching (`_conditional_state`, `changeConditionalState`). This is a different feature. The `keybind` doc comment must document runtime conditional bindings (bracket syntax), not config-time conditional configuration.
**How to avoid:** The new section is specifically about `[process=...]`, `[title=...]`, `[var=name:value]` syntax in keybind values. Keep it scoped to keybind behavior.

### Pitfall 2: Documenting the wrong eventual-consistency window
**What goes wrong:** The 200ms window applies specifically to `process=` conditions because process detection is async (polled every 200ms via `termiosTimer`). Title and var conditions are updated synchronously (on `set_title` message and `set_user_var` message respectively), so they have no eventual-consistency window.
**How to avoid:** The doc note must say "process-name conditions" specifically, not "all conditions."

### Pitfall 3: Test filter syntax
**What goes wrong:** `zig build test -Dtest-filter` takes a substring match. `"RuntimeContext"` matches all three RuntimeContext test blocks. If the filter is too narrow (e.g., `"matchesCondition"`) it may miss the `"set: getConditional priority"` test.
**How to avoid:** Run multiple filter passes or use `zig build test` without filter for the full suite.

### Pitfall 4: Linux process detection requires a live PTY
**What goes wrong:** `getForegroundProcessNameLinux` reads `/proc/<pid>/comm` — this only works in a real terminal session with a PTY. The unit test `"invalid fd returns null"` passes on Linux but doesn't validate the happy path.
**How to avoid:** The plan should note that Linux process detection happy-path validation requires a manual smoke test (open Ghostty on Linux, run `vim`, verify `[process=vim]` binding fires). This is a manual-only test.

### Pitfall 5: Missing `var` condition documentation
**What goes wrong:** The three condition types are `process`, `title`, and `var` (OSC 1337 SetUserVar). It's easy to document only `process` and `title` and forget `var`.
**How to avoid:** The success criteria explicitly requires "all condition types with at least one example each" — checklist: process, title, var.

### Pitfall 6: Wrong `var` condition syntax in examples
**What goes wrong:** The internal Zig type is `Condition.var_` but the config syntax is `[var=name:value]` — the type key is `var` (not `var_`) and name/value are colon-separated within the bracket value.
**How to avoid:** Use `[var=in_vim:1]` style in all documentation examples. Verified from `parseCondition` (line 350) and `test "parse: conditional bindings"` (line 5228).

---

## Code Examples

### New Doc Section for Config.zig (target location: between `## Key Tables` and `keybind:` field)

```zig
/// ## Conditional Bindings
///
/// A keybind can be made conditional by prefixing the trigger with a
/// condition in square brackets. The binding only activates when the
/// condition is true at the time the key is pressed.
///
/// The syntax is `[condition]trigger=action`. For example:
///
/// ```ini
/// keybind = [process=vim]ctrl+w=close_surface
/// ```
///
/// This binds `ctrl+w` to `close_surface` only when the foreground
/// process in the terminal is `vim`.
///
/// ### Condition Types
///
/// **`process=<name>`** — Match on the name of the foreground process
/// running in the terminal. Supports glob wildcards (`*` and `?`).
///
/// ```ini
/// keybind = [process=vim]ctrl+w=close_surface
/// keybind = [process=nvim*]ctrl+w=close_surface
/// ```
///
/// Note: Process-name detection is updated approximately every 200ms
/// in the background. There is an eventual-consistency window of up to
/// ~200ms between when a process starts and when a `process=` condition
/// begins matching. For latency-critical use cases, prefer `var=`
/// conditions set via OSC 1337.
///
/// **`title=<pattern>`** — Match on the terminal window title.
/// Supports glob wildcards (`*` and `?`).
///
/// ```ini
/// keybind = [title=vim: main.zig]ctrl+s=write_scrollback_file:~/output.txt
/// keybind = [title=vim:*]ctrl+s=write_scrollback_file:~/output.txt
/// ```
///
/// **`var=<name>:<value>`** — Match on a user-defined variable set via
/// OSC 1337 SetUserVar. Supports glob wildcards (`*` and `?`).
///
/// ```ini
/// keybind = [var=mode:insert]ctrl+c=text:\x1b
/// keybind = [var=env:production*]ctrl+r=reload_config
/// ```
///
/// User variables are set by the running program using the iTerm2
/// OSC 1337 `SetUserVar` escape sequence:
/// `\e]1337;SetUserVar=<name>=<base64-value>\a`
///
/// ### Conditional Binding Priority
///
/// When a key is pressed, conditional bindings are checked first. If a
/// conditional binding matches, it takes priority over any unconditional
/// binding for the same trigger. If no conditional binding matches, the
/// unconditional binding (if any) is used as a fallback.
///
/// If multiple conditional bindings exist for the same trigger, the
/// last one defined in the configuration wins (same as unconditional
/// bindings).
///
/// ### Limitations
///
/// * Only one condition per binding is supported. Multiple conditions
///   (AND/OR logic) are not available in this version.
///
/// * Conditional bindings are not supported for key sequences
///   (e.g., `[process=vim]ctrl+a>n=new_window` is not valid).
///
/// * The `global:` and `all:` prefixes are not supported with
///   conditional bindings.
```

### Existing Test Commands (verified from source)

```bash
# Run all RuntimeContext tests (covers PLAT-01, PLAT-02 logic)
zig build test -Dtest-filter="RuntimeContext"

# Run conditional binding parse tests
zig build test -Dtest-filter="conditional"

# Run getConditional priority tests
zig build test -Dtest-filter="getConditional"

# Syntax check only (no network required)
zig ast-check src/config/Config.zig
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No conditional bindings | `[process=...]`, `[title=...]`, `[var=name:value]` bracket syntax | Phases 1–5 | Full conditional keybinding feature |
| `std.mem.eql` for process/title | `matchesGlob` with `*`/`?` | Phase 5 | Glob patterns work for all condition types |
| No doc coverage | `## Conditional Bindings` section in Config.zig | Phase 6 | Man page documents the feature |

**Deprecated/outdated:**
- Nothing deprecated. Phase 6 adds documentation only (plus test verification).

---

## Open Questions

1. **Linux CI availability**
   - What we know: Prior sessions had no network access; `zig build test` could not fetch deps
   - What's unclear: Whether the plan should include a CI step or rely on local Linux testing
   - Recommendation: Plan should include `zig ast-check` as the automated gate (always works) and note that full `zig build test` requires a network-connected Linux environment or CI

2. **Limitations section scope**
   - What we know: v1 supports single condition only; key sequences not supported for conditional bindings; `global:`/`all:` not supported
   - What's unclear: Whether to document these as limitations or simply omit them
   - Recommendation: Document as a brief "Limitations" subsection — users will try these combinations and need to know they won't work

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Zig built-in test runner |
| Config file | none (inline `test` blocks in .zig files) |
| Quick run command | `zig build test -Dtest-filter="RuntimeContext"` |
| Full suite command | `zig build test -Dtest-filter="conditional"` + `zig build test -Dtest-filter="RuntimeContext"` + `zig build test -Dtest-filter="getConditional"` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PLAT-01 | All condition types match correctly on macOS | unit | `zig build test -Dtest-filter="RuntimeContext"` | ✅ Binding.zig lines 5341–5480 |
| PLAT-02 | All condition types match correctly on Linux | unit | `zig build test -Dtest-filter="RuntimeContext"` | ✅ Same tests, platform-agnostic |
| PLAT-01 | macOS process detection (libproc) returns name | manual | manual smoke test: run vim, verify `[process=vim]` fires | ❌ No automated test for happy path |
| PLAT-02 | Linux process detection (/proc/comm) returns name | manual | manual smoke test: run vim on Linux, verify `[process=vim]` fires | ❌ No automated test for happy path |
| PLAT-01/02 | Config.zig doc comment covers all condition types | manual | `zig ast-check src/config/Config.zig` (syntax only) | ❌ Doc section not yet written |

### Sampling Rate
- **Per task commit:** `zig ast-check src/config/Config.zig`
- **Per wave merge:** `zig build test -Dtest-filter="RuntimeContext"`
- **Phase gate:** All RuntimeContext tests green + Config.zig doc section present with all 3 condition types + 200ms note

### Wave 0 Gaps

- [ ] `src/config/Config.zig` — `## Conditional Bindings` doc section (covers PLAT-01, PLAT-02 documentation requirement)
- [ ] No new test files needed — existing test infrastructure covers all automated requirements

*(Process detection happy-path is manual-only: requires live PTY on each platform)*

---

## Sources

### Primary (HIGH confidence)
- Direct source read: `src/input/Binding.zig` — `RuntimeContext`, `Condition`, `matchesGlob`, `parseCondition` (line 328), all test blocks (lines 5211–5480)
- Direct source read: `src/os/process.zig` — `getForegroundProcessName`, Linux and macOS implementations, existing tests
- Direct source read: `src/config/Config.zig` — `keybind` doc comment (lines 1590–1868), existing section structure
- Direct source read: `src/Surface.zig` — `deinit` (lines 783–844), `handleMessage` set_title handler (lines 970–994)
- `.planning/STATE.md` — key decisions log, session history confirming all phases 1–5 complete
- `.planning/REQUIREMENTS.md` — PLAT-01, PLAT-02 definitions
- `.planning/phases/05-window-title-glob-matching/05-01-SUMMARY.md` — confirmed Phase 5 complete

### Secondary (MEDIUM confidence)
- `build.zig` — test step configuration, `-Dtest-filter` option confirmed

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all files read directly
- Architecture: HIGH — doc comment structure verified in source, test commands verified in build.zig
- Pitfalls: HIGH — identified from reading actual source and prior phase research
- Open questions: LOW — only Linux CI availability is unresolved; all syntax questions answered from source

**Research date:** 2026-03-19
**Valid until:** Stable until Ghostty source structure changes (no external dependencies)
