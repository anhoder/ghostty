# Architecture Research: Conditional Keybindings

**Researched:** 2026-03-18
**Confidence:** HIGH (based on direct source analysis)

---

## Current Keybinding Flow

### Config-time parsing

Keybinds are stored in `Config.Keybinds` (`src/config/Config.zig`, line ~6396), which owns:
- `set: input.Binding.Set` — the root/default binding set
- `tables: std.StringArrayHashMapUnmanaged(input.Binding.Set)` — named key tables (e.g. `foo/ctrl+a=new_window`)

Each `input.Binding.Set` (`src/input/Binding.zig`, line ~2009) is a hash map from `Trigger` → `Value`. A `Value` is one of:
- `.leader`: points to a child `Set` (sequence support, e.g. `ctrl+a>n`)
- `.leaf`: a single `Action` + `Flags`
- `.leaf_chained`: a list of actions (chain support)

The `Keybinds.parseCLI` method tokenises a string like `[table/][flags:]trigger=action` and calls `set.parseAndPut`. Flags parsed here: `all:`, `global:`, `unconsumed:`, `performable:`.

### Runtime lookup in Surface

`Surface.keyCallback` (`src/Surface.zig`) calls `self.maybeHandleBinding(event, ...)` on every key press/repeat event.

`maybeHandleBinding` resolves an entry using this priority order:
1. Active key sequence set (from a previously pressed leader key)
2. Active key table stack (inner-most to outer-most), controlled by `activate_key_table`/`deactivate_key_table` actions
3. Root set: `self.config.keybind.set.getEvent(event)`

Once a matching entry is found, the action is executed via `performBindingAction`. The consumed flag on the binding determines whether the key is forwarded to the PTY.

### Binding.Flags

Current flags in `Binding.Flags` (packed struct):
- `consumed: bool` — whether to swallow the keypress
- `all: bool` — broadcast to all surfaces
- `global: bool` — system-wide shortcut
- `performable: bool` — only trigger if action is currently possible

---

## Current Conditional System

`src/config/conditional.zig` is the existing conditional evaluation engine.

### What it currently supports

`conditional.State` is a **static struct** evaluated once at startup (or on theme change):
```zig
pub const State = struct {
    theme: Theme = .light,   // .light | .dark
    os: std.Target.Os.Tag = builtin.target.os.tag,
    pub const Theme = enum { light, dark };
};
```

`Conditional` pairs a `Key` (derived from `State` field names) with an `Op` (`.eq` / `.ne`) and a string value.

`State.match(cond)` checks the single condition against current state.

### Critical design insight

The conditional system is explicitly **static** — the comment on `State` reads: "Conditionals in Ghostty configuration are based on a static, typed state of the world instead of a dynamic key-value set." This design is intentional for type-checking and the C API.

Process name, window title, and user variables are **dynamic** — they change continuously at runtime. They cannot be added to `conditional.State` as-is. The conditional system is used for config-time evaluation (dark/light theme switching, OS-specific defaults), not for per-keypress runtime evaluation. Conditional keybindings require a separate evaluation model.

---

## Proposed Component Architecture

### New components to create

#### 1. `src/input/ConditionSet.zig`

Stores a list of `ConditionalBinding` entries parsed from config:

```zig
pub const Condition = union(enum) {
    process_name: []const u8,        // exact match
    process_name_glob: []const u8,   // glob pattern
    window_title: []const u8,        // exact match
    window_title_glob: []const u8,   // glob pattern
    user_var: struct {               // key=value match
        key: []const u8,
        value: []const u8,
    },
};

pub const ConditionalBinding = struct {
    condition: Condition,
    trigger: input.Binding.Trigger,
    action: input.Binding.Action,
    flags: input.Binding.Flags,
};
```

A `ConditionSet` holds a slice of these, built at config load time. At runtime, `Surface` checks the set given current runtime state.

#### 2. Runtime state struct on `Surface`

