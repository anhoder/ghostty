# Phase 3: Process Name Detection - Research

**Researched:** 2026-03-18
**Domain:** Terminal process detection (macOS/Linux)
**Confidence:** HIGH

## Summary

Phase 3 implements asynchronous foreground process name detection on both macOS and Linux platforms. The core approach uses `tcgetpgrp()` to get the foreground process group ID from the PTY master file descriptor, then platform-specific APIs to resolve the process name. Detection runs on a 200ms timer in the existing I/O thread (matching `TERMIOS_POLL_MS`), updates `RuntimeContext.process_name` via mailbox message, and degrades gracefully in sandboxed environments like Flatpak.

**Primary recommendation:** Use `tcgetpgrp(pty_master_fd)` + platform-specific name resolution (Linux: `/proc/<pid>/comm`, macOS: `libproc.h`), poll every 200ms via existing `xev.Timer` infrastructure in `Exec.zig`, send updates to Surface via mailbox.

## User Constraints

### Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PROC-03 | Process name detection works on macOS | `tcgetpgrp()` + `libproc` (`proc_pidinfo` with `PROC_PIDTBSDINFO`) provides process name from PGID |
| PROC-04 | Process name detection works on Linux | `tcgetpgrp()` + `/proc/<pid>/stat` (field 5: pgrp) + `/proc/<pid>/comm` provides process name from PGID |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `tcgetpgrp()` | POSIX | Get foreground process group ID from terminal fd | Standard POSIX function, works identically on macOS/Linux/BSD |
| `/proc/<pid>/comm` | Linux kernel | Read process name (16 char max) | Standard Linux interface, fast single-file read |
| `/proc/<pid>/stat` | Linux kernel | Read process group ID (field 5) | Standard Linux interface for process metadata |
| `libproc.h` | macOS | Query process info via `proc_pidinfo`/`proc_listallpids` | De facto standard for macOS process introspection (used by `ps`, Activity Monitor) |
| `xev.Timer` | Ghostty existing | Async timer for polling | Already used for termios polling at 200ms |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `getpgid(pid)` | POSIX | Get process group ID for a specific PID | Filtering processes by PGID after `tcgetpgrp()` |
| `proc_listallpids()` | macOS libproc | List all PIDs on system | macOS: enumerate processes to find PGID match |
| `std.fs.Dir.iterate()` | Zig stdlib | Iterate `/proc` directory | Linux: enumerate PIDs in `/proc` |

### Installation

No external dependencies — all APIs are system-provided.

## Architecture Patterns

### Recommended Integration Points

```
src/
├── os/
│   └── process.zig          # New file: platform-specific process detection
├── termio/
│   └── Exec.zig             # Add process detection timer callback
├── apprt/
│   └── surface.zig          # Add process_name_update message type
└── Surface.zig              # Handle process_name_update, update runtime_context
```

### Pattern 1: Async Polling via Timer

**What:** Reuse existing `xev.Timer` infrastructure (already polling termios at 200ms) to add process detection callback

**When to use:** Keeps keypress path syscall-free; eventual consistency acceptable (~200ms lag)

**Example:**
```zig
// In Exec.zig termiosTimer callback (existing)
fn termiosTimer(...) xev.CallbackAction {
    // ... existing termios logic ...

    // NEW: Process name detection
    if (comptime builtin.os.tag != .windows) {
        detectProcessName(td) catch |err| {
            log.warn("process detection failed err={}", .{err});
        };
    }

    // Rearm timer
    if (exec.termios_timer_running) {
        exec.termios_timer.run(...);
    }
    return .disarm;
}
```

### Pattern 2: Platform Dispatch

**What:** Single public API in `os/process.zig`, platform-specific implementations

**When to use:** Clean separation of Linux vs macOS logic

**Example:**
```zig
// src/os/process.zig
pub fn getForegroundProcessName(
    alloc: Allocator,
    pty_master_fd: posix.fd_t,
) !?[]const u8 {
    return switch (builtin.os.tag) {
        .linux => getForegroundProcessNameLinux(alloc, pty_master_fd),
        .macos, .freebsd => getForegroundProcessNameBSD(alloc, pty_master_fd),
        else => null, // Unsupported platform
    };
}
```

