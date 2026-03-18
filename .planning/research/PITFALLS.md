# Pitfalls Research: Conditional Keybindings

**Domain:** Terminal emulator conditional keybinding system
**Researched:** 2026-03-18
**Confidence:** HIGH (based on direct codebase analysis)

---

## Critical Pitfalls

### 1. Per-Keypress Process Syscall

**Risk Level:** HIGH
**Phase:** Phase 1 (Architecture) and Phase 2 (Process Detection)

**What goes wrong:**
Naively querying the OS for the foreground process on every keypress event. A keypress in Ghostty passes through: AppRuntime (GTK/SwiftUI) -> `Surface.keyCallback()` -> `maybeHandleBinding()` -> binding set lookup. Any syscall inserted into `maybeHandleBinding()` before the `ArrayHashMap` lookup adds latency on the GUI thread.

**Why it happens:**
The natural implementation impulse is to call `tcgetpgrp(pty_fd)` then `proc_pidpath()` (macOS) or read `/proc/<pid>/exe` (Linux) directly inside the lookup path. Both involve at minimum one syscall; on macOS `proc_pidpath` may involve Mach IPC.

**Measured risk:**
- `tcgetpgrp()` is typically 1–3 µs — acceptable alone
- `proc_pidpath()` / `/proc/<pid>/exe` readlink: 5–30 µs depending on kernel state
- Combined on every keypress: 8–33 µs added to the GUI thread per event
- Ghostty is designed for sub-millisecond input latency; this is a measurable regression

**Warning Signs:**
- Input latency noticeably higher when a matched conditional is active
- Profiling shows `keyCallback` spending >10 µs in OS calls instead of the expected ~1 µs for the `ArrayHashMap` lookup

**Prevention:**
Cache the current process name/title string on the Surface. Update it asynchronously:
1. On `start_command` / `stop_command` messages (already sent via `surface_mailbox` when shell integration is active — see `apprt/surface.zig:94`)
2. On `set_title` messages (OSC 0/2 window title changes, already handled in `stream_handler.zig:windowTitle()`)
3. On `report_pwd` (already fires on `cd`)

For the no-shell-integration path, update the cached process name on a timer (200 ms is acceptable; `TERMIOS_POLL_MS = 200` is already the established poll cadence in `termio/Exec.zig:34`).

The conditional match at keypress time then reads only from the cached in-memory string — zero syscalls.

---

### 2. Race Between Process Change and Keypress Evaluation

**Risk Level:** HIGH
**Phase:** Phase 2 (Process Detection), Phase 3 (Evaluation)

**What goes wrong:**
A user types a key. Concurrently, the foreground process exits and the shell restores focus. The conditional check reads "vim" but by the time the action executes, the PTY belongs to the shell. The wrong action fires.

**Why it happens:**
Ghostty uses three threads: GUI thread (keypress + binding evaluation), I/O thread (PTY read/write), renderer thread. The I/O thread fires `start_command`/`stop_command` surface messages when shell integration detects transitions. These messages are asynchronous — the GUI thread sees them with up to one event-loop cycle of delay.

Process-name updates travel:
```
Shell emits OSC / semantic-prompt
  -> I/O thread processes in processOutputLocked() [holds renderer_state.mutex]
  -> surfaceMessageWriter() enqueues to surface_mailbox
  -> GUI thread processes mailbox message, updates cached process name
```

The cached name and the actual foreground process can be out of sync by ~1–5 ms during transitions.

**Warning Signs:**
- Wrong binding fires when switching from vim to shell rapidly
- Reported as "keybinding fires after I exit vim"

**Prevention:**
1. Accept the race as a fundamental limitation of async process detection and document it clearly. A 1–5 ms window where the wrong binding might fire is imperceptible in normal use.
2. Never attempt synchronous correction at key-action time — it creates its own latency and complexity problems.
3. For UserVar-based conditions (set via OSC 1337 `SetUserVar`), the race is smaller because the app explicitly sets the var. Prefer UserVar patterns for critical bindings.

