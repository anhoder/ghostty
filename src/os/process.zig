const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.process);

/// Get the name of the foreground process in the PTY session.
/// Returns allocated string or null if no foreground process.
/// Caller owns returned memory.
pub fn getForegroundProcessName(
    alloc: Allocator,
    pty_master_fd: posix.fd_t,
) !?[]const u8 {
    return switch (builtin.os.tag) {
        .linux => getForegroundProcessNameLinux(alloc, pty_master_fd),
        .macos => getForegroundProcessNameBSD(alloc, pty_master_fd),
        else => null,
    };
}

const c_unistd = @cImport({
    @cInclude("unistd.h");
});

// libproc declarations (macOS). Declared manually instead of @cImport("libproc.h")
// because libproc.h transitively includes mach/message.h, whose new static size
// assertions fail translation on recent SDKs (bitfield structs are demoted to
// opaque, then @sizeOf(opaque) errors). Only the symbols used below are needed.
const PROC_PIDTBSDINFO: c_int = 3;

const proc_bsdinfo = extern struct {
    pbi_flags: u32,
    pbi_status: u32,
    pbi_xstatus: u32,
    pbi_pid: u32,
    pbi_ppid: u32,
    pbi_uid: u32,
    pbi_gid: u32,
    pbi_ruid: u32,
    pbi_rgid: u32,
    pbi_svuid: u32,
    pbi_svgid: u32,
    rfu_1: u32,
    pbi_comm: [16]u8,
    pbi_name: [32]u8,
    pbi_nfiles: u32,
    pbi_pgid: u32,
    pbi_pjobc: u32,
    e_tdev: u32,
    e_tpgid: u32,
    pbi_nice: i32,
    pbi_start_tvsec: u64,
    pbi_start_tvusec: u64,
};

comptime {
    std.debug.assert(@sizeOf(proc_bsdinfo) == 136);
}

extern "c" fn proc_pidinfo(pid: c_int, flavor: c_int, arg: u64, buffer: *anyopaque, buffersize: c_int) c_int;
extern "c" fn proc_listallpids(buffer: *anyopaque, buffersize: c_int) c_int;

fn getForegroundProcessNameLinux(
    alloc: Allocator,
    pty_master_fd: posix.fd_t,
) !?[]const u8 {
    const pgid = c_unistd.tcgetpgrp(pty_master_fd);
    if (pgid <= 0) return null;

    // First, try the process group leader directly (pid == pgid).
    // This is the main foreground process and avoids non-deterministic
    // results from iterating /proc in arbitrary order.
    {
        var buf: [32]u8 = undefined;
        const comm_path = std.fmt.bufPrint(&buf, "/proc/{d}/comm", .{pgid}) catch
            return getForegroundProcessNameLinuxScan(alloc, pgid);

        const comm_file = std.fs.openFileAbsolute(comm_path, .{}) catch
            return getForegroundProcessNameLinuxScan(alloc, pgid);
        defer comm_file.close();

        var name_buf: [16]u8 = undefined;
        const bytes_read = comm_file.readAll(&name_buf) catch
            return getForegroundProcessNameLinuxScan(alloc, pgid);
        if (bytes_read > 0) {
            const name = std.mem.trimRight(u8, name_buf[0..bytes_read], "\n");
            return try alloc.dupe(u8, name);
        }
    }

    return getForegroundProcessNameLinuxScan(alloc, pgid);
}

/// Fallback: scan /proc for any process in the given process group.
fn getForegroundProcessNameLinuxScan(
    alloc: Allocator,
    pgid: posix.pid_t,
) !?[]const u8 {
    var proc_dir = std.fs.openDirAbsolute("/proc", .{ .iterate = true }) catch |err| {
        log.warn("failed to open /proc: {}", .{err});
        return null;
    };
    defer proc_dir.close();

    var iter = proc_dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind != .directory) continue;

        const pid = std.fmt.parseInt(posix.pid_t, entry.name, 10) catch continue;

        const pid_pgid = c_unistd.getpgid(pid);
        if (pid_pgid == pgid) {
            var buf: [32]u8 = undefined;
            const comm_path = std.fmt.bufPrint(&buf, "/proc/{d}/comm", .{pid}) catch continue;

            const comm_file = std.fs.openFileAbsolute(comm_path, .{}) catch continue;
            defer comm_file.close();

            var name_buf: [16]u8 = undefined;
            const bytes_read = comm_file.readAll(&name_buf) catch continue;
            if (bytes_read == 0) continue;

            const name = std.mem.trimRight(u8, name_buf[0..bytes_read], "\n");
            return try alloc.dupe(u8, name);
        }
    }

    return null;
}

fn getForegroundProcessNameBSD(
    alloc: Allocator,
    pty_master_fd: posix.fd_t,
) !?[]const u8 {
    const pgid = c_unistd.tcgetpgrp(pty_master_fd);
    if (pgid <= 0) return null;

    // First, try to get the name of the process group leader directly.
    // The group leader's PID equals the PGID, and this is typically the
    // main foreground process (e.g., vim, not its child processes).
    // This avoids non-deterministic results from iterating all PIDs.
    {
        var bsdinfo: proc_bsdinfo = undefined;
        const ret = proc_pidinfo(
            pgid,
            PROC_PIDTBSDINFO,
            0,
            &bsdinfo,
            @sizeOf(proc_bsdinfo),
        );
        if (ret > 0) {
            const name = std.mem.sliceTo(&bsdinfo.pbi_name, 0);
            if (name.len > 0) {
                return try alloc.dupe(u8, name);
            }
        }
    }

    // Fallback: scan all PIDs for a process in the same process group.
    // This handles edge cases where the group leader has exited but
    // child processes remain.
    var pids_buf: [4096]c_int = undefined;
    const buf_size = @sizeOf(@TypeOf(pids_buf));
    const bytes = proc_listallpids(&pids_buf, buf_size);
    if (bytes <= 0) return null;

    const pid_count = @divTrunc(bytes, @sizeOf(c_int));
    for (pids_buf[0..@intCast(pid_count)]) |pid| {
        if (pid <= 0) continue;

        const pid_pgid = c_unistd.getpgid(pid);
        if (pid_pgid == pgid) {
            var bsdinfo: proc_bsdinfo = undefined;
            const ret = proc_pidinfo(
                pid,
                PROC_PIDTBSDINFO,
                0,
                &bsdinfo,
                @sizeOf(proc_bsdinfo),
            );
            if (ret <= 0) continue;

            const name = std.mem.sliceTo(&bsdinfo.pbi_name, 0);
            if (name.len == 0) continue;

            return try alloc.dupe(u8, name);
        }
    }

    return null;
}

test "unsupported platform returns null" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const result = try getForegroundProcessName(std.testing.allocator, 0);
    try std.testing.expectEqual(@as(?[]const u8, null), result);
}

test "invalid fd returns null" {
    const result = try getForegroundProcessName(std.testing.allocator, -1);
    try std.testing.expectEqual(@as(?[]const u8, null), result);
}
