# Phase 2: Evaluation Engine - Context

**Gathered:** 2026-03-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire RuntimeContext into Surface and implement condition evaluation on the keypress path. When RuntimeContext.process_name matches a conditional binding's condition, that binding fires instead of the unconditional fallback. No process detection (Phase 3) or UserVar/title population (Phase 4/5) — this phase only builds the evaluation engine and RuntimeContext struct.

</domain>

<decisions>
## Implementation Decisions

### Key table interaction
- Conditional bindings evaluated only in the root keybind set
- Key tables and sequences continue using `getEvent()` — no conditional support
- When a key table is active, skip conditional evaluation entirely; table takes full priority
- Replace the root set's `getEvent` call entirely with `getEventConditional` (single code path)
- `last_trigger` tracking unchanged — tracks physical trigger hash regardless of which condition matched

### Empty context fallback
- When RuntimeContext fields are null, all conditional bindings silently don't match
- Unconditional bindings fire as before — zero surprises, zero noise
- No logging on context miss; debugging is the user's responsibility
- All RuntimeContext fields start as null optionals — no "ready" flag needed

### RuntimeContext placement
- RuntimeContext struct defined in `src/input/Binding.zig` (co-located with Condition and getConditional)
- Direct field on Surface: `runtime_context: input.Binding.RuntimeContext`
- All fields defined upfront (process_name, title, user_vars) — all null until populated by later phases
- Field types: `?[]const u8` for process_name and title; memory owned by whoever populates them

### Evaluation API
- `getConditional` / `getEventConditional` API changed to accept `?*const RuntimeContext` instead of `?Condition`
- RuntimeContext provides `matchesCondition(Condition) -> bool` method that encapsulates matching logic
- Clean extension point for title/var matching in later phases

### Claude's Discretion
- Exact matchesCondition implementation details
- user_vars field type (StringHashMap or similar)
- Test organization and helper structure
- Whether to add a `hasConditionalBindings() -> bool` fast-path optimization

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Binding.Set.getEventConditional()` (Binding.zig:2883): Already implements trigger-variant fallback with conditional priority — needs API signature change from `?Condition` to `?*const RuntimeContext`
- `Binding.Set.getConditional()` (Binding.zig:2845): Core conditional lookup — needs same signature change
- `Condition` tagged union (Binding.zig): Already supports `.process`, `.title`, `.var_` variants
- `Condition.eql()`: Existing exact-match comparison — will be replaced by `RuntimeContext.matchesCondition()`

### Established Patterns
- Mailbox/message pattern (App.zig, Surface.zig): Thread-safe messaging via BlockingQueue — Phase 3 will use this for async context updates
- Scoped logging: `const log = std.log.scoped(.input)` — follow existing pattern
- Optional slice pattern: `?[]const u8` used throughout for nullable strings
- Self-referential struct: `const RuntimeContext = @This()` pattern

### Integration Points
- `Surface.maybeHandleBinding()` (Surface.zig:2799): Main integration point — root set lookup (line 2875) changes from `getEvent` to `getEventConditional`
- `Surface.init()`: Initialize `runtime_context` field with all-null defaults
- `Surface.config.keybind.set`: The root binding set where conditional evaluation occurs
- Key table stack (Surface.zig:2854): Untouched — continues using `getEvent()`
- Sequence set (Surface.zig:2827): Untouched — continues using `getEvent()`

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-evaluation-engine*
*Context gathered: 2026-03-18*