### Pattern 3: Mailbox Message for Updates

**What:** Send process name changes from I/O thread to Surface via mailbox (same pattern as `password_input`, `pwd_change`)

**When to use:** Cross-thread communication without locks

**Example:**
```zig
// In Exec.zig after detecting name change
_ = td.surface_mailbox.push(.{
    .process_name_update = .{
        .name = name_slice, // Owned by message
    },
}, .{ .forever = {} });

// In Surface.zig handleMessage
.process_name_update => |name| {
    defer self.alloc.free(name);

    // Update runtime context
    if (self.runtime_context.process_name) |old| {
        self.alloc.free(old);
    }
    self.runtime_context.process_name = try self.alloc.dupe(u8, name);
},
```

### Anti-Patterns to Avoid

- **Per-keypress syscalls:** Never call `tcgetpgrp()` or read `/proc` on keypress path — defeats PROC-05 requirement
- **Blocking I/O in timer callback:** All file reads must be non-blocking or fast enough to not stall event loop
- **Ignoring PGID=0 or errors:** `tcgetpgrp()` returns 0 or -1 when no foreground group exists — treat as "no process" not crash

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Process enumeration | Custom `/proc` parser or `ps` wrapper | `std.fs.Dir.iterate()` (Linux), `proc_listallpids()` (macOS) | Edge cases: zombie processes, permission errors, race conditions |
| Process name truncation | String manipulation for 16-char limit | Read `/proc/<pid>/comm` directly | Kernel already truncates to `TASK_COMM_LEN` (16 bytes) |
| Cross-platform abstraction | Generic "process" API | Platform dispatch with shared interface | macOS and Linux have fundamentally different APIs; thin wrapper is sufficient |

**Key insight:** Process detection is inherently racy (process can exit between `tcgetpgrp()` and name lookup) — accept this, handle errors gracefully, don't try to eliminate the race.

## Common Pitfalls

### Pitfall 1: Using PTY Slave FD Instead of Master

**What goes wrong:** `tcgetpgrp()` called on PTY slave returns correct PGID, but Ghostty only has PTY master fd in I/O thread

**Why it happens:** Documentation examples often show `tcgetpgrp(STDIN_FILENO)` which works for shell scripts but not terminal emulators

**How to avoid:** Call `tcgetpgrp(pty_master_fd)` directly — works on both Linux and macOS

**Warning signs:** `tcgetpgrp()` returns -1 with `ENOTTY` (not a terminal)

### Pitfall 2: Assuming PGID == PID

**What goes wrong:** Using `tcgetpgrp()` result directly as PID for `/proc/<pid>/comm` or `proc_pidinfo()`

**Why it happens:** Process Group ID and Process ID are different concepts; PGID is shared by multiple processes

**How to avoid:** After `tcgetpgrp()`, enumerate all processes and filter by `getpgid(pid) == foreground_pgid`

**Warning signs:** Process name is always the shell, never the foreground command (vim, etc.)

### Pitfall 3: Memory Leaks in Mailbox Messages

**What goes wrong:** Allocating process name string, sending via mailbox, but receiver doesn't free it

**Why it happens:** Mailbox transfers ownership but this isn't enforced by type system

**How to avoid:** Use `defer` in message handler to free allocated strings; document ownership in message type

**Warning signs:** Memory usage grows over time when switching between processes

### Pitfall 4: Flatpak /proc Isolation

**What goes wrong:** `/proc` only shows processes inside Flatpak sandbox, `tcgetpgrp()` returns PGID for host process that doesn't exist in sandbox `/proc`

**Why it happens:** Flatpak uses PID namespaces for security isolation

**How to avoid:** Detect Flatpak at startup (`std.fs.accessAbsolute("/.flatpak-info")`), log warning once, treat all process detection as unavailable

**Warning signs:** `tcgetpgrp()` succeeds but no matching PID found in `/proc`

## Code Examples

### Linux: Get Foreground Process Name

