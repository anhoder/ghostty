# Phase 1: Config Syntax & Parsing - Research

**Researched:** 2026-03-18
**Domain:** Zig parser extension, keybind configuration syntax
**Confidence:** HIGH

## Summary

Phase 1 extends Ghostty's existing keybind parser (`Binding.zig`) to support conditional syntax `[condition=value]` prefixed before triggers. The parser already has a robust prefix-parsing pattern (for `all:`, `global:`, etc.) that can be extended with bracket-delimited conditions. The codebase uses Zig 0.15.2 with tagged unions for type-safe parsing, comprehensive test coverage via `parseSingle()` helper, and a recursive `parseAndPutRecurse()` for storing bindings in nested Sets.

**Primary recommendation:** Insert condition parsing before `parseFlags()` in `Parser.init()`, store parsed conditions in a new `Condition` tagged union, and extend `Binding` struct with optional `condition: ?Condition` field. Reuse existing error types and test patterns.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **条件字段语法**: 条件类型和值之间用等号分隔：`[process=vim]`
- **UserVar 条件语法**: 变量名和值用冒号分隔：`[var=in_vim:1]`
- **条件位置**: 条件在 flags 前面：`[process=vim]global:ctrl+w=close_surface`
- **错误处理**: 畸形条件复用 `InvalidFormat`，未知条件类型严格报错
- **v1 单条件限制**: 多条件并列（`[process=vim][title=foo]`）报错
- **解析范围**: Phase 1 识别全部三种条件类型（`process`、`title`、`var`），但只存储精确匹配值

### Claude's Discretion
- Condition 解析在 `parseFlags` 之前还是独立函数中提取
- ConditionSet 的具体内部数据结构（hashmap 策略等）
- 测试用例的具体组织方式

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CONF-01 | 条件性快捷键使用 Ghostty 风格的配置语法 | Bracket syntax `[condition=value]` follows Ghostty's prefix pattern (like `all:`, `global:`) |
| CONF-02 | 条件性快捷键语法与现有 keybind 语法一致扩展 | Parser.init() already handles prefixes before trigger parsing; condition parsing inserts at same layer |
| CONF-03 | 后定义的条件性快捷键覆盖先定义的 | Set.parseAndPut() uses HashMap with last-write-wins semantics via put/remove operations |
| CONF-04 | 条件性快捷键优先于无条件快捷键 | Requires separate storage (ConditionSet) checked before unconditional Binding.Set during lookup |
| CONF-05 | 不破坏任何现有快捷键配置的向后兼容性 | Condition parsing only triggers on `[` prefix; all existing syntax passes through unchanged |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Zig | 0.15.2 | Language & stdlib | Project language; stdlib provides parsing primitives |
| std.mem | stdlib | String operations | `indexOf`, `eql` for delimiter/prefix matching |
| std.unicode | stdlib | UTF-8 validation | Already used in Trigger.parse() for unicode keys |
| std.hash | stdlib | Hashing | Wyhash for Trigger/Action hashing in HashMap |
| std.ArrayHashMapUnmanaged | stdlib | Storage | Existing pattern in Binding.Set for trigger→action mapping |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| std.testing | stdlib | Test assertions | All test blocks; `expectEqual`, `expectError` |
| std.ArrayList | stdlib | Dynamic arrays | If ConditionSet needs multiple conditions per trigger (v2) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Tagged union | Separate structs | Tagged union provides exhaustive switch safety, matches existing Action/Trigger.Key patterns |
| ArrayHashMapUnmanaged | HashMap | Unmanaged version avoids storing allocator, matches existing Set pattern |

**Installation:**
```bash
# No external dependencies — Zig stdlib only
zig build test  # Run existing test suite
```

## Architecture Patterns

### Recommended Project Structure
```
src/input/
├── Binding.zig          # Extend Parser.init(), add condition field
├── Condition.zig        # NEW: Condition tagged union definition
└── (ConditionSet.zig)   # DEFERRED to Phase 2 (runtime evaluation)
```

### Pattern 1: Prefix Parsing with State Machine
**What:** Loop through input, match known prefixes, advance index, break on unknown prefix
**When to use:** Parsing optional prefixes before main content (flags, conditions)
**Example:**
```zig
// Source: Binding.zig lines 148-187
fn parseFlags(raw_input: []const u8) Error!struct { Flags, usize } {
    var flags: Flags = .{};
    var start_idx: usize = 0;
    var input: []const u8 = raw_input;
    while (true) {
        const idx = std.mem.indexOf(u8, input, ":") orelse break;
        const prefix = input[0..idx];

        if (std.mem.eql(u8, prefix, "all")) {
            if (flags.all) return Error.InvalidFormat;
            flags.all = true;
        } else {
            break;  // Unknown prefix, let downstream handle
        }

        start_idx += idx + 1;
        input = input[idx + 1 ..];
    }
    return .{ flags, start_idx };
}
```