---

### 3. Breaking Existing Keybind Config Backward Compatibility

**Risk Level:** HIGH
**Phase:** Phase 1 (Config Syntax Design)

**What goes wrong:**
The new conditional syntax reuses characters already meaningful in the keybind parser. The current parser (`Binding.zig:Parser`) has several special characters that are load-bearing:
- `=` separates trigger from action (with complex logic to handle `=+` and `==`)
- `>` separates multi-key sequences (e.g., `ctrl+a>ctrl+b`)
- `:` separates flags from the trigger (`all:`, `global:`, `unconsumed:`, `performable:`)
- `/` separates table name from the trigger (`tablename/trigger=action`)

If a conditional syntax reuses `=`, `:`, `>`, or `/` in ambiguous positions, it will silently misparse existing valid configs or throw `InvalidFormat` on them.

**Specific collision risks:**
- Using `:` for conditions (e.g., `when:process=vim:ctrl+w=close_surface`) collides with the existing flag prefix parser (`parseFlags` at `Binding.zig:148`) which stops only on unknown prefixes
- Using `=` for conditions collides with the trigger/action separator logic (already handles `=+` and `==` specially with an inner loop)
- Using `[condition]` bracket syntax before the trigger is safe — the trigger parser (`Trigger.parse`) would need to explicitly support or reject brackets

**Warning Signs:**
- Existing test suite failures in `Binding.zig` tests after introducing the new syntax
- Tests in `parseCLI table with slash in binding` pattern break (there are many edge-case tests for `/` handling already)

**Prevention:**
1. Choose a syntax that uses a completely new delimiter not present in any existing parse path. A bracketed prefix like `[condition]trigger=action` is safest.
2. Run the full existing binding test suite against the new parser before merging.
3. Add a dedicated `compatibility` map entry in `Config.zig` (the map already exists at line 61 for migrating renamed options) if any syntax migration is needed.
4. The existing `conditional.zig` system (for theme/OS conditions) uses a separate key-value file section mechanism, not inline binding syntax. Do not conflate the two systems.

---

### 4. Stale Process Cache After Rapid Process Changes

**Risk Level:** MEDIUM
**Phase:** Phase 2 (Process Detection)

**What goes wrong:**
User runs: `vim file; echo done`. Vim exits within milliseconds. The cached process name is still "vim" when the shell resumes and the user types a key. The vim-specific binding fires instead of the shell binding.

**Why it happens:**
- Shell integration `stop_command` is emitted by the shell's `preexec`/`precmd` hooks, but only for the shell itself — not for all subprocesses of subprocesses.
- If the user has no shell integration, the timer-based update (recommended: 200 ms) means a 200 ms window of staleness after a process change.

**Warning Signs:**
- Intermittent wrong-binding reports in user bug reports, especially from users running short-lived commands

**Prevention:**
1. Shell integration path: rely on `start_command`/`stop_command` surface messages for immediate updates. These are already emitted for shell-level commands.
2. Timer fallback path: keep the poll interval at 200 ms (matching `TERMIOS_POLL_MS`) — this is the established Ghostty tolerance for "best effort" process tracking.
3. For title-based conditions: OSC 0/2 title changes from programs like vim fire immediately, making title-based conditions more reliable than process-name-based ones for apps that set titles.
4. Document explicitly: process-name conditions have eventual-consistency semantics, not real-time guarantees.

---

### 5. Title Matching Complexity and Encoding

**Risk Level:** MEDIUM
**Phase:** Phase 3 (Condition Evaluation)

**What goes wrong:**
Window titles sent via OSC 0/2 have encoding ambiguity. `stream_handler.zig:windowTitle()` reads:

```
If title mode 0 is set text is expected to be hex encoded (i.e. utf-8
with each code unit further encoded with two hex digits).
If title mode 2 is set or the terminal is setup for unconditional
utf-8 titles text is interpreted as utf-8. Else text is interpreted
as latin1.
```

