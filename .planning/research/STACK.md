# Stack Research: Conditional Keybindings

**Researched:** 2026-03-18
**Overall confidence:** HIGH for existing Ghostty infrastructure, MEDIUM for platform APIs, HIGH for OSC integration approach

---

## Existing Infrastructure (in Ghostty)

### Conditional System (`src/config/conditional.zig`)

Ghostty already has a conditional configuration system. `conditional.State` holds typed state (currently `theme` and `os`), and `conditional.Conditional` stores `{ key, op, value }` tuples. The `State.match()` method evaluates a conditional against current state.

This is the **primary extension point** for adding process-name and user-var matching. The `State` struct needs two new fields:
- `process_name: []const u8` — foreground process basename
- `user_vars: std.StringHashMapUnmanaged([]const u8)` — runtime variables

The existing `match()` method currently only handles enum fields (`@tagName(raw)`). Extending to `[]const u8` fields requires a small refactor of the inline switch, but the structure is well-suited for it.

### Key Table System (`src/Surface.zig`, `src/input/Binding.zig`)

Ghostty already has a named key-table stack (`keyboard.table_stack`, capped at 8). The `activate_key_table` / `activate_key_table_once` / `deactivate_key_table` / `deactivate_all_key_tables` actions drive it. Tables are named entries in `Config.Keybinds.tables` (a `StringArrayHashMapUnmanaged(Binding.Set)`).

**Key insight:** The table-stack approach is already in Ghostty. Conditional keybindings can be built on top of it: at each key event, check active conditions against current state and activate/deactivate tables as appropriate, or alternatively evaluate conditions inline during key lookup.

### Keybind Parsing (`src/config/Config.zig`, `Keybinds` struct)

`Keybinds.parseCLI` already parses the `table_name/trigger=action` syntax. Adding a condition prefix (e.g., `when:process=vim/trigger=action`) is a syntactic extension of the existing flag-parsing in `Binding.Parser.parseFlags`.

### OSC Parsing Infrastructure (`src/terminal/osc/parsers/iterm2.zig`)

The OSC 1337 parser (`parsers/iterm2.zig`) already recognizes `SetUserVar` as a valid key but marks it "unimplemented" and returns `null`. The parsing machinery is complete — only the `Command` enum variant and the dispatch handler in `stream_handler.zig` are missing.

### `RepeatableStringMap` (`src/config/RepeatableStringMap.zig`)

An existing `ArrayHashMapUnmanaged([:0]const u8, [:0]const u8)` with `parseCLI`, `clone`, `equal`, and `formatEntry`. This is the right type for pre-defined user variables in config (analogous to the `env` config field at line 1304 of `Config.zig`).

### Window Title Access

Window title flows through `apprt.surface.Message.set_title` (a 256-byte array), handled in `Surface.zig:949`. The runtime title is accessible via `self.rt_surface.getTitle()` (line 973). This means at key-dispatch time, title is available via the surface's runtime backend.

### Linux Process Name Pattern (`src/os/systemd.zig`)

`systemd.zig` already demonstrates the exact pattern needed for Linux process detection: read `/proc/{pid}/comm` (max 16 bytes, `TASK_COMM_LEN`). This can be directly adapted for foreground process name lookup.

---

## Platform APIs Needed

### macOS

**Foreground process group from PTY (`tcgetpgrp`):**

```c
#include <unistd.h>
pid_t tcgetpgrp(int fd);  // Returns foreground process group of terminal fd
```

Call `tcgetpgrp(pty_master_fd)` to get the foreground process group ID (PGID). Then find the PID within that group (usually the PGID itself for a simple shell → child relationship).

**Process name from PID (`libproc.h`):**

```c
#include <libproc.h>
int proc_name(int pid, void *buffer, uint32_t buffersize);
// Returns: 0 on failure, length on success
// buffer receives the process name (basename only, max MAXCOMLEN = 16)

int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
// Returns: 0 on failure, length on success
// buffer receives the full executable path (max PROC_PIDPATHINFO_MAXSIZE = 4096)
```

`proc_name` returns just the basename (e.g., `vim`). `proc_pidpath` returns the full path (e.g., `/usr/bin/vim`). For matching purposes, `proc_name` is sufficient and cheaper.

**Zig extern declaration:**

```zig
extern "c" fn proc_name(pid: c_int, buf: [*]u8, bufsize: u32) c_int;
extern "c" fn proc_pidpath(pid: c_int, buf: [*]u8, bufsize: u32) c_int;

const MAXCOMLEN = 16;
const PROC_PIDPATHINFO_MAXSIZE = 4096;
```

These are available on macOS 10.5+ (all Ghostty-supported versions). Header: `<libproc.h>` — but Ghostty uses `@cImport` only in specific files; this should be added to `src/os/macos.zig` (which already uses objc and extern "c" declarations).

**Confidence:** HIGH — `proc_name` is a standard public macOS API documented in Apple developer documentation and used widely in terminal emulators.

### Linux

**Foreground process group from PTY:**

```c
#include <unistd.h>
pid_t tcgetpgrp(int fd);
```

Same POSIX API as macOS.

