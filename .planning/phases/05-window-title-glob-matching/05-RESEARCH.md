# Phase 5: Window Title & Glob Matching — Research

**Researched:** 2026-03-18
**Domain:** Zig codebase extension — title condition wiring + glob matching for process/title conditions
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TITL-01 | User can configure keybindings that match on window title (exact) | `Condition.title` variant and `RuntimeContext.title` field already defined; `set_title` message handler must update `runtime_context.title` |
| TITL-02 | User can use glob wildcards to match window title | `matchesGlob`/`globMatchImpl` already implemented; `matchesCondition(.title)` uses `std.mem.eql` only — must call `matchesGlob` instead |
| PROC-02 | User can use glob wildcards to match process name | `matchesCondition(.process)` uses `std.mem.eql` only — same fix: call `matchesGlob` instead |
</phase_requirements>

---

## Summary

Phase 5 adds window title conditional matching and glob wildcard support across all condition types. The overwhelming finding is that **most of the infrastructure is already in place** from earlier phases — the work in this phase is primarily wiring the existing pieces together and extending two match functions.

Specifically: `Condition.title`, `RuntimeContext.title`, and `parseCondition("[title=...]")` were all implemented in Phase 1. The `matchesGlob`/`globMatchImpl` functions were implemented in Phase 4 for `var_` conditions. What is missing is (a) the `runtime_context.title` update in `Surface.handleMessage` when a `set_title` message arrives, and (b) updating `matchesCondition` for `.title` and `.process` to call `matchesGlob` instead of `std.mem.eql`.

The glob compiler decision from the key decisions log — "Glob compiled at config-load time" — is already satisfied: the pattern string is stored in the condition at parse time, and `matchesGlob` only compiles nothing (it is a pure runtime backtracking matcher). This is consistent because there is no separate compile step needed for this simple `*`/`?` glob algorithm.

**Primary recommendation:** Phase 5 is a small, focused change: wire `runtime_context.title` into the `set_title` message handler in `Surface.zig`, then change two lines in `RuntimeContext.matchesCondition` to call `matchesGlob` instead of `std.mem.eql` for `.title` and `.process` cases. Add memory cleanup for `runtime_context.title` in `Surface.deinit`. Write tests.

---

## Standard Stack

### Core
| Library/Module | Version | Purpose | Why Standard |
|----------------|---------|---------|--------------|
| `src/input/Binding.zig` | in-repo | `Condition`, `RuntimeContext`, `matchesGlob` | Already contains all condition/glob infrastructure |
| `src/Surface.zig` | in-repo | `handleMessage`, `runtime_context`, `deinit` | App-thread message handler; owns runtime state |
| `src/apprt/surface.zig` | in-repo | `Message` union | Defines `set_title: [256]u8` message type |

### Supporting
| Library/Module | Version | Purpose | When to Use |
|----------------|---------|---------|-------------|
| `std.mem.eql` | Zig stdlib | Exact string comparison | Fast-path when no wildcards detected |
| `std.mem.indexOfAny` | Zig stdlib | Wildcard detection | Used in `matchesGlob` fast-path |

No new dependencies required. Everything needed is already in the codebase.

---

## Architecture Patterns

### Existing Data Flow (Already Working)

```
OSC 0/2 (window title escape sequence)
    → osc.zig parser → .change_window_title command
    → stream.zig oscDispatch
    → stream_handler.zig windowTitle()
    → surfaceMessageWriter(.{ .set_title = buf })
    → Surface.handleMessage(.set_title)
    → rt_app.performAction(.set_title, ...)    ← visual title update only
    (runtime_context.title NOT updated here)   ← Phase 5 gap
```

### Target Data Flow After Phase 5

```
OSC 0/2 (window title escape sequence)
    → ... (same pipeline) ...
    → Surface.handleMessage(.set_title)
    → rt_app.performAction(.set_title, ...)    ← visual title update (unchanged)
    → runtime_context.title updated            ← NEW: Phase 5 adds this

Next keypress:
    → getEventConditional(&self.runtime_context)
    → matchesCondition(.title)
    → matchesGlob(runtime_context.title, condition.title)  ← NEW glob call
```

### Pattern 1: Title Storage in RuntimeContext (mirrors process_name pattern)

The `process_name` case in `handleMessage` is the reference implementation:

