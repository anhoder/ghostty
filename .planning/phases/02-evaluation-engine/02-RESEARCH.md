# Phase 2: Evaluation Engine - Research

**Researched:** 2026-03-18
**Domain:** Zig struct design, Surface.zig integration, keypress hot path
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- Conditional bindings evaluated only in the root keybind set
- Key tables and sequences continue using `getEvent()` — no conditional support
- When a key table is active, skip conditional evaluation entirely; table takes full priority
- Replace the root set's `getEvent` call entirely with `getEventConditional` (single code path)
- `last_trigger` tracking unchanged — tracks physical trigger hash regardless of which condition matched
- When RuntimeContext fields are null, all conditional bindings silently don't match
- Unconditional bindings fire as before — zero surprises, zero noise
- No logging on context miss; debugging is the user's responsibility
- All RuntimeContext fields start as null optionals — no "ready" flag needed
- RuntimeContext struct defined in `src/input/Binding.zig` (co-located with Condition and getConditional)
- Direct field on Surface: `runtime_context: input.Binding.RuntimeContext`
- All fields defined upfront (process_name, title, user_vars) — all null until populated by later phases
- Field types: `?[]const u8` for process_name and title; memory owned by whoever populates them
- `getConditional` / `getEventConditional` API changed to accept `?*const RuntimeContext` instead of `?Condition`
- RuntimeContext provides `matchesCondition(Condition) -> bool` method that encapsulates matching logic

### Claude's Discretion

- Exact matchesCondition implementation details
- user_vars field type (StringHashMap or similar)
- Test organization and helper structure
- Whether to add a `hasConditionalBindings() -> bool` fast-path optimization

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PROC-01 | User can configure keybinds that match on exact foreground process name | RuntimeContext.process_name field + matchesCondition(.process) enables exact string match at keypress time |
| PROC-05 | Process detection on keypress path introduces no perceptible latency | RuntimeContext holds cached `?[]const u8` — evaluation is a single `std.mem.eql` call, zero syscalls |
</phase_requirements>

## Summary

Phase 2 wires the already-built `getEventConditional` API into the live keypress path. The core work is three things: define `RuntimeContext` in `Binding.zig`, add it as a field on `Surface`, and swap the single root-set lookup at `Surface.zig:2875` from `getEvent` to `getEventConditional`.

The existing `getConditional` / `getEventConditional` functions already accept `?Condition` — this phase changes that signature to `?*const RuntimeContext` and moves the condition-matching logic into `RuntimeContext.matchesCondition()`. This is a pure refactor of the call site; the lookup algorithm is unchanged.

The hot-path performance constraint (PROC-05) is already satisfied by design: `RuntimeContext` holds pre-cached `?[]const u8` values. Evaluation at keypress time is a single `std.mem.eql` string comparison — no syscalls, no allocations.

