---
phase: 06-platform-validation-documentation
verified: 2026-03-19T02:59:27Z
status: human_needed
score: 4/5 must-haves verified
re_verification: false
human_verification:
  - test: "Run full test suite on macOS: zig build test -Dtest-filter=\"RuntimeContext\""
    expected: "All RuntimeContext, conditional parse, and getConditional tests pass with no failures"
    why_human: "Build requires network access to fetch Zig dependencies (deps.files.ghostty.org); not available in this environment. Cannot confirm tests actually execute and pass — only that test source code exists and AST-checks clean."
  - test: "Run full test suite on Linux: zig build test -Dtest-filter=\"RuntimeContext\""
    expected: "Identical test suite passes on Linux, validating PLAT-02 cross-platform claim"
    why_human: "This environment is macOS-only. Linux platform execution cannot be verified programmatically from here."
  - test: "Manual smoke test: add [process=vim]ctrl+w=close_surface to config, open vim, press ctrl+w"
    expected: "The conditional action fires (close_surface) instead of any unconditional binding for that trigger"
    why_human: "Runtime behavior requires a running Ghostty instance. Cannot verify at static analysis time."
---

# Phase 6: Platform Validation & Documentation Verification Report

**Phase Goal:** All conditional keybinding features work correctly on both macOS and Linux, and the keybind config documentation covers all condition types with examples
**Verified:** 2026-03-19T02:59:27Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | The keybind doc comment in Config.zig documents all three condition types (process, title, var) with examples | VERIFIED | Lines 1880-1910: all three types present with code examples matching plan requirements exactly |
| 2 | The documentation notes the ~200ms eventual-consistency window for process-name conditions specifically | VERIFIED | Lines 1888-1891: "approximately every 200ms... eventual-consistency window of up to ~200ms"; note is scoped inside the `process=` subsection, not repeated under title or var |
| 3 | The documentation explains conditional binding priority (conditional > unconditional fallback) | VERIFIED | Lines 1914-1918: "Conditional bindings are checked before unconditional bindings... unconditional binding fires as a fallback... last one written in the config wins" |
| 4 | The documentation notes v1 limitations (single condition, no sequences, no global:/all: prefix) | VERIFIED | Lines 1920-1926: all three limitations listed verbatim as specified in plan |
| 5 | The full conditional keybinding test suite passes (RuntimeContext, conditional parse, getConditional) | UNCERTAIN | 7 test blocks confirmed present in Binding.zig (lines 5211-5482+); `zig ast-check` passes on both files; full `zig build test` requires network — cannot confirm execution |

**Score:** 4/5 truths verified (1 uncertain — needs human for full test run)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/config/Config.zig` | `## Conditional Bindings` doc section in keybind doc comment | VERIFIED | Section at line 1869, immediately before `keybind: Keybinds = .{},` at line 1928. 60 lines of substantive documentation. `zig ast-check` exit code 0. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `src/config/Config.zig` | man page generation | `/// doc comment on keybind field` | VERIFIED | Pattern `/// ## Conditional Bindings` confirmed at line 1869 as a `///` doc comment on the `keybind` field. Ghostty's man page is generated from `///` doc comments on config fields, so this wires automatically. |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| PLAT-01 | 06-01-PLAN.md | 所有条件匹配功能在 macOS 上正常工作 (All conditional matching features work correctly on macOS) | NEEDS HUMAN | Documentation complete and AST-clean. Test source present. Full `zig build test` requires network to confirm macOS execution. |
| PLAT-02 | 06-01-PLAN.md | 所有条件匹配功能在 Linux 上正常工作 (All conditional matching features work correctly on Linux) | NEEDS HUMAN | Test logic is platform-agnostic (pure string matching in Binding.zig). No Linux-specific runtime path exercised in this phase. Linux execution requires a Linux environment. |

**Orphaned requirements check:** REQUIREMENTS.md maps PLAT-01 and PLAT-02 to Phase 6. Both are declared in 06-01-PLAN.md frontmatter. No orphaned requirements.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | — | — | None found in modified range (lines 1869-1927) |