**Process name from PGID:**

Read `/proc/{pgid}/comm` (as demonstrated in `src/os/systemd.zig`):

```zig
var buf: [16]u8 = undefined;  // TASK_COMM_LEN = 16
const path = try std.fmt.bufPrint(&path_buf, "/proc/{d}/comm", .{pgid});
const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
defer file.close();
const n = try file.readAll(&buf);
const name = std.mem.trimRight(u8, buf[0..n], "\n");
```

For the full executable path: `/proc/{pgid}/exe` (symlink, use `std.fs.readLink`).

**Confidence:** HIGH — the exact pattern already exists in `systemd.zig` (lines 31-58).

**PTY file descriptor access:**

The PTY master fd is managed in `src/termio/Exec.zig`. The subprocess stores the PID in `cmd.pid` (accessible via `subprocess.process.fork_exec.cmd.pid`). A new method on `Exec` or `Termio` to expose the PTY master fd for `tcgetpgrp` polling is needed.

**Performance note:** `tcgetpgrp` + `proc_name` / `/proc/comm` are cheap syscalls. On a 100 Hz key-repeat rate, these should not contribute measurable latency. Cache the result and invalidate only on PTY state change events (or poll at most every 100ms).

---

## Pattern Matching

### Recommended Approach: `std.mem` exact + glob, with optional oniguruma for regex

Ghostty already vendors **oniguruma** (`pkg/oniguruma`) and uses it in `src/renderer/link.zig` for regex-backed URL matching. This is available for use in conditional matching.

**Three-tier matching (recommended for v1):**

1. **Exact match** — `std.mem.eql(u8, candidate, pattern)`. Zero allocation, O(n). Handles `process=vim`.

2. **Glob / wildcard match** — Zig 0.15 does not have `std.mem.glob` in stable, but Ghostty can implement a simple recursive glob (handling `*` and `?`) in ~30 lines. Handles `process=vi*`, `title=*editor*`.

   ```zig
   pub fn globMatch(pattern: []const u8, str: []const u8) bool {
       if (pattern.len == 0) return str.len == 0;
       if (pattern[0] == '*') {
           // Try matching the rest of pattern against each suffix of str
           var i: usize = 0;
           while (i <= str.len) : (i += 1) {
               if (globMatch(pattern[1..], str[i..])) return true;
           }
           return false;
       }
       if (str.len == 0) return false;
       if (pattern[0] == '?' or pattern[0] == str[0]) {
           return globMatch(pattern[1..], str[1..]);
       }
       return false;
   }
   ```

3. **Regex** — Use the existing `oniguruma` binding for `~` or `/regex/` syntax (similar to how Kitty uses its matcher). This is optional for v1 but the infrastructure exists.

**Recommended v1 syntax:** Only exact and glob matching. Regex can be v2. This avoids compile-time regex cost on every config load.

**Existing precedent:** The `conditional.State.match()` method uses `std.mem.eql` for enum-name comparison. The same pattern can be extended with a glob fallback when the value contains `*` or `?`.

---

## OSC Integration

### OSC 1337 SetUserVar Format

The escape sequence is:
```
ESC ] 1337 ; SetUserVar=<name>=<base64-encoded-value> ST
```

Where `ST` is either `ESC \` (ST) or `BEL` (`\a`). The value is base64-encoded UTF-8.

**Example** (shell integration):
```bash
# Set variable "in_vim" to "1"
printf '\e]1337;SetUserVar=in_vim=%s\e\\' "$(printf '1' | base64)"
```

### Ghostty Integration Path

**Step 1:** In `src/terminal/osc/parsers/iterm2.zig`, implement the `SetUserVar` case (currently line 187-190, falls through to "unimplemented"):

```zig
.SetUserVar => {
    const value = value_ orelse {
        parser.command = .invalid;
        return null;
    };
    // value format: "<name>=<base64-value>"
    const eq_idx = std.mem.indexOfScalar(u8, value, '=') orelse {
        parser.command = .invalid;
        return null;
    };
    parser.command = .{
        .set_user_var = .{
            .key = value[0..eq_idx],
            .value = value[eq_idx + 1..],  // base64-encoded
        },
    };
    return &parser.command;
},
```

**Step 2:** Add `set_user_var` to the `Command` union in `src/terminal/osc.zig`:

```zig
set_user_var: struct {
    key: [:0]const u8,
    value: [:0]const u8,  // base64-encoded; handler decodes
},
```

**Step 3:** In `src/termio/stream_handler.zig`, handle the new command:

```zig
.set_user_var => |v| {
    // Decode base64 value
    const decoded = base64.decode(v.value) catch {
        log.warn("invalid base64 in SetUserVar", .{});
        return;
    };
    // Store in Surface's user_vars map via mailbox message
    self.surface_mailbox.push(.{ .set_user_var = .{
        .key = v.key,
        .value = decoded,
    }});
},
```

**Step 4:** Store variables in `Surface` (or a dedicated `ConditionalState` struct living on Surface):

```zig
user_vars: std.StringHashMapUnmanaged([]const u8) = .empty,
```

**Pre-defined user vars in config:** Use an existing `RepeatableStringMap` field on config (like `env`), merged into `user_vars` at surface init time.

**OSC base64:** Zig standard library has `std.base64.standard.Decoder` — no additional dependency needed.

---

## Recommendations

### 1. Extend `conditional.State` rather than invent a new system

Add `process_name` and `user_vars` to `conditional.State`. The existing `match()` method already has the right structure. The only change is handling `[]const u8` fields in addition to enum fields. This keeps conditional logic in one place and reuses the `Conditional { key, op, value }` type.

**Recommended approach for `match()` extension:**

```zig
.process_name => std.mem.eql(u8, self.process_name, cond.value) or
                 globMatch(cond.value, self.process_name),