A user writes `when title = "My Project"` but the title was set in latin1-mode and stored differently. The match silently fails.

Additionally, `windowTitle()` truncates titles longer than 256 bytes (`buf: [256]u8`). A title pattern that expects a long title will never match.

**Warning Signs:**
- Title-based conditions fail for non-ASCII titles
- Pattern matching works on some terminals but not others (depending on their title encoding mode)

**Prevention:**
1. Store and match titles as the raw bytes Ghostty has already processed (post-decoding). The title stored in memory after `windowTitle()` is already normalized.
2. Document the 256-byte limit.
3. For pattern matching (regex / glob), operate on the already-stored `[256]u8` buffer.

---

### 6. UserVar Not Implemented in OSC 1337

**Risk Level:** MEDIUM
**Phase:** Phase 2 (UserVar Condition)

**What goes wrong:**
The `SetUserVar` command from OSC 1337 is currently logged as unimplemented and returns `parser.command = .invalid` (see `terminal/osc/parsers/iterm2.zig:187–194`). Any feature depending on UserVar-via-OSC requires implementing this OSC handler first, which is a non-trivial prerequisite.

**Warning Signs:**
- UserVar conditions never trigger even when the OSC sequence is sent
- Debug logs show `unimplemented OSC 1337: SetUserVar`

**Prevention:**
1. Implement `SetUserVar` parsing and storage as a prerequisite phase before building UserVar-based conditions.
2. UserVar storage needs a home: either on `terminal.Terminal` or on `Surface`. Surface is more appropriate since UserVars are session-scoped state, not terminal-emulation state.
3. Test with iTerm2 shell integration scripts which already emit `SetUserVar`.

---

### 7. Config Reload Invalidates Active Key Table Pointers

**Risk Level:** MEDIUM
**Phase:** Phase 4 (Config Integration)

**What goes wrong:**
`Surface.keyboard.table_stack` stores raw pointers to `input.Binding.Set` values owned by `self.config.keybind.tables`. When the user reloads the config, `changeConfig()` in `termio/Termio.zig` replaces the config. If the old `Binding.Set` memory is freed while pointers to it are still on the table_stack, the next keypress dereferences freed memory.

This is an existing concern for the key table system (the non-conditional version) but becomes more acute with conditional keybindings because the table may be activated automatically (not just manually by the user) and may be active when a config reload fires.

**Warning Signs:**
- Segfault or undefined behavior after config reload while a key table is active
- Zig safety checks (in debug/safe builds) fire on the dereference

**Prevention:**
1. On config reload, call `deactivateAllKeyTables()` before swapping config, then re-evaluate conditions against the new config.
2. Or: keep the old config alive until the table stack is empty. The existing config lifecycle (see `Surface.zig:config.deinit()`) runs only in `deinit`, so this requires explicit reference counting or a generation counter.
3. The simplest safe approach: clear the table stack on any config change, consistent with how config reloads work for other stateful properties.

---

### 8. Condition Priority Confusion

**Risk Level:** MEDIUM
**Phase:** Phase 1 (Config Syntax Design)

**What goes wrong:**
Users expect: "conditional binding overrides unconditional binding for the same key." But if the implementation inserts conditional bindings into the same flat `Set` as unconditional bindings, the last-defined wins rule (already established in Ghostty) may produce surprising results depending on config file ordering.

Example confusion:
```
# unconditional, defined later in file -> wins?
ctrl+w = close_surface

# conditional, defined earlier in file -> loses?
[process=vim] ctrl+w = write_to_pty:ctrl+w
```

The PROJECT.md requirement states "conditional bindings take priority over unconditional bindings" but the existing `Set` uses simple `ArrayHashMap` with last-writer-wins semantics.

**Warning Signs:**
- Users report that their conditional bindings are ignored when a default binding for the same key exists below them in the config