A small struct on `Surface` that tracks current dynamic context:

```zig
pub const RuntimeContext = struct {
    process_name: ?[]const u8 = null,   // owned, updated when foreground process changes
    window_title: ?[]const u8 = null,   // owned, already tracked via set_title
    user_vars: std.StringArrayHashMapUnmanaged([]const u8) = .empty,  // from OSC 1337
    alloc: Allocator,

    pub fn deinit(self: *RuntimeContext) void { ... }
    pub fn setProcessName(self: *RuntimeContext, name: []const u8) !void { ... }
    pub fn setUserVar(self: *RuntimeContext, key: []const u8, value: []const u8) !void { ... }
};
```

This is stored directly in `Surface` (not behind a mutex, since `Surface` is single-threaded on the main/UI thread for key events). However, process name updates arrive from the IO thread via the surface mailbox — see integration section.

#### 3. `src/input/condition_eval.zig`

A pure evaluation function with no side effects:

```zig
pub fn matches(condition: Condition, ctx: *const Surface.RuntimeContext) bool {
    return switch (condition) {
        .process_name => |name| ctx.process_name != null and
            std.mem.eql(u8, ctx.process_name.?, name),
        .process_name_glob => |pattern| ctx.process_name != null and
            globMatch(pattern, ctx.process_name.?),
        .window_title => |title| ctx.window_title != null and
            std.mem.eql(u8, ctx.window_title.?, title),
        .window_title_glob => |pattern| ctx.window_title != null and
            globMatch(pattern, ctx.window_title.?),
        .user_var => |kv| blk: {
            const v = ctx.user_vars.get(kv.key) orelse break :blk false;
            break :blk std.mem.eql(u8, v, kv.value);
        },
    };
}
```

Glob matching: use `std.fs.path.match` (already available in stdlib) for basic glob, or integrate the existing `oniguruma` (oni) dependency already imported in `Surface.zig` for regex if patterns need more power.

### Modified existing components

#### `src/config/Config.zig` — `Keybinds`

Add `conditional_bindings: ConditionSet = .{}` alongside existing `set` and `tables`. Parsing the new syntax `[when:process=vim:]ctrl+w=close_surface` stores into `conditional_bindings`. Unconditional bindings continue using `set` unchanged.

#### `src/input/Binding.zig` — `Flags`

No change required. Conditional bindings will use the same `Flags` struct.

#### `src/Surface.zig`

Add `runtime_ctx: RuntimeContext` field. Modify `maybeHandleBinding` to check `conditional_bindings` before checking the root `set`:

```
priority order (highest to lowest):
1. active key sequence
2. active key table stack
3. conditional bindings (matched by runtime_ctx) — NEW
4. root set (unconditional bindings)
```

Add handlers for new surface messages: `set_process_name` and `set_user_var`.

#### `src/apprt/surface.zig` — `Message`

Add two new message variants:
```zig
set_process_name: [256]u8,
set_user_var: struct { key: [64]u8, value: [192]u8 },
```

#### `src/termio/stream_handler.zig`

Implement the `SetUserVar` case in the OSC 1337 handler (currently logs "unimplemented"). When a `SetUserVar` command arrives, send `set_user_var` surface message.

---

## Data Flow

### Configuration load time

```
config file text
    ↓
Config.Keybinds.parseCLI()
    ↓
  detect "when:..." prefix in binding string
    ↓
  parse condition (process=X, title=X, var=X:Y)
    ↓
  store in ConditionSet as ConditionalBinding
    ↓
  unconditional bindings continue into Binding.Set as before
```

### Key event handling (runtime, per-keypress)

```
user presses key
    ↓
Surface.keyCallback()
    ↓
Surface.maybeHandleBinding()
    ↓
  1. check sequence_set (leader keys)
  2. check table_stack (activate_key_table)
  3. NEW: check config.keybind.conditional_bindings
         for each ConditionalBinding whose trigger matches event:
           evaluate condition_eval.matches(cond, &self.runtime_ctx)
           if match: return this binding's action
           (last-defined matching conditional binding wins — O(n) scan)
  4. check config.keybind.set (unconditional root bindings)
```