```zig
// Source: Research synthesis from man7.org tcgetpgrp(3), proc(5)
fn getForegroundProcessNameLinux(
    alloc: Allocator,
    pty_master_fd: posix.fd_t,
) !?[]const u8 {
    // Get foreground process group ID
    const pgid = std.c.tcgetpgrp(pty_master_fd);
    if (pgid <= 0) return null; // No foreground process group

    // Iterate /proc to find process with matching PGID
    var proc_dir = try std.fs.openDirAbsolute("/proc", .{ .iterate = true });
    defer proc_dir.close();

    var iter = proc_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;

        // Parse PID from directory name
        const pid = std.fmt.parseInt(std.c.pid_t, entry.name, 10) catch continue;

        // Check if this process is in the foreground group
        if (std.c.getpgid(pid) == pgid) {
            // Read process name from /proc/<pid>/comm
            var path_buf: [64]u8 = undefined;
            const path = try std.fmt.bufPrint(&path_buf, "/proc/{d}/comm", .{pid});

            const file = std.fs.openFileAbsolute(path, .{}) catch continue;
            defer file.close();

            var name_buf: [16]u8 = undefined; // TASK_COMM_LEN
            const bytes_read = try file.readAll(&name_buf);
            const name = std.mem.trimRight(u8, name_buf[0..bytes_read], "\n");

            return try alloc.dupe(u8, name);
        }
    }

    return null; // No matching process found
}
```

### macOS: Get Foreground Process Name

```zig
// Source: Research synthesis from libproc.h documentation
const c = @cImport({
    @cInclude("libproc.h");
});

fn getForegroundProcessNameBSD(
    alloc: Allocator,
    pty_master_fd: posix.fd_t,
) !?[]const u8 {
    // Get foreground process group ID
    const pgid = std.c.tcgetpgrp(pty_master_fd);
    if (pgid <= 0) return null;

    // Get list of all PIDs
    const max_pids = 4096;
    const pids = try alloc.alloc(std.c.pid_t, max_pids);
    defer alloc.free(pids);

    const num_pids = c.proc_listallpids(pids.ptr, @intCast(max_pids * @sizeOf(std.c.pid_t)));
    if (num_pids <= 0) return null;

    // Find process with matching PGID
    for (pids[0..@intCast(num_pids)]) |pid| {
        if (std.c.getpgid(pid) == pgid) {
            // Get process info
            var bsdinfo: c.proc_bsdinfo = undefined;
            const ret = c.proc_pidinfo(
                pid,
                c.PROC_PIDTBSDINFO,
                0,
                &bsdinfo,
                @sizeOf(c.proc_bsdinfo),
            );

            if (ret <= 0) continue;

            // pbi_name is null-terminated, max 16 chars
            const name = std.mem.sliceTo(&bsdinfo.pbi_name, 0);
            return try alloc.dupe(u8, name);
        }
    }

    return null;
}
```

### Timer Integration in Exec.zig

