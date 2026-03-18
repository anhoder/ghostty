# Code Patterns

**Analysis Date:** 2026-03-18

## Architecture Patterns

**Layered Architecture:**
- Core terminal emulation layer (`src/terminal/`) - VT parsing, screen management, terminal state
- Application runtime layer (`src/apprt.zig`) - Platform abstraction for windowing systems
- Rendering layer (`src/renderer/`) - OpenGL, Metal, WebGL implementations
- Platform-specific implementations (`src/os/`, `macos/Sources/`) - OS-specific code isolation

**Component Ownership:**
- Each `Surface` owns its PTY session and terminal state
- `App` manages multiple surfaces and shared resources (fonts, config)
- Clear parent-child relationships with explicit allocator passing

**Build System Pattern:**
- Zig build system with modular build packages in `src/build/`
- Configuration-driven builds via `src/build/Config.zig`
- Shared dependencies managed through `buildpkg.SharedDeps`

## Design Patterns

**Self-Referential Struct Pattern:**
```zig
const TypeName = @This();
```
Used consistently across the codebase in files like:
- `src/Command.zig`
- `src/App.zig`
- `src/Surface.zig`
- `src/terminal/Terminal.zig`

**Module Re-export Pattern:**
```zig
// In main.zig files
pub const TypeName = @import("file.zig").TypeName;
```
Example: `src/datastruct/main.zig` re-exports all data structures

**Error Set Pattern:**
```zig
pub const Error = error{
    SpecificError1,
    SpecificError2,
};
```
Custom error sets defined per module (e.g., `src/renderer/metal/Sampler.zig`)

**Scoped Logging:**
```zig
const log = std.log.scoped(.module_name);
```
Every module defines its own scoped logger for categorized logging

**Allocator Threading:**
- Allocators passed explicitly as function parameters
- No global allocators except `global_state`
- Pattern: `pub fn init(alloc: Allocator, ...) !Type`

**Mailbox/Message Queue Pattern:**
- Async communication via `BlockingQueue` from `src/datastruct/blocking_queue.zig`
- Used in `App.zig` and `Surface.zig` for thread-safe messaging

## Naming Conventions

**Files:**
- PascalCase for struct/type files: `Command.zig`, `Surface.zig`, `Terminal.zig`
- snake_case for module/utility files: `main.zig`, `config.zig`, `surface_mouse.zig`
- Descriptive names matching primary type: file `Terminal.zig` contains `const Terminal = @This()`

**Directories:**
- snake_case: `src/terminal/`, `src/datastruct/`, `src/shell-integration/`
- Organized by feature/domain: `renderer/`, `config/`, `input/`, `font/`

**Functions:**
- camelCase: `init()`, `deinit()`, `carriageReturn()`, `cursorUp()`
- Lifecycle: `init()` for initialization, `deinit()` for cleanup
- Verb-based names describing actions: `printString()`, `saveCursor()`, `restoreCursor()`

**Variables:**
- snake_case: `font_grid_key`, `rt_surface`, `focused_surface`
- Descriptive names with context: `last_notification_time`, `config_conditional_state`

**Constants:**
- SCREAMING_SNAKE_CASE: `TABSTOP_INTERVAL`, `min_window_width_cells`
- Compile-time known values

**Types:**
- PascalCase: `Terminal`, `Surface`, `BlockingQueue`, `CircBuf`
- Descriptive of what they represent

**Error Sets:**
- PascalCase ending in `Error`: `CreateError`, `PostForkError`, `ParseError`

## Code Organization

**Module Structure:**
```
module/
├── main.zig          # Public API, re-exports
├── TypeName.zig      # Primary type implementation
├── helper.zig        # Utility functions
└── submodule/        # Sub-features
    └── ...
```

**File Header Pattern:**
```zig
//! Module-level documentation describing purpose and usage.
//! Multiple lines explaining the "why" and high-level "what".
const TypeName = @This();

const std = @import("std");
const builtin = @import("builtin");
// ... other imports grouped logically

const log = std.log.scoped(.scope_name);
```

**Import Organization:**
1. Standard library imports (`std`, `builtin`)
2. Internal package imports (relative paths)
3. Type aliases and constants
4. Scoped logger definition

**Struct Field Organization:**
1. Allocator (if needed)
2. Core data/state
3. Configuration
4. Runtime state
5. Callbacks/function pointers

**Public API Pattern:**
- `pub fn init()` - Constructor
- `pub fn deinit()` - Destructor
- `pub fn` for public methods
- Private functions have no `pub` qualifier

## Common Implementation Patterns

**Initialization Pattern:**
```zig
pub fn init(alloc: Allocator, ...) !*Type {
    var instance = try alloc.create(Type);
    errdefer alloc.destroy(instance);
    // Initialize fields
    return instance;
}

pub fn deinit(self: *Type, alloc: Allocator) void {
    // Cleanup
    alloc.destroy(self);
}
```

**Error Handling:**
- Use Zig's error unions: `!ReturnType`
- `errdefer` for cleanup on error paths
- Custom error sets per module
- Propagate errors with `try` or explicit handling

**Testing Pattern:**
```zig
test "descriptive test name explaining what is tested" {
    const testing = std.testing;
    // Test implementation
    try testing.expectEqual(expected, actual);
}

test {
    @import("std").testing.refAllDecls(@This());
}
```

**Conditional Compilation:**
```zig
const is_macos = builtin.target.os.tag.isDarwin();
if (config.feature_flag) {
    // Feature-specific code
}
```

**Resource Management:**
- RAII-style with `init`/`deinit` pairs
- Explicit allocator passing
- `defer` and `errdefer` for cleanup
- No hidden allocations

**Platform Abstraction:**
- Platform-specific code in `src/os/` with common interface
- Runtime detection via `builtin.target.os.tag`
- Separate macOS Swift code in `macos/Sources/`

**C Interop:**
- C API exposed via `src/main_c.zig` and `src/lib_vt.zig`
- Null-terminated strings for C compatibility: `[:0]const u8`
- Explicit C ABI handling

**Documentation Comments:**
- `//!` for module/file-level documentation
- `///` for function/type documentation (less common in this codebase)
- Focus on "why" and usage, not "what" (code is self-documenting)

**Benchmark Pattern:**
- Dedicated `src/benchmark/` directory
- Each benchmark in its own file: `TerminalParser.zig`, `ScreenClone.zig`
- Consistent structure with `Benchmark.zig` base

**Multi-Platform Support:**
- Zig for core logic (cross-platform)
- Swift for macOS/iOS UI (`macos/Sources/`)
- Platform-specific backends: Metal (macOS), OpenGL (Linux), WebGL (WASM)

---

*Pattern analysis: 2026-03-18*