**Condition parsing follows same pattern:**
```zig
fn parseCondition(raw_input: []const u8) Error!struct { ?Condition, usize } {
    if (raw_input.len == 0 or raw_input[0] != '[') return .{ null, 0 };

    const close_idx = std.mem.indexOf(u8, raw_input, "]") orelse
        return Error.InvalidFormat;
    const content = raw_input[1..close_idx];

    const eq_idx = std.mem.indexOf(u8, content, "=") orelse
        return Error.InvalidFormat;
    const cond_type = content[0..eq_idx];
    const cond_value = content[eq_idx + 1 ..];

    if (cond_value.len == 0) return Error.InvalidFormat;

    const condition: Condition = if (std.mem.eql(u8, cond_type, "process"))
        .{ .process = cond_value }
    else if (std.mem.eql(u8, cond_type, "title"))
        .{ .title = cond_value }
    else if (std.mem.eql(u8, cond_type, "var"))
        parseVarCondition(cond_value)?
    else
        return Error.InvalidFormat;  // Unknown condition type

    return .{ condition, close_idx + 1 };
}
```

### Pattern 2: Tagged Union for Type Safety
**What:** Use `union(enum)` for mutually exclusive types with exhaustive switch checking
**When to use:** Representing alternatives (process OR title OR var), not combinations
**Example:**
```zig
// Source: Binding.zig lines 1631-1646 (Trigger.Key)
pub const Key = union(C.Tag) {
    physical: key.Key,
    unicode: u21,
    catch_all,
};

// Condition follows same pattern:
pub const Condition = union(enum) {
    process: []const u8,
    title: []const u8,
    var_: VarCondition,

    pub const VarCondition = struct {
        name: []const u8,
        value: []const u8,
    };
};
```

### Pattern 3: Test-Driven with parseSingle() Helper
**What:** `parseSingle()` wraps `Parser.init()` + `next()` for single-binding tests
**When to use:** All parser tests; validates format without Set storage complexity
**Example:**
```zig
// Source: Binding.zig lines 248-259
fn parseSingle(raw_input: []const u8) !Binding {
    var p = try Parser.init(raw_input);
    const elem = (try p.next()) orelse return Error.InvalidFormat;
    return switch (elem) {
        .leader => error.UnexpectedSequence,
        .binding => elem.binding,
        .chain => error.UnexpectedChain,
    };
}

// Test pattern:
test "parse: conditional process" {
    const b = try parseSingle("[process=vim]ctrl+w=close_surface");
    try testing.expectEqual(.process, std.meta.activeTag(b.condition.?));
    try testing.expectEqualStrings("vim", b.condition.?.process);
}
```

### Anti-Patterns to Avoid
- **Allocating during parse:** Condition values should reference input slice, not dupe. Allocation happens in `Set.parseAndPut()` via arena allocator.
- **Modifying existing Binding.Set storage:** Conditional bindings need separate ConditionSet to implement priority (CONF-04). Don't mix conditional/unconditional in same HashMap.
- **Silent fallthrough on unknown condition:** Must error on `[unknown=foo]` per CONF-01 requirement. Don't treat as unconditional binding.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| String hashing | Custom hash function | `std.hash.Wyhash` | Already used in Trigger.hash(), Action.hash(); consistent performance |
| HashMap | Custom map | `std.ArrayHashMapUnmanaged` | Existing pattern in Set; unmanaged avoids allocator storage |
| UTF-8 validation | Byte-by-byte checks | `std.unicode.Utf8View` | Already used in Trigger.parse() for unicode keys; handles edge cases |
| String comparison | Manual loops | `std.mem.eql` | Optimized, used throughout codebase |

**Key insight:** Zig stdlib is comprehensive and battle-tested. Ghostty already uses these primitives extensively — follow existing patterns rather than introducing new approaches.

## Common Pitfalls

### Pitfall 1: Bracket in Trigger Value
**What goes wrong:** User writes `[process=vim]ctrl+[=action` — parser treats `[` in trigger as condition start
**Why it happens:** Greedy prefix matching without context awareness
**How to avoid:** Condition parsing only at string start (index 0). After first non-condition character, `[` is part of trigger.
**Warning signs:** Test case `[process=vim]bracket_left=ignore` fails to parse