No TODO/FIXME/placeholder comments found in the Conditional Bindings doc section. No empty implementations or stub patterns. The section is substantive and complete.

### Human Verification Required

#### 1. macOS Full Test Suite (PLAT-01 gate)

**Test:** In a network-connected environment, run `cd /path/to/ghostty && zig build test -Dtest-filter="RuntimeContext"`, then `zig build test -Dtest-filter="conditional"`, then `zig build test -Dtest-filter="getConditional"`
**Expected:** All three filter runs pass with zero failures. Combined they cover 7 test blocks: `parse: conditional bindings` (line 5211), `parse: conditional errors` (line 5254), `set: parseAndPut conditional bindings` (line 5276), `RuntimeContext: matchesCondition` (line 5341), `RuntimeContext: matchesCondition var_ glob patterns` (line 5396), `RuntimeContext: matchesCondition title/process glob patterns` (line 5428), `set: getConditional priority` (line 5482).
**Why human:** `zig build test` requires fetching dependencies from deps.files.ghostty.org (returned 403 Forbidden in this environment). Test source and AST are verified clean, but actual test execution cannot be confirmed without network access.

#### 2. Linux Test Suite (PLAT-02 gate)

**Test:** On a Linux host or CI runner, run the same three test-filter commands as above.
**Expected:** Identical pass results as macOS — the test logic is platform-agnostic pure string matching, so Linux should produce identical output.
**Why human:** Cannot execute Linux binaries from a macOS-only environment. This is a platform boundary that requires a Linux shell or CI job.

#### 3. Optional Manual Smoke Test (macOS)

**Test:** Add `keybind = [process=vim]ctrl+w=close_surface` to `~/.config/ghostty/config`, launch Ghostty, open vim, press ctrl+w.
**Expected:** `close_surface` action fires (terminal surface closes), rather than any unconditional ctrl+w binding.
**Why human:** Runtime behavior in a running Ghostty process cannot be verified with static file analysis.

### Documentation Content Verification (Automated — All Pass)

The following specific content requirements from the plan were all verified in `src/config/Config.zig`:

- `[condition]trigger=action` bracket syntax explained (line 1875)
- `process=<name>` with glob examples: `[process=vim]ctrl+w=close_surface` and `[process=nvim*]ctrl+w=close_surface` (lines 1885-1886)
- `~200ms` note scoped exclusively to process conditions (lines 1888-1891), not present under title or var
- `var=` recommendation for latency-critical use cases (line 1891)
- `title=<pattern>` with example: `[title=vim:*]ctrl+s=write_scrollback_file:~/output.txt` (lines 1893-1896)
- `var=<name>:<value>` with colon separator explained (lines 1898-1900)
- `[var=in_vim:1]ctrl+w=close_surface` example (line 1902)
- OSC 1337 SetUserVar escape sequence documented (lines 1904-1910)
- Priority rules: conditional checked first, unconditional fallback, last-write-wins (lines 1914-1918)
- Limitations: single condition only, no key sequences, no `global:`/`all:` prefixes (lines 1920-1926)
- Section appears immediately before `keybind: Keybinds = .{},` field (line 1928)
- `zig ast-check src/config/Config.zig` exits 0 (no syntax errors)
- `zig ast-check src/input/Binding.zig` exits 0 (no syntax errors)
- Commit 533f8c938 confirmed in git history with matching commit message

### Gaps Summary

No gaps in documentation deliverables. The only outstanding items require human action:

1. **Test execution** — The full `zig build test` suite cannot run without network access in this environment. The test source code is complete and AST-clean (7 test blocks confirmed at lines 5211-5482), but execution must be confirmed in a network-connected macOS environment and on Linux.

2. **PLAT-02 Linux coverage** — This phase's primary automated artifact (documentation) is platform-independent. The underlying code implementing conditional matching was validated in earlier phases. Linux test execution remains a human/CI gate.

These are environment constraints, not implementation gaps. The codebase deliverables for Phase 6 are complete.

---

_Verified: 2026-03-19T02:59:27Z_
_Verifier: Claude (gsd-verifier)_
