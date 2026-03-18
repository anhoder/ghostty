---
phase: 05-window-title-glob-matching
verified: 2026-03-18T00:00:00Z
status: passed
score: 6/6 must-haves verified
---

# Phase 5: Window Title & Glob Matching Verification Report

**Phase Goal:** Users can match on window title, and all condition types support glob wildcards for flexible pattern matching
**Verified:** 2026-03-18
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `[title=vim: main.zig]ctrl+s=...` fires when window title exactly matches | ✓ VERIFIED | `matchesCondition .title` calls `matchesGlob` which has exact-match fast path via `std.mem.eql`; test at line 5434 confirms |
| 2 | `[title=vim:*]ctrl+s=...` fires for any title starting with `vim:` | ✓ VERIFIED | `matchesGlob` handles `*` wildcard via `globMatchImpl`; tests at lines 5441-5443 confirm |
| 3 | `[process=nvim*]ctrl+w=...` matches both `nvim` and `nvim-qt` | ✓ VERIFIED | `.process` case calls `matchesGlob`; tests at lines 5459 and 5463 confirm both match |
| 4 | Glob matching does not increase keypress latency | ✓ VERIFIED | `matchesGlob` fast path: `std.mem.indexOfAny(u8, pattern, "*?") == null` → `std.mem.eql` — no glob overhead for exact patterns |
| 5 | Title conditions match from first keypress, including statically configured title | ✓ VERIFIED | `Surface.init` seeds `runtime_context.title` from `config.title` at line 736; `set_title` handler updates before config guard at line 976 |
| 6 | No memory leaks: `runtime_context.title` and `runtime_context.process_name` freed in `Surface.deinit` | ✓ VERIFIED | Lines 835-836 in `Surface.zig` free both fields after user_vars cleanup |

**Score:** 6/6 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/Surface.zig` | `runtime_context.title` wiring in set_title handler, config-title seeding, deinit cleanup | ✓ VERIFIED | All three wiring points present and substantive |
| `src/input/Binding.zig` | Glob matching for `.title` and `.process` conditions, unit tests | ✓ VERIFIED | `matchesCondition` uses `matchesGlob` for both; full test block at line 5428 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `Surface.zig` set_title handler | `runtime_context.title` | `alloc.dupe` before config guard | ✓ WIRED | Lines 976-980: frees old, dupes new, guard follows at line 983 |
| `Binding.zig` matchesCondition `.title` | `matchesGlob` | replaces `std.mem.eql` | ✓ WIRED | Lines 98-101: `if (self.title) |ti| matchesGlob(ti, t)` |
| `Binding.zig` matchesCondition `.process` | `matchesGlob` | replaces `std.mem.eql` | ✓ WIRED | Lines 93-96: `if (self.process_name) |pn| matchesGlob(pn, name)` |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| TITL-01 | 05-01-PLAN.md | User can match keybindings on window title (exact) | ✓ SATISFIED | `runtime_context.title` populated from `set_title` and `config.title`; `matchesGlob` fast path handles exact match |
| TITL-02 | 05-01-PLAN.md | User can use glob wildcards to match window title | ✓ SATISFIED | `matchesGlob` with `*` and `?` support; tests at lines 5441-5448 |
| PROC-02 | 05-01-PLAN.md | User can use glob wildcards to match process name | ✓ SATISFIED | `.process` case uses `matchesGlob`; tests at lines 5456-5479 |

No orphaned requirements — all three IDs declared in plan frontmatter are accounted for. REQUIREMENTS.md traceability table maps TITL-01, TITL-02, PROC-02 to Phase 5 with status Complete.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `src/input/Binding.zig` | 238 | `TODO: change parser into real state machine` | ℹ️ Info | Pre-existing, unrelated to phase 5 |
| `src/Surface.zig` | 2139, 4945, 4957 | `TODO` comments | ℹ️ Info | Pre-existing, unrelated to phase 5 |

No blockers. No phase-5-introduced TODOs or stubs.

### Human Verification Required

#### 1. Live title condition firing

**Test:** Run ghostty, configure a binding like `keybind = [title=test*]ctrl+k=new_window`, then set the terminal title via `printf '\e]0;test title\a'` and press Ctrl+K.
**Expected:** The conditional binding fires (new window opens). Without the title prefix, Ctrl+K should not fire the binding.
**Why human:** `set_title` message flow through the mailbox to `Surface.handleMessage` cannot be exercised without a running Surface instance.

### Gaps Summary

No gaps. All six must-have truths are verified, all artifacts are substantive and wired, all three requirement IDs are satisfied, and both source files pass `zig ast-check` with no syntax errors.

---

_Verified: 2026-03-18_
_Verifier: Claude (gsd-verifier)_
