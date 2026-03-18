---
phase: 04-osc-1337-uservar-conditions
plan: "02"
subsystem: termio/surface-messaging
tags: [osc-1337, uservar, base64, mailbox, stream-handler]
dependency_graph:
  requires: [04-01]
  provides: [set_user_var-mailbox-message]
  affects: [src/termio/stream_handler.zig, src/apprt/surface.zig]
tech_stack:
  added: []
  patterns: [fixed-size-message-struct, surfaceMessageWriter, base64-stack-decode]
key_files:
  created: []
  modified:
    - src/apprt/surface.zig
    - src/termio/stream_handler.zig
decisions:
  - Fixed-size arrays (name[63:0], value[191:0]) follow desktop_notification pattern for predictable message size
  - Stack decode buffer (256 bytes) avoids heap allocation in hot path
  - Truncate-with-warn on oversized names/values rather than dropping message
  - Invalid base64 logs warning and returns without crashing
metrics:
  duration: "~5 minutes"
  completed: "2026-03-18T08:41:00Z"
  tasks_completed: 2
  files_modified: 2
---

# Phase 4 Plan 02: SetUserVar Mailbox Bridge Summary

One-liner: Base64-decoded OSC 1337 SetUserVar values bridged to Surface via fixed-size mailbox message.

## What Was Built

- `Message.set_user_var` variant added to `src/apprt/surface.zig` with `name[63:0]u8` and `value[191:0]u8` fixed-size null-terminated arrays
- `setUserVar` handler in `src/termio/stream_handler.zig` that decodes base64 data, copies name/value into fixed arrays (truncating with warnings if oversized), and sends via `surfaceMessageWriter`
- `set_user_var` case wired into `vtFallible` switch

## Deviations from Plan

None - plan executed exactly as written.

## Self-Check: PASSED

- FOUND: src/apprt/surface.zig
- FOUND: src/termio/stream_handler.zig
- FOUND: 04-02-SUMMARY.md
- FOUND: cfc14c8e4 feat(04-02): add set_user_var message variant to surface.zig
- FOUND: c3e8e1d4c feat(04-02): implement setUserVar handler in stream_handler.zig