.user_var => {
    // cond.value format: "varname=expected_value" or just "varname"
    // parse out varname, look up in self.user_vars, compare
},
```

### 2. Implement process detection as a separate `src/os/process.zig`

Create `src/os/process.zig` with a `foregroundProcessName(pty_fd: std.posix.fd_t, buf: []u8) ![]const u8` function that dispatches to macOS (`proc_name`) or Linux (`/proc/{pgid}/comm`). This follows the existing pattern in `src/os/`.

### 3. Poll process name on I/O thread, not on key-press thread

The I/O thread in `src/termio/Thread.zig` already has a timer (`termios_timer`) for polling PTY state. Add a second low-frequency timer (e.g., 200ms) that:
1. Calls `tcgetpgrp(pty_master_fd)` to get the foreground PGID
2. Calls `proc_name` / reads `/proc/{pgid}/comm`
3. Sends a `surface_mailbox` message if the name changed

This avoids blocking the key-press path.

### 4. Config syntax: inline `when:` prefix on `keybind`

Proposed syntax (Ghostty-native, not Kitty syntax):

```
keybind = when:process=vim>ctrl+w=close_buffer
keybind = when:process=vi*>ctrl+w=close_buffer
keybind = when:title=*editor*>ctrl+w=close_buffer
keybind = when:var=in_editor>ctrl+c=text:q
```

Parse the `when:` prefix in `Binding.Parser.parseFlags` (which already handles `global:`, `all:`, `unconsumed:`, `performable:`). Store the condition on the `Binding` struct alongside `flags`.

### 5. Key lookup: check condition at `getEvent` time

At `Surface.keyCallback` (line 2576+), during binding lookup, add condition evaluation inline:

```zig
// After finding a candidate entry from set.getEvent(event):
if (entry.binding.condition) |cond| {
    if (!self.conditional_state.match(cond)) continue; // try next
}
```

This is O(1) per key press for simple exact or glob matching.

### 6. Use exact + glob matching for v1, defer regex

- Exact: `std.mem.eql` — zero cost
- Glob: 30-line custom implementation using `*` and `?` — no dependency
- Regex via oniguruma: defer to v2 (add `/regex/` syntax)

---

## Confidence Levels

| Area | Confidence | Rationale |
|------|------------|-----------|
| Existing conditional.zig extension | HIGH | Code is in-repo and well-understood |
| Key-table system reuse | HIGH | Already shipping in Ghostty |
| OSC 1337 SetUserVar parsing | HIGH | Parser structure exists; only Command variant missing |
| macOS `proc_name` API | HIGH | Standard Apple API, widely used in terminal emulators |
| Linux `/proc/{pid}/comm` approach | HIGH | Exact pattern already in `systemd.zig` |
| `tcgetpgrp` for foreground process | HIGH | POSIX standard, available on both platforms |
| Glob matching in Zig | HIGH | Standard algorithm, no dependency |
| Config syntax `when:` prefix | MEDIUM | Design choice — needs review by Ghostty maintainers for stylistic fit |
| Performance of polling approach | MEDIUM | 200ms timer is an estimate; needs profiling |
| Oniguruma for regex matching | HIGH | Already vendored and used in link.zig |

---

## Gaps to Address

- **Thread safety for `user_vars` / `conditional_state`:** The process-name update comes from the I/O thread but is read by the key-press callback (which runs on the main/UI thread). A simple approach: store the process name as an atomic or pass it via the existing `surface_mailbox` message infrastructure. Needs design decision.

- **`conditional.State` owns `user_vars` memory:** Who allocates and frees the string map entries? The arena-based config approach won't work here since user vars are dynamic (set at runtime via OSC). The surface's GPA allocator is appropriate, with careful deallocation on `deinit`.

- **Title matching requires rt_surface.getTitle() on key-press path:** The title is stored in the platform layer (GTK widget title or macOS window title), not in `Surface`'s Zig struct directly. The `conditional_state` should cache the title when `set_title` is received (the `Surface.handleTerminalMessage` path at line 949) rather than querying the platform on every key press.

- **Zig 0.15 `std.mem.glob`:** Verify if `std.mem.glob` exists in Zig 0.15.2 before implementing custom glob. A quick check in Zig standard library docs is needed (not confirmed in this research).

- **`RepeatableStringMap` for config-defined user vars:** The merge strategy (config vars vs OSC-set vars) needs definition: does config override OSC, or does OSC override config?
