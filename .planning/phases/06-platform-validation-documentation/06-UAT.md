---
status: testing
phase: milestone-v1.0-full
source:
  - 01-01-SUMMARY.md
  - 01-02-SUMMARY.md
  - 02-01-SUMMARY.md
  - 03-01-SUMMARY.md
  - 03-02-SUMMARY.md
  - 04-01-SUMMARY.md
  - 04-02-SUMMARY.md
  - 04-03-SUMMARY.md
  - 05-01-SUMMARY.md
  - 06-01-SUMMARY.md
started: 2026-03-19T03:10:00Z
updated: 2026-03-19T03:10:00Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

number: 1
name: Parse Conditional Keybinding Syntax
expected: |
  Add `keybind = [process=vim]ctrl+w=close_surface` to your Ghostty config file. Launch Ghostty. It should start without any parse errors or warnings related to this keybind entry.
awaiting: user response

## Tests

### 1. Parse Conditional Keybinding Syntax
expected: Add `keybind = [process=vim]ctrl+w=close_surface` to your Ghostty config file. Launch Ghostty. It should start without any parse errors or warnings related to this keybind entry.
result: [pending]

### 2. Conditional Binding Priority Over Unconditional
expected: Add both `keybind = ctrl+w=close_surface` and `keybind = [process=vim]ctrl+w=ignore` to your config. Open vim in Ghostty. Press ctrl+w. The conditional binding (`ignore`) should take effect instead of `close_surface` while vim is the foreground process.
result: [pending]

### 3. Last-Write-Wins for Same Condition
expected: Add two conditional bindings for the same trigger and condition: `keybind = [process=vim]ctrl+w=close_surface` then `keybind = [process=vim]ctrl+w=ignore`. The second entry should win. In vim, pressing ctrl+w should trigger `ignore` (nothing happens), not `close_surface`.
result: [pending]

### 4. Invalid Condition Produces Error
expected: Add `keybind = [unknown=foo]ctrl+w=close_surface` to your config. Ghostty should produce a clear parse error on startup (visible in logs or terminal output), not silently ignore the line.
result: [pending]

### 5. Process Name Detection — Vim
expected: Open Ghostty with `keybind = [process=vim]ctrl+w=ignore` in config. Start without vim — ctrl+w should trigger the default action. Then open vim — within ~200ms, ctrl+w should now be ignored (conditional binding active). Exit vim — ctrl+w returns to default action.
result: [pending]

### 6. Process Name Detection — Shell Restoration
expected: After exiting vim (or any process), the process name should update back to your shell name (bash/zsh/fish) within ~200ms. Conditional bindings tied to the previous process should stop matching.
result: [pending]

### 7. OSC 1337 SetUserVar — Set Variable
expected: In a Ghostty terminal, run: `printf '\e]1337;SetUserVar=in_vim=MQ==\a'` (base64 "1"). Then with `keybind = [var=in_vim:1]ctrl+w=ignore` in config, press ctrl+w — it should be ignored (conditional match). Run `printf '\e]1337;SetUserVar=in_vim=MA==\a'` (base64 "0") — ctrl+w should return to default action.
result: [pending]

### 8. UserVar Glob Pattern Matching
expected: With `keybind = [var=mode:insert*]ctrl+w=ignore` in config, set `printf '\e]1337;SetUserVar=mode=aW5zZXJ0X21vZGU=\a'` (base64 "insert_mode"). Press ctrl+w — should be ignored (glob `insert*` matches `insert_mode`). Set mode to `normal` — ctrl+w returns to default.
result: [pending]

### 9. Window Title Exact Match
expected: With `keybind = [title=vim: main.zig]ctrl+s=write_scrollback_file:~/output.txt` in config. When the window title is exactly "vim: main.zig", pressing ctrl+s should trigger `write_scrollback_file`. With a different title, ctrl+s should use default behavior.
result: [pending]

### 10. Window Title Glob Pattern
expected: With `keybind = [title=vim:*]ctrl+s=write_scrollback_file:~/output.txt` in config. Any window title starting with "vim:" should trigger the conditional binding on ctrl+s. Titles not starting with "vim:" should use default behavior.
result: [pending]

### 11. Process Name Glob Pattern
expected: With `keybind = [process=nvim*]ctrl+w=ignore` in config. Running `nvim` should match (exact prefix). Running `nvim-qt` should also match (glob `nvim*`). Running `vim` should NOT match.
result: [pending]

### 12. Config Documentation — Man Page
expected: Run `ghostty +show-config --default --docs | grep -A5 "Conditional Bindings"` (or check the man page). The output should include a "Conditional Bindings" section documenting all three condition types (process, title, var) with examples.
result: [pending]

### 13. Documentation — 200ms Note
expected: In the keybind documentation (man page or `+show-config --docs`), the ~200ms eventual-consistency note should appear specifically under the `process=` condition type, explaining that process detection has a polling interval.
result: [pending]

## Summary

total: 13
passed: 0
issues: 0
pending: 13
skipped: 0

## Gaps

[none yet]
