---
status: awaiting_human_verify
trigger: "conditional-bindings-still-failing: After deep-clone fix, conditional keybindings still intermittently fail"
created: 2026-03-23T00:00:00Z
updated: 2026-03-23T01:00:00Z
---

## Current Focus

hypothesis: Three distinct bugs found causing intermittent conditional binding failures
test: Fixed all three issues, build and unit tests pass
expecting: Conditional bindings should now work consistently
next_action: User needs to verify in real environment

## Symptoms

expected: Conditional keybindings like `keybind = [process=vim]ctrl+w=ignore` should consistently work when the condition matches
actual: Same config sometimes works, sometimes doesn't. All condition types affected (process, title, var)
errors: No error messages - bindings silently fail to match
reproduction: Add conditional keybindings to config, build app, try using them - intermittently fail
started: Intermittent since initial implementation. Deep-clone fix applied but did not resolve.

## Eliminated

- hypothesis: Set.clone() shallow-copies condition slices causing dangling pointers
  evidence: Fix applied in commit ff50338a6 to deep-clone conditions, but problem persists
  timestamp: prior to this session

- hypothesis: Race condition between message handling and key callback
  evidence: Both handleMessage and keyCallback run on the main thread via App.drainMailbox
  timestamp: 2026-03-23

- hypothesis: Config reload drops conditional_bindings
  evidence: Keybinds.clone() correctly clones conditional_bindings and conditions
  timestamp: 2026-03-23

- hypothesis: Trigger comparison fails due to key type mismatch (physical vs unicode)
  evidence: getEventConditional correctly falls through physical->unicode->unshifted_codepoint, so unicode triggers are found via fallback
  timestamp: 2026-03-23

## Evidence

- timestamp: 2026-03-23
  checked: Test at Binding.zig:5641 for getEventConditional
  found: Compile error - .key = .w does not exist in Key enum (should be .key_w). Test was NEVER compiled or run.
  implication: The getEventConditional integration with real key events was completely untested

- timestamp: 2026-03-23
  checked: parseAndPutRecurse return path for conditional bindings
  found: putConditional does not set chain_parent, but parseAndPut asserts chain_parent != null after successful put. This causes debug assertion failure or UB in release mode when a conditional binding is the first binding after keybind=clear.
  implication: Could cause crashes or UB in configs that use keybind=clear before conditional bindings

- timestamp: 2026-03-23
  checked: getForegroundProcessNameBSD implementation
  found: Iterates ALL pids via proc_listallpids and returns FIRST one matching pgid. When foreground process has children in same process group, iteration order is non-deterministic, causing DIFFERENT process names to be returned on different polling intervals.
  implication: This is the primary cause of intermittent process condition failures - the function might return a child process name instead of the main process name

- timestamp: 2026-03-23
  checked: getForegroundProcessNameLinux implementation
  found: Same pattern - iterates /proc directories in arbitrary order and returns first match
  implication: Same intermittent issue on Linux

## Resolution

root_cause: Three bugs contributing to intermittent conditional binding failures:
  1. Process name detection non-determinism: Both macOS and Linux implementations scan all processes and return the FIRST with matching pgid, but process iteration order is undefined. When the foreground process (e.g., vim) has child processes in the same process group, the detection might return a child's name instead of "vim", causing condition mismatch.
  2. Assert/UB in parseAndPut: putConditional doesn't set chain_parent, causing assertion failure (debug) or undefined behavior (release) when a conditional binding is first after keybind=clear.
  3. Test never compiled: The getEventConditional integration test had .key = .w (should be .key_w), causing a compile error that prevented the test from ever running.

fix: |
  1. Process detection: Query the process group leader (pid == pgid) directly first, then fall back to scanning. The group leader is the main foreground process.
  2. parseAndPut: Return null (clearing chain_parent) after putConditional instead of returning set, since conditional bindings don't support chaining.
  3. Test: Fix .key = .w to .key = .key_w so the test compiles and runs.

verification: |
  - All existing unit tests pass
  - getConditional priority test now compiles and passes
  - Full build succeeds
  - User needs to verify in real environment with conditional keybindings

files_changed:
  - src/input/Binding.zig (test fix + parseAndPut chain_parent fix)
  - src/os/process.zig (process name detection fix)
