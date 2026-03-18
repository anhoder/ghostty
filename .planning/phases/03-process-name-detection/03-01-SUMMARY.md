---
phase: 03-process-name-detection
plan: 01
subsystem: process-detection
tags: [infrastructure, platform-specific, mailbox]
dependency_graph:
  requires: [02-01]
  provides: [process-detection-api, process-name-message]
  affects: []
tech_stack:
  added: [libproc, procfs]
  patterns: [platform-dispatch, mailbox-message]
key_files:
  created: [src/os/process.zig]
  modified: [src/apprt/surface.zig]
decisions:
  - "Use WriteReq for process_name_update message (consistent with pwd_change pattern)"
  - "Return null for unsupported platforms rather than error (graceful degradation)"
  - "Iterate /proc on Linux, proc_listallpids on macOS (platform-specific APIs)"
metrics:
  duration_seconds: 78
  tasks_completed: 2
  files_created: 1
  files_modified: 1
  commits: 2
  completed_date: "2026-03-18"
---

# Phase 03 Plan 01: Process Detection Infrastructure Summary

**One-liner:** Platform-specific process name detection using tcgetpgrp + procfs (Linux) / libproc (macOS) with mailbox message type

## Overview

Created foundational infrastructure for async process name detection without blocking keypress path. Implemented platform-specific APIs for Linux and macOS, plus mailbox message type for I/O thread → Surface communication.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Platform-specific process detection | dcfc1dbde | src/os/process.zig |
| 2 | Add process_name_update message type | ba8e7fe09 | src/apprt/surface.zig |

## Implementation Details

### Task 1: Process Detection API

Created `src/os/process.zig` with `getForegroundProcessName()` public API:

**Linux implementation:**
- `tcgetpgrp()` to get foreground PGID
- Iterate `/proc` to find matching process
- Read `/proc/<pid>/comm` for process name

**macOS implementation:**
- `tcgetpgrp()` to get foreground PGID
- `proc_listallpids()` to enumerate processes
- `proc_pidinfo(PROC_PIDTBSDINFO)` to get process name

**Error handling:**
- Returns null for unsupported platforms (Windows)
- Returns null for invalid fd or no foreground process
- Gracefully handles permission denied during iteration

### Task 2: Mailbox Message Type

Added `process_name_update: WriteReq` to `Message` union in `src/apprt/surface.zig`, placed after `pwd_change` (similar runtime state update pattern).

## Deviations from Plan

None - plan executed exactly as written.

## Verification Results

- ✅ `zig ast-check src/os/process.zig` passes
- ✅ `zig ast-check src/apprt/surface.zig` passes
- ✅ `getForegroundProcessName` public API exists
- ✅ `process_name_update` message variant exists
- ✅ Platform dispatch for Linux and macOS present

## Next Steps

Plan 03-02 will integrate this infrastructure:
- Add polling timer in `Exec.zig`
- Send `process_name_update` messages via mailbox
- Handle messages in `Surface` to update `runtime_context.process_name`

## Self-Check: PASSED

**Files created:**
- FOUND: src/os/process.zig

**Commits:**
- FOUND: dcfc1dbde
- FOUND: ba8e7fe09

**Message type:**
- FOUND: process_name_update at line 89 in src/apprt/surface.zig