The conditional check is O(n) over conditional bindings for that trigger. Since bindings are sparse and this is per-keypress on the main thread, a simple linear scan is acceptable for v1. If performance becomes an issue, conditional bindings can be grouped by trigger in a `HashMap(Trigger, []ConditionalBinding)`.

### Process name update (runtime, from IO thread)

```
shell integration OSC sequence received (e.g. OSC 7 with process context,
or a new custom OSC for process name reporting)
    OR
foreground process group change detected via ioctl(TIOCGPGRP) + /proc/<pid>/comm
    ↓
termio/stream_handler or termio/Exec reads process name
    ↓
surface_mailbox.push(.{ .set_process_name = name })
    ↓
App thread receives message, dispatches to Surface.handleMessage()
    ↓
Surface.runtime_ctx.setProcessName(name)
    [no config reload needed — just runtime_ctx state update]
```

Process detection mechanism: The PTY file descriptor is available in `Exec`. `ioctl(pty_fd, TIOCGPGRP, &pgrp)` returns the foreground process group. Then `/proc/<pid>/comm` (Linux) or `proc_pidpath` (macOS via `libproc`) gives the process name. This is polled on the IO thread, not event-driven, so polling interval should be configurable (default 500ms).

### User variable update (runtime, from OSC 1337)

```
terminal program writes: ESC]1337;SetUserVar=key=base64(value)BEL
    ↓
terminal/osc/parsers/iterm2.zig handles SetUserVar case (currently unimplemented)
    ↓
stream_handler dispatches to surface_mailbox.push(.{ .set_user_var = ... })
    ↓
App thread routes to Surface.handleMessage()
    ↓
Surface.runtime_ctx.setUserVar(key, value)
```

---

## Build Order

Build these components in dependency order. Each step is independently testable.

### Step 1: Config syntax and parsing

**Files:** `src/input/ConditionSet.zig` (new), `src/config/Config.zig`

Parse `when:process=vim:ctrl+w=close_surface` in `Keybinds.parseCLI`. Store into `conditional_bindings`. Add `clone`, `equal`, `formatEntry` methods to `ConditionSet` to satisfy the `Config` interface. Write unit tests covering parse success and error cases.

### Step 2: Runtime context and evaluation

**Files:** `src/Surface.zig` (add `runtime_ctx` field), `src/input/condition_eval.zig` (new)

Add `RuntimeContext` to `Surface`. Implement `condition_eval.matches`. Wire evaluation into `maybeHandleBinding`. Write unit tests for `matches` with each condition type.

### Step 3: Conditional binding lookup

**Files:** `src/Surface.zig`

Modify `maybeHandleBinding` to scan `config.keybind.conditional_bindings`. The conditional check sits between the table stack and the root set (step 3 in the priority list above). Add integration test: configure `when:process=vim:ctrl+w=close_surface`, set `runtime_ctx.process_name = "vim"`, assert key event routes to `close_surface`.

### Step 4: OSC 1337 SetUserVar

**Files:** `src/terminal/osc/parsers/iterm2.zig`, `src/termio/stream_handler.zig`, `src/apprt/surface.zig`

Implement `SetUserVar` in the iTerm2 OSC parser. Add `set_user_var` surface message. Handle it in `Surface.handleMessage()` to call `runtime_ctx.setUserVar`. Write tests for the full OSC 1337 SetUserVar parse-to-surface pipeline.

### Step 5: Process name detection

**Files:** `src/termio/Exec.zig`, `src/os/process.zig` (new), `src/apprt/surface.zig`