### Pitfall 2: Multiple Conditions in v1
**What goes wrong:** Parser accepts `[process=vim][title=foo]ctrl+w=action` when v1 spec forbids it
**Why it happens:** Condition parsing loop doesn't enforce single-condition limit
**How to avoid:** After parsing one condition, break immediately. Don't loop for additional `[`.
**Warning signs:** Test case with double brackets doesn't error

### Pitfall 3: Condition After Flags
**What goes wrong:** Parser accepts `global:[process=vim]ctrl+w=action` (wrong order)
**Why it happens:** Parsing order in `Parser.init()` is flags-first, then trigger
**How to avoid:** Parse condition BEFORE `parseFlags()` call. Locked decision: condition comes first.
**Warning signs:** Test case `global:[process=vim]ctrl+w=action` doesn't error

### Pitfall 4: Breaking Existing Configs
**What goes wrong:** Existing config `ctrl+[=ignore` (bind bracket key) fails to parse
**Why it happens:** Condition parser triggers on `[` anywhere in input
**How to avoid:** Only parse condition if input starts with `[`. Otherwise pass through unchanged.
**Warning signs:** Existing test suite fails (lines 2810-3275 have 400+ test cases)

### Pitfall 5: Empty Condition Values
**What goes wrong:** Parser accepts `[process=]ctrl+w=action` or `[=vim]ctrl+w=action`
**Why it happens:** No validation after splitting on `=`
**How to avoid:** Check `cond_type.len > 0` and `cond_value.len > 0` after split
**Warning signs:** Test case `[process=]ctrl+w=action` doesn't error with InvalidFormat

## Code Examples

Verified patterns from codebase:

### Extending Parser.init()
```zig
// Source: Binding.zig lines 94-146
pub fn init(raw_input: []const u8) Error!Parser {
    // NEW: Parse condition first (before flags)
    const condition, const cond_end = try parseCondition(raw_input);
    const after_condition = raw_input[cond_end..];

    // EXISTING: Parse flags
    const flags, const start_idx = try parseFlags(after_condition);
    const input = after_condition[start_idx..];

    // EXISTING: Find action delimiter, parse action
    const eql_idx = findActionDelimiter(input)?;
    const chain = std.mem.eql(u8, input[0..eql_idx], "chain");

    return .{
        .trigger_it = .{ .input = if (chain) "a" else input[0..eql_idx] },
        .action = try .parse(input[eql_idx + 1 ..]),
        .flags = flags,
        .chain = chain,
        .condition = condition,  // NEW field
    };
}
```

### Condition Tagged Union
```zig
// NEW FILE: src/input/Condition.zig
const Condition = @This();
const std = @import("std");

pub const Condition = union(enum) {
    process: []const u8,
    title: []const u8,
    var_: VarCondition,

    pub const VarCondition = struct {
        name: []const u8,
        value: []const u8,
    };

    pub fn parse(input: []const u8) !Condition {
        // Called from parseCondition() after extracting bracket content
        const eq_idx = std.mem.indexOf(u8, input, "=") orelse
            return error.InvalidFormat;
        const cond_type = input[0..eq_idx];
        const cond_value = input[eq_idx + 1 ..];

        if (cond_type.len == 0 or cond_value.len == 0)
            return error.InvalidFormat;

        if (std.mem.eql(u8, cond_type, "process")) {
            return .{ .process = cond_value };
        } else if (std.mem.eql(u8, cond_type, "title")) {
            return .{ .title = cond_value };
        } else if (std.mem.eql(u8, cond_type, "var")) {
            const colon_idx = std.mem.indexOf(u8, cond_value, ":") orelse
                return error.InvalidFormat;
            return .{ .var_ = .{
                .name = cond_value[0..colon_idx],
                .value = cond_value[colon_idx + 1 ..],
            } };
        } else {
            return error.InvalidFormat;  // Unknown condition type
        }
    }
};
```