```zig
// Source: Existing termiosTimer pattern in Exec.zig
fn termiosTimer(
    td_: ?*termio.Termio.ThreadData,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Timer.RunError!void,
) xev.CallbackAction {
    _ = r catch |err| switch (err) {
        error.Canceled => return .disarm,
        else => {
            log.warn("error in termios timer callback err={}", .{err});
            @panic("crash in termios timer callback");
        },
    };

    const td = td_.?;
    assert(td.backend == .exec);
    const exec = &td.backend.exec;

    // Existing termios mode detection
    const mode = (Pty{ .master = exec.read_thread_fd, .slave = undefined })
        .getMode() catch .{};

    if (!std.meta.eql(mode, exec.termios_mode)) {
        exec.termios_mode = mode;
        // ... existing password_input logic ...
    }

    // NEW: Process name detection
    if (comptime builtin.os.tag != .windows) {
        detectProcessName(td, exec.read_thread_fd) catch |err| {
            log.warn("process name detection failed err={}", .{err});
        };
    }

    // Rearm timer
    if (exec.termios_timer_running) {
        exec.termios_timer.run(
            td.loop,
            &exec.termios_timer_c,
            TERMIOS_POLL_MS,
            termio.Termio.ThreadData,
            td,
            termiosTimer,
        );
    }

    return .disarm;
}

fn detectProcessName(
    td: *termio.Termio.ThreadData,
    pty_master_fd: posix.fd_t,
) !void {
    const name = try internal_os.process.getForegroundProcessName(
        td.arena.allocator(), // Temporary allocation
        pty_master_fd,
    ) orelse return; // No foreground process

    // Send to Surface via mailbox
    _ = td.surface_mailbox.push(.{
        .process_name_update = name, // Ownership transferred
    }, .{ .forever = {} });
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Per-keypress `tcgetpgrp()` | Async polling every 200ms | Terminal emulator best practice | Eliminates keypress latency |
| Parsing `ps` output | Direct `/proc` or `libproc` | Linux 2.6+ (2003), macOS 10.5+ (2007) | 10-100x faster, no fork overhead |
| Blocking syscalls | Event loop integration | Modern async I/O (io_uring, kqueue) | Non-blocking, scales to many surfaces |

**Deprecated/outdated:**
- `ps aux | grep`: Slow (fork+exec), fragile parsing, unnecessary overhead
- Polling `/proc/<pid>/stat` for all PIDs: O(n) every poll; better to filter by PGID first

## Open Questions

1. **Process name caching strategy**
   - What we know: Name changes are rare (only when user runs new command)
   - What's unclear: Should we cache last-known name and only send updates on change?
   - Recommendation: Send update only if name differs from last poll (store `last_process_name` in `ThreadData`)

2. **Flatpak detection timing**
   - What we know: `/.flatpak-info` exists in Flatpak environment
   - What's unclear: Check once at startup or every poll?
   - Recommendation: Check once in `Exec.init()`, store boolean flag, log warning once

3. **Error handling for permission denied**
   - What we know: `proc_pidinfo()` may fail for other users' processes without root
   - What's unclear: Should we fall back to shell name or report "unknown"?
   - Recommendation: Return `null` (no process name), let conditional bindings fall through to unconditional

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Zig built-in test runner |
| Config file | None — tests embedded in source files |
| Quick run command | `zig build test` |
| Full suite command | `zig build test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PROC-03 | macOS: `tcgetpgrp()` + `libproc` returns process name | unit | `zig test src/os/process.zig` | ❌ Wave 0 |
| PROC-04 | Linux: `tcgetpgrp()` + `/proc` returns process name | unit | `zig test src/os/process.zig` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `zig build test -Dfilter=process`
- **Per wave merge:** `zig build test`
- **Phase gate:** Full suite green + manual verification (open vim in Ghostty, verify process name updates)

### Wave 0 Gaps

- [ ] `src/os/process.zig` — covers PROC-03, PROC-04 (unit tests for platform-specific logic)
- [ ] Integration test: spawn Ghostty, run vim, verify `RuntimeContext.process_name == "vim"`

## Sources

### Primary (HIGH confidence)

- [man7.org - tcgetpgrp(3)](https://man7.org/linux/man-pages/man3/tcgetpgrp.3.html) - POSIX terminal foreground process group
- [man7.org - proc(5)](https://man7.org/linux/man-pages/man5/proc.5.html) - Linux /proc filesystem documentation
- [opengroup.org - tcgetpgrp](https://pubs.opengroup.org/onlinepubs/9699919799/functions/tcgetpgrp.html) - POSIX standard specification

### Secondary (MEDIUM confidence)

- [stackoverflow.com - Linux foreground process detection](https://stackoverflow.com/questions/tagged/tcgetpgrp) - Community patterns and pitfalls
- [stackoverflow.com - macOS libproc usage](https://stackoverflow.com/questions/tagged/libproc) - Practical libproc examples
- [flatpak.org - Sandbox documentation](https://docs.flatpak.org/en/latest/sandbox-permissions.html) - Flatpak /proc isolation behavior

### Tertiary (LOW confidence)

- Various terminal emulator implementations (Alacritty, Kitty, WezTerm) - Real-world polling patterns

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - `tcgetpgrp()`, `/proc`, `libproc` are stable, well-documented APIs
- Architecture: HIGH - Existing `xev.Timer` pattern proven in termios polling
- Pitfalls: HIGH - Verified via official documentation and community reports

**Research date:** 2026-03-18
**Valid until:** 90 days (stable POSIX/kernel APIs, unlikely to change)