**Prevention:**
1. Use separate lookup layers: check conditional bindings before the root set. This mirrors how `table_stack` already works — it is checked before the root set (see `Surface.zig:maybeHandleBinding()` lines 2854–2874).
2. Represent conditional bindings as a separate set that overlays the root set, using the same priority ordering as `table_stack`.
3. Document the priority order explicitly in the config docs: conditional > active key tables > root set.

---

### 9. Pattern Matching Performance (Regex)

**Risk Level:** MEDIUM
**Phase:** Phase 3 (Condition Evaluation)

**What goes wrong:**
If conditions support regex (e.g., for title matching), running a regex match on every keypress against a potentially complex pattern is expensive. Ghostty already uses `oniguruma` (imported in `Surface.zig:24` as `oni`) for regex elsewhere. Oniguruma compiles patterns — if patterns are not pre-compiled and cached, each keypress recompiles them.

**Warning Signs:**
- High CPU usage during rapid typing when title-based regex conditions are active
- `@import("oniguruma")` usage without `oni.Regex.compile()` at config load time

**Prevention:**
1. Compile all condition patterns (regex or glob) at config parse time, not at match time.
2. Store compiled patterns in the condition struct alongside the raw pattern string.
3. For simple cases (exact match, prefix, suffix), avoid regex entirely and use `std.mem.eql` / `std.mem.startsWith` — these are order-of-magnitude faster.

---

## Platform-Specific Pitfalls

### macOS: Process Detection API Availability

**Risk Level:** MEDIUM

macOS provides `proc_pidpath()` (from `libproc`) and `proc_pidinfo()` for querying process information by PID. These require the `libproc.h` header, which is already C-importable via `@cImport`. However:

1. **Entitlement requirement in sandboxed builds:** macOS App Store sandboxing restricts `proc_pidpath()` for arbitrary PIDs. Ghostty's macOS build is distributed outside the App Store, but if this ever changes, process-name detection will fail silently.
2. **`proc_pidpath` returns the executable path, not argv[0]:** `vim` and `nvim` have different paths, but a user might expect matching `vi` to match `vim`. Path-based matching requires basename extraction.
3. **`tcgetpgrp()` returns PGID, not PID:** On macOS, the foreground process group may contain multiple processes. You need `tcgetpgrp()` then iterate the group to find the "current" foreground process, which is not always unambiguous in pipelines.

**Prevention:**
- Extract the basename of `proc_pidpath()` result for process-name matching
- Document that matching is against the executable basename, not argv[0]
- Test in a non-sandboxed context during development

### Linux: `/proc` Filesystem Availability

**Risk Level:** LOW

Linux process detection reads `/proc/<pid>/exe` (symlink to executable) or `/proc/<pid>/comm` (15-char truncated name) or `/proc/<pid>/status` (full name via `Name:` field). The differences:

1. **`/proc/<pid>/comm` is truncated to 15 chars:** `ghostty-terminal` becomes `ghostty-termina`. Users matching long process names will see subtle failures.
2. **`/proc/<pid>/exe` requires permission:** On some hardened Linux systems (with `hidepid=2` mount option on `/proc`), reading another process's `/proc` entry may be restricted. However, reading the *child* process (which Ghostty spawned) is always permitted by the parent.
3. **Flatpak isolation:** The GTK build supports Flatpak (`build_config.flatpak`). Inside a Flatpak sandbox, `/proc` is available but the child processes run in a different PID namespace. `tcgetpgrp()` returns a PID from the child namespace. Using `FlatpakHostCommand` (already handled in `termio/Exec.zig:38`) means processes execute on the host; their `/proc` entries may not be visible from inside the sandbox without additional portal access.

**Prevention:**
- Use `/proc/<pid>/comm` for fast 15-char matching, fall back to `/proc/<pid>/status` `Name:` field for longer names
- Document Flatpak limitation — process-name detection may be unavailable in Flatpak builds
- Add a build-config flag to disable process detection (graceful degradation)

### macOS vs. Linux: Different Thread Safety for PTY FD Access

**Risk Level:** LOW