Add `set_process_name` surface message. Implement `os/process.zig` with platform-specific foreground process name lookup:
- Linux: `ioctl(fd, TIOCGPGRP, &pgrp)` + read `/proc/<pgrp>/comm`
- macOS: `ioctl(fd, TIOCGPGRP, &pgrp)` + `proc_pidpath` from `libproc`

Poll from the IO thread on a timer (xev timer, 500ms default). When the name changes, push `set_process_name` message to surface. Wire into `Surface.handleMessage()`.

### Step 6: Window title matching

**Files:** `src/Surface.zig`

`window_title` is already tracked in `Surface` via the `set_title` surface message. Sync it into `runtime_ctx.window_title` when `set_title` is handled. No new infrastructure needed.

### Step 7: Config documentation and man page

**Files:** `src/config/Config.zig` doc comment on `keybind` field

Document the `when:` prefix syntax in the keybind documentation comment (which generates the man page). This is the last step because the full syntax is only stable after all condition types are implemented.

---

## Integration Points

### `src/config/Config.zig`

- `Keybinds.parseCLI` — detect and route `when:` prefix bindings
- `Keybinds.clone` — must clone `ConditionSet`
- `Keybinds.equal` — must compare `ConditionSet`
- `Keybinds.formatEntry` — must serialize conditional bindings back to config syntax

### `src/input/Binding.zig`

- `Flags` — no changes, conditional bindings reuse existing flags
- `Set.parseAndPut` — no changes; conditional bindings bypass this entirely

### `src/Surface.zig`

- Add `runtime_ctx: RuntimeContext` field (after `config`)
- `maybeHandleBinding` — add conditional scan between table stack and root set
- `keyEventIsBinding` — mirror the conditional scan for pre-check callers
- `handleMessage` — handle `set_process_name` and `set_user_var` messages
- `deinit` — call `runtime_ctx.deinit()`

### `src/apprt/surface.zig`

- `Message` union — add `set_process_name` and `set_user_var` variants

### `src/termio/Exec.zig`

- IO thread timer loop — add process polling (uses xev timer already available)

### `src/termio/stream_handler.zig`

- OSC 1337 SetUserVar case — implement instead of logging "unimplemented"

### `src/terminal/osc/parsers/iterm2.zig`

- `SetUserVar` in the unimplemented list — parse key=base64(value) and emit a proper `Command` variant

### `src/terminal/osc.zig` (the `Command` union)

- Add `set_user_var: struct { key: []u8, value: []u8 }` variant so the OSC pipeline can carry it from parser to stream_handler

### `src/pty.zig`

- May need `pub fn foregroundProcessGroup(self: Pty) !std.posix.pid_t` helper using `ioctl(TIOCGPGRP)`

---

## Key Constraints Noted During Research

**Thread safety:** Surface key handling and message handling both run on the main/UI thread. `RuntimeContext` is not shared across threads. Process name updates arrive via the surface mailbox (App thread → main thread dispatch), which is already how `set_title`, `pwd_change`, etc. work. No new locking needed.

**Performance:** The conditional binding scan is O(n) per keypress over all conditional bindings that could match a trigger. For typical configs (fewer than 50 conditional bindings) this is sub-microsecond. Process polling at 500ms adds no keypress latency.

**Backward compatibility:** `when:` is a new prefix. Existing bindings without it are unaffected. The `when:` parser can check for this prefix before handing off to the existing flag parser, so unknown prefixes continue to fall through as documented in `parseFlags`.

**OSC 1337 SetUserVar encoding:** iTerm2 uses base64-encoded values. The existing parser infrastructure handles the key=value split; the implementation needs base64 decoding of the value part. `std.base64` is available in the standard library.

**Pattern matching library:** `oniguruma` is already imported in `Surface.zig`. Glob matching with `*` and `?` can be handled by `std.fs.path.match` without adding a new dependency. Regex matching (if desired) can use the existing `oniguruma` binding.

---

*Architecture analysis: 2026-03-18*