**Primary recommendation:** Define RuntimeContext in Binding.zig, add it to Surface, change the two function signatures, implement matchesCondition, update the one call site in maybeHandleBinding. Everything else is tests.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `std.mem.eql` | stdlib | Exact string comparison for process/title match | Zero-allocation, O(n) on string length, already used throughout Binding.zig |
| `std.StringHashMapUnmanaged` | stdlib | user_vars storage (Claude's discretion) | Consistent with Ghostty's preference for Unmanaged containers; caller controls allocator lifetime |

### Supporting

None — this phase adds no new dependencies.

**Installation:** No new packages.

## Architecture Patterns

### Recommended Project Structure

No new files required. All changes land in existing files:

```
src/
├── input/Binding.zig       # Add RuntimeContext struct + matchesCondition; change getConditional/getEventConditional signatures
└── Surface.zig             # Add runtime_context field; update maybeHandleBinding root-set lookup
```

The STATE.md mentions `src/input/condition_eval.zig` as a possible new file, but the CONTEXT.md locks RuntimeContext into `Binding.zig`. No separate file is needed — the struct is small and co-location with `Condition` is the right call.

### Pattern 1: RuntimeContext struct definition

**What:** Plain Zig struct with optional slice fields, all null by default. Lives in Binding.zig alongside `Condition`.
**When to use:** Defined once, referenced by Surface and by getConditional callers.

```zig
// src/input/Binding.zig — add after Condition definition
pub const RuntimeContext = struct {
    /// Name of the foreground process. Null until Phase 3 populates it.
    /// Memory owned by whoever sets it (Surface holds the slice).
    process_name: ?[]const u8 = null,

    /// Terminal window title. Null until Phase 5 populates it.
    title: ?[]const u8 = null,

    /// User variables set via OSC 1337. Null until Phase 4 populates it.
    /// Use StringHashMapUnmanaged; Surface owns the allocator.
    user_vars: ?std.StringHashMapUnmanaged([]const u8) = null,

    /// Returns true if this context satisfies the given Condition.
    /// Called once per keypress when a conditional binding exists.
    pub fn matchesCondition(self: *const RuntimeContext, cond: Condition) bool {
        return switch (cond) {
            .process => |name| if (self.process_name) |pn|
                std.mem.eql(u8, pn, name)
            else
                false,
            .title => |t| if (self.title) |ti|
                std.mem.eql(u8, ti, t)
            else
                false,
            .var_ => |v| if (self.user_vars) |uv|
                if (uv.get(v.name)) |val| std.mem.eql(u8, val, v.value) else false
            else
                false,
        };
    }
};
```

### Pattern 2: Signature change for getConditional / getEventConditional

**What:** Replace `condition: ?Condition` parameter with `ctx: ?*const RuntimeContext`. The body calls `ctx.matchesCondition(entry.condition)` instead of `entry.condition.eql(cond)`.
**When to use:** Both functions get the same change.

```zig
// Before (Phase 1):
pub fn getConditional(self: *const Set, t: Trigger, condition: ?Condition) ?ConditionalResult

// After (Phase 2):
pub fn getConditional(self: *const Set, t: Trigger, ctx: ?*const RuntimeContext) ?ConditionalResult
```

Inner loop change — replace:
```zig
if (entry.trigger.bindingSetEqual(t) and entry.condition.eql(cond)) {
```
with:
```zig
if (entry.trigger.bindingSetEqual(t) and
    ctx != null and ctx.?.matchesCondition(entry.condition)) {
```

### Pattern 3: Surface field and init

**What:** Add `runtime_context` as a direct field on Surface. Zero-init is correct because all fields default to null.

```zig
// Surface.zig — add to struct fields (near keyboard: Keyboard)
runtime_context: input.Binding.RuntimeContext = .{},
```

No change to `Surface.init` is needed — the default value handles initialization.

### Pattern 4: maybeHandleBinding call site swap

**What:** The single root-set lookup at line 2875 changes from `getEvent` to `getEventConditional`. The result type changes from `Set.Entry` to `Set.ConditionalResult`, so the downstream leaf extraction also needs updating.

```zig
// Surface.zig:2875 — before:
break :entry self.config.keybind.set.getEvent(event) orelse return null;

// After:
const cond_result = self.config.keybind.set.getEventConditional(
    event,
    &self.runtime_context,
) orelse return null;
// ConditionalResult carries action + flags directly; synthesize an Entry-compatible value
// or restructure the entry: block to work with ConditionalResult directly.
```

The `entry: { ... }` block currently produces a `Set.Entry` (a pointer into the HashMap). `ConditionalResult` is a value type with `action`, `flags`, `condition`. The downstream code at line 2880 switches on `entry.value_ptr.*` — this needs to be adapted to use `ConditionalResult` directly for the root-set path. The cleanest approach: keep the `entry:` block returning `Set.Entry` for sequence/table paths, and handle the root-set path as a separate branch that goes directly to leaf processing using `ConditionalResult`.

### Anti-Patterns to Avoid

- **Passing `Condition` directly to getConditional:** The whole point of this phase is to replace `?Condition` with `?*const RuntimeContext`. Don't keep the old signature as an overload.
- **Allocating in matchesCondition:** The method must be allocation-free. All string data is pre-owned.
- **Adding a "ready" flag to RuntimeContext:** Decided against — null fields are the sentinel. A ready flag adds complexity with no benefit.
- **Logging on context miss:** Decided against — no log on null process_name. Silent fallback to unconditional.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| String equality | Custom byte loop | `std.mem.eql(u8, a, b)` | Already used in Condition.eql; correct, inlined by compiler |
| Key-value store for user_vars | Custom linked list | `std.StringHashMapUnmanaged` | Ghostty already uses Unmanaged variants; O(1) lookup |

**Key insight:** The evaluation logic is trivially simple — a switch + mem.eql. The complexity in this phase is entirely in the plumbing: getting the right type through the call chain without breaking the existing Entry-based path for sequences and tables.

## Common Pitfalls

### Pitfall 1: Entry vs ConditionalResult type mismatch

**What goes wrong:** `getEvent` returns `?Set.Entry` (a pointer into the HashMap). `getEventConditional` returns `?ConditionalResult` (a value type). The `entry:` block in `maybeHandleBinding` is typed to produce `Set.Entry`. Naively swapping the call produces a type error.

**Why it happens:** The downstream code at line 2880 does `switch (entry.value_ptr.*)` which only works on `Set.Entry`. `ConditionalResult` has a flat `action`/`flags` structure.

**How to avoid:** Restructure the root-set branch to break out of `entry:` with a synthetic leaf directly, bypassing the switch. Or: change the `entry:` block to produce a union of `Set.Entry | ConditionalResult` — but that's more complex. Simplest: handle root-set as an early-exit path before the `entry:` block.

**Warning signs:** Compiler error "expected type 'Set.Entry', found 'ConditionalResult'" at the break statement.

### Pitfall 2: Sequence/table paths accidentally getting conditional evaluation

**What goes wrong:** Applying `getEventConditional` to the sequence set or table stack lookups.

**Why it happens:** Copy-paste when updating the call sites.

**How to avoid:** Only the root-set lookup (the final `break :entry` at line 2875) changes. The sequence set (`set.getEvent(event)`) and table stack (`table.set.getEvent(event)`) are explicitly left unchanged per the locked decisions.

### Pitfall 3: RuntimeContext pointer lifetime

**What goes wrong:** Passing `&self.runtime_context` where `self` is a stack copy, or the pointer outlives the Surface.

**Why it happens:** Zig's ownership model requires care with pointer-to-field.

**How to avoid:** `self` in `maybeHandleBinding` is `*Surface` — taking `&self.runtime_context` is safe for the duration of the call. The pointer is never stored; it's consumed within `getEventConditional`.

### Pitfall 4: Forgetting to update ConditionalResult in getConditional body

**What goes wrong:** The inner loop still calls `entry.condition.eql(cond)` after the signature change, causing a compile error or logic bug.

**Why it happens:** Signature change without updating the body.

**How to avoid:** The body must change `entry.condition.eql(cond)` → `ctx.?.matchesCondition(entry.condition)`, and the null guard on `condition` → null guard on `ctx`.

## Code Examples

### matchesCondition — full implementation

```zig
// Source: derived from Condition.eql pattern in Binding.zig:52
pub fn matchesCondition(self: *const RuntimeContext, cond: Condition) bool {
    return switch (cond) {
        .process => |name| if (self.process_name) |pn|
            std.mem.eql(u8, pn, name)
        else
            false,
        .title => |t| if (self.title) |ti|
            std.mem.eql(u8, ti, t)
        else
            false,
        .var_ => |v| if (self.user_vars) |uv|
            if (uv.get(v.name)) |val| std.mem.eql(u8, val, v.value) else false
        else
            false,
    };
}
```

### Updated getConditional body (key diff)

```zig
// Source: Binding.zig:2845 — updated for Phase 2
pub fn getConditional(self: *const Set, t: Trigger, ctx: ?*const RuntimeContext) ?ConditionalResult {
    if (ctx) |c| {
        for (self.conditional_bindings.items) |entry| {
            if (entry.trigger.bindingSetEqual(t) and c.matchesCondition(entry.condition)) {
                return .{
                    .action = entry.action,
                    .flags = entry.flags,
                    .condition = entry.condition,
                };
            }
        }
    }
    // Fallback: unconditional
    const map_entry = self.bindings.getEntry(t) orelse return null;
    return switch (map_entry.value_ptr.*) {
        .leaf => |leaf| .{ .action = leaf.action, .flags = leaf.flags, .condition = null },
        .leader, .leaf_chained => null,
    };
}
```

### maybeHandleBinding root-set path (key diff)

```zig
// Surface.zig — replace line 2875 block
// Root set: use conditional evaluation
const cond_result = self.config.keybind.set.getEventConditional(
    event,
    &self.runtime_context,
) orelse return null;
// cond_result is ConditionalResult — use directly as leaf
const leaf: input.Binding.Set.GenericLeaf = .{
    .action = cond_result.action,
    .flags = cond_result.flags,
};
// ... rest of leaf processing unchanged
```

### Test scaffold for RuntimeContext.matchesCondition

```zig
test "RuntimeContext: matchesCondition process hit" {
    const ctx: Binding.RuntimeContext = .{ .process_name = "vim" };
    try std.testing.expect(ctx.matchesCondition(.{ .process = "vim" }));
}

test "RuntimeContext: matchesCondition process miss" {
    const ctx: Binding.RuntimeContext = .{ .process_name = "nvim" };
    try std.testing.expect(!ctx.matchesCondition(.{ .process = "vim" }));
}

test "RuntimeContext: matchesCondition null process_name" {
    const ctx: Binding.RuntimeContext = .{};
    try std.testing.expect(!ctx.matchesCondition(.{ .process = "vim" }));
}

test "RuntimeContext: matchesCondition empty context all false" {
    const ctx: Binding.RuntimeContext = .{};
    try std.testing.expect(!ctx.matchesCondition(.{ .process = "vim" }));
    try std.testing.expect(!ctx.matchesCondition(.{ .title = "foo" }));
    try std.testing.expect(!ctx.matchesCondition(.{ .var_ = .{ .name = "k", .value = "v" } }));
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `getEvent` for all root-set lookups | `getEventConditional` with RuntimeContext | Phase 2 | Conditional bindings now fire on keypress |
| `?Condition` passed directly to getConditional | `?*const RuntimeContext` with matchesCondition | Phase 2 | Clean extension point for title/var in later phases |

## Open Questions

1. **GenericLeaf synthesis from ConditionalResult**
   - What we know: `ConditionalResult` has `action: Action`, `flags: Flags`, `condition: ?Condition`. `GenericLeaf` has `action: Action`, `flags: Flags`, plus `actionsSlice()`.
   - What's unclear: Whether `GenericLeaf` can be directly constructed from action+flags or requires going through a `Leaf`.
   - Recommendation: Check `GenericLeaf` definition in Binding.zig before writing the Surface integration. If it can't be directly constructed, the planner should add a task to read that struct first.

2. **hasConditionalBindings() fast-path**
   - What we know: Claude's discretion. If `conditional_bindings.items.len == 0`, calling `getEventConditional` is equivalent to `getEvent` with a tiny overhead.
   - What's unclear: Whether the overhead is measurable in practice.
   - Recommendation: Skip for now. Add only if profiling shows need. The linear scan over an empty slice is a single bounds check.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Zig built-in test runner |
| Config file | none — `zig build test` or `zig test src/input/Binding.zig` |
| Quick run command | `zig test src/input/Binding.zig` |
| Full suite command | `zig build test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PROC-01 | process_name="vim" matches [process=vim] binding | unit | `zig test src/input/Binding.zig` | ❌ Wave 0 |
| PROC-01 | process_name="nvim" does not match [process=vim] | unit | `zig test src/input/Binding.zig` | ❌ Wave 0 |
| PROC-01 | null process_name never matches any conditional | unit | `zig test src/input/Binding.zig` | ❌ Wave 0 |
| PROC-01 | unconditional binding fires when no condition matches | unit | `zig test src/input/Binding.zig` | ❌ Wave 0 |
| PROC-05 | matchesCondition performs no allocation or syscall | unit (structural) | `zig test src/input/Binding.zig` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `zig test src/input/Binding.zig`
- **Per wave merge:** `zig build test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] Tests for `RuntimeContext.matchesCondition` — covers PROC-01 (match hit, miss, null context, priority ordering)
- [ ] Tests for updated `getConditional` signature with `?*const RuntimeContext` — covers PROC-01 integration
- [ ] Tests for `getEventConditional` with RuntimeContext — covers end-to-end keypress path

*(All tests live in `src/input/Binding.zig` alongside existing conditional tests at line 5113+)*

## Sources

### Primary (HIGH confidence)

- `src/input/Binding.zig` — Condition, getConditional, getEventConditional, ConditionalResult, existing test patterns (lines 2845–2916, 5113–5314)
- `src/Surface.zig` — maybeHandleBinding, Keyboard struct, Surface fields (lines 259–287, 2799–2985)
- `.planning/phases/02-evaluation-engine/02-CONTEXT.md` — all locked decisions

### Secondary (MEDIUM confidence)

- `.planning/STATE.md` — accumulated decisions, key file map, open questions

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; stdlib only
- Architecture: HIGH — call sites are identified by exact line numbers from source
- Pitfalls: HIGH — type mismatch pitfall verified by reading both ConditionalResult and Entry definitions

**Research date:** 2026-03-18
**Valid until:** 2026-04-17 (stable codebase, no external dependencies)