```zig
// src/Surface.zig (existing process_name pattern)
.process_name_update => |update| {
    defer self.alloc.free(update.name);
    if (self.runtime_context.process_name) |old| {
        self.alloc.free(old);
    }
    self.runtime_context.process_name = try self.alloc.dupe(u8, update.name);
},
```

The title update follows the same pattern. The `set_title` message delivers a `[256]u8` array (null-terminated). The existing handler extracts the slice via `std.mem.sliceTo`. The Phase 5 addition stores a heap-allocated copy in `runtime_context.title` after performing the visual action.

**Key constraint:** The `set_title` handler already has a guard: `if (self.config.title != null) return;`. When a static title is configured, title-condition matching should still work (the config title IS the window title). Decide whether to: (a) skip runtime_context update when config.title is set (matching won't work for OSC-driven titles when config locks title), or (b) update runtime_context.title unconditionally from whatever title string is actually displayed. Option (b) is more useful but requires extracting the title string even when the handler returns early. **Recommended:** Store the config title in `runtime_context.title` at Surface init time, then update `runtime_context.title` in the `set_title` handler for OSC-driven changes. The guard `if (self.config.title != null) return` only prevents the visual `performAction` — do not return before updating `runtime_context.title`.

### Pattern 2: Glob Matching Extension

`matchesGlob` and `globMatchImpl` are already private functions on `RuntimeContext`. The current `matchesCondition` code:

```zig
// Current (exact match only):
.title => |t| if (self.title) |ti|
    std.mem.eql(u8, ti, t)
else
    false,

.process => |name| if (self.process_name) |pn|
    std.mem.eql(u8, pn, name)
else
    false,
```

Phase 5 change — call `matchesGlob` instead of `std.mem.eql`:

```zig
// After Phase 5:
.title => |t| if (self.title) |ti|
    matchesGlob(ti, t)
else
    false,

.process => |name| if (self.process_name) |pn|
    matchesGlob(pn, name)
else
    false,
```

`matchesGlob` already has the fast-path for exact match (no wildcards detected → falls through to `std.mem.eql`). No performance regression on common case.

### Pattern 3: Memory Management for runtime_context.title

Follows `process_name` model exactly:

- **Type:** `?[]const u8` (already declared in `RuntimeContext`)
- **Init:** null (already the default)
- **Update:** `alloc.free(old)` then `alloc.dupe(u8, new_title)`
- **Deinit:** `if (self.runtime_context.title) |t| self.alloc.free(t);` — add to `Surface.deinit` alongside `process_name` cleanup (which currently is NOT explicitly freed in `deinit` — verify this)

**Important:** Check `Surface.deinit` for `process_name` cleanup. Current `deinit` only shows `user_vars` cleanup. If `process_name` is not freed in `deinit`, add both `process_name` and `title` cleanup in the same pass for consistency.

### Pattern 4: Config-set Title Initialization

If `config.title` is set, the window starts with a known title. For title conditions to work at startup, set `runtime_context.title` during Surface init from `config.title` if present:

```zig
// In Surface.init, after config is read:
if (config.title) |t| {
    self.runtime_context.title = try alloc.dupeZ(u8, t);
}
```

This is optional but completes the feature: `[title=MyApp]` will match even when title is config-static.

### Anti-Patterns to Avoid

- **Don't store pointer into the `[256]u8` stack buffer:** The `set_title` message arrives as `*v` (pointer to the union's array field). The slice must be duped to heap before the message is consumed.
- **Don't compile glob patterns per-keypress:** Already avoided — `matchesGlob` is a pure runtime function, no pre-compilation step.
- **Don't forget the `deinit` cleanup:** `runtime_context.title` must be freed in `Surface.deinit` or it leaks on surface close.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Glob matching | Custom `*`/`?` matcher | `matchesGlob` (already in `RuntimeContext`) | Already implemented in Phase 4, tested, handles backtracking correctly |
| Title extraction | Re-parse window title | `std.mem.sliceTo` on existing `set_title` message | Already used in the existing handler; type-safe |
| String interning | Hash-based title dedup | Simple `dupe` + `free` | Volume is low (one title per surface, updated rarely) |

**Key insight:** The glob algorithm complexity is already solved. Phase 5 is wiring, not algorithm work.

---

## Common Pitfalls

