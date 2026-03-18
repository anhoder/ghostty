# Phase 4: OSC 1337 & UserVar Conditions — Research

**Researched:** 2026-03-18
**Confidence:** HIGH
**Blockers:** None

## Phase Goal

Terminal programs can set named variables via OSC 1337 SetUserVar, and users can write keybindings that match on those variable values.

## Requirements

- **UVAR-01**: User can configure conditional keybindings based on user variable values
- **UVAR-02**: Terminal programs can set user variables via OSC 1337 SetUserVar
- **UVAR-03**: User variables stored and managed at Surface level
- **UVAR-04**: User variables support exact match and pattern match

## Existing Infrastructure (Already Implemented)

### Condition Type & Parser (Phase 1)
- `Binding.Condition.var_` variant with `VarCondition{name, value}` — already defined
- `parseCondition()` handles `[var=name:value]` syntax — already works
- Conditional binding storage in `Set.conditional_bindings` — fully operational

### RuntimeContext (Phase 2)
- `RuntimeContext.user_vars: ?std.StringHashMapUnmanaged([]const u8)` — field exists
- `matchesCondition(.var_)` does hashmap lookup — already implemented
- Only missing: code to populate `user_vars` from OSC 1337

### Surface Integration (Phase 2-3)
- `Surface.runtime_context` field exists
- `maybeHandleBinding` / `keyEventIsBinding` use `getEventConditional` with `&self.runtime_context`
- Message mailbox pattern proven with `process_name_update`

## What Needs To Be Built

### 1. OSC 1337 SetUserVar Parser (iterm2.zig)

**Current state:** `SetUserVar` key exists in the enum but falls through to unimplemented block returning null.

**Wire format:** `ESC ] 1337 ; SetUserVar=<name>=<base64-value> BEL/ST`

**Implementation:**
- Move `.SetUserVar` out of unimplemented catch-all
- Split `value_` on `=` to get variable name and base64-encoded value
- Set `parser.command = .{ .set_user_var = .{ .name = name_slice, .data = base64_slice } }`

**File:** `src/terminal/osc/parsers/iterm2.zig` — modify the `.SetUserVar` case (currently at lines ~187-195)

### 2. OSC Command Variant (osc.zig)

**Add to `Command` union:**
```zig
set_user_var: struct {
    name: [:0]const u8,   // variable name
    data: [:0]const u8,   // base64-encoded value
},
```

**Constraint:** Command union has compile-time size check (max 64 bytes). Two slices = 32 bytes — fits.

**File:** `src/terminal/osc.zig` — add variant near line ~161

### 3. Stream Dispatch (stream.zig)

**Add to `oscDispatch`:**
```zig
.set_user_var => |v| {
    self.handler.vt(.set_user_var, .{ .name = v.name, .data = v.data });
},
```

**Also add `set_user_var` action to the handler Action union.**

**File:** `src/terminal/stream.zig`

### 4. Stream Handler (stream_handler.zig)

**Add `setUserVar` function:**
- Receive name and base64-encoded data
- Base64-decode the value
- Send via surface mailbox as `set_user_var` message

**Pattern:** Follow `reportPwd` / `process_name_update` mailbox pattern.

**File:** `src/termio/stream_handler.zig`

### 5. Surface Message (apprt/surface.zig)

**Add message variant for `set_user_var`.** Options:
- Fixed-size struct like `desktop_notification` pattern (name + value as fixed arrays)
- Two WriteReq fields

Recommended: Single struct with fixed-size null-terminated arrays:
```zig
set_user_var: struct {
    name: [63:0]u8,    // variable name
    value: [191:0]u8,  // decoded value
},
```

**File:** `src/apprt/surface.zig`

### 6. Surface Handler (Surface.zig)

**Handle `set_user_var` message:**
1. Initialize `runtime_context.user_vars` hashmap if null
2. Free old value if key exists (explicit memory management)
3. Heap-dupe name and value with `self.alloc`
4. Insert into hashmap
5. Clean up hashmap in `deinit`

**File:** `src/Surface.zig`

## Data Flow

```
PTY output:  ESC ] 1337 ; SetUserVar=FOO=<base64> BEL
                    ↓
   osc.zig Parser → state=.@"1337" → iterm2.parse()
                    ↓
   iterm2.zig: key="SetUserVar", value_="FOO=<b64>"
   → command = .{ .set_user_var = {name="FOO", data="<b64>"} }
                    ↓
   stream.zig oscDispatch()
   .set_user_var → handler.vt(.set_user_var, ...)
                    ↓
   stream_handler.zig vtFallible()
   → base64-decode → surfaceMessageWriter(.set_user_var)
                    ↓
   Surface mailbox → Surface.handleMessage()
   .set_user_var → update runtime_context.user_vars
                    ↓
   Next keypress: matchesCondition(.var_) → hashmap lookup
```

## Memory Management Strategy

- **Allocator:** Use `Surface.alloc` (GPA) for all user_var storage
- **HashMap init:** Lazy — only init on first `set_user_var` message
- **Key replacement:** Free old value before inserting new one
- **Cleanup:** In Surface.deinit, iterate and free all keys/values, then deinit the hashmap
- **No leaks:** Each `put` that replaces must `alloc.free()` the old value

## Base64 Decoding

- iTerm2 spec encodes values as base64
- Zig stdlib: `std.base64.standard.Decoder` or `std.base64.standard.decode()`
- Decode in stream_handler before sending to Surface (Surface receives plain text values)
- Invalid base64 → log warning, skip the SetUserVar

## Glob Pattern Matching (UVAR-04)

The current `matchesCondition(.var_)` uses `std.mem.eql` for exact match only. Phase 5 adds glob support for all condition types. However, UVAR-04 requires glob for user vars.

**Options:**
1. Add glob matching in this phase for `var_` only
2. Use existing `std.fs.path.match` or implement simple glob
3. Defer glob to Phase 5 and note it as a gap

**Recommendation:** Implement glob matching for `var_` in this phase since it's required by UVAR-04. Use a simple approach — check if the condition value contains `*` or `?`, and if so, use glob matching; otherwise use exact match. This keeps the common case (exact match) fast.

## Validation Architecture

### Test Strategy
1. **Unit tests in iterm2.zig:** Parse SetUserVar OSC correctly, handle malformed input
2. **Unit tests in Binding.zig:** matchesCondition with var_ conditions (already exists, extend for glob)
3. **Integration pattern:** SetUserVar OSC → RuntimeContext populated → condition matches
4. **Memory leak tests:** Set var, replace var, verify no leaks via GPA

### Key Scenarios
- Set a user var via OSC 1337 → verify RuntimeContext updated
- Keybinding with `[var=name:value]` → fires when var matches
- Keybinding with `[var=name:value]` → falls through when var doesn't match
- Replace user var → old value freed, new value matches
- Glob pattern `[var=mode:insert*]` → matches "insert" and "insert-visual"
- Invalid base64 in OSC → graceful skip, no crash

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Base64 decode failure | LOW | Log warning, skip invalid SetUserVar |
| HashMap memory leaks | MEDIUM | Explicit free on replacement and deinit; test with GPA |
| Command union size overflow | LOW | Two slices = 32 bytes, well under 64-byte limit |
| Glob performance on hot path | LOW | Only glob when pattern contains wildcards |

## RESEARCH COMPLETE