### Test Pattern
```zig
// Source: Binding.zig test pattern (lines 2810+)
test "parse: conditional bindings" {
    const testing = std.testing;

    // Valid process condition
    {
        const b = try parseSingle("[process=vim]ctrl+w=close_surface");
        try testing.expect(b.condition != null);
        try testing.expectEqual(.process, std.meta.activeTag(b.condition.?));
        try testing.expectEqualStrings("vim", b.condition.?.process);
        try testing.expectEqual(.ctrl, b.trigger.mods);
        try testing.expectEqual(.w, b.trigger.key.physical);
    }

    // Valid var condition
    {
        const b = try parseSingle("[var=in_vim:1]ctrl+w=close_surface");
        try testing.expectEqual(.var_, std.meta.activeTag(b.condition.?));
        try testing.expectEqualStrings("in_vim", b.condition.?.var_.name);
        try testing.expectEqualStrings("1", b.condition.?.var_.value);
    }

    // Condition with flags
    {
        const b = try parseSingle("[process=vim]global:ctrl+w=close_surface");
        try testing.expect(b.condition != null);
        try testing.expect(b.flags.global);
    }

    // Error cases
    try testing.expectError(Error.InvalidFormat, parseSingle("[process=]ctrl+w=action"));
    try testing.expectError(Error.InvalidFormat, parseSingle("[=vim]ctrl+w=action"));
    try testing.expectError(Error.InvalidFormat, parseSingle("[unknown=foo]ctrl+w=action"));
    try testing.expectError(Error.InvalidFormat, parseSingle("[process=vim"));  // Unclosed
    try testing.expectError(Error.InvalidFormat, parseSingle("[process=vim][title=foo]ctrl+w=action"));  // v1 multi-condition
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| N/A | Conditional keybinds | New feature | First implementation; no migration needed |
| Prefix flags only | Bracket-delimited conditions | Phase 1 | Extends existing prefix pattern without breaking it |

**Deprecated/outdated:**
- None — this is a new feature with no prior implementation

## Open Questions

1. **Condition storage in Binding struct**
   - What we know: Binding has trigger, action, flags fields
   - What's unclear: Should condition be `?Condition` (nullable) or separate ConditionalBinding struct?
   - Recommendation: Use `?Condition` for minimal change; null = unconditional binding

2. **String lifetime in Condition**
   - What we know: Parser receives `[]const u8` input, values reference input slice
   - What's unclear: When does input get deallocated? Do we need to dupe strings?
   - Recommendation: Follow Action.parse() pattern — values reference input, Set.parseAndPut() handles allocation via arena

3. **Test organization**
   - What we know: Binding.zig has 400+ test cases at end of file
   - What's unclear: Add condition tests inline or separate test block?
   - Recommendation: Add new `test "parse: conditional bindings"` block after existing tests (line 3275+)

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Zig built-in test (zig build test) |
| Config file | build.zig — no separate test config |
| Quick run command | `zig test src/input/Binding.zig` |
| Full suite command | `zig build test` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CONF-01 | Parse `[process=vim]ctrl+w=action` without error | unit | `zig test src/input/Binding.zig -Dtest-filter="parse: conditional"` | ❌ Wave 0 |
| CONF-02 | Existing bindings parse identically | unit | `zig test src/input/Binding.zig` (full suite) | ✅ (lines 2810-3275) |
| CONF-03 | Later conditional binding overwrites earlier | unit | `zig test src/input/Binding.zig -Dtest-filter="Set.parseAndPut"` | ❌ Wave 0 |
| CONF-04 | Conditional priority over unconditional | integration | Manual test — requires ConditionSet (Phase 2) | ❌ Phase 2 |
| CONF-05 | Backward compatibility | unit | `zig test src/input/Binding.zig` (full suite) | ✅ (existing tests) |

### Sampling Rate
- **Per task commit:** `zig test src/input/Binding.zig` (< 5 seconds)
- **Per wave merge:** `zig build test` (full project suite)
- **Phase gate:** Full suite green + manual verification of 5 success criteria

### Wave 0 Gaps
- [ ] `test "parse: conditional bindings"` — covers CONF-01 (valid syntax)
- [ ] `test "parse: conditional errors"` — covers CONF-01 (error cases)
- [ ] `test "Set.parseAndPut: conditional overwrite"` — covers CONF-03
- [ ] Extend existing tests with condition=null assertions — covers CONF-05

## Sources

### Primary (HIGH confidence)
- Ghostty codebase `/Users/anhoder/Desktop/ghostty/src/input/Binding.zig` (4847 lines, Zig 0.15.2)
- Ghostty codebase `/Users/anhoder/Desktop/ghostty/src/config/Config.zig` (keybind integration)
- Zig 0.15.2 stdlib documentation (std.mem, std.hash, std.unicode)

### Secondary (MEDIUM confidence)
- .planning/STATE.md — project decisions and key files
- .planning/REQUIREMENTS.md — v1 requirements CONF-01 through CONF-05
- .planning/phases/01-config-syntax-parsing/01-CONTEXT.md — user decisions from discussion

### Tertiary (LOW confidence)
- None — all research based on codebase inspection and stdlib

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Zig stdlib only, no external dependencies
- Architecture: HIGH - Existing patterns clearly established in Binding.zig
- Pitfalls: HIGH - Identified from codebase patterns and locked decisions

**Research date:** 2026-03-18
**Valid until:** 2026-04-18 (30 days — stable domain, Zig 0.15.2 unlikely to change)