### Pitfall 1: Forgetting the config.title Guard
**What goes wrong:** The `set_title` handler has `if (self.config.title != null) return;` which prevents visual title updates when a config title is set. If `runtime_context.title` update is placed after this guard, title matching won't work for surfaces with a config-set title.
**Why it happens:** The guard was written to protect only the visual action, not the runtime context.
**How to avoid:** Update `runtime_context.title` before the guard (or handle the config-title case separately). The config title string should seed `runtime_context.title` at init time.
**Warning signs:** `[title=MyApp]ctrl+s=write_scrollback_file` never fires even when the title is correct.

### Pitfall 2: Dangling Pointer into Message Buffer
**What goes wrong:** `set_title` arrives as `[256]u8` in the Message union. The handler currently uses `std.mem.sliceTo(@as([*:0]const u8, @ptrCast(v)), 0)` to get a slice into that buffer. If this slice is stored directly in `runtime_context.title` without duping, the pointer becomes invalid after the message is consumed.
**How to avoid:** Always `self.alloc.dupe(u8, slice)` before storing.

### Pitfall 3: Missing deinit Cleanup
**What goes wrong:** If `runtime_context.title` is not freed in `Surface.deinit`, every title update leaks memory. Not immediately visible but will accumulate.
**How to avoid:** Add `if (self.runtime_context.title) |t| self.alloc.free(t);` in `Surface.deinit`. Also verify if `runtime_context.process_name` is currently freed in `deinit` — if not, add it in the same pass.

### Pitfall 4: process match still using std.mem.eql (PROC-02 silently missing)
**What goes wrong:** Updating only `.title` in `matchesCondition` but forgetting `.process` means PROC-02 is never implemented. Both are one-liners but easy to miss.
**How to avoid:** The success criteria explicitly tests `[process=nvim*]` — write this test first.

### Pitfall 5: Empty Title Reset Behavior
**What goes wrong:** `stream_handler.zig windowTitle()` has special handling for empty title: it substitutes the pwd as the new title. This means `runtime_context.title` should reflect the effective title (pwd fallback), not the raw empty string.
**How to avoid:** The `runtime_context.title` update should happen after the empty-title logic resolves the effective title. In `Surface.handleMessage`, the `set_title` message already contains the resolved title (the stream_handler does the pwd substitution before sending the message). So no special handling is needed in Surface — just store whatever arrives in the message.

---

## Code Examples

### Title Update in handleMessage (Phase 5 addition)

```zig
// src/Surface.zig — extend existing .set_title handler
.set_title => |*v| {
    // Extract the effective title string from the null-terminated buffer
    const slice = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(v)), 0);

    // Update runtime_context.title for condition matching (do this BEFORE guard)
    if (self.runtime_context.title) |old| self.alloc.free(old);
    self.runtime_context.title = self.alloc.dupe(u8, slice) catch |err| blk: {
        log.warn("failed to dupe title for runtime_context: {}", .{err});
        break :blk null;
    };

    // Guard: ignore visual title change if static title is configured
    if (self.config.title != null) {
        log.debug("ignoring title change request since static title is set via config", .{});
        return;
    }

    log.debug("changing title \"{s}\"", .{slice});
    _ = try self.rt_app.performAction(
        .{ .surface = self },
        .set_title,
        .{ .title = slice },
    );
},
```

### Glob Extension in matchesCondition (two-line change)

```zig
// src/input/Binding.zig — RuntimeContext.matchesCondition
pub fn matchesCondition(self: *const RuntimeContext, cond: Condition) bool {
    return switch (cond) {
        .process => |name| if (self.process_name) |pn|
            matchesGlob(pn, name)   // was: std.mem.eql(u8, pn, name)
        else
            false,

        .title => |t| if (self.title) |ti|
            matchesGlob(ti, t)      // was: std.mem.eql(u8, ti, t)
        else
            false,

        .var_ => |v| if (self.user_vars) |vars|
            if (vars.get(v.name)) |val| matchesGlob(val, v.value) else false
        else
            false,
    };
}
```

### Deinit Cleanup (Surface.deinit addition)