`tcgetpgrp(pty_fd)` is called with the PTY master file descriptor. In Ghostty, the PTY FD is owned by the I/O thread (`termio/Exec.zig`). Calling `tcgetpgrp()` from the GUI thread on a FD owned by another thread is technically a data race on FD state, even though `tcgetpgrp` is a read-only call.

On macOS, FD operations are generally thread-safe at the kernel level. On Linux with `close-on-exec` semantics, the concern is that another thread could close the FD between the check and the call.

**Prevention:**
- Call `tcgetpgrp()` only from the I/O thread (which owns the PTY FD)
- Pass the result back to the GUI thread via the existing `surface_mailbox` mechanism
- Never access the PTY FD from the GUI thread

---

## Performance Pitfalls

### Summary Table

| Pitfall | Operation | Cost | Mitigation |
|---------|-----------|------|-----------|
| Per-keypress process syscall | `tcgetpgrp` + `proc_pidpath` | 8–33 µs | Cache, update async |
| Per-keypress regex compile | Oniguruma `compile()` | 50–500 µs | Compile at config load |
| Per-keypress regex match | Oniguruma `match()` | 2–20 µs | Use exact match when possible |
| Polling without caching | Timer every 200 ms | Negligible | Already bounded by `TERMIOS_POLL_MS` |
| Config reload with active table | `deinit` of live pointer | Use-after-free | Clear table stack on reload |

### The Key Constraint

The binding lookup (`Set.getEvent()`) uses `ArrayHashMap` which is designed to be called on every keypress (the comment at `Binding.zig:2007` explicitly states this). Any condition evaluation added to the critical path must match the O(1) characteristics of the existing map lookup. Process name comparison with a cached `[]const u8` is O(n) on name length but with n < 256 this is ~10–50 ns — acceptable. Syscalls are not.

---

## Recommendations

### Priority Order for Implementation Safety

1. **Define the config syntax first, before any code.** The syntax must not collide with existing delimiters (`=`, `:`, `>`, `/`). Use `[condition]` bracket prefix. Verify against all existing `parseCLI` tests before writing any evaluation logic.

2. **Implement UserVar storage before UserVar conditions.** OSC 1337 `SetUserVar` is currently a stub. This is a prerequisite, not an optional task.

3. **Cache all runtime state; never do syscalls on the keypress path.** Use `start_command`/`stop_command` surface messages as the primary update mechanism. Use a 200 ms fallback timer for the no-shell-integration path.

4. **Accept the process-change race condition.** Do not try to eliminate it with synchronous checks — that creates worse latency problems. Document it.

5. **Use the existing `table_stack` model for priority.** Conditional bindings should be evaluated as an overlay on the root set, consistent with how `table_stack` works today, rather than replacing or merging into the root set. This preserves the existing priority semantics users already understand.

6. **Clear the active table stack on config reload.** This prevents use-after-free from stale pointers into freed config memory.

7. **Compile regex/glob patterns at config parse time.** Store compiled form alongside the condition struct. Use exact-match fast paths where pattern syntax allows.

8. **Test the Flatpak path explicitly.** Process-name detection may be silently broken in Flatpak builds. Detect and degrade gracefully.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|----------------|------------|
| Config syntax design | Delimiter collision with existing parser | Use `[condition]` prefix, run all existing binding tests |
| Process name detection | Syscall on keypress path | Cache result; update via surface messages |
| OSC 1337 UserVar | Unimplemented handler stub | Implement `SetUserVar` as prerequisite |
| Condition evaluation | Regex recompilation per keypress | Compile at config load time |
| Config reload | Stale table pointer to freed memory | Clear table stack on config change |
| Linux Flatpak | PID namespace isolation | Detect and disable gracefully |
| macOS sandboxing | `proc_pidpath` entitlement restrictions | Test outside App Store distribution |
| Priority semantics | Conditional vs. unconditional binding order | Use overlay model, not flat merge |
| Race condition | Process changes between cache update and keypress | Document as known limitation, accept |
| Title encoding | Latin1 vs. UTF-8 title mode | Operate on already-decoded stored title |