```zig
// src/Surface.zig — Surface.deinit, alongside user_vars cleanup
if (self.runtime_context.title) |t| self.alloc.free(t);
if (self.runtime_context.process_name) |p| self.alloc.free(p);
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `std.mem.eql` for title/process conditions | `matchesGlob` with `*`/`?` support | Phase 5 | Enables flexible pattern matching without per-keypress compilation |
| `runtime_context.title` always null | Updated from `set_title` message | Phase 5 | Title conditions can now match |

---

## Open Questions

1. **Config-set title at init time**
   - What we know: `config.title` is read during Surface init; `runtime_context.title` starts as null
   - What's unclear: Should `runtime_context.title` be pre-populated from `config.title` at Surface init?
   - Recommendation: Yes — seed `runtime_context.title` from `config.title` during init so `[title=MyApp]` works even when the title never changes via OSC. This is a one-liner in the init block.

2. **process_name deinit gap**
   - What we know: `Surface.deinit` frees `user_vars` but does not explicitly free `process_name`
   - What's unclear: Whether `process_name` is owned by Surface (it is — duped in `process_name_update` handler)
   - Recommendation: Add `process_name` free in `deinit` alongside the new `title` free. This fixes a pre-existing leak and makes Phase 5 a net improvement.

3. **Title deduplication**
   - What we know: `process_name_update` in Phase 3 has "No deduplication in I/O thread" decision
   - What's unclear: Should title updates be deduplicated (skip if title unchanged)?
   - Recommendation: Not required for correctness. The overhead is minimal (one `dupe` + `free` on title change events, which are rare). Defer optimization if needed.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Zig built-in test runner |
| Config file | none (inline `test` blocks in .zig files) |
| Quick run command | `zig test src/input/Binding.zig -freference-trace` |
| Full surface test | `zig ast-check src/Surface.zig && zig ast-check src/input/Binding.zig` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TITL-01 | `[title=vim: main.zig]` exact match fires | unit | `zig test src/input/Binding.zig -freference-trace` | ✅ test block exists (line 5356) |
| TITL-02 | `[title=vim:*]` glob match fires for any matching title | unit | `zig test src/input/Binding.zig -freference-trace` | ❌ Wave 0: extend existing matchesCondition test |
| TITL-01 | runtime_context.title updated on set_title message | integration | `zig ast-check src/Surface.zig` + manual inspection | ❌ Wave 0: no automated test for message handler |
| PROC-02 | `[process=nvim*]` matches "nvim" and "nvim-qt" | unit | `zig test src/input/Binding.zig -freference-trace` | ❌ Wave 0: extend existing matchesCondition test |

### Sampling Rate
- **Per task commit:** `zig ast-check src/input/Binding.zig && zig ast-check src/Surface.zig`
- **Per wave merge:** `zig test src/input/Binding.zig -freference-trace`
- **Phase gate:** Both files ast-check clean + Binding.zig tests green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] Extend `test "RuntimeContext: matchesCondition"` in `src/input/Binding.zig` to cover:
  - `[title=vim: main.zig]` exact match (TITL-01)
  - `[title=vim:*]` glob match (TITL-02)
  - `[process=nvim*]` glob match (PROC-02)
- [ ] Add `test "RuntimeContext: matchesCondition title/process glob patterns"` block covering wildcard edge cases
- [ ] No new test files needed — all tests belong in existing `Binding.zig` test suite

---

## Sources

### Primary (HIGH confidence)

- Direct source read: `src/input/Binding.zig` — full content of `RuntimeContext`, `Condition`, `matchesGlob`, `matchesCondition`, `parseCondition`, existing tests
- Direct source read: `src/Surface.zig` — `handleMessage`, `set_title` handler, `process_name_update` handler, `set_user_var` handler, `deinit`
- Direct source read: `src/apprt/surface.zig` — `Message` union definition, `set_title: [256]u8`
- Direct source read: `src/termio/stream_handler.zig` — `windowTitle()` implementation and empty-title behavior

### Secondary (MEDIUM confidence)

- `.planning/STATE.md` — Key decisions log confirming "Glob compiled at config-load time" decision and existing implementation status
- `.planning/phases/04-osc-1337-uservar-conditions/04-RESEARCH.md` — Phase 4 glob implementation research

### Tertiary (LOW confidence)

- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all files read directly, no guessing
- Architecture: HIGH — exact handler patterns verified in source
- Pitfalls: HIGH — identified from reading actual handler code and existing tests
- Open questions: MEDIUM — implementation choices that are clear but require a decision

**Research date:** 2026-03-18
**Valid until:** Stable until Ghostty source structure changes (no external dependencies)
